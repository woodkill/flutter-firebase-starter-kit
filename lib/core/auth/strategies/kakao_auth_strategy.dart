import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../features/auth/presentation/kakao_sign_in_notifier.dart';
import '../auth_strategy.dart';
import '../provider_id.dart';

/// Kakao Sign-In Strategy — [KakaoSignInNotifier] 위임 wrapper (Phase 12 D-24).
///
/// **Race-fix 보존 (D-15, Pitfall 8):** [AuthRepository.signInWithKakao] 가
/// 이미 race-guard begin / end 를 try-finally 로 호출한다 (Plan 12-03).
/// Strategy 단계에서 추가 호출 시 이중 begin race (T-11-RACE-01) 가
/// 발생하므로 절대 금지.
///
/// Phase 16.1 (SOCL-10) 에서 [defaultPriorityFor] 본문을 채운다.
class KakaoAuthStrategy extends AuthStrategy {
  /// `const` 생성자 — Registry 의 `_allStrategies` 가 const list 로 보유.
  const KakaoAuthStrategy();

  @override
  String get providerId => kProviderIdKakao;

  @override
  String get labelKey => 'authKakaoSignIn';

  @override
  String get iconAsset => 'kakao';

  @override
  Future<void> signIn(WidgetRef ref) =>
      ref.read(kakaoSignInProvider.notifier).signInWithKakao();
}
