// Phase 13.1 — see ROADMAP.md (D-61 sealed BrandSpec hierarchy + R1/R2/R8 정정)

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
  /// 흰 surface — Naver ID 로그인 BI 그린 (#03A94D, R1 verbatim) 배경 + 흰 라벨.
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
      LineSpec() || WechatSpec() => _renderPlaceholder(context, spec, label),
      KakaoSpec() => _renderActiveButton(context, spec, label, onPressed),
      NaverSpec() => _renderActiveButton(context, spec, label, onPressed),
      GoogleSpec() => _renderActiveButton(context, spec, label, onPressed),
    };
  }
}

/// Active provider (Kakao/Naver/Google) 렌더 — 자상 baked-in shape 권위 패턴.
///
/// **Phase 13.1 Gap-1 X2 (2026-05-09 재설계):** wide 자상 (Kakao 600×90 /
/// Naver 1472×192 / Google viewBox 189×40) 은 logo + 텍스트가 통째로 buttons
/// 외관을 형성하도록 BI 가이드에서 의도됨 — Plan 13.1-05 의 18dp icon 슬롯
/// squash 패턴 폐기. 자상 자체에 배경/라벨/로고/모서리 모두 baked-in 이므로
/// widget 책임은 (1) full-width SizedBox 강제 sizing (2) Material clipBehavior
/// 로 InkWell ripple 영역 12dp rounded 제어 (3) 탭 핸들러 + 비활성 + 포커스
/// unfocus 만. 자상의 시각 외관은 자상이 단독 권위.
///
/// **Plan 14 deviation 정정 (2026-05-09 사용자 시각 검증 후):** 1차 디자인
/// (`fit: BoxFit.fitWidth` + `ClipRRect` 강제 12dp) 이 자상의 자연 종횡비와
/// baked-in 모서리 무시로 4 시각 결함 발생 — (1) Kakao/Naver corner 더블
/// 클리핑 (PNG baked radius < 12dp scaled, ClipRRect 추가 잘림), (2) Google
/// 상하 외곽선 잘림 (4.725:1 자상이 7.5:1 button 에 fitWidth 시 height 76dp
/// overflow), (3) Google text 1.9× 확대 (fitWidth scale-up 부작용), (4)
/// 자상의 자연 corner 모양 (Naver 사각 / Google rx=19.5 pill) 무시.
///
/// **정정 채택:** `fit: BoxFit.contain` + `ClipRRect` 폐기. 자상 자연 종횡비
/// 보존, 크롭 0, baked-in 모서리 시각 권위. letterbox 영역 (Kakao 좌우 ~20dp /
/// Google 좌우 ~67dp) 은 Scaffold 배경 (light 흰 / dark 검정) 으로 자연 채움
/// — Naver dark variant 도 검정 letterbox 와 검정 자상 배경 자연 융합.
///
/// **AppleSpec/FacebookSpec/LineSpec/WechatSpec 영향 없음** — 본 함수는
/// build() 의 KakaoSpec/NaverSpec/GoogleSpec 분기에서만 호출.
///
/// **Phase 13.1 REVIEW CR-01 정정 (2026-05-10):** [label] 매개변수 신규 +
/// 외부 [Semantics] wrap 추가. wide 자상 통째 buttons 패턴이
/// `excludeFromSemantics: true` 를 명시하여 자상 내부 라벨이 a11y tree 에
/// propagate 0 — screen reader 사용자가 라벨 정보 0 노출 회귀 발생. ARB 해석
/// 라벨 (예: '카카오 로그인' / 'Continue with Kakao') 을 외부 [Semantics]
/// 노드에 명시 주입하여 a11y layer 단독 권위.
///
/// **Phase 13.1 REVIEW iter2 CR-01 정정 (2026-05-10):** iter1 의
/// `excludeSemantics: true` + `onTap` 미전달 패턴은 InkWell 의
/// GestureSemantics (활성화 액션 핸들러) 를 시멘틱 트리에서 drop 하여
/// TalkBack/VoiceOver 사용자가 "이중 탭" 명령으로 InkWell 을 활성화 불가
/// 회귀. 옵션 1 채택 — [Semantics.onTap] 에 [onPressed] 명시 전달 + 자식
/// InkWell 의 자동 GestureSemantics 와 중복 회피 위해 `excludeSemantics:
/// true` 보존 (자상의 `excludeFromSemantics: true` 와 정합). 회귀 가드는
/// `branded_social_button_test.dart` 의 시멘틱 액션 검증 test 신규 추가.
Widget _renderActiveButton(
  BuildContext context,
  BrandSpec spec,
  String label,
  VoidCallback? onPressed,
) {
  final assetPath = _iconAssetFor(context, spec);
  final radius = BorderRadius.circular(spec.borderRadius);
  return Semantics(
    button: true,
    enabled: onPressed != null,
    label: label,
    onTap: onPressed,
    excludeSemantics: true,
    child: SizedBox(
      width: double.infinity,
      height: spec.height,
      child: Material(
        color: Colors.transparent,
        // **Plan 14 deviation 정정 (2026-05-09 사용자 시각 검증 2차):** Material
        // 의 `clipBehavior: Clip.antiAlias` 가 자상 child 를 추가로 클립 →
        // 자상의 자연 baked-in corner 무효화 (ClipRRect 폐기로도 해소되지
        // 않은 두 번째 클리핑 layer). `Clip.none` 으로 자상 baked-in shape 가
        // 시각 단독 권위. InkWell 의 `borderRadius: radius` 는 ripple 영역만
        // 계속 12dp 제어 (시각 변경 0).
        clipBehavior: Clip.none,
        child: InkWell(
          // **Phase 13.1 REVIEW WR-03 정정 (2026-05-10):** unfocus 책임은
          // `social_button.dart` 의 caller side wrapper 가 단독 보유 (이미
          // `FocusManager.instance.primaryFocus?.unfocus()` 호출). 이전 버전은
          // InkWell.onTap 에서도 한 번 더 unfocus 호출 → DRY 위반 + Apple
          // (caller 단독) 분기와 일관성 결여. caller 가 onPressed 를 wrap
          // 하므로 본 InkWell 은 onPressed 직접 호출만 책임.
          onTap: onPressed,
          borderRadius: radius,
          child: switch (spec.assetType) {
            AssetType.png => Image.asset(
              assetPath,
              fit: BoxFit.contain,
              alignment: Alignment.center,
              width: double.infinity,
              height: spec.height,
              excludeFromSemantics: true,
            ),
            AssetType.svg => SvgPicture.asset(
              assetPath,
              fit: BoxFit.contain,
              alignment: Alignment.center,
              width: double.infinity,
              height: spec.height,
              excludeFromSemantics: true,
            ),
            AssetType.none => const SizedBox.shrink(),
          },
        ),
      ),
    ),
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
    // Phase 13.1 REVIEW WR-07 정정 (2026-05-10): nested ternary →
    // exhaustive switch. Kakao/Naver 의 단일 ternary 와 일관성 + Dart 3
    // idiomatic + GoogleTheme enum 확장 시 컴파일 fail 강제.
    GoogleSpec(theme: final t) => switch (t) {
      GoogleTheme.dark => '$kBrandAssetBase/google/dark/btn_signin_full.svg',
      GoogleTheme.neutral =>
        '$kBrandAssetBase/google/neutral/btn_signin_full.svg',
      GoogleTheme.light => '$kBrandAssetBase/google/light/btn_signin_full.svg',
    },
    // 다른 spec 은 자상 path 호출 안 됨 (Apple/Facebook/Line/Wechat).
    AppleSpec() || FacebookSpec() || LineSpec() || WechatSpec() => '',
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
Widget _renderPlaceholder(
  BuildContext context,
  BrandSpec spec,
  String label,
) {
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
