import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

import '../../../tool/setup/command_runner.dart';
import '../../../tool/setup/config_files.dart';
import '../../../tool/setup/confirm.dart';
import '../../../tool/setup/redactor.dart';
import '../../../tool/setup/step.dart';
import '../../../tool/setup/steps/apis_step.dart';
import '../../../tool/setup/steps/billing_step.dart';
import '../../../tool/setup/steps/dev_steps.dart';
import '../../../tool/setup/steps/user_files_step.dart';
import '../../../tool/setup/wizard.dart';
import 'fakes.dart';

/// 테스트 프로젝트 ID.
const String projectId = 'acme-dev';

const String _billingInfoKey =
    'gcloud billing projects describe $projectId --format=json';
const String _openAccountsKey =
    'gcloud billing accounts list --filter=open=true --format=json';
const String _servicesListKey =
    'gcloud services list --enabled --project $projectId '
    '--format=value(config.name)';
const CommandResult _ok = CommandResult(0, '', '');

/// 가짜 결제 계정 ID — 한 덩어리 리터럴로 두지 않고 조각을 잇는다.
final String fakeAccountId = <String>['01AB23', '-CD45EF', '-678901'].join();

/// 가짜 결제 계정 표시 이름.
final String fakeAccountName = <String>['Acme', ' Billing', ' Main'].join();

/// `gcloud billing projects link` 가짜 실행기 키.
String linkKey(String accountId) =>
    'gcloud billing projects link $projectId --billing-account=$accountId';

/// `gcloud billing projects describe --format=json` 모양(ProjectBillingInfo)을 만든다.
CommandResult buildBillingInfo({required bool isEnabled}) => CommandResult(
  0,
  jsonEncode(<String, Object?>{
    'billingAccountName': isEnabled ? 'billingAccounts/$fakeAccountId' : '',
    'billingEnabled': isEnabled,
    'name': 'projects/$projectId/billingInfo',
    'projectId': projectId,
  }),
  '',
);

/// `gcloud billing accounts list --format=json` 모양(BillingAccount 배열)을 만든다.
CommandResult buildAccounts(Map<String, String> accounts) => CommandResult(
  0,
  jsonEncode(<Object?>[
    for (final MapEntry<String, String> entry in accounts.entries)
      <String, Object?>{
        'displayName': entry.value,
        'masterBillingAccount': '',
        'name': 'billingAccounts/${entry.key}',
        'open': true,
      },
  ]),
  '',
);

/// 켜진 API 목록(`--format=value(config.name)` — 한 줄에 하나)을 만든다.
CommandResult buildEnabledServices(List<String> services) =>
    CommandResult(0, '${services.join('\n')}\n', '');

/// 이미 끝난 앞 단계 — 결제 · API 단계의 의존 단계를 대신한다.
final class _FinishedStep implements Step {
  _FinishedStep(this.id, this.title);

  @override
  final String id;

  @override
  final String title;

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
  for (final result in results) {
    runner.on(key, result);
  }
}

/// 스트림으로 실행된 명령 키를 순서대로 모은다.
List<String> listStreamKeys(FakeCommandRunner runner) => runner.calls
    .where((FakeCall call) => call.mode == RunMode.stream)
    .map((FakeCall call) => call.key)
    .toList();

/// [path] 에 표준 출력으로 [stdoutText] 를 내는 실행 스크립트를 쓴다.
File writeStubScript(String path, String stdoutText) {
  final stub = File(path)
    ..writeAsStringSync("#!/bin/sh\ncat <<'STUB_EOF'\n$stdoutText\nSTUB_EOF\n");
  Process.runSync('chmod', <String>['+x', stub.path]);
  return stub;
}

void main() {
  late Directory tempDir;
  late String root;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('billing_step_test_');
    root = tempDir.path;
    final config = File('$root/${UserFilesStep.jsonUserPath}')
      ..parent.createSync(recursive: true);
    File(UserFilesStep.jsonExamplePath).copySync(config.path);
    replaceJsonString(config.path, 'firebaseProjectId', projectId);
  });

  tearDown(() {
    tempDir.deleteSync(recursive: true);
  });

  /// 프로젝트(끝남) · 결제 단계로 위저드를 돌린다.
  Future<int> runBillingStep(
    FakeCommandRunner runner,
    ScriptedTerminal terminal,
  ) => runWizard(
    buildTestContext(projectRoot: root, runner: runner, terminal: terminal),
    <Step>[_FinishedStep('firebase_project', 'Firebase 프로젝트'), BillingStep()],
  );

  /// 결제(끝남) · API 단계로 위저드를 돌린다.
  Future<int> runApisStep(
    FakeCommandRunner runner,
    ScriptedTerminal terminal,
  ) => runWizard(
    buildTestContext(projectRoot: root, runner: runner, terminal: terminal),
    <Step>[_FinishedStep('billing', '결제 계정 (Blaze 요금제)'), ApisStep()],
  );

  test('T-19-BILL-01 결제가 켜져 있으면 묻지 않고 ✓', () async {
    final runner = FakeCommandRunner()
      ..on(_billingInfoKey, buildBillingInfo(isEnabled: true));
    final terminal = ScriptedTerminal(const <String?>[]);

    final int code = await runBillingStep(runner, terminal);

    expect(code, wizardExitDone);
    expect(
      terminal.output.toString(),
      contains('  ✓ ${BillingStep.stepTitle} — '),
    );
    expect(terminal.asks, isEmpty);
    expect(runner.countCalls(RunMode.capture, _openAccountsKey), 0);
  });

  test(
    'T-19-BILL-02 열린 결제 계정이 1개면 기본값 · 확인 표에 결제 계정과 Blaze 경고 · y 뒤 연결 1회 → 재검사 ✓',
    () async {
      final runner = FakeCommandRunner()
        ..on(
          _openAccountsKey,
          buildAccounts(<String, String>{fakeAccountId: fakeAccountName}),
        )
        ..on(linkKey(fakeAccountId), _ok);
      registerQueue(runner, _billingInfoKey, <CommandResult>[
        buildBillingInfo(isEnabled: false),
        buildBillingInfo(isEnabled: false),
        buildBillingInfo(isEnabled: true),
      ]);
      final terminal = ScriptedTerminal(const <String?>['y', '', 'y']);

      final int code = await runBillingStep(runner, terminal);

      final output = terminal.output.toString();
      expect(code, wizardExitDone);
      expect(output, contains('  ✗ ${BillingStep.stepTitle} — '));
      expect(terminal.asks, contains(BillingStep.accountChoiceQuestion));
      expect(terminal.asks, contains(summaryConfirmQuestion));
      expect(output, contains('── ${BillingStep.confirmTitle} ──'));
      expect(output, contains('$fakeAccountName ($fakeAccountId)'));
      for (final String warning in BillingStep.costWarnings) {
        expect(output, contains('  ! $warning'));
      }
      expect(BillingStep.costWarnings.join(), contains('Blaze(종량제)'));
      expect(listStreamKeys(runner), <String>[linkKey(fakeAccountId)]);
      expect(output, contains('  ✓ ${BillingStep.stepTitle} — '));
    },
  );

  test(
    'T-19-BILL-03 열린 결제 계정이 0개면 만들기 링크 · Enter 뒤 다시 목록을 읽어 진행하고, 입력 끝이면 거절',
    () async {
      final runner = FakeCommandRunner()..on(linkKey(fakeAccountId), _ok);
      registerQueue(runner, _openAccountsKey, <CommandResult>[
        buildAccounts(const <String, String>{}),
        buildAccounts(<String, String>{fakeAccountId: fakeAccountName}),
      ]);
      registerQueue(runner, _billingInfoKey, <CommandResult>[
        buildBillingInfo(isEnabled: false),
        buildBillingInfo(isEnabled: false),
        buildBillingInfo(isEnabled: true),
      ]);
      final terminal = ScriptedTerminal(const <String?>['y', '', '', 'y']);

      final int code = await runBillingStep(runner, terminal);

      final output = terminal.output.toString();
      expect(code, wizardExitDone);
      expect(output, contains(BillingStep.createAccountUrl));
      expect(
        BillingStep.createAccountUrl,
        'https://console.cloud.google.com/billing/create',
      );
      expect(terminal.asks, contains(waitForEnterMessage));
      expect(runner.countCalls(RunMode.capture, _openAccountsKey), 2);
      expect(listStreamKeys(runner), <String>[linkKey(fakeAccountId)]);

      // 입력 끝 — 링크를 보인 뒤 Enter 대신 입력이 끝나면 거절로 멈춘다.
      final emptyRunner = FakeCommandRunner()
        ..on(_billingInfoKey, buildBillingInfo(isEnabled: false))
        ..on(_openAccountsKey, buildAccounts(const <String, String>{}));
      final WizardContext context = buildTestContext(
        projectRoot: root,
        runner: emptyRunner,
      );
      final step = BillingStep();
      await step.check(context);

      expect(await step.apply(context), isA<Declined>());
      expect(emptyRunner.countMode(RunMode.stream), 0);
    },
  );

  test('T-19-BILL-04 확인 표에서 N 이면 연결하지 않는다', () async {
    final runner = FakeCommandRunner()
      ..on(_billingInfoKey, buildBillingInfo(isEnabled: false))
      ..on(
        _openAccountsKey,
        buildAccounts(<String, String>{fakeAccountId: fakeAccountName}),
      );
    final terminal = ScriptedTerminal(const <String?>['y', '', 'n']);

    final int code = await runBillingStep(runner, terminal);

    expect(code, wizardExitStopped);
    expect(terminal.asks, contains(summaryConfirmQuestion));
    expect(runner.countMode(RunMode.stream), 0);
  });

  group('T-19-BILL-07 값 표 재확인 안내는 확인 표를 보이는 모드에서만 붙는다', () {
    for (final (String label, CommandResult info, bool hasNotice)
        in <(String, CommandResult, bool)>[
          ('결제 계정 연결', buildBillingInfo(isEnabled: false), true),
          ('결제 정보 읽기 실패', const CommandResult(1, '', 'ERROR: denied'), false),
        ]) {
      test('T-19-BILL-07 $label', () async {
        final runner = FakeCommandRunner()..on(_billingInfoKey, info);
        final terminal = ScriptedTerminal(const <String?>[]);

        final int code = await runBillingStep(runner, terminal);

        final output = terminal.output.toString();
        expect(code, wizardExitStopped);
        expect(output, contains('▶ ${BillingStep.stepTitle}'));
        expect(output.contains('    $costlyStepNotice'), hasNotice);
      });
    }
  });

  test('T-19-BILL-05 연결 실패 출력에 quota 가 있으면 원문과 한도 안내 링크를 보인다', () async {
    const quota =
        'ERROR: (gcloud.billing.projects.link) FAILED_PRECONDITION: '
        'Precondition check failed. Cloud billing quota exceeded\n';
    final runner = FakeCommandRunner()
      ..on(_billingInfoKey, buildBillingInfo(isEnabled: false))
      ..on(
        _openAccountsKey,
        buildAccounts(<String, String>{fakeAccountId: fakeAccountName}),
      )
      ..on(linkKey(fakeAccountId), const CommandResult(1, '', quota));
    final terminal = ScriptedTerminal(const <String?>['y', '', 'y']);

    final int code = await runBillingStep(runner, terminal);

    final output = terminal.output.toString();
    expect(code, wizardExitStopped);
    expect(output, contains(quota));
    expect(output, contains(BillingStep.quotaHelpUrl));
    expect(
      BillingStep.quotaHelpUrl,
      'https://support.google.com/cloud/answer/6330231',
    );
  });

  test(
    'T-19-BILL-06 실제 실행기 기록 경로 — 결제 capture 는 출력 본문 대신 생략 표시를 남긴다(대조군 있음)',
    () async {
      final Command infoCommand = BillingStep.billingInfoCommand('demo-p');
      expect(BillingStep.openAccountsCommand.isOutputSensitive, isTrue);
      expect(infoCommand.isOutputSensitive, isTrue);
      final File stub = writeStubScript(
        '${tempDir.path}/billing-stub',
        jsonEncode(<Object?>[
          <String, Object?>{
            'displayName': fakeAccountName,
            'name': 'billingAccounts/$fakeAccountId',
            'open': true,
          },
        ]),
      );

      for (final constant in <Command>[
        BillingStep.openAccountsCommand,
        infoCommand,
      ]) {
        final log = MemoryLogSink(Redactor());
        final runner = ProcessCommandRunner(
          ScriptedTerminal(const <String?>[]),
          log: log,
        );

        final CommandResult result = await runner.capture(
          Command(
            stub.path,
            constant.arguments,
            isOutputSensitive: constant.isOutputSensitive,
          ),
        );

        expect(result.exitCode, 0);
        expect(result.stdout, contains(fakeAccountId));
        expect(log.text, isNot(contains(fakeAccountId)));
        expect(log.text, isNot(contains(fakeAccountName)));
        expect(log.text, contains(ProcessCommandRunner.sensitiveOutputNotice));

        // 대조군 — 같은 스텁을 민감 표시 없이 실행하면 기록에 본문이 남는다.
        final controlLog = MemoryLogSink(Redactor());
        await ProcessCommandRunner(
          ScriptedTerminal(const <String?>[]),
          log: controlLog,
        ).capture(Command(stub.path, constant.arguments));
        expect(controlLog.text, contains(fakeAccountId));
        expect(controlLog.text, contains(fakeAccountName));
      }
    },
  );

  test('T-19-API-01 필요한 API 6개가 모두 켜져 있으면 ✓', () async {
    expect(ApisStep.requiredServices, hasLength(6));
    final runner = FakeCommandRunner()
      ..on(
        _servicesListKey,
        buildEnabledServices(<String>[
          'cloudresourcemanager.googleapis.com',
          ...ApisStep.requiredServices,
        ]),
      );
    final terminal = ScriptedTerminal(const <String?>[]);

    final int code = await runApisStep(runner, terminal);

    expect(code, wizardExitDone);
    expect(
      terminal.output.toString(),
      contains('  ✓ ${ApisStep.stepTitle} — '),
    );
    expect(terminal.asks, isEmpty);
    expect(runner.countMode(RunMode.stream), 0);
  });

  test('T-19-API-02 2개가 꺼져 있으면 그 2개만 켜는 명령을 보이고 y 뒤 한 번 실행한다', () async {
    const missing = <String>[
      'firebaserules.googleapis.com',
      'secretmanager.googleapis.com',
    ];
    final enableKey =
        'gcloud services enable ${missing.join(' ')} --project $projectId';
    final runner = FakeCommandRunner()..on(enableKey, _ok);
    registerQueue(runner, _servicesListKey, <CommandResult>[
      buildEnabledServices(
        ApisStep.requiredServices
            .where((String service) => !missing.contains(service))
            .toList(),
      ),
      buildEnabledServices(
        ApisStep.requiredServices
            .where((String service) => !missing.contains(service))
            .toList(),
      ),
      buildEnabledServices(ApisStep.requiredServices),
    ]);
    final terminal = ScriptedTerminal(const <String?>['y']);

    final int code = await runApisStep(runner, terminal);

    final output = terminal.output.toString();
    expect(code, wizardExitDone);
    expect(output, contains('  \$ $enableKey'));
    expect(listStreamKeys(runner), <String>[enableKey]);
    expect(output, contains('  ✓ ${ApisStep.stepTitle} — '));
  });

  test('T-19-API-03 켜기가 실패하면 원문과 함께 실패 경로로 간다', () async {
    final enableKey =
        'gcloud services enable ${ApisStep.requiredServices.join(' ')} '
        '--project $projectId';
    const denied =
        'ERROR: (gcloud.services.enable) PERMISSION_DENIED: '
        'Permission denied to enable service\n';
    final runner = FakeCommandRunner()
      ..on(_servicesListKey, buildEnabledServices(const <String>[]))
      ..on(enableKey, const CommandResult(1, '', denied));
    final terminal = ScriptedTerminal(const <String?>['y']);

    final int code = await runApisStep(runner, terminal);

    final output = terminal.output.toString();
    expect(code, wizardExitStopped);
    expect(output, contains('  실패 — '));
    expect(output, contains(denied));
    expect(terminal.asks, contains(failureChoiceQuestion));
  });

  test('buildDevSteps 는 프로젝트 → 결제 → API 순서로 이어진다', () {
    final List<String> ids = buildDevSteps()
        .map((Step step) => step.id)
        .toList();

    expect(ids.indexOf('billing'), ids.indexOf('firebase_project') + 1);
    expect(ids.indexOf('apis'), ids.indexOf('billing') + 1);
  });
}
