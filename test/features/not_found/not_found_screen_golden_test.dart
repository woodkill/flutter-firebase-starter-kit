// Phase 17.1 D-18 · D-23 — 404 화면 golden (UI-SPEC §Golden 캡처 계약).
//
// **캡처 계약:** `NotFoundScreen` 단독 root(`home:` 직접 · back 없음) · ko ·
// 280×800 logical · DPR 3 · production 폰트 FontLoader + ko CJK fallback ·
// `find.byType(MaterialApp)` 전체 캡처. 비교 원본 =
// `.planning/phases/17.1-production-home-and-404-screen-split/mockups/adopted_not_found_ko_280_{light,dark}.png`
// (사용자 sign-off · 승격 전 임시 함수를 그린 렌더) — golden 은 그 PNG 와 byte
// 동일해야 한다(`cmp`). 다르면 승격이 본문을 바꾼 것이므로 채택 PNG 를 덮어쓰지
// 말고 원인을 먼저 찾는다.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_starter_kit/features/not_found/presentation/not_found_screen.dart';
import 'package:flutter_starter_kit/l10n/generated/app_localizations.dart';

import '../settings/presentation/settings_golden_harness.dart';

/// golden viewport 너비 (logical px) — 지원 최소 폭.
const double _goldenWidth = 280;

void main() {
  setUpAll(loadGoldenFonts);

  group('Phase 17.1 404 golden (T-171-NOTFOUND-golden)', () {
    for (final brightness in Brightness.values) {
      final mode = brightness.name;
      testWidgets(
        'T-171-NOTFOUND-golden: ko 280×800 $mode = 채택 mockup byte 동일',
        (tester) async {
          tester.view.devicePixelRatio = kGoldenDpr;
          tester.view.physicalSize =
              const Size(_goldenWidth, kGoldenHeight) * kGoldenDpr;
          addTearDown(tester.view.reset);

          await tester.pumpWidget(
            MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: goldenTheme(brightness, 'ko'),
              locale: const Locale('ko'),
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              home: const NotFoundScreen(),
            ),
          );
          await settleGoldenAssets(tester);

          expect(tester.takeException(), isNull);
          final ko = lookupAppLocalizations(const Locale('ko'));
          expect(find.text(ko.errorNotFoundGoHomeCta), findsOneWidget);

          await expectLater(
            find.byType(MaterialApp),
            matchesGoldenFile('goldens/not_found_171_ko_280_$mode.png'),
          );
        },
      );
    }
  });
}
