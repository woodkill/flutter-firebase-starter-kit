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
#   bash scripts/publish_kit.sh verify     # mirror 의 fresh clone 에서 analyze · 전체 Flutter 테스트 · Jest
#   bash scripts/publish_kit.sh check      # 공개 저장소 main · v* 태그가 재생성 main 의 조상인지
#   bash scripts/publish_kit.sh push       # 태그 생성 · main + 태그 push 명령만 출력(dry-run) · --apply 면 실행
#   bash scripts/publish_kit.sh release    # GitHub Release 명령 · notes 파일만 준비(dry-run) · --apply 면 실행
#   bash scripts/publish_kit.sh rules-hash # 규칙 3파일 + mirror 레시피 블록의 sha256 4줄(파일을 쓰지 않는다)
#   순서: mirror → scan → verify → check → push → release
#
# 동결 (D-12):
#   .planning/release/rules.sha256 이 규칙 3파일과 이 스크립트의 mirror 레시피 블록
#   (`# MIRROR-RECIPE-BEGIN` ~ `# MIRROR-RECIPE-END`)의 sha256 을 담는다. mirror 는 시작할 때
#   rules-hash 결과와 이 파일을 바이트로 비교해 다르면 clone 전에 멈춘다. rc.1 발행 뒤에는
#   규칙 · 레시피를 바꾸지 않는다(바꾸면 공개 이력 전체의 해시가 달라진다). rc.1 전 의도한
#   변경이면: bash scripts/publish_kit.sh rules-hash > .planning/release/rules.sha256
#
# 출력 계약:
#   - mirror 마지막 줄: MIRROR OK main=<40자 해시> commits=<N> (앞 줄 `tools: git=… filter-repo=…`)
#   - scan: `control: <이름>=1` 8줄 · `invariant: <이름>=<수>` 10줄 → gitleaks →
#     마지막 줄 SCAN OK main=<해시> gitleaks=0 invariants=10
#   - verify: `ios-goldens: copied=<N>` 또는 `ios-goldens: skipped (not macOS)` → 단계 로그
#     $WORK/verify-{fvm,pubget,build-runner,analyze,test,functions}.log → `flutter-tests: +N ~M` ·
#     `jest: Tests: …` → 마지막 줄 VERIFY OK main=<해시> flutter=pass jest=pass ios-goldens=<N|skipped>
#   - check 마지막 줄: CHECK OK first-publish main=<해시> 또는
#     CHECK OK main=<해시> public-main=<해시> tags=<N>
#   - push: `command: …` 줄들(태그 생성 · main 과 태그를 한 번에 보내는 `push --atomic`) →
#     DRY-RUN OK push tag=<TAG> main=<해시> (--apply 면 PUSH OK tag=<TAG> main=<해시>)
#   - release: `command: …` 줄 → DRY-RUN OK release tag=<TAG> (--apply 면 RELEASE OK tag=<TAG>)
#   - 인자 없음: 사용법 · 다음 할 일 → 마지막 줄
#     status: mirror=<ok|-> scan=<ok|-> verify=<ok|-> check=<ok|-> push=<ok|-> main=<해시|none>
#   - 단계를 통과하면 $WORK/<단계>.ok 에 그때의 mirror main 해시 1줄을 쓴다. push 는 mirror · scan ·
#     verify · check 표시가, release 는 push 표시가 전부 지금 mirror main 해시와 같아야 열린다.
#   - 실패: FAIL: <사유> (stderr, exit 1) · 인자 오류: usage (stderr, exit 2)
#
# 안전 계약:
#   - 치환 대상 값(키 · Team ID · Channel ID · 메일 주소)을 출력하지 않는다 — 계수만 출력한다.
#     검사 정규식의 양성 대조 문자열도 실행 시점에 조각으로 조립한다.
#   - 이력 필터는 $WORK/mirror 의 fresh clone 안에서만 돈다. 이 저장소(작업 트리 · .git)는
#     읽기만 한다. filter-repo 의 fresh clone 검사를 우회하는 옵션을 쓰지 않는다.
#   - 공개 저장소를 바꾸는 것은 `push --apply`(main fast-forward + 새 v* 태그)와 `release --apply`
#     (GitHub Release)뿐이다. --apply 가 없으면 실행할 명령만 출력한다. 강제 갱신 · 태그 이동 ·
#     ref 삭제 경로는 없다 — 공개 태그가 이미 있으면 같은 커밋일 때만 통과한다.
#   - 로컬 작업 트리를 스캔하지 않는다 — 검사 대상은 mirror 이력뿐이다.
#   - 지우는 것은 자기 산출물 $WORK/mirror · $WORK/verify 둘이다. WORK 는 <저장소>/build/ 아래만 받는다.
#   - verify 가 유지보수자 트리에서 clone 으로 넘기는 파일은 gitignored iOS golden PNG(`*_ios.png`)뿐이다.
#     실 키 파일(skip-worktree 2파일 · config/*.json · flavor xcconfig)은 복사하지 않는다.
#
# 환경변수 (테스트 · 리허설 대역용 — 기본값은 실제 주소):
#   KIT_PUBLISH_ORIGIN  private origin   (기본 git@github.com:woodkill/flutter_starter_kit.git)
#   KIT_PUBLISH_PUBLIC  공개 저장소       (기본 git@github.com:woodkill/flutter-firebase-starter-kit.git)
#   KIT_PUBLISH_WORK    작업 디렉터리     (기본 <저장소>/build/publish — <저장소>/build/ 아래 절대경로만)
#   KIT_PUBLISH_REPO    Release 저장소    (기본 woodkill/flutter-firebase-starter-kit — gh 의 OWNER/REPO)
#
# 규칙 위치:
#   .planning/release/ 의 규칙 파일 3종이다. 이 디렉터리는 공개 mirror 에서 빠지므로 공개본에서
#   이 스크립트는 사용법만 출력하고 서브커맨드는 FAIL 로 멈춘다(유지보수자 전용).
#
# starter-kit 정책: 외부 CI 미도입 — 사람이 직접 돌리는 스크립트다.

set -euo pipefail

usage() {
  cat <<'USAGE'
usage: bash scripts/publish_kit.sh [mirror|scan|verify|check|rules-hash]
       bash scripts/publish_kit.sh push [--apply]
       bash scripts/publish_kit.sh release [--apply]

  인자 없이 실행하면 할 일만 출력한다. 서브커맨드는 이 순서로 돈다:
    mirror  origin master 를 fresh clone 해 이력을 필터하고 main 으로 개명한다
    scan    mirror 이력의 킷 불변식(제외 경로 · 치환 대상 0)과 gitleaks 를 검사한다
    verify  mirror 를 새로 clone 해 pub get · build_runner · analyze · 전체 Flutter 테스트 · Jest 를 돌린다
    check   공개 저장소의 main · v* 태그가 재생성한 main 의 조상인지 확인한다
    push    mirror main tip 에 태그 v<KIT_VERSION> 을 만들고 main 과 태그를 공개 저장소에 보낸다
    release CHANGELOG 의 해당 판 절을 본문으로 GitHub Release 를 만든다(rc 판은 pre-release)
  push · release 는 --apply 가 없으면 실행할 명령만 출력한다(원격 변경 0).
  rules-hash  규칙 3파일 + mirror 레시피 블록의 sha256 4줄을 출력한다(동결본 rules.sha256 재생성용)
  환경변수: KIT_PUBLISH_ORIGIN · KIT_PUBLISH_PUBLIC · KIT_PUBLISH_WORK · KIT_PUBLISH_REPO (테스트 · 리허설 대역용)
USAGE
}

# 실패 사유 한 줄을 stderr 로 내고 종료한다.
fail() {
  echo "FAIL: $1" >&2
  exit 1
}

# 인자 검사가 가장 먼저다 — push · release 만 --apply 하나를 받고, 나머지는 인자를 받지 않는다.
CMD="${1:-}"
APPLY=0
case "$CMD" in
  "" | mirror | scan | verify | check | rules-hash)
    if [ "$#" -gt 1 ]; then
      usage >&2
      exit 2
    fi
    ;;
  push | release)
    if [ "$#" -gt 2 ] || { [ "$#" -eq 2 ] && [ "$2" != "--apply" ]; }; then
      usage >&2
      exit 2
    fi
    [ "$#" -eq 2 ] && APPLY=1
    ;;
  *)
    usage >&2
    exit 2
    ;;
esac

# 저장소 루트는 스크립트 위치 기준으로 찾는다 — 어느 디렉터리에서 실행해도 같은 파일을 읽는다.
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
RULES="$ROOT/.planning/release"
SELF="$ROOT/scripts/publish_kit.sh"
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

# 단계 표시 파일 $WORK/$1.ok 의 내용이 해시 $2 와 같으면 참이다.
stamp_matches() {
  [ -f "$WORK/$1.ok" ] && [ "$(cat "$WORK/$1.ok")" = "$2" ]
}

# 인자 없음 — 사용법과 단계별 진행 상태만 출력한다. 아무것도 만들지 않는다.
# 마지막 줄은 언제나 `status: … main=<해시|none>` 한 줄이다.
show_status() {
  local main step state line
  usage
  echo ""
  echo "다음 할 일:"
  main=""
  if [ ! -f "$RULES/mirror-exclude-paths.txt" ]; then
    echo "  규칙 파일이 없는 트리(공개 mirror) — 서브커맨드는 유지보수자 전용이다"
  elif [ ! -d "$MIRROR/.git" ]; then
    echo "  아직 mirror 없음 — bash scripts/publish_kit.sh mirror 부터"
  else
    main=$(git -C "$MIRROR" rev-parse --verify -q refs/heads/main 2>/dev/null) || main=""
    if [ -z "$main" ]; then
      echo "  mirror 가 불완전하다 — bash scripts/publish_kit.sh mirror 를 다시 돌린다"
    else
      echo "  mirror main=$main"
      for step in mirror scan verify check push; do
        if stamp_matches "$step" "$main"; then
          echo "  [완료] $step"
        else
          echo "  [할 일] $step"
        fi
      done
    fi
  fi
  line="status:"
  for step in mirror scan verify check push; do
    state="-"
    if [ -n "$main" ] && stamp_matches "$step" "$main"; then
      state="ok"
    fi
    line="$line $step=$state"
  done
  echo "$line main=${main:-none}"
}

# 저장소 주소(ssh · https · 로컬 경로 · gh 의 OWNER/REPO)에서 저장소 이름만 출력한다 —
# 끝 `/` 와 `.git` 을 떼고 마지막 `/` 또는 `:` 뒤를 남긴다.
repo_name() {
  local url="${1%/}"
  url="${url%.git}"
  printf '%s\n' "${url##*[/:]}"
}

# 공개 쪽 대상 $2(이름 $1)가 private 저장소를 가리키면 FAIL 한다(원격 오인 방어).
# private 이름은 KIT_PUBLISH_ORIGIN 과 이 저장소의 origin remote 두 곳에서 얻는다 — 리허설용
# 대역 환경변수를 바꿔도 실제 private 주소를 공개 대상으로 쓰지 못하게 한다.
require_not_private() {
  local label="$1" target="$2" name private_url
  name=$(repo_name "$target")
  [ "$name" != "$(repo_name "$ORIGIN")" ] ||
    fail "$label 의 저장소 이름이 KIT_PUBLISH_ORIGIN(private)과 같다($name) — 공개 저장소 주소를 확인한다: $target"
  private_url=$(git -C "$ROOT" remote get-url origin 2>/dev/null) || private_url=""
  if [ -n "$private_url" ]; then
    [ "$name" != "$(repo_name "$private_url")" ] ||
      fail "$label 의 저장소 이름이 이 저장소의 origin(private)과 같다($name) — 공개 저장소 주소를 확인한다: $target"
  fi
}

# 공개 저장소 주소가 private origin 과 다른지 확인한다 — check · push 가 원격을 읽거나 바꾸기 전에 돈다.
require_public_target() {
  [ "$ORIGIN" != "$PUBLIC" ] ||
    fail "KIT_PUBLISH_ORIGIN 과 KIT_PUBLISH_PUBLIC 이 같다 — 공개 저장소 주소를 확인한다: $PUBLIC"
  require_not_private KIT_PUBLISH_PUBLIC "$PUBLIC"
}

# 공개 저장소에서 가져온 비교용 로컬 ref(refs/public/*)를 mirror 에서 걷어낸다.
drop_public_refs() {
  git -C "$MIRROR" for-each-ref --format='delete %(refname)' refs/public refs/public-tags |
    git -C "$MIRROR" update-ref --stdin
}

# 규칙 3파일 + mirror 레시피 블록의 sha256 4줄을 `shasum -a 256` 형식으로 출력한다.
# 경로는 저장소 루트 기준이고, 넷째 줄 이름은 scripts/publish_kit.sh#MIRROR-RECIPE 이다.
print_rules_hash() {
  local f sum begin end
  for f in mirror-exclude-paths.txt mirror-replace-text.txt mirror-replace-message.txt; do
    sum=$(shasum -a 256 < "$RULES/$f") || fail "sha256 계산 실패: .planning/release/$f"
    printf '%s  %s\n' "${sum%% *}" ".planning/release/$f"
  done
  begin=$(grep -c -x -F '# MIRROR-RECIPE-BEGIN' "$SELF") || true
  end=$(grep -c -x -F '# MIRROR-RECIPE-END' "$SELF") || true
  if [ "$begin" != 1 ] || [ "$end" != 1 ]; then
    fail "scripts/publish_kit.sh 의 mirror 레시피 표시 줄이 각 1줄이 아니다"
  fi
  sum=$(sed -n '/^# MIRROR-RECIPE-BEGIN$/,/^# MIRROR-RECIPE-END$/p' "$SELF" | shasum -a 256) ||
    fail "sha256 계산 실패: mirror 레시피 블록"
  printf '%s  %s\n' "${sum%% *}" "scripts/publish_kit.sh#MIRROR-RECIPE"
}

# mirror 레시피 — clone 옵션(입력 ref 집합) · 이력 필터 인자 · main 개명. 결정성 입력이라
# 표시 줄 사이 전체가 rules.sha256 으로 동결된다. 실패 사유는 호출부가 종료 코드로 붙인다.
run_recipe() {
# MIRROR-RECIPE-BEGIN
  git clone --quiet --no-local --branch master --single-branch --no-tags "$ORIGIN" "$MIRROR" || return 1
  ( cd "$MIRROR" && git filter-repo --paths-from-file "$RULES/mirror-exclude-paths.txt" --invert-paths --replace-text "$RULES/mirror-replace-text.txt" --replace-message "$RULES/mirror-replace-message.txt" ) > "$WORK/filter-repo.log" 2>&1 || return 2
  git -C "$MIRROR" branch -m master main || return 3
# MIRROR-RECIPE-END
}

cmd_mirror() {
  local remote local_master refs main count git_version filter_version recipe_status

  # 동결 비교가 가장 먼저다 — 규칙 · 레시피가 바뀌었으면 도구 · origin 을 보기 전에 멈춘다.
  if ! print_rules_hash | cmp -s - "$RULES/rules.sha256"; then
    fail "규칙이 동결본(rules.sha256)과 다르다 — rc.1 뒤에는 규칙을 바꾸지 않는다. rc.1 전 의도한 변경이면 bash scripts/publish_kit.sh rules-hash > .planning/release/rules.sha256"
  fi

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

  recipe_status=0
  run_recipe || recipe_status=$?
  case "$recipe_status" in
    0) ;;
    1) fail "origin clone 실패: $ORIGIN" ;;
    2) fail "이력 필터 실패 — $WORK/filter-repo.log" ;;
    *) fail "main 개명 실패" ;;
  esac

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
  # merge 커밋도 첫 부모 대비 diff 를 낸다 — `git log` 의 -p · --name-only 기본값은 merge 에서
  # 아무것도 내지 않아(--diff-merges=off) 충돌 해소 중에만 들어온 경로 · 내용이 검사 밖에 남는다.
  # 모든 커밋이 (root 는 빈 트리, merge 는 첫 부모) 대비 diff 를 내면, 어느 트리에 있는 줄 · 경로든
  # 그것을 처음 들인 커밋의 diff 에 나온다. 도달 가능한 이력만 보므로 filter-repo 가 버린 객체는
  # 검사 대상이 아니다.
  git -C "$MIRROR" -c core.quotepath=off log --all --diff-merges=first-parent --name-only --format= > "$names" ||
    fail "mirror 이력 경로 목록을 만들지 못했다"
  git -C "$MIRROR" log -p --all --diff-merges=first-parent --no-color --no-ext-diff --no-textconv --format= > "$patch" ||
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
  require_public_target

  git ls-remote "$PUBLIC" > "$WORK/public-refs.txt" 2> "$WORK/public-refs.err" ||
    fail "공개 저장소에 접근할 수 없다: $PUBLIC"
  heads=$(awk -F '\t' '$2 == "refs/heads/main" { n++ } END { print n + 0 }' "$WORK/public-refs.txt")
  tags=$(awk -F '\t' 'index($2, "refs/tags/v") == 1 { n++ } END { print n + 0 }' "$WORK/public-refs.txt")

  if [ "$heads" = 0 ]; then
    [ "$tags" = 0 ] || fail "공개 저장소에 main 없이 v* 태그만 있다 — 불일치 상태라 원인을 조사한다"
    # 첫 발행은 빈 저장소(ref 0개)일 때만이다 — main 이 없어도 다른 ref(예: private 의 master)가
    # 있으면 엉뚱한 저장소를 가리키고 있을 수 있다.
    [ ! -s "$WORK/public-refs.txt" ] ||
      fail "공개 저장소에 main 은 없는데 다른 ref 가 있다 — 빈 저장소가 아니다. 주소 · 상태를 조사한다: $PUBLIC"
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

# 명령 하나를 디렉터리 $1(verify clone) 안에서 돌려 출력(stdout + stderr)을 로그 파일 $2 에 남긴다.
# 종료 코드를 그대로 돌려준다 — 판정은 호출부가 종료 코드와 로그 문구로 한다.
run_in_clone() {
  local dir="$1" log="$2"
  shift 2
  ( cd "$dir" && "$@" ) > "$log" 2>&1
}

# D-31 — 공개 mirror 를 사용자가 받는 그대로(fresh clone) 받아 검수한다.
cmd_verify() {
  local main stamp flutter_version expected found rel golden_label summary jest_line rc v
  main=$(mirror_main)
  rm -f "$WORK/verify.ok"
  stamp=""
  [ -f "$WORK/mirror.ok" ] && stamp=$(cat "$WORK/mirror.ok")
  [ "$stamp" = "$main" ] || fail "mirror 를 이 mirror(main=$main)에서 먼저 통과해야 한다"

  command -v fvm >/dev/null 2>&1 || fail "fvm 이 PATH 에 없다"
  command -v jq >/dev/null 2>&1 || fail "jq 가 PATH 에 없다"
  command -v pnpm >/dev/null 2>&1 || fail "pnpm 이 PATH 에 없다"

  v="$WORK/verify"
  rm -rf "$v"
  git clone --quiet --no-local "$MIRROR" "$v" || fail "mirror clone 실패: $v"
  [ "$(git -C "$v" rev-parse HEAD)" = "$main" ] || fail "verify clone HEAD 가 mirror main 과 다르다"
  # 공개본에 없어야 할 것이 clone 에 있으면 검수 대상이 틀렸다(T-174-26).
  [ ! -e "$v/.planning" ] || fail "verify clone 에 .planning 이 있다 — mirror 가 공개본이 아니다"
  [ ! -e "$v/config/dev.json" ] || fail "verify clone 에 config/dev.json 이 있다 — 공개본에 실 config 가 실렸다"

  flutter_version=$(jq -r .flutter "$v/.fvmrc") || fail ".fvmrc 를 읽지 못했다"
  run_in_clone "$v" "$WORK/verify-fvm.log" fvm use "$flutter_version" --force ||
    fail "fvm use $flutter_version 실패 — $WORK/verify-fvm.log"

  # iOS golden 은 gitignore 라 clone 에 없다(RESEARCH Pitfall 10) — macOS 에서는 유지보수자가
  # sign-off 한 PNG 를 같은 상대경로로 복사해 회귀를 판정한다. 복사 대상은 이 PNG 뿐이다.
  if [ "$(uname)" = Darwin ]; then
    expected=$(git -C "$v" show HEAD:.gitignore | grep -c '_ios\.png$') || expected=0
    found=$(find "$ROOT/test" -name '*_ios.png' -not -path '*/failures/*' | wc -l | tr -d '[:space:]')
    [ "$found" = "$expected" ] ||
      fail "유지보수자 트리의 iOS golden 이 $found/$expected — macOS 에서 생성 · sign-off 뒤 다시"
    while IFS= read -r golden; do
      [ -n "$golden" ] || continue
      rel="${golden#"$ROOT"/}"
      case "$rel" in
        test/*_ios.png) ;;
        *) fail "iOS golden 경로가 예상 밖이다: $rel" ;;
      esac
      mkdir -p "$v/$(dirname "$rel")"
      cp "$golden" "$v/$rel" || fail "iOS golden 복사 실패: $rel"
    done <<EOF_GOLDENS
$(find "$ROOT/test" -name '*_ios.png' -not -path '*/failures/*')
EOF_GOLDENS
    echo "ios-goldens: copied=$expected"
    golden_label="$expected"
  else
    echo "ios-goldens: skipped (not macOS)"
    golden_label="skipped"
  fi

  run_in_clone "$v" "$WORK/verify-pubget.log" fvm flutter pub get ||
    fail "fvm flutter pub get 실패 — $WORK/verify-pubget.log"
  run_in_clone "$v" "$WORK/verify-build-runner.log" fvm dart run build_runner build --delete-conflicting-outputs ||
    fail "build_runner 실패 — $WORK/verify-build-runner.log"

  rc=0
  run_in_clone "$v" "$WORK/verify-analyze.log" fvm dart analyze || rc=$?
  grep -qF 'No issues found!' "$WORK/verify-analyze.log" ||
    fail "fvm dart analyze 결과가 No issues found! 가 아니다(exit $rc) — $WORK/verify-analyze.log"

  rc=0
  run_in_clone "$v" "$WORK/verify-test.log" fvm flutter test --no-pub || rc=$?
  if [ "$rc" != 0 ] || ! grep -qE 'All (other )?tests passed!' "$WORK/verify-test.log" ||
    grep -qF 'Some tests failed' "$WORK/verify-test.log"; then
    fail "전체 Flutter 테스트 실패(exit $rc) — $WORK/verify-test.log"
  fi
  summary=$(tr '\r' '\n' < "$WORK/verify-test.log" | grep -E 'All (other )?tests passed!' | tail -n 1 |
    grep -oE '\+[0-9]+( ~[0-9]+)?' | head -n 1) || summary="?"
  echo "flutter-tests: $summary"

  rc=0
  run_in_clone "$v" "$WORK/verify-functions.log" sh -c 'cd functions && pnpm install --frozen-lockfile && pnpm run lint && pnpm run build && pnpm test' || rc=$?
  if [ "$rc" != 0 ] || grep -qE '^Tests:.*failed' "$WORK/verify-functions.log"; then
    fail "functions install · lint · build · Jest 실패(exit $rc) — $WORK/verify-functions.log"
  fi
  jest_line=$(grep -E '^Tests:' "$WORK/verify-functions.log" | tail -n 1) ||
    fail "Jest 요약 줄(Tests:)이 없다 — $WORK/verify-functions.log"
  echo "jest: $jest_line"

  printf '%s\n' "$main" > "$WORK/verify.ok"
  echo "VERIFY OK main=$main flutter=pass jest=pass ios-goldens=$golden_label"
}

# 단계 표시가 전부 지금 mirror main 해시와 같은지 확인한다(D-29 게이트). 하나라도 다르면 FAIL.
require_stamps() {
  local main step
  main=$(mirror_main)
  for step in "$@"; do
    stamp_matches "$step" "$main" || fail "$step 를 이 mirror(main=$main)에서 먼저 통과해야 한다"
  done
}

# mirror main 의 KIT_VERSION(한 줄 semver)을 출력한다. CHANGELOG 에 그 판 절이 정확히 1개여야 한다.
read_version() {
  local ver count
  ver=$(git -C "$MIRROR" show main:KIT_VERSION 2>/dev/null) ||
    fail "KIT_VERSION 이 없다 — 릴리스 컷(유지보수자 문서 「릴리스 컷」) 먼저"
  case "$ver" in
    *$'\n'* | *$'\r'*) fail "KIT_VERSION 이 한 줄이 아니다" ;;
  esac
  printf '%s\n' "$ver" | grep -qxE '[0-9]+\.[0-9]+\.[0-9]+(-rc\.[0-9]+)?' ||
    fail "KIT_VERSION 이 판 번호 모양(X.Y.Z 또는 X.Y.Z-rc.N)이 아니다: $ver"
  count=$(git -C "$MIRROR" show main:CHANGELOG.md 2>/dev/null |
    awk -v p="## [$ver] - " 'index($0, p) == 1 && substr($0, length(p) + 1) ~ /^[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]$/ { n++ } END { print n + 0 }') ||
    fail "CHANGELOG.md 를 읽지 못했다"
  [ "$count" = 1 ] || fail "CHANGELOG.md 에 ## [$ver] - YYYY-MM-DD 절이 정확히 1개가 아니다($count) — 릴리스 컷 먼저"
  printf '%s\n' "$ver"
}

# D-24 · D-29 — 게이트를 통과한 mirror main 과 태그 v<ver> 를 공개 저장소에 보낸다.
cmd_push() {
  local main ver release_tag local_commit remote_refs remote_commit create_tag send_tag
  local -a refspecs
  main=$(mirror_main)
  require_public_target
  require_stamps mirror scan verify check
  ver=$(read_version)
  release_tag="v$ver"
  [ "$APPLY" = 1 ] && rm -f "$WORK/push.ok"

  # 태그 대상은 mirror main tip 이다(RESEARCH Pitfall 4). 이미 있는 태그는 옮기지 않는다.
  create_tag=1
  if local_commit=$(git -C "$MIRROR" rev-parse --verify -q "refs/tags/$release_tag^{commit}"); then
    [ "$local_commit" = "$main" ] ||
      fail "mirror 의 $release_tag 가 main 이 아닌 커밋($local_commit)을 가리킨다 — 원인을 조사한다"
    create_tag=0
  fi

  remote_refs="$WORK/push-public-refs.txt"
  git ls-remote "$PUBLIC" > "$remote_refs" 2> "$WORK/push-public-refs.err" ||
    fail "공개 저장소에 접근할 수 없다: $PUBLIC"
  remote_commit=$(awk -F '\t' -v r="refs/tags/$release_tag" '$2 == r "^{}" { p = $1 } $2 == r { d = $1 } END { print (p != "" ? p : d) }' "$remote_refs")
  send_tag=1
  if [ -n "$remote_commit" ]; then
    [ "$remote_commit" = "$main" ] ||
      fail "공개 저장소의 $release_tag 가 다른 커밋($remote_commit)을 가리킨다 — 태그를 옮기지 않는다. 원인을 조사한다"
    create_tag=0
    send_tag=0
    echo "공개 저장소에 $release_tag 가 이미 같은 커밋에 있다 — 태그 push 를 건너뛴다"
  fi

  # main 과 태그는 한 번의 원자 push 로 보낸다 — 둘 중 하나라도 거부되면 둘 다 반영되지 않아
  # 공개 main 이 어느 v* 태그와도 다른 커밋에 머무는 창(D-24 위반)이 생기지 않는다.
  refspecs=(main:refs/heads/main)
  [ "$send_tag" = 1 ] && refspecs+=("refs/tags/$release_tag:refs/tags/$release_tag")

  if [ "$APPLY" != 1 ]; then
    [ "$create_tag" = 1 ] && echo "command: git -C $MIRROR tag -a $release_tag -m $release_tag main"
    echo "command: git -C $MIRROR push --atomic $PUBLIC ${refspecs[*]}"
    echo "실제로 발행하려면: bash scripts/publish_kit.sh push --apply"
    echo "DRY-RUN OK push tag=$release_tag main=$main"
    return 0
  fi

  if [ "$create_tag" = 1 ]; then
    echo "command: git -C $MIRROR tag -a $release_tag -m $release_tag main"
    git -C "$MIRROR" tag -a "$release_tag" -m "$release_tag" main || fail "태그 $release_tag 생성 실패"
  fi
  echo "command: git -C $MIRROR push --atomic $PUBLIC ${refspecs[*]}"
  git -C "$MIRROR" push --atomic "$PUBLIC" "${refspecs[@]}" ||
    fail "공개 main · 태그 push 실패(원자 push 라 둘 다 반영되지 않았다) — 공개 main 이 새 main 의 조상이 아니면 git 이 거부한다. check 부터 다시"
  printf '%s\n' "$main" > "$WORK/push.ok"
  echo "PUSH OK tag=$release_tag main=$main"
}

# D-22 — CHANGELOG 의 해당 판 절만 잘라 notes 파일로 만들고 GitHub Release 를 만든다.
cmd_release() {
  local ver release_tag notes repo
  require_stamps push
  ver=$(read_version)
  release_tag="v$ver"
  notes="$WORK/release-notes-$ver.md"
  # 절 머리 다음 줄부터 다음 `## [` 줄 전까지 — 맨 아래 비교 링크 정의(`[x]: url`)는 뺀다.
  git -C "$MIRROR" show main:CHANGELOG.md |
    awk -v p="## [$ver] - " 'index($0, p) == 1 { on = 1; next } on && index($0, "## [") == 1 { exit } on && /^\[[^]]+\]: / { next } on { print }' > "$notes" ||
    fail "CHANGELOG.md 에서 $ver 절을 자르지 못했다"
  grep -q '^### ' "$notes" || fail "CHANGELOG 의 $ver 절에 ### 소절이 없다 — $notes"
  repo="${KIT_PUBLISH_REPO:-woodkill/flutter-firebase-starter-kit}"
  require_not_private KIT_PUBLISH_REPO "$repo"

  if [ "$APPLY" != 1 ]; then
    case "$ver" in
      *-rc.*) echo "command: gh release create $release_tag --repo $repo --verify-tag --prerelease --title $release_tag --notes-file $notes" ;;
      *) echo "command: gh release create $release_tag --repo $repo --verify-tag --title $release_tag --notes-file $notes" ;;
    esac
    echo "실제로 만들려면: bash scripts/publish_kit.sh release --apply"
    echo "DRY-RUN OK release tag=$release_tag"
    return 0
  fi

  command -v gh >/dev/null 2>&1 || fail "gh 가 PATH 에 없다 — 설치: brew install gh · 로그인: gh auth login"
  case "$ver" in
    *-rc.*)
      echo "command: gh release create $release_tag --repo $repo --verify-tag --prerelease --title $release_tag --notes-file $notes"
      gh release create "$release_tag" --repo "$repo" --verify-tag --prerelease --title "$release_tag" --notes-file "$notes" ||
        fail "gh release create 실패"
      ;;
    *)
      echo "command: gh release create $release_tag --repo $repo --verify-tag --title $release_tag --notes-file $notes"
      gh release create "$release_tag" --repo "$repo" --verify-tag --title "$release_tag" --notes-file "$notes" ||
        fail "gh release create 실패"
      ;;
  esac
  echo "RELEASE OK tag=$release_tag"
}

if [ -z "$CMD" ]; then
  show_status
  exit 0
fi

require_rules

case "$CMD" in
  mirror) cmd_mirror ;;
  scan) cmd_scan ;;
  verify) cmd_verify ;;
  check) cmd_check ;;
  push) cmd_push ;;
  release) cmd_release ;;
  rules-hash) print_rules_hash ;;
esac
