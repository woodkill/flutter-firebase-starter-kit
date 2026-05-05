// Phase 13 — see ROADMAP.md (D-55 BrandedSocialButton 5 provider 공통 추상화)

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:gap/gap.dart';

import '../../../../core/theme/theme_extensions.dart';

// 5 provider brand 색상 — 단일 진실원 (D-55 / 13-UI-SPEC line 186-198).
//
// 본 파일 외부 어디에도 Kakao / Naver 색상 하드코딩 금지. Kakao/Naver Brand
// Guideline 이 강제하는 색이며 앱 디자인 토큰(`AppColors` / `colorScheme`) 과
// 분리된 단일 진실원이다. light/dark 모두 동일 색 (Buttons.facebookNew /
// Phase 12 Kakao 정책 일관 — D-25 / D-52 옵션 A).

/// Kakao 공식 노란색 — Kakao Brand Guideline 강제 (#FEE500).
const Color _kKakaoYellow = Color(0xFFFEE500);

/// Kakao 가이드 권장 라벨 색 — 검정 ~85% 불투명.
///
/// 노란 배경 0xFFFEE500 와의 contrast 약 11.7:1 으로 WCAG AAA 충족.
const Color _kKakaoLabel = Color(0xD9000000);

/// KakaoTalk 말풍선 로고 색 — 검정 100% (Kakao 디자인 자산 그대로).
const Color _kKakaoIcon = Color(0xFF000000);

/// Naver 공식 그린 — Naver Brand Guideline 강제 (#03C75A).
const Color _kNaverGreen = Color(0xFF03C75A);

/// Naver 가이드 권장 라벨 색 — 흰 100% (그린 배경에 contrast >= 4.5:1).
const Color _kNaverLabel = Color(0xFFFFFFFF);

/// 5 provider 공통 brand spec (D-55).
///
/// `BrandedSocialButton` 의 색·자산·치수 사양을 단일 const 객체로 묶어
/// 외부 호출자가 임의 spec 을 주입하지 못하도록 한다. 호출자는 named factory
/// (`BrandedSocialButton.kakao()` / `BrandedSocialButton.naver()`) 만 사용해야
/// 한다 — 신규 spec 생성은 본 파일 내부 const 인스턴스만 허용.
@immutable
class BrandSpec {
  /// brand spec const 생성자.
  const BrandSpec({
    required this.backgroundColor,
    required this.foregroundColor,
    required this.brandIconAsset,
    this.iconColor,
    this.iconSize = 18,
    this.borderRadius = 6,
  });

  /// 버튼 배경 색.
  final Color backgroundColor;

  /// 라벨(Text) 색. [iconColor] 미지정 시 아이콘에도 동일 적용.
  final Color foregroundColor;

  /// 아이콘 색 — `null` 이면 [foregroundColor] 동일.
  ///
  /// Kakao 의 경우 라벨(0xD9000000 검정 85%) 과 아이콘(0xFF000000 검정 100%)
  /// 색이 분리되어 본 필드 사용. Naver 는 동일 흰색이라 `null` 처리.
  final Color? iconColor;

  /// `assets/icons/...svg` 경로 — `pubspec.yaml` assets 등록 필수.
  final String brandIconAsset;

  /// 아이콘 width / height (dp). 기본 18 dp — sign_in_button 동등.
  final double iconSize;

  /// Material + InkWell border radius (dp). 기본 6 dp — Phase 12 Kakao 와 일관.
  final double borderRadius;
}

/// 5 provider brand spec — single source of truth (D-55, 13-UI-SPEC line 482-495).
const BrandSpec _kakaoSpec = BrandSpec(
  backgroundColor: _kKakaoYellow,
  foregroundColor: _kKakaoLabel,
  iconColor: _kKakaoIcon, // 라벨과 다른 색 (라벨 85% / 아이콘 100%)
  brandIconAsset: 'assets/icons/kakao_logo.svg',
);

const BrandSpec _naverSpec = BrandSpec(
  backgroundColor: _kNaverGreen,
  foregroundColor: _kNaverLabel,
  // iconColor 미지정 → foregroundColor 동일 (흰 100%)
  brandIconAsset: 'assets/icons/naver_logo.svg',
);

/// 5 provider 공통 — Material + InkWell + SvgPicture 컴포지션 (Phase 12
/// `social_button.dart` line 96-147 `_buildKakaoButton` 추출 + 일반화).
///
/// 호출자는 [BrandedSocialButton.kakao] 또는 [BrandedSocialButton.naver]
/// named factory 만 사용한다 — `spec` 외부 주입은 본 파일 내부 const
/// 인스턴스만 허용 (D-55 / 13-UI-SPEC line 124).
///
/// **위임 invariant:** [onPressed] 가 `null` 이면 InkWell.onTap 도 `null` 로
/// 전달되어 Material default disabled 상태(ripple 없음)가 된다.
///
/// **시각 사양 (13-UI-SPEC line 522-572 verbatim):**
/// - 너비 = `double.infinity` / 높이 48 dp (sign_in_button 와 동일)
/// - border radius 6 dp / 좌우 패딩 = `appSpacing.md` (12 dp)
/// - 아이콘 18 dp / 아이콘 ↔ 라벨 간격 = `appSpacing.sm` (8 dp)
/// - TextStyle 14 dp / w500 / letterSpacing 0.1 / line height 20/14
///   (Material 3 `labelLarge` 기본값 일관)
class BrandedSocialButton extends StatelessWidget {
  /// brand spec 외부 주입을 허용하지만 호출자는 named factory 만 사용 권장.
  const BrandedSocialButton({
    required this.spec,
    required this.label,
    required this.onPressed,
    this.semanticsLabel,
    super.key,
  });

  /// Kakao named factory — 13-UI-SPEC line 156-163.
  factory BrandedSocialButton.kakao({
    required String label,
    required VoidCallback? onPressed,
    Key? key,
  }) => BrandedSocialButton(
    key: key,
    spec: _kakaoSpec,
    label: label,
    onPressed: onPressed,
  );

  /// Naver named factory — 13-UI-SPEC line 144-153.
  factory BrandedSocialButton.naver({
    required String label,
    required VoidCallback? onPressed,
    Key? key,
  }) => BrandedSocialButton(
    key: key,
    spec: _naverSpec,
    label: label,
    onPressed: onPressed,
  );

  /// brand spec — 색·자산·치수 사양.
  final BrandSpec spec;

  /// 버튼 라벨 (이미 ARB 로케일 해석된 문자열).
  final String label;

  /// 탭 핸들러. `null` 이면 비활성 상태 (ripple 없음).
  final VoidCallback? onPressed;

  /// 접근성 라벨 — `null` 이면 [label] 사용.
  final String? semanticsLabel;

  @override
  Widget build(BuildContext context) {
    final spacing = context.appSpacing;
    final iconColor = spec.iconColor ?? spec.foregroundColor;
    return SizedBox(
      width: double.infinity,
      height: 48,
      child: Material(
        color: spec.backgroundColor,
        borderRadius: BorderRadius.circular(spec.borderRadius),
        child: InkWell(
          onTap: onPressed == null
              ? null
              : () {
                  FocusManager.instance.primaryFocus?.unfocus();
                  onPressed!();
                },
          borderRadius: BorderRadius.circular(spec.borderRadius),
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: spacing.md),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                SvgPicture.asset(
                  spec.brandIconAsset,
                  width: spec.iconSize,
                  height: spec.iconSize,
                  colorFilter: ColorFilter.mode(iconColor, BlendMode.srcIn),
                  excludeFromSemantics: true,
                ),
                Gap(spacing.sm),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: spec.foregroundColor,
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
}
