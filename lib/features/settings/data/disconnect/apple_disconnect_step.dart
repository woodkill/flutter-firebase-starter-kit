// Phase 16.10 — see ROADMAP.md
//
// Apple 재로그인 끊기 행 (D-02 클라이언트 · D-04 · D-05 · D-07 · D-08 · C-09).
//
// 양 플랫폼 모두 `reauthenticateWithProvider(AppleAuthProvider)` 1회로 신원
// 대조(`user-mismatch` · `user-not-found` — D-08) · `auth_time` 갱신(D-07) ·
// 폐기 토큰 확보를 한 번에 얻는다. 폐기 토큰의 위치는 플랫폼마다 다르다
// (firebase_auth 6.7.0 pub cache 실측 · RESEARCH OQ4).
// - iOS: native `ASAuthorizationController` 가 `authorizationCode` 를
//   `additionalUserInfo.authorizationCode` 에 싣는다 →
//   `revokeTokenWithAuthorizationCode`. Apple code 는 5분 · 1회용이라
//   받자마자 쓴다(D-05). iOS 에서 access token API 는 지원되지 않는다.
// - Android: `UserCredential.credential.accessToken` →
//   `revokeAccessToken` **만**. C-09 함정: Android 의
//   authorization code API 는 아무것도 하지 않고 성공을 돌려준다 — 호출하면
//   Apple 연결이 남은 채 「해제됨」 이 표시된다. 테스트가 호출 0 을 잠근다.
// - A4 `[ASSUMED]`: Android 재인증 결과에 access token 이 non-null 인지는
//   Firebase 문서가 로그인 경로만 예시로 들어 UAT(plan 10 Apple 행)에서
//   실측한다. null 이면 행 실패 → 건너뛰기(D-12).
//
// 기각한 대안: 서버가 Apple REST `/auth/revoke` 를 직접 호출 — Apple private
// key 를 Secret Manager 에 복제해야 해 Firebase 콘솔 설정과 이중화된다.
// `sign_in_with_apple` 패키지로 code 별도 취득 — 의존성 추가 + Apple 프롬프트
// 2회인데 Firebase 가 같은 값을 이미 노출한다.
import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:flutter/foundation.dart';

import '../../../../core/auth/auth_strategy.dart';
import '../../../../core/auth/provider_id.dart';
import '../../../../core/auth/strategies/apple_auth_strategy.dart';
import '../../../../core/error/app_exception.dart';
import 'disconnect_step.dart';

/// Apple 재로그인 뒤 플랫폼별 API 로 Apple 토큰을 폐기하는 행.
class AppleDisconnectStep extends DisconnectStep {
  /// [AppleDisconnectStep] 을 생성한다.
  const AppleDisconnectStep();

  @override
  AccountProvider get provider => AccountProvider.apple;

  @override
  AuthStrategy? get signInStrategy => const AppleAuthStrategy();

  @override
  Future<DisconnectOutcome> run(
    DisconnectDeps deps, {
    required bool reloginForFreshness,
  }) async {
    final current = signedInUserOf(deps.auth);
    if (current == null) {
      logDisconnectFailure(provider, 'no signed-in user');
      return const DisconnectFailed(UnknownException());
    }
    try {
      // 탈퇴 · 해제 모두 재인증한다 — 폐기 토큰의 유일한 원천이다.
      final credential = await current.reauthenticateWithProvider(
        fb.AppleAuthProvider()
          ..addScope('email')
          ..addScope('name'),
      );
      if (deps.platform == TargetPlatform.iOS) {
        final code = credential.additionalUserInfo?.authorizationCode;
        if (code == null || code.isEmpty) {
          logDisconnectFailure(provider, 'authorizationCode missing');
          return const DisconnectFailed(ServiceUnavailable());
        }
        await deps.auth.revokeTokenWithAuthorizationCode(code);
      } else {
        // Android — code API 는 가짜 성공이라 access token 경로만 쓴다(C-09).
        final accessToken = credential.credential?.accessToken;
        if (accessToken == null || accessToken.isEmpty) {
          logDisconnectFailure(provider, 'accessToken missing');
          return const DisconnectFailed(ServiceUnavailable());
        }
        await deps.auth.revokeAccessToken(accessToken);
      }
      return const DisconnectDone();
    } on fb.FirebaseAuthException catch (e) {
      return disconnectOutcomeFromAuthException(provider, e);
    } on Object catch (e) {
      // PII 0 — runtimeType 만.
      logDisconnectFailure(provider, 'runtimeType=${e.runtimeType}');
      return DisconnectFailed(ServiceUnavailable(cause: e));
    }
  }
}
