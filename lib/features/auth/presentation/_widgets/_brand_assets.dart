// Phase 13.1 — see ROADMAP.md (D-74 sentinel detection 단일 진실원)

/// Brand asset sentinel detection 단일 진실원 — Phase 13.1 (D-74).
/// **현재 production 소비자 0.**
///
/// **WR-07 정정 (Phase 09 review).** 이전 문서는
/// "`BrandedSocialButton.build()` 가 본 list 를 참조해 fallback 분기" 라고
/// 적었으나 **사실이 아니다.** `branded_social_button.dart` 에서 본 상수가
/// 등장하는 곳은 주석 2줄뿐이고, `build()` 는 sealed [BrandSpec] **타입**
/// 으로만 분기한다. 실제 fallback 렌더러 `_renderPlaceholder` 는 Phase 14
/// (LINE active 전환) + Phase 16 (WeChat 폐기) 을 거치며 caller 0 이 되어
/// 폐기됐다.
///
/// 더 위험했던 것은 확장 절차 서술이다. 이전 문서는 "신규 provider 진입 시
/// 본 list 에 슬러그 추가 의무" 라고 지시했는데, **유일한 소비자인
/// `brand_assets_lint_test.dart` 는 정반대로 본 list 가 비어 있을 것을
/// 단언한다.** 문서를 따르면 게이트가 깨지는 모순이었다.
///
/// **placeholder 패턴을 재도입하려면 3가지를 함께 해야 한다:**
/// 1. `branded_social_button.dart` 에 `_renderPlaceholder` 복원
///    (Phase 13.1 D-74 + Phase 13.3 WR-04 의 라벨 l10n + Material shape
///    일관 패턴을 reference 로 삼는다)
/// 2. `BrandedSocialButton.build()` 에 fallback 분기 추가 — 현재 sealed
///    타입 switch 는 본 list 를 보지 않으므로 등재만으로는 아무 일도
///    일어나지 않는다
/// 3. `brand_assets_lint_test.dart` 의 empty 단언을 sentinel 파일 존재
///    검증으로 완화
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
