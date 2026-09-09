import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_starter_kit/core/auth/auth_strategies_registry.dart';
import 'package:flutter_starter_kit/core/auth/auth_strategy.dart';
import 'package:flutter_starter_kit/core/auth/strategies/apple_auth_strategy.dart';
import 'package:flutter_starter_kit/core/auth/strategies/facebook_auth_strategy.dart';
import 'package:flutter_starter_kit/core/auth/strategies/google_auth_strategy.dart';
import 'package:flutter_starter_kit/core/error/app_exception.dart';
import 'package:flutter_starter_kit/core/error/result.dart';
import 'package:flutter_starter_kit/core/providers/firebase_providers.dart';
import 'package:flutter_starter_kit/core/router/app_routes.dart';
import 'package:flutter_starter_kit/core/theme/app_theme.dart';
import 'package:flutter_starter_kit/features/auth/data/auth_repository.dart';
import 'package:flutter_starter_kit/features/auth/domain/user.dart';
import 'package:flutter_starter_kit/features/auth/presentation/login_screen.dart';
import 'package:flutter_starter_kit/l10n/generated/app_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';

/// [fb.FirebaseAuth] mock.
class _MockFirebaseAuth extends Mock implements fb.FirebaseAuth {}

/// [fb.User] mock.
class _MockFirebaseUser extends Mock implements fb.User {}

/// [AuthRepository] mock.
class _MockAuthRepository extends Mock implements AuthRepository {}

/// 테스트용 GoRouter 기반 앱을 pump 한다.
///
/// Home route 도달 시 'HOME_REACHED' 텍스트를 표시하여 navigation 결과를
/// 검증할 수 있다.
Widget _buildApp({
  required _MockFirebaseAuth mockAuth,
  required _MockAuthRepository mockRepo,
  String initialLocation = AppRoutes.login,
}) {
  final router = GoRouter(
    initialLocation: initialLocation,
    routes: [
      GoRoute(
        path: AppRoutes.home,
        builder: (_, _) => const Scaffold(body: Text('HOME_REACHED')),
      ),
      GoRoute(path: AppRoutes.login, builder: (_, _) => const LoginScreen()),
    ],
  );

  return ProviderScope(
    overrides: [
      isFirebaseInitializedProvider.overrideWithValue(false),
      firebaseAuthProvider.overrideWithValue(mockAuth),
      authRepositoryProvider.overrideWithValue(mockRepo),
      activeStrategiesProvider(const Locale('en')).overrideWithValue(
        const <AuthStrategy>[
          GoogleAuthStrategy(),
          AppleAuthStrategy(),
          FacebookAuthStrategy(),
        ],
      ),
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

/// 정상 입력 폼 진입 (Sign in 버튼 활성화 + 제출 가능).
Future<void> _enterValidCredentials(WidgetTester tester) async {
  await tester.enterText(find.byType(TextFormField).first, 'user@example.com');
  await tester.enterText(find.byType(TextFormField).at(1), 'password123');
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

  group('LoginScreen 이메일 로그인 성공 navigation (Issue #5 safety net)', () {
    testWidgets('Test 1: 성공 + emailVerified=true -> Home navigation', (
      tester,
    ) async {
      // 정식 사용자 + emailVerified=true mock.
      when(() => mockUser.isAnonymous).thenReturn(false);
      when(() => mockUser.emailVerified).thenReturn(true);
      when(() => mockUser.uid).thenReturn('verified-user-uid');

      // signInWithEmail 호출 시 성공 반환 + currentUser 설정.
      when(
        () => mockRepo.signInWithEmail(
          email: any(named: 'email'),
          password: any(named: 'password'),
        ),
      ).thenAnswer((_) async {
        when(() => mockAuth.currentUser).thenReturn(mockUser);
        return Result<User>.success(
          User(
            uid: 'verified-user-uid',
            email: 'user@example.com',
            emailVerified: true,
            createdAt: DateTime.utc(2026),
          ),
        );
      });

      // 초기: currentUser = null (미인증).
      when(() => mockAuth.currentUser).thenReturn(null);

      await tester.pumpWidget(
        _buildApp(mockAuth: mockAuth, mockRepo: mockRepo),
      );
      await tester.pumpAndSettle();

      expect(find.byType(LoginScreen), findsOneWidget);
      await _enterValidCredentials(tester);

      // 이메일 Sign in 버튼 (FilledButton 텍스트 'Sign in').
      await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
      await tester.pumpAndSettle();

      expect(find.text('HOME_REACHED'), findsOneWidget);
      expect(find.byType(LoginScreen), findsNothing);
    });

    testWidgets(
      'Test 2: emailVerified=false (신규 가입 직후 race) -> navigation 미발동',
      (tester) async {
        // emailVerified=false (race) — safety net 가드 발동 → /login 머무름.
        when(() => mockUser.isAnonymous).thenReturn(false);
        when(() => mockUser.emailVerified).thenReturn(false);
        when(() => mockUser.uid).thenReturn('unverified-uid');

        when(
          () => mockRepo.signInWithEmail(
            email: any(named: 'email'),
            password: any(named: 'password'),
          ),
        ).thenAnswer((_) async {
          when(() => mockAuth.currentUser).thenReturn(mockUser);
          return Result<User>.success(
            User(
              uid: 'unverified-uid',
              email: 'user@example.com',
              emailVerified: false,
              createdAt: DateTime.utc(2026),
            ),
          );
        });

        when(() => mockAuth.currentUser).thenReturn(null);

        await tester.pumpWidget(
          _buildApp(mockAuth: mockAuth, mockRepo: mockRepo),
        );
        await tester.pumpAndSettle();

        expect(find.byType(LoginScreen), findsOneWidget);
        await _enterValidCredentials(tester);

        await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
        await tester.pumpAndSettle();

        // safety net 가드 발동 → Home 미진입.
        expect(find.byType(LoginScreen), findsOneWidget);
        expect(find.text('HOME_REACHED'), findsNothing);
      },
    );

    testWidgets('Test 3: currentUser.isAnonymous=true (defense-in-depth) -> '
        'navigation 미발동', (tester) async {
      when(() => mockUser.isAnonymous).thenReturn(true);
      when(() => mockUser.emailVerified).thenReturn(false);
      when(() => mockUser.uid).thenReturn('anon-uid');

      when(
        () => mockRepo.signInWithEmail(
          email: any(named: 'email'),
          password: any(named: 'password'),
        ),
      ).thenAnswer((_) async {
        when(() => mockAuth.currentUser).thenReturn(mockUser);
        return Result<User>.success(
          User(
            uid: 'anon-uid',
            email: 'user@example.com',
            emailVerified: false,
            createdAt: DateTime.utc(2026),
          ),
        );
      });

      when(() => mockAuth.currentUser).thenReturn(null);

      await tester.pumpWidget(
        _buildApp(mockAuth: mockAuth, mockRepo: mockRepo),
      );
      await tester.pumpAndSettle();

      await _enterValidCredentials(tester);
      await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
      await tester.pumpAndSettle();

      expect(find.byType(LoginScreen), findsOneWidget);
      expect(find.text('HOME_REACHED'), findsNothing);
    });

    testWidgets('Test 4: 성공 후 currentUser == null -> navigation 미발동', (
      tester,
    ) async {
      when(
        () => mockRepo.signInWithEmail(
          email: any(named: 'email'),
          password: any(named: 'password'),
        ),
      ).thenAnswer((_) async {
        // currentUser 가 갱신되지 않은 상태로 성공 반환.
        when(() => mockAuth.currentUser).thenReturn(null);
        return Result<User>.success(
          User(
            uid: 'no-current',
            email: 'user@example.com',
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

      await _enterValidCredentials(tester);
      await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
      await tester.pumpAndSettle();

      expect(find.byType(LoginScreen), findsOneWidget);
      expect(find.text('HOME_REACHED'), findsNothing);
    });

    testWidgets('Test 5 (회귀): AsyncError -> 기존 _emailError 배너 표시 + '
        'navigation 미발동', (tester) async {
      when(
        () => mockRepo.signInWithEmail(
          email: any(named: 'email'),
          password: any(named: 'password'),
        ),
      ).thenAnswer(
        (_) async => const Result<User>.failure(InvalidCredentials()),
      );

      when(() => mockAuth.currentUser).thenReturn(null);

      await tester.pumpWidget(
        _buildApp(mockAuth: mockAuth, mockRepo: mockRepo),
      );
      await tester.pumpAndSettle();

      await _enterValidCredentials(tester);
      await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
      await tester.pumpAndSettle();

      // 기존 에러 처리 회귀: InvalidCredentials 배너가 표시되어야 한다.
      expect(find.text('Invalid email or password.'), findsOneWidget);
      // navigation 미발동.
      expect(find.byType(LoginScreen), findsOneWidget);
      expect(find.text('HOME_REACHED'), findsNothing);
    });

    testWidgets('Test 6 (취소 시 머무름): signInWithEmail 결과 null-like 시나리오 — '
        '실제로는 이메일은 null 반환 경로가 없으나 currentUser=null 가드가 '
        '취소 동등 보호', (tester) async {
      // Note: LoginNotifier.submit 은 null 반환 경로가 없다. 본 테스트는
      // Test 4 와 동일 가드를 다른 시나리오 (Repository 가 success 이지만
      // Firebase 측 currentUser 미갱신) 로 한 번 더 검증한다.
      final completer = Completer<Result<User>>();
      when(
        () => mockRepo.signInWithEmail(
          email: any(named: 'email'),
          password: any(named: 'password'),
        ),
      ).thenAnswer((_) => completer.future);

      when(() => mockAuth.currentUser).thenReturn(null);

      await tester.pumpWidget(
        _buildApp(mockAuth: mockAuth, mockRepo: mockRepo),
      );
      await tester.pumpAndSettle();

      await _enterValidCredentials(tester);
      await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
      await tester.pump();

      // 로딩 중 — 미완료 상태에서 머무름.
      expect(find.byType(LoginScreen), findsOneWidget);
      expect(find.text('HOME_REACHED'), findsNothing);

      // 완료 (currentUser 는 여전히 null — Firebase 측 미갱신 시뮬).
      completer.complete(
        Result<User>.success(
          User(
            uid: 'race-uid',
            email: 'user@example.com',
            emailVerified: true,
            createdAt: DateTime.utc(2026),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // safety net 의 currentUser==null 가드로 navigation 차단.
      expect(find.byType(LoginScreen), findsOneWidget);
      expect(find.text('HOME_REACHED'), findsNothing);
    });
  });
}
