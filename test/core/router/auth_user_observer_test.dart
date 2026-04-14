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
  _FakeFirebaseAuth(this._stream);
  final Stream<fb.User?> _stream;

  @override
  Stream<fb.User?> authStateChanges() => _stream;
}

/// `mirrorToFirestore` 호출 카운트를 검증하기 위한 stub TermsNotifier.
class _RecordingTermsNotifier extends TermsNotifier {
  _RecordingTermsNotifier();

  final List<String> mirrorCalls = <String>[];

  @override
  TermsAcceptance? build() => TermsAcceptance(
        version: TermsNotifier.currentVersion,
        service: true,
        privacy: true,
        marketing: false,
        acceptedAt: DateTime.utc(2026, 4, 14),
      );

  @override
  Future<Result<void>> mirrorToFirestore({required String uid}) async {
    mirrorCalls.add(uid);
    return const Result.success(null);
  }
}

void main() {
  setUpAll(() {
    registerFallbackValue(StackTrace.empty);
  });

  fb.User makeUser({
    required String uid,
    required bool isAnonymous,
  }) {
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
    when(() => analytics.setUserProperty(
          name: any(named: 'name'),
          value: any(named: 'value'),
        )).thenAnswer((_) async {});
    when(() => analytics.setUserId(id: any(named: 'id')))
        .thenAnswer((_) async {});
  }

  void stubCrashlytics(_MockFirebaseCrashlytics crashlytics) {
    when(() => crashlytics.setUserIdentifier(any())).thenAnswer((_) async {});
  }

  group('authUserObserver (Phase 10 D-30, BLOCKER #4, INFO #21)', () {
    test('Test 1: 익명 User emit -> setGuestMode(true) + setUserId + Crashlytics setUserId (mirrorToFirestore 호출 없음)',
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

      verify(() => analytics.setUserProperty(
            name: 'guest_mode',
            value: 'true',
          )).called(1);
      verify(() => analytics.setUserId(id: 'anon-1')).called(1);
      verify(() => crashlytics.setUserIdentifier('anon-1')).called(1);
      expect(
        terms.mirrorCalls,
        isEmpty,
        reason: '익명 첫 emit 은 전이가 아니므로 mirror 호출 안 함',
      );
    });

    test('Test 2: 정식 User 첫 emit (prev=null) -> setGuestMode(false) + setUserId, mirror 호출 없음',
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

      verify(() => analytics.setUserProperty(
            name: 'guest_mode',
            value: 'false',
          )).called(1);
      verify(() => analytics.setUserId(id: 'reg-1')).called(1);
      verify(() => crashlytics.setUserIdentifier('reg-1')).called(1);
      expect(
        terms.mirrorCalls,
        isEmpty,
        reason: 'prev=null 이므로 전이로 간주하지 않는다',
      );
    });

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

        expect(
          terms.mirrorCalls,
          ['reg-1'],
          reason: 'BLOCKER #4 — 익명->정식 전이 1회 mirror 호출',
        );
      },
    );

    test('Test 4: null User emit (signOut) -> setUserId(null), mirror 호출 없음',
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

      verify(() => analytics.setUserProperty(
            name: 'guest_mode',
            value: 'false',
          )).called(1);
      verify(() => analytics.setUserId(id: null)).called(1);
      verify(() => crashlytics.setUserIdentifier('')).called(1);
      expect(terms.mirrorCalls, isEmpty);
    });

    test(
      'Test 5 (INFO #21): authUserObserver 소스에 ref.keepAlive() 호출 포함',
      () async {
        // Provider rebuild 시 churn 방지 — 소스 검증.
        final source =
            await File('lib/core/router/auth_guard.dart').readAsString();
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
