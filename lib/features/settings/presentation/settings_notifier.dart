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

import '../../../core/auth/provider_id.dart';
import '../../../core/error/app_exception.dart';
import '../../../core/error/result.dart';
import '../../auth/data/auth_repository.dart';
import '../../auth/domain/user.dart';
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

  /// 로그인된 사용자에게 [provider] 계정을 proactive 하게 연결한다
  /// (Phase 16 16-11 / Surface D / SOCL-12 / UAT A6·A7).
  ///
  /// [provider] 종류에 따라 16-10/16-09 의 proactive link 메서드를 dispatch
  /// 한다:
  /// - native (google/apple/facebook) →
  ///   [AuthRepository.linkGoogleCredential] / [AuthRepository.linkAppleCredential]
  ///   / [AuthRepository.linkFacebookCredential].
  /// - Custom Token (kakao/line/yahoojp) →
  ///   [AuthRepository.linkCustomTokenProviderArm].
  /// - naver → deployed callable OIDC 미지원 ([AccountLinkOutcome.unsupported]
  ///   — sheet `_linkCustomToken` 의 naver graceful 분기 mirror, Phase 17+
  ///   carry-forward).
  /// - email → Surface D 에서 제외 (mockup §0 EXCLUDE) — 본 메서드에 도달 시
  ///   [AccountLinkOutcome.unsupported] (방어적 차단, UI 후보 집합에 email
  ///   미포함).
  ///
  /// 진행 중 [state] 를 [AsyncValue.loading] 으로 설정해 위젯이 link in-progress
  /// 오버레이를 표시할 수 있게 하고, 종료 시 [AsyncValue.data]`(null)` 로
  /// 복귀한다 (성공/실패/취소 모두 — state 자체는 결과 분기에 사용하지 않음).
  ///
  /// 반환: 위젯이 결과별 UI (성공 snackbar / reauth 라우팅 / already-linked
  /// 안내 / 취소 no-op) 를 분기하기 위한 [AccountLinkOutcome]. link 성공 시
  /// `currentUserProvider` 가 Firestore linkedProviders stream 으로 자동 refresh
  /// 되어 해당 provider 버튼이 available 집합에서 제거된다.
  Future<AccountLinkOutcome> linkProvider(AccountProvider provider) async {
    // naver / email 은 proactive link 미지원 (deployed callable OIDC 부재 /
    // Surface D email EXCLUDE) — graceful 안내 (크래시 0).
    if (provider == AccountProvider.naver ||
        provider == AccountProvider.email) {
      return AccountLinkOutcome.unsupported;
    }

    state = const AsyncValue<void>.loading();
    try {
      final repo = ref.read(authRepositoryProvider);
      final Result<User>? result = switch (provider) {
        AccountProvider.google => await repo.linkGoogleCredential(),
        AccountProvider.apple => await repo.linkAppleCredential(),
        AccountProvider.facebook => await repo.linkFacebookCredential(),
        AccountProvider.kakao ||
        AccountProvider.line ||
        AccountProvider.yahoojp => await repo.linkCustomTokenProviderArm(
          targetProvider: provider,
        ),
        // naver / email 은 위에서 early-return — exhaustive switch 보강.
        AccountProvider.naver ||
        AccountProvider.email => null,
      };
      state = const AsyncValue<void>.data(null);

      // 사용자 SDK 취소 (null) — no-op.
      if (result == null) return AccountLinkOutcome.cancelled;
      return switch (result) {
        Success<User>() => AccountLinkOutcome.success,
        Failure<User>(:final exception) =>
          exception is ReauthenticationRequiredException
              ? AccountLinkOutcome.reauthRequired
              : AccountLinkOutcome.alreadyLinkedOrFailed,
      };
    } on Object catch (_) {
      // 방어적 — repository 가 Result 로 흡수하므로 도달 거의 없음.
      state = const AsyncValue<void>.data(null);
      return AccountLinkOutcome.alreadyLinkedOrFailed;
    }
  }
}

/// proactive 계정 연결 결과 분기 (Phase 16 16-11 / Surface D).
///
/// [SettingsNotifier.linkProvider] 가 반환하며, 위젯이 결과별 UI
/// (성공 snackbar / reauth 라우팅 / already-linked 안내 / 취소 no-op /
/// 미지원 graceful) 를 분기하는 데 사용한다.
enum AccountLinkOutcome {
  /// link 성공 — 성공 snackbar + linkedProviders 자동 refresh.
  success,

  /// 사용자 SDK 취소 (null) — no-op (snackbar 0, 버튼 유지).
  cancelled,

  /// 재인증 필요 (`requires-recent-login`) — 재로그인 라우팅 (D-06 mirror).
  reauthRequired,

  /// 이미 연결됨 / 기타 link 실패 — graceful 안내 SnackBar (크래시 0).
  alreadyLinkedOrFailed,

  /// proactive link 미지원 (naver: deployed callable OIDC 부재 / email:
  /// Surface D EXCLUDE) — graceful 안내 SnackBar.
  unsupported,
}
