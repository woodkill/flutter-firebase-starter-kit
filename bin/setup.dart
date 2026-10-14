import 'dart:io';

import 'package:args/args.dart';

import '../tool/setup/command_runner.dart';
import '../tool/setup/steps/dev_steps.dart';
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

/// 설정 위저드 진입점 — `./setup.sh` 가 FVM 의 Dart 로 실행한다.
///
/// 점검표를 먼저 보이고 첫 할 일 단계부터 차례로 진행한다. 종료 코드는
/// 0(모든 단계 끝) · 1(멈춤 · 거절 · 입력 끝 · 인자 오류) · 3(위저드 밖 작업
/// 안내 후 종료)이다.
Future<void> main(List<String> arguments) async {
  final ArgParser parser = ArgParser()
    ..addFlag('help', abbr: 'h', help: '사용법을 보여 줍니다.', negatable: false);

  final ArgResults results;
  try {
    results = parser.parse(arguments);
  } on FormatException catch (e) {
    stderr
      ..writeln('인자 오류: ${e.message}')
      ..writeln('')
      ..writeln('사용법: ./setup.sh [옵션]')
      ..writeln(parser.usage);
    exitCode = wizardExitStopped;
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

  if (!hasInteractiveTerminal()) {
    stderr.writeln(nonTerminalMessage);
    exitCode = wizardExitStopped;
    return;
  }

  final StdioTerminal terminal = StdioTerminal();
  final WizardContext context = WizardContext(
    projectRoot: projectRoot,
    runner: ProcessCommandRunner(terminal),
    terminal: terminal,
  );
  exitCode = await runWizard(context, buildDevSteps());
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
