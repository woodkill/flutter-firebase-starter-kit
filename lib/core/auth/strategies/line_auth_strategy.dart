// Phase 14 — see ROADMAP.md
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../features/auth/presentation/line_sign_in_notifier.dart';
import '../auth_strategy.dart';
import '../provider_id.dart';

/// LINE Sign-In Strategy — [LineSignInNotifier] 위임 wrapper
/// (Phase 14, SOCL-09 Registry add-only).
///
/// **Race-fix 보존 (Pitfall 8):** [AuthRepository.signInWithLine] 가 이미
/// race-guard begin / end 를 try-finally 로 호출한다 (Plan 14-05 Task 1).
/// Strategy 단계에서 추가 호출 시 이중 begin race (T-11-RACE-01) 가 발생하므로
/// 절대 금지.
///
/// Phase 16.1 (SOCL-10) 에서 [defaultPriorityFor] 본문을 채운다.
class LineAuthStrategy extends AuthStrategy {
  /// `const` 생성자 — Registry 의 `_allStrategies` 가 const list 로 보유.
  const LineAuthStrategy();

  @override
  String get providerId => kProviderIdLine;

  @override
  String get labelKey => 'authLineSignIn';

  @override
  String get iconAsset => 'line';

  @override
  Future<void> signIn(WidgetRef ref) =>
      ref.read(lineSignInProvider.notifier).signInWithLine();
}
