#!/usr/bin/env bash
# Phase 16.2 D-05 — 키 미설정 계약(fresh clone 상태)의 빌드 게이트.
# Phase 17.3 D-15 — see ROADMAP.md. provider on/off 3케이스 설정 매트릭스 + 산출물 scheme 단언으로 확장.
#
# 목적:
#   fork/clone 직후처럼 실제 키가 하나도 없는 상태(tracked placeholder 만 있는 상태)에서도
#   dev / stg / prod 3 flavor 의 Android · iOS 빌드가 성공한다는 계약(D-05)을 재현 가능한
#   한 명령으로 검증한다. Naver Login 은 runtime initialize 가 없고 빌드 타임 native 설정
#   (Android manifest meta-data / iOS Info.plist Nid*)을 읽으므로, 키가 비어 있을 때
#   빌드가 깨지면 킷을 clone 한 사람이 첫 빌드부터 막힌다.
#   17.3 부터는 키를 비운 provider 가 일반 URL scheme(빈 값 · fb · kakao)을 등록하지 않는다는
#   불변식(D-04)도 빌드 산출물로 함께 단언한다.
#
# 케이스 (D-15):
#   off    ① 소셜 전부 off — enabledAuthProviders "" · 키 8개 전부 비움 (clone 직후 기본 상태)
#   google ② Google 만 on — enabledAuthProviders "google" · googleServerClientId 외 키 7개 비움
#   all    ③ 6개 전부 on — enabledAuthProviders 6개 · 키는 example placeholder 그대로 (16.2 D-05 회귀, 기본값)
#
# 빌드 뒤 부팅 체크리스트 (사람이 확인 — 이 스크립트 밖, D-15 매트릭스 · D-16 실기기):
#   산출물을 에뮬레이터 · 시뮬레이터 · 실기기에 설치해 케이스마다 차례로 본다.
#   1. 부팅 → 온보딩 → 로그인 화면(케이스의 소셜 버튼 수 · 「또는」 구분선 유무).
#   2. 설정 화면.
#   3. 이메일 로그인 → 로그아웃 → 온보딩 복귀. off · google 케이스는 bootstrap 이 초기화하지
#      않은 SDK 의 로그아웃을 부르면 안 된다(LINE 은 setup 없이 logout 을 부르면 네이티브가
#      프로세스를 끝낸다 — 17.3 code review CR-01 · WR-01). Android 는 logcat `FATAL EXCEPTION`
#      0 건, iOS 는 앱 생존(crash log 0 건)을 기록한다. 이메일 계정이 없으면 가입 링크로 만든다.
#
# 사용법:
#   bash scripts/verify_placeholder_builds.sh <android|ios> <dev|stg|prod> [off|google|all] [--simulator]
#   셋째 인자 생략 = all. --simulator 는 ios 전용(시뮬레이터 부팅용 build/ios/iphonesimulator/Runner.app).
#   성공 시 마지막 줄: PLACEHOLDER-BUILD-OK <platform> <flavor> <case>[ simulator] (exit 0)
#   실패 시: FAIL: <사유> + 빌드 로그 마지막 30줄 (exit 1), 인자 오류는 exit 2
#   케이스 입력: build/placeholder-gate/<flavor>-<case>.json (example 에서 jq 로 생성)
#   빌드 로그: build/placeholder-gate/<platform>-<flavor>-<case>[-sim].log (stdout + stderr, build/ 는 gitignored)
#
# 안전 계약 (C-04):
#   - 실 키 파일(config/<flavor>.json · ios/Flutter/<flavor>.xcconfig 의 값)을 읽지도 바꾸지도 않는다.
#   - 입력은 tracked placeholder(config/<flavor>.example.json · ios/Flutter/<flavor>.example.xcconfig)와
#     거기서 만든 케이스 JSON 뿐이다.
#   - iOS 는 xcconfig 키 8개를 전부 FLUTTER_XCODE_* 환경변수 override 로 넣는다 — 파일 교체가 아니다
#     (Flutter tool 이 이 접두어 환경변수를 xcodebuild 빌드 설정으로 넘기고, 명령행 빌드 설정은
#      xcconfig 보다 우선한다 — 3.47.5 packages/flutter_tools/lib/src/ios/xcodeproj.dart:516).
#     빈 값 override 도 유효하므로 실 xcconfig 값이 산출물에 섞이지 않는다.
#   - ios/Flutter/<flavor>.xcconfig 는 "없을 때만" example 에서 복사한다. 이미 있으면 절대 건드리지 않는다.
#   - 빌드 성공만으로 통과시키지 않는다 — 산출물의 Naver 값과 URL scheme 목록을 케이스 기대값과 함께 단언한다.
#
# 여기서 비교·출력되는 값은 전부 tracked placeholder 또는 빈 값이라 로그에 노출돼도 무방하다.
#
# starter-kit 정책: 외부 CI 미도입 — 사람이 직접 호출하는 게이트 스크립트다.

set -euo pipefail

usage() {
  cat >&2 <<'USAGE'
usage: bash scripts/verify_placeholder_builds.sh <android|ios> <dev|stg|prod> [off|google|all] [--simulator]

  placeholder(키 미설정) 입력만으로 해당 플랫폼 · flavor 빌드가 성공하는지 검증한다.
  케이스: off = 소셜 전부 off + 키 비움 · google = Google 만 on · all = 6개 on + placeholder (기본값)
  --simulator 는 ios 전용 — 시뮬레이터용 Runner.app 을 빌드한다.
  빌드 하나에 수 분이 걸리므로 조합마다 따로 호출한다.
USAGE
}

if [ "$#" -gt 4 ]; then
  usage
  exit 2
fi

PLATFORM="${1:-}"
FLAVOR="${2:-}"
CASE="${3:-all}"
SIM_ARG="${4:-}"

case "$PLATFORM" in
  android | ios) ;;
  *)
    usage
    exit 2
    ;;
esac

case "$FLAVOR" in
  dev | stg | prod) ;;
  *)
    usage
    exit 2
    ;;
esac

case "$CASE" in
  off | google | all) ;;
  *)
    usage
    exit 2
    ;;
esac

SIMULATOR=0
case "$SIM_ARG" in
  "") ;;
  --simulator)
    # 시뮬레이터 빌드는 iOS 에만 있다.
    if [ "$PLATFORM" != "ios" ]; then
      usage
      exit 2
    fi
    SIMULATOR=1
    ;;
  *)
    usage
    exit 2
    ;;
esac

# flavor 첫 글자 대문자형 (Android 병합 manifest 경로용).
# bash 3.2(macOS 기본)에는 ${var^} 가 없으므로 case 로 만든다.
case "$FLAVOR" in
  dev) FLAVOR_CAP="Dev" ;;
  stg) FLAVOR_CAP="Stg" ;;
  prod) FLAVOR_CAP="Prod" ;;
esac

SIM_SUFFIX=""
SIM_SENTINEL=""
if [ "$SIMULATOR" -eq 1 ]; then
  SIM_SUFFIX="-sim"
  SIM_SENTINEL=" simulator"
fi

LOG_DIR="build/placeholder-gate"
LOG="${LOG_DIR}/${PLATFORM}-${FLAVOR}-${CASE}${SIM_SUFFIX}.log"
EXAMPLE_JSON="config/${FLAVOR}.example.json"
CASE_JSON="${LOG_DIR}/${FLAVOR}-${CASE}.json"

# 케이스가 비우는 config 키 8개 (enabledAuthProviders 는 따로 정한다).
ALL_SOCIAL_CSV="google,apple,facebook,kakao,naver,line"

mkdir -p "$LOG_DIR"

# 실패 시: 사유 한 줄 + 빌드 로그 꼬리를 stderr 로 내고 종료한다.
fail() {
  echo "FAIL: $1" >&2
  if [ -f "$LOG" ]; then
    echo "--- tail -30 ${LOG} ---" >&2
    tail -30 "$LOG" >&2
  fi
  exit 1
}

# gradleResValues.xml 에서 <string name="..."> 값 추출 (빈 값 · 자기 닫힘 태그는 빈 문자열).
res_value() {
  local file="$1"
  local name="$2"
  sed -nE 's#^[[:space:]]*<string name="'"$name"'"[^>]*>(.*)</string>.*$#\1#p' "$file"
}

# 파일에서 줄 전체가 정확히 일치하는 줄 수. 0 건이어도 set -e 로 죽지 않게 한다.
count_exact_lines() {
  grep -cxF "$1" "$2" || true
}

if [ ! -f "$EXAMPLE_JSON" ]; then
  echo "FAIL: placeholder 입력 파일 없음: ${EXAMPLE_JSON}" >&2
  exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "FAIL: jq 가 필요하다 (brew install jq)" >&2
  exit 1
fi

# ── 케이스 JSON 생성 ─────────────────────────────────────────────────────────
# example 만 입력으로 쓴다. off · google 은 키를 빈 문자열로 덮어쓴다.
case "$CASE" in
  all)
    CASE_FILTER='.enabledAuthProviders = $csv'
    CASE_CSV="$ALL_SOCIAL_CSV"
    ;;
  google)
    CASE_FILTER='.enabledAuthProviders = $csv | .facebookAppId = "" | .facebookClientToken = "" | .kakaoNativeAppKey = "" | .naverClientId = "" | .naverClientSecret = "" | .naverUrlScheme = "" | .lineChannelId = ""'
    CASE_CSV="google"
    ;;
  off)
    CASE_FILTER='.enabledAuthProviders = $csv | .googleServerClientId = "" | .facebookAppId = "" | .facebookClientToken = "" | .kakaoNativeAppKey = "" | .naverClientId = "" | .naverClientSecret = "" | .naverUrlScheme = "" | .lineChannelId = ""'
    CASE_CSV=""
    ;;
esac

jq --arg csv "$CASE_CSV" "$CASE_FILTER" "$EXAMPLE_JSON" >"$CASE_JSON" ||
  fail "케이스 JSON 생성 실패: ${CASE_JSON}"
echo "case ${CASE}: ${CASE_JSON} (from ${EXAMPLE_JSON})"

if [ "$PLATFORM" = "android" ]; then
  # ── Android ────────────────────────────────────────────────────────────────
  # 키는 dart-define(=케이스 json) → gradle resValue · manifestPlaceholders → manifest 경로로 들어간다.
  echo "building android ${FLAVOR} ${CASE} with ${CASE_JSON} (log: ${LOG})"
  if ! fvm flutter build apk --debug --flavor "$FLAVOR" \
    --dart-define-from-file="$CASE_JSON" >"$LOG" 2>&1; then
    fail "android ${FLAVOR} ${CASE} 빌드 실패"
  fi

  APK="build/app/outputs/flutter-apk/app-${FLAVOR}-debug.apk"
  [ -f "$APK" ] || fail "APK 미생성: ${APK}"

  MERGED_MANIFEST="build/app/intermediates/merged_manifests/${FLAVOR}Debug/process${FLAVOR_CAP}DebugManifest/AndroidManifest.xml"
  [ -f "$MERGED_MANIFEST" ] || fail "병합 manifest 미발견: ${MERGED_MANIFEST}"

  for meta in com.naver.sdk.clientId com.naver.sdk.clientSecret com.naver.sdk.clientName com.naver.sdk.logEnabled; do
    grep -qF "$meta" "$MERGED_MANIFEST" || fail "병합 manifest 에 meta-data 없음: ${meta}"
  done

  RES_VALUES="build/app/generated/res/resValues/${FLAVOR}/debug/values/gradleResValues.xml"
  [ -f "$RES_VALUES" ] || fail "resValues 미발견: ${RES_VALUES}"

  EXPECTED_ID="$(jq -r '.naverClientId' "$CASE_JSON")"
  ACTUAL_ID="$(res_value "$RES_VALUES" naver_client_id)"
  [ "$ACTUAL_ID" = "$EXPECTED_ID" ] ||
    fail "naver_client_id 가 케이스 값이 아니다 — 기대 '${EXPECTED_ID}', 실제 '${ACTUAL_ID}'"

  EXPECTED_NAME="$(jq -r '.appName' "$CASE_JSON")"
  ACTUAL_NAME="$(res_value "$RES_VALUES" naver_client_name)"
  [ "$ACTUAL_NAME" = "$EXPECTED_NAME" ] ||
    fail "naver_client_name 불일치 — 기대 '${EXPECTED_NAME}', 실제 '${ACTUAL_NAME}'"

  # 산출물 scheme 단언 (D-04): 키를 비운 provider 는 일반 scheme 을 남기지 않는다.
  SCHEMES="${LOG_DIR}/android-${FLAVOR}-${CASE}-schemes.txt"
  grep -oE 'android:scheme="[^"]*"' "$MERGED_MANIFEST" >"$SCHEMES" || true

  N_EMPTY="$(count_exact_lines 'android:scheme=""' "$SCHEMES")"
  N_KAKAO="$(count_exact_lines 'android:scheme="kakao"' "$SCHEMES")"
  if [ "$N_EMPTY" != "0" ] || [ "$N_KAKAO" != "0" ]; then
    fail "일반 scheme 잔존: 빈 값 ${N_EMPTY}건 · kakao ${N_KAKAO}건 (${SCHEMES})"
  fi

  if [ "$CASE" = "all" ]; then
    EXPECTED_KAKAO_SCHEME="kakao$(jq -r '.kakaoNativeAppKey' "$CASE_JSON")"
    EXPECTED_NAVER_SCHEME="$(jq -r '.naverUrlScheme' "$CASE_JSON")"
  else
    EXPECTED_KAKAO_SCHEME="unset.kakao.oauth"
    EXPECTED_NAVER_SCHEME="unset.naver.web"
  fi

  for expected in "$EXPECTED_KAKAO_SCHEME" "$EXPECTED_NAVER_SCHEME"; do
    N="$(count_exact_lines "android:scheme=\"${expected}\"" "$SCHEMES")"
    [ "$N" = "1" ] || fail "scheme '${expected}' 이 정확히 1건이 아니다 — ${N}건 (${SCHEMES})"
  done

  echo "apk: ${APK}"
  echo "naver_client_id='${ACTUAL_ID}' naver_client_name=${ACTUAL_NAME} (케이스 값 일치)"
  echo "schemes: kakao=${EXPECTED_KAKAO_SCHEME} naver=${EXPECTED_NAVER_SCHEME} · 빈 값 0 · kakao 0 (${SCHEMES})"
else
  # ── iOS ────────────────────────────────────────────────────────────────────
  # flavor xcconfig 는 Debug-<flavor>.xcconfig 가 #include 로 필수 참조하므로 파일 자체는 있어야 한다.
  # 없을 때만 example 에서 만든다(매뉴얼 Initial Setup 의 cp 와 같은 동작, gitignored).
  # 값은 파일이 아니라 환경변수 override 로 케이스 값을 강제한다.
  XCCONFIG="ios/Flutter/${FLAVOR}.xcconfig"
  XCCONFIG_EXAMPLE="ios/Flutter/${FLAVOR}.example.xcconfig"

  [ -f "$XCCONFIG_EXAMPLE" ] || fail "placeholder xcconfig 없음: ${XCCONFIG_EXAMPLE}"

  if [ ! -f "$XCCONFIG" ]; then
    cp "$XCCONFIG_EXAMPLE" "$XCCONFIG"
    echo "created ${XCCONFIG} from example (gitignored)"
  fi

  # example xcconfig 에서 변수 값 하나를 읽는다 (없으면 빈 문자열).
  example_xcconfig_value() {
    awk -F' = ' -v key="$1" '$1 == key {print $2; exit}' "$XCCONFIG_EXAMPLE"
  }

  # example 값 8개 — all 케이스는 전부, google 케이스는 REVERSED_CLIENT_ID 만 쓴다.
  EX_REVERSED_CLIENT_ID="$(example_xcconfig_value REVERSED_CLIENT_ID)"
  EX_FACEBOOK_APP_ID="$(example_xcconfig_value FACEBOOK_APP_ID)"
  EX_FACEBOOK_CLIENT_TOKEN="$(example_xcconfig_value FACEBOOK_CLIENT_TOKEN)"
  EX_KAKAO_NATIVE_APP_KEY="$(example_xcconfig_value KAKAO_NATIVE_APP_KEY)"
  EX_NAVER_URL_SCHEME="$(example_xcconfig_value NAVER_URL_SCHEME)"
  EX_NAVER_CLIENT_ID="$(example_xcconfig_value NAVER_CLIENT_ID)"
  EX_NAVER_CLIENT_SECRET="$(example_xcconfig_value NAVER_CLIENT_SECRET)"
  EX_LINE_CHANNEL_ID="$(example_xcconfig_value LINE_CHANNEL_ID)"

  for pair in \
    "REVERSED_CLIENT_ID=${EX_REVERSED_CLIENT_ID}" \
    "FACEBOOK_APP_ID=${EX_FACEBOOK_APP_ID}" \
    "FACEBOOK_CLIENT_TOKEN=${EX_FACEBOOK_CLIENT_TOKEN}" \
    "KAKAO_NATIVE_APP_KEY=${EX_KAKAO_NATIVE_APP_KEY}" \
    "NAVER_URL_SCHEME=${EX_NAVER_URL_SCHEME}" \
    "NAVER_CLIENT_ID=${EX_NAVER_CLIENT_ID}" \
    "NAVER_CLIENT_SECRET=${EX_NAVER_CLIENT_SECRET}" \
    "LINE_CHANNEL_ID=${EX_LINE_CHANNEL_ID}"; do
    [ -n "${pair#*=}" ] || fail "${XCCONFIG_EXAMPLE} 에서 ${pair%%=*} placeholder 를 못 읽었다"
  done

  # 케이스별 override 값 — 비운 provider 는 빈 문자열.
  OV_REVERSED_CLIENT_ID=""
  OV_FACEBOOK_APP_ID=""
  OV_FACEBOOK_CLIENT_TOKEN=""
  OV_KAKAO_NATIVE_APP_KEY=""
  OV_NAVER_URL_SCHEME=""
  OV_NAVER_CLIENT_ID=""
  OV_NAVER_CLIENT_SECRET=""
  OV_LINE_CHANNEL_ID=""
  case "$CASE" in
    all)
      OV_REVERSED_CLIENT_ID="$EX_REVERSED_CLIENT_ID"
      OV_FACEBOOK_APP_ID="$EX_FACEBOOK_APP_ID"
      OV_FACEBOOK_CLIENT_TOKEN="$EX_FACEBOOK_CLIENT_TOKEN"
      OV_KAKAO_NATIVE_APP_KEY="$EX_KAKAO_NATIVE_APP_KEY"
      OV_NAVER_URL_SCHEME="$EX_NAVER_URL_SCHEME"
      OV_NAVER_CLIENT_ID="$EX_NAVER_CLIENT_ID"
      OV_NAVER_CLIENT_SECRET="$EX_NAVER_CLIENT_SECRET"
      OV_LINE_CHANNEL_ID="$EX_LINE_CHANNEL_ID"
      ;;
    google)
      OV_REVERSED_CLIENT_ID="$EX_REVERSED_CLIENT_ID"
      ;;
    off) ;;
  esac

  # 8변수 전부 override — 실 xcconfig 값이 산출물에 섞이지 않게 한다(빈 값 override 도 유효).
  export FLUTTER_XCODE_REVERSED_CLIENT_ID="$OV_REVERSED_CLIENT_ID"
  export FLUTTER_XCODE_FACEBOOK_APP_ID="$OV_FACEBOOK_APP_ID"
  export FLUTTER_XCODE_FACEBOOK_CLIENT_TOKEN="$OV_FACEBOOK_CLIENT_TOKEN"
  export FLUTTER_XCODE_KAKAO_NATIVE_APP_KEY="$OV_KAKAO_NATIVE_APP_KEY"
  export FLUTTER_XCODE_NAVER_URL_SCHEME="$OV_NAVER_URL_SCHEME"
  export FLUTTER_XCODE_NAVER_CLIENT_ID="$OV_NAVER_CLIENT_ID"
  export FLUTTER_XCODE_NAVER_CLIENT_SECRET="$OV_NAVER_CLIENT_SECRET"
  export FLUTTER_XCODE_LINE_CHANNEL_ID="$OV_LINE_CHANNEL_ID"

  echo "building ios ${FLAVOR} ${CASE}${SIM_SENTINEL} with ${CASE_JSON} + FLUTTER_XCODE_* override 8개 (log: ${LOG})"
  if [ "$SIMULATOR" -eq 1 ]; then
    # --codesign 은 device 빌드 전용 옵션이라(flutter build ios --help) 시뮬레이터 빌드에는 붙이지 않는다.
    if ! fvm flutter build ios --debug --simulator --flavor "$FLAVOR" \
      --dart-define-from-file="$CASE_JSON" >"$LOG" 2>&1; then
      fail "ios ${FLAVOR} ${CASE} simulator 빌드 실패"
    fi
    PLIST="build/ios/iphonesimulator/Runner.app/Info.plist"
  else
    if ! fvm flutter build ios --debug --no-codesign --flavor "$FLAVOR" \
      --dart-define-from-file="$CASE_JSON" >"$LOG" 2>&1; then
      fail "ios ${FLAVOR} ${CASE} 빌드 실패"
    fi
    PLIST="build/ios/iphoneos/Runner.app/Info.plist"
  fi

  [ -f "$PLIST" ] || fail "산출물 Info.plist 미발견: ${PLIST}"

  PLIST_JSON="$(plutil -convert json -o - "$PLIST")"
  printf '%s' "$PLIST_JSON" >"${LOG_DIR}/ios-${FLAVOR}-${CASE}${SIM_SUFFIX}-plist.json"

  ACTUAL_CLIENT_ID="$(printf '%s' "$PLIST_JSON" | jq -r '.NidClientID // ""')"
  [ "$ACTUAL_CLIENT_ID" = "$OV_NAVER_CLIENT_ID" ] ||
    fail "NidClientID 가 케이스 값이 아니다 — 기대 '${OV_NAVER_CLIENT_ID}', 실제 '${ACTUAL_CLIENT_ID}' (환경변수 override 미적용 의심)"

  ACTUAL_CLIENT_SECRET="$(printf '%s' "$PLIST_JSON" | jq -r '.NidClientSecret // ""')"
  [ "$ACTUAL_CLIENT_SECRET" = "$OV_NAVER_CLIENT_SECRET" ] ||
    fail "NidClientSecret 이 케이스 값이 아니다 (환경변수 override 미적용 의심)"

  ACTUAL_FB_APP_ID="$(printf '%s' "$PLIST_JSON" | jq -r '.FacebookAppID // ""')"
  [ "$ACTUAL_FB_APP_ID" = "$OV_FACEBOOK_APP_ID" ] ||
    fail "FacebookAppID 가 케이스 값이 아니다 — 기대 '${OV_FACEBOOK_APP_ID}', 실제 '${ACTUAL_FB_APP_ID}' (환경변수 override 미적용 의심)"

  ACTUAL_APP_NAME="$(printf '%s' "$PLIST_JSON" | jq -r '.NidAppName // ""')"
  [ -n "$ACTUAL_APP_NAME" ] || fail "NidAppName 이 비어 있다 (DISPLAY_NAME 치환 실패)"

  BUNDLE_ID="$(printf '%s' "$PLIST_JSON" | jq -r '.CFBundleIdentifier // ""')"
  [ -n "$BUNDLE_ID" ] || fail "CFBundleIdentifier 가 비어 있다"

  # 산출물 scheme 단언 (D-04): 일반 scheme("" · fb · kakao) 0.
  printf '%s' "$PLIST_JSON" |
    jq -e '[.CFBundleURLTypes[]?.CFBundleURLSchemes[]?] | all(. != "" and . != "fb" and . != "kakao")' >/dev/null ||
    fail "일반 scheme 잔존: $(printf '%s' "$PLIST_JSON" | jq -c '[.CFBundleURLTypes[]?.CFBundleURLSchemes[]?]')"

  # 케이스별 기대 scheme — 비운 provider 는 Info.plist :default= 자리표시(bundle id 포함).
  if [ -n "$OV_REVERSED_CLIENT_ID" ]; then
    EXPECTED_GOOGLE="$OV_REVERSED_CLIENT_ID"
  else
    EXPECTED_GOOGLE="unset.google.${BUNDLE_ID}"
  fi
  if [ -n "$OV_FACEBOOK_APP_ID" ]; then
    EXPECTED_FB="fb${OV_FACEBOOK_APP_ID}"
  else
    EXPECTED_FB="fbunset.${BUNDLE_ID}"
  fi
  if [ -n "$OV_KAKAO_NATIVE_APP_KEY" ]; then
    EXPECTED_KAKAO="kakao${OV_KAKAO_NATIVE_APP_KEY}"
  else
    EXPECTED_KAKAO="kakaounset.${BUNDLE_ID}"
  fi
  if [ -n "$OV_NAVER_URL_SCHEME" ]; then
    EXPECTED_NAVER="$OV_NAVER_URL_SCHEME"
  else
    EXPECTED_NAVER="unset.naver.${BUNDLE_ID}"
  fi

  for expected in "$EXPECTED_GOOGLE" "$EXPECTED_FB" "$EXPECTED_KAKAO" "$EXPECTED_NAVER"; do
    N="$(printf '%s' "$PLIST_JSON" |
      jq -r --arg s "$expected" '[.CFBundleURLTypes[]?.CFBundleURLSchemes[]? | select(. == $s)] | length')"
    [ "$N" = "1" ] || fail "scheme '${expected}' 이 정확히 1건이 아니다 — ${N}건"
  done

  # NidUrlScheme 은 naver 항목과 같은 값이어야 한다.
  ACTUAL_NID_URL_SCHEME="$(printf '%s' "$PLIST_JSON" | jq -r '.NidUrlScheme // ""')"
  [ "$ACTUAL_NID_URL_SCHEME" = "$EXPECTED_NAVER" ] ||
    fail "NidUrlScheme 불일치 — 기대 '${EXPECTED_NAVER}', 실제 '${ACTUAL_NID_URL_SCHEME}'"

  SCHEME_PRESENT="$(printf '%s' "$PLIST_JSON" |
    jq -r --arg s "$ACTUAL_NID_URL_SCHEME" '[.CFBundleURLTypes[]? | select(.CFBundleURLName == "naver") | .CFBundleURLSchemes[]?] | index($s) != null')"
  [ "$SCHEME_PRESENT" = "true" ] ||
    fail "CFBundleURLName=naver 의 scheme 목록에 '${ACTUAL_NID_URL_SCHEME}' 이 없다"

  echo "plist: ${PLIST} (bundle ${BUNDLE_ID})"
  echo "NidClientID='${ACTUAL_CLIENT_ID}' FacebookAppID='${ACTUAL_FB_APP_ID}' NidAppName=${ACTUAL_APP_NAME} (케이스 값 일치)"
  echo "schemes: google=${EXPECTED_GOOGLE} fb=${EXPECTED_FB} kakao=${EXPECTED_KAKAO} naver=${EXPECTED_NAVER} · 일반 scheme 0"
fi

echo "PLACEHOLDER-BUILD-OK ${PLATFORM} ${FLAVOR} ${CASE}${SIM_SENTINEL}"
