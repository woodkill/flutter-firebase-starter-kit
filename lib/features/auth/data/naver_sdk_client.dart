// Phase 16.2 — see ROADMAP.md
//
// Naver 로그인 진입점 — 플러그인 Future 직결 + typedef 주입 (Phase 12
// KakaoSdkClient 미러). D-43 ~ D-45 + D-57 정책 일관.
// Phase 16.4 D-18 로그 2줄 — signIn() 시작 · 도착 (kDebugMode 전용).
// Phase 16.5 D-01 ~ D-04 — signIn() 이 NAVER 앱 설치 판정 bool 하나로 1-tap
// (SDK) 과 킷 웹 흐름을 라우팅한다. 웹 클라이언트는 함수 typedef 로만 안다.
import 'package:flutter/foundation.dart';
import 'package:naver_login_flutter/naver_login_flutter.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/error/app_exception.dart';
import 'naver_host_channel.dart';
import 'naver_sign_in_result.dart';
import 'naver_web_auth_client.dart';

part 'naver_sdk_client.g.dart';

/// 플러그인 `FlutterNaverLogin.logIn()` 시그니처 typedef.
///
/// [NaverSdkClient.forTest] 의 ctor 인자 타입 — 테스트가 fake 함수를 주입한다.
typedef NaverLoginFn = Future<NaverLoginResult> Function();

/// 플러그인 `FlutterNaverLogin.logOut()` 시그니처 typedef (D-57).
typedef NaverLogoutFn = Future<NaverLoginResult> Function();

/// 플러그인 `errorMessage` 를 보관하는 구조화 에러 (Phase 16.2 D-13).
///
/// 새 API 에는 정수 errorCode 가 없어 구 `NaverSdkError(int, String)` 을
/// `String` 단일 필드로 축소했다. [message] 원문은 자유 문자열(요청 URL ·
/// 사용자 입력 등)을 실을 수 있으므로 [toString] 이 [describeNaverErrorForLog]
/// 를 거쳐 닫힌 집합 이름 · 길이만 내보낸다 (WR-05 — `cause` 가 어디선가
/// 문자열화돼도 구조적으로 안전).
@immutable
class NaverSdkError implements Exception {
  /// 플러그인이 `NaverLoginResult.errorMessage` 로 전달한 원문을 보관한다.
  const NaverSdkError(this.message);

  /// 플러그인 원문 메시지 — 로그 · 사용자 문구로 그대로 내보내지 않는다.
  final String message;

  @override
  String toString() => 'NaverSdkError(${describeNaverErrorForLog(message)})';
}

/// iOS 플러그인이 사용자 취소에 붙이는 **고정 리터럴**.
///
/// 출처: `naver_login_flutter` 4.0.0 iOS 플러그인
/// `ios/naver_login_flutter/Sources/naver_login_flutter/`
/// `FlutterNaverLoginPlugin.swift:249` 의 `sendError(message:)` 인자다
/// (기준선은 `16.2-PLUGIN-AUDIT.md`). SDK 메시지가 아니라 플러그인이 직접
/// 만든 영문 리터럴이라 단말 locale 과 무관하다.
const String kNaverIosCancelMessage = 'Login cancelled by user';

/// 완전 일치 닫힌 집합 — 원문 → 로그용 이름 (RESEARCH §9 verbatim).
const Map<String, String> _kNaverExactMessages = <String, String>{
  kNaverIosCancelMessage: 'ios_plugin_cancelled',
  'Another request is in progress. Please wait':
      'ios_plugin_request_in_progress',
  'No access token available': 'ios_plugin_no_access_token',
  'No refresh token available': 'plugin_no_refresh_token',
  'Activity is null': 'android_plugin_activity_null',
  'Failed to get refreshed access token': 'android_plugin_refresh_failed',
  'SDK not initialized. Please call initSdk first.':
      'android_plugin_sdk_not_initialized',
  'NidOAuth.initialize() should be called before using NidOAuth.':
      'ios_sdk_not_initialized',
  'Missing client configuration. \nPlease check your configuration.':
      'ios_sdk_missing_client_config',
  'Client configuration format is invalid. \nPlease check if your '
          'configuration is in correct format.':
      'ios_sdk_invalid_client_config',
  'User canceled the request.': 'ios_sdk_user_canceled',
  'Unsupported response type.': 'ios_sdk_unsupported_response_type',
  'Naver app is not installed. \nPlease install Naver App to authenticate '
          'using Naver App.':
      'ios_sdk_naver_app_not_installed',
  'No active window scene to present the login screen on. \nPlease request '
          'login while your app is in the foreground.':
      'ios_sdk_no_window_scene',
  'Response is not in valid format.': 'ios_sdk_invalid_response',
  'Multiple initialize() calls detected.\nThis method should be invoked '
          'only once during app launch.':
      'ios_sdk_multiple_initialize',
};

/// Android 플러그인이 종단 실패에 붙이는 접두어 — 뒤에 code 와 desc 가 온다.
const String _kNaverAndroidErrorCodePrefix = 'errorCode:';

/// 접두어 닫힌 집합 — 접두어 → 로그용 이름 (RESEARCH §9 verbatim).
///
/// 뒤 꼬리는 자유 문자열(요청 URL · NSError userInfo)이라 **절대 출력하지
/// 않는다** — 이름과 길이만 남긴다.
const Map<String, String> _kNaverPrefixMessages = <String, String>{
  'Failed to get user info:': 'android_plugin_user_info_failed',
  'Failed to parse user info:': 'android_plugin_user_info_parse_failed',
  'Token deletion failed:': 'ios_plugin_token_deletion_failed',
  'State not matched.': 'ios_sdk_state_not_matched',
  'Invalid URL Response.': 'ios_sdk_invalid_url_response',
  'Network error. Detailed error description:': 'ios_sdk_network_error',
  'ASWebAuthentication internal error.': 'ios_sdk_web_auth_internal_error',
  'NID given Error. Error Code:': 'ios_sdk_nid_given_error',
};

/// Android SDK 의 errorCode 닫힌 집합 (AAR 바이트코드 실측 — RESEARCH §2).
///
/// SDK 상수라 로그에 그대로 써도 사용자 정보가 아니다. 이 집합 밖의 값은
/// `other` 로 접는다. (`no_catagorized_error` 의 철자는 SDK 원문 그대로다.)
const Set<String> _kNaverAndroidErrorCodes = <String>{
  'invalid_request',
  'unauthorized_client',
  'access_denied',
  'unsupported_response_type',
  'invalid_scope',
  'server_error',
  'temporarily_unavailable',
  'no_catagorized_error',
  'parsing_fail',
  'user_cancel',
  'activity_is_single_task',
  'web_view_is_deprecated',
  'no_app_for_authentication',
  'sdk_is_not_initialized',
  'need_app_update',
  'sdk_execution_error',
};

/// 플러그인 결과가 **사용자 취소**인지 판정한다 (D-45 silent 대상).
///
/// 플랫폼별 표면이 다르다 (RESEARCH §2 verbatim):
/// - Android: 취소는 `onFailure` 를 거쳐 `status` [NaverLoginStatus.loggedOut]
///   로 온다. `logIn()` 이 `loggedOut` 을 돌려주는 native 경로는 취소와
///   「토큰 없는 성공」 둘뿐이고 후자도 silent 대상이다.
/// - iOS: 취소는 `loggedOut` 이 아니라 [NaverLoginStatus.error] + 플러그인
///   고정 리터럴 [kNaverIosCancelMessage] 로 온다.
///
/// **완전 일치만 본다** (D-12) — `contains` · 접두어 · 대소문자 무시 비교로
/// 넓히면 `-999 cancelled` 같은 네트워크 오류까지 silent 로 흡수돼 사용자가
/// 실패를 알 수 없게 된다.
///
/// **이 규칙은 iOS 표면에만 적용된다 (WR-08).** Android 는 플러그인이 킷에
/// 결과를 주기 **전에** `errorCode == "user_cancel" ||
/// errorDesc.contains("cancel", ignoreCase = true)` 를 취소
/// ([NaverLoginStatus.loggedOut]) 로 접어 보낸다
/// (`FlutterNaverLoginPlugin.kt:293-296`). 즉 **플러그인 상류가 이미 넓혀
/// 놓았으므로**, desc 에 `cancel` 이 섞인 Android 네트워크 오류는 킷에
/// 도착하는 시점에 이미 취소이고 배너 없이 silent 로 흡수된다. 킷 코드로는
/// 고칠 수 없다 — 아래 [isNaverUserCancel] 을 좁혀도 `loggedOut` 밖의
/// 정보가 남아 있지 않다. Android 의 「무반응」 제보는 취소 로그부터 확인할
/// 것 (`docs/manual.md` Naver Pitfall 11).
///
/// 16.4 레버 2 는 Phase 16.5 가 제거했다 — 웹 경로는 킷 소유 흐름(D-16).
///
/// **비대상:** iOS 에서 NAVER 앱(1-tap) 경로의 취소는 이 매핑을 타지 않을 수
/// 있다 — 복귀 URL 의 code 가 취소 값을 갖지 않아 서버 오류로 표면화된다.
/// 테스트 SIM 부재로 실측이 불가능하다 (C-06). `docs/manual.md` 의 Naver
/// Pitfall 절을 참조할 것.
@visibleForTesting
bool isNaverUserCancel(NaverLoginStatus status, String? errorMessage) {
  if (status == NaverLoginStatus.loggedOut) return true;
  return status == NaverLoginStatus.error &&
      errorMessage == kNaverIosCancelMessage;
}

/// 플러그인 `errorMessage` 를 PII 없는 진단 문자열로 바꾼다 (D-14 / WR-05).
///
/// 원문은 요청 URL · NSError userInfo · 사용자 입력을 실을 수 있어 **한 글자도
/// 출력하지 않는다**. 닫힌 집합에 들면 그 이름을, 아니면 `other` 를 쓰고 길이만
/// 덧붙인다.
///
/// 출력 계약 (한 줄):
/// - `null` → `message=null length=0`
/// - 완전 일치 집합 → `message=<이름> length=<n>`
/// - `errorCode:` 접두어 → `message=android_plugin_error_code` 뒤에
///   `errorCode=<code|other>` 와 `length=<n>`
/// - 그 외 접두어 집합 → `message=<이름> length=<n>` (꼬리는 길이로만 보고)
/// - 그 외 자유 문자열 → `message=other length=<n>`
@visibleForTesting
String describeNaverErrorForLog(String? errorMessage) {
  if (errorMessage == null) return 'message=null length=0';

  final length = errorMessage.length;

  final exactName = _kNaverExactMessages[errorMessage];
  if (exactName != null) return 'message=$exactName length=$length';

  if (errorMessage.startsWith(_kNaverAndroidErrorCodePrefix)) {
    final code = _readAndroidErrorCode(errorMessage);
    return 'message=android_plugin_error_code errorCode=$code '
        'length=$length';
  }

  for (final entry in _kNaverPrefixMessages.entries) {
    if (errorMessage.startsWith(entry.key)) {
      return 'message=${entry.value} length=$length';
    }
  }

  return 'message=other length=$length';
}

/// `errorCode:<code>, errorDesc:<자유 문자열>` 에서 code 만 뽑는다.
///
/// 닫힌 집합([_kNaverAndroidErrorCodes]) 밖이면 `other` 로 접는다 — desc 는
/// 자유 문자열이라 애초에 읽지 않는다.
String _readAndroidErrorCode(String errorMessage) {
  final tail = errorMessage.substring(_kNaverAndroidErrorCodePrefix.length);
  final separator = tail.indexOf(',');
  final code = (separator < 0 ? tail : tail.substring(0, separator)).trim();
  return _kNaverAndroidErrorCodes.contains(code) ? code : 'other';
}

/// Naver 로그인 진입점 — 플러그인 Future 직결 wrapper (Phase 16.2 — see
/// ROADMAP.md, D-16 · D-43 ~ D-45 + D-57).
///
/// **분리 이유 (Phase 12 `KakaoSdkClient` 패턴 미러):**
/// - mocktail 격리 — `FlutterNaverLogin.logIn` 이 static 이라 ctor 함수
///   typedef 주입으로 fake 가능하게 한다.
/// - D-57 1회성 토큰 — [signIn] 성공/실패/취소 모든 분기에서
///   `AuthRepository.signInWithNaver` 의 finally 블록이 [logout] 을 호출한다.
///
/// **타이머 없음 (D-16):** 플러그인 Future 를 그대로 await 한다. 앱 쪽
/// `Completer` · `Future.timeout` 이 없으므로 「늦게 끝난 성공을 버리는」
/// 주체가 구조적으로 존재하지 않는다.
///
/// **in-flight 가드 (D-18) — 보장과 비보장:**
/// - (보장) 킷이 만들어내는 동시 plugin 호출이 0 이다. [signIn] 이 진행 중인
///   동안의 재진입은 plugin 을 호출하지 않고 null 을 돌려주며, 같은 동안의
///   [logout] 도 plugin 을 즉시 호출하지 않는다. Android 로그인 콜백이 static
///   단일 슬롯이라 덮어쓰기 위험이 있고, iOS 는 재진입 시 스스로
///   「Another request is in progress」 를 자초하기 때문이다. **지연된
///   [logout] 을 소비하는 동안에도 가드는 내려가지 않는다 (WR-09)** — 그래서
///   이 보장이 plugin `logOut()` 라운드트립 구간까지 끊기지 않고 이어진다.
/// - (보장) 가드에 걸린 [logout] 은 **버려지지 않는다** (WR-01). 요청을
///   기억해 두고 [signIn] 의 finally 가 **가드를 든 채** 소비하므로, D-57
///   (「모든 path 에서 finally logout」) 이 동시성 구간에서도 유지된다.
/// - (비보장) plugin 이 **이미 잠긴 상태**는 풀지 못한다. iOS 1-tap 에서
///   사용자가 NAVER 앱에서 돌아오지 않으면 plugin 의 대기 슬롯이 점유된 채
///   남고, 그 상태는 앱을 다시 켜기 전까지 지속된다 — 그동안 Naver 로그인은
///   불가능하다. plugin 에 상태를 되돌릴 API 가 없고 C-06(테스트 SIM 부재)
///   으로 재현조차 못 하므로 미해결 잔존으로 남긴다. 대기 시간에 한도를 두지도
///   않는다 — cross-provider 정책이라 본 phase 범위 밖이다 (D-19).
///
/// **네이티브 설정 (D-01 · D-04):** 새 플러그인은 runtime `initialize()` 가
/// 없다. client ID · secret · 앱 이름은 Android `AndroidManifest.xml` 의
/// `com.naver.sdk.*` meta-data 와 iOS `Info.plist` 키를 plugin registration
/// 시점에 읽는다.
///
/// **경로 라우팅 (Phase 16.5 D-01 ~ D-04):** [signIn] 이 호스트 설치 판정
/// ([NaverHostChannel]) 결과 하나로 갈린다 — 설치면 위 플러그인 1-tap
/// ([NaverAppSignIn]), 미설치 · 판정 실패면 킷 웹 흐름([NaverWebSignIn]).
/// 웹 클라이언트는 [NaverWebSignInFn] 함수 타입으로만 주입받는다 — 1-tap 경로는
/// 웹 세션 패키지에 닿지 않는다.
class NaverSdkClient {
  /// production 진입점 — 실제 Naver 플러그인 · 호스트 채널 · 웹 클라 호출.
  ///
  /// [webAuthClient] 는 provider 가 [naverWebAuthClientProvider] 에서 주입한다.
  /// 테스트는 [NaverSdkClient.forTest] 로 함수 typedef 를 주입한다.
  NaverSdkClient({required NaverWebAuthClient webAuthClient})
    : _login = _defaultLogin,
      _logout = _defaultLogout,
      _isNaverAppInstalled = const NaverHostChannel().isNaverAppInstalled,
      _webSignIn = webAuthClient.signIn;

  /// 테스트 전용 ctor — 플러그인 · 설치 판정 · 웹 흐름을 함수 typedef 로
  /// fake 한다.
  ///
  /// [isNaverAppInstalled] 기본값은 「항상 설치」 — 1-tap 경로만 보는 기존
  /// 테스트가 인자 추가 없이 그대로 통과한다. [webSignIn] 기본값은 호출되면
  /// [StateError] 를 던진다(웹 경로를 기대하지 않은 테스트가 조용히 통과하지
  /// 않게).
  ///
  /// production 코드는 [NaverSdkClient.new] 만 사용해야 한다.
  @visibleForTesting
  NaverSdkClient.forTest({
    required NaverLoginFn login,
    required NaverLogoutFn logout,
    NaverInstalledFn? isNaverAppInstalled,
    NaverWebSignInFn? webSignIn,
  }) : _login = login,
       _logout = logout,
       _isNaverAppInstalled = isNaverAppInstalled ?? _alwaysInstalled,
       _webSignIn = webSignIn ?? _webSignInUnexpected;

  final NaverLoginFn _login;
  final NaverLogoutFn _logout;

  /// NAVER 앱 설치 판정 — true 면 1-tap, false · 예외면 킷 웹 (D-02).
  final NaverInstalledFn _isNaverAppInstalled;

  /// 킷 웹 흐름 — [NaverWebAuthClient.signIn] (D-07).
  final NaverWebSignInFn _webSignIn;

  /// [signIn] 이 진행 중인지 — 클래스 doc 의 in-flight 가드 (D-18).
  bool _inFlight = false;

  /// [signIn] 진행 중에 들어온 [logout] 요청 — 가드가 풀리는 즉시 소비한다
  /// (WR-01 — 「생략」 이 아니라 「지연」 이라 D-57 이 유지된다).
  ///
  /// 진행 중에 [logout] 이 여러 번 불려도 **1회**로 접는다 — 기기 토큰 제거는
  /// 멱등이므로 횟수를 보존할 이유가 없다.
  bool _logoutPending = false;

  /// Naver 로그인 — 설치 판정으로 1-tap(SDK) 또는 킷 웹 흐름을 고른다.
  ///
  /// 흐름:
  /// 1. in-flight 가드 — 진행 중이면 plugin 을 호출하지 않고 null (D-18).
  ///    웹 경로도 같은 가드를 공유한다 (세션 중복 열기 0).
  /// 2. 경로 선택 (Phase 16.5 D-01 ~ D-04) — 호스트 설치 판정이 `false` 이거나
  ///    예외면 [NaverWebAuthClient.signIn] 의 결과([NaverWebSignIn] · null ·
  ///    예외)를 그대로 돌려준다. 진단 줄 `Naver 경로 선택: mode=… installed=…`.
  ///    아래 3~8 은 설치(1-tap) 경로 한정이다.
  /// 3. 진단 로그 — 시작/도착 2줄, `kDebugMode` 전용, errorMessage 비출력
  ///    (Phase 16.4 D-18). 대기 구간이 logcat 에 보이게 하는 것이 목적이라
  ///    도착 줄은 `status` 와 경과 ms 만 싣는다.
  /// 4. `_login()` 의 Future 를 **그대로 await** 한다 (D-16 — 타이머 없음).
  /// 5. [isNaverUserCancel] 을 **error 분기보다 먼저** 본다 — iOS 취소가
  ///    `status: error` 로 오므로 error 를 곧장 배너로 보내면 취소가 오류로
  ///    보인다 (`1c884c73` 회귀 경로).
  /// 6. status `error` → [ServiceUnavailable] (`cause` = [NaverSdkError]).
  /// 7. 빈 토큰 → null (silent).
  /// 8. 그 외 예외 → [ServiceUnavailable] 로 흡수. iOS `Info.plist` 4키가
  ///    없으면 채널이 미등록돼 `PlatformException` 이 아닌
  ///    `MissingPluginException` 이 전파되기 때문이다 (D-05). 웹 경로의
  ///    `PlatformException`(세션 FAILED 등) 도 여기서 `cause` 로 보존된다.
  ///
  /// 결과 객체에서 읽는 값은 `status` · `errorMessage` ·
  /// `accessToken?.accessToken` **셋뿐**이다 — 프로필은 참조하지 않고 결과 ·
  /// 토큰 객체를 문자열 보간에 넣지 않는다 (D-21 — 토큰 클래스의 `toString`
  /// 이 access · refresh token 전문을 출력한다).
  ///
  /// finally 는 **가드를 든 채** 지연된 [logout] 요청을 배수(`while`)하고,
  /// 다 비운 뒤에 가드를 내린다 (WR-01 / WR-09). 가드를 먼저 내리면 plugin
  /// `logOut()` 이 아직 in-flight 인 구간에서 재진입 [signIn] 이 가드를
  /// 통과해 **킷이 스스로 동시 plugin 호출을 만든다**. 그 소비는
  /// [_invokeLogout] 의 내부 try/catch 로 **절대 throw 하지 않으므로**, 본
  /// 메서드의 반환값과 전파 중인 예외를 바꾸지 않는다 (logout 은 graceful
  /// 계약).
  ///
  /// 반환:
  /// - [NaverAppSignIn] (accessToken) — 1-tap 성공.
  /// - [NaverWebSignIn] (code · state) — 킷 웹 성공 (서버가 code 를 교환).
  /// - null — 사용자 취소 / 빈 토큰 / 재진입 (silent).
  /// - throw [ServiceUnavailable] — network / SDK / 웹 세션 · 콜백 오류.
  Future<NaverSignInResult?> signIn() async {
    if (_inFlight) {
      if (kDebugMode) {
        debugPrint('Naver logIn 재진입 무시 (in-flight)');
      }
      return null;
    }
    _inFlight = true;
    // IN-03: 경과 ms 는 `kDebugMode` 블록에서만 소비된다 — release 에서는
    // Stopwatch 를 만들지도 않는다 (킷은 템플릿으로 복사되는 코드다).
    final Stopwatch? watch = kDebugMode ? (Stopwatch()..start()) : null;
    try {
      // Phase 16.5 D-01 ~ D-04 — 설치 판정 bool 하나로 경로를 고른다. 판정
      // 예외는 웹으로 접는다(D-02) — SDK 커스텀탭 경로를 피하는 것이 목적이다.
      bool installed;
      try {
        installed = await _isNaverAppInstalled();
      } on Object catch (e) {
        if (kDebugMode) {
          debugPrint('Naver 설치 판정 예외(web 으로 접음): ${e.runtimeType}');
        }
        installed = false;
      }
      if (kDebugMode) {
        debugPrint(
          'Naver 경로 선택: mode=${installed ? 'app' : 'web'} '
          'installed=$installed',
        );
      }
      if (!installed) return await _webSignIn();

      if (kDebugMode) {
        debugPrint('Naver logIn 시작');
      }
      final result = await _login();

      // D-18 도착 줄 — status 이름과 경과 ms 만. `errorMessage` 원문은 한 글자도
      // 싣지 않는다 (WR-05). 취소 · 오류 요약은 바로 아래 기존 분기가 찍는다.
      if (kDebugMode) {
        debugPrint(
          'Naver logIn 도착: status=${result.status.name} '
          'elapsedMs=${watch?.elapsedMilliseconds ?? 0}',
        );
      }

      if (isNaverUserCancel(result.status, result.errorMessage)) {
        // D-45 silent — Android loggedOut · iOS error + 고정 리터럴.
        if (kDebugMode) {
          debugPrint(
            'Naver logIn cancel: status=${result.status.name} '
            '${describeNaverErrorForLog(result.errorMessage)}',
          );
        }
        return null;
      }

      if (result.status == NaverLoginStatus.error) {
        if (kDebugMode) {
          debugPrint(
            'Naver logIn error: '
            '${describeNaverErrorForLog(result.errorMessage)}',
          );
        }
        throw ServiceUnavailable(
          cause: NaverSdkError(result.errorMessage ?? ''),
        );
      }

      // D-21: 프로필은 참조하지 않는다 — accessToken 만 꺼낸다.
      final token = result.accessToken?.accessToken ?? '';
      if (token.isEmpty) return null;
      return NaverAppSignIn(accessToken: token);
    } on ServiceUnavailable {
      rethrow;
    } on Object catch (e) {
      // MissingPluginException(iOS Info.plist 키 부재) 포함 — D-05 가드.
      if (kDebugMode) {
        debugPrint('Naver logIn 예외: ${e.runtimeType}');
      }
      throw ServiceUnavailable(cause: e);
    } finally {
      // 지연됐던 logout 소비 — D-57 (WR-01). 가드를 **든 채** 배수한다
      // (WR-09): 소비 중 재진입 [signIn] 은 계속 null 이고, 같은 구간에
      // 들어온 [logout] 은 다시 지연돼 이 루프가 그것까지 소비한다
      // (유실 0 · 킷이 만드는 동시 plugin 호출 0). [_invokeLogout] 은
      // throw 하지 않으므로 위 분기의 반환값 · 전파 중인 예외에 영향이 없다.
      while (_logoutPending) {
        _logoutPending = false;
        await _invokeLogout();
      }
      _inFlight = false;
    }
  }

  /// 플러그인 logout — D-57 1회성 토큰 정책. 기기 내 토큰만 제거한다.
  ///
  /// 호출처는 **셋**이며 모두 `AuthRepository` 다 (WR-01 — 이전 doc 은 첫
  /// 항목 하나만 논증했다):
  /// 1. `signInWithNaver` 의 finally — race-fix end 직전 (Pitfall 2).
  /// 2. `_logoutCustomTokenSdk(AccountProvider.naver)` — 재인증 finally.
  /// 3. `signOut` — 전 provider 세션 해제.
  ///
  /// 서버 연동 해제(revoke) 계열 API 는 쓰지 않는다 (D-15 — 매 로그인 동의
  /// 재요구로 1-tap UX 가 깨진다).
  ///
  /// **[signIn] 진행 중이면 「생략」 이 아니라 「지연」 한다 (D-18 / WR-01).**
  /// 진행 중인 로그인의 native 상태를 건드리지 않되, 요청을 [_logoutPending]
  /// 에 기억해 두고 [signIn] 의 finally 가 **가드를 든 채** 배수한다. 그래서
  /// D-57(「매 로그인 finally 로 기기 토큰 제거」)이 **세 호출처 모두에서**
  /// 유지된다:
  /// - (1) 그 로그인 자신의 finally 는 [signIn] 완료 **뒤에** 실행되므로
  ///   애초에 가드가 풀려 있다 — 지연 없이 즉시 plugin 을 호출한다.
  /// - (2)(3) 다른 Naver 로그인이 진행 중인 동시성 구간에서는 지연되지만,
  ///   그 로그인이 끝나는 즉시 plugin logout 이 **반드시 1회** 실행된다.
  ///   진행 중이던 로그인이 방금 받은 토큰까지 함께 지워지는데, 재인증
  ///   finally · 전면 로그아웃의 의도가 바로 세션 해제이므로 부합한다.
  ///   이전 구현처럼 버려지면 이 두 경로에서 기기 토큰이 24h TTL 동안
  ///   소리 없이 잔존했다.
  ///
  /// 실패 시 graceful ([kDebugMode] [debugPrint]) — outer 흐름 차단 안 함.
  Future<void> logout() async {
    if (_inFlight) {
      // 생략이 아니라 지연 — D-57 은 유지된다 (WR-01).
      _logoutPending = true;
      if (kDebugMode) {
        debugPrint('NaverSdkClient.logout 지연 (in-flight)');
      }
      return;
    }
    await _invokeLogout();
  }

  /// plugin `logOut()` 실제 호출 — [logout] 과 [signIn] 의 지연 소비가 쓴다.
  ///
  /// **어떤 경우에도 예외를 던지지 않는 것**이 계약이다 (D-57 graceful).
  /// [signIn] 의 finally 에서도 불리므로, 던지면 [signIn] 의 반환값이나
  /// 전파 중인 예외를 덮어쓰게 된다.
  ///
  /// **결과 `status` 를 반드시 판정한다 (WR-11).** 플러그인은 logout 실패를
  /// 예외가 아니라 **결과 객체**([NaverLoginStatus.error] + `errorMessage`)
  /// 로 돌려주므로, `try/catch` 만으로는 실패를 하나도 잡지 못한다. iOS 는
  /// `pendingResult != nil` 이면 `logOut` 을 포함한 모든 메서드를
  /// `Another request is in progress. Please wait` 로 거부하므로
  /// (`FlutterNaverLoginPlugin.swift:122-126`) 실제 도달 가능한 경로다.
  /// `16.2-HUMAN-UAT.md` 가 `NaverSdkClient.logout 완료` 한 줄을 D-57
  /// (기기 토큰 삭제) 성공 판정 근거로 쓰기 때문에, status 를 보지 않으면
  /// 거부된 logout 이 **PASS 로 위양성 집계**된다.
  ///
  /// 실패 로그는 원문을 쓰지 않고 [describeNaverErrorForLog] 를 거친다
  /// (D-14 / WR-05 — `errorMessage` 는 자유 문자열이라 PII 를 실을 수 있다).
  Future<void> _invokeLogout() async {
    try {
      final result = await _logout();
      if (kDebugMode) {
        if (result.status == NaverLoginStatus.loggedOut) {
          debugPrint('NaverSdkClient.logout 완료');
        } else {
          debugPrint(
            'NaverSdkClient.logout 실패 (무시): '
            'status=${result.status.name} '
            '${describeNaverErrorForLog(result.errorMessage)}',
          );
        }
      }
    } on Object catch (e) {
      if (kDebugMode) {
        debugPrint('NaverSdkClient.logout 실패 (무시): ${e.runtimeType}');
      }
    }
  }
}

/// Default `FlutterNaverLogin.logIn` 호출 — production 진입점.
Future<NaverLoginResult> _defaultLogin() => FlutterNaverLogin.logIn();

/// Default `FlutterNaverLogin.logOut` 호출 — production 진입점 (D-57).
Future<NaverLoginResult> _defaultLogout() => FlutterNaverLogin.logOut();

/// [NaverSdkClient.forTest] 의 설치 판정 기본값 — 항상 설치(1-tap 경로).
Future<bool> _alwaysInstalled() async => true;

/// [NaverSdkClient.forTest] 의 웹 흐름 기본값 — 주입 없이 웹 경로에 닿으면
/// 테스트가 시끄럽게 실패하도록 던진다.
Future<NaverWebSignIn?> _webSignInUnexpected() async =>
    throw StateError('webSignIn fake 미주입');

/// [NaverSdkClient] Provider — keepAlive (Phase 12 [kakaoSdkClientProvider]
/// 패턴). 웹 클라이언트는 [naverWebAuthClientProvider] 에서 주입한다.
@Riverpod(keepAlive: true)
NaverSdkClient naverSdkClient(Ref ref) {
  return NaverSdkClient(webAuthClient: ref.watch(naverWebAuthClientProvider));
}
