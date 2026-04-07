import 'dart:async';

import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/error/result.dart';
import '../data/auth_repository.dart';

part 'signup_notifier.g.dart';

/// 이메일/비밀번호 회원가입 폼 제출을 담당하는 [AsyncNotifier].
///
/// 제출 상태를 [AsyncValue] (void) 로 노출한다.
/// - 초기 상태: 암묵적 [AsyncData] (null) — 제출 이전.
/// - [submit] 진입 시 [AsyncLoading].
/// - [AuthRepository.signUpWithEmail] 성공 시 [AsyncData] (null).
/// - 실패 시 [AsyncError] ([AppException], stackTrace).
///
/// 성공 후 화면 이동은 Phase 5 redirect 가드가 담당하므로
/// 본 Notifier 는 navigation 을 호출하지 않는다 (D-05).
/// autoDispose 이므로 화면 이탈 시 상태가 초기화된다 (D-14).
@riverpod
class SignupNotifier extends _$SignupNotifier {
  @override
  FutureOr<void> build() {
    // 초기 상태는 AsyncData(null) — 제출 전.
  }

  /// 회원가입 폼을 제출한다.
  ///
  /// [email] 과 [password] 는 이미 클라이언트 validator 를 통과한 값이어야
  /// 한다. [displayName] 은 호출 전 트림되어 1~32자 검증을 통과한 값이어야
  /// 한다 (D-22). 결과는 [state] 의 [AsyncValue] 로 반영된다.
  Future<void> submit({
    required String email,
    required String password,
    required String displayName,
  }) async {
    state = const AsyncLoading<void>();
    final result = await ref.read(authRepositoryProvider).signUpWithEmail(
          email: email,
          password: password,
          displayName: displayName,
        );
    state = switch (result) {
      Success<dynamic>() => const AsyncData<void>(null),
      Failure<dynamic>(exception: final ex) =>
        AsyncError<void>(ex, StackTrace.current),
    };
  }
}
