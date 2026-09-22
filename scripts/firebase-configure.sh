#!/usr/bin/env bash
#
# Flavor별 Firebase 설정 파일 자동 생성 wrapper.
#
# 표준 명령을 박제하여 starter-kit 의 flavor 분리 메커니즘 (Phase 02) 과
# FlutterFire CLI 의 default 동작 충돌을 영구 차단한다.
#
# 핵심 옵션:
#   --ios-out=ios/config/<flavor>/GoogleService-Info.plist
#       → Xcode Runner 그룹 정적 등록 회피, flavor 경로 직접 출력
#   --ios-build-config=Debug-<flavor>
#       → --ios-out 을 주면서 build configuration / target 중 무엇을 쓸지 알려주지
#         않으면 CLI 가 선택 프롬프트를 띄운다. --yes 는 덮어쓰기 확인만 처리하고
#         이 프롬프트는 막지 못해, 비대화형(비-TTY) 실행이 그대로 멈춘다.
#         값은 ios/Runner.xcodeproj 에 실재하는 configuration 이어야 한다
#         (Debug-dev / Debug-stg / Debug-prod).
#       → ⚠ 부수효과 (2026-09-11 실측): 이 옵션을 주면 flutterfire 가 요청하지 않은
#         파일 2종을 함께 변형한다.
#           1) ios/Runner.xcodeproj/project.pbxproj
#              · bundle-service-file 실행 스크립트 단계를 새로 추가한다 — 본 프로젝트는
#                이미 Copy GoogleService-Info.plist 단계가 $CONFIGURATION 접미사로
#                ios/config/<flavor>/ 를 복사하므로 중복이다.
#              · 기존 upload-crashlytics-symbols 단계의 마지막 인자를
#                --default-config=default 에서 --build-configuration=$CONFIGURATION
#                으로 바꾼다. firebase.json 에는 Debug-<flavor> 한 개만 등록되므로
#                나머지 8개 configuration 의 iOS 빌드가 그 단계에서 실패한다.
#           2) firebase.json — 한 줄로 재작성되고 buildConfigurations 기록이 추가된다.
#                이 프로젝트 빌드는 읽지 않는 CLI 내부 기록이다.
#         → 이 스크립트는 두 파일을 flutterfire 호출 직전에 스냅샷해 두고, 호출 후
#           (실패한 경우도 포함) 자동으로 되돌린다. 수동 fff configure 로 실행하면
#           직접 되돌려야 한다. plist/dart options 는 --ios-out/--out 경로에 정상 생성된다.
#   --android-out=android/app/src/<flavor>/google-services.json
#       → Android source set 경로 직접 출력
#   --platforms=android,ios
#       → web 플랫폼 자동 등록 회피 (모바일 only 정책)
#   --yes
#       → 덮어쓰기 확인 자동 응답
#
# 전제조건 (macOS):
#   ruby 에 xcodeproj gem 이 설치돼 있어야 한다 — FlutterFire CLI 가
#   --ios-build-config 을 검증할 때 ruby 로 Runner.xcodeproj 를 읽는다.
#   확인: ruby -e "require 'xcodeproj'"   설치: gem install xcodeproj
#   (CocoaPods 가 벤더링한 xcodeproj 는 gem 경로에 없어 인식되지 않는다)
#   이 전제조건의 주체는 flutterfire CLI 의 ruby gem 의존이지 프로젝트의 의존성
#   관리자가 아니다 — 이 킷의 iOS 는 SPM 이라 CocoaPods 설치가 필요 없고, 위
#   벤더링 함정은 CocoaPods 를 따로 설치해 둔 머신에만 해당한다 (Phase 16.3).
#
# 사용법:
#   ./scripts/firebase-configure.sh dev
#   ./scripts/firebase-configure.sh stg
#   ./scripts/firebase-configure.sh prod
#
#   DRY_RUN=1 ./scripts/firebase-configure.sh prod
#       → flutterfire 호출만 건너뛰고 식별자 계산 + skip-worktree 후처리만 실행
#         (네트워크·Firebase 인증 불필요, 검증용)
#         (스냅샷·복원·dart 포맷 후처리도 함께 건너뛴다 — 변형 원인이 없다)
#
# starter-kit 정책:
#   기본 상태에서는 dev flavor 만 실제 Firebase 프로젝트가 연결된다.
#   stg/prod 는 placeholder 이며, fork 후 별도 Firebase 프로젝트 생성 필요.
#
# starter-kit fork 후 수정 사항:
#   아래 3개 prefix 상수를 자신의 프로젝트 식별자에 맞게 변경할 것.

set -euo pipefail

FLAVOR="${1:-}"
if [[ -z "$FLAVOR" ]]; then
  echo "Usage: $0 <dev|stg|prod>" >&2
  exit 1
fi

if [[ ! "$FLAVOR" =~ ^(dev|stg|prod)$ ]]; then
  echo "Error: invalid flavor '$FLAVOR' (must be dev, stg, or prod)" >&2
  exit 1
fi

# === starter-kit fork 시 아래 3개 prefix 를 자신의 프로젝트에 맞게 수정 ===
PROJECT_ID_PREFIX="slimpumpkin-starter-kit"
IOS_BUNDLE_ID_PREFIX="com.slimpumpkin.flutterStarterKit"
ANDROID_PACKAGE_PREFIX="com.slimpumpkin.flutter_starter_kit"
# =======================================================================

# prod 만 앱 식별자에 flavor 접미사가 없다.
#   진실원 1 — android/app/build.gradle.kts productFlavors:
#     create("dev")  { applicationIdSuffix = ".dev" }
#     create("stg")  { applicationIdSuffix = ".stg" }
#     create("prod") { /* prod는 suffix 없음 */ }
#   진실원 2 — ios/Flutter/prod.example.xcconfig:
#     PRODUCT_BUNDLE_IDENTIFIER = com.slimpumpkin.flutterStarterKit
# 여기에 ".prod" 를 붙이면 flutterfire 가 잘못된 식별자로 앱을 등록하고,
# 생성된 google-services.json 이 Gradle 에서 "No matching client found for
# package name" 으로 빌드를 깨뜨린다.
# 반면 PROJECT_ID 는 Firebase 프로젝트를 3개로 분리하는 정책이므로 prod 에도
# flavor 접미사를 유지한다.
if [[ "$FLAVOR" == "prod" ]]; then
  APP_ID_SUFFIX=""
else
  APP_ID_SUFFIX=".${FLAVOR}"
fi

PROJECT_ID="${PROJECT_ID_PREFIX}-${FLAVOR}"
IOS_BUNDLE_ID="${IOS_BUNDLE_ID_PREFIX}${APP_ID_SUFFIX}"
ANDROID_PACKAGE="${ANDROID_PACKAGE_PREFIX}${APP_ID_SUFFIX}"

OUT_DART="lib/core/firebase/firebase_options_${FLAVOR}.dart"
OUT_IOS="ios/config/${FLAVOR}/GoogleService-Info.plist"
OUT_ANDROID="android/app/src/${FLAVOR}/google-services.json"

# FlutterFire CLI 가 --ios-build-config 과 함께 **요청하지 않아도** 변형하는 파일 2종.
# 산출물(plist · google-services.json · dart options)은 여기에 넣지 않는다 —
# 그건 이 스크립트가 만들어야 하는 결과물이다.
CLI_TOUCHED_PBXPROJ="ios/Runner.xcodeproj/project.pbxproj"
CLI_TOUCHED_FIREBASE_JSON="firebase.json"

# 스냅샷 디렉터리. set -u 아래이므로 빈 값으로 초기화해 둔다 (DRY_RUN 경로에서는
# 끝까지 빈 값 → 복원 함수가 즉시 return).
SNAP_DIR=""

# 스냅샷 1건 되돌리기. 내용이 같으면 아무 것도 하지 않는다(조용한 성공).
restore_one_file() {
  local target="$1"
  local snap="${SNAP_DIR}/$2"
  local reason="$3"
  [ -f "$snap" ] || return 0
  [ -f "$target" ] || return 0
  if cmp -s "$snap" "$target"; then
    return 0
  fi
  cp "$snap" "$target"
  echo "  ↩ 복원: ${target}"
  echo "     이유: ${reason}"
}

# flutterfire 호출 후 부수효과를 되돌린다.
#   · EXIT trap 으로도 불린다 — flutterfire 가 실패하면 set -e 가 그 자리에서
#     스크립트를 끝내므로 명시 호출에 도달하지 못한다.
#   · 멱등하다 — 한 번 돌면 SNAP_DIR 을 비워 두 번째 호출은 즉시 return.
#   · 스크립트의 원래 종료 코드를 보존한다 (local rc=$? / return "$rc").
#     보존하지 않으면 flutterfire 실패가 rc=0 으로 둔갑한다.
restore_cli_side_effects() {
  local rc=$?
  [ -n "${SNAP_DIR:-}" ] || return "$rc"
  restore_one_file "$CLI_TOUCHED_PBXPROJ" "project.pbxproj" \
    'bundle-service-file 단계가 중복 추가되고, crashlytics 단계 인자가 --build-configuration=${CONFIGURATION} 로 바뀌어 firebase.json 에 없는 8개 configuration 의 iOS 빌드가 깨진다'
  restore_one_file "$CLI_TOUCHED_FIREBASE_JSON" "firebase.json" \
    'CLI 내부 기록용 파일이며 이 프로젝트 빌드는 읽지 않는다 (위 단계와 flutterfire reconfigure 만 사용)'
  rm -rf "$SNAP_DIR"
  SNAP_DIR=""
  return "$rc"
}

cat <<EOF
▶ Firebase configure for flavor: ${FLAVOR}
  project:       ${PROJECT_ID}
  iOS bundle:    ${IOS_BUNDLE_ID}
  Android pkg:   ${ANDROID_PACKAGE}
  Dart out:      ${OUT_DART}
  iOS plist:     ${OUT_IOS}
  Android json:  ${OUT_ANDROID}

EOF

if [[ "$FLAVOR" != "dev" ]]; then
  cat <<EOF
⚠ starter-kit 기본 상태에서는 'dev' flavor 만 실제 Firebase 프로젝트가
  연결되어 있다. '${FLAVOR}' 실행 전 Firebase Console 에서 프로젝트
  '${PROJECT_ID}' 를 먼저 생성했는지 확인할 것.

EOF
fi

# DRY_RUN=1 이면 flutterfire 호출만 건너뛴다.
#
# 용도: 네트워크·Firebase 인증 없이 (1) 위에서 계산한 식별자가 gradle
# applicationId · xcconfig bundle id 와 일치하는지 (2) 아래 skip-worktree
# 후처리가 tracked 산출물 전부에 걸리는지 검증하기 위한 것.
# set -euo pipefail 아래이므로 반드시 ${DRY_RUN:-0} 형태로 읽는다 — 맨 이름으로
# 읽으면 미설정 환경에서 unbound variable 로 죽는다. 미설정 시 동작은 종전과
# 완전히 동일하다.
#
# 주의: DRY_RUN 실행도 skip-worktree 는 실제로 건다. 검증 후에는
# `git update-index --no-skip-worktree <path>` 로 해제할 것.
if [[ "${DRY_RUN:-0}" == "1" ]]; then
  echo "⏭ DRY_RUN=1 — flutterfire configure 호출을 건너뛴다 (후처리는 실행)."
  echo "⏭ DRY_RUN=1 — ruby xcodeproj 전제조건 검사도 건너뛴다 (flutterfire 미호출)."
  echo "⏭ DRY_RUN=1 — pbxproj/firebase.json 스냅샷·복원과 dart 포맷 후처리도 건너뛴다."
  echo ""
else
  # 전제조건 — FlutterFire CLI 는 --ios-build-config 값이 실재하는지 확인하려고
  # ruby + xcodeproj gem 으로 ios/Runner.xcodeproj 를 파싱한다. CLI 는 PATH 의 첫
  # ruby 를 그대로 쓰며 플래그로 바꿀 수 없다. gem 이 없으면 LoadError 로 죽으므로
  # **산출물을 하나도 건드리기 전에** 여기서 끊고 해결법을 안내한다.
  if ! ruby -e "require 'xcodeproj'" >/dev/null 2>&1; then
    cat >&2 <<EOF
✗ ruby 의 'xcodeproj' gem 을 찾을 수 없다 (ruby: $(command -v ruby || echo '미설치')).

  FlutterFire CLI 는 --ios-build-config 검증에 이 gem 을 사용한다. 없으면 CLI 가
  LoadError 로 실패하므로 configure 를 시작하지 않는다. 생성된 파일은 없다.

  해결 (둘 중 하나):
    1) gem install xcodeproj
    2) xcodeproj 가 이미 설치된 ruby 를 PATH 앞에 두고 재실행
       예: PATH="/usr/bin:\$PATH" $0 ${FLAVOR}

  확인: ruby -e "require 'xcodeproj'" 가 아무 출력 없이 끝나면 준비 완료.
EOF
    exit 1
  fi

  # FlutterFire CLI 는 아래 호출에서 pbxproj 와 firebase.json 을 함께 변형한다
  # (2026-09-11 실측). 요청한 산출물이 아니므로 실행 직전 스냅샷을 떠 둔다.
  # trap 을 **여기서** 건다 — 전제조건 실패(exit 1)는 스냅샷 이전이라 복원할 것이 없고,
  # 여기부터는 flutterfire 가 죽어도 EXIT 경로로 복원된다.
  SNAP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/firebase-configure-XXXXXX")"
  trap restore_cli_side_effects EXIT
  for SNAP_SRC in "$CLI_TOUCHED_PBXPROJ" "$CLI_TOUCHED_FIREBASE_JSON"; do
    if [ -f "$SNAP_SRC" ]; then
      cp "$SNAP_SRC" "${SNAP_DIR}/$(basename "$SNAP_SRC")"
    fi
  done

  # FVM Dart 경유로 flutterfire CLI 실행 (시스템 PATH 미오염, FVM 정책 준수)
  fvm dart pub global run flutterfire_cli:flutterfire configure \
    --project="${PROJECT_ID}" \
    --out="${OUT_DART}" \
    --ios-bundle-id="${IOS_BUNDLE_ID}" \
    --android-package-name="${ANDROID_PACKAGE}" \
    --platforms=android,ios \
    --ios-out="${OUT_IOS}" \
    --ios-build-config="Debug-${FLAVOR}" \
    --android-out="${OUT_ANDROID}" \
    --yes

  # 부수효과 되돌림 — 성공 경로에서는 여기서 끝난다(안내가 ✓ 완료 줄보다 먼저 찍히도록).
  # 실패 경로는 위 EXIT trap 이 같은 함수를 부른다.
  restore_cli_side_effects

  # flutterfire 출력은 dart format 이 적용돼 있지 않다 (긴 client id 한 줄 + 파일 끝
  # newline 없음). 이대로 두면 프로젝트 포맷 게이트가 rc=1 로 깨진다.
  fvm dart format "$OUT_DART"
fi

# 생성된 산출물 중 **tracked 인 것 전부**에 skip-worktree 를 적용한다.
#
# tracked placeholder 목록은 세 계열이다 — Dart options 3종 + Android json
# 2종(.gitignore negation 예외) + **iOS plist 3종(dev 포함)**. iOS plist 는
# .gitignore 무시 대상이 아니라 그냥 tracked 다. 재생성된 실제 키 파일이
# 그대로 `git status` 에 뜨고 실수로 커밋될 수 있으므로, skip-worktree 로
# index 의 placeholder 내용을 유지한 채 로컬 수정본을 무시하게 만든다.
#
# dev 도 예외가 아니다(quick 260911-twn): dev 의 iOS plist
# (ios/config/dev/GoogleService-Info.plist)는 **커밋된 내용이 placeholder**이고,
# 개발자의 실제 dev plist 는 커밋되지 않는 **로컬 전용 skip-worktree 사본**으로만
# 존재한다 — 그 사본을 만들어 주는 것이 바로 이 스크립트
# (`./scripts/firebase-configure.sh dev`)다. 따라서 아래 루프는 dev 에서도 반드시
# 걸려야 한다. placeholder 자체를 의도적으로 갱신해 커밋하려면 먼저
# skip-worktree 를 해제해야 한다.
#
# 단점: placeholder 가 upstream 에서 변경되면 `git pull` 이 충돌하고
# `git stash` 가 에러를 낸다. 그 경우 `git update-index --no-skip-worktree
# <path>` 로 일시 해제 후 다시 적용할 것.
#
# bash 3.2 호환 — mapfile 미사용, 위치 인자 for 루프로 순회.
for OUT_PATH in "$OUT_DART" "$OUT_IOS" "$OUT_ANDROID"; do
  if git ls-files --error-unmatch "$OUT_PATH" >/dev/null 2>&1; then
    git update-index --skip-worktree "$OUT_PATH" || true
    echo "  · git update-index --skip-worktree ${OUT_PATH}"
  fi
done

echo ""
echo "✓ Firebase configure complete for ${FLAVOR}"
