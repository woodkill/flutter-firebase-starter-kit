import 'dart:async';

import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/error/result.dart';
import '../data/auth_repository.dart';

part 'forgot_password_notifier.g.dart';

/// 비밀번호 재설정 메일 발송 폼 [AsyncNotifier].
///
/// 제출 상태를 [AsyncValue] (void) 로 노출한다.
/// - 초기 상태: 암묵적 [AsyncData] (null) — 제출 이전.
/// - [submit] 진입 시 [AsyncLoading].
/// - [AuthRepository.sendPasswordReset] 성공 시 [AsyncData] (null).
/// - 실패 시 [AsyncError] ([AppException], stackTrace).
///
/// EEP(Email Enumeration Protection) 활성 환경에서는
/// `sendPasswordResetEmail` 이 존재하지 않는 이메일에 대해서도 에러를
/// 던지지 않는다. 따라서 성공 응답은 "메일이 발송됐다" 가 아니라
/// "요청이 처리됐다" 를 의미한다 (RESEARCH.md Pitfall 1 회피).
///
/// autoDispose 이므로 화면 이탈 시 상태가 초기화된다 (D-14).
@riverpod
class ForgotPasswordNotifier extends _$ForgotPasswordNotifier {
  @override
  FutureOr<void> build() {
    // 초기 상태는 AsyncData(null) — 제출 전.
  }

  /// 비밀번호 재설정 메일 발송 요청을 제출한다.
  ///
  /// [email] 은 이미 클라이언트 validator 를 통과한 값이어야 한다.
  /// 결과는 [state] 의 [AsyncValue] 로 반영된다.
  Future<void> submit({required String email}) async {
    state = const AsyncLoading<void>();
    final result = await ref
        .read(authRepositoryProvider)
        .sendPasswordReset(email: email);
    state = switch (result) {
      Success<dynamic>() => const AsyncData<void>(null),
      Failure<dynamic>(exception: final ex) =>
        AsyncError<void>(ex, StackTrace.current),
    };
  }
}
