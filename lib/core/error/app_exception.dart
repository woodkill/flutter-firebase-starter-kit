import '../auth/provider_id.dart';

/// 애플리케이션 전역 예외 계층의 최상위 sealed class.
///
/// 모든 도메인별 예외는 이 클래스를 상속한다.
/// sealed class이므로 switch 문에서 exhaustive 패턴 매칭이 가능하다.
///
/// 직속 하위는 5종이다 — [NetworkException] / [AuthException] /
/// [ServerException] / [InvalidInput] (입력·계약 위반, WR-13) /
/// [UnknownException] (캐치올, IN-05). exhaustive switch 는 다섯 갈래를 모두
/// 다뤄야 한다.
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

  /// 진단용 문자열 표현 (코드 리뷰 WR-07).
  ///
  /// 오버라이드하지 않으면 Dart 기본 구현이 `Instance of 'ServiceUnavailable'`
  /// 를 반환하므로, 이 객체를 기록하는 **모든 채널이 원인 정보를 0비트
  /// 전달**한다. [cause] 는 doc 상 "디버깅/로깅 전용" 인데 정작 어떤 로깅
  /// 경로에서도 출력되지 않았다 — `splash_initializer` 의
  /// `recordError(exception, ...)` 리포트가 대표 사례다.
  ///
  /// **PII 화이트리스트 (중요).** 포함하는 것은 [runtimeType] /
  /// [userMessage] / [cause] 요약 **세 가지뿐**이다. 서브타입 고유 필드
  /// ([AccountExistsWithDifferentCredential.email],
  /// [AccountExistsWithDifferentCredential.pendingCredential] 등) 는 어떤
  /// 경우에도 포함하지 않으며, 그 보장 수단은 **서브타입에서 [toString] 을
  /// 오버라이드하지 않는 것** 이다. 새 서브타입을 추가할 때도 오버라이드하지
  /// 말 것 — 필드를 일괄 출력하는 구현은 이메일을 Crashlytics 리포트와
  /// release 로그로 흘린다 (반복-이슈 체크리스트 9/10항).
  @override
  String toString() {
    final causeSummary = cause == null
        ? ''
        : ', cause: ${_summarizeCause(cause!)}';
    return '$runtimeType($userMessage$causeSummary)';
  }
}

/// 이메일 주소 패턴 — [_summarizeCause] 의 redaction 대상.
final RegExp _kEmailPattern = RegExp(
  r'[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}',
);

/// [cause] 를 PII 없이 요약한다 (WR-07).
///
/// 원본 `toString()` 을 담되 이메일 주소 패턴은 `<redacted-email>` 로
/// 치환한다. [cause] 는 대개 `FirebaseAuthException` 같은 플랫폼 예외이고 그
/// 메시지는 우리가 통제하지 않는 문자열이므로, 사용자 이메일이 섞여 들어가
/// Crashlytics 리포트와 release 로그로 흘러가는 경로를 진단 정보 진입점에서
/// 원천 차단한다.
///
/// core/error 계층은 firebase_auth 에 의존하지 않으므로 (본 파일의
/// `pendingCredential` 경계 주석 참조) 예외 타입별 분기 대신 문자열 수준
/// redaction 을 쓴다.
String _summarizeCause(Object cause) =>
    cause.toString().replaceAll(_kEmailPattern, '<redacted-email>');

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

/// 해제하려는 provider 가 이미 이 계정에 연결되어 있지 않음 (Phase 16.8).
///
/// 대응 코드:
/// - native `User.unlink` 의 Firebase `no-such-provider`.
/// - callable `unlinkCustomTokenProvider` 의 `not-found` (대상 CT 신원 없음).
///
/// 다른 기기에서 먼저 해제했거나 화면이 stale 한 경합에서 발생한다. 재시도로
/// 해소되지 않는 **결정적** 결과이므로 [ServiceUnavailable] 로 뭉개면
/// 「잠시 후 다시 시도」 로 오안내된다 (RESEARCH Pitfall 4) — 전용 문구
/// `settingsUnlinkFailedAlreadyUnlinked` 를 쓴다.
final class ProviderNotLinked extends AuthException {
  /// [ProviderNotLinked]를 생성한다.
  const ProviderNotLinked({super.cause})
    : super(userMessage: 'settingsUnlinkFailedAlreadyUnlinked');
}

/// 남은 로그인 수단이 하나뿐이라 서버가 해제를 거부함 (Phase 16.8 D-03).
///
/// 대응 코드: callable `unlinkCustomTokenProvider` 의 `failed-precondition` +
/// `details.reason: 'last_credential'`. 클라이언트는 자격증명 1개 상태에서
/// 해제 버튼을 숨기지만(`canUnlinkProvider`), 화면 표시와 서버 판정이 경합한
/// 경우 서버 가드가 최종 방어선이다.
///
/// `failed-precondition` 은 기본 매핑(`_mapFunctionsException`)에서
/// [ServiceUnavailable] 로 뭉개져 「잠시 후 다시 시도」 로 오안내되므로
/// (RESEARCH Pitfall 4) 그보다 앞에서 본 타입으로 분기한다 — 재시도로는
/// 절대 해소되지 않는다.
final class UnlinkLastCredentialRejected extends AuthException {
  /// [UnlinkLastCredentialRejected]를 생성한다.
  const UnlinkLastCredentialRejected({super.cause})
    : super(userMessage: 'settingsUnlinkFailedLastCredential');
}

/// 재인증 필요 (Phase 16 D-06 / D-07).
///
/// 서버는 `errorReauthenticationRequired` 를 `unauthenticated` +
/// `details.reason: 'reauthentication_required'` 로 보낸다
/// (`deleteUserAccount` · `linkCustomTokenProvider` · `linkNaverProvider` —
/// idToken 검증 실패 · `assertFreshAuth` auth_time 5분 초과 · 누락 · 미래값 —
/// 16.8 review iteration 2 IN-01 · 16.9 review WR-01).
/// `permission-denied` 는 uid 불일치(`errorUnauthenticated`)다. 클라이언트는
/// 메시지를 읽지 않는다. 두 연결 arm(`AuthRepository._mapLinkCallableException`)
/// 은 reason 이 있는 `unauthenticated` 와 `permission-denied` 만 본 타입으로
/// 만들고, reason 없는 `unauthenticated`(IdP 자격증명 거부 · App Check 차단)는
/// 일시 오류로 흘린다. `SettingsRepository._mapDeleteError` 는 아직 code 만
/// 보고 두 code 모두 본 타입으로 만들므로 App Check 차단(firebase-functions
/// 7.2.5 는 `unauthenticated`)도 본 타입이 된다(알려진 한계 · 동작 불변 —
/// 서버가 싣는 reason 은 이 경로에 무해하다). 그 밖의 생성처:
/// `getIdToken(true)` 비네트워크 실패 · null/빈 idToken
/// (`SettingsRepository`), native link · unlink 의 `requires-recent-login`.
/// 사용자는 `/login` 으로 redirect 후 재로그인 의무.
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

/// 재인증에 쓴 자격증명이 지금 로그인한 계정의 것이 아님
/// (debug reauth-login-auto-merge).
///
/// 재인증 모드 로그인 화면(`/login?reauth=1`)에서만 발생한다. 매핑 원천:
/// - native `reauthenticateWith…` 의 `user-mismatch` · `user-not-found` ·
///   `account-exists-with-different-credential`.
/// - Google 계정 선택기에서 고른 계정 ID 가 현재 계정의 `google.com` 연결과
///   다를 때 (Firebase 호출 전 사전 대조).
/// - Custom Token callable 의 서버 거부 `permission-denied` +
///   `details.reason == 'caller_identity_mismatch'` (비익명 caller 에 매핑 안 된
///   identity).
///
/// 세션은 바뀌지 않은 상태이므로 사용자는 같은 계정으로 다시 시도하면 된다.
final class ReauthUserMismatch extends AuthException {
  /// [ReauthUserMismatch]을 생성한다.
  const ReauthUserMismatch({super.cause})
    : super(userMessage: 'errorReauthUserMismatch');
}

/// 재인증 모드에서 쓸 수 있는 로그인 수단이 하나도 없음
/// (debug reauth-login-auto-merge).
///
/// 현재 계정에 연결된 provider 가 모두 비활성(정적 config 또는 Remote Config
/// kill switch)이고 비밀번호도 연결돼 있지 않을 때 재인증 화면이 배너로
/// 표시한다. 다른 계정으로 로그인하는 우회 경로를 열지 않기 위해 연결되지
/// 않은 provider 는 대안으로 노출하지 않는다.
final class ReauthMethodUnavailable extends AuthException {
  /// [ReauthMethodUnavailable]을 생성한다.
  const ReauthMethodUnavailable({super.cause})
    : super(userMessage: 'errorReauthMethodUnavailable');
}

// ---------------------------------------------------------------------------
// 서버 관련 예외
// ---------------------------------------------------------------------------

/// 서버 관련 예외의 sealed class.
///
/// 서버 내부 오류, 서비스 불가 등 서버 계층에서 발생하는 예외를 분류한다.
///
/// **분류 불가 오류는 여기 두지 않는다 (IN-05).** 캐치올은 [AppException]
/// 직속 leaf 인 [UnknownException] 이다 — "미분류" 를 "서버 장애" 로 오분류하면
/// 재시도 정책과 사용자 문구가 틀어진다.
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

// ---------------------------------------------------------------------------
// 입력 / 계약 위반
// ---------------------------------------------------------------------------

/// 입력값 또는 호출 계약 위반 (10-REVIEW WR-13).
///
/// **[AppException] 직속 leaf 다** — 서비스 장애가 아니기 때문이다.
/// [ServiceUnavailable] 로 표현하면 호출자가 "네트워크 일시 오류이니 잠시 후
/// 재시도" 문구를 붙이게 되는데, 프로그래머 계약 위반은 재시도로 절대 해소
/// 되지 않는다. 실제로 `TermsNotifier.accept` 는 필수 동의 누락(계약 위반)과
/// SharedPreferences 쓰기 실패(서비스 오류)를 같은 타입으로 반환하고 있었고,
/// 호출자는 두 경우를 구분할 방법이 없었다.
///
/// **도달 자체가 결함 신호다.** 정상 UI 경로는 제출 전에 입력을 검증하므로
/// 본 타입이 만들어졌다는 것은 상류 가드가 빠졌다는 뜻이다.
///
/// [userMessage] 는 전용 ARB 키를 신설하지 않고 `errorUnknown` 을 재사용한다
/// (deviation) — 사용자에게 노출될 일이 없는 경로이며, 3 locale ARB 파리티를
/// 늘리지 않기 위해서다. 사용자 노출이 필요한 새 소비처가 생기면 그때 전용
/// 키로 분리한다.
final class InvalidInput extends AppException {
  /// [InvalidInput] 을 생성한다.
  const InvalidInput({super.cause}) : super(userMessage: 'errorUnknown');
}

// ---------------------------------------------------------------------------
// 미분류 예외
// ---------------------------------------------------------------------------

/// 어느 도메인으로도 분류되지 않은 오류 (Phase 16 D-06).
///
/// **[AppException] 직속 leaf 다 ([ServerException] 하위가 아니다) — 코드 리뷰
/// IN-05.** 과거에는 "분류되지 않은 일반 **서버** 오류" 라는 doc 과 함께
/// [ServerException] 을 상속했는데, 실제 사용은 분류 불가 전반의 캐치올이었다.
/// `settings_repository.dart` 의 `_ => UnknownException(cause: e)` 는
/// `invalid-argument` / `cancelled` 같은 **클라이언트 측 원인**까지 흡수하고,
/// `auth_repository.dart` 는 caller 부재 등 구조적 실패에 이 타입을 쓴다.
///
/// 그 상태로 두면 `case ServerException` 으로 분기하는 코드가 서버 장애가
/// 아닌 오류를 서버 장애로 취급해 재시도 정책과 문구 선택이 틀어진다
/// (`splash_initializer._isTransient` 같은 분류기가 확장될 때 특히 위험하다).
/// 직속 leaf 로 올리면 [AppException] 에 대한 exhaustive switch 가 본 타입을
/// **명시적으로 다루도록 컴파일러가 강제**한다 — 오분류가 침묵하지 않는다.
///
/// 사용자에게는 각 표면의 generic 실패 문구 (예: UI-SPEC Surface C /
/// withdrawalFailure SnackBar) 가 표시된다.
final class UnknownException extends AppException {
  /// [UnknownException]을 생성한다.
  const UnknownException({super.cause}) : super(userMessage: 'errorUnknown');
}
