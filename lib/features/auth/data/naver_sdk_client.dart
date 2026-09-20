// Phase 16.2 — see ROADMAP.md
//
// Naver 로그인 진입점 — 플러그인 Future 직결 + typedef 주입 (Phase 12
// KakaoSdkClient 미러). D-43 ~ D-45 + D-57 정책 일관.
import 'package:flutter/foundation.dart';
import 'package:naver_login_flutter/naver_login_flutter.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/error/app_exception.dart';

part 'naver_sdk_client.g.dart';

/// Naver 로그인 결과 — `access_token` 1회성 사용 (Phase 13 — see ROADMAP.md).
///
/// `AuthRepository.signInWithNaver` 가 본 [accessToken] 을 Cloud Function
/// `naverCustomToken` 호출 인자에 그대로 전달하고, finally 블록에서
/// `_naverSdkClient.logout()` 으로 디바이스 토큰을 즉시 제거한다 (D-57).
@immutable
class NaverSignInResult {
  /// [accessToken] (Naver OAuth 2.0 Access Token) 묶음.
  const NaverSignInResult({required this.accessToken});

  /// Naver Access Token (Cloud Function `/v1/nid/me` Bearer 검증 대상).
  final String accessToken;
}

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
/// 사용자 입력 등)을 실을 수 있으므로 [toString] 이 원문을 내보내지 않는다
/// (WR-05 — `cause` 가 어디선가 문자열화돼도 구조적으로 안전).
@immutable
class NaverSdkError implements Exception {
  /// 플러그인이 `NaverLoginResult.errorMessage` 로 전달한 원문을 보관한다.
  const NaverSdkError(this.message);

  /// 플러그인 원문 메시지 — 로그 · 사용자 문구로 내보내지 않는다.
  final String message;

  @override
  String toString() => 'NaverSdkError(length=${message.length})';
}

/// RED 단계 자리표시자 — 닫힌 집합 매칭은 GREEN 에서 구현한다 (D-14).
///
/// 정적 타입 언어라 테스트가 컴파일되려면 선언이 먼저 있어야 한다. 이 본문은
/// 구현이 아니라 상수 반환이며, `T-16.2-NAVER-SDK-11` ~ `14` 를 단언 수준에서
/// 실패시키기 위한 것이다.
@visibleForTesting
String describeNaverErrorForLog(String? errorMessage) =>
    'message=other length=0';

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
/// **네이티브 설정 (D-01 · D-04):** 새 플러그인은 runtime `initialize()` 가
/// 없다. client ID · secret · 앱 이름은 Android `AndroidManifest.xml` 의
/// `com.naver.sdk.*` meta-data 와 iOS `Info.plist` 키를 plugin registration
/// 시점에 읽는다.
class NaverSdkClient {
  /// production 진입점 — 실제 Naver 플러그인 호출.
  ///
  /// 테스트는 [NaverSdkClient.forTest] 로 함수 typedef 를 주입한다.
  NaverSdkClient() : _login = _defaultLogin, _logout = _defaultLogout;

  /// 테스트 전용 ctor — 플러그인 호출을 함수 typedef 로 fake 한다.
  ///
  /// production 코드는 [NaverSdkClient.new] 만 사용해야 한다.
  @visibleForTesting
  NaverSdkClient.forTest({
    required NaverLoginFn login,
    required NaverLogoutFn logout,
  }) : _login = login,
       _logout = logout;

  final NaverLoginFn _login;
  final NaverLogoutFn _logout;

  /// Naver 로그인 — 앱우선 + 웹 fallback (플러그인 · SDK 자체 제어).
  ///
  /// 흐름:
  /// 1. `_login()` 의 Future 를 **그대로 await** 한다 (D-16 — 타이머 없음).
  /// 2. status `loggedIn` + `accessToken` 비어있지 않음 → [NaverSignInResult].
  /// 3. status `loggedIn` + 빈 토큰 → null (silent).
  /// 4. status `loggedOut` → null (Android 사용자 취소, D-45 silent).
  /// 5. status `error` → [ServiceUnavailable] (`cause` = [NaverSdkError]).
  /// 6. 그 외 예외 → [ServiceUnavailable] 로 흡수. iOS `Info.plist` 4키가
  ///    없으면 채널이 미등록돼 `PlatformException` 이 아닌
  ///    `MissingPluginException` 이 전파되기 때문이다 (D-05).
  ///
  /// 결과 객체에서 읽는 값은 `status` · `errorMessage` ·
  /// `accessToken?.accessToken` **셋뿐**이다 — 프로필(`account`) 은 참조하지
  /// 않고 결과 · 토큰 객체를 문자열 보간에 넣지 않는다 (D-21).
  ///
  /// 반환:
  /// - [NaverSignInResult] (accessToken) — 성공.
  /// - null — 사용자 취소 / 빈 토큰 (silent).
  /// - throw [ServiceUnavailable] — network / SDK 오류.
  Future<NaverSignInResult?> signIn() async {
    try {
      final result = await _login();

      if (result.status == NaverLoginStatus.loggedOut) {
        // Android 사용자 취소 — D-45 silent.
        return null;
      }

      if (result.status == NaverLoginStatus.error) {
        throw ServiceUnavailable(
          cause: NaverSdkError(result.errorMessage ?? ''),
        );
      }

      // D-21: account(프로필) 는 참조하지 않는다 — accessToken 만 꺼낸다.
      final token = result.accessToken?.accessToken ?? '';
      if (token.isEmpty) return null;
      return NaverSignInResult(accessToken: token);
    } on ServiceUnavailable {
      rethrow;
    } on Object catch (e) {
      // MissingPluginException(iOS Info.plist 키 부재) 포함 — D-05 가드.
      if (kDebugMode) {
        debugPrint('Naver logIn 예외: ${e.runtimeType}');
      }
      throw ServiceUnavailable(cause: e);
    }
  }

  /// 플러그인 logout — D-57 1회성 토큰 정책. 기기 내 토큰만 제거한다.
  ///
  /// `AuthRepository.signInWithNaver` 의 finally 블록 (race-fix end 직전 —
  /// Pitfall 2) 에서 호출한다. 서버 연동 해제(revoke) 계열 API 는 쓰지 않는다
  /// (D-15 — 매 로그인 동의 재요구로 1-tap UX 가 깨진다).
  ///
  /// 실패 시 graceful ([kDebugMode] [debugPrint]) — outer 흐름 차단 안 함.
  Future<void> logout() async {
    try {
      await _logout();
      if (kDebugMode) {
        debugPrint('NaverSdkClient.logout 완료');
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

/// [NaverSdkClient] Provider — keepAlive (Phase 12 [kakaoSdkClientProvider]
/// 패턴).
@Riverpod(keepAlive: true)
NaverSdkClient naverSdkClient(Ref ref) {
  return NaverSdkClient();
}
