// Phase 17.1 D-18 — 404 전용 화면 테스트 (app_router_test.dart 에서 이전).
//
// 라우터 배선(errorBuilder → NotFoundScreen)은 app_router_test.dart 의
// T-171-ROUTER-01 이 잠그고, 이 파일은 404 본문(locale · 280dp · 가로 모드 ·
// a11y · 소스 가드)을 맡는다.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_starter_kit/core/theme/app_theme.dart';
import 'package:flutter_starter_kit/core/theme/app_typography.dart';
import 'package:flutter_starter_kit/features/not_found/presentation/not_found_screen.dart';
import 'package:flutter_starter_kit/l10n/generated/app_localizations.dart';

import '../../helpers/source_text.dart';

/// 404 [NotFoundScreen] 본문을 지정한 [locale] 로 pump 한다.
///
/// GoRouter 전체 스택 없이 errorBuilder 의 본문 위젯만 직접 검증한다.
/// [theme] 를 생략하면 라이트 테마다.
Future<void> _pumpNotFound(
  WidgetTester tester, {
  required Locale locale,
  ThemeData? theme,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: theme ?? AppTheme.light(),
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: const NotFoundScreen(),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('NotFoundScreen 본문 (errorBuilder 에서 이전)', () {
    testWidgets(
      'T-171-NOTFOUND-01: en 로케일에서 l10n 제목/본문/CTA + error_outline 렌더',
      (tester) async {
        await _pumpNotFound(tester, locale: const Locale('en'));

        // AppBar title 과 body title 두 곳에 동일 텍스트가 노출될 수 있다.
        expect(find.text('Page not found'), findsAtLeastNWidgets(1));
        expect(
          find.text('The page you requested does not exist.'),
          findsOneWidget,
        );
        expect(find.text('Go home'), findsOneWidget);
        expect(find.byIcon(Icons.error_outline), findsOneWidget);
        expect(find.byType(FilledButton), findsOneWidget);
        expect(find.widgetWithIcon(FilledButton, Icons.home), findsOneWidget);
      },
    );

    testWidgets('T-171-NOTFOUND-02: ko 로케일에서 한글 l10n 제목/본문/CTA 렌더', (
      tester,
    ) async {
      await _pumpNotFound(tester, locale: const Locale('ko'));

      expect(find.text('페이지를 찾을 수 없습니다'), findsAtLeastNWidgets(1));
      expect(find.text('요청하신 페이지가 존재하지 않습니다.'), findsOneWidget);
      expect(find.text('홈으로'), findsOneWidget);
      expect(find.byIcon(Icons.error_outline), findsOneWidget);
      expect(find.byType(FilledButton), findsOneWidget);
    });

    testWidgets(
      'T-171-NOTFOUND-03 (IN-01): AppTypography extension override 를 따라간다 (drift 차단)',
      (tester) async {
        // 회귀 대상: `context.textTheme` 은 AppTypography extension override 를
        // 반영하지 않으므로, 사용자가 ThemeData 를 교체하면 404 화면만 나머지
        // 화면과 다르게 drift 한다 (저장소 dominant 규약은 context.appTypography).
        const overrideTitle = TextStyle(fontSize: 29, letterSpacing: 7);
        const overrideBody = TextStyle(fontSize: 17, wordSpacing: 5);
        final base = AppTheme.light();

        await tester.pumpWidget(
          MaterialApp(
            // AppTypography extension 만 교체한다 (나머지 토큰은 ThemeX
            // 접근자의 폴백이 커버하므로 본 검증에 영향이 없다).
            theme: base.copyWith(
              extensions: [
                AppTypography.empty.copyWith(
                  titleLarge: overrideTitle,
                  bodyMedium: overrideBody,
                ),
              ],
            ),
            locale: const Locale('en'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: const NotFoundScreen(),
          ),
        );
        await tester.pumpAndSettle();

        final title = tester.widget<Text>(
          find.descendant(
            of: find.byType(Column),
            matching: find.text('Page not found'),
          ),
        );
        expect(
          title.style?.fontSize,
          29,
          reason: '제목은 AppTypography override 의 titleLarge 를 따라야 한다',
        );
        expect(title.style?.letterSpacing, 7);

        final body = tester.widget<Text>(
          find.text('The page you requested does not exist.'),
        );
        expect(
          body.style?.fontSize,
          17,
          reason: '본문은 AppTypography override 의 bodyMedium 을 따라야 한다',
        );
        expect(body.style?.wordSpacing, 5);
        expect(
          body.style?.color,
          base.colorScheme.onSurfaceVariant,
          reason: 'copyWith 로 얹는 색 토큰은 유지되어야 한다',
        );

        final icon = tester.widget<Icon>(find.byIcon(Icons.error_outline));
        expect(icon.size, 64, reason: '명명 상수 _notFoundIconSize 값 고정');
      },
    );
  });

  group('404 화면 가로 모드 (Phase 3 D-09 · quick 261003-0fp)', () {
    for (final size in _landscapeSizes) {
      for (final locale in _sweepLocales) {
        final label = '${_formatSize(size)} · ${locale.languageCode}';

        testWidgets(
          'T-171-NOTFOUND-04 (NF $label): 404 넘침 0 · 홈으로 도달 · 261003-0fp',
          (tester) async {
            _setLogicalViewport(tester, size);
            await _pumpNotFound(tester, locale: locale);
            expect(tester.takeException(), isNull, reason: '$label 404');

            final goHome = find.widgetWithText(
              FilledButton,
              lookupAppLocalizations(locale).errorNotFoundGoHomeCta,
            );
            await tester.ensureVisible(goHome);
            await tester.pumpAndSettle();
            expect(
              goHome.hitTestable(),
              findsOneWidget,
              reason: '$label 홈으로 도달',
            );
            expect(tester.takeException(), isNull, reason: '$label 마지막');
          },
        );
      }
    }

    testWidgets(
      'T-171-NOTFOUND-05 (P 360x800 · ko): 404 세로 rect 고정 · 261003-0fp',
      (tester) async {
        _setLogicalViewport(tester, _portraitSize);
        await _pumpNotFound(tester, locale: const Locale('ko'));
        expect(tester.takeException(), isNull);

        final l10n = lookupAppLocalizations(const Locale('ko'));
        final icon = find.byIcon(Icons.error_outline);
        final actual = <Rect>[
          tester.getRect(
            find.ancestor(of: icon, matching: find.byType(Column)).first,
          ),
          tester.getRect(icon),
          tester.getRect(find.text(l10n.errorNotFoundBody)),
          tester.getRect(find.byType(FilledButton)),
        ];
        const expected = _portraitNotFoundRects;
        expect(actual.length, expected.length);
        for (var i = 0; i < expected.length; i++) {
          _expectRectNear(actual[i], expected[i], reason: '#$i');
        }
      },
    );
  });

  // UI-SPEC §UI Considerations E6 (long-text) — 지원 최소 폭 280dp 세로에서도
  // 제목 · 본문이 가운데 정렬로 줄바꿈되고 넘침 없이 「홈으로」 에 닿는다.
  group('Phase 17.1 404 280dp 세로 (UI-SPEC E6)', () {
    for (final locale in _sweepLocales) {
      testWidgets(
        'T-171-NOTFOUND-06 (280x800 · ${locale.languageCode}): 넘침 0 · 홈으로 도달',
        (tester) async {
          _setLogicalViewport(tester, _minWidthPortraitSize);
          await _pumpNotFound(tester, locale: locale);
          expect(tester.takeException(), isNull);

          final goHome = find.widgetWithText(
            FilledButton,
            lookupAppLocalizations(locale).errorNotFoundGoHomeCta,
          );
          await tester.ensureVisible(goHome);
          await tester.pumpAndSettle();
          expect(goHome.hitTestable(), findsOneWidget);
          expect(tester.takeException(), isNull);
        },
      );
    }
  });

  // UI-SPEC §Semantics — 404 = androidTapTarget · labeledTapTarget ·
  // textContrast 전부 PASS (ko 280 light · dark).
  group('Phase 17.1 404 a11y guideline', () {
    for (final brightness in Brightness.values) {
      testWidgets(
        'T-171-NOTFOUND-a11y (ko 280 · ${brightness.name}): tap target · 대비',
        (tester) async {
          _setLogicalViewport(tester, _minWidthPortraitSize);
          final handle = tester.ensureSemantics();
          await _pumpNotFound(
            tester,
            locale: const Locale('ko'),
            theme: brightness == Brightness.light
                ? AppTheme.light()
                : AppTheme.dark(),
          );
          await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
          await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
          await expectLater(tester, meetsGuideline(textContrastGuideline));
          handle.dispose();
        },
      );
    }
  });

  // D-18 · T-17.1-03 — TODO · 임시 함수가 라우터에서 사라졌고, 404 화면은
  // 요청 경로 · 쿼리(PII 가능)를 받지도 그리지도 않는다. 주석을 걷어낸 코드만
  // 센다 — 부재 단언 전에 같은 문자열에서 양성 대조를 먼저 세운다.
  group('Phase 17.1 404 소스 가드', () {
    test('T-171-NOTFOUND-src: 라우터 TODO · 임시 함수 0 · 404 화면 state 미사용', () {
      final router = stripSlashComments(
        readTrackedFile('lib/core/router/app_router.dart'),
      );
      expect(
        countOccurrences(router, 'NotFoundScreen'),
        greaterThanOrEqualTo(1),
        reason: '양성 대조 — 라우터가 전용 404 화면을 쓴다',
      );
      expect(countOccurrences(router, 'TODO'), 0);
      expect(countOccurrences(router, '.planning/todos/pending/2026-09-09'), 0);
      expect(countOccurrences(router, 'buildNotFoundScreen'), 0);

      final screen = stripSlashComments(
        readTrackedFile(
          'lib/features/not_found/presentation/not_found_screen.dart',
        ),
      );
      expect(
        countOccurrences(screen, 'NotFoundScreen'),
        greaterThanOrEqualTo(1),
        reason: '양성 대조 — 위젯 파일을 읽었다',
      );
      expect(countOccurrences(screen, 'GoRouterState'), 0);
      expect(countOccurrences(screen, 'state.uri'), 0);
    });
  });
}

/// 가로 모드 점검 크기 (logical px).
///
/// - 780x360: SM-S942N 가로 실측 w780dp h360dp.
/// - 560x280: 지원 최소 폭 280dp 의 가로 — 최악.
const _landscapeSizes = <Size>[Size(780, 360), Size(560, 280)];

/// 세로 rect 고정 가드(P) 크기 — 일반 세로 폰.
const _portraitSize = Size(360, 800);

/// 지원 최소 폭 세로 크기 — 280dp (golden 과 같은 높이 800).
const _minWidthPortraitSize = Size(280, 800);

/// 점검 언어 — ko 먼저(R2), en, ja.
const _sweepLocales = <Locale>[Locale('ko'), Locale('en'), Locale('ja')];

/// 테스트 view 를 logical [size] 로 맞춘다 (DPR 1.0 · pump 전에 호출).
///
/// `setSurfaceSize` 는 MediaQuery 를 갱신하지 않으므로 쓰지 않는다
/// (quick 260929-pze 선례).
void _setLogicalViewport(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

/// [size] 를 테스트 이름용 `WxH` 문자열로 만든다.
String _formatSize(Size size) => '${size.width.toInt()}x${size.height.toInt()}';

/// [actual] 의 네 변이 [expected] 와 ±0.5 안인지 단언한다.
void _expectRectNear(Rect actual, Rect expected, {required String reason}) {
  expect(actual.left, closeTo(expected.left, 0.5), reason: '$reason left');
  expect(actual.top, closeTo(expected.top, 0.5), reason: '$reason top');
  expect(actual.right, closeTo(expected.right, 0.5), reason: '$reason right');
  expect(
    actual.bottom,
    closeTo(expected.bottom, 0.5),
    reason: '$reason bottom',
  );
}

/// 360x800 · ko 404 본문의 수정 전 rect — 본문 Column · 아이콘 · 안내 문구 ·
/// 「홈으로」 버튼 (quick 261003-0fp 가 lib 수정 전 트리에서 실측).
const _portraitNotFoundRects = <Rect>[
  Rect.fromLTRB(26, 324, 334, 532),
  Rect.fromLTRB(148, 324, 212, 388),
  Rect.fromLTRB(37.5, 440, 322.5, 460),
  Rect.fromLTRB(125.9, 484, 234.1, 532),
];
