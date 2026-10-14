import 'command_runner.dart';
import 'step.dart';
import 'terminal.dart';

/// 모든 단계가 끝났을 때의 종료 코드.
const int wizardExitDone = 0;

/// 멈춤 · 거절 · 입력 끝 · 실패로 끝났을 때의 종료 코드.
const int wizardExitStopped = 1;

/// 위저드 밖 작업을 안내하고 끝났을 때의 종료 코드.
const int wizardExitForUser = 3;

/// 점검표 머리 줄.
const String checklistHeading = '점검표';

/// 모든 단계가 끝났을 때의 줄.
const String allDoneLine = '모든 단계가 끝났습니다.';

/// 단계를 시작하기 전에 묻는 질문.
const String stepConfirmQuestion = '이 단계를 진행할까요?';

/// 멈출 때의 마지막 줄.
const String stopLine = '같은 명령을 다시 실행하면 이어집니다.';

/// 위저드 밖 작업 안내 뒤에 붙는 줄.
const String exitForUserTailLine = '끝나면 ./setup.sh 를 다시 실행하세요 — 끝난 단계는 건너뜁니다.';

/// 단계 실행에 필요한 공용 문맥.
final class WizardContext {
  /// 저장소 루트 · 실행기 · 터미널로 문맥을 만든다.
  WizardContext({
    required this.projectRoot,
    required this.runner,
    required this.terminal,
  });

  /// 저장소 루트의 절대 경로.
  final String projectRoot;

  /// 외부 명령 실행기.
  final CommandRunner runner;

  /// 화면 입출력.
  final Terminal terminal;

  /// [relativePath] 를 저장소 루트 기준 절대 경로로 바꾼다.
  String resolve(String relativePath) {
    if (relativePath.startsWith('/')) return relativePath;
    return '$projectRoot/$relativePath';
  }
}

/// 점검표를 보이고 첫 할 일 단계부터 차례로 진행하는 위저드.
final class Wizard {
  /// [context] 로 [steps] 를 순서대로 진행하는 위저드를 만든다.
  Wizard(this.context, this.steps);

  /// 공용 문맥.
  final WizardContext context;

  /// 순서대로 진행할 단계 목록.
  final List<Step> steps;

  Terminal get _terminal => context.terminal;

  /// 위저드를 실행하고 종료 코드를 돌려준다.
  Future<int> run() async {
    final Map<String, CheckResult> results = await _checkAll();
    _printChecklist(results);
    if (results.values.every((CheckResult result) => result is Done)) {
      _terminal.writeLine(allDoneLine);
      return wizardExitDone;
    }
    for (final Step step in steps) {
      if (results[step.id] is Done) continue;
      final int? code = await _runStep(step);
      if (code != null) return code;
    }
    _terminal.writeLine('');
    _terminal.writeLine(allDoneLine);
    return wizardExitDone;
  }

  /// 모든 단계를 순서대로 검사한다.
  Future<Map<String, CheckResult>> _checkAll() async {
    final Map<String, CheckResult> results = <String, CheckResult>{};
    for (final Step step in steps) {
      results[step.id] = await _check(step);
    }
    return results;
  }

  /// 단계 하나를 검사한다 — 검사 중 예외는 할 일로 본다.
  Future<CheckResult> _check(Step step) async {
    try {
      return await step.check(context);
    } on Exception catch (e) {
      return Todo('검사하지 못했습니다 — $e');
    }
  }

  /// 점검표를 한 번 출력한다.
  void _printChecklist(Map<String, CheckResult> results) {
    _terminal.writeLine(checklistHeading);
    for (final Step step in steps) {
      _terminal.writeLine(_formatCheckLine(step, results[step.id]!));
    }
  }

  /// 점검표 한 줄을 만든다.
  String _formatCheckLine(Step step, CheckResult result) => switch (result) {
    Done(:final String summary) => '  ✓ ${step.title} — $summary',
    Todo(:final String reason) => '  ✗ ${step.title} — $reason',
    Blocked(:final String waitingFor) =>
      '  ? ${step.title} — $waitingFor 뒤에 검사합니다',
  };

  /// 단계 하나를 진행한다 — 계속하면 null, 끝내야 하면 종료 코드를 돌려준다.
  Future<int?> _runStep(Step step) async {
    final CheckResult current = await _check(step);
    if (current is Done) {
      _terminal.writeLine(_formatCheckLine(step, current));
      return null;
    }
    _terminal.writeLine('');
    _terminal.writeLine('▶ ${step.title}');
    if (current is Todo) {
      _terminal.writeLine('  ${current.reason}');
    } else if (current is Blocked) {
      _terminal.writeLine(_formatCheckLine(step, current));
      return _stop();
    }
    _printPlannedLines(step);
    if (!_terminal.confirm(stepConfirmQuestion)) return _stop();

    final StepOutcome outcome = await _apply(step);
    switch (outcome) {
      case Applied():
        final CheckResult after = await _check(step);
        if (after is Done) {
          _terminal.writeLine(_formatCheckLine(step, after));
          return null;
        }
        _printFailure(_describeIncomplete(after), null);
        return _stop();
      case ExitForUser(:final String guide):
        _terminal.writeLine(guide);
        _terminal.writeLine(exitForUserTailLine);
        return wizardExitForUser;
      case Failed(:final String summary, :final CommandResult? result):
        _printFailure(summary, result);
        return _stop();
      case WaitForUser(:final String guide):
        _terminal.writeLine(guide);
        return _stop();
      case Declined():
        return _stop();
    }
  }

  /// 단계를 실행한다 — 실행 중 예외는 실패로 본다.
  Future<StepOutcome> _apply(Step step) async {
    try {
      return await step.apply(context);
    } on Exception catch (e) {
      return Failed('실행하지 못했습니다 — $e');
    }
  }

  /// 단계가 실행할 명령 줄을 출력한다 — `(` 로 시작하는 줄은 안내 줄이다.
  void _printPlannedLines(Step step) {
    for (final String line in step.plannedCommandLines(context)) {
      if (line.startsWith('(')) {
        _terminal.writeLine('    $line');
      } else {
        _terminal.writeCommand(line);
      }
    }
  }

  /// 실행 뒤에도 끝나지 않은 상태를 한 줄로 설명한다.
  String _describeIncomplete(CheckResult result) => switch (result) {
    Done(:final String summary) => summary,
    Todo(:final String reason) => reason,
    Blocked(:final String waitingFor) => '$waitingFor 단계가 끝나지 않았습니다',
  };

  /// 실패 요약과 명령 출력 원문을 그대로 보인다.
  void _printFailure(String summary, CommandResult? result) {
    _terminal.writeLine('  실패 — $summary');
    if (result == null) return;
    for (final String text in <String>[result.stdout, result.stderr]) {
      if (text.isEmpty) continue;
      _terminal.writeRaw(text.endsWith('\n') ? text : '$text\n');
    }
  }

  /// 멈춤 줄을 출력하고 멈춤 종료 코드를 돌려준다.
  int _stop() {
    _terminal.writeLine(stopLine);
    return wizardExitStopped;
  }
}

/// [steps] 를 [context] 로 진행하고 종료 코드(0 · 1 · 3)를 돌려준다.
Future<int> runWizard(WizardContext context, List<Step> steps) =>
    Wizard(context, steps).run();
