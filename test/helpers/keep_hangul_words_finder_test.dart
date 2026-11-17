// 감싸개 문구를 원문으로 찾는 공용 finder 의 성질 시험.
//
// 시험 ID: T-27-FIND-01 ~ 06 `findKeepHangulWordsText` (감싸개 하나 = 한 개 ·
// 감싸개 밖 `Text` · 여러 개 · tap · 위젯 꺼내기) · T-27-FIND-07
// `findKeepHangulWordsTextContaining` · T-27-FIND-08 `find.text` ·
// `find.textContaining` 의 상위 집합(감싸개 없는 `Text.rich` · 입력칸
// `EditableText` · 화면 밖) · T-27-FIND-09 감싸개 하위 클래스도 한 개.
//
// 표본은 이 파일 안 리터럴 — 킷 문구에 기대지 않는다.

import 'package:flutter/material.dart';
import 'package:flutter_starter_kit/shared/widgets/keep_hangul_words_text.dart';
import 'package:flutter_test/flutter_test.dart';

import 'keep_hangul_words_finder.dart';

/// 감싸개를 상속한 시험용 위젯 — 하위 클래스도 감싸개 하나로 세는지 본다.
class _SubclassedKeepHangulWordsText extends KeepHangulWordsText {
  const _SubclassedKeepHangulWordsText(super.data);
}

/// [children] 을 세로로 늘어놓아 pump 한다.
Future<void> _pumpColumn(WidgetTester tester, List<Widget> children) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(body: Column(children: children)),
    ),
  );
}

void main() {
  group('findKeepHangulWordsText', () {
    testWidgets('T-27-FIND-01 한글 문구 감싸개 하나를 한 개로 찾고 find.text 는 찾지 못한다', (
      tester,
    ) async {
      const text = '버튼을 길게 누르세요';
      await _pumpColumn(tester, const <Widget>[KeepHangulWordsText(text)]);

      expect(findKeepHangulWordsText(text), findsOneWidget);
      expect(find.text(text), findsNothing);
    });

    testWidgets('T-27-FIND-02 한글 없는 문구 감싸개도 안쪽 Text 를 따로 세지 않아 한 개다', (
      tester,
    ) async {
      const text = 'Hello world';
      await _pumpColumn(tester, const <Widget>[KeepHangulWordsText(text)]);

      expect(find.text(text), findsOneWidget, reason: '안쪽 Text 가 원문을 가진다');
      expect(findKeepHangulWordsText(text), findsOneWidget);
    });

    testWidgets('T-27-FIND-03 감싸개 밖 한글 Text 를 한 개로 찾는다', (tester) async {
      const text = '계정 설정';
      await _pumpColumn(tester, const <Widget>[Text(text)]);

      expect(findKeepHangulWordsText(text), findsOneWidget);
    });

    testWidgets('T-27-FIND-04 같은 문구 감싸개 둘은 두 개 · 다른 문구는 0개', (tester) async {
      const text = '같은 문구입니다';
      await _pumpColumn(tester, const <Widget>[
        KeepHangulWordsText(text),
        KeepHangulWordsText(text),
      ]);

      expect(findKeepHangulWordsText(text), findsNWidgets(2));
      expect(findKeepHangulWordsText('다른 문구입니다'), findsNothing);
    });

    testWidgets('T-27-FIND-05 그 finder 로 감싸개를 누르면 버튼 콜백이 한 번 돈다', (
      tester,
    ) async {
      const text = '다시 시도해 주세요';
      var taps = 0;
      await _pumpColumn(tester, <Widget>[
        TextButton(
          onPressed: () => taps++,
          child: const KeepHangulWordsText(text),
        ),
      ]);

      await tester.tap(findKeepHangulWordsText(text));
      await tester.pump();

      expect(taps, 1);
    });

    testWidgets('T-27-FIND-06 그 finder 로 감싸개 위젯을 꺼내면 넘긴 스타일이 있다', (
      tester,
    ) async {
      const text = '스타일을 넘긴 문구';
      const style = TextStyle(fontSize: 17, fontWeight: FontWeight.w600);
      await _pumpColumn(tester, const <Widget>[
        KeepHangulWordsText(text, style: style),
      ]);

      final widget = tester.widget<KeepHangulWordsText>(
        findKeepHangulWordsText(text),
      );
      expect(widget.style, style);
      expect(widget.data, text);
    });
  });

  group('findKeepHangulWordsText 하위 클래스', () {
    testWidgets(
      'T-27-FIND-09 감싸개 하위 클래스로 그린 한글 없는 문구도 안쪽 Text 를 따로 세지 않아 한 개다',
      (tester) async {
        const text = 'Hello subclass';
        await _pumpColumn(tester, const <Widget>[
          _SubclassedKeepHangulWordsText(text),
        ]);

        expect(find.text(text), findsOneWidget, reason: '안쪽 Text 가 원문을 가진다');
        expect(findKeepHangulWordsText(text), findsOneWidget);
        expect(findKeepHangulWordsTextContaining('subclass'), findsOneWidget);
      },
    );
  });

  group('findKeepHangulWordsTextContaining', () {
    testWidgets(
      'T-27-FIND-07 감싸개 어절 속 부분 문자열 · 감싸개 밖 Text · 한글 없는 감싸개를 한 개씩 찾는다',
      (tester) async {
        await _pumpColumn(tester, const <Widget>[
          KeepHangulWordsText('user@example.com(으)로 메일을 보냈습니다'),
          Text('알림 설정을 바꿉니다'),
          KeepHangulWordsText('Sign in again'),
        ]);

        expect(
          findKeepHangulWordsTextContaining('user@example.com'),
          findsOneWidget,
          reason: '한글 감싸개 어절 안 부분 문자열',
        );
        expect(
          find.textContaining('user@example.com'),
          findsNothing,
          reason: 'find.textContaining 은 이음 문자에 막힌다',
        );
        expect(
          findKeepHangulWordsTextContaining('설정을 바꿉'),
          findsOneWidget,
          reason: '감싸개 밖 일반 Text',
        );
        expect(
          findKeepHangulWordsTextContaining('in again'),
          findsOneWidget,
          reason: '한글 없는 감싸개 — 안쪽 Text 이중 계수 0',
        );
        expect(
          findKeepHangulWordsTextContaining(RegExp(r'user@\w+\.com')),
          findsOneWidget,
          reason: 'RegExp 인자',
        );
      },
    );
  });

  group('두 helper 의 상위 집합', () {
    testWidgets(
      'T-27-FIND-08 감싸개 없는 Text.rich · TextField 글은 find.text 와 같은 수 · 화면 밖은 skipOffstage: false 로만',
      (tester) async {
        final controller = TextEditingController(text: '입력한 글입니다');
        addTearDown(controller.dispose);
        await _pumpColumn(tester, <Widget>[
          const Text.rich(
            TextSpan(
              text: '안내 ',
              children: <InlineSpan>[TextSpan(text: '문구입니다')],
            ),
          ),
          TextField(controller: controller),
          const Offstage(child: KeepHangulWordsText('화면 밖 문구입니다')),
        ]);

        expect(find.byType(EditableText), findsOneWidget);
        for (final text in const <String>['안내 문구입니다', '입력한 글입니다']) {
          expect(find.text(text), findsOneWidget, reason: text);
          expect(findKeepHangulWordsText(text), findsOneWidget, reason: text);
          expect(
            findKeepHangulWordsText(text).evaluate().length,
            find.text(text).evaluate().length,
            reason: text,
          );
        }
        for (final pattern in const <String>['내 문구', '력한 글']) {
          expect(find.textContaining(pattern), findsOneWidget, reason: pattern);
          expect(
            findKeepHangulWordsTextContaining(pattern),
            findsOneWidget,
            reason: pattern,
          );
        }

        expect(findKeepHangulWordsText('화면 밖 문구입니다'), findsNothing);
        expect(
          findKeepHangulWordsText('화면 밖 문구입니다', skipOffstage: false),
          findsOneWidget,
        );
        expect(findKeepHangulWordsTextContaining('화면 밖'), findsNothing);
        expect(
          findKeepHangulWordsTextContaining('화면 밖', skipOffstage: false),
          findsOneWidget,
        );
      },
    );
  });
}
