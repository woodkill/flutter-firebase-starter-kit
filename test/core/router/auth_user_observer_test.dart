import 'dart:async';
import 'dart:io';

import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:flutter_starter_kit/core/analytics/analytics_service.dart';
import 'package:flutter_starter_kit/core/crashlytics/crashlytics_service.dart';
import 'package:flutter_starter_kit/core/error/result.dart';
import 'package:flutter_starter_kit/core/providers/firebase_providers.dart';
import 'package:flutter_starter_kit/core/router/auth_guard.dart';
import 'package:flutter_starter_kit/core/router/auth_refresh.dart';
import 'package:flutter_starter_kit/features/terms/domain/terms_acceptance.dart';
import 'package:flutter_starter_kit/features/terms/domain/terms_state.dart';
import 'package:flutter_starter_kit/features/terms/presentation/terms_notifier.dart';

class _MockFirebaseAnalytics extends Mock implements FirebaseAnalytics {}

class _MockFirebaseCrashlytics extends Mock implements FirebaseCrashlytics {}

class _MockUser extends Mock implements fb.User {}

class _FakeFirebaseAuth extends Fake implements fb.FirebaseAuth {
  _FakeFirebaseAuth(Stream<fb.User?> stream)
    : _stream = stream.asBroadcastStream();

  /// asBroadcastStream 으로 래핑하여 multi-subscription 을 허용한다.
  /// Plan 10-11 Issue #7 C-3 도입 이후 authUserObserver 뿐 아니라
  /// authRefreshProvider 의 [AuthRefresh] 도 동일 auth.userChanges()
  /// 를 listen 하므로, single-subscription stream 이면 두 번째 listen 에서
  /// `Bad state: Stream has already been listened to.` 가 발생한다.
  /// 실제 Firebase SDK 의 userChanges() 도 broadcast 성격을 갖는다.
  final Stream<fb.User?> _stream;

  @override
  Stream<fb.User?> authStateChanges() => _stream;

  @override
  Stream<fb.User?> userChanges() => _stream;
}

/// [_SpyAuthRefresh] 의 강제 재평가 호출 횟수를 notifier 밖에 두는 recorder.
///
/// fake notifier 에 public 필드 · getter 를 만들지 않기 위해(quick 260920-4h7
/// 패턴, riverpod_lint `avoid_public_notifier_properties`) 기록은 생성자로
/// 주입한 외부 객체가 담는다.
class _TriggerRecorder {
  int count = 0;
}

/// `triggerRedirect()` 호출만 가로채는 spy [AuthRefresh].
///
/// 실제 구현과 달리 `userChanges()` 를 구독하지 않고 초기 state 만 반환한다 —
/// 따라서 [_TriggerRecorder.count] 증가의 **유일한** 원인은 강제 재평가 호출
/// 이다 (옛 구조에서 별도 empty stream spy 로 얻던 격리와 동일한 의도).
class _SpyAuthRefresh extends AuthRefresh {
  _SpyAuthRefresh(this._recorder);

  final _TriggerRecorder _recorder;

  @override
  AuthRefreshState build() => initialAuthRefreshState;

  @override
  void triggerRedirect() => _recorder.count++;
}

/// [_RecordingTermsNotifier] 의 호출 기록과 제어 입력을 notifier 밖에 두는
/// recorder.
///
/// riverpod_lint `avoid_public_notifier_properties` — fake notifier 가 public
/// 필드를 노출하지 않도록 기록 상태를 이 객체로 분리하고, notifier 는
/// 생성자로 받은 recorder 에만 기록한다.
class _TermsCallRecorder {
  /// [TermsNotifier.mirrorToFirestore] 호출 uid 기록.
  final List<String> mirrorCalls = <String>[];

  /// Issue #9 (Plan 10-13) 회귀 가드: authUserObserver 의 자동 mirror 호출은
  /// force 파라미터의 기본값(false) 을 유지해야 한다 (Plan 10-12 multi-user
  /// invariant 보존). 각 호출의 force 값을 기록하여 검증 가능하게 한다.
  final List<bool> mirrorForceCalls = <bool>[];

  /// [TermsNotifier.reloadForUser] 호출 uid 기록 (코드 리뷰 05 WR-03 재시도
  /// 검증용).
  final List<String?> reloadCalls = <String?>[];

  /// true 면 [TermsNotifier.reloadForUser] 가 throw 하여 tick 실패를 재현한다
  /// (WR-03). notifier 가 호출 시점에 읽는다.
  bool shouldThrowOnReload = false;
}

/// `mirrorToFirestore` 호출 카운트를 검증하기 위한 stub TermsNotifier.
///
/// Plan 10-09: [reloadForUser] 도 stub override 추가 (실제 메서드는
/// firebaseFirestoreProvider mock 이 필요한데, 본 테스트는 Firestore 검증
/// 범위 외이므로 no-op 으로 처리. 실제 reload 동작은
/// terms_notifier_firestore_test 와 terms_notifier_uid_change_test 에서 검증).
/// 호출 기록은 [_TermsCallRecorder] 에 남긴다.
class _RecordingTermsNotifier extends TermsNotifier {
  /// 호출을 주입된 recorder 에 기록하는 stub 을 만든다.
  _RecordingTermsNotifier(this._recorder);

  final _TermsCallRecorder _recorder;

  @override
  TermsState build() => TermsState(
    acceptance: TermsAcceptance(
      version: TermsNotifier.currentVersion,
      service: true,
      privacy: true,
      marketing: false,
      acceptedAt: DateTime.utc(2026, 4, 14),
    ),
  );

  @override
  Future<Result<void>> mirrorToFirestore({
    required String uid,
    bool force = false,
  }) async {
    _recorder.mirrorCalls.add(uid);
    _recorder.mirrorForceCalls.add(force);
    return const Result.success(null);
  }

  @override
  Future<void> reloadForUser({String? uid, bool isAnonymous = false}) async {
    // no-op — 본 테스트의 검증 범위 외 (Plan 10-09 신규 호출 stub).
    _recorder.reloadCalls.add(uid);
    if (_recorder.shouldThrowOnReload) {
      // `on Exception` 으로 잡히지 않는 Error 계열 — WR-03 이 지목한
      // 플랫폼 채널 Error 를 대표한다.
      throw StateError('reloadForUser failed');
    }
  }
}

void main() {
  setUpAll(() {
    registerFallbackValue(StackTrace.empty);
  });

  /// [email] 과 [emailVerified] 도 반드시 stub 한다 — [AuthRefresh] 의
  /// distinct 가드(Phase 9 UAT Gap 2)가 emit 마다 네 필드 스냅샷을 읽으므로,
  /// 미stub mock 은 `type 'Null' is not a subtype of type 'bool'` 로 죽는다.
  fb.User makeUser({
    required String uid,
    required bool isAnonymous,
    String? email,
    bool emailVerified = false,
  }) {
    final user = _MockUser();
    when(() => user.uid).thenReturn(uid);
    when(() => user.isAnonymous).thenReturn(isAnonymous);
    when(() => user.email).thenReturn(email);
    when(() => user.emailVerified).thenReturn(emailVerified);
    return user;
  }

  /// authStateChanges fake stream 을 외부에서 push 할 수 있도록 controller 를
  /// override 한다. authStateProvider 는 firebaseAuthProvider 의
  /// authStateChanges() 를 그대로 watch 하므로, authStateProvider 자체를
  /// override 한다.
  ProviderContainer makeContainer({
    required StreamController<fb.User?> controller,
    required FirebaseAnalytics analytics,
    required FirebaseCrashlytics crashlytics,
    required _RecordingTermsNotifier terms,
  }) {
    final fakeAuth = _FakeFirebaseAuth(controller.stream);
    return ProviderContainer(
      overrides: [
        isFirebaseInitializedProvider.overrideWithValue(true),
        firebaseAuthProvider.overrideWithValue(fakeAuth),
        firebaseAnalyticsProvider.overrideWithValue(analytics),
        firebaseCrashlyticsProvider.overrideWithValue(crashlytics),
        analyticsServiceProvider.overrideWith(
          (ref) => AnalyticsService(analytics, isEnabled: true),
        ),
        crashlyticsServiceProvider.overrideWith(
          (ref) => CrashlyticsService(crashlytics, isEnabled: true),
        ),
        termsProvider.overrideWith(() => terms),
      ],
    );
  }

  void stubAnalytics(_MockFirebaseAnalytics analytics) {
    when(
      () => analytics.setUserProperty(
        name: any(named: 'name'),
        value: any(named: 'value'),
      ),
    ).thenAnswer((_) async {});
    when(
      () => analytics.setUserId(id: any(named: 'id')),
    ).thenAnswer((_) async {});
  }

  void stubCrashlytics(_MockFirebaseCrashlytics crashlytics) {
    when(() => crashlytics.setUserIdentifier(any())).thenAnswer((_) async {});
    when(
      () => crashlytics.recordError(
        any<Object>(),
        any<StackTrace?>(),
        reason: any(named: 'reason'),
        fatal: any(named: 'fatal'),
      ),
    ).thenAnswer((_) async {});
  }

  group('authUserObserver (Phase 10 D-30, BLOCKER #4, INFO #21)', () {
    test(
      'Test 1: 익명 User emit -> setGuestMode(true) + setUserId + Crashlytics setUserId (mirrorToFirestore 호출 없음)',
      () async {
        final controller = StreamController<fb.User?>();
        addTearDown(controller.close);
        final analytics = _MockFirebaseAnalytics();
        final crashlytics = _MockFirebaseCrashlytics();
        stubAnalytics(analytics);
        stubCrashlytics(crashlytics);
        final recorder = _TermsCallRecorder();
        final terms = _RecordingTermsNotifier(recorder);

        final container = makeContainer(
          controller: controller,
          analytics: analytics,
          crashlytics: crashlytics,
          terms: terms,
        );
        addTearDown(container.dispose);

        // Stream subscription 을 활성화한다.
        final sub = container.listen(authUserObserverProvider, (_, _) {});
        addTearDown(sub.close);

        controller.add(makeUser(uid: 'anon-1', isAnonymous: true));
        // microtask + listen 처리 대기.
        await Future<void>.delayed(Duration.zero);

        verify(
          () => analytics.setUserProperty(name: 'guest_mode', value: 'true'),
        ).called(1);
        verify(() => analytics.setUserId(id: 'anon-1')).called(1);
        verify(() => crashlytics.setUserIdentifier('anon-1')).called(1);
        expect(
          recorder.mirrorCalls,
          isEmpty,
          reason: '익명 첫 emit 은 전이가 아니므로 mirror 호출 안 함',
        );
      },
    );

    test(
      'Test 2: 정식 User 첫 emit (prev=null) -> setGuestMode(false) + setUserId, mirror 호출 없음',
      () async {
        final controller = StreamController<fb.User?>();
        addTearDown(controller.close);
        final analytics = _MockFirebaseAnalytics();
        final crashlytics = _MockFirebaseCrashlytics();
        stubAnalytics(analytics);
        stubCrashlytics(crashlytics);
        final recorder = _TermsCallRecorder();
        final terms = _RecordingTermsNotifier(recorder);

        final container = makeContainer(
          controller: controller,
          analytics: analytics,
          crashlytics: crashlytics,
          terms: terms,
        );
        addTearDown(container.dispose);
        final sub = container.listen(authUserObserverProvider, (_, _) {});
        addTearDown(sub.close);

        controller.add(makeUser(uid: 'reg-1', isAnonymous: false));
        await Future<void>.delayed(Duration.zero);

        verify(
          () => analytics.setUserProperty(name: 'guest_mode', value: 'false'),
        ).called(1);
        verify(() => analytics.setUserId(id: 'reg-1')).called(1);
        verify(() => crashlytics.setUserIdentifier('reg-1')).called(1);
        expect(
          recorder.mirrorCalls,
          isEmpty,
          reason: 'prev=null 이므로 전이로 간주하지 않는다',
        );
      },
    );

    test(
      'Test 3 (BLOCKER #4): 익명 -> 정식 전이 시 mirrorToFirestore(uid:reg-1) 정확히 1회 호출',
      () async {
        final controller = StreamController<fb.User?>();
        addTearDown(controller.close);
        final analytics = _MockFirebaseAnalytics();
        final crashlytics = _MockFirebaseCrashlytics();
        stubAnalytics(analytics);
        stubCrashlytics(crashlytics);
        final recorder = _TermsCallRecorder();
        final terms = _RecordingTermsNotifier(recorder);

        final container = makeContainer(
          controller: controller,
          analytics: analytics,
          crashlytics: crashlytics,
          terms: terms,
        );
        addTearDown(container.dispose);
        final sub = container.listen(authUserObserverProvider, (_, _) {});
        addTearDown(sub.close);

        // 1) 익명 emit
        controller.add(makeUser(uid: 'anon-1', isAnonymous: true));
        await Future<void>.delayed(Duration.zero);
        expect(recorder.mirrorCalls, isEmpty);

        // 2) 정식 emit (전이)
        controller.add(makeUser(uid: 'reg-1', isAnonymous: false));
        await Future<void>.delayed(Duration.zero);

        expect(recorder.mirrorCalls, [
          'reg-1',
        ], reason: 'BLOCKER #4 — 익명->정식 전이 1회 mirror 호출');
        // Issue #9 (Plan 10-13) 회귀 가드: 자동 mirror 경로는 force 파라미터의
        // 기본값(false) 을 유지해야 한다. Plan 10-12 multi-user invariant
        // (pre-read + snapshot.exists skip) 이 보존되도록 보장.
        expect(
          recorder.mirrorForceCalls,
          [false],
          reason:
              'Plan 10-13 — authUserObserver 자동 경로는 force=false 유지 '
              '(명시적 재동의 의도는 오직 OnboardingScreen._handleCta 만 force=true 호출)',
        );
      },
    );

    test(
      'Test 4: null User emit (signOut) -> setUserId(null), mirror 호출 없음',
      () async {
        final controller = StreamController<fb.User?>();
        addTearDown(controller.close);
        final analytics = _MockFirebaseAnalytics();
        final crashlytics = _MockFirebaseCrashlytics();
        stubAnalytics(analytics);
        stubCrashlytics(crashlytics);
        final recorder = _TermsCallRecorder();
        final terms = _RecordingTermsNotifier(recorder);

        final container = makeContainer(
          controller: controller,
          analytics: analytics,
          crashlytics: crashlytics,
          terms: terms,
        );
        addTearDown(container.dispose);
        final sub = container.listen(authUserObserverProvider, (_, _) {});
        addTearDown(sub.close);

        controller.add(null);
        await Future<void>.delayed(Duration.zero);

        verify(
          () => analytics.setUserProperty(name: 'guest_mode', value: 'false'),
        ).called(1);
        verify(() => analytics.setUserId(id: null)).called(1);
        verify(() => crashlytics.setUserIdentifier('')).called(1);
        expect(recorder.mirrorCalls, isEmpty);
      },
    );

    test('Test 6 (Issue #7 C-3 Plan 10-11): reloadForUser 완료 후 '
        'authRefreshProvider.triggerRedirect() 1회 이상 호출됨', () async {
      // Issue #7 핵심 회귀 가드: authUserObserver 가 reloadForUser 를
      // await 한 직후 AuthRefresh.triggerRedirect() 를 호출하여
      // GoRouter refreshListenable 의 재평가를 명시적으로 유도하는지
      // 확인한다. spy AuthRefresh 가 호출 카운트를 recorder 에 기록한다.
      final controller = StreamController<fb.User?>();
      addTearDown(controller.close);
      final analytics = _MockFirebaseAnalytics();
      final crashlytics = _MockFirebaseCrashlytics();
      stubAnalytics(analytics);
      stubCrashlytics(crashlytics);
      final recorder = _TermsCallRecorder();
      final terms = _RecordingTermsNotifier(recorder);

      // Spy AuthRefresh — userChanges 를 구독하지 않으므로 외부 emit 으로는
      // 카운트가 증가하지 않는다. 즉, 카운트 증가의 유일한 원인은
      // triggerRedirect() 호출이다.
      final triggerRecorder = _TriggerRecorder();

      final fakeAuth = _FakeFirebaseAuth(controller.stream);
      final container = ProviderContainer(
        overrides: [
          isFirebaseInitializedProvider.overrideWithValue(true),
          firebaseAuthProvider.overrideWithValue(fakeAuth),
          firebaseAnalyticsProvider.overrideWithValue(analytics),
          firebaseCrashlyticsProvider.overrideWithValue(crashlytics),
          analyticsServiceProvider.overrideWith(
            (ref) => AnalyticsService(analytics, isEnabled: true),
          ),
          crashlyticsServiceProvider.overrideWith(
            (ref) => CrashlyticsService(crashlytics, isEnabled: true),
          ),
          termsProvider.overrideWith(() => terms),
          authRefreshProvider.overrideWith(
            () => _SpyAuthRefresh(triggerRecorder),
          ),
        ],
      );
      addTearDown(container.dispose);
      final sub = container.listen(authUserObserverProvider, (_, _) {});
      addTearDown(sub.close);

      // 정식 user emit — isFirstEmit 이므로 reloadForUser 호출 + 그 직후
      // triggerRedirect() 호출 경로에 진입한다.
      controller.add(makeUser(uid: 'FULL-UID', isAnonymous: false));
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(
        triggerRecorder.count,
        greaterThanOrEqualTo(1),
        reason:
            'Issue #7 C-3 — reloadForUser 완료 후 authRefreshProvider.'
            'triggerRedirect() 가 최소 1회 호출되어야 GoRouter 가 stale '
            '가드를 벗어날 수 있다',
      );
    });

    test(
      'Test 5 (INFO #21): authUserObserver 소스에 ref.keepAlive() 호출 포함',
      () async {
        // Provider rebuild 시 churn 방지 — 소스 검증.
        final source = await File(
          'lib/core/router/auth_guard.dart',
        ).readAsString();
        expect(
          source.contains('ref.keepAlive()'),
          isTrue,
          reason: 'INFO #21: authUserObserver 는 ref.keepAlive() 를 호출해야 한다',
        );
        // BLOCKER #4 mirror 호출 코드 존재도 함께 검증.
        expect(
          source.contains('mirrorToFirestore(uid:'),
          isTrue,
          reason: 'BLOCKER #4: 전이 분기에서 mirrorToFirestore(uid:) 호출 필요',
        );
        // 전이 감지 변수.
        expect(
          source.contains('prevIsAnonymous'),
          isTrue,
          reason: '전이 감지를 위한 prevIsAnonymous 캐시 변수 필요',
        );
      },
    );
  });

  group('authUserObserver 에러 격리 — 코드 리뷰 05 WR-03 회귀 가드', () {
    // observer 는 termsProvider.reloadForUser 와
    // authRefreshProvider.triggerRedirect() 의 유일한 호출자다. 한 번 죽으면
    // lastReloadedUid 가 갱신되지 않아 resolveAuthRedirect 분기 (3)(5) 의 stale
    // 가드가 영구히 null 을 반환하고 사용자가 현재 위치에 무기한 고정된다.

    /// WR-03 시나리오용 컨테이너 + 활성 구독을 만든다.
    ({ProviderContainer container, _TermsCallRecorder recorder}) makeObserver(
      StreamController<fb.User?> controller,
      _MockFirebaseCrashlytics crashlytics,
    ) {
      final analytics = _MockFirebaseAnalytics();
      stubAnalytics(analytics);
      stubCrashlytics(crashlytics);
      final recorder = _TermsCallRecorder();
      final terms = _RecordingTermsNotifier(recorder);
      final container = makeContainer(
        controller: controller,
        analytics: analytics,
        crashlytics: crashlytics,
        terms: terms,
      );
      addTearDown(container.dispose);
      final sub = container.listen(authUserObserverProvider, (_, _) {});
      addTearDown(sub.close);
      return (container: container, recorder: recorder);
    }

    test('WR-03-A: 스트림 에러가 observer 를 죽이지 않고 이후 emit 을 계속 처리한다', () async {
      final controller = StreamController<fb.User?>();
      addTearDown(controller.close);
      final crashlytics = _MockFirebaseCrashlytics();
      final observer = makeObserver(controller, crashlytics);

      controller.add(makeUser(uid: 'u-1', isAnonymous: false));
      await Future<void>.delayed(Duration.zero);
      expect(observer.recorder.reloadCalls, <String?>['u-1']);

      controller.addError(StateError('userChanges stream failure'));
      await Future<void>.delayed(Duration.zero);

      controller.add(makeUser(uid: 'u-2', isAnonymous: false));
      await Future<void>.delayed(Duration.zero);

      expect(observer.recorder.reloadCalls, <String?>[
        'u-1',
        'u-2',
      ], reason: '스트림 에러 이후에도 UID 변경 감지가 계속 동작해야 한다');
      verify(
        () => crashlytics.recordError(
          any<Object>(),
          any<StackTrace?>(),
          reason: 'auth_user_observer_stream',
        ),
      ).called(1);
    });

    test('WR-03-B: tick 내부 throw 를 격리하고 다음 emit 에서 동일 전이를 재시도한다', () async {
      final controller = StreamController<fb.User?>();
      addTearDown(controller.close);
      final crashlytics = _MockFirebaseCrashlytics();
      final observer = makeObserver(controller, crashlytics);
      observer.recorder.shouldThrowOnReload = true;

      controller.add(makeUser(uid: 'u-1', isAnonymous: false));
      await Future<void>.delayed(Duration.zero);

      verify(
        () => crashlytics.recordError(
          any<Object>(),
          any<StackTrace?>(),
          reason: 'auth_user_observer_tick',
        ),
      ).called(1);

      // 실패한 tick 은 prevUid 를 갱신하지 않으므로, 동일 uid 재emit 에도
      // reload 를 재시도한다 (정상 동작이라면 동일 UID 는 무시된다).
      observer.recorder.shouldThrowOnReload = false;
      controller.add(makeUser(uid: 'u-1', isAnonymous: false));
      await Future<void>.delayed(Duration.zero);

      expect(observer.recorder.reloadCalls, <String?>[
        'u-1',
        'u-1',
      ], reason: '실패한 reload 는 다음 emit 에서 재시도되어야 한다');

      // 재시도 성공 후에는 스냅샷이 확정되어 동일 UID 재emit 을 무시한다.
      controller.add(makeUser(uid: 'u-1', isAnonymous: false));
      await Future<void>.delayed(Duration.zero);
      expect(
        observer.recorder.reloadCalls,
        <String?>['u-1', 'u-1'],
        reason: '성공한 tick 이후에는 동일 UID 재emit 이 불필요 Firestore read 를 만들지 않는다',
      );
    });
  });
}
