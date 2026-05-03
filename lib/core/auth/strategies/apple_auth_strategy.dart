import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../features/auth/presentation/apple_sign_in_notifier.dart';
import '../auth_strategy.dart';
import '../provider_id.dart';

/// Apple Sign-In Strategy — [AppleSignInNotifier] 위임 wrapper
/// (Phase 11 D-11).
///
/// **Race-fix 보존 (D-15, Pitfall 8):** `AuthRepository.signInWithApple` 가
/// 이미 `SocialLinkInProgress.begin / end` 를 try-finally 로 호출한다.
/// Strategy 단계에서 추가 호출 시 이중 begin race (T-11-RACE-01) 가 발생하
/// 므로 절대 금지.
class AppleAuthStrategy extends AuthStrategy {
  /// `const` 생성자 — Registry 의 `_allStrategies` 가 const list 로 보유.
  const AppleAuthStrategy();

  @override
  String get providerId => kProviderIdApple;

  @override
  String get labelKey => 'authAppleSignIn';

  @override
  String get iconAsset => 'apple';

  @override
  Future<void> signIn(WidgetRef ref) =>
      ref.read(appleSignInProvider.notifier).signInWithApple();
}
