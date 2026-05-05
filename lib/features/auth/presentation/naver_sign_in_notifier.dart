// Phase 13 — see ROADMAP.md
import 'dart:async';

import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/error/result.dart';
import '../data/auth_repository.dart';

part 'naver_sign_in_notifier.g.dart';

/// Naver 로그인 상태를 관리하는 [AsyncNotifier] (Phase 13 — see ROADMAP.md, D-26 / D-44).
///
/// Phase 7 [GoogleSignInNotifier] / Phase 8 [AppleSignInNotifier] / Phase 9
/// [FacebookSignInNotifier] / Phase 12 [KakaoSignInNotifier] 구조를 그대로
/// 미러링한다. autoDispose 이므로 화면 이탈 시 상태가 초기화된다. 성공 후 화면
/// 이동은 authRedirect 가 담당한다.
///
/// **race-fix invariant (Pitfall 8):** 본 Notifier 는 race-guard begin/end 를
/// 직접 호출하지 않는다. 단일 진실원은 [AuthRepository.signInWithNaver] 의
/// try-finally (Plan 13-03).
///
/// **build() 시그니처 (R7 / D-42 재정의):** `FutureOr<void> build()` 유지 —
/// Riverpod 3.x build inference 규칙상 `void build()` 로 변경 시 generator 가
/// sync `$Notifier<void>` 가족으로 강등 + AsyncNotifier API 자체가 깨진다
/// (todo `2026-05-05-r7-sibling-regression-guards.md` line 17). D-42 motivation
/// 은 회귀 가드 테스트 + docstring 으로 invariant enforce 로 재정의됨
/// (Plan 13-04 T-13-NAVER-NOTIFIER-R7-01).
///
/// **Custom Token 이므로 emailVerified=true 가 자동 부여**: Apple / Kakao 동일
/// 경로. authRedirect 는 home 으로 자동 이동하며 `/verify-email` 우회.
@riverpod
class NaverSignInNotifier extends _$NaverSignInNotifier {
  @override
  FutureOr<void> build() {
    // 초기 상태: AsyncData(null) — 회귀 가드 테스트가 verify
    // (Plan 13-04 T-13-NAVER-NOTIFIER-R7-01).
  }

  /// Naver 로그인을 수행한다.
  ///
  /// 취소(null) 시 state 를 [AsyncData] 로 유지하여 조용히 무시 (D-45).
  /// 성공 시 [AsyncData]. 실패 시 [AsyncError] 로 전환되어 LoginScreen /
  /// SignupScreen / LoginPromptSheet 의 ref.listen 에서 FormErrorBanner 로
  /// 렌더링된다.
  Future<void> signInWithNaver() async {
    state = const AsyncLoading<void>();
    final result = await ref.read(authRepositoryProvider).signInWithNaver();
    if (!ref.mounted) return;

    if (result == null) {
      state = const AsyncData<void>(null); // D-45 silent cancel
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
