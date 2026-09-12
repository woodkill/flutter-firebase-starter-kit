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
/// 로케일별 우선순위 정책 (SOCL-10) 은 2026-05-22 Out of Scope 로 폐기됐다
/// (진실원 .planning/REQUIREMENTS.md Out of Scope). IN-01 (Phase 7 review)
/// 에서 관련 dead API (`defaultPriorityFor` / `iconAsset`) 를 제거했다 —
/// 재도입 진입점은 [activeStrategies] 문서 참조.
class LineAuthStrategy extends AuthStrategy {
  /// `const` 생성자 — Registry 의 `_allStrategies` 가 const list 로 보유.
  const LineAuthStrategy();

  @override
  String get providerId => kProviderIdLine;

  @override
  String get labelKey => 'authLineSignIn';


  @override
  Future<void> signIn(WidgetRef ref) =>
      ref.read(lineSignInProvider.notifier).signInWithLine();
}
