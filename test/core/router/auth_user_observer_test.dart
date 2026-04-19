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
import 'package:flutter_starter_kit/features/terms/domain/terms_acceptance.dart';
import 'package:flutter_starter_kit/features/terms/presentation/terms_notifier.dart';

class _MockFirebaseAnalytics extends Mock implements FirebaseAnalytics {}

class _MockFirebaseCrashlytics extends Mock implements FirebaseCrashlytics {}

class _MockUser extends Mock implements fb.User {}

class _FakeFirebaseAuth extends Fake implements fb.FirebaseAuth {
  _FakeFirebaseAuth(Stream<fb.User?> stream)
    : _stream = stream.asBroadcastStream();

  /// asBroadcastStream 으로 래핑하여 multi-subscription 을 허용한다.
  /// Plan 10-11 Issue #7 C-3 도입 이후 authUserObserver 뿐 아니라
  /// authChangeProvider 의 [AuthChangeNotifier] 도 동일 auth.userChanges()
  /// 를 listen 하므로, single-subscription stream 이면 두 번째 listen 에서
  /// `Bad state: Stream has already been listened to.` 가 발생한다.
  /// 실제 Firebase SDK 의 userChanges() 도 broadcast 성격을 갖는다.
  final Stream<fb.User?> _stream;

  @override
  Stream<fb.User?> authStateChanges() => _stream;

  @override
  Stream<fb.User?> userChanges() => _stream;
}

/// `mirrorToFirestore` 호출 카운트를 검증하기 위한 stub TermsNotifier.
///
/// Plan 10-09: [reloadForUser] 도 stub override 추가 (실제 메서드는
/// firebaseFirestoreProvider mock 이 필요한데, 본 테스트는 Firestore 검증
/// 범위 외이므로 no-op 으로 처리. 실제 reload 동작은
/// terms_notifier_firestore_test 와 terms_notifier_uid_change_test 에서 검증).
class _RecordingTermsNotifier extends TermsNotifier {
  _RecordingTermsNotifier();

  final List<String> mirrorCalls = <String>[];

  /// Issue #9 (Plan 10-13) 회귀 가드: authUserObserver 의 자동 mirror 호출은
  /// force 파라미터의 기본값(false) 을 유지해야 한다 (Plan 10-12 multi-user
  /// invariant 보존). 각 호출의 force 값을 기록하여 검증 가능하게 한다.
  final List<bool> mirrorForceCalls = <bool>[];

  @override
  TermsAcceptance? build() => TermsAcceptance(
    version: TermsNotifier.currentVersion,
    service: true,
    privacy: true,
    marketing: false,
    acceptedAt: DateTime.utc(2026, 4, 14),
  );

  @override
  Future<Result<void>> mirrorToFirestore({
    required String uid,
    bool force = false,
  }) async {
    mirrorCalls.add(uid);
    mirrorForceCalls.add(force);
    return const Result.success(null);
  }

  @override
  Future<void> reloadForUser({String? uid, bool isAnonymous = false}) async {
    // no-op — 본 테스트의 검증 범위 외 (Plan 10-09 신규 호출 stub).
  }
}

void main() {
  setUpAll(() {
    registerFallbackValue(StackTrace.empty);
  });

  fb.User makeUser({required String uid, required bool isAnonymous}) {
    final user = _MockUser();
    when(() => user.uid).thenReturn(uid);
    when(() => user.isAnonymous).thenReturn(isAnonymous);
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
        final terms = _RecordingTermsNotifier();

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
          terms.mirrorCalls,
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
        final terms = _RecordingTermsNotifier();

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
          terms.mirrorCalls,
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
        final terms = _RecordingTermsNotifier();

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
        expect(terms.mirrorCalls, isEmpty);

        // 2) 정식 emit (전이)
        controller.add(makeUser(uid: 'reg-1', isAnonymous: false));
        await Future<void>.delayed(Duration.zero);

        expect(terms.mirrorCalls, [
          'reg-1',
        ], reason: 'BLOCKER #4 — 익명->정식 전이 1회 mirror 호출');
        // Issue #9 (Plan 10-13) 회귀 가드: 자동 mirror 경로는 force 파라미터의
        // 기본값(false) 을 유지해야 한다. Plan 10-12 multi-user invariant
        // (pre-read + snapshot.exists skip) 이 보존되도록 보장.
        expect(
          terms.mirrorForceCalls,
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
        final terms = _RecordingTermsNotifier();

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
        expect(terms.mirrorCalls, isEmpty);
      },
    );

    test('Test 6 (Issue #7 C-3 Plan 10-11): reloadForUser 완료 후 '
        'authChangeProvider.triggerRedirect() 1회 이상 호출됨', () async {
      // Issue #7 핵심 회귀 가드: authUserObserver 가 reloadForUser 를
      // await 한 직후 AuthChangeNotifier.triggerRedirect() 를 호출하여
      // GoRouter refreshListenable 의 재평가를 명시적으로 유도하는지
      // 확인한다. spy AuthChangeNotifier 의 addListener 로 notifyListeners
      // 호출 카운트를 검증한다.
      final controller = StreamController<fb.User?>();
      addTearDown(controller.close);
      final analytics = _MockFirebaseAnalytics();
      final crashlytics = _MockFirebaseCrashlytics();
      stubAnalytics(analytics);
      stubCrashlytics(crashlytics);
      final terms = _RecordingTermsNotifier();

      // Spy AuthChangeNotifier — 별도 empty stream 을 구독하므로 외부
      // userChanges 이벤트로는 notifyListeners 가 호출되지 않는다. 즉,
      // listener 카운트 증가의 유일한 원인은 triggerRedirect() 호출이다.
      final spyAuthChangeNotifier = AuthChangeNotifier(
        const Stream<fb.User?>.empty(),
      );
      addTearDown(spyAuthChangeNotifier.dispose);
      var notifyCount = 0;
      spyAuthChangeNotifier.addListener(() => notifyCount++);

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
          authChangeProvider.overrideWithValue(spyAuthChangeNotifier),
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
        notifyCount,
        greaterThanOrEqualTo(1),
        reason:
            'Issue #7 C-3 — reloadForUser 완료 후 authChangeProvider.'
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
}
