// Phase 16.10 — see ROADMAP.md
//
// Google 재로그인 끊기 행 (D-02 클라이언트 · D-07 · D-08 · RESEARCH OQ7).
//
// `GoogleSignIn.disconnect()` 는 Android 에서 `AuthorizationClient.revokeAccess`
// (앱에 준 모든 scope 승인 취소), iOS 에서 `GIDSignIn.disconnect` 로 동작한다.
// Android 구현은 **프로세스 메모리 캐시**(`authenticate()` 가 넣어 둔 계정)에
// 있는 계정만 취소한다 — 앱 재시작 뒤 `authenticate()` 없이 부르면 아무것도
// 취소하지 않고 성공한다(RESEARCH Pitfall 10). 그래서 authenticate → 연결
// 계정 대조 → (탈퇴만) 재인증 → disconnect 를 반드시 이 한 함수 안에서 이
// 순서로 한다. `disconnect()` 는 Google 계정 ↔ 앱 승인만 끊고 Firebase 세션 ·
// `providerData` 는 건드리지 않는다.
//
// revoke endpoint(`oauth2.googleapis.com/revoke`)는 채택하지 않았다 — ID
// token 은 받지 않아 access token 이 필요하고, 그 토큰을 얻으려면 별도 승인
// 프롬프트가 1회 더 뜬다. `disconnect()` 가 실패하면 행 실패(재시도 ·
// 건너뛰기 D-12)이며 endpoint fallback 은 두지 않는다.
import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:google_sign_in/google_sign_in.dart';

import '../../../../core/auth/auth_strategy.dart';
import '../../../../core/auth/provider_id.dart';
import '../../../../core/auth/strategies/google_auth_strategy.dart';
import '../../../../core/error/app_exception.dart';
import 'disconnect_step.dart';

/// Google 재로그인으로 앱 승인을 취소하는 행.
class GoogleDisconnectStep extends DisconnectStep {
  /// [GoogleDisconnectStep] 을 생성한다.
  const GoogleDisconnectStep();

  @override
  AccountProvider get provider => AccountProvider.google;

  @override
  AuthStrategy? get signInStrategy => const GoogleAuthStrategy();

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
      final account = await deps.googleSignIn.authenticate();
      // D-08: 다른 Google 계정의 앱 승인을 취소하지 않도록 재인증 · 끊기 전에
      // 이 계정에 연결된 신원인지 먼저 대조한다(불일치면 Firebase 호출 0).
      final isLinkedAccount = current.providerData.any(
        (info) => info.providerId == 'google.com' && info.uid == account.id,
      );
      if (!isLinkedAccount) {
        logDisconnectFailure(provider, 'account not linked');
        return const DisconnectIdentityMismatch();
      }
      if (reloginForFreshness) {
        // D-07: 탈퇴는 이 로그인이 서버 300초 신선도(auth_time)를 겸한다.
        final idToken = account.authentication.idToken;
        if (idToken == null || idToken.isEmpty) {
          logDisconnectFailure(provider, 'idToken missing');
          return const DisconnectFailed(ServiceUnavailable());
        }
        await current.reauthenticateWithCredential(
          fb.GoogleAuthProvider.credential(idToken: idToken),
        );
      }
      await deps.googleSignIn.disconnect();
      return const DisconnectDone();
    } on GoogleSignInException catch (e) {
      if (e.code == GoogleSignInExceptionCode.canceled) {
        return const DisconnectCancelled();
      }
      logDisconnectFailure(provider, 'google code=${e.code.name}');
      return DisconnectFailed(ServiceUnavailable(cause: e));
    } on fb.FirebaseAuthException catch (e) {
      return disconnectOutcomeFromAuthException(provider, e);
    } on Object catch (e) {
      // PII 0 — runtimeType 만.
      logDisconnectFailure(provider, 'runtimeType=${e.runtimeType}');
      return DisconnectFailed(ServiceUnavailable(cause: e));
    }
  }
}
