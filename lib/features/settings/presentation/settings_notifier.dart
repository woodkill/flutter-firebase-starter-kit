// Phase 16 Plan 16-06 / D-05~D-08 — SettingsNotifier 본체.
//
// 탈퇴 진행 상태 (AsyncValue<void>) 를 관리하는 Riverpod controller.
// requestAccountDeletion 호출 흐름:
// 1. state = AsyncValue.loading()
// 2. SettingsRepository.requestAccountDeletion() 호출
// 3. 성공: state = AsyncValue.data(null) → AuthRepository.signOutAndResetOnboarding() 트리거
// 4. 실패: state = AsyncValue.error(e, st)
//
// signOutAndResetOnboarding 후 router 의 authRedirect 가 자동으로 `/onboarding` 으로 reset.
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../auth/data/auth_repository.dart';
import '../data/settings_repository.dart';

part 'settings_notifier.g.dart';

/// 사용자 설정 화면의 상태 관리자 (Phase 16 D-06).
///
/// 탈퇴 진행 상태 (`AsyncValue<void>`) 를 노출하며, UI 는 본 Notifier 의
/// AsyncValue 를 ref.listen 으로 구독하여 success/error 분기를 처리한다.
///
/// **Plan 16-06 Task 6.1 (D-06):** `requestAccountDeletion()` 본체 채움.
@riverpod
class SettingsNotifier extends _$SettingsNotifier {
  @override
  AsyncValue<void> build() {
    return const AsyncValue<void>.data(null);
  }

  /// 사용자 탈퇴를 요청한다 (Phase 16 D-06 / D-07 / D-08).
  ///
  /// 흐름:
  /// 1. state = [AsyncValue.loading].
  /// 2. [SettingsRepository.requestAccountDeletion] 호출
  ///    (fresh ID Token 발급 + deleteUserAccount callable).
  /// 3. 성공: state = [AsyncValue.data]`(null)` +
  ///    [AuthRepository.signOutAndResetOnboarding] 호출 (onboardingSeen=false
  ///    reset + router 의 authRedirect 가 `/onboarding` 으로 자동 reset).
  /// 4. 실패: state = [AsyncValue.error]`(e, st)` — UI 가 ref.listen 으로
  ///    `ReauthenticationRequiredException` / `UnknownException` 분기 처리.
  Future<void> requestAccountDeletion() async {
    state = const AsyncValue<void>.loading();
    try {
      await ref.read(settingsRepositoryProvider).requestAccountDeletion();
      // 성공 — signOutAndResetOnboarding 트리거 (onboardingSeen=false reset +
      // router 의 authRedirect 가 /onboarding 으로 자동 redirect). 단독 signOut()
      // 은 onboardingSeen=true snapshot 유지로 /home 안착 (auth_repository 1160~).
      await ref.read(authRepositoryProvider).signOutAndResetOnboarding();
      state = const AsyncValue<void>.data(null);
    } on Object catch (e, st) {
      state = AsyncValue<void>.error(e, st);
    }
  }
}
