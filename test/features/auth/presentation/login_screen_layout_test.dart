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
import 'package:flutter_starter_kit/features/auth/presentation/_widgets/email_field.dart';
import 'package:flutter_starter_kit/features/auth/presentation/_widgets/or_divider.dart';
import 'package:flutter_starter_kit/features/auth/presentation/_widgets/social_sign_in_section.dart';
import 'package:flutter_starter_kit/features/auth/presentation/login_screen.dart';
import 'package:flutter_starter_kit/l10n/generated/app_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';

class _FakeFirebaseAuth extends Mock implements fb.FirebaseAuth {}

class _FakeAuthRepository extends Mock implements AuthRepository {}

/// [LoginScreen] 을 [GoRouter] + [MaterialApp.router] 로 pump 하여 실제
/// [GoRouterState] 의 쿼리 파라미터를 읽을 수 있도록 한다.
///
/// [initialLocation] 을 `/login?focus=email` 로 주면 WARNING #12 / D-31
/// focus 동작을 검증할 수 있다.
Widget pumpWrapper({String initialLocation = '/login'}) {
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
      GoRoute(path: AppRoutes.login, builder: (_, _) => const LoginScreen()),
    ],
  );

  return ProviderScope(
    overrides: [
      isFirebaseInitializedProvider.overrideWithValue(false),
      firebaseAuthProvider.overrideWithValue(mockAuth),
      authRepositoryProvider.overrideWithValue(mockRepo),
      activeStrategiesProvider(
        const Locale('en'),
      ).overrideWithValue(const <AuthStrategy>[
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
  );
}

void main() {
  group('LoginScreen D-31 레이아웃 회귀 가드 + WARNING #12 focus=email', () {
    testWidgets('D-31: SocialSignInSection 이 EmailField 보다 트리 상단에 위치', (
      tester,
    ) async {
      await tester.pumpWidget(pumpWrapper());
      await tester.pumpAndSettle();

      final socialFinder = find.byType(SocialSignInSection);
      final emailFinder = find.byType(EmailField);
      expect(socialFinder, findsOneWidget);
      expect(emailFinder, findsOneWidget);

      final socialOffset = tester.getTopLeft(socialFinder);
      final emailOffset = tester.getTopLeft(emailFinder);
      expect(
        socialOffset.dy,
        lessThan(emailOffset.dy),
        reason: 'D-31: 소셜 섹션이 이메일 필드보다 상단에 위치해야 함',
      );
    });

    testWidgets(
      'D-31: OrDivider 1개가 SocialSignInSection 내부에 렌더 (기본 showOrDivider=true)',
      (tester) async {
        await tester.pumpWidget(pumpWrapper());
        await tester.pumpAndSettle();
        expect(find.byType(OrDivider), findsOneWidget);
      },
    );

    testWidgets('D-04/D-31: Google/Apple/Facebook 3 소셜 버튼 라벨이 모두 렌더', (
      tester,
    ) async {
      await tester.pumpWidget(pumpWrapper());
      await tester.pumpAndSettle();

      final l10n = AppLocalizations.of(
        tester.element(find.byType(LoginScreen)),
      );
      expect(find.text(l10n.authGoogleSignIn), findsOneWidget);
      expect(find.text(l10n.authAppleSignIn), findsOneWidget);
      expect(find.text(l10n.authFacebookSignIn), findsOneWidget);
    });

    testWidgets(
      'WARNING #12 / D-31: /login?focus=email 로드 시 EmailField 에 자동 포커스',
      (tester) async {
        await tester.pumpWidget(
          pumpWrapper(initialLocation: '/login?focus=email'),
        );
        await tester.pumpAndSettle();

        // EmailField 가 감싸는 TextFormField 내부 TextField 의 focusNode
        // hasFocus 를 검증.
        final textField = tester.widget<TextField>(
          find.descendant(
            of: find.byType(EmailField),
            matching: find.byType(TextField),
          ),
        );
        expect(
          textField.focusNode?.hasFocus,
          isTrue,
          reason: 'D-31: focus=email 쿼리 시 EmailField 에 포커스되어야 함',
        );
      },
    );
  });
}
