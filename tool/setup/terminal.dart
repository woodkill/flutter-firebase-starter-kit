import 'dart:convert';
import 'dart:io';

import 'log_sink.dart';
import 'redactor.dart';

/// 위저드가 사용자와 주고받는 화면 입출력.
abstract interface class Terminal {
  /// 한 줄을 출력한다.
  void writeLine(String line);

  /// 실행할 명령 줄을 `  $ <display>` 꼴로 출력한다.
  void writeCommand(String display);

  /// 받은 문자열을 그대로 출력한다(줄바꿈을 더하지 않는다).
  void writeRaw(String text);

  /// 예 · 아니요를 묻는다 — `y` · `yes` 만 true 이고 기본값은 아니요다.
  bool confirm(String question);

  /// 값을 묻는다 — Enter 면 [defaultValue], 입력 끝이면 null.
  String? ask(String question, {String? defaultValue});

  /// 비밀 값을 화면에 보이지 않게 묻는다 — 앞뒤 공백을 뗀 답, 입력 끝이면 null.
  String? askSecret(String question);

  /// 번호로 고르게 한다 — 고른 0부터의 위치, 입력 끝이나 계속 틀리면 null.
  ///
  /// 빈 답은 [defaultIndex] 를 고른다. [defaultIndex] 가 null 이면 기본값이 없어
  /// 빈 답도 잘못된 답처럼 다시 묻는다.
  int? choose(String question, List<String> options, {int? defaultIndex = 0});

  /// Enter 를 기다린다 — 입력 끝이면 false.
  bool waitForEnter(String message);
}

/// 예 · 아니요 답을 해석한다 — 앞뒤 공백을 지운 소문자 `y` · `yes` 만 true.
bool parseYesAnswer(String? answer) {
  if (answer == null) return false;
  final String normalized = answer.trim().toLowerCase();
  return normalized == 'y' || normalized == 'yes';
}

/// 번호 고르기 답을 해석한다.
///
/// 빈 답은 [defaultIndex](null 이면 기본값 없음 = null), 1부터 [optionCount]
/// 사이의 숫자는 0부터의 위치, 그 밖은 null 이다.
int? parseChoiceAnswer(
  String answer, {
  required int optionCount,
  required int? defaultIndex,
}) {
  final String trimmed = answer.trim();
  if (trimmed.isEmpty) return defaultIndex;
  final int? number = int.tryParse(trimmed);
  if (number == null || number < 1 || number > optionCount) return null;
  return number - 1;
}

/// 표준 입출력을 쓰는 터미널.
final class StdioTerminal implements Terminal {
  /// [readLine] · [output] 을 주지 않으면 표준 입력 · 표준 출력을 쓴다.
  StdioTerminal({String? Function()? readLine, StringSink? output})
    : _readLine = readLine ?? _readStdinLine,
      _output = output ?? stdout;

  /// 번호를 다시 묻는 최대 횟수.
  static const int maxChoiceAttempts = 3;

  final String? Function() _readLine;
  final StringSink _output;

  /// 표준 입력에서 한 줄을 읽는다 — 입력 끝이면 null.
  static String? _readStdinLine() => stdin.readLineSync(encoding: utf8);

  @override
  void writeLine(String line) => _output.writeln(line);

  @override
  void writeCommand(String display) => _output.writeln('  \$ $display');

  @override
  void writeRaw(String text) => _output.write(text);

  @override
  bool confirm(String question) {
    _output.write('$question [y/N] ');
    final String? answer = _readLine();
    if (answer == null) _output.writeln();
    return parseYesAnswer(answer);
  }

  @override
  String? ask(String question, {String? defaultValue}) {
    final String hint = defaultValue == null ? '' : ' [$defaultValue]';
    _output.write('$question$hint: ');
    final String? answer = _readLine();
    if (answer == null) {
      _output.writeln();
      return null;
    }
    final String trimmed = answer.trim();
    return trimmed.isEmpty ? (defaultValue ?? '') : trimmed;
  }

  @override
  String? askSecret(String question) {
    _output.write('$question: ');
    // 터미널이 아니면 에코를 바꿀 수 없다 — 그때는 그대로 읽는다.
    bool? restoreEchoMode;
    try {
      final bool current = stdin.echoMode;
      stdin.echoMode = false;
      restoreEchoMode = current;
    } on StdinException {
      restoreEchoMode = null;
    }
    try {
      return _readLine()?.trim();
    } finally {
      final bool? before = restoreEchoMode;
      if (before != null) stdin.echoMode = before;
      // 에코가 꺼져 Enter 의 줄바꿈이 보이지 않으므로 직접 한 줄 내린다.
      _output.writeln();
    }
  }

  @override
  int? choose(String question, List<String> options, {int? defaultIndex = 0}) {
    _output.writeln(question);
    for (int i = 0; i < options.length; i++) {
      _output.writeln('  ${i + 1}) ${options[i]}');
    }
    for (int attempt = 0; attempt < maxChoiceAttempts; attempt++) {
      // 기본값이 없으면 대괄호 안내를 빼서 Enter 로 고를 수 없음을 보인다.
      final String hint = defaultIndex == null ? '' : ' [${defaultIndex + 1}]';
      _output.write('번호를 고르세요$hint: ');
      final String? answer = _readLine();
      if (answer == null) {
        _output.writeln();
        return null;
      }
      final int? index = parseChoiceAnswer(
        answer,
        optionCount: options.length,
        defaultIndex: defaultIndex,
      );
      if (index != null) return index;
      _output.writeln('1 부터 ${options.length} 사이의 번호를 입력하세요.');
    }
    return null;
  }

  @override
  bool waitForEnter(String message) {
    _output.write('$message ');
    final String? answer = _readLine();
    if (answer == null) {
      _output.writeln();
      return false;
    }
    return true;
  }
}

/// 모든 화면 출력을 비밀 값 가림 뒤 [inner] 로 넘기고 실행 기록에도 남기는 터미널.
///
/// 위저드의 화면 출력은 이 감싸개 하나를 거친다 — 명령 줄 · 흘리는 출력 · 실패
/// 원문 · 질문 모두 [Redactor.apply] 뒤에 화면과 [LogSink] 로 간다. 사용자 답은
/// 가린 뒤 `in` 종류로 남긴다.
final class RedactingTerminal implements Terminal {
  /// [inner] 에 가린 문자열을 쓰고 [log] 에 같은 문자열을 남기는 터미널을 만든다.
  RedactingTerminal(this.inner, this.redactor, this.log);

  /// 실제로 출력하는 터미널.
  final Terminal inner;

  /// 비밀 값을 가리는 함수.
  final Redactor redactor;

  /// 실행 기록.
  final LogSink log;

  /// 입력이 끝났을 때 실행 기록에 남기는 답.
  static const String endOfInputRecord = '(입력 끝)';

  @override
  void writeLine(String line) {
    final String shown = redactor.apply(line);
    inner.writeLine(shown);
    log.write('out', shown);
  }

  @override
  void writeCommand(String display) {
    final String shown = redactor.apply(display);
    inner.writeCommand(shown);
    log.write('out', '  \$ $shown');
  }

  @override
  void writeRaw(String text) {
    final String shown = redactor.apply(text);
    inner.writeRaw(shown);
    if (shown.isNotEmpty) log.write('out', shown);
  }

  @override
  bool confirm(String question) {
    final String shown = redactor.apply(question);
    log.write('out', '$shown [y/N]');
    final bool answer = inner.confirm(shown);
    log.write('in', answer ? 'y' : 'n');
    return answer;
  }

  @override
  String? ask(String question, {String? defaultValue}) {
    final String shown = redactor.apply(question);
    final String? shownDefault = defaultValue == null
        ? null
        : redactor.apply(defaultValue);
    log.write('out', shownDefault == null ? shown : '$shown [$shownDefault]');
    final String? answer;
    if (defaultValue != null && shownDefault != defaultValue) {
      // 기본값이 비밀 값이면 화면에는 가린 값만 보이고, Enter 면 원래 값을 쓴다.
      final String? typed = inner.ask('$shown [$shownDefault]');
      answer = (typed != null && typed.isEmpty) ? defaultValue : typed;
    } else {
      answer = inner.ask(shown, defaultValue: defaultValue);
    }
    log.write('in', answer == null ? endOfInputRecord : redactor.apply(answer));
    return answer;
  }

  /// 받은 비밀 값은 바로 가림 함수에 등록하고, 실행 기록에는 값 대신
  /// `(비밀 값 <n>자)` 만 남긴다.
  @override
  String? askSecret(String question) {
    final String shown = redactor.apply(question);
    log.write('out', shown);
    final String? answer = inner.askSecret(shown);
    if (answer == null) {
      log.write('in', endOfInputRecord);
      return null;
    }
    redactor.register(answer);
    log.write('in', describeSecretInput(answer));
    return answer;
  }

  /// 비밀 값 입력을 실행 기록에 남길 모양 — 값 없이 글자 수만.
  static String describeSecretInput(String answer) =>
      '(비밀 값 ${answer.length}자)';

  @override
  int? choose(String question, List<String> options, {int? defaultIndex = 0}) {
    final String shown = redactor.apply(question);
    final List<String> shownOptions = options
        .map(redactor.apply)
        .toList(growable: false);
    log.write('out', shown);
    for (int i = 0; i < shownOptions.length; i++) {
      log.write('out', '  ${i + 1}) ${shownOptions[i]}');
    }
    final int? index = inner.choose(
      shown,
      shownOptions,
      defaultIndex: defaultIndex,
    );
    log.write('in', index == null ? endOfInputRecord : '${index + 1}');
    return index;
  }

  @override
  bool waitForEnter(String message) {
    final String shown = redactor.apply(message);
    log.write('out', shown);
    final bool isEntered = inner.waitForEnter(shown);
    log.write('in', isEntered ? 'Enter' : endOfInputRecord);
    return isEntered;
  }
}
