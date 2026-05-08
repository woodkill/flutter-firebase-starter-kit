import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:sign_in_button/sign_in_button.dart';

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
import 'package:flutter_starter_kit/features/auth/presentation/_widgets/email_field.dart';
import 'package:flutter_starter_kit/features/auth/presentation/_widgets/form_error_banner.dart';
import 'package:flutter_starter_kit/features/auth/presentation/_widgets/social_button.dart';
import 'package:flutter_starter_kit/features/auth/presentation/_widgets/social_sign_in_section.dart';
import 'package:flutter_starter_kit/features/auth/presentation/login_screen.dart';
import 'package:flutter_starter_kit/l10n/generated/app_localizations.dart';

/// [AuthRepository] 를 mocktail 로 대체하기 위한 Mock.
class _MockAuthRepository extends Mock implements AuthRepository {}

/// [LoginScreen] 을 영문 로케일 + [AppTheme.light] 주입 상태로 pump 한다.
Future<void> _pumpLogin(
  WidgetTester tester,
  _MockAuthRepository mockRepo,
) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authRepositoryProvider.overrideWithValue(mockRepo),
        activeStrategiesProvider(
          const Locale('en'),
        ).overrideWithValue(const <AuthStrategy>[
          GoogleAuthStrategy(),
          AppleAuthStrategy(),
          FacebookAuthStrategy(),
        ]),
      ],
      child: MaterialApp(
        theme: AppTheme.light(),
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const LoginScreen(),
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

  group('LoginScreen', () {
    testWidgets('1. 빈 입력 제출 시 validator 에러 inline 표시', (tester) async {
      await _pumpLogin(tester, mockRepo);
      await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
      await tester.pump();
      expect(find.text('Enter your email address.'), findsOneWidget);
      expect(
        find.text('Password must be at least 8 characters.'),
        findsOneWidget,
      );
      verifyNever(
        () => mockRepo.signInWithEmail(
          email: any(named: 'email'),
          password: any(named: 'password'),
        ),
      );
    });

    testWidgets('2. 잘못된 이메일/짧은 비밀번호 inline 에러', (tester) async {
      await _pumpLogin(tester, mockRepo);
      await tester.enterText(find.byType(TextFormField).first, 'not-an-email');
      await tester.enterText(find.byType(TextFormField).at(1), 'short');
      await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
      await tester.pump();
      expect(find.text('Enter a valid email address.'), findsOneWidget);
      expect(
        find.text('Password must be at least 8 characters.'),
        findsOneWidget,
      );
    });

    testWidgets('3. 정상 입력 제출 시 Repository 호출', (tester) async {
      when(
        () => mockRepo.signInWithEmail(
          email: any(named: 'email'),
          password: any(named: 'password'),
        ),
      ).thenAnswer(
        (_) async => Result.success(
          User(
            uid: 'u1',
            email: 'user@example.com',
            emailVerified: true,
            createdAt: DateTime.utc(2026),
          ),
        ),
      );

      await _pumpLogin(tester, mockRepo);
      await tester.enterText(
        find.byType(TextFormField).first,
        'user@example.com',
      );
      await tester.enterText(find.byType(TextFormField).at(1), 'password123');
      await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
      await tester.pump();
      await tester.pumpAndSettle();

      verify(
        () => mockRepo.signInWithEmail(
          email: 'user@example.com',
          password: 'password123',
        ),
      ).called(1);
    });

    testWidgets('4. Repository 에러 시 폼 상단 배너 표시', (tester) async {
      when(
        () => mockRepo.signInWithEmail(
          email: any(named: 'email'),
          password: any(named: 'password'),
        ),
      ).thenAnswer((_) async => const Result.failure(InvalidCredentials()));

      await _pumpLogin(tester, mockRepo);
      await tester.enterText(
        find.byType(TextFormField).first,
        'user@example.com',
      );
      await tester.enterText(find.byType(TextFormField).at(1), 'password123');
      await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
      await tester.pump();
      await tester.pumpAndSettle();

      expect(find.text('Invalid email or password.'), findsOneWidget);
      expect(find.byIcon(Icons.error_outline), findsOneWidget);
    });

    testWidgets('5. 로딩 중 spinner + 버튼 disabled', (tester) async {
      final completer = Completer<Result<User>>();
      when(
        () => mockRepo.signInWithEmail(
          email: any(named: 'email'),
          password: any(named: 'password'),
        ),
      ).thenAnswer((_) => completer.future);

      await _pumpLogin(tester, mockRepo);
      await tester.enterText(
        find.byType(TextFormField).first,
        'user@example.com',
      );
      await tester.enterText(find.byType(TextFormField).at(1), 'password123');
      await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Sign in'), findsNothing);
      final button = tester.widget<FilledButton>(find.byType(FilledButton));
      expect(button.onPressed, isNull);

      completer.complete(
        Result.success(
          User(
            uid: 'u',
            email: 'a@b.com',
            emailVerified: true,
            createdAt: DateTime.utc(2026),
          ),
        ),
      );
      await tester.pumpAndSettle();
    });

    testWidgets(
      '6. 소셜 버튼 3개(Google + Apple + Facebook) 렌더링 — '
      'Phase 13.1 caller refactor 후 Google/Apple 은 BrandedSocialButton, '
      'Facebook 만 SignInButton 잔존',
      (tester) async {
        when(
          () => mockRepo.signInWithFacebook(),
        ).thenAnswer((_) async => null);
        await _pumpLogin(tester, mockRepo);
        // Plan 13.1-08 — Google/Apple → BrandedSocialButton, Facebook → SignInButton.
        expect(find.byType(SocialButton), findsNWidgets(3));
        expect(find.byType(BrandedSocialButton), findsNWidgets(2));
        expect(find.byType(SignInButton), findsNWidgets(1));
      },
    );

    testWidgets('7. OrDivider "or" 텍스트가 표시된다', (tester) async {
      await _pumpLogin(tester, mockRepo);
      expect(find.text('or'), findsOneWidget);
    });

    testWidgets('8. 소셜 버튼 영역이 EmailField 위에 위치한다', (tester) async {
      await _pumpLogin(tester, mockRepo);

      // Plan 13.1-08 — 첫 SocialButton (Google) 의 위치를 검증 (분기와 무관하게
      // SocialButton wrapper 는 모든 분기에서 사용됨).
      final firstSocialButton = tester.getTopLeft(
        find.byType(SocialButton).first,
      );
      final emailField = tester.getTopLeft(find.byType(TextFormField).first);
      expect(
        firstSocialButton.dy,
        lessThan(emailField.dy),
        reason: '소셜 버튼 영역이 이메일 필드 위에 배치되어야 한다',
      );
    });

    // -----------------------------------------------------------------
    // Phase 8 Apple 로그인 시나리오 (AUTH-03-15, 16, 17)
    // Phase 9: 플랫폼 분기 제거(D-04). 통일 순서 Google→Apple→Facebook.
    // Phase 13.1-08: Apple 버튼은 두 번째(index 1) SocialButton — 내부적으로
    // BrandedSocialButton.apple() (SignInWithAppleButton 위제 위임) 사용.
    // -----------------------------------------------------------------
    group('LoginScreen Apple sign-in integration', () {
      /// Apple 버튼 finder — 통일 순서에서 두 번째(index 1) SocialButton.
      Finder findAppleButton() => find.byType(SocialButton).at(1);

      testWidgets('AUTH-03-15: Apple 로그인 성공 시 FormErrorBanner에 에러 없음 '
          '(navigation은 authRedirect 위임)', (tester) async {
        when(() => mockRepo.signInWithApple()).thenAnswer(
          (_) async => Result<User>.success(
            User(
              uid: 'apple-uid',
              email: 'x@privaterelay.appleid.com',
              emailVerified: true,
              displayName: 'Apple User',
              createdAt: DateTime.utc(2026, 4, 11),
              providerIds: const <String>['apple.com'],
            ),
          ),
        );
        when(() => mockRepo.signInWithFacebook()).thenAnswer((_) async => null);

        await _pumpLogin(tester, mockRepo);
        await tester.pumpAndSettle();

        // D-04: 통일 순서에서 Apple 버튼은 두 번째.
        await tester.tap(findAppleButton());
        await tester.pumpAndSettle();

        // Repository 호출 검증.
        verify(() => mockRepo.signInWithApple()).called(1);

        // 소셜 영역 FormErrorBanner.exception == null (에러 없음).
        final banner = tester.widget<FormErrorBanner>(
          find.descendant(
            of: find.byType(SocialSignInSection),
            matching: find.byType(FormErrorBanner),
          ),
        );
        expect(banner.exception, isNull);
      });

      testWidgets(
        'AUTH-03-16: Apple 에러(ServiceUnavailable) 시 FormErrorBanner 표시',
        (tester) async {
          when(() => mockRepo.signInWithApple()).thenAnswer(
            (_) async => const Result<User>.failure(ServiceUnavailable()),
          );
          when(
            () => mockRepo.signInWithFacebook(),
          ).thenAnswer((_) async => null);

          await _pumpLogin(tester, mockRepo);
          await tester.pumpAndSettle();

          // D-04: 통일 순서에서 Apple 버튼은 두 번째.
          await tester.tap(findAppleButton());
          await tester.pumpAndSettle();

          final banner = tester.widget<FormErrorBanner>(
            find.descendant(
              of: find.byType(SocialSignInSection),
              matching: find.byType(FormErrorBanner),
            ),
          );
          expect(banner.exception, isA<ServiceUnavailable>());
        },
      );

      testWidgets(
        'AUTH-03-17: Apple AccountExistsWithDifferentCredential(email) 시 '
        '이메일 필드 자동 채움 + 포커스 이동 (D-10)',
        (tester) async {
          when(() => mockRepo.signInWithApple()).thenAnswer(
            (_) async => const Result<User>.failure(
              AccountExistsWithDifferentCredential(
                email: 'collision@example.com',
              ),
            ),
          );
          when(
            () => mockRepo.signInWithFacebook(),
          ).thenAnswer((_) async => null);

          await _pumpLogin(tester, mockRepo);
          await tester.pumpAndSettle();

          // D-04: 통일 순서에서 Apple 버튼은 두 번째.
          await tester.tap(findAppleButton());
          await tester.pumpAndSettle();

          // EmailField 내부 TextFormField의 controller 값을 검증.
          // dynamic 캐스트 금지 -- find.descendant + widget<TextFormField>.
          final emailFormField = tester.widget<TextFormField>(
            find.descendant(
              of: find.byType(EmailField),
              matching: find.byType(TextFormField),
            ),
          );
          expect(emailFormField.controller?.text, 'collision@example.com');

          // 소셜 영역 FormErrorBanner에도 에러가 표시되어야 한다.
          final banner = tester.widget<FormErrorBanner>(
            find.descendant(
              of: find.byType(SocialSignInSection),
              matching: find.byType(FormErrorBanner),
            ),
          );
          expect(banner.exception, isA<AccountExistsWithDifferentCredential>());
        },
      );
    });
  });
}
