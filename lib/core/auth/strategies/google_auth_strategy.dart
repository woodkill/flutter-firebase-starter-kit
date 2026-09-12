import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../features/auth/presentation/google_sign_in_notifier.dart';
import '../auth_strategy.dart';
import '../provider_id.dart';

/// Google Sign-In Strategy — [GoogleSignInNotifier] 위임 wrapper
/// (Phase 11 D-11).
///
/// **Race-fix 보존 (D-15, Pitfall 8):** `AuthRepository.signInWithGoogle` 가
/// 이미 `SocialLinkInProgress.begin / end` 를 try-finally 로 호출한다.
/// Strategy 단계에서 추가 호출 시 이중 begin race (T-11-RACE-01) 가 발생하
/// 므로 절대 금지.
class GoogleAuthStrategy extends AuthStrategy {
  /// `const` 생성자 — Registry 의 `_allStrategies` 가 const list 로 보유.
  const GoogleAuthStrategy();

  @override
  String get providerId => kProviderIdGoogle;

  @override
  String get labelKey => 'authGoogleSignIn';


  @override
  Future<void> signIn(WidgetRef ref) =>
      ref.read(googleSignInProvider.notifier).signInWithGoogle();
}
