// Phase 13.1 — see ROADMAP.md (D-62 Apple SDK 위임 + D-64 Google 명시 매개변수)

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sign_in_button/sign_in_button.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

import '../../../../core/auth/auth_strategy.dart';
import '../../../../core/auth/provider_id.dart';
import '../../../../core/l10n/l10n_extensions.dart';
import '../../../../l10n/generated/app_localizations.dart';
import 'branded_social_button.dart';

/// 단일 [AuthStrategy] 를 [BrandedSocialButton] 또는 `sign_in_button` 위제로
/// 렌더링하는 공용 버튼 (Phase 11 D-11, Pattern G).
///
/// **Phase 13.1 변경 (D-62 / D-64 / R5 / R6):**
/// - Apple 분기 → [BrandedSocialButton.apple] 위임 (1st-party
///   `sign_in_with_apple.SignInWithAppleButton` 사용)
/// - Google 분기 → [BrandedSocialButton.google] 위임 (공식 SVG 6종)
/// - Naver 분기 → [BrandedSocialButton.naver] (theme 매개변수 명시)
/// - Kakao 분기 → [BrandedSocialButton.kakao] (Phase 13 D-55 기존 위임)
/// - Facebook 만 `SignInButton(Buttons.facebookNew)` 잔존 (R12 — Phase 18 마이그)
///
/// **Brand Guideline 단일 진실원:**
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
  /// [BrandedSocialButton] 분기에서는 `onPressed` 에 `null` 을 전달해
  /// Material default disabled 상태로 만든다.
  final bool isDisabled;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final brightness = Theme.of(context).brightness;
    final label = _resolveLabel(l10n, strategy.labelKey);
    final onPressed = isDisabled
        ? null
        : () {
            FocusManager.instance.primaryFocus?.unfocus();
            strategy.signIn(ref);
          };

    // D-67 — provider switch (BrandedSocialButton 위임 + Facebook fallback).
    switch (strategy.providerId) {
      case kProviderIdKakao:
        return BrandedSocialButton.kakao(label: label, onPressed: onPressed);
      case kProviderIdNaver:
        // D-I — Theme.brightness 자동 분기 (Naver 자동, Google 은 명시 매개변수).
        return BrandedSocialButton.naver(
          label: label,
          theme: brightness == Brightness.dark
              ? NaverTheme.dark
              : NaverTheme.light,
          onPressed: onPressed,
        );
      case kProviderIdGoogle:
        // D-64 — Google 만 3 변형. light/dark 자동, neutral 은 caller 명시 시만.
        return BrandedSocialButton.google(
          label: label,
          theme: brightness == Brightness.dark
              ? GoogleTheme.dark
              : GoogleTheme.light,
          onPressed: onPressed,
        );
      case kProviderIdApple:
        // D-62 — Apple SDK 위제 위임. D-G-CLARIFY 정확 표기.
        return BrandedSocialButton.apple(
          label: label,
          style: brightness == Brightness.dark
              ? SignInWithAppleButtonStyle.white
              : SignInWithAppleButtonStyle.black,
          onPressed: onPressed,
        );
      case kProviderIdFacebook:
        // R12 — sign_in_button community package 잔존 (Phase 18 마이그 예정).
        return SizedBox(
          width: double.infinity,
          height: 48,
          child: SignInButton(
            Buttons.facebookNew,
            text: label,
            // sign_in_button 의 onPressed 는 non-nullable.
            onPressed: onPressed ?? () {},
          ),
        );
      default:
        throw UnsupportedError(
          'Unknown providerId: ${strategy.providerId}',
        );
    }
  }

  /// ARB 키를 [AppLocalizations] getter 로 매핑한다.
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
