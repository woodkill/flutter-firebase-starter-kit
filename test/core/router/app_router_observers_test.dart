import 'dart:async';
import 'dart:io';

import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter_starter_kit/app.dart';
import 'package:flutter_starter_kit/core/analytics/analytics_observer.dart'
    show analyticsObserverProvider;
import 'package:flutter_starter_kit/core/analytics/analytics_service.dart';
import 'package:flutter_starter_kit/core/config/splash_config.dart';
import 'package:flutter_starter_kit/core/providers/firebase_providers.dart';
import 'package:flutter_starter_kit/core/router/app_router.dart';
import 'package:flutter_starter_kit/core/router/app_routes.dart';

class _MockFirebaseAuth extends Mock implements FirebaseAuth {}

class _MockFirebaseAnalytics extends Mock implements FirebaseAnalytics {}

class _FakeNavigatorObserver extends NavigatorObserver {}

void main() {
  /// Firebase 미초기화 상태에서 appRouter 를 로드한다.
  ///
  /// _NoOpNavigatorObserver (private) 가 자동 주입되므로 별도 override 는
  /// 불필요하지만, `observer == ref.watch(analyticsObserverProvider)` 동일성을
  /// 확인하기 위해 fake observer 를 override 주입한다.
  ProviderContainer makeContainer({NavigatorObserver? observer}) {
    final mockAuth = _MockFirebaseAuth();
    when(
      () => mockAuth.authStateChanges(),
    ).thenAnswer((_) => const Stream<User?>.empty());
    return ProviderContainer(
      overrides: [
        isFirebaseInitializedProvider.overrideWithValue(false),
        firebaseAuthProvider.overrideWithValue(mockAuth),
        if (observer != null)
          analyticsObserverProvider.overrideWith((ref) => observer),
      ],
    );
  }

  group('appRouter (Phase 10 D-14 / D-29 / WARNING #14)', () {
    test(
      'Test 1: initialLocation 은 /splash (D-14 상태 머신 시작점) — 소스 검증',
      () async {
        // go_router 17.x 에서 GoRouter.routerDelegate.currentConfiguration 은
        // MaterialApp.router attach 전에는 빈 문자열을 반환하므로 단순 read
        // 만으로는 initialLocation 을 확인할 수 없다. 대신 소스 검증.
        final source = await File(
          'lib/core/router/app_router.dart',
        ).readAsString();
        expect(
          source.contains('initialLocation: AppRoutes.splash'),
          isTrue,
          reason: 'D-14: GoRouter initialLocation 이 /splash 로 설정되어야 함',
        );
        // GoRouter 인스턴스 생성이 가능한지도 확인.
        final container = makeContainer();
        addTearDown(container.dispose);
        expect(container.read(appRouterProvider), isA<GoRouter>());
      },
    );

    test('Test 2: GoRoute 11개 등록 (home/splash/onboarding/login/emailLogin/'
        'signup/forgotPassword/verifyEmail/termsService/termsPrivacy/'
        'settings)', () {
      final container = makeContainer();
      addTearDown(container.dispose);

      final router = container.read(appRouterProvider);
      // Phase 16 D-05 — /settings route 추가로 9 → 10.
      // Phase 16.1 — /login/email route 추가로 10 → 11.
      expect(router.configuration.routes.length, 11);
    });

    test('Test 3: 모든 GoRoute 에 name 이 설정됨 (Pitfall 1)', () {
      final container = makeContainer();
      addTearDown(container.dispose);

      final router = container.read(appRouterProvider);
      final names = router.configuration.routes
          .whereType<GoRoute>()
          .map((r) => r.name)
          .toList();
      // Phase 16 D-05 — /settings route 추가로 9 → 10.
      // Phase 16.1 — /login/email route 추가로 10 → 11.
      expect(names.length, 11);
      expect(
        names.where((n) => n == null || n.isEmpty).length,
        0,
        reason: '모든 GoRoute 에 name 이 설정되어야 한다',
      );
    });

    test(
      'Test 4: observers 가 analyticsObserverProvider override 로 주입됨 (소스 검증)',
      () async {
        // go_router 17.x 에서는 routerDelegate.observers 가 외부 노출되지 않음.
        // 대신 appRouter Provider 가 observers: [observer] 를 GoRouter 에
        // 전달하는지를 소스로 검증한다.
        final source = await File(
          'lib/core/router/app_router.dart',
        ).readAsString();
        expect(
          source.contains('observers: [observer]'),
          isTrue,
          reason: 'GoRouter 생성 시 observers 에 analyticsObserverProvider 결과 전달',
        );
        // analyticsObserverProvider 자체가 watch 되어 의존성이 발생하는지 확인.
        final fakeObserver = _FakeNavigatorObserver();
        final container = makeContainer(observer: fakeObserver);
        addTearDown(container.dispose);
        // appRouter 가 build 시 analyticsObserverProvider 를 watch 하므로
        // override 가 적용됨을 read 로 확인한다.
        final observer = container.read(analyticsObserverProvider);
        expect(observer, fakeObserver);
        // appRouter 가 정상 build 되는지도 확인.
        expect(container.read(appRouterProvider), isA<GoRouter>());
      },
    );

    test('Test 5 (CR-01): screen_view 수동 발신 경로가 소스에서 제거되어 있다', () async {
      // 구 WARNING #14 는 "observer 가 didPush 만 커버한다" 를 전제로
      // routerDelegate.addListener 수동 발신을 덧붙였으나, 패키지 소스
      // (firebase_analytics/lib/observer.dart) 는 didPush/didReplace/didPop
      // 3콜백 모두에서 screen_view 를 보낸다. 두 경로가 공존하면 교차 dedup
      // 이 없어 모든 전환이 2회 적재된다 (Test 6 가 런타임으로 계측).
      //
      // 본 테스트는 "발신 주체가 정확히 하나" 를 소스 수준에서 잠근다.
      // 수동 경로가 다시 들어오면 여기서 먼저 깨진다.
      final source = await File(
        'lib/core/router/app_router.dart',
      ).readAsString();
      // 주석/문서는 검사 대상이 아니다 — 실제 코드 라인만 본다
      // (.claude/rules/acceptance 계열의 주석 오탐 방지).
      final codeOnly = source
          .split('\n')
          .where((line) {
            final trimmed = line.trimLeft();
            return !trimmed.startsWith('//') && !trimmed.startsWith('///');
          })
          .join('\n');
      expect(
        RegExp(r'routerDelegate\s*\.\s*addListener').hasMatch(codeOnly),
        isFalse,
        reason: 'CR-01: 수동 screen_view 발신 리스너가 되살아났다',
      );
      expect(
        RegExp(r'logScreenView\s*\(').hasMatch(codeOnly),
        isFalse,
        reason:
            'CR-01: appRouter 는 logScreenView 를 직접 호출하지 않는다 '
            '(observer 가 유일한 발신 주체)',
      );
      // observer 등록은 유지되어야 한다 (유일한 발신 경로).
      expect(
        RegExp(r'observers:\s*\[observer\]').hasMatch(codeOnly),
        isTrue,
        reason: 'CR-01: observer 단일 경로가 유지되어야 한다',
      );
    });

    testWidgets('Test 6 (CR-01): 화면 전환 1회당 screen_view 가 정확히 1건만 발신된다', (
      tester,
    ) async {
      // 실제 appRouterProvider 배선을 그대로 pump 하여 push / pop / go
      // 세 전환을 각각 계측한다. 수정 전 구현에서는 observer 1건 +
      // 수동 리스너 1건으로 매 전환마다 2건이 적재됐다 (실측 확인:
      // push=[termsService, termsService], pop=[home, home],
      // go=[termsPrivacy, termsPrivacy]).
      //
      // isFirebaseInitialized=false 를 유지하여 resolveAuthRedirect 를 통과시키되
      // (실 Firebase 미접촉), production 과 동일한 모양의 observer /
      // AnalyticsService 를 mock FirebaseAnalytics 에 연결해 두 경로가
      // 같은 계측 지점을 공유하게 한다 — 어느 쪽이 발신하든 잡힌다.
      SharedPreferences.setMockInitialValues({});
      SplashConfig.overrideMinDuration = const Duration(milliseconds: 1);
      addTearDown(() => SplashConfig.overrideMinDuration = null);

      final mockAnalytics = _MockFirebaseAnalytics();
      when(
        () => mockAnalytics.logScreenView(
          screenName: any(named: 'screenName'),
          screenClass: any(named: 'screenClass'),
          parameters: any(named: 'parameters'),
          callOptions: any(named: 'callOptions'),
        ),
      ).thenAnswer((_) async {});

      final mockAuth = _MockFirebaseAuth();
      when(
        () => mockAuth.authStateChanges(),
      ).thenAnswer((_) => const Stream<User?>.empty());
      when(
        () => mockAuth.userChanges(),
      ).thenAnswer((_) => const Stream<User?>.empty());
      when(() => mockAuth.currentUser).thenReturn(null);

      final container = ProviderContainer(
        overrides: [
          isFirebaseInitializedProvider.overrideWithValue(false),
          firebaseAuthProvider.overrideWithValue(mockAuth),
          analyticsObserverProvider.overrideWith(
            (ref) => FirebaseAnalyticsObserver(
              analytics: mockAnalytics,
              nameExtractor: (settings) => settings.name,
            ),
          ),
          analyticsServiceProvider.overrideWith(
            (ref) => AnalyticsService(mockAnalytics, isEnabled: true),
          ),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(container: container, child: const App()),
      );
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pumpAndSettle();

      /// 마지막 drain 이후 발신된 screenName 목록을 반환한다.
      List<Object?> drainScreenNames() => verify(
        () => mockAnalytics.logScreenView(
          screenName: captureAny(named: 'screenName'),
          screenClass: any(named: 'screenClass'),
          parameters: any(named: 'parameters'),
          callOptions: any(named: 'callOptions'),
        ),
      ).captured;

      // splash -> home 착지까지의 발신을 비운 뒤 단일 전환만 계측한다.
      drainScreenNames();

      final router = container.read(appRouterProvider);

      unawaited(router.push(AppRoutes.termsService));
      await tester.pumpAndSettle();
      expect(drainScreenNames(), <Object?>[
        AppRoutes.termsServiceName,
      ], reason: 'push 1회 = screen_view 1건');

      router.pop();
      await tester.pumpAndSettle();
      expect(
        drainScreenNames(),
        <Object?>[AppRoutes.homeName],
        reason: 'pop 1회 = screen_view 1건 (observer 의 didPop 커버)',
      );

      router.go(AppRoutes.termsPrivacy);
      await tester.pumpAndSettle();
      expect(
        drainScreenNames(),
        <Object?>[AppRoutes.termsPrivacyName],
        reason:
            'go() same-level 전환 1회 = screen_view 1건 '
            '(observer 의 didPush/didReplace 커버 — 수동 보완 불필요)',
      );
    });
  });
}
