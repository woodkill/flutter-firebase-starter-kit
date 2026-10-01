import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_starter_kit/core/error/app_exception.dart';
import 'package:flutter_starter_kit/core/theme/app_theme.dart';
import 'package:flutter_starter_kit/features/auth/presentation/_widgets/form_error_banner.dart'
    show FormErrorBanner;
import 'package:flutter_starter_kit/l10n/generated/app_localizations.dart';
import 'package:flutter_starter_kit/shared/widgets/error_banner.dart';

/// [child] 를 ko 로케일 · 앱 테마로 pump 하는 헬퍼.
Future<void> pumpKo(WidgetTester tester, Widget child) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light(),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('ko'),
      home: Scaffold(body: child),
    ),
  );
}

/// liveRegion 이 켜진 [Semantics] 위젯 finder.
Finder findLiveRegion() => find.byWidgetPredicate(
  (widget) => widget is Semantics && (widget.properties.liveRegion ?? false),
);

void main() {
  group('Phase 17 오류 안전망 (T-17-ERR)', () {
    testWidgets(
      'T-17-ERR-04 exception null 이면 SizedBox.shrink 만 · liveRegion 0',
      (tester) async {
        await pumpKo(tester, const ErrorBanner(exception: null));

        expect(
          find.descendant(
            of: find.byType(ErrorBanner),
            matching: find.byType(SizedBox),
          ),
          findsOneWidget,
        );
        expect(tester.getSize(find.byType(ErrorBanner)).height, 0);
        expect(findLiveRegion(), findsNothing);
        expect(find.byIcon(Icons.error_outline), findsNothing);
      },
    );

    testWidgets('T-17-ERR-04 FormErrorBanner 별칭으로 만든 위젯이 ErrorBanner 로 찾아진다', (
      tester,
    ) async {
      await pumpKo(
        tester,
        const FormErrorBanner(exception: ServiceUnavailable()),
      );

      final ko = lookupAppLocalizations(const Locale('ko'));
      expect(find.byType(ErrorBanner), findsOneWidget);
      expect(find.text(ko.errorServiceUnavailable), findsOneWidget);
      expect(findLiveRegion(), findsOneWidget);
    });
  });
}
