// Phase 16.10 — see ROADMAP.md
//
// Naver 재로그인 끊기 행 (D-02 · D-07 · D-08 · D-09 · D-11 · C-03).
//
// Naver 토큰 폐기에는 `client_secret` 이 필요해 서버(`disconnectNaverProvider`)
// 를 거친다. 로그인 결과는 두 모양이고 callable 은 하나다 — payload 와
// timeout 만 [NaverSignInResult] sealed 결과로 고른다(provider 분기 아님).
// - 1-tap(NAVER 앱): `{accessToken}` · 로그인과 같은 Custom Token timeout.
// - 킷 웹: `{code, state}` · 20초 timeout. 서버가 code 교환 · 프로필 · 소유
//   대조 · 폐기 · custom token 발급을 NAVER 에 직렬로 호출하므로 1-tap 보다
//   길다(16.5 WR-01 — 로그인 웹 경로와 같은 예산). code 는 1회용이라 재로그인
//   과 끊기를 한 callable 이 함께 처리한다(RESEARCH Pitfall 5).
//
// 순서 의무 (RESEARCH Pitfall 1 · A7): SDK logout 은 callable 응답을 받은 뒤
// `finally` 에서만 부른다 — LINE 과 같은 규칙으로 두어 토큰 폐기 시점이
// provider 마다 갈리지 않게 한다.
//
// 소비 조건 · 이중 대조 · 토큰 비보관은 LINE 행과 같다: 탈퇴 진행 화면
// (`reloginForFreshness: true`)만 custom token 을 소비하고(D-07 · D-09), 서버
// 소유 대조 + 클라이언트 uid 대조([requireMintedCustomToken]) 중 하나라도
// 어긋나면 소비 0(D-08), SDK 토큰 · code · custom token 은 `run` 지역 변수
// 로만 쓴다(C-03).
import 'package:cloud_functions/cloud_functions.dart';

import '../../../../core/auth/auth_strategy.dart';
import '../../../../core/auth/provider_id.dart';
import '../../../../core/auth/strategies/naver_auth_strategy.dart';
import '../../../../core/error/app_exception.dart';
import '../../../auth/data/auth_repository.dart';
import '../../../auth/data/minted_custom_token.dart';
import '../../../auth/data/naver_sign_in_result.dart';
import 'disconnect_step.dart';

/// Naver 재로그인으로 앱 연결을 서버 경유 해제하는 행.
class NaverDisconnectStep extends DisconnectStep {
  /// [NaverDisconnectStep] 을 생성한다.
  const NaverDisconnectStep();

  @override
  AccountProvider get provider => AccountProvider.naver;

  @override
  AuthStrategy? get signInStrategy => const NaverAuthStrategy();

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
      final result = await deps.naverSdkClient.signIn();
      if (result == null) {
        // D-11: 로그인 취소는 실패가 아니다.
        return const DisconnectCancelled();
      }
      final (payload, timeout) = switch (result) {
        NaverAppSignIn(:final accessToken) => (
          <String, dynamic>{'accessToken': accessToken},
          AuthRepository.customTokenCallableTimeout,
        ),
        NaverWebSignIn(:final code, :final state) => (
          <String, dynamic>{'code': code, 'state': state},
          AuthRepository.naverWebCallableTimeout,
        ),
      };
      final callable = deps.functions.httpsCallable(
        'disconnectNaverProvider',
        options: HttpsCallableOptions(timeout: timeout),
      );
      final response = await callable.call<Map<String, dynamic>>(payload);
      final customToken = requireMintedCustomToken(
        response.data,
        currentUid: current.uid,
      );
      if (reloginForFreshness) {
        // D-07: 같은 uid 새 세션 = 새 auth_time (서버 탈퇴 신선도).
        await deps.auth.signInWithCustomToken(customToken);
      }
      return const DisconnectDone();
    } on ReauthUserMismatch {
      logDisconnectFailure(provider, 'callable uid');
      return const DisconnectIdentityMismatch();
    } on AppException catch (e) {
      logDisconnectFailure(provider, 'app ${e.runtimeType}');
      return DisconnectFailed(e);
    } on FirebaseFunctionsException catch (e) {
      logDisconnectFailure(provider, 'code=${e.code}');
      return disconnectOutcomeFromFunctionsException(e);
    } on Object catch (e) {
      // PII 0 — runtimeType 만.
      logDisconnectFailure(provider, 'runtimeType=${e.runtimeType}');
      return DisconnectFailed(ServiceUnavailable(cause: e));
    } finally {
      // Pitfall 1 · C-03: callable 응답 뒤에만 SDK 토큰을 폐기한다.
      await deps.naverSdkClient.logout();
    }
  }
}
