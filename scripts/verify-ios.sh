#!/usr/bin/env bash
# iOS 검증 게이트 — CI 워크플로 도입(0-D) 전까지 로컬 관문으로 사용한다.
# 사용: ./scripts/verify-ios.sh
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IOS_DIR="$ROOT/ios"

step() { printf '\n\033[1m▸ %s\033[0m\n' "$1"; }
fail() { printf '\033[31m✗ %s\033[0m\n' "$1" >&2; exit 1; }
ok()   { printf '\033[32m✓ %s\033[0m\n' "$1"; }

[ -d "$IOS_DIR" ] || fail "ios/ 디렉터리가 없습니다"

step "Tuist 프로젝트 생성"
cd "$IOS_DIR"
if [ -f "Workspace.swift" ] || [ -f "Project.swift" ]; then
  tuist install >/dev/null 2>&1 || true
  tuist generate --no-open || fail "tuist generate 실패"
  ok "생성 완료"
else
  fail "Workspace.swift / Project.swift 를 찾을 수 없습니다"
fi

step "빌드 대상 탐색"
CONTAINER_FLAG=""
if compgen -G "*.xcworkspace" >/dev/null; then
  CONTAINER_FLAG="-workspace $(ls -d *.xcworkspace | head -1)"
elif compgen -G "*.xcodeproj" >/dev/null; then
  CONTAINER_FLAG="-project $(ls -d *.xcodeproj | head -1)"
else
  fail "xcworkspace/xcodeproj 를 찾을 수 없습니다"
fi

# Tuist는 "Generate Project" 같은 헬퍼 스킴도 만든다. 앱 스킴을 골라야 한다.
SCHEME="$(xcodebuild $CONTAINER_FLAG -list -json 2>/dev/null \
  | python3 -c '
import sys, json
d = json.load(sys.stdin)
c = d.get("workspace") or d.get("project")
schemes = c["schemes"]
skip = {"Generate Project"}
# -Workspace 접미사가 붙은 통합 스킴보다 앱 스킴을 우선한다
app = [s for s in schemes if s not in skip and not s.endswith("-Workspace")]
print((app or [s for s in schemes if s not in skip] or schemes)[0])' 2>/dev/null || true)"
[ -n "$SCHEME" ] || fail "스킴을 찾을 수 없습니다"
ok "컨테이너: ${CONTAINER_FLAG#* } / 스킴: $SCHEME"

step "시뮬레이터 선택"
DEST_ID="$(xcrun simctl list devices available -j \
  | python3 -c '
import sys, json
d = json.load(sys.stdin)["devices"]
best = None
for runtime, devices in d.items():
    if "iOS-26" not in runtime:
        continue
    for dev in devices:
        if dev.get("isAvailable") and "iPhone" in dev["name"]:
            best = dev["udid"]
            break
    if best: break
print(best or "")' )"
[ -n "$DEST_ID" ] || fail "iOS 26 iPhone 시뮬레이터를 찾을 수 없습니다"
ok "시뮬레이터: $DEST_ID"

step "멀티플랫폼 스킴 탐색"
# macOS 대상을 선언한 프레임워크는 macOS로도 빌드해야 한다.
# 0-C 오프라인 CLI가 같은 엔진을 쓰므로, iOS만 통과하면 그쪽이 뒤늦게 깨진다.
MAC_SCHEMES=()
for manifest in Projects/*/Project.swift; do
  [ -f "$manifest" ] || continue
  grep -q "\.mac" "$manifest" || continue
  MAC_SCHEMES+=("$(basename "$(dirname "$manifest")")")
done
if [ ${#MAC_SCHEMES[@]} -gt 0 ]; then
  ok "macOS 대상: ${MAC_SCHEMES[*]}"
else
  printf "macOS 대상 없음 — iOS만 검증합니다\n"
fi

LOGS=()

step "iOS 빌드 ($SCHEME)"
IOS_LOG=/tmp/teniteni-build-ios.log
set +e
xcodebuild $CONTAINER_FLAG -scheme "$SCHEME" \
  -destination "id=$DEST_ID" \
  -configuration Debug \
  CODE_SIGNING_ALLOWED=NO \
  build 2>&1 | tee "$IOS_LOG" | tail -30
STATUS=${PIPESTATUS[0]}
set -e
[ "$STATUS" -eq 0 ] || fail "iOS 빌드 실패 — 전체 로그: $IOS_LOG"
LOGS+=("$IOS_LOG")
ok "iOS 빌드 성공"

for mac_scheme in ${MAC_SCHEMES[@]+"${MAC_SCHEMES[@]}"}; do
  step "macOS 빌드 ($mac_scheme)"
  MAC_LOG="/tmp/teniteni-build-macos-$mac_scheme.log"
  set +e
  xcodebuild $CONTAINER_FLAG -scheme "$mac_scheme" \
    -destination "platform=macOS,arch=$(uname -m)" \
    -configuration Debug \
    CODE_SIGNING_ALLOWED=NO \
    build 2>&1 | tee "$MAC_LOG" | tail -30
  STATUS=${PIPESTATUS[0]}
  set -e
  [ "$STATUS" -eq 0 ] || fail "macOS 빌드 실패 ($mac_scheme) — 전체 로그: $MAC_LOG"
  LOGS+=("$MAC_LOG")
  ok "macOS 빌드 성공 ($mac_scheme)"
done

step "동시성 경고 집계"
# 컴파일러 경고만 센다. appintentsmetadataprocessor 같은 툴이 내는
# "warning:" 줄은 소스 품질과 무관하므로 파일:행:열 형태로 한정한다.
WARN_PATTERN='^/.*:[0-9]+:[0-9]+: warning: '
CONC_PATTERN='sendable|concurrency|actor-isolated|data race'
WARNINGS="$(grep -hE "$WARN_PATTERN" "${LOGS[@]}" || true)"
WARN_COUNT=$(printf '%s' "$WARNINGS" | grep -c . || true)
CONC_COUNT=$(printf '%s' "$WARNINGS" | grep -ciE "$CONC_PATTERN" || true)
printf "전체 경고: %s / 동시성 관련: %s\n" "$WARN_COUNT" "$CONC_COUNT"
if [ "$CONC_COUNT" -gt 0 ]; then
  printf '\033[33m⚠ 동시성 경고가 있습니다 (CONCURRENCY.md 6.8절 검증 항목)\033[0m\n'
  printf '%s\n' "$WARNINGS" | grep -iE "$CONC_PATTERN" | head -10
fi

printf '\n\033[32m=== 게이트 통과 ===\033[0m\n'
