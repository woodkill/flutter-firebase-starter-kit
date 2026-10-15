import 'dart:io';

import 'package:test/test.dart';

import '../../../tool/setup/command_runner.dart';
import '../../../tool/setup/redactor.dart';
import '../../../tool/setup/step.dart';
import '../../../tool/setup/terminal.dart';
import '../../../tool/setup/wizard.dart';
import 'fake_rest_client.dart';
import 'fakes.dart';

const String _stopLine = '같은 명령을 다시 실행하면 이어집니다.';
const String _confirmQuestion = '이 단계를 진행할까요?';
const String _waitMessage = '끝나면 Enter 를 누르세요';

/// 실제 명령이 찍는 고유 줄 — 가림 패턴에 걸리지 않는 평범한 영문 · 숫자다.
const String _markerLine = 'wizard-stream-marker-42';

/// 고유 줄을 찍고 3 으로 끝나는 셸 명령.
const Command _markerCommand = Command('/bin/sh', <String>[
  '-c',
  "printf '$_markerLine\\n'; exit 3",
]);

/// 실패 요약 줄의 요약 문구.
const String _commandFailureSummary = '흘린 명령 실패';

/// [text] 에서 [line] 과 똑같은 줄의 개수를 센다.
int _countExactLines(String text, String line) =>
    text.split('\n').where((String shown) => shown == line).length;

/// 실행이 실제 실행기로 명령을 돌리고 그 결과를 실패로 돌려주는 단계.
final class _CommandFailureStep implements Step {
  _CommandFailureStep(this.runCommand);

  /// 실행기로 명령을 돌려 결과를 받는 함수.
  final Future<CommandResult> Function(CommandRunner runner) runCommand;

  @override
  String get id => 'command';

  @override
  String get title => '명령 단계';

  @override
  List<String> get dependsOn => const <String>[];

  @override
  bool get isCostlyOrIrreversible => false;

  @override
  Future<CheckResult> check(WizardContext context) async => const Todo('할 일');

  @override
  List<String> plannedCommandLines(WizardContext context) => const <String>[
    'sh marker',
  ];

  @override
  Future<StepOutcome> apply(WizardContext context) async =>
      Failed(_commandFailureSummary, result: await runCommand(context.runner));
}

/// 검사 결과 · 실행 결과를 미리 정해 두는 테스트용 단계.
///
/// 큐는 앞에서부터 하나씩 쓰고, 마지막 하나는 계속 되풀이한다.
final class _ScriptedStep implements Step {
  _ScriptedStep(
    this.id, {
    required List<CheckResult> checks,
    List<StepOutcome> outcomes = const <StepOutcome>[Applied()],
    this.dependsOn = const <String>[],
    this.isCostlyOrIrreversible = false,
  }) : _checks = List<CheckResult>.of(checks),
       _outcomes = List<StepOutcome>.of(outcomes);

  final List<CheckResult> _checks;
  final List<StepOutcome> _outcomes;

  int checkCount = 0;
  int applyCount = 0;

  @override
  final String id;

  @override
  final List<String> dependsOn;

  @override
  String get title => id;

  @override
  final bool isCostlyOrIrreversible;

  @override
  Future<CheckResult> check(WizardContext context) async {
    checkCount++;
    return _checks.length > 1 ? _checks.removeAt(0) : _checks.first;
  }

  @override
  List<String> plannedCommandLines(WizardContext context) => <String>[
    'run-$id',
  ];

  @override
  Future<StepOutcome> apply(WizardContext context) async {
    applyCount++;
    return _outcomes.length > 1 ? _outcomes.removeAt(0) : _outcomes.first;
  }
}

void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('wizard_test_');
  });

  tearDown(() {
    tempDir.deleteSync(recursive: true);
  });

  /// [steps] 를 [inputs] 답으로 진행하고 종료 코드와 터미널을 돌려준다.
  Future<({int code, ScriptedTerminal terminal})> runSteps(
    List<Step> steps,
    List<String?> inputs,
  ) async {
    final ScriptedTerminal terminal = ScriptedTerminal(inputs);
    final int code = await runWizard(
      buildTestContext(projectRoot: tempDir.path, terminal: terminal),
      steps,
    );
    return (code: code, terminal: terminal);
  }

  test('T-19-WIZ-01 앞 단계가 끝나지 않은 단계는 검사하지 않고 ? 로 보인다', () async {
    final _ScriptedStep a = _ScriptedStep(
      'A',
      checks: const <CheckResult>[Todo('할 일')],
    );
    final _ScriptedStep b = _ScriptedStep(
      'B',
      checks: const <CheckResult>[Done('끝')],
      dependsOn: const <String>['A'],
    );

    final ({int code, ScriptedTerminal terminal}) run = await runSteps(<Step>[
      a,
      b,
    ], const <String?>[]);

    final String output = run.terminal.output.toString();
    expect(output, contains('  ✗ A — 할 일'));
    expect(output, contains('  ? B — A 뒤에 검사합니다'));
    expect(b.checkCount, 0);
    expect(run.code, wizardExitStopped);
  });

  test('T-19-WIZ-13 비용 · 되돌릴 수 없는 단계만 계획 줄 끝에 값 표 재확인 안내를 한 줄 보인다', () async {
    final _ScriptedStep plain = _ScriptedStep(
      'A',
      checks: const <CheckResult>[Todo('a'), Todo('a'), Done('a 끝')],
    );
    final _ScriptedStep costly = _ScriptedStep(
      'B',
      checks: const <CheckResult>[Todo('b'), Todo('b'), Done('b 끝')],
      isCostlyOrIrreversible: true,
    );

    final ({int code, ScriptedTerminal terminal}) run = await runSteps(
      <Step>[plain, costly],
      const <String?>['y', 'y'],
    );

    final String output = run.terminal.output.toString();
    final String noticeLine = '    $costlyStepNotice';
    expect(run.code, wizardExitDone);
    expect(_countExactLines(output, noticeLine), 1);
    expect(output.indexOf(noticeLine), greaterThan(output.indexOf('▶ B')));
    expect(
      output.indexOf(noticeLine),
      greaterThan(output.indexOf('  \$ run-B')),
    );
  });

  test('T-19-WIZ-02 점검표 뒤 첫 ✗ 단계부터 진행하고 ✓ 단계는 실행하지 않는다', () async {
    final _ScriptedStep a = _ScriptedStep(
      'A',
      checks: const <CheckResult>[Done('끝')],
    );
    final _ScriptedStep b = _ScriptedStep(
      'B',
      checks: const <CheckResult>[Todo('b'), Todo('b'), Done('b 끝')],
    );
    final _ScriptedStep c = _ScriptedStep(
      'C',
      checks: const <CheckResult>[Todo('c')],
    );

    final ({int code, ScriptedTerminal terminal}) run = await runSteps(
      <Step>[a, b, c],
      const <String?>['y'],
    );

    final String output = run.terminal.output.toString();
    expect(output.indexOf('▶ B'), greaterThanOrEqualTo(0));
    expect(output.indexOf('▶ C'), greaterThan(output.indexOf('▶ B')));
    expect(output, isNot(contains('▶ A')));
    expect(a.applyCount, 0);
    expect(b.applyCount, 1);
    expect(c.applyCount, 0);
    expect(run.code, wizardExitStopped);
  });

  test('T-19-WIZ-03 실패하면 출력 원문을 보이고 다시 시도 재검사가 할 일이면 다시 실행한다', () async {
    final _ScriptedStep a = _ScriptedStep(
      'A',
      checks: const <CheckResult>[Todo('a'), Todo('a'), Todo('a'), Done('a 끝')],
      outcomes: const <StepOutcome>[
        Failed('x', result: CommandResult(1, 'OUT', 'ERR')),
        Applied(),
      ],
    );

    final ({int code, ScriptedTerminal terminal}) run = await runSteps(
      <Step>[a],
      const <String?>['y', '1'],
    );

    final String output = run.terminal.output.toString();
    expect(output, contains('OUT'));
    expect(output, contains('ERR'));
    expect(output, contains('다시 시도'));
    expect(output, contains('멈춤'));
    expect(a.applyCount, 2);
    expect(a.checkCount, 4);
    expect(run.code, wizardExitDone);
  });

  group('T-19-WIZ-10 다시 시도는 먼저 다시 검사하고 끝났으면 실행하지 않는다', () {
    test('T-19-WIZ-10 재검사가 ✓ 면 ✓ 줄을 보이고 다음 단계로 간다', () async {
      final _ScriptedStep a = _ScriptedStep(
        'A',
        checks: const <CheckResult>[Todo('a'), Todo('a'), Done('밖에서 끝냄')],
        outcomes: const <StepOutcome>[
          Failed('x', result: CommandResult(1, 'OUT', 'ERR')),
        ],
      );
      final _ScriptedStep b = _ScriptedStep(
        'B',
        checks: const <CheckResult>[Todo('b')],
      );

      final ({int code, ScriptedTerminal terminal}) run = await runSteps(
        <Step>[a, b],
        const <String?>['y', '1'],
      );

      final String output = run.terminal.output.toString();
      expect(a.applyCount, 1);
      expect(a.checkCount, 3);
      expect(output, contains('  ✓ A — 밖에서 끝냄'));
      expect(
        output.indexOf('▶ B'),
        greaterThan(output.indexOf('  ✓ A — 밖에서 끝냄')),
      );
      expect(b.applyCount, 0);
      expect(run.code, wizardExitStopped);
    });

    test('T-19-WIZ-10 재검사가 ? 면 그 줄을 보이고 실행하지 않고 멈춘다', () async {
      final _ScriptedStep a = _ScriptedStep(
        'A',
        checks: const <CheckResult>[Todo('a'), Todo('a'), Blocked('C')],
        outcomes: const <StepOutcome>[
          Failed('x', result: CommandResult(1, 'OUT', 'ERR')),
        ],
      );

      final ({int code, ScriptedTerminal terminal}) run = await runSteps(
        <Step>[a],
        const <String?>['y', '1'],
      );

      final String output = run.terminal.output.toString();
      expect(a.applyCount, 1);
      expect(output, contains('  ? A — C 뒤에 검사합니다'));
      expect(output, contains(_stopLine));
      expect(run.code, wizardExitStopped);
    });
  });

  test('T-19-WIZ-11 실행 뒤 미완료에서 다시 시도 재검사가 ✓ 면 다시 실행하지 않는다', () async {
    final _ScriptedStep a = _ScriptedStep(
      'A',
      checks: const <CheckResult>[Todo('a'), Todo('a'), Todo('남음'), Done('끝')],
    );

    final ({int code, ScriptedTerminal terminal}) run = await runSteps(
      <Step>[a],
      const <String?>['y', '1'],
    );

    final String output = run.terminal.output.toString();
    expect(output, contains('  실패 — 남음'));
    expect(output.indexOf('  ✓ A — 끝'), greaterThan(output.indexOf('남음')));
    expect(a.applyCount, 1);
    expect(a.checkCount, 4);
    expect(run.code, wizardExitDone);
  });

  group('T-19-WIZ-04 실패 뒤 멈춤 · 입력 끝이면 자동 재시도 없이 1 로 끝난다', () {
    for (final ({String label, List<String?> inputs}) answer
        in <({String label, List<String?> inputs})>[
          (label: '멈춤', inputs: <String?>['y', '2']),
          (label: '입력 끝(EOF)', inputs: <String?>['y']),
        ]) {
      test('T-19-WIZ-04 ${answer.label}', () async {
        final _ScriptedStep a = _ScriptedStep(
          'A',
          checks: const <CheckResult>[Todo('a')],
          outcomes: const <StepOutcome>[
            Failed('x', result: CommandResult(1, 'OUT', 'ERR')),
          ],
        );

        final ({int code, ScriptedTerminal terminal}) run = await runSteps(
          <Step>[a],
          answer.inputs,
        );

        expect(run.code, wizardExitStopped);
        expect(run.terminal.output.toString(), contains(_stopLine));
        expect(a.applyCount, 1);
      });
    }
  });

  test('T-19-WIZ-05 실행 뒤 재검사가 여전히 할 일이면 사유를 보이고 실패 고르기로 간다', () async {
    final _ScriptedStep a = _ScriptedStep(
      'A',
      checks: const <CheckResult>[Todo('a'), Todo('a'), Todo('남음')],
    );

    final ({int code, ScriptedTerminal terminal}) run = await runSteps(
      <Step>[a],
      const <String?>['y', '2'],
    );

    final String output = run.terminal.output.toString();
    expect(output, contains('남음'));
    expect(output, contains('다시 시도'));
    expect(run.terminal.asks.length, 2);
    expect(run.terminal.asks.first, _confirmQuestion);
    expect(a.applyCount, 1);
    expect(run.code, wizardExitStopped);
  });

  group('T-19-WIZ-06 위저드 밖 짧은 작업은 Enter 뒤 그 자리에서 다시 검사한다', () {
    test('T-19-WIZ-06 다시 검사가 ✗ 면 다시 안내하고 ✓ 면 다음 단계로 간다', () async {
      final _ScriptedStep a = _ScriptedStep(
        'A',
        checks: const <CheckResult>[
          Todo('a'),
          Todo('a'),
          Todo('아직'),
          Done('a 끝'),
        ],
        outcomes: const <StepOutcome>[WaitForUser('안내')],
      );
      final _ScriptedStep b = _ScriptedStep(
        'B',
        checks: const <CheckResult>[Todo('b'), Todo('b'), Done('b 끝')],
      );

      final ({int code, ScriptedTerminal terminal}) run = await runSteps(
        <Step>[a, b],
        const <String?>['y', '', '', 'y'],
      );

      final String output = run.terminal.output.toString();
      expect('안내'.allMatches(output).length, 2);
      expect(output, contains('아직'));
      expect(
        run.terminal.asks.where((String ask) => ask == _waitMessage).length,
        2,
      );
      expect(output, contains('▶ B'));
      expect(a.applyCount, 1);
      expect(b.applyCount, 1);
      expect(run.code, wizardExitDone);
    });

    test('T-19-WIZ-06 기다리는 중 입력 끝이면 1 로 멈춘다', () async {
      final _ScriptedStep a = _ScriptedStep(
        'A',
        checks: const <CheckResult>[Todo('a')],
        outcomes: const <StepOutcome>[WaitForUser('안내')],
      );

      final ({int code, ScriptedTerminal terminal}) run = await runSteps(
        <Step>[a],
        const <String?>['y'],
      );

      expect(run.terminal.asks, contains(_waitMessage));
      expect(run.terminal.output.toString(), contains(_stopLine));
      expect(run.code, wizardExitStopped);
    });
  });

  test('T-19-WIZ-07 단계 안의 확인에서 거절하면 1 로 멈춘다', () async {
    final _ScriptedStep a = _ScriptedStep(
      'A',
      checks: const <CheckResult>[Todo('a')],
      outcomes: const <StepOutcome>[Declined()],
    );

    final ({int code, ScriptedTerminal terminal}) run = await runSteps(
      <Step>[a],
      const <String?>['y'],
    );

    expect(run.code, wizardExitStopped);
    expect(run.terminal.output.toString(), contains(_stopLine));
    expect(a.applyCount, 1);
  });

  test('T-19-WIZ-08 모든 단계가 ✓ 면 묻지 않고 실행하지 않고 0 으로 끝난다', () async {
    final _ScriptedStep a = _ScriptedStep(
      'A',
      checks: const <CheckResult>[Done('a 끝')],
    );
    final _ScriptedStep b = _ScriptedStep(
      'B',
      checks: const <CheckResult>[Done('b 끝')],
      dependsOn: const <String>['A'],
    );

    final ({int code, ScriptedTerminal terminal}) run = await runSteps(<Step>[
      a,
      b,
    ], const <String?>[]);

    expect(run.code, wizardExitDone);
    expect(run.terminal.output.toString(), contains('모든 단계가 끝났습니다.'));
    expect(run.terminal.asks, isNot(contains(_confirmQuestion)));
    expect(a.applyCount + b.applyCount, 0);
  });

  group('T-19-WIZ-09 단계 확인은 y · yes 만 진행한다', () {
    for (final ({String answer, bool proceeds}) entry
        in <({String answer, bool proceeds})>[
          (answer: 'yes', proceeds: true),
          (answer: 'Y', proceeds: true),
          (answer: 'n', proceeds: false),
          (answer: '', proceeds: false),
          (answer: 'ok', proceeds: false),
        ]) {
      test('T-19-WIZ-09 답 "${entry.answer}"', () async {
        final _ScriptedStep a = _ScriptedStep(
          'A',
          checks: const <CheckResult>[Todo('a'), Todo('a'), Done('a 끝')],
        );

        final ({int code, ScriptedTerminal terminal}) run = await runSteps(
          <Step>[a],
          <String?>[entry.answer],
        );

        expect(a.applyCount, entry.proceeds ? 1 : 0);
        expect(run.code, entry.proceeds ? wizardExitDone : wizardExitStopped);
      });
    }
  });

  group('T-19-WIZ-12 실시간으로 흘린 출력은 실패 때 다시 찍지 않는다', () {
    late Redactor redactor;
    late MemoryLogSink log;
    late ScriptedTerminal screen;
    late ProcessCommandRunner runner;
    late WizardContext context;

    setUp(() {
      redactor = Redactor();
      log = MemoryLogSink(redactor);
      screen = ScriptedTerminal(const <String?>['y']);
      final RedactingTerminal terminal = RedactingTerminal(
        screen,
        redactor,
        log,
      );
      runner = ProcessCommandRunner(terminal, log: log);
      context = WizardContext(
        projectRoot: tempDir.path,
        runner: runner,
        terminal: terminal,
        redactor: redactor,
        log: log,
        rest: FakeRestClient(),
      );
    });

    test('T-19-WIZ-12 흘린 실패 줄은 화면에 한 번 · 기록은 명령 · 출력 · 종료 코드 그대로', () async {
      final int code = await runWizard(context, <Step>[
        _CommandFailureStep(
          (CommandRunner commandRunner) => commandRunner.stream(_markerCommand),
        ),
      ]);

      final String shown = screen.output.toString();
      expect(_countExactLines(shown, _markerLine), 1);
      expect(_countExactLines(shown, '  실패 — $_commandFailureSummary'), 1);
      expect(
        log.lines.where((String line) => line.startsWith('[cmd] /bin/sh')),
        hasLength(1),
      );
      expect(log.lines, contains('[exit] 3'));
      expect(_countExactLines(log.text, '[out] $_markerLine'), 1);
      expect(log.lines, contains('[out]   실패 — $_commandFailureSummary'));
      expect(code, wizardExitStopped);
    });

    test('T-19-WIZ-12 캡처한 실패 출력은 지금처럼 원문으로 한 번 보인다', () async {
      final int code = await runWizard(context, <Step>[
        _CommandFailureStep(
          (CommandRunner commandRunner) =>
              commandRunner.capture(_markerCommand),
        ),
      ]);

      final String shown = screen.output.toString();
      expect(_countExactLines(shown, _markerLine), 1);
      expect(_countExactLines(shown, '  실패 — $_commandFailureSummary'), 1);
      expect(log.lines, contains('[exit] 3'));
      expect(log.lines, contains('[stdout] $_markerLine'));
      expect(code, wizardExitStopped);
    });

    test('T-19-WIZ-12 흘린 결과만 이미 보였다고 표시한다', () async {
      expect(const CommandResult(0, '', '').isOutputShown, isFalse);

      final CommandResult streamed = await runner.stream(_markerCommand);
      expect(streamed.exitCode, 3);
      expect(streamed.isOutputShown, isTrue);

      final CommandResult captured = await runner.capture(_markerCommand);
      expect(captured.exitCode, 3);
      expect(captured.isOutputShown, isFalse);

      final CommandResult missing = await runner.stream(
        Command('${tempDir.path}/missing-tool', const <String>[]),
      );
      expect(missing.exitCode, ProcessCommandRunner.commandNotFoundExitCode);
      expect(missing.isOutputShown, isTrue);
    });
  });
}
