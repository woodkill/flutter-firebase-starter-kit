// Phase 13.1 — see ROADMAP.md (D-61 sealed BrandSpec hierarchy + R1/R2/R8 정정)
// Phase 13.3 — see ROADMAP.md (D-107 symbol SVG raw verbatim inline,
//             RESEARCH §1.1 + §1.2 — Wave 1 const 주입)

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

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

// Phase 13.3 — Wave 1 D-107 symbol SVG raw const (RESEARCH §1.1 + §1.2):
//
// Wave 2 의 `_renderKakaoButton` / `_renderNaverButton` 가 `SvgPicture.string`
// 으로 본 const 를 inline render. 외부 asset 분리 시 drift risk (D-107) —
// file 내 private const 단일 진실원 채택.
//
// Audit trail:
// - `_kKakaoSymbolSvg`: Kakao 공식 PSD 파일 (`kakao_login_original.psd`,
//   developers.kakao.com 다운로드) psd-tools v1.17 verbatim 추출 —
//   `축약_국문/Large (180px X 90px)/Shape 5` layer, 9 knots Bezier path,
//   bbox 40x37 (PSD layer 좌표 기준 normalized). 2026-05-15 Phase 13.3 Wave 4
//   재추출 (svgrepo third-party 폐기, `feedback_official_bi_verification.md`
//   HIGH-trust 충족). fill="currentColor" 채택 — yellow-bg = `Color(0xDD000000)`.
// - `_kNaverSymbolSvg`: Naver 공식 AI 파일 (`developers.naver.com/docs/login/bi/bi.md`,
//   `NAVER_login_KR.ai`, PDF-1.5 vector) PyMuPDF verbatim 추출 —
//   drawing[31] (축약형 Large green N white glyph), 2026-05-15. HIGH-trust
//   audit trail (memory `feedback_official_bi_verification.md` 충족).
//   fill="currentColor" 채택 — green-bg 버튼 = `Colors.white` / white-bg
//   버튼 = `Color(0xFF03A94D)` 로 caller 측 colorFilter 일관 매핑.

/// Kakao 말풍선 symbol SVG raw markup (D-107, RESEARCH §1.1, Phase 13.3 Wave 4
/// 재추출).
///
/// Source: Kakao 공식 PSD (`developers.kakao.com` 다운로드 — `kakao_login_original.psd`,
/// `축약_국문/Large (180px X 90px)/Shape 5` vector layer, 9 knots Bezier).
/// psd-tools v1.17 verbatim 추출 2026-05-15. viewBox = bbox verbatim (padding 0).
const String _kKakaoSymbolSvg =
    '<?xml version="1.0" encoding="UTF-8" standalone="no"?>'
    '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 40 37" '
    'width="40" height="37">'
    '<path d="M20 1.94 C10.06 1.94 2 8.19 2 15.91 '
    'C2 20.71 5.12 24.94 9.86 27.45 L7.87 34.78 '
    'C7.69 35.43 8.43 35.95 8.99 35.57 L17.75 29.77 '
    'C18.49 29.84 19.24 29.88 20 29.88 '
    'C29.94 29.88 38 23.63 38 15.91 '
    'C38 8.19 29.94 1.94 20 1.94 Z" '
    'fill="currentColor"/>'
    '</svg>';

/// Naver N symbol SVG raw markup (D-107, RESEARCH §1.2).
///
/// Source: Naver 공식 AI 파일 (`NAVER_login_KR.ai`) PyMuPDF v1 verbatim 추출 —
/// drawing[31] (축약형 Large green N white glyph), 2026-05-15.
/// viewBox 0 0 20 20, single closed polygon (10 line segments, no Bezier).
/// fill="currentColor" — caller 측 `ColorFilter.mode` 또는 wrapping `IconTheme`
/// 으로 green-bg = `Colors.white` / white-bg = `Color(0xFF03A94D)` 매핑.
const String _kNaverSymbolSvg =
    '<?xml version="1.0" encoding="UTF-8" standalone="no"?>'
    '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 20 20" '
    'width="20" height="20">'
    '<path d="M13.561 10.706 L6.146 0.0 L0.0 0.0 L0.0 20.0 L6.439 20.0 '
    'L6.439 9.298 L13.854 20.0 L20.0 20.0 L20.0 0.0 L13.561 0.0 Z" '
    'fill="currentColor"/>'
    '</svg>';

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

/// LINE 19 언어 placeholder — D-63 type-skeleton.
///
/// Phase 14 진입 시 19 entries 로 확장 — enum 재조정 부담 0.
enum LineLanguage {
  /// 한국어.
  ko,

  /// 영문.
  en,

  /// 일본어 — LINE 본사 시장.
  ja,
}

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
/// Phase 13.3 R2: `_renderKakaoButton` 가 `_kKakaoSymbolSvg` inline render —
/// [assetType] 은 `AssetType.svg` (Wave 2 inline SVG dispatch tag 일관).
class KakaoSpec extends BrandSpec {
  /// const 생성자 — 공통 default (height 48 / radius 12 / icon 18) 사용.
  const KakaoSpec();

  @override
  AssetType get assetType => AssetType.svg;
}

/// Naver 로그인 버튼 spec — D-61 sub-class.
///
/// Phase 13.3 R3: theme 필드 폐기 (caller 측 Theme.brightness 자동 분기 미사용,
/// Naver BI 단일 그린 #03A94D 강제). `_renderNaverButton` 가 `_kNaverSymbolSvg`
/// inline render — [assetType] 은 `AssetType.svg`.
class NaverSpec extends BrandSpec {
  /// const 생성자.
  const NaverSpec();

  @override
  AssetType get assetType => AssetType.svg;
}

/// Google 로그인 버튼 spec — D-61 sub-class.
///
/// Phase 13.3 R1: theme 필드 폐기 (caller 측 명시 매개변수 → `_renderGoogleButton`
/// 내부 Theme.brightness 자동 분기로 차원 축소). [assetType] 은 `AssetType.svg`
/// (Google Identity btn_signin_icon.svg).
class GoogleSpec extends BrandSpec {
  /// const 생성자.
  const GoogleSpec();

  @override
  AssetType get assetType => AssetType.svg;
}

/// Apple 로그인 버튼 spec — D-62 thin wrapper (SDK 위제 위임).
///
/// 본 spec 자체는 시각 사양 없음 — `SignInWithAppleButton` 위제가 HIG 강제
/// 사양 모두 처리. height 는 SDK 기본 44 (HIG 권장값, D-72-CLARIFY-1).
class AppleSpec extends BrandSpec {
  /// const 생성자.
  const AppleSpec();

  @override
  AssetType get assetType => AssetType.none;
}

/// Facebook 로그인 버튼 spec — Phase 13.2 완료 (옵션 A pivot, Wave 0 lock).
///
/// `_renderFacebookButton` 호출 단독 — Apple `SignInWithAppleButton` 패턴
/// mirror. `Theme.brightness` 자동 분기 + 18dp Primary Logo PNG 자상
/// (`assets/brand/facebook/facebook_login.png`) + ARB `authFacebookSignIn`
/// 라벨 + 1dp outline + Material radius 12dp. Meta brand pack 의 logo-only
/// 자상 (wide baked-in 미제공) 으로 Naver/Kakao/Google wide 자상 통째 buttons
/// 패턴 적용 불가 — Apple SDK 위제 패턴 mirror 의무 (옵션 A pivot).
///
/// **D-95 lock:** `AssetType.png` (Meta Primary Logo PNG 단독, SVG 미제공).
/// **D-94 lock:** theme 필드 부재 (Primary 단독 채택, Kakao 패턴 mirror).
/// **D-96 lock:** locale 독립 (단일 path, lang 분기 부재).
class FacebookSpec extends BrandSpec {
  /// const 생성자 — 공통 default (height 48 / radius 12 / icon 18) 사용.
  const FacebookSpec();

  @override
  AssetType get assetType => AssetType.png;
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
    return switch (spec) {
      AppleSpec() => SizedBox(
        width: double.infinity,
        child: SignInWithAppleButton(
          // D-72-CLARIFY-2 — borderRadius 는 BorderRadius 타입 의무.
          borderRadius: BorderRadius.circular(spec.borderRadius),
          // Phase 13.3 R5 — Theme.brightness 자동 매핑 (HIG 권장값):
          // light → .black / dark → .white. caller 측 style: parameter 부재.
          style: Theme.of(context).brightness == Brightness.dark
              ? SignInWithAppleButtonStyle.white
              : SignInWithAppleButtonStyle.black,
          text: label,
          onPressed: onPressed,
          // D-72-CLARIFY-1 — height SDK 기본 44 존종, SizedBox 래핑 안 함.
        ),
      ),
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
Widget _renderKakaoButton(
  BuildContext context,
  BrandSpec spec,
  String label,
  VoidCallback? onPressed,
) {
  final radius = BorderRadius.circular(spec.borderRadius);
  final isEnabled = onPressed != null;
  // Kakao BI verbatim (UI-SPEC):
  //   bg = #FEE500 (Kakao yellow, 단일 색)
  //   fg = #000000 85% alpha (Kakao Design Guide).
  const bgColor = Color(0xFFFEE500);
  const fgColor = Color(0xDD000000);
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
                  SvgPicture.string(
                    _kKakaoSymbolSvg,
                    width: spec.iconSize,
                    height: spec.iconSize,
                    semanticsLabel: null,
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(
                        context,
                      ).textTheme.labelLarge?.copyWith(color: fgColor),
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
Widget _renderNaverButton(
  BuildContext context,
  BrandSpec spec,
  String label,
  VoidCallback? onPressed,
) {
  final radius = BorderRadius.circular(spec.borderRadius);
  final isEnabled = onPressed != null;
  // Naver BI verbatim (UI-SPEC + 사용자 캡처 2026-05-14):
  //   bg = #03A94D (Naver ID 로그인 BI green). NCloud SSO #03C75A 비채택.
  //   fg = Colors.white (BI default — 흰 N glyph + 흰 라벨 1:1 일관).
  const bgColor = Color(0xFF03A94D);
  const fgColor = Colors.white;
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
                  SvgPicture.string(
                    _kNaverSymbolSvg,
                    width: spec.iconSize,
                    height: spec.iconSize,
                    semanticsLabel: null,
                    colorFilter: const ColorFilter.mode(
                      fgColor,
                      BlendMode.srcIn,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(
                        context,
                      ).textTheme.labelLarge?.copyWith(color: fgColor),
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

/// Facebook 전용 render — 옵션 A pivot (Wave 0 lock).
///
/// **옵션 A pivot 의무 (13.2-WAVE0-LOCK.md):** Meta brand pack 은 logo-only
/// 자상 (Primary Logo 2084×2084 square PNG) 단독 제공 — Kakao/Naver/Google 의
/// wide 자상 통째 buttons 패턴 (자상에 배경+라벨+로고 모두 baked-in) 적용
/// 불가. Apple `SignInWithAppleButton` SDK 위제 패턴 mirror 의무 — Logo 18dp
/// icon 슬롯 + ARB 라벨 외부 layer + Theme.brightness 자동 분기 + 1dp outline.
///
/// **render 사양 매트릭스:**
/// - SizedBox: `width: double.infinity` / `height: spec.height` (48dp).
/// - Material: light = white bg / dark = black bg, `borderRadius: 12dp`,
///   `clipBehavior: Clip.antiAlias` (Apple 패턴 mirror).
/// - 1dp outline: light = `Colors.black12` / dark = `Colors.white24`.
/// - InkWell: `borderRadius: 12dp`, ripple 영역 제어.
/// - Row: `padding: EdgeInsets.symmetric(horizontal: 12)` + `gap 8dp` (SizedBox
///   8dp, Phase 13.1 appSpacing.sm 일관).
/// - Image.asset: `assets/brand/facebook/facebook_login.png`, 18×18 (Phase 13.1
///   iconSize 일관), `excludeFromSemantics: true`.
/// - Text: `authFacebookSignIn` ARB 라벨, fontSize 14 / fontWeight w500 /
///   letterSpacing 0.1 (Phase 13.1 D-82 머레).
/// - Semantics 외부 layer 단독 권위: `button: true`, `enabled: onPressed != null`,
///   `label`, `onTap: onPressed`, `excludeSemantics: true` (Phase 13.1 a11y
///   layer 패턴 머레, iter2 CR-01 정정 일관).
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
  // Phase 13.2 REVIEW IN-01 정정 (2026-05-13): Theme.of(context) 중복 호출
  // 폐기 — 단일 lookup 후 colorScheme/brightness 재사용.
  final theme = Theme.of(context);
  final colorScheme = theme.colorScheme;
  final isDark = theme.brightness == Brightness.dark;
  // Phase 13.2 REVIEW CR-01 정정 (2026-05-13): onPressed == null 일 때 시각
  // disabled cue 누락 회귀. social_button.dart docstring 의 "Material default
  // disabled 외관" 약속과 일치하도록 (1) Opacity 0.5 wrap (Material 3 disabled
  // state cue), (2) fgColor / outlineColor 의 faded variant 분기로 보강.
  // 회귀 가드는 branded_social_button_test.dart 의 T-13.2-FACEBOOK-DISABLED-01
  // (Opacity 검증) + T-13.2-FACEBOOK-A11Y-02 (isEnabled false) 가 책임.
  final isEnabled = onPressed != null;
  // Phase 13.2 UI-REVIEW Pillar 3 정정: WAVE0-LOCK render spec 명시 토큰화.
  // light bg = Colors.white (locked literal), dark bg = colorScheme.surface,
  // outline = Colors.grey.shade300 (light) / Colors.grey.shade700 (dark),
  // fg = colorScheme.onSurface (Material 3 contrast 보장).
  final bgColor = isDark ? colorScheme.surface : Colors.white;
  final fgColor = isEnabled
      ? colorScheme.onSurface
      : colorScheme.onSurface.withValues(alpha: 0.38);
  final outlineColor = isEnabled
      ? (isDark ? Colors.grey.shade700 : Colors.grey.shade300)
      : (isDark ? Colors.grey.shade800 : Colors.grey.shade200);
  return Semantics(
    button: true,
    enabled: isEnabled,
    label: label,
    onTap: onPressed,
    excludeSemantics: true,
    child: SizedBox(
      width: double.infinity,
      height: spec.height,
      // Phase 13.2 REVIEW CR-01 — Material 3 disabled state 시각 cue
      // (0.5 opacity wrap). 활성 시 1.0 으로 기존 외관 보존.
      child: Opacity(
        opacity: isEnabled ? 1.0 : 0.5,
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
                  // Phase 13.2 REVIEW IN-03 정정 (2026-05-13): Meta Primary
                  // Logo PNG (2084×2084 square) 를 18dp icon 슬롯에 렌더 —
                  // cacheWidth/cacheHeight 미지정 시 full 2084×2084 decoded
                  // ARGB (~17 MB) 메모리 캐시. devicePixelRatio 기반 cache
                  // 사이즈 (예: 3.0 DPR → 54px) 로 메모리 footprint 격감.
                  Image.asset(
                    assetPath,
                    width: spec.iconSize,
                    height: spec.iconSize,
                    cacheWidth:
                        (spec.iconSize *
                                MediaQuery.of(context).devicePixelRatio)
                            .round(),
                    cacheHeight:
                        (spec.iconSize *
                                MediaQuery.of(context).devicePixelRatio)
                            .round(),
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
                      // Phase 13.2 UI-REVIEW Pillar 4 정정: WAVE0-LOCK Text
                      // slot spec — textTheme.labelLarge 토큰 사용, fg
                      // 색상은 위에서 계산한 fgColor (disabled 시 38%) 으로
                      // copyWith 주입.
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: fgColor,
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
/// Universal Layout Pattern + surface bg + #747775(L)/#8E918F(D) 1dp outline
/// + btn_signin_icon.svg + ARB authGoogleSignIn 라벨. Theme.brightness 자동
/// 분기. Google Identity Guidelines stroke 색 verbatim (light/dark 2 hex).
Widget _renderGoogleButton(
  BuildContext context,
  BrandSpec spec,
  String label,
  VoidCallback? onPressed,
) {
  final theme = Theme.of(context);
  final colorScheme = theme.colorScheme;
  final isDark = theme.brightness == Brightness.dark;
  final isEnabled = onPressed != null;
  // Google Identity Guidelines stroke verbatim (UI-SPEC):
  //   light = #747775 / dark = #8E918F (1dp outline).
  final outlineColor = isDark
      ? const Color(0xFF8E918F)
      : const Color(0xFF747775);
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
      child: Opacity(
        opacity: isEnabled ? 1.0 : 0.5,
        child: Material(
          color: colorScheme.surface,
          shape: RoundedRectangleBorder(
            borderRadius: radius,
            side: BorderSide(color: outlineColor, width: 1),
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
                  SvgPicture.asset(
                    iconPath,
                    width: spec.iconSize,
                    height: spec.iconSize,
                    semanticsLabel: null,
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: colorScheme.onSurface,
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
/// **Phase 13.3 Wave 2 (R1/R2/R3 정정):** Kakao/Naver/Google branch 모두 폐기
/// — Kakao/Naver 는 inline SVG (`SvgPicture.string`), Google 은 본 함수 미경유
/// 의 직접 path inline (`_renderGoogleButton` 내부). Facebook branch만 보존
/// (Phase 13.2 `_renderFacebookButton` 가 호출 — Pitfall 7 변경 0 강제).
String _iconAssetFor(BuildContext context, BrandSpec spec) {
  return switch (spec) {
    // Phase 13.2 — see ROADMAP.md (R6 — FacebookSpec _iconAssetFor branch
    // active, D-96 Google 패턴 locale 독립 단일 path). Localizations
    // dependency 미사용 — locale 변경 시 rebuild trigger 0.
    FacebookSpec() => '$kBrandAssetBase/facebook/facebook_login.png',
    // 다른 spec 은 자상 path 호출 안 됨 (Apple/Line/Wechat — SDK 위제 위임 또는
    // placeholder render. Kakao/Naver — inline SVG. Google — _renderGoogleButton
    // 내부 직접 path inline).
    AppleSpec() ||
    KakaoSpec() ||
    NaverSpec() ||
    GoogleSpec() ||
    LineSpec() ||
    WechatSpec() => '',
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
  return SizedBox(
    width: double.infinity,
    height: spec.height,
    child: Material(
      color: Colors.grey.shade200,
      borderRadius: BorderRadius.circular(spec.borderRadius),
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
