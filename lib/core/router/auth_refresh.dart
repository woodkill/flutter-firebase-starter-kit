import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:flutter/foundation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../providers/firebase_providers.dart';

part 'auth_refresh.g.dart';

/// `resolveAuthRedirect` 가 읽는 인증 상태 4종을 담는 값 스냅샷.
///
/// Dart 3 record 는 구조적 `==` 를 제공하므로, `userChanges()` 가 흘리는
/// 서로 다른 [fb.User] 인스턴스라도 네 필드가 같으면 동일 스냅샷으로 판정된다.
///
/// `email` 을 포함하는 이유: `resolveAuthRedirect` 의 `hasVerifiableEmail` 이
/// 이 값으로 분기 (4) 이메일 검증 게이트의 적용 여부를 결정한다. email 을 빼면
/// "email 없는 정식 사용자(Facebook email 권한 거부 등) → 이후 이메일 연결"
/// 전이에서 uid/emailVerified/isAnonymous 가 모두 그대로라 통지가 삼켜지고,
/// `/verify-email` 게이트가 영영 발동하지 않는다.
typedef AuthSnapshot = ({
  String uid,
  String? email,
  bool emailVerified,
  bool isAnonymous,
});

/// [AuthRefresh] 가 노출하는 불변 state (quick 260920-b28).
///
/// 세 필드 모두 구조적 `==` 대상이며, Riverpod 의 기본 `updateShouldNotify`
/// (state `!=` 일 때만 통지 — riverpod 3.4.3 `lib/src/core/element.dart:551`)
/// 가 곧 Phase 9 UAT Gap 2 의 distinct 가드다. 손으로 짠 sentinel 비교는
/// 필요 없다.
///
/// - [snapshot] — 가장 최근 emit 의 인증 스냅샷. `null` 은 미인증.
/// - [hasEmitted] — 스트림이 한 번이라도 emit 했는지. **초기 state 와 "최초
///   `null` emit 결과" 를 값으로 구분하는 유일한 수단이다.** 이 필드가 없으면
///   최초 `null` emit 이 초기값과 같아 통지가 삼켜지고, 앱 기동 직후 GoRouter
///   의 첫 redirect 평가가 통째로 사라진다.
/// - [revision] — [AuthRefresh.triggerRedirect] 강제 경로의 단조 증가 카운터.
typedef AuthRefreshState = ({
  AuthSnapshot? snapshot,
  bool hasEmitted,
  int revision,
});

/// 미인증 · 미emit 상태의 초기 [AuthRefreshState].
const AuthRefreshState initialAuthRefreshState = (
  snapshot: null,
  hasEmitted: false,
  revision: 0,
);

/// 사용자 변경 스트림을 **불변 state** 로 노출하는 notifier (quick 260920-b28).
///
/// [fb.FirebaseAuth.userChanges] 를 구독해 emit 마다 [AuthRefreshState] 를
/// 교체한다. `authStateChanges()` 대신 `userChanges()` 를 쓰므로 credential
/// linking(익명→정식 승격)에서도 상태가 바뀐다.
///
/// **GoRouter 배선:** 본 notifier 는 [Listenable] 을 값으로 반환하지 않는다
/// (riverpod_lint `unsupported_provider_value` 의 규칙 의도). GoRouter 가
/// 요구하는 `refreshListenable` 은 `appRouter` 가 직접 만들어 소유 · dispose
/// 하고, `ref.listen(authRefreshProvider, …)` 로 값을 올린다 — 그 Listenable
/// 은 router 의 구현 세부다.
///
/// **distinct 가드 (Phase 9 UAT Gap 2):** `userChanges()` 는 ID 토큰 갱신마다
/// 인증 상태가 전혀 바뀌지 않은 이벤트를 흘린다. 이를 그대로 통지하면 GoRouter
/// 가 동일한 입력으로 `resolveAuthRedirect` 를 수십 회 재평가한다. 네 필드가
/// 직전과 동일한 재emit 은 state 가 `==` 이므로 Riverpod 이 흡수한다. 단 두
/// 가지는 **항상** 통지된다 — (1) 최초 emit ([AuthRefreshState.hasEmitted] 가
/// `false` → `true` 로 바뀌므로 값이 `null` 이어도 통과), (2) [triggerRedirect]
/// 강제 호출([AuthRefreshState.revision] 증가).
@Riverpod(keepAlive: true)
class AuthRefresh extends _$AuthRefresh {
  @override
  AuthRefreshState build() {
    final isInitialized = ref.watch(isFirebaseInitializedProvider);
    // 분기는 "어느 스트림을 구독할 것인가" 까지만 한다. 구독 · 정리를 한 경로로
    // 합쳐 두면 WR-04 의 원래 버그(초기화 실패 분기에서 정리 누락) 자체가
    // 성립하지 않는다.
    final stream = isInitialized
        ? ref.watch(firebaseAuthProvider).userChanges()
        : const Stream<fb.User?>.empty();
    final subscription = stream.listen(_acceptUser, onError: _absorbError);
    ref.onDispose(subscription.cancel);
    return initialAuthRefreshState;
  }

  /// 스트림 emit 을 state 로 반영한다.
  ///
  /// 중복 흡수는 여기서 손으로 비교하지 않는다 — Riverpod 의 기본
  /// `updateShouldNotify` 가 담당한다.
  void _acceptUser(fb.User? user) {
    final AuthSnapshot? next = user == null
        ? null
        : (
            uid: user.uid,
            email: user.email,
            emailVerified: user.emailVerified,
            isAnonymous: user.isAnonymous,
          );
    if (kDebugMode) {
      // WARNING #18: uid 원문 대신 hashCode 로 PII 완화.
      final uidHash = user?.uid.hashCode.toString() ?? 'null';
      debugPrint('AuthRefresh: userChanges emit (uidHash=$uidHash)');
    }
    state = (snapshot: next, hasEmitted: true, revision: state.revision);
  }

  /// 스트림 에러를 기록만 하고 흡수한다 (WR-03).
  ///
  /// onError 가 없으면 `userChanges` 의 error 이벤트가 zone uncaught error 로
  /// 승격되어 앱 전체 에러 핸들러를 때린다 (`cancelOnError` 기본값이 false 라
  /// 구독 자체는 살아남는다). 에러의 Crashlytics 보고 책임은
  /// `authUserObserver` 가 진다 — 본 notifier 는 Crashlytics 의존성을 갖지
  /// 않는다.
  void _absorbError(Object e) {
    if (kDebugMode) {
      // PII 차단: 에러 본문 대신 타입만 기록한다.
      debugPrint('AuthRefresh: userChanges error (${e.runtimeType})');
    }
  }

  /// GoRouter redirect 재평가를 강제 트리거한다.
  ///
  /// Firebase SDK 의 `authStateChanges()` 스트림이 `reload()` 후
  /// `emailVerified` 변경을 emit 하지 않는 제한(FlutterFire Issue #8777)을
  /// 우회하기 위해, 외부에서 명시적으로 redirect 재평가를 요청할 때 사용한다.
  ///
  /// [AuthRefreshState.revision] 을 1 올려 distinct 가드(Phase 9 UAT Gap 2)를
  /// **항상** 통과한다. 여기에 스냅샷 비교를 끼워 넣으면 `reload()` 직후 검증
  /// 완료 상태가 라우터에 전달되지 않는 원래 버그가 되살아난다.
  void triggerRedirect() {
    state = (
      snapshot: state.snapshot,
      hasEmitted: state.hasEmitted,
      revision: state.revision + 1,
    );
  }
}
