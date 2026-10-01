// Phase 17 Plan 17-10 — 계정 대표 이메일 mirror callable client (D-26).
//
// `authUserObserver` 가 정식 사용자 세션 시작마다 [AccountEmailMirrorClient.mirror]
// 를 fire-and-forget 으로 1회 부른다. 서버 `mirrorAccountEmail` 은 입력 0 —
// 검증된 ID token 의 email · email_verified 만 `users/{uid}` 에 쓴다.
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/providers/firebase_providers.dart';

part 'account_email_mirror_client.g.dart';

/// `mirrorAccountEmail` Cloud Function 을 부르는 fire-and-forget client.
///
/// - 요청 본문 없이 호출한다 — 이메일 값은 서버가 ID token 에서만 읽는다
///   (클라이언트 입력값 금지 · D-26).
/// - 실패(네트워크 · App Check · dev cold start 503 · 타임아웃)는 전부 삼킨다.
///   Crashlytics 에 기록하지 않는다 — 세션마다 부르는 호출이라 cold start
///   실패가 Crashlytics 를 오염시킨다 (RESEARCH R-03 (5)).
/// - 사용자에게 보이는 표면이 없어 D-43 오류 표면 목록 밖이다 (UI 없음).
class AccountEmailMirrorClient {
  /// [AccountEmailMirrorClient] 를 생성한다.
  AccountEmailMirrorClient(this._functions);

  final FirebaseFunctions _functions;

  /// callable 응답 대기 상한 — 10 초.
  static const Duration _kMirrorTimeout = Duration(seconds: 10);

  /// 서버에 계정 대표 이메일 mirror 를 요청한다. 실패해도 throw 하지 않는다.
  ///
  /// debug 빌드에서만 예외 **타입 이름**을 debugPrint 한다 — 서버 message ·
  /// details 에 PII 가 섞일 수 있어 본문은 싣지 않는다.
  Future<void> mirror() async {
    try {
      await _functions
          .httpsCallable('mirrorAccountEmail')
          .call<void>()
          .timeout(_kMirrorTimeout);
    } on Object catch (e) {
      if (kDebugMode) {
        debugPrint('mirrorAccountEmail 실패 (무시): ${e.runtimeType}');
      }
    }
  }
}

/// [AccountEmailMirrorClient] 를 제공한다 (Phase 17 D-26).
///
/// Firebase 미초기화 상태에서는 읽지 않는다 — 호출자 `authUserObserver` 가
/// `isFirebaseInitializedProvider` 가드 뒤에서만 읽는다.
@Riverpod(keepAlive: true)
AccountEmailMirrorClient accountEmailMirrorClient(Ref ref) {
  return AccountEmailMirrorClient(ref.watch(firebaseFunctionsProvider));
}
