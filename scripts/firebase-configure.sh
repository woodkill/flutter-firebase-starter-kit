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
#   --android-out=android/app/src/<flavor>/google-services.json
#       → Android source set 경로 직접 출력
#   --platforms=android,ios
#       → web 플랫폼 자동 등록 회피 (모바일 only 정책)
#   --yes
#       → 덮어쓰기 확인 자동 응답
#
# 사용법:
#   ./scripts/firebase-configure.sh dev
#   ./scripts/firebase-configure.sh stg
#   ./scripts/firebase-configure.sh prod
#
#   DRY_RUN=1 ./scripts/firebase-configure.sh prod
#       → flutterfire 호출만 건너뛰고 식별자 계산 + skip-worktree 후처리만 실행
#         (네트워크·Firebase 인증 불필요, 검증용)
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
  echo ""
else
  # FVM Dart 경유로 flutterfire CLI 실행 (시스템 PATH 미오염, FVM 정책 준수)
  fvm dart pub global run flutterfire_cli:flutterfire configure \
    --project="${PROJECT_ID}" \
    --out="${OUT_DART}" \
    --ios-bundle-id="${IOS_BUNDLE_ID}" \
    --android-package-name="${ANDROID_PACKAGE}" \
    --platforms=android,ios \
    --ios-out="${OUT_IOS}" \
    --android-out="${OUT_ANDROID}" \
    --yes
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
