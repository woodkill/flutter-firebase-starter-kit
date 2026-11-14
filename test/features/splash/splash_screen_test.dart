import 'dart:async';
import 'dart:ui' as ui;

import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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
import 'package:flutter_starter_kit/features/splash/presentation/splash_body.dart';
import 'package:flutter_starter_kit/features/splash/presentation/splash_error_code.dart';
import 'package:flutter_starter_kit/features/splash/presentation/splash_frame.dart';
import 'package:flutter_starter_kit/features/splash/presentation/splash_initializer.dart';
import 'package:flutter_starter_kit/features/splash/presentation/splash_screen.dart';
import 'package:flutter_starter_kit/l10n/generated/app_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _MockAuthRepository extends Mock implements AuthRepository {}

class _MockFirebaseAuth extends Mock implements fb.FirebaseAuth {}

class _MockCrashlytics extends Mock implements CrashlyticsService {}

/// Test 10 전용 — `currentUser` 가 non-null 인 상태를 만들기 위한 목.
///
/// `SplashInitializer` 는 `currentUser == null` 여부만 읽으므로 별도 stub 이
/// 필요 없다.
class _MockFirebaseUser extends Mock implements fb.User {}

User _stubUser({String uid = 'anon-uid'}) =>
    User(uid: uid, emailVerified: false, createdAt: DateTime.utc(2026, 4, 21));

/// 킷 시험용 로고 아래 내용 — 내 화면(`splash_body.dart`)에 기대지 않는다.
///
/// 실패 신호(`hasFailure`)가 넘어왔는지만 글자로 드러낸다.
Widget _buildTestBody(BuildContext context, {required bool hasFailure}) =>
    Text(hasFailure ? 'TEST_BODY failed' : 'TEST_BODY running');

/// [SplashScreen] 을 [router] 로 pump 한다 (기본 en — [locale] 로 바꾼다).
///
/// 앱 테마는 [themeMode] 로 고른다 — 기본 [ThemeMode.system] 은 OS 밝기를
/// 따르고, 시험의 OS 밝기 기본값이 라이트라 라이트 테마다. [bundle] 을 주면
/// 로고를 내 로고 파일 대신 그 자산 묶음에서 읽는다.
Future<void> _pumpSplash(
  WidgetTester tester, {
  required SplashInitializer initializer,
  required GoRouter router,
  Locale locale = const Locale('en'),
  ThemeMode themeMode = ThemeMode.system,
  AssetBundle? bundle,
}) async {
  final app = MaterialApp.router(
    theme: AppTheme.light(),
    darkTheme: AppTheme.dark(),
    themeMode: themeMode,
    locale: locale,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    routerConfig: router,
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: [splashInitializerProvider.overrideWith((ref) => initializer)],
      child: bundle == null
          ? app
          : DefaultAssetBundle(bundle: bundle, child: app),
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
        builder: (_, _) => const SplashScreen(bodyBuilder: _buildTestBody),
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
        builder: (_, _) => const SplashScreen(bodyBuilder: _buildTestBody),
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
///
/// Test 11·12 도 `currentUser` 기반 클로저로 재사용한다.
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
        builder: (_, _) => const SplashScreen(bodyBuilder: _buildTestBody),
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
        builder: (_, _) => const SplashScreen(bodyBuilder: _buildTestBody),
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
    testWidgets('Test 1: 로고 + 시험용 로고 아래 내용 렌더', (tester) async {
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
        expect(find.text('TEST_BODY running'), findsOneWidget);
        expect(find.byType(Image), findsOneWidget);
      });
    });

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
      'throw 해도 실패 다이얼로그가 뜨고 로고 아래 내용에 실패 신호가 넘어간다',
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
        // _hasFailure == true 가 로고 아래 내용에 넘어갔다는 관측 증거 — 진행
        // 표시를 숨기는 것은 그 신호를 받은 내 화면의 몫이다.
        expect(
          find.text('TEST_BODY failed'),
          findsOneWidget,
          reason: '예상 외 throw 도 실패 신호가 로고 아래 내용에 넘어가야 한다',
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

        // 명시적 pump 반복만 쓴다 — 내 화면(`buildSplashBody`)의 진행 표시는
        // 프레임을 계속 요청해 pumpAndSettle 이 타임아웃한다. 이 시험은 애니메이션
        // 없는 시험용 화면을 넣지만 pump 꼴은 그대로 둔다.
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

    /// Phase 16 deferred-items 항목 1 — init 진행 중 전이 경로 (2026-09-14 실
    /// 단말 UAT FAIL, quick 260914-k81).
    ///
    /// **근거와 연역 경계:** quick 260914-f1p 적용 APK 에서 splash 스피너 고착이
    /// 다시 관측됐다. 로그에서 `userChanges emit (uidHash=null)` 이 첫 init 의
    /// `context.go` 로 해석한 `matchedLocation=/` 로그보다 52ms 먼저 찍혔고,
    /// 이로부터 「전이가 minDuration 창 안(`_initInFlight` 참)에 도착해 재초기화
    /// 신호가 버려졌다」고 **연역**했다. 훅 발화와 신호 소실 자체는 계측하지
    /// 않았다(계측 미수행).
    ///
    /// **Test 10 이 이 경로를 못 잡는 이유:** Test 10 은 setUp 의 1ms
    /// minDuration 을 그대로 쓰고 init 완료 후에 전이시키므로 전이 시점에
    /// in-flight 가 이미 거짓이다 — 구조적으로 post-init 전이만 본다.
    ///
    /// **값의 출처:** 2000ms = UAT APK 가 쓴 `config/dev.json` 의
    /// `splashMinDurationMs`. 52ms = 위 두 로그(`14:17:41.901` ↔
    /// `14:17:41.953`) 사이 측정 간격을 창 종료 전 여유로 그대로 옮긴 값.
    ///
    /// **이 테스트가 증명하지 않는 것:** 실 단말 고착 경로가 닫혔다는 것. 그
    /// 판정에는 deferred-items 항목 1 의 5단계 재현(비익명 계정 + 발급 후 약
    /// 1시간 토큰 만료 대기)이 다시 필요하다. 여기서 고정하는 범위는 「창 안
    /// 전이 신호가 보류됐다가 init 종료 후 1회 재초기화로 이어진다」까지다.
    ///
    /// **라우터 고정을 `currentUser` 에 연동하는 이유:** Test 10 처럼 emit
    /// 시점에 bool 을 끄면 첫 init 의 `context.go` 가 HOME 에 착지해
    /// SplashScreen 이 해체되므로 실 고착 상태(`/splash` 에 mounted)를 재현하지
    /// 못하고, 보류 재실행도 `mounted` 검사에 걸려 올바른 이유로 GREEN 이 될
    /// 수 없다.
    testWidgets(
      'Test 11 (Phase 16 deferred 항목 1 — init 진행 중 전이): minDuration 창 '
      '안에서 auth 스트림이 User -> null 로 전이해도 재초기화 신호가 보류됐다가 '
      'init 종료 후 1회 발동해 signInAnonymously 1회 + Home 랜딩',
      (tester) async {
        // UAT APK 실값 — 복원은 tearDown 이 한다.
        SplashConfig.overrideMinDuration = const Duration(milliseconds: 2000);
        SharedPreferences.setMockInitialValues({'onboarding.seen_version': 1});

        final mockAuth = _MockFirebaseAuth();
        final signedInUser = _MockFirebaseUser();
        final anonymousUser = _MockFirebaseUser();
        // 테스트 도중 재할당된다 — stub 은 응답 시점에 이 변수를 읽는다.
        fb.User? currentUser = signedInUser;
        when(() => mockAuth.currentUser).thenAnswer((_) => currentUser);
        // broadcast — authStateProvider 가 재구독해도 "already listened" 없음.
        final authController = StreamController<fb.User?>.broadcast();
        addTearDown(authController.close);
        when(mockAuth.userChanges).thenAnswer((_) => authController.stream);

        final mockRepo = _MockAuthRepository();
        when(mockRepo.signInAnonymously).thenAnswer((_) async {
          // 새 익명 사용자가 생긴 상태 재현.
          currentUser = anonymousUser;
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
        when(() => mockCrashlytics.setUserId(any())).thenAnswer((_) async {});

        var homeRedirectCount = 0;
        final router = _testRouterPinnedToSplash(
          shouldRedirectHome: () {
            // 헬퍼가 `/` 매칭일 때만 이 클로저를 평가하므로 호출 수 = `/`
            // redirect 평가 수다 — `_runInit` 의 `context.go` 도달을 관측하는
            // 외부 신호. currentUser 가 null 인 동안 `/` 를 `/splash` 로
            // 되돌린다 (GC-04 시뮬레이션).
            homeRedirectCount++;
            return currentUser == null;
          },
        );
        addTearDown(router.dispose);

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
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

        // pumpAndSettle 대신 명시적 pump 만 쓴다 — 내 화면의 진행 표시는 프레임을
        // 계속 요청한다(이 시험은 시험용 화면을 넣지만 pump 꼴은 그대로 둔다).
        for (var i = 0; i < 5; i++) {
          await tester.pump(const Duration(milliseconds: 10));
        }
        // listener 의 prev 가 값 이력을 갖게 하는 emit.
        authController.add(signedInUser);
        for (var i = 0; i < 5; i++) {
          await tester.pump(const Duration(milliseconds: 10));
        }
        // t=1948 — 창 종료 52ms 전.
        await tester.pump(const Duration(milliseconds: 1848));

        // C-1: 전제 — 첫 init 은 아직 익명 사인인도 context.go 도 하지 않았다.
        verifyNever(mockRepo.signInAnonymously);
        expect(homeRedirectCount, 0);
        expect(
          router.routerDelegate.currentConfiguration.uri.path,
          AppRoutes.splash,
        );

        // 토큰 만료로 user 가 사라진 상태 + 실 로그의 null 2연속 emit 재현.
        currentUser = null;
        authController
          ..add(null)
          ..add(null);
        await tester.pump();
        for (var i = 0; i < 2; i++) {
          await tester.pump(const Duration(milliseconds: 10));
        }

        // C-2: 창 안 도착의 외부 증거.
        expect(
          homeRedirectCount,
          0,
          reason: '전이 처리 시점에 첫 init 이 아직 context.go 전 — in-flight 창 안',
        );

        // t≈2068 — 첫 init 완료.
        for (var i = 0; i < 10; i++) {
          await tester.pump(const Duration(milliseconds: 10));
        }

        // C-3: 첫 init 의 context.go 가 GC-04 시뮬레이션으로 /splash 에 고정.
        expect(homeRedirectCount, greaterThanOrEqualTo(1));
        expect(
          router.routerDelegate.currentConfiguration.uri.path,
          AppRoutes.splash,
        );

        // C-4: 보류된 신호가 init 종료 후 재초기화로 소비됐다.
        verify(mockRepo.signInAnonymously).called(1);

        // t≈4568 — 재실행의 2000ms 대기 + HOME 전환 소화.
        for (var i = 0; i < 25; i++) {
          await tester.pump(const Duration(milliseconds: 100));
        }

        // C-5: 재초기화의 익명 사인인 성공 후 HOME 랜딩.
        expect(find.text('HOME'), findsOneWidget);
        expect(
          router.routerDelegate.currentConfiguration.uri.path,
          AppRoutes.home,
        );
      },
    );

    /// 보류 재초기화 상한 고정 (quick 260914-k81).
    ///
    /// init 진행 중 신호를 보류 후 소비하는 변경에 무한 루프 방지 상한
    /// (`_kMaxDeferredReinitCount`, SplashScreen State 수명당 1회)이 걸려 있음을
    /// 고정한다. 도입부는 Test 11 과 같고, 보류 재실행이 진행 중인 창 안에서
    /// 다시 `User -> null` 전이를 넣어 추가 재실행이 없는지 본다. 사인인 누계를
    /// 여러 시점에서 단언하므로 mocktail `verify(...).called(n)` (매칭 호출을
    /// verified 로 표시해 이후 새 호출만 센다) 대신 수동 카운터를 쓴다.
    ///
    /// 마지막의 `/splash` 잔류 단언은 **의도적으로** 상한의 대가를 기록한다 —
    /// 상한을 넘긴 뒤 창 안에 온 전이는 버려지므로 같은 부류의 고착이 다시 생길
    /// 수 있다. 이 테스트는 실 단말 경로가 닫혔음을 증명하지 않는다.
    testWidgets('Test 12 (보류 재초기화 상한): 보류 재실행 진행 중 창 안에서 다시 '
        'User -> null 전이가 와도 보류 재실행은 State 수명당 1회로 제한되어 '
        'signInAnonymously 누계 1회 + /splash 잔류 (알려진 한계)', (tester) async {
      // UAT APK 실값 — 복원은 tearDown 이 한다.
      SplashConfig.overrideMinDuration = const Duration(milliseconds: 2000);
      SharedPreferences.setMockInitialValues({'onboarding.seen_version': 1});

      final mockAuth = _MockFirebaseAuth();
      final signedInUser = _MockFirebaseUser();
      final anonymousUser = _MockFirebaseUser();
      // 테스트 도중 재할당된다 — stub 은 응답 시점에 이 변수를 읽는다.
      fb.User? currentUser = signedInUser;
      when(() => mockAuth.currentUser).thenAnswer((_) => currentUser);
      final authController = StreamController<fb.User?>.broadcast();
      addTearDown(authController.close);
      when(mockAuth.userChanges).thenAnswer((_) => authController.stream);

      var signInCallCount = 0;
      final mockRepo = _MockAuthRepository();
      when(mockRepo.signInAnonymously).thenAnswer((_) async {
        signInCallCount++;
        currentUser = anonymousUser;
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
      when(() => mockCrashlytics.setUserId(any())).thenAnswer((_) async {});

      var homeRedirectCount = 0;
      final router = _testRouterPinnedToSplash(
        shouldRedirectHome: () {
          // 호출 수 = `/` redirect 평가 수 (Test 11 과 같은 외부 신호).
          homeRedirectCount++;
          return currentUser == null;
        },
      );
      addTearDown(router.dispose);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
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

      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 10));
      }
      authController.add(signedInUser);
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 10));
      }
      // t=1948 — 첫 init 창 종료 52ms 전.
      await tester.pump(const Duration(milliseconds: 1848));

      // D-1: 첫 init 창 안 전이 → 보류.
      currentUser = null;
      authController
        ..add(null)
        ..add(null);
      await tester.pump();
      for (var i = 0; i < 2; i++) {
        await tester.pump(const Duration(milliseconds: 10));
      }
      // t≈2098 — 첫 init 완료, 보류 재실행 시작.
      for (var i = 0; i < 13; i++) {
        await tester.pump(const Duration(milliseconds: 10));
      }

      expect(signInCallCount, 1);
      final redirectsAfterFirstGo = homeRedirectCount;
      expect(redirectsAfterFirstGo, greaterThanOrEqualTo(1));

      // listener 의 prev 를 새 익명 사용자로 갱신.
      authController.add(anonymousUser);
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 10));
      }
      // t≈3000 — 보류 재실행의 minDuration 창 한가운데.
      await tester.pump(const Duration(milliseconds: 850));

      // D-2: 보류 재실행 진행 중 창 안에서 다시 User -> null.
      currentUser = null;
      authController.add(null);
      await tester.pump();
      for (var i = 0; i < 2; i++) {
        await tester.pump(const Duration(milliseconds: 10));
      }

      expect(
        homeRedirectCount,
        redirectsAfterFirstGo,
        reason: '두 번째 전이 처리 시점에 보류 재실행이 아직 context.go 전 — 창 안',
      );

      // t≈8420 — 재실행 완료 + 두 창 이상 추가 경과.
      for (var i = 0; i < 54; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }

      // 순서 고정 — 상한을 올리면 이 단언에서 먼저 실패해야 한다.
      expect(
        signInCallCount,
        1,
        reason: '보류 재초기화는 State 수명당 _kMaxDeferredReinitCount(1)회',
      );
      expect(homeRedirectCount, greaterThan(redirectsAfterFirstGo));
      // D-3: 알려진 한계 — 상한 초과 후 전이는 버려져 /splash 에 남는다.
      expect(
        router.routerDelegate.currentConfiguration.uri.path,
        AppRoutes.splash,
      );
    });
  });

  group('SplashScreen 가로 모드 (Phase 3 D-09 · quick 261003-0fp)', () {
    tearDown(() {
      SplashConfig.overrideMinDuration = null;
    });

    for (final size in _landscapeSizes) {
      for (final locale in _sweepLocales) {
        final label = '${_formatSize(size)} · ${locale.languageCode}';

        // 로고 파일과 떼어 놓음 — 내 로고 파일 대신 킷 자리 그림 크기의 시험용
        // 로고로 그려, adopter 가 로고를 바꿔도 「킷 배치에서 아래 내용이 가로
        // 칸에 들어가는가」 라는 같은 뜻을 본다.
        testWidgets('SB ($label): 스플래시 본문 넘침 0 · 시험용 로고 · '
            '261003-0fp', (tester) async {
          // Test 1 방식 — init 이 5분 뒤에 끝나 대기 상태 첫 프레임만 본다.
          SplashConfig.overrideMinDuration = const Duration(minutes: 5);
          final png = await _createLogoPng(tester, _kLandscapeLogoPngPixels);
          _setLogicalViewport(tester, size);
          final initializer = SplashInitializer(
            authRepository: _MockAuthRepository(),
            isFirebaseInitialized: false,
            currentUserIsNull: true,
            onboardingFuture: Future.value(false),
            isSocialLinkInProgress: false,
          );
          final router = _testRouter();
          addTearDown(router.dispose);

          await tester.runAsync(() async {
            await _pumpSplash(
              tester,
              initializer: initializer,
              router: router,
              locale: locale,
              bundle: _PngAssetBundle(png),
            );
            await tester.pump();
            // 시험용 로고를 디코딩해 그 크기로 배치한 프레임을 본다.
            final logo = find.byType(Image);
            await precacheImage(
              tester.widget<Image>(logo).image,
              tester.element(logo),
            );
            await tester.pump();
            expect(
              tester.getSize(logo),
              const Size.square(_kLandscapeLogoPngPixels / _kImageScale),
              reason: '$label 시험용 로고 크기',
            );
            expect(tester.takeException(), isNull, reason: '$label 본문');
            final body = find.text('TEST_BODY running');
            expect(body, findsOneWidget, reason: '$label 시험용 표시');
            expect(
              tester.getRect(body).bottom,
              lessThanOrEqualTo(size.height),
              reason: '$label 시험용 표시가 화면 안',
            );
          });
        });

        testWidgets('SD ($label): 실패 다이얼로그 넘침 0 · 액션 · 지문 도달 · '
            '261003-0fp', (tester) async {
          _setLogicalViewport(tester, size);
          final mockRepo = _MockAuthRepository();
          when(mockRepo.signInAnonymously).thenAnswer(
            (_) async => const Result.failure(NoInternetConnection()),
          );
          final initializer = SplashInitializer(
            authRepository: mockRepo,
            isFirebaseInitialized: true,
            currentUserIsNull: true,
            onboardingFuture: Future.value(true),
            isSocialLinkInProgress: false,
          );
          final router = _testRouter();
          addTearDown(router.dispose);

          await _pumpSplash(
            tester,
            initializer: initializer,
            router: router,
            locale: locale,
          );
          await tester.pump(const Duration(milliseconds: 50));
          await tester.pumpAndSettle();

          final l10n = lookupAppLocalizations(locale);
          final dialog = find.byType(AlertDialog);
          expect(dialog, findsOneWidget, reason: '$label 다이얼로그 열림');
          expect(tester.takeException(), isNull, reason: '$label 다이얼로그');
          expect(
            find
                .descendant(
                  of: dialog,
                  matching: find.widgetWithText(FilledButton, l10n.commonRetry),
                )
                .hitTestable(),
            findsOneWidget,
            reason: '$label 재시도 도달',
          );
          expect(
            find
                .descendant(
                  of: dialog,
                  matching: find.widgetWithText(
                    TextButton,
                    l10n.splashContinueOffline,
                  ),
                )
                .hitTestable(),
            findsOneWidget,
            reason: '$label 나중에 로그인 도달',
          );
          final fingerprint = find.descendant(
            of: dialog,
            matching: find.text(
              l10n.splashErrorCodeFingerprint(
                extractSplashErrorCode(const NoInternetConnection()),
              ),
            ),
          );
          await tester.ensureVisible(fingerprint);
          await tester.pumpAndSettle();
          expect(
            fingerprint.hitTestable(),
            findsOneWidget,
            reason: '$label 오류 지문 도달',
          );
          expect(tester.takeException(), isNull, reason: '$label 마지막');
        });
      }
    }

    testWidgets('P (360x800 · ko): 실패 다이얼로그 세로 rect 고정 · 261003-0fp', (
      tester,
    ) async {
      _setLogicalViewport(tester, _portraitSize);
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

      await _pumpSplash(
        tester,
        initializer: initializer,
        router: router,
        locale: const Locale('ko'),
      );
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      final l10n = lookupAppLocalizations(const Locale('ko'));
      final dialog = find.byType(AlertDialog);
      Finder inDialog(Finder matching) =>
          find.descendant(of: dialog, matching: matching);
      final actual = <Rect>[
        tester.getRect(inDialog(find.byType(Material)).first),
        tester.getRect(inDialog(find.text(l10n.splashFailureTitle))),
        tester.getRect(inDialog(find.text(l10n.splashFailureMessage))),
        tester.getRect(
          inDialog(
            find.text(
              l10n.splashErrorCodeFingerprint(
                extractSplashErrorCode(const NoInternetConnection()),
              ),
            ),
          ),
        ),
        tester.getRect(
          inDialog(find.widgetWithText(TextButton, l10n.splashContinueOffline)),
        ),
        tester.getRect(
          inDialog(find.widgetWithText(FilledButton, l10n.commonRetry)),
        ),
      ];
      const expected = _portraitFailureDialogRects;
      expect(actual.length, expected.length);
      for (var i = 0; i < expected.length; i++) {
        _expectRectNear(actual[i], expected[i], reason: '#$i');
      }
    });
  });

  // Phase 26 — 킷 틀(`SplashFrame`)이 그리는 값. 기대값은 사용자 소유 상수 ·
  // 밝기 판정 · `AppTheme` 호출에서 계산한다(내 앱 값이 바뀌어도 킷 시험은 그대로).
  group('스플래시 틀 값 (Phase 26 · T-26-FRAME)', () {
    testWidgets('T-26-FRAME-01: 배경 = OS 라이트면 주입한 color · OS 다크면 '
        '주입한 colorDark', (tester) async {
      _expectInjectedColorsOpposite();
      _restoreOsSettingsAfterTest(tester);
      tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;
      await _pumpFrame(
        tester,
        color: _kBrightInjected,
        colorDark: _kDarkInjected,
      );
      expect(_frameBackground(tester), _kBrightInjected, reason: 'OS 라이트');

      tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
      await tester.pump();
      expect(_frameBackground(tester), _kDarkInjected, reason: 'OS 다크');
    });

    testWidgets('T-26-FRAME-02: 주입이 없으면 배경 = OS 라이트 kSplashColor · '
        'OS 다크 kSplashColorDark', (tester) async {
      _restoreOsSettingsAfterTest(tester);
      tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;
      await _pumpFrame(tester);
      expect(_frameBackground(tester), kSplashColor, reason: 'OS 라이트');

      tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
      await tester.pump();
      expect(_frameBackground(tester), kSplashColorDark, reason: 'OS 다크');
    });

    testWidgets('T-26-FRAME-03: 로고 = ExactAssetImage · scale 4 · OS 라이트 '
        'kSplashImage · OS 다크 kSplashImageDark', (tester) async {
      _restoreOsSettingsAfterTest(tester);
      tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;
      await _pumpFrame(tester);
      final lightLogo = _logoProvider(tester);
      expect(lightLogo.assetName, kSplashImage, reason: 'OS 라이트');
      expect(lightLogo.scale, _kImageScale, reason: 'OS 라이트');

      tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
      await tester.pump();
      final darkLogo = _logoProvider(tester);
      expect(darkLogo.assetName, kSplashImageDark, reason: 'OS 다크');
      expect(darkLogo.scale, _kImageScale, reason: 'OS 다크');
    });

    testWidgets('T-26-FRAME-04: 아래 내용 테마 밝기 = 배경 밝기 판정 — 밝은 색 + '
        'OS 다크 → light · 어두운 색 + OS 라이트 → dark', (tester) async {
      _expectInjectedColorsOpposite();
      _restoreOsSettingsAfterTest(tester);
      tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;
      await _pumpFrame(
        tester,
        color: _kDarkInjected,
        colorDark: _kBrightInjected,
      );
      expect(
        _bodyTheme(tester).brightness,
        ThemeData.estimateBrightnessForColor(_kDarkInjected),
        reason: '어두운 색 + OS 라이트',
      );

      tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
      await tester.pump();
      expect(
        _bodyTheme(tester).brightness,
        ThemeData.estimateBrightnessForColor(_kBrightInjected),
        reason: '밝은 색 + OS 다크',
      );
    });

    testWidgets('T-26-FRAME-05: 대비 높임이면 아래 내용 팔레트 = contrastLevel 1.0 · '
        '끄면 0.0 (밝은 배경)', (tester) async {
      final Color highContrast = AppTheme.light(
        seedColor: AppTheme.brandColor,
        contrastLevel: 1,
      ).colorScheme.onSurfaceVariant;
      final Color standardContrast = AppTheme.light(
        seedColor: AppTheme.brandColor,
      ).colorScheme.onSurfaceVariant;
      expect(
        highContrast,
        isNot(standardContrast),
        reason: '두 팔레트가 같으면 이 시험은 아무것도 가리지 못한다',
      );
      expect(
        ThemeData.estimateBrightnessForColor(_kBrightInjected),
        Brightness.light,
      );
      _restoreOsSettingsAfterTest(tester);
      tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;
      await _pumpFrame(tester, color: _kBrightInjected);
      expect(
        _bodyTheme(tester).colorScheme.onSurfaceVariant,
        standardContrast,
        reason: '대비 높임 꺼짐',
      );

      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(highContrast: true);
      await tester.pump();
      expect(
        _bodyTheme(tester).colorScheme.onSurfaceVariant,
        highContrast,
        reason: '대비 높임 켜짐',
      );
    });

    testWidgets('T-26-FRAME-06: 상태 표시줄 아이콘 밝기 — 밝은 배경 dark · '
        '어두운 배경 light', (tester) async {
      _expectInjectedColorsOpposite();
      await _pumpFrame(tester, color: _kBrightInjected);
      expect(
        _statusBarIconBrightness(tester),
        Brightness.dark,
        reason: '밝은 배경',
      );

      await _pumpFrame(tester, color: _kDarkInjected);
      expect(
        _statusBarIconBrightness(tester),
        Brightness.light,
        reason: '어두운 배경',
      );
    });

    for (final size in _logoCenterSizes) {
      testWidgets('T-26-FRAME-07: 로고 중심 = 화면 중심 (${_formatSize(size)} · '
          '디코딩 전후)', (tester) async {
        final png = await _createLogoPng(tester, _kSmallPngPixels);
        await _pumpFrame(tester, size: size, bundle: _PngAssetBundle(png));
        final logo = find.byType(Image);
        final screenCenter = size.center(Offset.zero);
        expect(tester.getSize(logo), Size.zero, reason: '디코딩 전 크기');
        expect(tester.getCenter(logo), screenCenter, reason: '디코딩 전');

        await _decodeLogo(tester);
        expect(
          tester.getSize(logo),
          const Size.square(_kSmallPngPixels / _kImageScale),
          reason: '디코딩 뒤 크기',
        );
        expect(tester.getCenter(logo), screenCenter, reason: '디코딩 뒤');
      });
    }

    testWidgets('T-26-FRAME-08: 로고 크기 = 원본 ÷ 4(1152 → 288 · 512 → 128 · '
        '폭 280 에서도 288) · 아래 내용 위쪽 = 로고 상자 아래쪽', (tester) async {
      final large = await _createLogoPng(tester, _kLargePngPixels);
      final small = await _createLogoPng(tester, _kSmallPngPixels);
      final cases = <(Size, ByteData, int)>[
        (_portraitSize, large, _kLargePngPixels),
        (_portraitSize, small, _kSmallPngPixels),
        (const Size(280, 800), large, _kLargePngPixels),
      ];
      for (final (size, png, pixels) in cases) {
        final label = '${_formatSize(size)} · $pixels px';
        // 이미지 캐시 키가 겹치지 않게 경우마다 새 자산 묶음을 준다.
        await _pumpFrame(tester, size: size, bundle: _PngAssetBundle(png));
        await _decodeLogo(tester);

        final logoRect = tester.getRect(find.byType(Image));
        expect(
          logoRect.size,
          Size.square(pixels / _kImageScale),
          reason: '$label 로고 크기',
        );
        expect(
          tester.getRect(find.text('TEST_BODY running')).top,
          logoRect.bottom,
          reason: '$label 아래 내용 위쪽',
        );
      }
    });

    testWidgets('T-26-FRAME-09: 앱 라이트 + OS 다크 — 배경 = kSplashColorDark · '
        '실패 대화상자 · 복사 알림 막대는 앱 밝기(light)', (tester) async {
      _restoreOsSettingsAfterTest(tester);
      tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
      await _openFailureDialog(tester, themeMode: ThemeMode.light);

      expect(_frameBackground(tester), kSplashColorDark);
      await _expectOverlayBrightness(tester, Brightness.light);
    });

    testWidgets('T-26-FRAME-09: 앱 다크 + OS 라이트 — 배경 = kSplashColor · '
        '실패 대화상자 · 복사 알림 막대는 앱 밝기(dark)', (tester) async {
      _restoreOsSettingsAfterTest(tester);
      tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;
      await _openFailureDialog(tester, themeMode: ThemeMode.dark);

      expect(_frameBackground(tester), kSplashColor);
      await _expectOverlayBrightness(tester, Brightness.dark);
    });

    testWidgets('T-26-FRAME-10: 1152 px 로고를 560x280 가로에서 그려도 예외 0 · '
        '로고 중심 = 화면 중심', (tester) async {
      const size = Size(560, 280);
      final png = await _createLogoPng(tester, _kLargePngPixels);
      await _pumpFrame(tester, size: size, bundle: _PngAssetBundle(png));
      await _decodeLogo(tester);

      expect(tester.takeException(), isNull);
      final logo = find.byType(Image);
      expect(
        tester.getSize(logo),
        const Size.square(_kLargePngPixels / _kImageScale),
      );
      expect(tester.getCenter(logo), size.center(Offset.zero));
    });
  });
}

/// 가로 모드 점검 크기 (logical px).
///
/// - 780x360: SM-S942N 가로 실측 w780dp h360dp.
/// - 560x280: 지원 최소 폭 280dp 의 가로 — 최악.
const _landscapeSizes = <Size>[Size(780, 360), Size(560, 280)];

/// 세로 rect 고정 가드(P) 크기 — 일반 세로 폰.
const _portraitSize = Size(360, 800);

/// 점검 언어 — ko 먼저(R2), en, ja.
const _sweepLocales = <Locale>[Locale('ko'), Locale('en'), Locale('ja')];

/// 테스트 view 를 logical [size] 로 맞춘다 (DPR 1.0 · pump 전에 호출).
///
/// `setSurfaceSize` 는 MediaQuery 를 갱신하지 않으므로 쓰지 않는다
/// (quick 260929-pze 선례).
void _setLogicalViewport(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

/// [size] 를 테스트 이름용 `WxH` 문자열로 만든다.
String _formatSize(Size size) => '${size.width.toInt()}x${size.height.toInt()}';

/// [actual] 의 네 변이 [expected] 와 ±0.5 안인지 단언한다.
void _expectRectNear(Rect actual, Rect expected, {required String reason}) {
  expect(actual.left, closeTo(expected.left, 0.5), reason: '$reason left');
  expect(actual.top, closeTo(expected.top, 0.5), reason: '$reason top');
  expect(actual.right, closeTo(expected.right, 0.5), reason: '$reason right');
  expect(
    actual.bottom,
    closeTo(expected.bottom, 0.5),
    reason: '$reason bottom',
  );
}

/// 360x800 · ko 실패 다이얼로그의 수정 전 rect — 다이얼로그 Material · 제목 ·
/// 본문 · 오류 지문 · 「나중에 로그인」 · 「재시도」 (quick 261003-0fp 가 lib
/// 수정 전 트리에서 실측).
const _portraitFailureDialogRects = <Rect>[
  Rect.fromLTRB(40, 222, 320, 578),
  Rect.fromLTRB(64, 286, 296, 318),
  Rect.fromLTRB(64, 334, 296, 394),
  Rect.fromLTRB(64, 402, 296, 434),
  Rect.fromLTRB(131, 458, 296, 506),
  Rect.fromLTRB(205.7, 506, 296, 554),
];

/// T-26-FRAME 시험이 주입하는 밝은 배경색 — 노랑(배경 밝기 판정 light).
// design-literal: 시험 전용 주입 색 — 내 앱 색과 겹치지 않는 값이다
const Color _kBrightInjected = Color(0xFFF2B134);

/// T-26-FRAME 시험이 주입하는 어두운 배경색 — 짙은 남색(배경 밝기 판정 dark).
// design-literal: 시험 전용 주입 색 — 내 앱 색과 겹치지 않는 값이다
const Color _kDarkInjected = Color(0xFF1A2340);

/// 로고 원본 픽셀을 화면 크기로 바꾸는 나눗수 — 네이티브 스플래시와 같은 ÷ 4.
const double _kImageScale = 4;

/// 시험이 만드는 큰 로고 PNG 한 변 (px) — 화면에는 288.
const int _kLargePngPixels = 1152;

/// 시험이 만드는 작은 로고 PNG 한 변 (px) — 화면에는 128.
const int _kSmallPngPixels = 512;

/// 가로 모드(SB) 시험용 로고 PNG 한 변 (px) — 킷 자리 그림과 같은 128 이라
/// 화면에는 32.
///
/// 내 로고 파일과 떼어 놓아, adopter 가 로고를 바꿔도 SB 가 같은 뜻으로 남는다.
const int _kLandscapeLogoPngPixels = 128;

/// 로고 중심 점검 크기 (logical px) — 세로 폰 · 지원 최소 폭 세로 · 가로 폰.
const _logoCenterSizes = <Size>[Size(360, 780), Size(280, 800), Size(780, 360)];

/// 모든 자산 키에 같은 PNG 바이트를 돌려주는 시험용 자산 묶음이다.
///
/// 로고 원본 크기를 시험이 정한 픽셀로 고정한다. 이미지 캐시 키
/// (`AssetBundleImageKey`)는 묶음 인스턴스까지 비교하므로, 그림마다 새
/// 인스턴스를 주면 앞 시험이 디코딩한 로고를 다시 쓰지 않는다.
class _PngAssetBundle extends CachingAssetBundle {
  _PngAssetBundle(this._png);

  final ByteData _png;

  @override
  Future<ByteData> load(String key) async => _png;
}

/// OS 밝기 · 접근성 시험 값을 시험이 끝나면 되돌리도록 등록한다.
void _restoreOsSettingsAfterTest(WidgetTester tester) {
  addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
  addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
}

/// 주입한 두 색이 서로 다르고 밝기 판정이 서로 반대임을 단언한다 — 같으면
/// 양방향 단언이 아무것도 가리지 못한다.
void _expectInjectedColorsOpposite() {
  expect(_kBrightInjected, isNot(_kDarkInjected));
  expect(
    ThemeData.estimateBrightnessForColor(_kBrightInjected),
    Brightness.light,
  );
  expect(ThemeData.estimateBrightnessForColor(_kDarkInjected), Brightness.dark);
}

/// [SplashFrame] 을 init 없이 [size] 화면에 그린다(첫 프레임만).
///
/// 로고 아래 내용은 킷 시험용 내용([_buildTestBody])이다. [bundle] 을 주면 그
/// 자산 묶음에서 로고를 읽는다. 앱 테마는 OS 밝기를 따른다.
Future<void> _pumpFrame(
  WidgetTester tester, {
  Size size = _portraitSize,
  Color? color,
  Color? colorDark,
  AssetBundle? bundle,
}) async {
  _setLogicalViewport(tester, size);
  final frame = SplashFrame(
    hasFailure: false,
    bodyBuilder: _buildTestBody,
    color: color,
    colorDark: colorDark,
  );
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: bundle == null
          ? frame
          : DefaultAssetBundle(bundle: bundle, child: frame),
    ),
  );
}

/// 틀이 그린 Scaffold 의 배경색을 읽는다.
Color? _frameBackground(WidgetTester tester) => tester
    .widget<Scaffold>(
      find.descendant(
        of: find.byType(SplashFrame),
        matching: find.byType(Scaffold),
      ),
    )
    .backgroundColor;

/// 틀이 그린 로고의 이미지 제공자를 읽는다 — [ExactAssetImage] 가 아니면 실패.
ExactAssetImage _logoProvider(WidgetTester tester) {
  final ImageProvider provider = tester.widget<Image>(find.byType(Image)).image;
  if (provider is! ExactAssetImage) {
    throw TestFailure('로고가 ExactAssetImage 가 아니다: $provider');
  }
  return provider;
}

/// 킷 시험용 로고 아래 내용 자리의 테마를 읽는다.
ThemeData _bodyTheme(WidgetTester tester) =>
    Theme.of(tester.element(find.text('TEST_BODY running')));

/// 틀이 상태 표시줄에 거는 아이콘 밝기를 읽는다.
Brightness? _statusBarIconBrightness(WidgetTester tester) => tester
    .widget<AnnotatedRegion<SystemUiOverlayStyle>>(
      find.descendant(
        of: find.byType(SplashFrame),
        matching: find.byType(AnnotatedRegion<SystemUiOverlayStyle>),
      ),
    )
    .value
    .statusBarIconBrightness;

/// 한 변 [pixels] px 정사각 PNG 바이트를 만든다(`runAsync` 안에서 인코딩).
Future<ByteData> _createLogoPng(WidgetTester tester, int pixels) async {
  final png = await tester.runAsync<ByteData?>(() async {
    final recorder = ui.PictureRecorder();
    final side = pixels.toDouble();
    Canvas(recorder).drawRect(
      Rect.fromLTWH(0, 0, side, side),
      Paint()..color = _kDarkInjected,
    );
    final picture = recorder.endRecording();
    final image = await picture.toImage(pixels, pixels);
    picture.dispose();
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    return data;
  });
  if (png == null) {
    throw TestFailure('$pixels px 로고 PNG 를 만들지 못했다.');
  }
  return png;
}

/// 화면의 로고를 그 위젯 자신의 이미지 제공자로 디코딩하고 한 프레임 그린다.
Future<void> _decodeLogo(WidgetTester tester) async {
  final logo = find.byType(Image);
  final ImageProvider provider = tester.widget<Image>(logo).image;
  final element = tester.element(logo);
  await tester.runAsync(() => precacheImage(provider, element));
  await tester.pump();
}

/// [SplashScreen] 을 앱 [themeMode] 로 열어 초기화 실패 대화상자까지 간다.
///
/// Test 3 의 실패 경로다. 오류 지문 탭(클립보드 복사)이 플랫폼 채널 없이
/// 지나가도록 플랫폼 채널을 막아 둔다.
Future<void> _openFailureDialog(
  WidgetTester tester, {
  required ThemeMode themeMode,
}) async {
  final messenger = tester.binding.defaultBinaryMessenger;
  messenger.setMockMethodCallHandler(
    SystemChannels.platform,
    (call) async => null,
  );
  addTearDown(
    () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
  );

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

  await _pumpSplash(
    tester,
    initializer: initializer,
    router: router,
    themeMode: themeMode,
  );
  await tester.pump(const Duration(milliseconds: 50));
  await tester.pumpAndSettle();
  expect(find.byType(AlertDialog), findsOneWidget);
}

/// 실패 대화상자와 오류 지문 탭 뒤 「복사됨」 SnackBar 의 테마 밝기가
/// [expected](앱 밝기)인지 단언한다.
Future<void> _expectOverlayBrightness(
  WidgetTester tester,
  Brightness expected,
) async {
  final l10n = lookupAppLocalizations(const Locale('en'));
  final dialog = find.byType(AlertDialog);
  expect(
    Theme.of(tester.element(dialog)).brightness,
    expected,
    reason: '실패 대화상자',
  );

  await tester.tap(
    find.descendant(
      of: dialog,
      matching: find.text(
        l10n.splashErrorCodeFingerprint(
          extractSplashErrorCode(const NoInternetConnection()),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  final snackBar = find.byType(SnackBar);
  expect(snackBar, findsOneWidget);
  expect(
    find.descendant(of: snackBar, matching: find.text(l10n.commonCopied)),
    findsOneWidget,
  );
  expect(
    Theme.of(tester.element(snackBar)).brightness,
    expected,
    reason: '복사됨 SnackBar',
  );
}
