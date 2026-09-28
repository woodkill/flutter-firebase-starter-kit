// Phase 16.10 — see ROADMAP.md
//
// 서버 단독 끊기 행 (D-02 — Kakao 어드민 키 · Facebook app token).
//
// 사용자 로그인 없이 callable 1회로 끝난다. 끊을 신원은 서버가 호출자
// `request.auth.uid` 의 `identity_index` 에서 찾으므로 입력은 `{}` 다(plan 02
// 계약 — 응답 `{ok: true, disconnectedCount}`). provider 별 파일을 두지 않고
// 레지스트리가 이 클래스를 provider · callable 이름만 바꿔 인스턴스화한다
// (C-08 — 서버 행 제거 = 레지스트리 1줄).
import 'package:cloud_functions/cloud_functions.dart';

import '../../../../core/auth/auth_strategy.dart';
import '../../../../core/auth/provider_id.dart';
import '../../../../core/error/app_exception.dart';
import '../../../auth/data/auth_repository.dart';
import 'disconnect_step.dart';

/// 서버 callable 로 provider 측 연결을 끊는 행 (Kakao · Facebook).
class ServerDisconnectStep extends DisconnectStep {
  /// [provider] 를 [callableName] callable 로 끊는 step 을 생성한다.
  const ServerDisconnectStep({
    required this.provider,
    required this.callableName,
  });

  @override
  final AccountProvider provider;

  /// 호출할 끊기 callable 이름 (예: `disconnectKakaoProvider`).
  final String callableName;

  @override
  AuthStrategy? get signInStrategy => null;

  @override
  Future<DisconnectOutcome> run(
    DisconnectDeps deps, {
    required bool reloginForFreshness,
  }) async {
    if (signedInUserOf(deps.auth) == null) {
      // 결정적 실패 — 로그인 사용자 없이는 서버가 신원을 찾을 수 없다.
      logDisconnectFailure(provider, 'no signed-in user');
      return const DisconnectFailed(UnknownException());
    }
    try {
      final callable = deps.functions.httpsCallable(
        callableName,
        options: HttpsCallableOptions(
          timeout: AuthRepository.customTokenCallableTimeout,
        ),
      );
      final response = await callable.call<Map<String, dynamic>>(
        <String, dynamic>{},
      );
      if (response.data['ok'] != true) {
        // 서버 계약 위반 — 재시도로 해소되지 않는다.
        logDisconnectFailure(provider, 'ok!=true');
        return const DisconnectFailed(UnknownException());
      }
      return const DisconnectDone();
    } on FirebaseFunctionsException catch (e) {
      logDisconnectFailure(provider, 'code=${e.code}');
      return disconnectOutcomeFromFunctionsException(e);
    } on Object catch (e) {
      // PII 0 — runtimeType 만.
      logDisconnectFailure(provider, 'runtimeType=${e.runtimeType}');
      return DisconnectFailed(ServiceUnavailable(cause: e));
    }
  }
}
