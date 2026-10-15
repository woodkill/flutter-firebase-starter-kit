import 'dart:io';

import 'package:test/test.dart';

import '../../../tool/setup/command_runner.dart';
import '../../../tool/setup/step.dart';
import '../../../tool/setup/wizard.dart';
import 'fakes.dart';

const String _stopLine = '같은 명령을 다시 실행하면 이어집니다.';
const String _confirmQuestion = '이 단계를 진행할까요?';
const String _waitMessage = '끝나면 Enter 를 누르세요';

/// 검사 결과 · 실행 결과를 미리 정해 두는 테스트용 단계.
///
/// 큐는 앞에서부터 하나씩 쓰고, 마지막 하나는 계속 되풀이한다.
final class _ScriptedStep implements Step {
  _ScriptedStep(
    this.id, {
    required List<CheckResult> checks,
    List<StepOutcome> outcomes = const <StepOutcome>[Applied()],
    this.dependsOn = const <String>[],
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
  bool get isCostlyOrIrreversible => false;

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
}
