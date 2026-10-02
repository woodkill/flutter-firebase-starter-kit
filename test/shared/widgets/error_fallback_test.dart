import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_starter_kit/core/error/error_widget_builder.dart';
import 'package:flutter_starter_kit/core/theme/app_theme.dart';
import 'package:flutter_starter_kit/l10n/generated/app_localizations.dart';
import 'package:flutter_starter_kit/shared/widgets/error_fallback.dart';

import '../../features/settings/presentation/settings_golden_harness.dart';
import '../../helpers/source_text.dart';

/// [width]×[height] logical viewport 를 DPR 1 로 주입한다.
void setViewport(WidgetTester tester, double width, double height) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = Size(width, height);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
}

/// [home] 을 [locale] · [theme](기본 앱 라이트 테마) [MaterialApp] 안에 그린다.
Future<void> pumpLocalized(
  WidgetTester tester,
  Widget home, {
  Locale locale = const Locale('ko'),
  ThemeData? theme,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: theme ?? AppTheme.light(),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: locale,
      home: home,
    ),
  );
  await tester.pumpAndSettle();
}

/// 버튼 계열 위젯(ElevatedButton · TextButton · OutlinedButton · FilledButton
/// · IconButton) finder — 대체 화면에는 재시도 버튼이 없어야 한다.
Finder findAnyButton() => find.byWidgetPredicate(
  (widget) => widget is ButtonStyleButton || widget is IconButton,
);

/// [paragraph] 가 현재 너비에서 실제로 몇 줄로 그려지는지 센다.
///
/// [RenderParagraph] 에는 줄 metrics API 가 없어 같은 text · 제약으로
/// [TextPainter] 를 다시 layout 한다 (Phase 17 mockup harness 와 같은 방식).
int countParagraphLines(RenderParagraph paragraph) {
  final painter = TextPainter(
    text: paragraph.text,
    textAlign: paragraph.textAlign,
    textDirection: paragraph.textDirection,
    textScaler: paragraph.textScaler,
    locale: paragraph.locale,
    strutStyle: paragraph.strutStyle,
    textWidthBasis: paragraph.textWidthBasis,
    textHeightBehavior: paragraph.textHeightBehavior,
    maxLines: paragraph.maxLines,
  )..layout(maxWidth: paragraph.constraints.maxWidth);
  final lines = painter.computeLineMetrics().length;
  painter.dispose();
  return lines;
}

void main() {
  // ja 줄바꿈 측정(T-17-FALLBACK-06)은 실제 글꼴 폭이 필요하다 — golden 과 같은
  // production 폰트 + CJK subset 을 등록한다.
  setUpAll(loadGoldenFonts);

  group('Phase 17 깨진 화면 대체 (T-17-FALLBACK)', () {
    testWidgets(
      'T-17-FALLBACK-01 관통: 빌드 예외 → buildReleaseErrorWidget → 기록 1회 + ko 문구 · 버튼 0',
      (tester) async {
        setViewport(tester, 280, 800);
        final details = FlutterErrorDetails(
          exception: StateError('secret-internal-detail'),
          stack: StackTrace.current,
        );
        final recorded = <FlutterErrorDetails>[];

        await pumpLocalized(
          tester,
          Builder(
            builder: (_) =>
                buildReleaseErrorWidget(details, onBuildError: recorded.add),
          ),
        );

        final ko = lookupAppLocalizations(const Locale('ko'));
        expect(tester.takeException(), isNull);
        expect(find.byType(ErrorFallback), findsOneWidget);
        expect(find.text(ko.errorWidgetFallbackTitle), findsOneWidget);
        expect(find.text(ko.errorWidgetFallbackBody), findsOneWidget);
        // 기록은 그 details 그대로 정확히 1회.
        expect(recorded, hasLength(1));
        expect(identical(recorded.single, details), isTrue);
        // 재시도 버튼 없음 · 예외 문자열 노출 없음 (T-17-24).
        expect(findAnyButton(), findsNothing);
        expect(find.textContaining('secret-internal-detail'), findsNothing);
        expect(find.textContaining('StateError'), findsNothing);
        expect(kErrorWidgetBuildReason, 'error_widget_build');
      },
    );

    testWidgets('T-17-FALLBACK-07 재빌드마다 새 예외로 builder 가 다시 불려도 non-fatal 기록은 '
        '세션당 1회 · 대체 화면은 매번 (리뷰 IN-14)', (tester) async {
      final recorded = <FlutterErrorDetails>[];
      final builder = createReleaseErrorWidgetBuilder(
        onBuildError: recorded.add,
      );
      // framework 는 재빌드마다 build() 를 새로 실행해 새 예외 · 새 details
      // 를 만든다 — 같은 객체가 아니다.
      final first = FlutterErrorDetails(exception: StateError('build 1'));
      final second = FlutterErrorDetails(exception: StateError('build 2'));

      for (final details in [first, second, first]) {
        await pumpLocalized(tester, Builder(builder: (_) => builder(details)));
        expect(find.byType(ErrorFallback), findsOneWidget);
      }

      expect(recorded, hasLength(1));
      expect(identical(recorded.single, first), isTrue);

      // builder 를 새로 만들면(새 세션) 다시 1회 기록한다.
      final nextSession = createReleaseErrorWidgetBuilder(
        onBuildError: recorded.add,
      );
      await pumpLocalized(tester, Builder(builder: (_) => nextSession(second)));
      expect(recorded, hasLength(2));
    });

    testWidgets('T-17-FALLBACK-07 첫 기록이 throw 해도 대체 화면은 그려지고 다시 시도하지 않는다', (
      tester,
    ) async {
      var calls = 0;
      final builder = createReleaseErrorWidgetBuilder(
        onBuildError: (_) {
          calls++;
          throw StateError('record failed');
        },
      );
      final details = FlutterErrorDetails(exception: StateError('build'));

      for (var i = 0; i < 2; i++) {
        await pumpLocalized(tester, Builder(builder: (_) => builder(details)));
        expect(tester.takeException(), isNull);
        expect(find.byType(ErrorFallback), findsOneWidget);
      }
      expect(calls, 1);
    });

    test(
      'T-17-FALLBACK-02 소스 계약: bootstrap 이 !kDebugMode 에서만 ErrorWidget.builder 를 설치하고 기존 fatal 경로를 유지한다',
      () {
        final source = stripBlockComments(
          stripSlashComments(readTrackedFile('lib/core/bootstrap.dart')),
        );

        // 양성 대조 — 같은 API 가 기존 fatal 경로를 실제로 센다.
        expect(countOccurrences(source, 'recordFlutterFatalError'), 1);

        expect(countOccurrences(source, 'ErrorWidget.builder ='), 1);
        // 설치하는 builder 는 세션당 1회 기록 게이트를 거친다 (리뷰 IN-14).
        expect(
          countOccurrences(
            source,
            'ErrorWidget.builder = createReleaseErrorWidgetBuilder(',
          ),
          1,
        );
        expect(countOccurrences(source, 'kErrorWidgetBuildReason'), 1);
        expect(
          countOccurrences(source, 'fatal: false'),
          greaterThanOrEqualTo(1),
        );

        // builder 대입 직전의 조건이 `!kDebugMode` 여야 한다 — debug 는 SDK
        // 기본 빨간 화면을 유지한다 (D-22).
        final builderAt = source.indexOf('ErrorWidget.builder =');
        final guardAt = source.lastIndexOf('if (!kDebugMode) {', builderAt);
        expect(guardAt, greaterThanOrEqualTo(0));
        final between = source.substring(guardAt, builderAt);
        expect(between.contains('}'), isFalse);

        // 설치는 Firebase 초기화 분기 밖 · runApp 앞이다.
        final runAppAt = source.indexOf('runApp(');
        expect(builderAt, lessThan(runAppAt));
        final initCatchAt = source.indexOf(
          "debugPrint('bootstrap 초기화 실패 (Firebase 비활성)",
        );
        expect(initCatchAt, greaterThanOrEqualTo(0));
        expect(builderAt, greaterThan(initCatchAt));
      },
    );

    testWidgets(
      'T-17-FALLBACK-04 E5 overflow: 200 dp 미만 자리는 아이콘만 · 넓은 자리는 overflow 0',
      (tester) async {
        final ko = lookupAppLocalizations(const Locale('ko'));
        final compactLabel =
            '${ko.errorWidgetFallbackTitle}. ${ko.errorWidgetFallbackBody}';

        // (a) 카드 1장 크기(72 dp) · 좁은 너비(150 dp) 자리 → 아이콘 띠.
        setViewport(tester, 280, 800);
        await pumpLocalized(
          tester,
          Scaffold(
            body: ListView(
              padding: const EdgeInsets.all(16),
              children: const [
                SizedBox(
                  key: ValueKey('card-slot'),
                  height: 72,
                  child: ErrorFallback(),
                ),
                SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerLeft,
                  child: SizedBox(
                    key: ValueKey('narrow-slot'),
                    width: 150,
                    height: 300,
                    child: ErrorFallback(),
                  ),
                ),
              ],
            ),
          ),
        );
        expect(tester.takeException(), isNull);
        for (final slot in ['card-slot', 'narrow-slot']) {
          final fallback = find.descendant(
            of: find.byKey(ValueKey(slot)),
            matching: find.byType(ErrorFallback),
          );
          expect(
            find.descendant(of: fallback, matching: find.byType(Text)),
            findsNothing,
            reason: '$slot 은 compact — 제목 · 본문 Text 0',
          );
          final icon = tester.widget<Icon>(
            find.descendant(of: fallback, matching: find.byType(Icon)),
          );
          expect(icon.icon, Icons.error_outline);
          expect(icon.semanticLabel, compactLabel);
        }
        expect(
          tester.getSize(find.byKey(const ValueKey('card-slot'))).height,
          72,
        );

        // (b) 넓은 자리 2종(가로 780×360 · 세로 280×800) → full · overflow 0.
        for (final size in const [Size(780, 360), Size(280, 800)]) {
          setViewport(tester, size.width, size.height);
          await pumpLocalized(tester, const ErrorFallback());
          expect(
            tester.takeException(),
            isNull,
            reason: '${size.width}×${size.height} overflow 0',
          );
          expect(find.text(ko.errorWidgetFallbackTitle), findsOneWidget);
          expect(find.text(ko.errorWidgetFallbackBody), findsOneWidget);
          expect(find.byType(SingleChildScrollView), findsOneWidget);
          expect(findAnyButton(), findsNothing);
        }
      },
    );

    testWidgets(
      'T-17-FALLBACK-05 E5 error backstop: MaterialApp 없이 View 루트에 바로 그려도 throw 0 · 기기 locale 문구',
      (tester) async {
        addTearDown(tester.platformDispatcher.clearLocaleTestValue);

        // 미지원 기기 locale(fr) → en 문구.
        tester.platformDispatcher.localeTestValue = const Locale('fr', 'FR');
        await tester.pumpWidget(const ErrorFallback());
        await tester.pump();
        expect(tester.takeException(), isNull);
        final en = lookupAppLocalizations(const Locale('en'));
        expect(find.text(en.errorWidgetFallbackTitle), findsOneWidget);
        expect(find.text(en.errorWidgetFallbackBody), findsOneWidget);
        // Directionality 부재 → ltr 로 감쌌다.
        expect(
          tester
              .widget<Directionality>(
                find
                    .ancestor(
                      of: find.text(en.errorWidgetFallbackTitle),
                      matching: find.byType(Directionality),
                    )
                    .first,
              )
              .textDirection,
          TextDirection.ltr,
        );

        // 지원 기기 locale(ja_JP) → ja 문구.
        tester.platformDispatcher.localeTestValue = const Locale('ja', 'JP');
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpWidget(const ErrorFallback());
        await tester.pump();
        expect(tester.takeException(), isNull);
        final ja = lookupAppLocalizations(const Locale('ja'));
        expect(find.text(ja.errorWidgetFallbackTitle), findsOneWidget);
        expect(find.text(ja.errorWidgetFallbackBody), findsOneWidget);

        // 판정 함수 양성 · 음성 대조.
        expect(
          resolveErrorFallbackLocale(const Locale('ko', 'KR')),
          const Locale('ko'),
        );
        expect(
          resolveErrorFallbackLocale(const Locale('fr', 'FR')),
          const Locale('en'),
        );
      },
    );

    testWidgets(
      'T-17-FALLBACK-06 E5 long-text: ja 280 dp 에서 본문이 2줄 이상 줄바꿈 · maxLines 제한 없음',
      (tester) async {
        setViewport(tester, 280, 800);
        await pumpLocalized(
          tester,
          const ErrorFallback(),
          locale: const Locale('ja'),
          theme: goldenTheme(Brightness.light, 'ja'),
        );
        expect(tester.takeException(), isNull);

        final ja = lookupAppLocalizations(const Locale('ja'));
        for (final copy in [
          ja.errorWidgetFallbackTitle,
          ja.errorWidgetFallbackBody,
        ]) {
          final text = tester.widget<Text>(find.text(copy));
          expect(text.maxLines, isNull);
          expect(text.overflow, isNull);
          expect(text.textAlign, TextAlign.center);
        }
        final body = tester.renderObject<RenderParagraph>(
          find.descendant(
            of: find.text(ja.errorWidgetFallbackBody),
            matching: find.byType(RichText),
          ),
        );
        expect(countParagraphLines(body), greaterThanOrEqualTo(2));
        expect(body.didExceedMaxLines, isFalse);
      },
    );
  });
}
