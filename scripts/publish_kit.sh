#!/usr/bin/env bash
# Phase 17.4 D-29 · D-30 — 킷 공개 mirror 를 만들고 검사하는 발행 스크립트.
#
# 목적:
#   private 저장소(origin)의 master 이력에서 공개 mirror 를 기계적으로 다시 만들고,
#   공개해도 되는 이력인지 검사한 뒤 공개 저장소와 이어지는지 확인한다. 공개본은 손으로
#   고치지 않는다 — 고칠 것은 private 에서 고치고 이 스크립트로 다시 만든다.
#
# 사용법:
#   bash scripts/publish_kit.sh            # 할 일만 출력한다(파일 · 디렉터리를 만들지 않는다)
#   bash scripts/publish_kit.sh mirror     # origin master fresh clone → 이력 필터 → main 개명
#   bash scripts/publish_kit.sh scan       # mirror 이력의 킷 불변식 + gitleaks
#   bash scripts/publish_kit.sh check      # 공개 저장소 main · v* 태그가 재생성 main 의 조상인지
#   순서: mirror → scan → check
#
# 출력 계약:
#   - mirror 마지막 줄: MIRROR OK main=<40자 해시> commits=<N> (앞 줄 `tools: git=… filter-repo=…`)
#   - scan: `control: <이름>=1` 8줄 · `invariant: <이름>=<수>` 10줄 → gitleaks →
#     마지막 줄 SCAN OK main=<해시> gitleaks=0 invariants=10
#   - check 마지막 줄: CHECK OK first-publish main=<해시> 또는
#     CHECK OK main=<해시> public-main=<해시> tags=<N>
#   - 단계를 통과하면 $WORK/<단계>.ok 에 그때의 mirror main 해시 1줄을 쓴다.
#   - 실패: FAIL: <사유> (stderr, exit 1) · 인자 오류: usage (stderr, exit 2)
#
# 안전 계약:
#   - 치환 대상 값(키 · Team ID · Channel ID · 메일 주소)을 출력하지 않는다 — 계수만 출력한다.
#     검사 정규식의 양성 대조 문자열도 실행 시점에 조각으로 조립한다.
#   - 이력 필터는 $WORK/mirror 의 fresh clone 안에서만 돈다. 이 저장소(작업 트리 · .git)는
#     읽기만 한다. filter-repo 의 fresh clone 검사를 우회하는 옵션을 쓰지 않는다.
#   - 공개 저장소에는 읽기(ls-remote · fetch)만 한다. 강제 갱신 · 태그 이동 · ref 삭제를 하지 않는다.
#   - 로컬 작업 트리를 스캔하지 않는다 — 검사 대상은 mirror 이력뿐이다.
#   - 지우는 것은 자기 산출물 $WORK/mirror 하나다. WORK 는 <저장소>/build/ 아래만 받는다.
#
# 환경변수 (테스트 · 리허설 대역용 — 기본값은 실제 주소):
#   KIT_PUBLISH_ORIGIN  private origin   (기본 git@github.com:woodkill/flutter_starter_kit.git)
#   KIT_PUBLISH_PUBLIC  공개 저장소       (기본 git@github.com:woodkill/flutter-firebase-starter-kit.git)
#   KIT_PUBLISH_WORK    작업 디렉터리     (기본 <저장소>/build/publish — <저장소>/build/ 아래 절대경로만)
#
# 규칙 위치:
#   .planning/release/ 의 규칙 파일 3종이다. 이 디렉터리는 공개 mirror 에서 빠지므로 공개본에서
#   이 스크립트는 사용법만 출력하고 서브커맨드는 FAIL 로 멈춘다(유지보수자 전용).
#
# starter-kit 정책: 외부 CI 미도입 — 사람이 직접 돌리는 스크립트다.

set -euo pipefail

usage() {
  cat <<'USAGE'
usage: bash scripts/publish_kit.sh [mirror|scan|check]

  인자 없이 실행하면 할 일만 출력한다. 서브커맨드는 이 순서로 돈다:
    mirror  origin master 를 fresh clone 해 이력을 필터하고 main 으로 개명한다
    scan    mirror 이력의 킷 불변식(제외 경로 · 치환 대상 0)과 gitleaks 를 검사한다
    check   공개 저장소의 main · v* 태그가 재생성한 main 의 조상인지 확인한다
  환경변수: KIT_PUBLISH_ORIGIN · KIT_PUBLISH_PUBLIC · KIT_PUBLISH_WORK (테스트 · 리허설 대역용)
USAGE
}

# 실패 사유 한 줄을 stderr 로 내고 종료한다.
fail() {
  echo "FAIL: $1" >&2
  exit 1
}

if [ "$#" -gt 1 ]; then
  usage >&2
  exit 2
fi

CMD="${1:-}"
case "$CMD" in
  "" | mirror | scan | check) ;;
  *)
    usage >&2
    exit 2
    ;;
esac

# 저장소 루트는 스크립트 위치 기준으로 찾는다 — 어느 디렉터리에서 실행해도 같은 파일을 읽는다.
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
RULES="$ROOT/.planning/release"
ORIGIN="${KIT_PUBLISH_ORIGIN:-git@github.com:woodkill/flutter_starter_kit.git}"
PUBLIC="${KIT_PUBLISH_PUBLIC:-git@github.com:woodkill/flutter-firebase-starter-kit.git}"
WORK="${KIT_PUBLISH_WORK:-$ROOT/build/publish}"
MIRROR="$WORK/mirror"

# WORK 가드 — 이 스크립트가 지우는 $WORK/mirror 가 저장소의 build/ 밖을 가리키지 않게 한다.
case "$WORK" in
  "$ROOT"/build/?*) ;;
  *) fail "KIT_PUBLISH_WORK 는 $ROOT/build/ 아래 절대경로여야 한다: $WORK" ;;
esac
case "$WORK" in
  *..*) fail "KIT_PUBLISH_WORK 에 .. 를 쓸 수 없다: $WORK" ;;
esac

# 검사 정규식 (POSIX ERE · LC_ALL=C 바이트 비교). 값이 아니라 모양만 담는다.
RE_AIZA='AIza[0-9A-Za-z_-]{35}'
RE_TEAM='DEVELOPMENT_TEAM = [A-Z0-9]{10};'
KEEP_TEAM='DEVELOPMENT_TEAM = 0000000000;'
RE_CHANNEL_BLOB='\(예: `[0-9]{10}`\)'
KEEP_CHANNEL_BLOB='\(예: `0000000000`\)'
RE_CHANNEL_MESSAGE='(client_id |Channel )[0-9]{10}'
RE_SESSION='^Claude-Session:'
RE_EMAIL='[A-Za-z0-9._%+-]+@(naver|gmail)\.com'
RE_PLANNING_PATH='^"?\.planning/'
RE_EXCLUDED_PATH='^"?(CLAUDE\.md|\.claude/rules/docs-user-manual\.md|\.claude/settings\.json)"?$|^"?\.claude/skills/'

# 표준입력에서 ERE $1 에 맞는 줄 수를 출력한다 — 일치한 줄 자체는 출력하지 않는다.
count_re() {
  local n
  n=$(LC_ALL=C grep -a -c -E -- "$1") || [ "$?" -eq 1 ] || return 1
  echo "$n"
}

# 표준입력에서 ERE $1 에 맞으면서 ERE $2 에는 맞지 않는 줄 수를 출력한다(값은 출력하지 않는다).
count_re_except() {
  local n
  n=$({ LC_ALL=C grep -a -E -- "$1" || [ "$?" -eq 1 ]; } |
    { LC_ALL=C grep -a -c -v -E -- "$2" || [ "$?" -eq 1 ]; }) || return 1
  echo "$n"
}

# 규칙 파일 3종이 있는 트리(private)에서만 서브커맨드를 돌린다.
require_rules() {
  local f
  for f in mirror-exclude-paths.txt mirror-replace-text.txt mirror-replace-message.txt; do
    [ -f "$RULES/$f" ] ||
      fail "규칙 파일이 없는 트리(공개 mirror) — 이 스크립트는 유지보수자 전용이다"
  done
}

# mirror 산출물의 main 해시를 출력한다. 없으면 FAIL.
mirror_main() {
  [ -d "$MIRROR/.git" ] || fail "mirror 가 없다 — 먼저 bash scripts/publish_kit.sh mirror"
  git -C "$MIRROR" rev-parse --verify -q refs/heads/main ||
    fail "mirror 에 main 이 없다 — 다시 bash scripts/publish_kit.sh mirror"
}

# 인자 없음 — 사용법과 단계별 진행 상태만 출력한다. 아무것도 만들지 않는다.
show_status() {
  local main step
  usage
  echo ""
  echo "다음 할 일:"
  if [ ! -f "$RULES/mirror-exclude-paths.txt" ]; then
    echo "  규칙 파일이 없는 트리(공개 mirror) — 서브커맨드는 유지보수자 전용이다"
    return 0
  fi
  if [ ! -d "$MIRROR/.git" ]; then
    echo "  아직 mirror 없음 — bash scripts/publish_kit.sh mirror 부터"
    return 0
  fi
  main=$(git -C "$MIRROR" rev-parse --verify -q refs/heads/main 2>/dev/null) || main=""
  if [ -z "$main" ]; then
    echo "  mirror 가 불완전하다 — bash scripts/publish_kit.sh mirror 를 다시 돌린다"
    return 0
  fi
  echo "  mirror main=$main"
  for step in mirror scan check; do
    if [ -f "$WORK/$step.ok" ] && [ "$(cat "$WORK/$step.ok")" = "$main" ]; then
      echo "  [완료] $step"
    else
      echo "  [할 일] $step"
    fi
  done
}

# 공개 저장소에서 가져온 비교용 로컬 ref(refs/public/*)를 mirror 에서 걷어낸다.
drop_public_refs() {
  git -C "$MIRROR" for-each-ref --format='delete %(refname)' refs/public refs/public-tags |
    git -C "$MIRROR" update-ref --stdin
}

cmd_mirror() {
  local remote local_master refs main count git_version filter_version

  command -v git-filter-repo >/dev/null 2>&1 ||
    fail "git-filter-repo 가 PATH 에 없다 — 설치: brew install git-filter-repo"

  # origin 이 뒤처진 채 공개본을 만들지 않는다(RESEARCH Pitfall 1) — clone 전에 비교한다.
  remote=$(git ls-remote "$ORIGIN" refs/heads/master) || fail "origin 에 접근할 수 없다: $ORIGIN"
  remote="${remote%%[[:space:]]*}"
  local_master=$(git -C "$ROOT" rev-parse --verify -q refs/heads/master) ||
    fail "이 저장소에 master 가 없다"
  if [ -z "$remote" ] || [ "$remote" != "$local_master" ]; then
    fail "origin master 와 로컬 master 가 다르다 — 먼저 git push origin master"
  fi

  rm -f "$WORK/mirror.ok"
  rm -rf "$MIRROR"
  mkdir -p "$WORK"

  git clone --quiet --no-local --branch master --single-branch --no-tags "$ORIGIN" "$MIRROR" || fail "origin clone 실패: $ORIGIN"
  ( cd "$MIRROR" && git filter-repo --paths-from-file "$RULES/mirror-exclude-paths.txt" --invert-paths --replace-text "$RULES/mirror-replace-text.txt" --replace-message "$RULES/mirror-replace-message.txt" ) > "$WORK/filter-repo.log" 2>&1 || fail "이력 필터 실패 — $WORK/filter-repo.log"
  git -C "$MIRROR" branch -m master main || fail "main 개명 실패"

  # 이력 필터가 조용히 아무것도 안 하는 경우(fresh clone 검사)를 메타데이터로 잡는다(Pitfall 2).
  [ -f "$MIRROR/.git/filter-repo/commit-map" ] ||
    fail "이력 필터 메타데이터(commit-map)가 없다 — $WORK/filter-repo.log"
  [ -z "$(git -C "$MIRROR" remote)" ] || fail "mirror 에 remote 가 남아 있다"
  refs=$(git -C "$MIRROR" for-each-ref --format='%(refname)' refs/heads refs/tags) ||
    fail "mirror ref 목록을 읽지 못했다"
  [ "$refs" = "refs/heads/main" ] || fail "mirror ref 가 refs/heads/main 하나가 아니다"

  main=$(git -C "$MIRROR" rev-parse --verify -q refs/heads/main) || fail "mirror main 해시를 읽지 못했다"
  count=$(git -C "$MIRROR" rev-list --count main) || fail "mirror 커밋 수를 세지 못했다"
  git_version=$(git --version) || fail "git 버전을 읽지 못했다"
  git_version="${git_version#git version }"
  filter_version=$(git filter-repo --version) || fail "git-filter-repo 버전을 읽지 못했다"

  echo "tools: git=$git_version filter-repo=$filter_version"
  printf '%s\n' "$main" > "$WORK/mirror.ok"
  echo "MIRROR OK main=$main commits=$count"
}

cmd_scan() {
  local main x35 digits10 key_part team_part session_part mail_part
  local names patch messages head n name failed report_count
  main=$(mirror_main)
  rm -f "$WORK/scan.ok"

  names="$WORK/scan-names.txt"
  patch="$WORK/scan-patch.txt"
  messages="$WORK/scan-messages.txt"
  head="$WORK/scan-head.txt"
  git -C "$MIRROR" -c core.quotepath=off log --all --name-only --format= > "$names" ||
    fail "mirror 이력 경로 목록을 만들지 못했다"
  git -C "$MIRROR" log -p --all --no-color --no-ext-diff --no-textconv --format= > "$patch" ||
    fail "mirror 이력 diff 를 만들지 못했다"
  git -C "$MIRROR" log --all --format=%B > "$messages" || fail "mirror 메시지 목록을 만들지 못했다"
  git -C "$MIRROR" -c core.quotepath=off ls-tree -r --name-only main > "$head" ||
    fail "mirror main 트리 목록을 만들지 못했다"

  # 양성 대조 — 검사 정규식이 실제로 맞는지 먼저 본다(공허한 0 방지). 문자열은 조각으로 조립한다.
  # 숫자 · 키 모양 리터럴을 스크립트 본문에 두지 않는다 — 공개 이력의 이 파일도 같은 규칙으로 걸러진다.
  x35=$(printf '%35s' '' | tr ' ' x)
  digits10=$(printf '%10s' '' | tr ' ' 7)
  key_part="AI"
  team_part="DEVELOPMENT"
  session_part="Claude"
  mail_part="gm"
  failed=""
  n=$(count_re '^lib/' < "$names") || fail "양성 대조 계수 실패"
  [ "$n" -ge 1 ] && n=1
  echo "control: names=$n"
  [ "$n" = 1 ] || failed="$failed names"
  n=$(count_re '^diff --git ' < "$patch") || fail "양성 대조 계수 실패"
  [ "$n" -ge 1 ] && n=1
  echo "control: patch=$n"
  [ "$n" = 1 ] || failed="$failed patch"
  n=$(printf '%s\n' "${key_part}za${x35}" | count_re "$RE_AIZA") || fail "양성 대조 계수 실패"
  echo "control: aiza=$n"
  [ "$n" = 1 ] || failed="$failed aiza"
  n=$(printf '%s\n' "${team_part}_TEAM = ABCDEABCDE;" | count_re_except "$RE_TEAM" "$KEEP_TEAM") ||
    fail "양성 대조 계수 실패"
  echo "control: team-id=$n"
  [ "$n" = 1 ] || failed="$failed team-id"
  n=$(printf '%s\n' '  - `Channel ID` — 숫자 (예: `'"$digits10"'`) — 공개 키' |
    count_re_except "$RE_CHANNEL_BLOB" "$KEEP_CHANNEL_BLOB") || fail "양성 대조 계수 실패"
  echo "control: channel-id-blob=$n"
  [ "$n" = 1 ] || failed="$failed channel-id-blob"
  n=$(printf '%s\n' "(client_id $digits10 + PKCE" | count_re "$RE_CHANNEL_MESSAGE") ||
    fail "양성 대조 계수 실패"
  echo "control: channel-id-message=$n"
  [ "$n" = 1 ] || failed="$failed channel-id-message"
  n=$(printf '%s\n' "${session_part}-Session: https://example.invalid/s" | count_re "$RE_SESSION") ||
    fail "양성 대조 계수 실패"
  echo "control: claude-session=$n"
  [ "$n" = 1 ] || failed="$failed claude-session"
  n=$(printf '%s\n' "someone@${mail_part}ail.com" | count_re "$RE_EMAIL") || fail "양성 대조 계수 실패"
  echo "control: email=$n"
  [ "$n" = 1 ] || failed="$failed email"
  [ -z "$failed" ] || fail "검사 정규식 양성 대조 실패 —$failed"

  # 불변식 — 전부 출력한 뒤 판정한다. 값은 출력하지 않는다.
  failed=""
  for name in planning-paths excluded-paths head-excluded aiza-blob aiza-message team-id-blob \
    channel-id-blob channel-id-message claude-session-message email-message; do
    case "$name" in
      planning-paths) n=$(count_re "$RE_PLANNING_PATH" < "$names") ;;
      excluded-paths) n=$(count_re "$RE_EXCLUDED_PATH" < "$names") ;;
      head-excluded) n=$(count_re "$RE_PLANNING_PATH|$RE_EXCLUDED_PATH" < "$head") ;;
      aiza-blob) n=$(count_re "$RE_AIZA" < "$patch") ;;
      aiza-message) n=$(count_re "$RE_AIZA" < "$messages") ;;
      team-id-blob) n=$(count_re_except "$RE_TEAM" "$KEEP_TEAM" < "$patch") ;;
      channel-id-blob) n=$(count_re_except "$RE_CHANNEL_BLOB" "$KEEP_CHANNEL_BLOB" < "$patch") ;;
      channel-id-message) n=$(count_re "$RE_CHANNEL_MESSAGE" < "$messages") ;;
      claude-session-message) n=$(count_re "$RE_SESSION" < "$messages") ;;
      email-message) n=$(count_re "$RE_EMAIL" < "$messages") ;;
    esac || fail "불변식 계수 실패: $name"
    echo "invariant: $name=$n"
    [ "$n" = 0 ] || failed="$failed $name"
  done
  [ -z "$failed" ] || fail "공개 이력 불변식 위반 —$failed"

  # gitleaks — 설정은 기본 탐색(mirror 루트의 .gitleaks.toml)을 따른다. 결과는 가려서(--redact) 파일로만.
  command -v gitleaks >/dev/null 2>&1 || fail "gitleaks 가 PATH 에 없다 — 설치: brew install gitleaks"
  if gitleaks git "$MIRROR" --no-banner --redact --report-format json --report-path "$WORK/gitleaks.json" > "$WORK/gitleaks.log" 2>&1; then
    echo "invariant: gitleaks=0"
    printf '%s\n' "$main" > "$WORK/scan.ok"
    echo "SCAN OK main=$main gitleaks=0 invariants=10"
    return 0
  fi
  [ -s "$WORK/gitleaks.json" ] || fail "gitleaks 실행 실패 — $WORK/gitleaks.log"
  report_count=$(jq length "$WORK/gitleaks.json") || fail "gitleaks 보고서를 읽지 못했다 — $WORK/gitleaks.json"
  fail "gitleaks 가 ${report_count}건을 찾았다 — $WORK/gitleaks.json (값은 가려져 있다)"
}

cmd_check() {
  local main heads tags public_main tag_count ref
  main=$(mirror_main)
  rm -f "$WORK/check.ok"

  git ls-remote "$PUBLIC" > "$WORK/public-refs.txt" 2> "$WORK/public-refs.err" ||
    fail "공개 저장소에 접근할 수 없다: $PUBLIC"
  heads=$(awk -F '\t' '$2 == "refs/heads/main" { n++ } END { print n + 0 }' "$WORK/public-refs.txt")
  tags=$(awk -F '\t' 'index($2, "refs/tags/v") == 1 { n++ } END { print n + 0 }' "$WORK/public-refs.txt")

  if [ "$heads" = 0 ]; then
    [ "$tags" = 0 ] || fail "공개 저장소에 main 없이 v* 태그만 있다 — 불일치 상태라 원인을 조사한다"
    printf '%s\n' "$main" > "$WORK/check.ok"
    echo "CHECK OK first-publish main=$main"
    return 0
  fi

  # 공개 ref 를 비교용 로컬 ref 로만 가져온다(태그 자동 추적 없음) — 비교 뒤 걷어낸다.
  drop_public_refs || fail "비교용 ref 를 정리하지 못했다"
  git -C "$MIRROR" fetch --quiet --no-tags "$PUBLIC" '+refs/heads/main:refs/public/main' '+refs/tags/v*:refs/public-tags/v*' ||
    fail "공개 저장소의 main · v* 태그를 가져오지 못했다: $PUBLIC"
  public_main=$(git -C "$MIRROR" rev-parse --verify -q refs/public/main) ||
    fail "가져온 공개 main 을 읽지 못했다"

  if ! git -C "$MIRROR" merge-base --is-ancestor refs/public/main main; then
    drop_public_refs || true
    fail "공개 main 이 재생성 이력에 없다 — 입력(규칙 · origin · 도구 버전)이 달라졌다. 강제 갱신하지 않고 원인을 조사한다"
  fi

  tag_count=0
  while IFS= read -r ref; do
    [ -n "$ref" ] || continue
    if ! git -C "$MIRROR" merge-base --is-ancestor "${ref}^{commit}" main; then
      drop_public_refs || true
      fail "공개 태그 ${ref#refs/public-tags/} 불일치 — 재생성 main 의 조상이 아니다. 원인을 조사한다"
    fi
    tag_count=$((tag_count + 1))
  done <<EOF_TAGS
$(git -C "$MIRROR" for-each-ref --format='%(refname)' refs/public-tags)
EOF_TAGS

  drop_public_refs || fail "비교용 ref 를 정리하지 못했다"
  printf '%s\n' "$main" > "$WORK/check.ok"
  echo "CHECK OK main=$main public-main=$public_main tags=$tag_count"
}

if [ -z "$CMD" ]; then
  show_status
  exit 0
fi

require_rules

case "$CMD" in
  mirror) cmd_mirror ;;
  scan) cmd_scan ;;
  check) cmd_check ;;
esac
