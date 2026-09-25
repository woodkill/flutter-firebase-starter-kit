// Phase 16.5 — see ROADMAP.md
//
// 킷 소유 Naver 웹 OAuth 흐름 (D-07 · D-12 · D-12a · D-14). NAVER 앱이 없는
// 단말에서 SDK 커스텀탭 대신 `flutter_web_auth_2` 세션(Android Auth Tab /
// Custom Tab · iOS ASWebAuthenticationSession) 으로 authorize 를 열고, 콜백의
// `code` + `state` 를 돌려준다. token 교환은 서버(`naverWebCustomToken`) 몫이다.
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_web_auth_2/flutter_web_auth_2.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/auth/nonce.dart';
import '../../../core/config/app_config.dart';
import '../../../core/error/app_exception.dart';
import 'naver_sign_in_result.dart';

part 'naver_web_auth_client.g.dart';

/// `FlutterWebAuth2.authenticate` 시그니처 typedef — 반환은 콜백 URL 전문.
///
/// [NaverWebAuthClient.forTest] 의 인자 타입 — 테스트가 fake 를 주입한다.
/// 옵션 객체 대신 [preferEphemeral] bool 하나만 노출해 fake 가 D-12 선택을
/// 그대로 관측할 수 있게 한다.
typedef NaverWebAuthenticateFn =
    Future<String> Function({
      required String url,
      required String callbackUrlScheme,
      required bool preferEphemeral,
    });

/// 킷 웹 로그인 함수 시그니처 — `NaverSdkClient` 가 웹 클라이언트를 이 함수
/// 타입으로만 안다 (1-tap 경로가 `flutter_web_auth_2` 에 닿지 않게 하는 경계).
typedef NaverWebSignInFn = Future<NaverWebSignIn?> Function();

/// 콜백 scheme 형태 — RFC 3986 `ALPHA *( ALPHA / DIGIT / "+" / "-" / "." )`
/// 의 소문자 한정판.
///
/// `flutter_web_auth_2` 5.1.0 이 Dart 단에서 같은 정규식으로 강제하고, 위반 시
/// `PlatformException` 이 아닌 `ArgumentError` 를 던진다 (RESEARCH Pitfall 2).
/// 그 전에 여기서 걸러 「원인 불명 배너」 대신 `code=config` 로 드러낸다.
final RegExp kNaverWebCallbackSchemePattern = RegExp(r'^[a-z][a-z\d+.-]*$');

/// NAVER authorize 엔드포인트 host (RESEARCH 「엔드포인트 상수」).
const String _kNaverAuthorizeHost = 'nid.naver.com';

/// NAVER authorize 엔드포인트 path.
const String _kNaverAuthorizePath = '/oauth2.0/authorize';

/// 동의 화면 취소 — RFC 6749 §4.1.2.1 `error=access_denied`.
const String _kAccessDeniedError = 'access_denied';

/// Default `FlutterWebAuth2.authenticate` 호출 — production 진입점.
Future<String> _defaultNaverWebAuthenticate({
  required String url,
  required String callbackUrlScheme,
  required bool preferEphemeral,
}) {
  return FlutterWebAuth2.authenticate(
    url: url,
    callbackUrlScheme: callbackUrlScheme,
    options: FlutterWebAuth2Options(preferEphemeral: preferEphemeral),
  );
}

/// 킷 소유 Naver 웹 OAuth 클라이언트 (Phase 16.5 D-07 · D-12 · D-12a · D-14).
///
/// **분리 이유 (RESEARCH Pattern 1):** `NaverSdkClient.signIn()` 은 설치
/// 판정 → 분기만 하고 웹 흐름 전체는 이 클래스가 소유한다. 테스트가 「라우팅」
/// 과 「웹 흐름 세부」 를 독립적으로 fake 할 수 있다. 구조는 킷에서 OAuth
/// 흐름을 직접 소유하는 SDK client 의 typedef 주입 패턴을 따른다.
///
/// **타이머 없음 (16.2 D-16):** 세션 API 가 「창 닫힘 = Future 완료」 를
/// 보장한다(Android dangling 정리 포함) — 앱 쪽 대기 한도를 두지 않는다.
///
/// **PKCE 없음 (T-16.5-02, 잔존 위험 명시):** NAVER SDK 도 쓰지 않는다. 완화는
/// `state` 대조 + `code` 1회성 + `client_secret` 서버 단독 + access_token 서버
/// 메모리 한정(저장 · 응답 0).
class NaverWebAuthClient {
  /// production 진입점 — 실제 `flutter_web_auth_2` 호출.
  ///
  /// 테스트는 [NaverWebAuthClient.forTest] 로 authenticate 함수를 주입한다.
  NaverWebAuthClient({
    required this.clientId,
    required this.callbackUrlScheme,
    required this.redirectUri,
  }) : _authenticate = _defaultNaverWebAuthenticate;

  /// 테스트 전용 ctor — 웹 세션 호출을 함수 typedef 로 fake 한다.
  ///
  /// production 코드는 [NaverWebAuthClient.new] 만 사용해야 한다.
  @visibleForTesting
  NaverWebAuthClient.forTest({
    required this.clientId,
    required this.callbackUrlScheme,
    required this.redirectUri,
    required NaverWebAuthenticateFn authenticate,
  }) : _authenticate = authenticate;

  /// NAVER 개발자센터 Client ID — 공개 식별자 ([AppConfig.naverClientId]).
  final String clientId;

  /// 세션이 가로챌 콜백 scheme ([AppConfig.naverWebCallbackScheme]).
  final String callbackUrlScheme;

  /// authorize 요청의 `redirect_uri` ([AppConfig.naverWebRedirectUri]).
  final String redirectUri;

  final NaverWebAuthenticateFn _authenticate;

  /// 킷 웹 흐름으로 Naver 로그인 — authorize → 콜백 `code` + `state`.
  ///
  /// 흐름 (D-12a 분기):
  /// 1. 설정 가드 — [clientId] 빈 문자열 · [callbackUrlScheme] 형태 위반 ·
  ///    [redirectUri] 형태 불일치([_isRedirectUriConsistent])면 세션을 열지 않고
  ///    [ServiceUnavailable] (`code=config`).
  /// 2. `state` = `Random.secure()` 16 bytes (22 chars) — 매 호출 새 값 (D-14).
  /// 3. authorize URL = `response_type` · `client_id` · `redirect_uri` ·
  ///    `state` 4 파라미터 (probe ② A5 — 부가 파라미터 불필요).
  /// 4. 세션 — `preferEphemeral` 는 끈다 (D-12 SSO 쿠키 공유 · T-16.5-07).
  /// 5. `PlatformException.code == CANCELED` → null (silent · 3 message 변형
  ///    전부). 그 밖의 `PlatformException` 은 그대로 rethrow — 호출자
  ///    (`NaverSdkClient`) 가 `ServiceUnavailable(cause:)` 로 접는다.
  /// 6. 콜백 `error=access_denied` → null (동의 화면 취소). 그 밖의 `error` ·
  ///    `state` 불일치 · `code` 부재 → [ServiceUnavailable].
  ///
  /// 진단 로그 (`kDebugMode` 전용 · WR-05): `Naver web 시작` ·
  /// `Naver web 도착: outcome=<code|cancel|error> elapsedMs=<n>` (error 일 때만
  /// ` code=<config|callback|state|missing|PlatformException.code>` 접미) ·
  /// `Naver web state 불일치`. 콜백 URL · `code` · `state` 원문은 어느 줄에도
  /// 싣지 않는다.
  ///
  /// 반환:
  /// - [NaverWebSignIn] — 성공.
  /// - null — 사용자 취소 (세션 닫기 · 동의 거부 · Android 앱 전면 복귀).
  /// - throw [ServiceUnavailable] / `PlatformException` — 설정 · 콜백 · 세션 오류.
  Future<NaverWebSignIn?> signIn() async {
    if (clientId.isEmpty ||
        !kNaverWebCallbackSchemePattern.hasMatch(callbackUrlScheme) ||
        !_isRedirectUriConsistent()) {
      // T-15-15 패턴 — --dart-define-from-file 미주입 · scheme 오타를 세션
      // 열기 전에 시끄럽게 드러낸다 (ArgumentError 로 새지 않게).
      _logArrival('error', null, code: 'config');
      throw const ServiceUnavailable();
    }

    final state = generateNonce(byteLength: 16);
    final url = Uri.https(_kNaverAuthorizeHost, _kNaverAuthorizePath, {
      'response_type': 'code',
      'client_id': clientId,
      'redirect_uri': redirectUri,
      'state': state,
    }).toString();

    // IN-03: 경과 ms 는 `kDebugMode` 블록에서만 소비된다 — release 에서는
    // Stopwatch 를 만들지도 않는다.
    final Stopwatch? watch = kDebugMode ? (Stopwatch()..start()) : null;
    if (kDebugMode) {
      debugPrint('Naver web 시작');
    }

    final String callbackUrl;
    try {
      callbackUrl = await _authenticate(
        url: url,
        callbackUrlScheme: callbackUrlScheme,
        preferEphemeral: false,
      );
    } on PlatformException catch (e) {
      // Android Auth Tab 닫기 · Android dangling 정리 · iOS 세션 닫기 — 세
      // 경로 모두 code 만 같고 message 는 서로 다르다. message 로 판정하면
      // Android 취소 한 갈래를 놓친다 (RESEARCH 「취소 · 실패 표면」 · D-12a).
      if (e.code == 'CANCELED') {
        _logArrival('cancel', watch);
        return null;
      }
      // FAILED · EUNKNOWN · ACQUIRE_ROOT_VIEW_CONTROLLER_FAILED — 플러그인
      // 정의 code 라 로그에 실어도 사용자 정보가 아니다.
      _logArrival('error', watch, code: e.code);
      rethrow;
    }

    final params = _parseCallbackQuery(callbackUrl);
    if (params == null) {
      _logArrival('error', watch, code: 'callback');
      throw const ServiceUnavailable();
    }

    final error = params['error'];
    if (error == _kAccessDeniedError) {
      // 동의 화면 취소 — SDK 의 user_cancel 과 같은 축 (D-12a silent).
      _logArrival('cancel', watch);
      return null;
    }
    if (error != null) {
      _logArrival('error', watch, code: 'callback');
      throw const ServiceUnavailable();
    }

    // D-14 CSRF — 클라이언트가 만든 값과 콜백 값을 비교한다. 주입된 콜백은
    // state 를 모르므로 여기서 실패한다 (silent 아님 → 배너).
    if (params['state'] != state) {
      if (kDebugMode) {
        debugPrint('Naver web state 불일치');
      }
      _logArrival('error', watch, code: 'state');
      throw const ServiceUnavailable();
    }

    final code = params['code'];
    if (code == null || code.isEmpty) {
      _logArrival('error', watch, code: 'missing');
      throw const ServiceUnavailable();
    }

    _logArrival('code', watch);
    return NaverWebSignIn(code: code, state: state);
  }

  /// [redirectUri] 가 세션이 가로챌 수 있는 형태인지 확인한다 (16.5 review IN-04).
  ///
  /// [AppConfig.naverWebRedirectUri] 는 `'<scheme>://authorize'` 라 dart-define
  /// 이 없어도 빈 문자열이 되지 않는다 — `isEmpty` 가드는 도달 불가였다. 대신
  /// 형태를 본다.
  /// - 파싱 실패 · scheme 부재 → false.
  /// - `https` → host 가 있어야 한다. 매뉴얼 9단계 (6) Hosting bounce 대안은
  ///   https 페이지가 [callbackUrlScheme] 으로 재이동하므로 scheme 이 달라도
  ///   정상이다.
  /// - 그 밖의 custom scheme → [callbackUrlScheme] 과 같아야 한다. 다르면
  ///   NAVER 가 세션이 가로채지 못하는 주소로 콜백해 로그인이 끝나지 않는다.
  bool _isRedirectUriConsistent() {
    final uri = Uri.tryParse(redirectUri);
    if (uri == null || !uri.hasScheme) return false;
    if (uri.scheme == 'https') return uri.host.isNotEmpty;
    return uri.scheme == callbackUrlScheme;
  }

  /// 콜백 URL 의 쿼리 파라미터 — URL · percent-encoding 이 깨졌으면 null.
  ///
  /// `Uri.queryParameters` 는 잘못된 `%` 인코딩에 `FormatException` 을 던지므로
  /// 둘 다 null 로 접어 `code=callback` 오류로 드러낸다.
  Map<String, String>? _parseCallbackQuery(String callbackUrl) {
    try {
      return Uri.tryParse(callbackUrl)?.queryParameters;
    } on FormatException {
      return null;
    }
  }

  /// 도착 줄 — outcome 이름 · 경과 ms · (error 일 때) 닫힌 집합 code 만 싣는다.
  ///
  /// 콜백 URL · `code` · `state` 원문은 인자로 받지도 않는다 (WR-05).
  void _logArrival(String outcome, Stopwatch? watch, {String? code}) {
    if (!kDebugMode) return;
    final suffix = code == null ? '' : ' code=$code';
    debugPrint(
      'Naver web 도착: outcome=$outcome '
      'elapsedMs=${watch?.elapsedMilliseconds ?? 0}$suffix',
    );
  }
}

/// [NaverWebAuthClient] Provider — keepAlive (`lineSdkClientProvider` 패턴).
///
/// [AppConfig] 3상수(`naverClientId` · `naverWebCallbackScheme` ·
/// `naverWebRedirectUri`) 를 ctor 에 주입한다.
@Riverpod(keepAlive: true)
NaverWebAuthClient naverWebAuthClient(Ref ref) {
  return NaverWebAuthClient(
    clientId: AppConfig.naverClientId,
    callbackUrlScheme: AppConfig.naverWebCallbackScheme,
    redirectUri: AppConfig.naverWebRedirectUri,
  );
}
