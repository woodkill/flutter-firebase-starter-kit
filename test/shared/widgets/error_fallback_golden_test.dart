// Phase 17 Plan 17-07 Task 2 — release 깨진 화면 대체 golden.
//
// **캡처 계약 (UI-SPEC §Golden 캡처 계약):** `ErrorFallback` 단독 · ko ·
// 280×800 logical · DPR 3 · production 폰트 FontLoader + KR subset
// `fontFamilyFallback` · `find.byType(MaterialApp)` 전체 캡처. 비교 원본 =
// `.planning/phases/17-firebase-services/mockups/adopted_error_fallback_17_ko_280_{light,dark}.png`
// (sign-off 완료) — golden 은 그 PNG 와 byte 동일해야 한다(`cmp`).

import 'package:flutter/material.dart';
import 'package:flutter_starter_kit/l10n/generated/app_localizations.dart';
import 'package:flutter_starter_kit/shared/widgets/error_fallback.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../features/settings/presentation/settings_golden_harness.dart';

/// golden viewport 너비 (logical px) — 지원 최소 폭.
const double _goldenWidth = 280;

void main() {
  setUpAll(loadGoldenFonts);

  group('Phase 17 깨진 화면 대체 golden (T-17-FALLBACK)', () {
    for (final brightness in Brightness.values) {
      final mode = brightness.name;
      testWidgets('T-17-FALLBACK-03 ko 280×800 $mode = 채택 mockup byte 동일', (
        tester,
      ) async {
        tester.view.devicePixelRatio = kGoldenDpr;
        tester.view.physicalSize =
            const Size(_goldenWidth, kGoldenHeight) * kGoldenDpr;
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetPhysicalSize);

        await tester.pumpWidget(
          MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: goldenTheme(brightness, 'ko'),
            locale: const Locale('ko'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: const ErrorFallback(),
          ),
        );
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        final ko = lookupAppLocalizations(const Locale('ko'));
        expect(find.text(ko.errorWidgetFallbackTitle), findsOneWidget);
        expect(find.text(ko.errorWidgetFallbackBody), findsOneWidget);

        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile('goldens/error_fallback_17_ko_280_$mode.png'),
        );
      });
    }
  });
}
