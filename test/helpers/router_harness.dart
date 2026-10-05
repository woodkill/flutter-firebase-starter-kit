// production 라우터 테스트 하네스 공용 헬퍼 (Phase 17.2 review IN-01).
//
// route 표만 보는 container 와 production `App()` 을 그리는 하네스가
// `app_router_nesting_test.dart` · `auth_guard_test.dart` ·
// `app_router_observers_test.dart` 에 본문까지 복제돼 있었다. 사본 하나만 stub ·
// override 가 바뀌면 같은 이름의 하네스가 파일마다 다른 앱을 그린다 — 여기 한 번만
// 정의하고 모든 호출자가 import 한다 (`route_tree.dart` 와 같은 원칙).

import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter_starter_kit/app.dart' show App;
import 'package:flutter_starter_kit/core/analytics/analytics_observer.dart'
    show analyticsObserverProvider;
import 'package:flutter_starter_kit/core/analytics/analytics_service.dart'
    show AnalyticsService, analyticsServiceProvider;
import 'package:flutter_starter_kit/core/config/splash_config.dart'
    show SplashConfig;
import 'package:flutter_starter_kit/core/providers/firebase_providers.dart'
    show firebaseAuthProvider, isFirebaseInitializedProvider;
import 'package:flutter_starter_kit/core/router/app_router.dart'
    show appRouterProvider;

class _MockFirebaseAuth extends Mock implements fb.FirebaseAuth {}

class _MockFirebaseAnalytics extends Mock implements FirebaseAnalytics {}

/// production `appRouterProvider` 로 그린 앱 한 벌.
///
/// [drainScreenNames] 는 직전 drain 이후 발신된 `screen_view` 의 screenName
/// 목록을 돌려준다 — 직전 drain 이후 이동이 0회면 `verify` 가 실패하므로 매
/// drain 앞에 이동이 1회 이상 있어야 한다.
typedef ProductionApp = ({
  ProviderContainer container,
  GoRouter router,
  List<Object?> Function() drainScreenNames,
});

/// 인증 상태 스트림이 비어 있고 현재 사용자가 없는 mock [fb.FirebaseAuth] 를 만든다.
_MockFirebaseAuth _buildSignedOutAuth() {
  final mockAuth = _MockFirebaseAuth();
  when(
    () => mockAuth.authStateChanges(),
  ).thenAnswer((_) => const Stream<fb.User?>.empty());
  when(
    () => mockAuth.userChanges(),
  ).thenAnswer((_) => const Stream<fb.User?>.empty());
  when(() => mockAuth.currentUser).thenReturn(null);
  return mockAuth;
}

/// Firebase 미초기화 mock 인증을 단 container 를 만든다.
///
/// 위젯 없이 production route 표(`appRouterProvider` 의 `configuration`)만 볼 때
/// 쓴다. dispose 는 호출자가 `addTearDown(container.dispose)` 로 건다.
ProviderContainer buildRouteTableContainer() => ProviderContainer(
  overrides: [
    isFirebaseInitializedProvider.overrideWithValue(false),
    firebaseAuthProvider.overrideWithValue(_buildSignedOutAuth()),
  ],
);

/// production 라우터 배선(`App()`)을 그리고 홈 착지까지 진행한다.
///
/// `isFirebaseInitialized=false` 로 guard 를 통과시키고(실 Firebase 미접촉),
/// production 과 같은 모양의 analytics observer · [AnalyticsService] 를 mock
/// [FirebaseAnalytics] 에 연결해 `screen_view` 발신을 계측한다.
/// [extraOverrides] 는 기본 override 뒤에 붙는다 — 설정 · 계정 화면처럼 실
/// Firebase 에 닿는 화면을 그릴 때 그 화면의 의존성을 여기서 바꾼다.
Future<ProductionApp> pumpProductionApp(
  WidgetTester tester, {
  List<Override> extraOverrides = const <Override>[],
}) async {
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

  final container = ProviderContainer(
    overrides: [
      isFirebaseInitializedProvider.overrideWithValue(false),
      firebaseAuthProvider.overrideWithValue(_buildSignedOutAuth()),
      analyticsObserverProvider.overrideWith(
        (ref) => FirebaseAnalyticsObserver(
          analytics: mockAnalytics,
          nameExtractor: (settings) => settings.name,
        ),
      ),
      analyticsServiceProvider.overrideWith(
        (ref) => AnalyticsService(mockAnalytics, isEnabled: true),
      ),
      ...extraOverrides,
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
