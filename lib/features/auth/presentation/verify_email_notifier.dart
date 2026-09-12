import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/error/app_exception.dart';
import '../../../core/error/result.dart';
import '../../../core/providers/firebase_providers.dart';
import '../../../core/router/auth_guard.dart';
import '../data/auth_repository.dart';
import 'verify_email_state.dart';

part 'verify_email_notifier.g.dart';

/// 폴링 간격 (초).
const pollingIntervalSeconds = 3;

/// 폴링 타임아웃 (초). 5분 후 자동 중지.
const pollingTimeoutSeconds = 300;

/// 재전송 쿨다운 (초).
const cooldownSeconds = 60;

/// 폴링 중지를 유발하는 **연속** 실패 횟수 (WR-02 — Phase 09 review).
///
/// 폴링은 사용자 조작이 아니므로 1회 실패로 배너를 띄우면 소음이 된다.
/// 반대로 실패를 통째로 삼키면 오프라인에서 5분 내내 신호가 0이다.
/// 3회 연속 (= 약 [pollingIntervalSeconds] × 3 초) 실패를 "일시적 끊김이
/// 아니다" 의 판정선으로 삼는다.
const pollFailureThreshold = 3;

/// 이메일 인증 대기 화면의 비즈니스 로직을 담당하는 AsyncNotifier.
///
/// 3초 간격 폴링으로 [AuthRepository.reloadUser]를 호출하여
/// emailVerified 상태를 감지하고, 5분 타임아웃 후 폴링을 자동 중지한다.
/// 재전송 쿨다운(60초)과 수동 확인 기능을 제공한다.
/// autoDispose이므로 화면 이탈 시 Timer가 정리된다.
@riverpod
class VerifyEmailNotifier extends _$VerifyEmailNotifier {
  Timer? _pollingTimer;
  Timer? _cooldownTimer;
  int _elapsedSeconds = 0;

  /// [pollOnce]의 **연속** 실패 횟수 (WR-02). 성공 1회로 0 으로 되돌린다.
  int _consecutivePollFailures = 0;

  @override
  FutureOr<VerifyEmailState> build() {
    ref.onDispose(_cancelAllTimers);
    _startPolling();
    return const VerifyEmailState();
  }

  /// 폴링 타이머를 시작한다.
  ///
  /// [pollingIntervalSeconds]초 간격으로 [pollOnce]를
  /// 호출하여 emailVerified 변경을 감지한다.
  /// [pollingTimeoutSeconds]초 경과 시 자동 중지하고
  /// [VerifyEmailState.isPolling]을 false로 전환한다.
  void _startPolling() {
    _elapsedSeconds = 0;
    _consecutivePollFailures = 0;
    _pollingTimer = Timer.periodic(
      const Duration(seconds: pollingIntervalSeconds),
      (timer) {
        _elapsedSeconds += pollingIntervalSeconds;

        if (_elapsedSeconds >= pollingTimeoutSeconds) {
          timer.cancel();
          if (!ref.mounted) return;
          state = AsyncData(state.requireValue.copyWith(isPolling: false));
          return;
        }

        pollOnce();
      },
    );
  }

  /// 단일 폴링 사이클을 실행한다.
  ///
  /// [AuthRepository.reloadUser]를 호출한 뒤 emailVerified를 확인한다.
  /// emailVerified가 true이면 폴링을 중지하고 redirect를 트리거한다.
  ///
  /// **실패 처리 (WR-02 — Phase 09 review).** 폴링은 사용자 조작이 아니므로
  /// 1회 실패로 배너를 띄우지 않는다 (일시적 네트워크 끊김을 매 3초마다
  /// 에러로 보고하면 소음이 된다). 대신 **연속** 실패가
  /// [pollFailureThreshold]회 누적되면 폴링을 중지하고
  /// [VerifyEmailState.error]를 세팅한다 — 이전에는 `Result`를 통째로 버려
  /// 오프라인 상태에서 5분 내내 아무 신호 없이 헛도는 구간이 있었다.
  /// 성공 1회로 카운터는 초기화된다.
  @visibleForTesting
  Future<void> pollOnce() async {
    final result = await ref.read(authRepositoryProvider).reloadUser();
    if (!ref.mounted) return;

    if (result case Failure<void>(exception: final ex)) {
      _consecutivePollFailures++;
      if (_consecutivePollFailures >= pollFailureThreshold) {
        _pollingTimer?.cancel();
        state = AsyncData(
          state.requireValue.copyWith(isPolling: false, error: ex),
        );
      }
      return;
    }
    _consecutivePollFailures = 0;

    // reload() 후 currentUser를 다시 읽어 stale 방지 (T-06.1-03-03).
    final user = ref.read(firebaseAuthProvider).currentUser;
    if (user != null && user.emailVerified) {
      _pollingTimer?.cancel();
      _triggerRedirect();
    }
  }

  /// 이메일 인증 메일을 재전송한다.
  ///
  /// 성공 시 [cooldownSeconds]초 쿨다운을 시작하고 error를 초기화한다.
  /// 실패 시 [VerifyEmailState.error]에 [AppException]을 설정한다.
  ///
  /// **재진입 가드 (WR-03 — Phase 09 review).** 이전에는 네트워크 왕복이
  /// 끝난 **뒤에야** [cooldownSeconds] 를 세팅했고, 화면의 비활성화 조건이
  /// `cooldownRemaining > 0` 단 하나였기 때문에 왕복 구간(2~3초)에는
  /// 버튼이 계속 활성이었다. 연타하면 `sendEmailVerification` 이 그 횟수만큼
  /// 호출되어 중복 메일이 가고, Firebase 가 `too-many-requests` 를 반환하면
  /// **성공했는데도** 마지막 호출 결과로 에러 배너가 떴다.
  ///
  /// 이제 왕복 **전에** [VerifyEmailState.isResending] 을 세워
  /// ([checkManually] 의 `isChecking` 패턴과 대칭) 화면이 그 즉시 버튼을
  /// 비활성화하고, 본 메서드도 in-flight / 쿨다운 중 재진입을 자체 차단한다.
  /// 즉 방어선이 UI 단독에서 notifier + UI 이중으로 바뀐다.
  Future<void> resendVerification() async {
    final current = state.requireValue;
    if (current.isResending || current.cooldownRemaining > 0) return;
    state = AsyncData(current.copyWith(isResending: true, error: null));

    final result = await ref
        .read(authRepositoryProvider)
        .sendEmailVerification();
    if (!ref.mounted) return;

    switch (result) {
      case Success<void>():
        state = AsyncData(
          state.requireValue.copyWith(
            isResending: false,
            cooldownRemaining: cooldownSeconds,
            error: null,
          ),
        );
        _startCooldown();
      case Failure<void>(exception: final ex):
        state = AsyncData(
          state.requireValue.copyWith(isResending: false, error: ex),
        );
    }
  }

  /// 수동으로 이메일 인증 상태를 확인한다.
  ///
  /// [VerifyEmailState.isChecking]을 true로 설정한 뒤
  /// [AuthRepository.reloadUser]를 호출하고, emailVerified가 true이면
  /// redirect를 트리거한다. false이면 isChecking을 false로 복귀한다.
  ///
  /// **실패 처리 (WR-02 — Phase 09 review).** [AuthRepository.reloadUser]의
  /// `Failure`(네트워크 실패 / `user-token-expired` / `user-disabled`)를
  /// [VerifyEmailState.error]로 매핑한다. 이전에는 반환값을 버리고
  /// `emailVerified`만 다시 읽었기 때문에, 오프라인에서 "인증 확인"을 탭하면
  /// 스피너만 잠깐 돌고 **에러 표시가 0**이었다 —
  /// 같은 파일의 [resendVerification]은 이미 `Failure`를 상태로 매핑하고
  /// `verify_email_screen.dart`의 [FormErrorBanner]가 그것을 렌더하므로,
  /// 표시 표면은 이미 존재하는데 이 경로만 쓰지 않던 비대칭이었다.
  ///
  /// 재시도 시 직전 에러가 잔류하지 않도록 진입 시 `error`를 비운다.
  Future<void> checkManually() async {
    state = AsyncData(
      state.requireValue.copyWith(isChecking: true, error: null),
    );

    final result = await ref.read(authRepositoryProvider).reloadUser();
    if (!ref.mounted) return;

    if (result case Failure<void>(exception: final ex)) {
      state = AsyncData(
        state.requireValue.copyWith(isChecking: false, error: ex),
      );
      return;
    }

    final user = ref.read(firebaseAuthProvider).currentUser;
    if (user != null && user.emailVerified) {
      _triggerRedirect();
    } else {
      state = AsyncData(state.requireValue.copyWith(isChecking: false));
    }
  }

  /// 로그아웃한다 (Phase 10.2 I2 invariant 단일 진리원 경유).
  ///
  /// [AuthRepository.signOutAndResetOnboarding] 을 호출하여 onboarding
  /// 완료 플래그 reset → 5 SDK 순차 logout 순서를 강제한다 (D-A1/A3).
  /// 본 메서드를 [AuthRepository.signOut] 단독으로 직접 호출하면
  /// `onboardingSeen=true` snapshot 이 유지된 채 resolveAuthRedirect 가
  /// 재평가되어 익명홈 통과 race (D-20 cycle 회귀) 가 가능하다 — Phase
  /// 10.2 D-A7 호출자 책임 (auth_repository.dart line 919-925 doc-comment).
  ///
  /// 호출 후 [_triggerRedirect] 로 GoRouter 재평가를 강제한다 — Firebase
  /// SDK authStateChanges() 가 reload() 에 반응하지 않을 가능성
  /// (FlutterFire Issue #8777) 보강. 자연 redirect 분기 (2)
  /// (`!isAuthenticated && !onboardingSeen`) 가 `/onboarding` 으로 이동.
  Future<void> logout() async {
    await ref.read(authRepositoryProvider).signOutAndResetOnboarding();
    if (!ref.mounted) return;
    _triggerRedirect();
  }

  /// 폴링 타임아웃 도달 시 폴링을 중지한다.
  ///
  /// 테스트에서 [pollingTimeoutSeconds]초 경과를 직접 시뮬레이션할 수 있다.
  @visibleForTesting
  void stopPolling() {
    _pollingTimer?.cancel();
    if (!ref.mounted) return;
    state = AsyncData(state.requireValue.copyWith(isPolling: false));
  }

  /// 쿨다운 잔여 시간을 1초 감소시킨다.
  ///
  /// 테스트에서 쿨다운 카운트다운을 직접 시뮬레이션할 수 있다.
  @visibleForTesting
  void tickCooldown() {
    if (!ref.mounted) return;
    final current = state.requireValue.cooldownRemaining;
    if (current <= 1) {
      _cooldownTimer?.cancel();
      state = AsyncData(state.requireValue.copyWith(cooldownRemaining: 0));
    } else {
      state = AsyncData(
        state.requireValue.copyWith(cooldownRemaining: current - 1),
      );
    }
  }

  /// GoRouter redirect 재평가를 트리거한다.
  ///
  /// authStateProvider invalidate + [AuthChangeNotifier.triggerRedirect]
  /// 이중 호출로 확실한 redirect 재평가를 보장한다.
  /// Firebase SDK의 authStateChanges() 스트림이 reload()에 반응하지
  /// 않을 수 있으므로 (FlutterFire Issue #8777), triggerRedirect()를
  /// 호출하여 GoRouter가 redirect를 재평가하도록 강제한다.
  void _triggerRedirect() {
    ref.invalidate(authStateProvider);
    ref.read(authChangeProvider).triggerRedirect();
  }

  /// 재전송 쿨다운 타이머를 시작한다.
  ///
  /// 1초 간격으로 [VerifyEmailState.cooldownRemaining]을 감소시키고,
  /// 0에 도달하면 타이머를 정리한다.
  void _startCooldown() {
    _cooldownTimer?.cancel();
    _cooldownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!ref.mounted) {
        timer.cancel();
        return;
      }
      tickCooldown();
    });
  }

  /// 모든 Timer를 정리한다.
  void _cancelAllTimers() {
    _pollingTimer?.cancel();
    _cooldownTimer?.cancel();
  }
}
