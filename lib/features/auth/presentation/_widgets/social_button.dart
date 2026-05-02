import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sign_in_button/sign_in_button.dart';

import '../../../../core/auth/auth_strategy.dart';
import '../../../../core/auth/provider_id.dart';
import '../../../../core/l10n/l10n_extensions.dart';
import '../../../../l10n/generated/app_localizations.dart';

/// 단일 [AuthStrategy] 를 `sign_in_button` 으로 렌더링하는 공용 버튼
/// (Phase 11 D-11, Pattern G).
///
/// 기존 `social_sign_in_section.dart` 의 인라인 빌더 (`googleButton` /
/// `appleButton` / `facebookButton`) 를 통합한다. 버튼 enum 매핑은
/// [_resolveButtons], ARB 라벨 매핑은 [_resolveLabel] switch 가 담당하며
/// Phase 12+ 신규 provider 추가 시 두 switch 의 case 만 확장하면 된다.
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
  final bool isDisabled;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
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
  /// Phase 12+ 추가 시 default 분기를 SVG 기반으로 확장한다.
  Buttons _resolveButtons(String providerId, bool isDark) =>
      switch (providerId) {
        kProviderIdGoogle => isDark ? Buttons.googleDark : Buttons.google,
        kProviderIdApple => isDark ? Buttons.appleDark : Buttons.apple,
        kProviderIdFacebook => Buttons.facebookNew,
        _ => throw UnsupportedError('Unknown providerId: $providerId'),
      };

  /// ARB 키를 `AppLocalizations` getter 로 매핑한다.
  ///
  /// Phase 12+ 추가 시 case 를 확장한다 (예: `authKakaoSignIn`).
  String _resolveLabel(AppLocalizations l10n, String key) => switch (key) {
    'authGoogleSignIn' => l10n.authGoogleSignIn,
    'authAppleSignIn' => l10n.authAppleSignIn,
    'authFacebookSignIn' => l10n.authFacebookSignIn,
    _ => key,
  };
}
