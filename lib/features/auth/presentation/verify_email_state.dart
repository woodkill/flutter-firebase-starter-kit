import 'package:freezed_annotation/freezed_annotation.dart';

import '../../../core/error/app_exception.dart';

part 'verify_email_state.freezed.dart';

/// 이메일 인증 대기 화면의 상태를 나타내는 Freezed 클래스.
///
/// [VerifyEmailNotifier]가 관리하며, 폴링 상태, 재전송 쿨다운,
/// 수동 확인 진행 여부, 에러를 포함한다.
@freezed
abstract class VerifyEmailState with _$VerifyEmailState {
  /// [VerifyEmailState]를 생성한다.
  ///
  /// - [isPolling]: 자동 폴링 진행 여부 (기본 true).
  /// - [cooldownRemaining]: 재전송 쿨다운 잔여 초 (기본 0).
  /// - [isChecking]: 수동 "인증 확인" 진행 여부 (기본 false).
  /// - [error]: 에러 발생 시 [AppException] (기본 null).
  const factory VerifyEmailState({
    @Default(true) bool isPolling,
    @Default(0) int cooldownRemaining,
    @Default(false) bool isChecking,
    AppException? error,
  }) = _VerifyEmailState;
}
