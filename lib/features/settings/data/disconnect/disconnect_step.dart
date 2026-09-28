// Phase 16.10 — see ROADMAP.md
//
// provider 측 연결 끊기 계약 (D-01 · D-02 · D-06 · D-09 · D-10 · C-08).
//
// 탈퇴 진행 화면(plan 07)과 해제 다이얼로그(plan 08)가 provider 를 모르고
// [DisconnectStep] 만 부른다. provider 별 차이(서버 callable · 재로그인 SDK ·
// 플랫폼 분기)는 step 구현 파일 안에 갇히고, 호출부는 [DisconnectOutcome] 의
// 네 값만 다룬다.
//
// C-08 제거 단위: 서버 행 = 레지스트리(`disconnect_steps.dart`) 1줄, 재로그인
// 행 = step 파일 1개 + 레지스트리 1줄. [AccountProvider] 로 분기하는 switch 를
// 새로 쓰지 않는다 — 조회는 [disconnectStepFor] 의 목록 탐색 하나다.
//
// 테스트 가능성: step 은 const 이고 생성 시점에 Firebase 를 읽지 않는다. 실행
// 의존은 모두 [DisconnectDeps] 로 `run` 인자에 들어온다 — 행 종류([kind])만
// 읽는 다이얼로그 · golden 테스트는 Firebase 초기화 없이 동작한다.
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../../../../core/auth/auth_strategy.dart';
import '../../../../core/auth/provider_id.dart';
import '../../../../core/error/app_exception.dart';
import '../../../auth/data/auth_repository.dart';
import '../../../auth/data/line_sdk_client.dart';
import '../../../auth/data/naver_sdk_client.dart';

/// provider 측 연결 끊기 1행의 결과 (Phase 16.10 · UI-SPEC §행 상태).
///
/// 진행 화면은 값마다 행 상태를, 해제 다이얼로그는 해제 outcome 을 고른다.
/// 새 값이 생기면 두 소비처의 exhaustive switch 가 컴파일 단계에서 깨진다.
@immutable
sealed class DisconnectOutcome {
  /// 하위 variant 전용 생성자.
  const DisconnectOutcome();
}

/// 끊기 성공 — provider 측 연결(앱 승인 · 토큰)이 폐기됐다.
///
/// 진행 화면 = 행 「해제됨」 · 해제 다이얼로그 = 기존 해제 callable 진행.
final class DisconnectDone extends DisconnectOutcome {
  /// [DisconnectDone] 을 생성한다.
  const DisconnectDone();
}

/// 재로그인 창 사용자 취소 (D-11) — 실패가 아니다.
///
/// 진행 화면 = 행 「로그인 대기」 유지 · 해제 다이얼로그 = 조용히 닫힘.
final class DisconnectCancelled extends DisconnectOutcome {
  /// [DisconnectCancelled] 를 생성한다.
  const DisconnectCancelled();
}

/// 로그인한 provider 계정이 이 계정에 연결된 신원과 다르다 (D-08).
///
/// 원인: Google 선택 계정 id 불일치 · Firebase `user-mismatch` 류 · 서버
/// `permission-denied` + reason `caller_identity_mismatch`. 이 경우 끊기
/// 호출은 0 이다. 진행 화면 = 행 「다른 계정」 안내 · 해제 다이얼로그 =
/// `identityMismatch` outcome.
final class DisconnectIdentityMismatch extends DisconnectOutcome {
  /// [DisconnectIdentityMismatch] 를 생성한다.
  const DisconnectIdentityMismatch();
}

/// 끊기 실패 — 재시도 또는 건너뛰기(D-12) 대상.
///
/// [exception] 은 원인 분류다: [NoInternetConnection] (네트워크 · 시간 초과)
/// · [TooManyRequests] · [ServiceUnavailable] (운영 설정 · App Check · SDK
/// 오류 · 토큰 부재) · [UnknownException] (로그인 사용자 부재 · 서버 계약
/// 위반). 진행 화면 = 행 「실패」 · 해제 다이얼로그 = `disconnectFailed`.
final class DisconnectFailed extends DisconnectOutcome {
  /// [exception] 원인으로 [DisconnectFailed] 를 생성한다.
  const DisconnectFailed(this.exception);

  /// 실패 원인 — 화면 문구는 소비처가 타입으로 고른다(서버 message 렌더 0).
  final AppException exception;
}

/// 끊기 행의 종류 — 진행 화면의 행 순서 · 버튼 모양을 정한다 (UI-SPEC Q2-A).
enum DisconnectKind {
  /// 서버 단독 끊기 — 사용자 로그인 없이 callable 1회 (Kakao · Facebook).
  server,

  /// 재로그인 끊기 — 행 안 로그인 버튼으로 provider 로그인 후 끊는다.
  relogin,
}

/// [DisconnectStep.run] 의 실행 의존 묶음 (C-08 · 테스트 가능성).
///
/// `disconnectDepsProvider` 가 인프라 provider 에서 만들고, 테스트는 mock 을
/// 직접 넣는다. step 은 이 값을 `run` 시점에만 받는다 — 레지스트리 · step
/// 생성은 Firebase 를 읽지 않는다.
@immutable
class DisconnectDeps {
  /// 실행 의존 전부를 받아 [DisconnectDeps] 를 생성한다.
  const DisconnectDeps({
    required this.auth,
    required this.functions,
    required this.googleSignIn,
    required this.lineSdkClient,
    required this.naverSdkClient,
    required this.platform,
  });

  /// 현재 로그인 사용자 · 재인증 · Apple 토큰 폐기에 쓰는 Firebase Auth.
  final fb.FirebaseAuth auth;

  /// 서버 끊기 callable 을 부르는 Functions (region scoped).
  final FirebaseFunctions functions;

  /// Google 재로그인 · `disconnect` 에 쓰는 SDK 인스턴스.
  final GoogleSignIn googleSignIn;

  /// LINE 재로그인 SDK client (LINE step 이 사용).
  final LineSdkClient lineSdkClient;

  /// Naver 재로그인 SDK client (Naver step 이 사용).
  final NaverSdkClient naverSdkClient;

  /// 실행 플랫폼 — Apple 토큰 폐기 API 분기에 쓴다(C-09).
  final TargetPlatform platform;
}

/// provider 1개의 측 연결 끊기 — 진행 화면과 해제 다이얼로그가 공유한다.
///
/// 구현체는 stateless `const` 이고 레지스트리 `kDisconnectSteps` 에 1줄로
/// 등록된다. [kind] 는 [signInStrategy] 에서 유도해 두 값이 어긋날 수 없다.
@immutable
abstract class DisconnectStep {
  /// `const` 생성자 — 구현체는 모두 stateless.
  const DisconnectStep();

  /// 이 step 이 끊는 provider.
  AccountProvider get provider;

  /// 재로그인 행의 로그인 버튼 strategy — 서버 행이면 null.
  ///
  /// 진행 화면이 기존 `SocialButton(strategy:)` 로 브랜드 버튼을 그린다.
  AuthStrategy? get signInStrategy;

  /// 행 종류 — [signInStrategy] 가 null 이면 서버 행이다.
  DisconnectKind get kind =>
      signInStrategy == null ? DisconnectKind.server : DisconnectKind.relogin;

  /// 끊기를 실행하고 결과를 돌려준다 — 예외를 던지지 않는다.
  ///
  /// [reloginForFreshness] 가 `true` 면 탈퇴 진행 화면이다 — 재로그인이
  /// 서버 탈퇴의 300초 신선도(C-02)를 겸한다(D-07). `false` 면 해제
  /// 다이얼로그다 — 끊기 토큰 확보만 하고 Firebase 세션은 건드리지 않는다
  /// (D-09). 서버 행은 이 값을 쓰지 않는다.
  Future<DisconnectOutcome> run(
    DisconnectDeps deps, {
    required bool reloginForFreshness,
  });
}

/// 끊기 callable 거부를 [DisconnectOutcome] 으로 매핑한다 (D-12 · D-13).
///
/// 서버 `message` 는 쓰지 않고 `code` + `details.reason` 만 본다.
/// - `permission-denied` + reason `caller_identity_mismatch` →
///   [DisconnectIdentityMismatch].
/// - `unavailable` · `deadline-exceeded` → [NoInternetConnection].
/// - `resource-exhausted` → [TooManyRequests].
/// - 그 밖(`provider_config` · 익명 거부 · App Check `unauthenticated` ·
///   `internal` 등) → [ServiceUnavailable].
DisconnectOutcome disconnectOutcomeFromFunctionsException(
  FirebaseFunctionsException e,
) {
  final details = e.details;
  if (e.code == 'permission-denied' &&
      details is Map &&
      details['reason'] == 'caller_identity_mismatch') {
    return const DisconnectIdentityMismatch();
  }
  if (e.code == 'unavailable' || e.code == 'deadline-exceeded') {
    return DisconnectFailed(NoInternetConnection(cause: e));
  }
  if (e.code == 'resource-exhausted') {
    return DisconnectFailed(TooManyRequests(cause: e));
  }
  return DisconnectFailed(ServiceUnavailable(cause: e));
}

/// 재로그인 · 토큰 폐기의 Firebase Auth 거부를 [DisconnectOutcome] 으로
/// 매핑한다 (D-08 · D-11).
///
/// 판정 code 목록은 기존 재인증 경로와 공유한다 — [AuthRepository]
/// `isReauthUserMismatchCode` → [DisconnectIdentityMismatch] ·
/// `isOAuthCancelCode` → [DisconnectCancelled] · 그 밖 → [ServiceUnavailable].
DisconnectOutcome disconnectOutcomeFromAuthException(
  AccountProvider provider,
  fb.FirebaseAuthException e,
) {
  if (AuthRepository.isReauthUserMismatchCode(e.code)) {
    logDisconnectFailure(provider, 'identity mismatch code=${e.code}');
    return const DisconnectIdentityMismatch();
  }
  if (AuthRepository.isOAuthCancelCode(e.code)) {
    return const DisconnectCancelled();
  }
  logDisconnectFailure(provider, 'auth code=${e.code}');
  return DisconnectFailed(ServiceUnavailable(cause: e));
}

/// [steps] 에서 [provider] 의 step 을 찾는다 — 없으면 null.
///
/// provider 별 switch 대신 목록 탐색 하나로 조회한다(C-08). email 처럼 끊을
/// provider 측 연결이 없는 값은 null 이다.
DisconnectStep? disconnectStepFor(
  Iterable<DisconnectStep> steps,
  AccountProvider provider,
) {
  return steps.where((step) => step.provider == provider).firstOrNull;
}

/// 끊기를 실행할 로그인 사용자를 돌려준다 — 부재 · 익명이면 null.
fb.User? signedInUserOf(fb.FirebaseAuth auth) {
  final current = auth.currentUser;
  if (current == null || current.isAnonymous) return null;
  return current;
}

/// 끊기 실패 근거를 debug 에서만 기록한다 (PII 0).
///
/// [reason] 에는 오류 `code` · `runtimeType` 같은 분류만 싣는다 — uid ·
/// provider 사용자 id · 토큰 · 이메일 · 서버 message 는 싣지 않는다.
void logDisconnectFailure(AccountProvider provider, String reason) {
  if (kDebugMode) {
    debugPrint('Disconnect(${provider.slug}): $reason');
  }
}
