// Phase 17.2 Plan 17.2-02 — 알림 대상 route 의 홈 하위 중첩(todo 결정 1~5)을
// 잠근다. 실측값은 17.2-RESEARCH §R-01(2026-10-05) 그대로다.
//
// 알림 탭 이동은 `context.go(route)` 그대로(17 D-04)이고, 바뀌는 것은 route
// 트리 모양뿐이다 — 설정 · 계정 · 약관 2를 홈 GoRoute 의 하위 route 로 두면
// `go` 한 번으로 홈 → (설정) → 대상 스택이 만들어지고 홈의
// [PendingNotificationRouteListener](17.1 D-17)도 트리에 남는다.
//
// 이 파일은 데모 경로 · 데모 화면을 참조하지 않는다(매뉴얼 「데모 지우는 법」
// 이 이 파일을 건드리지 않게).

import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter_starter_kit/app.dart' show App;
import 'package:flutter_starter_kit/core/analytics/analytics_observer.dart'
    show analyticsObserverProvider;
import 'package:flutter_starter_kit/core/analytics/analytics_service.dart'
    show AnalyticsService, analyticsServiceProvider;
import 'package:flutter_starter_kit/core/auth/auth_strategies_registry.dart'
    show activeStrategiesProvider;
import 'package:flutter_starter_kit/core/auth/auth_strategy.dart'
    show AuthStrategy;
import 'package:flutter_starter_kit/core/auth/strategies/google_auth_strategy.dart'
    show GoogleAuthStrategy;
import 'package:flutter_starter_kit/core/config/splash_config.dart'
    show SplashConfig;
import 'package:flutter_starter_kit/core/providers/firebase_providers.dart'
    show firebaseAuthProvider, isFirebaseInitializedProvider;
import 'package:flutter_starter_kit/core/router/app_router.dart'
    show appRouterProvider;
import 'package:flutter_starter_kit/core/router/app_routes.dart' show AppRoutes;
import 'package:flutter_starter_kit/features/auth/data/auth_repository.dart'
    show
        AuthRepository,
        UserProviderRecord,
        authRepositoryProvider,
        currentUserProvider,
        linkedProvidersStreamProvider;
import 'package:flutter_starter_kit/features/auth/domain/user.dart' show User;
import 'package:flutter_starter_kit/features/notifications/application/notification_route.dart'
    show kNotificationRoutableRoutes;
import 'package:flutter_starter_kit/features/notifications/application/notification_settings_notifier.dart'
    show notificationSettingsProvider;
import 'package:flutter_starter_kit/features/notifications/application/pending_notification_route.dart'
    show pendingNotificationRouteProvider;
import 'package:flutter_starter_kit/features/notifications/presentation/pending_notification_route_listener.dart'
    show PendingNotificationRouteListener;
import 'package:flutter_starter_kit/features/settings/presentation/account_screen.dart'
    show AccountScreen;
import 'package:flutter_starter_kit/features/settings/presentation/settings_screen.dart'
    show SettingsScreen;

class _MockFirebaseAuth extends Mock implements fb.FirebaseAuth {}

class _MockFirebaseAnalytics extends Mock implements FirebaseAnalytics {}

class _MockAuthRepository extends Mock implements AuthRepository {}

/// 사진 출처 stream fixture — 업로드 사진 없음 (설정 화면 테스트와 같은 모양).
const UserProviderRecord _kNoPhotoRecord = (
  linkedProviderIds: <String>[],
  signUpProviderId: null,
  customPhotoUrl: null,
);

/// 설정 · 계정 화면을 그릴 정식 사용자 fixture (설정 화면 테스트와 같은 모양).
final User _kTestUser = User(
  uid: 'uid-1',
  email: 'me@example.com',
  emailVerified: true,
  displayName: 'Tester',
  createdAt: DateTime.utc(2026, 1, 1),
  providerIds: const <String>['password'],
  signUpProviderId: null,
);

/// production `appRouterProvider` 로 그린 앱 한 벌.
///
/// [drainScreenNames] 는 직전 drain 이후 발신된 `screen_view` 의 screenName
/// 목록을 돌려준다 — 직전 drain 이후 이동이 0회면 `verify` 가 실패하므로 매
/// drain 앞에 이동이 1회 이상 있어야 한다.
typedef _ProductionApp = ({
  ProviderContainer container,
  GoRouter router,
  List<Object?> Function() drainScreenNames,
});

/// Firebase 미초기화 mock 인증을 단 container 를 만든다 — 위젯 없이 route 표만
/// 볼 때 쓴다.
ProviderContainer _buildRouteTableContainer() {
  final mockAuth = _MockFirebaseAuth();
  when(
    () => mockAuth.authStateChanges(),
  ).thenAnswer((_) => const Stream<fb.User?>.empty());
  when(
    () => mockAuth.userChanges(),
  ).thenAnswer((_) => const Stream<fb.User?>.empty());
  when(() => mockAuth.currentUser).thenReturn(null);
  return ProviderContainer(
    overrides: [
      isFirebaseInitializedProvider.overrideWithValue(false),
      firebaseAuthProvider.overrideWithValue(mockAuth),
    ],
  );
}

/// production 라우터 배선(`App()`)을 그리고 홈 착지까지 진행한다.
///
/// 하네스는 `app_router_observers_test.dart` Test 6 과 같다 —
/// `isFirebaseInitialized=false` 로 guard 를 통과시키고, 설정 · 계정 화면이 실
/// Firebase 에 닿지 않게 설정 화면 테스트의 override 5종을 더한다.
Future<_ProductionApp> _pumpProductionApp(WidgetTester tester) async {
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
  ).thenAnswer((_) => const Stream<fb.User?>.empty());
  when(
    () => mockAuth.userChanges(),
  ).thenAnswer((_) => const Stream<fb.User?>.empty());
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
      // 설정 · 계정 화면이 실 Firebase 에 닿지 않게 (설정 화면 테스트와 같다).
      currentUserProvider.overrideWith((ref) => _kTestUser),
      activeStrategiesProvider.overrideWith(
        (ref) => const <AuthStrategy>[GoogleAuthStrategy()],
      ),
      authRepositoryProvider.overrideWithValue(_MockAuthRepository()),
      notificationSettingsProvider.overrideWithBuild((ref, notifier) => false),
      linkedProvidersStreamProvider(
        _kTestUser.uid,
      ).overrideWith((ref) => Stream.value(_kNoPhotoRecord)),
    ],
  );
  addTearDown(container.dispose);

  await tester.pumpWidget(
    UncontrolledProviderScope(container: container, child: const App()),
  );
  await tester.pump(const Duration(milliseconds: 50));
  await tester.pumpAndSettle();

  /// 직전 drain 이후 발신된 screenName 목록을 반환한다.
  List<Object?> drainScreenNames() => verify(
    () => mockAnalytics.logScreenView(
      screenName: captureAny(named: 'screenName'),
      screenClass: any(named: 'screenClass'),
      parameters: any(named: 'parameters'),
      callOptions: any(named: 'callOptions'),
    ),
  ).captured;

  return (
    container: container,
    router: container.read(appRouterProvider),
    drainScreenNames: drainScreenNames,
  );
}

/// 현재 Navigator 스택을 match 의 `matchedLocation` 목록으로 읽는다.
List<String> _readStack(GoRouter router) => router
    .routerDelegate
    .currentConfiguration
    .matches
    .map((match) => match.matchedLocation)
    .toList();

/// production 과 같은 리스너 경로로 알림 이동을 일으킨다.
///
/// pending 을 set 하면 홈 [PendingNotificationRouteListener] 가 microtask 뒤
/// consume 해 `context.go(route)` 한다 — `router.go` 를 직접 부르지 않는다.
Future<void> _deliverNotificationRoute(
  WidgetTester tester,
  ProviderContainer container,
  String route,
) async {
  container.read(pendingNotificationRouteProvider.notifier).set(route);
  await tester.pump();
  await tester.pump();
  await tester.pumpAndSettle();
}

void main() {
  group('Phase 17.2 홈 하위 route 중첩 (T-172-ROUTER · T-172-STACK)', () {
    test('T-172-ROUTER-01: 알림 허용 목록 중 홈이 아닌 경로는 모두 홈 하위 route 다 '
        '(구조 불변식 · 실패 메시지 = 고치는 법)', () {
      final container = _buildRouteTableContainer();
      addTearDown(container.dispose);
      final RouteConfiguration configuration = container
          .read(appRouterProvider)
          .configuration;

      var checkedCount = 0;
      for (final String path in kNotificationRoutableRoutes) {
        if (path == AppRoutes.home) {
          continue;
        }
        checkedCount++;
        final RouteMatchList matchList = configuration.findMatch(
          Uri.parse(path),
        );
        expect(
          matchList.isError,
          isFalse,
          reason: '알림 허용 목록 경로 $path 가 route 표에 없다 (todo 결정 1)',
        );
        final RouteMatchBase first = matchList.matches.first;
        expect(
          first,
          isA<RouteMatch>(),
          reason: '알림 허용 목록 경로 $path 의 첫 match 는 GoRoute 여야 한다',
        );
        expect(
          (first as RouteMatch).route.path,
          AppRoutes.home,
          reason:
              '알림 허용 목록 경로 $path 가 홈 하위 route 가 아니다 '
              '(첫 match = ${first.matchedLocation}). '
              'lib/core/router/app_router.dart 의 홈 GoRoute routes 안으로 옮긴다'
              ' — docs/manual.md 「홈 화면 바꾸기」 ④',
        );
        expect(
          matchList.matches.length,
          greaterThanOrEqualTo(2),
          reason: '알림 허용 목록 경로 $path 는 홈 위에 쌓인다 (홈 + 대상 ≥ 2장 · D-01 ①)',
        );
      }
      expect(
        checkedCount,
        greaterThanOrEqualTo(1),
        reason: '홈이 아닌 알림 허용 목록 경로가 0개면 불변식이 아무것도 검사하지 않는다',
      );
    });

    testWidgets('T-172-STACK-01: 알림 → 계정 = 홈 · 설정 · 계정 3장 · ← 2회면 홈 · '
        '홈 리스너 State 유지', (tester) async {
      final app = await _pumpProductionApp(tester);
      final listener = find.byType(
        PendingNotificationRouteListener,
        skipOffstage: false,
      );
      expect(listener, findsOneWidget, reason: '착지 = 홈 (홈 리스너 mount)');
      final State listenerState = tester.state(listener);

      await _deliverNotificationRoute(tester, app.container, AppRoutes.account);

      expect(_readStack(app.router), <String>[
        '/',
        AppRoutes.settings,
        AppRoutes.account,
      ], reason: '알림 → 계정 = 홈 · 설정 · 계정 3장 (D-01 ① 실측 · todo 결정 1)');
      expect(
        app.router.routerDelegate.currentConfiguration.matches
            .whereType<ImperativeRouteMatch>(),
        isEmpty,
        reason: '알림 이동은 go — push(ImperativeRouteMatch)가 아니다 (17 D-04)',
      );
      expect(app.router.canPop(), isTrue, reason: '계정 위에서 pop 가능');
      expect(
        find.byType(BackButton),
        findsOneWidget,
        reason: '계정 앱바에 ← 가 보인다 (D-11)',
      );
      expect(find.byType(AccountScreen), findsOneWidget, reason: '대상 = 계정 화면');
      expect(
        identical(tester.state(listener), listenerState),
        isTrue,
        reason: '홈 리스너 State 가 재생성되지 않는다 (D-01 ① 실측 · 17.1 D-17)',
      );
      expect(
        app.container.read(pendingNotificationRouteProvider),
        isNull,
        reason: '리스너가 pending 을 소비했다',
      );

      app.router.pop();
      await tester.pumpAndSettle();
      expect(_readStack(app.router), <String>[
        '/',
        AppRoutes.settings,
      ], reason: '← 1회 = 설정 (D-11)');
      expect(find.byType(BackButton), findsOneWidget, reason: '설정 앱바에도 ←');
      expect(find.byType(SettingsScreen), findsOneWidget, reason: '설정 화면이 보인다');

      app.router.pop();
      await tester.pumpAndSettle();
      expect(_readStack(app.router), <String>['/'], reason: '← 2회 = 홈 (D-11)');
      expect(app.router.canPop(), isFalse, reason: '홈에서는 더 pop 할 수 없다');
      expect(find.byType(BackButton), findsNothing, reason: '홈 앱바에는 ← 가 없다');
      expect(
        identical(tester.state(listener), listenerState),
        isTrue,
        reason: 'pop 2회 뒤에도 홈 리스너 State 유지 (D-01 ①)',
      );
      expect(tester.takeException(), isNull);
    });
  });
}
