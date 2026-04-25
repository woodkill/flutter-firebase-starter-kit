import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter_starter_kit/core/config/splash_config.dart';
import 'package:flutter_starter_kit/core/crashlytics/crashlytics_service.dart';
import 'package:flutter_starter_kit/core/error/app_exception.dart';
import 'package:flutter_starter_kit/core/error/result.dart';
import 'package:flutter_starter_kit/core/providers/firebase_providers.dart';
import 'package:flutter_starter_kit/core/router/app_routes.dart';
import 'package:flutter_starter_kit/core/theme/app_theme.dart';
import 'package:flutter_starter_kit/features/auth/data/auth_repository.dart';
import 'package:flutter_starter_kit/features/auth/domain/user.dart';
import 'package:flutter_starter_kit/features/splash/presentation/splash_screen.dart';
import 'package:flutter_starter_kit/features/splash/presentation/splash_initializer.dart';
import 'package:flutter_starter_kit/l10n/generated/app_localizations.dart';

class _MockAuthRepository extends Mock implements AuthRepository {}

class _MockFirebaseAuth extends Mock implements fb.FirebaseAuth {}

class _MockCrashlytics extends Mock implements CrashlyticsService {}

User _stubUser({String uid = 'anon-uid'}) => User(
  uid: uid,
  email: '',
  emailVerified: false,
  displayName: null,
  photoUrl: null,
  createdAt: DateTime.utc(2026, 4, 21),
  providerIds: const <String>[],
);

Future<void> _pumpSplash(
  WidgetTester tester, {
  required SplashInitializer initializer,
  required GoRouter router,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [splashInitializerProvider.overrideWith((ref) => initializer)],
      child: MaterialApp.router(
        theme: AppTheme.light(),
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        routerConfig: router,
      ),
    ),
  );
}

GoRouter _testRouter() {
  return GoRouter(
    initialLocation: AppRoutes.splash,
    routes: [
      GoRoute(
        path: AppRoutes.splash,
        name: AppRoutes.splashName,
        builder: (_, _) => const SplashScreen(),
      ),
      GoRoute(
        path: AppRoutes.home,
        name: AppRoutes.homeName,
        builder: (_, _) => const Scaffold(body: Text('HOME')),
      ),
    ],
  );
}

/// Test 6 helper — GC-04 fail-safe redirect 시뮬레이션 라우터.
///
/// `/` 경로 첫 진입 시 `/splash` 로 redirect 하여 Plan 10-14 의 GC-04
/// fail-safe 분기 (currentUser=null + onboardingSeen=true → /splash) 를
/// 모사한다. 두 번째부터는 redirect 없이 `/` 가 통과하여 무한 루프를
/// 방지한다 (재entry 후 init 성공 시 정상 Home 진입을 검증할 수 있도록).
GoRouter _testRouterWithRedirect({required void Function() onRedirect}) {
  var redirectCount = 0;
  return GoRouter(
    initialLocation: AppRoutes.splash,
    redirect: (context, state) {
      // GC-04 fail-safe 시뮬레이션: `/` 첫 진입 시 1회만 `/splash` 로 redirect.
      if (state.matchedLocation == AppRoutes.home && redirectCount == 0) {
        redirectCount += 1;
        onRedirect();
        return AppRoutes.splash;
      }
      return null;
    },
    routes: [
      GoRoute(
        path: AppRoutes.splash,
        name: AppRoutes.splashName,
        builder: (_, _) => const SplashScreen(),
      ),
      GoRoute(
        path: AppRoutes.home,
        name: AppRoutes.homeName,
        builder: (_, _) => const Scaffold(body: Text('HOME')),
      ),
    ],
  );
}

void main() {
  setUpAll(() {
    registerFallbackValue(StackTrace.empty);
  });

  // WARNING #13: 실대기 1ms 로 단축 (피드백 레이턴시 < 100ms).
  setUp(() {
    SplashConfig.overrideMinDuration = const Duration(milliseconds: 1);
  });

  tearDown(() {
    SplashConfig.overrideMinDuration = null;
  });

  group('SplashScreen (Phase 10 AUTH-08, D-22, D-25, D-27, WARNING #13)', () {
    testWidgets(
      'Test 1: 로고 + CircularProgressIndicator + splashPreparing 텍스트 렌더',
      (tester) async {
        // 초기 빌드 단계만 검증. minDuration 을 길게 설정해 init 완료되지
        // 않도록 고정하고, tester.pump() 1회만 실행하여 pending timer 로
        // dispose 가 실패하지 않도록 Home 이동 전에 FakeAsync 루프를 닫는다.
        SplashConfig.overrideMinDuration = const Duration(minutes: 5);

        final mockRepo = _MockAuthRepository();
        final initializer = SplashInitializer(
          authRepository: mockRepo,
          isFirebaseInitialized: false,
          currentUserIsNull: true,
          onboardingFuture: Future.value(false),
        );
        final router = _testRouter();
        addTearDown(router.dispose);

        await tester.runAsync(() async {
          await _pumpSplash(tester, initializer: initializer, router: router);
          // 첫 프레임만 렌더 — init 은 5분 뒤 resolve 이므로 아직 진행 중.
          await tester.pump();
          expect(find.text('Getting things ready...'), findsOneWidget);
          expect(find.byType(CircularProgressIndicator), findsOneWidget);
          expect(find.byType(Image), findsOneWidget);
        });
      },
    );

    testWidgets('Test 2: WARNING #13 seam — 1ms 오버라이드 후 초기화 완료 시 Home 으로 go', (
      tester,
    ) async {
      final mockRepo = _MockAuthRepository();
      final initializer = SplashInitializer(
        authRepository: mockRepo,
        isFirebaseInitialized: false, // signInAnonymously 호출 안 함
        currentUserIsNull: true,
        onboardingFuture: Future.value(false),
      );
      final router = _testRouter();
      addTearDown(router.dispose);

      await _pumpSplash(tester, initializer: initializer, router: router);
      // 1ms 대기 + addPostFrameCallback 처리.
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pumpAndSettle();

      expect(find.text('HOME'), findsOneWidget);
      expect(
        router.routerDelegate.currentConfiguration.uri.toString(),
        AppRoutes.home,
      );
    });

    testWidgets(
      'Test 3: signInAnonymously 실패 시 AlertDialog 표시 + splashFailureTitle/Message + 재시도/오프라인 버튼',
      (tester) async {
        final mockRepo = _MockAuthRepository();
        when(
          mockRepo.signInAnonymously,
        ).thenAnswer((_) async => const Result.failure(NoInternetConnection()));
        final initializer = SplashInitializer(
          authRepository: mockRepo,
          isFirebaseInitialized: true,
          currentUserIsNull: true,
          onboardingFuture: Future.value(true),
        );
        final router = _testRouter();
        addTearDown(router.dispose);

        await _pumpSplash(tester, initializer: initializer, router: router);
        await tester.pump(const Duration(milliseconds: 50));
        await tester.pumpAndSettle();

        expect(find.byType(AlertDialog), findsOneWidget);
        expect(find.text("Can't connect right now"), findsOneWidget);
        expect(
          find.text(
            "Something's blocking the connection. "
            'You can retry or continue offline.',
          ),
          findsOneWidget,
        );
        expect(find.text('Continue offline'), findsOneWidget);
        expect(find.text('Retry'), findsOneWidget);
      },
    );

    testWidgets(
      'Test 4: WARNING #13 seam — setUp/tearDown 패턴이 overrideMinDuration 을 1ms 로 설정/리셋',
      (tester) async {
        // setUp 후 시작 시점의 minDuration 이 1ms.
        expect(
          SplashConfig.overrideMinDuration,
          const Duration(milliseconds: 1),
          reason: 'setUp 에서 1ms 로 오버라이드되어야 한다',
        );
        expect(
          SplashConfig.minDuration,
          const Duration(milliseconds: 1),
          reason: 'minDuration getter 가 override 를 우선 반환',
        );
      },
    );

    testWidgets('Test 5 (Issue #10 Plan 10-14 — race 회귀 가드): '
        'SharedPreferences seen_version=1 + currentUser=null + '
        'splashInitializerProvider override **없이** 실제 Provider chain '
        '으로 signInAnonymously 가 1회 호출되고 Home 으로 이동한다', (tester) async {
      // 재현 조건: UAT Test 17 2-run 로그와 동일 — onboardingSeen=true
      // prefs + Firebase Auth 익명 캐시 없음.
      SharedPreferences.setMockInitialValues({'onboarding.seen_version': 1});

      final mockRepo = _MockAuthRepository();
      when(
        mockRepo.signInAnonymously,
      ).thenAnswer((_) async => Result.success(_stubUser()));

      final mockAuth = _MockFirebaseAuth();
      when(() => mockAuth.currentUser).thenReturn(null);
      when(
        mockAuth.userChanges,
      ).thenAnswer((_) => const Stream<fb.User?>.empty());

      final mockCrashlytics = _MockCrashlytics();
      when(
        () => mockCrashlytics.recordError(
          any<Object>(),
          any<StackTrace?>(),
          reason: any(named: 'reason'),
          fatal: any(named: 'fatal'),
        ),
      ).thenAnswer((_) async {});
      when(
        () => mockCrashlytics.setCustomKey(any(), any<Object>()),
      ).thenAnswer((_) async {});
      when(() => mockCrashlytics.setUserId(any())).thenAnswer((_) async {});

      final router = _testRouter();
      addTearDown(router.dispose);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            // Issue #10 Plan 10-14: splashInitializerProvider override 하지
            // 않음 — 실제 OnboardingNotifier (AsyncNotifier) +
            // SharedPreferences (setMockInitialValues) + mock FirebaseAuth
            // 조합으로 race path 재현. Plan 10-14 이전 구조에서는
            // onboardingSeen=false snapshot 으로 signInAnonymously 가
            // 스킵되어 이 테스트가 FAIL.
            isFirebaseInitializedProvider.overrideWithValue(true),
            firebaseAuthProvider.overrideWithValue(mockAuth),
            authRepositoryProvider.overrideWithValue(mockRepo),
            crashlyticsServiceProvider.overrideWithValue(mockCrashlytics),
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

      // postFrameCallback + prefs 로드 + minDuration + signInAnonymously
      // 전부 settle 하도록 충분히 pump.
      await tester.pump(const Duration(milliseconds: 10));
      await tester.pumpAndSettle();

      // 핵심 검증: race 제거 확증.
      verify(mockRepo.signInAnonymously).called(1);
      expect(find.text('HOME'), findsOneWidget);
      expect(
        router.routerDelegate.currentConfiguration.uri.toString(),
        AppRoutes.home,
      );
    });

    testWidgets('Test 6 (Gap A 회귀 가드 — GC-04 redirect 후 splash 재entry 시 '
        'splashInitializerProvider invalidate + _runInit 재실행): '
        '첫 init 실패 → "Continue offline" → context.go(/) → GC-04 redirect → '
        '/splash 재entry → re-init → signInAnonymously 2회 호출 + Home 랜딩', (
      tester,
    ) async {
      // 시나리오:
      // 1. SplashInitializer.initialize() 첫 호출에 Failure(NoInternetConnection)
      //    → splashFailureDialog 표시.
      // 2. 사용자 "Continue offline" 탭 → SplashScreen 이 context.go(/) 호출.
      // 3. _testRouterWithRedirect() 가 / 진입을 가로채서 /splash 로 redirect
      //    (Plan 10-14 GC-04 fail-safe 시뮬레이션).
      // 4. SplashScreen 재entry → didChangeDependencies hook 이
      //    splashInitializerProvider 를 invalidate + _runInit 재실행.
      // 5. 두 번째 호출에서 signInAnonymously 가 Success 반환 → Home 랜딩.

      SharedPreferences.setMockInitialValues({'onboarding.seen_version': 1});

      // signInAnonymously 호출 카운터 — 1회: Failure, 2회: Success.
      var signInCallCount = 0;
      final mockRepo = _MockAuthRepository();
      when(mockRepo.signInAnonymously).thenAnswer((_) async {
        signInCallCount += 1;
        if (signInCallCount == 1) {
          return const Result.failure(NoInternetConnection());
        }
        return Result.success(_stubUser());
      });

      final mockAuth = _MockFirebaseAuth();
      when(() => mockAuth.currentUser).thenReturn(null);
      when(
        mockAuth.userChanges,
      ).thenAnswer((_) => const Stream<fb.User?>.empty());

      final mockCrashlytics = _MockCrashlytics();
      when(
        () => mockCrashlytics.recordError(
          any<Object>(),
          any<StackTrace?>(),
          reason: any(named: 'reason'),
          fatal: any(named: 'fatal'),
        ),
      ).thenAnswer((_) async {});
      when(
        () => mockCrashlytics.setCustomKey(any(), any<Object>()),
      ).thenAnswer((_) async {});
      when(() => mockCrashlytics.setUserId(any())).thenAnswer((_) async {});

      var redirectFiredCount = 0;
      final router = _testRouterWithRedirect(
        onRedirect: () => redirectFiredCount += 1,
      );
      addTearDown(router.dispose);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            // splashInitializerProvider 는 override 하지 않음 — 실제 Provider
            // chain 으로 ref.invalidate 가 새 인스턴스를 생성하는지 확증.
            isFirebaseInitializedProvider.overrideWithValue(true),
            firebaseAuthProvider.overrideWithValue(mockAuth),
            authRepositoryProvider.overrideWithValue(mockRepo),
            crashlyticsServiceProvider.overrideWithValue(mockCrashlytics),
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

      // 첫 init 실패 + dialog 표시까지 settle.
      await tester.pump(const Duration(milliseconds: 10));
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.text('Continue offline'), findsOneWidget);

      // "Continue offline" 탭 → context.go(/) → redirect → /splash 재entry.
      await tester.tap(find.text('Continue offline'));
      await tester.pumpAndSettle();

      // 재entry 시 re-init 이 실행되어 signInAnonymously 가 2회째 호출되고
      // Home 으로 랜딩되는지 확증.
      expect(
        redirectFiredCount,
        1,
        reason: 'GC-04 fail-safe redirect 가 / → /splash 로 1회 발동',
      );
      verify(mockRepo.signInAnonymously).called(2);
      expect(find.text('HOME'), findsOneWidget);
      expect(
        router.routerDelegate.currentConfiguration.uri.toString(),
        AppRoutes.home,
      );
    });
  });
}
