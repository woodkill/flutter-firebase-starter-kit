import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_starter_kit/core/theme/app_theme.dart';
import 'package:flutter_starter_kit/features/auth/presentation/_widgets/primary_cta.dart';
import 'package:flutter_starter_kit/l10n/generated/app_localizations.dart';

/// 단일 PrimaryCta 를 영문 로케일로 pump 하는 헬퍼.
///
/// [AppTheme.light()] 를 주입하여 ThemeExtension 3종이 context 에서
/// resolve 되도록 한다 (PrimaryCta 는 colorScheme.onPrimary 를 사용).
Future<void> pumpCta(
  WidgetTester tester, {
  required bool isLoading,
  required VoidCallback? onPressed,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light(),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('en'),
      home: Scaffold(
        body: PrimaryCta(
          label: 'Submit',
          onPressed: onPressed,
          isLoading: isLoading,
        ),
      ),
    ),
  );
}

void main() {
  group('PrimaryCta', () {
    testWidgets('isLoading=false 시 라벨 텍스트가 표시된다', (tester) async {
      await pumpCta(tester, isLoading: false, onPressed: () {});
      expect(find.text('Submit'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('isLoading=true 시 spinner 로 교체되고 disabled', (tester) async {
      await pumpCta(tester, isLoading: true, onPressed: () {});
      expect(find.text('Submit'), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      final btn = tester.widget<FilledButton>(find.byType(FilledButton));
      expect(btn.onPressed, isNull);
    });

    testWidgets('onPressed=null 이면 disabled', (tester) async {
      await pumpCta(tester, isLoading: false, onPressed: null);
      final btn = tester.widget<FilledButton>(find.byType(FilledButton));
      expect(btn.onPressed, isNull);
    });
  });
}
