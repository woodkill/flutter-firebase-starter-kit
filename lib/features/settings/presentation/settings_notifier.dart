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
//
// Phase 16.10 D-09 · D-10 · D-11 — 연결된 계정 해제에도 provider 측 끊기를
// 붙인다(`disconnectAndUnlinkProvider`). 해제 뒤에는 신원 기록이 사라져 나중에
// 탈퇴해도 provider 측 연결을 끊을 수 없으므로(D-09 근거 ②) 해제 시점에
// 끊는다. 이로써 16.8 D-08(「킷 쪽만 해제」)은 폐기되고, 16.8 D-06(「재인증
// 없음」)은 재로그인 provider(Google · Apple · 네이버 · 라인)에 한해 부분
// 개정된다 — 끊기용 provider 로그인 1회가 붙는다(Firebase 세션은 불변).
import 'package:flutter/foundation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/auth/provider_id.dart';
import '../../../core/crashlytics/crashlytics_service.dart';
import '../../../core/error/app_exception.dart';
import '../../../core/error/result.dart';
import '../../auth/data/auth_repository.dart';
import '../../auth/domain/user.dart';
import '../application/account_link_in_progress.dart';
import '../data/disconnect/disconnect_step.dart';
import '../data/disconnect/disconnect_steps.dart';
import '../data/settings_repository.dart';

part 'settings_notifier.g.dart';

/// 계정 정보 화면(탈퇴 · 연결 · 해제) · 탈퇴 진행 화면의 상태 관리자 (Phase 16 D-06).
///
/// 탈퇴 진행 상태 (`AsyncValue<void>`) 를 노출하며, UI 는 본 Notifier 의
/// AsyncValue 를 ref.listen 으로 구독하여 success/error 분기를 처리한다.
///
/// **10-REVIEW WR-02:** 본 state 는 **회원탈퇴 전용**이다. proactive 계정
/// 연결의 진행 표시는 [accountLinkInProgressProvider] 가 따로 보유한다 —
/// 서로 무관한 두 유스케이스가 하나의 AsyncValue 를 공유하면 탈퇴 진행 중
/// 연결 버튼이 전부 잠기고, 탈퇴 실패 error state 가 계정 정보 화면에
/// 살아남으며, 향후 link 실패가 "탈퇴 실패" 로 오표시된다.
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
  ///    을 emit 한다 — 성공 emit 이 사후 정리 뒤에 있으면 timeout 없는 5개
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
    // **이전에** 수행한다. signOutAndResetOnboarding 은 5개 소셜 SDK logout 을
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
  /// - Custom Token (kakao/line) →
  ///   [AuthRepository.linkCustomTokenProviderArm].
  /// - naver → [AuthRepository.linkNaverProviderArm] (1-tap access token /
  ///   웹 code · Phase 16.9).
  /// - email → Surface D 에서 제외 (mockup §0 EXCLUDE) — 본 메서드에 도달 시
  ///   [AccountLinkOutcome.unsupported] (방어적 차단, UI 후보 집합에 email
  ///   미포함).
  ///
  /// 진행 중 [accountLinkInProgressProvider] 를 `true` 로 설정해 위젯이 link
  /// in-progress 오버레이를 표시할 수 있게 하고, 종료 시 `false` 로 복귀한다
  /// (성공/실패/취소 모두 — 플래그 자체는 결과 분기에 사용하지 않음).
  ///
  /// **WR-02:** 진행 상태는 탈퇴용 [state] 와 분리된 전용 provider 가
  /// 보유한다. 한 `AsyncValue` 를 공유하던 시절에는 탈퇴 진행 중에 계정 연결
  /// 버튼이 전부 disabled 되고, 탈퇴 실패로 남은 error state 가 Settings
  /// 화면에 살아남았다.
  ///
  /// 반환: 위젯이 결과별 UI (성공 snackbar / reauth 라우팅 / already-linked
  /// 안내 / 취소 no-op) 를 분기하기 위한 [AccountLinkOutcome]. link 성공 시
  /// `currentUserProvider` 가 Firestore linkedProviders stream 으로 자동 refresh
  /// 되어 해당 provider 버튼이 available 집합에서 제거된다.
  Future<AccountLinkOutcome> linkProvider(AccountProvider provider) {
    // WR-03: unsupported provider (email: Surface D EXCLUDE) 를 switch
    // 자체에 단일 진실원으로 둔다. 별도 early-
    // guard 와 dead `null` switch arm 의 수동 동기화 결합을 제거해, 미래에
    // email 을 wire 하더라도 "cancelled" 로 오보고되지 않게 한다.
    return switch (provider) {
      AccountProvider.email => Future<AccountLinkOutcome>.value(
        AccountLinkOutcome.unsupported,
      ),
      AccountProvider.google ||
      AccountProvider.apple ||
      AccountProvider.facebook ||
      AccountProvider.kakao ||
      AccountProvider.naver ||
      AccountProvider.line => _dispatchLink(provider),
    };
  }

  /// 지원 provider 의 proactive link 를 실제 dispatch 한다 (WR-03/WR-04).
  ///
  /// [state] 를 loading 으로 설정하고 repository link 메서드를 호출한 뒤,
  /// 결과를 [AccountLinkOutcome] 으로 매핑한다. unsupported provider
  /// (email) 는 [linkProvider] switch 에서 사전 분기되므로 본 메서드에
  /// 도달하지 않는다.
  ///
  /// **WR-04 / 10-REVIEW WR-02 (ref-disposed guard):** 본 Notifier 는
  /// auto-dispose `@riverpod` 이며, OAuth/callable round-trip 진행 중 사용자가
  /// 계정 정보 화면(`AccountScreen` · Phase 17.1 D-02 — 계정 연결 섹션이 설정에서
  /// 옮겨 감)을 pop 하면 disposed 될 수 있다. 진행 플래그 핸들
  /// ([accountLinkInProgressProvider] notifier) 과 repository 핸들을 진입
  /// 시점에 캡처해 두면, dispose 이후에도 `finally` 의 `end()` 가 도달해
  /// 오버레이가 `true` 로 고착되지 않는다 (플래그 provider 는 keepAlive).
  Future<AccountLinkOutcome> _dispatchLink(AccountProvider provider) async {
    final linkProgress = ref.read(accountLinkInProgressProvider.notifier);
    final repo = ref.read(authRepositoryProvider);
    linkProgress.begin();
    try {
      final Result<User>? result = switch (provider) {
        AccountProvider.google => await repo.linkGoogleCredential(),
        AccountProvider.apple => await repo.linkAppleCredential(),
        AccountProvider.facebook => await repo.linkFacebookCredential(),
        AccountProvider.kakao || AccountProvider.line =>
          await repo.linkCustomTokenProviderArm(targetProvider: provider),
        AccountProvider.naver => await repo.linkNaverProviderArm(),
        // email 은 linkProvider switch 에서 사전 분기 — 도달하지 않음.
        AccountProvider.email => null,
      };
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
      return AccountLinkOutcome.failed;
    } finally {
      // 성공/실패/취소/예외 어느 경로로 빠져나가도 진행 표시를 해제한다.
      linkProgress.end();
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
      // native `requires-recent-login` · CT `reauthentication_required` reason
      // — 방어 매핑. Firebase 는 연결에 최근 로그인을 요구하지 않는다
      // (quick 260928-cxs).
      ReauthenticationRequiredException() => AccountLinkOutcome.reauthRequired,
      // WR-04: `provider-already-linked` — 이미 **현재 계정에** 연결됨.
      // AccountAlreadyLinked 보다 먼저 둘 필요는 없지만 (형제 타입),
      // 두 arm 이 서로 다른 문구로 갈린다는 사실을 명시적으로 남긴다.
      ProviderAlreadyLinkedToThisAccount() =>
        AccountLinkOutcome.alreadyLinkedHere,
      // `credential-already-in-use` (해당 자격증명이 **다른 계정에** 연결) +
      // Custom Token arm 의 callable `already-exists` (reason 없음 — reason
      // `provider_already_linked` 는 위 alreadyLinkedHere · 16.9 IN-03).
      AccountAlreadyLinked() => AccountLinkOutcome.alreadyLinked,
      // `email-already-in-use` / `account-exists-with-different-credential`.
      EmailAlreadyInUse() ||
      AccountExistsWithDifferentCredential() => AccountLinkOutcome.emailInUse,
      // Phase 17 D-42 · D-43 — App Check 차단(SDK 계층 거부)은 일시 오류 ·
      // 재로그인과 다른 전용 문구로 안내한다.
      AppCheckFailedException() => AccountLinkOutcome.appCheckFailed,
      // NetworkException 은 sealed 상위 — ConnectionTimeout /
      // NoInternetConnection(`network-request-failed`) / RequestTimeout 흡수.
      NetworkException() ||
      TooManyRequests() ||
      ServiceUnavailable() => AccountLinkOutcome.transientFailure,
      // 미분류 catch-all — 조용히 사라지지 않게 전용 값으로 보존한다.
      _ => AccountLinkOutcome.failed,
    };
  }

  /// 연결된 계정 [providerId] 의 연결을 해제한다 (Phase 16.8 D-01 · D-02 ·
  /// D-03 · D-06 · D-19).
  ///
  /// native/CT 분기는 `AccountProvider.tryParse(providerId).isNative` 한 번뿐이다
  /// — provider 별 switch 를 두지 않는다 (D-19):
  /// - native (`google.com` · `apple.com` · `facebook.com` · `password`) →
  ///   [AuthRepository.unlinkNativeProvider] (Firebase URI 그대로).
  /// - Custom Token (`kakao` · `line` 등) →
  ///   [AuthRepository.unlinkCustomTokenProvider] (slug).
  ///
  /// 식별 불가 id 는 UI 의 `canUnlinkProvider` 가 이미 버튼을 숨기므로 도달하지
  /// 않지만, 방어적으로 [AccountUnlinkOutcome.failed] 를 돌려준다.
  ///
  /// **진행 provider 미사용:** [accountLinkInProgressProvider] 와 그 오버레이는
  /// 쓰지 않는다. 진행 표시는 확인 다이얼로그 안 스피너가 맡고(다이얼로그가
  /// modal 이라 계정 정보 화면(`AccountScreen`) 입력이 이미 막힌다), 오버레이
  /// 라벨은 「로그인 처리 중…」 이라 해제에 틀리다 (UI-SPEC §Surface U). 탈퇴용
  /// [state] 도 건드리지 않는다 (WR-02).
  ///
  /// 반환: 위젯이 결과별 SnackBar · reauth 라우팅을 분기하기 위한
  /// [AccountUnlinkOutcome]. 성공 시 목록 갱신은 user stream 재방출이 맡는다.
  Future<AccountUnlinkOutcome> unlinkProvider(String providerId) async {
    final provider = AccountProvider.tryParse(providerId);
    if (provider == null) return AccountUnlinkOutcome.failed;
    // auto-dispose notifier — await 전에 repository 핸들을 캡처한다.
    return _unlinkWith(ref.read(authRepositoryProvider), provider, providerId);
  }

  /// provider 측 연결을 먼저 끊고, 성공했을 때만 킷 쪽 연결을 해제한다
  /// (Phase 16.10 D-09 · D-10 · D-11 · RESEARCH Pattern 4).
  ///
  /// 순서:
  /// 1. [providerId] 식별 불가 → [AccountUnlinkOutcome.failed] (호출 0).
  /// 2. 레지스트리에 끊기 step 이 없는 id(이메일/비밀번호 — provider 측 연결이
  ///    없다)는 끊기 없이 16.8 해제만 한다 (D-09 범위 = 끊기 레지스트리의
  ///    provider).
  /// 3. step 이 있으면 `reloginForFreshness: false` 로 실행한다 — 해제는
  ///    서버 탈퇴의 300초 신선도가 필요 없으므로(D-09) 재로그인 provider 도
  ///    끊기 토큰만 확보하고 Firebase 세션 · custom token 은 건드리지 않는다
  ///    (세션 교체는 탈퇴 진행 화면만의 목적 — D-07).
  /// 4. [DisconnectDone] 일 때만 기존 해제([unlinkProvider] 와 같은 경로 —
  ///    `unlinkNativeProvider` · `unlinkCustomTokenProvider` 변경 0)로 간다.
  ///    그 해제가 일시 오류(`transientFailure`) · 미분류(`failed`)로 실패하면
  ///    provider 측은 이미 끊겼고 킷 연결만 남은 부분 상태라
  ///    `unlinkFailedAfterDisconnect` 로 바꿔 돌려준다(16.10 review IN-03 —
  ///    iteration 3 · UI-SPEC §N′ sign-off R2). 원인 문구가 더 구체적인
  ///    `lastCredential` · `alreadyUnlinked` · `reauthRequired` 와 `success` 는
  ///    그대로다. 끊기 전 서버 사전 확인은 두지 않는다(R2 기각 — 네트워크
  ///    오류는 사전 확인으로 막을 수 없다).
  ///    끊기가 실패했는데 해제하면 신원 기록이 사라져 provider 측 연결이 영구
  ///    고아가 되므로 나머지 결과는 모두 해제 0 · 연결 유지다 (D-11):
  ///    - [DisconnectCancelled] (provider 로그인 취소) → `cancelled`.
  ///    - [DisconnectIdentityMismatch] → `identityMismatch` (D-08).
  ///    - [DisconnectFailed] → App Check 차단([AppCheckFailedException])은
  ///      `appCheckFailed`(Phase 17 D-43 — 가장 먼저 판정), 네트워크 · rate
  ///      limit 은 `transientFailure`, 서버 `provider_config`
  ///      ([ProviderMisconfigured])는 `providerConfigFailed`(16.10 review
  ///      IN-04 — iteration 3), 그 밖은 `disconnectFailed`.
  ///    - 예상 밖 throw (step 계약 위반 · 실행 의존 생성 실패) →
  ///      `disconnectFailed`.
  ///
  /// [unlinkProvider] 와 마찬가지로 탈퇴용 [state] · 연결 진행 provider 를
  /// 건드리지 않는다 — 진행 표시는 다이얼로그 스피너 몫이다 (WR-02).
  Future<AccountUnlinkOutcome> disconnectAndUnlinkProvider(
    String providerId,
  ) async {
    final provider = AccountProvider.tryParse(providerId);
    if (provider == null) return AccountUnlinkOutcome.failed;
    // auto-dispose notifier — await 전에 repository · step 을 캡처한다.
    final repo = ref.read(authRepositoryProvider);
    final step = disconnectStepFor(ref.read(disconnectStepsProvider), provider);
    if (step == null) return _unlinkWith(repo, provider, providerId);

    final DisconnectOutcome disconnected;
    try {
      // 실행 의존은 이 시점에만 평가한다 — 인프라 provider 생성 실패도 끊기
      // 실패로 흡수한다(해제 0).
      final deps = ref.read(disconnectDepsProvider);
      disconnected = await step.run(deps, reloginForFreshness: false);
    } on Object catch (e) {
      // 방어적 — step.run 은 예외 없이 결과를 돌려주는 계약이다 (PII 0).
      if (kDebugMode) {
        debugPrint(
          'SettingsNotifier.disconnectAndUnlinkProvider 미흡수 예외: '
          'runtimeType=${e.runtimeType}',
        );
      }
      return AccountUnlinkOutcome.disconnectFailed;
    }

    switch (disconnected) {
      case DisconnectDone():
        final unlinked = await _unlinkWith(repo, provider, providerId);
        return _markPartialAfterDisconnect(unlinked);
      case DisconnectCancelled():
        return AccountUnlinkOutcome.cancelled;
      case DisconnectIdentityMismatch():
        return AccountUnlinkOutcome.identityMismatch;
      // Phase 17 D-43 — 끊기 callable 의 App Check 차단은 disconnectFailed
      // 보다 앞서 해제 callable 과 같은 전용 안내로 보낸다(해제 0 · 연결 유지).
      case DisconnectFailed(exception: AppCheckFailedException()):
        return AccountUnlinkOutcome.appCheckFailed;
      case DisconnectFailed(:final exception):
        return _mapDisconnectFailure(exception);
    }
  }

  /// provider 측 끊기 성공 뒤의 킷 해제 결과 [unlinked] 를 부분 상태 안내로
  /// 바꾼다 (16.10 review IN-03 — iteration 3 · UI-SPEC §N′).
  ///
  /// 일시 오류 · 미분류 실패만 [AccountUnlinkOutcome.unlinkFailedAfterDisconnect]
  /// 가 된다 — 기존 문구(「잠시 후 다시 시도」 · 「알 수 없는 오류」)는 provider
  /// 측이 이미 끊겼다는 사실을 알리지 않는다. 나머지 값은 그대로 돌려준다 —
  /// `appCheckFailed`(Phase 17 D-43 「같은 원인 같은 안내」)도 바꾸지 않는다.
  AccountUnlinkOutcome _markPartialAfterDisconnect(
    AccountUnlinkOutcome unlinked,
  ) {
    return switch (unlinked) {
      AccountUnlinkOutcome.transientFailure || AccountUnlinkOutcome.failed =>
        AccountUnlinkOutcome.unlinkFailedAfterDisconnect,
      _ => unlinked,
    };
  }

  /// 킷 쪽 연결 해제 본체 — [unlinkProvider] 와 [disconnectAndUnlinkProvider]
  /// 가 공유한다 (Phase 16.8 D-19 native/CT 분기 그대로).
  ///
  /// [repo] 는 호출자가 await 전에 캡처한 핸들이다(auto-dispose notifier).
  Future<AccountUnlinkOutcome> _unlinkWith(
    AuthRepository repo,
    AccountProvider provider,
    String providerId,
  ) async {
    try {
      final result = provider.isNative
          ? await repo.unlinkNativeProvider(providerId)
          : await repo.unlinkCustomTokenProvider(provider.slug);
      return switch (result) {
        Success<User>() => AccountUnlinkOutcome.success,
        Failure<User>(:final exception) => _mapUnlinkFailure(exception),
      };
    } on Object catch (e) {
      // 방어적 — repository 가 Result 로 흡수하므로 도달 거의 없음 (PII 0).
      if (kDebugMode) {
        debugPrint(
          'SettingsNotifier.unlinkProvider 미흡수 예외: '
          'runtimeType=${e.runtimeType}',
        );
      }
      return AccountUnlinkOutcome.failed;
    }
  }

  /// 해제 실패 [exception] 을 원인별 [AccountUnlinkOutcome] 으로 분기한다
  /// (Phase 16.8 · UI-SPEC §N).
  AccountUnlinkOutcome _mapUnlinkFailure(AppException exception) {
    return switch (exception) {
      ReauthenticationRequiredException() =>
        AccountUnlinkOutcome.reauthRequired,
      UnlinkLastCredentialRejected() => AccountUnlinkOutcome.lastCredential,
      ProviderNotLinked() => AccountUnlinkOutcome.alreadyUnlinked,
      NetworkException() ||
      TooManyRequests() ||
      ServiceUnavailable() => AccountUnlinkOutcome.transientFailure,
      // Phase 17 D-42 · D-43 — App Check 차단(SDK 계층 거부) 전용 안내.
      AppCheckFailedException() => AccountUnlinkOutcome.appCheckFailed,
      _ => AccountUnlinkOutcome.failed,
    };
  }

  /// provider 측 끊기 실패 [exception] 을 [AccountUnlinkOutcome] 으로
  /// 분기한다 (Phase 16.10 D-11 · UI-SPEC §N′).
  ///
  /// 네트워크 · rate limit 은 기존 `settingsUnlinkFailedTransient` 로 안내한다.
  /// 서버 `provider_config`([ProviderMisconfigured] — 운영자 설정 결함)는
  /// 재시도로 풀리지 않으므로 재시도 안내가 없는 전용 문구로 보낸다(16.10
  /// review IN-04 — iteration 3). 그 밖(익명 거부 · SDK 오류 · 로그인 사용자
  /// 부재 등)은 「앱 연결을 해제하지 못해 연결을 유지했습니다」 로 안내한다.
  /// App Check 차단([AppCheckFailedException])은 호출 전
  /// [disconnectAndUnlinkProvider] 가 `appCheckFailed` 로 먼저 가른다
  /// (Phase 17 D-43).
  AccountUnlinkOutcome _mapDisconnectFailure(AppException exception) {
    return switch (exception) {
      NetworkException() ||
      TooManyRequests() => AccountUnlinkOutcome.transientFailure,
      ProviderMisconfigured() => AccountUnlinkOutcome.providerConfigFailed,
      _ => AccountUnlinkOutcome.disconnectFailed,
    };
  }
}

/// 연결된 계정 해제 결과 분기 (Phase 16.8 · UI-SPEC §N · 16.10 §N′).
///
/// [SettingsNotifier.disconnectAndUnlinkProvider] ·
/// [SettingsNotifier.unlinkProvider] 가 반환하며, 계정 정보 화면
/// (`AccountScreen`)이 결과별 SnackBar · reauth 라우팅을 분기하는 데 사용한다.
enum AccountUnlinkOutcome {
  /// 해제 성공 — `accountUnlinkSucceededSnackbar` 로 렌더 · 목록은 user
  /// stream 재방출로 갱신.
  success,

  /// 다이얼로그 취소 · barrier · back · provider 로그인 취소(16.10) — no-op
  /// (SnackBar 0 · 연결 유지). 다이얼로그 닫힘은 확인 다이얼로그가, 로그인
  /// 취소는 notifier 가 만든다.
  cancelled,

  /// 재인증 필요 ([ReauthenticationRequiredException] — native
  /// `requires-recent-login` 뿐) — `authReauthRequired` 로 렌더 + 재로그인
  /// 라우팅. D-06 으로 기대하지 않는 방어 매핑. callable 의 두 code 는
  /// 근거가 달라도 둘 다 여기가 아니라 [transientFailure] 로 간다.
  /// - `unauthenticated`: App Check 차단(INVALID · MISSING)도 이 code 로 와
  ///   code 만으로는 auth 부재와 구분되지 않고, App Check 차단은 재로그인으로
  ///   해소되지 않는다. Phase 17 D-43 부터 SDK 계층 거부(App Check)는 매퍼가
  ///   [AppCheckFailedException] 으로 갈라 [appCheckFailed] 로 간다.
  /// - `permission-denied`: App Check 와 code 를 공유하지 않는다. 이
  ///   callable 이 던지지 않는 code 라(uid 는 `request.auth.uid` 만 써서
  ///   idToken uid 불일치 · `caller_identity_mismatch` 경로 없음) 방어
  ///   매핑일 뿐이다.
  ///
  /// (16.8 review IN-06 · iteration 2 WR-01 · iteration 3 IN-01)
  reauthRequired,

  /// 남은 로그인 수단이 하나뿐 ([UnlinkLastCredentialRejected] — callable
  /// `failed-precondition` + `details.reason: 'last_credential'`) —
  /// `settingsUnlinkFailedLastCredential` 로 렌더.
  lastCredential,

  /// 이미 해제됨 ([ProviderNotLinked] — native `no-such-provider` · callable
  /// `not-found`) — `settingsUnlinkFailedAlreadyUnlinked` 로 렌더.
  alreadyUnlinked,

  /// 네트워크 / 서비스 일시 오류 ([NetworkException] 계열 · [TooManyRequests]
  /// · [ServiceUnavailable]) — `settingsUnlinkFailedTransient` 로 렌더.
  ///
  /// - native: `network-request-failed` · `too-many-requests` · 그 밖의
  ///   미분류 Auth code(`_logAndFallback`).
  /// - callable: `unavailable` · `deadline-exceeded` · `resource-exhausted` ·
  ///   `unauthenticated`(서버 taxonomy — auth 부재 등 · SDK 계층 App Check
  ///   거부는 [appCheckFailed]) · `invalid-argument` ·
  ///   reason 이 `last_credential` 이 아닌 `failed-precondition`
  ///   (`anonymous_caller`) · `internal` 등 미분류 code, 서버가 던지지 않는
  ///   `permission-denied`(`caller_identity_mismatch` 제외) 방어 매핑.
  /// - 비-Auth · 비-Functions 예외.
  ///
  /// (16.8 review IN-06 · iteration 2 WR-01)
  transientFailure,

  /// 분류되지 않은 해제 실패 catch-all (그 외 [AppException]) —
  /// `settingsUnlinkFailedUnknown` 으로 렌더.
  failed,

  /// 재로그인한 provider 신원이 이 계정에 연결된 신원이 아님 (D-08) — native
  /// user-mismatch · CT caller_identity_mismatch · 응답 uid 불일치.
  /// `settingsUnlinkFailedIdentityMismatch` 로 렌더 · 연결 유지.
  identityMismatch,

  /// provider 측 연결 끊기 실패로 킷 해제를 중단함 (D-11) — 익명 거부 ·
  /// 서버 결함 등. `settingsUnlinkFailedDisconnect` 로 렌더 · 연결 유지.
  /// 서버 `provider_config` 는 [providerConfigFailed], App Check 차단은
  /// [appCheckFailed] 다 (Phase 17 D-43).
  disconnectFailed,

  /// provider 측 끊기는 성공했는데 이어진 킷 해제가 일시 오류 · 미분류로
  /// 실패함 — provider 측은 끊기고 킷 연결은 남은 부분 상태 (16.10 review
  /// IN-03 — iteration 3 · UI-SPEC §N′).
  /// `settingsUnlinkFailedAfterDisconnect` 로 렌더 · 킷 연결 유지(다시
  /// 로그인할 수 있어 고아는 없다). [SettingsNotifier.disconnectAndUnlinkProvider]
  /// 만 돌려준다 — 끊기 step 이 없는 이메일/비밀번호 해제와
  /// [SettingsNotifier.unlinkProvider] 는 기존 [transientFailure] · [failed] 다.
  unlinkFailedAfterDisconnect,

  /// provider 측 끊기 callable 이 운영자 설정 결함으로 거부함
  /// ([ProviderMisconfigured] — `failed-precondition` + `details.reason:
  /// 'provider_config'`) — 킷 해제 중단 (16.10 review IN-04 — iteration 3 ·
  /// UI-SPEC §N′). `settingsUnlinkFailedProviderConfig` 로 렌더 · 연결 유지.
  /// 재시도로 풀리지 않으므로 문구에 재시도 · 문의 안내가 없다(sign-off R4).
  providerConfigFailed,

  /// App Check 차단 ([AppCheckFailedException] — SDK 계층 거부, plan 08
  /// helper `classifyAppCheckRejection`) — `errorAppCheckFailed` SnackBar ·
  /// 재로그인 아님 (Phase 17 D-42 · D-43). 해제 callable 실패와 provider 측
  /// 끊기 step 의 `DisconnectFailed(AppCheckFailedException)` 둘 다 이 값이다
  /// (끊기 실패는 [disconnectFailed] 보다 앞서 판정). 끊기 성공 뒤 해제가 App
  /// Check 로 막혀도 [unlinkFailedAfterDisconnect] 로 바꾸지 않는다 — 같은
  /// 원인 같은 안내(D-43)를 우선하고, 재시도는 끊기 단계부터 다시 돈다.
  appCheckFailed,
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

  /// 재인증 필요 (`requires-recent-login` · CT reason) — 재로그인 라우팅.
  /// 방어 매핑 — 정상 연결 경로에서는 오지 않는다 (quick 260928-cxs).
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

  /// App Check 차단 ([AppCheckFailedException] — SDK 계층 거부, plan 08
  /// helper `classifyAppCheckRejection`) — `errorAppCheckFailed` SnackBar ·
  /// 재로그인 아님 (Phase 17 D-42 · D-43). 같은 화면에서 재시도한다.
  appCheckFailed,

  /// 분류되지 않은 link 실패 catch-all (G-16-A6-2) —
  /// `settingsLinkFailedUnknown` 으로 렌더. 정확한 코드는 repository 의
  /// kDebugMode `code=` 로그로 logcat 에 남는다.
  failed,

  /// proactive link 미지원 (email: Surface D EXCLUDE) — **실패가 아니라
  /// 미지원**이므로 실패 4 문구와 구분되는
  /// 전용 문구 `settingsLinkUnsupportedProvider` 로 렌더한다 (G-16-A6-2).
  unsupported,
}
