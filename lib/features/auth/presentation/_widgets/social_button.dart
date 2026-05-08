// Phase 13 — see ROADMAP.md (D-55 BrandedSocialButton 마이그레이션)

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sign_in_button/sign_in_button.dart';

import '../../../../core/auth/auth_strategy.dart';
import '../../../../core/auth/provider_id.dart';
import '../../../../core/l10n/l10n_extensions.dart';
import '../../../../l10n/generated/app_localizations.dart';
import 'branded_social_button.dart';

/// 단일 [AuthStrategy] 를 `sign_in_button` 또는 [BrandedSocialButton] 으로
/// 렌더링하는 공용 버튼 (Phase 11 D-11, Pattern G).
///
/// 기존 `social_sign_in_section.dart` 의 인라인 빌더 (`googleButton` /
/// `appleButton` / `facebookButton`) 를 통합한다. 버튼 enum 매핑은
/// [_resolveButtons], ARB 라벨 매핑은 [_resolveLabel] switch 가 담당하며
/// Phase 12+ 신규 provider 추가 시 두 switch 의 case 만 확장하면 된다.
///
/// **Kakao / Naver 분기 (Phase 13 D-55 BrandedSocialButton 마이그레이션):**
/// `sign_in_button` 패키지가 Kakao / Naver 브랜드를 미지원하므로 [build]
/// 첫 줄에서 [BrandedSocialButton.kakao] / [BrandedSocialButton.naver] 으로
/// 위임한다. Brand Guideline 준수의 단일 진실원은
/// `lib/features/auth/presentation/_widgets/branded_social_button.dart`.
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
  /// Kakao / Naver 분기에서는 [BrandedSocialButton] 의 `onPressed` 에 `null`
  /// 을 전달해 Material default disabled 상태로 만든다.
  final bool isDisabled;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;

    // Phase 13 D-55 — Kakao / Naver 는 sign_in_button 미지원 → BrandedSocialButton
    // 으로 위임. 5 provider brand spec 의 단일 진실원은 branded_social_button.dart.
    if (strategy.providerId == kProviderIdKakao) {
      return BrandedSocialButton.kakao(
        label: _resolveLabel(l10n, strategy.labelKey),
        onPressed: isDisabled ? null : () => strategy.signIn(ref),
      );
    }
    if (strategy.providerId == kProviderIdNaver) {
      // Phase 13.1 Plan 13.1-05 — sealed BrandSpec hierarchy 도입 (R8).
      // Naver factory 시그니처에 `theme` 명시 매개변수 추가됨 (D-I — caller
      // 가 `Theme.of(context).brightness` 자동 분기 책임). 본 caller 의 본격
      // refactor (Apple/Google branch BrandedSocialButton 위임 + brightness
      // 자동 매핑 통합) 는 Plan 13.1-08 — Wave 2 영역. 본 변경은 Plan 13.1-05
      // sealed factory break 흡수 위한 최소 patch (Rule 3 — blocking issue).
      final naverTheme = Theme.of(context).brightness == Brightness.dark
          ? NaverTheme.dark
          : NaverTheme.light;
      return BrandedSocialButton.naver(
        // Phase 13 Plan 13-06 — `l10n.authNaverSignIn` ARB 키 매핑
        // (`_resolveLabel` switch 의 'authNaverSignIn' case).
        label: _resolveLabel(l10n, strategy.labelKey),
        theme: naverTheme,
        onPressed: isDisabled ? null : () => strategy.signIn(ref),
      );
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

  /// `providerId` 를 `Buttons` enum 값으로 매핑한다.
  ///
  /// Kakao / Naver 분기는 [build] 첫 줄에서 짧은 회로하므로 본 switch 에
  /// 도달하지 않는다. Phase 14~16 의 다른 Custom Token provider (LINE/
  /// Yahoo!JP/WeChat) 도 sign_in_button 미지원 → BrandedSocialButton 추상화
  /// 위에 brand spec 추가만으로 자동 재사용 (D-55).
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
  /// Phase 13 Plan 13-06 — `authNaverSignIn` 추가 (Wave 4 atomic 분리 —
  /// Plan 13-05 의 임시 라벨 → ARB 키 교체).
  String _resolveLabel(AppLocalizations l10n, String key) => switch (key) {
    'authGoogleSignIn' => l10n.authGoogleSignIn,
    'authAppleSignIn' => l10n.authAppleSignIn,
    'authFacebookSignIn' => l10n.authFacebookSignIn,
    'authKakaoSignIn' => l10n.authKakaoSignIn,
    'authNaverSignIn' => l10n.authNaverSignIn,
    _ => key,
  };
}
