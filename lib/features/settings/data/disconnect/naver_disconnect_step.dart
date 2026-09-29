// Phase 16.10 — see ROADMAP.md
//
// Naver 재로그인 끊기 행 (D-02 · D-07 · D-08 · D-09 · D-11 · C-03).
//
// Naver 토큰 폐기에는 `client_secret` 이 필요해 서버(`disconnectNaverProvider`)
// 를 거친다. 로그인 결과는 두 모양이고 callable 은 하나다 — payload 만
// [NaverSignInResult] sealed 결과로 고른다(provider 분기 아님).
// - 1-tap(NAVER 앱): `{accessToken}`.
// - 킷 웹: `{code, state}`. code 는 1회용이라 재로그인과 끊기를 한 callable
//   이 함께 처리한다(RESEARCH Pitfall 5).
// timeout 은 두 모양 모두 [kReloginDisconnectCallableTimeout](25s)이다 (16.10
// review WR-03). 서버가 NAVER 를 직렬로 부른다 — 웹 = code 교환 · 프로필 ·
// 폐기 3회(15s), 1-tap = 프로필 · 폐기 2회(10s) — 로그인 경로보다 폐기 1회가
// 더 많아 로그인 timeout(10s · 웹 20s)을 쓰면 서버는 끊었는데 클라이언트는
// 실패로 표시할 수 있었다.
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
import '../../../auth/data/minted_custom_token.dart';
import '../../../auth/data/naver_sdk_client.dart';
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
    NaverSdkClient? sdkClient;
    try {
      // 자기 SDK client 를 직접 읽는다 — 공용 [DisconnectDeps] 에 provider 별
      // 필드를 두지 않는다(C-08 · review WR-04). 읽기 실패도 아래 `on Object`
      // 가 실패로 흡수한다(run 은 예외를 던지지 않는 계약).
      final client = deps.read(naverSdkClientProvider);
      sdkClient = client;
      final result = await client.signIn();
      if (result == null) {
        // D-11: 로그인 취소는 실패가 아니다.
        return const DisconnectCancelled();
      }
      final payload = switch (result) {
        NaverAppSignIn(:final accessToken) => <String, dynamic>{
          'accessToken': accessToken,
        },
        NaverWebSignIn(:final code, :final state) => <String, dynamic>{
          'code': code,
          'state': state,
        },
      };
      final callable = deps.functions.httpsCallable(
        'disconnectNaverProvider',
        options: HttpsCallableOptions(
          timeout: kReloginDisconnectCallableTimeout,
        ),
      );
      final response = await callable.call<Map<String, dynamic>>(payload);
      final customToken = requireMintedCustomToken(
        response.data,
        currentUid: current.uid,
      );
      if (reloginForFreshness) {
        // D-07: 같은 uid 새 세션 = 새 auth_time (서버 탈퇴 신선도). 서버 끊기는
        // 이미 끝났으므로 이 로그인 실패는 끊기 결과를 바꾸지 않는다(IN-03).
        await signInWithReloginToken(deps, provider, customToken);
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
      await sdkClient?.logout();
    }
  }
}
