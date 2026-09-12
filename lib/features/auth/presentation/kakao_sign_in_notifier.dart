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
@riverpod
class KakaoSignInNotifier extends _$KakaoSignInNotifier {
  @override
  FutureOr<void> build() {
    // 초기 상태: AsyncData(null)
  }

  /// Kakao 로그인을 수행한다.
  ///
  /// 취소(null) 시 state 를 [AsyncData] 로 유지하여 조용히 무시 (D-05).
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
