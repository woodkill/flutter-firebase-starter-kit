// Phase 16.10 — see ROADMAP.md
//
// LINE 재로그인 끊기 행 (D-02 · D-07 · D-08 · D-09 · D-11 · C-03).
//
// 흐름: LINE SDK 로그인 → 사용자 access token 으로 `disconnectLineProvider`
// 호출 → 서버가 소유 대조 · deauthorize · 같은 uid custom token 발급 →
// 클라이언트가 응답 uid 를 현재 uid 와 대조 → (탈퇴만) custom token 소비 →
// SDK logout.
//
// 순서 의무 (RESEARCH Pitfall 1): LINE SDK `logout()` 은 access token 을
// 서버에서 폐기한다. callable 응답을 받기 전에 logout 하면 deauthorize 가
// 실패하고 사용자는 「해제하지 못했습니다」 만 반복해 본다. 그래서 logout 은
// callable `await` 뒤의 `finally` 에서만 부른다(테스트가 호출 순서를 잠근다).
//
// 소비 조건 (D-07 · D-09): 탈퇴 진행 화면(`reloginForFreshness: true`)만
// `signInWithCustomToken` 으로 새 `auth_time` 을 만든다 — 서버 탈퇴의 300초
// 신선도를 이 로그인이 겸한다. 해제 다이얼로그(`false`)는 토큰을 버린다.
//
// 이중 대조 (D-08): 서버가 LINE userId 와 `identity_index` 소유를 대조하고
// (`permission-denied` + `caller_identity_mismatch`), 클라이언트가 응답 uid 를
// 현재 uid 와 대조한다([requireMintedCustomToken]). 어느 쪽이든 불일치면
// custom token 소비 0 — 다른 계정 세션으로 바뀌지 않는다.
//
// C-03: SDK access token · custom token 은 `run` 지역 변수로만 쓰고 필드 ·
// 캐시 · 로그에 남기지 않는다. 로그인 race 방어(`SocialLinkInProgress`)는
// 감싸지 않는다 — 끊기는 현재 세션을 유지한 채 진행해 `currentUser == null`
// 창이 없다.
import 'package:cloud_functions/cloud_functions.dart';

import '../../../../core/auth/auth_strategy.dart';
import '../../../../core/auth/provider_id.dart';
import '../../../../core/auth/strategies/line_auth_strategy.dart';
import '../../../../core/error/app_exception.dart';
import '../../../auth/data/line_sdk_client.dart';
import '../../../auth/data/minted_custom_token.dart';
import 'disconnect_step.dart';

/// LINE 재로그인으로 앱 연결을 서버 경유 해제하는 행.
class LineDisconnectStep extends DisconnectStep {
  /// [LineDisconnectStep] 을 생성한다.
  const LineDisconnectStep();

  @override
  AccountProvider get provider => AccountProvider.line;

  @override
  AuthStrategy? get signInStrategy => const LineAuthStrategy();

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
    LineSdkClient? sdkClient;
    try {
      // 자기 SDK client 를 직접 읽는다 — 공용 [DisconnectDeps] 에 provider 별
      // 필드를 두지 않는다(C-08 · review WR-04). 읽기 실패도 아래 `on Object`
      // 가 실패로 흡수한다(run 은 예외를 던지지 않는 계약).
      final client = deps.read(lineSdkClientProvider);
      sdkClient = client;
      final result = await client.signIn();
      if (result == null) {
        // D-11: 로그인 취소는 실패가 아니다.
        return const DisconnectCancelled();
      }
      if (result.accessToken.isEmpty) {
        logDisconnectFailure(provider, 'access token missing');
        return const DisconnectFailed(ServiceUnavailable());
      }
      final callable = deps.functions.httpsCallable(
        'disconnectLineProvider',
        // WR-03: 서버 외부 호출 예산(verify ∥ 프로필 → 발급 → 해제)보다 길게.
        options: HttpsCallableOptions(
          timeout: kReloginDisconnectCallableTimeout,
        ),
      );
      final response = await callable.call<Map<String, dynamic>>(
        <String, dynamic>{'accessToken': result.accessToken},
      );
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
