import 'package:firebase_auth/firebase_auth.dart' as fb;
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
import 'package:flutter_starter_kit/core/providers/firebase_providers.dart';
import 'package:flutter_starter_kit/core/router/app_routes.dart';
import 'package:flutter_starter_kit/core/theme/app_theme.dart';
import 'package:flutter_starter_kit/features/auth/data/auth_repository.dart';
import 'package:flutter_starter_kit/features/auth/domain/user.dart';
import 'package:flutter_starter_kit/features/onboarding/presentation/_widgets/terms_checkbox_group.dart';
import 'package:flutter_starter_kit/features/onboarding/presentation/onboarding_notifier.dart';
import 'package:flutter_starter_kit/features/onboarding/presentation/onboarding_screen.dart';
import 'package:flutter_starter_kit/features/terms/domain/terms_acceptance.dart';
import 'package:flutter_starter_kit/features/terms/presentation/terms_notifier.dart';
import 'package:flutter_starter_kit/l10n/generated/app_localizations.dart';

class _MockAuthRepository extends Mock implements AuthRepository {}

class _MockAnalyticsService extends Mock implements AnalyticsService {
  @override
  bool get isEnabled => false;
}

class _MockCrashlytics extends Mock implements CrashlyticsService {}

class _MockFirebaseAuth extends Mock implements fb.FirebaseAuth {}

class _MockFbUser extends Mock implements fb.User {}

/// `mirrorToFirestore` 호출 인자를 기록하는 테스트용 TermsNotifier (WR-02).
///
/// Plan 10-13 must-have: 재동의 경로에서 `mirrorToFirestore(uid, force: true)`
/// 가 호출되는지를 widget-level 에서 positive assertion 으로 검증하기 위해,
/// `auth_user_observer_test.dart` 의 `_RecordingTermsNotifier` 패턴을 재사용.
/// [mirrorCalls] 는 uid 순서, [mirrorForceCalls] 는 force 인자 순서를 기록한다.
///
/// `accept` / `reloadForUser` 는 본 테스트의 검증 범위 외이므로 최소 stub 으로
/// 성공 반환 / no-op 처리한다. 실제 Firestore 접근은 일으키지 않는다.
class _RecordingTermsNotifier extends TermsNotifier {
  _RecordingTermsNotifier();

  final List<String> mirrorCalls = <String>[];
  final List<bool> mirrorForceCalls = <bool>[];

  @override
  TermsAcceptance? build() => null;

  @override
  Future<Result<void>> accept({
    required bool service,
    required bool privacy,
    required bool marketing,
  }) async => const Result.success(null);

  @override
  Future<Result<void>> mirrorToFirestore({
    required String uid,
    bool force = false,
  }) async {
    mirrorCalls.add(uid);
    mirrorForceCalls.add(force);
    return const Result.success(null);
  }

  @override
  Future<void> reloadForUser({String? uid, bool isAnonymous = false}) async {
    // no-op — 본 테스트의 검증 범위 외.
  }
}

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

/// [OnboardingScreen] 을 pump 한다.
///
/// [isFirebaseInitialized] 는 Phase 1 D-13 분기를 제어한다 (코드 리뷰 CR-02).
/// 기본값 `true` 는 "정상 설정된 앱" 을 뜻하며, 기존 Test 4/6/7 이 전제하던
/// 상태다. `false` 는 stg/prod placeholder / `firebase-configure.sh` 실행 전
/// dev 의 **기본 상태** 로, `_handleCta` 가 `firebaseAuthProvider` 를 읽지
/// 않고 익명 사인인도 건너뛰어야 한다.
Future<void> _pumpOnboarding(
  WidgetTester tester, {
  required _MockAuthRepository mockRepo,
  required _MockAnalyticsService mockAnalytics,
  required _MockCrashlytics mockCrashlytics,
  fb.FirebaseAuth? auth,
  _RecordingTermsNotifier? termsOverride,
  bool isFirebaseInitialized = true,
}) async {
  SharedPreferences.setMockInitialValues({});
  final router = _buildRouter();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        isFirebaseInitializedProvider.overrideWithValue(isFirebaseInitialized),
        authRepositoryProvider.overrideWithValue(mockRepo),
        analyticsServiceProvider.overrideWithValue(mockAnalytics),
        crashlyticsServiceProvider.overrideWithValue(mockCrashlytics),
        if (auth != null) firebaseAuthProvider.overrideWithValue(auth),
        if (termsOverride != null)
          termsProvider.overrideWith(() => termsOverride),
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
      },
    );

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

    testWidgets('Test 3: 마지막 슬라이드 진입 → "Skip" 숨김 + 체크박스 그룹 표시 + '
        'FilledButton "Get started" 표시 (필수 미동의 시 클릭 가능 — 헬퍼 표시 경로)', (
      tester,
    ) async {
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

    testWidgets('Test 4: 필수 2개 체크 후 "Get started" 탭 → '
        'termsNotifier.accept + signInAnonymously + markSeen 호출', (
      tester,
    ) async {
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

      // Issue #9 Plan 10-13: _handleCta 가 firebaseAuthProvider.currentUser 를
      // 읽으므로 테스트 환경에서 실제 FirebaseAuth.instance 접근을 막기 위해
      // currentUser=null (최초 사용자) 을 리턴하는 mock 을 주입한다.
      final mockAuth = _MockFirebaseAuth();
      when(() => mockAuth.currentUser).thenReturn(null);

      await _pumpOnboarding(
        tester,
        mockRepo: mockRepo,
        mockAnalytics: mockAnalytics,
        mockCrashlytics: mockCrashlytics,
        auth: mockAuth,
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

    testWidgets('Test 5: 필수 미동의 상태에서 "Get started" 탭 → '
        'termsRequiredError 헬퍼 텍스트 노출 (초기 hidden, 탭 후 visible)', (
      tester,
    ) async {
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
      expect(find.text('Please agree to all required items.'), findsNothing);

      // 필수 미동의 상태에서 시작하기 탭 → 헬퍼 표시
      // (Plan 10-03 D-31: CTA 는 항상 enabled, _handleCta 가드가 헬퍼 노출)
      await tester.tap(find.widgetWithText(FilledButton, 'Get started'));
      await tester.pump();

      expect(find.text('Please agree to all required items.'), findsOneWidget);

      // 호출자(AuthRepository) 는 호출되지 않아야 한다.
      verifyNever(() => mockRepo.signInAnonymously());
    });

    testWidgets('Test 6 (Issue #9 Plan 10-13 — 재동의 경로): '
        '정식 사용자 A 로그인 상태 + 필수 체크 + "Get started" 탭 → '
        'signInAnonymously 미호출 + analytics 이벤트 호출 + HOME 이동 + '
        'mirrorToFirestore(uid: A-UID, force: true) positive assertion', (
      tester,
    ) async {
      // 정식 사용자 A mock.
      final mockAuth = _MockFirebaseAuth();
      final mockUser = _MockFbUser();
      when(() => mockUser.uid).thenReturn('A-UID');
      when(() => mockUser.isAnonymous).thenReturn(false);
      when(() => mockUser.emailVerified).thenReturn(true);
      when(() => mockAuth.currentUser).thenReturn(mockUser);

      // 재동의 경로에서는 signInAnonymously 가 호출되지 않아야 하지만,
      // defensive stub 만 등록하고 verifyNever 로 호출 자체를 검증한다.

      // WR-02: Plan 10-13 must-have (mirrorToFirestore(force: true)) 의
      // positive assertion 을 위해 _RecordingTermsNotifier 를 주입한다.
      // 실 Firestore 접근을 우회하여 "graceful degradation 경로로 GREEN" 이
      // 아닌 success 경로가 검증되도록 보장한다.
      final termsRec = _RecordingTermsNotifier();

      await _pumpOnboarding(
        tester,
        mockRepo: mockRepo,
        mockAnalytics: mockAnalytics,
        mockCrashlytics: mockCrashlytics,
        auth: mockAuth,
        termsOverride: termsRec,
      );

      // 마지막 슬라이드로 이동.
      await tester.tap(find.widgetWithText(FilledButton, 'Next'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Next'));
      await tester.pumpAndSettle();

      // 필수 2개 체크.
      final tiles = find.byType(CheckboxListTile);
      await tester.tap(tiles.at(1)); // service
      await tester.pump();
      await tester.tap(tiles.at(2)); // privacy
      await tester.pump();

      // CTA 탭.
      await tester.tap(find.widgetWithText(FilledButton, 'Get started'));
      await tester.pumpAndSettle();

      // signInAnonymously 호출되지 않아야 한다 (A 세션 보존).
      verifyNever(() => mockRepo.signInAnonymously());

      // analytics 이벤트는 기존과 동일하게 호출.
      verify(
        () => mockAnalytics.logEvent(
          'onboarding_completed',
          parameters: any(named: 'parameters'),
        ),
      ).called(1);

      // HOME 이동.
      expect(find.text('HOME'), findsOneWidget);

      // WR-02 positive assertion — Plan 10-13 must-have artifact:
      // 1) mirrorToFirestore 가 A 의 uid 로 1회 호출되었는지.
      expect(
        termsRec.mirrorCalls,
        <String>['A-UID'],
        reason: 'Plan 10-13 must-have — A 의 Firestore 에 재동의 재기록',
      );
      // 2) 해당 호출이 force=true 로 실행되어 Plan 10-12 skip 정책을 우회했는지.
      expect(
        termsRec.mirrorForceCalls,
        <bool>[true],
        reason: 'Plan 10-13 must-have — 사용자 명시적 재동의는 force=true',
      );
    });

    testWidgets('Test 7 (Issue #9 Plan 10-13 — 기본 경로 회귀): '
        '최초 사용자 (currentUser=null) + CTA 탭 → '
        'signInAnonymously 호출 유지 + HOME 이동 (Test 4 회귀 가드)', (tester) async {
      final mockAuth = _MockFirebaseAuth();
      when(() => mockAuth.currentUser).thenReturn(null);

      when(() => mockRepo.signInAnonymously()).thenAnswer(
        (_) async => Result.success(
          User(
            uid: 'anon-uid',
            email: '',
            emailVerified: false,
            createdAt: DateTime.utc(2026, 4, 19),
          ),
        ),
      );

      await _pumpOnboarding(
        tester,
        mockRepo: mockRepo,
        mockAnalytics: mockAnalytics,
        mockCrashlytics: mockCrashlytics,
        auth: mockAuth,
      );

      await tester.tap(find.widgetWithText(FilledButton, 'Next'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Next'));
      await tester.pumpAndSettle();

      final tiles = find.byType(CheckboxListTile);
      await tester.tap(tiles.at(1));
      await tester.pump();
      await tester.tap(tiles.at(2));
      await tester.pump();

      await tester.tap(find.widgetWithText(FilledButton, 'Get started'));
      await tester.pumpAndSettle();

      // 기존 경로: signInAnonymously 호출됨.
      verify(() => mockRepo.signInAnonymously()).called(1);
      expect(find.text('HOME'), findsOneWidget);
    });

    testWidgets('Test 8 (CR-02 — D-13): Firebase 미초기화 빌드에서 "Get started" 탭 → '
        'CTA 가 영구 비활성되지 않고 HOME 으로 진행한다 '
        '(firebaseAuthProvider 무접근 + signInAnonymously 미호출)', (tester) async {
      // `firebaseAuthProvider` 를 **의도적으로 override 하지 않는다** —
      // 수정 전 구현은 여기서 실제 FirebaseAuth.instance 에 도달해
      // `[core/no-app]` 을 던졌고, try/finally 가 없어 `_isSubmitting` 이
      // true 로 고정되며 CTA 가 영구 비활성됐다. 수정 후에는
      // isFirebaseInitializedProvider=false 가드로 접근 자체가 일어나지
      // 않아야 한다 (접근이 되살아나면 이 테스트가 예외로 실패한다).
      await _pumpOnboarding(
        tester,
        mockRepo: mockRepo,
        mockAnalytics: mockAnalytics,
        mockCrashlytics: mockCrashlytics,
        isFirebaseInitialized: false,
      );

      await tester.tap(find.widgetWithText(FilledButton, 'Next'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Next'));
      await tester.pumpAndSettle();

      final tiles = find.byType(CheckboxListTile);
      await tester.tap(tiles.at(1)); // service
      await tester.pump();
      await tester.tap(tiles.at(2)); // privacy
      await tester.pump();

      await tester.tap(find.widgetWithText(FilledButton, 'Get started'));
      await tester.pumpAndSettle();

      // 익명 사인인은 Firebase 없이는 불가능하므로 호출되지 않는다.
      verifyNever(() => mockRepo.signInAnonymously());

      // 약관 동의 + markSeen 은 SharedPreferences 전용이므로 그대로 기록된다.
      final prefs = await SharedPreferences.getInstance();
      expect(
        prefs.getInt('onboarding.seen_version'),
        OnboardingNotifier.currentVersion,
        reason: 'D-13: Firebase 없이도 온보딩 완료가 로컬에 기록되어야 한다',
      );

      // 첫 화면이 막히지 않는다 — 홈 도달이 CR-02 의 핵심 회귀 기준이다.
      expect(find.text('HOME'), findsOneWidget);
    });
  });
}
