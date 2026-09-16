// 재인증 표시 전달 회귀 고정 — R_EXTRA_G3_REAUTH_LOGIN_BOUNCE (quick 260916-p8d).
//
// 재인증 표시로 연 로그인 · 이메일 로그인 화면이 이메일 로그인 · 가입 ·
// 비밀번호 찾기로 이어 push 할 때 표시를 전달하는지 검증한다. 표시가 끊기면
// 실제 앱에서 다음 화면이 guard 분기 (6) 에서 홈으로 튕긴다.
//
// guard 는 일부러 연결하지 않는다 — 순수 전달 동작만 본다. guard 쪽 push 평가는
// test/core/router/auth_guard_test.dart 의 GoRouter push end-to-end group 이
// 담당한다. 단언은 guard 와 같은 판정 함수(AppRoutes.hasReauthMarker)로 해서
// 전달부 산출물과 guard 입력이 같은 계약임을 잇는다.

import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_starter_kit/core/auth/auth_strategies_registry.dart';
import 'package:flutter_starter_kit/core/auth/auth_strategy.dart';
import 'package:flutter_starter_kit/core/auth/strategies/apple_auth_strategy.dart';
import 'package:flutter_starter_kit/core/auth/strategies/facebook_auth_strategy.dart';
import 'package:flutter_starter_kit/core/auth/strategies/google_auth_strategy.dart';
import 'package:flutter_starter_kit/core/providers/firebase_providers.dart';
import 'package:flutter_starter_kit/core/router/app_routes.dart';
import 'package:flutter_starter_kit/core/theme/app_theme.dart';
import 'package:flutter_starter_kit/features/auth/data/auth_repository.dart';
import 'package:flutter_starter_kit/features/auth/presentation/_widgets/email_auth_cta.dart';
import 'package:flutter_starter_kit/features/auth/presentation/email_login_screen.dart';
import 'package:flutter_starter_kit/features/auth/presentation/login_screen.dart';
import 'package:flutter_starter_kit/l10n/generated/app_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';

class _FakeFirebaseAuth extends Mock implements fb.FirebaseAuth {}

class _FakeAuthRepository extends Mock implements AuthRepository {}

const _homeText = 'HOME_STUB';
const _signupText = 'SIGNUP_STUB';
const _forgotPasswordText = 'FORGOT_PASSWORD_STUB';

/// 로그인 흐름 화면을 guard 없는 GoRouter 로 pump 하고 router 를 반환한다.
Future<GoRouter> _pumpRouter(WidgetTester tester) async {
  final mockAuth = _FakeFirebaseAuth();
  when(
    () => mockAuth.authStateChanges(),
  ).thenAnswer((_) => const Stream<fb.User?>.empty());
  when(() => mockAuth.currentUser).thenReturn(null);

  final mockRepo = _FakeAuthRepository();
  when(() => mockRepo.signInWithGoogle()).thenAnswer((_) async => null);
  when(() => mockRepo.signInWithApple()).thenAnswer((_) async => null);
  when(() => mockRepo.signInWithFacebook()).thenAnswer((_) async => null);

  final router = GoRouter(
    initialLocation: AppRoutes.home,
    routes: [
      GoRoute(
        path: AppRoutes.home,
        builder: (context, state) => const Scaffold(body: Text(_homeText)),
      ),
      GoRoute(
        path: AppRoutes.login,
        builder: (context, state) => const LoginScreen(),
      ),
      GoRoute(
        path: AppRoutes.emailLogin,
        builder: (context, state) => const EmailLoginScreen(),
      ),
      GoRoute(
        path: AppRoutes.signup,
        builder: (context, state) => const Scaffold(body: Text(_signupText)),
      ),
      GoRoute(
        path: AppRoutes.forgotPassword,
        builder: (context, state) =>
            const Scaffold(body: Text(_forgotPasswordText)),
      ),
    ],
  );
  addTearDown(router.dispose);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        isFirebaseInitializedProvider.overrideWithValue(false),
        firebaseAuthProvider.overrideWithValue(mockAuth),
        authRepositoryProvider.overrideWithValue(mockRepo),
        activeStrategiesProvider.overrideWithValue(const <AuthStrategy>[
          GoogleAuthStrategy(),
          AppleAuthStrategy(),
          FacebookAuthStrategy(),
        ]),
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
  return router;
}

/// [location] 을 push 하고 화면이 안정될 때까지 기다린다.
Future<void> _pushLocation(
  WidgetTester tester,
  GoRouter router,
  String location,
) async {
  unawaited(router.push(location));
  await tester.pumpAndSettle();
}

/// 대상 버튼을 viewport 안으로 스크롤한 뒤 탭한다.
///
/// form-tail 버튼은 기본 800x600 viewport 밖이면 hit-test 가 조용히 실패하므로
/// ensureVisible 를 생략하지 않는다.
Future<void> _tapVisible(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

/// 현재 화면 위의 en 번역을 얻는다.
AppLocalizations _readL10n(WidgetTester tester, Type screenType) =>
    AppLocalizations.of(tester.element(find.byType(screenType)));

void main() {
  group('로그인 흐름 재인증 표시 전달 — R_EXTRA_G3_REAUTH_LOGIN_BOUNCE (260916-p8d)', () {
    testWidgets('F-1: 재인증 로그인 화면의 EmailAuthCta 는 표시를 전달한다', (tester) async {
      final router = await _pumpRouter(tester);
      await _pushLocation(
        tester,
        router,
        AppRoutes.buildReauthLocation(AppRoutes.login),
      );

      await _tapVisible(tester, find.byType(EmailAuthCta));

      expect(
        router.state.matchedLocation,
        AppRoutes.emailLogin,
        reason: 'EmailAuthCta 는 이메일 로그인 화면으로 push 한다',
      );
      expect(
        AppRoutes.hasReauthMarker(router.state.uri),
        isTrue,
        reason: '재인증 흐름의 다음 화면도 guard 분기 (6) 예외를 받아야 한다',
      );
    });

    testWidgets('F-2: 재인증 로그인 화면의 가입 링크는 표시를 전달한다', (tester) async {
      final router = await _pumpRouter(tester);
      await _pushLocation(
        tester,
        router,
        AppRoutes.buildReauthLocation(AppRoutes.login),
      );
      final l10n = _readL10n(tester, LoginScreen);

      await _tapVisible(
        tester,
        find.widgetWithText(TextButton, l10n.authLoginNoAccount),
      );

      expect(
        router.state.matchedLocation,
        AppRoutes.signup,
        reason: '가입 링크는 가입 화면으로 push 한다',
      );
      expect(
        AppRoutes.hasReauthMarker(router.state.uri),
        isTrue,
        reason: '재인증 흐름의 다음 화면도 guard 분기 (6) 예외를 받아야 한다',
      );
    });

    testWidgets('F-3: 재인증 이메일 로그인 화면의 비밀번호 찾기는 표시를 전달한다', (tester) async {
      final router = await _pumpRouter(tester);
      await _pushLocation(
        tester,
        router,
        AppRoutes.buildReauthLocation(AppRoutes.emailLogin),
      );
      final l10n = _readL10n(tester, EmailLoginScreen);

      await _tapVisible(
        tester,
        find.widgetWithText(TextButton, l10n.authLoginForgotPassword),
      );

      expect(
        router.state.matchedLocation,
        AppRoutes.forgotPassword,
        reason: '비밀번호 찾기 링크는 비밀번호 찾기 화면으로 push 한다',
      );
      expect(
        AppRoutes.hasReauthMarker(router.state.uri),
        isTrue,
        reason: '재인증 흐름의 다음 화면도 guard 분기 (6) 예외를 받아야 한다',
      );
    });

    testWidgets('F-4: 재인증 이메일 로그인 화면의 가입 링크는 표시를 전달한다', (tester) async {
      final router = await _pumpRouter(tester);
      await _pushLocation(
        tester,
        router,
        AppRoutes.buildReauthLocation(AppRoutes.emailLogin),
      );
      final l10n = _readL10n(tester, EmailLoginScreen);

      await _tapVisible(
        tester,
        find.widgetWithText(TextButton, l10n.authLoginNoAccount),
      );

      expect(
        router.state.matchedLocation,
        AppRoutes.signup,
        reason: '가입 링크는 가입 화면으로 push 한다',
      );
      expect(
        AppRoutes.hasReauthMarker(router.state.uri),
        isTrue,
        reason: '재인증 흐름의 다음 화면도 guard 분기 (6) 예외를 받아야 한다',
      );
    });

    testWidgets('F-5 (대조군): 표시 없는 진입은 다음 push 경로를 바꾸지 않는다', (tester) async {
      final router = await _pumpRouter(tester);
      await _pushLocation(tester, router, AppRoutes.login);

      await _tapVisible(tester, find.byType(EmailAuthCta));

      expect(
        router.state.matchedLocation,
        AppRoutes.emailLogin,
        reason: 'EmailAuthCta 는 이메일 로그인 화면으로 push 한다',
      );
      expect(
        AppRoutes.hasReauthMarker(router.state.uri),
        isFalse,
        reason: '표시 없는 진입(익명 · 미인증)에 표시를 새로 만들면 안 된다',
      );
      expect(
        router.state.uri.hasQuery,
        isFalse,
        reason: '표시 없는 진입은 경로를 그대로 push 해야 한다',
      );

      final plainRouter = await _pumpRouter(tester);
      await _pushLocation(tester, plainRouter, AppRoutes.emailLogin);
      final l10n = _readL10n(tester, EmailLoginScreen);

      await _tapVisible(
        tester,
        find.widgetWithText(TextButton, l10n.authLoginForgotPassword),
      );

      expect(
        plainRouter.state.matchedLocation,
        AppRoutes.forgotPassword,
        reason: '비밀번호 찾기 링크는 비밀번호 찾기 화면으로 push 한다',
      );
      expect(
        AppRoutes.hasReauthMarker(plainRouter.state.uri),
        isFalse,
        reason: '표시 없는 진입(익명 · 미인증)에 표시를 새로 만들면 안 된다',
      );
    });

    testWidgets('F-6 (연쇄): 로그인 → 이메일 로그인 → 비밀번호 찾기까지 표시가 유지된다', (tester) async {
      final router = await _pumpRouter(tester);
      await _pushLocation(
        tester,
        router,
        AppRoutes.buildReauthLocation(AppRoutes.login),
      );

      await _tapVisible(tester, find.byType(EmailAuthCta));
      final l10n = _readL10n(tester, EmailLoginScreen);
      await _tapVisible(
        tester,
        find.widgetWithText(TextButton, l10n.authLoginForgotPassword),
      );

      expect(
        router.state.matchedLocation,
        AppRoutes.forgotPassword,
        reason: '연쇄 push 의 마지막 화면은 비밀번호 찾기다',
      );
      expect(
        AppRoutes.hasReauthMarker(router.state.uri),
        isTrue,
        reason: '두 번 이어 push 해도 표시가 끊기지 않아야 한다',
      );
    });
  });
}
