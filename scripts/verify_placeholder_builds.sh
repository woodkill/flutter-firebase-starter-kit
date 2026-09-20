#!/usr/bin/env bash
# Phase 16.2 D-05 — 키 미설정 계약(fresh clone 상태)의 빌드 게이트.
#
# 목적:
#   fork/clone 직후처럼 실제 키가 하나도 없는 상태(tracked placeholder 만 있는 상태)에서도
#   dev / stg / prod 3 flavor 의 Android · iOS 빌드가 성공한다는 계약(D-05)을 재현 가능한
#   한 명령으로 검증한다. Naver Login 은 runtime initialize 가 없고 빌드 타임 native 설정
#   (Android manifest meta-data / iOS Info.plist Nid*)을 읽으므로, 키가 비어 있을 때
#   빌드가 깨지면 킷을 clone 한 사람이 첫 빌드부터 막힌다.
#
# 사용법:
#   bash scripts/verify_placeholder_builds.sh <android|ios> <dev|stg|prod>
#   성공 시 마지막 줄: PLACEHOLDER-BUILD-OK <platform> <flavor> (exit 0)
#   실패 시: FAIL: <사유> + 빌드 로그 마지막 30줄 (exit 1), 인자 오류는 exit 2
#   빌드 로그: build/placeholder-gate/<platform>-<flavor>.log (stdout + stderr, build/ 는 gitignored)
#
# 안전 계약 (C-04):
#   - 실 키 파일(config/<flavor>.json · ios/Flutter/<flavor>.xcconfig 의 값)을 읽지도 바꾸지도 않는다.
#   - 입력은 tracked placeholder(config/<flavor>.example.json · ios/Flutter/<flavor>.example.xcconfig)뿐이다.
#   - iOS 의 Naver 값은 파일 교체가 아니라 FLUTTER_XCODE_* 환경변수 override 로만 넣는다
#     (Flutter tool 이 이 접두어 환경변수를 xcodebuild 빌드 설정으로 넘기고, 명령행 빌드 설정은
#      xcconfig 보다 우선한다 — 3.47.5 packages/flutter_tools/lib/src/ios/xcodeproj.dart:516).
#   - ios/Flutter/<flavor>.xcconfig 는 "없을 때만" example 에서 복사한다. 이미 있으면 절대 건드리지 않는다.
#   - 빌드 성공만으로 통과시키지 않는다 — 산출물의 Naver 값이 placeholder 와 같은지를 함께 단언한다.
#
# 여기서 비교·출력되는 값은 전부 tracked placeholder 라 로그에 노출돼도 무방하다.
#
# starter-kit 정책: 외부 CI 미도입 — 사람이 직접 호출하는 게이트 스크립트다.

set -euo pipefail

usage() {
  cat >&2 <<'USAGE'
usage: bash scripts/verify_placeholder_builds.sh <android|ios> <dev|stg|prod>

  placeholder(키 미설정) 입력만으로 해당 플랫폼 · flavor 빌드가 성공하는지 검증한다.
  빌드 하나에 수 분이 걸리므로 조합마다 따로 호출한다.
USAGE
}

PLATFORM="${1:-}"
FLAVOR="${2:-}"

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

# flavor 첫 글자 대문자형 (Android 병합 manifest 경로용).
# bash 3.2(macOS 기본)에는 ${var^} 가 없으므로 case 로 만든다.
case "$FLAVOR" in
  dev) FLAVOR_CAP="Dev" ;;
  stg) FLAVOR_CAP="Stg" ;;
  prod) FLAVOR_CAP="Prod" ;;
esac

LOG_DIR="build/placeholder-gate"
LOG="${LOG_DIR}/${PLATFORM}-${FLAVOR}.log"
EXAMPLE_JSON="config/${FLAVOR}.example.json"

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

# gradleResValues.xml 에서 <string name="..."> 값 추출.
res_value() {
  local file="$1"
  local name="$2"
  sed -nE 's#^[[:space:]]*<string name="'"$name"'"[^>]*>(.*)</string>.*$#\1#p' "$file"
}

if [ ! -f "$EXAMPLE_JSON" ]; then
  echo "FAIL: placeholder 입력 파일 없음: ${EXAMPLE_JSON}" >&2
  exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "FAIL: jq 가 필요하다 (brew install jq)" >&2
  exit 1
fi

if [ "$PLATFORM" = "android" ]; then
  # ── Android ────────────────────────────────────────────────────────────────
  # 키는 dart-define(=example json) → gradle resValue → manifest meta-data 경로로 들어간다.
  echo "building android ${FLAVOR} with ${EXAMPLE_JSON} (log: ${LOG})"
  if ! fvm flutter build apk --debug --flavor "$FLAVOR" \
    --dart-define-from-file="$EXAMPLE_JSON" >"$LOG" 2>&1; then
    fail "android ${FLAVOR} 빌드 실패"
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

  EXPECTED_ID="$(jq -r '.naverClientId' "$EXAMPLE_JSON")"
  ACTUAL_ID="$(res_value "$RES_VALUES" naver_client_id)"
  [ "$ACTUAL_ID" = "$EXPECTED_ID" ] ||
    fail "naver_client_id 가 placeholder 가 아니다 — 기대 '${EXPECTED_ID}', 실제 '${ACTUAL_ID}'"

  EXPECTED_NAME="$(jq -r '.appName' "$EXAMPLE_JSON")"
  ACTUAL_NAME="$(res_value "$RES_VALUES" naver_client_name)"
  [ "$ACTUAL_NAME" = "$EXPECTED_NAME" ] ||
    fail "naver_client_name 불일치 — 기대 '${EXPECTED_NAME}', 실제 '${ACTUAL_NAME}'"

  echo "apk: ${APK}"
  echo "naver_client_id=${ACTUAL_ID} naver_client_name=${ACTUAL_NAME} (placeholder 일치)"
else
  # ── iOS ────────────────────────────────────────────────────────────────────
  # flavor xcconfig 는 Debug-<flavor>.xcconfig 가 #include 로 필수 참조하므로 파일 자체는 있어야 한다.
  # 없을 때만 example 에서 만든다(매뉴얼 Initial Setup 의 cp 와 같은 동작, gitignored).
  # Naver 값은 파일이 아니라 환경변수 override 로 placeholder 를 강제한다.
  XCCONFIG="ios/Flutter/${FLAVOR}.xcconfig"
  XCCONFIG_EXAMPLE="ios/Flutter/${FLAVOR}.example.xcconfig"

  [ -f "$XCCONFIG_EXAMPLE" ] || fail "placeholder xcconfig 없음: ${XCCONFIG_EXAMPLE}"

  if [ ! -f "$XCCONFIG" ]; then
    cp "$XCCONFIG_EXAMPLE" "$XCCONFIG"
    echo "created ${XCCONFIG} from example (gitignored)"
  fi

  PH_CLIENT_ID="$(awk -F' = ' '/^NAVER_CLIENT_ID = /{print $2; exit}' "$XCCONFIG_EXAMPLE")"
  PH_CLIENT_SECRET="$(awk -F' = ' '/^NAVER_CLIENT_SECRET = /{print $2; exit}' "$XCCONFIG_EXAMPLE")"
  PH_URL_SCHEME="$(awk -F' = ' '/^NAVER_URL_SCHEME = /{print $2; exit}' "$XCCONFIG_EXAMPLE")"

  [ -n "$PH_CLIENT_ID" ] || fail "${XCCONFIG_EXAMPLE} 에서 NAVER_CLIENT_ID placeholder 를 못 읽었다"
  [ -n "$PH_CLIENT_SECRET" ] || fail "${XCCONFIG_EXAMPLE} 에서 NAVER_CLIENT_SECRET placeholder 를 못 읽었다"
  [ -n "$PH_URL_SCHEME" ] || fail "${XCCONFIG_EXAMPLE} 에서 NAVER_URL_SCHEME placeholder 를 못 읽었다"

  export FLUTTER_XCODE_NAVER_CLIENT_ID="$PH_CLIENT_ID"
  export FLUTTER_XCODE_NAVER_CLIENT_SECRET="$PH_CLIENT_SECRET"
  export FLUTTER_XCODE_NAVER_URL_SCHEME="$PH_URL_SCHEME"

  echo "building ios ${FLAVOR} with ${EXAMPLE_JSON} + FLUTTER_XCODE_NAVER_* override (log: ${LOG})"
  if ! fvm flutter build ios --debug --no-codesign --flavor "$FLAVOR" \
    --dart-define-from-file="$EXAMPLE_JSON" >"$LOG" 2>&1; then
    fail "ios ${FLAVOR} 빌드 실패"
  fi

  PLIST="build/ios/iphoneos/Runner.app/Info.plist"
  [ -f "$PLIST" ] || fail "산출물 Info.plist 미발견: ${PLIST}"

  PLIST_JSON="$(plutil -convert json -o - "$PLIST")"

  ACTUAL_CLIENT_ID="$(printf '%s' "$PLIST_JSON" | jq -r '.NidClientID // ""')"
  [ "$ACTUAL_CLIENT_ID" = "$PH_CLIENT_ID" ] ||
    fail "NidClientID 가 placeholder 가 아니다 — 기대 '${PH_CLIENT_ID}', 실제 '${ACTUAL_CLIENT_ID}' (환경변수 override 미적용 의심)"

  ACTUAL_CLIENT_SECRET="$(printf '%s' "$PLIST_JSON" | jq -r '.NidClientSecret // ""')"
  [ "$ACTUAL_CLIENT_SECRET" = "$PH_CLIENT_SECRET" ] ||
    fail "NidClientSecret 이 placeholder 가 아니다 (환경변수 override 미적용 의심)"

  ACTUAL_APP_NAME="$(printf '%s' "$PLIST_JSON" | jq -r '.NidAppName // ""')"
  [ -n "$ACTUAL_APP_NAME" ] || fail "NidAppName 이 비어 있다 (DISPLAY_NAME 치환 실패)"

  SCHEME_PRESENT="$(printf '%s' "$PLIST_JSON" |
    jq -r --arg s "$PH_URL_SCHEME" '[.CFBundleURLTypes[]? | select(.CFBundleURLName == "naver") | .CFBundleURLSchemes[]?] | index($s) != null')"
  [ "$SCHEME_PRESENT" = "true" ] ||
    fail "CFBundleURLName=naver 의 scheme 목록에 '${PH_URL_SCHEME}' 이 없다"

  echo "NidClientID=${ACTUAL_CLIENT_ID} NidAppName=${ACTUAL_APP_NAME} NidUrlScheme=${PH_URL_SCHEME} (placeholder 일치)"
fi

echo "PLACEHOLDER-BUILD-OK ${PLATFORM} ${FLAVOR}"
