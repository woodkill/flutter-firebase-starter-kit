// Phase 10.2 D-D2/D-D3 — _confirmSignOut widget test (I2 invariant 단일 진리원).
//
// Plan 02 land 시 production `signOutAndResetOnboarding` 도입 (8-arg ctor +
// 메서드 신규) 으로 GREEN 전환. 현재 RED (Plan 02 land 전) 는 Wave 0 의
// 의도된 acceptance signal — `MockAuthRepository.signOutAndResetOnboarding()`
// 가 production AuthRepository 타입에 정의되지 않아 compile error 가 정상.
//
// 파일 위치: 기존 평탄 구조 (`test/features/home/`) 따름 — PATTERNS.md 의
// "Path Mismatch Flagged" 결정 (CONTEXT.md 의 `presentation/` 경로는 코드
// 베이스 실재 구조와 mismatch).

import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';

import 'package:flutter_starter_kit/core/analytics/analytics_service.dart';
import 'package:flutter_starter_kit/core/crashlytics/crashlytics_service.dart';
import 'package:flutter_starter_kit/core/providers/firebase_providers.dart';
import 'package:flutter_starter_kit/core/theme/app_theme.dart';
import 'package:flutter_starter_kit/features/auth/data/auth_repository.dart';
import 'package:flutter_starter_kit/features/auth/domain/user.dart';
import 'package:flutter_starter_kit/features/home/presentation/environment_info_screen.dart';
import 'package:flutter_starter_kit/features/onboarding/presentation/onboarding_notifier.dart';
import 'package:flutter_starter_kit/l10n/generated/app_localizations.dart';

/// [AuthRepository] mock.
class _MockAuthRepository extends Mock implements AuthRepository {}

/// [fb.FirebaseAuth] mock.
class _MockFirebaseAuth extends Mock implements fb.FirebaseAuth {}

/// [CrashlyticsService] mock.
class _MockCrashlyticsService extends Mock implements CrashlyticsService {}

/// [AnalyticsService] mock.
class _MockAnalyticsService extends Mock implements AnalyticsService {}

/// [OnboardingNotifier] override 구현.
///
/// `_confirmSignOut` widget test 는 onboarding reset 호출 추적이 직접 목적은
/// 아니지만 (Plan 02 의 production 코드가 callback 으로 호출), Provider scope
/// 에 onboardingProvider override 가 필요하므로 stub Notifier 를 둔다.
///
/// **Phase 10.2 review iter3 IN-02 정정:** `build()` override 시그니처를
/// production 의 `FutureOr<bool> build() async` 와 정확히 일치시킨다.
/// 이전 동기 `bool build() => true` 시그니처는 `bool` 이 `FutureOr<bool>`
/// 의 subtype 이라 Dart 가 허용했으나 (a) async/sync 시그니처 contract
/// drift 발생 + (b) 미래 Dart/Riverpod 의 `analyzer.errors.invalid_override`
/// tightening 이 surface 시 hard error 가능 + (c) `auth_guard_test.dart`
/// `_StubOnboardingNotifier` (line 45-51) 의 async 패턴과 정합 — test
/// suite 전반의 stub 시그니처를 단일화.
class _StubOnboardingNotifier extends OnboardingNotifier {
  @override
  FutureOr<bool> build() async => true; // 정상 진입 상태 (onboarding 완료 후 home 도달 가정)
}

/// 테스트 시나리오 결과 컨테이너.
class _SignOutTestEnv {
  _SignOutTestEnv({
    required this.authRepo,
    required this.crashlytics,
    required this.analytics,
    required this.onboarding,
    required this.router,
  });

  /// AuthRepository mock.
  final _MockAuthRepository authRepo;

  /// Crashlytics mock.
  final _MockCrashlyticsService crashlytics;

  /// Analytics mock.
  final _MockAnalyticsService analytics;

  /// OnboardingNotifier stub.
  final _StubOnboardingNotifier onboarding;

  /// 테스트 라우터 (`/`, `/login`, `/onboarding` stub 3개).
  final GoRouter router;
}

/// [EnvironmentInfoScreen] 을 ProviderScope + GoRouter 하에 pump 하고 모든
/// 의존성 mock 을 주입한 [_SignOutTestEnv] 를 반환한다.
///
/// `pumpDevToolsHarness` 패턴 (Phase 10 dev_tools_test.dart line 70-149)
/// 직접 차용 + `_confirmSignOut` 다이얼로그 확인 path 전용 stub 추가.
/// `tester.view.physicalSize = const Size(800, 8000)` 으로 긴 ListView 가
/// 한 frame 에 렌더되도록 한다.
Future<_SignOutTestEnv> _pumpSignOutHarness(WidgetTester tester) async {
  tester.view.physicalSize = const Size(800, 8000);
  tester.view.devicePixelRatio = 1;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });

  final mockCrash = _MockCrashlyticsService();
  when(
    () => mockCrash.recordError(any(), any(), reason: any(named: 'reason')),
  ).thenAnswer((_) async {});

  final mockAnalytics = _MockAnalyticsService();
  when(
    () => mockAnalytics.logEvent(any(), parameters: any(named: 'parameters')),
  ).thenAnswer((_) async {});

  final mockRepo = _MockAuthRepository();
  // Phase 10.2 D-D3 — Pattern F: stub return type 일관성 (Future<void>).
  // Plan 02 land 전이므로 본 stub 호출이 compile error RED 를 트리거하는 지점.
  when(
    () => mockRepo.signOutAndResetOnboarding(),
  ).thenAnswer((_) async => Future<void>.value());
  // `signOut()` 자체도 stub — verifyNever 의도 표명 + 실제 호출 시 noop.
  when(() => mockRepo.signOut()).thenAnswer((_) async {});

  final stubOnboarding = _StubOnboardingNotifier();

  final mockAuth = _MockFirebaseAuth();
  when(() => mockAuth.currentUser).thenReturn(null);

  // [Rule 1 - Bug fix] _AccountSection (line 769) 은 currentUser==null 시
  // 섹션 자체를 SizedBox.shrink() 로 숨긴다. Plan 01 의 widget test 는
  // `currentUserProvider.overrideWith((_) => null)` 로 두어 "Sign out" 버튼이
  // 렌더되지 않아 `_scrollTo` 가 element 를 찾지 못하는 결함이 있었다.
  // 로그아웃 invariant 검증을 위해 정상 인증된 (익명이 아닌) User 를 주입한다.
  final stubUser = User(
    uid: 'test-uid',
    email: 'test@example.com',
    emailVerified: true,
    displayName: 'Test User',
    photoUrl: null,
    createdAt: DateTime.utc(2026, 4, 14),
    providerIds: const <String>['password'],
  );

  final router = GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(path: '/', builder: (_, _) => const EnvironmentInfoScreen()),
      GoRoute(
        path: '/login',
        builder: (_, _) =>
            const Scaffold(body: Center(child: Text('LoginStub'))),
      ),
      // Phase 10.2 I2 — logout 후 resolveAuthRedirect 분기 (2) 가 /onboarding 으로
      // 자연 redirect 한다 (D-B1). 라우터 stub 으로 도달 가능성 유지.
      GoRoute(
        path: '/onboarding',
        builder: (_, _) =>
            const Scaffold(body: Center(child: Text('OnboardingStub'))),
      ),
    ],
  );

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        isFirebaseInitializedProvider.overrideWithValue(false),
        firebaseAuthProvider.overrideWithValue(mockAuth),
        authStateProvider.overrideWith((ref) => const Stream.empty()),
        currentUserProvider.overrideWith((ref) => stubUser),
        authRepositoryProvider.overrideWithValue(mockRepo),
        crashlyticsServiceProvider.overrideWithValue(mockCrash),
        analyticsServiceProvider.overrideWithValue(mockAnalytics),
        onboardingProvider.overrideWith(() => stubOnboarding),
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

  return _SignOutTestEnv(
    authRepo: mockRepo,
    crashlytics: mockCrash,
    analytics: mockAnalytics,
    onboarding: stubOnboarding,
    router: router,
  );
}

/// 원하는 버튼이 화면에 보이도록 ListView 를 스크롤한다.
///
/// `environment_info_screen_dev_tools_test.dart` line 152-159 `_scrollTo`
/// 패턴 직접 차용 (Pattern E).
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

  group('EnvironmentInfoScreen _confirmSignOut (Phase 10.2 D-D2/D-D3)', () {
    testWidgets(
      '_confirmSignOut: 다이얼로그 OK → signOutAndResetOnboarding 호출 (Phase 10.2 D-D3)',
      (tester) async {
        final env = await _pumpSignOutHarness(tester);
        final l10n = AppLocalizations.of(
          tester.element(find.byType(EnvironmentInfoScreen)),
        );

        // _confirmSignOut 트리거 — 계정 카드의 "Sign out" (authAccountSignOut)
        // 버튼이 보이도록 ListView 스크롤 후 tap.
        await _scrollTo(tester, find.text(l10n.authAccountSignOut));
        await tester.tap(find.text(l10n.authAccountSignOut));
        await tester.pumpAndSettle();

        // 다이얼로그 표시 확인 — [Rule 1 - Bug fix] `authLogoutConfirmTitle`
        // 과 `authAccountSignOut` 의 ARB 값이 동일하게 "Sign out" (en) 이므로
        // title 단독 finder 는 ListView 버튼 + 다이얼로그 confirm/title 의
        // 3 매칭이 잡힌다. 다이얼로그 본문 메시지 (`authLogoutConfirmMessage`)
        // 의 유일성으로 다이얼로그 표시를 검증한다.
        expect(
          find.text(l10n.authLogoutConfirmMessage),
          findsOneWidget,
          reason: '_confirmSignOut 다이얼로그가 본문 메시지와 함께 표시되어야 한다',
        );

        // 다이얼로그 confirm 버튼 tap — `authAccountSignOut` text 가 화면에
        // 두 개 (원래 ListView 버튼 + 다이얼로그 destructive 버튼) 존재하므로
        // `.last` 로 다이얼로그 내부 confirm 버튼을 지정 (Pattern E).
        await tester.tap(find.text(l10n.authAccountSignOut).last);
        await tester.pumpAndSettle();

        // I2 invariant 단일 진리원 — production `_confirmSignOut` 가 반드시
        // `signOutAndResetOnboarding()` 을 호출해야 한다.
        verify(() => env.authRepo.signOutAndResetOnboarding()).called(1);

        // D-A7 호출자 책임 — `signOut()` 단독 호출은 _safeDelete fallback 등
        // 내부 경로 전용. UI logout path 에서는 호출되지 않아야 한다.
        verifyNever(() => env.authRepo.signOut());
      },
    );
  });
}
