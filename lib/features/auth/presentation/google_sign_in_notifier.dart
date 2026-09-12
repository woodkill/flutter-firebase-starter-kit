import 'dart:async';

import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/error/result.dart';
import '../data/auth_repository.dart';

part 'google_sign_in_notifier.g.dart';

/// Google 로그인 상태를 관리하는 [AsyncNotifier] (D-13).
///
/// autoDispose이므로 화면 이탈 시 상태가 초기화된다.
/// 성공 후 화면 이동은 resolveAuthRedirect가 담당한다 (D-05).
///
/// **build() 시그니처 (R7 / Phase 13 D-42 invariant — 7 소셜 notifier 공통):**
/// `FutureOr<void> build()` 를 유지한다. Riverpod 3.x build inference 규칙상
/// `void build()` 로 바꾸면 generator 가 sync `$Notifier<void>` 가족으로
/// 강등되어 AsyncNotifier API 자체가 깨진다 (Phase 13 Plan 13-04
/// T-13-NAVER-NOTIFIER-R7-01 lesson). 회귀 가드 테스트 + 본 docstring 으로
/// invariant 를 강제한다 — IN-04 정정(Phase 09 review): 이 경고는 naver /
/// line / yahoojp 3개 파일에만 있었으나 회귀 조건은 7개 모두 동일하므로
/// 전 파일에 일치시킨다.
@riverpod
class GoogleSignInNotifier extends _$GoogleSignInNotifier {
  @override
  FutureOr<void> build() {
    // 초기 상태: AsyncData(null)
  }

  /// Google 로그인을 수행한다.
  ///
  /// 취소(null) 시 state를 AsyncData로 유지하여 조용히 무시 (D-06). 이 동작은 7 provider 가 문자 단위로 동일하며,
  /// 최초 결정 **D-06** 의 provider 별 인스턴스다 (IN-01 정정 — Phase 09
  /// review: 동일 동작이 6개의 서로 다른 ID 로 불리고 있었다).
  /// 성공 시 AsyncData. 실패 시 AsyncError.
  Future<void> signInWithGoogle() async {
    state = const AsyncLoading<void>();
    final result = await ref.read(authRepositoryProvider).signInWithGoogle();
    if (!ref.mounted) return;

    if (result == null) {
      state = const AsyncData<void>(null);
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
