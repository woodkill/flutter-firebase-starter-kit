// Phase 16 Plan 16-06 / D-05~D-08 — SettingsRepository 본체.
//
// `deleteUserAccount` Cloud Function callable wrapper:
// - fresh ID Token 발급 (`getIdToken(true)`) — auth_time 갱신, 5분 boundary
//   baseline (D-06).
// - callable invoke + FirebaseFunctionsException 코드별 매핑
//   (unauthenticated/permission-denied → ReauthenticationRequiredException,
//   internal/그 외 → UnknownException).
// - PII invariant — idToken 본문 / email 본문 logger 비전파 (S5 sentinel).
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:flutter/foundation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/error/app_exception.dart';
import '../../../core/providers/firebase_providers.dart';

part 'settings_repository.g.dart';

/// 사용자 설정 (탈퇴 등) 관련 Repository (Phase 16 D-06).
///
/// `deleteUserAccount` Cloud Function 호출 + FirebaseFunctionsException →
/// [AppException] 매핑 + fresh ID Token 발급 (D-06 의 5분 auth_time
/// boundary baseline).
class SettingsRepository {
  /// [SettingsRepository] 를 생성한다.
  SettingsRepository({
    required fb.FirebaseAuth auth,
    required FirebaseFunctions functions,
  })  : _auth = auth,
        _functions = functions;

  final fb.FirebaseAuth _auth;
  final FirebaseFunctions _functions;

  /// `deleteUserAccount` callable 호출 타임아웃 — 10 초.
  static const Duration _kDeleteTimeout = Duration(seconds: 10);

  /// 사용자 계정을 탈퇴 처리한다 (Phase 16 D-06 / D-07 / D-08).
  ///
  /// 흐름:
  /// 1. `_auth.currentUser` null 검증 → null 이면 [UnauthenticatedException].
  /// 2. `getIdToken(true /* forceRefresh */)` — fresh ID Token 발급 (D-06).
  ///    auth_time 갱신으로 server-side 5분 boundary 통과.
  /// 3. `deleteUserAccount` callable 호출 ({'idToken': idToken} payload).
  /// 4. FirebaseFunctionsException 코드 매핑:
  ///    - `unauthenticated` / `permission-denied` →
  ///      [ReauthenticationRequiredException]
  ///    - 그 외 (`internal` 포함) → [UnknownException]
  ///
  /// **PII invariant (S5 sentinel / T-16-NEW-07):** idToken 본문 / email 본문
  /// 모두 logger payload 에 절대 전파되지 않는다. catch path 의 debugPrint 는
  /// FirebaseFunctionsException 의 code 만 노출한다.
  Future<void> requestAccountDeletion() async {
    final user = _auth.currentUser;
    if (user == null) {
      throw const UnauthenticatedException();
    }
    final idToken = await user.getIdToken(true /* forceRefresh */);
    try {
      await _functions
          .httpsCallable(
            'deleteUserAccount',
            options: HttpsCallableOptions(timeout: _kDeleteTimeout),
          )
          .call<Object?>(<String, dynamic>{'idToken': idToken});
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
  /// - `unauthenticated` / `permission-denied` →
  ///   [ReauthenticationRequiredException] (5분 boundary 초과 — 재로그인 필요)
  /// - `unavailable` / `deadline-exceeded` → [NoInternetConnection]
  /// - `resource-exhausted` → [TooManyRequests]
  /// - 그 외 (`internal`, `unknown` 등) → [UnknownException]
  ///
  /// **taxonomy 정렬 (Phase 16 G-16-A6-2):** `unavailable` /
  /// `deadline-exceeded` / `resource-exhausted` 분리는
  /// `AuthRepository._mapFunctionsException` 과 동일한 프로젝트 표준 분류다.
  AppException _mapDeleteError(FirebaseFunctionsException e) {
    return switch (e.code) {
      'unauthenticated' ||
      'permission-denied' =>
        ReauthenticationRequiredException(cause: e),
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
  );
}
