import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_starter_kit/core/error/app_exception.dart';
import 'package:flutter_starter_kit/core/theme/app_theme.dart';
import 'package:flutter_starter_kit/features/auth/presentation/_widgets/form_error_banner.dart';
import 'package:flutter_starter_kit/l10n/generated/app_localizations.dart';

/// 단일 FormErrorBanner 를 영문 로케일로 pump 하는 헬퍼.
///
/// [AppTheme.light()] 를 주입하여 [AppSpacing] / [AppColors] /
/// [AppTypography] ThemeExtension 이 context 에서 resolve 되도록 한다.
Future<void> pumpBanner(
  WidgetTester tester, {
  required AppException? exception,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light(),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('en'),
      home: Scaffold(body: FormErrorBanner(exception: exception)),
    ),
  );
}

void main() {
  group('FormErrorBanner', () {
    testWidgets('exception 이 null 이면 SizedBox.shrink()', (tester) async {
      await pumpBanner(tester, exception: null);
      expect(find.byIcon(Icons.error_outline), findsNothing);
      expect(find.byType(Container), findsNothing);
    });

    testWidgets('InvalidCredentials 시 영어 메시지 표시', (tester) async {
      await pumpBanner(tester, exception: const InvalidCredentials());
      expect(find.byIcon(Icons.error_outline), findsOneWidget);
      expect(find.text('Invalid email or password.'), findsOneWidget);
    });

    testWidgets('InvalidEmail 시 신규 에러 메시지 표시', (tester) async {
      await pumpBanner(tester, exception: const InvalidEmail());
      expect(find.text('This email address is not valid.'), findsOneWidget);
    });
  });
}
