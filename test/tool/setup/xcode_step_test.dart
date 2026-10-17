import 'dart:io';

import 'package:test/test.dart';

import '../../../tool/setup/command_runner.dart';
import '../../../tool/setup/steps/xcode_step.dart';
import '../../../tool/setup/wizard.dart';
import 'fakes.dart';

const String _selectKey = 'xcode-select -p';
const String _licenseKey = 'xcodebuild -license check';
const String _firstLaunchKey = 'xcodebuild -checkFirstLaunchStatus';
const String _runtimesKey = 'xcrun simctl list runtimes -j';
const String _downloadKey = 'xcodebuild -downloadPlatform iOS';
const String _licenseAcceptKey = 'sudo xcodebuild -license accept';
const String _firstLaunchRunKey = 'sudo xcodebuild -runFirstLaunch';

const CommandResult _ok = CommandResult(0, '', '');
const CommandResult _fail = CommandResult(1, '', 'not ready');
const CommandResult _cltSelected = CommandResult(
  0,
  '/Library/Developer/CommandLineTools\n',
  '',
);

/// 쓸 수 있는 iOS 런타임 1개가 있는 `simctl` 출력.
const CommandResult _iosRuntime = CommandResult(0, '''
{
  "runtimes" : [
    {
      "identifier" : "com.apple.CoreSimulator.SimRuntime.iOS-26-2",
      "platform" : "iOS",
      "isAvailable" : true
    }
  ]
}
''', '');

/// 런타임이 하나도 없는 `simctl` 출력.
const CommandResult _noRuntime = CommandResult(0, '{"runtimes": []}', '');

/// [appPath] 의 Xcode 가 선택된 `xcode-select -p` 결과를 만든다.
CommandResult _selectedResult(String appPath) =>
    CommandResult(0, '$appPath/Contents/Developer\n', '');

void main() {
  late Directory tempDir;
  late String xcodeAppPath;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('xcode_step_test_');
    xcodeAppPath = '${tempDir.path}/Xcode.app';
  });

  tearDown(() {
    tempDir.deleteSync(recursive: true);
  });

  /// Xcode 가 선택된 상태의 네 검사를 등록한다.
  void registerSelectedChecks(
    FakeCommandRunner runner, {
    List<CommandResult> license = const <CommandResult>[_ok],
    List<CommandResult> firstLaunch = const <CommandResult>[_ok],
    List<CommandResult> runtimes = const <CommandResult>[_iosRuntime],
  }) {
    runner.on(_selectKey, _selectedResult(xcodeAppPath));
    for (final result in license) {
      runner.on(_licenseKey, result);
    }
    for (final result in firstLaunch) {
      runner.on(_firstLaunchKey, result);
    }
    for (final result in runtimes) {
      runner.on(_runtimesKey, result);
    }
  }

  test('T-19-XCODE-01 네 검사가 모두 통과하면 점검표에 ✓ 이고 아무것도 실행하지 않는다', () async {
    final runner = FakeCommandRunner();
    registerSelectedChecks(runner);
    final terminal = ScriptedTerminal(const <String?>[]);

    final int code = await runWizard(
      buildTestContext(
        projectRoot: tempDir.path,
        runner: runner,
        terminal: terminal,
      ),
      <XcodeStep>[XcodeStep(xcodeAppPath: xcodeAppPath)],
    );

    expect(code, wizardExitDone);
    expect(terminal.output.toString(), contains('  ✓ Xcode 준비 — '));
    expect(terminal.output.toString(), contains('모든 단계가 끝났습니다.'));
    expect(runner.countMode(RunMode.interactive), 0);
    expect(runner.countMode(RunMode.stream), 0);
    expect(terminal.asks, isEmpty);
  });

  test(
    'T-19-XCODE-02 Xcode 가 없으면 ✗ 이고 y 뒤 App Store 안내와 함께 3 으로 끝난다',
    () async {
      final runner = FakeCommandRunner()..on(_selectKey, _cltSelected);
      final terminal = ScriptedTerminal(const <String?>['y']);

      final int code = await runWizard(
        buildTestContext(
          projectRoot: tempDir.path,
          runner: runner,
          terminal: terminal,
        ),
        <XcodeStep>[
          XcodeStep(xcodeAppPath: '${tempDir.path}/missing/Xcode.app'),
        ],
      );

      final output = terminal.output.toString();
      expect(code, wizardExitForUser);
      expect(output, contains('  ✗ Xcode 준비 — Xcode 가 설치돼 있지 않습니다'));
      expect(output, contains('https://apps.apple.com/app/xcode/id497799835'));
      expect(output, contains('설치가 끝나면 Xcode 를 한 번 열어 추가 구성 요소 설치를 마친 뒤'));
      expect(output, contains('끝나면 ./setup.sh 를 다시 실행하세요 — 끝난 단계는 건너뜁니다.'));
      expect(runner.countMode(RunMode.interactive), 0);
      expect(runner.countMode(RunMode.stream), 0);
    },
  );

  test(
    'T-19-XCODE-03 라이선스만 미동의면 y 뒤 sudo 라이선스 동의를 한 번 실행하고 0 으로 끝난다',
    () async {
      final runner = FakeCommandRunner()..on(_licenseAcceptKey, _ok);
      // 점검표 · 단계 시작 검사는 미동의, 실행 뒤 재검사는 동의.
      registerSelectedChecks(
        runner,
        license: const <CommandResult>[_fail, _fail, _ok],
      );
      final terminal = ScriptedTerminal(const <String?>['y']);

      final int code = await runWizard(
        buildTestContext(
          projectRoot: tempDir.path,
          runner: runner,
          terminal: terminal,
        ),
        <XcodeStep>[XcodeStep(xcodeAppPath: xcodeAppPath)],
      );

      final output = terminal.output.toString();
      expect(code, wizardExitDone);
      expect(output, contains('  ✗ Xcode 준비 — 라이선스 동의 필요'));
      expect(output, contains('  \$ sudo xcodebuild -license accept'));
      expect(runner.countCalls(RunMode.interactive, _licenseAcceptKey), 1);
      expect(runner.countMode(RunMode.interactive), 1);
      expect(runner.countMode(RunMode.stream), 0);
    },
  );

  group('T-19-XCODE-04 단계 확인에서 y 가 아니면 실행하지 않고 1 로 끝난다', () {
    for (final answer in <({String label, List<String?> inputs})>[
      (label: 'Enter(빈 줄)', inputs: <String?>['']),
      (label: '입력 끝(EOF)', inputs: <String?>[]),
    ]) {
      test('T-19-XCODE-04 ${answer.label}', () async {
        final runner = FakeCommandRunner()..on(_licenseAcceptKey, _ok);
        registerSelectedChecks(runner, license: const <CommandResult>[_fail]);
        final terminal = ScriptedTerminal(answer.inputs);

        final int code = await runWizard(
          buildTestContext(
            projectRoot: tempDir.path,
            runner: runner,
            terminal: terminal,
          ),
          <XcodeStep>[XcodeStep(xcodeAppPath: xcodeAppPath)],
        );

        expect(code, wizardExitStopped);
        expect(runner.countMode(RunMode.interactive), 0);
        expect(runner.countMode(RunMode.stream), 0);
        expect(terminal.output.toString(), contains('같은 명령을 다시 실행하면 이어집니다.'));
      });
    }
  });

  test(
    'T-19-XCODE-05 iOS 런타임이 없으면 크기 안내와 내려받기 명령을 보이고 stream 으로 한 번 실행한다',
    () async {
      final runner = FakeCommandRunner()
        ..on(_downloadKey, const CommandResult(0, 'Downloading iOS\n', ''));
      registerSelectedChecks(
        runner,
        runtimes: const <CommandResult>[_noRuntime, _noRuntime, _iosRuntime],
      );
      final terminal = ScriptedTerminal(const <String?>['y']);

      final int code = await runWizard(
        buildTestContext(
          projectRoot: tempDir.path,
          runner: runner,
          terminal: terminal,
        ),
        <XcodeStep>[XcodeStep(xcodeAppPath: xcodeAppPath)],
      );

      final output = terminal.output.toString();
      expect(code, wizardExitDone);
      expect(output, contains('  \$ xcodebuild -downloadPlatform iOS'));
      expect(output, contains('수 GB'));
      expect(runner.countCalls(RunMode.stream, _downloadKey), 1);
      expect(runner.countMode(RunMode.interactive), 0);

      // 실행 전 표시 목록에도 안내 줄과 명령이 함께 들어 있다.
      final checkRunner = FakeCommandRunner();
      registerSelectedChecks(
        checkRunner,
        runtimes: const <CommandResult>[_noRuntime],
      );
      final WizardContext context = buildTestContext(
        projectRoot: tempDir.path,
        runner: checkRunner,
      );
      final step = XcodeStep(xcodeAppPath: xcodeAppPath);
      await step.check(context);
      final List<String> planned = step.plannedCommandLines(context);
      expect(planned, contains('xcodebuild -downloadPlatform iOS'));
      expect(planned.any((String line) => line.contains('수 GB')), isTrue);
    },
  );

  test(
    'T-19-XCODE-07 Command Line Tools 선택 상태면 선택 명령 · 재검사 안내만 보이고 선택 뒤 필요한 것만 보인 뒤 실행한다',
    () async {
      Directory(xcodeAppPath).createSync(recursive: true);
      final selectRunKey =
          'sudo xcode-select -s $xcodeAppPath/Contents/Developer';
      final runner = FakeCommandRunner()
        // 점검표 · 단계 시작은 Command Line Tools, 선택 뒤에는 Xcode.
        ..on(_selectKey, _cltSelected)
        ..on(_selectKey, _cltSelected)
        ..on(_selectKey, _selectedResult(xcodeAppPath))
        ..on(_licenseKey, _ok)
        ..on(_firstLaunchKey, _fail)
        ..on(_firstLaunchKey, _ok)
        ..on(_runtimesKey, _iosRuntime)
        ..on(selectRunKey, _ok)
        ..on(_firstLaunchRunKey, _ok);
      final terminal = ScriptedTerminal(const <String?>['y']);

      final int code = await runWizard(
        buildTestContext(
          projectRoot: tempDir.path,
          runner: runner,
          terminal: terminal,
        ),
        <XcodeStep>[XcodeStep(xcodeAppPath: xcodeAppPath)],
      );

      final output = terminal.output.toString();
      final int askAt = output.indexOf('이 단계를 진행할까요?');
      final String planned = output.substring(0, askAt);
      final String applied = output.substring(askAt);
      expect(code, wizardExitDone);
      expect(output, contains('  ✗ Xcode 준비 — Xcode 선택 필요(선택 뒤 나머지를 검사합니다)'));
      // 확인 전에는 선택 명령과 재검사 안내만 보인다.
      expect(planned, contains('  \$ $selectRunKey'));
      expect(planned, contains('    ${XcodeStep.recheckAfterSelectNotice}'));
      expect(planned, isNot(contains(_licenseAcceptKey)));
      expect(planned, isNot(contains(_firstLaunchRunKey)));
      expect(planned, isNot(contains('수 GB')));
      // 선택 뒤에는 실제로 이어서 실행하는 명령만 실행 전에 보인다.
      expect(applied, contains('    ${XcodeStep.followUpNotice}'));
      expect(applied, contains('  \$ $_firstLaunchRunKey'));
      expect(
        applied.indexOf(XcodeStep.followUpNotice),
        lessThan(applied.indexOf('  \$ $_firstLaunchRunKey')),
      );
      expect(applied, isNot(contains(_licenseAcceptKey)));
      expect(applied, isNot(contains('수 GB')));
      expect(
        runner.calls
            .where((FakeCall call) => call.mode == RunMode.interactive)
            .map((FakeCall call) => call.key),
        <String>[selectRunKey, _firstLaunchRunKey],
      );
      expect(runner.countMode(RunMode.stream), 0);
    },
  );

  test('T-19-XCODE-06 sudo 명령은 비밀번호를 묻거나 표준 입력으로 넘기지 않는다', () async {
    Directory(xcodeAppPath).createSync(recursive: true);
    final selectRunKey =
        'sudo xcode-select -s $xcodeAppPath/Contents/Developer';
    final runner = FakeCommandRunner()
      // 점검표 · 단계 시작은 Command Line Tools, 선택 뒤에는 Xcode.
      ..on(_selectKey, _cltSelected)
      ..on(_selectKey, _cltSelected)
      ..on(_selectKey, _selectedResult(xcodeAppPath))
      ..on(_licenseKey, _fail)
      ..on(_licenseKey, _ok)
      ..on(_firstLaunchKey, _fail)
      ..on(_firstLaunchKey, _ok)
      ..on(_runtimesKey, _iosRuntime)
      ..on(selectRunKey, _ok)
      ..on(_licenseAcceptKey, _ok)
      ..on(_firstLaunchRunKey, _ok);
    final terminal = ScriptedTerminal(const <String?>['y']);

    final int code = await runWizard(
      buildTestContext(
        projectRoot: tempDir.path,
        runner: runner,
        terminal: terminal,
      ),
      <XcodeStep>[XcodeStep(xcodeAppPath: xcodeAppPath)],
    );

    expect(code, wizardExitDone);
    final List<FakeCall> sudoCalls = runner.calls
        .where((FakeCall call) => call.key.startsWith('sudo '))
        .toList();
    expect(sudoCalls.map((FakeCall call) => call.key), <String>[
      selectRunKey,
      _licenseAcceptKey,
      _firstLaunchRunKey,
    ]);
    for (final call in sudoCalls) {
      expect(call.mode, RunMode.interactive);
      expect(call.stdinText, isNull);
    }
    expect(terminal.asks, <String>['이 단계를 진행할까요?']);
    expect(
      terminal.asks.any((String question) => question.contains('비밀번호')),
      isFalse,
    );
    expect(
      terminal.output.toString(),
      contains(
        'sudo 가 비밀번호를 물으면 macOS 로그인 비밀번호를 입력하세요 — '
        '위저드는 비밀번호를 받거나 저장하지 않습니다.',
      ),
    );
  });
}
