/// Issue #7 (Plan 10-11) race integration — subscription 순서 재현.
///
/// AuthChangeNotifier (subscription #1) 가 notifyListeners 를 먼저 발동해도
/// authRedirect 의 stale 가드가 termsProvider 의 lastReloadedUid 로 분기
/// (5) 를 보류하고, authUserObserver (subscription #2) 의 reloadForUser +
/// triggerRedirect 완료 후 재평가가 정상 경로를 반환함을 검증한다.
///
/// 실제 GoRouter 없이 [authRedirect] 를 직접 호출하여 1차/2차 평가 결과를
/// 비교하는 전략 — go_router 의 internal refreshListenable 경로 대신
/// [AuthChangeNotifier] listener 카운트로 재평가 트리거 여부를 간접 검증.
library;

import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter_starter_kit/core/analytics/analytics_service.dart';
import 'package:flutter_starter_kit/core/crashlytics/crashlytics_service.dart';
import 'package:flutter_starter_kit/core/providers/firebase_providers.dart';
import 'package:flutter_starter_kit/core/router/app_routes.dart';
import 'package:flutter_starter_kit/core/router/auth_guard.dart';
import 'package:flutter_starter_kit/features/onboarding/presentation/onboarding_notifier.dart';
import 'package:flutter_starter_kit/features/terms/presentation/terms_notifier.dart';

class _MockFirebaseAnalytics extends Mock implements FirebaseAnalytics {}

class _MockFirebaseCrashlytics extends Mock implements FirebaseCrashlytics {}

class _MockUser extends Mock implements fb.User {}

class _MockGoRouterState extends Mock implements GoRouterState {}

// cloud_firestore 의 sealed 클래스들을 Mock 으로 우회한다 (terms_notifier_test
// 동일 패턴 — fake_cloud_firestore 의존성 추가 없이 단위 테스트 수준에서
// Firestore read 경로를 시뮬레이션).
// ignore: subtype_of_sealed_class
class _MockFirestore extends Mock implements FirebaseFirestore {}

// ignore: subtype_of_sealed_class
class _MockCollection extends Mock
    implements CollectionReference<Map<String, dynamic>> {}

// ignore: subtype_of_sealed_class
class _MockDoc extends Mock
    implements DocumentReference<Map<String, dynamic>> {}

// ignore: subtype_of_sealed_class
class _MockSnapshot extends Mock
    implements DocumentSnapshot<Map<String, dynamic>> {}

/// asBroadcastStream 으로 래핑하여 authUserObserver 와 authChangeProvider
/// 가 모두 `userChanges()` 를 listen 할 수 있도록 한다 (Plan 10-11 C-3).
class _FakeFirebaseAuth extends Fake implements fb.FirebaseAuth {
  _FakeFirebaseAuth(Stream<fb.User?> stream, {fb.User? currentUser})
    : _stream = stream.asBroadcastStream(),
      _currentUser = currentUser;
  final Stream<fb.User?> _stream;
  fb.User? _currentUser;

  void setCurrentUser(fb.User? user) {
    _currentUser = user;
  }

  @override
  fb.User? get currentUser => _currentUser;

  @override
  Stream<fb.User?> authStateChanges() => _stream;

  @override
  Stream<fb.User?> userChanges() => _stream;
}

class _StubOnboardingNotifier extends OnboardingNotifier {
  _StubOnboardingNotifier(this._seen);
  final bool _seen;

  @override
  bool build() => _seen;
}

void main() {
  setUpAll(() {
    registerFallbackValue(StackTrace.empty);
  });

  fb.User makeUser({
    required String uid,
    required bool isAnonymous,
    bool emailVerified = true,
  }) {
    final user = _MockUser();
    when(() => user.uid).thenReturn(uid);
    when(() => user.isAnonymous).thenReturn(isAnonymous);
    when(() => user.emailVerified).thenReturn(emailVerified);
    return user;
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

  FutureOr<String?> callAuthRedirect(
    ProviderContainer container,
    GoRouterState state,
  ) {
    late FutureOr<String?> result;
    final testProvider = Provider<Object?>((ref) {
      result = authRedirect(ref, state);
      return null;
    });
    container.read(testProvider);
    return result;
  }

  group('Issue #7 race integration — subscription 순서 재현 (Plan 10-11)', () {
    test('authRedirect 가 subscription 순서 race 에서 1차 stale 반환 (null) '
        '→ authUserObserver reload + triggerRedirect 완료 후 2차 평가가 '
        '정상 경로 (/onboarding) 반환', () async {
      SharedPreferences.setMockInitialValues({});

      // Firestore mock — Task 2 race 시나리오에서는 Firestore 문서가 없어
      // reloadForUser 가 state=null 로 정리한다 (재동의 강제 흐름).
      final mockFirestore = _MockFirestore();
      final mockCollection = _MockCollection();
      final mockDoc = _MockDoc();
      final mockSnapshot = _MockSnapshot();
      when(() => mockFirestore.collection(any())).thenReturn(mockCollection);
      when(() => mockCollection.doc(any())).thenReturn(mockDoc);
      when(() => mockDoc.get()).thenAnswer((_) async => mockSnapshot);
      when(() => mockSnapshot.exists).thenReturn(false);
      when(() => mockSnapshot.data()).thenReturn(null);

      final controller = StreamController<fb.User?>();
      addTearDown(controller.close);
      final analytics = _MockFirebaseAnalytics();
      final crashlytics = _MockFirebaseCrashlytics();
      stubAnalytics(analytics);
      stubCrashlytics(crashlytics);

      final fullUser = makeUser(uid: 'FULL-A', isAnonymous: false);
      final fakeAuth = _FakeFirebaseAuth(
        controller.stream,
        currentUser: fullUser,
      );

      final mockState = _MockGoRouterState();
      when(() => mockState.matchedLocation).thenReturn(AppRoutes.home);

      final container = ProviderContainer(
        overrides: [
          isFirebaseInitializedProvider.overrideWithValue(true),
          firebaseAuthProvider.overrideWithValue(fakeAuth),
          firebaseFirestoreProvider.overrideWithValue(mockFirestore),
          firebaseAnalyticsProvider.overrideWithValue(analytics),
          firebaseCrashlyticsProvider.overrideWithValue(crashlytics),
          analyticsServiceProvider.overrideWith(
            (ref) => AnalyticsService(analytics, isEnabled: true),
          ),
          crashlyticsServiceProvider.overrideWith(
            (ref) => CrashlyticsService(crashlytics, isEnabled: true),
          ),
          onboardingProvider.overrideWith(() => _StubOnboardingNotifier(true)),
        ],
      );
      addTearDown(container.dispose);

      // 1) 사전 상태 — lastReloadedUid=null, termsProvider state=null.
      //    이는 AuthChangeNotifier subscription #1 이 먼저 발동한 직후의
      //    stale 상태를 모사한다 (실제로는 fresh ProviderContainer 가
      //    cold-start 이지만 의미는 동일 — reload 가 아직 실행되지 않음).
      expect(
        container.read(termsProvider.notifier).lastReloadedUid,
        isNull,
        reason: 'cold-start — lastReloadedUid=null',
      );
      expect(container.read(termsProvider), isNull);

      // 2) 1차 authRedirect 평가: stale 가드 발동 → null (현재 location
      //    유지, reload 완료 대기).
      final result1 = await callAuthRedirect(container, mockState);
      expect(
        result1,
        isNull,
        reason:
            'Issue #7 1차 평가 — subscription #1 이 먼저 발동한 race '
            '상태에서 lastReloadedUid != currentUser.uid 이므로 stale 가드 '
            'null 반환 (/onboarding 오진 차단)',
      );

      // 3) authUserObserver warm-up + user emit. authUserObserver 가
      //    reloadForUser 호출 → lastReloadedUid='FULL-A' 갱신 →
      //    triggerRedirect() 호출 (AuthChangeNotifier.notifyListeners).
      final observerSub = container.listen(authUserObserverProvider, (_, _) {});
      addTearDown(observerSub.close);
      controller.add(fullUser);
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      // lastReloadedUid 가 FULL-A 로 갱신되었는지 확인 (C-1 통합 검증).
      expect(
        container.read(termsProvider.notifier).lastReloadedUid,
        'FULL-A',
        reason: 'C-1 — reloadForUser 완료 후 lastReloadedUid 갱신',
      );

      // 4) 2차 authRedirect 평가: lastReloadedUid == currentUser.uid →
      //    stale 가드 통과 → termsAccepted=null → /onboarding 반환.
      final result2 = await callAuthRedirect(container, mockState);
      expect(
        result2,
        AppRoutes.onboarding,
        reason:
            'Issue #7 2차 평가 — reload 완료 후 재평가 시 분기 (5) 가 '
            '최신 lastReloadedUid 기준으로 정상 동작 (/onboarding 강제)',
      );
    });

    test('lastReloadedUid == currentUser.uid + termsAccepted=valid 이면 2차 평가 '
        '시 분기 (5) 미발동 (/login 에서 /home 분기 (6))', () async {
      SharedPreferences.setMockInitialValues({});

      // Firestore mock — termsAccepted 필드가 존재하는 정상 사용자.
      final mockFirestore = _MockFirestore();
      final mockCollection = _MockCollection();
      final mockDoc = _MockDoc();
      final mockSnapshot = _MockSnapshot();
      when(() => mockFirestore.collection(any())).thenReturn(mockCollection);
      when(() => mockCollection.doc(any())).thenReturn(mockDoc);
      when(() => mockDoc.get()).thenAnswer((_) async => mockSnapshot);
      when(() => mockSnapshot.exists).thenReturn(true);
      when(() => mockSnapshot.data()).thenReturn(<String, dynamic>{
        'termsAccepted': <String, dynamic>{
          'version': TermsNotifier.currentVersion,
          'service': true,
          'privacy': true,
          'marketing': false,
          'acceptedAt': Timestamp.fromDate(DateTime.utc(2026, 4, 14)),
        },
      });

      final controller = StreamController<fb.User?>();
      addTearDown(controller.close);
      final analytics = _MockFirebaseAnalytics();
      final crashlytics = _MockFirebaseCrashlytics();
      stubAnalytics(analytics);
      stubCrashlytics(crashlytics);

      final fullUser = makeUser(uid: 'FULL-B', isAnonymous: false);
      final fakeAuth = _FakeFirebaseAuth(
        controller.stream,
        currentUser: fullUser,
      );

      final mockState = _MockGoRouterState();
      when(() => mockState.matchedLocation).thenReturn(AppRoutes.login);

      final container = ProviderContainer(
        overrides: [
          isFirebaseInitializedProvider.overrideWithValue(true),
          firebaseAuthProvider.overrideWithValue(fakeAuth),
          firebaseFirestoreProvider.overrideWithValue(mockFirestore),
          firebaseAnalyticsProvider.overrideWithValue(analytics),
          firebaseCrashlyticsProvider.overrideWithValue(crashlytics),
          analyticsServiceProvider.overrideWith(
            (ref) => AnalyticsService(analytics, isEnabled: true),
          ),
          crashlyticsServiceProvider.overrideWith(
            (ref) => CrashlyticsService(crashlytics, isEnabled: true),
          ),
          onboardingProvider.overrideWith(() => _StubOnboardingNotifier(true)),
        ],
      );
      addTearDown(container.dispose);

      // 1) observer warm-up + emit — reloadForUser 완료 후 termsProvider
      //    state=valid + lastReloadedUid='FULL-B'.
      final observerSub = container.listen(authUserObserverProvider, (_, _) {});
      addTearDown(observerSub.close);
      controller.add(fullUser);
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(container.read(termsProvider.notifier).lastReloadedUid, 'FULL-B');
      expect(container.read(termsProvider), isNotNull);

      // 2) 평가: /login 에서 분기 (6) 으로 /home.
      final result = await callAuthRedirect(container, mockState);
      expect(
        result,
        AppRoutes.home,
        reason:
            'Issue #7 정상 경로 — termsAccepted=valid + reload 완료 상태 '
            '의 /login 접근은 분기 (6) 으로 /home 재이동',
      );
    });
  });
}
