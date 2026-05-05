import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:kakao_flutter_sdk_user/kakao_flutter_sdk_user.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/error/app_exception.dart';

part 'kakao_sdk_client.g.dart';

/// [KakaoSdkClient.signIn] 의 결과 — Kakao OIDC ID Token + 호출 시점 nonce.
///
/// `AuthRepository.signInWithKakao` 가 본 nonce 를 Cloud Function
/// `kakaoCustomToken` 호출 인자에 그대로 전달해야 jose 검증이 일치한다
/// (Phase 12 Pitfall 2 — single nonce invariant).
@immutable
class KakaoSignInResult {
  /// [idToken] (Kakao OIDC ID Token) + [nonce] (단일 호출 cryptographic 값) 묶음.
  const KakaoSignInResult({required this.idToken, required this.nonce});

  /// Kakao OIDC ID Token (jose.jwtVerify 검증 대상).
  final String idToken;

  /// Kakao SDK 인자 + Cloud Function 호출 양쪽에 동시 전달된 nonce.
  final String nonce;
}

/// Kakao 로그인 진입점 — `isKakaoTalkInstalled` / `loginWithKakaoTalk` /
/// `loginWithKakaoAccount` 분기 wrapper (Phase 12 D-01 / Pitfall 2 / Pitfall 8).
///
/// **분리 이유 (PATTERNS open discrepancy 2 옵션 A):**
/// - mocktail 격리 — `UserApi.instance` 가 static singleton 이라 ctor 함수
///   typedef 주입으로 fake 가능하게 한다 (Phase 8 `AppleSignInClient` 패턴 미러).
/// - Pitfall 2 single nonce — nonce 는 [signIn] 한 곳에서 1회 생성되어 SDK 인자
///   + 반환값 양쪽에 동시 전달된다.
/// - Pitfall 8 단일 진실원 — 본 wrapper 는 race-fix Notifier 를 읽지도 쓰지도
///   않는다. begin/end 는 `AuthRepository.signInWithKakao` 의 try-finally 가
///   단일 진실원이다.
///
/// **사용자 취소 silent (D-05):**
/// - `PlatformException(code: 'CANCELED')` (KakaoTalk app-to-app 취소) → null
/// - `KakaoClientException(reason: ClientErrorCause.cancelled)` (카카오계정
///   웹뷰 취소) → null
///
/// **idToken null 시 ServiceUnavailable throw (Pitfall 1):**
/// - Kakao Developer Console 의 OpenID Connect 활성화 토글 OFF 시
///   `OAuthToken.idToken` 이 null. 호출자 (AuthRepository) 가 Failure 로 매핑.
class KakaoSdkClient {
  /// production 진입점 — 실제 Kakao SDK 호출.
  ///
  /// 테스트는 [KakaoSdkClient.forTest] 로 함수 typedef 를 주입한다.
  KakaoSdkClient()
    : _isInstalled = isKakaoTalkInstalled,
      _loginWithTalk = _defaultLoginWithKakaoTalk,
      _loginWithAccount = _defaultLoginWithKakaoAccount,
      _logout = _defaultKakaoLogout;

  /// 테스트 전용 ctor — SDK 호출을 함수 typedef 로 fake 한다.
  ///
  /// production 코드는 [KakaoSdkClient.new] 만 사용해야 한다.
  @visibleForTesting
  KakaoSdkClient.forTest({
    required Future<bool> Function() isInstalled,
    required LoginWithKakaoFn loginWithTalk,
    required LoginWithKakaoFn loginWithAccount,
    required KakaoLogoutFn logout,
  }) : _isInstalled = isInstalled,
       _loginWithTalk = loginWithTalk,
       _loginWithAccount = loginWithAccount,
       _logout = logout;

  final Future<bool> Function() _isInstalled;
  final LoginWithKakaoFn _loginWithTalk;
  final LoginWithKakaoFn _loginWithAccount;
  final KakaoLogoutFn _logout;

  /// Kakao OIDC 로그인 — KakaoTalk 우선 + 카카오계정 웹뷰 fallback.
  ///
  /// 흐름:
  /// 1. `Random.secure()` + base64Url(32 bytes) 로 nonce 1회 생성 (Pitfall 2).
  /// 2. `isKakaoTalkInstalled` → true 면 `loginWithKakaoTalk` 우선, 실패 시
  ///    `loginWithKakaoAccount` fallback (D-01).
  /// 3. 사용자 취소 (`PlatformException` 'CANCELED' / `KakaoClientException`
  ///    `ClientErrorCause.cancelled`) → null 반환 (D-05 silent).
  /// 4. `token.idToken == null` (Pitfall 1 — OIDC 미활성화) → [ServiceUnavailable]
  ///    throw. AuthRepository 가 Failure 로 매핑한다.
  ///
  /// 반환:
  /// - [KakaoSignInResult] (idToken + 같은 nonce) — 성공.
  /// - null — 사용자 취소.
  Future<KakaoSignInResult?> signIn() async {
    final nonce = _generateNonce();
    try {
      final installed = await _isInstalled();
      OAuthToken token;
      if (installed) {
        try {
          token = await _loginWithTalk(
            serviceTerms: const <String>['openid'],
            nonce: nonce,
          );
        } on Object {
          // KakaoTalk 호출 실패 (앱 미존재 / 호출 거부 등) → 카카오계정 fallback (D-01).
          token = await _loginWithAccount(
            serviceTerms: const <String>['openid'],
            nonce: nonce,
          );
        }
      } else {
        token = await _loginWithAccount(
          serviceTerms: const <String>['openid'],
          nonce: nonce,
        );
      }

      final idToken = token.idToken;
      if (idToken == null) {
        // Pitfall 1: Kakao Developer Console 의 OIDC 활성화 토글 OFF.
        throw const ServiceUnavailable();
      }
      return KakaoSignInResult(idToken: idToken, nonce: nonce);
    } on PlatformException catch (e) {
      // KakaoTalk app-to-app 취소 (D-05).
      if (e.code == 'CANCELED') return null;
      rethrow;
    } on KakaoClientException catch (e) {
      // 카카오계정 웹뷰 취소 (D-05 보조).
      if (e.reason == ClientErrorCause.cancelled) return null;
      rethrow;
    }
  }

  /// SDK logout — D-57 1회성 토큰 정책 (Phase 13 — see ROADMAP.md, retroactive).
  ///
  /// `AuthRepository.signInWithKakao` 의 finally 블록 (race-fix end 직전 —
  /// Pitfall 2) 에서 호출한다. Kakao client-side 디바이스 토큰을 제거하여
  /// 재로그인 시 사용자가 명시적으로 동의 화면을 다시 보도록 한다.
  ///
  /// `signOut` 메서드와 책임 분리:
  /// - `signOut`: Firebase signOut 전체 ([fb.FirebaseAuth.signOut])
  /// - `logout`: SDK 1회성 토큰만 ([UserApi.instance.logout])
  ///
  /// 실패 시 graceful ([kDebugMode] [debugPrint]) — outer 흐름 차단 안 함.
  Future<void> logout() async {
    try {
      await _logout();
    } on Object catch (e, st) {
      if (kDebugMode) {
        debugPrint('KakaoSdkClient.logout 실패 (무시): $e\n$st');
      }
    }
  }

  /// nonce 생성 — `Random.secure()` (OS CSPRNG) + 32 bytes + base64Url.
  ///
  /// `Random()` (MT19937 — 예측 가능) 사용 금지. RFC 7636 권장 길이.
  String _generateNonce() {
    final random = Random.secure();
    final bytes = List<int>.generate(32, (_) => random.nextInt(256));
    return base64UrlEncode(bytes).replaceAll('=', '');
  }
}

/// Kakao SDK 의 `loginWithKakao*` 함수 시그니처 typedef.
///
/// `UserApi.instance.loginWithKakaoTalk` / `loginWithKakaoAccount` 의 공통
/// 인자 (`serviceTerms`, `nonce`) 만 노출한다. 본 wrapper 는 OIDC 로그인
/// 시나리오만 다루므로 `channelPublicIds` / `prompts` / `loginHint` 등은
/// 노출하지 않는다.
///
/// `KakaoSdkClient.forTest` 의 ctor 인자 타입 — 테스트가 fake 함수를 주입한다.
typedef LoginWithKakaoFn =
    Future<OAuthToken> Function({
      List<String>? serviceTerms,
      String? nonce,
    });

/// Default `loginWithKakaoTalk` 호출 — production 진입점.
Future<OAuthToken> _defaultLoginWithKakaoTalk({
  List<String>? serviceTerms,
  String? nonce,
}) {
  return UserApi.instance.loginWithKakaoTalk(
    serviceTerms: serviceTerms,
    nonce: nonce,
  );
}

/// Default `loginWithKakaoAccount` 호출 — production 진입점.
///
/// `prompts` / `loginHint` 는 본 wrapper 가 OIDC 로그인 시나리오만 다루므로
/// 미사용 (default null).
Future<OAuthToken> _defaultLoginWithKakaoAccount({
  List<String>? serviceTerms,
  String? nonce,
}) {
  return UserApi.instance.loginWithKakaoAccount(
    serviceTerms: serviceTerms,
    nonce: nonce,
  );
}

/// Kakao SDK logout 함수 시그니처 typedef (Phase 13 — see ROADMAP.md, D-57
/// retroactive).
///
/// [KakaoSdkClient.forTest] 의 ctor 인자 타입 — 테스트가 fake 함수를 주입한다.
typedef KakaoLogoutFn = Future<void> Function();

/// Default `UserApi.instance.logout` 호출 — production 진입점 (D-57).
Future<void> _defaultKakaoLogout() async {
  await UserApi.instance.logout();
}

/// [KakaoSdkClient] Provider — keepAlive (Phase 11 facebookAuthProvider 패턴).
@Riverpod(keepAlive: true)
KakaoSdkClient kakaoSdkClient(Ref ref) {
  return KakaoSdkClient();
}
