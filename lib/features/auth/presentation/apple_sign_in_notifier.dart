import 'dart:async';

import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/error/result.dart';
import '../data/auth_repository.dart';

part 'apple_sign_in_notifier.g.dart';

/// Apple 로그인 상태를 관리하는 [AsyncNotifier] (D-03).
///
/// Phase 7 [GoogleSignInNotifier] 구조를 그대로 미러링한다.
/// autoDispose이므로 화면 이탈 시 상태가 초기화된다.
/// 성공 후 화면 이동은 resolveAuthRedirect가 담당한다 (D-05).
///
/// **build() 시그니처 (R7 / Phase 13 D-42 invariant — 7 소셜 notifier 공통):**
/// `FutureOr<void> build()` 를 유지한다. Riverpod 3.x build inference 규칙상
/// `void build()` 로 바꾸면 generator 가 sync `$Notifier<void>` 가족으로
/// 강등되어 AsyncNotifier API 자체가 깨진다 (Phase 13 Plan 13-04
/// T-13-NAVER-NOTIFIER-R7-01 lesson). 회귀 가드 테스트 + 본 docstring 으로
/// invariant 를 강제한다 — IN-04 정정(Phase 09 review): 이 경고는 naver /
/// line / yahoojp 3개 파일에만 있었으나 회귀 조건은 7개 모두 동일하므로
/// 전 파일에 일치시킨다.
@riverpod
class AppleSignInNotifier extends _$AppleSignInNotifier {
  @override
  FutureOr<void> build() {
    // 초기 상태: AsyncData(null)
  }

  /// Apple 로그인을 수행한다.
  ///
  /// 취소(null) 시 state를 [AsyncData]로 유지하여 조용히 무시 (D-09). 이 동작은 7 provider 가 문자 단위로 동일하며,
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
  /// [AsyncError] 로 되돌린 뒤 `rethrow` 한다. 예외는 여전히 호출자에게
  /// 전파되지만, state 가 [AsyncLoading] 에 머물러 AuthInProgressOverlay 의
  /// AbsorbPointer 가 화면을 영구히 덮는 일은 없다. 이 가드 역시 7 provider 가
  /// 문자 단위로 동일하다 — 회귀 가드는
  /// `social_sign_in_notifier_loading_guard_test.dart`.
  Future<void> signInWithApple() async {
    state = const AsyncLoading<void>();
    try {
      final result = await ref.read(authRepositoryProvider).signInWithApple();
      if (!ref.mounted) return;

      if (result == null) {
        state = const AsyncData<void>(null);
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
    }
  }
}
