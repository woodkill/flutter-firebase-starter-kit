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

/// 미룰 수 있는 테스트용 단계의 진행 선택지.
const String _proceedLabel = '지금 진행';

/// 미룰 수 있는 테스트용 단계의 미루기 선택지.
const String _deferLabel = '지금 안 함';

/// 끝난 뒤 함수가 찍는 줄.
const String _completionLine = '끝 요약';

/// 할 일일 때 진행 · 미루기 · 멈춤을 고르게 하는 테스트용 단계.
final class _DeferrableScriptedStep extends _ScriptedStep
    implements DeferrableStep {
  _DeferrableScriptedStep(super.id, {required super.checks});

  @override
  String get proceedLabel => _proceedLabel;

  @override
  String get deferLabel => _deferLabel;
}

/// 끝 목록 [lines] 가 붙는 출력 끝부분(빈 줄 · 안내 줄 · 머리 · 줄들)을 만든다.
String _buildRemainingTail(List<String> lines) =>
    '\n\n$remainingDoneLine\n$remainingHeading\n'
    '${lines.map((String line) => '$line\n').join()}';

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
    final terminal = ScriptedTerminal(inputs);
    final int code = await runWizard(
      buildTestContext(projectRoot: tempDir.path, terminal: terminal),
      steps,
    );
    return (code: code, terminal: terminal);
  }

  /// [steps] 를 [inputs] 답으로 진행하고 끝난 뒤 함수가 불린 횟수도 돌려준다.
  ///
  /// 끝난 뒤 함수는 [_completionLine] 을 한 줄 찍는다.
  Future<({int code, ScriptedTerminal terminal, int completions})>
  runStepsWithCompletion(
    List<Step> steps,
    List<String?> inputs, {
    StepListBuilder? rebuildSteps,
  }) async {
    final terminal = ScriptedTerminal(inputs);
    var completions = 0;
    final int code = await runWizard(
      buildTestContext(projectRoot: tempDir.path, terminal: terminal),
      steps,
      onCompleted: (WizardContext context) async {
        completions++;
        context.terminal.writeLine(_completionLine);
      },
      rebuildSteps: rebuildSteps,
    );
    return (code: code, terminal: terminal, completions: completions);
  }

  test('T-19-WIZ-01 앞 단계가 끝나지 않은 단계는 검사하지 않고 ? 로 보인다', () async {
    final a = _ScriptedStep('A', checks: const <CheckResult>[Todo('할 일')]);
    final b = _ScriptedStep(
      'B',
      checks: const <CheckResult>[Done('끝')],
      dependsOn: const <String>['A'],
    );

    final ({int code, ScriptedTerminal terminal}) run = await runSteps(<Step>[
      a,
      b,
    ], const <String?>[]);

    final output = run.terminal.output.toString();
    expect(output, contains('  ✗ A — 할 일'));
    expect(output, contains('  ? B — A 뒤에 검사합니다'));
    expect(b.checkCount, 0);
    expect(run.code, wizardExitStopped);
  });

  test('T-19-WIZ-13 비용 · 되돌릴 수 없는 단계만 계획 줄 끝에 값 표 재확인 안내를 한 줄 보인다', () async {
    final plain = _ScriptedStep(
      'A',
      checks: const <CheckResult>[Todo('a'), Todo('a'), Done('a 끝')],
    );
    final costly = _ScriptedStep(
      'B',
      checks: const <CheckResult>[Todo('b'), Todo('b'), Done('b 끝')],
      isCostlyOrIrreversible: true,
    );

    final ({int code, ScriptedTerminal terminal}) run = await runSteps(
      <Step>[plain, costly],
      const <String?>['y', 'y'],
    );

    final output = run.terminal.output.toString();
    const noticeLine = '    $costlyStepNotice';
    expect(run.code, wizardExitDone);
    expect(_countExactLines(output, noticeLine), 1);
    expect(output.indexOf(noticeLine), greaterThan(output.indexOf('▶ B')));
    expect(
      output.indexOf(noticeLine),
      greaterThan(output.indexOf(r'  $ run-B')),
    );
  });

  test('T-19-WIZ-02 점검표 뒤 첫 ✗ 단계부터 진행하고 ✓ 단계는 실행하지 않는다', () async {
    final a = _ScriptedStep('A', checks: const <CheckResult>[Done('끝')]);
    final b = _ScriptedStep(
      'B',
      checks: const <CheckResult>[Todo('b'), Todo('b'), Done('b 끝')],
    );
    final c = _ScriptedStep('C', checks: const <CheckResult>[Todo('c')]);

    final ({int code, ScriptedTerminal terminal}) run = await runSteps(
      <Step>[a, b, c],
      const <String?>['y'],
    );

    final output = run.terminal.output.toString();
    expect(output.indexOf('▶ B'), greaterThanOrEqualTo(0));
    expect(output.indexOf('▶ C'), greaterThan(output.indexOf('▶ B')));
    expect(output, isNot(contains('▶ A')));
    expect(a.applyCount, 0);
    expect(b.applyCount, 1);
    expect(c.applyCount, 0);
    expect(run.code, wizardExitStopped);
  });

  test('T-19-WIZ-03 실패하면 출력 원문을 보이고 다시 시도 재검사가 할 일이면 다시 실행한다', () async {
    final a = _ScriptedStep(
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

    final output = run.terminal.output.toString();
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
      final a = _ScriptedStep(
        'A',
        checks: const <CheckResult>[Todo('a'), Todo('a'), Done('밖에서 끝냄')],
        outcomes: const <StepOutcome>[
          Failed('x', result: CommandResult(1, 'OUT', 'ERR')),
        ],
      );
      final b = _ScriptedStep('B', checks: const <CheckResult>[Todo('b')]);

      final ({int code, ScriptedTerminal terminal}) run = await runSteps(
        <Step>[a, b],
        const <String?>['y', '1'],
      );

      final output = run.terminal.output.toString();
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

    test(
      'T-19-WIZ-10 단계 check 가 Blocked 를 돌려주면 StateError 다(점검표 전용 판정)',
      () async {
        final a = _ScriptedStep(
          'A',
          checks: const <CheckResult>[Todo('a'), Todo('a'), Blocked('C')],
          outcomes: const <StepOutcome>[
            Failed('x', result: CommandResult(1, 'OUT', 'ERR')),
          ],
        );

        await expectLater(
          runSteps(<Step>[a], const <String?>['y', '1']),
          throwsA(
            isA<StateError>().having(
              (StateError error) => error.message,
              'message',
              contains('A 단계의 check 가 Blocked'),
            ),
          ),
        );
        expect(a.applyCount, 1);
      },
    );
  });

  group('T-19-WIZ-14 단계 check 의 Blocked 는 어느 검사 자리에서든 StateError 다', () {
    /// [step] 을 [inputs] 답으로 돌렸을 때 Blocked 계약 오류가 나는지 본다.
    Future<void> expectBlockedCheckError(
      _ScriptedStep step,
      List<String?> inputs,
    ) => expectLater(
      runSteps(<Step>[step], inputs),
      throwsA(
        isA<StateError>().having(
          (StateError error) => error.message,
          'message',
          contains('${step.id} 단계의 check 가 Blocked'),
        ),
      ),
    );

    test('T-19-WIZ-14 점검표 검사', () async {
      final a = _ScriptedStep('A', checks: const <CheckResult>[Blocked('C')]);

      await expectBlockedCheckError(a, const <String?>[]);
      expect(a.checkCount, 1);
      expect(a.applyCount, 0);
    });

    test('T-19-WIZ-14 실행 뒤 재검사', () async {
      final a = _ScriptedStep(
        'A',
        checks: const <CheckResult>[Todo('a'), Todo('a'), Blocked('C')],
      );

      await expectBlockedCheckError(a, const <String?>['y']);
      expect(a.applyCount, 1);
    });

    test('T-19-WIZ-14 Enter 대기 뒤 재검사', () async {
      final a = _ScriptedStep(
        'A',
        checks: const <CheckResult>[Todo('a'), Todo('a'), Blocked('C')],
        outcomes: const <StepOutcome>[WaitForUser('안내')],
      );

      await expectBlockedCheckError(a, const <String?>['y', '']);
      expect(a.applyCount, 1);
    });
  });

  test('T-19-WIZ-11 실행 뒤 미완료에서 다시 시도 재검사가 ✓ 면 다시 실행하지 않는다', () async {
    final a = _ScriptedStep(
      'A',
      checks: const <CheckResult>[Todo('a'), Todo('a'), Todo('남음'), Done('끝')],
    );

    final ({int code, ScriptedTerminal terminal}) run = await runSteps(
      <Step>[a],
      const <String?>['y', '1'],
    );

    final output = run.terminal.output.toString();
    expect(output, contains('  실패 — 남음'));
    expect(output.indexOf('  ✓ A — 끝'), greaterThan(output.indexOf('남음')));
    expect(a.applyCount, 1);
    expect(a.checkCount, 4);
    expect(run.code, wizardExitDone);
  });

  group('T-19-WIZ-04 실패 뒤 멈춤 · 입력 끝이면 자동 재시도 없이 1 로 끝난다', () {
    for (final answer in <({String label, List<String?> inputs})>[
      (label: '멈춤', inputs: <String?>['y', '2']),
      (label: '입력 끝(EOF)', inputs: <String?>['y']),
    ]) {
      test('T-19-WIZ-04 ${answer.label}', () async {
        final a = _ScriptedStep(
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
    final a = _ScriptedStep(
      'A',
      checks: const <CheckResult>[Todo('a'), Todo('a'), Todo('남음')],
    );

    final ({int code, ScriptedTerminal terminal}) run = await runSteps(
      <Step>[a],
      const <String?>['y', '2'],
    );

    final output = run.terminal.output.toString();
    expect(output, contains('남음'));
    expect(output, contains('다시 시도'));
    expect(run.terminal.asks.length, 2);
    expect(run.terminal.asks.first, _confirmQuestion);
    expect(a.applyCount, 1);
    expect(run.code, wizardExitStopped);
  });

  group('T-19-WIZ-06 위저드 밖 짧은 작업은 Enter 뒤 그 자리에서 다시 검사한다', () {
    test('T-19-WIZ-06 다시 검사가 ✗ 면 다시 안내하고 ✓ 면 다음 단계로 간다', () async {
      final a = _ScriptedStep(
        'A',
        checks: const <CheckResult>[
          Todo('a'),
          Todo('a'),
          Todo('아직'),
          Done('a 끝'),
        ],
        outcomes: const <StepOutcome>[WaitForUser('안내')],
      );
      final b = _ScriptedStep(
        'B',
        checks: const <CheckResult>[Todo('b'), Todo('b'), Done('b 끝')],
      );

      final ({int code, ScriptedTerminal terminal}) run = await runSteps(
        <Step>[a, b],
        const <String?>['y', '', '', 'y'],
      );

      final output = run.terminal.output.toString();
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
      final a = _ScriptedStep(
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
    final a = _ScriptedStep(
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
    final a = _ScriptedStep('A', checks: const <CheckResult>[Done('a 끝')]);
    final b = _ScriptedStep(
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
    for (final entry in <({String answer, bool proceeds})>[
      (answer: 'yes', proceeds: true),
      (answer: 'Y', proceeds: true),
      (answer: 'n', proceeds: false),
      (answer: '', proceeds: false),
      (answer: 'ok', proceeds: false),
    ]) {
      test('T-19-WIZ-09 답 "${entry.answer}"', () async {
        final a = _ScriptedStep(
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
      final terminal = RedactingTerminal(screen, redactor, log);
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

      final shown = screen.output.toString();
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

      final shown = screen.output.toString();
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

  test(
    'T-20-ENGINE-01: 할 수 없는 단계는 ✗ 로 보이고 실행하지 않고 다음 단계로 가며 끝 목록에 남는다',
    () async {
      const deferredLine = '  ✗ B — 지문이 없습니다';
      final a = _ScriptedStep('A', checks: const <CheckResult>[Done('a 끝')]);
      final b = _ScriptedStep(
        'B',
        checks: const <CheckResult>[Deferred('지문이 없습니다')],
      );
      final c = _ScriptedStep(
        'C',
        checks: const <CheckResult>[Todo('c'), Todo('c'), Done('c 끝')],
      );

      final ({int code, ScriptedTerminal terminal, int completions}) run =
          await runStepsWithCompletion(<Step>[a, b, c], const <String?>['y']);

      final output = run.terminal.output.toString();
      expect(run.code, wizardExitDone);
      expect(run.completions, 1);
      expect(b.applyCount, 0);
      expect(c.applyCount, 1);
      expect(output, isNot(contains('▶ B')));
      expect(output.indexOf(deferredLine), lessThan(output.indexOf('▶ C')));
      expect(
        output,
        endsWith(
          '${_buildRemainingTail(<String>[deferredLine])}'
          '$_completionLine\n',
        ),
      );
      expect(output, isNot(contains(allDoneLine)));
      expect(output, isNot(contains(_stopLine)));
    },
  );

  test(
    'T-20-ENGINE-02: 확인할 수 없는 단계는 ? 로 보이고 묻지도 실행하지도 않으며 ✓ 가 되지 않는다',
    () async {
      const unverifiableLine = '  ? A — 콘솔 업로드 — 확인은 실기기 알림';
      final a = _ScriptedStep(
        'A',
        checks: const <CheckResult>[Unverifiable('콘솔 업로드 — 확인은 실기기 알림')],
      );

      final ({int code, ScriptedTerminal terminal, int completions}) run =
          await runStepsWithCompletion(<Step>[a], const <String?>[]);

      final output = run.terminal.output.toString();
      expect(run.code, wizardExitDone);
      expect(run.completions, 1);
      expect(a.applyCount, 0);
      expect(run.terminal.asks, isEmpty);
      expect(output, startsWith('$checklistHeading\n$unverifiableLine\n'));
      expect(output, isNot(contains('  ✓ A')));
      expect(
        output,
        endsWith(
          '${_buildRemainingTail(<String>[unverifiableLine])}'
          '$_completionLine\n',
        ),
      );
    },
  );

  group('T-20-ENGINE-03: 미룰 수 있는 할 일은 진행 · 미루기 · 멈춤을 고른다', () {
    test('T-20-ENGINE-03: 미루면 ✗ 줄을 보이고 다음 단계로 가며 끝 목록에 남는다', () async {
      const deferredLine = '  ✗ A — $_deferLabel';
      final a = _DeferrableScriptedStep(
        'A',
        checks: const <CheckResult>[Todo('a 할 일')],
      );
      final b = _ScriptedStep(
        'B',
        checks: const <CheckResult>[Todo('b'), Todo('b'), Done('b 끝')],
      );

      final ({int code, ScriptedTerminal terminal, int completions}) run =
          await runStepsWithCompletion(<Step>[a, b], const <String?>['2', 'y']);

      final output = run.terminal.output.toString();
      expect(run.terminal.asks, <String>[
        failureChoiceQuestion,
        _confirmQuestion,
      ]);
      expect(output, contains('  1) $_proceedLabel\n'));
      expect(output, contains('  2) $_deferLabel\n'));
      expect(output, contains('  3) $stopOption\n'));
      expect(a.applyCount, 0);
      expect(b.applyCount, 1);
      expect(output.indexOf(deferredLine), lessThan(output.indexOf('▶ B')));
      expect(run.code, wizardExitDone);
      expect(run.completions, 1);
      expect(
        output,
        endsWith(
          '${_buildRemainingTail(<String>[deferredLine])}'
          '$_completionLine\n',
        ),
      );
    });

    test('T-20-ENGINE-03: 미룸은 저장하지 않아 같은 문맥으로 다시 돌리면 다시 ✗ 다', () async {
      final terminal = ScriptedTerminal(const <String?>['2', '2']);
      final WizardContext context = buildTestContext(
        projectRoot: tempDir.path,
        terminal: terminal,
      );
      final a = _DeferrableScriptedStep(
        'A',
        checks: const <CheckResult>[Todo('a 할 일')],
      );

      final int first = await runWizard(context, <Step>[a]);
      final int second = await runWizard(context, <Step>[a]);

      final output = terminal.output.toString();
      expect(first, wizardExitDone);
      expect(second, wizardExitDone);
      expect(_countExactLines(output, '  ✗ A — a 할 일'), 2);
      expect(
        terminal.asks.where((String ask) => ask == failureChoiceQuestion),
        hasLength(2),
      );
      expect(a.applyCount, 0);
      expect(tempDir.listSync(), isEmpty);
    });

    test('T-20-ENGINE-03: 같은 실행에서 단계 목록을 다시 짜도 미룬 단계는 다시 묻지 않는다', () async {
      const deferredLine = '  ✗ A — $_deferLabel';
      final a = _DeferrableScriptedStep(
        'A',
        checks: const <CheckResult>[Todo('a 할 일')],
      );
      final b = _ScriptedStep(
        'B',
        checks: const <CheckResult>[Todo('b')],
        outcomes: const <StepOutcome>[Replan()],
      );
      final rebuiltB = _ScriptedStep(
        'B',
        checks: const <CheckResult>[Done('b 끝')],
      );

      final ({int code, ScriptedTerminal terminal, int completions}) run =
          await runStepsWithCompletion(
            <Step>[a, b],
            const <String?>['2', 'y'],
            rebuildSteps: () => <Step>[a, rebuiltB],
          );

      final output = run.terminal.output.toString();
      expect(output, contains(replanLine));
      expect(
        run.terminal.asks.where((String ask) => ask == failureChoiceQuestion),
        hasLength(1),
      );
      expect(a.applyCount, 0);
      expect(run.code, wizardExitDone);
      expect(run.completions, 1);
      expect(
        output,
        endsWith(
          '${_buildRemainingTail(<String>[deferredLine])}'
          '$_completionLine\n',
        ),
      );
    });
  });

  group('T-20-ENGINE-04: 미루기 고르기는 기본값이 없고 멈춤 · 입력 끝이면 1 로 멈춘다', () {
    for (final answer in <({String label, List<String?> inputs})>[
      (label: 'Enter 뒤 멈춤', inputs: <String?>['', '3']),
      (label: '입력 끝(EOF)', inputs: <String?>[]),
    ]) {
      test('T-20-ENGINE-04: ${answer.label}', () async {
        final a = _DeferrableScriptedStep(
          'A',
          checks: const <CheckResult>[Todo('a 할 일')],
        );
        final b = _ScriptedStep('B', checks: const <CheckResult>[Todo('b')]);

        final ({int code, ScriptedTerminal terminal, int completions}) run =
            await runStepsWithCompletion(<Step>[a, b], answer.inputs);

        final output = run.terminal.output.toString();
        expect(run.code, wizardExitStopped);
        expect(output, contains(_stopLine));
        expect(output, isNot(contains('▶ B')));
        expect(a.applyCount, 0);
        expect(run.completions, 0);
      });
    }

    test('T-20-ENGINE-04: Enter 는 고르지 않은 것이라 다시 묻는다', () async {
      final a = _DeferrableScriptedStep(
        'A',
        checks: const <CheckResult>[Todo('a 할 일')],
      );

      final ({int code, ScriptedTerminal terminal, int completions}) run =
          await runStepsWithCompletion(<Step>[a], const <String?>['', '2']);

      expect(a.applyCount, 0);
      expect(run.code, wizardExitDone);
      expect(run.terminal.output.toString(), contains('  ✗ A — $_deferLabel'));
    });
  });

  test(
    'T-20-ENGINE-05: 미룰 수 있는 단계에서 진행을 고르면 실행하고 재검사 ✓ 면 모든 단계가 끝난다',
    () async {
      final a = _DeferrableScriptedStep(
        'A',
        checks: const <CheckResult>[Todo('a'), Todo('a'), Done('a 끝')],
      );

      final ({int code, ScriptedTerminal terminal, int completions}) run =
          await runStepsWithCompletion(<Step>[a], const <String?>['1']);

      final output = run.terminal.output.toString();
      expect(a.applyCount, 1);
      expect(run.code, wizardExitDone);
      expect(run.completions, 1);
      expect(output, contains('  ✓ A — a 끝'));
      expect(output, endsWith('\n\n$allDoneLine\n$_completionLine\n'));
      expect(output, isNot(contains(remainingHeading)));
    },
  );

  test('T-20-ENGINE-06: 실행이 나중에로 끝나면 ✗ 줄을 보이고 다음 단계로 가며 0 으로 끝난다', () async {
    const deferredLine = '  ✗ A — 나중에';
    final a = _ScriptedStep(
      'A',
      checks: const <CheckResult>[Todo('a')],
      outcomes: const <StepOutcome>[DeferredByUser('나중에')],
    );
    final b = _ScriptedStep(
      'B',
      checks: const <CheckResult>[Todo('b'), Todo('b'), Done('b 끝')],
    );

    final ({int code, ScriptedTerminal terminal, int completions}) run =
        await runStepsWithCompletion(<Step>[a, b], const <String?>['y', 'y']);

    final output = run.terminal.output.toString();
    expect(a.applyCount, 1);
    expect(b.applyCount, 1);
    expect(output.indexOf(deferredLine), lessThan(output.indexOf('▶ B')));
    expect(output, isNot(contains(_stopLine)));
    expect(run.code, wizardExitDone);
    expect(run.completions, 1);
    expect(
      output,
      endsWith(
        '${_buildRemainingTail(<String>[deferredLine])}'
        '$_completionLine\n',
      ),
    );
  });

  group('T-20-ENGINE-07: 남은 일이 없으면 끝 출력이 지금과 같다', () {
    test('T-20-ENGINE-07: 점검표에서 모두 ✓', () async {
      final ({int code, ScriptedTerminal terminal, int completions}) run =
          await runStepsWithCompletion(<Step>[
            _ScriptedStep('A', checks: const <CheckResult>[Done('a 끝')]),
            _ScriptedStep('B', checks: const <CheckResult>[Done('b 끝')]),
          ], const <String?>[]);

      expect(run.code, wizardExitDone);
      expect(run.completions, 1);
      expect(
        run.terminal.output.toString(),
        '$checklistHeading\n'
        '  ✓ A — a 끝\n'
        '  ✓ B — b 끝\n'
        '$allDoneLine\n'
        '$_completionLine\n',
      );
    });

    test('T-20-ENGINE-07: 할 일을 진행해 모두 ✓', () async {
      final ({int code, ScriptedTerminal terminal, int completions}) run =
          await runStepsWithCompletion(
            <Step>[
              _ScriptedStep(
                'A',
                checks: const <CheckResult>[Todo('a'), Todo('a'), Done('a 끝')],
              ),
            ],
            const <String?>['y'],
          );

      expect(run.code, wizardExitDone);
      expect(run.completions, 1);
      expect(
        run.terminal.output.toString(),
        '$checklistHeading\n'
        '  ✗ A — a\n'
        '\n'
        '▶ A\n'
        '  a\n'
        '  \$ run-A\n'
        '$_confirmQuestion [y/N] \n'
        '  ✓ A — a 끝\n'
        '\n'
        '$allDoneLine\n'
        '$_completionLine\n',
      );
    });
  });

  group(
    'T-20-ENGINE-08: 앞 단계가 이번 실행에서 ✓ 로 끝나지 않으면 뒤 단계는 검사 · 실행하지 않고 ? 로 남는다',
    () {
      for (final entry
          in <({String label, Step a, List<String?> inputs, String aLine})>[
            (
              label: '사용자가 미룸',
              a: _DeferrableScriptedStep(
                'A',
                checks: const <CheckResult>[Todo('a 할 일')],
              ),
              inputs: <String?>['2', 'y'],
              aLine: '  ✗ A — $_deferLabel',
            ),
            (
              label: '할 수 없음',
              a: _ScriptedStep(
                'A',
                checks: const <CheckResult>[Deferred('지문이 없습니다')],
              ),
              inputs: <String?>['y'],
              aLine: '  ✗ A — 지문이 없습니다',
            ),
            (
              label: '확인할 수 없음',
              a: _ScriptedStep(
                'A',
                checks: const <CheckResult>[Unverifiable('확인은 실기기 알림')],
              ),
              inputs: <String?>['y'],
              aLine: '  ? A — 확인은 실기기 알림',
            ),
          ]) {
        test('T-20-ENGINE-08: ${entry.label}', () async {
          const blockedLine = '  ? B — A 뒤에 검사합니다';
          final b = _ScriptedStep(
            'B',
            checks: const <CheckResult>[Done('b 끝')],
            dependsOn: const <String>['A'],
          );
          final c = _ScriptedStep(
            'C',
            checks: const <CheckResult>[Todo('c'), Todo('c'), Done('c 끝')],
          );

          final ({int code, ScriptedTerminal terminal, int completions}) run =
              await runStepsWithCompletion(<Step>[entry.a, b, c], entry.inputs);

          final output = run.terminal.output.toString();
          expect(b.checkCount, 0);
          expect(b.applyCount, 0);
          expect(c.applyCount, 1);
          expect(_countExactLines(output, blockedLine), 2);
          expect(output, isNot(contains('  ✓ B')));
          expect(run.code, wizardExitDone);
          expect(run.completions, 1);
          expect(
            output,
            endsWith(
              '${_buildRemainingTail(<String>[entry.aLine, blockedLine])}'
              '$_completionLine\n',
            ),
          );
        });
      }
    },
  );

  test(
    'T-20-ENGINE-09: 점검표에서 기다리던 단계는 앞 단계가 이번 실행에서 ✓ 가 되면 검사 · 실행한다',
    () async {
      const blockedLine = '  ? B — A 뒤에 검사합니다';
      final a = _ScriptedStep(
        'A',
        checks: const <CheckResult>[Todo('a'), Todo('a'), Done('a 끝')],
      );
      final b = _ScriptedStep(
        'B',
        checks: const <CheckResult>[Todo('b'), Done('b 끝')],
        dependsOn: const <String>['A'],
      );

      final ({int code, ScriptedTerminal terminal, int completions}) run =
          await runStepsWithCompletion(<Step>[a, b], const <String?>['y', 'y']);

      final output = run.terminal.output.toString();
      expect(_countExactLines(output, blockedLine), 1);
      expect(output.indexOf('▶ B'), greaterThan(output.indexOf('  ✓ A — a 끝')));
      expect(b.checkCount, 2);
      expect(b.applyCount, 1);
      expect(run.code, wizardExitDone);
      expect(output, endsWith('\n\n$allDoneLine\n$_completionLine\n'));
    },
  );

  group('T-20-ENGINE-10: 점검표와 같은 종류로 다시 판정된 줄은 진행 중에 다시 쓰지 않는다', () {
    for (final entry in <({String label, CheckResult result, String line})>[
      (
        label: '할 수 없음',
        result: const Deferred('지문이 없습니다'),
        line: '  ✗ A — 지문이 없습니다',
      ),
      (
        label: '확인할 수 없음',
        result: const Unverifiable('확인은 실기기 알림'),
        line: '  ? A — 확인은 실기기 알림',
      ),
    ]) {
      test('T-20-ENGINE-10: ${entry.label}', () async {
        final a = _ScriptedStep('A', checks: <CheckResult>[entry.result]);
        final b = _ScriptedStep('B', checks: const <CheckResult>[Done('b 끝')]);

        final ({int code, ScriptedTerminal terminal, int completions}) run =
            await runStepsWithCompletion(<Step>[a, b], const <String?>[]);

        final output = run.terminal.output.toString();
        expect(a.checkCount, 2);
        expect(_countExactLines(output, entry.line), 2);
        expect(run.code, wizardExitDone);
        expect(
          output,
          endsWith(
            '${_buildRemainingTail(<String>[entry.line])}$_completionLine\n',
          ),
        );
      });
    }
  });

  group(
    'T-20-ENGINE-11: 진행 중 다시 판정한 결과가 새로 할 수 없음 · 확인할 수 없음이면 한 번 보이고 끝 목록에 든다',
    () {
      test('T-20-ENGINE-11: 점검표 할 일 → 단계 머리 재검사 할 수 없음', () async {
        const deferredLine = '  ✗ A — 지문이 없습니다';
        final a = _ScriptedStep(
          'A',
          checks: const <CheckResult>[Todo('a 할 일'), Deferred('지문이 없습니다')],
        );

        final ({int code, ScriptedTerminal terminal, int completions}) run =
            await runStepsWithCompletion(<Step>[a], const <String?>[]);

        final output = run.terminal.output.toString();
        expect(_countExactLines(output, '  ✗ A — a 할 일'), 1);
        expect(_countExactLines(output, deferredLine), 2);
        expect(output, isNot(contains('▶ A')));
        expect(a.applyCount, 0);
        expect(run.code, wizardExitDone);
        expect(
          output,
          endsWith(
            '${_buildRemainingTail(<String>[deferredLine])}$_completionLine\n',
          ),
        );
      });

      for (final entry
          in <
            ({
              String label,
              CheckResult after,
              StepOutcome outcome,
              List<String?> inputs,
              String line,
            })
          >[
            (
              label: '실행 뒤 재검사',
              after: const Deferred('Android 쪽이 남았습니다'),
              outcome: const Applied(),
              inputs: <String?>['y', 'y'],
              line: '  ✗ A — Android 쪽이 남았습니다',
            ),
            (
              label: 'Enter 대기 뒤 재검사',
              after: const Unverifiable('확인은 실기기 알림'),
              outcome: const WaitForUser('안내'),
              inputs: <String?>['y', '', 'y'],
              line: '  ? A — 확인은 실기기 알림',
            ),
            (
              label: '다시 시도 재검사',
              after: const Deferred('지문이 없습니다'),
              outcome: const Failed(
                'x',
                result: CommandResult(1, 'OUT', 'ERR'),
              ),
              inputs: <String?>['y', '1', 'y'],
              line: '  ✗ A — 지문이 없습니다',
            ),
          ]) {
        test('T-20-ENGINE-11: ${entry.label}', () async {
          final a = _ScriptedStep(
            'A',
            checks: <CheckResult>[
              const Todo('a'),
              const Todo('a'),
              entry.after,
            ],
            outcomes: <StepOutcome>[entry.outcome],
          );
          final b = _ScriptedStep(
            'B',
            checks: const <CheckResult>[Todo('b'), Todo('b'), Done('b 끝')],
          );

          final ({int code, ScriptedTerminal terminal, int completions}) run =
              await runStepsWithCompletion(<Step>[a, b], entry.inputs);

          final output = run.terminal.output.toString();
          expect(a.applyCount, 1);
          expect(b.applyCount, 1);
          expect(_countExactLines(output, entry.line), 2);
          expect(output.indexOf(entry.line), lessThan(output.indexOf('▶ B')));
          expect(output, isNot(contains(_stopLine)));
          expect(run.code, wizardExitDone);
          expect(
            output,
            endsWith(
              '${_buildRemainingTail(<String>[entry.line])}$_completionLine\n',
            ),
          );
        });
      }
    },
  );
}
