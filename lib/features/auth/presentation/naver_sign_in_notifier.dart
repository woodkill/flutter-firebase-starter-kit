// Phase 13 — see ROADMAP.md
// Phase 16.4 — see ROADMAP.md (레버 5 판정용 lifecycle 임시 로그 · plan 06 이
// 존치/제거 확정)
import 'dart:async';

import 'package:flutter/foundation.dart' show debugPrint, kDebugMode;
import 'package:flutter/widgets.dart'
    show AppLifecycleListener, AppLifecycleState;
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/error/result.dart';
import '../data/auth_repository.dart';

part 'naver_sign_in_notifier.g.dart';

/// Naver 로그인 상태를 관리하는 [AsyncNotifier] (Phase 13 — see ROADMAP.md, D-26 / D-44).
///
/// Phase 7 [GoogleSignInNotifier] / Phase 8 [AppleSignInNotifier] / Phase 9
/// [FacebookSignInNotifier] / Phase 12 [KakaoSignInNotifier] 구조를 그대로
/// 미러링한다. autoDispose 이므로 화면 이탈 시 상태가 초기화된다. 성공 후 화면
/// 이동은 resolveAuthRedirect 가 담당한다.
///
/// **race-fix invariant (Pitfall 8):** 본 Notifier 는 race-guard begin/end 를
/// 직접 호출하지 않는다. 단일 진실원은 [AuthRepository.signInWithNaver] 의
/// try-finally (Plan 13-03).
///
/// **build() 시그니처 (R7 / D-42 재정의):** `FutureOr<void> build()` 유지 —
/// Riverpod 3.x build inference 규칙상 `void build()` 로 변경 시 generator 가
/// sync `$Notifier<void>` 가족으로 강등 + AsyncNotifier API 자체가 깨진다
/// (todo `2026-05-05-r7-sibling-regression-guards.md` line 17). D-42 motivation
/// 은 회귀 가드 테스트 + docstring 으로 invariant enforce 로 재정의됨
/// (Plan 13-04 T-13-NAVER-NOTIFIER-R7-01).
///
/// **Custom Token 이므로 emailVerified=true 가 자동 부여**: Apple / Kakao 동일
/// 경로. resolveAuthRedirect 는 home 으로 자동 이동하며 `/verify-email` 우회.
@riverpod
class NaverSignInNotifier extends _$NaverSignInNotifier {
  @override
  FutureOr<void> build() {
    // 초기 상태: AsyncData(null) — 회귀 가드 테스트가 verify
    // (Plan 13-04 T-13-NAVER-NOTIFIER-R7-01).
  }

  /// Naver 로그인을 수행한다.
  ///
  /// 취소(null) 시 state 를 [AsyncData] 로 유지하여 조용히 무시 (D-45). 이 동작은 7 provider 가 문자 단위로 동일하며,
  /// 최초 결정 **D-06** 의 provider 별 인스턴스다 (IN-01 정정 — Phase 09
  /// review: 동일 동작이 6개의 서로 다른 ID 로 불리고 있었다).
  /// 성공 시 [AsyncData]. 실패 시 [AsyncError] 로 전환되어 LoginScreen 의
  /// ref.listen 에서 FormErrorBanner 로 렌더링된다. Phase 16.1 에서 소셜
  /// 섹션을 함께 담던 구 가입 화면이 삭제됐고, LoginPromptSheet 의
  /// ref.listen 은 성공 분기만 처리한다.
  ///
  /// **lifecycle 임시 로그 (Phase 16.4 — see ROADMAP.md):** 본 메서드 진행
  /// 구간에만 [AppLifecycleListener] 를 붙이고 `finally` 에서 뗀다. 커스텀탭
  /// 왕복이 앱 lifecycle 전이로 관측되는지(RESEARCH 레버 5)를 다음 실기기
  /// 실행에서 판정하기 위한 것이며, 출력은 `AppLifecycleState` 이름과 정수
  /// 카운트뿐이라 PII 표면이 없다. 레버 5 판정 후 존치 여부는 plan 06 이
  /// 정한다.
  ///
  /// **release 표면 0 (16.4 code review IN-03):** 수집한 값이 `kDebugMode`
  /// 에서만 소비되므로 **리스너 등록 자체**를 `kDebugMode` 안으로 가둔다.
  /// 종전에는 출력만 debug 였고 `WidgetsBinding` 옵서버 등록·해제는 매
  /// 호출마다 release 에서도 일어났다 — 이 킷은 템플릿으로 복사되는 코드다.
  ///
  /// **AsyncLoading 누수 가드 (16.4 code review IN-06, quick 260923-cs5):**
  /// `ref.read(authRepositoryProvider)` 가 동기 throw 하거나(provider 생성
  /// 실패) repository 호출이 예외를 흘리면 `on Object catch` 가 state 를
  /// [AsyncError] 로 되돌린 뒤 `rethrow` 한다. 예외는 여전히 호출자에게
  /// 전파되지만, state 가 [AsyncLoading] 에 머물러 AuthInProgressOverlay 의
  /// AbsorbPointer 가 화면을 영구히 덮는 일은 없다. 이 가드 역시 7 provider 가
  /// 문자 단위로 동일하다 — 회귀 가드는
  /// `social_sign_in_notifier_loading_guard_test.dart`.
  Future<void> signInWithNaver() async {
    state = const AsyncLoading<void>();

    var transitions = 0;
    var resumed = 0;
    // debug 전용 — release 에서는 null 이라 옵서버가 등록되지 않는다.
    final AppLifecycleListener? lifecycle = kDebugMode
        ? AppLifecycleListener(
            onStateChange: (AppLifecycleState appState) {
              transitions++;
              if (appState == AppLifecycleState.resumed) {
                resumed++;
              }
              debugPrint(
                'Naver lifecycle 전이: state=${appState.name} seq=$transitions',
              );
            },
          )
        : null;

    try {
      final result = await ref.read(authRepositoryProvider).signInWithNaver();
      if (!ref.mounted) return;

      if (result == null) {
        state = const AsyncData<void>(null); // D-45 silent cancel
        return;
      }

      state = switch (result) {
        Success<dynamic>() => const AsyncData<void>(null),
        Failure<dynamic>(exception: final ex) => AsyncError<void>(
          ex,
          StackTrace.current,
        ),
      };
    } on Object catch (e, st) {
      if (ref.mounted) state = AsyncError<void>(e, st);
      rethrow;
    } finally {
      if (kDebugMode) {
        debugPrint(
          'Naver lifecycle 요약: resumed=$resumed transitions=$transitions',
        );
      }
      lifecycle?.dispose();
    }
  }
}
