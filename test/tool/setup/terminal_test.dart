import 'package:test/test.dart';

import '../../../tool/setup/redactor.dart';
import '../../../tool/setup/terminal.dart';
import 'fakes.dart';

/// 번호 고르기 테스트에 쓰는 선택지.
const List<String> sampleOptions = <String>['첫째 프로젝트', '둘째 프로젝트'];

/// 번호 고르기 질문.
const String sampleQuestion = '쓸 프로젝트를 고르세요';

/// 번호를 다시 고르라는 안내.
const String retryLine = '1 부터 2 사이의 번호를 입력하세요.';

/// [answers] 를 차례로 돌려주고 끝나면 입력 끝(null)인 읽기 함수를 만든다.
String? Function() buildReadLine(List<String> answers) {
  final List<String> queue = List<String>.of(answers);
  return () => queue.isEmpty ? null : queue.removeAt(0);
}

/// [haystack] 에서 [needle] 이 나타나는 횟수를 센다.
int countText(String haystack, String needle) =>
    RegExp(RegExp.escape(needle)).allMatches(haystack).length;

void main() {
  test('T-19-TERM-01: 기본값이 없으면 프롬프트에 [n] 이 없고 빈 답을 다시 묻는다', () {
    final StringBuffer output = StringBuffer();
    final StdioTerminal terminal = StdioTerminal(
      readLine: buildReadLine(<String>['', '2']),
      output: output,
    );

    final int? index = terminal.choose(
      sampleQuestion,
      sampleOptions,
      defaultIndex: null,
    );

    final String shown = output.toString();
    expect(index, 1);
    expect(countText(shown, '번호를 고르세요: '), 2);
    expect(shown, isNot(contains('번호를 고르세요 [')));
    expect(countText(shown, retryLine), 1);

    final StringBuffer exhausted = StringBuffer();
    final int? none = StdioTerminal(
      readLine: buildReadLine(<String>['', '', '']),
      output: exhausted,
    ).choose(sampleQuestion, sampleOptions, defaultIndex: null);

    expect(none, isNull);
    expect(
      countText(exhausted.toString(), '번호를 고르세요: '),
      StdioTerminal.maxChoiceAttempts,
    );
    expect(
      countText(exhausted.toString(), retryLine),
      StdioTerminal.maxChoiceAttempts,
    );
  });

  test('T-19-TERM-02: 기본값을 주지 않으면 지금처럼 [1] 을 보이고 빈 답은 첫째다', () {
    final StringBuffer output = StringBuffer();
    final StdioTerminal terminal = StdioTerminal(
      readLine: buildReadLine(<String>['']),
      output: output,
    );

    final int? index = terminal.choose(sampleQuestion, sampleOptions);

    expect(index, 0);
    expect(output.toString(), contains('번호를 고르세요 [1]: '));
    expect(output.toString(), isNot(contains(retryLine)));
  });

  test('T-19-TERM-03: 답 해석과 가림 감싸개도 기본값 없음을 그대로 따른다', () {
    expect(parseChoiceAnswer('', optionCount: 2, defaultIndex: null), isNull);
    expect(parseChoiceAnswer('2', optionCount: 2, defaultIndex: null), 1);
    expect(parseChoiceAnswer('3', optionCount: 2, defaultIndex: null), isNull);
    expect(parseChoiceAnswer('', optionCount: 2, defaultIndex: 1), 1);

    final StringBuffer output = StringBuffer();
    final Redactor redactor = Redactor();
    final RedactingTerminal terminal = RedactingTerminal(
      StdioTerminal(readLine: buildReadLine(<String>['1']), output: output),
      redactor,
      MemoryLogSink(redactor),
    );

    final int? index = terminal.choose(
      sampleQuestion,
      sampleOptions,
      defaultIndex: null,
    );

    expect(index, 0);
    expect(output.toString(), contains('번호를 고르세요: '));
    expect(output.toString(), isNot(contains('번호를 고르세요 [')));
  });
}
