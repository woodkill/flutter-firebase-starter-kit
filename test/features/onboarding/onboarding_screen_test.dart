import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter_starter_kit/core/analytics/analytics_service.dart';
import 'package:flutter_starter_kit/core/crashlytics/crashlytics_service.dart';
import 'package:flutter_starter_kit/core/error/result.dart';
import 'package:flutter_starter_kit/core/router/app_routes.dart';
import 'package:flutter_starter_kit/core/theme/app_theme.dart';
import 'package:flutter_starter_kit/features/auth/data/auth_repository.dart';
import 'package:flutter_starter_kit/features/auth/domain/user.dart';
import 'package:flutter_starter_kit/features/onboarding/presentation/_widgets/terms_checkbox_group.dart';
import 'package:flutter_starter_kit/features/onboarding/presentation/onboarding_notifier.dart';
import 'package:flutter_starter_kit/features/onboarding/presentation/onboarding_screen.dart';
import 'package:flutter_starter_kit/l10n/generated/app_localizations.dart';

class _MockAuthRepository extends Mock implements AuthRepository {}

class _MockAnalyticsService extends Mock implements AnalyticsService {
  @override
  bool get isEnabled => false;
}

class _MockCrashlytics extends Mock implements CrashlyticsService {}

GoRouter _buildRouter() {
  return GoRouter(
    initialLocation: AppRoutes.onboarding,
    routes: [
      GoRoute(
        path: AppRoutes.onboarding,
        name: AppRoutes.onboardingName,
        builder: (_, _) => const OnboardingScreen(),
      ),
      GoRoute(
        path: AppRoutes.home,
        name: AppRoutes.homeName,
        builder: (_, _) => const Scaffold(body: Text('HOME')),
      ),
      GoRoute(
        path: AppRoutes.termsService,
        name: AppRoutes.termsServiceName,
        builder: (_, _) => const Scaffold(body: Text('SERVICE_DETAIL')),
      ),
      GoRoute(
        path: AppRoutes.termsPrivacy,
        name: AppRoutes.termsPrivacyName,
        builder: (_, _) => const Scaffold(body: Text('PRIVACY_DETAIL')),
      ),
    ],
  );
}

Future<void> _pumpOnboarding(
  WidgetTester tester, {
  required _MockAuthRepository mockRepo,
  required _MockAnalyticsService mockAnalytics,
  required _MockCrashlytics mockCrashlytics,
}) async {
  SharedPreferences.setMockInitialValues({});
  final router = _buildRouter();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authRepositoryProvider.overrideWithValue(mockRepo),
        analyticsServiceProvider.overrideWithValue(mockAnalytics),
        crashlyticsServiceProvider.overrideWithValue(mockCrashlytics),
      ],
      child: MaterialApp.router(
        theme: AppTheme.light(),
        locale: const Locale('en'),
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        routerConfig: router,
      ),
    ),
  );
  await tester.pump();
}

void main() {
  setUpAll(() {
    registerFallbackValue(StackTrace.empty);
  });

  late _MockAuthRepository mockRepo;
  late _MockAnalyticsService mockAnalytics;
  late _MockCrashlytics mockCrashlytics;

  setUp(() {
    mockRepo = _MockAuthRepository();
    mockAnalytics = _MockAnalyticsService();
    mockCrashlytics = _MockCrashlytics();

    when(
      () => mockCrashlytics.recordError(
        any<Object>(),
        any<StackTrace?>(),
        reason: any(named: 'reason'),
        fatal: any(named: 'fatal'),
      ),
    ).thenAnswer((_) async {});

    when(
      () => mockAnalytics.logEvent(any(), parameters: any(named: 'parameters')),
    ).thenAnswer((_) async {});
  });

  group('OnboardingScreen', () {
    testWidgets(
        'Test 1: 첫 진입 시 1번 슬라이드 + AppBar "Skip" + FilledButton "Next" 렌더',
        (tester) async {
      await _pumpOnboarding(
        tester,
        mockRepo: mockRepo,
        mockAnalytics: mockAnalytics,
        mockCrashlytics: mockCrashlytics,
      );

      expect(find.text('Get started quickly'), findsOneWidget);
      expect(find.text('Skip'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Next'), findsOneWidget);
    });

    testWidgets('Test 2: "Next" 탭 → 2번 슬라이드로 전환', (tester) async {
      await _pumpOnboarding(
        tester,
        mockRepo: mockRepo,
        mockAnalytics: mockAnalytics,
        mockCrashlytics: mockCrashlytics,
      );

      await tester.tap(find.widgetWithText(FilledButton, 'Next'));
      await tester.pumpAndSettle();

      expect(find.text('Kept safe and sound'), findsOneWidget);
    });

    testWidgets(
        'Test 3: 마지막 슬라이드 진입 → "Skip" 숨김 + 체크박스 그룹 표시 + '
        'FilledButton "Get started" 표시 (필수 미동의 시 클릭 가능 — 헬퍼 표시 경로)',
        (tester) async {
      await _pumpOnboarding(
        tester,
        mockRepo: mockRepo,
        mockAnalytics: mockAnalytics,
        mockCrashlytics: mockCrashlytics,
      );

      // Next 두 번 → 마지막 슬라이드
      await tester.tap(find.widgetWithText(FilledButton, 'Next'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Next'));
      await tester.pumpAndSettle();

      // Skip 숨김
      expect(find.text('Skip'), findsNothing);

      // 체크박스 그룹
      expect(find.byType(TermsCheckboxGroup), findsOneWidget);

      // 시작하기 (Get started) — 클릭 가능 (필수 미동의 시 헬퍼 표시 경로 활성)
      final cta = find.widgetWithText(FilledButton, 'Get started');
      expect(cta, findsOneWidget);
      final button = tester.widget<FilledButton>(cta);
      expect(button.onPressed, isNotNull);
    });

    testWidgets(
        'Test 4: 필수 2개 체크 후 "Get started" 탭 → '
        'termsNotifier.accept + signInAnonymously + markSeen 호출',
        (tester) async {
      // signInAnonymously stub: 성공 User 반환
      when(() => mockRepo.signInAnonymously()).thenAnswer(
        (_) async => Result.success(
          User(
            uid: 'anon-uid',
            email: '',
            emailVerified: false,
            createdAt: DateTime.utc(2026, 4, 14),
          ),
        ),
      );

      await _pumpOnboarding(
        tester,
        mockRepo: mockRepo,
        mockAnalytics: mockAnalytics,
        mockCrashlytics: mockCrashlytics,
      );

      // 마지막 슬라이드로 이동
      await tester.tap(find.widgetWithText(FilledButton, 'Next'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Next'));
      await tester.pumpAndSettle();

      // 필수 2개 체크
      // index 0=AcceptAll, 1=Service, 2=Privacy, 3=Marketing
      // 마지막 슬라이드는 SingleChildScrollView 안 → CheckboxListTile finder OK
      final tiles = find.byType(CheckboxListTile);
      await tester.tap(tiles.at(1)); // service
      await tester.pump();
      await tester.tap(tiles.at(2)); // privacy
      await tester.pump();

      // 시작하기 활성화 확인
      final cta = find.widgetWithText(FilledButton, 'Get started');
      final button = tester.widget<FilledButton>(cta);
      expect(button.onPressed, isNotNull);

      // 탭
      await tester.tap(cta);
      await tester.pumpAndSettle();

      // signInAnonymously 호출 확인
      verify(() => mockRepo.signInAnonymously()).called(1);
      // analytics 이벤트 발송 확인
      verify(
        () => mockAnalytics.logEvent(
          'onboarding_completed',
          parameters: any(named: 'parameters'),
        ),
      ).called(1);

      // SharedPreferences 에 onboarding.seen_version=1 저장 확인
      // (markSeen 호출 효과)
      final prefs = await SharedPreferences.getInstance();
      expect(
        prefs.getInt('onboarding.seen_version'),
        OnboardingNotifier.currentVersion,
      );

      // 이동 확인
      expect(find.text('HOME'), findsOneWidget);
    });

    testWidgets(
        'Test 5: 필수 미동의 상태에서 "Get started" 탭 → '
        'termsRequiredError 헬퍼 텍스트 노출 (초기 hidden, 탭 후 visible)',
        (tester) async {
      await _pumpOnboarding(
        tester,
        mockRepo: mockRepo,
        mockAnalytics: mockAnalytics,
        mockCrashlytics: mockCrashlytics,
      );

      // 마지막 슬라이드로 이동
      await tester.tap(find.widgetWithText(FilledButton, 'Next'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Next'));
      await tester.pumpAndSettle();

      // 초기에는 termsRequiredError 미표시
      expect(
        find.text('Please agree to all required items.'),
        findsNothing,
      );

      // 필수 미동의 상태에서 시작하기 탭 → 헬퍼 표시
      // (Plan 10-03 D-31: CTA 는 항상 enabled, _handleCta 가드가 헬퍼 노출)
      await tester.tap(find.widgetWithText(FilledButton, 'Get started'));
      await tester.pump();

      expect(
        find.text('Please agree to all required items.'),
        findsOneWidget,
      );

      // 호출자(AuthRepository) 는 호출되지 않아야 한다.
      verifyNever(() => mockRepo.signInAnonymously());
    });
  });
}
