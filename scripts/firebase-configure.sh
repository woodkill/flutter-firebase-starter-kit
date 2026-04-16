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

PROJECT_ID="${PROJECT_ID_PREFIX}-${FLAVOR}"
IOS_BUNDLE_ID="${IOS_BUNDLE_ID_PREFIX}.${FLAVOR}"
ANDROID_PACKAGE="${ANDROID_PACKAGE_PREFIX}.${FLAVOR}"

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

echo ""
echo "✓ Firebase configure complete for ${FLAVOR}"
