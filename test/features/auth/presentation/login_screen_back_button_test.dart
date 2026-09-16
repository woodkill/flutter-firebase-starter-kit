// 로그인 화면 뒤로가기 표시 규칙 회귀 고정 — R_EXTRA_G2_IOS_BACK_NAV (quick 260916-woe).
//
// push 로 연 로그인 화면(홈 데모 · 탈퇴/계정 연결 재인증)은 AppBar 에 표준
// 뒤로가기를 표시하고, go 루트 교체 · 딥링크 · 최초 진입은 표시하지 않는다.
// 판정은 LoginScreen 이 showBackButton true 를 넘기고 AppBar 자동 판정에
// 위임한다 (D-01). 실제 GoRouter 로 진입별 동작을 실측한다.
// guard 는 일부러 연결하지 않는다 — 표시 규칙만 본다. 재인증 표시 guard 동작은
// test/core/router/auth_guard_test.dart 가 담당한다.

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
import 'package:flutter_starter_kit/features/auth/presentation/_widgets/auth_scaffold.dart';
import 'package:flutter_starter_kit/features/auth/presentation/login_screen.dart';
import 'package:flutter_starter_kit/l10n/generated/app_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';

class _FakeFirebaseAuth extends Mock implements fb.FirebaseAuth {}

class _FakeAuthRepository extends Mock implements AuthRepository {}

const _homeText = 'HOME_STUB';
const _settingsText = 'SETTINGS_STUB';

/// 홈 · 설정 stub 과 로그인 화면을 guard 없는 GoRouter 로 pump 하고 router 를 반환한다.
Future<GoRouter> _pumpRouter(
  WidgetTester tester, {
  String initialLocation = AppRoutes.home,
}) async {
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
    initialLocation: initialLocation,
    routes: [
      GoRoute(
        path: AppRoutes.home,
        builder: (context, state) => const Scaffold(body: Text(_homeText)),
      ),
      GoRoute(
        path: AppRoutes.settings,
        builder: (context, state) => const Scaffold(body: Text(_settingsText)),
      ),
      GoRoute(
        path: AppRoutes.login,
        builder: (context, state) => const LoginScreen(),
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

/// [location] 으로 go(루트 교체)하고 화면이 안정될 때까지 기다린다.
Future<void> _goLocation(
  WidgetTester tester,
  GoRouter router,
  String location,
) async {
  router.go(location);
  await tester.pumpAndSettle();
}

void main() {
  group('로그인 화면 뒤로가기 표시 규칙 — R_EXTRA_G2_IOS_BACK_NAV (260916-woe)', () {
    testWidgets('B-1 홈에서 push 로 연 로그인 화면은 BackButton 을 표시하고 탭하면 홈으로 돌아간다', (
      tester,
    ) async {
      final router = await _pumpRouter(tester);
      await _pushLocation(tester, router, AppRoutes.login);

      expect(
        find.byType(LoginScreen),
        findsOneWidget,
        reason: 'push 뒤 로그인 화면이 떠 있어야 한다',
      );
      expect(
        find.byType(BackButton),
        findsOneWidget,
        reason: 'push 진입은 AppBar 가 표준 ← 뒤로가기를 그려야 한다 (D-01 · D-02)',
      );
      expect(
        find.byType(CloseButton),
        findsNothing,
        reason: 'fullscreenDialog ✕ 닫기 버튼이 아니어야 한다 (D-02)',
      );

      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();

      expect(
        find.text(_homeText),
        findsOneWidget,
        reason: '뒤로가기 탭 뒤 직전 화면(홈)이 보여야 한다',
      );
      expect(
        router.state.matchedLocation,
        AppRoutes.home,
        reason: '뒤로가기 탭 뒤 현재 위치가 홈이어야 한다',
      );
      expect(
        find.byType(LoginScreen),
        findsNothing,
        reason: '뒤로가기 탭 뒤 로그인 화면은 닫혀야 한다',
      );
    });

    testWidgets(
      'B-2 설정에서 재인증 push 로 연 로그인 화면은 BackButton 탭 시 설정으로 안내 없이 돌아간다',
      (tester) async {
        final router = await _pumpRouter(tester);
        await _pushLocation(tester, router, AppRoutes.settings);
        await _pushLocation(
          tester,
          router,
          AppRoutes.buildReauthLocation(AppRoutes.login),
        );

        expect(
          AppRoutes.hasReauthMarker(router.state.uri),
          isTrue,
          reason: 'harness 건전성 — 재인증 표시가 붙은 /login 으로 진입해야 한다',
        );
        expect(
          find.byType(BackButton),
          findsOneWidget,
          reason: '재인증 push 진입도 AppBar 가 뒤로가기를 그려야 한다 (D-01)',
        );

        await tester.tap(find.byType(BackButton));
        await tester.pumpAndSettle();

        expect(
          find.text(_settingsText),
          findsOneWidget,
          reason: '뒤로가기 탭 뒤 직전 화면(설정)이 보여야 한다',
        );
        expect(
          router.state.matchedLocation,
          AppRoutes.settings,
          reason: '뒤로가기 탭 뒤 현재 위치가 설정이어야 한다',
        );
        expect(
          find.byType(SnackBar),
          findsNothing,
          reason: '재인증 취소 복귀는 별도 안내 없이 표준 pop 이어야 한다 (D-04)',
        );
      },
    );

    testWidgets('B-3 go 루트 교체로 연 로그인 화면은 뒤로가기를 표시하지 않는다', (tester) async {
      final router = await _pumpRouter(tester);
      await _goLocation(tester, router, AppRoutes.login);

      expect(
        find.byType(LoginScreen),
        findsOneWidget,
        reason: 'go 뒤 로그인 화면이 떠 있어야 한다',
      );
      expect(
        find.byType(BackButton),
        findsNothing,
        reason: 'go 루트 교체는 돌아갈 곳이 없어 뒤로가기가 없어야 한다',
      );
      expect(
        find.byType(CloseButton),
        findsNothing,
        reason: 'go 루트 교체에 닫기 버튼도 없어야 한다',
      );
    });

    testWidgets('B-4 딥링크 · 최초 진입 로그인 화면은 뒤로가기를 표시하지 않는다', (tester) async {
      await _pumpRouter(tester, initialLocation: AppRoutes.login);

      expect(
        find.byType(LoginScreen),
        findsOneWidget,
        reason: '최초 진입 위치가 로그인 화면이어야 한다',
      );
      expect(
        find.byType(BackButton),
        findsNothing,
        reason: '딥링크 · 최초 진입은 돌아갈 곳이 없어 뒤로가기가 없어야 한다',
      );
    });

    testWidgets('B-5 플래그가 켜져 있어도 go 진입에서는 AppBar 가 뒤로가기를 숨긴다', (tester) async {
      final router = await _pumpRouter(tester);
      await _goLocation(tester, router, AppRoutes.login);

      expect(
        tester.widget<AuthScaffold>(find.byType(AuthScaffold)).showBackButton,
        isTrue,
        reason:
            'LoginScreen 은 showBackButton true 를 넘기고 판정을 AppBar 에 맡긴다 (D-01)',
      );
      expect(
        find.byType(BackButton),
        findsNothing,
        reason: '플래그가 켜져 있어도 go 진입에서는 AppBar 가 스스로 숨겨야 한다 (D-01)',
      );
    });
  });
}
