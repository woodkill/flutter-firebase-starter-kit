import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:sign_in_button/sign_in_button.dart';

import 'package:flutter_starter_kit/core/error/app_exception.dart';
import 'package:flutter_starter_kit/core/error/result.dart';
import 'package:flutter_starter_kit/core/theme/app_theme.dart';
import 'package:flutter_starter_kit/features/auth/data/auth_repository.dart';
import 'package:flutter_starter_kit/features/auth/domain/user.dart';
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
      expect(
        find.text('Enter your email address.'),
        findsOneWidget,
      );
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
      await tester.enterText(
        find.byType(TextFormField).first,
        'not-an-email',
      );
      await tester.enterText(
        find.byType(TextFormField).at(1),
        'short',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
      await tester.pump();
      expect(
        find.text('Enter a valid email address.'),
        findsOneWidget,
      );
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
      await tester.enterText(
        find.byType(TextFormField).at(1),
        'password123',
      );
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
      ).thenAnswer(
        (_) async => const Result.failure(InvalidCredentials()),
      );

      await _pumpLogin(tester, mockRepo);
      await tester.enterText(
        find.byType(TextFormField).first,
        'user@example.com',
      );
      await tester.enterText(
        find.byType(TextFormField).at(1),
        'password123',
      );
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
      await tester.enterText(
        find.byType(TextFormField).at(1),
        'password123',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(
        find.widgetWithText(FilledButton, 'Sign in'),
        findsNothing,
      );
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
      '6. Google 버튼(SignInButton)이 렌더링된다',
      (tester) async {
        await _pumpLogin(tester, mockRepo);
        expect(find.byType(SignInButton), findsOneWidget);
      },
    );

    testWidgets(
      '7. OrDivider "or" 텍스트가 표시된다',
      (tester) async {
        await _pumpLogin(tester, mockRepo);
        expect(find.text('or'), findsOneWidget);
      },
    );

    testWidgets(
      '8. Google 버튼이 EmailField 위에 위치한다',
      (tester) async {
        await _pumpLogin(tester, mockRepo);

        final googleButton = tester.getTopLeft(
          find.byType(SignInButton),
        );
        final emailField = tester.getTopLeft(
          find.byType(TextFormField).first,
        );
        expect(
          googleButton.dy,
          lessThan(emailField.dy),
          reason: 'Google 버튼이 이메일 필드 위에 배치되어야 한다',
        );
      },
    );
  });
}
