#!/usr/bin/env bash
# Phase 17.5 D-02 · D-04 · D-05 · D-06 · D-09 · D-14 · D-22 · D-24 — 인증 메일 표면을 배포하는 스크립트.
#
# 목적:
#   두 대상 모두 emailDelivery 가 kit 일 때만 동작한다(원칙 P · 「off 면 설정 0」 · D-22 ④).
#   빈 값 · firebase 모드는 Firebase 메일 + Firebase 기본 페이지라 배포할 것이 없다 — FAIL 로
#   멈추고 빌드 · 명령 출력 · firebase 호출을 하지 않는다.
#   hosting — 결과 페이지만 다시 빌드(hosting/build.mjs)해 표준
#             `firebase deploy --project <id> --only hosting` 명령을 출력 · 실행한다
#             (문구 · 모양 · 로고 표시를 바꿨을 때). 결과 페이지는 kit 메일 링크가 연다.
#   kit     — 켜기 배포(결과 페이지 · 메일 함수 env · 확장).
#             ① 결과 페이지를 빌드해 `firebase deploy --project <id> --only hosting` 으로 먼저
#             배포한다 — kit 메일 링크가 이 페이지를 연다(D-22 ③).
#             ② ①이 성공한 뒤에만 메일 함수가 쓰는 env 4줄(EMAIL_APP_NAME · EMAIL_BRAND_COLOR ·
#             EMAIL_LOGO_URL · EMAIL_RESULT_PAGE_URL)을 config 에서 만들어
#             functions/.env.<projectId> 에 쓴다 — 함수는 config 를 읽지 못하고 env 는 배포 때만
#             실린다. 결과 페이지 주소는 프로젝트 ID 로 만든다(https://<id>.web.app/ · 새 config 키 0).
#             ③ Trigger Email 확장을 `firebase deploy --project <id> --only extensions` 로 배포한다.
#             kit 메일 함수 배포는 scripts/deploy_functions.sh 가 맡는다(함수 목록 진실원 1곳).
#
# 사용법:
#   bash scripts/deploy_email.sh <dev|stg|prod> <hosting|kit>            # dry-run (기본 — 아무것도 바꾸지 않는다)
#   bash scripts/deploy_email.sh <dev|stg|prod> <hosting|kit> --apply    # 출력한 계획을 실행한다
#   kit 순서: deploy_email.sh <flavor> kit --apply → TTL 명령(next:) → deploy_functions.sh <flavor> --apply
#             → 확장 함수 invoker 명령(next:)
#
# 출력 계약:
#   - 공통 출력: `flavor:` · `project:` · `mode: <firebase|kit>` · `target: <대상>`
#   - hosting: 빌드 결과 줄(`BUILD OK …`) · `command: firebase deploy --project <id> --only hosting`
#   - kit: 빌드 결과 줄(`BUILD OK …`) · `env: EMAIL_APP_NAME="…"` · `env: EMAIL_BRAND_COLOR="…"` ·
#     `env: EMAIL_LOGO_URL="…"` · `env: EMAIL_RESULT_PAGE_URL="https://<id>.web.app/"` 4줄 ·
#     `command:` 2줄(`… --only hosting` → `… --only extensions` 순) ·
#     `next:` 3줄(TTL → 함수 배포 → 확장 함수 invoker — 매뉴얼 「켜기」 ⑤ · ⑥ · ⑦ 순) ·
#     --apply 때 `wrote: functions/.env.<id> …` 1줄(hosting 배포 성공 뒤)
#   - brandColor 형식 오류: stderr `warn: …` 1줄(결과 페이지 빌드가 낸다) 뒤 기본 색(#673AB7)으로 계속
#   - dry-run 마지막 줄: DRY-RUN OK <flavor> target=<대상> mode=kit (exit 0)
#   - 실행 마지막 줄:    DEPLOY OK <flavor> target=<대상> mode=kit (exit 0)
#     실행 모드는 `running: firebase deploy …` 를 출력한 뒤 같은 명령을 실행한다.
#   - 실패: FAIL: <사유> (stderr, exit 1) · 인자 오류: usage (stderr, exit 2)
#     firebase 모드(빈 값 · firebase)는 두 대상 모두 `mode: firebase` 뒤 FAIL(`emailDelivery` · `kit` 언급)
#
# 안전 계약:
#   - config/<flavor>.json 에서 .firebaseProjectId · .emailDelivery · .appName · .brandColor
#     네 값만 읽는다. 다른 키(키 · secret 값)는 읽지도 출력하지도 않는다.
#     (hosting/build.mjs 는 firebaseProjectId · appName · brandColor · firebaseWebApiKey 만 쓴다 —
#     웹 API 키는 결과 페이지가 Firebase 를 초기화하는 공개 값이고, 비었거나 자리표시 값이면
#     빌드가 FAIL 한다. 이 스크립트는 그 값을 읽지 않는다.)
#   - 확장 env(extensions/firestore-send-email.env.<projectId>)는 키 4개의 존재만 확인한다 —
#     값을 변수에 담거나 출력하지 않는다(SMTP 주소 · secret 리소스 이름 포함).
#   - appName 이 비었거나 `"` · `\` · `$` · 백틱 · 제어 문자(줄바꿈 등)를 담으면 FAIL —
#     env 파일 줄이 깨지거나 다른 키가 끼어드는 일을 막는다.
#   - functions/.env.<projectId> 는 메일 env 4줄만 바꾸고 다른 줄(예: SEND_TEST_PUSH_ENABLED)은
#     그대로 둔다. 파일은 --apply 때, 결과 페이지 배포가 성공한 뒤에만 쓴다 — 페이지 배포가
#     실패하면 env 와 확장은 그대로다(결과 페이지 주소가 없는 페이지를 가리키는 상태 0).
#   - emailDelivery 는 빈 값 · firebase · kit 정확 일치만 받는다(공백 · 대소문자 보정 없음 —
#     앱과 같은 규칙). 그 밖이면 FAIL 이고, 원문 값은 출력하지 않는다(`mode:` 는 정규화 값).
#   - 강제 삭제 옵션과 비대화형 옵션을 명령에 넣지 않는다.
#   - 인자 없는 `firebase deploy` 를 쓰지 않는다 — firebase.json 의 모든 대상(확장 포함)이
#     배포된다. 대상은 항상 `--only` 로 고정한다.
#   - 명령은 bash 배열 인자로 실행한다(word splitting 없음).
#   - 스크립트는 IAM 을 쓰지 않는다 — 확장 함수(ext-firestore-send-email-processqueue ·
#     us-central1)를 부르는 기본 Compute 서비스 계정의 invoker 부여 명령은 `next:` 로 출력만
#     하고, 프로젝트 번호는 사용자가 그 줄을 실행할 때 `gcloud projects describe` 가 채운다
#     (dry-run 은 네트워크 0 · 서비스 1개 단위 부여 · D-24).
#
# dry-run 은 firebase CLI 없이 돈다. --apply 에서만 PATH 의 `firebase` 를 확인한다.
# 결과 페이지 빌드는 dry-run 에서도 한다(빌드 실패를 배포 전에 알린다). --apply 때는
# firebase.json 의 hosting predeploy 가 대상 프로젝트 config 로 한 번 더 빌드한다.
#
# starter-kit 정책: 외부 CI 미도입 — 사람이 직접 돌리는 스크립트다.

set -euo pipefail

usage() {
  cat >&2 <<'USAGE'
usage: bash scripts/deploy_email.sh <dev|stg|prod> <hosting|kit> [--apply]

  hosting — emailDelivery 가 kit 일 때만: 결과 페이지만 다시 빌드해 Firebase Hosting 에 배포한다(문구 · 모양 · 로고 표시를 바꿨을 때).
  kit     — emailDelivery 가 kit 일 때만: 결과 페이지 · 메일 함수 env · Trigger Email 확장을 배포한다.
  옵션 없이 실행하면 계획만 출력한다(dry-run). --apply 를 줄 때만 실제로 바꾼다.
USAGE
}

# 실패 사유 한 줄을 stderr 로 내고 종료한다.
fail() {
  echo "FAIL: $1" >&2
  exit 1
}

if [ "$#" -lt 2 ] || [ "$#" -gt 3 ]; then
  usage
  exit 2
fi

FLAVOR="$1"
TARGET="$2"
OPTION="${3:-}"

case "$FLAVOR" in
  dev | stg | prod) ;;
  *)
    usage
    exit 2
    ;;
esac

case "$TARGET" in
  hosting | kit) ;;
  *)
    usage
    exit 2
    ;;
esac

case "$OPTION" in
  "" | --apply) ;;
  *)
    usage
    exit 2
    ;;
esac

# 저장소 루트는 스크립트 위치 기준으로 찾는다 — 어느 디렉터리에서 실행해도 같은 파일을 읽는다.
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CONFIG="$ROOT/config/$FLAVOR.json"

if ! command -v jq >/dev/null 2>&1; then
  fail "jq 가 필요하다 (brew install jq)"
fi

[ -f "$CONFIG" ] ||
  fail "config/${FLAVOR}.json 이 없다 — cp config/${FLAVOR}.example.json config/${FLAVOR}.json 뒤 값을 채운다"

# 문자열 값을 `ok:<값>` 으로, 키가 없거나 null 이면 `ok:` 로 꺼낸다. 문자열이 아니거나
# 제어 문자(줄바꿈 등)가 든 값은 `bad` — 명령 치환이 끝 줄바꿈을 지워 값이 바뀌는 일을 막는다.
JQ_STRING='if . == null then "ok:" elif type == "string" and (test("[[:cntrl:]]") | not) then "ok:" + . else "bad" end'

# config 에서 읽는 값은 안전 계약의 네 개뿐이다(appName · brandColor 는 kit 대상에서 읽는다).
PROJECT="$(jq -r '.firebaseProjectId // ""' "$CONFIG")" ||
  fail "config/${FLAVOR}.json 을 JSON 으로 읽지 못했다"
MODE_RAW="$(jq -r ".emailDelivery | ${JQ_STRING}" "$CONFIG")" ||
  fail "config/${FLAVOR}.json 을 JSON 으로 읽지 못했다"

[ -n "$PROJECT" ] || fail "config/${FLAVOR}.json 의 firebaseProjectId 가 비어 있다"
# Firebase 프로젝트 ID 형식(소문자 · 숫자 · 하이픈, 소문자로 시작)만 받는다 —
# 값이 `-` 로 시작해 CLI 옵션으로 읽히는 일을 막는다.
# 문자 범위 표기 대신 허용 문자를 전부 나열한다 — macOS `/bin/bash` 3.2 는 UTF-8
# 로캘에서 대괄호 범위를 정렬 순서로 해석해 소문자 범위가 대문자까지 매치한다
# (scripts/deploy_functions.sh 와 같은 규칙).
case "$PROJECT" in
  [abcdefghijklmnopqrstuvwxyz]*) ;;
  *) fail "config/${FLAVOR}.json 의 firebaseProjectId 형식이 잘못됐다: ${PROJECT}" ;;
esac
case "$PROJECT" in
  *[!abcdefghijklmnopqrstuvwxyz0123456789-]*) fail "config/${FLAVOR}.json 의 firebaseProjectId 형식이 잘못됐다: ${PROJECT}" ;;
esac

# 발송 모드 — 빈 값(누락) · firebase → firebase, kit → kit, 그 밖은 FAIL(원문 미출력).
case "$MODE_RAW" in
  ok: | ok:firebase) EMAIL_MODE=firebase ;;
  ok:kit) EMAIL_MODE=kit ;;
  *) fail "config/${FLAVOR}.json 의 emailDelivery 값이 잘못됐다 — 빈 값 · firebase · kit 가운데 하나를 쓴다" ;;
esac

echo "flavor: ${FLAVOR}"
echo "project: ${PROJECT}"
echo "mode: ${EMAIL_MODE}"
echo "target: ${TARGET}"

# --apply 일 때 firebase CLI 를 확인하고 저장소 루트로 이동한다
# (firebase CLI 는 현재 디렉터리에서 firebase.json 을 찾는다).
prepare_apply() {
  if ! command -v firebase >/dev/null 2>&1; then
    fail "firebase CLI 가 PATH 에 없다 (npm install -g firebase-tools)"
  fi
  cd "$ROOT"
}

# 결과 페이지를 build/hosting/public 에 빌드한다(hosting · kit 공용 · dry-run 에서도 한다).
# 성공하면 hosting/build.mjs 가 `BUILD OK …` 1줄을 낸다.
build_result_page() {
  if ! command -v node >/dev/null 2>&1; then
    fail "node 가 필요하다 (결과 페이지 빌드)"
  fi
  node "$ROOT/hosting/build.mjs" --flavor "$FLAVOR" --root "$ROOT" ||
    fail "결과 페이지 빌드 실패 — 위 FAIL 사유를 고친 뒤 다시 실행한다"
}

# emailDelivery 가 kit 이 아니면 대상별 사유 $1 과 함께 FAIL 한다(원칙 P · D-22 ④).
# 두 대상 모두 빌드 · 명령 출력보다 먼저 부른다 — firebase 모드는 빌드 산출 · 호출 0.
require_kit_mode() {
  [ "$EMAIL_MODE" = kit ] ||
    fail "config/${FLAVOR}.json 의 emailDelivery 가 kit 이 아니다 — ${TARGET} 대상은 emailDelivery 가 kit 일 때만 배포한다($1)"
}

# hosting 대상 — 모드 가드 → 결과 페이지 빌드 → 배포 명령 출력 → (--apply) 실행.
deploy_hosting() {
  require_kit_mode "결과 페이지는 kit 모드 메일의 링크가 연다 — firebase 모드 메일 링크는 Firebase 기본 페이지로 열린다"
  build_result_page

  echo "command: firebase deploy --project ${PROJECT} --only hosting"

  if [ "$OPTION" != "--apply" ]; then
    echo ""
    echo "실제로 배포하려면: bash scripts/deploy_email.sh ${FLAVOR} hosting --apply"
    echo "DRY-RUN OK ${FLAVOR} target=hosting mode=${EMAIL_MODE}"
    return 0
  fi

  prepare_apply
  echo "running: firebase deploy --project ${PROJECT} --only hosting"
  firebase deploy --project "$PROJECT" --only hosting ||
    fail "결과 페이지 배포 실패"
  echo "DEPLOY OK ${FLAVOR} target=hosting mode=${EMAIL_MODE}"
}

# brandColor 기본값 — 앱 테마 Colors.deepPurple · functions/src/email/brand.ts 와 같다.
DEFAULT_BRAND_COLOR="#673AB7"

# 확장 env 의 키 4개가 값과 함께 있는지 확인한다(값은 읽어 담지 않는다).
check_extension_env() {
  local envx="$ROOT/extensions/firestore-send-email.env.$PROJECT"
  local rel="extensions/firestore-send-email.env.${PROJECT}"
  [ -f "$envx" ] ||
    fail "${rel} 이 없다 — cp extensions/firestore-send-email.env.example ${rel} 뒤 값을 채운다"

  local missing="" key
  for key in DATABASE_REGION DEFAULT_FROM SMTP_CONNECTION_URI; do
    grep -q "^${key}=." "$envx" || missing="${missing} ${key}"
  done
  # SMTP_PASSWORD 는 값이 아니라 Secret Manager 리소스 이름이다.
  grep -q '^SMTP_PASSWORD=projects/' "$envx" || missing="${missing} SMTP_PASSWORD"
  [ -z "$missing" ] ||
    fail "${rel} 에 값이 없는 키:${missing} (SMTP_PASSWORD 는 projects/… 로 시작하는 Secret Manager 리소스 이름)"

  # 예시 파일의 자리표시(<your-…>)가 남은 키 — 배포 중 CLI 오류 대신 여기서 알린다.
  local placeholder=""
  for key in DATABASE_REGION DEFAULT_FROM SMTP_CONNECTION_URI SMTP_PASSWORD; do
    if grep -q "^${key}=.*<your-" "$envx"; then
      placeholder="${placeholder} ${key}"
    fi
  done
  [ -z "$placeholder" ] ||
    fail "${rel} 에 예시 자리표시(<your-…>)가 남은 키:${placeholder}"
  return 0
}

# config 의 appName · brandColor 를 함수 env 값으로 만든다(APP_NAME · BRAND_COLOR · LOGO_URL).
resolve_brand_env() {
  local raw
  raw="$(jq -r ".appName | ${JQ_STRING}" "$CONFIG")" ||
    fail "config/${FLAVOR}.json 을 JSON 으로 읽지 못했다"
  case "$raw" in
    ok:*) APP_NAME="${raw#ok:}" ;;
    *) fail "config/${FLAVOR}.json 의 appName 이 문자열이 아니거나 제어 문자(줄바꿈 등)를 담고 있다" ;;
  esac
  # 앞뒤 공백 제거 (bash 3.2 호환 — 매개변수 확장만 쓴다 · build.mjs 의 trim 과 같다).
  APP_NAME="${APP_NAME#"${APP_NAME%%[![:space:]]*}"}"
  APP_NAME="${APP_NAME%"${APP_NAME##*[![:space:]]}"}"
  [ -n "$APP_NAME" ] || fail "config/${FLAVOR}.json 의 appName 이 비어 있다"
  case "$APP_NAME" in
    *'"'* | *'\'* | *'$'* | *'`'*)
      fail "config/${FLAVOR}.json 의 appName 에 쓸 수 없는 문자(\" · \\ · \$ · 백틱)가 있다 — env 파일 줄이 깨진다"
      ;;
  esac

  raw="$(jq -r ".brandColor | ${JQ_STRING}" "$CONFIG")" ||
    fail "config/${FLAVOR}.json 을 JSON 으로 읽지 못했다"
  # `#` + 16진 6자만 쓴다(대소문자 보존). 문자 범위 대신 허용 문자를 나열한다(bash 3.2 로캘).
  local hex='[0123456789abcdefABCDEF]'
  # shellcheck disable=SC2254 # 나열 문자 클래스를 패턴으로 쓰는 것이 목적이다.
  case "$raw" in
    ok:)
      # 키가 없거나 빈 값이면 기본 색이 정상 동작이다(경고 없음 — build.mjs 와 같다).
      BRAND_COLOR="$DEFAULT_BRAND_COLOR"
      ;;
    ok:#${hex}${hex}${hex}${hex}${hex}${hex})
      BRAND_COLOR="${raw#ok:}"
      ;;
    *)
      # 형식 오류 경고(`warn:` 1줄)는 결과 페이지 빌드(hosting/build.mjs · 같은 #RRGGBB 규칙)가
      # 낸다 — kit 은 항상 같은 config 로 빌드하므로 여기서 다시 내지 않는다(같은 경고 2줄 방지).
      BRAND_COLOR="$DEFAULT_BRAND_COLOR"
      ;;
  esac

  # 로고 = Hosting 공개 디렉터리의 파일 1개(D-05). 없으면 빈 값 → 메일은 앱 이름 텍스트 헤더.
  if [ -f "$ROOT/hosting/public/logo.png" ]; then
    LOGO_URL="https://${PROJECT}.web.app/logo.png"
  else
    LOGO_URL=""
  fi

  # 결과 페이지 주소 — 로고 주소와 같은 원천(프로젝트 ID)에서 만든다(D-22 ② · 새 config 키 0).
  # 메일 함수의 readResultPageUrl()(functions/src/email/brand.ts)이 이 값을 읽어 링크를 바꾼다.
  RESULT_PAGE_URL="https://${PROJECT}.web.app/"
}

# functions/.env.<projectId> 에서 메일 env 4줄만 바꿔 쓴다(다른 줄 · 파일 권한 유지).
write_function_env() {
  local fn_env="$ROOT/functions/.env.$PROJECT"
  local tmp
  tmp="$(mktemp "${TMPDIR:-/tmp}/deploy_email.XXXXXX")" || fail "임시 파일을 만들지 못했다"
  # shellcheck disable=SC2064 # 지금 경로로 고정한다.
  trap "rm -f '$tmp'" EXIT
  if [ -f "$fn_env" ]; then
    # 네 키(앞 공백 · export 접두 포함)가 아닌 줄만 옮긴다. grep 은 고른 줄이 없으면 1 이다.
    grep -v -E '^[[:space:]]*(export[[:space:]]+)?(EMAIL_APP_NAME|EMAIL_BRAND_COLOR|EMAIL_LOGO_URL|EMAIL_RESULT_PAGE_URL)[[:space:]]*=' \
      "$fn_env" >"$tmp" || [ "$?" -eq 1 ] ||
      fail "functions/.env.${PROJECT} 을 읽지 못했다"
  fi
  {
    echo "EMAIL_APP_NAME=\"${APP_NAME}\""
    echo "EMAIL_BRAND_COLOR=\"${BRAND_COLOR}\""
    echo "EMAIL_LOGO_URL=\"${LOGO_URL}\""
    echo "EMAIL_RESULT_PAGE_URL=\"${RESULT_PAGE_URL}\""
  } >>"$tmp"
  # 제자리에 덮어써 기존 파일 권한을 그대로 둔다(없으면 새로 만든다).
  cat "$tmp" >"$fn_env" || fail "functions/.env.${PROJECT} 을 쓰지 못했다"
  rm -f "$tmp"
  trap - EXIT
  echo "wrote: functions/.env.${PROJECT} (메일 env 4줄)"
}

# kit 다음 단계 3줄 — mail TTL · 메일 함수 배포 · 확장 함수 invoker(매뉴얼 「켜기」 ⑤ · ⑥ · ⑦ 순).
# 셋째 줄은 출력만 한다(D-24) — `\$(` 는 사용자가 실행할 때 프로젝트 번호로 바뀐다.
# PROJECT 는 위 형식 검사로 소문자 · 숫자 · 하이픈만 담아 붙여 넣어도 셸 해석이 바뀌지 않는다.
print_kit_next() {
  echo "next: gcloud firestore fields ttls update delivery.expireAt --collection-group=mail --enable-ttl --project ${PROJECT}"
  echo "next: bash scripts/deploy_functions.sh ${FLAVOR} --apply"
  echo "next: gcloud run services add-iam-policy-binding ext-firestore-send-email-processqueue --region=us-central1 --member=serviceAccount:\$(gcloud projects describe ${PROJECT} --format='value(projectNumber)')-compute@developer.gserviceaccount.com --role=roles/run.invoker --project ${PROJECT}"
}

# kit 대상 — 모드 가드 → 확장 env 확인 → 브랜드 · 결과 페이지 주소 → 결과 페이지 빌드 → 계획 출력
# → (--apply) 결과 페이지 배포 → 성공 뒤에만 메일 env 4줄 쓰기 → 확장 배포(D-22 ③).
deploy_kit() {
  require_kit_mode "firebase 모드는 확장 · 메일 함수가 필요 없다"

  check_extension_env
  resolve_brand_env
  build_result_page

  echo "함수 env 파일: functions/.env.${PROJECT} (아래 4줄을 바꿔 쓴다 · 다른 줄은 그대로)"
  echo "env: EMAIL_APP_NAME=\"${APP_NAME}\""
  echo "env: EMAIL_BRAND_COLOR=\"${BRAND_COLOR}\""
  echo "env: EMAIL_LOGO_URL=\"${LOGO_URL}\""
  echo "env: EMAIL_RESULT_PAGE_URL=\"${RESULT_PAGE_URL}\""
  echo "command: firebase deploy --project ${PROJECT} --only hosting"
  echo "command: firebase deploy --project ${PROJECT} --only extensions"

  if [ "$OPTION" != "--apply" ]; then
    print_kit_next
    echo ""
    echo "실제로 배포하려면: bash scripts/deploy_email.sh ${FLAVOR} kit --apply"
    echo "DRY-RUN OK ${FLAVOR} target=kit mode=${EMAIL_MODE}"
    return 0
  fi

  prepare_apply
  # 결과 페이지를 먼저 올린다 — 실패하면 함수 env 와 확장을 건드리지 않고 멈춘다
  # (env 의 결과 페이지 주소가 배포되지 않은 페이지를 가리키는 상태를 만들지 않는다).
  echo "running: firebase deploy --project ${PROJECT} --only hosting"
  firebase deploy --project "$PROJECT" --only hosting ||
    fail "결과 페이지 배포 실패 — 함수 env 와 확장은 바꾸지 않았다"
  write_function_env
  # 확장의 secret(SMTP_PASSWORD)이 없으면 CLI 가 이 터미널에서 값을 묻는다(대화형 그대로).
  echo "running: firebase deploy --project ${PROJECT} --only extensions"
  firebase deploy --project "$PROJECT" --only extensions ||
    fail "확장 배포 실패 — 결과 페이지와 함수 env 는 이미 바꿨다"
  print_kit_next
  echo "DEPLOY OK ${FLAVOR} target=kit mode=${EMAIL_MODE}"
}

case "$TARGET" in
  hosting) deploy_hosting ;;
  kit) deploy_kit ;;
esac
