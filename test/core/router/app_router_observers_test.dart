import 'dart:async';
import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter_starter_kit/core/analytics/analytics_observer.dart'
    show analyticsObserverProvider;
import 'package:flutter_starter_kit/core/providers/firebase_providers.dart';
import 'package:flutter_starter_kit/core/router/app_router.dart';
import 'package:flutter_starter_kit/core/router/app_routes.dart';
import 'package:flutter_starter_kit/core/theme/app_theme.dart';
import 'package:flutter_starter_kit/features/auth/data/auth_repository.dart';
import 'package:flutter_starter_kit/features/demo/presentation/demo_screen.dart';
import 'package:flutter_starter_kit/features/not_found/presentation/not_found_screen.dart';
import 'package:flutter_starter_kit/l10n/generated/app_localizations.dart';

import '../../helpers/route_tree.dart';
import '../../helpers/router_harness.dart' show pumpProductionApp;
import '../../helpers/source_text.dart';

class _MockFirebaseAuth extends Mock implements FirebaseAuth {}

class _FakeNavigatorObserver extends NavigatorObserver {}

class _MockAuthRepository extends Mock implements AuthRepository {}

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

    test('Test 2: GoRoute 14개 등록 · 최상위 8 (home/splash/onboarding/login/'
        'emailLogin/signup/forgotPassword/verifyEmail/termsService/termsPrivacy/'
        'settings/withdrawalDisconnect/account/developerDemo)', () {
      final container = makeContainer();
      addTearDown(container.dispose);

      final router = container.read(appRouterProvider);
      // Phase 16 D-05 — /settings route 추가로 9 → 10.
      // Phase 16.1 — /login/email route 추가로 10 → 11.
      // Phase 16.10 — /settings/withdraw 추가로 11 → 12.
      // Phase 17.1 — /settings/account 추가로 12 → 13.
      // Phase 17.1 — /settings/developer(!kReleaseMode) 추가로 13 → 14 (release 빌드는 13).
      // Phase 17.2 — 홈 하위 중첩(todo 결정 1): 최상위 14 → 8 · 재귀 14 (release 빌드는 재귀 13).
      expect(
        router.configuration.routes.length,
        8,
        reason: '최상위 = home + 흐름 화면 7 (설정 · 약관은 홈 하위)',
      );
      expect(
        collectGoRoutes(router.configuration.routes).length,
        14,
        reason: '재귀 14',
      );
    });

    test('Test 3: 모든 GoRoute 에 name 이 설정됨 (Pitfall 1)', () {
      final container = makeContainer();
      addTearDown(container.dispose);

      final router = container.read(appRouterProvider);
      // Phase 17.2 — 재귀 수집(트리 깊이 독립 · flat 이든 중첩이든 14).
      final names = collectGoRoutes(
        router.configuration.routes,
      ).map((r) => r.name).toList();
      // Phase 16 D-05 — /settings route 추가로 9 → 10.
      // Phase 16.1 — /login/email route 추가로 10 → 11.
      // Phase 16.10 — /settings/withdraw 추가로 11 → 12.
      // Phase 17.1 — /settings/account 추가로 12 → 13.
      // Phase 17.1 — /settings/developer(!kReleaseMode) 추가로 13 → 14 (release 빌드는 13).
      expect(names.length, 14);
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
      // 하네스 = test/helpers/router_harness.dart [pumpProductionApp] (17.2
      // review IN-01 — nesting 테스트와 공용 · 추가 override 없음).
      final app = await pumpProductionApp(tester);
      final drainScreenNames = app.drainScreenNames;

      // splash -> home 착지까지의 발신을 비운 뒤 단일 전환만 계측한다.
      drainScreenNames();

      final router = app.router;

      unawaited(router.push(AppRoutes.termsService));
      await tester.pumpAndSettle();
      expect(drainScreenNames(), <Object?>[
        AppRoutes.termsServiceName,
      ], reason: 'push 1회 = screen_view 1건');

      router.pop();
      await tester.pumpAndSettle();
      expect(drainScreenNames(), <Object?>[
        AppRoutes.homeName,
      ], reason: 'pop 1회 = screen_view 1건 (observer 의 didPop 커버)');

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

  // Phase 17.1 D-14 · D-20 ③ 정정 — 데모 GoRoute 는 release 가 아닌 빌드에서만
  // 등록된다. 테스트 VM 은 kReleaseMode 를 뒤집을 수 없으므로 (RESEARCH §R-11)
  // ① 소스 가드로 const 분기 형태를 잠그고 ② 실제 route 표에서 데모 GoRoute 를
  // 뺀 표(= release 의 표)로 404 를 시뮬레이션한다.
  // Phase 17.2 — 데모는 settings GoRoute 의 child.
  group('Phase 17.1 데모 경로 조건부 등록 (T-171-ROUTER)', () {
    test('T-171-ROUTER-02: 데모 GoRoute 는 if (!kReleaseMode) 바로 뒤 1곳 · '
        'DemoScreen import 는 app_router.dart 1파일 (D-14 · 소스 가드)', () {
      final code = stripSlashComments(
        readTrackedFile('lib/core/router/app_router.dart'),
      );
      final guarded = RegExp(
        r'if\s*\(\s*!kReleaseMode\s*\)\s*GoRoute\s*\(\s*'
        r'path:\s*AppRoutes\.developerDemoSegment\s*,\s*'
        r'name:\s*AppRoutes\.developerDemoName\s*,\s*'
        r'builder:\s*\(\s*context\s*,\s*state\s*\)\s*=>\s*'
        r'const\s+DemoScreen\s*\(\s*\)\s*,?\s*\)',
      );
      expect(
        guarded.allMatches(code),
        hasLength(1),
        reason: 'const !kReleaseMode 바로 뒤 데모 GoRoute 블록이 정확히 1개',
      );
      // 다른 곳(무조건 등록)에 같은 경로가 없다 — 경로 · 생성자 각 1회.
      expect(countOccurrences(code, 'AppRoutes.developerDemoSegment,'), 1);
      expect(
        countOccurrences(code, 'AppRoutes.developerDemo,'),
        0,
        reason: '데모 GoRoute.path 는 조각 상수 — 최상위 복귀 회귀 방지',
      );
      expect(countOccurrences(code, 'DemoScreen('), 1);

      // release tree-shake 전제 — DemoScreen 을 import 하는 lib 파일은
      // app_router.dart 1개뿐이다 (설정 행 · 홈 카드는 경로 문자열만).
      final importPattern = RegExp(
        r"^import\s+'[^']*features/demo/presentation/demo_screen\.dart';",
        multiLine: true,
      );
      final importers = Directory('lib')
          .listSync(recursive: true)
          .whereType<File>()
          .where((file) => file.path.endsWith('.dart'))
          .where(
            (file) => importPattern.hasMatch(
              stripSlashComments(file.readAsStringSync()),
            ),
          )
          .map((file) => file.path.replaceAll(r'\', '/'))
          .toList();
      expect(importers, ['lib/core/router/app_router.dart']);
    });

    testWidgets(
      'T-171-ROUTER-03: 데모 GoRoute 를 뺀 route 표(release 시뮬레이션) + 앱 '
      'errorBuilder → /settings/developer = NotFoundScreen · 양성 대조 DemoScreen',
      (tester) async {
        SharedPreferences.setMockInitialValues({});
        final container = makeContainer();
        addTearDown(container.dispose);
        final appRouter = container.read(appRouterProvider);
        final allRoutes = appRouter.configuration.routes;
        // Phase 17.2 — 데모 GoRoute 가 트리 어느 깊이에 있어도 name 으로 재귀
        // 복사해 뺀다. 절대 개수(재귀 14 · release 13)는 Test 2 · 3 에만 둔다.
        final List<RouteBase> releaseRoutes = buildRoutesWithoutNamed(
          allRoutes,
          AppRoutes.developerDemoName,
        );
        expect(
          collectGoRoutes(releaseRoutes).length,
          collectGoRoutes(allRoutes).length - 1,
          reason: 'release 표 = 데모 GoRoute 1개만 빠진다(재귀)',
        );
        expect(
          releaseRoutes,
          hasLength(allRoutes.length),
          reason: '최상위 8 은 그대로 — 데모는 settings 의 child (Phase 17.2)',
        );
        final errorBuilder = appRouter.routerDelegate.builder.errorBuilder;
        expect(errorBuilder, isNotNull, reason: '404 는 앱 errorBuilder 가 그린다');

        /// [routes] 표 + 앱 errorBuilder 로 만든 라우터를 데모 경로에서 연다.
        Future<void> pumpDemoPath(List<RouteBase> routes) async {
          final router = GoRouter(
            initialLocation: AppRoutes.developerDemo,
            routes: routes,
            errorBuilder: errorBuilder,
          );
          addTearDown(router.dispose);
          await tester.pumpWidget(
            ProviderScope(
              key: UniqueKey(),
              overrides: [
                isFirebaseInitializedProvider.overrideWithValue(false),
                firebaseAuthProvider.overrideWithValue(_MockFirebaseAuth()),
                currentUserProvider.overrideWith((ref) => null),
                authRepositoryProvider.overrideWithValue(_MockAuthRepository()),
              ],
              child: MaterialApp.router(
                theme: AppTheme.light(),
                locale: const Locale('en'),
                localizationsDelegates: AppLocalizations.localizationsDelegates,
                supportedLocales: AppLocalizations.supportedLocales,
                routerConfig: router,
              ),
            ),
          );
          await tester.pumpAndSettle();
        }

        // release 표 — 데모 경로가 없으므로 404.
        await pumpDemoPath(releaseRoutes);
        expect(find.byType(NotFoundScreen), findsOneWidget);
        expect(find.byType(DemoScreen), findsNothing);

        // 양성 대조 — 같은 경로가 비 release 표에서는 데모 화면이다.
        await pumpDemoPath(allRoutes);
        expect(find.byType(DemoScreen), findsOneWidget);
        expect(find.byType(NotFoundScreen), findsNothing);
      },
    );
  });
}
