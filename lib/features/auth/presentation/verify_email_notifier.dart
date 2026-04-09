import 'dart:async';

import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'verify_email_state.dart';

part 'verify_email_notifier.g.dart';

/// 이메일 인증 대기 화면의 비즈니스 로직을 담당하는 AsyncNotifier.
///
/// 3초 간격 폴링으로 [reloadUser]를 호출하여 emailVerified 상태를
/// 감지하고, 5분 타임아웃 후 폴링을 자동 중지한다.
/// 재전송 쿨다운(60초)과 수동 확인 기능을 제공한다.
/// autoDispose이므로 화면 이탈 시 Timer가 정리된다.
@riverpod
class VerifyEmailNotifier extends _$VerifyEmailNotifier {
  @override
  FutureOr<VerifyEmailState> build() {
    // TODO: 구현 예정 (GREEN 단계)
    throw UnimplementedError();
  }

  /// 이메일 인증 메일을 재전송한다.
  Future<void> resendVerification() async {
    // TODO: 구현 예정 (GREEN 단계)
    throw UnimplementedError();
  }

  /// 수동으로 이메일 인증 상태를 확인한다.
  Future<void> checkManually() async {
    // TODO: 구현 예정 (GREEN 단계)
    throw UnimplementedError();
  }

  /// 로그아웃한다.
  Future<void> logout() async {
    // TODO: 구현 예정 (GREEN 단계)
    throw UnimplementedError();
  }
}
