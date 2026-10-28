#!/usr/bin/env bash
# 릴리스 컷의 사용자 조치 판정 — 두 커밋 사이에서 사용자 소유 표면 `낮음` 행 파일의 변경을 찾는다.
#
# 목적:
#   CHANGELOG 판 번호 규칙의 MAJOR 기준 가운데 「사용자 소유 표면 표에서 킷이 고칠 가능성이
#   `낮음` 인 파일의 변경」 하나를 두 커밋 사이에서 판정한다. 나머지 기준(「충돌 시 조치」 칸
#   밖의 손질 · 콘솔 재설정 · 데이터 마이그레이션)은 사람이 정한다.
#
# 사용법:
#   bash scripts/release_user_action.sh <BASE> <TARGET>
#   릴리스 컷 때는 BASE = 직전 컷(`git log -1 --format=%H -- KIT_VERSION`), TARGET = `HEAD` 다.
#   커밋을 가리키는 이름이면 무엇이든 받는다(해시 · 태그 · `HEAD~1` 등).
#
# 출력 계약 (stdout · 이 순서 · 다른 줄 없음):
#   BASE <40자 해시>
#   TARGET <40자 해시>
#   CHANGED <경로>                         # 바뀐 경로마다(작업 일지 디렉터리 제외) · 0줄 가능
#   LOW_ROWS <번호 공백 구분 오름차순>      # 예: LOW_ROWS 3 5 8 14 15 16 22 28
#   LOW_ROW_CONTROL row=<행> n=<수> <ERE>   # LOW_PATTERNS 한 줄마다, 그 뒤에 그 꼴의 LOW_ROW_HIT 줄들
#   LOW_ROW_HIT row=<행> <경로>
#   OTHER_ROW_HIT row=<행> <경로>           # INFO_PATTERNS 일치(기록만)
#   LOW_ROW_HITS <N>
#   USER_ACTION_VERDICT none low_hits=0     # 또는 USER_ACTION_VERDICT review low_hits=<N>
#
# exit:
#   0 = 판정 출력(마지막 줄 USER_ACTION_VERDICT …)
#   3 = 마지막 stdout 줄 `LOW_ROW_FAIL git: <사유>` | `LOW_ROW_FAIL table: <사유>` |
#       `LOW_ROW_FAIL control: row=<행> <ERE>`
#   2 = 인자 오류 — stderr usage(첫 줄 `usage: bash scripts/release_user_action.sh <BASE> <TARGET>`) ·
#       stdout 0 바이트
#
# 안전 계약:
#   - 읽기 전용이다 — `git rev-parse` · `git diff` · `git show` · `git ls-tree` 만 부르고 원격에
#     접근하지 않으며 파일을 쓰지 않는다.
#   - 작업 트리 · 인덱스가 아니라 두 커밋만 본다. 표도 TARGET 커밋의 `docs/guide.md` 에서 읽는다.
#   - 출력은 경로 · 행 번호 · 해시뿐이고 파일 내용을 내지 않는다.
#   - 인자는 먼저 40자 커밋 해시로 풀고, 이후 git 호출은 그 두 해시만 쓴다.
#
# 경로 꼴 갱신:
#   표의 `낮음` 행이 바뀌면 이 스크립트가 exit 3 으로 멈춘다 — `LOW_PATTERNS` · `INFO_PATTERNS` 와
#   `test/release/release_user_action_script_test.dart` 를 함께 고친다. 시험이 두 블록을 heredoc
#   구분 줄(`LOW_PATTERNS_END` · `INFO_PATTERNS_END`)로 읽으므로 변수 이름과 구분 줄을 바꾸지 않는다.
#   블록 안은 `<행 번호> <ERE>` 줄만 둔다(빈 줄 · 주석 없음).

set -uo pipefail

# 표의 절 제목 — 이 줄부터 다음 `## ` · `### ` 제목 전까지만 표로 읽는다.
readonly SECTION_HEADING='### 사용자 소유 표면'

# 표의 `낮음` 행 파일 경로 꼴(행 번호 · ERE).
LOW_PATTERNS=$(cat <<'LOW_PATTERNS_END'
3 ^lib/core/firebase/firebase_options_(dev|stg|prod)\.dart$
3 ^ios/config/[^/]+/GoogleService-Info\.plist$
3 ^android/app/src/(stg|prod)/google-services\.json$
5 ^\.firebaserc$
8 ^android/app/src/main/kotlin/.*\.kt$
14 ^flutter_native_splash\.yaml$
14 ^assets/images/splash/logo(_dark)?\.png$
15 ^android/app/src/main/res/drawable[^/]*/launch_background\.xml$
15 ^android/app/src/main/res/values[^/]*/styles\.xml$
15 ^ios/Runner/Assets\.xcassets/LaunchImage\.imageset/
15 ^ios/Runner/Base\.lproj/LaunchScreen\.storyboard$
16 ^android/app/src/main/res/mipmap-[^/]+/ic_launcher\.png$
16 ^ios/Runner/Assets\.xcassets/AppIcon\.appiconset/
22 ^android/app/src/main/res/drawable/ic_notification\.xml$
22 ^android/app/src/main/res/values/colors\.xml$
22 ^lib/features/notifications/data/local_notifications_service\.dart$
28 ^ios/Runner/Runner\.entitlements$
LOW_PATTERNS_END
)

# 표의 `중간` · `높음` 행 가운데 기록만 하는 파일 경로 꼴(행 번호 · ERE).
INFO_PATTERNS=$(cat <<'INFO_PATTERNS_END'
7 ^android/app/build\.gradle\.kts$
10 ^(ios/Flutter/[^/]+\.example\.xcconfig|config/[^/]+\.example\.json)$
23 ^ios/Runner/(Info\.plist|[^/]+\.lproj/InfoPlist\.strings)$
24 ^android/app/src/main/AndroidManifest\.xml$
32 ^(KIT_VERSION|CHANGELOG\.md|LICENSE|CONTRIBUTING\.md|setup\.sh|bin/setup\.dart)$|^(\.github|tool/setup)/
INFO_PATTERNS_END
)

# 사용법을 stderr 로 낸다(stdout 에는 아무것도 내지 않는다).
print_usage() {
  {
    echo 'usage: bash scripts/release_user_action.sh <BASE> <TARGET>'
    echo '  BASE   : 직전 컷 커밋(릴리스 컷 때는 git log -1 --format=%H -- KIT_VERSION)'
    echo '  TARGET : 판정할 커밋(릴리스 컷 때는 HEAD)'
    echo '  두 인자 모두 비어 있지 않은 커밋 이름이어야 한다.'
  } >&2
}

# 실패 한 줄(LOW_ROW_FAIL <종류>: <사유>)을 stdout 으로 내고 exit 3 으로 멈춘다.
fail_verdict() {
  echo "LOW_ROW_FAIL $1: $2"
  exit 3
}

# 커밋 이름 하나를 40자 커밋 해시로 풀어 stdout 으로 낸다(실패면 exit 1).
resolve_commit() {
  git rev-parse --verify --quiet --end-of-options "$1^{commit}"
}

# 블록(<행> <ERE> 줄들)의 행 번호를 오름차순 · 중복 제거 · 공백 하나로 이어 낸다.
collect_block_rows() {
  printf '%s\n' "$1" | awk 'NF{print $1}' | LC_ALL=C sort -nu | paste -sd' ' -
}

# TARGET 표 문자열에서 절 범위 안의 `낮음` 행 번호를 낸다(절 제목이 없으면 exit 4).
collect_low_rows() {
  printf '%s\n' "$1" | LC_ALL=C awk -F'|' -v heading="$SECTION_HEADING" '
    !inside && $0 == heading { inside = 1; found = 1; next }
    inside && (/^## / || /^### /) { inside = 0 }
    inside && /^\| [0-9]+ \|/ {
      grade = $5
      sub(/^ +/, "", grade)
      if (index(grade, "낮음") == 1) {
        row = $2
        gsub(/ /, "", row)
        print row
      }
    }
    END { if (!found) exit 4 }
  '
}

# 빈 인자는 usage 로 막는다 — 직전 컷이 없으면 $(git log …) 가 빈 문자열이 되기 때문이다.
if [ "$#" -ne 2 ] || [ -z "$1" ] || [ -z "$2" ]; then
  print_usage
  exit 2
fi

# pathspec 이 언제나 저장소 루트 기준이 되게 루트로 옮긴다.
TOPLEVEL=$(git rev-parse --show-toplevel 2>/dev/null) || fail_verdict git "저장소 루트를 찾지 못했다"
cd "$TOPLEVEL" || fail_verdict git "저장소 루트로 옮기지 못했다"

BASE_SHA=$(resolve_commit "$1") || fail_verdict git "BASE 커밋을 풀지 못했다: $1"
echo "BASE $BASE_SHA"
TARGET_SHA=$(resolve_commit "$2") || fail_verdict git "TARGET 커밋을 풀지 못했다: $2"
echo "TARGET $TARGET_SHA"

CHANGED_PATHS=$(git -c core.quotePath=false diff --no-color --no-renames --name-only \
  "$BASE_SHA" "$TARGET_SHA" -- . ':!.planning') || fail_verdict git "두 커밋의 diff 를 읽지 못했다"
while IFS= read -r changed_path; do
  [ -n "$changed_path" ] || continue
  echo "CHANGED $changed_path"
done <<<"$CHANGED_PATHS"

GUIDE_TEXT=$(git show "$TARGET_SHA:docs/guide.md" 2>/dev/null) ||
  fail_verdict table "TARGET 의 docs/guide.md 를 읽지 못했다"
TABLE_ROWS=$(collect_low_rows "$GUIDE_TEXT") ||
  fail_verdict table "TARGET 의 docs/guide.md 에 「$SECTION_HEADING」 줄이 없다"
LOW_ROWS=$(printf '%s\n' "$TABLE_ROWS" | awk 'NF' | LC_ALL=C sort -nu | paste -sd' ' -)
echo "LOW_ROWS $LOW_ROWS"

SCRIPT_ROWS=$(collect_block_rows "$LOW_PATTERNS")
if [ "$LOW_ROWS" != "$SCRIPT_ROWS" ]; then
  fail_verdict table "표의 낮음 행 = ${LOW_ROWS:-없음} · 스크립트의 행 = ${SCRIPT_ROWS:-없음}"
fi

TRACKED_PATHS=$(git -c core.quotePath=false ls-tree -r --name-only "$TARGET_SHA") ||
  fail_verdict git "TARGET 의 추적 파일 목록을 읽지 못했다"

HITS=0
while read -r row pattern; do
  [ -n "$row" ] || continue
  control_count=$(LC_ALL=C command grep -cE -e "$pattern" <<<"$TRACKED_PATHS" || true)
  control_count=${control_count:-0}
  echo "LOW_ROW_CONTROL row=$row n=$control_count $pattern"
  if [ "$control_count" -lt 1 ]; then
    fail_verdict control "row=$row $pattern"
  fi
  while IFS= read -r hit_path; do
    [ -n "$hit_path" ] || continue
    echo "LOW_ROW_HIT row=$row $hit_path"
    HITS=$((HITS + 1))
  done < <(LC_ALL=C command grep -E -e "$pattern" <<<"$CHANGED_PATHS" || true)
done <<<"$LOW_PATTERNS"

while read -r row pattern; do
  [ -n "$row" ] || continue
  while IFS= read -r info_path; do
    [ -n "$info_path" ] || continue
    echo "OTHER_ROW_HIT row=$row $info_path"
  done < <(LC_ALL=C command grep -E -e "$pattern" <<<"$CHANGED_PATHS" || true)
done <<<"$INFO_PATTERNS"

echo "LOW_ROW_HITS $HITS"
if [ "$HITS" -eq 0 ]; then
  echo "USER_ACTION_VERDICT none low_hits=0"
else
  echo "USER_ACTION_VERDICT review low_hits=$HITS"
fi
exit 0
