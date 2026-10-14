import 'dart:math';

import 'command_runner.dart';
import 'log_sink.dart';
import 'redactor.dart';
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

/// 위저드 밖 짧은 작업을 기다릴 때의 문구.
const String waitForEnterMessage = '끝나면 Enter 를 누르세요';

/// 실패 뒤 고르기 질문.
const String failureChoiceQuestion = '어떻게 할까요?';

/// 실패 뒤 고르기의 다시 시도 선택지.
const String retryOption = '다시 시도';

/// 실패 뒤 고르기의 멈춤 선택지.
const String stopOption = '멈춤';

/// 단계 실행에 필요한 공용 문맥.
final class WizardContext {
  /// 저장소 루트 · 실행기 · 터미널 · 가림 함수 · 실행 기록으로 문맥을 만든다.
  ///
  /// [random] 을 주지 않으면 암호학적으로 안전한 난수를, [now] 를 주지 않으면
  /// 시스템 시각을 쓴다(테스트는 고정값을 넣는다).
  WizardContext({
    required this.projectRoot,
    required this.runner,
    required this.terminal,
    required this.redactor,
    required this.log,
    Random? random,
    DateTime Function()? now,
  }) : random = random ?? Random.secure(),
       now = now ?? DateTime.now;

  /// 저장소 루트의 절대 경로.
  final String projectRoot;

  /// 외부 명령 실행기.
  final CommandRunner runner;

  /// 화면 입출력 — 위저드는 가림 터미널을 넘긴다.
  final Terminal terminal;

  /// 화면 · 기록 직전에 비밀 값을 가리는 함수 — 단계가 아는 비밀 값을 등록한다.
  final Redactor redactor;

  /// 실행 기록.
  final LogSink log;

  /// 비밀 값 · 식별자를 만들 때 쓰는 난수.
  final Random random;

  /// 지금 시각을 돌려주는 함수.
  final DateTime Function() now;

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
  ///
  /// 의존 단계 가운데 이번 점검에서 끝나지 않은 것이 있으면 그 단계는 검사하지
  /// 않고 [Blocked] 로 적는다 — 앞 단계 없이 실패하는 검사 명령을 부르지 않는다.
  Future<Map<String, CheckResult>> _checkAll() async {
    final Map<String, CheckResult> results = <String, CheckResult>{};
    for (final Step step in steps) {
      final String? waitingFor = _findUnfinishedDependency(step, results);
      if (waitingFor == null) {
        results[step.id] = await _check(step);
      } else {
        final Blocked blocked = Blocked(waitingFor);
        _logCheck(step, blocked);
        results[step.id] = blocked;
      }
    }
    return results;
  }

  /// [step] 의 의존 단계 가운데 [results] 에서 끝나지 않은 첫 단계의 제목을 찾는다.
  String? _findUnfinishedDependency(
    Step step,
    Map<String, CheckResult> results,
  ) {
    for (final String dependency in step.dependsOn) {
      if (results[dependency] is Done) continue;
      return _findTitle(dependency);
    }
    return null;
  }

  /// [id] 단계의 제목을 찾는다 — 목록에 없으면 [id] 그대로.
  String _findTitle(String id) {
    for (final Step step in steps) {
      if (step.id == id) return step.title;
    }
    return id;
  }

  /// 단계 하나를 검사하고 판정을 기록에 남긴다 — 검사 중 예외는 할 일로 본다.
  Future<CheckResult> _check(Step step) async {
    CheckResult result;
    try {
      result = await step.check(context);
    } on Exception catch (e) {
      result = Todo('검사하지 못했습니다 — $e');
    }
    _logCheck(step, result);
    return result;
  }

  /// 검사 판정을 `<id> <✓|✗|?> <문장>` 꼴로 기록에 남긴다.
  void _logCheck(Step step, CheckResult result) {
    final String line = switch (result) {
      Done(:final String summary) => '✓ $summary',
      Todo(:final String reason) => '✗ $reason',
      Blocked(:final String waitingFor) => '? $waitingFor 뒤에 검사합니다',
    };
    context.log.write('check', '${step.id} $line');
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

    while (true) {
      final StepOutcome outcome = await _apply(step);
      switch (outcome) {
        case Applied():
          final CheckResult after = await _check(step);
          if (after is Done) {
            _terminal.writeLine(_formatCheckLine(step, after));
            return null;
          }
          _printFailure(_describeIncomplete(after), null);
          if (!_chooseRetry()) return _stop();
        case ExitForUser(:final String guide):
          _terminal.writeLine(guide);
          _terminal.writeLine(exitForUserTailLine);
          return wizardExitForUser;
        case WaitForUser(:final String guide):
          return _waitForUser(step, guide);
        case Failed(:final String summary, :final CommandResult? result):
          _printFailure(summary, result);
          if (!_chooseRetry()) return _stop();
        case Declined():
          return _stop();
      }
    }
  }

  /// 안내를 보이고 Enter 를 기다려 그 자리에서 다시 검사한다.
  ///
  /// 끝났으면 null, 입력 끝이면 멈춤 종료 코드를 돌려준다. 아직이면 사유를 보이고
  /// 다시 기다린다.
  Future<int?> _waitForUser(Step step, String guide) async {
    while (true) {
      _terminal.writeLine(guide);
      if (!_terminal.waitForEnter(waitForEnterMessage)) return _stop();
      final CheckResult after = await _check(step);
      if (after is Done) {
        _terminal.writeLine(_formatCheckLine(step, after));
        return null;
      }
      _terminal.writeLine('  아직 끝나지 않았습니다 — ${_describeIncomplete(after)}');
    }
  }

  /// 실패 뒤 다시 시도 · 멈춤을 고르게 한다 — 다시 시도면 true.
  bool _chooseRetry() {
    final int? choice = _terminal.choose(failureChoiceQuestion, const <String>[
      retryOption,
      stopOption,
    ], defaultIndex: 1);
    return choice == 0;
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
