// 한국어 낱말 줄바꿈 감싸개 `KeepHangulWordsText` 의 성질 시험.
//
// 시험 ID: T-27-WRAP-01 넣는 자리 · T-27-WRAP-02 이음 문자 span 구조 ·
// T-27-WRAP-03 한글 없으면 Text 그대로 · T-27-WRAP-11 locale 무관.
//
// 표본은 이 파일 안 리터럴 — 킷 문구에 기대지 않는다. 보이지 않는 문자는
// `String.fromCharCode` · `\u{…}` 이스케이프로만 적는다.

import 'package:flutter/material.dart';
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
  // 띄어쓰기 · 줄바꿈 · 탭은 덩어리 경계다.
  '가나 다라\n마바\t사아':
      '${_joined(<String>['가', '나'])} ${_joined(<String>['다', '라'])}'
      '\n${_joined(<String>['마', '바'])}\t${_joined(<String>['사', '아'])}',
  // ZWJ 이모지 · 결합 부호 안에는 넣지 않는다(글자 단위).
  '김\u{1F469}\u{200D}\u{1F4BB}님': _joined(<String>[
    '김',
    '\u{1F469}\u{200D}\u{1F4BB}',
    '님',
  ]),
  'Cafe\u{0301}로': _joined(<String>['C', 'a', 'f', 'e\u{0301}', '로']),
  // 한글이 없으면 그대로다.
  'Hello world': 'Hello world',
};

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
        final hangulKeys = _placementCases.keys.where(_hangul.hasMatch);
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
  });
}
