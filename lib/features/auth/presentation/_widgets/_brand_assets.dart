// Phase 13.1 — see ROADMAP.md (D-74 sentinel detection 단일 진실원)

/// Brand asset sentinel detection 단일 진실원 — Phase 13.1 (D-74).
///
/// `lib/features/auth/presentation/_widgets/branded_social_button.dart` 의
/// `BrandedSocialButton.build()` 가 본 list 를 참조해 fallback 분기.
/// `test/features/auth/presentation/_widgets/brand_assets_lint_test.dart`
/// 가 동일 list 를 import 해 `assets/brand/{p}/.placeholder` 파일 존재 검증.
///
/// **현재 active = 7 provider 전체 자상 commit 완료.** 향후 placeholder
/// 가 필요한 신규 provider 가 진입할 경우 본 list 에 슬러그 추가 +
/// `assets/brand/{provider}/.placeholder` sentinel 파일 commit 의무.
///
/// **slugs:** `lib/core/auth/provider_id.dart` 의 provider slug 와 일관.
/// 본 list 는 const 으로 string 직접 — 빌드 시점 import cycle 회피
/// (lint test 가 lib/ 내 다른 const 의존하지 않음).
// Phase 14 D-LINE-13: LINE sentinel 해제 (`['line', 'wechat']` → `['wechat']`).
// Phase 16 폐기 (2026-05-22): WeChat sentinel 해제 (`['wechat']` → `<String>[]`).
const List<String> kPlaceholderProviders = <String>[];

/// Brand asset 디렉토리 base path — `assets/brand`.
///
/// `pubspec.yaml` 의 `flutter.assets` 등록 경로와 일관. lint test 가
/// `File('$kBrandAssetBase/$provider/...')` 형태로 사용.
const String kBrandAssetBase = 'assets/brand';
