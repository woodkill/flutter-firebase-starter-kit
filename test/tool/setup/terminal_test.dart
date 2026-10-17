import 'dart:io';

import 'package:test/test.dart';

import '../../../bin/setup.dart' show handleInterrupt, interruptExitCode;
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

/// 숨김 입력 질문.
const String secretQuestion = '어드민 키를 붙여 넣으세요';

/// 숨김 입력이 부른 에코 읽기 · 쓰기 · 줄 읽기를 차례로 모으는 기록.
final class EchoRecorder {
  /// 시작 에코가 [echoAtStart] 인 터미널을 흉내 내는 기록을 만든다.
  EchoRecorder({this.echoAtStart = true});

  /// 에코 읽기가 돌려줄 시작 값.
  final bool echoAtStart;

  /// 호출 순서 — `read` · `write <값>` · `line`.
  final List<String> events = <String>[];

  /// 에코 쓰기에 넘어온 값만 차례로.
  final List<bool> writes = <bool>[];

  /// 에코 상태를 읽는다.
  bool readEchoMode() {
    events.add('read');
    return echoAtStart;
  }

  /// 에코 상태를 바꾼다.
  void writeEchoMode(bool isEnabled) {
    events.add('write $isEnabled');
    writes.add(isEnabled);
  }

  /// [readLine] 을 부르기 전에 `line` 을 남기는 읽기 함수로 감싼다.
  String? Function() wrapReadLine(String? Function() readLine) => () {
    events.add('line');
    return readLine();
  };
}

/// [recorder] 로 에코를 흉내 내고 [readLine] 으로 답하는 터미널을 만든다.
StdioTerminal buildSecretTerminal(
  EchoRecorder recorder,
  String? Function() readLine,
  StringSink output,
) => StdioTerminal(
  readLine: recorder.wrapReadLine(readLine),
  output: output,
  readEchoMode: recorder.readEchoMode,
  writeEchoMode: recorder.writeEchoMode,
);

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

  test('T-20-SECRET-01: 정상 입력은 에코를 끄고 읽은 뒤 시작 값으로 되돌린다', () {
    final EchoRecorder recorder = EchoRecorder();
    final StringBuffer output = StringBuffer();
    final String secret = 'k' * 32;
    final StdioTerminal terminal = buildSecretTerminal(
      recorder,
      buildReadLine(<String>['  $secret  ']),
      output,
    );

    final String? answer = terminal.askSecret(secretQuestion);

    expect(answer, secret);
    expect(recorder.events, <String>[
      'read',
      'write false',
      'line',
      'write true',
    ]);
    expect(recorder.writes, <bool>[false, true]);
    expect(output.toString(), '$secretQuestion: \n');
    expect(countText(output.toString(), secret), 0);
  });

  test('T-20-SECRET-02: 입력 끝이면 null 을 돌려주고 에코를 되돌린 뒤 한 줄 내린다', () {
    final EchoRecorder recorder = EchoRecorder();
    final StringBuffer output = StringBuffer();
    final StdioTerminal terminal = buildSecretTerminal(
      recorder,
      buildReadLine(const <String>[]),
      output,
    );

    final String? answer = terminal.askSecret(secretQuestion);

    expect(answer, isNull);
    expect(recorder.writes, <bool>[false, true]);
    expect(output.toString(), '$secretQuestion: \n');
  });

  test('T-20-SECRET-03: 읽기가 예외를 던져도 에코는 되돌아가고 예외는 그대로 전해진다', () {
    final EchoRecorder recorder = EchoRecorder();
    final StringBuffer output = StringBuffer();
    final StdioTerminal terminal = buildSecretTerminal(
      recorder,
      () => throw StateError('읽기 실패'),
      output,
    );

    expect(() => terminal.askSecret(secretQuestion), throwsStateError);
    expect(recorder.events, <String>[
      'read',
      'write false',
      'line',
      'write true',
    ]);
    expect(output.toString(), '$secretQuestion: \n');
  });

  test('T-20-SECRET-04: 시작 에코가 이미 꺼져 있으면 꺼진 그대로 되돌린다', () {
    final EchoRecorder recorder = EchoRecorder(echoAtStart: false);
    final StdioTerminal terminal = buildSecretTerminal(
      recorder,
      buildReadLine(<String>['k' * 32]),
      StringBuffer(),
    );

    terminal.askSecret(secretQuestion);

    expect(recorder.writes, <bool>[false, false]);
  });

  test('T-20-SECRET-05: Ctrl-C 처리는 에코 복구 → 기록 닫기 → 130 종료 순서다', () async {
    final List<String> events = <String>[];
    await handleInterrupt(
      writeEchoMode: (bool isEnabled) => events.add('echo $isEnabled'),
      echoBefore: true,
      closeLog: () async => events.add('close'),
      exitProcess: (int code) => events.add('exit $code'),
    );

    expect(interruptExitCode, 130);
    expect(events, <String>['echo true', 'close', 'exit 130']);

    // 기록 닫기가 실패해도 에코 복구와 종료는 일어난다.
    final List<String> failing = <String>[];
    await handleInterrupt(
      writeEchoMode: (bool isEnabled) => failing.add('echo $isEnabled'),
      echoBefore: false,
      closeLog: () async {
        failing.add('close');
        throw const FileSystemException('기록 닫기 실패');
      },
      exitProcess: (int code) => failing.add('exit $code'),
    );

    expect(failing, <String>['echo false', 'close', 'exit 130']);
  });

  test('T-20-SECRET-07: 표준 입력이 터미널이 아니면 에코를 건드리지 않고 그대로 읽는다', () {
    final List<bool> writes = <bool>[];
    final StringBuffer output = StringBuffer();
    final StdioTerminal terminal = StdioTerminal(
      readLine: buildReadLine(<String>['k' * 32]),
      output: output,
      readEchoMode: () => throw const StdinException('터미널이 아닙니다'),
      writeEchoMode: writes.add,
    );

    final String? answer = terminal.askSecret(secretQuestion);

    expect(answer, 'k' * 32);
    expect(writes, isEmpty);
    expect(output.toString(), '$secretQuestion: \n');
  });
}
