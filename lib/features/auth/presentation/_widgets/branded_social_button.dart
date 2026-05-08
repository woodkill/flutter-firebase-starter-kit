// Phase 13.1 — see ROADMAP.md (D-61 sealed BrandSpec hierarchy + R1/R2/R8 정정)

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:gap/gap.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

import '../../../../core/theme/theme_extensions.dart';
import '_brand_assets.dart';

// 5 active provider brand 색 — 단일 진실원 보존 (R1 정정 + Phase 13 D-55 mirror).
//
// **R1 (Phase 13.1):** Naver 그린은 NAVER ID 로그인 BI
// (developers.naver.com/docs/login/bi/bi.md) 의 `#03A94D` — NAVER Corp 회사
// 브랜드 (`#03C75A`, NCloud SSO 컨텍스트) 와 컨텍스트 분리. Phase 13 단계는
// third-party 출처 채택 오류 (memory feedback_official_bi_verification),
// Phase 13.1 정정.

/// Kakao 공식 노란색 — Kakao Brand Guideline 강제 (#FEE500).
const Color _kKakaoYellow = Color(0xFFFEE500);

/// Kakao 가이드 권장 라벨 색 — 검정 ~85% 불투명.
///
/// 노란 배경 0xFFFEE500 와의 contrast 약 11.7:1 으로 WCAG AAA 충족.
const Color _kKakaoLabel = Color(0xD9000000);

/// KakaoTalk 말풍선 로고 색 — 검정 100% (Kakao 디자인 자상 그대로).
const Color _kKakaoIcon = Color(0xFF000000);

/// Naver 공식 그린 — NAVER ID 로그인 BI (#03A94D). R1 정정 (Phase 13.1).
///
/// 회사 브랜드 (`#03C75A`, NAVER Corp + NCloud SSO) 와 컨텍스트 분리. 본
/// 상수는 로그인 버튼 BI 전용 — `developers.naver.com/docs/login/bi/bi.md`
/// verbatim. dark variant 자상은 별도 PNG (BlendMode.srcIn 변환 금지 — R3/R4
/// BI 위반).
const Color _kNaverGreen = Color(0xFF03A94D);

/// Naver 가이드 권장 라벨 색 — 흰 100% (그린 배경에 contrast >= 4.5:1).
const Color _kNaverLabel = Color(0xFFFFFFFF);

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

  /// 자상 미사용 — Apple/Facebook (위제 위임) + LINE/WeChat (placeholder).
  none,
}

/// Naver 다크 모드 분기 (D-I — Theme.brightness 자동 매핑은 caller 책임).
enum NaverTheme {
  /// 흰 surface — `_kNaverGreen` 배경 + 흰 라벨.
  light,

  /// dark surface — Naver BI 의 dark variant PNG 자상 (Plan 13.1-08 commit 후).
  dark,
}

/// Naver 라벨 변형 — D-63 placeholder.
enum NaverLabelVariant {
  /// 한국어 라벨 — Naver BI 화이트리스트 4 변형 중 starter-kit 채택값.
  ko,

  /// 영문 라벨 — Naver BI 영문 'Continue with Naver'.
  en,
}

/// Google 라벨/배경 변형 — D-64 명시 매개변수.
enum GoogleTheme {
  /// 흰 surface — Google Identity Branding Light 변형.
  light,

  /// dark surface — Google Dark 변형.
  dark,

  /// neutral 배경 — caller 명시 시만 사용.
  neutral,
}

/// Kakao 라벨 변형 — D-63 placeholder.
enum KakaoLabelVariant {
  /// 한국어 라벨 — Kakao BI ko 라벨.
  ko,

  /// 영문 라벨 — Kakao BI en 라벨 'Continue with Kakao'.
  en,
}

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
class KakaoSpec extends BrandSpec {
  /// const 생성자 — 공통 default (height 48 / radius 12 / icon 18) 사용.
  const KakaoSpec();

  @override
  AssetType get assetType => AssetType.png;
}

/// Naver 로그인 버튼 spec — D-61 sub-class.
///
/// [theme] 은 caller 명시 — `social_button.dart` 가 `Theme.of(context).brightness`
/// 로 자동 매핑한다 (D-I).
class NaverSpec extends BrandSpec {
  /// const 생성자 — [theme] 은 명시 매개변수.
  const NaverSpec({required this.theme});

  /// 다크 / 라이트 변형 dispatch.
  final NaverTheme theme;

  @override
  AssetType get assetType => AssetType.png;
}

/// Google 로그인 버튼 spec — D-61 sub-class.
///
/// [theme] 은 caller 명시 매개변수 — Naver 의 자동 분기 (D-I) 와 다름. Google
/// 만 3 변형 (Light/Dark/Neutral) 차원이라 명시 매개변수 의무 (D-64).
class GoogleSpec extends BrandSpec {
  /// const 생성자 — [theme] 은 명시 매개변수.
  const GoogleSpec({required this.theme});

  /// 라이트 / 다크 / 뉴트럴 변형 dispatch.
  final GoogleTheme theme;

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

/// Facebook 로그인 버튼 spec — sign_in_button community package 위임 wrapper.
///
/// 본 spec 의 `BrandedSocialButton.build()` 도달 시 `UnsupportedError` —
/// `social_button.dart` 의 Facebook 분기에서 직접 `SignInButton(Buttons.facebookNew)`
/// 호출 (R12 acceptance, sign_in_button 패키지 보존).
class FacebookSpec extends BrandSpec {
  /// const 생성자.
  const FacebookSpec();

  @override
  AssetType get assetType => AssetType.none;
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
  const BrandedSocialButton._({
    required this.spec,
    required this.label,
    required this.onPressed,
    this.appleStyle,
    super.key,
  });

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

  /// Naver named factory — [theme] 명시 매개변수.
  ///
  /// `social_button.dart` 가 `Theme.of(context).brightness` 로 자동 매핑한다
  /// (D-I — Naver 자동 분기는 caller 책임).
  factory BrandedSocialButton.naver({
    required String label,
    required NaverTheme theme,
    required VoidCallback? onPressed,
    Key? key,
  }) => BrandedSocialButton._(
    key: key,
    spec: NaverSpec(theme: theme),
    label: label,
    onPressed: onPressed,
  );

  /// Google named factory — D-64 명시 매개변수 (3 변형).
  factory BrandedSocialButton.google({
    required String label,
    required GoogleTheme theme,
    required VoidCallback? onPressed,
    Key? key,
  }) => BrandedSocialButton._(
    key: key,
    spec: GoogleSpec(theme: theme),
    label: label,
    onPressed: onPressed,
  );

  /// Apple named factory — D-62 thin wrapper (SDK 위제 위임).
  ///
  /// [style] 는 `SignInWithAppleButtonStyle.black` (default) /
  /// `SignInWithAppleButtonStyle.white` /
  /// `SignInWithAppleButtonStyle.whiteOutlined` (D-G-CLARIFY 정확 표기).
  factory BrandedSocialButton.apple({
    required String label,
    required VoidCallback? onPressed,
    SignInWithAppleButtonStyle style = SignInWithAppleButtonStyle.black,
    Key? key,
  }) => BrandedSocialButton._(
    key: key,
    spec: const AppleSpec(),
    label: label,
    onPressed: onPressed,
    appleStyle: style,
  );

  /// Facebook named factory — sign_in_button community package 위임 wrapper.
  ///
  /// 본 factory 는 호출자에게 통합된 인터페이스 제공 — 실제 build 는
  /// `social_button.dart` 의 Facebook 분기에서 직접
  /// `SignInButton(Buttons.facebookNew)` 호출 (R12 acceptance, sign_in_button
  /// 패키지 보존).
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

  /// Apple SDK 위제 style — [AppleSpec] 일 때만 의미.
  final SignInWithAppleButtonStyle? appleStyle;

  @override
  Widget build(BuildContext context) {
    // D-67 — sealed switch exhaustive (Dart 3 컴파일 시점 강제).
    return switch (spec) {
      AppleSpec() => SizedBox(
        width: double.infinity,
        child: SignInWithAppleButton(
          // D-72-CLARIFY-2 — borderRadius 는 BorderRadius 타입 의무.
          borderRadius: BorderRadius.circular(spec.borderRadius),
          // D-G-CLARIFY — whiteOutlined 정확 표기.
          style: appleStyle ?? SignInWithAppleButtonStyle.black,
          text: label,
          onPressed: onPressed,
          // D-72-CLARIFY-1 — height SDK 기본 44 존종, SizedBox 래핑 안 함.
        ),
      ),
      FacebookSpec() => throw UnsupportedError(
        'FacebookSpec 은 social_button.dart 의 Facebook 분기에서 '
        'SignInButton(Buttons.facebookNew) 직접 호출 — '
        'BrandedSocialButton 까지 도달 금지 (R12 acceptance)',
      ),
      LineSpec() ||
      WechatSpec() => _renderPlaceholder(context, spec, label, onPressed),
      KakaoSpec() => _renderActiveButton(context, spec, label, onPressed),
      NaverSpec() => _renderActiveButton(context, spec, label, onPressed),
      GoogleSpec() => _renderActiveButton(context, spec, label, onPressed),
    };
  }
}

/// Active provider (Kakao/Naver/Google) 렌더 — Material + InkWell + 자상 + Text.
Widget _renderActiveButton(
  BuildContext context,
  BrandSpec spec,
  String label,
  VoidCallback? onPressed,
) {
  final spacing = context.appSpacing;
  return SizedBox(
    width: double.infinity,
    height: spec.height,
    child: Material(
      color: _backgroundColorFor(spec),
      borderRadius: BorderRadius.circular(spec.borderRadius),
      child: InkWell(
        onTap: onPressed == null
            ? null
            : () {
                FocusManager.instance.primaryFocus?.unfocus();
                onPressed();
              },
        borderRadius: BorderRadius.circular(spec.borderRadius),
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: spacing.md),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              _brandIcon(context, spec),
              Gap(spacing.sm),
              Text(
                label,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: _foregroundColorFor(spec),
                  height: 20 / 14,
                  letterSpacing: 0.1,
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

/// 자상 렌더 — D-68 assetType 분기 (PNG: Image.asset / SVG: SvgPicture.asset).
///
/// **PNG 색 변환 금지 (RESEARCH Pitfall 7):** `ColorFilter.mode(BlendMode.srcIn)`
/// 적용 시 Naver/Kakao BI 위반 — PNG 자상은 단일 색 baked-in.
///
/// **외부 [SizedBox] 강제 sizing (Plan 13.1-09 R1 hotfix):** [SvgPicture.asset]
/// 는 `width`/`height` 매개변수 + `fit: BoxFit.contain` (default) 만으로는
/// 첫 frame 에 SVG 의 자연 viewBox dimension (예: Google 자상 188×40) 으로
/// layout 되어 부모 [Row] overflow 를 일으킨다 (vector_graphics 의 첫-frame
/// layout 동작). [Image.asset] 도 일관성을 위해 동일 [SizedBox] wrap 적용 —
/// 자상 width/height 가 layout 시점부터 [BrandSpec.iconSize] 로 강제된다.
Widget _brandIcon(BuildContext context, BrandSpec spec) {
  final assetPath = _iconAssetFor(context, spec);
  return SizedBox(
    width: spec.iconSize,
    height: spec.iconSize,
    child: switch (spec.assetType) {
      AssetType.png => Image.asset(
        assetPath,
        fit: BoxFit.contain,
        excludeFromSemantics: true,
      ),
      AssetType.svg => SvgPicture.asset(
        assetPath,
        fit: BoxFit.contain,
        excludeFromSemantics: true,
      ),
      AssetType.none => const SizedBox.shrink(),
    },
  );
}

/// 자상 file path resolver — provider + theme + (Naver/Kakao) locale 분기.
///
/// **Kakao (Plan 13.1-07 결정):** 공식 자상은 density bucket(1x/2x/3x)이 아닌
/// 사이즈 변형(medium 300×45 / large 600×90)을 wide·narrow 두 가로 비율로 제공.
/// 본 starter-kit 은 `완성형 wide`만 채택 (BrandedSocialButton 가로 텍스트
/// 버튼과 일치) — `kakao_login_large_wide.png` (600×90) 를 default 로 사용해
/// 고밀도 디스플레이에서 sharp 하게 렌더. ko/en 두 자상 모두 commit, 로케일에
/// 따라 분기. light only (Kakao BI 는 dark variant 미제공).
///
/// **Naver (Plan 13.1-07 결정):** 공식 자상은 5차원 매트릭스 (theme × locale ×
/// color × variant × height) 로 64 PNG 제공. 본 starter-kit 은 Kakao 의 2배
/// 차원으로 채택 — locale(ko/en) × theme(light/dark) × height(H48/H56) ×
/// variant(wide) = 8 PNG. 자상 색은 Naver BI 사용 패턴 따름: light theme →
/// `Light_${LANG}_green_wide` (흰 배경 위 그린 BI), dark theme →
/// `Dark_${LANG}_white_wide` (검정 배경 위 흰 BI). 코드는 Kakao 패턴 미러로
/// `naver_login_h48_wide.png` (Material Design 표준 button height) 를 default
/// 로 로드, H56 은 future-proof commit (CTA emphasis 시 향후 노출 가능).
/// R4 acceptance: ko/en × light/dark = 4 (theme×locale) 변형 모두 commit.
///
/// **Google (Plan 13.1-07 결정):** 공식 자상은 5차원 매트릭스 (platform ×
/// format × theme × shape × label) 로 360+ 파일 제공 (iOS/Android/Web 별도
/// ZIP). 본 starter-kit 은 mobile single codebase 단순성 + Flutter Material
/// 기반 일관성 따라 **Android + rd shape + ctn label + SVG** 채택 — 6 SVG
/// (3 theme × {full, icon}). cross-platform 사용 라이선스 제약 없음 (Google
/// Identity Branding Guidelines 명시 — "scale the button as needed for
/// different devices"). 자상은 언어 중립 (Roboto 영문 baked-in).
///
/// 공식 ↔ starter-kit 명명 매핑 (full = ctn 라벨, icon = na variant):
///   android_{theme}_rd_ctn.svg → google/{theme}/btn_signin_full.svg
///   android_{theme}_rd_na.svg  → google/{theme}/btn_signin_icon.svg
String _iconAssetFor(BuildContext context, BrandSpec spec) {
  final lang = Localizations.localeOf(context).languageCode == 'ko'
      ? 'ko'
      : 'en';
  return switch (spec) {
    KakaoSpec() =>
      '$kBrandAssetBase/kakao/$lang/light/kakao_login_large_wide.png',
    NaverSpec(theme: final t) =>
      '$kBrandAssetBase/naver/$lang/'
          '${t == NaverTheme.dark ? 'dark' : 'light'}/naver_login_h48_wide.png',
    GoogleSpec(theme: final t) =>
      '$kBrandAssetBase/google/'
          '${t == GoogleTheme.dark ? 'dark' : (t == GoogleTheme.neutral ? 'neutral' : 'light')}'
          '/btn_signin_full.svg',
    // 다른 spec 은 _brandIcon 호출 안 됨 (Apple/Facebook/Line/Wechat).
    AppleSpec() || FacebookSpec() || LineSpec() || WechatSpec() => '',
  };
}

/// 배경 색 resolver.
Color _backgroundColorFor(BrandSpec spec) => switch (spec) {
  KakaoSpec() => _kKakaoYellow,
  NaverSpec(theme: NaverTheme.light) => _kNaverGreen,
  NaverSpec(theme: NaverTheme.dark) => _kNaverGreen,
  // Google 자상 자체에 배경 baked-in — 위제 surface 는 transparent.
  GoogleSpec() => Colors.transparent,
  AppleSpec() ||
  FacebookSpec() ||
  LineSpec() ||
  WechatSpec() => Colors.transparent,
};

/// 라벨 색 resolver.
Color _foregroundColorFor(BrandSpec spec) => switch (spec) {
  KakaoSpec() => _kKakaoLabel,
  NaverSpec() => _kNaverLabel,
  // Google 자상 자체에 라벨 baked-in — 본 widget 의 Text 는 보조 (자상이
  // full button 변형이면 미렌더).
  GoogleSpec() => Colors.black87,
  AppleSpec() ||
  FacebookSpec() ||
  LineSpec() ||
  WechatSpec() => Colors.transparent,
};

/// LINE/WeChat placeholder render — D-73 (자상 미존재 시 회색 fallback).
///
/// debug 시 `debugPrint` 발생 — production 빌드는 회색 disabled 외관 (R10).
Widget _renderPlaceholder(
  BuildContext context,
  BrandSpec spec,
  String label,
  VoidCallback? onPressed,
) {
  assert(() {
    debugPrint(
      'BrandedSocialButton placeholder render — Phase 14/16 자상 commit 후 '
      '_brand_assets.dart 의 kPlaceholderProviders 에서 해당 provider 제거 의무',
    );
    return true;
  }());
  return SizedBox(
    width: double.infinity,
    height: spec.height,
    child: Material(
      color: Colors.grey.shade200,
      borderRadius: BorderRadius.circular(spec.borderRadius),
      child: Center(
        child: Text(
          'Asset missing: $label',
          style: TextStyle(fontSize: 14, color: Colors.grey.shade700),
        ),
      ),
    ),
  );
}

/// 본 파일이 미사용으로 흡수하지 않은 const 색 leak 검사용 sentinel — _kKakaoIcon
/// 은 Kakao 자상이 PNG 마이그레이션 후 일시적으로 사용 안 되지만, 색 mirror
/// 단일 진실원 보존을 위해 남겨둔다 (Plan 13.1-07 자상 commit 후 PNG 내부에
/// baked-in 검정 100%).
// ignore: unused_element
const Color _kKakaoIconRetained = _kKakaoIcon;
