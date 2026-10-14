import '../../../tool/setup/command_runner.dart';
import '../../../tool/setup/terminal.dart';
import '../../../tool/setup/wizard.dart';

/// 가짜 실행기가 기록하는 실행 방식.
enum RunMode {
  /// 출력 캡처 검사.
  capture,

  /// 표준 입출력을 넘기는 대화형 실행.
  interactive,

  /// 출력을 흘리는 긴 실행.
  stream,
}

/// 가짜 실행기 호출 한 건.
final class FakeCall {
  /// 실행 방식 · 명령 키 · 표준 입력 문자열로 기록을 만든다.
  const FakeCall(this.mode, this.key, this.stdinText);

  /// 실행 방식.
  final RunMode mode;

  /// 실행 파일과 인자를 공백으로 이은 키.
  final String key;

  /// 명령에 실린 표준 입력 문자열.
  final String? stdinText;
}

/// 등록한 결과를 돌려주는 가짜 실행기 — 실제 프로세스를 띄우지 않는다.
final class FakeCommandRunner implements CommandRunner {
  final Map<String, List<CommandResult>> _results =
      <String, List<CommandResult>>{};

  /// 호출 기록(순서대로).
  final List<FakeCall> calls = <FakeCall>[];

  /// [key] 명령의 결과 큐에 [result] 를 더한다.
  ///
  /// 큐는 앞에서부터 하나씩 쓰고, 마지막 하나는 계속 되풀이한다.
  void on(String key, CommandResult result) {
    _results.putIfAbsent(key, () => <CommandResult>[]).add(result);
  }

  /// [mode] 로 불린 [key] 명령의 호출 수를 센다.
  int countCalls(RunMode mode, String key) => calls
      .where((FakeCall call) => call.mode == mode && call.key == key)
      .length;

  /// [mode] 로 불린 호출 수를 센다.
  int countMode(RunMode mode) =>
      calls.where((FakeCall call) => call.mode == mode).length;

  /// 명령을 키 문자열로 바꾼다.
  static String buildKey(Command command) =>
      <String>[command.executable, ...command.arguments].join(' ');

  CommandResult _take(RunMode mode, Command command) {
    final String key = buildKey(command);
    calls.add(FakeCall(mode, key, command.stdinText));
    final List<CommandResult>? queue = _results[key];
    if (queue == null || queue.isEmpty) {
      throw StateError('등록하지 않은 명령: $key');
    }
    return queue.length > 1 ? queue.removeAt(0) : queue.first;
  }

  @override
  Future<CommandResult> capture(Command command) async =>
      _take(RunMode.capture, command);

  @override
  Future<int> interactive(Command command) async =>
      _take(RunMode.interactive, command).exitCode;

  @override
  Future<CommandResult> stream(Command command) async =>
      _take(RunMode.stream, command);
}

/// 미리 정한 입력 줄을 차례로 돌려주는 가짜 터미널.
///
/// 입력이 떨어지거나 null 을 만나면 입력 끝(EOF)으로 본다.
final class ScriptedTerminal implements Terminal {
  /// [inputs] 를 앞에서부터 하나씩 답으로 쓴다.
  ScriptedTerminal(List<String?> inputs) : _inputs = List<String?>.of(inputs);

  final List<String?> _inputs;

  /// 지금까지의 화면 출력.
  final StringBuffer output = StringBuffer();

  /// 사용자에게 던진 질문 · 기다림 문구(순서대로).
  final List<String> asks = <String>[];

  String? _next() => _inputs.isEmpty ? null : _inputs.removeAt(0);

  @override
  void writeLine(String line) => output.writeln(line);

  @override
  void writeCommand(String display) => output.writeln('  \$ $display');

  @override
  void writeRaw(String text) => output.write(text);

  @override
  bool confirm(String question) {
    asks.add(question);
    output.writeln('$question [y/N] ');
    return parseYesAnswer(_next());
  }

  @override
  String? ask(String question, {String? defaultValue}) {
    asks.add(question);
    output.writeln(question);
    final String? answer = _next();
    if (answer == null) return null;
    final String trimmed = answer.trim();
    return trimmed.isEmpty ? (defaultValue ?? '') : trimmed;
  }

  @override
  int? choose(String question, List<String> options, {int defaultIndex = 0}) {
    asks.add(question);
    output.writeln(question);
    for (int i = 0; i < options.length; i++) {
      output.writeln('  ${i + 1}) ${options[i]}');
    }
    for (
      int attempt = 0;
      attempt < StdioTerminal.maxChoiceAttempts;
      attempt++
    ) {
      final String? answer = _next();
      if (answer == null) return null;
      final int? index = parseChoiceAnswer(
        answer,
        optionCount: options.length,
        defaultIndex: defaultIndex,
      );
      if (index != null) return index;
    }
    return null;
  }

  @override
  bool waitForEnter(String message) {
    asks.add(message);
    output.writeln(message);
    return _next() != null;
  }
}

/// 가짜 실행기 · 가짜 터미널로 위저드 문맥을 만든다.
WizardContext buildTestContext({
  required String projectRoot,
  FakeCommandRunner? runner,
  ScriptedTerminal? terminal,
}) => WizardContext(
  projectRoot: projectRoot,
  runner: runner ?? FakeCommandRunner(),
  terminal: terminal ?? ScriptedTerminal(const <String?>[]),
);
