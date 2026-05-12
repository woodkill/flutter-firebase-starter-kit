import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_starter_kit/core/analytics/analytics_service.dart';
import 'package:flutter_starter_kit/core/crashlytics/crashlytics_service.dart';
import 'package:flutter_starter_kit/core/providers/firebase_providers.dart';
import 'package:flutter_starter_kit/core/theme/app_theme.dart';
import 'package:flutter_starter_kit/features/auth/data/auth_repository.dart';
import 'package:flutter_starter_kit/features/home/presentation/environment_info_screen.dart';
import 'package:flutter_starter_kit/features/onboarding/presentation/onboarding_notifier.dart';
import 'package:flutter_starter_kit/l10n/generated/app_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';

/// [AuthRepository] mock.
class MockAuthRepository extends Mock implements AuthRepository {}

/// [fb.FirebaseAuth] mock.
class MockFirebaseAuth extends Mock implements fb.FirebaseAuth {}

/// [CrashlyticsService] mock.
class MockCrashlyticsService extends Mock implements CrashlyticsService {}

/// [AnalyticsService] mock.
class MockAnalyticsService extends Mock implements AnalyticsService {}

/// [OnboardingNotifier] override 구현 (reset 호출 추적용).
///
/// Plan 03 수정판: `reset()` 은 public 메서드 (no `@visibleForTesting`).
///
/// **Phase 10.2 review iter3 IN-02 정정:** `build()` override 시그니처를
/// production 의 `FutureOr<bool> build() async` 와 정확히 일치시킨다.
/// 이전 동기 `bool build() => false` 시그니처는 `bool` 이 `FutureOr<bool>`
/// 의 subtype 이라 Dart 가 허용했으나 (a) async/sync 시그니처 contract
/// drift 발생 + (b) 미래 Dart/Riverpod 의 `analyzer.errors.invalid_override`
/// tightening 이 surface 시 hard error 가능 + (c) `auth_guard_test.dart`
/// `_StubOnboardingNotifier` (line 45-51) 의 async 패턴과 정합 — test
/// suite 전반의 stub 시그니처를 단일화.
class RecordingOnboardingNotifier extends OnboardingNotifier {
  /// 지금까지의 [reset] 호출 횟수.
  int resetCallCount = 0;

  @override
  FutureOr<bool> build() async => false;

  @override
  Future<void> reset() async {
    resetCallCount += 1;
  }
}

/// 테스트 시나리오 결과 컨테이너.
class DevToolsTestEnv {
  /// 테스트용 mock/fake 의존성을 담는다.
  DevToolsTestEnv({
    required this.crashlytics,
    required this.analytics,
    required this.authRepo,
    required this.onboarding,
  });

  /// Crashlytics mock.
  final MockCrashlyticsService crashlytics;

  /// Analytics mock.
  final MockAnalyticsService analytics;

  /// AuthRepository mock.
  final MockAuthRepository authRepo;

  /// OnboardingNotifier 의 reset 호출 추적 가능 구현.
  final RecordingOnboardingNotifier onboarding;
}

Future<DevToolsTestEnv> pumpDevToolsHarness(WidgetTester tester) async {
  tester.view.physicalSize = const Size(800, 8000);
  tester.view.devicePixelRatio = 1;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });

  final mockCrash = MockCrashlyticsService();
  when(
    () => mockCrash.recordError(any(), any(), reason: any(named: 'reason')),
  ).thenAnswer((_) async {});

  final mockAnalytics = MockAnalyticsService();
  when(
    () => mockAnalytics.logEvent(any(), parameters: any(named: 'parameters')),
  ).thenAnswer((_) async {});

  final mockRepo = MockAuthRepository();
  // Phase 10.2 D-A1/A4: 구 D-20 로그아웃 메서드(signOut → signInAnonymously
  // cascade)는 폐기되고 signOutAndResetOnboarding (Future<void>) 으로 교체됨.
  // production 와 Dev Tools 의 단일 진리원.
  when(
    () => mockRepo.signOutAndResetOnboarding(),
  ).thenAnswer((_) async {});

  final recordingOnboarding = RecordingOnboardingNotifier();

  final mockAuth = MockFirebaseAuth();
  when(() => mockAuth.currentUser).thenReturn(null);

  final router = GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(path: '/', builder: (_, _) => const EnvironmentInfoScreen()),
      GoRoute(
        path: '/login',
        builder: (_, _) =>
            const Scaffold(body: Center(child: Text('LoginStub'))),
      ),
    ],
  );

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        isFirebaseInitializedProvider.overrideWithValue(false),
        firebaseAuthProvider.overrideWithValue(mockAuth),
        authStateProvider.overrideWith((ref) => const Stream.empty()),
        currentUserProvider.overrideWith((ref) => null),
        authRepositoryProvider.overrideWithValue(mockRepo),
        crashlyticsServiceProvider.overrideWithValue(mockCrash),
        analyticsServiceProvider.overrideWithValue(mockAnalytics),
        onboardingProvider.overrideWith(() => recordingOnboarding),
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

  return DevToolsTestEnv(
    crashlytics: mockCrash,
    analytics: mockAnalytics,
    authRepo: mockRepo,
    onboarding: recordingOnboarding,
  );
}

/// 원하는 버튼이 화면에 보이도록 ListView 를 스크롤한다.
Future<void> _scrollTo(WidgetTester tester, Finder target) async {
  await tester.scrollUntilVisible(
    target,
    300,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() {
    registerFallbackValue(StackTrace.empty);
    registerFallbackValue(Exception('fallback'));
    registerFallbackValue(<String, Object>{});
  });

  group('EnvironmentInfoScreen Dev Tools (Phase 10 D-32, D-33)', () {
    testWidgets('kDebugMode=true 환경에서 devToolsSectionTitle 섹션 렌더', (
      tester,
    ) async {
      await pumpDevToolsHarness(tester);

      // 테스트 환경은 기본 kDebugMode=true.
      expect(kDebugMode, isTrue);

      final l10n = AppLocalizations.of(
        tester.element(find.byType(EnvironmentInfoScreen)),
      );
      // ListView 스크롤 후 섹션 타이틀 노출 확인.
      await _scrollTo(tester, find.text(l10n.devToolsSectionTitle));
      expect(find.text(l10n.devToolsSectionTitle), findsOneWidget);
    });

    testWidgets('Dev Tools 섹션에 4 버튼 (reset/error/analytics/forceSignOut) 렌더', (
      tester,
    ) async {
      await pumpDevToolsHarness(tester);
      final l10n = AppLocalizations.of(
        tester.element(find.byType(EnvironmentInfoScreen)),
      );

      await _scrollTo(tester, find.text(l10n.devToolsForceSignOut));

      expect(find.text(l10n.devToolsResetOnboarding), findsOneWidget);
      expect(find.text(l10n.devToolsTriggerError), findsOneWidget);
      expect(find.text(l10n.devToolsTriggerAnalytics), findsOneWidget);
      expect(find.text(l10n.devToolsForceSignOut), findsOneWidget);
    });

    testWidgets(
      'Reset onboarding 탭 → onboardingProvider.reset 호출 (Plan 03 public API)',
      (tester) async {
        final env = await pumpDevToolsHarness(tester);
        final l10n = AppLocalizations.of(
          tester.element(find.byType(EnvironmentInfoScreen)),
        );
        await _scrollTo(tester, find.text(l10n.devToolsResetOnboarding));
        await tester.tap(find.text(l10n.devToolsResetOnboarding));
        await tester.pumpAndSettle();
        expect(
          env.onboarding.resetCallCount,
          1,
          reason: 'Dev Tools Reset Onboarding 은 public reset() 을 직접 호출',
        );
      },
    );

    testWidgets('Trigger error 탭 → CrashlyticsService.recordError 호출', (
      tester,
    ) async {
      final env = await pumpDevToolsHarness(tester);
      final l10n = AppLocalizations.of(
        tester.element(find.byType(EnvironmentInfoScreen)),
      );
      await _scrollTo(tester, find.text(l10n.devToolsTriggerError));
      await tester.tap(find.text(l10n.devToolsTriggerError));
      await tester.pumpAndSettle();
      verify(
        () =>
            env.crashlytics.recordError(any(), any(), reason: 'dev_tools_test'),
      ).called(1);
    });

    testWidgets(
      'Force sign out 탭 → AuthRepository.signOutAndResetOnboarding 호출 '
      '(Phase 10.2 D-A4)',
      (tester) async {
        final env = await pumpDevToolsHarness(tester);
        final l10n = AppLocalizations.of(
          tester.element(find.byType(EnvironmentInfoScreen)),
        );
        await _scrollTo(tester, find.text(l10n.devToolsForceSignOut));
        await tester.tap(find.text(l10n.devToolsForceSignOut));
        await tester.pumpAndSettle();
        verify(() => env.authRepo.signOutAndResetOnboarding()).called(1);
      },
    );
  });
}
