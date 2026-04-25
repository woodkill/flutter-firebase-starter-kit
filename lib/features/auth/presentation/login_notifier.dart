import 'dart:async';

import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/error/result.dart';
import '../data/auth_repository.dart';

part 'login_notifier.g.dart';

/// 이메일/비밀번호 로그인 폼 제출을 담당하는 [AsyncNotifier].
///
/// 제출 상태를 [AsyncValue] (void) 로 노출한다.
/// - 초기 상태: 암묵적 [AsyncData] (null) — 제출 이전.
/// - [submit] 진입 시 [AsyncLoading].
/// - [AuthRepository.signInWithEmail] 성공 시 [AsyncData] (null).
/// - 실패 시 [AsyncError] ([AppException], stackTrace).
///
/// 성공 후 화면 이동은 Phase 5 `authRedirect` 가 담당하므로
/// 본 Notifier 는 navigation 을 호출하지 않는다 (D-05).
/// autoDispose 이므로 화면 이탈 시 상태가 초기화된다 (D-14).
@riverpod
class LoginNotifier extends _$LoginNotifier {
  @override
  FutureOr<void> build() {
    // 초기 상태는 AsyncData(null) — 제출 전.
  }

  /// 로그인 폼을 제출한다.
  ///
  /// [email] 과 [password] 는 이미 클라이언트 validator 를 통과한 값이어야
  /// 한다. 결과는 [state] 의 [AsyncValue] 로 반영된다.
  ///
  /// `await` 이후에는 [ref.mounted] 를 확인한 뒤에만 state 를 갱신한다.
  /// 로그인 성공 시 `authRedirect` 가 화면을 이동시켜 본 autoDispose
  /// notifier 가 즉시 dispose 되는데, 그 시점에 state setter 가 호출되면
  /// `UnmountedRefException` 이 발생하기 때문이다 (T-06.07-02).
  Future<void> submit({required String email, required String password}) async {
    state = const AsyncLoading<void>();
    final result = await ref
        .read(authRepositoryProvider)
        .signInWithEmail(email: email, password: password);
    if (!ref.mounted) return;
    state = switch (result) {
      Success<dynamic>() => const AsyncData<void>(null),
      Failure<dynamic>(exception: final ex) => AsyncError<void>(
        ex,
        StackTrace.current,
      ),
    };
  }
}
