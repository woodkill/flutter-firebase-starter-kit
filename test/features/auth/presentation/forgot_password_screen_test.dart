import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:flutter_starter_kit/core/error/app_exception.dart';
import 'package:flutter_starter_kit/core/error/result.dart';
import 'package:flutter_starter_kit/core/theme/app_theme.dart';
import 'package:flutter_starter_kit/features/auth/data/auth_repository.dart';
import 'package:flutter_starter_kit/features/auth/presentation/forgot_password_screen.dart';
import 'package:flutter_starter_kit/l10n/generated/app_localizations.dart';

/// [AuthRepository] 를 mocktail 로 대체하기 위한 Mock.
class _MockAuthRepository extends Mock implements AuthRepository {}

/// [ForgotPasswordScreen] 을 영문 로케일 + [AppTheme.light] 주입 상태로
/// pump 한다.
Future<void> _pumpForgot(
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
        home: const ForgotPasswordScreen(),
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

  group('ForgotPasswordScreen', () {
    testWidgets('1. 빈 입력 제출 시 inline 검증 에러', (tester) async {
      await _pumpForgot(tester, mockRepo);
      await tester.tap(
        find.widgetWithText(FilledButton, 'Send reset email'),
      );
      await tester.pump();

      expect(
        find.text('Enter a valid email address.'),
        findsOneWidget,
      );
      verifyNever(
        () => mockRepo.sendPasswordReset(email: any(named: 'email')),
      );
    });

    testWidgets(
      '2. 정상 이메일 제출 시 sendPasswordReset 호출 + 성공 inline 메시지',
      (tester) async {
        when(
          () => mockRepo.sendPasswordReset(email: any(named: 'email')),
        ).thenAnswer((_) async => const Result.success(null));

        await _pumpForgot(tester, mockRepo);
        await tester.enterText(
          find.byType(TextFormField),
          'user@example.com',
        );
        await tester.tap(
          find.widgetWithText(FilledButton, 'Send reset email'),
        );
        await tester.pump();
        await tester.pump();

        verify(
          () => mockRepo.sendPasswordReset(email: 'user@example.com'),
        ).called(1);
        expect(
          find.text('Password reset email sent. Check your inbox.'),
          findsOneWidget,
        );
        expect(find.byIcon(Icons.check_circle_outline), findsOneWidget);

        // 자동 pop 타이머가 dispose 전에 종료되도록 진행한다.
        await tester.pump(const Duration(seconds: 2));
        await tester.pump();
      },
    );

    testWidgets('3. InvalidEmail 에러 시 배너 표시', (tester) async {
      when(
        () => mockRepo.sendPasswordReset(email: any(named: 'email')),
      ).thenAnswer(
        (_) async => const Result.failure(InvalidEmail()),
      );

      await _pumpForgot(tester, mockRepo);
      await tester.enterText(
        find.byType(TextFormField),
        'user@example.com',
      );
      await tester.tap(
        find.widgetWithText(FilledButton, 'Send reset email'),
      );
      await tester.pump();
      await tester.pumpAndSettle();

      expect(
        find.text('This email address is not valid.'),
        findsOneWidget,
      );
      expect(find.byIcon(Icons.error_outline), findsOneWidget);
    });

    testWidgets(
      '4. 로딩 중 spinner + 성공 후 PrimaryCta disabled',
      (tester) async {
        final completer = Completer<Result<void>>();
        when(
          () => mockRepo.sendPasswordReset(email: any(named: 'email')),
        ).thenAnswer((_) => completer.future);

        await _pumpForgot(tester, mockRepo);
        await tester.enterText(
          find.byType(TextFormField),
          'user@example.com',
        );
        await tester.tap(
          find.widgetWithText(FilledButton, 'Send reset email'),
        );
        await tester.pump();

        expect(find.byType(CircularProgressIndicator), findsOneWidget);
        expect(
          find.widgetWithText(FilledButton, 'Send reset email'),
          findsNothing,
        );

        completer.complete(const Result.success(null));
        await tester.pump();
        await tester.pump();

        // 성공 후: PrimaryCta 라벨 다시 등장하고 disabled.
        final btn =
            tester.widget<FilledButton>(find.byType(FilledButton));
        expect(btn.onPressed, isNull);
        expect(
          find.text('Password reset email sent. Check your inbox.'),
          findsOneWidget,
        );

        // 자동 pop 타이머 종료까지 진행한다.
        await tester.pump(const Duration(seconds: 2));
        await tester.pump();
      },
    );
  });
}
