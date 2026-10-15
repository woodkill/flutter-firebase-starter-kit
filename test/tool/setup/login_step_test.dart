import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

import '../../../tool/setup/command_runner.dart';
import '../../../tool/setup/redactor.dart';
import '../../../tool/setup/rest_client.dart';
import '../../../tool/setup/step.dart';
import '../../../tool/setup/steps/dev_steps.dart';
import '../../../tool/setup/steps/login_step.dart';
import '../../../tool/setup/wizard.dart';
import 'fakes.dart';

const String _firebaseAccountsKey = 'firebase login:list --json';
const String _tokenKey = 'gcloud auth print-access-token';
const String _gcloudAccountKey = 'gcloud config get-value account';
const String _firebaseLoginKey = 'firebase login';
const String _gcloudLoginKey = 'gcloud auth login';

const CommandResult _ok = CommandResult(0, '', '');

/// 테스트용 가짜 계정 이메일 — 한 덩어리 리터럴로 두지 않고 조각을 잇는다.
final String fakeEmail = <String>['dev.user', '@', 'example', '.test'].join();

/// 다른 계정의 가짜 이메일.
final String otherEmail = <String>['someone', '@', 'example', '.test'].join();

/// 가짜 액세스 토큰 — 가림 패턴에 걸리지 않는 모양이라 화면 · 기록에 없음을 직접 본다.
final String fakeToken = <String>['stub', '-access-', 'token', '-0123'].join();

/// `firebase login:list --json` 모양(최상위 `status` · `result`, 항목 `user.email`)을 만든다.
CommandResult buildAccountsResult(List<String> emails) => CommandResult(
  0,
  jsonEncode(<String, Object?>{
    'status': 'success',
    'result': <Object?>[
      for (final String email in emails)
        <String, Object?>{
          'user': <String, Object?>{'email': email},
          'tokens': <String, Object?>{},
        },
    ],
  }),
  '',
);

/// 로그인 단계가 의존하는 개발 도구 단계를 대신하는 이미 끝난 단계.
final class _FinishedToolsStep implements Step {
  @override
  String get id => 'tools';

  @override
  String get title => '개발 도구';

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

/// [path] 에 표준 출력으로 [stdoutText] 를 내는 실행 스크립트를 쓴다.
File writeStubScript(String path, String stdoutText) {
  final File stub = File(path)
    ..writeAsStringSync("#!/bin/sh\ncat <<'STUB_EOF'\n$stdoutText\nSTUB_EOF\n");
  Process.runSync('chmod', <String>['+x', stub.path]);
  return stub;
}

/// [original] 의 인자 · 민감 표시를 그대로 두고 실행 파일만 [executable] 로 바꾼다.
Command replaceExecutable(
  Command original,
  String executable, {
  bool? isOutputSensitive,
}) => Command(
  executable,
  original.arguments,
  isOutputSensitive: isOutputSensitive ?? original.isOutputSensitive,
);

void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('login_step_test_');
  });

  tearDown(() {
    tempDir.deleteSync(recursive: true);
  });

  /// 개발 도구(끝남) · 로그인 단계로 위저드를 돌린다.
  Future<int> runLoginStep(
    FakeCommandRunner runner,
    ScriptedTerminal terminal,
    MemoryLogSink log,
  ) => runWizard(
    buildTestContext(
      projectRoot: tempDir.path,
      runner: runner,
      terminal: terminal,
      log: log,
    ),
    <Step>[_FinishedToolsStep(), LoginStep()],
  );

  test(
    'T-19-LOGIN-01 firebase 계정 · gcloud 토큰 · 두 계정이 같으면(대소문자 무시) ✓ 이고 이메일을 보이지 않는다',
    () async {
      final String upperEmail = fakeEmail.toUpperCase();
      final FakeCommandRunner runner = FakeCommandRunner()
        ..on(_firebaseAccountsKey, buildAccountsResult(<String>[upperEmail]))
        ..on(_tokenKey, CommandResult(0, '$fakeToken\n', ''))
        ..on(_gcloudAccountKey, CommandResult(0, '$fakeEmail\n', ''));
      final ScriptedTerminal terminal = ScriptedTerminal(const <String?>[]);
      final MemoryLogSink log = MemoryLogSink(Redactor());

      final int code = await runLoginStep(runner, terminal, log);

      final String output = terminal.output.toString();
      expect(code, wizardExitDone);
      expect(output, contains('  ✓ ${LoginStep.stepTitle} — '));
      expect(runner.countMode(RunMode.interactive), 0);
      expect(terminal.asks, isEmpty);
      for (final String text in <String>[output, log.text]) {
        expect(text.toLowerCase(), isNot(contains(fakeEmail)));
      }
    },
  );

  test(
    'T-19-LOGIN-02 firebase 계정이 없으면 ✗ · y 뒤 firebase login 을 대화형으로 실행하고 재검사로 ✓',
    () async {
      final FakeCommandRunner runner = FakeCommandRunner()
        ..on(_tokenKey, CommandResult(0, '$fakeToken\n', ''))
        ..on(_gcloudAccountKey, CommandResult(0, '$fakeEmail\n', ''))
        ..on(_firebaseLoginKey, _ok);
      // 점검표 · 단계 시작 검사는 계정 없음, 실행 뒤 재검사는 있음.
      registerQueue(runner, _firebaseAccountsKey, <CommandResult>[
        buildAccountsResult(const <String>[]),
        buildAccountsResult(const <String>[]),
        buildAccountsResult(<String>[fakeEmail]),
      ]);
      final ScriptedTerminal terminal = ScriptedTerminal(const <String?>['y']);
      final MemoryLogSink log = MemoryLogSink(Redactor());

      final int code = await runLoginStep(runner, terminal, log);

      final String output = terminal.output.toString();
      expect(code, wizardExitDone);
      expect(
        output,
        contains('  ✗ ${LoginStep.stepTitle} — ${LoginStep.noFirebaseReason}'),
      );
      expect(output, contains(r'  $ firebase login'));
      expect(listInteractiveKeys(runner), <String>[_firebaseLoginKey]);
      expect(output, contains('  ✓ ${LoginStep.stepTitle} — '));
    },
  );

  test(
    'T-19-LOGIN-03 액세스 토큰 갱신이 실패하면(재인증 실패 원문) ✗ · gcloud auth login 을 실행하고 계정 목록 명령은 부르지 않는다',
    () async {
      const CommandResult reauthFailed = CommandResult(
        1,
        '',
        'ERROR: (gcloud.auth.print-access-token) There was a problem '
            'refreshing your current auth tokens: Reauthentication failed. '
            'cannot prompt during non-interactive execution.\n',
      );
      final FakeCommandRunner runner = FakeCommandRunner()
        ..on(_firebaseAccountsKey, buildAccountsResult(<String>[fakeEmail]))
        ..on(_gcloudAccountKey, CommandResult(0, '$fakeEmail\n', ''))
        ..on(_gcloudLoginKey, _ok);
      registerQueue(runner, _tokenKey, <CommandResult>[
        reauthFailed,
        reauthFailed,
        CommandResult(0, '$fakeToken\n', ''),
      ]);
      final ScriptedTerminal terminal = ScriptedTerminal(const <String?>['y']);
      final MemoryLogSink log = MemoryLogSink(Redactor());

      final int code = await runLoginStep(runner, terminal, log);

      final String output = terminal.output.toString();
      expect(code, wizardExitDone);
      expect(
        output,
        contains('  ✗ ${LoginStep.stepTitle} — ${LoginStep.noTokenReason}'),
      );
      expect(listInteractiveKeys(runner), <String>[_gcloudLoginKey]);
      expect(
        runner.calls.where(
          (FakeCall call) => call.key.startsWith('gcloud auth list'),
        ),
        isEmpty,
      );
      // 토큰 술어가 실패한 동안에는 gcloud 계정을 비교하지 않는다(재검사에서 1회).
      expect(runner.countCalls(RunMode.capture, _gcloudAccountKey), 1);
    },
  );

  test(
    'T-19-LOGIN-04 두 CLI 의 계정이 다르면 ✗ 사유가 다른 계정이고 y 뒤 같은 계정 안내와 함께 gcloud auth login',
    () async {
      final FakeCommandRunner runner = FakeCommandRunner()
        ..on(_firebaseAccountsKey, buildAccountsResult(<String>[fakeEmail]))
        ..on(_tokenKey, CommandResult(0, '$fakeToken\n', ''))
        ..on(_gcloudLoginKey, _ok);
      registerQueue(runner, _gcloudAccountKey, <CommandResult>[
        CommandResult(0, '$otherEmail\n', ''),
        CommandResult(0, '$otherEmail\n', ''),
        CommandResult(0, '$fakeEmail\n', ''),
      ]);
      final ScriptedTerminal terminal = ScriptedTerminal(const <String?>['y']);
      final MemoryLogSink log = MemoryLogSink(Redactor());

      final int code = await runLoginStep(runner, terminal, log);

      final String output = terminal.output.toString();
      expect(code, wizardExitDone);
      expect(LoginStep.accountMismatchReason, contains('다른 계정'));
      expect(
        output,
        contains(
          '  ✗ ${LoginStep.stepTitle} — ${LoginStep.accountMismatchReason}',
        ),
      );
      expect(output, contains(LoginStep.sameAccountGuidance));
      expect(
        LoginStep.sameAccountGuidance,
        'gcloud 로그인 브라우저 창에서 firebase 에 로그인한 계정과 같은 계정을 고르세요.',
      );
      expect(listInteractiveKeys(runner), <String>[_gcloudLoginKey]);
      for (final String text in <String>[output, log.text]) {
        expect(text, isNot(contains(fakeEmail)));
        expect(text, isNot(contains(otherEmail)));
      }
    },
  );

  test(
    'T-19-LOGIN-05 토큰 · 계정 capture 는 민감 출력으로 실행하고 토큰 값은 화면 · 기록에 없다',
    () async {
      final FakeCommandRunner runner = FakeCommandRunner()
        ..on(_firebaseAccountsKey, buildAccountsResult(<String>[fakeEmail]))
        ..on(_tokenKey, CommandResult(0, '$fakeToken\n', ''))
        ..on(_gcloudAccountKey, CommandResult(0, '$fakeEmail\n', ''));
      final ScriptedTerminal terminal = ScriptedTerminal(const <String?>[]);
      final MemoryLogSink log = MemoryLogSink(Redactor());

      await runLoginStep(runner, terminal, log);

      final List<FakeCall> captures = runner.calls
          .where((FakeCall call) => call.mode == RunMode.capture)
          .toList();
      for (final String key in <String>[
        _firebaseAccountsKey,
        _tokenKey,
        _gcloudAccountKey,
      ]) {
        final Iterable<FakeCall> matched = captures.where(
          (FakeCall call) => call.key == key,
        );
        expect(matched, isNotEmpty, reason: key);
        expect(
          matched.every((FakeCall call) => call.isOutputSensitive),
          isTrue,
          reason: key,
        );
      }
      expect(AccessTokenSource.tokenCommand.isOutputSensitive, isTrue);
      expect(terminal.output.toString(), isNot(contains(fakeToken)));
      expect(log.text, isNot(contains(fakeToken)));
    },
  );

  test(
    'T-19-LOGIN-06 실제 실행기 기록 경로 — 계정 capture 상수는 출력 본문 대신 생략 표시를 남긴다(대조군 있음)',
    () async {
      expect(LoginStep.firebaseAccountsCommand.isOutputSensitive, isTrue);
      expect(LoginStep.gcloudAccountCommand.isOutputSensitive, isTrue);
      final File accountsStub = writeStubScript(
        '${tempDir.path}/accounts-stub',
        jsonEncode(<String, Object?>{
          'status': 'success',
          'result': <Object?>[
            <String, Object?>{
              'user': <String, Object?>{'email': fakeEmail},
            },
          ],
        }),
      );
      final File accountStub = writeStubScript(
        '${tempDir.path}/account-stub',
        fakeEmail,
      );

      for (final (Command constant, File stub) in <(Command, File)>[
        (LoginStep.firebaseAccountsCommand, accountsStub),
        (LoginStep.gcloudAccountCommand, accountStub),
      ]) {
        final MemoryLogSink log = MemoryLogSink(Redactor());
        final ProcessCommandRunner runner = ProcessCommandRunner(
          ScriptedTerminal(const <String?>[]),
          log: log,
        );

        final CommandResult result = await runner.capture(
          replaceExecutable(constant, stub.path),
        );

        expect(result.exitCode, 0);
        expect(result.stdout, contains(fakeEmail));
        expect(log.text, isNot(contains(fakeEmail)));
        expect(log.text, contains(ProcessCommandRunner.sensitiveOutputNotice));

        // 대조군 — 같은 스텁을 민감 표시 없이 실행하면 기록에 본문이 남는다.
        final MemoryLogSink controlLog = MemoryLogSink(Redactor());
        final ProcessCommandRunner controlRunner = ProcessCommandRunner(
          ScriptedTerminal(const <String?>[]),
          log: controlLog,
        );
        await controlRunner.capture(
          replaceExecutable(constant, stub.path, isOutputSensitive: false),
        );
        expect(controlLog.text, contains(fakeEmail));
      }
    },
  );

  test('buildDevSteps 는 앱 정체성 다음에 로그인 단계를 둔다', () {
    final List<String> ids = buildDevSteps()
        .map((Step step) => step.id)
        .toList();

    expect(ids, contains('login'));
    expect(ids.indexOf('login'), ids.indexOf('identity') + 1);
  });
}
