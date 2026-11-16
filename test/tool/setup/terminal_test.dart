import 'dart:io';

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
  final queue = List<String>.of(answers);
  return () => queue.isEmpty ? null : queue.removeAt(0);
}

/// [haystack] 에서 [needle] 이 나타나는 횟수를 센다.
int countText(String haystack, String needle) =>
    RegExp(RegExp.escape(needle)).allMatches(haystack).length;

/// 숨김 입력 질문.
const String secretQuestion = '어드민 키를 붙여 넣으세요';

/// 터미널이 붙여 넣거나 끌어다 놓은 글 앞에 붙이는 표시(시험 자신의 리터럴).
const String pasteStart = '\x1B[200~';

/// 터미널이 붙여 넣거나 끌어다 놓은 글 뒤에 붙이는 표시(시험 자신의 리터럴).
const String pasteEnd = '\x1B[201~';

/// 끌어다 놓기 꼴 경로 — 공백 앞에 `\` 가 있다.
const String droppedPath = r'/Users/me/src/logo\ 1024.png';

/// 경로 질문.
const String pathQuestion = '원본 이미지 경로';

/// [text] 를 붙여 넣기 표시로 감싼다.
String wrapPaste(String text) => '$pasteStart$text$pasteEnd';

/// 붙여 넣기 표시 경계 사례 — 이름 · 읽은 줄 · 기대 결과.
typedef PasteCase = ({String name, String input, String expected});

/// 표시를 지우는 사례.
final List<PasteCase> strippedCases = <PasteCase>[
  (name: '앞뒤', input: wrapPaste(droppedPath), expected: droppedPath),
  (name: '앞만', input: '$pasteStart$droppedPath', expected: droppedPath),
  (name: '뒤만', input: '$droppedPath$pasteEnd', expected: droppedPath),
  (name: '중간', input: 'ab${wrapPaste('/c.png')}', expected: 'ab/c.png'),
  (
    name: '두 번',
    input: '${wrapPaste('/a.png')} ${wrapPaste('/b.png')}',
    expected: '/a.png /b.png',
  ),
  (name: '표시만', input: wrapPaste(''), expected: ''),
  (name: '표시 안 공백', input: wrapPaste('  /a.png  '), expected: '  /a.png  '),
];

/// 표시가 아니어서 그대로 두는 사례.
final List<PasteCase> keptCases = <PasteCase>[
  (name: '표시 없는 경로', input: droppedPath, expected: droppedPath),
  (name: '빈 줄', input: '', expected: ''),
  (
    name: 'ESC 없는 [200~',
    input: '[200~/a.png[201~',
    expected: '[200~/a.png[201~',
  ),
  (name: 'ESC[202~', input: '\x1B[202~/a.png', expected: '\x1B[202~/a.png'),
  (
    name: 'ESC[0m 색 코드',
    input: '\x1B[0m/a.png\x1B[1m',
    expected: '\x1B[0m/a.png\x1B[1m',
  ),
  (name: '물결 없는 ESC[200', input: '\x1B[200/a.png', expected: '\x1B[200/a.png'),
];

/// [lines] 가운데 ESC 가 든 줄.
Iterable<String> findEscapeLines(List<String> lines) =>
    lines.where((String line) => line.contains('\x1B'));

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
    final output = StringBuffer();
    final terminal = StdioTerminal(
      readLine: buildReadLine(<String>['', '2']),
      output: output,
    );

    final int? index = terminal.choose(
      sampleQuestion,
      sampleOptions,
      defaultIndex: null,
    );

    final shown = output.toString();
    expect(index, 1);
    expect(countText(shown, '번호를 고르세요: '), 2);
    expect(shown, isNot(contains('번호를 고르세요 [')));
    expect(countText(shown, retryLine), 1);

    final exhausted = StringBuffer();
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
    final output = StringBuffer();
    final terminal = StdioTerminal(
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

    final output = StringBuffer();
    final redactor = Redactor();
    final terminal = RedactingTerminal(
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
    final recorder = EchoRecorder();
    final output = StringBuffer();
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
    final recorder = EchoRecorder();
    final output = StringBuffer();
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
    final recorder = EchoRecorder();
    final output = StringBuffer();
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
    final recorder = EchoRecorder(echoAtStart: false);
    final StdioTerminal terminal = buildSecretTerminal(
      recorder,
      buildReadLine(<String>['k' * 32]),
      StringBuffer(),
    );

    terminal.askSecret(secretQuestion);

    expect(recorder.writes, <bool>[false, false]);
  });

  test('T-20-SECRET-07: 표준 입력이 터미널이 아니면 에코를 건드리지 않고 그대로 읽는다', () {
    final writes = <bool>[];
    final output = StringBuffer();
    final terminal = StdioTerminal(
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

  group('T-28-PASTE-01: 붙여 넣기 표시는 자리 · 횟수와 상관없이 지운다', () {
    for (final PasteCase item in strippedCases) {
      test('${item.name} → 표시를 지운 글', () {
        expect(stripBracketedPasteMarkers(item.input), item.expected);
      });
    }
  });

  group('T-28-PASTE-02: 표시가 아닌 글자는 그대로 둔다', () {
    for (final PasteCase item in keptCases) {
      test('${item.name} → 읽은 줄 그대로', () {
        expect(stripBracketedPasteMarkers(item.input), item.expected);
      });
    }
  });

  group('T-28-PASTE-03: 표준 입출력 터미널의 네 입력이 표시를 지운 답을 쓴다', () {
    test('ask → 표시 안 공백까지 떼고 escape 는 그대로', () {
      final terminal = StdioTerminal(
        readLine: buildReadLine(<String>[wrapPaste('  $droppedPath  ')]),
        output: StringBuffer(),
      );

      expect(terminal.ask(pathQuestion), droppedPath);
    });

    test('ask 기본값 → 표시만 있는 답은 기본값', () {
      final terminal = StdioTerminal(
        readLine: buildReadLine(<String>[wrapPaste('')]),
        output: StringBuffer(),
      );

      expect(terminal.ask(pathQuestion, defaultValue: '#FFFFFF'), '#FFFFFF');
    });

    test('askSecret → 표시를 지운 32자', () {
      final String secret = 'k' * 32;
      final StdioTerminal terminal = buildSecretTerminal(
        EchoRecorder(),
        buildReadLine(<String>[wrapPaste(secret)]),
        StringBuffer(),
      );

      expect(terminal.askSecret(secretQuestion), secret);
    });

    test('confirm → 감싼 y 는 예 · 감싼 n 은 아니요', () {
      final terminal = StdioTerminal(
        readLine: buildReadLine(<String>[wrapPaste('y'), wrapPaste('n')]),
        output: StringBuffer(),
      );

      expect(terminal.confirm(sampleQuestion), isTrue);
      expect(terminal.confirm(sampleQuestion), isFalse);
    });

    test('choose → 감싼 2 는 둘째 · 다시 고르라는 줄 0', () {
      final output = StringBuffer();
      final terminal = StdioTerminal(
        readLine: buildReadLine(<String>[wrapPaste('2')]),
        output: output,
      );

      expect(terminal.choose(sampleQuestion, sampleOptions), 1);
      expect(countText(output.toString(), retryLine), 0);
    });
  });

  group('T-28-PASTE-04: 가림 감싸개의 기록 · 가림이 표시를 지운 값을 쓴다', () {
    test('[in] 기록 → 표시를 지운 경로 한 줄 · ESC 든 줄 0', () {
      final redactor = Redactor();
      final log = MemoryLogSink(redactor);
      final terminal = RedactingTerminal(
        StdioTerminal(
          readLine: buildReadLine(<String>[wrapPaste(droppedPath)]),
          output: StringBuffer(),
        ),
        redactor,
        log,
      );

      expect(terminal.ask(pathQuestion), droppedPath);
      expect(
        log.lines.where((String line) => line == '[in] $droppedPath').length,
        1,
      );
      expect(findEscapeLines(log.lines), isEmpty);
    });

    test('비밀 값 가림 → 표시를 지운 32자를 가리고 기록은 글자 수만', () {
      final String secret = 'k' * 32;
      final redactor = Redactor();
      final log = MemoryLogSink(redactor);
      final terminal = RedactingTerminal(
        buildSecretTerminal(
          EchoRecorder(),
          buildReadLine(<String>[wrapPaste(secret)]),
          StringBuffer(),
        ),
        redactor,
        log,
      );

      final String? answer = terminal.askSecret(secretQuestion);

      expect(answer?.length, 32);
      expect(redactor.apply(secret), Redactor.mask);
      expect(
        log.lines.where((String line) => line == '[in] (비밀 값 32자)').length,
        1,
      );
      expect(countText(log.text, '(비밀 값 44자)'), 0);
      expect(findEscapeLines(log.lines), isEmpty);
    });
  });

  group('T-28-PASTE-06: 비밀 값은 표시를 지운 뒤 공백을 뗀다', () {
    test('표시 안 앞뒤 공백이 든 비밀 값 → 공백 없는 32자', () {
      final String secret = 'k' * 32;
      final StdioTerminal terminal = buildSecretTerminal(
        EchoRecorder(),
        buildReadLine(<String>[wrapPaste('  $secret  ')]),
        StringBuffer(),
      );

      final String? answer = terminal.askSecret(secretQuestion);

      expect(answer, secret);
      expect(answer?.length, 32);
    });

    test('가림 감싸개 → 32자만 가리고 기록은 공백 뺀 글자 수만', () {
      final String secret = 'k' * 32;
      final redactor = Redactor();
      final log = MemoryLogSink(redactor);
      final terminal = RedactingTerminal(
        buildSecretTerminal(
          EchoRecorder(),
          buildReadLine(<String>[wrapPaste('  $secret  ')]),
          StringBuffer(),
        ),
        redactor,
        log,
      );

      final String? answer = terminal.askSecret(secretQuestion);

      expect(answer?.length, 32);
      expect(redactor.apply(secret), Redactor.mask);
      expect(
        log.lines.where((String line) => line == '[in] (비밀 값 32자)').length,
        1,
      );
      expect(countText(log.text, '(비밀 값 36자)'), 0);
      expect(findEscapeLines(log.lines), isEmpty);
    });
  });
}
