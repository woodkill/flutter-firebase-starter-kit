import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_starter_kit/core/auth/auth_strategies_registry.dart';
import 'package:flutter_starter_kit/core/auth/auth_strategy.dart';
import 'package:flutter_starter_kit/core/auth/provider_id.dart';
import 'package:flutter_starter_kit/features/auth/presentation/_widgets/social_button.dart';
import 'package:flutter_starter_kit/core/auth/strategies/apple_auth_strategy.dart';
import 'package:flutter_starter_kit/core/auth/strategies/facebook_auth_strategy.dart';
import 'package:flutter_starter_kit/core/auth/strategies/google_auth_strategy.dart';
import 'package:flutter_starter_kit/core/providers/firebase_providers.dart';
import 'package:flutter_starter_kit/core/router/app_routes.dart';
import 'package:flutter_starter_kit/core/theme/app_theme.dart';
import 'package:flutter_starter_kit/features/auth/data/auth_repository.dart';
import 'package:flutter_starter_kit/features/auth/domain/user.dart';
import 'package:flutter_starter_kit/features/auth/presentation/signup_screen.dart';
import 'package:flutter_starter_kit/l10n/generated/app_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';

import 'package:flutter_starter_kit/core/error/result.dart';

/// [fb.FirebaseAuth] mock.
class _MockFirebaseAuth extends Mock implements fb.FirebaseAuth {}

/// [fb.User] mock.
class _MockFirebaseUser extends Mock implements fb.User {}

/// [AuthRepository] mock.
class _MockAuthRepository extends Mock implements AuthRepository {}

/// 테스트용 GoRouter 기반 앱을 pump 한다.
///
/// Home route 에 도달 시 'HOME_REACHED' 텍스트를 표시하여
/// navigation 결과를 검증할 수 있다.
Widget _buildApp({
  required _MockFirebaseAuth mockAuth,
  required _MockAuthRepository mockRepo,
  String initialLocation = AppRoutes.signup,
}) {
  final router = GoRouter(
    initialLocation: initialLocation,
    routes: [
      GoRoute(
        path: AppRoutes.home,
        builder: (_, _) => const Scaffold(body: Text('HOME_REACHED')),
      ),
      GoRoute(path: AppRoutes.signup, builder: (_, _) => const SignupScreen()),
      GoRoute(
        path: AppRoutes.login,
        builder: (_, _) => const Scaffold(body: Text('LOGIN_SCREEN')),
      ),
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
  late _MockFirebaseAuth mockAuth;
  late _MockAuthRepository mockRepo;
  late _MockFirebaseUser mockUser;

  setUp(() {
    mockAuth = _MockFirebaseAuth();
    mockRepo = _MockAuthRepository();
    mockUser = _MockFirebaseUser();

    when(
      () => mockAuth.authStateChanges(),
    ).thenAnswer((_) => const Stream<fb.User?>.empty());

    // 기본: 다른 소셜 provider stub (취소 반환).
    when(() => mockRepo.signInWithGoogle()).thenAnswer((_) async => null);
    when(() => mockRepo.signInWithApple()).thenAnswer((_) async => null);
    when(() => mockRepo.signInWithFacebook()).thenAnswer((_) async => null);
  });

  group('SignupScreen 소셜 로그인 성공 navigation (Issue #3 safety net)', () {
    testWidgets('Google 로그인 성공 -> Home navigation', (tester) async {
      when(() => mockUser.isAnonymous).thenReturn(false);
      when(() => mockUser.uid).thenReturn('google-uid');

      when(() => mockRepo.signInWithGoogle()).thenAnswer((_) async {
        when(() => mockAuth.currentUser).thenReturn(mockUser);
        return Result<User>.success(
          User(
            uid: 'google-uid',
            email: 'g@example.com',
            emailVerified: true,
            createdAt: DateTime.utc(2026),
          ),
        );
      });

      when(() => mockAuth.currentUser).thenReturn(null);

      await tester.pumpWidget(
        _buildApp(mockAuth: mockAuth, mockRepo: mockRepo),
      );
      await tester.pumpAndSettle();

      expect(find.byType(SignupScreen), findsOneWidget);

      // Phase 13.1 Gap-1 X2 — Google 자상이 wide 자상 baked-in 패턴 (라벨이
      // SVG 내부에 통합) 이라 `find.text('Sign in with Google')` 무효. 대신
      // SocialButton (strategy.providerId == kProviderIdGoogle) 으로 탭.
      await tester.tap(
        find.byWidgetPredicate(
          (w) => w is SocialButton && w.strategy.providerId == kProviderIdGoogle,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('HOME_REACHED'), findsOneWidget);
      expect(find.byType(SignupScreen), findsNothing);
    });

    testWidgets('Apple 로그인 성공 -> Home navigation', (tester) async {
      when(() => mockUser.isAnonymous).thenReturn(false);
      when(() => mockUser.uid).thenReturn('apple-uid');

      when(() => mockRepo.signInWithApple()).thenAnswer((_) async {
        when(() => mockAuth.currentUser).thenReturn(mockUser);
        return Result<User>.success(
          User(
            uid: 'apple-uid',
            email: 'a@privaterelay.appleid.com',
            emailVerified: true,
            createdAt: DateTime.utc(2026),
          ),
        );
      });

      when(() => mockAuth.currentUser).thenReturn(null);

      await tester.pumpWidget(
        _buildApp(mockAuth: mockAuth, mockRepo: mockRepo),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Sign in with Apple'));
      await tester.pumpAndSettle();

      expect(find.text('HOME_REACHED'), findsOneWidget);
      expect(find.byType(SignupScreen), findsNothing);
    });

    testWidgets('Google 로그인 취소 (currentUser anonymous) -> navigation 미호출', (
      tester,
    ) async {
      final anonUser = _MockFirebaseUser();
      when(() => anonUser.isAnonymous).thenReturn(true);
      when(() => anonUser.uid).thenReturn('anon-uid');

      when(() => mockRepo.signInWithGoogle()).thenAnswer((_) async => null);

      when(() => mockAuth.currentUser).thenReturn(anonUser);

      await tester.pumpWidget(
        _buildApp(mockAuth: mockAuth, mockRepo: mockRepo),
      );
      await tester.pumpAndSettle();

      expect(find.byType(SignupScreen), findsOneWidget);

      // Phase 13.1 Gap-1 X2 — Google 자상이 wide 자상 baked-in 패턴 (라벨이
      // SVG 내부에 통합) 이라 `find.text('Sign in with Google')` 무효. 대신
      // SocialButton (strategy.providerId == kProviderIdGoogle) 으로 탭.
      await tester.tap(
        find.byWidgetPredicate(
          (w) => w is SocialButton && w.strategy.providerId == kProviderIdGoogle,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(SignupScreen), findsOneWidget);
      expect(find.text('HOME_REACHED'), findsNothing);
    });
  });
}
