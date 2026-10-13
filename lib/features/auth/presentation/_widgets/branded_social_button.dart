// 소셜 로그인 버튼 — 공통 골격 한 벌 + 브랜드 스킨 6벌.
//
// 버튼 6개(Google · Apple · Facebook · Kakao · Naver · LINE)를 한 벌의 위젯
// 트리가 그린다. 값이 있는 자리는 셋이다.
// - 골격 값 — 이 파일 상단의 상수. 한 줄이 버튼 6개에 함께 걸린다.
// - 스킨 값 — `BrandSpec` 하위 클래스 6개. provider 마다 남는 색 · 외곽선 ·
//   로고 · 간격 · 여백 · 라벨 글꼴이다.
// - 문구 — 호출하는 쪽이 넘기는 `label`.
//
// 버튼은 앱 테마의 색 · 글자 스타일을 읽지 않는다. 테마에서 읽는 것은 밝기와
// 플랫폼뿐이라 앱 테마를 바꿔도 버튼 외관은 그대로다.
//
// 이 위젯은 외관만 맡는다. 인증은 호출하는 쪽이 `onPressed` 로 잇는다.
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../../core/theme/brand_focus_wrapper.dart';
import '_brand_assets.dart';

/// 소셜 버튼 6개가 함께 쓰는 높이 (dp).
const double kBrandButtonHeight = 48;

/// 소셜 버튼 6개가 함께 쓰는 모서리 반지름 (dp).
///
/// 버튼 바탕 · 누름 물결 · 포커스 테두리가 모두 이 값을 쓴다.
const double kBrandButtonRadius = 12;

/// 버튼 안쪽 좌우 여백의 기본값 (dp).
const double kBrandButtonHorizontalPadding = 12;

/// 로고와 라벨 사이 간격의 기본값 (dp).
const double kBrandButtonLogoGap = 8;

/// 라벨 글자 크기 (sp).
const double kBrandLabelFontSize = 16;

/// 라벨 글자 굵기.
const FontWeight kBrandLabelFontWeight = FontWeight.w500;

/// 라벨 글꼴 이름 — iOS · macOS 가 아닌 플랫폼에서 쓴다.
///
/// 한글 · 가나처럼 이 글꼴에 없는 글자는 테마의 대체 글꼴 목록을 따라 기기
/// 글꼴로 넘어간다.
const String kBrandLabelFontFamily = 'Roboto';

/// 라벨 글꼴 이름 — iOS · macOS 의 시스템 글꼴을 가리킨다.
const String kBrandLabelFontFamilyApple = 'CupertinoSystemText';

/// Google 버튼 라벨의 글꼴 이름 — 번들한 Google Sans 라틴 축소본의 family 다.
const String kGoogleLabelFontFamily = 'GoogleSans';

// 아래 여섯 값도 버튼 6개가 함께 쓴다. golden 그림과 계약 테스트가 이 값을
// 고정한다 — 바꾸면 계약 테스트의 기대값을 함께 고치고 golden 을 다시 만든다.

/// 라벨 글자 배율의 상한.
///
/// 기기의 글자 크기 설정이 이 배율을 넘으면 라벨은 여기서 멈춘다. 버튼 높이와
/// 로고는 글자 배율을 따르지 않는다.
const double kBrandLabelScaleCap = 1.34;

/// 비활성 버튼의 투명도 (0 ~ 1).
const double kBrandButtonDisabledOpacity = 0.38;

/// 라벨 줄 높이 (dp) — [kBrandLabelFontSize] 크기 글자 한 줄이 차지하는 높이.
const double kBrandLabelLineHeight = 22;

/// 라벨 자간 (dp).
const double kBrandLabelLetterSpacing = 0.1;

/// iOS · macOS 에서 라벨 위에 두는 여백 (dp).
///
/// 시스템 한글 글꼴이 줄 안에서 위로 앉는 것을 보정한다. 시스템 글꼴의 줄
/// 상자에 맞춘 값이라 버튼 6개에 모두 걸고, 자기 글꼴을 쓰는 라벨(Google)도
/// 시스템 글꼴 줄 상자를 받쳐 같은 자리에 앉힌다.
const double kBrandLabelIosTopInset = 1;

/// Apple 버튼의 로고와 라벨 사이 간격 (dp).
const double kBrandAppleLogoGap = 9;

/// 소셜 버튼 한 개의 브랜드 스킨 — provider 마다 남는 값의 묶음.
///
/// 하위 클래스는 6개로 닫혀 있다. provider 를 더하면 하위 클래스를 하나 더
/// 만들고 아래 멤버를 모두 구현한다 — 빠뜨린 값은 컴파일러가 알려 준다.
///
/// 높이 · 모서리 · 라벨 크기처럼 버튼 6개가 함께 쓰는 값은 여기에 두지 않는다.
/// 그 값은 파일 상단 상수에 있다.
sealed class BrandSpec {
  /// 스킨 const 생성자.
  const BrandSpec();

  /// 버튼 배경색을 밝기에 맞춰 돌려준다.
  Color resolveBackgroundColor(Brightness brightness);

  /// 라벨 글자색을 밝기에 맞춰 돌려준다.
  Color resolveLabelColor(Brightness brightness);

  /// 외곽선 색을 밝기에 맞춰 돌려준다 — 외곽선이 없는 버튼은 null 이다.
  Color? resolveOutlineColor(Brightness brightness);

  /// 로고 자산 경로를 밝기에 맞춰 돌려준다.
  ///
  /// `.png` 로 끝나는 경로는 비트맵으로, 그 밖은 SVG 로 그린다.
  String resolveLogoAsset(Brightness brightness);

  /// 로고를 그리는 상자의 폭 × 높이 (dp).
  Size get logoSize;

  /// 로고를 한 색으로 칠할 때의 색 — 자산의 색을 그대로 쓰는 로고는 null 이다.
  Color? get logoTint;

  /// 로고와 라벨 사이 간격 (dp) 을 플랫폼에 맞춰 돌려준다.
  double resolveLogoGap({required bool isApplePlatform});

  /// 버튼 안쪽 좌우 여백 (dp) 을 플랫폼에 맞춰 돌려준다.
  double resolveHorizontalPadding({required bool isApplePlatform});

  /// 이 버튼만 쓰는 라벨 글꼴 이름.
  ///
  /// 플랫폼 공통 글꼴([kBrandLabelFontFamily] · [kBrandLabelFontFamilyApple])을
  /// 쓰는 버튼은 null 이다.
  String? get labelFontFamily;
}

/// Kakao 로그인 버튼 스킨.
///
/// 노랑 바탕 · 검정 85% 라벨 · 검정 말풍선 심볼이고 밝기에 따라 바뀌지 않는다.
/// Kakao 가이드는 컨테이너의 모서리 반지름을 12 로 정한다 —
/// [kBrandButtonRadius] 가 그 값이다.
class KakaoSpec extends BrandSpec {
  /// const 생성자.
  const KakaoSpec();

  @override
  Color resolveBackgroundColor(Brightness brightness) =>
      const Color(0xFFFEE500);

  // 검정 85% — Kakao 가이드의 라벨 색이다.
  @override
  Color resolveLabelColor(Brightness brightness) => const Color(0xD9000000);

  @override
  Color? resolveOutlineColor(Brightness brightness) => null;

  @override
  String resolveLogoAsset(Brightness brightness) =>
      '$kBrandAssetBase/kakao/btn_signin_icon.svg';

  @override
  Size get logoSize => const Size(20, 20);

  @override
  Color? get logoTint => const Color(0xFF000000);

  @override
  double resolveLogoGap({required bool isApplePlatform}) => kBrandButtonLogoGap;

  @override
  double resolveHorizontalPadding({required bool isApplePlatform}) =>
      kBrandButtonHorizontalPadding;

  @override
  String? get labelFontFamily => null;
}

/// Naver 로그인 버튼 스킨.
///
/// 초록 바탕 · 흰 라벨 · 흰 N 로고이고 밝기에 따라 바뀌지 않는다. Naver
/// 가이드의 두 조항(라벨은 로고 높이보다 작게 · 가운데 정렬의 간격 8)은 아래
/// 값이 지킨다.
class NaverSpec extends BrandSpec {
  /// const 생성자.
  const NaverSpec();

  @override
  Color resolveBackgroundColor(Brightness brightness) =>
      const Color(0xFF03A94D);

  @override
  Color resolveLabelColor(Brightness brightness) => const Color(0xFFFFFFFF);

  @override
  Color? resolveOutlineColor(Brightness brightness) => null;

  @override
  String resolveLogoAsset(Brightness brightness) =>
      '$kBrandAssetBase/naver/btn_signin_icon.svg';

  // Naver 가이드는 라벨이 로고 높이보다 작아야 한다고 정한다 — 로고 18 이
  // 라벨 [kBrandLabelFontSize] 보다 크다.
  @override
  Size get logoSize => const Size(18, 18);

  @override
  Color? get logoTint => const Color(0xFFFFFFFF);

  // Naver 가이드는 가운데 정렬의 로고 · 라벨 간격을 8 로 정한다. 기본 간격을
  // 다른 값으로 바꾸면 이 자리에는 8 을 따로 적는다.
  @override
  double resolveLogoGap({required bool isApplePlatform}) => kBrandButtonLogoGap;

  @override
  double resolveHorizontalPadding({required bool isApplePlatform}) =>
      kBrandButtonHorizontalPadding;

  @override
  String? get labelFontFamily => null;
}

/// Google 로그인 버튼 스킨.
///
/// Google 가이드의 색 표(밝은 · 어두운)와 외곽선 · gradient G · Google Sans
/// 라벨을 쓴다. 좌우 여백과 로고 간격은 가이드가 플랫폼별로 따로 정한 값이다.
class GoogleSpec extends BrandSpec {
  /// const 생성자.
  const GoogleSpec();

  @override
  Color resolveBackgroundColor(Brightness brightness) =>
      brightness == Brightness.dark
      ? const Color(0xFF131314)
      : const Color(0xFFFFFFFF);

  @override
  Color resolveLabelColor(Brightness brightness) =>
      brightness == Brightness.dark
      ? const Color(0xFFE3E3E3)
      : const Color(0xFF1F1F1F);

  @override
  Color? resolveOutlineColor(Brightness brightness) =>
      brightness == Brightness.dark
      ? const Color(0xFF8E918F)
      : const Color(0xFF747775);

  // gradient G 투명 PNG — 밝기와 무관하게 같은 그림이고, 기기 화소 밀도에 맞는
  // 해상도 변형은 SDK 가 고른다.
  @override
  String resolveLogoAsset(Brightness brightness) =>
      '$kBrandAssetBase/google/g.png';

  @override
  Size get logoSize => const Size(20, 20);

  @override
  Color? get logoTint => null;

  // Google 가이드의 플랫폼별 값 — Android 10 · iOS 12.
  @override
  double resolveLogoGap({required bool isApplePlatform}) =>
      isApplePlatform ? 12 : 10;

  // Google 가이드의 플랫폼별 값 — Android 12 · iOS 16.
  @override
  double resolveHorizontalPadding({required bool isApplePlatform}) =>
      isApplePlatform ? 16 : kBrandButtonHorizontalPadding;

  @override
  String? get labelFontFamily => kGoogleLabelFontFamily;
}

/// Apple 로그인 버튼 스킨.
///
/// 밝은 테마는 검정 바탕에 흰 로고 · 흰 라벨, 어두운 테마는 흰 바탕에 검정
/// 로고 · 검정 라벨이다. 로고는 Apple 공식 medium 로고를 변형 없이 쓴다.
class AppleSpec extends BrandSpec {
  /// const 생성자.
  const AppleSpec();

  @override
  Color resolveBackgroundColor(Brightness brightness) =>
      brightness == Brightness.dark
      ? const Color(0xFFFFFFFF)
      : const Color(0xFF000000);

  @override
  Color resolveLabelColor(Brightness brightness) =>
      brightness == Brightness.dark
      ? const Color(0xFF000000)
      : const Color(0xFFFFFFFF);

  @override
  Color? resolveOutlineColor(Brightness brightness) => null;

  // 밝은 테마 = 검정 바탕에 흰 로고 · 어두운 테마 = 흰 바탕에 검정 로고.
  @override
  String resolveLogoAsset(Brightness brightness) =>
      brightness == Brightness.dark
      ? '$kBrandAssetBase/apple/black_logo/btn_signin_icon.svg'
      : '$kBrandAssetBase/apple/white_logo/btn_signin_icon.svg';

  // 공식 medium 로고 — 파일 높이를 버튼 높이에 맞추고(Apple 가이드) 폭은
  // 파일의 17 : 44 비율을 따른다.
  @override
  Size get logoSize =>
      const Size(17 * kBrandButtonHeight / 44, kBrandButtonHeight);

  @override
  Color? get logoTint => null;

  // 로고 파일이 좌우에 자기 여백을 갖고 있어 기본 간격과 다른 값을 쓴다.
  @override
  double resolveLogoGap({required bool isApplePlatform}) => kBrandAppleLogoGap;

  @override
  double resolveHorizontalPadding({required bool isApplePlatform}) =>
      kBrandButtonHorizontalPadding;

  @override
  String? get labelFontFamily => null;
}

/// Facebook 로그인 버튼 스킨.
///
/// 밝기에 따라 흰 · 어두운 바탕에 외곽선 1 을 두르고, Meta 공식 「f」 로고를
/// 색 그대로 쓴다. 로고는 밝기와 무관하게 한 장이다.
class FacebookSpec extends BrandSpec {
  /// const 생성자.
  const FacebookSpec();

  @override
  Color resolveBackgroundColor(Brightness brightness) =>
      brightness == Brightness.dark
      ? const Color(0xFF131314)
      : const Color(0xFFFFFFFF);

  @override
  Color resolveLabelColor(Brightness brightness) =>
      brightness == Brightness.dark
      ? const Color(0xFFE3E3E3)
      : const Color(0xFF1F1F1F);

  @override
  Color? resolveOutlineColor(Brightness brightness) =>
      brightness == Brightness.dark
      ? const Color(0xFF8E918F)
      : const Color(0xFF747775);

  @override
  String resolveLogoAsset(Brightness brightness) =>
      '$kBrandAssetBase/facebook/btn_signin_icon.svg';

  @override
  Size get logoSize => const Size(20, 20);

  @override
  Color? get logoTint => null;

  @override
  double resolveLogoGap({required bool isApplePlatform}) => kBrandButtonLogoGap;

  @override
  double resolveHorizontalPadding({required bool isApplePlatform}) =>
      kBrandButtonHorizontalPadding;

  @override
  String? get labelFontFamily => null;
}

/// LINE 로그인 버튼 스킨.
///
/// 초록 바탕 · 흰 라벨 · 흰 말풍선 로고이고 밝기에 따라 바뀌지 않는다. LINE
/// 가이드는 로고의 종횡비를 바꾸지 못하게 한다 — 로고 상자가
/// [iconAspectRatio] 를 따른다.
class LineSpec extends BrandSpec {
  /// const 생성자.
  const LineSpec();

  /// LINE 로고의 가로 ÷ 세로 비율 — 47 : 44.
  static const double iconAspectRatio = 47.0 / 44.0;

  @override
  Color resolveBackgroundColor(Brightness brightness) =>
      const Color(0xFF06C755);

  @override
  Color resolveLabelColor(Brightness brightness) => const Color(0xFFFFFFFF);

  @override
  Color? resolveOutlineColor(Brightness brightness) => null;

  @override
  String resolveLogoAsset(Brightness brightness) =>
      '$kBrandAssetBase/line/btn_signin_icon.svg';

  // 높이 20 에 폭은 로고의 47 : 44 비율을 따른다 — LINE 가이드는 로고의
  // 종횡비를 바꾸지 못하게 한다.
  @override
  Size get logoSize => const Size(20 * iconAspectRatio, 20);

  @override
  Color? get logoTint => const Color(0xFFFFFFFF);

  @override
  double resolveLogoGap({required bool isApplePlatform}) => kBrandButtonLogoGap;

  @override
  double resolveHorizontalPadding({required bool isApplePlatform}) =>
      kBrandButtonHorizontalPadding;

  @override
  String? get labelFontFamily => null;
}

/// 소셜 로그인 버튼 — 버튼 6개가 이 위젯 하나로 그려진다.
///
/// 이름 붙은 생성자만 쓴다:
/// - [BrandedSocialButton.google]
/// - [BrandedSocialButton.apple]
/// - [BrandedSocialButton.facebook]
/// - [BrandedSocialButton.kakao]
/// - [BrandedSocialButton.naver]
/// - [BrandedSocialButton.line]
///
/// 스킨([BrandSpec])은 생성자가 정한다 — 밖에서 임의의 스킨을 넣지 못하게 해
/// 브랜드 값이 호출하는 쪽에서 바뀌지 않는다.
///
/// 버튼 6개는 높이 · 모서리 · 라벨 크기 · 굵기 · 배치가 같고 색 · 외곽선 ·
/// 로고 · 문구만 다르다. 밝기와 플랫폼에 따른 차이는 위젯이 스스로 고른다 —
/// 호출하는 쪽은 문구와 탭 핸들러만 넘긴다.
class BrandedSocialButton extends StatelessWidget {
  /// 내부 전용 const 생성자 — 호출하는 쪽은 이름 붙은 생성자를 쓴다.
  const BrandedSocialButton._({
    required this.spec,
    required this.label,
    required this.onPressed,
    super.key,
  });

  /// Kakao 로그인 버튼을 만든다.
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

  /// Naver 로그인 버튼을 만든다.
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

  /// Google 로그인 버튼을 만든다.
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

  /// Apple 로그인 버튼을 만든다.
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

  /// Facebook 로그인 버튼을 만든다.
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

  /// LINE 로그인 버튼을 만든다.
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

  /// 브랜드 스킨 — [BrandSpec] 하위 클래스의 인스턴스.
  final BrandSpec spec;

  /// 버튼 라벨 (이미 ARB 로케일 해석된 문자열).
  final String label;

  /// 탭 핸들러. `null` 이면 비활성 상태 (ripple 없음).
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    // 포커스 테두리는 버튼 6개가 이 한 자리에서 함께 받는다.
    return BrandFocusWrapper(
      borderRadius: kBrandButtonRadius,
      isEnabled: onPressed != null,
      child: _renderUnifiedButton(context, spec, label, onPressed),
    );
  }
}

/// 소셜 버튼 6개를 한 벌의 트리로 그린다 — 공통 골격.
///
/// 버튼 6개가 함께 쓰는 값은 파일 상단 상수에서, provider 마다 다른 값(색 ·
/// 외곽선 · 로고 · 간격 · 여백 · 라벨 글꼴)은 [spec] 에서 온다. 테마에서 읽는
/// 것은 밝기와 플랫폼뿐이다 — 앱 테마의 색이나 글자 스타일을 바꿔도 버튼
/// 외관은 그대로다.
///
/// 라벨은 글자 배율 상한 안에서만 커진다. 버튼 높이와 로고는 글자 배율을
/// 따르지 않는다. 포커스 테두리는 호출하는 쪽이 감싼다.
Widget _renderUnifiedButton(
  BuildContext context,
  BrandSpec spec,
  String label,
  VoidCallback? onPressed,
) {
  final theme = Theme.of(context);
  final brightness = theme.brightness;
  final isApplePlatform =
      theme.platform == TargetPlatform.iOS ||
      theme.platform == TargetPlatform.macOS;
  final isEnabled = onPressed != null;
  final radius = BorderRadius.circular(kBrandButtonRadius);
  final outlineColor = spec.resolveOutlineColor(brightness);
  // 자기 글꼴이 없는 라벨은 플랫폼 공통 글꼴을 쓴다. 글꼴 이름을 늘 명시해
  // 앱 테마의 글꼴이 라벨에 스며들지 않게 한다.
  final skinFontFamily = spec.labelFontFamily;
  final labelFontFamily =
      skinFontFamily ??
      (isApplePlatform ? kBrandLabelFontFamilyApple : kBrandLabelFontFamily);
  // 세로 보정은 Apple 플랫폼의 라벨 6개에 모두 건다. 엔진은 줄의 baseline 을
  // dp 정수로 반올림해 그리므로, 자기 글꼴 라벨은 줄 위쪽 높이가 시스템 글꼴과
  // 조금만 달라도 1dp 어긋난다. 그래서 자기 글꼴 라벨에는 시스템 글꼴 strut 를
  // 받쳐 줄 상자를 시스템 글꼴 라벨과 맞춘다 — 강제하지 않아 최솟값으로만
  // 걸린다. 다른 플랫폼은 보정도 strut 도 없다.
  final labelTopInset = isApplePlatform ? kBrandLabelIosTopInset : 0.0;
  final labelStrutStyle = isApplePlatform && skinFontFamily != null
      ? const StrutStyle(
          fontFamily: kBrandLabelFontFamilyApple,
          fontSize: kBrandLabelFontSize,
          height: kBrandLabelLineHeight / kBrandLabelFontSize,
          leadingDistribution: TextLeadingDistribution.even,
        )
      : null;
  final logoGap = spec.resolveLogoGap(isApplePlatform: isApplePlatform);
  return Semantics(
    button: true,
    enabled: isEnabled,
    label: label,
    onTap: onPressed,
    excludeSemantics: true,
    child: SizedBox(
      width: double.infinity,
      height: kBrandButtonHeight,
      child: Opacity(
        opacity: isEnabled ? 1.0 : kBrandButtonDisabledOpacity,
        child: Material(
          color: spec.resolveBackgroundColor(brightness),
          shape: RoundedRectangleBorder(
            borderRadius: radius,
            side: outlineColor == null
                ? BorderSide.none
                : BorderSide(color: outlineColor, width: 1),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onPressed,
            borderRadius: radius,
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: spec.resolveHorizontalPadding(
                  isApplePlatform: isApplePlatform,
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildBrandLogo(spec, brightness),
                  SizedBox(width: logoGap),
                  Flexible(
                    // 글자 배율 상한은 라벨에만 건다 — 이 자리 한 곳이라
                    // 버튼이 그려지는 모든 화면에 함께 걸린다.
                    child: MediaQuery.withClampedTextScaling(
                      maxScaleFactor: kBrandLabelScaleCap,
                      child: Padding(
                        padding: EdgeInsets.only(top: labelTopInset),
                        child: Text(
                          label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          strutStyle: labelStrutStyle,
                          // 대체 글꼴 목록은 적지 않는다 — 테마의 목록을
                          // 물려받아 한글 · 가나가 기기 글꼴로 넘어간다.
                          style: TextStyle(
                            color: spec.resolveLabelColor(brightness),
                            fontSize: kBrandLabelFontSize,
                            fontWeight: kBrandLabelFontWeight,
                            height: kBrandLabelLineHeight / kBrandLabelFontSize,
                            letterSpacing: kBrandLabelLetterSpacing,
                            leadingDistribution: TextLeadingDistribution.even,
                            fontFamily: labelFontFamily,
                          ),
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

/// 스킨의 로고를 그 상자 크기로 그린다.
///
/// 경로가 `.png` 로 끝나면 비트맵으로, 그 밖은 SVG 로 그린다. 단색 칠은 SVG
/// 로고에만 한다 — 비트맵 로고는 색이 그림에 들어 있다. 로고는 접근성 트리에
/// 넣지 않는다(버튼 전체가 라벨 하나로 읽힌다).
Widget _buildBrandLogo(BrandSpec spec, Brightness brightness) {
  final asset = spec.resolveLogoAsset(brightness);
  final size = spec.logoSize;
  final tint = spec.logoTint;
  if (asset.endsWith('.png')) {
    assert(tint == null, '비트맵 로고에는 단색 칠을 하지 않는다: $asset');
    return Image.asset(
      asset,
      width: size.width,
      height: size.height,
      excludeFromSemantics: true,
    );
  }
  return SvgPicture.asset(
    asset,
    width: size.width,
    height: size.height,
    colorFilter: tint == null ? null : ColorFilter.mode(tint, BlendMode.srcIn),
    excludeFromSemantics: true,
  );
}
