import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_starter_kit/core/error/app_exception.dart';
import 'package:flutter_starter_kit/core/theme/app_theme.dart';
import 'package:flutter_starter_kit/l10n/generated/app_localizations.dart';
import 'package:flutter_starter_kit/shared/widgets/error_snack_bar.dart';

/// 버튼 탭 시 [onTap] 으로 SnackBar 헬퍼를 호출하는 화면을 pump 한다.
Future<void> pumpTrigger(
  WidgetTester tester, {
  required Locale locale,
  required void Function(BuildContext context) onTap,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light(),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: locale,
      home: Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: TextButton(
              onPressed: () => onTap(context),
              child: const Text('trigger'),
            ),
          ),
        ),
      ),
    ),
  );
}

void main() {
  group('Phase 17 오류 안전망 (T-17-ERR)', () {
    final ko = lookupAppLocalizations(const Locale('ko'));

    testWidgets('T-17-ERR-05 오류 문구 SnackBar 를 띄우고 액션은 없다', (tester) async {
      await pumpTrigger(
        tester,
        locale: const Locale('ko'),
        onTap: (context) =>
            showErrorSnackBar(context, const ServiceUnavailable()),
      );

      await tester.tap(find.text('trigger'));
      await tester.pumpAndSettle();

      expect(find.text(ko.errorServiceUnavailable), findsOneWidget);
      final snackBar = tester.widget<SnackBar>(find.byType(SnackBar));
      expect(snackBar.action, isNull);
      expect(snackBar.behavior, isNull);
    });

    testWidgets('T-17-ERR-05 연속 2회 호출하면 마지막 SnackBar 1개만 남는다', (tester) async {
      await pumpTrigger(
        tester,
        locale: const Locale('ko'),
        onTap: (context) {
          showErrorSnackBar(context, const ServiceUnavailable());
          showErrorSnackBar(context, const NoInternetConnection());
        },
      );

      await tester.tap(find.text('trigger'));
      await tester.pumpAndSettle();

      expect(find.byType(SnackBar), findsOneWidget);
      expect(find.text(ko.errorNoInternet), findsOneWidget);
      expect(find.text(ko.errorServiceUnavailable), findsNothing);
    });

    testWidgets('T-17-ERR-05 behavior 를 넘기면 SnackBar 에 그대로 전달된다', (
      tester,
    ) async {
      await pumpTrigger(
        tester,
        locale: const Locale('ko'),
        onTap: (context) => showErrorSnackBar(
          context,
          const ServiceUnavailable(),
          behavior: SnackBarBehavior.floating,
        ),
      );

      await tester.tap(find.text('trigger'));
      await tester.pumpAndSettle();

      final snackBar = tester.widget<SnackBar>(find.byType(SnackBar));
      expect(snackBar.behavior, SnackBarBehavior.floating);
    });

    testWidgets('T-17-ERR-06 280 dp ja 에서 overflow 0 · maxLines 미지정', (
      tester,
    ) async {
      tester.view
        ..physicalSize = const Size(280, 800)
        ..devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await pumpTrigger(
        tester,
        locale: const Locale('ja'),
        onTap: (context) =>
            showErrorSnackBar(context, const UnknownException()),
      );

      await tester.tap(find.text('trigger'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      final ja = lookupAppLocalizations(const Locale('ja'));
      final content = tester.widget<Text>(
        find.descendant(
          of: find.byType(SnackBar),
          matching: find.text(ja.errorUnknown),
        ),
      );
      expect(content.maxLines, isNull);
    });
  });
}
