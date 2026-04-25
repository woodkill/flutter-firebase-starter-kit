import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_starter_kit/core/theme/app_theme.dart';
import 'package:flutter_starter_kit/features/terms/presentation/terms_detail_screen.dart';
import 'package:flutter_starter_kit/l10n/generated/app_localizations.dart';

Widget _wrap(TermsType type) => MaterialApp(
  theme: AppTheme.light(),
  locale: const Locale('en'),
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: TermsDetailScreen(type: type),
);

void main() {
  group('TermsDetailScreen', () {
    testWidgets(
      'Test 1: type=TermsType.service → AppBar 타이틀 termsDetailServiceTitle',
      (tester) async {
        await tester.pumpWidget(_wrap(TermsType.service));
        await tester.pumpAndSettle();

        // 영어 ARB: termsDetailServiceTitle = "Terms of service"
        // body 에는 placeholder 가 표시되므로 AppBar 에 한정해 검증한다.
        final appBarTitle = find.descendant(
          of: find.byType(AppBar),
          matching: find.text('Terms of service'),
        );
        expect(appBarTitle, findsOneWidget);
      },
    );

    testWidgets(
      'Test 2: type=TermsType.privacy → AppBar 타이틀 termsDetailPrivacyTitle',
      (tester) async {
        await tester.pumpWidget(_wrap(TermsType.privacy));
        await tester.pumpAndSettle();

        // 영어 ARB: termsDetailPrivacyTitle = "Privacy policy"
        final appBarTitle = find.descendant(
          of: find.byType(AppBar),
          matching: find.text('Privacy policy'),
        );
        expect(appBarTitle, findsOneWidget);
      },
    );

    testWidgets('Test 3: body 에 termsDetailPlaceholder 텍스트 렌더', (tester) async {
      await tester.pumpWidget(_wrap(TermsType.service));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('Place your terms content here'),
        findsOneWidget,
      );
    });
  });
}
