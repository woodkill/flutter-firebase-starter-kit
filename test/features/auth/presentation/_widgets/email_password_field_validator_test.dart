import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_starter_kit/features/auth/presentation/_widgets/email_field.dart';
import 'package:flutter_starter_kit/features/auth/presentation/_widgets/password_field.dart';
import 'package:flutter_starter_kit/l10n/generated/app_localizations.dart';

/// EmailField 를 Form 안에서 pump 하고 그 안의 [TextFormField] 를 추출한다.
Future<TextFormField> pumpEmailField(WidgetTester tester) async {
  final controller = TextEditingController();
  final focus = FocusNode();
  addTearDown(controller.dispose);
  addTearDown(focus.dispose);
  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: Form(
          child: EmailField(controller: controller, focusNode: focus),
        ),
      ),
    ),
  );
  return tester.widget<TextFormField>(find.byType(TextFormField));
}

/// PasswordField 를 Form 안에서 pump 하고 그 안의 [TextFormField] 를 추출한다.
Future<TextFormField> pumpPasswordField(
  WidgetTester tester, {
  required bool isNewPassword,
}) async {
  final controller = TextEditingController();
  final focus = FocusNode();
  addTearDown(controller.dispose);
  addTearDown(focus.dispose);
  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: Form(
          child: PasswordField(
            controller: controller,
            focusNode: focus,
            isNewPassword: isNewPassword,
          ),
        ),
      ),
    ),
  );
  return tester.widget<TextFormField>(find.byType(TextFormField));
}

void main() {
  group('EmailField validator', () {
    testWidgets('빈 값 → errorEmailRequired', (tester) async {
      final field = await pumpEmailField(tester);
      expect(field.validator?.call(''), 'Enter your email address.');
    });

    testWidgets('공백만 입력 → errorEmailRequired', (tester) async {
      final field = await pumpEmailField(tester);
      expect(field.validator?.call('   '), 'Enter your email address.');
    });

    testWidgets('잘못된 형식 → errorInvalidEmailFormat', (tester) async {
      final field = await pumpEmailField(tester);
      expect(
        field.validator?.call('not-an-email'),
        'Enter a valid email address.',
      );
    });

    testWidgets('정상 이메일 → null', (tester) async {
      final field = await pumpEmailField(tester);
      expect(field.validator?.call('user@example.com'), isNull);
    });
  });

  group('PasswordField validator', () {
    testWidgets('빈 값 → errorPasswordTooShort', (tester) async {
      final field = await pumpPasswordField(tester, isNewPassword: false);
      expect(
        field.validator?.call(''),
        'Password must be at least 8 characters.',
      );
    });

    testWidgets('짧은 비밀번호 (7자) → errorPasswordTooShort', (tester) async {
      final field = await pumpPasswordField(tester, isNewPassword: true);
      expect(
        field.validator?.call('short12'),
        'Password must be at least 8 characters.',
      );
    });

    testWidgets('정상 비밀번호 (8자 이상) → null', (tester) async {
      final field = await pumpPasswordField(tester, isNewPassword: false);
      expect(field.validator?.call('password123'), isNull);
    });
  });
}
