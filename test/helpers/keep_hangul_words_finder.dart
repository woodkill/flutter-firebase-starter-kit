// 한국어 낱말 줄바꿈 감싸개 문구를 원문으로 찾는 공용 finder — 사본을 두지 않는다.
//
// 감싸개 `KeepHangulWordsText` 가 받은 원문, 그리고 감싸개 밖 일반 `Text` ·
// 입력칸(`EditableText`)의 원문으로 위젯을 찾는다.
//
// **왜 따로 두나:** 감싸개는 한글이 든 문구를 안에서 `Text.rich` 로 그리고 글자
// 사이에 묶는 표시를 더하므로 `find.text(원문)` 이 그 문구를 찾지 못한다. 한글이
// 없는 문구는 감싸개가 안에서 같은 원문의 `Text` 를 만들어, 감싸개와 안쪽 `Text`
// 를 모두 세는 단순 술어는 한 문구를 두 번 센다. 이 finder 는 감싸개 하나를 한
// 개로 세고, 감싸개 안에서 만든 `Text` 는 세지 않는다.
//
// 이 파일 한 곳에 정의하고 모든 시험이 import 한다. 사본이 생기면 하나만 술어가
// 바뀌어 같은 이름의 finder 가 파일마다 다르게 센다.

import 'package:flutter/widgets.dart';
import 'package:flutter_starter_kit/shared/widgets/keep_hangul_words_text.dart';
import 'package:flutter_test/flutter_test.dart';

/// 원문이 [text] 와 같은 감싸개 · `Text` · 입력칸을 찾는다.
///
/// 찾는 대상은 원문이 [text] 인 [KeepHangulWordsText], 감싸개 밖에 있고
/// `data ?? textSpan.toPlainText()` 가 [text] 인 [Text], 입력값이 [text] 인
/// [EditableText] 다. 감싸개 하나는 한 개로 세고, 한글이 없는 문구도 감싸개가
/// 안에서 만든 [Text] 를 따로 세지 않아 한 개다.
///
/// 개수 기준으로 `find.text` 의 상위 집합이다 — 감싸개 안에서 만든 [Text] 는
/// 감싸개로 대신 센다. 그래서 `find.text(text)` 자리에 바꿔 써도 찾는 개수는 같거나
/// 많다(한글이 든 감싸개 문구만 더 찾는다). 다만 감싸개 문구는 [Text] 대신
/// [KeepHangulWordsText] 를 돌려주므로 `tester.widget<KeepHangulWordsText>` 로
/// 읽는다. [skipOffstage] 는 `find.text` 의 같은 이름 인자와 같다.
Finder findKeepHangulWordsText(String text, {bool skipOffstage = true}) {
  return find.byElementPredicate(
    (element) => _matchesKeepHangulWordsText(element, (value) => value == text),
    description: 'KeepHangulWordsText/Text "$text"',
    skipOffstage: skipOffstage,
  );
}

/// 원문이 [pattern] 을 담은 감싸개 · `Text` · 입력칸을 찾는다.
///
/// 찾는 대상과 세는 방법은 [findKeepHangulWordsText] 와 같고, 원문이 같은지
/// 대신 [pattern] 을 담는지(`String.contains`)를 본다.
///
/// 개수 기준으로 `find.textContaining` 의 상위 집합이다 — 감싸개 안에서 만든
/// [Text] 는 감싸개로 대신 센다. 감싸개 문구는 [Text] 대신 [KeepHangulWordsText]
/// 를 돌려준다. [skipOffstage] 는 `find.textContaining` 의 같은 이름 인자와 같다.
Finder findKeepHangulWordsTextContaining(
  Pattern pattern, {
  bool skipOffstage = true,
}) {
  return find.byElementPredicate(
    (element) => _matchesKeepHangulWordsText(
      element,
      (value) => value.contains(pattern),
    ),
    description: 'KeepHangulWordsText/Text containing $pattern',
    skipOffstage: skipOffstage,
  );
}

/// [element] 의 위젯 원문이 [matches] 를 만족하는지 본다.
///
/// 감싸개는 원문 `data` 를, 감싸개 밖 [Text] 는 `data ?? textSpan.toPlainText()`
/// 를, [EditableText] 는 입력값을 본다. 감싸개 안에서 만든 [Text] 와 그 밖의
/// 위젯은 거짓이다.
bool _matchesKeepHangulWordsText(
  Element element,
  bool Function(String value) matches,
) {
  final widget = element.widget;
  if (widget is KeepHangulWordsText) {
    return matches(widget.data);
  }
  if (widget is Text) {
    if (element.findAncestorWidgetOfExactType<KeepHangulWordsText>() != null) {
      return false;
    }
    final value = widget.data ?? widget.textSpan?.toPlainText();
    return value != null && matches(value);
  }
  if (widget is EditableText) {
    return matches(widget.controller.text);
  }
  return false;
}
