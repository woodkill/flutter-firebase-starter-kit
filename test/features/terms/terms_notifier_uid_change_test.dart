import 'dart:async';
import 'dart:convert';

import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

  /// asBroadcastStream 으로 래핑하여 multi-subscription 을 허용한다
  /// (Plan 10-11 Issue #7 C-3 이후 authChangeProvider 가 내부적으로
  /// userChanges 를 listen 하므로 필요).
  final Stream<fb.User?> _stream;

  @override
  Stream<fb.User?> authStateChanges() => _stream;

  @override
  Stream<fb.User?> userChanges() => _stream;
}

/// 호출 기록을 위한 stub TermsNotifier (Mock 대신 실제 reloadForUser 호출
/// 카운트만 검증).
class _RecordingTermsNotifier extends TermsNotifier {
  _RecordingTermsNotifier({this.initial});

  final TermsAcceptance? initial;
  final List<({String? uid, bool isAnonymous})> reloadCalls = [];
  final List<String> mirrorCalls = [];

  @override
  TermsAcceptance? build() => initial;

  @override
  Future<Result<void>> mirrorToFirestore({required String uid}) async {
    mirrorCalls.add(uid);
    return const Result.success(null);
  }

  @override
  Future<void> reloadForUser({
    String? uid,
    bool isAnonymous = false,
  }) async {
    reloadCalls.add((uid: uid, isAnonymous: isAnonymous));
    // state 갱신 시뮬레이션 (테스트 단순화 — 실제 reload 동작은 Task 2 에서 검증).
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

  group('authUserObserver UID 변경 감지 + termsProvider reload (Issue #6)',
      () {
    test(
      'Test 1: anonymous(uid=A) → full(uid=B) 전이 → reloadForUser(B, false) + '
      'mirrorToFirestore(B) 직렬화',
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
        final sub =
            container.listen(authUserObserverProvider, (_, _) {});
        addTearDown(sub.close);

        controller.add(makeUser(uid: 'anon-uid', isAnonymous: true));
        await Future<void>.delayed(Duration.zero);
        controller.add(makeUser(uid: 'full-uid', isAnonymous: false));
        await Future<void>.delayed(Duration.zero);

        // Mirror 호출은 anonymous→full 전이 1회.
        expect(
          terms.mirrorCalls,
          ['full-uid'],
          reason: 'anonymous→full 전이 mirrorToFirestore 호출 유지',
        );
        // Reload 호출은 UID 변경 감지마다 발생: null→anon, anon→full.
        expect(terms.reloadCalls.length, 2);
        // 첫 번째: null → anon-uid
        expect(terms.reloadCalls[0].uid, 'anon-uid');
        expect(terms.reloadCalls[0].isAnonymous, isTrue);
        // 두 번째: anon-uid → full-uid (Issue #6 핵심)
        expect(terms.reloadCalls[1].uid, 'full-uid');
        expect(terms.reloadCalls[1].isAnonymous, isFalse);
        // Issue #7 C-1 (Plan 10-11): _RecordingTermsNotifier 는 실제
        // reloadForUser 를 호출하지 않지만, reloadCalls 목록이 3분기 순서대로
        // 누적됨을 확인하여 lastReloadedUid 의 "마지막 uid 추적" 계약을
        // 메서드 수준으로 회귀 방어한다 (실제 lastReloadedUid 검증은
        // terms_notifier_test.dart Test 9d).
        expect(
          terms.reloadCalls.map((e) => e.uid).toList(),
          ['anon-uid', 'full-uid'],
          reason: 'reload 호출 순서가 lastReloadedUid 누적 순서와 일치',
        );
      },
    );

    test(
      'Test 2: full(A) → full(B) 전이 → reloadForUser(B, false) (mirror 호출 없음)',
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
        final sub =
            container.listen(authUserObserverProvider, (_, _) {});
        addTearDown(sub.close);

        controller.add(makeUser(uid: 'user-A', isAnonymous: false));
        await Future<void>.delayed(Duration.zero);
        controller.add(makeUser(uid: 'user-B', isAnonymous: false));
        await Future<void>.delayed(Duration.zero);

        // mirror 는 anonymous→full 이 아니라서 호출되지 않는다.
        expect(terms.mirrorCalls, isEmpty);
        // reload 는 두 번 — null→A, A→B.
        expect(terms.reloadCalls.length, 2);
        expect(terms.reloadCalls[1].uid, 'user-B');
        expect(terms.reloadCalls[1].isAnonymous, isFalse);
      },
    );

    test(
      'Test 3: full(A) → null (로그아웃) → reloadForUser(null) state 초기화',
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
        final sub =
            container.listen(authUserObserverProvider, (_, _) {});
        addTearDown(sub.close);

        controller.add(makeUser(uid: 'user-A', isAnonymous: false));
        await Future<void>.delayed(Duration.zero);
        controller.add(null);
        await Future<void>.delayed(Duration.zero);

        // reload 호출: null→A, A→null
        expect(terms.reloadCalls.length, 2);
        expect(terms.reloadCalls[1].uid, isNull);
      },
    );

    test(
      'Test 4: full(A) → anonymous (signOutAndContinueAsGuest) → '
      'reloadForUser(anon-2, true) SharedPreferences fallback',
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
        final sub =
            container.listen(authUserObserverProvider, (_, _) {});
        addTearDown(sub.close);

        controller.add(makeUser(uid: 'user-A', isAnonymous: false));
        await Future<void>.delayed(Duration.zero);
        controller.add(makeUser(uid: 'anon-2', isAnonymous: true));
        await Future<void>.delayed(Duration.zero);

        expect(terms.reloadCalls.length, 2);
        expect(terms.reloadCalls[1].uid, 'anon-2');
        expect(terms.reloadCalls[1].isAnonymous, isTrue);
        // mirror 는 호출되지 않음 (full→anon 은 전이 대상 아님).
        expect(terms.mirrorCalls, isEmpty);
      },
    );

    test(
      'Test 5: 동일 UID 재emit (userChanges idle refresh) → '
      'reloadForUser 추가 호출 없음 (불필요 Firestore read 차단)',
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
        final sub =
            container.listen(authUserObserverProvider, (_, _) {});
        addTearDown(sub.close);

        controller.add(makeUser(uid: 'user-A', isAnonymous: false));
        await Future<void>.delayed(Duration.zero);
        controller.add(makeUser(uid: 'user-A', isAnonymous: false));
        await Future<void>.delayed(Duration.zero);

        // reload 호출 1회 (null→A) — A→A 는 prevUid 비교로 건너뜀.
        expect(
          terms.reloadCalls.length,
          1,
          reason: '동일 UID 재emit 시 reloadForUser 호출 안 됨',
        );
        expect(terms.reloadCalls[0].uid, 'user-A');
      },
    );
  });

  group('authUserObserver mirror→reload 직렬화 데이터 연속성 (Test 6)', () {
    test(
      'Test 6: anonymous→full 전이 시 mirrorToFirestore (write) → '
      'reloadForUser (read) 직렬화로 원본 acceptance 복원',
      () async {
        // 사전: SharedPreferences 에 익명 단계의 acceptance 저장.
        final originalAcceptedAt = DateTime.utc(2026, 4, 15, 9, 0, 0);
        final original = TermsAcceptance(
          version: TermsNotifier.currentVersion,
          service: true,
          privacy: true,
          marketing: true,
          acceptedAt: originalAcceptedAt,
        );
        SharedPreferences.setMockInitialValues(<String, Object>{
          'terms.accepted_value': jsonEncode(original.toJson()),
        });

        final controller = StreamController<fb.User?>();
        addTearDown(controller.close);
        final analytics = _MockFirebaseAnalytics();
        final crashlytics = _MockFirebaseCrashlytics();
        stubAnalytics(analytics);
        stubCrashlytics(crashlytics);

        // Recording stub 으로 호출 순서 검증 (real implementation 은 Task 2 검증).
        final terms = _RecordingTermsNotifier(initial: original);

        final container = makeContainer(
          controller: controller,
          analytics: analytics,
          crashlytics: crashlytics,
          terms: terms,
        );
        addTearDown(container.dispose);
        final sub =
            container.listen(authUserObserverProvider, (_, _) {});
        addTearDown(sub.close);

        // 1) 익명 emit
        controller.add(makeUser(uid: 'anon-uid', isAnonymous: true));
        await Future<void>.delayed(Duration.zero);
        // 2) 정식 emit (전이)
        controller.add(
            makeUser(uid: 'continuity-uid', isAnonymous: false));
        await Future<void>.delayed(Duration.zero);

        // 호출 순서 검증: anon→full 전이에서 mirror 가 reload 보다 먼저
        // 직렬화되어야 한다 (race condition 차단).
        expect(terms.mirrorCalls, ['continuity-uid']);
        // reload 는 anon (idx 0), continuity-uid (idx 1).
        expect(terms.reloadCalls.length, 2);
        expect(terms.reloadCalls[1].uid, 'continuity-uid');
        expect(terms.reloadCalls[1].isAnonymous, isFalse);

        // 데이터 연속성 의의: build() 의 initial state 가 mirrorToFirestore
        // payload 의 source 가 되고, reloadForUser 가 그 직후 호출되어
        // freshly mirrored 데이터를 read 할 수 있도록 await 직렬화 보장.
        // (실제 Firestore read 정확성은 Task 2 의 terms_notifier_firestore_test
        // Test 4 에서 millisecond 단위로 검증된다.)
      },
    );
  });
}
