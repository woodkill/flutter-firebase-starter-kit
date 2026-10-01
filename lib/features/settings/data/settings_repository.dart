// Phase 16 Plan 16-06 / D-05~D-08 — SettingsRepository 본체.
//
// `deleteUserAccount` Cloud Function callable wrapper:
// - fresh ID Token 발급 (`getIdToken(true)`) — revoked 토큰 차단 + 클레임
//   최신화 목적 (D-06). **forceRefresh 는 `auth_time` 을 갱신하지 않는다**
//   (WR-04) — 서버의 5분 boundary 통과는 실제 재인증으로만 가능하다.
// - callable invoke + FirebaseFunctionsException 원인별 매핑
//   (reason reauthentication_required → ReauthenticationRequiredException,
//   SDK 계층 거부 → AppCheckFailedException (Phase 17 D-43),
//   unavailable{storage_cleanup_failed} → ServiceUnavailable (Phase 17 D-40),
//   그 밖은 code switch).
// - PII invariant — idToken 본문 / email 본문 logger 비전파 (S5 sentinel).
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:flutter/foundation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/crashlytics/crashlytics_service.dart';
import '../../../core/error/app_exception.dart';
import '../../../core/functions/callable_rejection.dart';
import '../../../core/providers/firebase_providers.dart';
import '../domain/delete_user_request.dart';

part 'settings_repository.g.dart';

/// 사용자 설정 (탈퇴 등) 관련 Repository (Phase 16 D-06).
///
/// `deleteUserAccount` Cloud Function 호출 + FirebaseFunctionsException →
/// [AppException] 매핑 + fresh ID Token 발급 (D-06 의 5분 auth_time
/// boundary baseline).
class SettingsRepository {
  /// [SettingsRepository] 를 생성한다.
  ///
  /// [crashlytics] 는 App Check 차단 판정(`classifyAppCheckRejection`)이
  /// non-fatal 1회를 남기는 채널이다 (Phase 17 D-44). 기본값은 no-op 이라
  /// 기존 생성부 · 테스트는 바뀌지 않는다.
  SettingsRepository({
    required fb.FirebaseAuth auth,
    required FirebaseFunctions functions,
    CrashlyticsService crashlytics = const CrashlyticsService(
      null,
      isEnabled: false,
    ),
  }) : _auth = auth,
       _functions = functions,
       _crashlytics = crashlytics;

  final fb.FirebaseAuth _auth;
  final FirebaseFunctions _functions;
  final CrashlyticsService _crashlytics;

  /// `deleteUserAccount` callable 호출 타임아웃 — 10 초.
  static const Duration _kDeleteTimeout = Duration(seconds: 10);

  /// 사용자 계정을 탈퇴 처리한다 (Phase 16 D-06 / D-07 / D-08).
  ///
  /// 흐름:
  /// 1. `_auth.currentUser` null 검증 → null 이면 [UnauthenticatedException].
  /// 2. `getIdToken(true /* forceRefresh */)` — fresh ID Token 발급 (D-06).
  ///
  ///    **WR-04 정정:** `forceRefresh` 는 revoked 토큰 차단과 커스텀 클레임
  ///    최신화를 위한 것이며 `auth_time` 은 **갱신하지 않는다**. `auth_time`
  ///    은 실제 인증(sign-in / reauthenticate) 시각이므로, 서버
  ///    (`functions/src/auth/delete_user_account.ts` → `assertFreshAuth`) 의
  ///    300초 boundary 통과는 실제 재인증으로만 가능하다. 이 사실을 뒤집어
  ///    "이미 fresh 하니 reauth gate 는 불필요" 로 판단하면 D-07 재인증
  ///    의무가 무력화된다.
  ///
  ///    발급 실패 (네트워크 단절 / `user-token-expired`) 는 raw
  ///    [fb.FirebaseAuthException] 으로 새지 않고 [NoInternetConnection] /
  ///    [ReauthenticationRequiredException] 으로 매핑된다 (WR-03). 반환값이
  ///    null/빈 문자열이면 [ReauthenticationRequiredException] (WR-20).
  /// 3. `deleteUserAccount` callable 호출 ({'idToken': idToken} payload).
  /// 4. FirebaseFunctionsException 매핑 — [_mapDeleteError] 참조
  ///    (재인증 reason · App Check 차단 · 사진 삭제 실패 · code switch 순).
  ///
  /// **PII invariant (S5 sentinel / T-16-NEW-07):** idToken 본문 / email 본문
  /// 모두 logger payload 에 절대 전파되지 않는다. catch path 의 debugPrint 는
  /// FirebaseFunctionsException 의 code 만 노출한다.
  Future<void> requestAccountDeletion() async {
    final user = _auth.currentUser;
    if (user == null) {
      throw const UnauthenticatedException();
    }
    // WR-03: getIdToken 을 try 밖에 두면 네트워크 단절 / `user-token-expired`
    // 시 raw FirebaseAuthException 이 그대로 상류로 새어 _mapDeleteError 를
    // 타지 않는다 → 다이얼로그의 원인별 문구 분기가 generic 으로 collapse 된다.
    final String? idToken;
    try {
      idToken = await user.getIdToken(true /* forceRefresh */);
    } on fb.FirebaseAuthException catch (e) {
      throw e.code == 'network-request-failed'
          ? NoInternetConnection(cause: e)
          : ReauthenticationRequiredException(cause: e);
    }
    // WR-20: firebase_auth 6.x 의 시그니처는 `Future<String?> getIdToken(...)`
    // 다. null 을 그대로 실어 보내면 서버가 `invalid-argument` 로 거절하고
    // 그 코드는 _mapDeleteError 의 default arm (UnknownException) 을 타서
    // "회원탈퇴에 실패했습니다" 로 뭉개진다 — 실제 원인(세션/토큰 부재)과
    // 반대 방향의 안내다. 원인대로 재인증 경로로 보낸다.
    if (idToken == null || idToken.isEmpty) {
      throw const ReauthenticationRequiredException();
    }
    try {
      await _functions
          .httpsCallable(
            'deleteUserAccount',
            options: HttpsCallableOptions(timeout: _kDeleteTimeout),
          )
          // WR-17: payload 를 손으로 만들지 않고 도메인 모델을 반드시 경유
          // 한다. 정의만 있고 호출자 0 이던 상태에서는 서버가 필드를 추가해도
          // 모델이 조용히 낡고 컴파일러 경고도 없었다.
          .call<Object?>(DeleteUserRequest(idToken: idToken).toJson());
    } on FirebaseFunctionsException catch (e) {
      // PII invariant: code 만 노출, message / details 본문 비전파.
      if (kDebugMode) {
        debugPrint(
          'SettingsRepository.requestAccountDeletion: callable fail '
          'code=${e.code}',
        );
      }
      throw _mapDeleteError(e);
    }
  }

  /// FirebaseFunctionsException 을 [AppException] 으로 매핑한다.
  ///
  /// 판정 순서 (Phase 17 D-24 정정 · D-43 · D-40 — 앞 단계가 이긴다):
  /// 1. `unauthenticated` + `details.reason == 'reauthentication_required'` →
  ///    [ReauthenticationRequiredException] (서버 `assertFreshAuth` 5분
  ///    boundary 초과 · idToken 검증 실패).
  /// 2. `classifyAppCheckRejection` — SDK 계층 거부(App Check 차단 · 무효 ID
  ///    token)면 [AppCheckFailedException] + Crashlytics non-fatal 1회
  ///    (reason `app_check_rejected_deleteUserAccount` · D-44). 재로그인으로
  ///    보내지 않는다(D-42).
  /// 3. `unavailable` + `details.reason == 'storage_cleanup_failed'` →
  ///    [ServiceUnavailable] (plan 17-05 서버가 Storage 선삭제 실패 시 계정을
  ///    지우지 않고 돌려주는 거부 — 재시도로 해소된다).
  /// 4. 기존 code switch:
  ///    - `unauthenticated` (reason 없음 · 서버 `errorUnauthenticated`) /
  ///      `permission-denied` (idToken uid 불일치) →
  ///      [ReauthenticationRequiredException]
  ///    - `unavailable` / `deadline-exceeded` → [NoInternetConnection]
  ///    - `resource-exhausted` → [TooManyRequests]
  ///    - 그 외 (`internal`, `unknown` 등) → [UnknownException]
  ///
  /// 서버 코드는 바꾸지 않는다 — 판별은 `code` + `details.reason` 만 본다
  /// (서버 taxonomy message 로 분기하지 않는다 · IN-04).
  ///
  /// **taxonomy 정렬 (Phase 16 G-16-A6-2 / IN-02 정정):**
  /// `unavailable` / `deadline-exceeded` → [NoInternetConnection] 은
  /// `AuthRepository._mapFunctionsException` 과 동일하나,
  /// `resource-exhausted` → [TooManyRequests] arm 은 **본 매퍼에만 있다**
  /// (auth 쪽은 default `ServiceUnavailable` 로 흡수). 3 코드 중 2 코드만
  /// 일치하므로 "완전 동일" 이 아니다.
  ///
  /// **하류 계약 (WR-03 · Phase 17 UI-SPEC (A) · (W)):**
  /// `WithdrawalConfirmationDialog` · 탈퇴 진행 화면이 본 매퍼의 서브타입을
  /// `resolveWithdrawalFailureMessage` 로 원인별 SnackBar 문구로 렌더한다 —
  /// [AppCheckFailedException] 은 `errorAppCheckFailed`,
  /// [NetworkException] 계열 / [TooManyRequests] / [ServiceUnavailable] 는
  /// `withdrawalFailureTransient`, 그 외는 `withdrawalFailure`. 따라서 arm 을
  /// 넓히거나 좁힐 때 dialog 의 문구 분기를 함께 확인할 것.
  AppException _mapDeleteError(FirebaseFunctionsException e) {
    final details = e.details;
    // 1. 서버가 reason 으로 지목한 재인증 필요 — helper 보다 먼저 판정한다.
    if (e.code == 'unauthenticated' &&
        details is Map &&
        details['reason'] == 'reauthentication_required') {
      return ReauthenticationRequiredException(cause: e);
    }
    // 2. Phase 17 D-43 — SDK 계층 거부(App Check 차단)는 재로그인이 아니다.
    // 호출 머리(helper · 대상 · callable 이름)를 한 줄로 유지해 helper 경유
    // 지점을 grep 한 번으로 계수할 수 있게 한다(plan 17-11 verify).
    // dart format off
    final appCheck = classifyAppCheckRejection(e, callable: 'deleteUserAccount',
        crashlytics: _crashlytics);
    // dart format on
    if (appCheck != null) return appCheck;
    // 3. Phase 17 D-40 — 사진(Storage) 선삭제 실패. 계정은 그대로이므로
    //    재시도 안내(transient)로 보낸다.
    if (e.code == 'unavailable' &&
        details is Map &&
        details['reason'] == 'storage_cleanup_failed') {
      return ServiceUnavailable(cause: e);
    }
    return switch (e.code) {
      'unauthenticated' ||
      'permission-denied' => ReauthenticationRequiredException(cause: e),
      // auth_repository._mapFunctionsException 과 동일 taxonomy — 서비스 도달
      // 실패는 일시 오류로 안내해 재시도를 유도한다.
      'unavailable' || 'deadline-exceeded' => NoInternetConnection(cause: e),
      // 2026-09-07 실측: dev Cloud Run 할당량 차단(resource-exhausted)이
      // "회원탈퇴에 실패했습니다"(UnknownException) 로 표시되어 원인 오인을
      // 유발했다 — 재시도 가능한 rate-limit 으로 분리한다.
      'resource-exhausted' => TooManyRequests(cause: e),
      _ => UnknownException(cause: e),
    };
  }
}

/// [SettingsRepository] 의 단일 인스턴스를 제공한다 (Phase 16 D-06).
@Riverpod(keepAlive: true)
SettingsRepository settingsRepository(Ref ref) {
  return SettingsRepository(
    auth: ref.watch(firebaseAuthProvider),
    functions: ref.watch(firebaseFunctionsProvider),
    crashlytics: ref.watch(crashlyticsServiceProvider),
  );
}
