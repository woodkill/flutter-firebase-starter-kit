import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:test/test.dart';

import '../../../tool/setup/command_runner.dart';
import '../../../tool/setup/config_files.dart';
import '../../../tool/setup/redactor.dart';
import '../../../tool/setup/rest_client.dart';
import '../../../tool/setup/step.dart';
import '../../../tool/setup/steps/dev_steps.dart';
import '../../../tool/setup/steps/sign_in_step.dart';
import '../../../tool/setup/steps/user_files_step.dart';
import '../../../tool/setup/terminal.dart';
import '../../../tool/setup/wizard.dart';
import 'fake_rest_client.dart';
import 'fakes.dart';

/// 테스트 프로젝트 ID.
const String projectId = 'p';

/// 로그인 설정 주소.
const String configUrl =
    'https://identitytoolkit.googleapis.com/admin/v2/projects/$projectId/config';

/// 이메일 · 비밀번호 · 익명을 함께 켜는 PATCH 주소.
const String patchUrl =
    '$configUrl?updateMask=signIn.email.enabled,'
    'signIn.email.passwordRequired,signIn.anonymous.enabled';

/// PATCH 본문.
const String patchBody =
    '{"signIn":{"email":{"enabled":true,"passwordRequired":true},'
    '"anonymous":{"enabled":true}}}';

/// 임시 auth 설정 파일 내용.
const String authConfigJson =
    '{"auth":{"providers":{"emailPassword":true,"anonymous":true}}}';

/// 초기화 실행 명령 키.
const String deployKey =
    'firebase deploy --only auth --config .setup/auth-config.json '
    '--project $projectId --non-interactive';

/// 초기화되지 않은 프로젝트의 GET 응답.
const RestResponse notInitialized = RestResponse(
  404,
  '{"error":{"code":404,"message":"CONFIGURATION_NOT_FOUND",'
  '"status":"NOT_FOUND"}}',
);

const CommandResult _ok = CommandResult(0, '', '');

/// 로그인 설정 GET 응답을 만든다.
RestResponse buildConfig({
  bool isEmailEnabled = true,
  bool isPasswordRequired = true,
  bool isAnonymousEnabled = true,
}) => RestResponse(
  200,
  jsonEncode(<String, Object?>{
    'name': 'projects/$projectId/config',
    'signIn': <String, Object?>{
      'email': <String, Object?>{
        'enabled': isEmailEnabled,
        'passwordRequired': isPasswordRequired,
      },
      'anonymous': <String, Object?>{'enabled': isAnonymousEnabled},
    },
  }),
);

/// 이미 끝난 앞 단계 — 로그인 수단 단계의 의존 단계를 대신한다.
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

/// 가짜 실행기에 넘기면서, 초기화 명령이 실행되는 순간의 임시 설정 파일 내용을
/// 기록하는 실행기.
final class _DeploySnapshotRunner implements CommandRunner {
  _DeploySnapshotRunner(this.inner, this.authConfig);

  /// 결과를 돌려주는 가짜 실행기.
  final FakeCommandRunner inner;

  /// 임시 설정 파일.
  final File authConfig;

  /// 초기화 명령 시점의 파일 내용(없으면 null) — 실행 순서대로.
  final List<String?> snapshots = <String?>[];

  @override
  Future<CommandResult> capture(Command command) => inner.capture(command);

  @override
  Future<int> interactive(Command command) => inner.interactive(command);

  @override
  Future<CommandResult> stream(Command command) {
    if (FakeCommandRunner.buildKey(command) == deployKey) {
      snapshots.add(
        authConfig.existsSync() ? authConfig.readAsStringSync() : null,
      );
    }
    return inner.stream(command);
  }
}

/// [method] · [url] 응답 큐를 [responses] 순서로 등록한다.
void registerResponses(
  FakeRestClient rest,
  String method,
  String url,
  List<RestResponse> responses,
) {
  for (final RestResponse response in responses) {
    rest.on(method, url, response);
  }
}

void main() {
  late Directory tempDir;
  late String root;
  late File authConfig;
  late File firebaseJson;
  late List<int> firebaseJsonBefore;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('sign_in_step_test_');
    root = tempDir.path;
    final File config = File('$root/${UserFilesStep.jsonUserPath}')
      ..parent.createSync(recursive: true);
    File(UserFilesStep.jsonExamplePath).copySync(config.path);
    replaceJsonString(config.path, 'firebaseProjectId', projectId);
    firebaseJson = File('firebase.json').copySync('$root/firebase.json');
    firebaseJsonBefore = firebaseJson.readAsBytesSync();
    authConfig = File('$root/${SignInStep.authConfigPath}');
  });

  tearDown(() {
    tempDir.deleteSync(recursive: true);
  });

  /// API(끝남) · 로그인 수단 단계로 위저드를 돌린다.
  Future<int> runSignInStep(
    CommandRunner runner,
    FakeRestClient rest,
    ScriptedTerminal terminal,
  ) {
    final Redactor redactor = Redactor();
    final MemoryLogSink log = MemoryLogSink(redactor);
    final WizardContext context = WizardContext(
      projectRoot: root,
      runner: runner,
      terminal: RedactingTerminal(terminal, redactor, log),
      redactor: redactor,
      log: log,
      rest: rest,
      random: Random(fixedTestRandomSeed),
      now: () => fixedTestNow,
    );
    return runWizard(context, <Step>[
      _FinishedStep('apis', '필요한 Google Cloud API'),
      SignInStep(),
    ]);
  }

  /// PATCH 요청만 모은다.
  List<RestRequest> listPatches(FakeRestClient rest) => rest.requests
      .where((RestRequest request) => request.method == 'PATCH')
      .toList();

  test(
    'T-19-SIGNIN-01 이메일 · 비밀번호 · 익명이 모두 켜져 있으면 ✓ · PATCH 0 · 초기화 0',
    () async {
      final FakeRestClient rest = FakeRestClient()
        ..on('GET', configUrl, buildConfig());
      final FakeCommandRunner runner = FakeCommandRunner();
      final ScriptedTerminal terminal = ScriptedTerminal(const <String?>[]);

      final int code = await runSignInStep(runner, rest, terminal);

      expect(code, wizardExitDone);
      expect(
        terminal.output.toString(),
        contains('  ✓ ${SignInStep.stepTitle} — '),
      );
      expect(terminal.asks, isEmpty);
      expect(listPatches(rest), isEmpty);
      expect(runner.countMode(RunMode.stream), 0);
      expect(rest.requests.first.quotaProject, projectId);
    },
  );

  test(
    'T-19-SIGNIN-02 익명만 꺼져 있으면 사유에 익명 · y 뒤 updateMask PATCH 1회 · 재검사 ✓',
    () async {
      expect(Uri.parse(patchUrl).toString(), patchUrl);
      final FakeRestClient rest = FakeRestClient()
        ..on('PATCH', patchUrl, buildConfig());
      registerResponses(rest, 'GET', configUrl, <RestResponse>[
        buildConfig(isAnonymousEnabled: false),
        buildConfig(isAnonymousEnabled: false),
        buildConfig(),
      ]);
      final FakeCommandRunner runner = FakeCommandRunner();
      final ScriptedTerminal terminal = ScriptedTerminal(const <String?>['y']);

      final int code = await runSignInStep(runner, rest, terminal);

      final String output = terminal.output.toString();
      final String checklistLine = output
          .split('\n')
          .firstWhere(
            (String line) => line.startsWith('  ✗ ${SignInStep.stepTitle}'),
          );
      expect(code, wizardExitDone);
      final String reason = checklistLine.split(' — ').last;
      expect(reason, contains('익명'));
      expect(reason, isNot(contains('이메일')));
      final List<RestRequest> patches = listPatches(rest);
      expect(patches, hasLength(1));
      expect(patches.single.url.toString(), patchUrl);
      expect(patches.single.body, patchBody);
      expect(patches.single.quotaProject, projectId);
      expect(output, contains('curl -s -X PATCH "$patchUrl"'));
      expect(runner.countMode(RunMode.stream), 0);
      expect(output, contains('  ✓ ${SignInStep.stepTitle} — '));
    },
  );

  test(
    'T-19-SIGNIN-03 404 CONFIGURATION_NOT_FOUND 면 Web 앱 안내 뒤 임시 설정으로 초기화하고 파일을 지운 다음 재검사 ✓',
    () async {
      final FakeRestClient rest = FakeRestClient();
      registerResponses(rest, 'GET', configUrl, <RestResponse>[
        notInitialized,
        notInitialized,
        buildConfig(),
      ]);
      final _DeploySnapshotRunner runner = _DeploySnapshotRunner(
        FakeCommandRunner()..on(deployKey, _ok),
        authConfig,
      );
      final ScriptedTerminal terminal = ScriptedTerminal(const <String?>['y']);

      final int code = await runSignInStep(runner, rest, terminal);

      final String output = terminal.output.toString();
      expect(code, wizardExitDone);
      expect(output, contains('초기화되지 않았습니다'));
      expect(
        SignInStep.defaultWebAppNotice,
        '프로젝트에 Web 앱이 없으면 Firebase CLI 가 「Default Web App」 을 하나 만듭니다.',
      );
      final int noticeAt = output.indexOf(SignInStep.defaultWebAppNotice);
      final int deployAt = output.indexOf('\$ $deployKey');
      expect(noticeAt, greaterThanOrEqualTo(0));
      expect(deployAt, greaterThan(noticeAt));
      expect(runner.inner.countCalls(RunMode.stream, deployKey), 1);
      expect(runner.snapshots, <String?>[authConfigJson]);
      expect(SignInStep.authConfigContent, authConfigJson);
      expect(authConfig.existsSync(), isFalse);
      expect(listPatches(rest), isEmpty);
      expect(output, contains('  ✓ ${SignInStep.stepTitle} — '));
    },
  );

  test('T-19-SIGNIN-04 초기화 명령이 실패해도 원문을 보이고 임시 파일을 지운다', () async {
    const String deployError = 'Error: Failed to provision Firebase app.\n';
    final FakeRestClient rest = FakeRestClient()
      ..on('GET', configUrl, notInitialized);
    final _DeploySnapshotRunner runner = _DeploySnapshotRunner(
      FakeCommandRunner()
        ..on(deployKey, const CommandResult(1, '', deployError)),
      authConfig,
    );
    final ScriptedTerminal terminal = ScriptedTerminal(const <String?>['y']);

    final int code = await runSignInStep(runner, rest, terminal);

    final String output = terminal.output.toString();
    expect(code, wizardExitStopped);
    expect(output, contains('  실패 — '));
    expect(output, contains(deployError));
    expect(runner.snapshots, <String?>[authConfigJson]);
    expect(authConfig.existsSync(), isFalse);
    expect(File('${authConfig.path}.setup-tmp').existsSync(), isFalse);
  });

  test('T-19-SIGNIN-05 초기화 뒤 익명이 꺼져 있으면 PATCH 1회로 마무리한다', () async {
    final FakeRestClient rest = FakeRestClient()
      ..on('PATCH', patchUrl, buildConfig());
    registerResponses(rest, 'GET', configUrl, <RestResponse>[
      notInitialized,
      notInitialized,
      buildConfig(isAnonymousEnabled: false),
      buildConfig(),
    ]);
    final _DeploySnapshotRunner runner = _DeploySnapshotRunner(
      FakeCommandRunner()..on(deployKey, _ok),
      authConfig,
    );
    final ScriptedTerminal terminal = ScriptedTerminal(const <String?>['y']);

    final int code = await runSignInStep(runner, rest, terminal);

    expect(code, wizardExitDone);
    expect(runner.inner.countCalls(RunMode.stream, deployKey), 1);
    expect(rest.countRequests('PATCH', patchUrl), 1);
    expect(listPatches(rest).single.body, patchBody);
    expect(authConfig.existsSync(), isFalse);
    expect(
      terminal.output.toString(),
      contains('  ✓ ${SignInStep.stepTitle} — '),
    );
  });

  test('T-19-SIGNIN-06 GET 이 403 이면 사유 HTTP 403 · y 뒤 실패 · 초기화 경로 0', () async {
    const String denied =
        '{"error":{"code":403,"message":"The caller does not have permission",'
        '"status":"PERMISSION_DENIED"}}';
    final FakeRestClient rest = FakeRestClient()
      ..on('GET', configUrl, const RestResponse(403, denied));
    final FakeCommandRunner runner = FakeCommandRunner();
    final ScriptedTerminal terminal = ScriptedTerminal(const <String?>['y']);

    final int code = await runSignInStep(runner, rest, terminal);

    final String output = terminal.output.toString();
    expect(code, wizardExitStopped);
    expect(output, contains('  ✗ ${SignInStep.stepTitle} — '));
    expect(output, contains('HTTP 403'));
    expect(output, contains('  실패 — '));
    expect(output, contains(denied));
    expect(output, isNot(contains(SignInStep.defaultWebAppNotice)));
    expect(runner.countMode(RunMode.stream), 0);
    expect(listPatches(rest), isEmpty);
    expect(authConfig.existsSync(), isFalse);
  });

  test(
    'T-19-SIGNIN-07 어느 경로에서도 로그인 설정 주소 밖 요청 0 · 초기화 API 요청 0 · firebase.json 바이트 불변',
    () async {
      final List<RestRequest> allRequests = <RestRequest>[];

      // 켜기 경로.
      final FakeRestClient patchRest = FakeRestClient()
        ..on('PATCH', patchUrl, buildConfig());
      registerResponses(patchRest, 'GET', configUrl, <RestResponse>[
        buildConfig(isEmailEnabled: false, isAnonymousEnabled: false),
        buildConfig(isEmailEnabled: false, isAnonymousEnabled: false),
        buildConfig(),
      ]);
      await runSignInStep(
        FakeCommandRunner(),
        patchRest,
        ScriptedTerminal(const <String?>['y']),
      );
      allRequests.addAll(patchRest.requests);

      // 초기화 경로(성공 · 실패).
      for (final CommandResult deployResult in <CommandResult>[
        _ok,
        const CommandResult(1, '', 'Error: deploy failed\n'),
      ]) {
        final FakeRestClient initRest = FakeRestClient();
        registerResponses(initRest, 'GET', configUrl, <RestResponse>[
          notInitialized,
          notInitialized,
          buildConfig(),
        ]);
        await runSignInStep(
          FakeCommandRunner()..on(deployKey, deployResult),
          initRest,
          ScriptedTerminal(const <String?>['y']),
        );
        allRequests.addAll(initRest.requests);
      }

      expect(allRequests, isNotEmpty);
      for (final RestRequest request in allRequests) {
        final String url = request.url.toString();
        expect(url, startsWith(configUrl));
        expect(url, isNot(contains('initializeAuth')));
        expect(url, isNot(contains('identityPlatform')));
      }
      expect(firebaseJson.readAsBytesSync(), firebaseJsonBefore);
      expect(authConfig.existsSync(), isFalse);
      expect(File(SignInStep.authConfigPath).existsSync(), isFalse);
    },
  );

  test('buildDevSteps 는 기본 bucket 다음에 로그인 수단 단계를 둔다', () {
    final List<String> ids = buildDevSteps()
        .map((Step step) => step.id)
        .toList();

    expect(ids.indexOf('sign_in'), ids.indexOf('storage') + 1);
  });
}
