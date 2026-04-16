import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter_starter_kit/core/providers/firebase_providers.dart';
import 'package:flutter_starter_kit/core/router/app_routes.dart';
import 'package:flutter_starter_kit/core/router/auth_guard.dart';
import 'package:flutter_starter_kit/features/onboarding/presentation/onboarding_notifier.dart';
import 'package:flutter_starter_kit/features/terms/domain/terms_acceptance.dart';
import 'package:flutter_starter_kit/features/terms/presentation/terms_notifier.dart';

class _MockGoRouterState extends Mock implements GoRouterState {}

class _MockUser extends Mock implements fb.User {}

class _MockFirebaseAuth extends Mock implements fb.FirebaseAuth {}

/// onboarding/terms Provider 의 build() 가 SharedPreferences 비동기 로드를
/// 시도하므로, 테스트에서는 동기 stub Notifier 로 교체하여 race 없이 검증한다.
class _StubOnboardingNotifier extends OnboardingNotifier {
  _StubOnboardingNotifier(this._initial);
  final bool _initial;

  @override
  bool build() => _initial;
}

class _StubTermsNotifier extends TermsNotifier {
  _StubTermsNotifier(this._initial);
  final TermsAcceptance? _initial;

  @override
  TermsAcceptance? build() => _initial;
}

void main() {
  setUpAll(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  late _MockGoRouterState mockState;

  setUp(() {
    mockState = _MockGoRouterState();
  });

  /// 인증 상태 + onboarding/terms 상태를 시뮬레이션하는 컨테이너 빌더.
  ///
  /// [user] 가 null 이면 미인증, non-null 이면 인증 (mock isAnonymous 활용).
  /// [onboardingSeen] 기본 false (첫 실행 가정).
  /// [termsAcceptance] null 이면 약관 미동의.
  ProviderContainer makeContainer({
    required bool isInitialized,
    fb.User? user,
    bool onboardingSeen = false,
    TermsAcceptance? termsAcceptance,
  }) {
    final mockAuth = _MockFirebaseAuth();
    when(() => mockAuth.currentUser).thenReturn(user);
    return ProviderContainer(
      overrides: [
        isFirebaseInitializedProvider.overrideWithValue(isInitialized),
        firebaseAuthProvider.overrideWithValue(mockAuth),
        onboardingProvider.overrideWith(
          () => _StubOnboardingNotifier(onboardingSeen),
        ),
        termsProvider.overrideWith(
          () => _StubTermsNotifier(termsAcceptance),
        ),
      ],
    );
  }

  TermsAcceptance acceptedTerms() => TermsAcceptance(
        version: TermsNotifier.currentVersion,
        service: true,
        privacy: true,
        marketing: false,
        acceptedAt: DateTime.utc(2026, 4, 14),
      );

  fb.User regularUser({
    String uid = 'reg-uid',
    bool emailVerified = true,
  }) {
    final mockUser = _MockUser();
    when(() => mockUser.uid).thenReturn(uid);
    when(() => mockUser.isAnonymous).thenReturn(false);
    when(() => mockUser.emailVerified).thenReturn(emailVerified);
    return mockUser;
  }

  fb.User anonymousUser({String uid = 'anon-uid'}) {
    final mockUser = _MockUser();
    when(() => mockUser.uid).thenReturn(uid);
    when(() => mockUser.isAnonymous).thenReturn(true);
    when(() => mockUser.emailVerified).thenReturn(false);
    return mockUser;
  }

  group('authRedirect (Phase 10 D-14 / BLOCKER #3 / BLOCKER #7 / WARNING #19)',
      () {
    /// authRedirect 는 Ref 를 첫 번째 파라미터로 받는다.
    /// ProviderContainer 에서 Ref 를 얻기 위해 임시 Provider 안에서 호출한다.
    FutureOr<String?> callAuthRedirect(
      ProviderContainer container,
      GoRouterState state,
    ) {
      late FutureOr<String?> result;
      final testProvider = Provider<Object?>((ref) {
        result = authRedirect(ref, state);
        return null;
      });
      container.read(testProvider);
      return result;
    }

    test('Test 1: Firebase 미초기화 시 null', () async {
      final container = makeContainer(isInitialized: false);
      addTearDown(container.dispose);
      when(() => mockState.matchedLocation).thenReturn(AppRoutes.home);

      final result = await callAuthRedirect(container, mockState);
      expect(result, isNull);
    });

    test('Test 2: 미인증 + onboardingSeen=false + home -> /onboarding (D-14)',
        () async {
      final container = makeContainer(isInitialized: true);
      addTearDown(container.dispose);
      when(() => mockState.matchedLocation).thenReturn(AppRoutes.home);

      final result = await callAuthRedirect(container, mockState);
      expect(result, AppRoutes.onboarding);
    });

    test('Test 3: 미인증 + onboardingSeen=true + home -> null (Splash 가 책임)',
        () async {
      final container = makeContainer(
        isInitialized: true,
        onboardingSeen: true,
      );
      addTearDown(container.dispose);
      when(() => mockState.matchedLocation).thenReturn(AppRoutes.home);

      final result = await callAuthRedirect(container, mockState);
      expect(result, isNull);
    });

    test(
      'Test 4: 인증(정식) + emailVerified=false + home -> /verify-email',
      () async {
        final container = makeContainer(
          isInitialized: true,
          user: regularUser(emailVerified: false),
        );
        addTearDown(container.dispose);
        when(() => mockState.matchedLocation).thenReturn(AppRoutes.home);

        final result = await callAuthRedirect(container, mockState);
        expect(result, AppRoutes.verifyEmail);
      },
    );

    test(
      'Test 5: 익명 사용자 + /login -> null (unauth 허용, 승격 가능)',
      () async {
        final container = makeContainer(
          isInitialized: true,
          user: anonymousUser(),
        );
        addTearDown(container.dispose);
        when(() => mockState.matchedLocation).thenReturn(AppRoutes.login);

        final result = await callAuthRedirect(container, mockState);
        expect(result, isNull);
      },
    );

    test(
      'Test 6: 인증 + emailVerified + termsAccepted + /login -> /home',
      () async {
        final container = makeContainer(
          isInitialized: true,
          user: regularUser(),
          termsAcceptance: acceptedTerms(),
        );
        addTearDown(container.dispose);
        when(() => mockState.matchedLocation).thenReturn(AppRoutes.login);

        final result = await callAuthRedirect(container, mockState);
        expect(result, AppRoutes.home);
      },
    );

    test(
      'Test 7 (BLOCKER #3 / #7): 인증 + emailVerified + termsAccepted=null + '
      '/home -> /onboarding (이메일 바이패스 차단)',
      () async {
        final container = makeContainer(
          isInitialized: true,
          user: regularUser(),
          // termsAcceptance: null (약관 미동의 — 이메일 직접 가입 후 Home 시도)
        );
        addTearDown(container.dispose);
        when(() => mockState.matchedLocation).thenReturn(AppRoutes.home);

        final result = await callAuthRedirect(container, mockState);
        expect(
          result,
          AppRoutes.onboarding,
          reason: 'BLOCKER #3 D-14 emailVerified+!termsAccepted -> /onboarding',
        );
      },
    );

    test(
      'Test 8: 완료된 사용자(termsAccepted) + /onboarding -> /home (재진입 차단)',
      () async {
        final container = makeContainer(
          isInitialized: true,
          user: regularUser(),
          termsAcceptance: acceptedTerms(),
        );
        addTearDown(container.dispose);
        when(() => mockState.matchedLocation).thenReturn(AppRoutes.onboarding);

        final result = await callAuthRedirect(container, mockState);
        expect(result, AppRoutes.home);
      },
    );

    test(
      'Test 9 (WARNING #19 / AUTH-13 자동 검증): 인증 + emailVerified + '
      'termsAccepted + matchedLocation=/ -> null (Home 랜딩 완료)',
      () async {
        final container = makeContainer(
          isInitialized: true,
          user: regularUser(),
          termsAcceptance: acceptedTerms(),
        );
        addTearDown(container.dispose);
        when(() => mockState.matchedLocation).thenReturn(AppRoutes.home);

        final result = await callAuthRedirect(container, mockState);
        expect(
          result,
          isNull,
          reason: 'AUTH-13 자동 검증 — 인증 완료 사용자가 Home 랜딩 시 redirect 없음',
        );
      },
    );

    test(
      'Test 10: 미인증 + onboardingSeen=false + /terms/service -> null (공개 경로)',
      () async {
        final container = makeContainer(isInitialized: true);
        addTearDown(container.dispose);
        when(() => mockState.matchedLocation)
            .thenReturn(AppRoutes.termsService);

        final result = await callAuthRedirect(container, mockState);
        expect(result, isNull);
      },
    );

    test(
      'Test 11: 미인증 + onboardingSeen=true + /signup -> null (정식 가입 진입)',
      () async {
        // /signup 은 unauth 화이트리스트 — 미인증이어도 접근 가능.
        final container = makeContainer(
          isInitialized: true,
          onboardingSeen: true,
        );
        addTearDown(container.dispose);
        when(() => mockState.matchedLocation).thenReturn(AppRoutes.signup);

        final result = await callAuthRedirect(container, mockState);
        expect(result, isNull);
      },
    );

    test(
      'Test 12: 익명 사용자 + /verify-email -> /home (정식 사용자 전용 차단)',
      () async {
        final container = makeContainer(
          isInitialized: true,
          user: anonymousUser(),
        );
        addTearDown(container.dispose);
        when(() => mockState.matchedLocation)
            .thenReturn(AppRoutes.verifyEmail);

        final result = await callAuthRedirect(container, mockState);
        expect(result, AppRoutes.home);
      },
    );

    test(
      'Test 13: 미인증 + onboardingSeen=false + /splash -> null (스플래시 진입 허용)',
      () async {
        // 앱 시작 직후 splash 경로에서 redirect 발동을 막는다.
        final container = makeContainer(isInitialized: true);
        addTearDown(container.dispose);
        when(() => mockState.matchedLocation).thenReturn(AppRoutes.splash);

        final result = await callAuthRedirect(container, mockState);
        expect(result, isNull);
      },
    );
  });

  group('authRedirect 분기 (5) — Issue #6 회귀 가드 (Plan 10-09)', () {
    /// authRedirect 는 Ref 를 첫 번째 파라미터로 받는다.
    /// ProviderContainer 에서 Ref 를 얻기 위해 임시 Provider 안에서 호출한다.
    FutureOr<String?> callAuthRedirect(
      ProviderContainer container,
      GoRouterState state,
    ) {
      late FutureOr<String?> result;
      final testProvider = Provider<Object?>((ref) {
        result = authRedirect(ref, state);
        return null;
      });
      container.read(testProvider);
      return result;
    }

    test(
      'Issue #6 Test A: 정식 사용자 + emailVerified=true + termsProvider=null '
      '(reload 후 stale 평가) -> /onboarding (분기 (5) 발동)',
      () async {
        // Issue #6 핵심 회귀 가드: Firestore termsAccepted 가 비어 있는 정식
        // 사용자가 로그인한 직후, authUserObserver 가 reloadForUser 호출 후
        // termsProvider state 가 null 로 평가되면 분기 (5) 가 발동되어야 한다.
        final container = makeContainer(
          isInitialized: true,
          user: regularUser(),
          // termsAcceptance: null (Firestore reload 결과 필드 부재)
        );
        addTearDown(container.dispose);
        when(() => mockState.matchedLocation).thenReturn(AppRoutes.home);

        final result = await callAuthRedirect(container, mockState);
        expect(
          result,
          AppRoutes.onboarding,
          reason:
              'Issue #6 — termsProvider 가 사용자 단위로 평가되어 reload 후 '
              'null 이면 분기 (5) 가 /onboarding 으로 강제 리다이렉트',
        );
      },
    );

    test(
      'Issue #6 Test B: 정식 사용자 + termsProvider=null + '
      'matchedLocation=/onboarding -> null (이미 onboarding 화면 — '
      '공개 경로 허용)',
      () async {
        final container = makeContainer(
          isInitialized: true,
          user: regularUser(),
        );
        addTearDown(container.dispose);
        when(() => mockState.matchedLocation)
            .thenReturn(AppRoutes.onboarding);

        final result = await callAuthRedirect(container, mockState);
        expect(
          result,
          isNull,
          reason: '분기 (5) 가 /onboarding / /terms/* 공개 경로는 허용',
        );
      },
    );

    test(
      'Issue #6 Test C: 정식 사용자 + termsProvider=valid (reload 후 정상 복원) '
      '-> null (false-positive 방어)',
      () async {
        // Issue #6 fix 가 정상 사용자에게도 분기 (5) 를 발동시키지 않는지 확인.
        final container = makeContainer(
          isInitialized: true,
          user: regularUser(),
          termsAcceptance: acceptedTerms(),
        );
        addTearDown(container.dispose);
        when(() => mockState.matchedLocation).thenReturn(AppRoutes.home);

        final result = await callAuthRedirect(container, mockState);
        expect(
          result,
          isNull,
          reason:
              'termsProvider 가 valid TermsAcceptance 면 분기 (5) 미발동 → '
              '분기 (7) null (Home 랜딩 허용)',
        );
      },
    );

    test(
      'Issue #6 Test D: 정식 사용자 + termsProvider=null + '
      'matchedLocation=/terms/service -> null (공개 약관 경로 허용)',
      () async {
        final container = makeContainer(
          isInitialized: true,
          user: regularUser(),
        );
        addTearDown(container.dispose);
        when(() => mockState.matchedLocation)
            .thenReturn(AppRoutes.termsService);

        final result = await callAuthRedirect(container, mockState);
        expect(result, isNull);
      },
    );
  });
}
