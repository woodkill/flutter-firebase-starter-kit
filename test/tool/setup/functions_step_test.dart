import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:test/test.dart';

import '../../../tool/setup/command_runner.dart';
import '../../../tool/setup/config_files.dart';
import '../../../tool/setup/redactor.dart';
import '../../../tool/setup/step.dart';
import '../../../tool/setup/steps/dev_steps.dart';
import '../../../tool/setup/steps/functions_step.dart';
import '../../../tool/setup/steps/user_files_step.dart';
import '../../../tool/setup/terminal.dart';
import '../../../tool/setup/wizard.dart';
import 'fake_rest_client.dart';
import 'fakes.dart';

/// 테스트 프로젝트 ID(가짜).
const String projectId = 'demo-p';

/// 테스트 Functions 리전 — example config 의 값 그대로.
const String region = 'asia-northeast3';

/// fixture 가 선언하는 secret 이름(정렬).
const List<String> declaredSecrets = <String>[
  'FACEBOOK_APP_ID',
  'FACEBOOK_APP_SECRET',
  'KAKAO_ADMIN_KEY',
  'KAKAO_NATIVE_APP_KEY',
  'LINE_CHANNEL_ID',
  'LINE_CHANNEL_SECRET',
  'NAVER_CLIENT_ID',
  'NAVER_CLIENT_SECRET',
];

/// 의존성 설치 명령 키.
const String installKey = 'pnpm -C functions install --frozen-lockfile';

/// secret 목록 명령 키.
const String secretsListKey =
    'gcloud secrets list --project $projectId --format=value(name)';

/// 배포된 함수 목록 명령 키.
const String functionsListKey =
    'firebase functions:list --json --project $projectId';

/// 배포 스크립트 명령 키.
const String deployKey = 'bash scripts/deploy_functions.sh dev --apply';

/// [name] secret 을 만드는 명령 키.
String buildSetKey(String name) =>
    'firebase functions:secrets:set $name --project $projectId --data-file -';

/// [service] 의 IAM 정책을 읽는 명령 키.
String buildIamKey(String service) =>
    'gcloud run services get-iam-policy $service --region $region '
    '--project $projectId --format=json';

/// [functionId] 의 Cloud Run 서비스 이름(가짜 — 소문자).
String buildServiceId(String functionId) => functionId.toLowerCase();

const CommandResult _ok = CommandResult(0, '', '');

/// 공개 호출이 붙은 IAM 정책 응답.
const CommandResult publicPolicy = CommandResult(
  0,
  '{"bindings":[{"members":["allUsers"],"role":"roles/run.invoker"}],'
      '"etag":"BwYfake"}',
  '',
);

/// 이미 끝난 앞 단계 — Functions 단계의 의존 단계를 대신한다.
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

/// 가짜 실행기에 넘기면서 실제 실행기처럼 흘리는 실행(stream)의 명령 줄과 출력을
/// 화면에 쓰는 실행기 — 의존성 설치 순간에는 [onInstall] 을 부른다.
final class _EchoingRunner implements CommandRunner {
  _EchoingRunner(this.inner, this.terminal, {this.onInstall});

  /// 결과를 돌려주는 가짜 실행기.
  final FakeCommandRunner inner;

  /// 흘리는 출력을 쓸 화면.
  final Terminal terminal;

  /// 의존성 설치 실행 순간에 부를 콜백.
  final void Function()? onInstall;

  /// 흘리는 실행에 넘어간 작업 디렉터리(명령 키별 마지막 값).
  final Map<String, String?> workingDirectories = <String, String?>{};

  @override
  Future<CommandResult> capture(Command command) => inner.capture(command);

  @override
  Future<int> interactive(Command command) => inner.interactive(command);

  @override
  Future<CommandResult> stream(Command command) async {
    final String key = FakeCommandRunner.buildKey(command);
    workingDirectories[key] = command.workingDirectory;
    if (key == installKey) onInstall?.call();
    terminal.writeCommand(command.render());
    final CommandResult result = await inner.stream(command);
    for (final String text in <String>[result.stdout, result.stderr]) {
      if (text.isEmpty) continue;
      terminal.writeRaw(text.endsWith('\n') ? text : '$text\n');
    }
    return result;
  }
}

/// 위저드 한 번 실행에 쓰는 가짜 실행기 · 화면 · 기록 묶음.
final class _Harness {
  _Harness(this.root, List<String?> inputs, {void Function()? onInstall})
    : fake = FakeCommandRunner(),
      screen = ScriptedTerminal(inputs),
      log = MemoryLogSink(Redactor()) {
    terminal = RedactingTerminal(screen, log.redactor, log);
    runner = _EchoingRunner(fake, terminal, onInstall: onInstall);
  }

  final String root;
  final FakeCommandRunner fake;
  final ScriptedTerminal screen;
  final MemoryLogSink log;
  late final RedactingTerminal terminal;
  late final _EchoingRunner runner;

  /// 화면 출력 전체.
  String get output => screen.output.toString();

  /// 앞 단계(끝남) · Functions 단계로 위저드를 돌린다.
  Future<int> run() => runWizard(
    WizardContext(
      projectRoot: root,
      runner: runner,
      terminal: terminal,
      redactor: log.redactor,
      log: log,
      rest: FakeRestClient(),
      random: Random(fixedTestRandomSeed),
      now: () => fixedTestNow,
    ),
    <Step>[
      _FinishedStep('configure', '앱 등록 · 설정 파일'),
      _FinishedStep('apis', '필요한 Google Cloud API'),
      _FinishedStep('firestore', '위치 · Firestore'),
      FunctionsStep(),
    ],
  );
}

/// `gcloud secrets list --format=value(name)` 출력을 만든다(전체 자원 이름).
CommandResult buildSecretsList(Iterable<String> names) => CommandResult(
  0,
  names.map((String name) => 'projects/000000000000/secrets/$name\n').join(),
  '',
);

/// `firebase functions:list --json` 성공 출력을 만든다.
CommandResult buildFunctionsList(Iterable<String> functionIds) => CommandResult(
  0,
  jsonEncode(<String, Object?>{
    'status': 'success',
    'result': <Object?>[
      for (final String id in functionIds)
        <String, Object?>{
          'id': id,
          'project': projectId,
          'region': region,
          'platform': 'gcfv2',
          'entryPoint': id,
          'runtime': 'nodejs22',
          'httpsTrigger': <String, Object?>{},
          'runServiceId': buildServiceId(id),
        },
    ],
  }),
  '',
);

/// 배포 스크립트의 실행 출력을 만든다 — [lastLine] 이 마지막 줄이다.
CommandResult buildDeployOutput(
  List<String> functionIds, {
  int exitCode = 0,
  String? lastLine,
  String stderr = '',
}) {
  final String only = functionIds.map((String id) => 'functions:$id').join(',');
  return CommandResult(
    exitCode,
    'flavor: dev\n'
    'project: $projectId\n'
    'mode: firebase\n'
    'enabled: (없음)\n'
    'functions (${functionIds.length}):\n'
    '${functionIds.map((String id) => '  - $id\n').join()}'
    'command: firebase deploy --project $projectId --only $only\n'
    'running: firebase deploy --project $projectId --only $only\n'
    '\n'
    '${lastLine ?? 'DEPLOY OK dev functions=${functionIds.length} batches=1'}\n',
    stderr,
  );
}

void main() {
  late Directory tempDir;
  late String root;
  late List<String> commonFunctions;

  setUpAll(() {
    final Object? manifest = jsonDecode(
      File(FunctionsStep.manifestPath).readAsStringSync(),
    );
    commonFunctions = <String>[
      for (final Object? id
          in (manifest! as Map<String, Object?>)['common']! as List<Object?>)
        id! as String,
    ];
  });

  /// 저장소 상대 경로에 내용을 쓴다(부모 디렉터리를 만든다).
  void writeFixture(String relativePath, String content) {
    File('$root/$relativePath')
      ..parent.createSync(recursive: true)
      ..writeAsStringSync(content);
  }

  /// 의존성 설치 표시 파일을 만든다.
  void writeModulesMarker() {
    writeFixture(FunctionsStep.modulesMarkerPath, '');
  }

  /// 배포됨 · 공개 호출 상태를 가짜 실행기에 등록한다.
  void registerDeployed(FakeCommandRunner fake) {
    fake.on(functionsListKey, buildFunctionsList(commonFunctions));
    for (final String id in commonFunctions) {
      fake.on(buildIamKey(buildServiceId(id)), publicPolicy);
    }
  }

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('functions_step_test_');
    root = tempDir.path;
    final File config = File('$root/${UserFilesStep.jsonUserPath}')
      ..parent.createSync(recursive: true);
    File(UserFilesStep.jsonExamplePath).copySync(config.path);
    replaceJsonString(config.path, 'firebaseProjectId', projectId);
    writeFixture(
      FunctionsStep.manifestPath,
      File(FunctionsStep.manifestPath).readAsStringSync(),
    );
    writeFixture(
      'functions/src/shared/secrets.ts',
      declaredSecrets
          .map((String name) => 'export const $name = defineSecret("$name");\n')
          .join(),
    );
  });

  tearDown(() {
    tempDir.deleteSync(recursive: true);
  });

  test(
    'T-19-FN-01: 모듈 · secret 전부 · common 전부 배포 · 공개 호출이면 ✓ · 흘리는 실행 0',
    () async {
      writeModulesMarker();
      final _Harness harness = _Harness(root, const <String?>[]);
      harness.fake.on(secretsListKey, buildSecretsList(declaredSecrets));
      registerDeployed(harness.fake);

      final int code = await harness.run();

      expect(code, wizardExitDone);
      expect(harness.fake.countMode(RunMode.stream), 0);
      expect(harness.output, contains('  ✓ ${FunctionsStep.stepTitle} — '));
      expect(harness.screen.asks, isEmpty);
    },
  );

  test('T-19-FN-02: 모듈 없음 · secret 3개 없음 · 함수 없음 → 설치 · 없는 secret 만 stdin '
      '생성 · 배포 · DEPLOY OK → 재검사 ✓', () async {
    const List<String> missing = <String>[
      'FACEBOOK_APP_SECRET',
      'KAKAO_ADMIN_KEY',
      'NAVER_CLIENT_ID',
    ];
    final List<String> present = declaredSecrets
        .where((String name) => !missing.contains(name))
        .toList();
    final _Harness harness = _Harness(root, const <String?>[
      'y',
    ], onInstall: writeModulesMarker);
    harness.fake
      ..on(secretsListKey, buildSecretsList(present))
      ..on(secretsListKey, buildSecretsList(present))
      ..on(secretsListKey, buildSecretsList(declaredSecrets))
      ..on(installKey, _ok)
      ..on(deployKey, buildDeployOutput(commonFunctions));
    for (final String name in missing) {
      harness.fake.on(buildSetKey(name), _ok);
    }
    registerDeployed(harness.fake);

    final int code = await harness.run();

    expect(code, wizardExitDone);
    expect(harness.fake.countCalls(RunMode.stream, installKey), 1);
    expect(harness.fake.countCalls(RunMode.stream, deployKey), 1);
    for (final String name in missing) {
      final List<FakeCall> sets = harness.fake.calls
          .where((FakeCall call) => call.key == buildSetKey(name))
          .toList();
      expect(sets, hasLength(1), reason: name);
      expect(sets.single.mode, RunMode.capture);
      expect(sets.single.stdinText, FunctionsStep.secretPlaceholder);
      expect(sets.single.key, isNot(contains('unset')));
    }
    for (final String name in present) {
      expect(
        harness.fake.calls.where(
          (FakeCall call) => call.key == buildSetKey(name),
        ),
        isEmpty,
        reason: name,
      );
    }
    final List<String> keys = harness.fake.calls
        .map((FakeCall call) => call.key)
        .toList();
    expect(
      keys.indexOf(installKey),
      lessThan(keys.indexOf(buildSetKey(missing.first))),
    );
    expect(
      keys.indexOf(buildSetKey(missing.last)),
      lessThan(keys.indexOf(deployKey)),
    );
    expect(harness.runner.workingDirectories[installKey], root);
    expect(harness.runner.workingDirectories[deployKey], root);
    expect(harness.output, contains('  \$ $installKey'));
    expect(harness.output, contains('  \$ $deployKey'));
    expect(harness.output, contains('DEPLOY OK dev functions=7 batches=1'));
    expect(harness.output, contains('  ✓ ${FunctionsStep.stepTitle} — '));
  });

  test('T-19-FN-03: 배포 exit 0 이지만 마지막 줄이 DRY-RUN OK 면 실패', () async {
    writeModulesMarker();
    final _Harness harness = _Harness(root, const <String?>['y', '2']);
    harness.fake
      ..on(secretsListKey, buildSecretsList(declaredSecrets))
      ..on(functionsListKey, buildFunctionsList(const <String>[]))
      ..on(
        deployKey,
        buildDeployOutput(
          commonFunctions,
          lastLine: 'DRY-RUN OK dev functions=7 batches=1',
        ),
      );

    final int code = await harness.run();

    expect(code, wizardExitStopped);
    expect(harness.fake.countCalls(RunMode.stream, deployKey), 1);
    expect(harness.output, contains('  실패 — '));
    expect(harness.output, contains('DRY-RUN OK dev functions=7 batches=1'));
    expect(harness.output, isNot(contains('  ✓ ${FunctionsStep.stepTitle}')));
  });

  test('T-19-FN-04: 배포 exit 1 · 일반 실패 원문은 그대로 · 조직 정책 문구 0', () async {
    writeModulesMarker();
    const String errorLine =
        'Error: HTTP Error: 403, The caller does not have permission';
    const String failLine = 'FAIL: 1번째 묶음 배포 실패 (1개 중) — 앞 묶음은 이미 배포됐다';
    final _Harness harness = _Harness(root, const <String?>['y', '2']);
    harness.fake
      ..on(secretsListKey, buildSecretsList(declaredSecrets))
      ..on(functionsListKey, buildFunctionsList(const <String>[]))
      ..on(
        deployKey,
        buildDeployOutput(
          commonFunctions,
          exitCode: 1,
          lastLine: errorLine,
          stderr: '$failLine\n',
        ),
      );

    final int code = await harness.run();

    expect(code, wizardExitStopped);
    expect(harness.output, contains('  실패 — '));
    expect(harness.output, contains(errorLine));
    expect(harness.output, contains(failLine));
    expect(harness.output, isNot(contains('조직 정책')));
    expect(harness.output, isNot(contains('restrict-domains')));
  });

  test('T-19-FN-05: secret 생성이 exit 1 이면 실패 · 배포 0', () async {
    writeModulesMarker();
    const String errorLine =
        'Error: HTTP Error: 403, Permission denied on secret';
    final _Harness harness = _Harness(root, const <String?>['y', '2']);
    harness.fake
      ..on(
        secretsListKey,
        buildSecretsList(
          declaredSecrets.where((String name) => name != 'LINE_CHANNEL_ID'),
        ),
      )
      ..on(
        buildSetKey('LINE_CHANNEL_ID'),
        const CommandResult(1, 'stdout-body-not-shown', '$errorLine\n'),
      )
      ..on(deployKey, buildDeployOutput(commonFunctions));

    final int code = await harness.run();

    expect(code, wizardExitStopped);
    expect(
      harness.fake.countCalls(RunMode.capture, buildSetKey('LINE_CHANNEL_ID')),
      1,
    );
    expect(harness.fake.countCalls(RunMode.stream, deployKey), 0);
    expect(harness.output, contains('  실패 — '));
    expect(harness.output, contains('LINE_CHANNEL_ID'));
    expect(harness.output, contains(errorLine));
    expect(harness.output, isNot(contains('stdout-body-not-shown')));
  });

  test('T-19-FN-06: 화면에는 printf 표시형 · secret 생성은 민감 출력으로 실행', () async {
    writeModulesMarker();
    const List<String> missing = <String>[
      'FACEBOOK_APP_ID',
      'LINE_CHANNEL_SECRET',
    ];
    const String createdLine =
        'Created a new secret version projects/000000000000/secrets/X/versions/1';
    final _Harness harness = _Harness(root, const <String?>['y']);
    harness.fake
      ..on(
        secretsListKey,
        buildSecretsList(
          declaredSecrets.where((String name) => !missing.contains(name)),
        ),
      )
      ..on(
        secretsListKey,
        buildSecretsList(
          declaredSecrets.where((String name) => !missing.contains(name)),
        ),
      )
      ..on(secretsListKey, buildSecretsList(declaredSecrets))
      ..on(deployKey, buildDeployOutput(commonFunctions));
    for (final String name in missing) {
      harness.fake.on(
        buildSetKey(name),
        const CommandResult(0, createdLine, ''),
      );
    }
    registerDeployed(harness.fake);

    final int code = await harness.run();

    expect(code, wizardExitDone);
    for (final String name in missing) {
      expect(
        harness.output,
        contains(
          "  \$ printf 'unset' | firebase functions:secrets:set $name "
          '--project $projectId --data-file -',
        ),
      );
      final FakeCall call = harness.fake.calls.singleWhere(
        (FakeCall c) => c.key == buildSetKey(name),
      );
      expect(call.isOutputSensitive, isTrue);
    }
    expect(harness.output, isNot(contains(createdLine)));
    expect(harness.log.text, isNot(contains(createdLine)));

    // 단계가 만든 명령의 표시형 · 민감 표시를 실제 실행기에 그대로 실어(실행 파일만
    // cat) 기록 모양을 확인한다 — 명령 줄은 표시형, 출력 본문은 생략 표시다.
    final Command command = FunctionsStep.buildSecretSetCommand(
      'FACEBOOK_APP_ID',
      projectId,
    );
    final MemoryLogSink realLog = MemoryLogSink(Redactor());
    final ScriptedTerminal realScreen = ScriptedTerminal(const <String?>[]);
    final ProcessCommandRunner real = ProcessCommandRunner(
      RedactingTerminal(realScreen, realLog.redactor, realLog),
      log: realLog,
    );
    final CommandResult echoed = await real.capture(
      Command(
        'cat',
        const <String>[],
        stdinText: command.stdinText,
        display: command.display,
        isOutputSensitive: command.isOutputSensitive,
      ),
    );
    expect(echoed.stdout.trim(), FunctionsStep.secretPlaceholder);
    expect(command.arguments, isNot(contains(FunctionsStep.secretPlaceholder)));
    expect(
      realLog.lines,
      contains(
        "[cmd] printf 'unset' | firebase functions:secrets:set FACEBOOK_APP_ID "
        '--project $projectId --data-file -',
      ),
    );
    expect(
      realLog.lines,
      contains('[stdout] ${ProcessCommandRunner.sensitiveOutputNotice}'),
    );
    expect(realLog.lines, isNot(contains('[stdout] unset')));
  });

  test('config 의 프로젝트 ID 가 자리표시면 명령 없이 할 일 · 사유', () async {
    replaceJsonString(
      '$root/${UserFilesStep.jsonUserPath}',
      'firebaseProjectId',
      'your-project-dev',
    );
    final _Harness harness = _Harness(root, const <String?>[]);

    final int code = await harness.run();

    expect(code, wizardExitStopped);
    expect(harness.fake.calls, isEmpty);
    expect(
      harness.output,
      contains(
        '  ✗ ${FunctionsStep.stepTitle} — ${UserFilesStep.jsonUserPath}',
      ),
    );
  });

  test('buildDevSteps 는 App Check 단계 다음에 Functions 단계를 둔다', () {
    final List<String> ids = buildDevSteps()
        .map((Step step) => step.id)
        .toList();

    expect(ids.indexOf('functions'), ids.indexOf('app_check') + 1);
    final Step step = buildDevSteps().firstWhere(
      (Step s) => s.id == 'functions',
    );
    expect(step.title, FunctionsStep.stepTitle);
    expect(step.dependsOn, <String>['configure', 'apis', 'firestore']);
  });
}
