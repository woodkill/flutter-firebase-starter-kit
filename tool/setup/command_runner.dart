import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'log_sink.dart';
import 'terminal.dart';

/// 실행할 외부 명령 하나 — 셸 없이 실행 파일과 인자 배열로만 실행한다.
final class Command {
  /// [executable] 을 [arguments] 로 실행하는 명령을 만든다.
  const Command(
    this.executable,
    this.arguments, {
    this.workingDirectory,
    this.stdinText,
    this.display,
    this.isOutputSensitive = false,
  });

  /// 실행 파일 이름 또는 경로.
  final String executable;

  /// 인자 배열 — 셸 해석을 거치지 않는다.
  final List<String> arguments;

  /// 작업 디렉터리. null 이면 현재 디렉터리.
  final String? workingDirectory;

  /// 표준 입력에 쓸 문자열. null 이면 아무것도 쓰지 않는다.
  final String? stdinText;

  /// 화면에 보일 표시형. null 이면 [executable] 과 [arguments] 로 조립한다.
  final String? display;

  /// 출력에 비밀 값이 섞일 수 있으면 true.
  final bool isOutputSensitive;

  /// 화면에 보일 명령 줄을 만든다.
  ///
  /// [display] 가 있으면 그 값을, 없으면 실행 파일과 인자를 공백으로 잇는다.
  /// 공백 · 따옴표 · 셸 특수 문자가 있는 인자는 작은따옴표로 감싼다.
  String render() {
    final String? shown = display;
    if (shown != null) return shown;
    return <String>[
      executable,
      ...arguments,
    ].map(quoteForShellDisplay).join(' ');
  }
}

/// 표시용으로 셸 인자 하나를 감싼다.
///
/// 공백 · 따옴표 · 셸 특수 문자가 있거나 비었으면 작은따옴표로 감싸고, 안의
/// 작은따옴표는 `'\''` 로 바꾼다. 화면에 보일 명령 줄을 만들 때만 쓴다 — 실제
/// 실행은 셸 없이 인자 배열로 한다.
String quoteForShellDisplay(String argument) {
  if (argument.isNotEmpty &&
      !RegExp(r'''[\s'"\\$`*?;&|<>(){}]''').hasMatch(argument)) {
    return argument;
  }
  return "'${argument.replaceAll("'", r"'\''")}'";
}

/// [output] 의 마지막 빈 줄 아닌 줄을 앞뒤 공백을 떼고 찾는다 — 없으면 null.
///
/// 스크립트의 마지막 줄 계약(`DEPLOY OK …` · `FAIL: …`)을 읽을 때 쓴다.
String? findLastOutputLine(String output) {
  final List<String> lines = const LineSplitter()
      .convert(output)
      .where((String line) => line.trim().isNotEmpty)
      .toList();
  return lines.isEmpty ? null : lines.last.trim();
}

/// 명령 실행 결과.
final class CommandResult {
  /// 종료 코드와 캡처한 출력으로 결과를 만든다.
  ///
  /// 출력이 실행 중에 이미 화면에 흘렀으면 [isOutputShown] 을 true 로 준다.
  const CommandResult(
    this.exitCode,
    this.stdout,
    this.stderr, {
    this.isOutputShown = false,
  });

  /// 종료 코드.
  final int exitCode;

  /// 캡처한 표준 출력.
  final String stdout;

  /// 캡처한 표준 오류.
  final String stderr;

  /// 출력이 실행 중에 이미 화면에 흘렀으면 true.
  ///
  /// 위저드는 실패 때 이 결과의 출력 원문을 다시 쓰지 않고 실패 요약 줄만
  /// 보인다. 캡처만 한 결과와 단계가 만든 결과는 false 라 원문을 보인다.
  final bool isOutputShown;

  /// 종료 코드가 0 이면 true.
  bool get isSuccess => exitCode == 0;

  /// 표준 출력을 뺀 사본을 만든다.
  ///
  /// [Command.isOutputSensitive] 명령의 결과를 실패 원문으로 화면에 보일 때
  /// 쓴다 — 민감 표시는 기록의 본문 생략에만 걸리므로, 화면에 넘기는 결과는
  /// 단계가 이 함수로 표준 출력을 떼고 오류 원문만 남긴다.
  CommandResult withoutStdout() =>
      CommandResult(exitCode, '', stderr, isOutputShown: isOutputShown);
}

/// 외부 명령 실행기 — 테스트는 가짜 구현을 주입한다.
abstract interface class CommandRunner {
  /// 검사용으로 실행한다 — 화면에 출력하지 않고 출력을 캡처한다.
  Future<CommandResult> capture(Command command);

  /// 대화형으로 실행한다 — 표준 입출력을 그대로 넘기고 종료 코드만 돌려준다.
  Future<int> interactive(Command command);

  /// 긴 명령을 실행한다 — 출력을 줄 단위로 화면에 흘리면서 모아 돌려준다.
  Future<CommandResult> stream(Command command);
}

/// `dart:io` 프로세스로 명령을 실행하는 실행기.
///
/// 모든 실행을 [log] 에 남긴다 — 명령 줄(`cmd`) · 종료 코드(`exit`), 캡처한
/// 출력(`stdout` · `stderr`). [Command.isOutputSensitive] 인 명령은 출력 본문 대신
/// [sensitiveOutputNotice] 를 남긴다. 흘리는 출력은 [terminal] 을 거쳐 화면과
/// 기록에 함께 남는다(위저드는 가림 터미널을 넘긴다).
final class ProcessCommandRunner implements CommandRunner {
  /// [terminal] 에 명령 줄과 흘리는 출력을 쓰고 [log] 에 실행을 남기는 실행기를
  /// 만든다.
  ProcessCommandRunner(this.terminal, {required this.log});

  /// 명령 줄 · 흘리는 출력을 쓸 터미널.
  final Terminal terminal;

  /// 실행 기록.
  final LogSink log;

  /// 실행 파일을 찾지 못했을 때의 종료 코드(셸 관례와 같다).
  static const int commandNotFoundExitCode = 127;

  /// 민감 출력 명령의 출력 본문 대신 기록에 남기는 문구.
  static const String sensitiveOutputNotice = '(민감 출력 생략)';

  @override
  Future<CommandResult> capture(Command command) async {
    log.write('cmd', command.render());
    CommandResult result;
    try {
      final Process process = await _start(command);
      result = await _collect(process, command, onLine: null);
    } on ProcessException catch (e) {
      result = CommandResult(commandNotFoundExitCode, '', e.message);
    }
    _logResult(command, result);
    return result;
  }

  @override
  Future<int> interactive(Command command) async {
    terminal.writeCommand(command.render());
    log.write('cmd', command.render());
    int code;
    try {
      final Process process = await Process.start(
        command.executable,
        command.arguments,
        workingDirectory: command.workingDirectory,
        mode: ProcessStartMode.inheritStdio,
      );
      code = await process.exitCode;
    } on ProcessException catch (e) {
      terminal.writeRaw('${e.message}\n');
      code = commandNotFoundExitCode;
    }
    log.write('exit', '$code');
    return code;
  }

  @override
  Future<CommandResult> stream(Command command) async {
    terminal.writeCommand(command.render());
    log.write('cmd', command.render());
    CommandResult result;
    try {
      final Process process = await _start(command);
      final CommandResult collected = await _collect(
        process,
        command,
        onLine: (String line) => terminal.writeRaw('$line\n'),
      );
      // 줄마다 이미 화면에 흘렸다 — 위저드가 실패 때 다시 쓰지 않게 표시한다.
      result = CommandResult(
        collected.exitCode,
        collected.stdout,
        collected.stderr,
        isOutputShown: true,
      );
    } on ProcessException catch (e) {
      terminal.writeRaw('${e.message}\n');
      result = CommandResult(
        commandNotFoundExitCode,
        '',
        e.message,
        isOutputShown: true,
      );
    }
    log.write('exit', '${result.exitCode}');
    return result;
  }

  /// 캡처 실행의 종료 코드와 출력을 기록에 남긴다.
  void _logResult(Command command, CommandResult result) {
    log.write('exit', '${result.exitCode}');
    final Map<String, String> outputs = <String, String>{
      'stdout': result.stdout,
      'stderr': result.stderr,
    };
    outputs.forEach((String kind, String text) {
      if (text.isEmpty) return;
      log.write(kind, command.isOutputSensitive ? sensitiveOutputNotice : text);
    });
  }

  /// 셸 없이 프로세스를 시작한다.
  Future<Process> _start(Command command) => Process.start(
    command.executable,
    command.arguments,
    workingDirectory: command.workingDirectory,
  );

  /// 표준 입력을 쓰고 닫은 뒤 출력을 모은다.
  ///
  /// 파이프 버퍼가 차서 멈추지 않도록 종료 코드를 기다리기 전에 출력 읽기를
  /// 먼저 시작한다. [onLine] 이 있으면 줄마다 부른다.
  Future<CommandResult> _collect(
    Process process,
    Command command, {
    required void Function(String line)? onLine,
  }) async {
    final Future<String> outFuture = _drain(process.stdout, onLine);
    final Future<String> errFuture = _drain(process.stderr, onLine);
    final String? input = command.stdinText;
    try {
      if (input != null) {
        process.stdin.write(input);
      }
      await process.stdin.close();
    } on IOException {
      // 프로세스가 입력을 읽기 전에 끝나면 파이프가 닫혀 있다 — 결과는 종료 코드로 판정한다.
    }
    final int code = await process.exitCode;
    return CommandResult(code, await outFuture, await errFuture);
  }

  /// 스트림을 줄 단위로 읽어 하나의 문자열로 모은다.
  Future<String> _drain(
    Stream<List<int>> source,
    void Function(String line)? onLine,
  ) async {
    final StringBuffer buffer = StringBuffer();
    await for (final String line
        in source
            .transform(const Utf8Decoder(allowMalformed: true))
            .transform(const LineSplitter())) {
      buffer.writeln(line);
      onLine?.call(line);
    }
    return buffer.toString();
  }
}
