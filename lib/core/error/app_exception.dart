/// 애플리케이션 전역 예외 계층의 최상위 sealed class.
///
/// 모든 도메인별 예외는 이 클래스를 상속한다.
/// sealed class이므로 switch 문에서 exhaustive 패턴 매칭이 가능하다.
///
/// [userMessage]는 ARB 키 문자열을 저장하고,
/// UI 레이어에서 [resolveExceptionMessage]를 통해 l10n 룩업으로 번역한다.
/// 기술 상세(스택 트레이스, 내부 에러 코드 등)를 포함하지 않는다.
/// [cause]는 디버깅/로깅 전용으로, UI에 노출하지 않는다.
sealed class AppException implements Exception {
  /// [AppException]을 생성한다.
  ///
  /// [userMessage]는 사용자에게 표시할 안전한 메시지.
  /// [cause]는 원본 예외를 보존하기 위한 optional 파라미터.
  const AppException({required this.userMessage, this.cause});

  /// 사용자에게 표시할 안전한 에러 메시지.
  ///
  /// 기술 상세 정보를 포함하지 않는다 (보안 위협 T-02-01 대응).
  final String userMessage;

  /// 원본 예외. 디버깅/로깅 전용이며 UI에 노출하지 않는다.
  final Object? cause;
}

// ---------------------------------------------------------------------------
// 네트워크 관련 예외
// ---------------------------------------------------------------------------

/// 네트워크 관련 예외의 sealed class.
///
/// HTTP 통신, 연결 상태 등 네트워크 계층에서 발생하는 예외를 분류한다.
sealed class NetworkException extends AppException {
  /// [NetworkException]을 생성한다.
  const NetworkException({required super.userMessage, super.cause});
}

/// 서버 연결 시간 초과.
final class ConnectionTimeout extends NetworkException {
  /// [ConnectionTimeout]을 생성한다.
  const ConnectionTimeout({super.cause})
      : super(userMessage: 'errorNetworkTimeout');
}

/// 인터넷 연결 없음.
final class NoInternetConnection extends NetworkException {
  /// [NoInternetConnection]을 생성한다.
  const NoInternetConnection({super.cause})
      : super(userMessage: 'errorNoInternet');
}

/// 요청 시간 초과.
final class RequestTimeout extends NetworkException {
  /// [RequestTimeout]을 생성한다.
  const RequestTimeout({super.cause})
      : super(userMessage: 'errorRequestTimeout');
}

// ---------------------------------------------------------------------------
// 인증 관련 예외
// ---------------------------------------------------------------------------

/// 인증 관련 예외의 sealed class.
///
/// 로그인, 회원가입, 세션 관리 등 인증 계층에서 발생하는 예외를 분류한다.
sealed class AuthException extends AppException {
  /// [AuthException]을 생성한다.
  const AuthException({required super.userMessage, super.cause});
}

/// 이메일 또는 비밀번호가 올바르지 않음.
final class InvalidCredentials extends AuthException {
  /// [InvalidCredentials]을 생성한다.
  const InvalidCredentials({super.cause})
      : super(userMessage: 'errorInvalidCredentials');
}

/// 사용자를 찾을 수 없음.
final class UserNotFound extends AuthException {
  /// [UserNotFound]를 생성한다.
  const UserNotFound({super.cause})
      : super(userMessage: 'errorUserNotFound');
}

/// 이미 사용 중인 이메일.
final class EmailAlreadyInUse extends AuthException {
  /// [EmailAlreadyInUse]를 생성한다.
  const EmailAlreadyInUse({super.cause})
      : super(userMessage: 'errorEmailAlreadyInUse');
}

/// 비밀번호가 너무 약함.
final class WeakPassword extends AuthException {
  /// [WeakPassword]를 생성한다.
  const WeakPassword({super.cause})
      : super(userMessage: 'errorWeakPassword');
}

/// 세션이 만료됨.
final class SessionExpired extends AuthException {
  /// [SessionExpired]를 생성한다.
  const SessionExpired({super.cause})
      : super(userMessage: 'errorSessionExpired');
}

// ---------------------------------------------------------------------------
// 서버 관련 예외
// ---------------------------------------------------------------------------

/// 서버 관련 예외의 sealed class.
///
/// 서버 내부 오류, 서비스 불가 등 서버 계층에서 발생하는 예외를 분류한다.
sealed class ServerException extends AppException {
  /// [ServerException]을 생성한다.
  const ServerException({required super.userMessage, super.cause});
}

/// 서버 내부 오류.
final class InternalServerError extends ServerException {
  /// [InternalServerError]를 생성한다.
  const InternalServerError({super.cause})
      : super(userMessage: 'errorInternalServer');
}

/// 서비스가 일시적으로 사용 불가.
final class ServiceUnavailable extends ServerException {
  /// [ServiceUnavailable]을 생성한다.
  const ServiceUnavailable({super.cause})
      : super(userMessage: 'errorServiceUnavailable');
}
