#!/usr/bin/env bash
# iOS 검증 게이트 — CI 워크플로 도입(0-D) 전까지 로컬 관문으로 사용한다.
# 사용: ./scripts/verify-ios.sh
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IOS_DIR="$ROOT/ios"

step() { printf '\n\033[1m▸ %s\033[0m\n' "$1"; }
fail() { printf '\033[31m✗ %s\033[0m\n' "$1" >&2; exit 1; }
ok()   { printf '\033[32m✓ %s\033[0m\n' "$1"; }

# 검증 단계. 잡 하나가 전부를 직렬로 돌면 타임아웃에 반복해 닿는다 —
# 실측 20.7분·20.8분에 상한이 30분이었고 한 번은 30분 30초에 취소됐다
# (이슈 #113). 단계를 쪼개면 CI가 병렬로 돌릴 수 있다.
#
# ⚠️ 기본값은 `all`이다. **사람이 쓰는 방식은 달라지지 않는다** — 로컬에서
# 한 줄로 전부 도는 것이 이 스크립트의 원래 용도이고, 쪼갠 것을 사람이
# 조립하게 만들면 "로컬에서는 통과했다"의 의미가 흐려진다.
#
# | 단계 | 내용 | 시뮬레이터 |
# |---|---|---|
# | `ios`   | 앱 빌드 + iOS 단위 테스트 | 필요 |
# | `ui`    | UI 테스트 (앱을 test 액션이 빌드한다) | 필요 |
# | `macos` | macOS 대상 스킴 | 불필요 |
PHASE=all
for arg in "$@"; do
  case "$arg" in
    --phase=*) PHASE="${arg#--phase=}" ;;
    -h|--help)
      printf '사용: %s [--phase=all|ios|ui|macos]\n' "$0"
      printf '  all   (기본) 전부 — 로컬 게이트\n'
      printf '  ios   앱 빌드 + iOS 단위 테스트\n'
      printf '  ui    iOS UI 테스트\n'
      printf '  macos macOS 대상 스킴\n'
      exit 0 ;;
    *) fail "모르는 인자: $arg (--help 참고)" ;;
  esac
done
case "$PHASE" in
  all|ios|ui|macos) ;;
  *) fail "--phase는 all|ios|ui|macos 중 하나다 (받은 값: $PHASE)" ;;
esac

# 이 단계가 해당 작업을 하는가.
wants() { [ "$PHASE" = all ] || [ "$PHASE" = "$1" ]; }

[ -d "$IOS_DIR" ] || fail "ios/ 디렉터리가 없습니다"

# 로컬과 CI의 툴체인이 다르면 같은 코드가 한쪽에서만 깨진다. 실제로 1-A에서
# UIKitNavigation의 가용성 검사가 로컬(Xcode 26.6)에서는 통과하고 CI에서는
# 실패했다. 버전을 찍어두면 다음에 갈릴 때 바로 보인다.
#
# ⚠️ 이 검사는 **프로젝트 생성보다 먼저** 한다. 뒤에 두면 지원하지 않는
# Xcode에서도 install·checkouts 치환·generate를 다 치르고 수 분 뒤에야
# 끊긴다. checkouts 치환은 로컬 캐시 상태를 바꾸는 일이라 더 그렇다.
step "툴체인"

# ⚠️ `xcodebuild -version`을 **한 번만** 부른다. 그리고 그 실패를
# `set -e`에 그대로 넘기지 않는다.
#
# 전에는 표시용과 판정용으로 두 번 불렀다. 두 번째가 러너에서 SIGABRT로
# 죽으면(exit 134) 그것이 **명령 치환 대입**이라 `set -e`가 종료 코드만
# 전파하고, 바로 아래의 사람이 읽을 메시지는 영원히 출력되지 않았다.
# 게이트가 "Process completed with exit code 134" 한 줄만 남기고 끊겼다.
#
# 실측 2회: PR #112(2026-10-26) · PR #115(2026-10-27). 일회성이 아니다.
# 잡을 셋으로 쪼갠 뒤에는 **한 실행에서 세 번 노출된다** — 아무 하나가
# 걸려도 게이트가 막힌다. 근거: 이슈 #113
#
# 재시도는 실패를 숨기는 것이 아니다. 세 번 다 실패하면 사유와 함께
# 끊는다 — 숨기는 것은 침묵하는 134 쪽이다.
XCODE_RAW=""
for attempt in 1 2 3; do
  # `|| true`가 핵심이다. 없으면 치환 실패가 그대로 스크립트를 끊는다.
  XCODE_RAW="$(xcodebuild -version 2>/dev/null || true)"
  if [ -n "$XCODE_RAW" ]; then
    break
  fi
  printf "  xcodebuild -version이 응답하지 않습니다 — 다시 시도 (%s/3)\n" "$attempt"
  sleep 3
done
[ -n "$XCODE_RAW" ] || fail "xcodebuild를 찾을 수 없습니다 ($(xcode-select -p)).
    Xcode가 설치돼 있는지, DEVELOPER_DIR이 올바른지 확인하세요.
    세 번 시도했습니다 — 러너 쪽 일시 장애일 수 있습니다."

printf "  %s\n" "$(printf '%s' "$XCODE_RAW" | tr '\n' ' ')"
printf "  %s\n" "$(swift --version 2>&1 | head -1)"

# ⚠️ 최소 버전을 여기서 끊는다. 낮은 Xcode에서는 외부 패키지 안쪽이
# 깨지면서 터져 원인이 전혀 보이지 않는다 — 26.0.1(Swift 6.2)에서는
# "'_StoreBindable_Perception' is unavailable in iOS"가, SWIFT_VERSION을
# 묶어 두면 "invalid redeclaration of 'IsolationCheck'"가 나온다.
# 둘 다 우리 코드와 무관한데 우리 코드를 의심하게 만든다.
MIN_XCODE="26.6"
# 위에서 받아 둔 출력을 쓴다. 다시 부르지 않는다.
XCODE_VERSION="$(printf '%s\n' "$XCODE_RAW" | head -1 | awk '{print $2}')"
[ -n "$XCODE_VERSION" ] || fail "xcodebuild -version의 출력에서 버전을 읽지 못했습니다.
    받은 것: $XCODE_RAW"
if [ "$(printf '%s\n%s\n' "$MIN_XCODE" "$XCODE_VERSION" | sort -V | head -1)" != "$MIN_XCODE" ]; then
  fail "Xcode $MIN_XCODE 이상이 필요합니다 (현재 $XCODE_VERSION, $(xcode-select -p)).
    DEVELOPER_DIR을 지정하거나 xcode-select로 바꾸세요."
fi
ok "툴체인 확인 (Xcode $XCODE_VERSION)"

step "Tuist 프로젝트 생성"
cd "$IOS_DIR"
if [ -f "Workspace.swift" ] || [ -f "Project.swift" ]; then
  tuist install >/dev/null 2>&1 || true

  # ⚠️ Tuist 4.203+는 checkouts/를 공유 캐시로 가는 심링크로 만든다.
  # 매크로 패키지들은 swift-syntax의 모듈맵을 `checkouts/<pkg>/../swift-syntax/…`
  # 로 가리키는데, 심링크를 타고 `..`를 풀면 캐시 디렉터리로 나가버려
  # "module map file … not found"로 빌드가 통째로 깨진다.
  # APFS 클론(cp -Rc)이라 복사는 사실상 공짜다.
  #
  # readlink -f로 실경로를 받는다. 그냥 readlink는 심링크에 적힌 값을
  # 그대로 주므로, Tuist가 상대 경로로 걸어두면 cp의 소스가 현재 디렉터리
  # 기준으로 해석돼 엉뚱한 곳을 가리킨다.
  #
  # TODO(#70): Tuist가 이 레이아웃을 바꾸면 이 블록은 불필요해진다.
  #   checkouts/가 더 이상 심링크가 아니면 루프가 통째로 건너뛴다.
  if [ -d "Tuist/.build/checkouts" ]; then
    for link in Tuist/.build/checkouts/*; do
      [ -L "$link" ] || continue
      target="$(readlink -f "$link")"
      [ -d "$target" ] || fail "checkouts 심링크가 가리키는 곳이 없습니다: $link → $target"
      rm "$link"
      cp -Rc "$target" "$link" 2>/dev/null || cp -R "$target" "$link"
    done
  fi

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
#
# ⚠️ 예전에는 필터 후 첫 번째를 집었다. 모듈이 하나일 때는 맞았지만 1-A에서
# 여섯 개로 늘자 알파벳 순으로 "Application"(정적 프레임워크)이 잡혔고,
# **앱 타깃이 빌드되지 않은 채 게이트가 통과했다.** 진입점도 Info.plist도
# 검증되지 않는다. 워크스페이스 이름과 같은 스킴을 먼저 찾는다.
SCHEME="$(xcodebuild $CONTAINER_FLAG -list -json 2>/dev/null \
  | python3 -c '
import sys, json
d = json.load(sys.stdin)
c = d.get("workspace") or d.get("project")
schemes = c["schemes"]
name = c.get("name")
skip = {"Generate Project"}
candidates = [s for s in schemes if s not in skip and not s.endswith("-Workspace")]
# 1순위: 컨테이너 이름과 같은 스킴 (= 앱 타깃)
exact = [s for s in candidates if s == name]
print((exact or candidates or [s for s in schemes if s not in skip] or schemes)[0])' 2>/dev/null || true)"
[ -n "$SCHEME" ] || fail "스킴을 찾을 수 없습니다"
ok "컨테이너: ${CONTAINER_FLAG#* } / 스킴: $SCHEME"

step "시뮬레이터 선택"
# macOS 단계는 시뮬레이터를 쓰지 않는다. 고르기만 해도 `simctl`이 런타임을
# 깨우느라 수십 초를 먹으므로 건너뛴다.
DEST_ID=""
if wants ios || wants ui; then
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
else
  printf "단계 %s — 시뮬레이터가 필요 없습니다\n" "$PHASE"
fi

step "멀티플랫폼 스킴 탐색"
# macOS 대상을 선언한 프레임워크는 macOS로도 빌드해야 한다.
# 0-C 오프라인 CLI가 같은 엔진을 쓰므로, iOS만 통과하면 그쪽이 뒤늦게 깨진다.
#
# 단계가 macos가 아니면 **빈 배열로 둔다.** 아래 루프가 자연히 돌지 않는다.
MAC_SCHEMES=()
if wants macos; then
for manifest in Projects/*/Project.swift; do
  [ -f "$manifest" ] || continue
  # destinations 선언만 본다. 주석에 ".mac"이 있어도 오탐하지 않는다.
  grep -qE '^[[:space:]]*destinations:.*\.mac' "$manifest" || continue
  MAC_SCHEMES+=("$(basename "$(dirname "$manifest")")")
done
fi
if [ ${#MAC_SCHEMES[@]} -gt 0 ]; then
  ok "macOS 대상: ${MAC_SCHEMES[*]}"
elif wants macos; then
  printf "macOS 대상 없음 — iOS만 검증합니다\n"
else
  printf "단계 %s — macOS 대상은 다른 단계가 본다\n" "$PHASE"
fi

LOGS=()

# 빌드가 깨졌을 때 왜 깨졌는지 보여준다.
#
# ⚠️ tee | tail -30 은 진행 상황을 줄이려는 것인데, 실패하면 꼬리 30줄이
# 컴파일 명령줄로 가득 차 정작 error: 가 화면 밖으로 밀린다. 로컬에서는
# 전체 로그를 열면 되지만 CI에서는 러너가 사라져 영영 못 본다.
# 실제로 1-A에서 CI 실패 원인을 못 찾아 한 바퀴 돌았다.
show_errors() {
  local log="$1"
  printf '\n\033[1m▸ 오류\033[0m\n'
  grep -E '(error|Error):' "$log" | grep -vE '^\s' | sed 's|.*/TeniTeni/||' | sort -u | head -20 | sed 's/^/    /'
}

if wants ios; then
step "iOS 빌드 ($SCHEME)"
IOS_LOG=/tmp/teniteni-build-ios.log
# CLEAN_BUILD=1이면 clean을 먼저 넣어 전체 재컴파일한다 (경고 사각 제거)
BUILD_ACTION="build"
[ "${CLEAN_BUILD:-0}" = "1" ] && BUILD_ACTION="clean build"
set +e
xcodebuild $CONTAINER_FLAG -scheme "$SCHEME" \
  -destination "id=$DEST_ID" \
  -configuration Debug \
  CODE_SIGNING_ALLOWED=NO \
  $BUILD_ACTION 2>&1 | tee "$IOS_LOG" | tail -30
STATUS=${PIPESTATUS[0]}
set -e
[ "$STATUS" -eq 0 ] || { show_errors "$IOS_LOG"; fail "iOS 빌드 실패 — 전체 로그: $IOS_LOG"; }
fi

# ⚠️ 앱 스킴에는 테스트가 들어오지 않는다. Tuist는 모듈별 프로젝트의
# 스킴에 그 모듈의 테스트를 넣는다. 앱만 빌드하면 iOS 테스트를 써도
# 한 번도 실행되지 않은 채 "게이트 통과"가 찍힌다 — 규약 12.7이 경고하는
# "돌지 않고 통과하는" 실패 양식이다.
#
# 단계가 ios가 아니면 **빈 배열로 둔다.** 아래 루프가 자연히 돌지 않는다.
IOS_TEST_SCHEMES=()
if wants ios; then
for manifest in Projects/*/Project.swift; do
  grep -q 'product: \.unitTests' "$manifest" || continue
  # macOS 루프가 따로 도는 멀티플랫폼 모듈은 여기서 제외한다
  grep -qE 'destinations:.*\.mac' "$manifest" && continue
  IOS_TEST_SCHEMES+=("$(basename "$(dirname "$manifest")")")
done
fi

for scheme in ${IOS_TEST_SCHEMES[@]+"${IOS_TEST_SCHEMES[@]}"}; do
  step "iOS 테스트 ($scheme)"
  TEST_LOG="/tmp/teniteni-test-ios-$scheme.log"
  set +e
  xcodebuild $CONTAINER_FLAG -scheme "$scheme" \
    -destination "id=$DEST_ID" \
    -configuration Debug \
    CODE_SIGNING_ALLOWED=NO \
    test 2>&1 | tee "$TEST_LOG" | tail -30
  STATUS=${PIPESTATUS[0]}
  set -e
  [ "$STATUS" -eq 0 ] || { show_errors "$TEST_LOG"; fail "iOS 테스트 실패 ($scheme) — 전체 로그: $TEST_LOG"; }
  # ⚠️ 요약 문자열이 비어 있지 않은지만 보면 안 된다. 수집에 실패하면
  # xcodebuild는 "Test run with 0 tests in 0 suites passed"를 출력하고
  # 종료 코드 0을 준다 — 비어 있지 않으므로 그대로 통과해버린다.
  # 규약 12.7이 경고하는 "돌지 않고 통과하는" 실패 양식이다. 숫자를 본다.
  # (아래 macOS 분기와 같은 검사다)
  SUMMARY="$(grep -oE 'Test run with [0-9]+ tests?[^.]*' "$TEST_LOG" | tail -1 || true)"
  COUNT=$(printf '%s' "$SUMMARY" | grep -oE '[0-9]+' | head -1 || true)
  if [ -z "${COUNT:-}" ] || [ "$COUNT" -eq 0 ]; then
    fail "iOS 테스트가 0건 실행됐습니다 ($scheme) — 수집 실패일 수 있습니다. 로그: $TEST_LOG"
  fi
  ok "iOS 테스트 성공 ($scheme) — $SUMMARY"
  LOGS+=("$TEST_LOG")
done
if wants ios; then
  LOGS+=("$IOS_LOG")
  ok "iOS 빌드 성공"
fi

# UI 테스트는 앱 타깃에 붙는다 — 화면 전환과 방향 잠금은 모듈 테스트가
# 닿지 않는 곳에서 일어난다 (이슈 #83). 위 루프는 Projects/*의 unitTests만
# 모으므로 여기서 따로 돈다.
#
# `ui` 단계는 앞의 평범한 빌드를 건너뛴다. `test` 액션이 앱과 러너를
# 어차피 빌드하므로 두 번 빌드하면 쪼갠 이유가 사라진다. 그래서 이 단계의
# 경고 집계는 **UI 테스트 로그에서** 나온다 — 거기에 앱 전체 빌드가 들어 있다.
if wants ui && grep -q 'product: \.uiTests' Project.swift; then
  step "iOS UI 테스트 ($SCHEME)"
  UI_LOG=/tmp/teniteni-test-ios-ui.log
  set +e
  xcodebuild $CONTAINER_FLAG -scheme "$SCHEME" \
    -destination "id=$DEST_ID" \
    -configuration Debug \
    CODE_SIGNING_ALLOWED=NO \
    -only-testing:TeniTeniUITests \
    test 2>&1 | tee "$UI_LOG" | tail -30
  STATUS=${PIPESTATUS[0]}
  set -e
  [ "$STATUS" -eq 0 ] || { show_errors "$UI_LOG"; fail "iOS UI 테스트 실패 — 전체 로그: $UI_LOG"; }
  # 0건 통과를 막는다. UI 테스트는 수집 실패가 더 흔하다 —
  # 타깃 이름을 고치면 -only-testing이 조용히 아무것도 고르지 않는다.
  UI_COUNT=$(grep -cE "^Test Case .* passed" "$UI_LOG" || true)
  [ "${UI_COUNT:-0}" -gt 0 ] || fail "UI 테스트가 0건 실행됐습니다 — 로그: $UI_LOG"
  # ${} 로 감싼다. 한글이 바로 뒤에 붙으면 bash가 변수명으로 먹는다.
  ok "iOS UI 테스트 성공 — ${UI_COUNT}건"
  LOGS+=("$UI_LOG")
fi

for mac_scheme in ${MAC_SCHEMES[@]+"${MAC_SCHEMES[@]}"}; do
  # 테스트 타깃이 있으면 build 대신 test를 돌린다. 빌드만 보면
  # "테스트는 있는데 한 번도 실행되지 않는" 상태를 못 잡는다.
  ACTION=build
  if grep -q 'product: \.unitTests' "Projects/$mac_scheme/Project.swift" 2>/dev/null; then
    ACTION=test
  fi

  step "macOS $ACTION ($mac_scheme)"
  MAC_LOG="/tmp/teniteni-build-macos-$mac_scheme.log"
  set +e
  MAC_ACTION="$ACTION"
  [ "${CLEAN_BUILD:-0}" = "1" ] && MAC_ACTION="clean $ACTION"
  xcodebuild $CONTAINER_FLAG -scheme "$mac_scheme" \
    -destination "platform=macOS,arch=$(uname -m)" \
    -configuration Debug \
    CODE_SIGNING_ALLOWED=NO \
    $MAC_ACTION 2>&1 | tee "$MAC_LOG" | tail -30
  STATUS=${PIPESTATUS[0]}
  set -e
  [ "$STATUS" -eq 0 ] || { show_errors "$MAC_LOG"; fail "macOS $ACTION 실패 ($mac_scheme) — 전체 로그: $MAC_LOG"; }
  LOGS+=("$MAC_LOG")

  if [ "$ACTION" = test ]; then
    # 통과 개수만 보면 수집되지 않아 조용히 건너뛴 테스트를 놓친다.
    # 실제 형식: "Test run with 25 tests in 6 suites passed after 48.3 seconds."
    # tests와 passed 사이에 "in N suites"가 끼므로 붙여서 매칭하면 안 된다.
    SUMMARY="$(grep -oE 'Test run with [0-9]+ tests?[^.]*' "$MAC_LOG" | tail -1 || true)"
    COUNT=$(printf '%s' "$SUMMARY" | grep -oE '[0-9]+' | head -1 || true)
    if [ -z "${COUNT:-}" ] || [ "$COUNT" -eq 0 ]; then
      fail "테스트가 0건 실행됐습니다 ($mac_scheme) — 수집 실패일 수 있습니다. 로그: $MAC_LOG"
    fi
    ok "macOS 테스트 성공 ($mac_scheme) — $SUMMARY"
  else
    ok "macOS 빌드 성공 ($mac_scheme)"
  fi
done

step "동시성 경고 집계"
# ⚠️ 증분 빌드는 경고를 가린다. 바뀌지 않은 파일은 재컴파일되지 않으므로
# 그 파일의 경고가 로그에 남지 않는다. 실제로 var/let 경고 하나가 며칠간
# "경고 0"으로 보고되다가 그 파일을 건드린 순간 드러났다.
#
# CI는 매번 새 러너라 항상 전체 빌드다. 로컬만 이 사각이 있다.
# CLEAN_BUILD=1로 전체 빌드를 강제할 수 있다 — 느리므로 기본은 아니다.
if [ "${CLEAN_BUILD:-0}" = "1" ]; then
  printf "CLEAN_BUILD=1 — 전체 빌드로 경고를 전부 봅니다\n"
fi

# 컴파일러 경고만 센다. appintentsmetadataprocessor 같은 툴이 내는
# "warning:" 줄은 소스 품질과 무관하므로 파일:행:열 형태로 한정한다.
WARN_PATTERN='^/.*:[0-9]+:[0-9]+: warning: '
CONC_PATTERN='sendable|concurrency|actor-isolated|data race'
# 로그가 하나도 없으면 집계가 "경고 0"을 찍는다. 그것은 **검증이 아니라
# 아무것도 돌지 않았다는 뜻**이므로 구분해 끊는다 — 규약 12.7이 경고하는
# "조용히 통과하는" 실패 양식이다.
[ ${#LOGS[@]} -gt 0 ] || fail "이 단계($PHASE)가 로그를 하나도 남기지 않았습니다 — 아무것도 돌지 않았습니다"
WARNINGS="$(grep -hE "$WARN_PATTERN" "${LOGS[@]}" || true)"
WARN_COUNT=$(printf '%s' "$WARNINGS" | grep -c . || true)
CONC_COUNT=$(printf '%s' "$WARNINGS" | grep -ciE "$CONC_PATTERN" || true)
printf "전체 경고: %s / 동시성 관련: %s\n" "$WARN_COUNT" "$CONC_COUNT"
if [ "$CONC_COUNT" -gt 0 ]; then
  printf '\033[33m⚠ 동시성 경고가 있습니다 (CONCURRENCY.md 6.8절 검증 항목)\033[0m\n'
  printf '%s\n' "$WARNINGS" | grep -iE "$CONC_PATTERN" | head -10
fi

if [ "$PHASE" = all ]; then
  printf '\n\033[32m=== 게이트 통과 ===\033[0m\n'
else
  printf '\n\033[32m=== 게이트 통과 (단계: %s) ===\033[0m\n' "$PHASE"
fi
