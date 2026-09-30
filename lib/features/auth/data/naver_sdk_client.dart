// Phase 16.2 — see ROADMAP.md
//
// Naver 로그인 진입점 — 플러그인 Future 직결 + typedef 주입 (Phase 12
// KakaoSdkClient 미러). D-43 ~ D-45 + D-57 정책 일관.
// Phase 16.4 D-18 로그 2줄 — signIn() 시작 · 도착 (kDebugMode 전용).
// Phase 16.5 D-01 ~ D-04 — signIn() 이 NAVER 앱 설치 판정 bool 하나로 1-tap
// (SDK) 과 킷 웹 흐름을 라우팅한다. 웹 클라이언트는 함수 typedef 로만 안다.
// Phase 16.11 — see ROADMAP.md (EX-03 · EX-04 — iOS 1-tap 취소 표면 · stale 슬롯 재시도)
// Phase 16.11 D-01 ~ D-07 — iOS 1-tap 포기 판정 · 고아 대기
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show AppLifecycleListener;
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

/// iOS 1-tap 에서 background 복귀(`resumed`) 뒤 포기 판정을 보류하는 시간.
///
/// LINE SDK 5.17.0 `AppSwitchingObserver` 의 0.3초 verbatim
/// (`LineSDK/Login/LoginProcess.swift:66-98` · `:226-241`). 복귀 직후 콜백 URL
/// 도착과 앱 활성화의 순서를 보정하려는 **판정 보류**일 뿐 로그인 대기 한도가
/// 아니다 — 16.2 D-16(타이머 없음)의 명시적 예외다 (16.11 D-01 · D-02). 보류가
/// 끝난 뒤 URL 이 도착했으면 한도 없이 계속 기다린다 (C-01). 값을 올리는 것은
/// U1 실측(`openURL` ↔ `resumed` 간격) 근거가 있을 때만 한다.
const Duration kNaverResumeSettleDelay = Duration(milliseconds: 300);

/// 앱 lifecycle 구독 함수 시그니처 — 해제 함수를 돌려준다 (16.11 D-03).
///
/// [NaverSdkClient] 는 iOS 1-tap `logIn` 1회분 동안만 구독한다(시작 시 생성 ·
/// 결과 또는 포기 시 해제). [NaverSdkClient.forTest] 가 fake 를 주입한다.
typedef NaverLifecycleSubscribeFn =
    void Function() Function({
      required VoidCallback onPause,
      required VoidCallback onResume,
    });

/// production 구독 — [AppLifecycleListener] 의 `onPause` · `onResume` 으로
/// background 진입 · 복귀를 받고, 그 `dispose` 를 해제 함수로 돌려준다.
///
/// `onPause` 는 `hidden → paused`, `onResume` 은 `inactive → resumed` 전환에서만
/// 불린다 — iOS 시스템 알림처럼 `inactive` 만 거치는 전환은 판정에 닿지 않는다
/// (16.11 RESEARCH OQ2 · OQ6).
@visibleForTesting
void Function() subscribeNaverAppLifecycle({
  required VoidCallback onPause,
  required VoidCallback onResume,
}) {
  final listener = AppLifecycleListener(
    onPause: onPause,
    onResume: onResume,
    // UAT 임시 — plan 07 이 제거 (U2 — Dart 가 받은 lifecycle 상태 · 시각)
    onStateChange: kDebugMode
        ? (state) => debugPrint(
            'Naver lifecycle: state=${state.name} '
            't=${DateTime.now().millisecondsSinceEpoch}',
          )
        : null,
  );
  return listener.dispose;
}

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

/// iOS 플러그인이 대기 슬롯 점유 중 새 호출을 거부할 때 붙이는 **고정 리터럴**
/// (43자).
///
/// 출처: `naver_login_flutter` 4.0.0 iOS 플러그인
/// `FlutterNaverLoginPlugin.swift:124` — `pendingResult != nil` 이면 모든
/// 메서드를 이 문구로 거부한다. 거부 응답은 `sendError` 에서 대기 중이던 고아
/// 슬롯(`pendingResult`)을 `nil` 로 비운다 (`:370-380` · RESEARCH DG-2 S-2).
/// 그래서 16.11 EX-03 부터 iOS 에서는 이 거부를 stale 슬롯으로 보고 **1회**
/// 재시도한다.
const String kNaverIosRequestInProgressMessage =
    'Another request is in progress. Please wait';

/// iOS NAVER 앱(1-tap) 동의 화면 [Cancel] 이 오는 **고정 문구** (73자 · A1).
///
/// NAVER iOS SDK 5.2.1 앱 경로가 복귀 URL 의 code `10`(`AppAuthCode.undefined`)
/// + `error_detail=access_denied` 에 붙이는 문구다. 출처:
/// `naveridlogin-sdk-ios-swift` 5.2.1
/// `Projects/NidThirdPartyLogin/Sources/NidLogin/Domain/UseCases/Login/`
/// `PerformAppLogin.swift:27-61`(code 10 → `undefined` · 설명 nil 이라
/// `error_detail` 값을 씀) · `:70`(`error_detail` 키) · `:137`(callback) 과
/// `Sources/NidCore/NidError.swift:58`(`NID given Error. Error Code: … \n
/// Error Description: …` 형식). 260929-snf A1 실측 `length=73`.
///
/// **완전 일치만 취소다 (16.11 C-03)** — 같은 접두어의 다른 NID 오류(설정 ·
/// 서버 오류)는 계속 배너 경로다.
const String kNaverIosAppAccessDeniedMessage =
    'NID given Error. Error Code: undefined. \n'
    'Error Description: access_denied';

/// iOS NAVER 앱(1-tap) 「NAVER 열기?」 시스템 알림 [Cancel] 이 오는 **고정
/// 문구** (86자 · SYSC).
///
/// SDK `NidError.clientError(.naverAppNotInstalled)` 의 문구다. 출처:
/// `naveridlogin-sdk-ios-swift` 5.2.1 `Sources/NidCore/NidError.swift:33`.
/// 1-tap 에서 iOS 「"<앱>" wants to open "NAVER"」 알림의 [Cancel] 이 이 오류로
/// 온다 (260929-snf SYSC 실측 `length=86`).
///
/// **SDK 발생 조건은 알림 [Cancel] 보다 넓다 (IN-01).** SDK 는
/// `UIApplication.shared.open` 완료 `false` 전부를 이 오류로 만든다 (출처:
/// `naveridlogin-sdk-ios-swift` 5.2.1
/// `Projects/NidThirdPartyLogin/Sources/NidLogin/Data/Repository/`
/// `DefaultAppAuthorizationCodeRepository.swift:49-64` — `:49` 의 `open` 완료
/// 핸들러가 `:64` 에서 이 오류로 callback).
/// 그래서 앱은 설치돼 있으나 실행이 막힌 단말(스크린 타임 · MDM 제한 등)도
/// 같은 문구로 오며, 킷은 알림 [Cancel] 과 구분하지 못해 silent 취소로 접는다
/// — iOS 1-tap 「무반응」 제보 시 확인 항목이다. 킷 설치 판정(`canOpenURL`)이
/// `false` 인 단말은 웹 경로로 먼저 가므로 이 매핑에 닿는 것은 설치 판정
/// `true` 뒤의 `open` 실패뿐이다.
///
/// **iOS 1-tap 에서 완전 일치일 때만 취소다 (16.11 EX-04 · C-03 · C-04).**
const String kNaverIosAppNotInstalledMessage =
    'Naver app is not installed. \nPlease install Naver App to authenticate '
    'using Naver App.';

/// 완전 일치 닫힌 집합 — 원문 → 로그용 이름 (RESEARCH §9 verbatim).
const Map<String, String> _kNaverExactMessages = <String, String>{
  kNaverIosCancelMessage: 'ios_plugin_cancelled',
  kNaverIosAppAccessDeniedMessage: 'ios_sdk_nid_access_denied',
  kNaverIosRequestInProgressMessage: 'ios_plugin_request_in_progress',
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
  kNaverIosAppNotInstalledMessage: 'ios_sdk_naver_app_not_installed',
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
/// **완전 일치만 본다** (D-12 · 16.11 C-03) — `contains` · 접두어 · 대소문자
/// 무시 비교로 넓히면 `-999 cancelled` 같은 네트워크 오류까지 silent 로
/// 흡수돼 사용자가 실패를 알 수 없게 된다.
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
/// **iOS NAVER 앱 1-tap 의 취소 표면 (16.11 EX-04 · C-04):** 1-tap 취소는
/// 플러그인 리터럴이 아니라 SDK 오류 문구로 온다 (260929-snf 실측). 두 표면을
/// [isIosOneTap] 이 `true` 일 때만 **완전 일치**로 취소로 본다:
/// - A1 — NAVER 동의 화면 [Cancel]: [kNaverIosAppAccessDeniedMessage] (73자).
/// - SYSC — iOS 「NAVER 열기?」 알림 [Cancel]:
///   [kNaverIosAppNotInstalledMessage] (86자).
///
/// Android 1-tap 은 호출부가 `false` 를 넘기므로 판정이 바뀌지 않는다. 킷 웹
/// 경로는 설치 판정 `false` 분기가 먼저 반환하므로 이 함수에 닿지 않는다.
/// `docs/manual.md` 의 Naver Pitfall 절을 참조할 것.
@visibleForTesting
bool isNaverUserCancel(
  NaverLoginStatus status,
  String? errorMessage, {
  required bool isIosOneTap,
}) {
  if (status == NaverLoginStatus.loggedOut) return true;
  if (status != NaverLoginStatus.error) return false;
  // 플랫폼 공통 — iOS 플러그인 취소 리터럴 (기존).
  if (errorMessage == kNaverIosCancelMessage) return true;
  // 아래는 iOS NAVER 앱 1-tap 한정 (16.11 C-04).
  if (!isIosOneTap) return false;
  return errorMessage == kNaverIosAppAccessDeniedMessage ||
      errorMessage == kNaverIosAppNotInstalledMessage;
}

/// iOS 플러그인의 stale 슬롯 거부인지 판정한다 (16.11 EX-03 · C-04).
///
/// iOS 이고 `status` 가 [NaverLoginStatus.error] 이며 `errorMessage` 가
/// [kNaverIosRequestInProgressMessage] 와 **완전 일치**할 때만 `true` 다.
/// Android 는 같은 문자열이어도 `false` — 재시도 동작이 바뀌지 않는다.
bool _isIosStaleSlotRejection(NaverLoginResult result) =>
    defaultTargetPlatform == TargetPlatform.iOS &&
    result.status == NaverLoginStatus.error &&
    result.errorMessage == kNaverIosRequestInProgressMessage;

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
/// **타이머 없음 (D-16):** 플러그인 Future 를 그대로 await 한다. 로그인 결과를
/// 감싸는 `Completer` · `Future.timeout` 이 없으므로 「늦게 끝난 성공을
/// 버리는」 주체가 구조적으로 존재하지 않는다.
/// 예외(16.11 D-01 · D-02): iOS 1-tap 에서 background 복귀 직후
/// [kNaverResumeSettleDelay] 동안 판정을 보류한다 — 로그인 결과 대기 한도가
/// 아니라 URL ↔ 활성화 순서 보정이며, URL 이 도착했으면 한도 없이 기다린다
/// (C-01). 포기 신호용 `Completer<void>` 1건만 쓰고 로그인 결과를 감싸는
/// Completer · timeout 은 여전히 0 이다.
///
/// **in-flight 가드 (D-18) — 보장과 비보장:**
/// - (보장) 킷이 만들어내는 동시 plugin 호출이 0 이다. [signIn] 이 진행 중인
///   동안의 재진입은 plugin 을 호출하지 않고 null 을 돌려주며, 같은 동안의
///   [logout] 도 plugin 을 즉시 호출하지 않는다. Android 로그인 콜백이 static
///   단일 슬롯이라 덮어쓰기 위험이 있고, iOS 는 재진입 시 스스로
///   「Another request is in progress」 를 자초하기 때문이다. **지연된
///   [logout] 을 소비하는 동안에도 가드는 내려가지 않는다 (WR-09)** — 그래서
///   이 보장이 plugin `logOut()` 라운드트립 구간까지 끊기지 않고 이어진다.
///   **가드 밖에서 시작된 [logout] 의 라운드트립 중 들어온 [signIn] 도 그
///   라운드트립이 끝날 때까지 기다린다 (U5 · 16.11 · RESEARCH DG-3)** — 기다리지
///   않으면 plugin 이 `logIn` 을 거부하며 `logOut` 의 슬롯을 비워 그 Future 가
///   영영 끝나지 않는다.
///   **예외 (EX-03 · 16.11):** iOS 에서 이전 요청이 남긴 stale 슬롯은 다음
///   plugin 호출이 **의도적으로** 거부를 1회 받아 비우고 1회 재시도한다. 킷이
///   만드는 동시 호출이 아니라 plugin 에 남은 고아 슬롯의 정리다 (Android 불변).
/// - (보장) 가드에 걸린 [logout] 은 **버려지지 않는다** (WR-01). 요청을
///   기억해 두고 [signIn] 의 finally 가 **가드를 든 채** 소비하므로, D-57
///   (「모든 path 에서 finally logout」) 이 동시성 구간에서도 유지된다.
/// - (해결 — Phase 16.11) iOS 1-tap 에서 사용자가 결과 없이 돌아오면(홈으로
///   나감 · NAVER 강제 종료) 포기 판정이 요청을 끝낸다: background 복귀
///   (`paused` 뒤 `resumed`) + [kNaverResumeSettleDelay] + 네이티브 콜백 URL
///   도착 기록 `false` → silent `null` · 가드 해제(EX-01 · D-07). 포기한 요청은
///   plugin 슬롯을 계속 점유하는 고아로 남고, 그동안 [logout] 은 plugin 을
///   부르지 않고 지연된다(D-06). 고아가 늦게 끝나면 결과를 버리고 logout 을
///   1회 실행한다(C-02). 고아가 끝나지 않으면 다음 탭의 plugin 호출이 stale
///   거부를 1회 받아 슬롯을 비우고 재시도하며(EX-03), 지연된 logout 은 그
///   로그인의 finally 가 소비한다.
///   잔여 한계(RESEARCH DG-2 (b)): 새 요청이 끝난 **뒤** 옛 NAVER 화면에서
///   늦은 동의가 오면 토큰이 다음 로그인까지 keychain 에 남을 수 있다 — SDK 가
///   process 를 정리하지 않고 앱 경로에 state 검사가 없어 킷이 알 수 없다.
///   발생 조건은 「새 1-tap 을 끝낸 뒤 앱 전환기로 옛 동의 화면에 돌아가
///   [동의]」 로 극히 좁고, 다음 로그인의 finally 가 지운다.
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
      _webSignIn = webAuthClient.signIn,
      _subscribeLifecycle = subscribeNaverAppLifecycle,
      _hasCallbackArrived = const NaverHostChannel().hasNaverCallbackArrived,
      _resetCallbackRecord = const NaverHostChannel().resetNaverCallbackRecord;

  /// 테스트 전용 ctor — 플러그인 · 설치 판정 · 웹 흐름을 함수 typedef 로
  /// fake 한다.
  ///
  /// [isNaverAppInstalled] 기본값은 「항상 설치」 — 1-tap 경로만 보는 기존
  /// 테스트가 인자 추가 없이 그대로 통과한다. [webSignIn] 기본값은 호출되면
  /// [StateError] 를 던진다(웹 경로를 기대하지 않은 테스트가 조용히 통과하지
  /// 않게).
  ///
  /// 16.11 포기 판정 재료 3개도 선택 인자다 — [lifecycleSubscribe] 기본값은
  /// 아무것도 붙들지 않는 구독, [callbackArrived] 기본값은 `false`,
  /// [callbackReset] 기본값은 no-op 이다. 기존 테스트는 인자 추가 없이 통과한다.
  ///
  /// production 코드는 [NaverSdkClient.new] 만 사용해야 한다.
  @visibleForTesting
  NaverSdkClient.forTest({
    required NaverLoginFn login,
    required NaverLogoutFn logout,
    NaverInstalledFn? isNaverAppInstalled,
    NaverWebSignInFn? webSignIn,
    NaverLifecycleSubscribeFn? lifecycleSubscribe,
    NaverCallbackArrivedFn? callbackArrived,
    NaverCallbackResetFn? callbackReset,
  }) : _login = login,
       _logout = logout,
       _isNaverAppInstalled = isNaverAppInstalled ?? _alwaysInstalled,
       _webSignIn = webSignIn ?? _webSignInUnexpected,
       _subscribeLifecycle = lifecycleSubscribe ?? _subscribeLifecycleNoop,
       _hasCallbackArrived = callbackArrived ?? _callbackNeverArrived,
       _resetCallbackRecord = callbackReset ?? _resetCallbackRecordNoop;

  final NaverLoginFn _login;
  final NaverLogoutFn _logout;

  /// NAVER 앱 설치 판정 — true 면 1-tap, false · 예외면 킷 웹 (D-02).
  final NaverInstalledFn _isNaverAppInstalled;

  /// 킷 웹 흐름 — [NaverWebAuthClient.signIn] (D-07).
  final NaverWebSignInFn _webSignIn;

  /// iOS 1-tap `logIn` 1회분 lifecycle 구독 (16.11 D-03).
  final NaverLifecycleSubscribeFn _subscribeLifecycle;

  /// 현재 요청 동안 Naver 콜백 URL 이 도착했는지 — 네이티브 기록 조회
  /// (16.11 D-05). 실패는 `true`(계속 대기) 로 접는다.
  final NaverCallbackArrivedFn _hasCallbackArrived;

  /// 네이티브 콜백 도착 기록 초기화 — iOS 1-tap 요청 시작 때 부른다.
  final NaverCallbackResetFn _resetCallbackRecord;

  /// [signIn] 이 진행 중인지 — 클래스 doc 의 in-flight 가드 (D-18).
  bool _inFlight = false;

  /// [signIn] 진행 중에 들어온 [logout] 요청 — 가드가 풀리는 즉시 소비한다
  /// (WR-01 — 「생략」 이 아니라 「지연」 이라 D-57 이 유지된다).
  ///
  /// 진행 중에 [logout] 이 여러 번 불려도 **1회**로 접는다 — 기기 토큰 제거는
  /// 멱등이므로 횟수를 보존할 이유가 없다.
  bool _logoutPending = false;

  /// plugin `logOut` 라운드트립 진행 중 — [signIn] 이 먼저 기다린다 (U5).
  ///
  /// 기다리지 않으면 plugin 이 `logIn` 을 거부하며 `logOut` 의 슬롯을 비워 그
  /// Future 가 영영 끝나지 않는다 (RESEARCH DG-3). [_invokeLogout] 이 채우고,
  /// 끝나면 **자기 Future 일 때만** `null` 로 되돌린다.
  Future<void>? _logoutInFlight;

  /// 포기한 iOS 1-tap 요청(고아)의 plugin `logIn` Future — 없으면 `null`
  /// (16.11 D-06 · D-07).
  ///
  /// 포기해도 plugin 대기 슬롯은 여전히 이 요청이 점유한다. in-flight 가드와는
  /// 별개 상태다 — 가드는 포기 시점에 풀린다. 이 동안 plugin 을 부르면 거부
  /// 응답이 슬롯을 비워 늦은 SDK 성공 토큰이 keychain 에 남는다(RESEARCH DG-2
  /// S-2 · S-4). 그래서 고아가 있는 동안 [logout] 은 전부 지연된다.
  Future<NaverLoginResult>? _orphanLogin;

  /// 고아 요청이 plugin 슬롯을 점유 중인지.
  bool get _orphanPending => _orphanLogin != null;

  /// Naver 로그인 — 설치 판정으로 1-tap(SDK) 또는 킷 웹 흐름을 고른다.
  ///
  /// 흐름:
  /// 1. in-flight 가드 — 진행 중이면 plugin 을 호출하지 않고 null (D-18).
  ///    웹 경로도 같은 가드를 공유한다 (세션 중복 열기 0). 가드를 세운 직후
  ///    진행 중인 plugin `logOut` 라운드트립([_logoutInFlight])이 있으면 먼저
  ///    기다린다 (U5 · 16.11).
  /// 2. 경로 선택 (Phase 16.5 D-01 ~ D-04) — 호스트 설치 판정이 `false` 이거나
  ///    예외면 [NaverWebAuthClient.signIn] 의 결과([NaverWebSignIn] · null ·
  ///    예외)를 그대로 돌려준다. 진단 줄 `Naver 경로 선택: mode=… installed=…`.
  ///    아래 3~8 은 설치(1-tap) 경로 한정이다.
  /// 3. 진단 로그 — 시작/도착 2줄, `kDebugMode` 전용, errorMessage 비출력
  ///    (Phase 16.4 D-18). 대기 구간이 logcat 에 보이게 하는 것이 목적이라
  ///    도착 줄은 `status` 와 경과 ms 만 싣는다.
  /// 4. `_login()` 의 Future 를 **그대로 await** 한다 (D-16 — 타이머 없음).
  ///    iOS 에서 결과가 stale 슬롯 거부([kNaverIosRequestInProgressMessage])면
  ///    진단 줄 `Naver logIn stale 슬롯 재시도: method=logIn` 뒤 **1회만**
  ///    다시 부른다 (16.11 EX-03 — [_callLoginWithStaleRetry]). 재시도도
  ///    거부면 아래 6 의 오류 경로다.
  ///    **iOS 1-tap 한정 포기 판정 (16.11 EX-01 · EX-02 · D-03):** 시작 전에
  ///    네이티브 콜백 기록을 초기화하고, `logIn` 을 부른 직후 lifecycle 을
  ///    구독한다. `paused` 뒤 `resumed` 로 돌아오면 [kNaverResumeSettleDelay]
  ///    뒤 기록을 조회해 URL 이 없으면 포기(진단 줄
  ///    `Naver logIn 포기: reason=no_callback_after_resume`) — 곧바로 null 을
  ///    돌려주고 그 요청은 고아가 된다([_awaitLoginOrAbandon]). URL 이
  ///    도착했으면 한도 없이 계속 기다린다(C-01). Android · 웹은 구독 · 조회 ·
  ///    초기화 0.
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
  /// 계약). 고아 대기 중에는 배수하지 않는다(16.11 D-06) — 포기한 요청 자신의
  /// finally 도 마찬가지이며, 지연분은 고아 완료 또는 다음 로그인 finally 가
  /// 소비한다.
  ///
  /// 반환:
  /// - [NaverAppSignIn] (accessToken) — 1-tap 성공.
  /// - [NaverWebSignIn] (code · state) — 킷 웹 성공 (서버가 code 를 교환).
  /// - null — 사용자 취소 / 빈 토큰 / 재진입 / iOS 1-tap 포기 (silent).
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
      // U5 (16.11 · RESEARCH DG-3) — 가드 밖에서 시작된 plugin `logOut` 이
      // 아직 라운드트립 중이면 끝날 때까지 기다린다. 웹 경로도 같은 순서다
      // (부작용 0). [_invokeLogout] 은 throw 하지 않는다.
      final logoutRoundTrip = _logoutInFlight;
      if (logoutRoundTrip != null) await logoutRoundTrip;

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

      // 이 지점은 설치 판정 true 뒤라 1-tap 전용 — 포기 판정(16.11 D-03)과
      // iOS 1-tap 취소 표면(EX-04)은 여기서만 켠다 (웹 경로는 위에서 반환했다).
      final isIosOneTap = defaultTargetPlatform == TargetPlatform.iOS;
      if (isIosOneTap) await _resetCallbackRecordSafely();

      if (kDebugMode) {
        debugPrint('Naver logIn 시작');
      }
      final result = isIosOneTap
          ? await _awaitLoginOrAbandon()
          : await _callLoginWithStaleRetry();
      // 포기 — silent 취소. 기존 `null` 계약이 로딩 막 · race-fix 를 푼다.
      if (result == null) return null;

      // D-18 도착 줄 — status 이름과 경과 ms 만. `errorMessage` 원문은 한 글자도
      // 싣지 않는다 (WR-05). 취소 · 오류 요약은 바로 아래 기존 분기가 찍는다.
      if (kDebugMode) {
        debugPrint(
          'Naver logIn 도착: status=${result.status.name} '
          'elapsedMs=${watch?.elapsedMilliseconds ?? 0}',
        );
      }

      if (isNaverUserCancel(
        result.status,
        result.errorMessage,
        isIosOneTap: isIosOneTap,
      )) {
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
      // 고아 대기 중에는 배수하지 않는다 (16.11 D-06) — plugin 을 부르면 거부가
      // 고아 슬롯을 비워 늦은 성공 토큰이 keychain 에 남는다.
      if (!_orphanPending) {
        while (_logoutPending) {
          _logoutPending = false;
          await _invokeLogout();
        }
      }
      _inFlight = false;
    }
  }

  /// 콜백 기록 초기화 — 주입 함수 예외는 삼키고 진단 줄만 남긴다.
  Future<void> _resetCallbackRecordSafely() async {
    try {
      await _resetCallbackRecord();
    } on Object catch (e) {
      if (kDebugMode) {
        debugPrint('Naver 콜백 기록 초기화 예외(무시): ${e.runtimeType}');
      }
    }
  }

  /// 콜백 기록 조회 — 주입 함수 예외는 `true`(계속 대기) 로 접는다
  /// (RESEARCH Pitfall 5 — 판정 실패가 성공 폐기로 둔갑하지 않게).
  Future<bool> _queryCallbackArrived() async {
    try {
      return await _hasCallbackArrived();
    } on Object catch (e) {
      if (kDebugMode) {
        debugPrint('Naver 콜백 기록 조회 예외(계속 대기로 접음): ${e.runtimeType}');
      }
      return true;
    }
  }

  /// iOS 1-tap 결과를 기다리되, 결과 없는 복귀면 포기한다 (16.11 EX-01 · EX-02).
  ///
  /// plugin `logIn` 을 시작한 **직후** lifecycle 을 구독한다. `paused` 를 본
  /// 뒤의 `resumed` 에서만 [kNaverResumeSettleDelay] 뒤 판정을 예약한다 —
  /// `inactive` 만 거친 복귀(시스템 알림)는 판정하지 않는다. 판정은 네이티브
  /// 기록을 조회해 콜백 URL 이 도착했으면 한도 없이 계속 기다리고(C-01), 아니면
  /// 포기 신호를 보낸다. 판정 클로저는 **자기 요청의** 플래그 · 포기 신호만 본다
  /// — 결과가 이미 왔거나 포기했으면 아무것도 하지 않는다.
  /// 판정 창 안에 다시 `paused` 가 오면 예약된 판정은 판정하지 않는다 — 다음
  /// `resumed` 가 새 판정을 예약한다 (WR-01 · 보류 0.3초는 마지막 복귀 기준).
  ///
  /// 반환: 로그인 결과, 또는 포기면 `null`(그 로그인 Future 는 고아가 된다 —
  /// [_abandonToOrphan]). 구독은 결과 · 포기 · 예외 어느 쪽이든 해제한다.
  Future<NaverLoginResult?> _awaitLoginOrAbandon() async {
    final login = _callLoginWithStaleRetry();
    final abandon = Completer<void>();
    var settled = false;
    var sawPaused = false;
    // `paused` 마다 올리는 세대 — 예약된 판정은 예약 시점 세대를 들고 가서,
    // 그 뒤 다시 background 로 갔으면(세대 불일치) 판정하지 않는다 (WR-01).
    // `sawPaused` 만 보면 복귀 · 재이탈 · 재복귀가 0.3초 안에 모두 일어날 때
    // 첫 예약이 마지막 복귀로부터 0.3초 전에 판정해 D-02 가 깨진다.
    var pauseGeneration = 0;

    bool isJudgementStale(int generation) =>
        settled || abandon.isCompleted || generation != pauseGeneration;

    Future<void> judgeAfterSettle(int generation) async {
      if (isJudgementStale(generation)) return;
      final arrived = await _queryCallbackArrived();
      if (isJudgementStale(generation)) return;
      if (arrived) {
        // U1 실측 때 성공 경로에서 판정이 어느 쪽으로 갔는지 보이게 하는 줄.
        if (kDebugMode) {
          debugPrint('Naver logIn 복귀 판정: callback=arrived (계속 대기)');
        }
        return;
      }
      abandon.complete();
    }

    void Function()? unsubscribe;
    try {
      try {
        unsubscribe = _subscribeLifecycle(
          onPause: () {
            sawPaused = true;
            pauseGeneration++;
          },
          onResume: () {
            if (!sawPaused) return;
            sawPaused = false;
            final generation = pauseGeneration;
            unawaited(
              Future<void>.delayed(
                kNaverResumeSettleDelay,
                () => judgeAfterSettle(generation),
              ),
            );
          },
        );
      } on Object {
        // 구독 실패 (IN-03) — plugin 요청은 이미 시작돼 슬롯을 점유한다. 고아로
        // 추적해 logout 을 지연시키고(D-06) 늦은 결과 · 예외에 핸들러를 붙인
        // 뒤(미처리 비동기 예외 0) 호출부의 ServiceUnavailable 경로로 보낸다.
        _abandonToOrphan(login, reason: 'lifecycle_subscribe_failed');
        rethrow;
      }
      final outcome = await Future.any<NaverLoginResult?>(
        <Future<NaverLoginResult?>>[
          login,
          abandon.future.then<NaverLoginResult?>((_) => null),
        ],
      );
      if (outcome != null) return outcome;
      _abandonToOrphan(login, reason: 'no_callback_after_resume');
      return null;
    } finally {
      settled = true;
      unsubscribe?.call();
    }
  }

  /// 포기한 요청을 고아로 등록한다 (16.11 D-06 · C-02).
  ///
  /// 고아가 끝나면(성공 · 오류 결과 · 예외) 결과를 버리고 [logout] 을 1회
  /// 실행한다. 예외 갈래에도 핸들러를 붙여 미처리 비동기 예외를 0 으로 둔다.
  /// [reason] 은 진단 줄 꼬리다 — 결과 없는 복귀(`no_callback_after_resume`)
  /// 또는 lifecycle 구독 실패(`lifecycle_subscribe_failed` · IN-03).
  void _abandonToOrphan(
    Future<NaverLoginResult> login, {
    required String reason,
  }) {
    _orphanLogin = login;
    if (kDebugMode) {
      debugPrint('Naver logIn 포기: reason=$reason');
    }
    unawaited(
      login.then<void>(
        (result) => _discardOrphan(
          login,
          () =>
              'status=${result.status.name} '
              '${describeNaverErrorForLog(result.errorMessage)}',
        ),
        onError: (Object error) =>
            _discardOrphan(login, () => 'exception=${error.runtimeType}'),
      ),
    );
  }

  /// 고아 결과를 버리고 기기 토큰을 지운다 (16.11 C-02 · Phase 13 D-57).
  ///
  /// [orphan] 이 **현재** 고아일 때만 동작한다 — stale 거부로 이미 해제된 옛
  /// 고아는 무시한다. [describe] 는 진단 줄 꼬리(status 이름 + 로그 이름 또는
  /// 예외 타입)만 만든다 — 결과 · 토큰 객체는 문자열 보간에 넣지 않는다(D-21).
  /// [logout] 을 거치므로 새 로그인이 진행 중이면 다시 지연돼 그 로그인의
  /// finally 가 소비한다 — 킷이 만드는 동시 plugin 호출 0.
  Future<void> _discardOrphan(
    Future<NaverLoginResult> orphan,
    String Function() describe,
  ) async {
    if (!identical(_orphanLogin, orphan)) return;
    _orphanLogin = null;
    if (kDebugMode) {
      debugPrint('Naver logIn 고아 결과 도착: ${describe()}');
    }
    _logoutPending = false;
    await logout();
  }

  /// plugin `logIn()` 을 부르고, iOS stale 슬롯 거부면 **정확히 1회** 다시
  /// 부른다 (16.11 EX-03).
  ///
  /// 거부 응답이 이미 고아 슬롯을 비웠으므로(RESEARCH DG-2 S-2) 두 번째 호출은
  /// 정상 진행한다. 두 번째 결과는 그대로 돌려준다 — 그것도 거부면 호출부의
  /// 기존 error 분기가 [ServiceUnavailable] 로 보낸다(새 줄 없음 · 무한 재시도
  /// 0). 진단 줄은 `kDebugMode` 전용이고 `errorMessage` 원문을 싣지 않는다
  /// (D-12).
  Future<NaverLoginResult> _callLoginWithStaleRetry() async {
    final first = await _login();
    if (!_isIosStaleSlotRejection(first)) return first;
    // 거부가 고아의 슬롯을 비웠으므로 고아는 영영 완료되지 않는다 (16.11 D-06 ·
    // RESEARCH DG-2) — 대기를 해제한다. 지연된 logout 은 이 로그인의 finally 가
    // 소비한다.
    if (_orphanPending) {
      _orphanLogin = null;
      if (kDebugMode) {
        debugPrint('Naver logIn 고아 대기 해제: reason=stale_rejected');
      }
    }
    if (kDebugMode) {
      debugPrint('Naver logIn stale 슬롯 재시도: method=logIn');
    }
    return _login();
  }

  /// 플러그인 logout — D-57 1회성 토큰 정책. 기기 내 토큰만 제거한다.
  ///
  /// 현재 호출처 (16.11 RESEARCH DG-2 범위 명확화):
  /// 1. `AuthRepository.signInWithNaver` 의 finally — race-fix end 직전
  ///    (Pitfall 2).
  /// 2. `AuthRepository._logoutCustomTokenSdk(AccountProvider.naver)` — 재인증
  ///    finally.
  /// 3. `AuthRepository.signOut` — 전 provider 세션 해제.
  /// 4. `AuthRepository` 연결 arm 의 finally — 로컬 SDK 토큰 정리.
  /// 5. 탈퇴 끊기 step(`naver_disconnect_step.dart`) — callable 응답 뒤.
  ///
  /// 서버 연동 해제(revoke) 계열 API 는 쓰지 않는다 (D-15 — 매 로그인 동의
  /// 재요구로 1-tap UX 가 깨진다).
  ///
  /// **[signIn] 진행 중이면 「생략」 이 아니라 「지연」 한다 (D-18 / WR-01).**
  /// 진행 중인 로그인의 native 상태를 건드리지 않되, 요청을 [_logoutPending]
  /// 에 기억해 두고 [signIn] 의 finally 가 **가드를 든 채** 배수한다. 그래서
  /// D-57(「매 로그인 finally 로 기기 토큰 제거」)이 **모든 호출처에서**
  /// 유지된다:
  /// - (1) 그 로그인 자신의 finally 는 [signIn] 완료 **뒤에** 실행되므로
  ///   애초에 가드가 풀려 있다 — 지연 없이 즉시 plugin 을 호출한다.
  /// - (2)~(5) 다른 Naver 로그인이 진행 중인 동시성 구간에서는 지연되지만,
  ///   그 로그인이 끝나는 즉시 plugin logout 이 **반드시 1회** 실행된다.
  ///   진행 중이던 로그인이 방금 받은 토큰까지 함께 지워지는데, 재인증
  ///   finally · 전면 로그아웃의 의도가 바로 세션 해제이므로 부합한다.
  ///   이전 구현처럼 버려지면 이 경로들에서 기기 토큰이 24h TTL 동안
  ///   소리 없이 잔존했다.
  ///
  /// **고아 대기 중이면 호출처와 무관하게 지연한다 (16.11 D-06 · RESEARCH DG-2
  /// 범위 명확화).** 포기한 iOS 1-tap 요청이 plugin 슬롯을 점유하는 동안
  /// plugin 을 부르면 거부 응답이 슬롯을 비워 늦은 성공 토큰이 keychain 에
  /// 남는다. 지연분은 고아 완료 핸들러([_discardOrphan]) 또는 다음 로그인의
  /// finally 가 소비한다 (진단 줄 `NaverSdkClient.logout 지연 (orphan-wait)`).
  ///
  /// 실패 시 graceful ([kDebugMode] [debugPrint]) — outer 흐름 차단 안 함.
  Future<void> logout() async {
    if (_inFlight || _orphanPending) {
      // 생략이 아니라 지연 — D-57 은 유지된다 (WR-01 · 16.11 D-06).
      _logoutPending = true;
      if (kDebugMode) {
        debugPrint(
          _inFlight
              ? 'NaverSdkClient.logout 지연 (in-flight)'
              : 'NaverSdkClient.logout 지연 (orphan-wait)',
        );
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
  /// 16.11 부터는 그 거부를 stale 슬롯으로 보고 1회 재시도한다(iOS 한정 ·
  /// Android 는 불변 — EX-03 · C-04). 성공/실패 로그는 두 번째 결과로 판정한다.
  /// `16.2-HUMAN-UAT.md` 가 `NaverSdkClient.logout 완료` 한 줄을 D-57
  /// (기기 토큰 삭제) 성공 판정 근거로 쓰기 때문에, status 를 보지 않으면
  /// 거부된 logout 이 **PASS 로 위양성 집계**된다.
  ///
  /// 라운드트립 동안 Future 를 [_logoutInFlight] 에 걸어 [signIn] 이 기다리게
  /// 한다 (U5 · 16.11).
  ///
  /// 실패 로그는 원문을 쓰지 않고 [describeNaverErrorForLog] 를 거친다
  /// (D-14 / WR-05 — `errorMessage` 는 자유 문자열이라 PII 를 실을 수 있다).
  Future<void> _invokeLogout() async {
    final roundTrip = _runLogoutRoundTrip();
    _logoutInFlight = roundTrip;
    await roundTrip;
    // 더 늦게 시작된 라운드트립의 Future 는 지우지 않는다.
    if (identical(_logoutInFlight, roundTrip)) _logoutInFlight = null;
  }

  /// [_invokeLogout] 의 실제 본문 — plugin `logOut()` 호출 · iOS stale 슬롯
  /// 1회 재시도 · status 판정 로그. **어떤 경우에도 throw 하지 않는다.**
  Future<void> _runLogoutRoundTrip() async {
    try {
      var result = await _logout();
      if (_isIosStaleSlotRejection(result)) {
        if (kDebugMode) {
          debugPrint('Naver logIn stale 슬롯 재시도: method=logOut');
        }
        result = await _logout();
      }
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

/// [NaverSdkClient.forTest] 의 lifecycle 구독 기본값 — 아무것도 붙들지 않고
/// no-op 해제 함수를 돌려준다 (판정이 일어나지 않는다).
void Function() _subscribeLifecycleNoop({
  required VoidCallback onPause,
  required VoidCallback onResume,
}) => _unsubscribeNoop;

/// [_subscribeLifecycleNoop] 이 돌려주는 해제 함수.
void _unsubscribeNoop() {}

/// [NaverSdkClient.forTest] 의 콜백 기록 조회 기본값 — 도착 없음.
Future<bool> _callbackNeverArrived() async => false;

/// [NaverSdkClient.forTest] 의 콜백 기록 초기화 기본값 — no-op.
Future<void> _resetCallbackRecordNoop() async {}

/// [NaverSdkClient] Provider — keepAlive (Phase 12 [kakaoSdkClientProvider]
/// 패턴). 웹 클라이언트는 [naverWebAuthClientProvider] 에서 주입한다.
@Riverpod(keepAlive: true)
NaverSdkClient naverSdkClient(Ref ref) {
  return NaverSdkClient(webAuthClient: ref.watch(naverWebAuthClientProvider));
}
