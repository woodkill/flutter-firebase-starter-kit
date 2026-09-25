// Phase 14 — see ROADMAP.md
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/error/result.dart';
import '../data/auth_repository.dart';

part 'line_sign_in_notifier.g.dart';

/// LINE 로그인 상태를 관리하는 [AsyncNotifier] (Phase 14, SOCL-03).
///
/// Phase 7 [GoogleSignInNotifier] / Phase 8 [AppleSignInNotifier] / Phase 9
/// [FacebookSignInNotifier] / Phase 12 [KakaoSignInNotifier] / Phase 13
/// [NaverSignInNotifier] 구조를 그대로 미러링한다. autoDispose 이므로 화면
/// 이탈 시 상태가 초기화된다. 성공 후 화면 이동은 resolveAuthRedirect 가 담당한다.
///
/// **race-fix invariant (Pitfall 8):** 본 Notifier 는 race-guard begin/end 를
/// 직접 호출하지 않는다. 단일 진실원은 [AuthRepository.signInWithLine] 의
/// try-finally (Plan 14-05 Task 1).
///
/// **build() 시그니처 (R7 / Phase 13 D-42 carry-forward):**
/// `FutureOr<void> build()` 유지 — Riverpod 3.x build inference 규칙상
/// `void build()` 로 변경 시 generator 가 sync `$Notifier<void>` 가족으로
/// 강등되며 AsyncNotifier API 자체가 깨진다 (Phase 13 Plan 13-04
/// T-13-NAVER-NOTIFIER-R7-01 lesson). 회귀 가드 테스트 + docstring 으로
/// invariant enforce.
///
/// **Custom Token 이므로 emailVerified=true 가 자동 부여**: Apple / Kakao /
/// Naver 동일 경로. resolveAuthRedirect 는 home 으로 자동 이동하며 `/verify-email`
/// 우회.
@riverpod
class LineSignInNotifier extends _$LineSignInNotifier {
  @override
  FutureOr<void> build() {
    // 초기 상태: AsyncData(null) — 회귀 가드 테스트가 verify
    // (T-14-LINE-NOTIFIER-R7-01).
  }

  /// LINE 로그인을 수행한다.
  ///
  /// 취소(null) 시 state 를 [AsyncData] 로 유지하여 조용히 무시 (D-LINE-21). 이 동작은 6 provider 가 문자 단위로 동일하며,
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
  /// AbsorbPointer 가 화면을 영구히 덮는 일도 없다. 이 가드 역시 6 provider 가
  /// 문자 단위로 동일하다 — 회귀 가드는
  /// `social_sign_in_notifier_loading_guard_test.dart`.
  /// 그 회귀 가드가 덮는 범위는 **두 축 모두**다 — provider 생성 시의 동기
  /// `Error` throw 와, repository 메서드 호출의 비동기 `Exception` throw
  /// (16.4 code review IN-02 — 종전에는 앞 축 하나뿐이었다).
  ///
  /// **payload 계약 확장 (16.4 code review IN-05):** 이 경로의 [AsyncError]
  /// payload 는 `Result.failure` 경로와 달리 `AppException` 이 아닐 수 있다
  /// (예: riverpod 의 `ProviderException`, repository 가 흘린 raw 예외).
  /// 두 UI surface 의 `err is AppException ? … : ServiceUnavailable(cause: err)`
  /// fallback 이 이를 흡수한다 — 그 분기는 더 이상 dead 가 아니다.
  Future<void> signInWithLine() async {
    state = const AsyncLoading<void>();
    try {
      final result = await ref.read(authRepositoryProvider).signInWithLine();
      if (!ref.mounted) return;

      if (result == null) {
        state = const AsyncData<void>(null); // D-LINE-21 silent cancel
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
