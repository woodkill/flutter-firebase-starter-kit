import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter_starter_kit/core/config/auth_retry_config.dart';
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

/// Test 10 전용 — `currentUser` 가 non-null 인 상태를 만들기 위한 목.
///
/// `SplashInitializer` 는 `currentUser == null` 여부만 읽으므로 별도 stub 이
/// 필요 없다.
class _MockFirebaseUser extends Mock implements fb.User {}

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

/// Test 6 helper — Gap A 재entry redirect 시뮬레이션 라우터.
///
/// Phase 10.1 D-05 이후 "Sign in later" 탭 destination 이 `/login` 으로
/// 변경되었다. GC-04 fail-safe 자체는 `/login` 에서 trigger 안 되지만
/// (D-06 _unauthRoutes 자연 호환), 다른 redirect path 등장 시 안전망
/// 보존을 검증하기 위해 `/login` 첫 진입을 `/splash` 로 redirect 하는
/// 시뮬레이션을 모사한다. 두 번째 진입부터는 redirect 없이 `/login` 이
/// 통과한다 (재entry 후 init 성공 시 정상 Home 진입을 검증할 수 있도록).
GoRouter _testRouterWithRedirect({required void Function() onRedirect}) {
  var redirectCount = 0;
  return GoRouter(
    initialLocation: AppRoutes.splash,
    redirect: (context, state) {
      // Gap A 시뮬레이션: `/login` 첫 진입 시 1회만 `/splash` 로 redirect.
      if (state.matchedLocation == AppRoutes.login && redirectCount == 0) {
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
      GoRoute(
        path: AppRoutes.login,
        name: AppRoutes.loginName,
        builder: (_, _) => const Scaffold(body: Text('LOGIN')),
      ),
    ],
  );
}

/// Test 10 helper — GC-04 fail-safe redirect **시뮬레이션** 라우터.
///
/// [shouldRedirectHome] 이 `true` 를 반환하는 동안 [AppRoutes.home] 진입을
/// [AppRoutes.splash] 로 되돌려, SplashScreen 이 `/splash` 에 머무른 채
/// mounted 인 상태를 만든다. 2026-09-13 실 단말 로그의
/// `fail-safe race guard (...) -> /splash [Issue #10 GC-04]` 상황에 대응한다.
///
/// **이것은 시뮬레이션이며 실제 `resolveAuthRedirect` 가 아니다** — 그 함수의
/// 동작은 본 헬퍼로 검증되지 않는다.
///
/// 조건을 `bool Function()` 클로저로 받는 이유: 테스트 도중 redirect 를 꺼야
/// 재초기화 성공 후의 HOME 랜딩을 관측할 수 있다
/// ([_testRouterWithRedirect] 의 콜백 규약 mirror).
GoRouter _testRouterPinnedToSplash({
  required bool Function() shouldRedirectHome,
}) {
  return GoRouter(
    initialLocation: AppRoutes.splash,
    redirect: (context, state) {
      if (state.matchedLocation == AppRoutes.home && shouldRedirectHome()) {
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

/// Phase 10.1 helper — `/splash` + `/login` + `/home` 3 routes.
///
/// T6 widget test (Phase 10.1 W2: "Sign in later" 탭 → /login) 에서
/// AppRoutes.login 도달 검증용. `/login` 빌더는 'LOGIN' 텍스트만 렌더.
GoRouter _testRouterWithLogin() {
  return GoRouter(
    initialLocation: AppRoutes.splash,
    routes: [
      GoRoute(
        path: AppRoutes.splash,
        name: AppRoutes.splashName,
        builder: (_, _) => const SplashScreen(),
      ),
      GoRoute(
        path: AppRoutes.login,
        name: AppRoutes.loginName,
        builder: (_, _) => const Scaffold(body: Text('LOGIN')),
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
    // Phase 10.1 D-16: retry backoff 실대기 9s → 3ms 단축 (1ms × 3).
    AuthRetryConfig.overrideBackoffSteps = const [
      Duration(milliseconds: 1),
      Duration(milliseconds: 1),
      Duration(milliseconds: 1),
    ];
  });

  tearDown(() {
    SplashConfig.overrideMinDuration = null;
    AuthRetryConfig.overrideBackoffSteps = null;
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
          isSocialLinkInProgress: false,
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
        isSocialLinkInProgress: false,
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
          isSocialLinkInProgress: false,
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
        // Phase 10.1 D-08: splashContinueOffline 값 'Continue offline' →
        // 'Sign in later' 로 변경 (offline 분기 destination = /login).
        expect(find.text('Sign in later'), findsOneWidget);
        expect(find.text('Retry'), findsOneWidget);
      },
    );

    testWidgets(
      'Test 3b (10-REVIEW CR-02): initialize() 가 Result.failure 반환이 아니라 '
      'throw 해도 실패 다이얼로그가 뜨고 스피너가 사라진다',
      (tester) async {
        // 재현 수단은 실제 누출원과 동일한 경로다 — initialize() 의 첫 문장
        // `await onboardingFuture` 가 try 밖이므로 이 future 의 error 가
        // 그대로 initialize() 의 throw 가 된다. Error 계열을 쓰는 이유는
        // CR-03 이 기술한 실제 누출원(prefs cast TypeError)이 Error 이기 때문.
        //
        // 생성 즉시 완료되는 `Future.error` 는 _runInit 이 (post-frame
        // callback 이라) listener 를 붙이기 전에 이미 error 상태가 되어
        // flutter_test zone 이 이를 unhandled 로 보고해 버린다 — 프로덕션
        // 동작과 무관한 harness 잡음이다. delayed 로 지연시켜 listener 가
        // 붙은 뒤 error 가 도착하게 한다 (await 지점은 동일).
        final mockRepo = _MockAuthRepository();
        final initializer = SplashInitializer(
          authRepository: mockRepo,
          isFirebaseInitialized: true,
          currentUserIsNull: true,
          onboardingFuture: Future<bool>.delayed(
            const Duration(milliseconds: 5),
            () => throw StateError('onboarding prefs corrupted'),
          ),
          isSocialLinkInProgress: false,
        );
        final router = _testRouter();
        addTearDown(router.dispose);

        await _pumpSplash(tester, initializer: initializer, router: router);
        await tester.pump(const Duration(milliseconds: 50));
        await tester.pumpAndSettle();

        // Test 3 의 단언 집합을 mirror — 동일한 D-27 실패 다이얼로그로 수렴.
        expect(find.byType(AlertDialog), findsOneWidget);
        expect(find.text('Retry'), findsOneWidget);
        expect(find.text('Sign in later'), findsOneWidget);
        // _hasFailure == true 로 전이되어 무한 스피너가 사라졌다는 관측 증거.
        expect(
          find.byType(CircularProgressIndicator),
          findsNothing,
          reason: '예상 외 throw 도 탈출구가 있어야 한다 (무한 스피너 금지)',
        );
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

    testWidgets('Test 6 (Gap A 회귀 가드 — Phase 10.1 D-05 이후 "Sign in later" '
        '→ /login redirect 시뮬레이션 후 splash 재entry 시 '
        'splashInitializerProvider invalidate + _runInit 재실행): '
        '첫 init 실패 (retry × 3 소진) → "Sign in later" → context.go(/login) → '
        '시뮬레이션 redirect → /splash 재entry → re-init → '
        'signInAnonymously 5회째 호출 Success + Home 랜딩', (tester) async {
      // 시나리오 (Phase 10.1 D-05 + D-04 retry 도입 후):
      // 1. SplashInitializer.initialize() 첫 호출에 transient × 4
      //    (attempt 1 + retry 3) 모두 Failure(NoInternetConnection) →
      //    retry 소진 → splashFailureDialog 표시.
      // 2. 사용자 "Sign in later" 탭 → SplashScreen 이 context.go(/login) 호출.
      // 3. _testRouterWithRedirect() 가 /login 첫 진입을 가로채서 /splash 로
      //    redirect (D-05 이후에도 다른 redirect path 등장 시 Gap A 안전망
      //    보존 검증 — 시뮬레이션 목적).
      // 4. SplashScreen 재entry → didChangeDependencies hook 이
      //    splashInitializerProvider 를 invalidate + _runInit 재실행.
      // 5. 5번째 호출에서 signInAnonymously 가 Success 반환 → Home 랜딩.

      SharedPreferences.setMockInitialValues({'onboarding.seen_version': 1});

      // signInAnonymously 호출 카운터 — 1~4회: Failure (retry 소진), 5회: Success.
      var signInCallCount = 0;
      final mockRepo = _MockAuthRepository();
      when(mockRepo.signInAnonymously).thenAnswer((_) async {
        signInCallCount += 1;
        if (signInCallCount <= 4) {
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
      // Phase 10.1 D-08: 'Continue offline' → 'Sign in later'.
      expect(find.text('Sign in later'), findsOneWidget);

      // "Sign in later" 탭 → context.go(/login) → 시뮬레이션 redirect →
      // /splash 재entry.
      await tester.tap(find.text('Sign in later'));
      await tester.pumpAndSettle();

      // 재entry 시 re-init 이 실행되어 signInAnonymously 가 5회째 호출되고
      // Home 으로 랜딩되는지 확증 (1~4: 첫 init retry 소진, 5: 재entry success).
      expect(
        redirectFiredCount,
        1,
        reason:
            'Phase 10.1 D-05 시뮬레이션 redirect (/login → /splash) 1회 발동 '
            '— Gap A 안전망 보존 검증',
      );
      verify(mockRepo.signInAnonymously).called(5);
      expect(find.text('HOME'), findsOneWidget);
      expect(
        router.routerDelegate.currentConfiguration.uri.toString(),
        AppRoutes.home,
      );
    });

    /// Phase 10.1 W1: retry 소진 후 dialog 의 fingerprint Text + tap-to-copy
    /// SnackBar 표시 검증 (T-10.1-02 mitigation, Pattern D outer context).
    testWidgets('Test 7 (Phase 10.1 W1): retry 소진 후 fingerprint Text '
        '"Error code: unknown" 표시 + 탭 시 "Copied to clipboard" SnackBar', (
      tester,
    ) async {
      // Clipboard platform channel mock — test 환경에서 Clipboard.setData
      // 가 MissingPluginException 없이 통과하도록 stub.
      final clipboardMessenger = tester.binding.defaultBinaryMessenger;
      final copiedTextStore = <String>[];
      clipboardMessenger.setMockMethodCallHandler(SystemChannels.platform, (
        call,
      ) async {
        if (call.method == 'Clipboard.setData') {
          final args = call.arguments as Map<Object?, Object?>?;
          final text = args?['text'] as String?;
          if (text != null) copiedTextStore.add(text);
          return null;
        }
        if (call.method == 'Clipboard.getData') {
          return <String, Object?>{'text': copiedTextStore.lastOrNull};
        }
        return null;
      });
      addTearDown(() {
        clipboardMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        );
      });

      final mockRepo = _MockAuthRepository();
      // 4회 모두 fail — attempt 1 + retry 3 소진.
      when(mockRepo.signInAnonymously).thenAnswer(
        (_) async => Result.failure(
          ServiceUnavailable(cause: fb.FirebaseAuthException(code: 'unknown')),
        ),
      );
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
      final initializer = SplashInitializer(
        authRepository: mockRepo,
        isFirebaseInitialized: true,
        currentUserIsNull: true,
        onboardingFuture: Future.value(true),
        isSocialLinkInProgress: false,
        crashlyticsService: mockCrashlytics,
      );
      final router = _testRouterWithLogin();
      addTearDown(router.dispose);

      await _pumpSplash(tester, initializer: initializer, router: router);
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pumpAndSettle();

      // (1) Fingerprint Text 표시 (D-10 — code only, message PII 제외).
      expect(find.text('Error code: unknown'), findsOneWidget);

      // (1-b) WR-19: tap-to-copy 가 스크린 리더에 button 으로 노출된다.
      // 라벨만 있고 button role 이 없으면 복사 가능한 액션임을 알 수 없다.
      final semanticsHandle = tester.ensureSemantics();
      expect(
        tester.getSemantics(find.bySemanticsLabel('Error code: unknown')),
        isSemantics(
          label: 'Error code: unknown',
          isButton: true,
          hasTapAction: true,
        ),
      );
      semanticsHandle.dispose();

      // (2) Tap-to-copy + SnackBar (D-12, Pattern D outer context).
      await tester.tap(find.text('Error code: unknown'));
      await tester.pumpAndSettle();
      expect(find.text('Copied to clipboard'), findsOneWidget);

      // (3) Clipboard 에 D-10 PII-safe 포맷 ('splash_auto_signin: <code>')
      // 으로 저장되었는지 검증.
      expect(copiedTextStore, contains('splash_auto_signin: unknown'));

      // (4) Crashlytics emit 1회 검증 (D-14 — retry 소진 시점).
      verify(
        () => mockCrashlytics.setCustomKey(
          'splash_auto_signin_retry_exhausted',
          'unknown',
        ),
      ).called(1);
    });

    /// Phase 10.1 W2: "Sign in later" 탭 → /login 도달 + GC-04 race_guard
    /// trigger 안 됨 검증 (D-05, D-06).
    testWidgets('Test 8 (Phase 10.1 W2): "Sign in later" 탭 → '
        'context.go(/login) + verifyNever(race_guard_triggered)', (
      tester,
    ) async {
      final mockRepo = _MockAuthRepository();
      // 4회 모두 fail — dialog 도달.
      when(
        mockRepo.signInAnonymously,
      ).thenAnswer((_) async => const Result.failure(NoInternetConnection()));
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
      final initializer = SplashInitializer(
        authRepository: mockRepo,
        isFirebaseInitialized: true,
        currentUserIsNull: true,
        onboardingFuture: Future.value(true),
        isSocialLinkInProgress: false,
        crashlyticsService: mockCrashlytics,
      );
      final router = _testRouterWithLogin();
      addTearDown(router.dispose);

      await _pumpSplash(tester, initializer: initializer, router: router);
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pumpAndSettle();

      // (1) 다이얼로그 표시 확인.
      expect(find.byType(AlertDialog), findsOneWidget);

      // (2) "Sign in later" 탭.
      await tester.tap(find.text('Sign in later'));
      await tester.pumpAndSettle();

      // (3) /login 도달 검증.
      expect(find.text('LOGIN'), findsOneWidget);
      expect(
        router.routerDelegate.currentConfiguration.uri.toString(),
        AppRoutes.login,
      );

      // (4) GC-04 fail-safe race_guard_triggered key 가 호출되지 않음 검증
      // (D-06 — /login 은 _unauthRoutes 자연 포함, auth_guard GC-04 trigger
      // 안 됨). retry 소진 emit (splash_auto_signin_retry_exhausted) 만
      // 호출되고, race_guard_triggered 는 negative assert.
      verifyNever(
        () =>
            mockCrashlytics.setCustomKey('race_guard_triggered', any<Object>()),
      );
    });

    /// Phase 10.1 CR-01 회귀 가드: 다이얼로그의 "Retry" 버튼 탭 시 외곽
    /// `_runInit` 의 `_initInFlight = true` 가 아직 살아있는 시점에 재귀
    /// 호출되면 가드가 단락시켜 retry 가 no-op 가 된다. 본 테스트는 retry
    /// 버튼이 실제로 `signInAnonymously` 재호출을 발동하고 결과적으로 Home
    /// 으로 진입함을 검증한다 (D-27 "사용자 재시도" path 의 직접 회귀 가드).
    testWidgets(
      'Test 9 (Phase 10.1 CR-01 회귀 가드): "Retry" 탭 시 signInAnonymously 가 '
      '재호출되어 5회째 호출에서 Success → Home 진입',
      (tester) async {
        // 1~4회: NoInternetConnection (attempt 1 + retry 3 소진 → 다이얼로그).
        // 5회: Success (Retry 탭 후 재호출 성공 → Home).
        var callCount = 0;
        final mockRepo = _MockAuthRepository();
        when(mockRepo.signInAnonymously).thenAnswer((_) async {
          callCount += 1;
          if (callCount <= 4) {
            return const Result.failure(NoInternetConnection());
          }
          return Result.success(_stubUser());
        });
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
        final initializer = SplashInitializer(
          authRepository: mockRepo,
          isFirebaseInitialized: true,
          currentUserIsNull: true,
          onboardingFuture: Future.value(true),
          isSocialLinkInProgress: false,
          crashlyticsService: mockCrashlytics,
        );
        final router = _testRouterWithLogin();
        addTearDown(router.dispose);

        await _pumpSplash(tester, initializer: initializer, router: router);
        await tester.pump(const Duration(milliseconds: 50));
        await tester.pumpAndSettle();

        // (1) 첫 init 4회 소진 → 다이얼로그 표시.
        expect(find.byType(AlertDialog), findsOneWidget);
        expect(find.text('Retry'), findsOneWidget);
        expect(callCount, 4, reason: '첫 init 에서 attempt 1 + retry 3 소진');

        // (2) Retry 탭 → addPostFrameCallback 으로 `_runInit` 재진입
        // (CR-01 fix — 재귀 호출 시 _initInFlight 가드 단락 회피).
        await tester.tap(find.text('Retry'));
        await tester.pumpAndSettle();

        // (3) 5번째 호출에서 Success → Home 진입 확증.
        verify(mockRepo.signInAnonymously).called(5);
        expect(find.text('HOME'), findsOneWidget);
        expect(
          router.routerDelegate.currentConfiguration.uri.toString(),
          AppRoutes.home,
        );
      },
    );

    /// Phase 16 deferred-items 항목 1 회귀 가드 (2026-09-13 실 단말 재현,
    /// quick 260914-f1p) — 재초기화 훅 3 의 **발동**을 고정한다.
    ///
    /// **생성 시점 `currentUser != null` 이어야 성립한다.** 생성 시점 null 인
    /// 테스트는 첫 init 이 곧바로 `signInAnonymously` 를 타 버려 본 경로를
    /// 재현하지 못한다 — `SplashInitializer.currentUserIsNull` 이 생성 시점
    /// bool 캡처이기 때문이며, deferred-items 항목 1 의 「지름길 금지」가
    /// 가리키는 것과 같은 이유다.
    ///
    /// **이 테스트가 증명하지 않는 것:** 서버측 세션 폐기 → splash 무한 대기
    /// 라는 실 단말 경로가 닫혔다는 것. 그 판정에는 deferred-items 항목 1 의
    /// 5단계 재현 절차(특히 4단계 — 약 1시간 ID 토큰 만료 대기)가 필요하며
    /// 본 위젯 테스트는 그것을 대체하지 않는다. 여기서 고정하는 범위는
    /// 「생성 이후 `User -> null` 전이에서 훅이 실제로 발동한다」까지다.
    testWidgets(
      'Test 10 (Phase 16 deferred 항목 1 회귀 가드): 생성 시점 currentUser != null '
      '인 SplashScreen 이 /splash 에 머무른 채 auth 스트림이 User -> null 로 '
      '전이하면 재초기화가 발동해 signInAnonymously 가 1회 호출되고 Home 랜딩',
      (tester) async {
        SharedPreferences.setMockInitialValues({'onboarding.seen_version': 1});

        final mockRepo = _MockAuthRepository();
        when(
          mockRepo.signInAnonymously,
        ).thenAnswer((_) async => Result.success(_stubUser()));

        // 생성 시점 currentUser = non-null — 본 결함의 필수 전제.
        final mockAuth = _MockFirebaseAuth();
        final signedInUser = _MockFirebaseUser();
        when(() => mockAuth.currentUser).thenReturn(signedInUser);
        // broadcast — authStateProvider 가 재구독해도 "already listened" 없음.
        final authController = StreamController<fb.User?>.broadcast();
        addTearDown(authController.close);
        when(mockAuth.userChanges).thenAnswer((_) => authController.stream);

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

        // 전이 전에는 HOME 진입을 /splash 로 되돌려 SplashScreen 을 붙잡아 둔다.
        var pinToSplash = true;
        final router = _testRouterPinnedToSplash(
          shouldRedirectHome: () => pinToSplash,
        );
        addTearDown(router.dispose);

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              // splashInitializerProvider / authStateProvider 어느 쪽도
              // override 하지 않는다 — 실 provider chain (userChanges →
              // authStateProvider → ref.listen → ref.invalidate) 을 그대로
              // 통과시키는 것이 본 테스트의 요지다.
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

        // `/splash` 에 머무는 동안 CircularProgressIndicator 가 프레임을 계속
        // 스케줄하므로 pumpAndSettle 은 타임아웃한다 — 명시적 pump 반복만 쓴다.
        for (var i = 0; i < 10; i++) {
          await tester.pump(const Duration(milliseconds: 10));
        }

        // B-1: 첫 init 은 currentUser 가 있어 익명 사인인을 타지 않는다.
        // 이후 관측되는 재초기화가 auth 전이에 귀속됨을 고정한다 — 훅 1·2 는
        // location 이 불변이라 조건 자체가 성립하지 않는다.
        verifyNever(mockRepo.signInAnonymously);
        expect(
          router.routerDelegate.currentConfiguration.uri.path,
          AppRoutes.splash,
          reason: 'GC-04 시뮬레이션 redirect 로 SplashScreen 이 계속 mounted',
        );

        // 실 단말 로그의 `userChanges emit (uidHash=334766815)` 에 대응 —
        // 이 emit 이 있어야 listener 의 prev 가 값 이력을 갖는다.
        authController.add(signedInUser);
        for (var i = 0; i < 5; i++) {
          await tester.pump(const Duration(milliseconds: 10));
        }

        // 토큰 만료로 user 가 사라진 상태 재현 + redirect 해제.
        when(() => mockAuth.currentUser).thenReturn(null);
        pinToSplash = false;

        // 실 단말 로그의 `uidHash=null` 2연속 emit (중복 스냅샷) 재현.
        authController
          ..add(null)
          ..add(null);
        for (var i = 0; i < 20; i++) {
          await tester.pump(const Duration(milliseconds: 10));
        }

        // B-2 + B-3: 재초기화가 정확히 1회 발동한다 — 중복 null 스냅샷이
        // 재초기화 루프를 만들지 않음까지 함께 고정.
        verify(mockRepo.signInAnonymously).called(1);
        // B-4: 재초기화 성공 후 HOME 랜딩.
        expect(find.text('HOME'), findsOneWidget);
        expect(
          router.routerDelegate.currentConfiguration.uri.path,
          AppRoutes.home,
        );
      },
    );
  });
}
