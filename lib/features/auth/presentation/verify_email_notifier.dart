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
  @visibleForTesting
  Future<void> pollOnce() async {
    await ref.read(authRepositoryProvider).reloadUser();
    if (!ref.mounted) return;

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
  /// 쿨다운 중에는 호출하지 않아야 한다 (UI에서 버튼 비활성화).
  Future<void> resendVerification() async {
    final result = await ref
        .read(authRepositoryProvider)
        .sendEmailVerification();
    if (!ref.mounted) return;

    switch (result) {
      case Success<void>():
        state = AsyncData(
          state.requireValue.copyWith(
            cooldownRemaining: cooldownSeconds,
            error: null,
          ),
        );
        _startCooldown();
      case Failure<void>(exception: final ex):
        state = AsyncData(state.requireValue.copyWith(error: ex));
    }
  }

  /// 수동으로 이메일 인증 상태를 확인한다.
  ///
  /// [VerifyEmailState.isChecking]을 true로 설정한 뒤
  /// [AuthRepository.reloadUser]를 호출하고, emailVerified가 true이면
  /// redirect를 트리거한다. false이면 isChecking을 false로 복귀한다.
  Future<void> checkManually() async {
    state = AsyncData(state.requireValue.copyWith(isChecking: true));

    await ref.read(authRepositoryProvider).reloadUser();
    if (!ref.mounted) return;

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
