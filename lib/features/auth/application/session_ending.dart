// quick 261011-e6c — 세션 종료(로그아웃 · 회원탈퇴 마무리) 관리자.
//
// 로그아웃을 확인한 직후(회원탈퇴는 서버 삭제가 끝난 직후)부터 온보딩 화면이 뜰
// 때까지 앱 최상위 오버레이(`SessionEndingOverlay`)가 화면 전체를 덮는다. 이
// 파일은 그 구간의 상태와 저장소 로그아웃 호출을 한 곳에서 맡는다.
//
// 걷히는 조건 3가지:
//   1. 저장소 호출이 끝났고 **그리고** 온보딩 route 의 진입 전환이 끝났다
//      (`SessionEndingArrival` 이 알린다 — 두 사건의 순서는 무관).
//   2. 저장소 호출이 예외로 끝났다 — 즉시 걷고 같은 예외를 호출자에게 넘긴다.
//   3. 덮은 지 [sessionEndingOverlayCap] 이 지났다 — 오버레이만 걷는다(저장소
//      호출은 취소하지 않는다).
import 'dart:async';

import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../data/auth_repository.dart';

part 'session_ending.g.dart';

/// 지금 오버레이가 덮고 있는 세션 종료의 종류.
enum SessionEndingKind {
  /// 덮고 있지 않다 — 오버레이 없음.
  none,

  /// 로그아웃 진행 중 (문구 `authSigningOut`).
  signOut,

  /// 회원탈퇴 마무리 중 — 서버 삭제는 이미 끝났다 (문구 `withdrawalFinalizing`).
  withdrawal,
}

/// [SessionEnding] 이 노출하는 불변 state.
///
/// - [kind] — 지금 오버레이가 덮는 종류. [SessionEndingKind.none] 이면 오버레이가
///   없다.
/// - [isAccountDeleted] — 이 프로세스에서 서버 계정 삭제가 확정됐고 아직 온보딩
///   화면에 닿지 않았다. 오버레이가 실패 · 상한으로 걷힌 뒤에도 `true` 로 남아
///   「탈퇴」 버튼을 잠근다.
typedef SessionEndingState = ({SessionEndingKind kind, bool isAccountDeleted});

/// 진행 중인 세션 종료가 없는 초기 [SessionEndingState].
const SessionEndingState idleSessionEndingState = (
  kind: SessionEndingKind.none,
  isAccountDeleted: false,
);

/// 오버레이가 덮을 수 있는 최대 시간 — 덮기 시작한 시점부터 잰다.
///
/// 상한에 닿으면 오버레이만 걷는다. 저장소 로그아웃 호출은 그대로 진행한다.
const Duration sessionEndingOverlayCap = Duration(seconds: 30);

/// 세션 종료 구간(로그아웃 · 회원탈퇴 마무리)의 상태와 저장소 로그아웃 호출을
/// 맡는 관리자 (quick 261011-e6c).
///
/// **저장소 로그아웃 함수의 유일한 lib 호출자다.** 화면 · notifier 는
/// [AuthRepository.signOutAndResetOnboarding] 을 직접 부르지 않고 [signOut] ·
/// [runWithdrawalCleanup] 을 거친다 — 그래야 진행 오버레이가 모든 진입점에서
/// 같은 규칙으로 켜지고 꺼진다(호출 파일 집합은 T-171-HOME-16 이 고정한다).
///
/// **future 가 끝나는 시점:** [signOut] · [runWithdrawalCleanup] 이 돌려주는
/// future 는 저장소 호출이 끝나면 끝난다. 온보딩 도착을 기다리지 않는다 —
/// 오버레이가 걷히는 시점은 future 완료와 별개다.
///
/// **`keepAlive` 인 이유:** 호출한 notifier · 화면은 로그아웃 도중 사라진다
/// (라우터가 온보딩으로 보낸다). 그 뒤에도 저장소 호출의 종료 처리와 상한
/// 타이머 정리가 도달해야 한다 — auto-dispose 면 상태가 진행 중인 채 버려지거나
/// 새 인스턴스가 「없음」 으로 시작해 오버레이가 중간에 사라진다.
@Riverpod(keepAlive: true)
class SessionEnding extends _$SessionEnding {
  /// 진행 중인 저장소 로그아웃 호출의 future — 없으면 `null` (진행 중 표식).
  Future<void>? _pendingSignOut;

  /// 온보딩 route 진입 전환이 끝났다는 보고를 받았는지.
  bool _hasArrived = false;

  /// 덮은 시점부터 [sessionEndingOverlayCap] 을 재는 타이머.
  Timer? _capTimer;

  /// 초기 상태는 [idleSessionEndingState] — 진행 중인 세션 종료가 없다.
  @override
  SessionEndingState build() {
    // 타이머가 남으면 dispose 뒤에 state 를 건드리게 된다.
    ref.onDispose(_cancelCapTimer);
    return idleSessionEndingState;
  }

  /// 로그아웃을 시작한다 — 오버레이를 덮고 저장소 로그아웃을 부른다.
  ///
  /// 돌려주는 future 는 저장소 호출이 끝나면 끝나고, 저장소가 던진 예외를 같은
  /// error · stack 으로 넘긴다(오버레이는 그 전에 걷힌다). 이미 저장소 호출이
  /// 진행 중이면 다시 부르지 않고 같은 future 를 돌려준다.
  Future<void> signOut() {
    _cover(SessionEndingKind.signOut);
    return _runRepositorySignOut();
  }

  /// 서버 계정 삭제가 확정된 직후 회원탈퇴 마무리 구간을 연다 (동기).
  ///
  /// 성공을 화면에 알리기 **전에** 부른다 — 화면의 잠금이 풀리는 프레임에 이미
  /// 오버레이와 `isAccountDeleted` 가 켜져 있어야 틈이 없다. 저장소는 부르지
  /// 않는다([runWithdrawalCleanup] 이 한다).
  void beginWithdrawalCleanup() => _cover(SessionEndingKind.withdrawal);

  /// 회원탈퇴 사후 정리(저장소 로그아웃)를 실행한다.
  ///
  /// [beginWithdrawalCleanup] 이 먼저 불리지 않았어도 같은 상태에서 시작한다.
  /// future 규칙은 [signOut] 과 같다.
  Future<void> runWithdrawalCleanup() {
    _cover(SessionEndingKind.withdrawal);
    return _runRepositorySignOut();
  }

  /// 온보딩 route 의 진입 전환이 끝났음을 받는다.
  ///
  /// `SessionEndingArrival` 전용이다 — 다른 곳에서 부르지 않는다(T-171-HOME-16).
  /// 진행 중인 세션 종료가 없으면 아무것도 하지 않는다. 저장소 호출이 아직
  /// 진행 중이면 도착만 기록하고, 호출이 끝날 때 「없음」 으로 돌아간다.
  void handleOnboardingShown() {
    if (state == idleSessionEndingState && _pendingSignOut == null) {
      return;
    }
    _hasArrived = true;
    _settleIfDone();
  }

  /// 오버레이를 [kind] 로 덮는다.
  ///
  /// 이미 덮여 있으면 종류와 상한 타이머는 그대로 두고 `isAccountDeleted` 만
  /// 반영한다. 덮여 있지 않으면 상한을 새로 재기 시작한다 — 상한으로 걷힌 뒤의
  /// 재진입도 여기로 온다.
  void _cover(SessionEndingKind kind) {
    final current = state;
    final isAccountDeleted =
        current.isAccountDeleted || kind == SessionEndingKind.withdrawal;
    if (current.kind != SessionEndingKind.none) {
      state = (kind: current.kind, isAccountDeleted: isAccountDeleted);
      return;
    }
    if (_pendingSignOut == null) {
      // 새 구간의 시작 — 지난 구간의 도착 기록을 물려받지 않는다.
      _hasArrived = false;
    }
    _cancelCapTimer();
    _capTimer = Timer(sessionEndingOverlayCap, _handleCapElapsed);
    state = (kind: kind, isAccountDeleted: isAccountDeleted);
  }

  /// 저장소 로그아웃을 1회 실행하고 그 future 를 돌려준다.
  ///
  /// 진행 중인 호출이 있으면 그 future 를 그대로 돌려준다(저장소 재호출 0).
  Future<void> _runRepositorySignOut() {
    final pending = _pendingSignOut;
    if (pending != null) {
      return pending;
    }
    final completer = Completer<void>();
    // 표식은 저장소를 부르기 **전에** 세운다 — 저장소가 동기적으로 throw 하면
    // 아래 처리가 이 대입보다 먼저 끝나므로, 호출 뒤에 세우면 실패한 future 가
    // 표식으로 남아 이후 모든 호출이 저장소를 부르지 않는다.
    _pendingSignOut = completer.future;
    unawaited(_driveRepositorySignOut(completer));
    return completer.future;
  }

  /// 저장소 호출을 기다렸다가 결과를 [completer] 와 state 에 반영한다.
  Future<void> _driveRepositorySignOut(Completer<void> completer) async {
    try {
      await ref.read(authRepositoryProvider).signOutAndResetOnboarding();
    } on Object catch (error, stackTrace) {
      _pendingSignOut = null;
      // await 뒤에는 provider 가 이미 dispose 됐을 수 있다.
      if (ref.mounted) {
        _uncover();
        _settleIfDone();
      }
      completer.completeError(error, stackTrace);
      return;
    }
    _pendingSignOut = null;
    if (ref.mounted) {
      _settleIfDone();
    }
    completer.complete();
  }

  /// 상한에 닿았다 — 오버레이만 걷는다(저장소 호출 · `isAccountDeleted` 불변).
  void _handleCapElapsed() {
    _capTimer = null;
    if (!ref.mounted) {
      return;
    }
    _uncover();
  }

  /// 오버레이를 걷는다 — `isAccountDeleted` 는 그대로 둔다.
  void _uncover() {
    _cancelCapTimer();
    final current = state;
    if (current.kind == SessionEndingKind.none) {
      return;
    }
    state = (
      kind: SessionEndingKind.none,
      isAccountDeleted: current.isAccountDeleted,
    );
  }

  /// 온보딩에 닿았고 저장소 호출도 끝났으면 「없음」 으로 돌아간다.
  void _settleIfDone() {
    if (!_hasArrived || _pendingSignOut != null) {
      return;
    }
    _cancelCapTimer();
    _hasArrived = false;
    state = idleSessionEndingState;
  }

  /// 상한 타이머를 취소한다.
  void _cancelCapTimer() {
    _capTimer?.cancel();
    _capTimer = null;
  }
}
