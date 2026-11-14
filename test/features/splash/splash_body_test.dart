// 스플래시 로고 아래 내용 시험 — 내 앱의 파일이다. 로고 아래 내용
// (`buildSplashBody` · `lib/features/splash/presentation/splash_body.dart`)을
// 바꾸면 이 시험도 함께 고친다. 킷은 이 파일을 고치지 않는다.
// 안내: `docs/guide.md` 「스플래시 바꾸기」.
//
// - T-26-BODY-01: 준비 문구 1개 · 진행 표시 1개
// - T-26-BODY-02: 진행 표시 = `SmallProgressIndicator` 1개 · 지름 = 아이콘 토큰
//   md · 선 굵기 2 (옛 T-24-LIT-04 를 옮긴 것)
// - T-26-BODY-03: 실패 신호(`hasFailure`)가 오면 진행 표시를 숨기고 문구는 남긴다
// - T-26-BODY-04: 기본 스플래시 틀(`SplashFrame`)의 가로 화면 780x360 ·
//   560x280 × ko · en · ja 에서 예외 0 · 준비 문구가 화면 안
//
// 문구 · 크기 기대값은 l10n 조회 · 테마 토큰에서 읽는다 — ARB 문구를 바꿔도 같은
// 뜻으로 남는다.

import 'package:flutter/material.dart';
import 'package:flutter_starter_kit/core/theme/app_icon_sizes.dart';
import 'package:flutter_starter_kit/core/theme/app_theme.dart';
import 'package:flutter_starter_kit/features/splash/presentation/splash_body.dart';
import 'package:flutter_starter_kit/features/splash/presentation/splash_frame.dart';
import 'package:flutter_starter_kit/l10n/generated/app_localizations.dart';
import 'package:flutter_starter_kit/shared/widgets/small_progress_indicator.dart';
import 'package:flutter_test/flutter_test.dart';

/// 시험 문구 언어 — 영어.
const Locale _en = Locale('en');

/// 가로 화면 점검 크기 (logical px) — 가로 폰 실측 780x360 · 지원 최소 폭 280 의
/// 가로 560x280.
const List<Size> _landscapeSizes = <Size>[Size(780, 360), Size(560, 280)];

/// 가로 화면 점검 언어 — ko · en · ja.
const List<Locale> _sweepLocales = <Locale>[
  Locale('ko'),
  Locale('en'),
  Locale('ja'),
];

/// [home] 을 라이트 테마 · [locale] 앱으로 띄우고 첫 프레임만 그린다.
///
/// 진행 표시가 끝나지 않으므로 `pumpAndSettle` 을 쓰지 않는다.
Future<void> _pumpHome(
  WidgetTester tester, {
  required Widget home,
  Locale locale = _en,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light(),
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: home,
    ),
  );
  await tester.pump();
}

/// 로고 아래 내용(`buildSplashBody`)만 Scaffold 본문으로 띄운다.
Future<void> _pumpBody(WidgetTester tester, {required bool hasFailure}) =>
    _pumpHome(
      tester,
      home: Scaffold(
        body: Builder(
          builder: (context) =>
              buildSplashBody(context, hasFailure: hasFailure),
        ),
      ),
    );

/// 테스트 view 를 logical [size] 로 맞추고 시험이 끝나면 되돌린다.
void _setLogicalViewport(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void main() {
  group('스플래시 로고 아래 내용 (T-26-BODY)', () {
    testWidgets('T-26-BODY-01: 준비 문구 1개 · 진행 표시 1개를 그린다', (tester) async {
      await _pumpBody(tester, hasFailure: false);

      expect(
        find.text(lookupAppLocalizations(_en).splashPreparing),
        findsOneWidget,
      );
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('T-26-BODY-02: 진행 표시는 SmallProgressIndicator 하나 · '
        '지름 = 아이콘 토큰 md · 선 굵기 2', (tester) async {
      await _pumpBody(tester, hasFailure: false);

      final indicator = find.byType(SmallProgressIndicator);
      expect(indicator, findsOneWidget);
      final double expectedDimension = AppTheme.light()
          .extension<AppIconSizes>()!
          .md;
      expect(
        tester.widget<SmallProgressIndicator>(indicator).dimension,
        expectedDimension,
      );
      expect(tester.getSize(indicator), Size.square(expectedDimension));
      final spinner = tester.widget<CircularProgressIndicator>(
        find.descendant(
          of: indicator,
          matching: find.byType(CircularProgressIndicator),
        ),
      );
      expect(spinner.strokeWidth, 2);
    });

    testWidgets('T-26-BODY-03: 실패 신호가 오면 진행 표시를 숨기고 문구는 남긴다', (tester) async {
      await _pumpBody(tester, hasFailure: true);

      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(
        find.text(lookupAppLocalizations(_en).splashPreparing),
        findsOneWidget,
      );
    });

    for (final size in _landscapeSizes) {
      for (final locale in _sweepLocales) {
        final label =
            '${size.width.toInt()}x${size.height.toInt()} · '
            '${locale.languageCode}';

        testWidgets('T-26-BODY-04: 기본 스플래시 틀 가로 화면($label) — '
            '예외 0 · 준비 문구가 화면 안', (tester) async {
          _setLogicalViewport(tester, size);
          await _pumpHome(
            tester,
            home: const SplashFrame(hasFailure: false),
            locale: locale,
          );

          expect(tester.takeException(), isNull, reason: '$label 예외');
          final preparing = find.text(
            lookupAppLocalizations(locale).splashPreparing,
          );
          expect(preparing, findsOneWidget, reason: '$label 준비 문구');
          expect(
            tester.getRect(preparing).bottom,
            lessThanOrEqualTo(size.height),
            reason: '$label 준비 문구가 화면 안',
          );
        });
      }
    }
  });
}
