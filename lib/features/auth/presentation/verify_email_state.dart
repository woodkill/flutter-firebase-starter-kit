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
  /// - [isResending]: 재전송 메일 발송 진행 여부 (기본 false).
  /// - [error]: 에러 발생 시 [AppException] (기본 null).
  ///
  /// **[isResending] 의 존재 이유 (WR-03 — Phase 09 review).**
  /// 재전송은 `sendEmailVerification` 왕복이 끝난 **뒤에야**
  /// [cooldownRemaining] 을 세팅하므로, 그 전까지는 상태 변화가 전혀 없어
  /// 화면의 재전송 버튼이 계속 활성이었다. [isChecking] 이 수동 확인의
  /// 이중 탭을 막는 것과 동일한 역할을 재전송에 대해 수행한다 — 같은
  /// notifier 안의 비대칭을 해소한다.
  const factory VerifyEmailState({
    @Default(true) bool isPolling,
    @Default(0) int cooldownRemaining,
    @Default(false) bool isChecking,
    @Default(false) bool isResending,
    AppException? error,
  }) = _VerifyEmailState;
}
