import 'dart:async';
import 'dart:io';

import 'package:args/args.dart';

import '../tool/setup/command_runner.dart';
import '../tool/setup/completion.dart';
import '../tool/setup/flavor.dart';
import '../tool/setup/log_sink.dart';
import '../tool/setup/providers/provider_catalog.dart';
import '../tool/setup/redactor.dart';
import '../tool/setup/rest_client.dart';
import '../tool/setup/step.dart';
import '../tool/setup/steps/flavor_steps.dart';
import '../tool/setup/terminal.dart';
import '../tool/setup/wizard.dart';

/// 입력이 터미널이 아닐 때의 안내.
const String nonTerminalMessage =
    '터미널 앱에서 ./setup.sh 를 실행하세요 — 질문에 답해야 하는 위저드라 '
    '입력이 터미널이 아니면 시작하지 않습니다.';

/// 저장소 루트가 아닌 곳에서 실행했을 때의 안내.
const String notProjectRootMessage =
    '저장소 루트에서 ./setup.sh 를 실행하세요 — 지금 디렉터리에 pubspec.yaml · '
    'setup.sh 가 없습니다.';

/// 실행 기록 경로를 알리는 마지막 줄의 머리.
const String logPathLinePrefix = '실행 기록: ';

/// 실행 기록 파일을 만들지 못했을 때의 안내 머리.
const String logOpenFailedPrefix = '실행 기록 파일을 만들지 못했습니다 — ';

/// Ctrl-C 로 끝날 때의 종료 코드(셸 관례 128 + SIGINT 2).
const int interruptExitCode = 130;

/// Ctrl-C 처리 중 실행 기록을 닫지 못했을 때의 안내 머리.
const String interruptLogCloseFailedPrefix = '실행 기록을 닫지 못했습니다 — ';

/// 설정 위저드 진입점 — `./setup.sh` 가 FVM 의 Dart 로 실행한다.
///
/// 점검표를 먼저 보이고 첫 할 일 단계부터 차례로 진행한다. 실행마다
/// `.setup/logs/` 에 기록 파일 하나를 남기고 마지막 줄에 그 경로를 보인다. 종료
/// 코드는 0(모든 단계 끝) · 1(멈춤 · 거절 · 입력 끝 · 인자 오류) · 3(위저드 밖
/// 작업 안내 후 종료)이다.
Future<void> main(List<String> arguments) async {
  final ArgParser parser = ArgParser()
    ..addFlag('help', abbr: 'h', help: '사용법을 보여 줍니다.', negatable: false)
    ..addFlag(
      'providers',
      help: '로그인 수단 체크 목록을 엽니다 — 켜고 끌 수단을 고릅니다.',
      negatable: false,
    )
    ..addOption(
      'flavor',
      allowed: <String>[for (final Flavor flavor in Flavor.values) flavor.name],
      defaultsTo: Flavor.dev.name,
      help: '설정할 flavor — 그 flavor 의 Firebase 프로젝트에 같은 흐름을 적용합니다.',
    );

  final ArgResults results;
  try {
    results = parser.parse(arguments);
  } on FormatException catch (e) {
    writeArgumentError(parser, e.message);
    return;
  }
  // 허용 값은 parser 가 이미 걸렀다 — 그래도 읽지 못하면 인자 오류로 끝낸다.
  final String flavorName = results.option('flavor') ?? Flavor.dev.name;
  final Flavor? flavor = Flavor.tryParse(flavorName);
  if (flavor == null) {
    writeArgumentError(parser, '"$flavorName" 은 flavor 가 아닙니다.');
    return;
  }

  if (results.flag('help')) {
    stdout
      ..writeln('설정 위저드 — 개발 환경과 Firebase 설정을 차례로 준비합니다.')
      ..writeln('')
      ..writeln('사용법: ./setup.sh [옵션]')
      ..writeln(parser.usage);
    return;
  }

  final String projectRoot = Directory.current.path;
  if (!File('$projectRoot/pubspec.yaml').existsSync() ||
      !File('$projectRoot/setup.sh').existsSync()) {
    stderr.writeln(notProjectRootMessage);
    exitCode = wizardExitStopped;
    return;
  }

  final Redactor redactor = Redactor();
  final FileLogSink log;
  try {
    log = await FileLogSink.open(
      projectRoot: projectRoot,
      now: DateTime.now(),
      redactor: redactor,
    );
  } on FileSystemException catch (e) {
    final String? failedPath = e.path;
    stderr.writeln(
      failedPath == null
          ? '$logOpenFailedPrefix${e.message}'
          : '$logOpenFailedPrefix${e.message} ($failedPath)',
    );
    exitCode = wizardExitStopped;
    return;
  }

  final RedactingTerminal terminal = RedactingTerminal(
    StdioTerminal(),
    redactor,
    log,
  );
  int code = wizardExitStopped;
  try {
    if (!hasInteractiveTerminal()) {
      // 안내는 표준 오류로 내보내되, 같은 가림 · 기록 경로를 거친다.
      final RedactingTerminal errorTerminal = RedactingTerminal(
        StdioTerminal(output: stderr),
        redactor,
        log,
      );
      errorTerminal
        ..writeLine(nonTerminalMessage)
        ..writeLine('$logPathLinePrefix${log.path}');
      return;
    }

    // 숨김 입력 중 Ctrl-C 로 끝나도 사용자의 셸이 에코 꺼진 채 남지 않게 한다 —
    // Dart VM 은 종료할 때 터미널 에코를 되돌리지 않는다.
    final bool echoBefore = readStdinEchoMode();
    final StreamSubscription<ProcessSignal> interruptSubscription =
        ProcessSignal.sigint.watch().listen((ProcessSignal signal) {
          unawaited(
            handleInterrupt(
              writeEchoMode: writeStdinEchoMode,
              echoBefore: echoBefore,
              closeLog: log.close,
              exitProcess: exit,
            ),
          );
        });
    try {
      final ProcessCommandRunner runner = ProcessCommandRunner(
        terminal,
        log: log,
      );
      final HttpRestClient rest = HttpRestClient(
        tokens: AccessTokenSource(runner, redactor),
        terminal: terminal,
        log: log,
      );
      final WizardContext context = WizardContext(
        projectRoot: projectRoot,
        runner: runner,
        terminal: terminal,
        redactor: redactor,
        log: log,
        rest: rest,
        flavor: flavor,
      );
      context.session.isProviderSelectionRequested = results.flag('providers');
      // 로그인 수단을 바꾸면 위저드가 config 를 다시 읽어 단계 목록을 새로 만든다.
      List<Step> buildCurrentSteps() => buildSteps(
        flavor: flavor,
        enabledProviders: readEnabledProviders(
          context.resolve(context.paths.json),
        ),
      );
      try {
        code = await runWizard(
          context,
          buildCurrentSteps(),
          onCompleted: showCompletionSummary,
          rebuildSteps: buildCurrentSteps,
        );
      } finally {
        rest.close();
      }
      terminal.writeLine('$logPathLinePrefix${log.path}');
    } finally {
      // 신호 구독이 남아 있으면 Dart VM 이 끝나지 않는다.
      await interruptSubscription.cancel();
    }
  } finally {
    await log.close();
    exitCode = code;
  }
}

/// 인자 오류 [message] 와 사용법을 표준 오류에 쓰고 종료 코드를 멈춤(1)으로 둔다.
void writeArgumentError(ArgParser parser, String message) {
  stderr
    ..writeln('인자 오류: $message')
    ..writeln('')
    ..writeln('사용법: ./setup.sh [옵션]')
    ..writeln(parser.usage);
  exitCode = wizardExitStopped;
}

/// Ctrl-C 를 받았을 때 터미널을 되돌리고 끝낸다.
///
/// 순서: [writeEchoMode] 로 에코를 [echoBefore] 로 되돌림 → [closeLog] 로 실행
/// 기록 닫기(실패하면 표준 오류에 한 줄 남기고 넘어간다) → [exitProcess] 에
/// [interruptExitCode]. 에코 복구가 실패해도 종료는 일어난다.
Future<void> handleInterrupt({
  required EchoModeWriter writeEchoMode,
  required bool echoBefore,
  required Future<void> Function() closeLog,
  required void Function(int code) exitProcess,
}) async {
  try {
    writeEchoMode(echoBefore);
  } finally {
    try {
      await closeLog();
    } on Exception catch (e) {
      stderr.writeln('$interruptLogCloseFailedPrefix$e');
    }
    exitProcess(interruptExitCode);
  }
}

/// 표준 입력이 사용자가 답할 수 있는 터미널인지 확인한다.
///
/// `stdin.hasTerminal` 은 `/dev/null` 같은 문자 장치도 터미널로 판정하므로,
/// 터미널 에코 모드를 읽을 수 있는지까지 본다 — 터미널이 아니면 읽기가 실패한다.
bool hasInteractiveTerminal() {
  if (!stdin.hasTerminal) return false;
  try {
    stdin.echoMode;
    return true;
  } on StdinException {
    return false;
  }
}
