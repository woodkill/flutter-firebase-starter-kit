import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_starter_kit/core/analytics/analytics_service.dart';
import 'package:flutter_starter_kit/core/crashlytics/crashlytics_service.dart';
import 'package:flutter_starter_kit/core/error/app_exception.dart';
import 'package:flutter_starter_kit/core/providers/firebase_providers.dart';
import 'package:flutter_starter_kit/core/theme/app_theme.dart';
import 'package:flutter_starter_kit/features/auth/data/auth_repository.dart';
import 'package:flutter_starter_kit/features/home/presentation/environment_info_screen.dart';
import 'package:flutter_starter_kit/features/notifications/data/test_push_client.dart';
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

/// [TestPushClient] mock (Phase 17 plan 18 — 테스트 알림 버튼).
class MockTestPushClient extends Mock implements TestPushClient {}

/// [RecordingOnboardingNotifier] 의 [OnboardingNotifier.reset] 호출 횟수를
/// notifier 밖에서 기록하는 recorder.
///
/// riverpod_lint `avoid_public_notifier_properties` — fake notifier 가 public
/// 카운터를 노출하지 않도록 기록 상태를 이 객체로 분리하고, notifier 는
/// 생성자로 받은 recorder 에만 기록한다.
class OnboardingResetRecorder {
  /// 지금까지의 [OnboardingNotifier.reset] 호출 횟수.
  int resetCallCount = 0;
}

/// [OnboardingNotifier] override 구현 (reset 호출을 [OnboardingResetRecorder]
/// 에 기록).
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
  /// reset 호출을 주입된 recorder 에 기록하는 stub 을 만든다.
  RecordingOnboardingNotifier(this._recorder);

  final OnboardingResetRecorder _recorder;

  @override
  FutureOr<bool> build() async => false;

  @override
  Future<void> reset() async {
    _recorder.resetCallCount += 1;
  }
}

/// 테스트 시나리오 결과 컨테이너.
class DevToolsTestEnv {
  /// 테스트용 mock/fake 의존성을 담는다.
  DevToolsTestEnv({
    required this.crashlytics,
    required this.analytics,
    required this.authRepo,
    required this.onboardingRecorder,
    required this.testPushClient,
  });

  /// Crashlytics mock.
  final MockCrashlyticsService crashlytics;

  /// Analytics mock.
  final MockAnalyticsService analytics;

  /// AuthRepository mock.
  final MockAuthRepository authRepo;

  /// OnboardingNotifier 의 reset 호출 기록.
  final OnboardingResetRecorder onboardingRecorder;

  /// TestPushClient mock — `send()` 는 각 테스트가 stub 한다.
  final MockTestPushClient testPushClient;
}

/// Dev Tools 를 포함한 [EnvironmentInfoScreen] 을 띄운다.
///
/// [locale] 은 앱 언어(기본 en)이고 [width] 는 논리 폭(기본 800)이다.
Future<DevToolsTestEnv> pumpDevToolsHarness(
  WidgetTester tester, {
  Locale locale = const Locale('en'),
  double width = 800,
}) async {
  tester.view.physicalSize = Size(width, 8000);
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
  when(() => mockRepo.signOutAndResetOnboarding()).thenAnswer((_) async {});

  final onboardingRecorder = OnboardingResetRecorder();
  final recordingOnboarding = RecordingOnboardingNotifier(onboardingRecorder);

  final mockAuth = MockFirebaseAuth();
  when(() => mockAuth.currentUser).thenReturn(null);

  final mockTestPush = MockTestPushClient();

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
        testPushClientProvider.overrideWithValue(mockTestPush),
      ],
      child: MaterialApp.router(
        theme: AppTheme.light(),
        locale: locale,
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
    onboardingRecorder: onboardingRecorder,
    testPushClient: mockTestPush,
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

/// Dev Tools 「테스트 알림」 버튼 finder.
Finder _sendButton(AppLocalizations l10n) =>
    find.widgetWithText(OutlinedButton, l10n.devToolsSendTestPush);

/// [outcome] 을 돌려주게 한 뒤 테스트 알림 버튼을 탭하고 SnackBar 문구를
/// 돌려준다 (floating 단언 포함).
Future<String> _tapAndReadSnackBar(
  WidgetTester tester,
  DevToolsTestEnv env,
  TestPushOutcome outcome,
) async {
  when(() => env.testPushClient.send()).thenAnswer((_) async => outcome);
  final l10n = AppLocalizations.of(
    tester.element(find.byType(EnvironmentInfoScreen)),
  );
  final button = _sendButton(l10n);
  await _scrollTo(tester, button);
  await tester.ensureVisible(button);
  await tester.tap(button);
  await tester.pumpAndSettle();
  final snackBar = tester.widget<SnackBar>(find.byType(SnackBar));
  expect(snackBar.behavior, SnackBarBehavior.floating);
  return (snackBar.content as Text).data ?? '';
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
          env.onboardingRecorder.resetCallCount,
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

  group('Phase 17 테스트 알림 (T-17-SEND)', () {
    testWidgets('T-17-SEND-03 Analytics 다음 · 강제 로그아웃 앞 버튼 → 탭 → client 1회 → '
        '성공 SnackBar(floating)', (tester) async {
      final env = await pumpDevToolsHarness(tester, locale: const Locale('ko'));
      when(
        () => env.testPushClient.send(),
      ).thenAnswer((_) async => const TestPushSent(2));
      final l10n = AppLocalizations.of(
        tester.element(find.byType(EnvironmentInfoScreen)),
      );
      final sendButton = find.widgetWithText(
        OutlinedButton,
        l10n.devToolsSendTestPush,
      );
      await _scrollTo(tester, sendButton);

      // 위치: Analytics < 테스트 알림 < 강제 로그아웃 (UI-SPEC (T)).
      final analyticsY = tester
          .getTopLeft(find.text(l10n.devToolsTriggerAnalytics))
          .dy;
      final sendY = tester.getTopLeft(sendButton).dy;
      final signOutY = tester
          .getTopLeft(find.text(l10n.devToolsForceSignOut))
          .dy;
      expect(analyticsY, lessThan(sendY));
      expect(sendY, lessThan(signOutY));

      await tester.ensureVisible(sendButton);
      await tester.tap(sendButton);
      await tester.pumpAndSettle();

      verify(() => env.testPushClient.send()).called(1);
      expect(find.text('기기 2대에 테스트 알림을 보냈어요.'), findsOneWidget);
      final snackBar = tester.widget<SnackBar>(find.byType(SnackBar));
      expect(snackBar.behavior, SnackBarBehavior.floating);
    });

    testWidgets('T-17-SEND-03 Dev Tools 버튼 5개의 트리 순서 — 초기화 · 오류 · '
        'Analytics · 테스트 알림 · 강제 로그아웃 (리뷰 IN-11)', (tester) async {
      await pumpDevToolsHarness(tester, locale: const Locale('ko'));
      final l10n = AppLocalizations.of(
        tester.element(find.byType(EnvironmentInfoScreen)),
      );
      await _scrollTo(tester, find.text(l10n.devToolsForceSignOut));

      final devToolsLabels = <String>{
        l10n.devToolsResetOnboarding,
        l10n.devToolsTriggerError,
        l10n.devToolsTriggerAnalytics,
        l10n.devToolsSendTestPush,
        l10n.devToolsForceSignOut,
      };
      // find.byType 는 위젯 트리 순서(깊이 우선)로 돌려준다.
      final labels = tester
          .widgetList<OutlinedButton>(find.byType(OutlinedButton))
          .map((button) => button.child)
          .whereType<Text>()
          .map((text) => text.data)
          .where(devToolsLabels.contains)
          .toList();
      expect(labels, [
        l10n.devToolsResetOnboarding,
        l10n.devToolsTriggerError,
        l10n.devToolsTriggerAnalytics,
        l10n.devToolsSendTestPush,
        l10n.devToolsForceSignOut,
      ]);
    });

    testWidgets('T-17-SEND-10 기기 없음 · 운영 거부 · App Check 문구 (ko)', (
      tester,
    ) async {
      final env = await pumpDevToolsHarness(tester, locale: const Locale('ko'));
      final l10n = AppLocalizations.of(
        tester.element(find.byType(EnvironmentInfoScreen)),
      );

      expect(
        await _tapAndReadSnackBar(tester, env, const TestPushNoDevice()),
        '알림을 받을 기기가 없어요. 설정에서 알림 받기를 켜 주세요.',
      );
      expect(
        await _tapAndReadSnackBar(tester, env, const TestPushDisabled()),
        '이 환경에서는 테스트 알림을 보낼 수 없어요.',
      );
      expect(
        await _tapAndReadSnackBar(
          tester,
          env,
          const TestPushFailed(AppCheckFailedException()),
        ),
        l10n.errorAppCheckFailed,
      );
    });

    testWidgets('T-17-SEND-10 en 성공 1대 → 단수 문구', (tester) async {
      final env = await pumpDevToolsHarness(tester);

      expect(
        await _tapAndReadSnackBar(tester, env, const TestPushSent(1)),
        'Sent a test notification to 1 device.',
      );
    });

    testWidgets('T-17-SEND-11 요청 중 버튼 비활성 — 두 번째 탭은 무시 · 응답 뒤 다시 활성', (
      tester,
    ) async {
      final env = await pumpDevToolsHarness(tester);
      final pending = Completer<TestPushOutcome>();
      when(() => env.testPushClient.send()).thenAnswer((_) => pending.future);
      final l10n = AppLocalizations.of(
        tester.element(find.byType(EnvironmentInfoScreen)),
      );
      final button = _sendButton(l10n);
      await _scrollTo(tester, button);
      await tester.ensureVisible(button);

      await tester.tap(button);
      await tester.pump();
      expect(tester.widget<OutlinedButton>(button).onPressed, isNull);
      // 라벨은 그대로다 (E7 loading — 라벨 · 크기 불변).
      expect(find.text(l10n.devToolsSendTestPush), findsOneWidget);

      await tester.tap(button, warnIfMissed: false);
      await tester.pump();
      verify(() => env.testPushClient.send()).called(1);

      pending.complete(const TestPushSent(2));
      await tester.pumpAndSettle();
      expect(tester.widget<OutlinedButton>(button).onPressed, isNotNull);
    });

    for (final locale in const [Locale('ko'), Locale('en'), Locale('ja')]) {
      testWidgets(
        'T-17-SEND-12 ${locale.languageCode} 280dp — 버튼 라벨 무절단 · 예외 0',
        (tester) async {
          await pumpDevToolsHarness(tester, locale: locale, width: 280);
          final l10n = AppLocalizations.of(
            tester.element(find.byType(EnvironmentInfoScreen)),
          );
          final button = _sendButton(l10n);
          await _scrollTo(tester, button);

          expect(tester.takeException(), isNull);
          final label = tester.renderObject<RenderParagraph>(
            find.descendant(
              of: button,
              matching: find.text(l10n.devToolsSendTestPush),
            ),
          );
          expect(label.didExceedMaxLines, isFalse);
          expect(tester.getSize(button).width, lessThanOrEqualTo(280));
        },
      );
    }
  });
}
