// Phase 16 Plan 16-06 / D-05~D-08 — SettingsNotifier 본체.
//
// 탈퇴 진행 상태 (AsyncValue<void>) 를 관리하는 Riverpod controller.
// requestAccountDeletion 호출 흐름 (10-REVIEW CR-01 / CR-04 이후):
// 1. state = AsyncValue.loading()
// 2. SettingsRepository.requestAccountDeletion() 호출 (서버 hard delete)
// 3. 2 가 던지면: state = AsyncValue.error(e, st) 후 종료 — 사후 정리 미수행
//    (서버 삭제가 확정되지 않았다)
// 4. 2 가 성공하면: 즉시 state = AsyncValue.data(null) (CR-04 — 성공 emit 이
//    사후 정리보다 앞선다) → 그 뒤 AuthRepository.signOutAndResetOnboarding()
//    을 best-effort 로 호출 (실패는 Crashlytics 기록만 하고 흡수)
//
// signOutAndResetOnboarding 후 router 의 resolveAuthRedirect 가 자동으로 `/onboarding` 으로 reset.
import 'package:flutter/foundation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/auth/provider_id.dart';
import '../../../core/crashlytics/crashlytics_service.dart';
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
  /// 흐름 (10-REVIEW CR-01 이후):
  /// 1. state = [AsyncValue.loading].
  /// 2. [SettingsRepository.requestAccountDeletion] 호출
  ///    (fresh ID Token 발급 + deleteUserAccount callable).
  /// 3. 2 가 던지면: state = [AsyncValue.error]`(e, st)` 후 즉시 종료 —
  ///    서버 삭제가 확정되지 않았으므로 사후 정리를 수행하지 않는다. UI 가
  ///    ref.listen 으로 `ReauthenticationRequiredException` /
  ///    `UnknownException` 분기 처리.
  /// 4. 2 가 성공하면 서버 hard delete 가 확정된 것이므로 탈퇴는 이미 성공이다.
  ///    **10-REVIEW CR-04:** 이 시점에 즉시 state = [AsyncValue.data]`(null)`
  ///    을 emit 한다 — 성공 emit 이 사후 정리 뒤에 있으면 timeout 없는 6개
  ///    소셜 SDK logout 이 지연될 때 다이얼로그가 무한 loading 에 갇힌다.
  /// 5. emit 이후 [AuthRepository.signOutAndResetOnboarding]
  ///    (onboardingSeen=false reset + router 의 resolveAuthRedirect 가
  ///    `/onboarding` 으로 자동 reset) 을 best-effort 사후 정리로 수행하며,
  ///    실패해도 탈퇴 실패로 분류하지 않고 Crashlytics 에만 기록한다.
  Future<void> requestAccountDeletion() async {
    state = const AsyncValue<void>.loading();
    // CR-04: 성공 emit 은 다이얼로그를 pop 시키고 그 결과로 본 Notifier 가
    // dispose 될 수 있다. 사후 정리에 필요한 핸들은 emit 이전에 캡처해 둔다 —
    // dispose 된 ref 로 ref.read 를 하면 StateError 가 던져진다.
    final authRepository = ref.read(authRepositoryProvider);
    final crashlytics = ref.read(crashlyticsServiceProvider);
    try {
      await ref.read(settingsRepositoryProvider).requestAccountDeletion();
    } on Object catch (e, st) {
      // 서버 삭제가 확정되지 않았다 — 종전대로 탈퇴 실패로 분류하고 종료한다.
      if (!ref.mounted) return;
      state = AsyncValue<void>.error(e, st);
      return;
    }
    // CR-04: 여기서 서버 hard delete 가 확정됐다. 성공 emit 을 사후 정리
    // **이전에** 수행한다. signOutAndResetOnboarding 은 6개 소셜 SDK logout 을
    // timeout 없이 직렬 await 하므로, emit 을 그 뒤에 두면 되돌릴 수 없는
    // 삭제가 끝난 뒤에도 다이얼로그가 loading 에 고정된다 (취소 버튼 disabled
    // + barrierDismissible:false → iOS 에는 탈출 경로가 0).
    if (ref.mounted) {
      state = const AsyncValue<void>.data(null);
    }
    // 로컬 정리 실패를 "탈퇴 실패" 로 분류하면 사용자는 이미 삭제된 계정으로
    // 재시도를 반복하게 된다 — best-effort 로만 수행하고 telemetry 만 남긴다.
    try {
      await authRepository.signOutAndResetOnboarding();
    } on Object catch (e, st) {
      await crashlytics.recordError(e, st, reason: 'withdrawal_post_signout');
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
  Future<AccountLinkOutcome> linkProvider(AccountProvider provider) {
    // WR-03: unsupported provider (naver: deployed callable OIDC 부재 / email:
    // Surface D EXCLUDE) 를 switch 자체에 단일 진실원으로 둔다. 별도 early-
    // guard 와 dead `null` switch arm 의 수동 동기화 결합을 제거해, 미래에
    // email 을 wire 하더라도 "cancelled" 로 오보고되지 않게 한다.
    return switch (provider) {
      AccountProvider.naver || AccountProvider.email =>
        Future<AccountLinkOutcome>.value(AccountLinkOutcome.unsupported),
      AccountProvider.google ||
      AccountProvider.apple ||
      AccountProvider.facebook ||
      AccountProvider.kakao ||
      AccountProvider.line ||
      AccountProvider.yahoojp => _dispatchLink(provider),
    };
  }

  /// 지원 provider 의 proactive link 를 실제 dispatch 한다 (WR-03/WR-04).
  ///
  /// [state] 를 loading 으로 설정하고 repository link 메서드를 호출한 뒤,
  /// 결과를 [AccountLinkOutcome] 으로 매핑한다. unsupported provider
  /// (naver/email) 는 [linkProvider] switch 에서 사전 분기되므로 본 메서드에
  /// 도달하지 않는다.
  ///
  /// **WR-04 (ref-disposed guard):** 본 Notifier 는 auto-dispose
  /// `@riverpod` 이며, OAuth/callable round-trip 진행 중 사용자가 SettingsScreen
  /// 을 pop 하면 disposed 될 수 있다. `await` 이후 [state] 를 쓰기 전에
  /// `ref.mounted` 를 확인해 disposed Notifier 에 대한 write (`StateError`)
  /// 를 회피한다.
  Future<AccountLinkOutcome> _dispatchLink(AccountProvider provider) async {
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
        // naver / email 은 linkProvider switch 에서 사전 분기 — 도달하지 않음.
        AccountProvider.naver || AccountProvider.email => null,
      };
      // WR-04: await 이후 disposed 여부 확인 후 state write.
      if (!ref.mounted) return AccountLinkOutcome.cancelled;
      state = const AsyncValue<void>.data(null);

      // 사용자 SDK 취소 (null) — no-op.
      if (result == null) return AccountLinkOutcome.cancelled;
      return switch (result) {
        Success<User>() => AccountLinkOutcome.success,
        Failure<User>(:final exception) => _mapLinkFailure(exception),
      };
    } on Object catch (e) {
      // 방어적 — repository 가 Result 로 흡수하므로 도달 거의 없음.
      // G-16-A6-2: 도달 시 원인을 잃지 않도록 runtimeType 만 남긴다 (PII 0).
      if (kDebugMode) {
        debugPrint(
          'SettingsNotifier._dispatchLink 미흡수 예외: '
          'runtimeType=${e.runtimeType}',
        );
      }
      // WR-04: catch path 에서도 disposed 여부 확인 후 state write.
      if (!ref.mounted) return AccountLinkOutcome.failed;
      state = const AsyncValue<void>.data(null);
      return AccountLinkOutcome.failed;
    }
  }

  /// link 실패 [exception] 을 원인별 [AccountLinkOutcome] 으로 분기한다
  /// (Phase 16 G-16-A6-2).
  ///
  /// 상류 `AuthRepository._mapProactiveLinkException` /
  /// `_mapFunctionsException` 이 만든 [AppException] 서브타입이 입력 계약이며,
  /// 반환값이 Surface D 위젯의 SnackBar 문구를 직접 결정한다. 단일
  /// `alreadyLinkedOrFailed` 로 뭉개던 기존 삼항을 대체한다 — 2026-09-07 A6
  /// 실측에서 `credential-already-in-use` 실패에 이메일 문구가 표시된 원인.
  AccountLinkOutcome _mapLinkFailure(AppException exception) {
    return switch (exception) {
      // `requires-recent-login` — 5분 auth_time boundary (기존 동작 유지).
      ReauthenticationRequiredException() => AccountLinkOutcome.reauthRequired,
      // WR-04: `provider-already-linked` — 이미 **현재 계정에** 연결됨.
      // AccountAlreadyLinked 보다 먼저 둘 필요는 없지만 (형제 타입),
      // 두 arm 이 서로 다른 문구로 갈린다는 사실을 명시적으로 남긴다.
      ProviderAlreadyLinkedToThisAccount() =>
        AccountLinkOutcome.alreadyLinkedHere,
      // `credential-already-in-use` (해당 자격증명이 **다른 계정에** 연결) +
      // Custom Token arm 의 callable `already-exists`.
      AccountAlreadyLinked() => AccountLinkOutcome.alreadyLinked,
      // `email-already-in-use` / `account-exists-with-different-credential`.
      EmailAlreadyInUse() ||
      AccountExistsWithDifferentCredential() => AccountLinkOutcome.emailInUse,
      // NetworkException 은 sealed 상위 — ConnectionTimeout /
      // NoInternetConnection(`network-request-failed`) / RequestTimeout 흡수.
      NetworkException() ||
      TooManyRequests() ||
      ServiceUnavailable() => AccountLinkOutcome.transientFailure,
      // 미분류 catch-all — 조용히 사라지지 않게 전용 값으로 보존한다.
      _ => AccountLinkOutcome.failed,
    };
  }
}

/// proactive 계정 연결 결과 분기 (Phase 16 16-11 / Surface D).
///
/// [SettingsNotifier.linkProvider] 가 반환하며, 위젯이 결과별 UI
/// (성공 snackbar / reauth 라우팅 / 원인별 실패 문구 / 취소 no-op /
/// 미지원 전용 문구) 를 분기하는 데 사용한다.
///
/// **G-16-A6-2:** 실패는 원인별 4 값 ([alreadyLinked] / [emailInUse] /
/// [transientFailure] / [failed]) 으로 분리된다. 이전 단일 값
/// `alreadyLinkedOrFailed` 는 서로 다른 원인을 같은(대부분 틀린) 문구로
/// 표시해 2026-09-07 A6 실측 오진의 원인이 되었다.
enum AccountLinkOutcome {
  /// link 성공 — 성공 snackbar + linkedProviders 자동 refresh.
  success,

  /// 사용자 SDK 취소 (null) — no-op (snackbar 0, 버튼 유지).
  cancelled,

  /// 재인증 필요 (`requires-recent-login`) — 재로그인 라우팅 (D-06 mirror).
  reauthRequired,

  /// 해당 로그인 정보가 이미 **다른 계정에** 연결됨 ([AccountAlreadyLinked]
  /// — `credential-already-in-use`, G-16-A6-2) —
  /// `settingsLinkFailedAlreadyLinked` 로 렌더.
  alreadyLinked,

  /// 해당 provider 가 이미 **현재 계정에** 연결됨
  /// ([ProviderAlreadyLinkedToThisAccount] — `provider-already-linked`,
  /// WR-04) — `settingsLinkFailedAlreadyLinkedHere` 로 렌더.
  ///
  /// [alreadyLinked] 와 의미가 정반대다. 하나로 뭉개면 "다른 계정에
  /// 연결되어 있으니 먼저 해제하세요" 라는, 사실과 반대이면서 수행도
  /// 불가능한 안내가 나간다.
  alreadyLinkedHere,

  /// 이메일이 이미 다른 계정에서 사용 중 ([EmailAlreadyInUse] /
  /// [AccountExistsWithDifferentCredential], G-16-A6-2) —
  /// `settingsLinkFailedEmailInUse` 로 렌더.
  emailInUse,

  /// 네트워크 / 서비스 일시 오류 ([NetworkException] 계열 / [TooManyRequests] /
  /// [ServiceUnavailable], G-16-A6-2) — `settingsLinkFailedTransient` 로 렌더.
  transientFailure,

  /// 분류되지 않은 link 실패 catch-all (G-16-A6-2) —
  /// `settingsLinkFailedUnknown` 으로 렌더. 정확한 코드는 repository 의
  /// kDebugMode `code=` 로그로 logcat 에 남는다.
  failed,

  /// proactive link 미지원 (naver: deployed callable OIDC 부재 / email:
  /// Surface D EXCLUDE) — **실패가 아니라 미지원**이므로 실패 4 문구와 구분되는
  /// 전용 문구 `settingsLinkUnsupportedProvider` 로 렌더한다 (G-16-A6-2).
  unsupported,
}
