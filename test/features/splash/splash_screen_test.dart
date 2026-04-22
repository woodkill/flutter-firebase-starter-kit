import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';

import 'package:flutter_starter_kit/core/config/splash_config.dart';
import 'package:flutter_starter_kit/core/error/app_exception.dart';
import 'package:flutter_starter_kit/core/error/result.dart';
import 'package:flutter_starter_kit/core/router/app_routes.dart';
import 'package:flutter_starter_kit/core/theme/app_theme.dart';
import 'package:flutter_starter_kit/features/auth/data/auth_repository.dart';
import 'package:flutter_starter_kit/features/splash/presentation/splash_screen.dart';
import 'package:flutter_starter_kit/features/splash/presentation/splash_initializer.dart';
import 'package:flutter_starter_kit/l10n/generated/app_localizations.dart';

class _MockAuthRepository extends Mock implements AuthRepository {}

Future<void> _pumpSplash(
  WidgetTester tester, {
  required SplashInitializer initializer,
  required GoRouter router,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        splashInitializerProvider.overrideWith((ref) => initializer),
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
    testWidgets('Test 1: 로고 + CircularProgressIndicator + splashPreparing 텍스트 렌더',
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
        await _pumpSplash(
          tester,
          initializer: initializer,
          router: router,
        );
        // 첫 프레임만 렌더 — init 은 5분 뒤 resolve 이므로 아직 진행 중.
        await tester.pump();
        expect(find.text('Getting things ready...'), findsOneWidget);
        expect(find.byType(CircularProgressIndicator), findsOneWidget);
        expect(find.byType(Image), findsOneWidget);
      });
    });

    testWidgets(
      'Test 2: WARNING #13 seam — 1ms 오버라이드 후 초기화 완료 시 Home 으로 go',
      (tester) async {
        final mockRepo = _MockAuthRepository();
        final initializer = SplashInitializer(
          authRepository: mockRepo,
          isFirebaseInitialized: false, // signInAnonymously 호출 안 함
          currentUserIsNull: true,
          onboardingFuture: Future.value(false),
        );
        final router = _testRouter();
        addTearDown(router.dispose);

        await _pumpSplash(
          tester,
          initializer: initializer,
          router: router,
        );
        // 1ms 대기 + addPostFrameCallback 처리.
        await tester.pump(const Duration(milliseconds: 50));
        await tester.pumpAndSettle();

        expect(find.text('HOME'), findsOneWidget);
        expect(
          router.routerDelegate.currentConfiguration.uri.toString(),
          AppRoutes.home,
        );
      },
    );

    testWidgets(
      'Test 3: signInAnonymously 실패 시 AlertDialog 표시 + splashFailureTitle/Message + 재시도/오프라인 버튼',
      (tester) async {
        final mockRepo = _MockAuthRepository();
        when(mockRepo.signInAnonymously).thenAnswer(
          (_) async => const Result.failure(NoInternetConnection()),
        );
        final initializer = SplashInitializer(
          authRepository: mockRepo,
          isFirebaseInitialized: true,
          currentUserIsNull: true,
          onboardingFuture: Future.value(true),
        );
        final router = _testRouter();
        addTearDown(router.dispose);

        await _pumpSplash(
          tester,
          initializer: initializer,
          router: router,
        );
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
  });
}
