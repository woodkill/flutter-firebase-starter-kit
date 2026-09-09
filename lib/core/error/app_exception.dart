import '../auth/provider_id.dart';

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
  const UserNotFound({super.cause}) : super(userMessage: 'errorUserNotFound');
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
  const WeakPassword({super.cause}) : super(userMessage: 'errorWeakPassword');
}

/// 세션이 만료됨.
final class SessionExpired extends AuthException {
  /// [SessionExpired]를 생성한다.
  const SessionExpired({super.cause})
    : super(userMessage: 'errorSessionExpired');
}

/// 잘못된 이메일 형식 (Firebase `invalid-email` 코드 매핑).
final class InvalidEmail extends AuthException {
  /// [InvalidEmail]을 생성한다.
  const InvalidEmail({super.cause}) : super(userMessage: 'errorInvalidEmail');
}

/// 비활성화된 계정 (Firebase `user-disabled` 코드 매핑).
final class UserDisabled extends AuthException {
  /// [UserDisabled]를 생성한다.
  const UserDisabled({super.cause}) : super(userMessage: 'errorUserDisabled');
}

/// 단시간 요청 과다 (Firebase `too-many-requests` 코드 매핑).
final class TooManyRequests extends AuthException {
  /// [TooManyRequests]를 생성한다.
  const TooManyRequests({super.cause})
    : super(userMessage: 'errorTooManyRequests');
}

/// 동일 이메일이 다른 인증 방식으로 이미 등록되어 있음.
///
/// Firebase `account-exists-with-different-credential` 코드에 매핑된다.
/// [email]은 충돌이 발생한 이메일 주소로, UI에서 자동 채움용으로 사용한다.
/// [existingProvider]는 Phase 16 D-12 wiring 으로 채워지는 server-side
/// 식별 결과 — `lookupSignInMethods` callable 응답에서 매핑한다 (nullable
/// optional: callable fail/unknown 시 null → R2 unknown fallback 경로).
final class AccountExistsWithDifferentCredential extends AuthException {
  /// [AccountExistsWithDifferentCredential]을 생성한다.
  const AccountExistsWithDifferentCredential({
    this.email,
    this.existingProvider,
    this.pendingCredential,
    super.cause,
  }) : super(userMessage: 'errorAccountExistsWithDifferentCredential');

  /// 충돌이 발생한 이메일 주소. UI에서 자동 채움용으로 사용.
  final String? email;

  /// 기존에 가입된 provider (Phase 16 D-12).
  ///
  /// Cloud Function `lookupSignInMethods` 또는 identity_index conflictKind
  /// 응답으로 채워진다. `null` 인 경우 R2 unknown fallback (R2 baseline
  /// 보존 — `errorAccountExistsWithUnknownProvider`).
  final AccountProvider? existingProvider;

  /// 충돌 시점에 보존된 native pending credential (Phase 16 16-08).
  ///
  /// Firebase `account-exists-with-different-credential` 예외의
  /// `e.credential` 을 보존한다 — 사용자가 기존 provider 로 재인증한 뒤
  /// `linkWithCredential(pendingCredential)` 로 두 자격증명을 한 계정에
  /// 연결하기 위한 입력이다 (native reactive link arm).
  ///
  /// **firebase_auth 경계 보존:** 본 필드는 `Object?` 로 선언되어
  /// core/error 계층이 firebase_auth 에 직접 의존하지 않는다. 실제
  /// `fb.AuthCredential` 로의 cast 는 `AuthRepository`
  /// (`features/auth/data` 경계) 안에서만 수행한다. `null` 인 경우
  /// (Cloud Function `already-exists` path 등 credential 부재) reactive
  /// link 대신 재로그인 유도 fallback 으로 처리한다.
  final Object? pendingCredential;
}

/// 이미 동일 provider 가 계정에 연결되어 있음 (Phase 16 16-08).
///
/// `linkPendingNativeCredential` 의 `linkWithCredential` 단계에서 Firebase
/// 가 `provider-already-linked` 또는 `credential-already-in-use` 코드를
/// 반환할 때 매핑된다. 이미 연결된 자격증명을 중복 link 시도한 경우다.
///
/// **표시 문구는 표면마다 다르다 (Phase 16 G-16-A6-2 / WR-02 / WR-04).**
/// - proactive (Settings Surface D): `SettingsNotifier` 가 본 타입을
///   `AccountLinkOutcome.alreadyLinked` 로 분기하고 위젯이 전용 문구
///   `settingsLinkFailedAlreadyLinked` 를 렌더한다. 2026-09-07 A6 실측에서
///   실제 원인이 `credential-already-in-use` 인데 이메일 문구가 표시된 collapse
///   를 해소하기 위한 것이다.
/// - reactive (AccountLinkingSheet 경로 A): 4차 리뷰 WR-02 이후 시트도 원인별
///   분기를 쓰므로 **같은 전용 문구** `settingsLinkFailedAlreadyLinked` 를
///   렌더한다 — 두 표면의 문구가 일치한다.
/// - 범용 `resolveExceptionMessage` 표면 (FormErrorBanner 등): [userMessage]
///   필드값 `errorAccountExistsWithUnknownProvider` 가 매핑 표를 거쳐 해석
///   된다. 4차 리뷰 WR-04 이전에는 그 arm 이 표에 없어 번역문이 아니라 ARB
///   **키 문자열** 이 렌더됐다 — 지금은 매핑되어 있으므로 이 docstring 이
///   보증하는 경로가 실제로 동작한다.
///
/// [userMessage] 자체는 Phase 9.2 R2 baseline 보존을 위해 변경하지 않는다.
final class AccountAlreadyLinked extends AuthException {
  /// [AccountAlreadyLinked]을 생성한다.
  const AccountAlreadyLinked({super.cause})
    : super(userMessage: 'errorAccountExistsWithUnknownProvider');
}

/// 해당 provider 가 **현재 계정에** 이미 연결되어 있음 (Phase 16 WR-04).
///
/// Firebase `provider-already-linked` 코드에 대응한다. 의미가 정반대인
/// `credential-already-in-use` ([AccountAlreadyLinked] — 해당 자격증명이
/// **다른 계정에** 연결됨) 와 같은 타입으로 뭉개면 사용자에게 사실과 반대인
/// 안내가 나간다.
///
/// - `provider-already-linked` → 본 타입. "이미 이 계정에 연결되어 있다" —
///   사용자가 할 일이 없다.
/// - `credential-already-in-use` → [AccountAlreadyLinked]. "다른 계정이
///   쓰고 있다" — 해제는 그 계정 소유주만 가능하다.
///
/// [userMessage] 는 전용 문구 `settingsLinkFailedAlreadyLinkedHere` 다 (WR-03).
/// 이전에는 reactive 경로 호환을 이유로 [AccountAlreadyLinked] 와 동일한
/// `errorAccountExistsWithUnknownProvider` ("다른 방식으로 가입되어 있습니다 —
/// 처음 가입한 방식으로 다시 로그인해 주세요") 를 공유했는데, 그 문구는
/// `provider-already-linked` 에 대해 사실과 정반대이며 `resolveExceptionMessage`
/// 를 쓰는 모든 표면 (예: `FormErrorBanner`) 에 그대로 노출되었다. 즉 본 타입을
/// 분리한 목적 자체를 reactive 경로에서 되돌리고 있었다.
///
/// proactive Surface D 는 `SettingsNotifier` 가
/// [AccountLinkOutcome.alreadyLinkedHere] 로 분기해 같은 문구를 렌더하므로 두
/// 경로의 문구가 일치한다.
final class ProviderAlreadyLinkedToThisAccount extends AuthException {
  /// [ProviderAlreadyLinkedToThisAccount]을 생성한다.
  const ProviderAlreadyLinkedToThisAccount({super.cause})
    : super(userMessage: 'settingsLinkFailedAlreadyLinkedHere');
}

/// 재인증 필요 (Phase 16 D-06 / D-07).
///
/// `deleteUserAccount` Cloud Function 이 `unauthenticated` 또는
/// `permission-denied` 코드와 함께 `errorReauthenticationRequired` 메시지를
/// 반환할 때 매핑된다. 5분 auth_time boundary 초과 시 발생 — 사용자는
/// `/login` 으로 redirect 후 재로그인 의무.
final class ReauthenticationRequiredException extends AuthException {
  /// [ReauthenticationRequiredException]을 생성한다.
  const ReauthenticationRequiredException({super.cause})
    : super(userMessage: 'errorReauthenticationRequired');
}

/// 인증되지 않은 호출 (Phase 16 D-06).
///
/// `SettingsRepository.requestAccountDeletion` 진입 시
/// `FirebaseAuth.instance.currentUser == null` 일 때 throw 된다.
/// 로그아웃 상태에서의 탈퇴 호출을 가드한다.
final class UnauthenticatedException extends AuthException {
  /// [UnauthenticatedException]을 생성한다.
  const UnauthenticatedException({super.cause})
    : super(userMessage: 'errorUnauthenticated');
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

/// 분류되지 않은 일반 서버 오류 (Phase 16 D-06).
///
/// `deleteUserAccount` Cloud Function 이 `internal` 등 server-side
/// 일반 오류 코드를 반환할 때 매핑된다. 사용자에게는 "탈퇴 실패, 재시도"
/// 안내 (UI-SPEC Surface C / withdrawalFailure SnackBar) 가 표시된다.
final class UnknownException extends ServerException {
  /// [UnknownException]을 생성한다.
  const UnknownException({super.cause}) : super(userMessage: 'errorUnknown');
}
