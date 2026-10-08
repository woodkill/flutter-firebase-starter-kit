#!/usr/bin/env bash
# Phase 17.5 D-02 · D-04 · D-09 — 인증 결과 페이지(Hosting)를 배포하는 스크립트.
#
# 목적:
#   config/<flavor>.json 을 읽어 결과 페이지를 빌드(hosting/build.mjs)한 뒤 표준
#   `firebase deploy --project <id> --only hosting` 명령을 출력 · 실행한다.
#   결과 페이지는 발송 모드(emailDelivery)와 독립이다 — firebase · kit 둘 다 배포할 수 있다.
#
# 사용법:
#   bash scripts/deploy_email.sh <dev|stg|prod> hosting            # dry-run (기본 — 아무것도 배포하지 않는다)
#   bash scripts/deploy_email.sh <dev|stg|prod> hosting --apply    # 출력한 명령을 실행한다
#
# 출력 계약:
#   - 공통 출력: `flavor:` · `project:` · `mode: <firebase|kit>` · `target: <대상>`
#   - hosting: 빌드 결과 줄(`BUILD OK …`) · `command: firebase deploy --project <id> --only hosting` ·
#     Console 작업 URL 안내 1줄
#   - dry-run 마지막 줄: DRY-RUN OK <flavor> target=<대상> mode=<firebase|kit> (exit 0)
#   - 실행 마지막 줄:    DEPLOY OK <flavor> target=<대상> mode=<firebase|kit> (exit 0)
#     실행 모드는 `running: firebase deploy …` 를 출력한 뒤 같은 명령을 실행한다.
#   - 실패: FAIL: <사유> (stderr, exit 1) · 인자 오류: usage (stderr, exit 2)
#
# 안전 계약:
#   - config/<flavor>.json 에서 .firebaseProjectId · .emailDelivery · .appName · .brandColor
#     네 값만 읽는다. 다른 키(키 · secret 값)는 읽지도 출력하지도 않는다.
#     (hosting/build.mjs 도 firebaseProjectId · appName · brandColor 만 쓴다.)
#   - emailDelivery 는 빈 값 · firebase · kit 정확 일치만 받는다(공백 · 대소문자 보정 없음 —
#     앱과 같은 규칙). 그 밖이면 FAIL 이고, 원문 값은 출력하지 않는다(`mode:` 는 정규화 값).
#   - 강제 삭제 옵션과 비대화형 옵션을 명령에 넣지 않는다.
#   - 인자 없는 `firebase deploy` 를 쓰지 않는다 — firebase.json 의 모든 대상(확장 포함)이
#     배포된다. 대상은 항상 `--only` 로 고정한다.
#   - 명령은 bash 배열 인자로 실행한다(word splitting 없음).
#
# dry-run 은 firebase CLI 없이 돈다. --apply 에서만 PATH 의 `firebase` 를 확인한다.
# 결과 페이지 빌드는 dry-run 에서도 한다(빌드 실패를 배포 전에 알린다). --apply 때는
# firebase.json 의 hosting predeploy 가 대상 프로젝트 config 로 한 번 더 빌드한다.
#
# starter-kit 정책: 외부 CI 미도입 — 사람이 직접 돌리는 스크립트다.

set -euo pipefail

usage() {
  cat >&2 <<'USAGE'
usage: bash scripts/deploy_email.sh <dev|stg|prod> hosting [--apply]

  hosting — 인증 결과 페이지를 빌드해 Firebase Hosting 에 배포한다(발송 모드와 무관).
  옵션 없이 실행하면 명령만 출력한다(dry-run). --apply 를 줄 때만 실제로 배포한다.
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
  hosting) ;;
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

# hosting 대상 — 결과 페이지 빌드 → 배포 명령 출력 → (--apply) 실행.
deploy_hosting() {
  if ! command -v node >/dev/null 2>&1; then
    fail "node 가 필요하다 (결과 페이지 빌드)"
  fi
  node "$ROOT/hosting/build.mjs" --flavor "$FLAVOR" --root "$ROOT" ||
    fail "결과 페이지 빌드 실패 — 위 FAIL 사유를 고친 뒤 다시 실행한다"

  echo "command: firebase deploy --project ${PROJECT} --only hosting"
  echo "배포 뒤 Console → Authentication → 템플릿 → 작업 URL 맞춤설정 에 https://${PROJECT}.web.app/ 를 넣는다"

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

case "$TARGET" in
  hosting) deploy_hosting ;;
esac
