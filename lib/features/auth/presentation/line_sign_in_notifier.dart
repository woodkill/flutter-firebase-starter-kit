// Phase 14 — see ROADMAP.md
import 'dart:async';

import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/error/result.dart';
import '../data/auth_repository.dart';

part 'line_sign_in_notifier.g.dart';

/// LINE 로그인 상태를 관리하는 [AsyncNotifier] (Phase 14, SOCL-03).
///
/// Phase 7 [GoogleSignInNotifier] / Phase 8 [AppleSignInNotifier] / Phase 9
/// [FacebookSignInNotifier] / Phase 12 [KakaoSignInNotifier] / Phase 13
/// [NaverSignInNotifier] 구조를 그대로 미러링한다. autoDispose 이므로 화면
/// 이탈 시 상태가 초기화된다. 성공 후 화면 이동은 authRedirect 가 담당한다.
///
/// **race-fix invariant (Pitfall 8):** 본 Notifier 는 race-guard begin/end 를
/// 직접 호출하지 않는다. 단일 진실원은 [AuthRepository.signInWithLine] 의
/// try-finally (Plan 14-05 Task 1).
///
/// **build() 시그니처 (R7 / Phase 13 D-42 carry-forward):**
/// `FutureOr<void> build()` 유지 — Riverpod 3.x build inference 규칙상
/// `void build()` 로 변경 시 generator 가 sync `$Notifier<void>` 가족으로
/// 강등되며 AsyncNotifier API 자체가 깨진다 (Phase 13 Plan 13-04
/// T-13-NAVER-NOTIFIER-R7-01 lesson). 회귀 가드 테스트 + docstring 으로
/// invariant enforce.
///
/// **Custom Token 이므로 emailVerified=true 가 자동 부여**: Apple / Kakao /
/// Naver 동일 경로. authRedirect 는 home 으로 자동 이동하며 `/verify-email`
/// 우회.
@riverpod
class LineSignInNotifier extends _$LineSignInNotifier {
  @override
  FutureOr<void> build() {
    // 초기 상태: AsyncData(null) — 회귀 가드 테스트가 verify
    // (T-14-LINE-NOTIFIER-R7-01).
  }

  /// LINE 로그인을 수행한다.
  ///
  /// 취소(null) 시 state 를 [AsyncData] 로 유지하여 조용히 무시 (D-LINE-21).
  /// 성공 시 [AsyncData]. 실패 시 [AsyncError] 로 전환되어 LoginScreen /
  /// SignupScreen / LoginPromptSheet 의 ref.listen 에서 FormErrorBanner 로
  /// 렌더링된다.
  Future<void> signInWithLine() async {
    state = const AsyncLoading<void>();
    final result = await ref.read(authRepositoryProvider).signInWithLine();
    if (!ref.mounted) return;

    if (result == null) {
      state = const AsyncData<void>(null); // D-LINE-21 silent cancel
      return;
    }

    state = switch (result) {
      Success<dynamic>() => const AsyncData<void>(null),
      Failure<dynamic>(exception: final ex) => AsyncError<void>(
        ex,
        StackTrace.current,
      ),
    };
  }
}
