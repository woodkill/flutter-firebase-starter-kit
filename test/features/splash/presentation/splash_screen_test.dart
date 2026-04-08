import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_starter_kit/core/theme/app_theme.dart';
import 'package:flutter_starter_kit/features/splash/presentation/splash_screen.dart';
import 'package:flutter_starter_kit/l10n/generated/app_localizations.dart';

/// [SplashScreen] 을 지정한 [locale] 로 pump 한다.
Future<void> _pumpSplash(
  WidgetTester tester, {
  required Locale locale,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light(),
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: const SplashScreen(),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('SplashScreen', () {
    testWidgets('1. en 로케일에서 l10n 제목 + stub 마커 + 공사 중 아이콘 렌더', (
      tester,
    ) async {
      await _pumpSplash(tester, locale: const Locale('en'));

      expect(find.text('Splash'), findsOneWidget);
      expect(find.text('Phase 10 placeholder'), findsOneWidget);
      expect(find.byIcon(Icons.construction), findsOneWidget);
    });

    testWidgets('2. ko 로케일에서 한글 l10n 제목 + 한글 stub 마커 렌더', (
      tester,
    ) async {
      await _pumpSplash(tester, locale: const Locale('ko'));

      expect(find.text('스플래시'), findsOneWidget);
      expect(find.text('Phase 10 플레이스홀더'), findsOneWidget);
      expect(find.byIcon(Icons.construction), findsOneWidget);
    });
  });
}
