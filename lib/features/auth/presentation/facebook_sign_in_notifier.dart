import 'dart:async';

import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/error/result.dart';
import '../data/auth_repository.dart';

part 'facebook_sign_in_notifier.g.dart';

/// Facebook 로그인 상태를 관리하는 [AsyncNotifier] (D-01).
///
/// Phase 7 [GoogleSignInNotifier] / Phase 8 [AppleSignInNotifier] 구조를
/// 그대로 미러링한다. autoDispose이므로 화면 이탈 시 상태가 초기화된다.
/// 성공 후 화면 이동은 authRedirect가 담당한다.
@riverpod
class FacebookSignInNotifier extends _$FacebookSignInNotifier {
  @override
  FutureOr<void> build() {
    // 초기 상태: AsyncData(null)
  }

  /// Facebook 로그인을 수행한다.
  ///
  /// 취소(null) 시 state를 [AsyncData]로 유지하여 조용히 무시 (D-09).
  /// 성공 시 [AsyncData]. 실패 시 [AsyncError]로 전환되어
  /// LoginScreen/SignupScreen의 ref.listen에서 FormErrorBanner로
  /// 렌더링된다.
  Future<void> signInWithFacebook() async {
    state = const AsyncLoading<void>();
    final result = await ref.read(authRepositoryProvider).signInWithFacebook();
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
