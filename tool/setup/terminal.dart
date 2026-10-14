import 'dart:convert';
import 'dart:io';

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

  /// 번호로 고르게 한다 — 고른 0부터의 위치, 입력 끝이나 계속 틀리면 null.
  int? choose(String question, List<String> options, {int defaultIndex = 0});

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
/// 빈 답은 [defaultIndex], 1부터 [optionCount] 사이의 숫자는 0부터의 위치,
/// 그 밖은 null 이다.
int? parseChoiceAnswer(
  String answer, {
  required int optionCount,
  required int defaultIndex,
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
  int? choose(String question, List<String> options, {int defaultIndex = 0}) {
    _output.writeln(question);
    for (int i = 0; i < options.length; i++) {
      _output.writeln('  ${i + 1}) ${options[i]}');
    }
    for (int attempt = 0; attempt < maxChoiceAttempts; attempt++) {
      _output.write('번호를 고르세요 [${defaultIndex + 1}]: ');
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
