#!/usr/bin/env bash
# Phase 17.3 D-08 · D-09 — 켠 provider 의 Cloud Functions 만 배포하는 스크립트.
#
# 목적:
#   config/<flavor>.json 의 enabledAuthProviders(CSV)를 읽어 공통 함수 + 켠 provider 의
#   함수만 표준 `firebase deploy --project <id> --only functions:…` 명령으로 배포한다.
#   끈 provider 의 함수는 배포 목록에 들어가지 않으므로 그 provider 의 함수 배포가
#   필요 없다.
#
# secret 전제 (끈 provider 포함):
#   Firebase CLI 는 `--only` 필터와 무관하게 코드베이스가 선언한 secret 8개
#   (`defineSecret` — functions/src/shared/) 전부가 Secret Manager 에 있는지 확인하고,
#   없으면 배포 중 값을 묻는다(비대화형이면 오류). 그래서 끈 provider 의 secret 도
#   **존재**해야 한다 — 값은 자리표시(예: unset)여도 된다. 그 provider 의 함수가
#   배포되지 않으므로 값이 읽히지 않고, 함수 단위로 거르는 유효 버전 검사 · secret
#   접근 권한 부여도 그 secret 에는 걸리지 않는다. 일괄 생성 명령은 docs/manual.md
#   「로그인 수단 켜고 끄기」 의 「켜기」 ④.
#
# 사용법:
#   bash scripts/deploy_functions.sh <dev|stg|prod>            # dry-run (기본 — 아무것도 배포하지 않는다)
#   bash scripts/deploy_functions.sh <dev|stg|prod> --apply    # 출력한 명령을 차례로 실행한다
#
# 출력 계약:
#   - 공통 출력: `flavor:` · `project:` · `enabled:` · `functions (<N>):` + 줄마다 `  - <이름>` ·
#     묶음마다 `command: firebase deploy --project <id> --only functions:a,functions:b,…`
#   - dry-run 마지막 줄: DRY-RUN OK <flavor> functions=<N> batches=<B> (exit 0)
#   - 실행 마지막 줄:    DEPLOY OK <flavor> functions=<N> batches=<B> (exit 0)
#     실행 모드는 묶음마다 `running: firebase deploy …` 를 출력한 뒤 같은 명령을 실행한다.
#   - 실패: FAIL: <사유> (stderr, exit 1) · 인자 오류: usage (stderr, exit 2)
#
# 안전 계약:
#   - config/<flavor>.json 에서 .firebaseProjectId · .enabledAuthProviders 두 값만 읽는다.
#     다른 키(키 · secret 값)는 읽지도 출력하지도 않는다.
#   - 함수를 지우지 않는다. 강제 삭제 옵션과 비대화형 옵션을 명령에 넣지 않는다 —
#     없는 secret 은 Firebase CLI 가 배포 중 값을 묻는 표준 동작을 그대로 둔다.
#   - secret 사전 점검 · 목록 밖 배포 함수 안내 · rules 배포는 하지 않는다(D-09 — 부가 기능 없음).
#   - 입력 검증만 한다: 인자 · config 부재 · 프로젝트 ID 형식 · manifest 에 없는 provider 이름.
#   - 명령은 bash 배열 인자로 실행한다(word splitting 없음). CSV 토큰은 manifest 키와 일치할
#     때만 통과하므로 명령에 임의 문자열이 섞이지 않는다.
#
# 10개 분할:
#   함수가 10개를 넘으면 명령을 10개 이하 묶음으로 나눠 출력 · 실행한다. 근거는 Firebase 공식
#   문서(https://firebase.google.com/docs/functions/manage-functions) 원문 —
#   "When deploying large numbers of functions, you may exceed the standard quota and receive
#    HTTP 429 or 500 error messages. To solve this, deploy functions in groups of 10 or fewer."
#   묶음마다 `firebase deploy` 를 따로 실행하므로 firebase.json 의 functions predeploy
#   (pnpm lint · build) · 코드베이스 로드 · secret 존재 확인이 묶음 수만큼 반복된다(정상).
#
# 함수 목록의 진실원:
#   scripts/functions_manifest.json 한 곳이다(common + providers.<slug>). 이 목록과
#   functions/src/index.ts 의 export 가 어긋나면 functions/test/deploy_manifest.test.ts 가,
#   providers 키가 앱의 kAllProviderIds 와 어긋나면
#   test/core/config/functions_manifest_contract_test.dart 가 실패한다.
#   Functions 를 추가하면 manifest 의 common(또는 해당 provider 배열)에 이름을 더한다.
#
# dry-run 은 firebase CLI 없이 돈다. --apply 에서만 PATH 의 `firebase` 를 확인한다.
#
# starter-kit 정책: 외부 CI 미도입 — 사람이 직접 돌리는 스크립트다.

set -euo pipefail

usage() {
  cat >&2 <<'USAGE'
usage: bash scripts/deploy_functions.sh <dev|stg|prod> [--apply]

  config/<flavor>.json 의 enabledAuthProviders 로 공통 함수 + 켠 provider 함수만 고른다.
  옵션 없이 실행하면 배포 명령만 출력한다(dry-run). --apply 를 줄 때만 실제로 배포한다.
USAGE
}

# 실패 사유 한 줄을 stderr 로 내고 종료한다.
fail() {
  echo "FAIL: $1" >&2
  exit 1
}

if [ "$#" -lt 1 ] || [ "$#" -gt 2 ]; then
  usage
  exit 2
fi

FLAVOR="$1"
MODE="${2:-}"

case "$FLAVOR" in
  dev | stg | prod) ;;
  *)
    usage
    exit 2
    ;;
esac

case "$MODE" in
  "" | --apply) ;;
  *)
    usage
    exit 2
    ;;
esac

# 저장소 루트는 스크립트 위치 기준으로 찾는다 — 어느 디렉터리에서 실행해도 같은 파일을 읽는다.
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CONFIG="$ROOT/config/$FLAVOR.json"
MANIFEST="$ROOT/scripts/functions_manifest.json"
BATCH_SIZE=10

if ! command -v jq >/dev/null 2>&1; then
  fail "jq 가 필요하다 (brew install jq)"
fi

[ -f "$MANIFEST" ] || fail "함수 목록 파일이 없다: scripts/functions_manifest.json"
[ -f "$CONFIG" ] ||
  fail "config/${FLAVOR}.json 이 없다 — cp config/${FLAVOR}.example.json config/${FLAVOR}.json 뒤 값을 채운다"

# config 에서 읽는 값은 이 두 개뿐이다.
PROJECT="$(jq -r '.firebaseProjectId // ""' "$CONFIG")" ||
  fail "config/${FLAVOR}.json 을 JSON 으로 읽지 못했다"
CSV="$(jq -r '.enabledAuthProviders // ""' "$CONFIG")" ||
  fail "config/${FLAVOR}.json 을 JSON 으로 읽지 못했다"

[ -n "$PROJECT" ] || fail "config/${FLAVOR}.json 의 firebaseProjectId 가 비어 있다"
# Firebase 프로젝트 ID 형식(소문자 · 숫자 · 하이픈, 소문자로 시작)만 받는다 —
# 값이 `-` 로 시작해 CLI 옵션으로 읽히는 일을 막는다.
# 문자 범위 표기 대신 허용 문자를 전부 나열한다 — macOS `/bin/bash` 3.2 는 UTF-8
# 로캘(en_US.UTF-8 · ko_KR.UTF-8)에서 대괄호 범위를 정렬 순서로 해석해 소문자 범위가
# 대문자까지 매치한다. 나열은 로캘과 무관하므로 스크립트 로캘은 바꾸지 않는다(한국어 안내 유지).
case "$PROJECT" in
  [abcdefghijklmnopqrstuvwxyz]*) ;;
  *) fail "config/${FLAVOR}.json 의 firebaseProjectId 형식이 잘못됐다: ${PROJECT}" ;;
esac
case "$PROJECT" in
  *[!abcdefghijklmnopqrstuvwxyz0123456789-]*) fail "config/${FLAVOR}.json 의 firebaseProjectId 형식이 잘못됐다: ${PROJECT}" ;;
esac

KNOWN="$(jq -r '.providers | keys_unsorted | join(" ")' "$MANIFEST")" ||
  fail "scripts/functions_manifest.json 을 JSON 으로 읽지 못했다"

# CSV → 토큰(앞뒤 공백 제거 · 빈 토큰 버림 · 중복 제거 · manifest 키 화이트리스트).
ENABLED=()
RAW_TOKENS=()
OLD_IFS="$IFS"
IFS=','
# shellcheck disable=SC2206 # 쉼표 분리가 목적이다(glob 은 아래에서 화이트리스트로 걸러진다).
set -f
RAW_TOKENS=($CSV)
set +f
IFS="$OLD_IFS"

for RAW in ${RAW_TOKENS[@]+"${RAW_TOKENS[@]}"}; do
  # 앞뒤 공백 제거 (bash 3.2 호환 — 매개변수 확장만 쓴다).
  TOKEN="${RAW#"${RAW%%[![:space:]]*}"}"
  TOKEN="${TOKEN%"${TOKEN##*[![:space:]]}"}"
  [ -n "$TOKEN" ] || continue

  IS_KNOWN=0
  for K in $KNOWN; do
    if [ "$K" = "$TOKEN" ]; then
      IS_KNOWN=1
      break
    fi
  done
  [ "$IS_KNOWN" = 1 ] ||
    fail "enabledAuthProviders 에 알 수 없는 provider: ${TOKEN} (쓸 수 있는 값: ${KNOWN})"

  IS_DUP=0
  for E in ${ENABLED[@]+"${ENABLED[@]}"}; do
    if [ "$E" = "$TOKEN" ]; then
      IS_DUP=1
      break
    fi
  done
  [ "$IS_DUP" = 1 ] || ENABLED+=("$TOKEN")
done

ENABLED_JOINED="${ENABLED[*]+"${ENABLED[*]}"}"

# 함수 목록 = common + manifest 키 순서로 켠 provider 의 배열 (CSV 순서와 무관 · 결정적).
FN_LIST="$(jq -r --arg en "$ENABLED_JOINED" '
  ($en | split(" ") | map(select(length > 0))) as $on
  | .common[],
    (.providers | to_entries[] | select(.key as $k | $on | any(.[]; . == $k)) | .value[])
' "$MANIFEST")" || fail "scripts/functions_manifest.json 에서 함수 목록을 만들지 못했다"

FUNCS=()
while IFS= read -r FN; do
  [ -n "$FN" ] && FUNCS+=("$FN")
done <<EOF_FUNCS
$FN_LIST
EOF_FUNCS

N="${#FUNCS[@]}"
[ "$N" -gt 0 ] || fail "배포할 함수가 없다 — scripts/functions_manifest.json 의 common 을 확인한다"

# 10개 이하 묶음마다 `--only` 값 하나를 만든다.
BATCHES=()
I=0
while [ "$I" -lt "$N" ]; do
  ONLY=""
  J="$I"
  END=$((I + BATCH_SIZE))
  while [ "$J" -lt "$END" ] && [ "$J" -lt "$N" ]; do
    if [ -n "$ONLY" ]; then
      ONLY="${ONLY},"
    fi
    ONLY="${ONLY}functions:${FUNCS[$J]}"
    J=$((J + 1))
  done
  BATCHES+=("$ONLY")
  I="$END"
done
B="${#BATCHES[@]}"

echo "flavor: ${FLAVOR}"
echo "project: ${PROJECT}"
if [ -n "$ENABLED_JOINED" ]; then
  echo "enabled: ${ENABLED_JOINED}"
else
  echo "enabled: (없음)"
fi
echo "functions (${N}):"
for FN in "${FUNCS[@]}"; do
  echo "  - ${FN}"
done
for ONLY in "${BATCHES[@]}"; do
  echo "command: firebase deploy --project ${PROJECT} --only ${ONLY}"
done

if [ "$MODE" != "--apply" ]; then
  echo ""
  echo "실제로 배포하려면: bash scripts/deploy_functions.sh ${FLAVOR} --apply"
  echo "DRY-RUN OK ${FLAVOR} functions=${N} batches=${B}"
  exit 0
fi

if ! command -v firebase >/dev/null 2>&1; then
  fail "firebase CLI 가 PATH 에 없다 (npm install -g firebase-tools)"
fi

# firebase CLI 는 현재 디렉터리에서 firebase.json 을 찾는다 — 저장소 루트에서 실행한다.
cd "$ROOT"

IDX=0
for ONLY in "${BATCHES[@]}"; do
  IDX=$((IDX + 1))
  echo "running: firebase deploy --project ${PROJECT} --only ${ONLY}"
  firebase deploy --project "$PROJECT" --only "$ONLY" ||
    fail "${IDX}번째 묶음 배포 실패 (${B}개 중) — 앞 묶음은 이미 배포됐다"
done

echo "DEPLOY OK ${FLAVOR} functions=${N} batches=${B}"
