// Phase 13 — see ROADMAP.md
//
// Naver 로그인 진입점 (callback → Future wrapper) + Phase 12 KakaoSdkClient
// 의 typedef 주입 패턴 미러. D-43 ~ D-45 + D-57 정책 일관.
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:naver_login_sdk/naver_login_sdk.dart';
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

/// Naver SDK `login(callback:)` 함수 시그니처 typedef.
///
/// [NaverSdkClient.forTest] 의 ctor 인자 타입 — 테스트가 fake 함수를 주입한다.
typedef NaverLoginFn = void Function({required OAuthLoginCallback callback});

/// Naver SDK `getAccessToken()` 함수 시그니처 typedef.
typedef NaverGetAccessTokenFn = Future<String> Function();

/// Naver SDK `logout()` 함수 시그니처 typedef (D-57).
typedef NaverLogoutFn = Future<void> Function();

/// Default `NaverLoginSDK.login` 호출 — production 진입점.
///
/// [Future<bool>] 반환은 무시한다 — 진실원은 callback (Pitfall 9). SDK 가
/// callback 으로 전달하는 onSuccess / onFailure / onError 분기가 결과를 결정한다.
void _defaultLogin({required OAuthLoginCallback callback}) {
  // ignore: discarded_futures — Future<bool> 반환은 무시 (callback 이 진실원).
  NaverLoginSDK.login(callback: callback);
}

/// Default `NaverLoginSDK.getAccessToken` 호출 — production 진입점.
Future<String> _defaultGetAccessToken() async {
  return NaverLoginSDK.getAccessToken();
}

/// Default `NaverLoginSDK.logout` 호출 — production 진입점 (D-57).
Future<void> _defaultLogout() async {
  await NaverLoginSDK.logout();
}

/// Naver 로그인 진입점 — `NaverLoginSDK.login(callback:)` callback → Future
/// wrapper (Phase 13 — see ROADMAP.md, D-43 ~ D-45 + D-57).
///
/// **분리 이유 (Phase 12 `KakaoSdkClient` 패턴 미러):**
/// - mocktail 격리 — `NaverLoginSDK.login` 이 static 이라 ctor 함수 typedef
///   주입으로 fake 가능하게 한다.
/// - Pitfall 1 single complete — Completer 의 모든 분기에 `isCompleted`
///   가드를 두어 다중 complete `StateError` 회피.
/// - D-57 1회성 토큰 — [signIn] 성공/실패/취소 모든 분기에서
///   `AuthRepository.signInWithNaver` 의 finally 블록이 [logout] 을 호출한다.
///
/// **사용자 취소 silent (D-45):**
/// - `onError(message: 'user_cancel')` (iOS — 사용자 인증 시작 안 함) → null
/// - `onError(message: 'Canceled By User…')` (iOS — 로그인 화면 취소) → null
/// - `onFailure` (Android cancel 도착) → null silent (D-45 conservative)
///
/// **timeout 60s** — 콜백 미도착 시 silent (Decision #2 — D-45 일관).
///
/// **Naver 앱 미설치 / 업데이트 필요 (`naverapp_*`):** SDK 가 자동 webview
/// fallback 을 진행하므로 onError 분기를 무시한다 — 후속 onSuccess /
/// onFailure / onError 가 도착할 때까지 대기.
class NaverSdkClient {
  /// production 진입점 — 실제 Naver SDK 호출.
  ///
  /// 테스트는 [NaverSdkClient.forTest] 로 함수 typedef 를 주입한다.
  NaverSdkClient()
    : _login = _defaultLogin,
      _getAccessToken = _defaultGetAccessToken,
      _logout = _defaultLogout;

  /// 테스트 전용 ctor — SDK 호출을 함수 typedef 로 fake 한다.
  ///
  /// production 코드는 [NaverSdkClient.new] 만 사용해야 한다.
  @visibleForTesting
  NaverSdkClient.forTest({
    required NaverLoginFn login,
    required NaverGetAccessTokenFn getAccessToken,
    required NaverLogoutFn logout,
  }) : _login = login,
       _getAccessToken = getAccessToken,
       _logout = logout;

  final NaverLoginFn _login;
  final NaverGetAccessTokenFn _getAccessToken;
  final NaverLogoutFn _logout;

  /// Naver 로그인 — 앱우선 + 웹뷰 fallback (SDK 자체 제어).
  ///
  /// 흐름:
  /// 1. [Completer] 1회 생성 + 3 분기 isCompleted 가드 (Pitfall 1).
  /// 2. `_login(callback:)` 호출 — onSuccess / onFailure / onError 분기 합성.
  /// 3. onSuccess → `_getAccessToken()` → [NaverSignInResult] 반환.
  /// 4. onError 'user_cancel' / 'Canceled By User…' → null 반환 (D-45).
  /// 5. onError 'naverapp_*' → 분기 무시 (SDK 자동 webview fallback).
  /// 6. onError 그 외 → [ServiceUnavailable] throw.
  /// 7. onFailure → null 반환 (D-45 conservative — Android cancel 흡수).
  /// 8. timeout 60s → null 반환 (silent — D-45 일관).
  ///
  /// 반환:
  /// - [NaverSignInResult] (accessToken) — 성공.
  /// - null — 사용자 취소 / 빈 토큰 / 콜백 timeout (silent).
  /// - throw [ServiceUnavailable] — network / SDK 오류.
  Future<NaverSignInResult?> signIn() async {
    final completer = Completer<NaverSignInResult?>();

    void completeSilent() {
      if (!completer.isCompleted) completer.complete(null);
    }

    void completeError(Object err) {
      if (!completer.isCompleted) completer.completeError(err);
    }

    void completeSuccess(NaverSignInResult result) {
      if (!completer.isCompleted) completer.complete(result);
    }

    _login(
      callback: OAuthLoginCallback(
        onSuccess: () async {
          try {
            final token = await _getAccessToken();
            if (token.isEmpty) {
              completeSilent();
            } else {
              completeSuccess(NaverSignInResult(accessToken: token));
            }
          } on Object catch (e, st) {
            if (kDebugMode) debugPrint('Naver getAccessToken 실패: $e\n$st');
            completeError(ServiceUnavailable(cause: e));
          }
        },
        onFailure: (String httpStatus, String message) {
          // Android cancel 도 onFailure 로 도착 가능 — silent 흡수 (D-45 conservative).
          if (kDebugMode) {
            debugPrint('Naver onFailure: $httpStatus $message');
          }
          completeSilent();
        },
        onError: (int errorCode, String message) {
          if (message == 'user_cancel' ||
              message.startsWith('Canceled By User')) {
            completeSilent(); // D-45 silent
            return;
          }
          if (message == 'naverapp_not_installed' ||
              message == 'naverapp_need_update') {
            // SDK 자동 webview fallback 진행 중 — 분기 무시 (후속 콜백 대기).
            if (kDebugMode) {
              debugPrint('Naver onError $message — webview fallback');
            }
            return;
          }
          // 그 외 (network / SDK 오류) → ServiceUnavailable.
          completeError(ServiceUnavailable(cause: '$errorCode $message'));
        },
      ),
    );

    // timeout 60s — 콜백 미도착 시 silent (Decision #2, D-45 일관).
    return completer.future.timeout(
      const Duration(seconds: 60),
      onTimeout: () {
        if (kDebugMode) debugPrint('Naver login timeout 60s');
        return null; // D-45 일관
      },
    );
  }

  /// SDK logout — D-57 1회성 토큰 정책. Naver client-side 토큰 제거.
  ///
  /// `AuthRepository.signInWithNaver` 의 finally 블록 (race-fix end 직전 —
  /// Pitfall 2) 에서 호출한다. 실패 시 graceful ([kDebugMode] [debugPrint]) —
  /// outer 흐름 차단 안 함.
  Future<void> logout() async {
    try {
      await _logout();
    } on Object catch (e, st) {
      if (kDebugMode) {
        debugPrint('NaverSdkClient.logout 실패 (무시): $e\n$st');
      }
    }
  }
}

/// [NaverSdkClient] Provider — keepAlive (Phase 12 [kakaoSdkClientProvider]
/// 패턴).
@Riverpod(keepAlive: true)
NaverSdkClient naverSdkClient(Ref ref) {
  return NaverSdkClient();
}
