import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:gap/gap.dart';
import 'package:sign_in_button/sign_in_button.dart';

import '../../../../core/auth/auth_strategy.dart';
import '../../../../core/auth/provider_id.dart';
import '../../../../core/l10n/l10n_extensions.dart';
import '../../../../core/theme/theme_extensions.dart';
import '../../../../l10n/generated/app_localizations.dart';

/// Kakao 공식 브랜드 색 — Phase 12 D-25 / 12-UI-SPEC line 162-166.
///
/// **이 3개 리터럴 외 어디에도 Kakao 색 하드코딩 금지** — Kakao Brand
/// Guideline 이 강제하는 색이며 앱 디자인 토큰(`AppColors` /
/// `colorScheme`) 과 분리된 단일 진실원이다. light/dark 모두 동일 색
/// (Buttons.facebookNew 정책 일관 — D-25 옵션 A).
const Color _kKakaoYellow = Color(0xFFFEE500);

/// Kakao 가이드 권장 라벨 색 — 검정 ~85% 불투명 (4.5:1 contrast 충족,
/// 노란 배경 0xFFFEE500 와의 contrast 약 11.7:1 으로 WCAG AAA 충족).
const Color _kKakaoLabel = Color(0xD9000000);

/// KakaoTalk 말풍선 로고 색 — 검정 100% (Kakao 디자인 자산 그대로).
const Color _kKakaoIcon = Color(0xFF000000);

/// 단일 [AuthStrategy] 를 `sign_in_button` 으로 렌더링하는 공용 버튼
/// (Phase 11 D-11, Pattern G).
///
/// 기존 `social_sign_in_section.dart` 의 인라인 빌더 (`googleButton` /
/// `appleButton` / `facebookButton`) 를 통합한다. 버튼 enum 매핑은
/// [_resolveButtons], ARB 라벨 매핑은 [_resolveLabel] switch 가 담당하며
/// Phase 12+ 신규 provider 추가 시 두 switch 의 case 만 확장하면 된다.
///
/// **Kakao 분기 (Phase 12 D-25 옵션 A):** `sign_in_button` 패키지가 Kakao
/// 브랜드를 미지원하므로 [build] 첫 줄에서 [_buildKakaoButton] 으로 분기하여
/// Material+InkWell+SVG 로 직접 그린다. Kakao Brand Guideline (#FEE500
/// 노란 배경 + 검정 라벨/아이콘 + KakaoTalk 말풍선 로고) 준수.
///
/// **위임 invariant (D-11/D-12):** 탭 시 [strategy].signIn 으로 직접 위임한다.
/// 기존 `*SignInNotifier` 가 `AsyncValue<void>` 로 success/error 를 노출하므로
/// UI 는 `ref.listen(*SignInProvider, ...)` 으로 분기한다.
class SocialButton extends ConsumerWidget {
  /// [SocialButton] 을 생성한다.
  const SocialButton({
    required this.strategy,
    required this.isDisabled,
    super.key,
  });

  /// 렌더링·위임 대상 [AuthStrategy].
  final AuthStrategy strategy;

  /// 다른 사회적 로그인 / 폼 로딩 등으로 인한 비활성 상태.
  ///
  /// `sign_in_button` 의 `onPressed` 는 non-nullable 이므로 빈 콜백으로 교체.
  /// Kakao 분기에서는 [InkWell.onTap] 에 `null` 을 전달해 Material default
  /// disabled 상태로 만든다.
  final bool isDisabled;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;

    // Phase 12 D-25 옵션 A: Kakao 는 sign_in_button 패키지가 미지원하므로
    // Kakao Brand Guideline 그대로 직접 그린다 (12-UI-SPEC line 391-437).
    if (strategy.providerId == kProviderIdKakao) {
      return _buildKakaoButton(context, ref, l10n);
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;
    return SizedBox(
      width: double.infinity,
      height: 48,
      child: SignInButton(
        _resolveButtons(strategy.providerId, isDark),
        text: _resolveLabel(l10n, strategy.labelKey),
        onPressed: isDisabled
            ? () {} // sign_in_button 의 onPressed 는 non-nullable
            : () {
                FocusManager.instance.primaryFocus?.unfocus();
                strategy.signIn(ref);
              },
      ),
    );
  }

  /// Kakao 공식 브랜드 가이드라인 준수 (Phase 12 D-25 옵션 A).
  ///
  /// 노란 #FEE500 배경 + 검정 ~85% 라벨 + 검정 100% KakaoTalk 말풍선 아이콘.
  /// light/dark 모두 동일 색 — Buttons.facebookNew 와 동일 정책 (12-UI-SPEC
  /// color table). 높이 48 dp / border radius 6 dp / 아이콘 18 dp / 아이콘
  /// ↔ 라벨 간격 = `appSpacing.sm` (8 dp) / 좌우 패딩 = `appSpacing.md`
  /// (12 dp). 위임 invariant 일관 — [strategy.signIn] 직접 호출.
  Widget _buildKakaoButton(
    BuildContext context,
    WidgetRef ref,
    AppLocalizations l10n,
  ) {
    final spacing = context.appSpacing;
    return SizedBox(
      width: double.infinity,
      height: 48,
      child: Material(
        color: _kKakaoYellow,
        borderRadius: BorderRadius.circular(6),
        child: InkWell(
          onTap: isDisabled
              ? null
              : () {
                  FocusManager.instance.primaryFocus?.unfocus();
                  strategy.signIn(ref);
                },
          borderRadius: BorderRadius.circular(6),
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: spacing.md),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                SvgPicture.asset(
                  'assets/icons/kakao_logo.svg',
                  width: 18,
                  height: 18,
                  colorFilter: const ColorFilter.mode(
                    _kKakaoIcon,
                    BlendMode.srcIn,
                  ),
                ),
                Gap(spacing.sm),
                Text(
                  _resolveLabel(l10n, strategy.labelKey),
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: _kKakaoLabel,
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

  /// `providerId` 를 `Buttons` enum 값으로 매핑한다.
  ///
  /// Kakao 분기는 [build] 첫 줄에서 짧은 회로하므로 본 switch 에 도달하지
  /// 않는다. Phase 13~16 의 다른 Custom Token provider (Naver/LINE/Yahoo!JP/
  /// WeChat) 도 sign_in_button 미지원 → 본 switch 가 아닌 별도 _build*Button
  /// 분기 패턴으로 추가될 가능성 (Phase 13+ planner 결정).
  Buttons _resolveButtons(String providerId, bool isDark) =>
      switch (providerId) {
        kProviderIdGoogle => isDark ? Buttons.googleDark : Buttons.google,
        kProviderIdApple => isDark ? Buttons.appleDark : Buttons.apple,
        kProviderIdFacebook => Buttons.facebookNew,
        _ => throw UnsupportedError('Unknown providerId: $providerId'),
      };

  /// ARB 키를 `AppLocalizations` getter 로 매핑한다.
  ///
  /// Phase 12 — `authKakaoSignIn` 추가 (D-29).
  String _resolveLabel(AppLocalizations l10n, String key) => switch (key) {
    'authGoogleSignIn' => l10n.authGoogleSignIn,
    'authAppleSignIn' => l10n.authAppleSignIn,
    'authFacebookSignIn' => l10n.authFacebookSignIn,
    'authKakaoSignIn' => l10n.authKakaoSignIn,
    _ => key,
  };
}
