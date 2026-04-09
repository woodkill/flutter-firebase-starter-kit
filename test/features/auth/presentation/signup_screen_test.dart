import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:flutter_starter_kit/core/error/app_exception.dart';
import 'package:flutter_starter_kit/core/error/result.dart';
import 'package:flutter_starter_kit/core/theme/app_theme.dart';
import 'package:flutter_starter_kit/features/auth/data/auth_repository.dart';
import 'package:flutter_starter_kit/features/auth/domain/user.dart';
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
      await tester.tap(find.widgetWithText(FilledButton, 'Create account'));
      await tester.pump();

      expect(find.text('Enter your name.'), findsOneWidget);
      expect(
        find.text('Enter your email address.'),
        findsOneWidget,
      );
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

      expect(
        find.text('Name must be 32 characters or fewer.'),
        findsOneWidget,
      );
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
      await tester.enterText(
        find.byType(TextFormField).at(0),
        '  Test User  ',
      );
      await tester.enterText(
        find.byType(TextFormField).at(1),
        '  new@example.com  ',
      );
      await tester.enterText(
        find.byType(TextFormField).at(2),
        'password123',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Create account'));
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
      ).thenAnswer(
        (_) async => const Result.failure(EmailAlreadyInUse()),
      );

      await _pumpSignup(tester, mockRepo);
      await tester.enterText(
        find.byType(TextFormField).at(0),
        'Name',
      );
      await tester.enterText(
        find.byType(TextFormField).at(1),
        'a@b.com',
      );
      await tester.enterText(
        find.byType(TextFormField).at(2),
        'password123',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Create account'));
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
      await tester.enterText(
        find.byType(TextFormField).at(0),
        'Name',
      );
      await tester.enterText(
        find.byType(TextFormField).at(1),
        'a@b.com',
      );
      await tester.enterText(
        find.byType(TextFormField).at(2),
        'password123',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Create account'));
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(
        find.widgetWithText(FilledButton, 'Create account'),
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
            displayName: 'Name',
            createdAt: DateTime.utc(2026),
          ),
        ),
      );
      await tester.pumpAndSettle();
    });

    testWidgets('6. 화면 렌더 시 navigation 미호출 (예외 없음)', (tester) async {
      // SignupScreen 자체 렌더에서 navigation 콜이 발생하면 unhandled
      // exception 이 발생한다. 본 testWidgets 가 통과하면 D-05 (성공 시
      // navigation 은 redirect 가드가 처리) 가 화면 빌드 단계에서 위반
      // 되지 않음을 보장한다. 정적 grep guard 는 acceptance criteria 가
      // 별도로 검증한다.
      await _pumpSignup(tester, mockRepo);
      expect(tester.takeException(), isNull);
    });
  });
}
