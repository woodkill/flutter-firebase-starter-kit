import 'dart:async';

import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/error/result.dart';
import '../data/auth_repository.dart';

part 'kakao_sign_in_notifier.g.dart';

/// Kakao 로그인 상태를 관리하는 [AsyncNotifier] (Phase 12 D-27).
///
/// Phase 7 [GoogleSignInNotifier] / Phase 8 [AppleSignInNotifier] / Phase 9
/// [FacebookSignInNotifier] 구조를 그대로 미러링한다. autoDispose이므로 화면
/// 이탈 시 상태가 초기화된다. 성공 후 화면 이동은 resolveAuthRedirect 가 담당한다.
///
/// **race-fix invariant (D-15, Pitfall 8):** 본 Notifier 는 race-guard
/// begin/end 를 직접 호출하지 않는다. 단일 진실원은
/// [AuthRepository.signInWithKakao] 의 try-finally (Plan 12-03).
///
/// **Custom Token 이므로 emailVerified=true 가 자동 부여**: Apple 동일 경로
/// (UI-SPEC Kakao success state). resolveAuthRedirect 는 home 으로 자동 이동하며
/// `/verify-email` 우회.
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
class KakaoSignInNotifier extends _$KakaoSignInNotifier {
  @override
  FutureOr<void> build() {
    // 초기 상태: AsyncData(null)
  }

  /// Kakao 로그인을 수행한다.
  ///
  /// 취소(null) 시 state 를 [AsyncData] 로 유지하여 조용히 무시 (D-05). 이 동작은 7 provider 가 문자 단위로 동일하며,
  /// 최초 결정 **D-06** 의 provider 별 인스턴스다 (IN-01 정정 — Phase 09
  /// review: 동일 동작이 6개의 서로 다른 ID 로 불리고 있었다).
  /// 성공 시 [AsyncData]. 실패 시 [AsyncError] 로 전환되어 LoginScreen 의
  /// ref.listen 에서 FormErrorBanner 로 렌더링된다. Phase 16.1 에서 소셜
  /// 섹션을 함께 담던 구 가입 화면이 삭제됐고, LoginPromptSheet 의
  /// ref.listen 은 성공 분기만 처리한다.
  Future<void> signInWithKakao() async {
    state = const AsyncLoading<void>();
    final result = await ref.read(authRepositoryProvider).signInWithKakao();
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
  }
}
