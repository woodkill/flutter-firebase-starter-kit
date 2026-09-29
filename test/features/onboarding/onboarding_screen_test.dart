import 'dart:async';

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
import 'package:flutter_starter_kit/core/error/app_exception.dart';
import 'package:flutter_starter_kit/core/error/result.dart';
import 'package:flutter_starter_kit/core/providers/firebase_providers.dart';
import 'package:flutter_starter_kit/core/router/app_routes.dart';
import 'package:flutter_starter_kit/core/theme/app_theme.dart';
import 'package:flutter_starter_kit/features/auth/data/auth_repository.dart';
import 'package:flutter_starter_kit/features/auth/domain/user.dart';
import 'package:flutter_starter_kit/features/auth/presentation/_widgets/primary_cta.dart';
import 'package:flutter_starter_kit/features/onboarding/presentation/_widgets/onboarding_indicator.dart';
import 'package:flutter_starter_kit/features/onboarding/presentation/_widgets/terms_checkbox_group.dart';
import 'package:flutter_starter_kit/features/onboarding/presentation/onboarding_notifier.dart';
import 'package:flutter_starter_kit/features/onboarding/presentation/onboarding_screen.dart';
import 'package:flutter_starter_kit/features/terms/domain/terms_state.dart';
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
  TermsState build() => const TermsState();

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

/// `accept()` 가 항상 실패하는 TermsNotifier (10-REVIEW WR-10 회귀용).
///
/// 실제 실패 원인은 SharedPreferences 쓰기 실패다. UI 관점에서는 "시작하기를
/// 눌렀는데 아무 일도 일어나지 않는" dead-end 였다.
class _FailingAcceptTermsNotifier extends TermsNotifier {
  @override
  TermsState build() => const TermsState();

  @override
  Future<Result<void>> accept({
    required bool service,
    required bool privacy,
    required bool marketing,
  }) async => const Result.failure(ServiceUnavailable());

  @override
  Future<void> reloadForUser({String? uid, bool isAnonymous = false}) async {}
}

/// `accept()` 완료 시점을 테스트가 제어하는 TermsNotifier (WR-08 회귀용).
///
/// 제출 in-flight 구간을 결정적으로 관찰하기 위해 [gate] 가 완료될 때까지
/// `accept()` 가 반환하지 않는다.
class _GatedAcceptTermsNotifier extends TermsNotifier {
  final Completer<void> gate = Completer<void>();

  @override
  TermsState build() => const TermsState();

  @override
  Future<Result<void>> accept({
    required bool service,
    required bool privacy,
    required bool marketing,
  }) async {
    await gate.future;
    return const Result.success(null);
  }

  @override
  Future<void> reloadForUser({String? uid, bool isAnonymous = false}) async {}
}

/// `mirrorToFirestore` 가 항상 실패하는 TermsNotifier (10-REVIEW WR-11 회귀용).
class _FailingMirrorTermsNotifier extends _RecordingTermsNotifier {
  @override
  Future<Result<void>> mirrorToFirestore({
    required String uid,
    bool force = false,
  }) async {
    await super.mirrorToFirestore(uid: uid, force: force);
    return const Result.failure(ServiceUnavailable());
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
  TermsNotifier? termsOverride,
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
            email: null,
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
      expect(termsRec.mirrorCalls, <String>[
        'A-UID',
      ], reason: 'Plan 10-13 must-have — A 의 Firestore 에 재동의 재기록');
      // 2) 해당 호출이 force=true 로 실행되어 Plan 10-12 skip 정책을 우회했는지.
      expect(termsRec.mirrorForceCalls, <bool>[
        true,
      ], reason: 'Plan 10-13 must-have — 사용자 명시적 재동의는 force=true');
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
            email: null,
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

    testWidgets('Test 9 (WR-08): CTA 가 공용 PrimaryCta 를 재사용하고 제출 중 '
        'spinner a11y 라벨을 노출한다', (tester) async {
      // 손복제 CTA 에는 PrimaryCta 의 Semantics(label: commonLoading) 래퍼가
      // 없어 제출 중 스크린 리더가 상태를 읽지 못했다.
      when(
        () => mockRepo.signInAnonymously(),
      ).thenAnswer((_) async => Result<User>.success(_stubUser()));
      final terms = _GatedAcceptTermsNotifier();
      final auth = _MockFirebaseAuth();
      when(() => auth.currentUser).thenReturn(null);

      await _pumpOnboarding(
        tester,
        mockRepo: mockRepo,
        mockAnalytics: mockAnalytics,
        mockCrashlytics: mockCrashlytics,
        auth: auth,
        termsOverride: terms,
      );

      expect(find.byType(PrimaryCta), findsOneWidget);

      await _goToLastSlideAndCheckRequired(tester);

      await tester.tap(find.widgetWithText(FilledButton, 'Get started'));
      // 제출 in-flight 프레임 — spinner + a11y 라벨 노출 구간.
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.bySemanticsLabel('Loading'), findsOneWidget);
      // isLoading 이면 PrimaryCta 가 버튼을 disabled 로 만든다 —
      // 기존 `_isCtaEnabled = !_isSubmitting` 의미 보존.
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton).last).onPressed,
        isNull,
      );

      terms.gate.complete();
      await tester.pumpAndSettle();
    });

    testWidgets('Test 10 (WR-10): 약관 저장 실패 시 SnackBar 로 안내하고 홈으로 '
        '진행하지 않는다', (tester) async {
      await _pumpOnboarding(
        tester,
        mockRepo: mockRepo,
        mockAnalytics: mockAnalytics,
        mockCrashlytics: mockCrashlytics,
        termsOverride: _FailingAcceptTermsNotifier(),
      );

      await _goToLastSlideAndCheckRequired(tester);

      await tester.tap(find.widgetWithText(FilledButton, 'Get started'));
      await tester.pumpAndSettle();

      // errorUnknown (en) — dead-end 대신 사유 안내.
      expect(find.text('An unknown error occurred.'), findsOneWidget);
      expect(find.text('HOME'), findsNothing);
      // CTA 는 원상 복귀되어 재시도 가능하다.
      expect(
        tester.widget<PrimaryCta>(find.byType(PrimaryCta)).isLoading,
        isFalse,
      );
    });

    testWidgets('Test 11 (WR-11): 재동의 mirror 실패를 사용자에게 알리고 홈 진행은 '
        '유지한다', (tester) async {
      final auth = _MockFirebaseAuth();
      final fbUser = _MockFbUser();
      when(() => fbUser.uid).thenReturn('A-UID');
      when(() => fbUser.isAnonymous).thenReturn(false);
      when(() => auth.currentUser).thenReturn(fbUser);
      final terms = _FailingMirrorTermsNotifier();

      await _pumpOnboarding(
        tester,
        mockRepo: mockRepo,
        mockAnalytics: mockAnalytics,
        mockCrashlytics: mockCrashlytics,
        auth: auth,
        termsOverride: terms,
      );

      await _goToLastSlideAndCheckRequired(tester);

      await tester.tap(find.widgetWithText(FilledButton, 'Get started'));
      await tester.pumpAndSettle();

      // settingsLinkFailedTransient (en) — 동의 기록이 조용히 유실되지 않는다.
      expect(
        find.text(
          "Couldn't link due to a network or service error. "
          'Please try again later.',
        ),
        findsOneWidget,
      );
      // 홈 진행은 유지 — 재동의 자체는 로컬에 반영됐다.
      expect(find.text('HOME'), findsOneWidget);
      expect(terms.mirrorCalls, <String>['A-UID']);
    });

    testWidgets('Test 12 (IN-07): 인디케이터 도트 수가 실제 슬라이드 수와 일치한다', (tester) async {
      // 슬라이드 개수가 3곳에 하드코딩되어 있어 한 곳만 바뀌면 도트 수와
      // 실제 페이지가 어긋났다 (정적 분석 미검출).
      await _pumpOnboarding(
        tester,
        mockRepo: mockRepo,
        mockAnalytics: mockAnalytics,
        mockCrashlytics: mockCrashlytics,
      );

      final indicator = tester.widget<OnboardingIndicator>(
        find.byType(OnboardingIndicator),
      );
      final pageView = tester.widget<PageView>(find.byType(PageView));
      expect(
        indicator.count,
        (pageView.childrenDelegate as SliverChildListDelegate).children.length,
      );
    });
  });

  group('OnboardingScreen 가로 모드 (Phase 3 D-09 · quick 260929-pze)', () {
    /// 기존 setUp 의 mock 3종으로 온보딩 화면을 띄운다.
    Future<void> pumpScreen(WidgetTester tester) => _pumpOnboarding(
      tester,
      mockRepo: mockRepo,
      mockAnalytics: mockAnalytics,
      mockCrashlytics: mockCrashlytics,
    );

    // L1 — 가로 두 크기 × 슬라이드 1·2: 오버플로우 없이 세로 스크롤로 본문 도달.
    for (final size in _landscapeSizes) {
      final sizeLabel = '${size.width.toInt()}x${size.height.toInt()}';
      for (final slide in _slideSpecs) {
        final where = '$sizeLabel 슬라이드 ${slide.index + 1}';
        testWidgets('L1 ($sizeLabel): 슬라이드 ${slide.index + 1} — '
            '오버플로우 없이 세로 스크롤로 본문에 도달한다', (tester) async {
          _setLogicalViewport(tester, size);
          await pumpScreen(tester);
          await _goToSlide(tester, slide.index);

          // 제목 · 배지 finder 가 아니라 PageView 중앙에서 드래그한다 —
          // 최소 크기에서는 제목이 뷰포트 밖이라 hit test 가 빗나간다.
          await tester.dragFrom(
            tester.getCenter(find.byType(PageView)),
            Offset(0, -size.height),
          );
          await tester.pumpAndSettle();

          final page = tester.getRect(find.byType(PageView));
          final body = tester.getRect(find.text(slide.body));
          expect(
            body.bottom,
            lessThanOrEqualTo(page.bottom + 0.5),
            reason: '$where: 본문 bottom 이 PageView 아래로 잘림',
          );
          expect(
            body.top,
            greaterThanOrEqualTo(page.top - 0.5),
            reason: '$where: 본문 top 이 PageView 위로 벗어남',
          );
          // 예외 단언은 마지막 — 수정 전 실패 메시지가 geometry 로 갈리도록.
          expect(
            tester.takeException(),
            isNull,
            reason: '$where: 레이아웃 예외(오버플로우) 없음',
          );
        });
      }
    }

    // L2 — 가로 두 크기: 슬라이드 3(unbounded 경로) 무회귀.
    for (final size in _landscapeSizes) {
      final sizeLabel = '${size.width.toInt()}x${size.height.toInt()}';
      testWidgets('L2 ($sizeLabel): 슬라이드 3 — 예외 없이 약관 그룹과 '
          'Get started 버튼이 렌더된다', (tester) async {
        _setLogicalViewport(tester, size);
        await pumpScreen(tester);
        await _goToSlide(tester, 2);

        expect(
          tester.takeException(),
          isNull,
          reason: '$sizeLabel 슬라이드 3: 레이아웃 예외 없음',
        );
        expect(
          find.byType(TermsCheckboxGroup),
          findsOneWidget,
          reason: '$sizeLabel 슬라이드 3: 약관 그룹 1개',
        );
        expect(
          find.widgetWithText(FilledButton, 'Get started'),
          findsOneWidget,
          reason: '$sizeLabel 슬라이드 3: Get started 버튼 1개',
        );
      });
    }

    // P1 — 세로 360x800 × 슬라이드 1·2: 외관 불변 비회귀 가드(수정 전에도 통과).
    for (final slide in _slideSpecs) {
      final sizeLabel =
          '${_portraitSize.width.toInt()}x${_portraitSize.height.toInt()}';
      final where = '$sizeLabel 슬라이드 ${slide.index + 1}';
      testWidgets('P1 ($sizeLabel): 슬라이드 ${slide.index + 1} — 세로 중앙 정렬 · '
          '드래그해도 움직이지 않음 · Semantics 라벨 유지', (tester) async {
        _setLogicalViewport(tester, _portraitSize);
        final semantics = tester.ensureSemantics();
        await pumpScreen(tester);
        await _goToSlide(tester, slide.index);

        final page = tester.getRect(find.byType(PageView));
        // 배지 = 아이콘의 가장 가까운 Container 조상.
        final badge = tester.getRect(
          find
              .ancestor(
                of: find.byIcon(slide.icon),
                matching: find.byType(Container),
              )
              .first,
        );
        final body = tester.getRect(find.text(slide.body));
        final topGap = badge.top - page.top;
        final bottomGap = page.bottom - body.bottom;
        expect(
          (topGap - bottomGap).abs(),
          lessThan(1.0),
          reason: '$where: 위 여백 $topGap · 아래 여백 $bottomGap — 세로 중앙',
        );

        final titleBefore = tester.getRect(find.text(slide.title));
        await tester.dragFrom(
          tester.getCenter(find.byType(PageView)),
          const Offset(0, -300),
        );
        await tester.pumpAndSettle();
        final titleAfter = tester.getRect(find.text(slide.title));
        expect(
          (titleAfter.top - titleBefore.top).abs(),
          lessThanOrEqualTo(0.5),
          reason: '$where: 세로 드래그 뒤 제목 top 불변(스크롤 불필요)',
        );
        expect(
          (titleAfter.left - titleBefore.left).abs(),
          lessThanOrEqualTo(0.5),
          reason: '$where: 세로 드래그 뒤 제목 left 불변',
        );

        final labelPattern = RegExp('^${RegExp.escape(slide.title)}\\. ');
        expect(
          find.bySemanticsLabel(labelPattern),
          findsWidgets,
          reason: '$where: Semantics 라벨이 「제목. 」 으로 시작',
        );
        expect(tester.takeException(), isNull, reason: '$where: 레이아웃 예외 없음');
        semantics.dispose();
      });
    }

    // B1 — 최소 가로 크기: 하단 고정 영역(indicator · CTA) 측정 가드.
    testWidgets('B1 (560x280): 슬라이드 1 — 하단 고정 영역이 화면 안에 있고 '
        'CTA 를 탭할 수 있다', (tester) async {
      final size = _landscapeSizes.last;
      _setLogicalViewport(tester, size);
      await pumpScreen(tester);

      final page = tester.getRect(find.byType(PageView));
      final indicator = tester.getRect(find.byType(OnboardingIndicator));
      final cta = tester.getRect(find.byType(PrimaryCta));
      expect(page.height, greaterThan(0), reason: '560x280: PageView 높이 > 0');
      expect(
        indicator.top,
        greaterThanOrEqualTo(page.bottom),
        reason: '560x280: indicator 가 PageView 아래',
      );
      expect(
        cta.bottom,
        lessThanOrEqualTo(size.height),
        reason: '560x280: CTA 가 화면 아래로 잘리지 않음',
      );
      expect(
        find.byType(PrimaryCta).hitTestable(),
        findsOneWidget,
        reason: '560x280: CTA hit test 가능',
      );
      // 예외 단언은 마지막 — 수정 전에는 슬라이드 1 오버플로우로 여기서만 실패.
      expect(
        tester.takeException(),
        isNull,
        reason: '560x280 슬라이드 1: 레이아웃 예외 없음',
      );
    });
  });
}

/// 가로 모드 테스트가 다루는 슬라이드 1·2 명세 (index · 아이콘 · en 문구).
typedef _SlideSpec = ({int index, IconData icon, String title, String body});

/// 슬라이드 1·2 — harness locale 이 `en` 이라 영어 문구를 쓴다.
const _slideSpecs = <_SlideSpec>[
  (
    index: 0,
    icon: Icons.rocket_launch,
    title: 'Get started quickly',
    body: 'Explore core features without creating an account.',
  ),
  (
    index: 1,
    icon: Icons.security,
    title: 'Kept safe and sound',
    body: 'Sign in when you need more, and your data carries over.',
  ),
];

/// 가로 모드 논리 크기 (dp).
const _landscapeSizes = <Size>[
  Size(800, 360), // 일반 폰 가로
  Size(560, 280), // 지원 최소 폭 280dp 의 가로 — 최악
];

/// 세로 모드 비회귀 기준 논리 크기 (dp).
const _portraitSize = Size(360, 800);

/// 테스트 viewport 를 [size] 논리 크기로 둔다 — `_pumpOnboarding` 보다 먼저 호출.
///
/// DPR 1.0 이라 물리 픽셀 == dp 다.
void _setLogicalViewport(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

/// 「Next」 를 [index] 번 눌러 해당 슬라이드로 이동한다.
Future<void> _goToSlide(WidgetTester tester, int index) async {
  for (var i = 0; i < index; i++) {
    await tester.tap(find.widgetWithText(FilledButton, 'Next'));
    await tester.pumpAndSettle();
  }
}

/// 마지막 슬라이드로 이동해 필수 2개를 체크한다 (테스트 공용 단계).
Future<void> _goToLastSlideAndCheckRequired(WidgetTester tester) async {
  await tester.tap(find.widgetWithText(FilledButton, 'Next'));
  await tester.pumpAndSettle();
  await tester.tap(find.widgetWithText(FilledButton, 'Next'));
  await tester.pumpAndSettle();

  final tiles = find.byType(CheckboxListTile);
  await tester.tap(tiles.at(1)); // service
  await tester.pump();
  await tester.tap(tiles.at(2)); // privacy
  await tester.pump();
}

/// 테스트용 정식 사용자 스텁.
User _stubUser() => User(
  uid: 'anon-uid',
  email: null,
  emailVerified: false,
  createdAt: DateTime.utc(2026, 1, 1),
  providerIds: const <String>[],
);
