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

step "빌드"
set +e
xcodebuild $CONTAINER_FLAG -scheme "$SCHEME" \
  -destination "id=$DEST_ID" \
  -configuration Debug \
  CODE_SIGNING_ALLOWED=NO \
  build 2>&1 | tee /tmp/teniteni-build.log | tail -30
STATUS=${PIPESTATUS[0]}
set -e
[ "$STATUS" -eq 0 ] || fail "빌드 실패 — 전체 로그: /tmp/teniteni-build.log"
ok "빌드 성공"

step "동시성 경고 집계"
WARN_COUNT=$(grep -c "warning:" /tmp/teniteni-build.log || true)
CONC_COUNT=$(grep -ci "sendable\|concurrency\|actor-isolated\|data race" /tmp/teniteni-build.log || true)
printf "전체 경고: %s / 동시성 관련: %s\n" "$WARN_COUNT" "$CONC_COUNT"
if [ "$CONC_COUNT" -gt 0 ]; then
  printf '\033[33m⚠ 동시성 경고가 있습니다 (CONCURRENCY.md 6.8절 검증 항목)\033[0m\n'
  grep -i "sendable\|concurrency\|actor-isolated\|data race" /tmp/teniteni-build.log | head -10
fi

printf '\n\033[32m=== 게이트 통과 ===\033[0m\n'
