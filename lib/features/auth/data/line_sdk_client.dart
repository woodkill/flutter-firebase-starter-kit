// Phase 14 — see ROADMAP.md
//
// LINE 로그인 진입점 + Phase 12 KakaoSdkClient 의 typedef 주입 패턴 미러.
// D-LINE-16 ~ D-LINE-22a + Pitfall 4/8 race-fix 단일 진실원 정책 일관.
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter_line_sdk/flutter_line_sdk.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/error/app_exception.dart';

part 'line_sdk_client.g.dart';

/// [LineSdkClient.signIn] 의 결과 — LINE OIDC ID Token + 호출 시점 nonce.
///
/// `AuthRepository.signInWithLine` 가 본 nonce 를 Cloud Function
/// `lineCustomToken` 호출 인자에 그대로 전달해야 jose 검증이 일치한다
/// (Phase 14 D-LINE-21 single nonce invariant — Phase 12 Kakao 패턴 mirror).
@immutable
class LineSignInResult {
  /// [idToken] (LINE OIDC ID Token, JWT) + [nonce] (단일 호출 raw nonce) 묶음.
  const LineSignInResult({required this.idToken, required this.nonce});

  /// LINE OIDC ID Token — JWT raw 문자열. Cloud Function 의 jose 검증 대상.
  final String idToken;

  /// LINE SDK 인자 + Cloud Function 호출 양쪽에 동시 전달된 raw nonce.
  ///
  /// LINE SDK 가 내부적으로 SHA256 hash 후 `id_token` claim 에 박는다. Cloud
  /// Function 측에서 client 가 보낸 raw nonce 를 동일하게 SHA256 해 claim 과
  /// 비교한다 (Wave 3 A1 emulator 검증 의무 — Plan 14-04 helper nonceHashing).
  final String nonce;
}

/// LINE SDK `login(scopes:, option:)` 함수 시그니처 typedef.
///
/// [LineSdkClient.forTest] 의 ctor 인자 타입 — 테스트가 fake 함수를 주입한다.
/// `LineSDK.instance.login` 의 static 특성상 함수 typedef 주입 패턴 필수
/// (Phase 12 Kakao / Phase 13 Naver 패턴 일관).
typedef LineLoginFn =
    Future<LoginResult> Function({
      required List<String> scopes,
      required LoginOption option,
    });

/// LINE SDK `logout()` 함수 시그니처 typedef (D-LINE-57 1회성 토큰 정책).
typedef LineLogoutFn = Future<void> Function();

/// Default `LineSDK.instance.login` 호출 — production 진입점.
Future<LoginResult> _defaultLineLogin({
  required List<String> scopes,
  required LoginOption option,
}) {
  return LineSDK.instance.login(scopes: scopes, option: option);
}

/// Default `LineSDK.instance.logout` 호출 — production 진입점 (D-LINE-57).
Future<void> _defaultLineLogout() async {
  await LineSDK.instance.logout();
}

/// LINE 로그인 진입점 — `LineSDK.instance.login` wrapper (Phase 14 D-LINE-17).
///
/// **분리 이유 (Phase 12 [KakaoSdkClient] / Phase 13 [NaverSdkClient] 패턴
/// 미러):**
/// - mocktail 격리 — `LineSDK.instance.login` 이 static 이라 ctor 함수 typedef
///   주입으로 fake 가능하게 한다.
/// - D-LINE-21 single nonce — nonce 는 [signIn] 한 곳에서 1회 생성되어 SDK
///   인자 + 반환값 양쪽에 동시 전달된다 (raw nonce → SDK 내부 SHA256 hash →
///   `id_token` claim 비교).
/// - Pitfall 8 단일 진실원 — 본 wrapper 는 race-fix Notifier 를 읽지도 쓰지도
///   않는다. begin/end 는 `AuthRepository.signInWithLine` 의 try-finally 가
///   단일 진실원이다.
///
/// **사용자 취소 silent (D-LINE-21 / Phase 9 D-09 패턴):**
/// - `PlatformException(code: 'CANCEL')` (iOS LINE app-to-app 취소) → null
/// - `PlatformException(code: 'AUTHENTICATION_CANCELLED')` (Android LINE 앱
///   취소) → null
///
/// **idToken null 시 [ServiceUnavailable] throw (Pitfall 1 — OIDC scope 누락):**
/// - LINE Developer Console 의 Channel scope 에 `openid` 미선택 시
///   `LoginResult.accessToken.idTokenRaw` 가 null. 호출자 (AuthRepository) 가
///   Failure 로 매핑.
class LineSdkClient {
  /// production 진입점 — 실제 LINE SDK 호출.
  ///
  /// 테스트는 [LineSdkClient.forTest] 로 함수 typedef 를 주입한다.
  LineSdkClient()
    : _login = _defaultLineLogin,
      _logout = _defaultLineLogout;

  /// 테스트 전용 ctor — SDK 호출을 함수 typedef 로 fake 한다.
  ///
  /// production 코드는 [LineSdkClient.new] 만 사용해야 한다.
  @visibleForTesting
  LineSdkClient.forTest({
    required LineLoginFn login,
    required LineLogoutFn logout,
  }) : _login = login,
       _logout = logout;

  final LineLoginFn _login;
  final LineLogoutFn _logout;

  /// LINE OIDC 로그인 — LINE 앱 우선 + 웹뷰 fallback (SDK 자체 제어).
  ///
  /// 흐름:
  /// 1. `Random.secure()` + base64Url(16 bytes) 로 raw nonce 1회 생성
  ///    (D-LINE-21 single nonce). 16 bytes = 22 chars (base64url, padding 제거).
  /// 2. `_login(scopes: const ['openid', 'profile'], option: LoginOption(
  ///    false, 'normal')..idTokenNonce = nonce)` 호출.
  /// 3. `result.accessToken.idTokenRaw == null` (Pitfall 1 — OIDC scope 누락) →
  ///    [ServiceUnavailable] throw.
  /// 4. 사용자 취소 (`PlatformException` 'CANCEL' / 'AUTHENTICATION_CANCELLED')
  ///    → null 반환 (D-LINE-21 silent).
  ///
  /// 반환:
  /// - [LineSignInResult] (idToken + 같은 nonce) — 성공.
  /// - null — 사용자 취소.
  Future<LineSignInResult?> signIn() async {
    final nonce = _generateNonce();
    try {
      final option = LoginOption(false, 'normal')..idTokenNonce = nonce;
      final result = await _login(
        scopes: const <String>['openid', 'profile'],
        option: option,
      );
      final idTokenRaw = result.accessToken.idTokenRaw;
      if (idTokenRaw == null) {
        // Pitfall 1: LINE Developer Console 에서 'openid' scope 미선택 시.
        throw const ServiceUnavailable();
      }
      return LineSignInResult(idToken: idTokenRaw, nonce: nonce);
    } on PlatformException catch (e) {
      // D-LINE-21 silent cancel — iOS = 'CANCEL', Android = 'AUTHENTICATION_CANCELLED'.
      if (e.code == 'CANCEL' || e.code == 'AUTHENTICATION_CANCELLED') {
        return null;
      }
      rethrow;
    }
  }

  /// SDK logout — D-LINE-57 1회성 토큰 정책 (Phase 13 [NaverSdkClient] 패턴
  /// mirror, D-57 retroactive 일관).
  ///
  /// `AuthRepository.signInWithLine` 의 finally 블록 (race-fix end 직전 —
  /// Pitfall 2) 에서 호출한다. LINE client-side 디바이스 access token 을
  /// 제거하여 재로그인 시 사용자가 명시적으로 동의 화면을 다시 보도록 한다.
  ///
  /// 실패 시 graceful ([kDebugMode] [debugPrint]) — outer 흐름 차단 안 함.
  Future<void> logout() async {
    try {
      await _logout();
    } on Object catch (e, st) {
      if (kDebugMode) {
        debugPrint('LineSdkClient.logout 실패 (무시): $e\n$st');
      }
    }
  }

  /// raw nonce 생성 — `Random.secure()` (OS CSPRNG) + 16 bytes + base64Url.
  ///
  /// `Random()` (MT19937 — 예측 가능) 사용 금지. 16 bytes 는 base64url 후
  /// 22 chars — RFC 7636 권장 길이 (PKCE code_verifier 와 동등).
  String _generateNonce() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    return base64UrlEncode(bytes).replaceAll('=', '');
  }
}

/// [LineSdkClient] Provider — keepAlive (Phase 12 [kakaoSdkClientProvider] /
/// Phase 13 [naverSdkClientProvider] 패턴 일관).
@Riverpod(keepAlive: true)
LineSdkClient lineSdkClient(Ref ref) {
  return LineSdkClient();
}
