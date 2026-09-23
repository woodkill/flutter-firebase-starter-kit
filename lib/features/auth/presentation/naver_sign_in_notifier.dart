// Phase 13 — see ROADMAP.md
// Phase 16.4 — see ROADMAP.md (레버 5 판정용 lifecycle 임시 로그 제거됨 —
// 레버 2 채택. 취소/실패 구분은 Android 호스트 계수 + MethodChannel 이
// 담당하므로 이 파일은 7 provider 공통 모양으로 되돌아왔다)
import 'dart:async';

import 'package:flutter/foundation.dart';
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
  /// 성공 시 [AsyncData]. 실패 시 [AsyncError] 로 전환되어 **LoginScreen 과
  /// LoginPromptSheet 두 surface 모두**의 `ref.listen` 이 처리한다 —
  /// `AccountExistsWithDifferentCredential`(+ `existingProvider != null`) 은
  /// 계정 연결 시트로, 그 외는 `FormErrorBanner` 로 렌더링된다
  /// (`login_screen.dart:150` · `login_prompt_sheet.dart:156`).
  /// Phase 16.1 에서 소셜 섹션을 함께 담던 구 가입 화면은 삭제됐다
  /// (16.4 code review WR-02 — 종전 「LoginPromptSheet 의 ref.listen 은 성공
  /// 분기만 처리한다」 는 실측과 배치되는 문장이었다).
  ///
  /// **AsyncLoading 누수 가드 (16.4 code review IN-06, quick 260923-cs5):**
  /// `ref.read(authRepositoryProvider)` 가 동기 throw 하거나(provider 생성
  /// 실패) repository 호출이 예외를 흘리면 `on Object catch` 가 state 를
  /// [AsyncError] 로 되돌린 뒤 **예외를 밖으로 전파하지 않고 종료한다**
  /// (16.4 code review WR-03). 호출부 `social_button.dart` 가 반환 Future 를
  /// 버리므로, `rethrow` 하면 복구된 실패가 unhandled error 로 zone 에 올라가
  /// bootstrap 이 Crashlytics 에 `fatal: true` 로 기록한다 — 「배너로
  /// 복구했다」 와 「치명적으로 죽었다」 가 동시에 보고되는 모순이다.
  /// state 가 [AsyncLoading] 에 머물러 AuthInProgressOverlay 의
  /// AbsorbPointer 가 화면을 영구히 덮는 일도 없다. 이 가드 역시 7 provider 가
  /// 문자 단위로 동일하다 — 회귀 가드는
  /// `social_sign_in_notifier_loading_guard_test.dart`.
  Future<void> signInWithNaver() async {
    state = const AsyncLoading<void>();
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
      // 배너로 복구했으므로 fatal 이 아니다 — rethrow 하면 fire-and-forget
      // Future(`social_button.dart` 가 반환값을 버린다) 의 unhandled error 가
      // 되어 bootstrap 이 Crashlytics 에 `fatal: true` 로 올린다
      // (16.4 code review WR-03).
      // PII 표면 0 — 예외 메시지에는 이메일 · 토큰이 실릴 수 있으므로
      // `e.toString()` 이 아니라 **타입만** 찍는다.
      if (kDebugMode) {
        debugPrint('$runtimeType: ${e.runtimeType}');
      }
      return;
    }
  }
}
