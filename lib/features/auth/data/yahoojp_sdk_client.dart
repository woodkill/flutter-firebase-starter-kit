// Phase 15 — see ROADMAP.md
//
// Yahoo!JP 로그인 진입점 + Phase 14 LineSdkClient 의 typedef 주입 패턴 미러.
// D-YJP-01~22 + Pitfall 8 race-fix 단일 진실원 정책 일관.
//
// **Phase 14 LINE 직접 mirror + 4 deviation:**
// 1. typedef: LineLoginFn → YahoojpAuthorizeFn (flutter_appauth
//    `authorizeAndExchangeCode` 시그니처)
// 2. 사용자 취소 예외 타입: PlatformException 'CANCEL'/'AUTHENTICATION_CANCELLED'
//    → FlutterAppAuthUserCancelledException (flutter_appauth 단일 예외 타입)
// 3. endSession 시그니쳐: LineSDK.logout() → flutter_appauth.endSession(
//    EndSessionRequest) — D-YJP-08. **단 Yahoo!JP 는 endSession endpoint 를
//    공개하지 않아 [YahoojpSdkClient.logout] 은 구조적 no-op 이며 LINE 의
//    실효 토큰 폐기와 동등하지 않다 (WR-03 정정).**
// 4. clientId ctor 주입: LINE 은 LineSDK.instance.setup native config 사용 →
//    Yahoo!JP 는 [AppConfig.yahoojpClientId] 를 SdkClient 생성자에 주입
//    (LineSDK 의 global singleton 와 달리 [FlutterAppAuth] 는 stateless
//    wrapper 이므로 ctor 시점에 config 주입).
import 'package:flutter/foundation.dart';
import 'package:flutter_appauth/flutter_appauth.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/config/app_config.dart';
import '../../../core/auth/nonce.dart';
import '../../../core/error/app_exception.dart';

part 'yahoojp_sdk_client.g.dart';

/// [YahoojpSdkClient.signIn] 의 결과 — Yahoo!JP OIDC ID Token + 호출 시점 nonce.
///
/// `AuthRepository.signInWithYahoojp` 가 본 nonce 를 Cloud Function
/// `yahoojpCustomToken` 호출 인자에 그대로 전달해야 jose 검증이 일치한다
/// (Phase 15 D-YJP-04 single nonce invariant — Phase 14 LINE 패턴 mirror).
///
/// **D-YJP-04 raw nonce transit (5-source cross-verified — see RESEARCH.md):**
/// Yahoo!JP 는 raw nonce 를 그대로 id_token 의 `nonce` claim 에 박는다 (LINE
/// 의 SHA256 hash 와 다름). Cloud Function 측 verifier 는 `nonceHashing: "none"`
/// 으로 raw === claim 비교 (Plan 15-02 D-YJP-04 verbatim).
@immutable
class YahoojpSignInResult {
  /// [idToken] (Yahoo!JP OIDC ID Token, JWT) + [nonce] (단일 호출 raw nonce) 묶음.
  const YahoojpSignInResult({required this.idToken, required this.nonce});

  /// Yahoo!JP OIDC ID Token — JWT raw 문자열. Cloud Function 의 jose 검증 대상.
  final String idToken;

  /// flutter_appauth `AuthorizationTokenRequest.nonce` 인자 + Cloud Function
  /// 호출 양쪽에 동시 전달된 raw nonce (D-YJP-04 nonceHashing=none).
  final String nonce;
}

/// flutter_appauth `FlutterAppAuth.authorizeAndExchangeCode` 함수 시그니처
/// typedef.
///
/// [YahoojpSdkClient.forTest] 의 ctor 인자 타입 — 테스트가 fake 함수를 주입한다.
/// `FlutterAppAuth().authorizeAndExchangeCode(request)` 는 stateless wrapper
/// 이므로 인스턴스 주입 대신 함수 typedef 주입 패턴 채택 (Phase 14 LineSdkClient
/// 패턴 일관).
typedef YahoojpAuthorizeFn =
    Future<AuthorizationTokenResponse> Function(AuthorizationTokenRequest);

/// flutter_appauth `FlutterAppAuth.endSession` 함수 시그니처 typedef
/// (D-YJP-08 endSession 1회성 정책 — Phase 14 D-LINE-57 mirror).
typedef YahoojpEndSessionFn =
    Future<EndSessionResponse> Function(EndSessionRequest);

/// Default `FlutterAppAuth.authorizeAndExchangeCode` 호출 — production 진입점.
Future<AuthorizationTokenResponse> _defaultYahoojpAuthorize(
  AuthorizationTokenRequest request,
) {
  return const FlutterAppAuth().authorizeAndExchangeCode(request);
}

/// Default `FlutterAppAuth.endSession` 호출 — production 진입점.
Future<EndSessionResponse> _defaultYahoojpEndSession(
  EndSessionRequest request,
) {
  return const FlutterAppAuth().endSession(request);
}

/// Yahoo!JP OIDC `AuthorizationServiceConfiguration` (D-YJP-03/05 verbatim).
///
/// Yahoo!JP `configuration.html` OpenID Provider Metadata 의 trailing slash
/// 포함 issuer 와 1:1 일치 의무. discovery URL 미사용 — manual config 채택
/// (RESEARCH §D-YJP-03 verbatim).
///
/// **endSessionEndpoint = null (D-YJP-08):** Yahoo!JP 는 별도 RP-Initiated
/// Logout endpoint 미명시 → [YahoojpSdkClient.logout] 의 endSession 호출 시
/// flutter_appauth 가 `MissingArgumentError` / `PlatformException` throw 가능
/// → graceful try-catch 가 흡수.
const AuthorizationServiceConfiguration _yahoojpServiceConfig =
    AuthorizationServiceConfiguration(
      authorizationEndpoint:
          'https://auth.login.yahoo.co.jp/yconnect/v2/authorization',
      tokenEndpoint: 'https://auth.login.yahoo.co.jp/yconnect/v2/token',
      // ignore: avoid_redundant_argument_values
      endSessionEndpoint: null,
    );

/// Yahoo!JP 로그인 진입점 — `FlutterAppAuth.authorizeAndExchangeCode` wrapper
/// (Phase 15 D-YJP-01/03/04/09).
///
/// **분리 이유 (Phase 14 [LineSdkClient] 패턴 미러):**
/// - mocktail 격리 — `FlutterAppAuth()` 가 인스턴스 메서드이지만 const ctor +
///   stateless wrapper 이므로 ctor 함수 typedef 주입으로 fake 가능하게 한다.
/// - D-YJP-04 single nonce — nonce 는 [signIn] 한 곳에서 1회 생성되어 SDK
///   인자 + 반환값 양쪽에 동시 전달된다 (raw nonce → claim 비교, nonceHashing
///   none).
/// - Pitfall 8 단일 진실원 — 본 wrapper 는 race-fix Notifier 를 읽지도 쓰지도
///   않는다. begin/end 는 `AuthRepository.signInWithYahoojp` 의 try-finally 가
///   단일 진실원이다.
///
/// **사용자 취소 silent (D-YJP-09 정정 lock — Phase 14 D-LINE-21 패턴 mirror):**
/// - [FlutterAppAuthUserCancelledException] (iOS ASWebAuthenticationSession
///   사용자 닫기 / Android Custom Tabs 사용자 뒤로가기) → null
///
/// **idToken null/empty 시 [ServiceUnavailable] throw (Pitfall 1 — OIDC scope
/// 누락):** Yahoo!JP "クライアントサイド・アプリケーション" 등록 시 `openid`
/// scope 미선택 / 사용자 동의 거부 시 idToken null 가능. 호출자
/// (AuthRepository) 가 Failure 로 매핑.
///
/// **clientId.isEmpty 시 [ServiceUnavailable] throw (T-15-15 mitigation):**
/// `--dart-define-from-file` 미주입 시 silent failure 회피.
///
/// **토큰 폐기 미지원 (WR-03 — Phase 7 review 정정):** Yahoo!JP 는
/// RP-Initiated Logout endpoint 를 공개하지 않으므로 [logout] 은 구조적
/// no-op 이다. Kakao / LINE / Naver 가 만족하는 "1회성 토큰 즉시 폐기"
/// (D-57 계열) invariant 를 본 provider 는 **만족하지 못한다** — 상세는
/// [logout] 문서 참조.
class YahoojpSdkClient {
  /// production 진입점 — 실제 flutter_appauth 호출.
  ///
  /// 테스트는 [YahoojpSdkClient.forTest] 로 함수 typedef 를 주입한다.
  YahoojpSdkClient({required this.clientId, required this.redirectUrl})
    : _authorize = _defaultYahoojpAuthorize,
      _endSession = _defaultYahoojpEndSession;

  /// 테스트 전용 ctor — SDK 호출을 함수 typedef 로 fake 한다.
  ///
  /// production 코드는 [YahoojpSdkClient.new] 만 사용해야 한다.
  @visibleForTesting
  YahoojpSdkClient.forTest({
    required this.clientId,
    required this.redirectUrl,
    required YahoojpAuthorizeFn authorize,
    required YahoojpEndSessionFn endSession,
  }) : _authorize = authorize,
       _endSession = endSession;

  /// Yahoo Developers Console "クライアントサイド・アプリケーション" 의 Client
  /// ID (D-YJP-03). [AppConfig.yahoojpClientId] 로부터 주입.
  final String clientId;

  /// Yahoo!JP OAuth redirect URL — `${scheme}:/oauth2redirect` (D-YJP-03).
  /// [AppConfig.yahoojpRedirectScheme] 가 source.
  final String redirectUrl;

  final YahoojpAuthorizeFn _authorize;
  final YahoojpEndSessionFn _endSession;

  /// Yahoo!JP OIDC 로그인 — ASWebAuthenticationSession (iOS) / Custom Tabs
  /// (Android) (flutter_appauth 가 OS 분기 자동 처리).
  ///
  /// 흐름:
  /// 1. [generateNonce] (`byteLength: 16`, IN-05 공통 helper) 로 raw nonce
  ///    1회 생성 (D-YJP-04 single nonce). 16 bytes = 22 chars
  ///    (base64url, padding 제거).
  /// 2. `clientId.isEmpty` 시 [ServiceUnavailable] throw (T-15-15 mitigation).
  /// 3. `_authorize(AuthorizationTokenRequest(clientId, redirectUrl,
  ///    serviceConfiguration: _yahoojpServiceConfig, scopes: ['openid',
  ///    'profile'], nonce: nonce))` 호출 (D-YJP-09 정정 lock — email scope
  ///    미채택).
  /// 4. `response.idToken == null || isEmpty` (Pitfall 1 — OIDC scope 누락) →
  ///    [ServiceUnavailable] throw.
  /// 5. 사용자 취소 ([FlutterAppAuthUserCancelledException]) → null 반환
  ///    (D-YJP-09 silent cancel).
  ///
  /// 반환:
  /// - [YahoojpSignInResult] (idToken + 같은 nonce) — 성공.
  /// - null — 사용자 취소.
  Future<YahoojpSignInResult?> signIn() async {
    if (clientId.isEmpty) {
      // T-15-15: --dart-define-from-file 미주입 silent failure 회피.
      throw const ServiceUnavailable();
    }
    final nonce = generateNonce(byteLength: 16);
    try {
      final request = AuthorizationTokenRequest(
        clientId,
        redirectUrl,
        serviceConfiguration: _yahoojpServiceConfig,
        // D-YJP-09 정정 lock — Yahoo!JP UserInfo API 審査 절차 회피.
        // openid+profile 만, email scope 미채택. Firebase Auth user record 의
        // email 필드는 비어 있어 _autoSendEmailVerification 가 자연 no-op.
        scopes: const <String>['openid', 'profile'],
        nonce: nonce,
      );
      final response = await _authorize(request);
      final idToken = response.idToken;
      if (idToken == null || idToken.isEmpty) {
        // Pitfall 1 (LINE WR-03 mirror): OIDC scope 누락 / 사용자 동의 거부 시
        // idToken null 가능. server-side errorInvalidCredentials 분기와
        // 일관성 보장 + Cloud Function round-trip / App Check / JWKS network
        // 비용 회피.
        throw const ServiceUnavailable();
      }
      return YahoojpSignInResult(idToken: idToken, nonce: nonce);
    } on FlutterAppAuthUserCancelledException {
      // D-YJP-09 정정 lock silent cancel (Phase 14 D-LINE-21 mirror).
      // flutter_appauth 가 iOS ASWebAuthenticationSession 사용자 닫기 /
      // Android Custom Tabs 사용자 뒤로가기 양쪽을 단일 예외 타입으로 노출
      // (LINE 의 PlatformException 'CANCEL'/'AUTHENTICATION_CANCELLED' 이원
      // 분기와 다름 — deviation #2).
      return null;
    }
  }

  /// SDK endSession — **현재는 구조적 no-op** (WR-03, Phase 7 review 정정).
  ///
  /// `AuthRepository.signInWithYahoojp` 의 finally 블록 (race-fix end 직전 —
  /// Pitfall 2) 에서 호출한다.
  ///
  /// **미지원 명시 (WR-03 — D-YJP-08 의 실효 범위 정정):** Yahoo!JP 는
  /// RP-Initiated Logout endpoint 를 공개하지 않는다 ([_yahoojpServiceConfig]
  /// 의 `endSessionEndpoint = null` — D-YJP-03/05 verbatim). 따라서
  /// **client-side 토큰 폐기는 수행되지 않으며**, 본 메서드는 Kakao
  /// (`UserApi.instance.logout`) / LINE (`LineSDK.logout`) / Naver
  /// (`FlutterNaverLogin.logOut`) 의 D-57 invariant 와 **동등하지 않다**.
  /// Yahoo!JP 세션·토큰은 디바이스에 남으며, 호출 대칭성 유지와 미래
  /// endpoint 공개 대비를 위해 메서드 자체는 보존한다.
  ///
  /// 이전 구현은 `endSessionEndpoint = null` 인 config 로 그대로 `endSession`
  /// 을 호출해 **매번 예외를 발생시키고 graceful catch 가 삼키는** 구조였다.
  /// 성공할 수 없는 platform-channel 왕복이므로 endpoint 부재를 선행 분기로
  /// 명시해 no-op 임을 코드에 드러낸다.
  ///
  /// **재도입 진입점:** Yahoo!JP 가 endSession endpoint 를 공개하면
  /// [_yahoojpServiceConfig] 의 `endSessionEndpoint` 만 채우면 아래 분기가
  /// 자동으로 실효 폐기로 전환된다 — 호출부 변경 0.
  ///
  /// **idTokenHint + postLogoutRedirectUrl 모두 null (D-YJP-08):**
  /// [EndSessionRequest] 의 assertion `(idTokenHint==null &&
  /// postLogoutRedirectUrl==null) || (둘 다 non-null)` 를 충족하기 위해 둘 다
  /// null 로 호출 (best-effort logout).
  Future<void> logout() async {
    // WR-03: endpoint 부재 = 폐기 불가. 도달 불가능한 호출을 생략한다.
    if (_yahoojpServiceConfig.endSessionEndpoint == null) {
      if (kDebugMode) {
        debugPrint(
          'YahoojpSdkClient.logout: endSessionEndpoint 미공개 — no-op '
          '(WR-03: D-57 토큰 폐기 invariant 미지원 provider)',
        );
      }
      return;
    }
    try {
      await _endSession(
        EndSessionRequest(
          // ignore: avoid_redundant_argument_values
          idTokenHint: null,
          // ignore: avoid_redundant_argument_values
          postLogoutRedirectUrl: null,
          serviceConfiguration: _yahoojpServiceConfig,
        ),
      );
    } on Object catch (e, st) {
      if (kDebugMode) {
        debugPrint('YahoojpSdkClient.logout 실패 (무시): ${e.runtimeType}\n$st');
      }
    }
  }
}

/// [YahoojpSdkClient] Provider — keepAlive (Phase 14 [lineSdkClientProvider]
/// 패턴 일관).
///
/// **clientId ctor 주입 (deviation #4):** LINE 은 `LineSDK.instance.setup`
/// 가 native global config 를 보유하므로 ctor 인자 0개. Yahoo!JP 는
/// [FlutterAppAuth] 가 stateless wrapper 이므로 ctor 시점에 clientId +
/// redirectUrl 주입 의무. [AppConfig.yahoojpClientId] +
/// [AppConfig.yahoojpRedirectScheme] 가 source.
@Riverpod(keepAlive: true)
YahoojpSdkClient yahoojpSdkClient(Ref ref) {
  return YahoojpSdkClient(
    clientId: AppConfig.yahoojpClientId,
    redirectUrl: '${AppConfig.yahoojpRedirectScheme}:/oauth2redirect',
  );
}
