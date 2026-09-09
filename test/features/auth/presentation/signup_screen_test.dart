import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:flutter_starter_kit/core/auth/auth_strategies_registry.dart';
import 'package:flutter_starter_kit/core/auth/auth_strategy.dart';
import 'package:flutter_starter_kit/core/auth/strategies/apple_auth_strategy.dart';
import 'package:flutter_starter_kit/core/auth/strategies/facebook_auth_strategy.dart';
import 'package:flutter_starter_kit/core/auth/strategies/google_auth_strategy.dart';
import 'package:flutter_starter_kit/core/error/app_exception.dart';
import 'package:flutter_starter_kit/core/error/result.dart';
import 'package:flutter_starter_kit/core/theme/app_theme.dart';
import 'package:flutter_starter_kit/features/auth/data/auth_repository.dart';
import 'package:flutter_starter_kit/features/auth/domain/user.dart';
import 'package:flutter_starter_kit/features/auth/presentation/_widgets/branded_social_button.dart';
import 'package:flutter_starter_kit/features/auth/presentation/_widgets/form_error_banner.dart';
import 'package:flutter_starter_kit/features/auth/presentation/_widgets/social_button.dart';
import 'package:flutter_starter_kit/features/auth/presentation/_widgets/social_sign_in_section.dart';
import 'package:flutter_starter_kit/features/auth/presentation/signup_screen.dart';
import 'package:flutter_starter_kit/l10n/generated/app_localizations.dart';

/// [AuthRepository] 를 mocktail 로 대체하기 위한 Mock.
class _MockAuthRepository extends Mock implements AuthRepository {}

/// [SignupScreen] 을 영문 로케일 + [AppTheme.light] 주입 상태로 pump 한다.
Future<void> _pumpSignup(
  WidgetTester tester,
  _MockAuthRepository mockRepo,
) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authRepositoryProvider.overrideWithValue(mockRepo),
        activeStrategiesProvider(const Locale('en')).overrideWithValue(
          const <AuthStrategy>[
            GoogleAuthStrategy(),
            AppleAuthStrategy(),
            FacebookAuthStrategy(),
          ],
        ),
      ],
      child: MaterialApp(
        theme: AppTheme.light(),
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const SignupScreen(),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  late _MockAuthRepository mockRepo;

  setUp(() {
    mockRepo = _MockAuthRepository();
  });

  group('SignupScreen', () {
    testWidgets('1. 빈 입력 제출 시 3개 validator 에러 inline 표시', (tester) async {
      await _pumpSignup(tester, mockRepo);
      // AuthScaffold(SingleChildScrollView) content 가 default 800x600 viewport
      // 보다 길어 Create account 버튼이 viewport 밖에 위치. Test 2~ 는 enterText
      // → EditableText.ensureVisible 자동 우회. Test 1 만 텍스트 입력 0건이라
      // 명시적 ensureVisible 필요.
      await tester.ensureVisible(
        find.widgetWithText(FilledButton, 'Create account'),
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Create account'));
      await tester.pump();

      expect(find.text('Enter your name.'), findsOneWidget);
      expect(find.text('Enter your email address.'), findsOneWidget);
      expect(
        find.text('Password must be at least 8 characters.'),
        findsOneWidget,
      );
      verifyNever(
        () => mockRepo.signUpWithEmail(
          email: any(named: 'email'),
          password: any(named: 'password'),
          displayName: any(named: 'displayName'),
        ),
      );
    });

    testWidgets('2. displayName 33자 입력 시 too long 에러 표시', (tester) async {
      await _pumpSignup(tester, mockRepo);
      final longName = 'a' * 33;
      await tester.enterText(find.byType(TextFormField).at(0), longName);
      await tester.tap(find.widgetWithText(FilledButton, 'Create account'));
      await tester.pump();

      expect(find.text('Name must be 32 characters or fewer.'), findsOneWidget);
    });

    testWidgets('3. 정상 입력 제출 시 Repository 호출 (트림 검증)', (tester) async {
      when(
        () => mockRepo.signUpWithEmail(
          email: any(named: 'email'),
          password: any(named: 'password'),
          displayName: any(named: 'displayName'),
        ),
      ).thenAnswer(
        (_) async => Result.success(
          User(
            uid: 'u1',
            email: 'new@example.com',
            emailVerified: true,
            displayName: 'Test User',
            createdAt: DateTime.utc(2026),
          ),
        ),
      );

      await _pumpSignup(tester, mockRepo);
      await tester.enterText(find.byType(TextFormField).at(0), '  Test User  ');
      await tester.enterText(
        find.byType(TextFormField).at(1),
        '  new@example.com  ',
      );
      await tester.enterText(find.byType(TextFormField).at(2), 'password123');
      final ctaFinder = find.widgetWithText(FilledButton, 'Create account');
      await tester.ensureVisible(ctaFinder);
      await tester.pumpAndSettle();
      await tester.tap(ctaFinder);
      await tester.pump();
      await tester.pumpAndSettle();

      verify(
        () => mockRepo.signUpWithEmail(
          email: 'new@example.com',
          password: 'password123',
          displayName: 'Test User',
        ),
      ).called(1);
    });

    testWidgets('4. EmailAlreadyInUse 에러 시 폼 상단 배너 표시', (tester) async {
      when(
        () => mockRepo.signUpWithEmail(
          email: any(named: 'email'),
          password: any(named: 'password'),
          displayName: any(named: 'displayName'),
        ),
      ).thenAnswer((_) async => const Result.failure(EmailAlreadyInUse()));

      await _pumpSignup(tester, mockRepo);
      await tester.enterText(find.byType(TextFormField).at(0), 'Name');
      await tester.enterText(find.byType(TextFormField).at(1), 'a@b.com');
      await tester.enterText(find.byType(TextFormField).at(2), 'password123');
      final ctaFinder = find.widgetWithText(FilledButton, 'Create account');
      await tester.ensureVisible(ctaFinder);
      await tester.pumpAndSettle();
      await tester.tap(ctaFinder);
      await tester.pump();
      await tester.pumpAndSettle();

      expect(find.text('Email is already in use.'), findsOneWidget);
      expect(find.byIcon(Icons.error_outline), findsOneWidget);
    });

    testWidgets('5. 로딩 중 spinner + 버튼 disabled', (tester) async {
      final completer = Completer<Result<User>>();
      when(
        () => mockRepo.signUpWithEmail(
          email: any(named: 'email'),
          password: any(named: 'password'),
          displayName: any(named: 'displayName'),
        ),
      ).thenAnswer((_) => completer.future);

      await _pumpSignup(tester, mockRepo);
      await tester.enterText(find.byType(TextFormField).at(0), 'Name');
      await tester.enterText(find.byType(TextFormField).at(1), 'a@b.com');
      await tester.enterText(find.byType(TextFormField).at(2), 'password123');
      final ctaFinder = find.widgetWithText(FilledButton, 'Create account');
      await tester.ensureVisible(ctaFinder);
      await tester.pumpAndSettle();
      await tester.tap(ctaFinder);
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Create account'), findsNothing);
      final button = tester.widget<FilledButton>(find.byType(FilledButton));
      expect(button.onPressed, isNull);

      completer.complete(
        Result.success(
          User(
            uid: 'u',
            email: 'a@b.com',
            emailVerified: true,
            displayName: 'Name',
            createdAt: DateTime.utc(2026),
          ),
        ),
      );
      await tester.pumpAndSettle();
    });

    testWidgets('6. 화면 렌더 시 navigation 미호출 (예외 없음)', (tester) async {
      await _pumpSignup(tester, mockRepo);
      expect(tester.takeException(), isNull);
    });

    testWidgets('7. 소셜 버튼 3개(Google + Apple + Facebook) 렌더링 — '
        'Phase 13.2 caller refactor 후 모든 provider 가 '
        'BrandedSocialButton 단일 위임', (tester) async {
      when(() => mockRepo.signInWithFacebook()).thenAnswer((_) async => null);
      await _pumpSignup(tester, mockRepo);
      // Phase 13.2 R7/R8 (옵션 A pivot, Wave 0 lock D-94) — Facebook 분기도
      // BrandedSocialButton.facebook 위임 (Meta 공식 자상 PNG + Apple
      // SignInWithAppleButton 패턴 mirror 의 _renderFacebookButton 위제).
      // Google/Apple/Facebook 3 provider 모두 BrandedSocialButton 단일
      // 위임 — sign_in_button 패키지 의존 폐기 (R10).
      expect(find.byType(SocialButton), findsNWidgets(3));
      expect(find.byType(BrandedSocialButton), findsNWidgets(3));
    });

    testWidgets('8. OrDivider "or" 텍스트가 표시된다', (tester) async {
      await _pumpSignup(tester, mockRepo);
      expect(find.text('or'), findsOneWidget);
    });

    // -----------------------------------------------------------------
    // Phase 8 Apple 로그인 시나리오 (AUTH-03-18)
    // Phase 9: 플랫폼 분기 제거(D-04). 통일 순서 Google->Apple->Facebook.
    // Apple 버튼은 두 번째(index 1) SignInButton.
    // -----------------------------------------------------------------
    group('SignupScreen Apple sign-in integration', () {
      testWidgets('AUTH-03-18: SocialSignInSection 렌더링 + Apple 에러 시 '
          'FormErrorBanner 표시 (이메일 자동 채움 없음)', (tester) async {
        when(() => mockRepo.signInWithApple()).thenAnswer(
          (_) async => const Result<User>.failure(ServiceUnavailable()),
        );
        when(() => mockRepo.signInWithFacebook()).thenAnswer((_) async => null);

        await _pumpSignup(tester, mockRepo);
        await tester.pumpAndSettle();

        // SocialSignInSection이 렌더되고 3개 SocialButton 존재 (D-04).
        expect(find.byType(SocialSignInSection), findsOneWidget);
        expect(find.byType(SocialButton), findsNWidgets(3));

        // D-04: 통일 순서에서 Apple 버튼은 두 번째(index 1).
        // Phase 13.1-08 — Apple 분기는 BrandedSocialButton.apple() 위임.
        await tester.tap(find.byType(SocialButton).at(1));
        await tester.pumpAndSettle();

        // 소셜 영역 FormErrorBanner에 ServiceUnavailable 에러가 표시되어야 한다.
        final banner = tester.widget<FormErrorBanner>(
          find.descendant(
            of: find.byType(SocialSignInSection),
            matching: find.byType(FormErrorBanner),
          ),
        );
        expect(banner.exception, isA<ServiceUnavailable>());

        // SignupScreen은 이메일 자동 채움 없음 -- 이메일 필드는 비어 있다
        // (LoginScreen의 D-10 정책과 다름).
        final emailField = tester.widget<TextFormField>(
          find.byType(TextFormField).at(1),
        );
        expect(emailField.controller?.text, isEmpty);
      });
    });
  });
}
