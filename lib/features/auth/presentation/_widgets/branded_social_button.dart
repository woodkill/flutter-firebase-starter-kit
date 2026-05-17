// Phase 13.1 — see ROADMAP.md (D-61 sealed BrandSpec hierarchy + R1/R2/R8 정정)
// Phase 13.3 — see ROADMAP.md (D-107 symbol SVG raw verbatim inline,
//             RESEARCH §1.1 + §1.2 — Wave 1 const 주입)

// Phase 13.3 Wave 4 Step 2 (2026-05-15): `sign_in_with_apple` package import
// 제거. SDK Button widget (`SignInWithAppleButton`) → 자체 render
// (`_renderAppleButton`) 전환. OAuth flow (credential 요청) 는 별도 파일
// (`apple_auth_strategy.dart` 등) 에서 `SignInWithApple.getAppleIDCredential()`
// 호출.
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../../core/theme/focus_wrapper.dart';
import '../../../../l10n/generated/app_localizations.dart';
import '_brand_assets.dart';

// Phase 13.1 REVIEW WR-02 / WR-09 정정 (2026-05-10):
// 5 active provider brand 색 (Kakao 0xFFFEE500 / 0xD9000000 / 0xFF000000 +
// Naver 0xFF03A94D / 0xFFFFFFFF) source const 폐기. Phase 13.1 Gap-1 X2 의
// wide 자상 통째 buttons 패턴 도입 후 widget render path 에서 직접 참조 0
// (자상에 색 baked-in). 회귀 가드는 `branded_social_button_test.dart` 의
// expected literal 단독 책임 — production const 가 더 이상 BI 색을 lib/
// 트리에서 참조하지 않으므로 const mirror 책임 자체가 무의미. BI 단일
// 진실원은 (1) `assets/brand/{kakao,naver}/` PNG 자상 (2) test expected
// literal (3) `docs/manual.md` 의 D-Note (R1 컨텍스트 분리). 향후 Phase 18
// Brand Center 마이그 시 fallback 색 reference 가 필요하면 그 시점에
// 신규 const 도입 — 현재 dead retention 패턴 폐기로 woody_lints
// unused_element 룰과 정합.

// Phase 13.3 — Wave 1 D-107 symbol SVG (Wave 4 Step 2 자산 분리 supersede):
//
// Wave 1 D-107 결정: `_renderKakaoButton` / `_renderNaverButton` 가 inline const
// SVG 를 `SvgPicture.string` 으로 render — 외부 asset 분리 시 drift risk 회피.
//
// Wave 4 Step 2 (2026-05-15) supersede: Kakao + Naver 모두 자산 파일로 분리
// (`assets/brand/{kakao,naver}/btn_signin_icon.svg`, Google 자산 파일 패턴 일관).
// drift risk 는 source-of-truth 단일 (자산 파일) + test expected 의 verbatim
// audit 로 mitigation.
//
// Audit trail:
// - Kakao SVG (`assets/brand/kakao/btn_signin_icon.svg`): 공식 PSD
//   `kakao_login_original.psd` (developers.kakao.com), `국문/Medium and Wide
//   (300px X 45px)/Shape 1` vector layer (9 knots Bezier path), psd-tools v1.17
//   verbatim 추출 2026-05-15. viewBox "0 0 20 20" — Google SVG (size 20×20,
//   aspect ratio 1:1) 와 정확 일치. fill="currentColor" — caller 측
//   colorFilter `symbolColor` (#000000 alpha 1.0) 적용.
// - Naver SVG (`assets/brand/naver/btn_signin_icon.svg`): 공식 AI 파일
//   `NAVER_login_KR.ai` (developers.naver.com/docs/login/bi/bi.md, PDF-1.5
//   vector) PyMuPDF v1.x verbatim 추출 — Page 1 drawing[38] (완성형 height 48
//   center align variant 의 logo, 16×16), single closed polygon (10 line
//   segments, no Bezier). 20×20 scale (가이드 "≥16" 부합 + Google/Kakao 일관).
//   fill="currentColor" — caller 측 colorFilter 으로 green-bg = `Colors.white`
//   / white-bg = `Color(0xFF03A94D)` / dark-bg = `Colors.white` 매핑.

// Phase 13.3 Wave 4 Step 2 (2026-05-15) — Naver N symbol SVG 는
// `assets/brand/naver/btn_signin_icon.svg` 자산 파일로 분리.
// Source: Naver 공식 AI 파일 (`NAVER_login_KR.ai`) PyMuPDF v1 재추출 —
//   Page 1 drawing[38] (완성형 height 48 center align variant 의 logo, 16×16),
//   single closed polygon (10 line segments, no Bezier). 20×20 으로 scale (가이드
//   "≥16" 의무 부합 + Google/Kakao SVG size 일관성). viewBox "0 0 20 20".
//   fill="currentColor" — caller 측 colorFilter 으로 green-bg = `Colors.white` /
//   white-bg = `Color(0xFF03A94D)` 매핑.

/// 자상 렌더링 dispatch 태그 (D-68).
///
/// `BrandedSocialButton.build()` 의 sealed switch 가 본 enum 으로 분기하여
/// PNG/SVG/위제 위임 셋 중 하나를 선택. 자상 형식 자동 추론 (확장자 string)
/// 비채택 — fragile + 장래 WebP 추가 시 회귀 가드 명료.
enum AssetType {
  /// PNG 자상 — Image.asset 으로 렌더, ColorFilter 적용 절대 금지 (R3/R4).
  png,

  /// SVG 자상 — SvgPicture.asset 으로 렌더 (Google 자상 6종).
  svg,

  /// 자상 미사용 — Apple (SDK 위제 위임, sign_in_with_apple) +
  /// LINE/WeChat (placeholder). Facebook 은 Phase 13.2 부로 [png] 전환.
  none,
}

// Phase 13.3 — see ROADMAP.md (R4 — 4 enum 폐기:
// NaverTheme/GoogleTheme/KakaoLabelVariant/NaverLabelVariant. caller
// 측 Theme.brightness 자동 분기 + Kakao BI 단일 라벨 강제 + Google
// Identity Theme.brightness 자동 분기로 차원 축소.)

// Phase 13.3 code review IN-01 정정 (2026-05-17): `LineLanguage` enum 삭제.
// Phase 14 (LINE 자상화) 진입 전까지 lib/ / test/ 트리에서 참조 0 — dead code.
// Phase 14 진입 시 LineSpec 이 실제 19 entries 매핑을 요구하는 시점에
// 재도입 (현재 enum 만 선언되면 woody_lints unused_element 룰 가시화 불가
// + 빈 placeholder 의무 0).

/// WeChat 자상 4 해상도 (24/32/48/64px) — D-63 placeholder.
enum WechatPixelSize {
  /// 24px PNG 자상.
  px24,

  /// 32px PNG 자상.
  px32,

  /// 48px PNG 자상.
  px48,

  /// 64px PNG 자상.
  px64,
}

/// Phase 13.1 — 7 provider brand 사양의 closed hierarchy (D-61).
///
/// 신규 provider 추가 시 [BrandSpec] sub-class 정의 + [BrandedSocialButton.build]
/// switch case 추가 의무 — exhaustive switch 컴파일 시점 강제. abstract class /
/// `Map<String, Object>` dynamic config 패턴 비채택 (D-61).
///
/// **공통 시각 사양 (D-71):** height 48 / borderRadius 12 / iconSize 18.
/// Apple SDK 위제만 SDK 기본 height 44 별도 (D-72-CLARIFY-1).
sealed class BrandSpec {
  /// brand spec const 생성자.
  const BrandSpec({
    this.height = 48,
    this.borderRadius = 12,
    this.iconSize = 18,
  });

  /// 버튼 높이 (dp). default 48. Apple SDK 위제는 본 필드 미사용 — SDK 기본 44.
  final double height;

  /// Material + InkWell border radius (dp). default 12 — Kakao BI 강제 (R2)
  /// + Naver 일관.
  final double borderRadius;

  /// 아이콘 width / height (dp). default 18.
  final double iconSize;

  /// 자상 렌더 경로 dispatch tag (D-68).
  AssetType get assetType;
}

/// Kakao 로그인 버튼 spec — D-61 sub-class.
///
/// Phase 13.3 R2 (Wave 4 Step 2): `_renderKakaoButton` 가
/// `assets/brand/kakao/btn_signin_icon.svg` 자산 파일 render — [assetType] 은
/// `AssetType.svg` (Google 자산 파일 패턴 일관).
///
/// **Phase 13.3 Wave 4 Step 3 (2026-05-16) — Kakao 공식 PSD M Wide verbatim
/// override:** Kakao 공식 PSD (`kakao_login_original.psd` of
/// developers.kakao.com, "국문/Medium and Wide (300px X 45px)" + "영문/Medium
/// and Wide (300px X 45px)" variant) psd-tools 추출 spec 으로 BrandSpec default
/// override:
/// - `iconSize: 20` (PSD M Wide Shape 1 측정 20×20dp + Google CSS 20px 정확
///   일치) — D-71 default 18 대비 별도
/// `borderRadius: 12` 는 BrandSpec default 와 일치 (정문 필수 "12 픽셀" 정확
/// 대응). `height: 48` 은 BrandSpec default 유지 (PSD M Wide 45 + 3dp ≈ 모바일
/// 표준 48dp, Naver case 의 height 48 default 유지 패턴 일관).
///
/// **Starter kit brand drift 회피:** `_renderKakaoButton` 모든 외관 spec
/// hardcoded — `colorScheme.*` / `textTheme.*` 토큰 의존 0 (Apple/Google/Naver
/// 패턴 mirror).
class KakaoSpec extends BrandSpec {
  /// const 생성자 — Kakao 공식 PSD M Wide verbatim override.
  const KakaoSpec() : super(iconSize: 20);

  @override
  AssetType get assetType => AssetType.svg;
}

/// Naver 로그인 버튼 spec — D-61 sub-class.
///
/// Phase 13.3 R3 (Wave 4 Step 2): theme 필드 폐기 (caller 측 Theme.brightness
/// 자동 분기 미사용, Naver BI 단일 그린 #03A94D 강제). `_renderNaverButton` 가
/// `assets/brand/naver/btn_signin_icon.svg` 자산 파일 render — [assetType] 은
/// `AssetType.svg`.
///
/// **Phase 13.3 Wave 4 Step 3 (2026-05-16) — Naver 공식 PNG 자상 verbatim
/// override:** NAVER 공식 PNG 자상 (`NAVER_login_EN.zip` 의
/// `NAVER_login_Light_EN_green_center_H48.png`, 사용자 제공 권위 출처) 정밀
/// 측정 (368×48dp @ 4x) 으로 BrandSpec default override:
/// - `borderRadius: 8` (공식 PNG 측정 ~7.5dp + STEP2-naver-VERBATIM AI cubic
///   Bezier 측정 8dp 부합) — D-71 default 12 대비 별도
/// - `iconSize: 16` (공식 PNG 측정 정확 16×16dp + 정문 "완성형 16px 이상"
///   필수 최소점 정확 대응) — D-71 default 18 대비 별도
/// `height: 48` 은 BrandSpec default 와 일치 (Naver AI 자산 모델 variant 48
/// 부합).
///
/// **Starter kit brand drift 회피:** `_renderNaverButton` 모든 외관 spec
/// hardcoded — `colorScheme.*` / `textTheme.*` 토큰 의존 0 (Apple/Google
/// 패턴 mirror).
class NaverSpec extends BrandSpec {
  /// const 생성자 — NAVER 공식 PNG 자상 verbatim override.
  const NaverSpec() : super(borderRadius: 8, iconSize: 16);

  @override
  AssetType get assetType => AssetType.svg;
}

/// Google 로그인 버튼 spec — D-61 sub-class.
///
/// Phase 13.3 R1: theme 필드 폐기 (caller 측 명시 매개변수 → `_renderGoogleButton`
/// 내부 Theme.brightness 자동 분기로 차원 축소). [assetType] 은 `AssetType.svg`
/// (Google Identity btn_signin_icon.svg).
///
/// **Phase 13.3 Wave 4 Step 3 (2026-05-16) — Google production CSS verbatim
/// override (X1 supersede 2026-05-17):** Google Identity Services 의 권위
/// 있는 production CSS (`.gsi-material-button` 클래스, 사용자 제공
/// 2026-05-16) 의 외관 spec 으로 `BrandSpec` default override:
/// - `height: 48` (mobile native 정합 — Google CSS 의 40 은 web context
///   한정, mobile 은 Android Material Button ~48dp / iOS UIButton ~44pt
///   native default 따름. WCAG 2.1 AAA + 5 provider vertical rhythm 통일
///   부합. STEP3-CONFLICT-MATRIX §3.1 supersede 2026-05-17 X1 WCAG audit)
/// - `borderRadius: 4` (CSS `border-radius: 4px`) — D-71 default 12 대비 별도
/// - `iconSize: 20` (CSS `.gsi-material-button-icon { width: 20px }`) — D-71
///   default 18 대비 별도
///
/// 5 provider 시각 통일 lock 의 trade-off 로 Google CSS verbatim 중 mobile
/// 적합 항목만 채택 (사용자 결정 2026-05-16 + X1 2026-05-17,
/// STEP3-CONFLICT-MATRIX §3.1/§3.2/§3.3 supersede).
/// 다른 4 provider (Kakao/Naver/Apple/Facebook) 는 BrandSpec default 유지.
class GoogleSpec extends BrandSpec {
  /// const 생성자 — Google production CSS verbatim override (X1 height 48 회귀).
  const GoogleSpec()
      : super(
          height: 48,
          borderRadius: 4,
          iconSize: 20,
        );

  @override
  AssetType get assetType => AssetType.svg;
}

/// Apple 로그인 버튼 spec — D-62 (Wave 4 Step 2 SDK 위제 → custom render supersede).
///
/// Phase 13.3 Wave 4 Step 2 (2026-05-15): SDK 위제 (`SignInWithAppleButton`) →
/// 자체 render (`_renderAppleButton`) 전환. Apple 공식 Logo-only SVG 자산
/// (`Logo-Sign-in-with-Apple.dmg` from developer.apple.com/design/resources/) 채택.
/// light = Black variant / dark = White variant — wrapper bg 색 일치 시 SVG
/// 정사각 외곽 invisible. Universal Layout 와 일관 + HIG mandate 100% 부합
/// (자산 변형 0, "Never crop" + "Don't add padding" 부합).
class AppleSpec extends BrandSpec {
  /// const 생성자.
  const AppleSpec();

  @override
  AssetType get assetType => AssetType.svg;
}

/// Facebook 로그인 버튼 spec — Phase 13.2 완료 (옵션 A pivot, Wave 0 lock).
///
/// `_renderFacebookButton` 호출 단독 — Apple `SignInWithAppleButton` 패턴
/// mirror. `Theme.brightness` 자동 분기 + 18dp Primary Logo SVG 자상
/// (`assets/brand/facebook/btn_signin_icon.svg`, Wave 4 Step 2 AI verbatim
/// 추출) + ARB `authFacebookSignIn` 라벨 + 1dp outline + Material radius 12dp.
/// Meta brand pack 의 logo-only 자상 (wide baked-in 미제공) 으로 Naver/Kakao/
/// Google wide 자상 통째 buttons 패턴 적용 불가 — Apple SDK 위제 패턴 mirror
/// 의무 (옵션 A pivot).
///
/// **D-95 lock (Wave 4 Step 2 supersede):** `AssetType.svg` (Wave 4 에서 PNG →
/// SVG 전환, Naver/Kakao 패턴 일관 + 자산 형식 통일). SVG path 는 Meta Brand
/// Asset Pack 의 `Facebook_Logo_Primary.ai` (PDF-1.5 vector) PyMuPDF verbatim
/// 추출. 출처 audit trail = `README.md`.
/// **D-94 lock:** theme 필드 부재 (Primary 단독 채택, Kakao 패턴 mirror).
/// **D-96 lock:** locale 독립 (단일 path, lang 분기 부재).
class FacebookSpec extends BrandSpec {
  /// const 생성자 — 공통 default (height 48 / radius 12 / icon 18) 사용.
  const FacebookSpec();

  @override
  AssetType get assetType => AssetType.svg;
}

/// LINE 로그인 버튼 spec — D-73 placeholder (자상 미존재 시 fallback render).
///
/// Phase 14 진입 시 자상 commit 후 `_brand_assets.dart` 의
/// `kPlaceholderProviders` 에서 'line' 제거 의무.
class LineSpec extends BrandSpec {
  /// const 생성자.
  const LineSpec();

  @override
  AssetType get assetType => AssetType.png;
}

/// WeChat 로그인 버튼 spec — D-73 placeholder.
///
/// Phase 16 진입 시 자상 commit 후 `_brand_assets.dart` 의
/// `kPlaceholderProviders` 에서 'wechat' 제거 의무. 4 해상도 (24/32/48/64) 중
/// [size] 매개변수로 선택.
class WechatSpec extends BrandSpec {
  /// const 생성자 — [size] 는 명시 매개변수.
  const WechatSpec({required this.size});

  /// 자상 해상도 dispatch.
  final WechatPixelSize size;

  @override
  AssetType get assetType => AssetType.png;
}

/// 7 provider brand button 통합 위제 — D-61 sealed hierarchy + D-67 sealed switch.
///
/// **호출자는 named factory 만 사용 의무 (D-65, D-70):**
/// - [BrandedSocialButton.kakao]
/// - [BrandedSocialButton.naver]
/// - [BrandedSocialButton.google]
/// - [BrandedSocialButton.apple]
/// - [BrandedSocialButton.facebook]
/// - [BrandedSocialButton.line]
/// - [BrandedSocialButton.wechat]
///
/// `_kakaoSpec` 등 const 인스턴스는 private — 외부 임의 spec 주입 차단으로
/// brand drift 최소화 (D-70).
///
/// **render dispatch (D-67):** [build] 내부 sealed switch 가 [BrandSpec]
/// 7 sub-class 모두 case 처리 — 신규 provider 추가 시 컴파일 fail 강제.
///
/// **시각 사양 (R2 Kakao BI 강제 12dp radius):**
/// - 너비 = `double.infinity` / 높이 48 dp (Apple SDK 위제만 SDK 기본 44,
///   D-72-CLARIFY-1)
/// - border radius 12 dp — Apple 은 `BorderRadius.circular(12)` (D-72-CLARIFY-2)
/// - 아이콘 18 dp / 아이콘 ↔ 라벨 간격 = `appSpacing.sm` (8 dp)
/// - TextStyle 14 dp / w500 / letterSpacing 0.1 / line height 20/14
class BrandedSocialButton extends StatelessWidget {
  /// 내부 전용 const 생성자 — 호출자는 named factory 만 사용.
  ///
  /// Phase 13.3 R5: Apple SDK 위제 style 필드 폐기 — AppleSpec build() 가
  /// `Theme.brightness` 자동 매핑 (light → .black / dark → .white).
  const BrandedSocialButton._({
    required this.spec,
    required this.label,
    required this.onPressed,
    super.key,
  });

  // Phase 13.3 — see ROADMAP.md (R4/R5 — theme/style parameter 폐기,
  // Naver/Google factory 의 theme: + Apple factory 의 style: 제거).

  /// Kakao named factory — D-65 lowercase provider 말단.
  factory BrandedSocialButton.kakao({
    required String label,
    required VoidCallback? onPressed,
    Key? key,
  }) => BrandedSocialButton._(
    key: key,
    spec: const KakaoSpec(),
    label: label,
    onPressed: onPressed,
  );

  /// Naver named factory — Phase 13.3 R3 theme: parameter 폐기.
  ///
  /// Naver BI 단일 그린 #03A94D 강제 — caller 측 분기 책임 0.
  factory BrandedSocialButton.naver({
    required String label,
    required VoidCallback? onPressed,
    Key? key,
  }) => BrandedSocialButton._(
    key: key,
    spec: const NaverSpec(),
    label: label,
    onPressed: onPressed,
  );

  /// Google named factory — Phase 13.3 R1 theme: parameter 폐기.
  ///
  /// `_renderGoogleButton` 내부 `Theme.brightness` 자동 분기로 차원 축소.
  factory BrandedSocialButton.google({
    required String label,
    required VoidCallback? onPressed,
    Key? key,
  }) => BrandedSocialButton._(
    key: key,
    spec: const GoogleSpec(),
    label: label,
    onPressed: onPressed,
  );

  /// Apple named factory — Phase 13.3 R5 style: parameter 폐기.
  ///
  /// AppleSpec build() 가 `Theme.brightness` 자동 매핑 (light → .black /
  /// dark → .white). HIG 권장값 자동 채택.
  factory BrandedSocialButton.apple({
    required String label,
    required VoidCallback? onPressed,
    Key? key,
  }) => BrandedSocialButton._(
    key: key,
    spec: const AppleSpec(),
    label: label,
    onPressed: onPressed,
  );

  /// Facebook named factory — Phase 13.2 완료 (옵션 A pivot, Wave 0 lock).
  ///
  /// `_renderFacebookButton` 위제 직접 호출 (Apple `SignInWithAppleButton`
  /// 패턴 mirror). `social_button.dart` 의 Facebook 분기가 본 factory 로 위임
  /// (Plan 13.2-05 완료 — 모든 provider 가 [BrandedSocialButton] 단일 진실원).
  factory BrandedSocialButton.facebook({
    required String label,
    required VoidCallback? onPressed,
    Key? key,
  }) => BrandedSocialButton._(
    key: key,
    spec: const FacebookSpec(),
    label: label,
    onPressed: onPressed,
  );

  /// LINE named factory — D-73 placeholder (자상 미존재 시 fallback render).
  factory BrandedSocialButton.line({
    required String label,
    required VoidCallback? onPressed,
    Key? key,
  }) => BrandedSocialButton._(
    key: key,
    spec: const LineSpec(),
    label: label,
    onPressed: onPressed,
  );

  /// WeChat named factory — D-73 placeholder + 4 해상도 enum.
  factory BrandedSocialButton.wechat({
    required String label,
    required VoidCallback? onPressed,
    WechatPixelSize size = WechatPixelSize.px48,
    Key? key,
  }) => BrandedSocialButton._(
    key: key,
    spec: WechatSpec(size: size),
    label: label,
    onPressed: onPressed,
  );

  /// brand spec — sealed sub-class 인스턴스.
  final BrandSpec spec;

  /// 버튼 라벨 (이미 ARB 로케일 해석된 문자열).
  final String label;

  /// 탭 핸들러. `null` 이면 비활성 상태 (ripple 없음).
  final VoidCallback? onPressed;

  // Phase 13.3 — see ROADMAP.md (R5 Apple Theme.brightness 자동 매핑 +
  // R1/R2/R3 render dispatch 단일 함수 → 3 별 함수 분리).
  @override
  Widget build(BuildContext context) {
    // D-67 — sealed switch exhaustive (Dart 3 컴파일 시점 강제).
    final Widget rendered = switch (spec) {
      // Phase 13.3 Wave 4 Step 2 (2026-05-15) — SDK 위제 (SignInWithAppleButton)
      // → 자체 render. Apple 공식 Logo-only SVG (light = Black variant /
      // dark = White variant) 채택, Universal Layout wrapper 일관 적용.
      AppleSpec() => _renderAppleButton(context, spec, label, onPressed),
      // Phase 13.2 — see ROADMAP.md (R5 — FacebookSpec active 전환, 옵션 A pivot)
      // Phase 13.3 Pitfall 7: line 399 변경 0 강제. signature/argument 순서/명칭
      // 변경 0. Wave 5 review 단계 git diff 검증.
      final FacebookSpec facebookSpec => _renderFacebookButton(
        context,
        facebookSpec,
        label,
        onPressed,
      ),
      LineSpec() || WechatSpec() => _renderPlaceholder(context, spec, label),
      KakaoSpec() => _renderKakaoButton(context, spec, label, onPressed),
      NaverSpec() => _renderNaverButton(context, spec, label, onPressed),
      GoogleSpec() => _renderGoogleButton(context, spec, label, onPressed),
    };
    // Phase 13.3 X2 (2026-05-17, 260517-uv4 옵션 B) — theme-level focus
    // indicator. 5 provider 자동 상속 (BrandedSocialButton.build 단일 boundary
    // 에서 wrap). WCAG 2.1 SC 2.4.7 Level AA 부합. token 의존 0 (starter kit
    // brand drift 회피). BrandFocusWrapper docstring 참조.
    return BrandFocusWrapper(
      borderRadius: spec.borderRadius,
      isEnabled: onPressed != null,
      child: rendered,
    );
  }
}

// Phase 13.3 — see ROADMAP.md (R2 Kakao | R3 Naver render —
// Universal Layout Pattern + brand verbatim). Phase 13.2 `_renderFacebookButton`
// 패턴 1:1 mirror. Q5 DEFAULT (별 함수 2개 보존) — Facebook 패턴 일관 +
// Phase 13.1 D-69 책임 분리.

/// Kakao 로그인 button render (R2).
///
/// Universal Layout Pattern + #FEE500 bg + 말풍선 symbol SVG inline
/// (D-105 + D-107) + ARB authKakaoSignIn 라벨. light/dark 단일 (Kakao BI
/// 강제, theme 분기 0). outline 0 (bg-only).
///
/// **Starter kit brand drift 회피 (Wave 4 Step 3 — Apple/Google/Naver 패턴
/// mirror):** 모든 외관 spec hardcoded — `colorScheme.*` / `textTheme.*` 토큰
/// 의존 0. 스타터킷 사용자가 `ThemeData.colorScheme` 또는 `textTheme` override
/// 시 brand 버튼 외관이 영향 받지 않도록 `TextStyle()` 직접 명시 + Color literal
/// hardcode.
///
/// **Kakao 정문 + 공식 PSD M Wide variant spec (STEP2-kakao-VERBATIM):**
/// - bg: #FEE500 (정문 필수 "컨테이너: #FEE500")
/// - fg color: #000000 alpha 0.85 = `Color(0xD9000000)` (정문 필수 "#000000
///   85%" — PSD 자산은 #191919 100% 사용하나 가이드 정문 우선 채택, Step 2
///   사용자 sign-off)
/// - symbol color: #000000 (정문 필수 "심볼: #000000")
/// - borderRadius: 12 (정문 필수 정량 "컨테이너 박스의 radius는 12 픽셀")
/// - iconSize: 20 (PSD M Wide Shape 1 측정 + Google CSS 20px 정확 일치),
///   KakaoSpec override
/// - logoLabelGap: 8 (PSD M Wide center align 자동 + Naver 일관 8dp)
/// - fontFamily + fontWeight: `Theme.of(context).platform` 분기 (Step B,
///   사용자 결정 2026-05-16):
///   - **iOS**: `AppleSDGothicNeo` (native macOS/iOS 시스템 폰트, bundle 0,
///     Apple OS 내부 사용 = Apple Font License + Sandoll 라이센스 부합) +
///     `FontWeight.w500` (Medium — PSD L Wide variant
///     `AppleSDGothicNeo-Medium` verbatim, PSD designer 의도 그대로 렌더)
///   - **Android / others**: `Pretendard` (PSD `AppleSDGothicNeo` 의 open-
///     source 대체, Pretendard 가 Apple SD Gothic Neo 기반으로 디자인, SIL
///     OFL 1.1 bundled) + `FontWeight.w400` (Regular — Pretendard 명목 weight
///     매핑이 AppleSDGothicNeo 보다 무거워 한 단계 낮춤, Naver case lesson
///     #15 mirror, Step A 시각 sign-off)
///   starter kit drift 회피 원칙 "허용 (분기 trigger): theme.platform" 부합 ✓.
///   Naver 와 같은 platform 분기 패턴 (iOS = AppleSDGothicNeo / Android =
///   Pretendard) — 한국 brand 2 provider cross-provider 일관성 회복 (Wave 4
///   Step 3 이후 Naver 도 동일 platform 분기 채택).
///   *audit trail*: KakaoSmallSans (kakao/kakao-font 2025-06-18 공개) 시도
///   → PSD 자상 (~2022) 의 AppleSDGothicNeo 글리프 character set 과 명백히
///   다른 신규 digital-optimized 디자인 → revert (Kakao Small Sans bundle 도
///   제거). AppleSDGothicNeo binary bundle 은 라이센스 위반 위험으로 채택 불가
///   → iOS native 명시 (bundle 0) + Android Pretendard 분기 패턴 채택.
/// - fontSize: `Theme.of(context).platform` 분기 (fontFamily/weight 분기와 동일
///   audit-trail 패턴, 사용자 시각 sign-off 2026-05-16)
///   - **iOS**: 16pt (+1pt cap height 보정 — AppleSDGothicNeo cap height 가
///     Pretendard 보다 작은 비율이라 Apple OS 만 +1pt, Naver case mirror,
///     사용자 시각 보고 3회 iteration 2026-05-16: 15→16→17→16 수렴)
///   - **Android / others**: 15pt (PSD M Wide variant verbatim —
///     AppleSDGothicNeo / 15pt). 모바일 UX (height 48dp) 부합.
Widget _renderKakaoButton(
  BuildContext context,
  BrandSpec spec,
  String label,
  VoidCallback? onPressed,
) {
  final radius = BorderRadius.circular(spec.borderRadius);
  final isEnabled = onPressed != null;
  // Kakao BI verbatim (UI-SPEC + Phase 13.3 Wave 4 Step 3 정정):
  //   bg = #FEE500 (Kakao yellow, 단일 색)
  //   fg = #000000 alpha 0.85 (Kakao Design Guide "#000000 85%") → 0xD9 (217/255 = 85.1%)
  //   symbol = #000000 alpha 1.0 (Kakao Design Guide "심볼: #000000")
  const bgColor = Color(0xFFFEE500);
  const fgColor = Color(0xD9000000);
  const symbolColor = Color(0xFF000000);
  // Kakao 정문 "OS별 기본 시스템 서체" + PSD verbatim 결합 (Step B platform 분기,
  // 사용자 2026-05-16):
  //   iOS = AppleSDGothicNeo (native macOS/iOS 시스템 폰트, bundle 0, Apple OS
  //   내부 사용 = Apple Font License + Sandoll 라이센스 부합) + w500 (Medium —
  //   PSD L Wide variant `AppleSDGothicNeo-Medium` verbatim, PSD designer 의도
  //   그대로 iOS 렌더).
  //   Android / others = Pretendard (PSD `AppleSDGothicNeo` 의 open-source
  //   대체, SIL OFL 1.1 bundled) + w400 (Regular — Pretendard 명목 weight 매핑이
  //   AppleSDGothicNeo 보다 무거워 한 단계 낮춤, Naver case lesson #15 mirror).
  //   starter kit drift 회피 원칙 "허용 (분기 trigger): theme.platform" 부합 ✓.
  //
  // *audit trail (2026-05-16)*: 사용자 의도 "카카오 자체 제작 폰트" 추구로
  //   Kakao Small Sans (kakao/kakao-font, 2025-06-18 공개, SIL OFL 1.1) 시도
  //   → PSD 자상 (~2022 디자인) 의 AppleSDGothicNeo 글리프 character set 과
  //   명백히 다름 (digital-optimized 신규 디자인) → revert. AppleSDGothicNeo
  //   binary bundle 은 라이센스 위반 위험으로 채택 불가 → iOS native 명시
  //   (bundle 0) + Android Pretendard 분기 패턴 채택.
  // Phase 13.3 code review CR-02 정정 (2026-05-17): Apple/Google/Facebook 패턴
  // mirror — `isApplePlatform` (iOS || macOS) 분기 트리거. 사용자 결정 "iOS/
  // macOS 환경에서 Apple OS native font 활용 = Apple Font License 부합" 의도
  // 일관. 기존 `isIOS` 단독 분기는 macOS desktop 실행 시 Kakao/Naver 만
  // Pretendard 로 fallback → Apple/Google/Facebook 와 cross-provider drift.
  final theme = Theme.of(context);
  final isApplePlatform =
      theme.platform == TargetPlatform.iOS ||
      theme.platform == TargetPlatform.macOS;
  final labelFontFamily = isApplePlatform ? 'AppleSDGothicNeo' : 'Pretendard';
  final labelFontWeight = isApplePlatform ? FontWeight.w500 : FontWeight.w400;
  return Semantics(
    button: true,
    enabled: isEnabled,
    label: label,
    onTap: onPressed,
    excludeSemantics: true,
    child: SizedBox(
      width: double.infinity,
      height: spec.height,
      child: Opacity(
        opacity: isEnabled ? 1.0 : 0.5,
        child: Material(
          color: bgColor,
          shape: RoundedRectangleBorder(borderRadius: radius),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onPressed,
            borderRadius: radius,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  SvgPicture.asset(
                    '$kBrandAssetBase/kakao/btn_signin_icon.svg',
                    width: spec.iconSize,
                    height: spec.iconSize,
                    colorFilter: const ColorFilter.mode(
                      symbolColor,
                      BlendMode.srcIn,
                    ),
                    semanticsLabel: null,
                  ),
                  // PSD M Wide center align 자동 + Naver 일관 8dp.
                  const SizedBox(width: 8),
                  Flexible(
                    // Apple OS (iOS || macOS) 만 Padding(top: 2) wrap —
                    // AppleSDGothicNeo glyph line box 안 위쪽 위치 보정
                    // (Naver case mirror, 사용자 시각 보고 2026-05-16).
                    // CR-02 정정: `isApplePlatform` 으로 트리거 통일.
                    child: Padding(
                      padding: EdgeInsets.only(top: isApplePlatform ? 2 : 0),
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      // Kakao 라벨 spec (Step B platform 분기):
                      //   fontFamily/fontWeight = isApplePlatform ?
                      //   AppleSDGothicNeo w500 : Pretendard w400 (위 분기
                      //   lookup 참조).
                      //   fontSize = isApplePlatform ? 16 : 15 —
                      //   AppleSDGothicNeo cap height 가 Pretendard 보다 작은
                      //   비율이라 시각 보정 위해 Apple OS 만 +1pt (Naver case
                      //   mirror, 사용자 시각 보고 3회 iteration 2026-05-16:
                      //   15→16→17→16 수렴).
                      //   Android 는 PSD M Wide variant verbatim 15pt 유지.
                      //   height 1.0 + leadingDistribution.even (Apple OS 만)
                      //   — line box 압축 + leading 균등 분배 → text visible
                      //   glyph 가 line box center 에 정확 align → SVG vertical
                      //   center 와 정렬 향상.
                      //   color fgColor = #000000 α0.85 (가이드 정문 우선).
                      //   textTheme.labelLarge.copyWith 비채택 (사용자
                      //   ThemeData drift 회피).
                        style: TextStyle(
                          color: fgColor,
                          fontSize: isApplePlatform ? 16 : 15,
                          fontWeight: labelFontWeight,
                          fontFamily: labelFontFamily,
                          height: isApplePlatform ? 1.0 : null,
                          leadingDistribution: isApplePlatform
                              ? TextLeadingDistribution.even
                              : null,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

/// Naver 로그인 button render (R3).
///
/// Universal Layout Pattern + #03A94D bg + N symbol SVG inline + ARB
/// authNaverSignIn 라벨. #03C75A (NCloud SSO) carve-out 미적용 — Naver ID
/// 로그인 BI 의 #03A94D 단일 색 강제. light/dark 단일. outline 0 (bg-only).
///
/// **Starter kit brand drift 회피 (Wave 4 Step 3 — Apple/Google 패턴 mirror):**
/// 모든 외관 spec hardcoded — `colorScheme.*` / `textTheme.*` 토큰 의존 0.
/// 스타터킷 사용자가 `ThemeData.colorScheme` 또는 `textTheme` override 시
/// brand 버튼 외관이 영향 받지 않도록 `TextStyle()` 직접 명시 + Color literal
/// hardcode.
///
/// **Naver 정문 + 공식 PNG 자상 spec (STEP2-naver-VERBATIM 매트릭스):**
/// - bg: #03A94D (정문 필수 "반드시 지정된 녹색")
/// - logo color: #FFFFFF (정문 필수, green-bg variant)
/// - label color: #FFFFFF (정문 필수, green-bg variant)
/// - logoLabelGap: 8 (정문 필수 "가운데 정렬 시 8px")
/// - borderRadius: 8 (공식 PNG 측정 ~7.5dp + AI 자산 8dp), NaverSpec override
/// - iconSize: 16 (공식 PNG 측정 16×16dp + 정문 "완성형 16px 이상"),
///   NaverSpec override
/// - fontFamily + fontWeight: `Theme.of(context).platform` 분기 (Kakao 패턴
///   mirror, 사용자 결정 2026-05-16 — cross-provider 일관성):
///   - **iOS**: `AppleSDGothicNeo` (Pretendard 의 source font — native macOS/
///     iOS 시스템 폰트, bundle 0, Apple OS 내부 사용 = Apple Font License +
///     Sandoll 라이센스 부합) + `FontWeight.w700` (Bold — NAVER 공식 PNG 굵은
///     stroke 시각 매칭, AppleSDGothicNeo 명목 weight 가 Pretendard 보다 가벼워
///     Android w600 에서 한 단계 올림, 사용자 시각 sign-off 2026-05-16)
///   - **Android / others**: `Pretendard` (PSD `AppleSDGothicNeo` 의
///     open-source 대체, SIL OFL 1.1 bundled) + `FontWeight.w600` (SemiBold —
///     공식 PNG 자상 시각 sign-off Step 3 lock)
///   `Theme.platform` 분기 trigger 채택 — starter kit drift 회피 원칙 "허용
///   분기 trigger" 부합 ✓. iOS golden fixture (`naver_light_ios.png`) macOS
///   dev only — `.gitignore` 처리 (Apple Font License 위반 위험 회피) +
///   `testWidgets(skip: !Platform.isMacOS)` 게이트 (Kakao iOS golden 패턴 mirror).
/// - fontSize: `Theme.of(context).platform` 분기 (Kakao 패턴 mirror)
///   - **iOS**: 17pt (+1pt cap height 보정 — AppleSDGothicNeo cap height 가
///     Pretendard 보다 작은 비율이라 Apple OS 만 +1pt, 사용자 시각 sign-off
///     2026-05-16: 16→17→18→17 수렴)
///   - **Android / others**: 16pt (공식 PNG 측정 + 사용자 시각 sign-off
///     Step 3 lock)
///   정문 조건 "로고 높이보다 작은 크기" 는 cap-height 기준 해석 (cap height
///   ≈ fontSize × 0.7 ≈ 11dp < logo.height 16 부합).
Widget _renderNaverButton(
  BuildContext context,
  BrandSpec spec,
  String label,
  VoidCallback? onPressed,
) {
  final radius = BorderRadius.circular(spec.borderRadius);
  final isEnabled = onPressed != null;
  // Naver BI verbatim (정문 필수 정량):
  //   bg = #03A94D (Naver ID 로그인 BI green). NCloud SSO #03C75A 비채택.
  //   fg = #FFFFFF (BI default — 흰 N glyph + 흰 라벨 1:1 일관).
  const bgColor = Color(0xFF03A94D);
  const fgColor = Colors.white;
  // Naver 정문 자유 fontFamily — Kakao 패턴 mirror platform 분기 (사용자
  // 결정 2026-05-16 cross-provider 일관성):
  //   iOS = AppleSDGothicNeo (Pretendard 의 source font, native macOS/iOS
  //   시스템 폰트, bundle 0, Apple OS 내부 사용 = Apple Font License +
  //   Sandoll 라이센스 부합) + w700 (Bold — NAVER 공식 PNG 굵은 stroke 시각
  //   매칭, AppleSDGothicNeo 명목 weight 가 Pretendard 보다 가벼워 한 단계
  //   올림, 사용자 시각 sign-off 2026-05-16).
  //   Android / others = Pretendard + w600 (공식 PNG 자상 시각 sign-off Step 3
  //   lock, NAVER_login_Light_EN_green_center_H48 글리프 부합). 한국 design
  //   표준 web font. SIL OFL 1.1.
  // Phase 13.3 code review CR-02 정정 (2026-05-17): Apple/Google/Facebook 패턴
  // mirror — `isApplePlatform` (iOS || macOS) 분기 트리거. Kakao 와 동일 사유.
  final theme = Theme.of(context);
  final isApplePlatform =
      theme.platform == TargetPlatform.iOS ||
      theme.platform == TargetPlatform.macOS;
  final labelFontFamily = isApplePlatform ? 'AppleSDGothicNeo' : 'Pretendard';
  final labelFontWeight = isApplePlatform ? FontWeight.w700 : FontWeight.w600;
  return Semantics(
    button: true,
    enabled: isEnabled,
    label: label,
    onTap: onPressed,
    excludeSemantics: true,
    child: SizedBox(
      width: double.infinity,
      height: spec.height,
      child: Opacity(
        opacity: isEnabled ? 1.0 : 0.5,
        child: Material(
          color: bgColor,
          shape: RoundedRectangleBorder(borderRadius: radius),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onPressed,
            borderRadius: radius,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  SvgPicture.asset(
                    '$kBrandAssetBase/naver/btn_signin_icon.svg',
                    width: spec.iconSize,
                    height: spec.iconSize,
                    semanticsLabel: null,
                    colorFilter: const ColorFilter.mode(
                      fgColor,
                      BlendMode.srcIn,
                    ),
                  ),
                  // Naver 정문 필수 "가운데 정렬 시 8px" (logoLabelGap).
                  const SizedBox(width: 8),
                  Flexible(
                    // Apple OS (iOS || macOS) 만 Padding(top: 2) wrap —
                    // AppleSDGothicNeo glyph 가 line box 안에서 위쪽에 위치
                    // (font 자연 metric) → leadingDistribution.even + height
                    // 1.0 만으로 미해결 → widget bounding box top 2dp 빈공간
                    // 추가 → Row crossAxis center 시 visible text 가 SVG
                    // center 보다 1dp 아래로 이동 → 정렬 향상 (사용자 시각
                    // 보고 2026-05-16). CR-02 정정: `isApplePlatform` 트리거 통일.
                    child: Padding(
                      padding: EdgeInsets.only(top: isApplePlatform ? 2 : 0),
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      // Naver 라벨 spec (Kakao 패턴 mirror platform 분기):
                      //   fontFamily = isApplePlatform ? AppleSDGothicNeo :
                      //   Pretendard.
                      //   fontWeight = isApplePlatform ? w700 : w600 (위 분기
                      //   lookup).
                      //   fontSize = isApplePlatform ? 17 : 16 —
                      //   AppleSDGothicNeo cap height 가 Pretendard 보다 작은
                      //   비율이라 시각 보정 위해 Apple OS 만 +1pt (사용자
                      //   시각 보고 3회 iteration 2026-05-16: 16→17→18→17 수렴).
                      //   height 1.0 + leadingDistribution.even (Apple OS 만)
                      //   — line box 를 fontSize 와 같게 압축 + leading 을
                      //   ascent/descent 균등 분배 → text visible glyph 가
                      //   line box center 에 정확 align → SVG vertical center
                      //   와 정렬 (default proportional 시 ascent 에 leading
                      //   많이 분배되어 text 가 line box 안에서 위쪽으로 치우침).
                      //   color fgColor = #FFFFFF (정문 필수).
                      //   textTheme.labelLarge.copyWith 비채택 (사용자
                      //   ThemeData drift 회피).
                        style: TextStyle(
                          color: fgColor,
                          fontSize: isApplePlatform ? 17 : 16,
                          fontWeight: labelFontWeight,
                          fontFamily: labelFontFamily,
                          height: isApplePlatform ? 1.0 : null,
                          leadingDistribution: isApplePlatform
                              ? TextLeadingDistribution.even
                              : null,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

/// Facebook 전용 render — 옵션 A pivot (Wave 0 lock) + Google CSS mirror
/// (Wave 4 Step 3, 2026-05-17).
///
/// **옵션 A pivot 의무 (13.2-WAVE0-LOCK.md):** Meta brand pack 은 logo-only
/// 자상 (Primary Logo 2084×2084 square PNG) 단독 제공 — Kakao/Naver/Google 의
/// wide 자상 통째 buttons 패턴 (자상에 배경+라벨+로고 모두 baked-in) 적용
/// 불가. Apple `SignInWithAppleButton` SDK 위제 패턴 mirror 의무 — Logo 18dp
/// icon 슬롯 + ARB 라벨 외부 layer + Theme.brightness 자동 분기 + 1dp outline.
///
/// **Starter kit brand drift 회피 (Wave 4 Step 3 — Google 패턴 mirror):**
/// 모든 외관 spec hardcoded — `colorScheme.*` / `textTheme.*` 토큰 의존 0.
/// Facebook 정문 (developers.facebook.com/docs/facebook-login/userexperience/)
/// 은 bg/label color · fontFamily · size · weight 모두 정성 권고만 ("Choose
/// the font, font weight, and kerning that looks best in your app") — 자유
/// 영역. 5 provider 시각 consistency 위해 Google CSS verbatim 패턴 mirror 적용
/// (사용자 결정 2026-05-17):
///   bg     light #FFFFFF  / dark #131314
///   label  light #1F1F1F  / dark #E3E3E3
///   outline light #DADCE0 / dark #8E918F (1dp inside)
///   font   Roboto (Android) / SF Pro Text (iOS+macOS), size 14, weight w500,
///          height 20/14, letterSpacing 0.25 (Android) / -0.15 (iOS+macOS,
///          Apple HIG SF Pro Text 14pt 권고 tracking)
///   disabled  Opacity 0.38 (Google CSS verbatim — `.gsi-material-button:
///             disabled { opacity: 38%; }` 머레)
///
/// **render 사양 매트릭스:**
/// - SizedBox: `width: double.infinity` / `height: spec.height` (48dp).
/// - Material: hex hardcoded bg + 1dp outline (BorderSide.width 1), borderRadius
///   `spec.borderRadius` (12dp default), `clipBehavior: Clip.antiAlias`.
/// - InkWell: `borderRadius` 머레, ripple 영역 제어.
/// - Row: `padding: EdgeInsets.symmetric(horizontal: 12)` + `gap 8dp` (SizedBox
///   8dp, Facebook 정문 자유 — Phase 13.1 appSpacing.sm 머레).
/// - SvgPicture.asset: `assets/brand/facebook/btn_signin_icon.svg` (Wave 4
///   Step 2 PNG → SVG 전환, AI verbatim 추출 — 2 paths blue circle #0866FF +
///   white 'f'), `spec.iconSize`, `excludeFromSemantics: true`.
/// - Text: `authFacebookSignIn` ARB 라벨, `TextStyle()` 직접 명시 (M3 textTheme
///   비채택).
/// - Semantics 외부 layer 단독 권위: `button: true`, `enabled: onPressed != null`,
///   `label`, `onTap: onPressed`, `excludeSemantics: true` (Phase 13.1 a11y
///   layer 패턴 머레, iter2 CR-01 정정 머레).
///
/// **AppleSpec/KakaoSpec/NaverSpec/GoogleSpec/LineSpec/WechatSpec 영향 없음** —
/// 본 함수는 build() 의 FacebookSpec 분기에서만 호출.
Widget _renderFacebookButton(
  BuildContext context,
  FacebookSpec spec,
  String label,
  VoidCallback? onPressed,
) {
  final assetPath = _iconAssetFor(context, spec);
  final radius = BorderRadius.circular(spec.borderRadius);
  // Phase 13.3 Wave 4 Step 3 정정 (2026-05-17, Google 패턴 mirror): theme 단일
  // lookup 으로 `brightness` + `platform` 만 분기 trigger 로 사용. `colorScheme`
  // / `textTheme` 의존 0 (starter kit brand drift 회피, 사용자 ThemeData
  // override 시 외관 보존). 기존 `colorScheme.surface` / `colorScheme.onSurface`
  // / `theme.textTheme.labelLarge` 의존 4건 → Google CSS verbatim hex hardcode.
  final theme = Theme.of(context);
  final isDark = theme.brightness == Brightness.dark;
  final isEnabled = onPressed != null;
  // Google CSS verbatim (사용자 결정 2026-05-17 — Facebook 정문 자유 영역,
  // 5 provider 시각 consistency 위해 Google `.gsi-material-button` 패턴 mirror):
  //   bg      = light #FFFFFF / dark #131314
  //   label   = light #1F1F1F / dark #E3E3E3
  //   outline = light #DADCE0 / dark #8E918F (1dp inside)
  // disabled 처리 = Opacity 0.38 wrap (Google CSS `:disabled { opacity: 38%; }`
  // 머레). 5 provider 일관 0.5 보다 CSS verbatim 부합 우선.
  final bgColor = isDark ? const Color(0xFF131314) : const Color(0xFFFFFFFF);
  final labelColor = isDark
      ? const Color(0xFFE3E3E3)
      : const Color(0xFF1F1F1F);
  final outlineColor = isDark
      ? const Color(0xFF8E918F)
      : const Color(0xFFDADCE0);
  // Google 패턴 mirror — fontFamily platform 분기 (사용자 결정 2026-05-17).
  // Apple SF Pro Text (iOS/macOS) / Roboto (Android+other). letterSpacing iOS
  // 강등 (-0.15) Google CSS 패턴 머레 (Roboto 0.25 가 SF Pro Text wider default
  // tracking 위에 누적되어 시각 자간 과도 발생 회피).
  final isApplePlatform =
      theme.platform == TargetPlatform.iOS ||
      theme.platform == TargetPlatform.macOS;
  final labelFontFamily = isApplePlatform ? 'SF Pro Text' : 'Roboto';
  return Semantics(
    button: true,
    enabled: isEnabled,
    label: label,
    onTap: onPressed,
    excludeSemantics: true,
    child: SizedBox(
      width: double.infinity,
      height: spec.height,
      // Phase 13.3 Wave 4 Step 3 (2026-05-17) — Google CSS verbatim disabled
      // state mirror: `.gsi-material-button:disabled { opacity: 38%; }`. Phase
      // 13.2 REVIEW CR-01 의 0.5 supersede (5 provider 정량 색 Google mirror
      // 결정 일관성). disabled 시 outline + label 색 단계 강등 폐기 — Opacity
      // wrap 단독 의존 (Google 패턴 머레). 회귀 가드 T-13.2-FACEBOOK-DISABLED-01
      // 도 0.38 검증으로 갱신.
      child: Opacity(
        opacity: isEnabled ? 1.0 : 0.38,
        // Phase 13.2 REVIEW WR-01 정정 (2026-05-13): borderRadius 3중 적용
        // (Material + InkWell + DecoratedBox) → Material.shape 의
        // RoundedRectangleBorder(side) 단일화. clipBehavior: Clip.antiAlias
        // 가 외부 border 0.5dp 잘림 문제를 야기하던 DecoratedBox.border 폐기
        // 후 shape side 가 Material 자체 path 의 stroke 로 그려져 1dp 완전
        // 두께로 visible. radius 적용 layer: Material.shape (visual border) +
        // InkWell.borderRadius (ripple 영역 제어) 의 2 layer 만 잔존.
        child: Material(
          color: bgColor,
          shape: RoundedRectangleBorder(
            borderRadius: radius,
            side: BorderSide(color: outlineColor),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onPressed,
            borderRadius: radius,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Phase 13.3 Wave 4 Step 2 (2026-05-15): PNG → SVG 전환.
                  // Meta Brand Asset Pack 의 Facebook_Logo_Primary.ai (PDF-1.5
                  // vector) PyMuPDF verbatim 추출 — 2 paths (blue circle
                  // #0866FF + white 'f'). viewBox "0 0 20 20" (Google/Kakao/
                  // Naver 와 size + aspect ratio 일치). cacheWidth/cacheHeight
                  // 불필요 (SVG render path 별 GPU layer).
                  SvgPicture.asset(
                    assetPath,
                    width: spec.iconSize,
                    height: spec.iconSize,
                    excludeFromSemantics: true,
                  ),
                  const SizedBox(width: 8),
                  // Phase 13.2 Plan 13.2-06 [Rule 1 - Bug]: 좁은 viewport
                  // (예: 360dp) + 긴 라벨 ('Continue with Facebook' 21자) 시
                  // Row mainAxisSize.max 가 Padding(horizontal:12) 안에서
                  // 0.2px overflow. mainAxisSize.min + Flexible(child: Text)
                  // 으로 안전 fit + 마진 환경에서 ellipsis fallback.
                  Flexible(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      // Google production CSS verbatim TextStyle (사용자 결정
                      // 2026-05-17 — Facebook 정문 자유, 5 provider 시각
                      // consistency 위해 Google 패턴 머레):
                      //   .gsi-material-button { font-size: 14px;
                      //     letter-spacing: 0.25px; font-family: 'Roboto', ... }
                      //   .gsi-material-button-contents { font-weight: 500; }
                      //   "14/20" 가이드 → lineHeight 20pt (height = 20/14).
                      // letterSpacing platform 분기: Roboto 0.25 (Android Google
                      // CSS verbatim) / SF Pro Text -0.15 (iOS Apple HIG SF
                      // Pro Text 14pt 권고 tracking). M3 textTheme.labelLarge
                      // 비채택 (starter kit drift 회피, 사용자 ThemeData
                      // override 무관).
                      style: TextStyle(
                        color: labelColor,
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        height: 20 / 14,
                        letterSpacing: isApplePlatform ? -0.15 : 0.25,
                        fontFamily: labelFontFamily,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

// Phase 13.3 — see ROADMAP.md (R1 Google render — Material 3 colorScheme.surface
// + Identity Guidelines stroke verbatim). Phase 13.2 `_renderFacebookButton`
// 패턴 1:1 mirror + Theme.brightness 자동 분기 (caller 측 theme: parameter
// 폐기 R1).

/// Google 로그인 button render (R1).
///
/// Universal Layout Pattern + Google Identity Guidelines verbatim
/// (light bg #FFFFFF / dark bg #131314, light stroke #747775 / dark stroke
/// #8E918F 1dp outline, light label #1F1F1F / dark label #E3E3E3, Roboto
/// Medium 14/20, OS 분기 padding/gap) + btn_signin_icon.svg + ARB
/// authGoogleSignIn 라벨. Theme.brightness + Theme.platform 자동 분기.
///
/// **Starter kit brand drift 회피 (Wave 4 Step 3 — Apple 패턴 mirror):**
/// 모든 외관 spec hardcoded — `colorScheme.*` / `textTheme.*` 토큰 의존 0.
/// 스타터킷 사용자가 `ThemeData.colorScheme` 또는 `textTheme` override 시
/// brand 버튼 외관이 영향 받지 않도록 `TextStyle()` 직접 명시 + Color literal
/// hardcode. `theme.brightness` / `theme.platform` 는 분기 trigger 단독 사용
/// (외관 spec 자체가 아닌 어떤 variant 선택할지 결정).
///
/// **Google 정문 OS 분기 필수 (Step 3 §3.5 / §3.6 사용자 결정 2026-05-16):**
/// - `padding.horizontal`: Android/Web 12 / iOS 16 (정문 필수).
/// - `logoLabelGap`: Android/Web 10 / iOS 12 (정문 필수).
/// 다른 4 provider 는 정문 자유 영역이라 Google 만 platform 분기 적용
/// (Kakao/Naver/Facebook 의 단일 통일값과 의도된 비균일).
Widget _renderGoogleButton(
  BuildContext context,
  BrandSpec spec,
  String label,
  VoidCallback? onPressed,
) {
  final theme = Theme.of(context);
  final isDark = theme.brightness == Brightness.dark;
  final isEnabled = onPressed != null;
  // Google Identity Guidelines verbatim (정문 필수 정량):
  //   bg     = light #FFFFFF / dark #131314
  //   stroke = light #747775 / dark #8E918F (1dp inside)
  //   label  = light #1F1F1F / dark #E3E3E3
  final bgColor = isDark ? const Color(0xFF131314) : Colors.white;
  final outlineColor = isDark
      ? const Color(0xFF8E918F)
      : const Color(0xFF747775);
  final labelColor = isDark
      ? const Color(0xFFE3E3E3)
      : const Color(0xFF1F1F1F);
  // Google 정문 OS 분기 필수 (Step 3 §3.5 / §3.6):
  //   padding.horizontal: Android/Web 12 / iOS 16
  //   logoLabelGap:       Android/Web 10 / iOS 12
  final isApplePlatform =
      theme.platform == TargetPlatform.iOS ||
      theme.platform == TargetPlatform.macOS;
  final padHorizontal = isApplePlatform ? 16.0 : 12.0;
  final logoLabelGap = isApplePlatform ? 12.0 : 10.0;
  // Google 정문 label fontFamily 강등 정책 (STEP2-google-VERBATIM §2 row
  // label.fontFamily): Android 필수 'Roboto Medium' / iOS 강등 'SF Pro Text'
  // (OS 권고 fontFamily). 다른 platform 은 Roboto (Flutter 시스템 fallback —
  // Android system Roboto 자동 매핑).
  final labelFontFamily = isApplePlatform ? 'SF Pro Text' : 'Roboto';
  final iconPath =
      '$kBrandAssetBase/google/${isDark ? "dark" : "light"}/btn_signin_icon.svg';
  final radius = BorderRadius.circular(spec.borderRadius);
  return Semantics(
    button: true,
    enabled: isEnabled,
    label: label,
    onTap: onPressed,
    excludeSemantics: true,
    child: SizedBox(
      width: double.infinity,
      height: spec.height,
      // Google production CSS verbatim disabled state (사용자 제공 2026-05-16):
      //   .gsi-material-button:disabled .gsi-material-button-contents,
      //   .gsi-material-button:disabled .gsi-material-button-icon {
      //     opacity: 38%;
      //   }
      // 즉 disabled visible = 38% → `Opacity(0.38)`. 5 provider 일관 0.5 보다
      // CSS verbatim 부합 우선.
      child: Opacity(
        opacity: isEnabled ? 1.0 : 0.38,
        child: Material(
          color: bgColor,
          shape: RoundedRectangleBorder(
            borderRadius: radius,
            side: BorderSide(color: outlineColor, width: 1),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onPressed,
            borderRadius: radius,
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: padHorizontal),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  SvgPicture.asset(
                    iconPath,
                    width: spec.iconSize,
                    height: spec.iconSize,
                    semanticsLabel: null,
                  ),
                  SizedBox(width: logoLabelGap),
                  Flexible(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      // Google production CSS verbatim TextStyle:
                      //   .gsi-material-button { font-size: 14px;
                      //     letter-spacing: 0.25px; font-family: 'Roboto', ... }
                      //   .gsi-material-button-contents { font-weight: 500; }
                      //   "14/20" guide → lineHeight 20pt (height = 20/14).
                      // letterSpacing platform 분기 (사용자 결정 2026-05-17):
                      //   Roboto 0.25 (Google CSS verbatim) / SF Pro Text -0.15
                      //   (Apple HIG SF Pro Text size 14pt 권고 tracking,
                      //   developer.apple.com/design/human-interface-guidelines/
                      //   typography). Roboto 의 0.25 가 SF Pro Text 의 wider
                      //   default tracking 위에 누적되어 시각 자간 과도 발생 →
                      //   iOS 강등 (padding/gap iOS 강등 패턴 mirror).
                      // Apple 패턴 mirror — textTheme.labelLarge.copyWith
                      // 비채택 (사용자 ThemeData drift 회피).
                      style: TextStyle(
                        color: labelColor,
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        height: 20 / 14,
                        letterSpacing: isApplePlatform ? -0.15 : 0.25,
                        fontFamily: labelFontFamily,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

// Phase 13.3 Wave 4 Step 2 (2026-05-15) — Apple 자체 render 함수.
// SDK 위제 (`SignInWithAppleButton`) → custom render 전환. Apple 공식 Logo-only
// SVG 자산 (developer.apple.com/design/resources/ DMG, Black + White variant)
// 채택, Universal Layout 일관 적용.

/// Apple 로그인 button render (R5 — Wave 4 Step 2 자체 render).
///
/// Apple HIG mandate 부합:
/// - 자산 변형 0 ("Never crop" + "Don't add padding" 부합 — SVG 자체 padding 보존)
/// - logo file height = button height ("Match the height of the logo file
///   to the height of the button" HIG mandate)
/// - light = Black variant SVG (rect 흰 + logo 검정) / dark = White variant SVG
///   (rect 검정 + logo 흰) — Theme.brightness 자동 매핑
///
/// Universal Layout Pattern:
/// - SVG 정사각 외곽 색 (rect 의 #FFFFFF or #000000) = wrapper bg 색 일치 →
///   정사각 외곽 invisible, visual = Apple logo 단독 + 라벨
/// - 라벨 자체 render (ARB `authAppleSignIn`)
Widget _renderAppleButton(
  BuildContext context,
  BrandSpec spec,
  String label,
  VoidCallback? onPressed,
) {
  final theme = Theme.of(context);
  final isDark = theme.brightness == Brightness.dark;
  final isEnabled = onPressed != null;
  // Apple HIG variant mapping (V1 옵션 A, 2026-05-17 lock — 260517-uv4 X1):
  //   light theme → Black filled (bg #000000 + Apple logo+label 흰) — HIG
  //     maximum-contrast pairing. Logo-only SVG light variant (rect 검정 +
  //     logo 흰), wrapper bg 일치 → SVG 정사각 외곽 invisible.
  //   dark theme → White filled (bg #FFFFFF + Apple logo+label 검정) — HIG
  //     maximum-contrast pairing. Logo-only SVG dark variant (rect 흰 +
  //     logo 검정), wrapper bg 일치 → SVG 정사각 외곽 invisible.
  final bgColor = isDark ? Colors.white : Colors.black;
  final fgColor = isDark ? Colors.black : Colors.white;
  final iconPath =
      '$kBrandAssetBase/apple/${isDark ? "light" : "dark"}/btn_signin_icon.svg';
  final radius = BorderRadius.circular(spec.borderRadius);
  // Phase 13.3 Wave 4 Step 3 (2026-05-16) — Apple Sign-in 라벨 fontFamily 결정.
  // iOS/macOS 환경: system 'SF Pro Text' (Apple OS system font, OS license 의
  // 일부 — Apple Font License Agreement 부합) — 시각 Apple Button generator
  // 와 정확 매칭. Android/Linux/Windows/test env: Inter Medium (SIL OFL 1.1,
  // SF Pro 와 가장 유사한 license-safe alternative) asset 사용.
  // 명시적 platform 분기 사유: Flutter font resolution 의 `fontFamilyFallback`
  // 가 test env 에서 unregistered fontFamily 일 때 작동 안 함 (Ahem fallback
  // 발생). platform 별 직접 fontFamily 선택으로 회피.
  final platform = theme.platform;
  final isApplePlatform =
      platform == TargetPlatform.iOS || platform == TargetPlatform.macOS;
  final labelFontFamily = isApplePlatform ? 'SF Pro Text' : 'Inter';
  return Semantics(
    button: true,
    enabled: isEnabled,
    label: label,
    onTap: onPressed,
    excludeSemantics: true,
    child: SizedBox(
      width: double.infinity,
      height: spec.height,
      child: Opacity(
        opacity: isEnabled ? 1.0 : 0.5,
        child: Material(
          color: bgColor,
          shape: RoundedRectangleBorder(borderRadius: radius),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onPressed,
            borderRadius: radius,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Phase 13.3 Wave 4 Step 3 (2026-05-16) — Apple Button API
                  // (id.apple.com/IDMSEmailVetting siwa-demo.js) verbatim
                  // R['small'] geometry 채택. HIG mandate 부합 + Apple internal
                  // detail 부합:
                  //   logoWidth = floor(R.small.logoWidth × button.height / R.small.height)
                  //             = floor(12 × 48/44) = 13dp
                  //   SVG height = button.height (HIG mandate)
                  //   viewBox "6 0 12 44" (Apple Button API _ 함수 verbatim)
                  SvgPicture.asset(
                    iconPath,
                    width: 13,
                    height: spec.height,
                    semanticsLabel: null,
                  ),
                  // Apple Button API U 함수 verbatim — middleMargin SizedBox.
                  // U 함수: c = floor(0.7 × logoWidth) = 9, default labelPosition
                  // 0 → r 가 l = a + o + c = 28 으로 clamp → middleMargin D =
                  // r - p - o = 28 - 6 - 13 = 9dp.
                  // (Apple internal layout spec, HIG 미명시)
                  const SizedBox(width: 9),
                  Flexible(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      // Phase 13.3 Wave 4 Step 3 (2026-05-16) — Apple Button API
                      // verbatim textStyle + license-safe font 매핑.
                      //
                      // Font 분석 결과 (id.apple.com 의 siwa-demo.js inline WOFF
                      // 추출): family 'SF Pro Text', weight Medium (w500, font
                      // name table verbatim). Button API JS 의 `fontWeight: "400"`
                      // CSS 명세는 font 파일이 단일 Medium glyph 만 가져 무시됨
                      // → visible weight = Medium.
                      //
                      // License 결정: Apple SF Pro Font License Agreement
                      // (developer.apple.com/fonts/) 의 2.A "iOS/OS X/tvOS only"
                      // + 2.B "may not embed... in any software programs" 조항
                      // 위반 회피 — Apple Font binary 미배포. iOS/macOS 환경에서
                      // system 'SF Pro Text' 자동 fallback (Apple OS license 의
                      // 일부). 다른 환경 (Android/Linux) 에서는 Inter Medium
                      // (SIL Open Font License 1.1, SF Pro 와 가장 시각적으로
                      // 유사한 license-safe alternative) fallback.
                      //
                      // 적용 (Phase 13.3 code review WR-02 정정 2026-05-17):
                      //   fontFamily: 'SF Pro Text' (iOS/macOS system font) /
                      //               'Inter' (Android/Linux/test env)
                      //   fontSize: 20 (= 0.43 × 48 HIG mandate)
                      //   fontWeight: w400 (Apple Button API CSS verbatim —
                      //     `fontWeight: "400"`. Apple font 파일은 단일 Medium
                      //     glyph 이라 CSS 의 400 declare 가 무시되어 visible
                      //     weight = Medium. Inter 는 w400 (Regular) 사용 —
                      //     Apple SF Pro Text Medium 의 visual weight 시각
                      //     매칭. Inter Medium 자산은 future use 대비 보존).
                      //   letterSpacing: -0.44 (= -0.022em × 20sp, Button API verbatim)
                      // Phase 13.3 Wave 4 Step 3 — platform 별 fontFamily 단일
                      // 명시 (위 `labelFontFamily` 변수 참조). `fontFamilyFallback`
                      // 비채택 사유: Flutter test env 에서 unregistered fontFamily
                      // 의 fallback resolution 가 Ahem 으로 직접 점프 (fallback
                      // 우회) — fontFamilyFallback 작동 안 함.
                      style: TextStyle(
                        color: fgColor,
                        fontSize: 20,
                        // Apple Button API CSS `fontWeight: "400"` verbatim
                        // (Phase 13.3 WR-02 정정 2026-05-17). Apple SF Pro Text
                        // 자체는 system font 가 단일 Medium glyph 만 제공해
                        // visible weight 가 Medium 이지만, Button API 의 CSS
                        // declare 는 400 이라 verbatim 부합. Inter Regular w400
                        // 가 SF Pro Text Medium 의 visual weight 시각 매칭.
                        // golden 재생성 회피 위해 w400 유지 (Apple visual
                        // weight 변경 시 사용자 visual sign-off 의무).
                        fontWeight: FontWeight.w400,
                        letterSpacing: -0.44,
                        fontFamily: labelFontFamily,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

/// 자상 file path resolver — Facebook 단일 caller 잔존 (Phase 13.3 cleanup 후).
///
/// **Phase 13.3 Wave 2 (R1/R2/R3 정정) + Wave 4 Step 2:** Kakao/Naver/Google
/// branch 모두 폐기 — Kakao/Naver 는 각 `_renderXxxButton` 내부에서
/// `SvgPicture.asset` 으로 직접 자산 파일 (`assets/brand/{kakao,naver}/
/// btn_signin_icon.svg`) 로딩, Google 은 본 함수 미경유의 직접 path inline
/// (`_renderGoogleButton` 내부). Facebook branch만 보존 (Phase 13.2
/// `_renderFacebookButton` 가 호출 — Pitfall 7 변경 0 강제).
String _iconAssetFor(BuildContext context, BrandSpec spec) {
  return switch (spec) {
    // Phase 13.2 — see ROADMAP.md (R6 — FacebookSpec _iconAssetFor branch
    // active, D-96 Google 패턴 locale 독립 단일 path). Localizations
    // dependency 미사용 — locale 변경 시 rebuild trigger 0.
    FacebookSpec() => '$kBrandAssetBase/facebook/btn_signin_icon.svg',
    // 다른 spec 은 자상 path 호출 안 됨 (Apple/Line/Wechat — SDK 위제 위임 또는
    // placeholder render. Kakao/Naver — 각 _renderXxxButton 내부에서
    // SvgPicture.asset 으로 `assets/brand/{kakao,naver}/btn_signin_icon.svg`
    // 직접 로딩 (Wave 4 Step 2 자산 분리). Google — _renderGoogleButton 내부
    // 직접 path inline).
    //
    // Phase 13.3 code review WR-05 정정 (2026-05-17): dead branch 의 sentinel
    // `''` 반환 → `throw UnsupportedError` fail-loud 전환. future caller 가
    // 실수로 호출 시 silent fail (빈 path → asset load runtime error) 대신
    // 호출 자체가 즉시 surface. _resolveLabel 의 default branch 와 동일 패턴.
    AppleSpec() ||
    KakaoSpec() ||
    NaverSpec() ||
    GoogleSpec() ||
    LineSpec() ||
    WechatSpec() => throw UnsupportedError(
      '_iconAssetFor: ${spec.runtimeType} 는 _renderXxxButton 내부에서 직접 '
      '자상 path 처리 (Apple/Line/Wechat = SDK 위제 또는 placeholder, '
      'Kakao/Naver = SvgPicture.asset 직접 로딩, Google = inline path). '
      'Facebook 단독 caller — caller path 회귀 차단.',
    ),
  };
}

/// LINE/WeChat placeholder render — D-73 (자상 미존재 시 회색 fallback).
///
/// production 빌드는 회색 disabled 외관 (R10).
///
/// **Phase 13.1 REVIEW CR-03 정정 (2026-05-10):** placeholder 본문 텍스트가
/// `'Asset missing: $label'` 하드코딩 영어로 ARB 미경유 → ja/ko 사용자에게
/// 영어 노출 회귀 발생. `authBrandAssetMissing` ARB 키 신규 + l10n 해석
/// 라벨 사용. memory feedback_review_recurring_issues.md 9대 패턴 #2
/// (ARB 미사용 하드코딩 문자열) 직접 정정.
///
/// **Phase 13.1 REVIEW iter2 WR-02 정정 (2026-05-10):** `onPressed` 매개변수
/// 제거 (시그니처 단순화 — 본 함수는 InkWell/GestureDetector 미사용으로 탭
/// 처리 없음, 호출자에게 placeholder 가 탭 가능한 것처럼 시사하던 시그니처
/// dead parameter 정리). docstring 의 "회색 disabled 외관 (R10)" 의도를 시그
/// 니처에도 반영 — Phase 14/16 자상 commit 시점까지 비활성 외관 보장.
///
/// **Phase 13.1 REVIEW iter3 WR-02 정정 (2026-05-10):** `assert(() {
/// debugPrint(...); }())` side-effect 폐기. 본 assert 는 debug 빌드에서만
/// 실행되지만 `flutter test` 환경 default 가 debug 모드라 LineSpec/WechatSpec
/// 가 build() 진입 시마다 stdout 에 noise 출력 (T-13.1-PLACEHOLDER-01/02 +
/// 추후 widget test 마다 1줄씩) — reviewer 가 진짜 에러 메시지와 구분 어려움.
/// `kPlaceholderProviders` list 자체가 sentinel 단일 책임 (D-74) — list 에서
/// 'line' / 'wechat' 제거 시 build() 의 LineSpec/WechatSpec 분기 자체가
/// unreachable (Phase 14/16 strategy 가 BrandedSocialButton.line() /
/// .wechat() 호출 안 함). debugPrint 가 누락 detection 가치 0 + runtime
/// noise 만 부담 → 폐기.
Widget _renderPlaceholder(BuildContext context, BrandSpec spec, String label) {
  final l10n = AppLocalizations.of(context);
  // Phase 13.3 code review WR-04 정정 (2026-05-17): 5 active provider
  // (Kakao/Naver/Google/Facebook/Apple) 모두 `Material(shape:
  // RoundedRectangleBorder(...))` 패턴을 사용 — placeholder 도 5 provider
  // 일관성 의무 (future 갱신자가 LINE/WeChat 자상화 시 5 provider 패턴 mirror
  // 의도). `Material.borderRadius` 매개변수에서 `shape` 로 전환.
  return SizedBox(
    width: double.infinity,
    height: spec.height,
    child: Material(
      color: Colors.grey.shade200,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(spec.borderRadius),
      ),
      clipBehavior: Clip.antiAlias,
      child: Center(
        child: Text(
          l10n.authBrandAssetMissing(label),
          style: TextStyle(fontSize: 14, color: Colors.grey.shade700),
        ),
      ),
    ),
  );
}

// Phase 13.1 REVIEW iter2 WR-04 정정 (2026-05-10):
// 본 file 하단의 dead retention 주석 (5 source const + 5 *_Retained mirror
// sentinel 의 "BI 단일 진실원 가치 보유" 표현) 은 file 상단 (line 10-21)
// 주석의 "source const 폐기" 표현과 모순 — 실제 production 코드 grep 결과
// `_kKakaoYellow` / `_kKakaoLabel` / `_kKakaoIcon` / `_kNaverGreen` /
// `_kNaverLabel` 5개 const 모두 file 에서 제거됨. 모순 주석을 단일 진실 표현
// 으로 정정 — 상단 주석이 권위 (해당 진실 단독 보유). 향후 Phase 18 Brand
// Center 마이그 시 fallback 색 reference 가 필요하면 그 시점에 신규 const
// 도입 의무 (file 상단 주석 line 18-20 명시).
