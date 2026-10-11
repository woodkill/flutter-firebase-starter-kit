// quick 261011-e6c — 세션 종료 관리자 [SessionEnding] 단위 테스트.
//
// 상태 규칙을 1:1 로 고정한다:
// - E6C-SE-01: signOut 진행 중 kind · 저장소 1회 · future 는 저장소 완료에 끝난다
// - E6C-SE-02: 저장소 완료 + 온보딩 도착(순서 무관) → 없음
// - E6C-SE-03: 비동기 throw → 걷힘 · 같은 error 전파
// - E6C-SE-04: 동기 throw → 같은 결과 · 진행 중 표식이 남지 않는다
// - E6C-SE-05: 30초 상한 → 오버레이만 걷힘(저장소 호출은 계속)
// - E6C-SE-06: 재진입 — 저장소 1회 · 타이머 불변 · 상한 뒤에는 다시 30초
// - E6C-SE-07: 탈퇴 두 단계(begin → run) · isAccountDeleted 유지
// - E6C-SE-08: 진행 중이 아닐 때의 도착 보고는 무시
// - E6C-SE-09: dispose → 타이머 0 · 그 뒤 저장소가 끝나도 예외 없음
// - E6C-SE-10: 도착이 먼저 기록된 뒤 저장소 throw → 없음
//
// 시간은 fake_async 로 넘긴다 — 관리자의 타이머는 덮는 순간(fakeAsync 본문 안의
// 호출)에 만들어지므로 fake zone 에 잡힌다.

import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:flutter_starter_kit/features/auth/application/session_ending.dart';
import 'package:flutter_starter_kit/features/auth/data/auth_repository.dart';

class _MockAuthRepository extends Mock implements AuthRepository {}

/// 로그아웃이 덮고 있는 상태.
const SessionEndingState _signingOut = (
  kind: SessionEndingKind.signOut,
  isAccountDeleted: false,
);

/// 탈퇴 마무리가 덮고 있는 상태.
const SessionEndingState _finalizing = (
  kind: SessionEndingKind.withdrawal,
  isAccountDeleted: true,
);

/// 오버레이는 걷혔지만 계정 삭제 사실은 남은 상태.
const SessionEndingState _deletedUncovered = (
  kind: SessionEndingKind.none,
  isAccountDeleted: true,
);

/// 상한 1ms 전.
final Duration _justBeforeCap =
    sessionEndingOverlayCap - const Duration(milliseconds: 1);

/// future 가 끝났는지와 그 error 를 기록한다.
class _Outcome {
  /// 정상 · 실패를 가리지 않고 끝났는지.
  bool isDone = false;

  /// 실패로 끝났을 때의 error 객체.
  Object? error;
}

/// [future] 의 종료를 [_Outcome] 에 기록한다 (error 는 여기서 소비한다).
_Outcome _track(Future<void> future) {
  final outcome = _Outcome();
  unawaited(
    future.then<void>(
      (_) => outcome.isDone = true,
      onError: (Object error) {
        outcome
          ..isDone = true
          ..error = error;
      },
    ),
  );
  return outcome;
}

void main() {
  late _MockAuthRepository repo;

  /// 저장소 mock 을 단 container 를 만든다 (dispose 는 호출자가 건다).
  ProviderContainer buildContainer() => ProviderContainer(
    overrides: [authRepositoryProvider.overrideWithValue(repo)],
  );

  /// 저장소 로그아웃이 [completer] 가 끝날 때까지 끝나지 않게 스텁한다.
  void stubPending(Completer<void> completer) {
    when(
      () => repo.signOutAndResetOnboarding(),
    ).thenAnswer((_) => completer.future);
  }

  setUp(() {
    repo = _MockAuthRepository();
  });

  group('SessionEnding 상태 규칙 (quick 261011-e6c)', () {
    test('E6C-SE-01: signOut 진행 중 kind = signOut · 저장소 1회 · future 는 저장소 '
        '완료에 끝난다(도착을 기다리지 않는다) · 그 뒤에도 덮은 채', () {
      fakeAsync((async) {
        final container = buildContainer();
        addTearDown(container.dispose);
        final repoDone = Completer<void>();
        stubPending(repoDone);
        final notifier = container.read(sessionEndingProvider.notifier);
        expect(container.read(sessionEndingProvider), idleSessionEndingState);

        final outcome = _track(notifier.signOut());
        async.flushMicrotasks();

        expect(container.read(sessionEndingProvider), _signingOut);
        verify(() => repo.signOutAndResetOnboarding()).called(1);
        expect(outcome.isDone, isFalse, reason: '저장소가 끝나기 전');
        expect(async.pendingTimers, hasLength(1), reason: '30초 상한 타이머');

        repoDone.complete();
        async.flushMicrotasks();

        expect(outcome.isDone, isTrue, reason: '온보딩 도착 없이 끝난다 (D-04)');
        expect(outcome.error, isNull);
        expect(
          container.read(sessionEndingProvider),
          _signingOut,
          reason: '오버레이는 온보딩 도착까지 남는다',
        );
        expect(async.pendingTimers, hasLength(1));
      });
    });

    test('E6C-SE-02: 저장소 완료 → 도착 = 없음 · 타이머 0 / 도착 → 저장소 완료(역순)도 '
        '없음', () {
      fakeAsync((async) {
        // 저장소 완료 → 도착.
        final container = buildContainer();
        addTearDown(container.dispose);
        final firstDone = Completer<void>();
        stubPending(firstDone);
        final notifier = container.read(sessionEndingProvider.notifier);

        final first = _track(notifier.signOut());
        firstDone.complete();
        async.flushMicrotasks();
        expect(first.isDone, isTrue);
        expect(container.read(sessionEndingProvider), _signingOut);

        notifier.handleOnboardingShown();
        expect(container.read(sessionEndingProvider), idleSessionEndingState);
        expect(async.pendingTimers, isEmpty);

        // 역순: 도착 → 저장소 완료.
        final secondDone = Completer<void>();
        stubPending(secondDone);
        final second = _track(notifier.signOut());
        async.flushMicrotasks();
        expect(container.read(sessionEndingProvider), _signingOut);

        notifier.handleOnboardingShown();
        expect(
          container.read(sessionEndingProvider),
          _signingOut,
          reason: '저장소가 아직 끝나지 않았다 — 도착만 기록한다',
        );
        expect(async.pendingTimers, hasLength(1));

        secondDone.complete();
        async.flushMicrotasks();
        expect(second.isDone, isTrue);
        expect(container.read(sessionEndingProvider), idleSessionEndingState);
        expect(async.pendingTimers, isEmpty);
        verify(() => repo.signOutAndResetOnboarding()).called(2);
      });
    });

    test('E6C-SE-03: 저장소가 비동기로 throw → kind = none · 같은 error 객체 전파 · '
        '타이머 0', () {
      fakeAsync((async) {
        final container = buildContainer();
        addTearDown(container.dispose);
        final repoDone = Completer<void>();
        stubPending(repoDone);
        final notifier = container.read(sessionEndingProvider.notifier);
        final error = StateError('sign-out failed');

        final outcome = _track(notifier.signOut());
        async.flushMicrotasks();
        expect(container.read(sessionEndingProvider), _signingOut);

        repoDone.completeError(error, StackTrace.current);
        async.flushMicrotasks();

        expect(outcome.isDone, isTrue);
        expect(identical(outcome.error, error), isTrue, reason: '같은 error 객체');
        expect(container.read(sessionEndingProvider), idleSessionEndingState);
        expect(async.pendingTimers, isEmpty);
      });
    });

    test('E6C-SE-04: 저장소가 동기로 throw → 같은 결과 · 그 뒤 재호출은 저장소를 다시 '
        '부른다(진행 중 표식이 남지 않는다)', () {
      fakeAsync((async) {
        final container = buildContainer();
        addTearDown(container.dispose);
        final error = StateError('sync sign-out failed');
        when(() => repo.signOutAndResetOnboarding()).thenThrow(error);
        final notifier = container.read(sessionEndingProvider.notifier);

        final first = _track(notifier.signOut());
        async.flushMicrotasks();

        expect(first.isDone, isTrue);
        expect(identical(first.error, error), isTrue);
        expect(container.read(sessionEndingProvider), idleSessionEndingState);
        expect(async.pendingTimers, isEmpty);

        final second = _track(notifier.signOut());
        async.flushMicrotasks();

        expect(second.isDone, isTrue);
        expect(identical(second.error, error), isTrue);
        expect(container.read(sessionEndingProvider), idleSessionEndingState);
        expect(async.pendingTimers, isEmpty);
        verify(() => repo.signOutAndResetOnboarding()).called(2);
      });
    });

    test('E6C-SE-05: 29,999ms 까지 덮은 채 → 30,000ms 에 걷힘 · 저장소 호출과 future 는 '
        '계속 → 저장소 완료 뒤 도착 = 없음', () {
      fakeAsync((async) {
        final container = buildContainer();
        addTearDown(container.dispose);
        final repoDone = Completer<void>();
        stubPending(repoDone);
        final notifier = container.read(sessionEndingProvider.notifier);
        expect(sessionEndingOverlayCap, const Duration(seconds: 30));

        final outcome = _track(notifier.signOut());
        async.elapse(_justBeforeCap);
        expect(container.read(sessionEndingProvider), _signingOut);

        async.elapse(const Duration(milliseconds: 1));
        expect(
          container.read(sessionEndingProvider).kind,
          SessionEndingKind.none,
          reason: '상한 — 오버레이만 걷는다',
        );
        expect(outcome.isDone, isFalse, reason: '저장소 호출은 취소하지 않는다');
        expect(repoDone.isCompleted, isFalse);
        expect(async.pendingTimers, isEmpty);

        repoDone.complete();
        async.flushMicrotasks();
        expect(outcome.isDone, isTrue);
        expect(outcome.error, isNull);

        notifier.handleOnboardingShown();
        expect(container.read(sessionEndingProvider), idleSessionEndingState);
        expect(async.pendingTimers, isEmpty);
        verify(() => repo.signOutAndResetOnboarding()).called(1);
      });
    });

    test('E6C-SE-06: 진행 중 재호출 = 저장소 1회 · 타이머 불변 / 상한 뒤 재호출 = 다시 '
        '덮고 그때부터 30초 · 저장소 여전히 1회 · 세 future 가 한 번에 끝난다', () {
      fakeAsync((async) {
        final container = buildContainer();
        addTearDown(container.dispose);
        final repoDone = Completer<void>();
        stubPending(repoDone);
        final notifier = container.read(sessionEndingProvider.notifier);

        final first = _track(notifier.signOut());
        async.elapse(const Duration(seconds: 10));

        // 진행 중 두 번째 호출 — 타이머를 다시 재지 않는다.
        final second = _track(notifier.signOut());
        async.flushMicrotasks();
        expect(async.pendingTimers, hasLength(1));
        async.elapse(
          const Duration(seconds: 20) - const Duration(milliseconds: 1),
        );
        expect(container.read(sessionEndingProvider), _signingOut);
        async.elapse(const Duration(milliseconds: 1));
        expect(
          container.read(sessionEndingProvider).kind,
          SessionEndingKind.none,
          reason: '첫 시작부터 30초에 걷힌다',
        );

        // 상한 뒤 세 번째 호출 — 다시 덮고 30초를 새로 잰다.
        async.elapse(const Duration(seconds: 10));
        final third = _track(notifier.signOut());
        async.flushMicrotasks();
        expect(container.read(sessionEndingProvider), _signingOut);
        expect(async.pendingTimers, hasLength(1));
        async.elapse(_justBeforeCap);
        expect(container.read(sessionEndingProvider), _signingOut);
        async.elapse(const Duration(milliseconds: 1));
        expect(
          container.read(sessionEndingProvider).kind,
          SessionEndingKind.none,
        );

        expect(first.isDone || second.isDone || third.isDone, isFalse);
        repoDone.complete();
        async.flushMicrotasks();
        expect(first.isDone && second.isDone && third.isDone, isTrue);
        expect(first.error ?? second.error ?? third.error, isNull);
        verify(() => repo.signOutAndResetOnboarding()).called(1);
        expect(async.pendingTimers, isEmpty);
      });
    });

    test('E6C-SE-07: 탈퇴 두 단계 — begin = (withdrawal, 삭제됨) · 저장소 0회 → run = '
        '1회 → throw · 상한 뒤에도 삭제됨 유지 → 도착 = 없음', () {
      fakeAsync((async) {
        final container = buildContainer();
        addTearDown(container.dispose);
        final firstDone = Completer<void>();
        stubPending(firstDone);
        final notifier = container.read(sessionEndingProvider.notifier);
        final error = StateError('cleanup failed');

        notifier.beginWithdrawalCleanup();
        expect(container.read(sessionEndingProvider), _finalizing);
        verifyNever(() => repo.signOutAndResetOnboarding());
        expect(async.pendingTimers, hasLength(1));

        final first = _track(notifier.runWithdrawalCleanup());
        async.flushMicrotasks();
        expect(container.read(sessionEndingProvider), _finalizing);
        expect(async.pendingTimers, hasLength(1), reason: 'begin 의 타이머 그대로');

        firstDone.completeError(error, StackTrace.current);
        async.flushMicrotasks();
        expect(identical(first.error, error), isTrue);
        expect(
          container.read(sessionEndingProvider),
          _deletedUncovered,
          reason: '실패로 걷혀도 삭제 사실은 남는다',
        );
        expect(async.pendingTimers, isEmpty);

        // 다시 begin · run → 상한.
        final secondDone = Completer<void>();
        stubPending(secondDone);
        notifier.beginWithdrawalCleanup();
        final second = _track(notifier.runWithdrawalCleanup());
        async.flushMicrotasks();
        expect(container.read(sessionEndingProvider), _finalizing);

        async.elapse(sessionEndingOverlayCap);
        expect(container.read(sessionEndingProvider), _deletedUncovered);
        expect(second.isDone, isFalse);

        secondDone.complete();
        async.flushMicrotasks();
        expect(second.isDone, isTrue);
        expect(
          container.read(sessionEndingProvider),
          _deletedUncovered,
          reason: '온보딩에 닿기 전까지 삭제 사실은 남는다',
        );

        notifier.handleOnboardingShown();
        expect(container.read(sessionEndingProvider), idleSessionEndingState);
        expect(async.pendingTimers, isEmpty);
        verify(() => repo.signOutAndResetOnboarding()).called(2);
      });
    });

    test('E6C-SE-08: 진행 중이 아닐 때 handleOnboardingShown 은 상태를 바꾸지 않고 '
        '도착도 기록하지 않는다', () {
      fakeAsync((async) {
        final container = buildContainer();
        addTearDown(container.dispose);
        final repoDone = Completer<void>();
        stubPending(repoDone);
        final notifier = container.read(sessionEndingProvider.notifier);
        var notifications = 0;
        container.listen(sessionEndingProvider, (_, _) => notifications++);

        notifier.handleOnboardingShown();
        async.flushMicrotasks();

        expect(container.read(sessionEndingProvider), idleSessionEndingState);
        expect(notifications, 0);
        expect(async.pendingTimers, isEmpty);

        // 그 보고가 기록됐다면 아래 로그아웃은 저장소 완료와 동시에 걷힌다.
        final outcome = _track(notifier.signOut());
        repoDone.complete();
        async.flushMicrotasks();
        expect(outcome.isDone, isTrue);
        expect(
          container.read(sessionEndingProvider),
          _signingOut,
          reason: '진행 중이 아닐 때의 도착 보고는 다음 구간으로 넘어가지 않는다',
        );
      });
    });

    test('E6C-SE-09: 진행 중 dispose → 타이머 0 · 그 뒤 저장소가 끝나도 예외 없이 '
        'future 가 끝난다', () {
      fakeAsync((async) {
        final container = buildContainer();
        final repoDone = Completer<void>();
        stubPending(repoDone);
        final notifier = container.read(sessionEndingProvider.notifier);

        final outcome = _track(notifier.signOut());
        async.flushMicrotasks();
        expect(async.pendingTimers, hasLength(1));

        container.dispose();
        expect(async.pendingTimers, isEmpty, reason: 'dispose 가 타이머를 취소한다');

        repoDone.complete();
        async.flushMicrotasks();
        async.elapse(sessionEndingOverlayCap);

        expect(outcome.isDone, isTrue);
        expect(outcome.error, isNull);
      });
    });

    test('E6C-SE-10: 도착이 먼저 기록된 뒤 저장소 throw → 없음(삭제됨이 켜져 있었어도) · '
        'error 전파', () {
      fakeAsync((async) {
        final container = buildContainer();
        addTearDown(container.dispose);
        final repoDone = Completer<void>();
        stubPending(repoDone);
        final notifier = container.read(sessionEndingProvider.notifier);
        final error = StateError('cleanup failed after arrival');

        final outcome = _track(notifier.runWithdrawalCleanup());
        async.flushMicrotasks();
        expect(container.read(sessionEndingProvider), _finalizing);

        notifier.handleOnboardingShown();
        expect(container.read(sessionEndingProvider), _finalizing);

        repoDone.completeError(error, StackTrace.current);
        async.flushMicrotasks();

        expect(identical(outcome.error, error), isTrue);
        expect(
          container.read(sessionEndingProvider),
          idleSessionEndingState,
          reason: '이미 온보딩에 닿았다 — 잠글 화면이 없다',
        );
        expect(async.pendingTimers, isEmpty);
      });
    });
  });
}
