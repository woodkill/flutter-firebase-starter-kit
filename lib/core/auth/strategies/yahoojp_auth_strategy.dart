// Phase 15 — see ROADMAP.md
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../features/auth/presentation/yahoojp_sign_in_notifier.dart';
import '../auth_strategy.dart';
import '../provider_id.dart';

/// Yahoo!JP Sign-In Strategy — [YahoojpSignInNotifier] 위임 wrapper
/// (Phase 15, SOCL-09 Registry add-only).
///
/// **Race-fix 보존 (Pitfall 8):** [AuthRepository.signInWithYahoojp] 가 이미
/// race-guard begin / end 를 try-finally 로 호출한다 (Plan 15-03 Task 2).
/// Strategy 단계에서 추가 호출 시 이중 begin race (T-11-RACE-01 등가) 가
/// 발생하므로 절대 금지.
///
/// Phase 16.1 (SOCL-10) 에서 [defaultPriorityFor] 본문을 채운다.
class YahoojpAuthStrategy extends AuthStrategy {
  /// `const` 생성자 — Registry 의 `_allStrategies` 가 const list 로 보유.
  const YahoojpAuthStrategy();

  @override
  String get providerId => kProviderIdYahooJp;

  @override
  String get labelKey => 'authYahoojpSignIn';

  @override
  String get iconAsset => 'yahoojp';

  @override
  Future<void> signIn(WidgetRef ref) =>
      ref.read(yahoojpSignInProvider.notifier).signInWithYahoojp();
}
