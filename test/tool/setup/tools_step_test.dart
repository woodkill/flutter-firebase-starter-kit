import 'dart:io';

import 'package:test/test.dart';

import '../../../tool/setup/command_runner.dart';
import '../../../tool/setup/step.dart';
import '../../../tool/setup/steps/tools_step.dart';
import '../../../tool/setup/wizard.dart';
import 'fakes.dart';

const String _nodeKey = 'node --version';
const String _pnpmKey = 'pnpm --version';
const String _firebaseKey = 'firebase --version';
const String _gcloudKey = 'gcloud --version';
const String _jqKey = 'jq --version';
const String _xcodeprojKey = "ruby -e require 'xcodeproj'";
const String _rubyPathKey = 'ruby -e print RbConfig.ruby';
const String _brewPrefixKey = 'brew --prefix';
const String _pubGlobalKey = 'fvm dart pub global list';

const CommandResult _notFound = CommandResult(127, '', 'not found');
const CommandResult _ok = CommandResult(0, '', '');
const CommandResult _homebrewPrefix = CommandResult(0, '/opt/homebrew\n', '');
const CommandResult _noXcodeproj = CommandResult(
  1,
  '',
  'cannot load such file -- xcodeproj',
);

/// 도구 단계가 의존하는 Xcode 준비 단계를 대신하는 이미 끝난 단계.
final class _FinishedXcodeStep implements Step {
  @override
  String get id => 'xcode';

  @override
  String get title => 'Xcode 준비';

  @override
  List<String> get dependsOn => const <String>[];

  @override
  bool get isCostlyOrIrreversible => false;

  @override
  Future<CheckResult> check(WizardContext context) async => const Done('준비됨');

  @override
  List<String> plannedCommandLines(WizardContext context) => const <String>[];

  @override
  Future<StepOutcome> apply(WizardContext context) async => const Applied();
}

/// 일곱 검사가 모두 통과하는 결과를 등록한다 — [skip] 의 키는 등록하지 않는다.
void registerPassingTools(
  FakeCommandRunner runner, {
  Set<String> skip = const <String>{},
}) {
  final Map<String, CommandResult> passing = <String, CommandResult>{
    _nodeKey: const CommandResult(0, 'v26.11.1\n', ''),
    _pnpmKey: const CommandResult(0, '10.33.2\n', ''),
    _firebaseKey: const CommandResult(0, '15.29.0\n', ''),
    _gcloudKey: const CommandResult(
      0,
      'Google Cloud SDK 566.0.0\nbq 2.1.25\ncore 2026.10.01\n',
      '',
    ),
    _jqKey: const CommandResult(0, 'jq-1.7.1-apple\n', ''),
    _xcodeprojKey: _ok,
    _pubGlobalKey: const CommandResult(
      0,
      'devtools 2.40.0\nflutterfire_cli 1.3.2\n',
      '',
    ),
  };
  for (final MapEntry<String, CommandResult> entry in passing.entries) {
    if (skip.contains(entry.key)) continue;
    runner.on(entry.key, entry.value);
  }
}

/// [key] 명령 결과 큐를 [results] 순서로 등록한다.
void registerQueue(
  FakeCommandRunner runner,
  String key,
  List<CommandResult> results,
) {
  for (final CommandResult result in results) {
    runner.on(key, result);
  }
}

/// 대화형으로 실행된 명령 키를 순서대로 모은다.
List<String> listInteractiveKeys(FakeCommandRunner runner) => runner.calls
    .where((FakeCall call) => call.mode == RunMode.interactive)
    .map((FakeCall call) => call.key)
    .toList();

void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('tools_step_test_');
  });

  tearDown(() {
    tempDir.deleteSync(recursive: true);
  });

  /// Xcode 준비(끝남) · 도구 단계로 위저드를 돌린다.
  Future<int> runToolsStep(
    FakeCommandRunner runner,
    ScriptedTerminal terminal,
  ) => runWizard(
    buildTestContext(
      projectRoot: tempDir.path,
      runner: runner,
      terminal: terminal,
    ),
    <Step>[_FinishedXcodeStep(), ToolsStep()],
  );

  test('T-19-TOOLS-01 일곱 검사가 모두 통과하면 ✓ 이고 이름 · 주 버전만 보이며 설치하지 않는다', () async {
    final FakeCommandRunner runner = FakeCommandRunner();
    registerPassingTools(runner);
    final ScriptedTerminal terminal = ScriptedTerminal(const <String?>[]);

    final int code = await runToolsStep(runner, terminal);

    final String output = terminal.output.toString();
    expect(code, wizardExitDone);
    expect(
      output,
      contains(
        '  ✓ 개발 도구 — Node 26 · pnpm 10 · Firebase CLI 15 · '
        'Google Cloud CLI 566 · jq 1 · xcodeproj · FlutterFire CLI 1',
      ),
    );
    expect(output, isNot(contains('/opt/homebrew')));
    expect(output, isNot(contains('/Users/')));
    expect(runner.countMode(RunMode.interactive), 0);
    expect(runner.countCalls(RunMode.capture, _brewPrefixKey), 0);
    expect(terminal.asks, isEmpty);
  });

  test(
    'T-19-TOOLS-02 Node 가 최소 판보다 낮으면 ✗ 사유에 Node 가 있고 brew install node 를 계획한다',
    () async {
      final FakeCommandRunner runner = FakeCommandRunner()
        ..on(_nodeKey, const CommandResult(0, 'v20.11.0\n', ''))
        ..on(_brewPrefixKey, _homebrewPrefix);
      registerPassingTools(runner, skip: const <String>{_nodeKey});
      final WizardContext context = buildTestContext(
        projectRoot: tempDir.path,
        runner: runner,
      );
      final ToolsStep step = ToolsStep();

      final CheckResult result = await step.check(context);

      expect(result, isA<Todo>());
      final String reason = (result as Todo).reason;
      expect(reason, contains('Node 20'));
      expect(reason, contains('${ToolsStep.minNodeMajor}'));
      expect(step.plannedCommandLines(context), <String>['brew install node']);
    },
  );

  test(
    'T-19-TOOLS-03 Firebase CLI · jq 가 없으면 y 뒤 Homebrew 설치를 차례로 실행하고 재검사 통과로 0',
    () async {
      final FakeCommandRunner runner = FakeCommandRunner()
        ..on(_brewPrefixKey, _homebrewPrefix)
        ..on('brew install firebase-cli', _ok)
        ..on('brew install jq', _ok);
      registerPassingTools(runner, skip: const <String>{_firebaseKey, _jqKey});
      // 점검표 · 단계 시작 검사는 없음, 실행 뒤 재검사는 있음.
      registerQueue(runner, _firebaseKey, const <CommandResult>[
        _notFound,
        _notFound,
        CommandResult(0, '15.33.0\n', ''),
      ]);
      registerQueue(runner, _jqKey, const <CommandResult>[
        _notFound,
        _notFound,
        CommandResult(0, 'jq-1.8.1\n', ''),
      ]);
      final ScriptedTerminal terminal = ScriptedTerminal(const <String?>['y']);

      final int code = await runToolsStep(runner, terminal);

      final String output = terminal.output.toString();
      expect(code, wizardExitDone);
      expect(output, contains('  ✗ 개발 도구 — Firebase CLI 없음 · jq 없음'));
      expect(output, contains(r'  $ brew install firebase-cli'));
      expect(output, contains(r'  $ brew install jq'));
      expect(output, contains('  ✓ 개발 도구 — '));
      expect(listInteractiveKeys(runner), <String>[
        'brew install firebase-cli',
        'brew install jq',
      ]);
      expect(terminal.asks, <String>[stepConfirmQuestion]);
    },
  );

  group(
    'T-19-TOOLS-04 xcodeproj 가 없고 ruby 가 시스템 ruby 면 sudo 없이 Homebrew ruby 로 설치한다',
    () {
      for (final String systemRuby in <String>[
        '/usr/bin/ruby',
        '/System/Library/Frameworks/Ruby.framework/Versions/2.6/usr/bin/ruby',
      ]) {
        test('T-19-TOOLS-04 $systemRuby', () async {
          final FakeCommandRunner runner = FakeCommandRunner()
            ..on(_xcodeprojKey, _noXcodeproj)
            ..on(_rubyPathKey, CommandResult(0, systemRuby, ''))
            ..on(_brewPrefixKey, _homebrewPrefix)
            ..on('brew install ruby', _ok)
            ..on('/opt/homebrew/bin/gem install xcodeproj', _ok);
          registerPassingTools(runner, skip: const <String>{_xcodeprojKey});
          final WizardContext context = buildTestContext(
            projectRoot: tempDir.path,
            runner: runner,
          );
          final ToolsStep step = ToolsStep();

          final CheckResult result = await step.check(context);

          expect(result, isA<Todo>());
          expect((result as Todo).reason, contains('xcodeproj'));
          expect(step.plannedCommandLines(context), <String>[
            'brew install ruby',
            '/opt/homebrew/bin/gem install xcodeproj',
          ]);

          // 설치 뒤에도 PATH 의 ruby 가 시스템 ruby 면 셸 설정 안내를 사유로 낸다.
          final ScriptedTerminal terminal = ScriptedTerminal(const <String?>[
            'y',
          ]);
          final int code = await runToolsStep(runner, terminal);

          expect(code, wizardExitStopped);
          expect(
            terminal.output.toString(),
            contains(ToolsStep.rubyPathGuidance),
          );
          expect(listInteractiveKeys(runner), <String>[
            'brew install ruby',
            '/opt/homebrew/bin/gem install xcodeproj',
          ]);
          expect(
            runner.calls.where((FakeCall call) => call.key.startsWith('sudo')),
            isEmpty,
          );
        });
      }

      test(
        'T-19-TOOLS-04 Homebrew 등 사용자 ruby 면 그 ruby 의 gem 으로 설치한다',
        () async {
          final FakeCommandRunner runner = FakeCommandRunner()
            ..on(_xcodeprojKey, _noXcodeproj)
            ..on(
              _rubyPathKey,
              const CommandResult(
                0,
                '/opt/homebrew/Cellar/ruby/4.0.7/bin/ruby',
                '',
              ),
            );
          registerPassingTools(runner, skip: const <String>{_xcodeprojKey});
          final WizardContext context = buildTestContext(
            projectRoot: tempDir.path,
            runner: runner,
          );
          final ToolsStep step = ToolsStep();

          await step.check(context);

          expect(step.plannedCommandLines(context), <String>[
            'gem install xcodeproj',
          ]);
          expect(runner.countCalls(RunMode.capture, _brewPrefixKey), 0);
        },
      );
    },
  );

  test('T-19-TOOLS-05 설치 명령이 실패하면 실패 경로(다시 시도 · 멈춤)로 간다', () async {
    final FakeCommandRunner runner = FakeCommandRunner()
      ..on(_brewPrefixKey, _homebrewPrefix)
      ..on(_jqKey, _notFound)
      ..on('brew install jq', const CommandResult(1, '', ''));
    registerPassingTools(runner, skip: const <String>{_jqKey});
    final ScriptedTerminal terminal = ScriptedTerminal(const <String?>['y']);

    final int code = await runToolsStep(runner, terminal);

    final String output = terminal.output.toString();
    expect(code, wizardExitStopped);
    expect(output, contains('  실패 — brew install jq'));
    expect(output, contains('종료 코드 1'));
    expect(terminal.asks, <String>[stepConfirmQuestion, failureChoiceQuestion]);
    expect(listInteractiveKeys(runner), <String>['brew install jq']);
  });

  test(
    'T-19-TOOLS-06 Homebrew 를 찾지 못하면 설치하지 않고 ./setup.sh 로 실행하라고 안내한다',
    () async {
      final FakeCommandRunner runner = FakeCommandRunner()
        ..on(_brewPrefixKey, _notFound)
        ..on(_jqKey, _notFound);
      registerPassingTools(runner, skip: const <String>{_jqKey});
      final ScriptedTerminal terminal = ScriptedTerminal(const <String?>['y']);

      final int code = await runToolsStep(runner, terminal);

      final String output = terminal.output.toString();
      expect(code, wizardExitStopped);
      expect(output, contains('  실패 — ${ToolsStep.homebrewMissingGuidance}'));
      expect(ToolsStep.homebrewMissingGuidance, contains('./setup.sh'));
      expect(ToolsStep.homebrewMissingGuidance, contains('Homebrew'));
      expect(runner.countMode(RunMode.interactive), 0);
    },
  );

  test(
    'T-19-TOOLS-07 FlutterFire CLI 가 없으면 fvm dart pub global activate 로 설치한다',
    () async {
      final FakeCommandRunner runner = FakeCommandRunner()
        ..on('fvm dart pub global activate flutterfire_cli', _ok);
      registerPassingTools(runner, skip: const <String>{_pubGlobalKey});
      registerQueue(runner, _pubGlobalKey, const <CommandResult>[
        CommandResult(0, 'devtools 2.40.0\n', ''),
        CommandResult(0, 'devtools 2.40.0\n', ''),
        CommandResult(0, 'devtools 2.40.0\nflutterfire_cli 1.3.2\n', ''),
      ]);
      final ScriptedTerminal terminal = ScriptedTerminal(const <String?>['y']);

      final int code = await runToolsStep(runner, terminal);

      final String output = terminal.output.toString();
      expect(code, wizardExitDone);
      expect(output, contains('  ✗ 개발 도구 — FlutterFire CLI 없음'));
      expect(
        output,
        contains(r'  $ fvm dart pub global activate flutterfire_cli'),
      );
      expect(listInteractiveKeys(runner), <String>[
        'fvm dart pub global activate flutterfire_cli',
      ]);
      // Homebrew 가 필요 없는 설치는 brew 를 찾지 않는다.
      expect(runner.countCalls(RunMode.capture, _brewPrefixKey), 0);
    },
  );
}
