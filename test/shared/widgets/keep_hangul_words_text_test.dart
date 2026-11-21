// 한국어 낱말 줄바꿈 감싸개 `KeepHangulWordsText` 의 성질 시험.
//
// 시험 ID: T-27-WRAP-01 넣는 자리 · T-27-WRAP-02 이음 문자 span 구조 ·
// T-27-WRAP-03 한글 없으면 Text 그대로 · T-27-WRAP-04 자간 축 픽셀 같음 ·
// T-27-WRAP-05 어절 안 줄바꿈 0 · T-27-WRAP-06 긴 덩어리 넘침 0 ·
// T-27-WRAP-07 ja · en 픽셀 같음 · T-27-WRAP-08 낭독 원문 ·
// T-27-WRAP-09 낭독 덮어쓰기 · T-27-WRAP-10 maxLines · 말줄임 ·
// T-27-WRAP-11 locale 무관 · T-27-WRAP-12 예외 범위 끝점 ·
// T-27-WRAP-13 한글 갈래 인자 전달 · T-27-WRAP-14 한글 없는 문구 낭독 덮어쓰기.
// T-27-WRAP-15 긴 덩어리 배율 · T-27-WRAP-16 긴 덩어리 뒤 어절(quick 261121-ep1 이 더함).
// 한글 음절 범위의 끝(힣 · 범위 바로 앞뒤 코드 포인트)은 넣는 자리 표본이 맡는다.
//
// 표본은 이 파일 안 리터럴 — 킷 문구에 기대지 않는다. 보이지 않는 문자는
// `String.fromCharCode` · `\u{…}` 이스케이프로만 적는다.

import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_starter_kit/core/theme/app_theme.dart';
import 'package:flutter_starter_kit/l10n/generated/app_localizations.dart';
import 'package:flutter_starter_kit/shared/widgets/keep_hangul_words_text.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../features/settings/presentation/settings_golden_harness.dart';

/// 이음 문자(U+2060 WORD JOINER).
final String _wj = String.fromCharCode(0x2060);

/// 한글 음절이 하나라도 있는지 보는 식.
final RegExp _hangul = RegExp('[가-힣]');

/// 글자 조각 [graphemes] 사이마다 이음 문자를 끼운 기대 문자열을 만든다.
String _joined(List<String> graphemes) => graphemes.join(_wj);

/// 넣는 자리 표본 — 키 = 원문 · 값 = 이음 문자를 끼운 기대 문자열.
final Map<String, String> _placementCases = <String, String>{
  // 덩어리 안 모든 글자 사이.
  'ID가': _joined(<String>['I', 'D', '가']),
  '8자 이상': '${_joined(<String>['8', '자'])} ${_joined(<String>['이', '상'])}',
  '연결(권한)도': _joined(<String>['연', '결', '(', '권', '한', ')', '도']),
  'Wi-Fi로': _joined(<String>['W', 'i', '-', 'F', 'i', '로']),
  '이메일/비밀번호': _joined(<String>['이', '메', '일', '/', '비', '밀', '번', '호']),
  'user.name@example.com(으)로': _joined('user.name@example.com(으)로'.split('')),
  // 가나 · CJK 문장부호 · 전각 괄호와 맞닿은 경계는 빠진다.
  '김철수さんの': '${_joined(<String>['김', '철', '수'])}さんの',
  'ようこそ、김철수さん！': 'ようこそ、${_joined(<String>['김', '철', '수'])}さん！',
  '김철수（キム）さん': '${_joined(<String>['김', '철', '수'])}（キム）さん',
  // 보충 평면 한자(U+20BB7)도 한자라 맞닿은 경계가 빠진다.
  '김\u{20BB7}田さん': '김\u{20BB7}田さん',
  // 띄어쓰기 · 줄바꿈 · 탭은 덩어리 경계다.
  '가나 다라\n마바\t사아':
      '${_joined(<String>['가', '나'])} ${_joined(<String>['다', '라'])}'
      '\n${_joined(<String>['마', '바'])}\t${_joined(<String>['사', '아'])}',
  // CRLF(한 글자) · CR 줄바꿈도 덩어리 경계라 앞 줄 끝 낱말은 묶이지 않는다.
  'Hello\r\n세계': 'Hello\r\n${_joined(<String>['세', '계'])}',
  'Hello\r세계': 'Hello\r${_joined(<String>['세', '계'])}',
  // ZWJ 이모지 · 결합 부호 안에는 넣지 않는다(글자 단위).
  '김\u{1F469}\u{200D}\u{1F4BB}님': _joined(<String>[
    '김',
    '\u{1F469}\u{200D}\u{1F4BB}',
    '님',
  ]),
  'Cafe\u{0301}로': _joined(<String>['C', 'a', 'f', 'e\u{0301}', '로']),
  // 한글이 없으면 그대로다.
  'Hello world': 'Hello world',
  // 한글 음절 범위(가 ~ 힣) 끝 — 힣은 범위 안, 범위 바로 앞 U+ABFF · 바로 뒤 U+D7A4 는 밖이다.
  'ID힣': _joined(<String>['I', 'D', '힣']),
  'ID\u{ABFF}': 'ID\u{ABFF}',
  'ID\u{D7A4}': 'ID\u{D7A4}',
};

/// 예외 범위 표 — (처음, 끝) 코드 포인트. 감싸개의 범위 목록과 같은 일곱 칸이다.
const List<(int, int)> _exceptionRanges = <(int, int)>[
  (0x3000, 0x303F),
  (0x3040, 0x30FF),
  (0x3400, 0x4DBF),
  (0x4E00, 0x9FFF),
  (0xF900, 0xFAFF),
  (0xFF01, 0xFF9F),
  (0x20000, 0x3FFFF),
];

/// [codePoint] 가 예외 범위 표 어느 한 칸에 드는지 본다.
bool _inExceptionRanges(int codePoint) => _exceptionRanges.any(
  (range) => codePoint >= range.$1 && codePoint <= range.$2,
);

/// 픽셀 캡처 대상 [RepaintBoundary] 의 key.
final GlobalKey _boundaryKey = GlobalKey();

/// [child] 를 앱 테마 · [locale] 로 폭 [width] 상자 안에 pump 한다.
Future<void> _pumpBox(
  WidgetTester tester,
  Widget child, {
  double width = 360,
  Locale locale = const Locale('ko'),
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light(),
      locale: locale,
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      home: Scaffold(
        body: Center(
          child: RepaintBoundary(
            key: _boundaryKey,
            child: ColoredBox(
              color: const Color(0xFFFFFFFF),
              child: SizedBox(width: width, child: child),
            ),
          ),
        ),
      ),
    ),
  );
}

/// 감싸개 아래 [RichText] 위젯을 찾는다.
RichText _richTextUnderWrapper(WidgetTester tester) {
  return tester.widget<RichText>(
    find.descendant(
      of: find.byType(KeepHangulWordsText),
      matching: find.byType(RichText),
    ),
  );
}

/// 감싸개 아래 [Text] 위젯을 찾는다.
Text _textUnderWrapper(WidgetTester tester) {
  return tester.widget<Text>(
    find.descendant(
      of: find.byType(KeepHangulWordsText),
      matching: find.byType(Text),
    ),
  );
}

/// 감싸개가 그린 글의 이음 문자 포함 평문.
String _plainUnderWrapper(WidgetTester tester) {
  return _richTextUnderWrapper(
    tester,
  ).text.toPlainText(includeSemanticsLabels: false);
}

/// 자리표시 문자(U+FFFC OBJECT REPLACEMENT CHARACTER).
final String _objectReplacement = String.fromCharCode(0xFFFC);

/// 픽셀 비교에 쓰는 글자 간격 — 테마 글자 스타일이 실제로 받는 값 전부.
const List<double> _letterSpacings = <double>[0, 0.1, 0.15, 0.25, 0.4, 0.5];

/// 낭독 · 말줄임 시험 문구.
const String _sentence = '탈퇴하기 전에 이 계정에 연결된 서비스의 앱 권한을 하나씩 해제합니다.';

/// 공백 없는 42음절 덩어리 — T-27-WRAP-15 · 16 표본(T-27-WRAP-06 지역 상수와 같은 글자).
const String _longChunk = '가나다라마바사아자차카타파하가나다라마바사아자차카타파하가나다라마바사아자차카타파하';

/// [base] 에 글자 간격 [letterSpacing] 과 글꼴 [font] 를 건 스타일을 만든다.
///
/// `Roboto` 는 한글 · 가나를 `MockCjkKR` 대체 글꼴로 그리는 사슬이다.
TextStyle _styleWithFont(TextStyle base, String font, double letterSpacing) {
  final style = base.copyWith(letterSpacing: letterSpacing);
  if (font == 'Roboto') {
    return style.copyWith(
      fontFamily: 'Roboto',
      fontFamilyFallback: const <String>['MockCjkKR'],
    );
  }
  return style.copyWith(fontFamily: font);
}

/// 테마 `bodyMedium` 에 [font] · [letterSpacing] 을 건 [text] 를 그린다.
///
/// [keep] 이 참이면 감싸개, 거짓이면 원문 [Text] 다.
Widget _styledText(
  String text, {
  required bool keep,
  required String font,
  required double letterSpacing,
  TextScaler? textScaler,
}) {
  return Builder(
    builder: (context) {
      final style = _styleWithFont(
        Theme.of(context).textTheme.bodyMedium!,
        font,
        letterSpacing,
      );
      return keep
          ? KeepHangulWordsText(text, style: style, textScaler: textScaler)
          : Text(text, style: style, textScaler: textScaler);
    },
  );
}

/// [_boundaryKey] 상자를 배율 3 으로 찍은 rawRgba 바이트와 상자 높이.
Future<({List<int> bytes, double height})> _capture(WidgetTester tester) async {
  final boundary =
      _boundaryKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  List<int>? bytes;
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 3);
    // 바이트 비교 형식을 rawRgba 로 못 박는다 — 기본값에 기대지 않는다.
    // ignore: avoid_redundant_argument_values
    final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    bytes = data?.buffer.asUint8List();
    image.dispose();
  });
  expect(bytes, isNotNull);
  return (bytes: bytes!, height: boundary.size.height);
}

/// 원문 [Text] 와 감싸개를 차례로 그려 두 캡처가 다르면 칸 설명을 돌려준다.
Future<String?> _compareCell(
  WidgetTester tester, {
  required Widget plain,
  required Widget keep,
  required String label,
  double width = 674,
  Locale locale = const Locale('ko'),
}) async {
  await _pumpBox(tester, plain, width: width, locale: locale);
  final base = await _capture(tester);
  await _pumpBox(tester, keep, width: width, locale: locale);
  final kept = await _capture(tester);
  if (base.height != kept.height) {
    return '$label 높이 ${base.height} → ${kept.height}';
  }
  if (!listEquals(base.bytes, kept.bytes)) {
    return '$label rawRgba 다름';
  }
  return null;
}

/// [richText] 를 폭 [width] 로 다시 배치해 줄 시작을 원문 offset 으로 돌려준다.
///
/// 이음 문자는 원문에 없으므로 그 앞 이음 문자 수만큼 offset 을 당긴다. 함께
/// 돌려주는 높이는 다시 배치한 문단 높이다(실제 문단과 대조용).
({List<int> starts, double height}) _lineStartsInOriginal(
  RichText richText,
  double width,
) {
  final painter = TextPainter(
    text: richText.text,
    textDirection: TextDirection.ltr,
    textAlign: richText.textAlign,
    textScaler: richText.textScaler,
    maxLines: richText.maxLines,
    locale: richText.locale,
    strutStyle: richText.strutStyle,
    textWidthBasis: richText.textWidthBasis,
    textHeightBehavior: richText.textHeightBehavior,
  )..layout(maxWidth: width);
  final plain = richText.text.toPlainText(includeSemanticsLabels: false);
  final starts = <int>{};
  for (var i = 0; i < plain.length; i++) {
    starts.add(painter.getLineBoundary(TextPosition(offset: i)).start);
  }
  final height = painter.height;
  painter.dispose();
  final original = <int>[
    for (final start in starts)
      plain.substring(0, start).replaceAll(_wj, '').length,
  ]..sort();
  return (starts: original, height: height);
}

/// [richText] 의 글자 스타일 · 배율로 [chunk] 한 줄 폭을 잰다.
double _chunkWidth(RichText richText, String chunk) {
  final painter = TextPainter(
    text: TextSpan(text: chunk, style: richText.text.style),
    textDirection: TextDirection.ltr,
    textScaler: richText.textScaler,
    locale: richText.locale,
  )..layout();
  final width = painter.width;
  painter.dispose();
  return width;
}

/// [_boundaryKey] 상자 안 [RichText] 위젯 하나.
RichText _richTextInBox(WidgetTester tester) {
  return tester.widget<RichText>(
    find.descendant(
      of: find.byKey(_boundaryKey),
      matching: find.byType(RichText),
    ),
  );
}

/// [_boundaryKey] 상자 안 [RenderParagraph] 하나.
RenderParagraph _paragraphInBox(WidgetTester tester) {
  return tester.renderObject<RenderParagraph>(
    find.descendant(
      of: find.byKey(_boundaryKey),
      matching: find.byType(RichText),
    ),
  );
}

/// 실제 그려진 문단 [paragraph] 의 글자 상자에서 가장 오른쪽 끝과 줄 수를 잰다.
///
/// [joined] 는 이음 문자를 포함한 평문이다. 공백 · 이음 문자는 뺀다 — 줄 끝 공백
/// 상자는 폭 밖으로 걸칠 수 있고, 그것은 글자 넘침이 아니다. 줄 수는
/// `BoxHeightStyle.max` 상자의 top 값 수다. 표본은 BMP 글자뿐이라 코드 유닛
/// 하나가 글자 하나다.
({double maxRight, int lineCount}) _measureGlyphBoxes(
  RenderParagraph paragraph,
  String joined,
) {
  var maxRight = double.negativeInfinity;
  final tops = <double>{};
  for (var i = 0; i < joined.length; i++) {
    final character = joined[i];
    if (character == ' ' || character == _wj) continue;
    final boxes = paragraph.getBoxesForSelection(
      TextSelection(baseOffset: i, extentOffset: i + 1),
      boxHeightStyle: ui.BoxHeightStyle.max,
    );
    for (final box in boxes) {
      if (box.right > maxRight) maxRight = box.right;
      tops.add(box.top);
    }
  }
  return (maxRight: maxRight, lineCount: tops.length);
}

void main() {
  setUpAll(loadGoldenFonts);

  group('KeepHangulWordsText 넣는 자리', () {
    testWidgets('T-27-WRAP-01 넣는 자리 — 표본마다 이음 문자를 끼운 평문이 기대와 같다', (
      tester,
    ) async {
      for (final entry in _placementCases.entries) {
        await _pumpBox(tester, KeepHangulWordsText(entry.key));
        expect(_plainUnderWrapper(tester), entry.value, reason: entry.key);
      }
    });

    testWidgets(
      'T-27-WRAP-02 구조 — 이음 문자마다 letterSpacing 0 만 가진 자식 span 하나 · 나머지 자식 style 은 null',
      (tester) async {
        // 한글이 들어도 모든 경계가 예외라 이음 문자가 0개인 표본은 뺀다.
        final hangulKeys = _placementCases.entries
            .where(
              (entry) =>
                  _hangul.hasMatch(entry.key) && entry.value.contains(_wj),
            )
            .map((entry) => entry.key);
        expect(hangulKeys, isNotEmpty);
        for (final key in hangulKeys) {
          await _pumpBox(tester, KeepHangulWordsText(key));
          final span = _textUnderWrapper(tester).textSpan;
          expect(span, isA<TextSpan>(), reason: key);
          final children = (span! as TextSpan).children ?? const <InlineSpan>[];
          var joinerCount = 0;
          var zeroSpacingSpans = 0;
          for (final child in children) {
            expect(child, isA<TextSpan>(), reason: key);
            final childSpan = child as TextSpan;
            final text = childSpan.text ?? '';
            joinerCount += _wj.allMatches(text).length;
            if (text == _wj) {
              if (childSpan.style == const TextStyle(letterSpacing: 0)) {
                zeroSpacingSpans++;
              }
            } else {
              expect(childSpan.style, isNull, reason: '$key · $text');
              expect(text.contains(_wj), isFalse, reason: '$key · $text');
            }
          }
          expect(joinerCount, greaterThanOrEqualTo(1), reason: key);
          expect(zeroSpacingSpans, joinerCount, reason: key);
        }
      },
    );

    testWidgets('T-27-WRAP-03 한글 없음 — 감싸개 아래가 넘긴 인자 그대로의 Text(data) 다', (
      tester,
    ) async {
      const style = TextStyle(fontSize: 13);
      const scaler = TextScaler.linear(1.1);
      for (final data in <String>['Hello world', 'ログインできません']) {
        await _pumpBox(
          tester,
          KeepHangulWordsText(
            data,
            style: style,
            textAlign: TextAlign.center,
            maxLines: 3,
            overflow: TextOverflow.fade,
            softWrap: true,
            textScaler: scaler,
          ),
        );
        expect(
          find.descendant(
            of: find.byType(KeepHangulWordsText),
            matching: find.byType(Text),
          ),
          findsOneWidget,
          reason: data,
        );
        final text = _textUnderWrapper(tester);
        expect(text.data, data, reason: data);
        expect(text.textSpan, isNull, reason: data);
        expect(text.style, style, reason: data);
        expect(text.textAlign, TextAlign.center, reason: data);
        expect(text.maxLines, 3, reason: data);
        expect(text.overflow, TextOverflow.fade, reason: data);
        expect(text.softWrap, isTrue, reason: data);
        expect(text.textScaler, scaler, reason: data);
        expect(text.semanticsLabel, isNull, reason: data);
      }
    });

    testWidgets('T-27-WRAP-11 locale 무관 — 같은 입력이 ko · en · ja 앱에서 같은 평문을 낸다', (
      tester,
    ) async {
      for (final data in _placementCases.keys) {
        final outputs = <String>{};
        for (final locale in const <Locale>[
          Locale('ko'),
          Locale('en'),
          Locale('ja'),
        ]) {
          await _pumpBox(tester, KeepHangulWordsText(data), locale: locale);
          outputs.add(_plainUnderWrapper(tester));
        }
        expect(outputs, hasLength(1), reason: data);
      }
    });

    testWidgets('T-27-WRAP-12 예외 범위 끝점 — 범위 안 끝점은 묶지 않고 범위 밖 이웃은 묶는다', (
      tester,
    ) async {
      var inside = 0;
      var outside = 0;
      for (final range in _exceptionRanges) {
        for (final codePoint in <int>[
          range.$1,
          range.$2,
          range.$1 - 1,
          range.$2 + 1,
        ]) {
          final mark = String.fromCharCode(codePoint);
          final data = '가$mark나';
          await _pumpBox(tester, KeepHangulWordsText(data));
          final label = 'U+${codePoint.toRadixString(16)}';
          // 이웃 범위 안으로 들어가는 끝점은 표 전체로 판정한다.
          if (_inExceptionRanges(codePoint)) {
            inside++;
            expect(_plainUnderWrapper(tester), data, reason: label);
          } else {
            outside++;
            expect(
              _plainUnderWrapper(tester),
              _joined(<String>['가', mark, '나']),
              reason: label,
            );
          }
        }
      }
      // 안 = 끝점 14 + 맞붙은 두 범위의 이웃 2 · 밖 = 나머지 12 — 표 한 칸이 빠져도 깨진다.
      expect(inside, 16);
      expect(outside, 12);
    });

    testWidgets('T-27-WRAP-13 한글 갈래 — 감싸개 아래가 넘긴 인자 그대로의 Text.rich 다', (
      tester,
    ) async {
      const style = TextStyle(fontSize: 13);
      const scaler = TextScaler.linear(1.1);
      await _pumpBox(
        tester,
        const KeepHangulWordsText(
          '가나 다라',
          style: style,
          textAlign: TextAlign.center,
          softWrap: false,
          overflow: TextOverflow.fade,
          maxLines: 3,
          textScaler: scaler,
        ),
      );
      final given = _textUnderWrapper(tester);
      expect(given.data, isNull);
      expect(given.textSpan, isNotNull);
      expect(given.style, style);
      expect(given.textAlign, TextAlign.center);
      expect(given.softWrap, isFalse);
      expect(given.overflow, TextOverflow.fade);
      expect(given.maxLines, 3);
      expect(given.textScaler, scaler);

      await _pumpBox(tester, const KeepHangulWordsText('가나 다라'));
      final bare = _textUnderWrapper(tester);
      expect(bare.data, isNull);
      expect(bare.textSpan, isNotNull);
      expect(bare.style, isNull);
      expect(bare.textAlign, isNull);
      expect(bare.softWrap, isNull);
      expect(bare.overflow, isNull);
      expect(bare.maxLines, isNull);
      expect(bare.textScaler, isNull);
    });

    testWidgets(
      'T-27-WRAP-14 한글 없는 문구 낭독 덮어쓰기 — semanticsLabel 을 주면 그 값을 읽는다',
      (tester) async {
        final handle = tester.ensureSemantics();
        for (final data in <String>['Hello world', 'ログインできません']) {
          await _pumpBox(
            tester,
            KeepHangulWordsText(data, semanticsLabel: '안내: $data'),
          );
          expect(
            _textUnderWrapper(tester).semanticsLabel,
            '안내: $data',
            reason: data,
          );
          expect(
            tester.getSemantics(find.byType(KeepHangulWordsText)).label,
            '안내: $data',
            reason: data,
          );
        }
        handle.dispose();
      },
    );
  });

  group('KeepHangulWordsText 렌더 · 낭독', () {
    testWidgets(
      'T-27-WRAP-04 자간 축 — 글꼴 3 × 자간 6 에서 한 줄 문구가 원문 Text 와 rawRgba · 높이 같다',
      (tester) async {
        tester.view.devicePixelRatio = 3;
        tester.view.physicalSize = const Size(700 * 3, 2400 * 3);
        addTearDown(tester.view.reset);
        // 공백 없이 한글만 든 줄과 라틴 낱말이 든 문구는 픽셀 비교 표본에서 뺀다 — 알려진 예외
        const samples = <String>[
          '앱을 종료한 뒤 다시 실행해 주세요.',
          '연결을 해제할까요? 다시 로그인해야 합니다.',
        ];
        const fonts = <String>['PretendardJP', 'MockCjkKR', 'Roboto'];
        final mismatches = <String>[];
        var cells = 0;
        for (final font in fonts) {
          for (final letterSpacing in _letterSpacings) {
            for (final sample in samples) {
              cells++;
              final mismatch = await _compareCell(
                tester,
                plain: _styledText(
                  sample,
                  keep: false,
                  font: font,
                  letterSpacing: letterSpacing,
                ),
                keep: _styledText(
                  sample,
                  keep: true,
                  font: font,
                  letterSpacing: letterSpacing,
                ),
                label: '$font · $letterSpacing · $sample',
              );
              if (mismatch != null) mismatches.add(mismatch);
            }
          }
        }
        expect(cells, fonts.length * _letterSpacings.length * samples.length);
        expect(mismatches, isEmpty);
      },
    );

    testWidgets('T-27-WRAP-05 어절 안 줄바꿈 0 — 덩어리가 한 줄에 들어가면 줄 시작은 모두 공백 바로 뒤', (
      tester,
    ) async {
      const samples = <String>[
        '버튼을 길게 누르세요',
        'ID가 8자 이상이어야 합니다',
        '연결(권한)도 함께 해제됩니다',
        '설정을 바꾸려면 먼저 계정에 다시 로그인한 뒤 화면 아래 저장 버튼을 누르세요.',
      ];
      for (final font in const <String>['PretendardJP', 'MockCjkKR']) {
        var checkedCombos = 0;
        var plainInsideStarts = 0;
        for (final width in const <double>[160, 200, 280, 360]) {
          for (final scale in const <double>[1, 1.3, 2]) {
            final scaler = TextScaler.linear(scale);
            for (final sample in samples) {
              final label = '$font · $width · $scale · $sample';
              await _pumpBox(
                tester,
                _styledText(
                  sample,
                  keep: true,
                  font: font,
                  letterSpacing: 0.25,
                  textScaler: scaler,
                ),
                width: width,
              );
              final keptText = _richTextInBox(tester);
              final widest = sample
                  .split(' ')
                  .map((chunk) => _chunkWidth(keptText, chunk))
                  .reduce((a, b) => a > b ? a : b);
              if (widest > width) continue;
              checkedCombos++;
              final kept = _lineStartsInOriginal(keptText, width);
              expect(
                kept.height,
                _paragraphInBox(tester).size.height,
                reason: '$label 다시 배치한 높이',
              );
              for (final start in kept.starts.where((s) => s > 0)) {
                expect(sample[start - 1], ' ', reason: '$label @ $start');
              }

              await _pumpBox(
                tester,
                _styledText(
                  sample,
                  keep: false,
                  font: font,
                  letterSpacing: 0.25,
                  textScaler: scaler,
                ),
                width: width,
              );
              final plain = _lineStartsInOriginal(
                _richTextInBox(tester),
                width,
              );
              plainInsideStarts += plain.starts
                  .where((s) => s > 0 && sample[s - 1] != ' ')
                  .length;
            }
          }
        }
        expect(checkedCombos, greaterThan(0), reason: font);
        expect(plainInsideStarts, greaterThanOrEqualTo(1), reason: font);
      }
    });

    testWidgets('T-27-WRAP-06 긴 덩어리 — 공백 없는 42음절이 폭 100 에서 예외 없이 2줄 이상', (
      tester,
    ) async {
      const chunk = '가나다라마바사아자차카타파하가나다라마바사아자차카타파하가나다라마바사아자차카타파하';
      expect(chunk.length, 42);
      await _pumpBox(tester, const KeepHangulWordsText('가'), width: 100);
      final lineHeight = tester
          .getSize(find.byType(KeepHangulWordsText))
          .height;
      await _pumpBox(tester, const KeepHangulWordsText(chunk), width: 100);
      expect(tester.takeException(), isNull);
      expect(
        tester.getSize(find.byType(KeepHangulWordsText)).height,
        greaterThanOrEqualTo(lineHeight * 2),
      );
    });

    testWidgets(
      'T-27-WRAP-15 긴 덩어리 배율 — 공백 없는 42음절이 폭 100 · 160 × 배율 1 · 1.3 · 2 에서 예외 없이 글자 상자 오른쪽 ≤ 폭 · 2줄 이상',
      (tester) async {
        var cells = 0;
        for (final font in const <String>['PretendardJP', 'MockCjkKR']) {
          for (final width in const <double>[100, 160]) {
            for (final scale in const <double>[1, 1.3, 2]) {
              final scaler = TextScaler.linear(scale);
              final label = '$font · $width · $scale';
              await _pumpBox(
                tester,
                _styledText(
                  _longChunk,
                  keep: true,
                  font: font,
                  letterSpacing: 0.25,
                  textScaler: scaler,
                ),
                width: width,
              );
              expect(tester.takeException(), isNull, reason: label);
              // 이음 문자 포함 평문(83자)으로 잰다 — 원문 42자만 재면 절반만 본다.
              final kept = _measureGlyphBoxes(
                _paragraphInBox(tester),
                _richTextInBox(
                  tester,
                ).text.toPlainText(includeSemanticsLabels: false),
              );
              expect(kept.maxRight, lessThanOrEqualTo(width), reason: label);
              expect(kept.lineCount, greaterThanOrEqualTo(2), reason: label);

              // 대조: softWrap 끔 감싸개는 한 줄로 폭을 넘는다 — 단언이 민감하다.
              await _pumpBox(
                tester,
                Builder(
                  builder: (context) => KeepHangulWordsText(
                    _longChunk,
                    style: _styleWithFont(
                      Theme.of(context).textTheme.bodyMedium!,
                      font,
                      0.25,
                    ),
                    textScaler: scaler,
                    softWrap: false,
                  ),
                ),
                width: width,
              );
              expect(tester.takeException(), isNull, reason: '$label 대조');
              final control = _measureGlyphBoxes(
                _paragraphInBox(tester),
                _richTextInBox(
                  tester,
                ).text.toPlainText(includeSemanticsLabels: false),
              );
              expect(control.maxRight, greaterThan(width), reason: '$label 대조');
              expect(control.lineCount, 1, reason: '$label 대조');
              cells++;
            }
          }
        }
        expect(cells, 12);
      },
    );

    testWidgets(
      'T-27-WRAP-16 긴 덩어리 뒤 어절 — 넓은 덩어리 뒤 어절은 한 줄에 들어가면 어절째 넘어가고 글자 상자는 폭 안',
      (tester) async {
        const sample = '$_longChunk 버튼을 길게 누르세요';
        final words = sample.substring(_longChunk.length + 1).split(' ');
        for (final font in const <String>['PretendardJP', 'MockCjkKR']) {
          var checkedCells = 0;
          var wrapperWordStarts = 0;
          var plainInsideStarts = 0;
          for (final width in const <double>[100, 160]) {
            for (final scale in const <double>[1, 1.3, 2]) {
              final scaler = TextScaler.linear(scale);
              final label = '$font · $width · $scale';
              await _pumpBox(
                tester,
                _styledText(
                  sample,
                  keep: true,
                  font: font,
                  letterSpacing: 0.25,
                  textScaler: scaler,
                ),
                width: width,
              );
              expect(tester.takeException(), isNull, reason: label);
              // 뒤 어절 가운데 하나라도 한 줄보다 넓으면 어절째 넘어갈 수 없어 뺀다.
              final keptText = _richTextInBox(tester);
              final widest = words
                  .map((word) => _chunkWidth(keptText, word))
                  .reduce((a, b) => a > b ? a : b);
              if (widest > width) continue;
              checkedCells++;
              final glyphs = _measureGlyphBoxes(
                _paragraphInBox(tester),
                keptText.text.toPlainText(includeSemanticsLabels: false),
              );
              expect(glyphs.maxRight, lessThanOrEqualTo(width), reason: label);
              // 넓은 덩어리 안(offset ≤ 42) 줄 시작 자리는 고정하지 않는다.
              final kept = _lineStartsInOriginal(keptText, width);
              final wordStarts = kept.starts.where(
                (start) => start > _longChunk.length,
              );
              for (final start in wordStarts) {
                expect(sample[start - 1], ' ', reason: '$label @ $start');
              }
              wrapperWordStarts += wordStarts.length;
              // 시험 화면 높이(600)에서 잘리기 전 칸만 오므로 건너뛰기 뒤에 둔다.
              expect(
                kept.height,
                _paragraphInBox(tester).size.height,
                reason: '$label 다시 배치한 높이',
              );

              // 원문 Text 대조: 뒤 어절 안에서 줄을 시작해 표본이 민감하다.
              await _pumpBox(
                tester,
                _styledText(
                  sample,
                  keep: false,
                  font: font,
                  letterSpacing: 0.25,
                  textScaler: scaler,
                ),
                width: width,
              );
              expect(tester.takeException(), isNull, reason: '$label 원문');
              plainInsideStarts +=
                  _lineStartsInOriginal(_richTextInBox(tester), width).starts
                      .where(
                        (s) => s > _longChunk.length && sample[s - 1] != ' ',
                      )
                      .length;
            }
          }
          expect(checkedCells, greaterThan(0), reason: font);
          expect(wrapperWordStarts, greaterThanOrEqualTo(1), reason: font);
          expect(plainInsideStarts, greaterThanOrEqualTo(1), reason: font);
        }
      },
    );

    testWidgets('T-27-WRAP-07 ja · en — 폭 280 에서 원문 Text 와 rawRgba · 높이 같다', (
      tester,
    ) async {
      const samples = <(Locale, String)>[
        (Locale('ja'), 'このアカウントに連携されたサービスのアプリ連携を一つずつ解除します。'),
        (
          Locale('en'),
          'Before deleting your account, disconnect each app linked to it one by one.',
        ),
      ];
      for (final (locale, sample) in samples) {
        final mismatch = await _compareCell(
          tester,
          plain: Text(sample),
          keep: KeepHangulWordsText(sample),
          label: sample,
          width: 280,
          locale: locale,
        );
        expect(mismatch, isNull);
      }
    });

    testWidgets(
      'T-27-WRAP-08 낭독 원문 — 감싸개 · ListTile · FilledButton 의 label 이 원문이고 이음 문자 · 자리표시 0',
      (tester) async {
        final handle = tester.ensureSemantics();
        final invisible = <String>[_wj, _objectReplacement];

        await _pumpBox(tester, const KeepHangulWordsText(_sentence));
        final single = tester
            .getSemantics(find.byType(KeepHangulWordsText))
            .label;
        expect(single, _sentence);

        await _pumpBox(
          tester,
          const ListTile(
            title: KeepHangulWordsText(_sentence),
            subtitle: KeepHangulWordsText(_sentence),
          ),
        );
        final tile = tester.getSemantics(find.byType(ListTile)).label;
        expect(tile, '$_sentence\n$_sentence');

        await _pumpBox(
          tester,
          FilledButton(
            onPressed: () {},
            child: const KeepHangulWordsText(_sentence),
          ),
        );
        final button = tester.getSemantics(find.byType(FilledButton)).label;
        expect(button, _sentence);

        for (final label in <String>[single, tile, button]) {
          for (final char in invisible) {
            expect(char.allMatches(label), isEmpty, reason: label);
          }
        }
        handle.dispose();
      },
    );

    testWidgets('T-27-WRAP-09 낭독 덮어쓰기 — semanticsLabel 을 주면 그 값을 읽는다', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await _pumpBox(
        tester,
        const KeepHangulWordsText(_sentence, semanticsLabel: '공지: $_sentence'),
      );
      expect(
        tester.getSemantics(find.byType(KeepHangulWordsText)).label,
        '공지: $_sentence',
      );
      handle.dispose();
    });

    testWidgets('T-27-WRAP-10 maxLines 2 · 말줄임 — 높이가 원문 Text 와 같고 예외 0', (
      tester,
    ) async {
      const long =
          '$_sentence 연결을 해제하면 그 서비스로는 더 이상 로그인할 수 없고, 다시 연결하려면 처음부터 권한을 허용해야 합니다.';
      await _pumpBox(
        tester,
        const Text(long, maxLines: 2, overflow: TextOverflow.ellipsis),
        width: 200,
      );
      final plainHeight = tester.getSize(find.byType(Text)).height;
      await _pumpBox(
        tester,
        const KeepHangulWordsText(
          long,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        width: 200,
      );
      expect(tester.takeException(), isNull);
      expect(_paragraphInBox(tester).didExceedMaxLines, isTrue);
      expect(
        tester.getSize(find.byType(KeepHangulWordsText)).height,
        plainHeight,
      );
    });
  });
}
