import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:test/test.dart';

import '../../../tool/setup/command_runner.dart';
import '../../../tool/setup/config_files.dart';
import '../../../tool/setup/flavor.dart';
import '../../../tool/setup/redactor.dart';
import '../../../tool/setup/rest_client.dart';
import '../../../tool/setup/secret_store.dart';
import '../../../tool/setup/step.dart';
import '../../../tool/setup/steps/dev_steps.dart';
import '../../../tool/setup/steps/functions_step.dart';
import '../../../tool/setup/steps/rules_step.dart';
import '../../../tool/setup/steps/sign_in_step.dart';
import '../../../tool/setup/steps/storage_step.dart';
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

/// firebase-tools `--json` 실패 출력(오류 객체 · 2칸 들여쓰기 · 끝 줄바꿈
/// 없음) — 함수 목록 조회 실패 원문 모양.
const String functionsListErrorStdout =
    '{\n'
    '  "status": "error",\n'
    '  "error": "Failed to list functions for $projectId"\n'
    '}';

/// 배포 스크립트 명령 키.
const String deployKey = 'bash scripts/deploy_functions.sh dev --apply';

/// stg 테스트 프로젝트 ID(가짜).
const String stgProjectId = 'demo-s';

/// stg 문맥 배포 스크립트 명령 키.
const String stgDeployKey = 'bash scripts/deploy_functions.sh stg --apply';

/// stg 문맥 secret 목록 명령 키.
const String stgSecretsListKey =
    'gcloud secrets list --project $stgProjectId --format=value(name)';

/// stg 문맥 배포된 함수 목록 명령 키.
const String stgFunctionsListKey =
    'firebase functions:list --json --project $stgProjectId';

/// stg 문맥 [service] 의 IAM 정책을 읽는 명령 키.
String buildStgIamKey(String service) =>
    'gcloud run services get-iam-policy $service --region $region '
    '--project $stgProjectId --format=json';

/// [name] secret 을 만드는 명령 키.
String buildSetKey(String name) =>
    'firebase functions:secrets:set $name --project $projectId --data-file -';

/// [service] 의 IAM 정책을 읽는 명령 키.
String buildIamKey(String service) =>
    'gcloud run services get-iam-policy $service --region $region '
    '--project $projectId --format=json';

/// [functionId] 의 Cloud Run 서비스 이름(가짜 — 소문자).
String buildServiceId(String functionId) => functionId.toLowerCase();

/// [service] 에 공개 호출을 붙이는 명령 키.
String buildBindKey(String service) =>
    'gcloud run services add-iam-policy-binding $service --region $region '
    '--member=allUsers --role=roles/run.invoker --project $projectId';

/// 컨테이너 이미지 정리 정책을 만드는 명령 키.
const String cleanupKey =
    'firebase functions:artifacts:setpolicy --project $projectId '
    '--location $region --non-interactive';

/// firebase-tools 원문 fixture — 조직 정책이 공개 호출을 막은 배포 출력.
const String invokerBlockedFixturePath =
    'test/tool/setup/fixtures/deploy_invoker_blocked.txt';

/// firebase-tools 원문 모양 fixture — 함수 빌드 계정에 역할이 없어 빌드가 실패한
/// 배포 출력(정리 정책 줄 · 묶음 실패 줄 포함 · 가짜 값).
const String buildAccountFixturePath =
    'test/tool/setup/fixtures/deploy_build_service_account.txt';

/// `functions:list --json` 원문 모양 fixture — 로그인 수단 함수 · 확장 함수가 쓰는
/// secret 과 배포 때 고정된 버전(모두 `1`)이 든 함수 목록(가짜 프로젝트).
const String providerSecretsFixturePath =
    'test/tool/setup/fixtures/functions_list_provider_secrets.json';

/// 배포 스크립트가 묶음 실패 때 표준 오류에 쓰는 줄.
const String batchFailLine = 'FAIL: 1번째 묶음 배포 실패 (1개 중) — 앞 묶음은 이미 배포됐다';

/// firebase-tools 가 비대화형에서 정리 정책을 묻지 못할 때의 오류 줄(색 없음).
const String cleanupPolicyErrorLine =
    'Error: Functions successfully deployed but could not set up cleanup '
    'policy in location $region. Pass the --force option to automatically '
    "set up a cleanup policy or run 'firebase functions:artifacts:setpolicy' "
    'to manually set up a cleanup policy.';

/// gcloud 가 조직 정책으로 공개 호출 추가를 거절할 때의 오류 줄.
const String permittedCustomerErrorLine =
    'ERROR: (gcloud.run.services.add-iam-policy-binding) FAILED_PRECONDITION: '
    'One or more users named in the policy do not belong to a permitted '
    'customer.';

/// 공개 호출이 없는 IAM 정책 응답(바인딩 없음).
const CommandResult emptyPolicy = CommandResult(0, '{}', '');

/// 공개 호출이 없는 IAM 정책 응답(다른 역할만 있음).
const CommandResult privatePolicy = CommandResult(
  0,
  '{"bindings":[{"members":["user:owner"],"role":"roles/run.admin"}],'
      '"etag":"BwYfake"}',
  '',
);

/// [text] 에서 [needle] 이 나온 횟수를 센다.
int countText(String text, String needle) => needle.allMatches(text).length;

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
    for (final text in <String>[result.stdout, result.stderr]) {
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
      rest = FakeRestClient(),
      screen = ScriptedTerminal(inputs),
      log = MemoryLogSink(Redactor()) {
    terminal = RedactingTerminal(screen, log.redactor, log);
    runner = _EchoingRunner(fake, terminal, onInstall: onInstall);
  }

  final String root;
  final FakeCommandRunner fake;
  final FakeRestClient rest;
  final ScriptedTerminal screen;
  final MemoryLogSink log;
  late final RedactingTerminal terminal;
  late final _EchoingRunner runner;

  /// 화면 출력 전체.
  String get output => screen.output.toString();

  /// 앞 단계(끝남) · Functions 단계로 위저드를 돌린다.
  ///
  /// [enabledProviders] 를 주면 그 로그인 수단 단계(끝남)를 앞에 두고 Functions
  /// 단계가 그 함수까지 확인한다. [flavor] 는 이번 실행의 flavor 다.
  Future<int> run({
    Set<String> enabledProviders = const <String>{},
    Flavor flavor = Flavor.dev,
  }) => runSteps(<Step>[
    _FinishedStep('configure', '앱 등록 · 설정 파일'),
    _FinishedStep('apis', '필요한 Google Cloud API'),
    _FinishedStep('firestore', '위치 · Firestore'),
    for (final String token in enabledProviders) _FinishedStep(token, token),
    FunctionsStep(
      enabledProviders: enabledProviders,
      providerStepIds: enabledProviders.toList(),
    ),
  ], flavor: flavor);

  /// [steps] 를 [flavor] 문맥으로 돌린다.
  Future<int> runSteps(List<Step> steps, {Flavor flavor = Flavor.dev}) =>
      runWizard(
        WizardContext(
          projectRoot: root,
          runner: runner,
          terminal: terminal,
          redactor: log.redactor,
          log: log,
          rest: rest,
          flavor: flavor,
          random: Random(fixedTestRandomSeed),
          now: () => fixedTestNow,
        ),
        steps,
      );
}

/// `gcloud secrets list --format=value(name)` 출력을 만든다(전체 자원 이름).
CommandResult buildSecretsList(Iterable<String> names) => CommandResult(
  0,
  names.map((String name) => 'projects/000000000000/secrets/$name\n').join(),
  '',
);

/// 1세대 Auth 삭제 트리거(`functions.auth.user().onDelete`)의 `eventTrigger` 모양.
const Map<String, Object?> authDeleteTrigger = <String, Object?>{
  'eventType': 'providers/firebase.auth/eventTypes/user.delete',
  'eventFilters': <String, Object?>{'resource': 'projects/$projectId'},
  'retry': false,
};

/// `functions:list --json` 항목 하나를 만든다 — 기본값은 실제 onCall 함수
/// 모양(2세대 · `callableTrigger: {}` · Cloud Run 서비스 있음 · 상태 없음)이다.
///
/// [triggerKey] 가 빈 문자열이면 트리거 키를 넣지 않는다.
Map<String, Object?> buildListedFunction(
  String id, {
  String platform = 'gcfv2',
  String triggerKey = 'callableTrigger',
  Map<String, Object?> trigger = const <String, Object?>{},
  bool hasRunService = true,
  String? state,
}) => <String, Object?>{
  'id': id,
  'project': projectId,
  'region': region,
  'platform': platform,
  'entryPoint': id,
  'runtime': 'nodejs22',
  if (triggerKey.isNotEmpty) triggerKey: trigger,
  if (hasRunService) 'runServiceId': buildServiceId(id),
  'state': ?state,
};

/// [items] 를 담은 `firebase functions:list --json` 성공 출력을 만든다.
CommandResult buildFunctionsListOf(Iterable<Map<String, Object?>> items) =>
    CommandResult(
      0,
      jsonEncode(<String, Object?>{
        'status': 'success',
        'result': <Object?>[...items],
      }),
      '',
    );

/// `firebase functions:list --json` 성공 출력을 만든다(함수마다 실제 onCall 모양).
CommandResult buildFunctionsList(Iterable<String> functionIds) =>
    buildFunctionsListOf(functionIds.map(buildListedFunction));

/// 공통 함수(secret 없음) 뒤에 [providerSecretsFixturePath] 의 함수를 이어 붙인
/// `functions:list --json` 출력을 만든다.
///
/// [versions] 는 함수 이름 → 그 함수가 쓰는 secret 전부의 배포 버전이다(없으면
/// fixture 값 그대로).
CommandResult buildFunctionsListWithSecrets(
  Iterable<String> commonIds, {
  Map<String, String> versions = const <String, String>{},
}) {
  final common =
      jsonDecode(buildFunctionsList(commonIds).stdout)! as Map<String, Object?>;
  final fixture =
      jsonDecode(File(providerSecretsFixturePath).readAsStringSync())!
          as Map<String, Object?>;
  return CommandResult(
    0,
    jsonEncode(<String, Object?>{
      'status': 'success',
      'result': <Object?>[
        ...common['result']! as List<Object?>,
        for (final Object? item in fixture['result']! as List<Object?>)
          replaceSecretVersion(item! as Map<String, Object?>, versions),
      ],
    }),
    '',
  );
}

/// [item] 함수의 secret 버전을 [versions] 의 값으로 바꾼 사본을 만든다.
Map<String, Object?> replaceSecretVersion(
  Map<String, Object?> item,
  Map<String, String> versions,
) {
  final String? version = versions[item['id']];
  if (version == null) return item;
  return <String, Object?>{
    ...item,
    'secretEnvironmentVariables': <Object?>[
      for (final Object? variable
          in item['secretEnvironmentVariables']! as List<Object?>)
        <String, Object?>{
          ...variable! as Map<String, Object?>,
          'version': version,
        },
    ],
  };
}

/// [name] 의 Secret Manager 최신 버전 메타데이터 요청 주소.
String buildLatestUrl(String name) =>
    buildLatestVersionRequest(projectId, name).url.toString();

/// Secret Manager 최신 버전 메타데이터 응답(값 없음)을 만든다 — 이름은 프로젝트
/// 번호로 온다.
RestResponse buildLatestResponse(String name, int version) => RestResponse(
  200,
  jsonEncode(<String, Object?>{
    'name': 'projects/000000000000/secrets/$name/versions/$version',
    'createTime': 'fixed',
    'state': 'ENABLED',
    'replicationStatus': <String, Object?>{'automatic': <String, Object?>{}},
    'etag': '"e0"',
  }),
);

/// 배포 스크립트의 실행 출력을 만든다 — [lastLine] 이 마지막 줄이다.
CommandResult buildDeployOutput(
  List<String> functionIds, {
  int exitCode = 0,
  String? lastLine,
  String stderr = '',
  String flavorName = 'dev',
  String project = projectId,
}) {
  final String only = functionIds.map((String id) => 'functions:$id').join(',');
  return CommandResult(
    exitCode,
    'flavor: $flavorName\n'
    'project: $project\n'
    'mode: firebase\n'
    'enabled: (없음)\n'
    'functions (${functionIds.length}):\n'
    '${functionIds.map((String id) => '  - $id\n').join()}'
    'command: firebase deploy --project $project --only $only\n'
    'running: firebase deploy --project $project --only $only\n'
    '\n'
    '${lastLine ?? 'DEPLOY OK $flavorName functions=${functionIds.length} batches=1'}\n',
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
    for (final id in commonFunctions) {
      fake.on(buildIamKey(buildServiceId(id)), publicPolicy);
    }
  }

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('functions_step_test_');
    root = tempDir.path;
    final config = File('$root/${UserFilesStep.jsonUserPath}')
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
      final harness = _Harness(root, const <String?>[]);
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
    const missing = <String>[
      'FACEBOOK_APP_SECRET',
      'KAKAO_ADMIN_KEY',
      'NAVER_CLIENT_ID',
    ];
    final List<String> present = declaredSecrets
        .where((String name) => !missing.contains(name))
        .toList();
    final harness = _Harness(root, const <String?>[
      'y',
    ], onInstall: writeModulesMarker);
    harness.fake
      ..on(secretsListKey, buildSecretsList(present))
      ..on(secretsListKey, buildSecretsList(present))
      ..on(secretsListKey, buildSecretsList(declaredSecrets))
      ..on(installKey, _ok)
      ..on(deployKey, buildDeployOutput(commonFunctions));
    for (final name in missing) {
      harness.fake.on(buildSetKey(name), _ok);
    }
    registerDeployed(harness.fake);

    final int code = await harness.run();

    expect(code, wizardExitDone);
    expect(harness.fake.countCalls(RunMode.stream, installKey), 1);
    expect(harness.fake.countCalls(RunMode.stream, deployKey), 1);
    for (final name in missing) {
      final List<FakeCall> sets = harness.fake.calls
          .where((FakeCall call) => call.key == buildSetKey(name))
          .toList();
      expect(sets, hasLength(1), reason: name);
      expect(sets.single.mode, RunMode.capture);
      expect(sets.single.stdinText, FunctionsStep.secretPlaceholder);
      expect(sets.single.key, isNot(contains('unset')));
    }
    for (final name in present) {
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
    expect(
      harness.output,
      contains('DEPLOY OK dev functions=${commonFunctions.length} batches=1'),
    );
    expect(harness.output, contains('  ✓ ${FunctionsStep.stepTitle} — '));
  });

  test('T-19-FN-03: 배포 exit 0 이지만 마지막 줄이 DRY-RUN OK 면 실패', () async {
    writeModulesMarker();
    final harness = _Harness(root, const <String?>['y', '2']);
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
    const errorLine =
        'Error: HTTP Error: 403, The caller does not have permission';
    const failLine = 'FAIL: 1번째 묶음 배포 실패 (1개 중) — 앞 묶음은 이미 배포됐다';
    final harness = _Harness(root, const <String?>['y', '2']);
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
    // 계획 줄의 「조직 정책이 막으면 안내합니다」 는 남고, 안내 본문은 나오지 않는다.
    expect(harness.output, isNot(contains(FunctionsStep.orgPolicyGuidance)));
    expect(harness.output, isNot(contains('조직 관리자에게')));
    expect(harness.output, isNot(contains('restrict-domains')));
  });

  test('T-19-FN-05: secret 생성이 exit 1 이면 실패 · 배포 0', () async {
    writeModulesMarker();
    const errorLine = 'Error: HTTP Error: 403, Permission denied on secret';
    final harness = _Harness(root, const <String?>['y', '2']);
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
    const missing = <String>['FACEBOOK_APP_ID', 'LINE_CHANNEL_SECRET'];
    const createdLine =
        'Created a new secret version projects/000000000000/secrets/X/versions/1';
    final harness = _Harness(root, const <String?>['y']);
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
    for (final name in missing) {
      harness.fake.on(
        buildSetKey(name),
        const CommandResult(0, createdLine, ''),
      );
    }
    registerDeployed(harness.fake);

    final int code = await harness.run();

    expect(code, wizardExitDone);
    for (final name in missing) {
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
    final realLog = MemoryLogSink(Redactor());
    final realScreen = ScriptedTerminal(const <String?>[]);
    final real = ProcessCommandRunner(
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

  /// fixture [path] 원문을 배포 스크립트 결과로 만든다 — `FAIL:` 줄은 표준 오류,
  /// 나머지는 표준 출력이다.
  CommandResult buildFixtureDeployResult([
    String path = invokerBlockedFixturePath,
  ]) {
    final List<String> lines = File(path).readAsLinesSync();
    return CommandResult(
      1,
      lines.where((String line) => !line.startsWith('FAIL:')).join('\n'),
      '${lines.where((String line) => line.startsWith('FAIL:')).join('\n')}\n',
    );
  }

  /// 점검표의 Functions 단계 사유를 꺼낸다.
  String readChecklistReason(String output) => output
      .split('\n')
      .firstWhere(
        (String line) => line.startsWith('  ✗ ${FunctionsStep.stepTitle} — '),
      )
      .substring('  ✗ ${FunctionsStep.stepTitle} — '.length);

  /// 모든 공개 호출 추가 명령의 호출 수.
  int countBindings(FakeCommandRunner fake) => fake.calls
      .where(
        (FakeCall call) =>
            call.key.startsWith('gcloud run services add-iam-policy-binding'),
      )
      .length;

  test('T-19-FN-07: 배포됨 · 한 서비스만 공개 호출 없음 → 그 서비스만 보정 → 재검사 ✓', () async {
    writeModulesMarker();
    final String lackingService = buildServiceId('deleteUserAccount');
    final harness = _Harness(root, const <String?>['y']);
    harness.fake
      ..on(secretsListKey, buildSecretsList(declaredSecrets))
      ..on(functionsListKey, buildFunctionsList(commonFunctions))
      // 점검표 · 단계 시작 검사는 공개 호출 없음, 실행 뒤 재검사는 있음.
      ..on(buildIamKey(lackingService), privatePolicy)
      ..on(buildIamKey(lackingService), privatePolicy)
      ..on(buildIamKey(lackingService), publicPolicy)
      ..on(buildBindKey(lackingService), _ok);
    for (final id in commonFunctions) {
      if (buildServiceId(id) == lackingService) continue;
      harness.fake.on(buildIamKey(buildServiceId(id)), publicPolicy);
    }

    final int code = await harness.run();

    expect(code, wizardExitDone);
    expect(readChecklistReason(harness.output), contains('공개 호출이 막힌 함수'));
    expect(readChecklistReason(harness.output), contains('deleteUserAccount'));
    expect(
      harness.fake.countCalls(RunMode.stream, buildBindKey(lackingService)),
      1,
    );
    expect(countBindings(harness.fake), 1);
    expect(harness.fake.countCalls(RunMode.stream, deployKey), 0);
    expect(harness.output, contains('  \$ ${buildBindKey(lackingService)}'));
    expect(harness.output, contains('  ✓ ${FunctionsStep.stepTitle} — '));
  });

  test('배포 뒤 공개 호출이 빠진 서비스는 같은 확인 안에서 붙인다', () async {
    writeModulesMarker();
    final String lackingService = buildServiceId('mirrorAccountEmail');
    final harness = _Harness(root, const <String?>['y']);
    harness.fake
      ..on(secretsListKey, buildSecretsList(declaredSecrets))
      ..on(functionsListKey, buildFunctionsList(const <String>[]))
      ..on(functionsListKey, buildFunctionsList(const <String>[]))
      ..on(functionsListKey, buildFunctionsList(commonFunctions))
      ..on(deployKey, buildDeployOutput(commonFunctions))
      // 배포 직후 확인은 공개 호출 없음, 실행 뒤 재검사는 있음.
      ..on(buildIamKey(lackingService), emptyPolicy)
      ..on(buildIamKey(lackingService), publicPolicy)
      ..on(buildBindKey(lackingService), _ok);
    for (final id in commonFunctions) {
      if (buildServiceId(id) == lackingService) continue;
      harness.fake.on(buildIamKey(buildServiceId(id)), publicPolicy);
    }

    final int code = await harness.run();

    expect(code, wizardExitDone);
    expect(harness.fake.countCalls(RunMode.stream, deployKey), 1);
    expect(
      harness.fake.countCalls(RunMode.stream, buildBindKey(lackingService)),
      1,
    );
    expect(countBindings(harness.fake), 1);
    expect(harness.screen.asks, <String>[stepConfirmQuestion]);
    expect(harness.output, contains('  ✓ ${FunctionsStep.stepTitle} — '));
  });

  test('T-19-FN-08: 배포 출력이 조직 정책 원문이면 원문 뒤에 안내 · 공개 호출 추가 0', () async {
    writeModulesMarker();
    final harness = _Harness(root, const <String?>['y', '2']);
    harness.fake
      ..on(secretsListKey, buildSecretsList(declaredSecrets))
      ..on(functionsListKey, buildFunctionsList(const <String>[]))
      ..on(deployKey, buildFixtureDeployResult());

    final int code = await harness.run();

    expect(code, wizardExitStopped);
    final String output = harness.output;
    for (final String line in File(
      invokerBlockedFixturePath,
    ).readAsLinesSync()) {
      if (line.trim().isEmpty) continue;
      expect(output, contains(line));
    }
    expect(output, contains(FunctionsStep.orgPolicyGuidance));
    expect(output, contains(FunctionsStep.orgPolicyDocUrl));
    expect(
      output.indexOf(FunctionsStep.orgPolicyGuidance),
      greaterThan(output.lastIndexOf('Unable to set the invoker')),
    );
    expect(
      output.indexOf(FunctionsStep.orgPolicyGuidance),
      greaterThan(output.lastIndexOf(batchFailLine)),
    );
    expect(countText(output, 'Unable to set the invoker'), 1);
    expect(countBindings(harness.fake), 0);
    expect(harness.fake.countCalls(RunMode.stream, cleanupKey), 0);
    expect(harness.fake.countCalls(RunMode.stream, deployKey), 1);
  });

  test('T-19-FN-09: 공개 호출 추가가 permitted customer 로 실패하면 안내 · 같은 명령 '
      '재시도 0', () async {
    writeModulesMarker();
    final String first = buildServiceId('deleteUserAccount');
    final String second = buildServiceId('sendTestPush');
    final harness = _Harness(root, const <String?>['y', '2']);
    harness.fake.on(secretsListKey, buildSecretsList(declaredSecrets));
    harness.fake.on(functionsListKey, buildFunctionsList(commonFunctions));
    for (final id in commonFunctions) {
      final String service = buildServiceId(id);
      harness.fake.on(
        buildIamKey(service),
        service == first || service == second ? emptyPolicy : publicPolicy,
      );
    }
    harness.fake
      ..on(
        buildBindKey(first),
        const CommandResult(1, '', '$permittedCustomerErrorLine\n'),
      )
      ..on(buildBindKey(second), _ok);

    final int code = await harness.run();

    expect(code, wizardExitStopped);
    expect(harness.fake.countCalls(RunMode.stream, buildBindKey(first)), 1);
    expect(countBindings(harness.fake), 1);
    final String output = harness.output;
    expect(output, contains(permittedCustomerErrorLine));
    expect(output, contains(FunctionsStep.orgPolicyGuidance));
    expect(output, contains(FunctionsStep.orgPolicyDocUrl));
    expect(
      output.indexOf(FunctionsStep.orgPolicyGuidance),
      greaterThan(output.lastIndexOf(permittedCustomerErrorLine)),
    );
    expect(countText(output, permittedCustomerErrorLine), 1);
    expect(harness.screen.asks, <String>[
      stepConfirmQuestion,
      failureChoiceQuestion,
    ]);
  });

  test('T-19-FN-10: 바인딩 없는 정책({})은 공개 호출 없음으로 판정', () async {
    expect(FunctionsStep.hasPublicInvoker(emptyPolicy), isFalse);
    expect(
      FunctionsStep.hasPublicInvoker(
        const CommandResult(0, '{"etag":"BwYfake"}', ''),
      ),
      isFalse,
    );
    expect(FunctionsStep.hasPublicInvoker(privatePolicy), isFalse);
    expect(FunctionsStep.hasPublicInvoker(publicPolicy), isTrue);
    expect(
      FunctionsStep.hasPublicInvoker(const CommandResult(1, '', 'ERROR')),
      isNull,
    );
    expect(
      FunctionsStep.hasPublicInvoker(const CommandResult(0, 'not json', '')),
      isNull,
    );

    writeModulesMarker();
    final String service = buildServiceId('ping');
    final harness = _Harness(root, const <String?>[]);
    harness.fake.on(secretsListKey, buildSecretsList(declaredSecrets));
    harness.fake.on(functionsListKey, buildFunctionsList(commonFunctions));
    for (final id in commonFunctions) {
      harness.fake.on(
        buildIamKey(buildServiceId(id)),
        buildServiceId(id) == service ? emptyPolicy : publicPolicy,
      );
    }

    final int code = await harness.run();

    expect(code, wizardExitStopped);
    expect(readChecklistReason(harness.output), contains('공개 호출이 막힌 함수'));
    expect(readChecklistReason(harness.output), contains('ping'));
    expect(countBindings(harness.fake), 0);
  });

  test('T-19-FN-11: fixture 에 이메일 · 실제 프로젝트 ID 모양 문자열이 없다', () {
    final String fixture = File(invokerBlockedFixturePath).readAsStringSync();

    expect(
      RegExp(
        r'[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}',
      ).hasMatch(fixture),
      isFalse,
    );
    expect(fixture, isNot(contains('slimpumpkin')));
    final projects = <String>{
      for (final RegExpMatch match in RegExp(
        r'projects/([^/\s]+)',
      ).allMatches(fixture))
        match.group(1)!,
      for (final RegExpMatch match in RegExp(
        r'--project (\S+)',
      ).allMatches(fixture))
        match.group(1)!,
    };
    expect(projects, <String>{projectId});
    expect(fixture, contains('\tping($region)'));
    expect(
      countText(
        fixture,
        'Unable to set the invoker for the IAM policy on the following '
        'functions:',
      ),
      1,
    );
    expect(countText(fixture, 'There was an error deploying functions'), 1);
  });

  group('T-19-FN-12: 정리 정책이 없어 배포가 실패로 끝날 때', () {
    /// 정리 정책 오류로 끝난 첫 배포 결과.
    CommandResult buildCleanupFailure({String extraLines = ''}) =>
        buildDeployOutput(
          commonFunctions,
          exitCode: 1,
          lastLine: '$extraLines$cleanupPolicyErrorLine',
          stderr: '$batchFailLine\n',
        );

    test('정책을 만들고(강제 옵션 없이) 한 번 더 배포 → DEPLOY OK → 재검사 ✓', () async {
      writeModulesMarker();
      final harness = _Harness(root, const <String?>['y']);
      harness.fake
        ..on(secretsListKey, buildSecretsList(declaredSecrets))
        ..on(functionsListKey, buildFunctionsList(const <String>[]))
        ..on(functionsListKey, buildFunctionsList(const <String>[]))
        ..on(functionsListKey, buildFunctionsList(commonFunctions))
        ..on(deployKey, buildCleanupFailure())
        ..on(deployKey, buildDeployOutput(commonFunctions))
        ..on(cleanupKey, _ok);
      for (final id in commonFunctions) {
        harness.fake.on(buildIamKey(buildServiceId(id)), publicPolicy);
      }

      final int code = await harness.run();

      expect(code, wizardExitDone);
      expect(harness.fake.countCalls(RunMode.stream, cleanupKey), 1);
      expect(harness.fake.countCalls(RunMode.stream, deployKey), 2);
      expect(
        harness.fake.calls.where(
          (FakeCall call) => call.key.contains('--force'),
        ),
        isEmpty,
      );
      final List<String> streamed = harness.fake.calls
          .where((FakeCall call) => call.mode == RunMode.stream)
          .map((FakeCall call) => call.key)
          .toList();
      expect(streamed, <String>[deployKey, cleanupKey, deployKey]);
      expect(harness.runner.workingDirectories[cleanupKey], root);
      expect(harness.output, contains(cleanupPolicyErrorLine));
      expect(harness.output, contains('  \$ $cleanupKey'));
      expect(harness.output, contains('  ✓ ${FunctionsStep.stepTitle} — '));
      expect(countBindings(harness.fake), 0);
    });

    test('출력에 공개 호출 실패 줄도 있으면 조직 정책 안내 · 정책 명령 0', () async {
      writeModulesMarker();
      final harness = _Harness(root, const <String?>['y', '2']);
      harness.fake
        ..on(secretsListKey, buildSecretsList(declaredSecrets))
        ..on(functionsListKey, buildFunctionsList(const <String>[]))
        ..on(
          deployKey,
          buildCleanupFailure(
            extraLines:
                'Unable to set the invoker for the IAM policy on the '
                'following functions:\n\tping($region)\n',
          ),
        );

      final int code = await harness.run();

      expect(code, wizardExitStopped);
      expect(harness.fake.countCalls(RunMode.stream, cleanupKey), 0);
      expect(harness.fake.countCalls(RunMode.stream, deployKey), 1);
      expect(harness.output, contains(FunctionsStep.orgPolicyGuidance));
    });

    test('정책 명령이 exit 1 이면 원문과 함께 실패 · 둘째 배포 0', () async {
      writeModulesMarker();
      const policyError =
          'Error: Failed to set up artifact registry '
          'cleanup policy';
      final harness = _Harness(root, const <String?>['y', '2']);
      harness.fake
        ..on(secretsListKey, buildSecretsList(declaredSecrets))
        ..on(functionsListKey, buildFunctionsList(const <String>[]))
        ..on(deployKey, buildCleanupFailure())
        ..on(cleanupKey, const CommandResult(1, '', '$policyError\n'));

      final int code = await harness.run();

      expect(code, wizardExitStopped);
      expect(harness.fake.countCalls(RunMode.stream, cleanupKey), 1);
      expect(harness.fake.countCalls(RunMode.stream, deployKey), 1);
      expect(harness.output, contains('  실패 — '));
      expect(harness.output, contains(policyError));
      expect(harness.output, isNot(contains(FunctionsStep.orgPolicyGuidance)));
    });
  });

  test('config 의 프로젝트 ID 가 자리표시면 명령 없이 할 일 · 사유', () async {
    replaceJsonString(
      '$root/${UserFilesStep.jsonUserPath}',
      'firebaseProjectId',
      'your-project-dev',
    );
    final harness = _Harness(root, const <String?>[]);

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

  group('배포된 함수 목록을 읽지 못한 사유 한 줄', () {
    /// 함수 목록 조회 실패 사유의 고정 앞부분.
    const listFailurePrefix = '배포된 함수 목록을 읽지 못했습니다 — ';

    /// 함수 목록 조회가 [listed] 로 끝나는 위저드를 돌려 화면 출력 전체를
    /// 돌려준다.
    Future<String> runListFailure(CommandResult listed) async {
      writeModulesMarker();
      final harness = _Harness(root, const <String?>[]);
      harness.fake
        ..on(secretsListKey, buildSecretsList(declaredSecrets))
        ..on(functionsListKey, listed);

      final int code = await harness.run();

      expect(code, wizardExitStopped);
      expect(harness.fake.countMode(RunMode.stream), 0);
      return harness.output;
    }

    /// 함수 목록 조회가 [listed] 로 끝날 때 점검표의 Functions 사유를 돌려준다.
    Future<String> readListFailureReason(CommandResult listed) async =>
        readChecklistReason(await runListFailure(listed));

    test('JSON 오류 출력(여러 줄)이면 error 값을 사유로 쓴다', () async {
      final String reason = await readListFailureReason(
        const CommandResult(1, functionsListErrorStdout, ''),
      );

      expect(
        reason,
        equals('${listFailurePrefix}Failed to list functions for $projectId'),
      );
    });

    test('표준 오류에 Node 경고 줄이 있어도 표준 출력 JSON 의 error 값이 먼저다', () async {
      final String reason = await readListFailureReason(
        const CommandResult(
          1,
          functionsListErrorStdout,
          '(node:4242) [DEP0040] DeprecationWarning: The punycode module is '
          'deprecated. Please use a userland alternative instead.\n',
        ),
      );

      expect(
        reason,
        equals('${listFailurePrefix}Failed to list functions for $projectId'),
      );
    });

    test('error 값이 여러 줄이면 첫 빈 줄 아닌 줄만 쓴다', () async {
      final String stdout = const JsonEncoder.withIndent('  ')
          .convert(<String, Object?>{
            'status': 'error',
            'error': '\nFailed to list functions for $projectId\n(두 번째 줄)',
          });

      final String output = await runListFailure(CommandResult(1, stdout, ''));

      expect(
        readChecklistReason(output),
        equals('${listFailurePrefix}Failed to list functions for $projectId'),
      );
      // 둘째 줄이 점검표 다음 줄로 새어 나오지 않는다.
      expect(output, isNot(contains('(두 번째 줄)')));
    });

    /// 쓸 수 없는 표준 출력(라벨 → 내용) — 모두 표준 오류 첫 줄로 대체돼야 한다.
    const unusableStdouts = <(String, String)>[
      ('JSON 아닌 글', 'Something went wrong'),
      ('빈 표준 출력', ''),
      ('객체 아닌 JSON', '[]'),
      ('error 없는 객체', '{\n  "status": "error"\n}'),
      ('error 가 숫자', '{"status": "error", "error": 42}'),
      ('error 가 공백 · 줄바꿈뿐', r'{"status": "error", "error": "  \n  "}'),
    ];
    for (final (String label, String stdout) in unusableStdouts) {
      test('JSON 오류 객체가 아니면 지금처럼 표준 오류 첫 줄 — $label', () async {
        final String reason = await readListFailureReason(
          CommandResult(
            1,
            stdout,
            'Error: HTTP Error: 403, The caller does not have permission\n',
          ),
        );

        expect(
          reason,
          equals(
            '${listFailurePrefix}Error: HTTP Error: 403, '
            'The caller does not have permission',
          ),
        );
      });
    }

    test('JSON 이 아니고 표준 오류가 비면 표준 출력의 첫 빈 줄 아닌 줄', () async {
      final String reason = await readListFailureReason(
        const CommandResult(
          1,
          '\nError: Failed to authenticate, have you run firebase login?\n',
          '',
        ),
      );

      expect(
        reason,
        equals(
          '${listFailurePrefix}Error: Failed to authenticate, '
          'have you run firebase login?',
        ),
      );
    });
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

  test(
    'T-20-FUNC-01: Kakao 를 켜고 Kakao 함수 1개가 배포되지 않았으면 ✗ · 계획 줄에 배포 스크립트',
    () async {
      writeModulesMarker();
      final List<String> kakaoFunctions = FunctionsStep.readProviderFunctions(
        root,
        'kakao',
      )!;
      expect(kakaoFunctions, isNotEmpty);
      final deployed = <String>[...commonFunctions, ...kakaoFunctions.skip(1)];
      final harness = _Harness(root, const <String?>[]);
      harness.fake
        ..on(secretsListKey, buildSecretsList(declaredSecrets))
        ..on(functionsListKey, buildFunctionsList(deployed));
      for (final id in deployed) {
        harness.fake.on(buildIamKey(buildServiceId(id)), publicPolicy);
      }

      final int code = await harness.run(
        enabledProviders: const <String>{'kakao'},
      );

      expect(code, wizardExitStopped);
      expect(
        readChecklistReason(harness.output),
        contains('배포되지 않은 함수가 있습니다 (${kakaoFunctions.first})'),
      );
      expect(harness.output, contains('  \$ $deployKey'));
      expect(harness.fake.countMode(RunMode.stream), 0);
      expect(
        FunctionsStep(
          enabledProviders: const <String>{'kakao'},
          providerStepIds: const <String>['kakao'],
        ).dependsOn,
        <String>['configure', 'apis', 'firestore', 'kakao'],
      );
      expect(FunctionsStep().dependsOn, <String>[
        'configure',
        'apis',
        'firestore',
      ]);
    },
  );

  /// Kakao 함수 · 공통 함수 모두의 공개 호출을 등록한다.
  void registerPublicPolicies(FakeCommandRunner fake, List<String> ids) {
    for (final id in ids) {
      fake.on(buildIamKey(buildServiceId(id)), publicPolicy);
    }
  }

  /// Kakao 함수 이름(함수 목록 파일 순서).
  List<String> readKakaoFunctions() =>
      FunctionsStep.readProviderFunctions(root, 'kakao')!;

  test('T-20-FUNC-02: Kakao 켬 · kakaoCustomToken 의 네이티브 앱 키 버전 1 · 최신 2 → ✗ '
      '함수 1개 · 배포 스크립트 1회 · 재검사 ✓', () async {
    writeModulesMarker();
    final List<String> kakaoFunctions = readKakaoFunctions();
    final harness = _Harness(root, const <String?>['y']);
    harness.fake
      ..on(secretsListKey, buildSecretsList(declaredSecrets))
      ..on(
        functionsListKey,
        buildFunctionsListWithSecrets(
          commonFunctions,
          versions: const <String, String>{'linkKakaoProvider': '2'},
        ),
      )
      ..on(
        functionsListKey,
        buildFunctionsListWithSecrets(
          commonFunctions,
          versions: const <String, String>{'linkKakaoProvider': '2'},
        ),
      )
      ..on(
        functionsListKey,
        buildFunctionsListWithSecrets(
          commonFunctions,
          versions: const <String, String>{
            'kakaoCustomToken': '2',
            'linkKakaoProvider': '2',
          },
        ),
      )
      ..on(
        deployKey,
        buildDeployOutput(<String>[...commonFunctions, ...kakaoFunctions]),
      );
    registerPublicPolicies(harness.fake, <String>[
      ...commonFunctions,
      ...kakaoFunctions,
    ]);
    harness.rest
      ..on(
        'GET',
        buildLatestUrl('KAKAO_NATIVE_APP_KEY'),
        buildLatestResponse('KAKAO_NATIVE_APP_KEY', 2),
      )
      ..on(
        'GET',
        buildLatestUrl('KAKAO_ADMIN_KEY'),
        buildLatestResponse('KAKAO_ADMIN_KEY', 1),
      );

    final int code = await harness.run(
      enabledProviders: const <String>{'kakao'},
    );

    expect(code, wizardExitDone, reason: harness.output);
    expect(
      readChecklistReason(harness.output),
      'secret 새 값이 함수에 반영되지 않았습니다 — 함수 1개',
    );
    expect(harness.output, contains('  \$ $deployKey'));
    expect(harness.output, contains('(배포하면 함수가 secret 최신 값을 씁니다)'));
    expect(harness.fake.countCalls(RunMode.stream, deployKey), 1);
    // 점검표 · 단계 머리 재검사 · 실행 뒤 재검사에서 secret 마다 한 번씩.
    expect(
      harness.rest.countRequests('GET', buildLatestUrl('KAKAO_NATIVE_APP_KEY')),
      3,
    );
    expect(
      harness.rest.countRequests('GET', buildLatestUrl('KAKAO_ADMIN_KEY')),
      3,
    );
    expect(harness.rest.requests, hasLength(6));
    expect(harness.output, contains('  ✓ ${FunctionsStep.stepTitle} — '));
  });

  test('T-20-FUNC-03: 켠 수단 함수의 secret 버전이 모두 최신이면 ✓ · 배포 0', () async {
    writeModulesMarker();
    final List<String> kakaoFunctions = readKakaoFunctions();
    final harness = _Harness(root, const <String?>[]);
    harness.fake
      ..on(secretsListKey, buildSecretsList(declaredSecrets))
      ..on(
        functionsListKey,
        buildFunctionsListWithSecrets(
          commonFunctions,
          versions: const <String, String>{
            'kakaoCustomToken': '2',
            'linkKakaoProvider': '2',
          },
        ),
      );
    registerPublicPolicies(harness.fake, <String>[
      ...commonFunctions,
      ...kakaoFunctions,
    ]);
    harness.rest
      ..on(
        'GET',
        buildLatestUrl('KAKAO_NATIVE_APP_KEY'),
        buildLatestResponse('KAKAO_NATIVE_APP_KEY', 2),
      )
      ..on(
        'GET',
        buildLatestUrl('KAKAO_ADMIN_KEY'),
        buildLatestResponse('KAKAO_ADMIN_KEY', 1),
      );

    final int code = await harness.run(
      enabledProviders: const <String>{'kakao'},
    );

    expect(code, wizardExitDone, reason: harness.output);
    expect(harness.output, contains('  ✓ ${FunctionsStep.stepTitle} — '));
    expect(harness.fake.countMode(RunMode.stream), 0);
    expect(harness.screen.asks, isEmpty);
    expect(harness.rest.requests, hasLength(2));
  });

  group('T-20-FUNC-04: 최신 버전을 읽지 못하면 ✓ 가 아니고 실행은 원문을 보이는 실패다', () {
    for (final (int status, String body, String shown) in <(int, String, String)>[
      (
        403,
        '{"error":{"code":403,"status":"PERMISSION_DENIED","message":"denied"}}',
        'HTTP 403',
      ),
      (0, '', '요청하지 못했습니다'),
    ]) {
      test('상태 $status', () async {
        writeModulesMarker();
        final harness = _Harness(root, const <String?>['y', '2']);
        harness.fake
          ..on(secretsListKey, buildSecretsList(declaredSecrets))
          ..on(
            functionsListKey,
            buildFunctionsListWithSecrets(commonFunctions),
          );
        harness.rest.on(
          'GET',
          buildLatestUrl('KAKAO_NATIVE_APP_KEY'),
          RestResponse(status, body),
        );

        final int code = await harness.run(
          enabledProviders: const <String>{'kakao'},
        );

        expect(code, wizardExitStopped, reason: harness.output);
        final String reason = readChecklistReason(harness.output);
        expect(reason, contains('KAKAO_NATIVE_APP_KEY'));
        expect(reason, contains(shown));
        expect(
          harness.output,
          isNot(contains('  ✓ ${FunctionsStep.stepTitle} — ')),
        );
        expect(harness.screen.asks.last, failureChoiceQuestion);
        expect(harness.fake.countMode(RunMode.stream), 0);
        if (body.isNotEmpty) {
          expect(harness.output, contains('PERMISSION_DENIED'));
        }
      });
    }
  });

  test('T-20-FUNC-05: 켠 수단이 없으면 함수에 secret 이 있어도 최신 버전 요청 0 · '
      '판정 문장 그대로', () async {
    writeModulesMarker();
    final harness = _Harness(root, const <String?>[]);
    harness.fake
      ..on(secretsListKey, buildSecretsList(declaredSecrets))
      ..on(functionsListKey, buildFunctionsListWithSecrets(commonFunctions));
    registerPublicPolicies(harness.fake, commonFunctions);

    final int code = await harness.run();

    expect(code, wizardExitDone, reason: harness.output);
    expect(harness.rest.requests, isEmpty);
    expect(
      harness.output,
      contains(
        '  ✓ ${FunctionsStep.stepTitle} — 의존성 · secret '
        '${declaredSecrets.length}개 · 공통 함수 ${commonFunctions.length}개 배포 · '
        '공개 호출 확인',
      ),
    );
  });

  group('T-20-FUNC-06: 꺼진 로그인 수단의 함수가 남아 있으면 ✓ 줄에 정보만 붙인다', () {
    const kakaoFunctions = <String>[
      'kakaoCustomToken',
      'linkKakaoProvider',
      'disconnectKakaoProvider',
    ];

    /// 공통 함수만 확인하는 ✓ 판정 문장.
    String buildDoneLine() =>
        '  ✓ ${FunctionsStep.stepTitle} — 의존성 · secret '
        '${declaredSecrets.length}개 · 공통 함수 ${commonFunctions.length}개 배포 · '
        '공개 호출 확인';

    test('Kakao 를 끈 저장소에 Kakao 함수 3개가 남으면 개수 · 지우는 명령을 보이고 묻지 '
        '않는다', () async {
      writeModulesMarker();
      final harness = _Harness(root, const <String?>[]);
      harness.fake
        ..on(secretsListKey, buildSecretsList(declaredSecrets))
        ..on(
          functionsListKey,
          buildFunctionsList(<String>[
            ...commonFunctions,
            ...kakaoFunctions.reversed,
          ]),
        );
      registerPublicPolicies(harness.fake, commonFunctions);

      final int code = await harness.run();

      expect(code, wizardExitDone, reason: harness.output);
      expect(
        harness.output,
        contains(
          '${buildDoneLine()} · 꺼진 로그인 수단의 함수 3개가 남아 있습니다 — 지우기: '
          'firebase functions:delete kakaoCustomToken linkKakaoProvider '
          'disconnectKakaoProvider --region $region --project $projectId\n',
        ),
      );
      expect(harness.output, isNot(contains('--force')));
      expect(harness.screen.asks, isEmpty);
      expect(harness.fake.countMode(RunMode.stream), 0);
    });

    test('남은 게 없으면 판정 문장 그대로다', () async {
      writeModulesMarker();
      final harness = _Harness(root, const <String?>[]);
      harness.fake.on(secretsListKey, buildSecretsList(declaredSecrets));
      registerDeployed(harness.fake);

      final int code = await harness.run();

      expect(code, wizardExitDone, reason: harness.output);
      expect(harness.output, contains('${buildDoneLine()}\n'));
      expect(harness.output, isNot(contains('꺼진 로그인 수단')));
      expect(harness.screen.asks, isEmpty);
    });
  });

  /// stg config(example 복사 · stg 프로젝트 ID)를 쓴다.
  void writeStgConfig() {
    const paths = FlavorPaths(Flavor.stg);
    final config = File('$root/${paths.json}')
      ..parent.createSync(recursive: true);
    File(paths.jsonExample).copySync(config.path);
    replaceJsonString(config.path, 'firebaseProjectId', stgProjectId);
  }

  group('T-20-STG-07: stg 문맥 Functions 배포 — 명령 키 · 마지막 줄 계약이 stg', () {
    setUp(() {
      writeStgConfig();
      writeModulesMarker();
    });

    test('마지막 줄이 DEPLOY OK dev … 면 실패 · 사유에 stg 완료 줄', () async {
      final harness = _Harness(root, const <String?>['y', '2']);
      harness.fake
        ..on(stgSecretsListKey, buildSecretsList(declaredSecrets))
        ..on(stgFunctionsListKey, buildFunctionsList(const <String>[]))
        ..on(
          stgDeployKey,
          buildDeployOutput(
            commonFunctions,
            project: stgProjectId,
            lastLine: 'DEPLOY OK dev functions=7 batches=1',
          ),
        );

      final int code = await harness.run(flavor: Flavor.stg);

      expect(code, wizardExitStopped);
      expect(harness.fake.countCalls(RunMode.stream, stgDeployKey), 1);
      expect(harness.output, contains('  실패 — '));
      expect(harness.output, contains('DEPLOY OK stg functions=<개수>'));
      expect(harness.output, isNot(contains('  ✓ ${FunctionsStep.stepTitle}')));
    });

    test(
      'DEPLOY OK stg … 면 성공 · 실행 키 deploy_functions.sh stg · 모든 명령이 stg 프로젝트',
      () async {
        final harness = _Harness(root, const <String?>['y']);
        harness.fake
          ..on(stgSecretsListKey, buildSecretsList(declaredSecrets))
          ..on(stgFunctionsListKey, buildFunctionsList(const <String>[]))
          ..on(stgFunctionsListKey, buildFunctionsList(const <String>[]))
          ..on(stgFunctionsListKey, buildFunctionsList(commonFunctions))
          ..on(
            stgDeployKey,
            buildDeployOutput(
              commonFunctions,
              flavorName: 'stg',
              project: stgProjectId,
            ),
          );
        for (final id in commonFunctions) {
          harness.fake.on(buildStgIamKey(buildServiceId(id)), publicPolicy);
        }

        final int code = await harness.run(flavor: Flavor.stg);

        expect(code, wizardExitDone);
        expect(harness.fake.countCalls(RunMode.stream, stgDeployKey), 1);
        expect(harness.runner.workingDirectories[stgDeployKey], root);
        expect(harness.output, contains('  \$ $stgDeployKey'));
        expect(harness.output, isNot(contains(deployKey)));
        expect(harness.output, contains('  ✓ ${FunctionsStep.stepTitle} — '));
        for (final FakeCall call in harness.fake.calls) {
          if (!call.key.contains('--project')) continue;
          expect(call.key, contains('--project $stgProjectId'));
        }
      },
    );
  });

  test(
    'T-20-STG-08: stg 문맥 로그인(이메일 · 익명) · rules 단계가 stg config 의 프로젝트 ID 로 요청 · 명령을 만든다',
    () async {
      writeStgConfig();
      const firestoreRules = 'rules_version = "2"; // firestore fixture\n';
      const storageRules = 'rules_version = "2"; // storage fixture\n';
      writeFixture(RulesStep.firestoreRulesPath, firestoreRules);
      writeFixture(RulesStep.storageRulesPath, storageRules);
      const storageRelease =
          '${RulesStep.storageReleasePrefix}/$stgProjectId'
          '${RulesStep.defaultBucketSuffix}';

      /// ruleset 응답(파일 하나)을 만든다.
      RestResponse buildRuleset(String content) => RestResponse(
        200,
        jsonEncode(<String, Object?>{
          'source': <String, Object?>{
            'files': <Object?>[
              <String, Object?>{'name': 'rules', 'content': content},
            ],
          },
        }),
      );

      final harness = _Harness(root, const <String?>['y', 'y']);
      void onRest(RestRequest request, RestResponse response) =>
          harness.rest.on(request.method, request.url.toString(), response);

      const notFound = RestResponse(
        404,
        '{"error":{"code":404,"message":"CONFIGURATION_NOT_FOUND"}}',
      );
      final RestRequest signInGet = SignInStep.buildGetRequest(stgProjectId);
      onRest(signInGet, notFound);
      onRest(signInGet, notFound);
      onRest(
        signInGet,
        const RestResponse(
          200,
          '{"signIn":{"email":{"enabled":true,"passwordRequired":true}}}',
        ),
      );
      onRest(
        signInGet,
        const RestResponse(
          200,
          '{"signIn":{"email":{"enabled":true,"passwordRequired":true},'
          '"anonymous":{"enabled":true}}}',
        ),
      );
      onRest(
        SignInStep.buildPatchRequest(stgProjectId),
        const RestResponse(200, '{}'),
      );
      onRest(
        StorageStep.buildGetRequest(stgProjectId),
        const RestResponse(404, '{}'),
      );
      for (final MapEntry<String, String> release in <String, String>{
        RulesStep.firestoreRelease: 'f1',
        storageRelease: 's1',
      }.entries) {
        final RestRequest get = RulesStep.buildReleaseRequest(
          stgProjectId,
          release.key,
        );
        onRest(get, const RestResponse(404, '{}'));
        onRest(get, const RestResponse(404, '{}'));
        onRest(
          get,
          RestResponse(
            200,
            jsonEncode(<String, Object?>{
              'rulesetName': 'projects/$stgProjectId/rulesets/${release.value}',
            }),
          ),
        );
      }
      onRest(
        RulesStep.buildRulesetRequest(
          stgProjectId,
          'projects/$stgProjectId/rulesets/f1',
        ),
        buildRuleset(firestoreRules),
      );
      onRest(
        RulesStep.buildRulesetRequest(
          stgProjectId,
          'projects/$stgProjectId/rulesets/s1',
        ),
        buildRuleset(storageRules),
      );
      final String signInDeployKey = FakeCommandRunner.buildKey(
        SignInStep.buildDeployCommand(stgProjectId),
      );
      final String rulesDeployKey = FakeCommandRunner.buildKey(
        RulesStep.buildDeployCommand(stgProjectId),
      );
      harness.fake
        ..on(signInDeployKey, _ok)
        ..on(rulesDeployKey, _ok);

      final int code = await harness.runSteps(<Step>[
        _FinishedStep('apis', '필요한 Google Cloud API'),
        _FinishedStep('firestore', '위치 · Firestore'),
        _FinishedStep('storage', 'Storage'),
        SignInStep(),
        RulesStep(),
      ], flavor: Flavor.stg);

      expect(code, wizardExitDone);
      expect(harness.fake.countCalls(RunMode.stream, signInDeployKey), 1);
      expect(harness.fake.countCalls(RunMode.stream, rulesDeployKey), 1);
      expect(
        harness.rest.countRequests(
          'PATCH',
          SignInStep.buildPatchRequest(stgProjectId).url.toString(),
        ),
        1,
      );
      expect(harness.rest.requests, isNotEmpty);
      for (final RestRequest request in harness.rest.requests) {
        expect(request.quotaProject, stgProjectId);
        expect(request.url.toString(), contains(stgProjectId));
        expect(
          request.url.toString(),
          isNot(contains('/projects/$projectId/')),
        );
      }
      for (final FakeCall call in harness.fake.calls) {
        expect(call.key, contains('--project $stgProjectId'));
      }
    },
  );

  /// 함수 목록 파일의 `common` 끝에 [name] 을 더해 쓴다 — 이미 있으면 그대로 두고,
  /// 다른 키는 바꾸지 않는다.
  void writeManifestWithExtraCommon(String name) {
    final manifest =
        jsonDecode(
              File('$root/${FunctionsStep.manifestPath}').readAsStringSync(),
            )!
            as Map<String, Object?>;
    final common = manifest[FunctionsStep.manifestCommonKey]! as List<Object?>;
    writeFixture(
      FunctionsStep.manifestPath,
      jsonEncode(<String, Object?>{
        ...manifest,
        FunctionsStep.manifestCommonKey: <Object?>[
          ...common,
          if (!common.contains(name)) name,
        ],
      }),
    );
  }

  /// 공통 함수 가운데 [background] 를 뺀 것 — 앱이 부르는 함수로 목록에 싣는다.
  List<String> listAppFunctions(String background) =>
      commonFunctions.where((String name) => name != background).toList();

  test('T-19-FN-13: 상세 파서가 트리거 종류 · platform · state · runServiceId 를 '
      '읽고 기존 표는 그 파생이다', () {
    final CommandResult listed = buildFunctionsListOf(<Map<String, Object?>>[
      buildListedFunction('callableActive', state: 'ACTIVE'),
      buildListedFunction('httpsNoState', triggerKey: 'httpsTrigger'),
      buildListedFunction(
        'eventV1',
        platform: 'gcfv1',
        triggerKey: 'eventTrigger',
        trigger: authDeleteTrigger,
        hasRunService: false,
        state: 'ACTIVE',
      ),
      buildListedFunction(
        'eventV2',
        triggerKey: 'eventTrigger',
        trigger: const <String, Object?>{
          'eventType': 'google.cloud.firestore.document.v1.written',
        },
      ),
      buildListedFunction(
        'scheduled',
        triggerKey: 'scheduleTrigger',
        trigger: const <String, Object?>{'schedule': 'every 5 minutes'},
      ),
      buildListedFunction('queued', triggerKey: 'taskQueueTrigger'),
      buildListedFunction(
        'blocking',
        triggerKey: 'blockingTrigger',
        trigger: const <String, Object?>{
          'eventType': 'providers/cloud.auth/eventTypes/user.beforeCreate',
        },
      ),
      buildListedFunction('connector', triggerKey: 'dataConnectGraphqlTrigger'),
      buildListedFunction('noTrigger', triggerKey: ''),
      buildListedFunction(
        'callableV1',
        platform: 'gcfv1',
        hasRunService: false,
        state: 'UNKONWN',
      ),
      <String, Object?>{
        ...buildListedFunction('emptyService'),
        'runServiceId': '',
      },
      <String, Object?>{
        ...buildListedFunction('otherRegion'),
        'region': 'us-central1',
      },
      <String, Object?>{...buildListedFunction('numericId'), 'id': 7},
    ]);

    expect(
      FunctionsStep.parseDeployedFunctionDetails(listed, region),
      <String, DeployedFunction>{
        'callableActive': (
          triggerKind: DeployedTriggerKind.callable,
          platform: 'gcfv2',
          state: 'ACTIVE',
          runServiceId: 'callableactive',
        ),
        'httpsNoState': (
          triggerKind: DeployedTriggerKind.https,
          platform: 'gcfv2',
          state: null,
          runServiceId: 'httpsnostate',
        ),
        'eventV1': (
          triggerKind: DeployedTriggerKind.event,
          platform: 'gcfv1',
          state: 'ACTIVE',
          runServiceId: null,
        ),
        'eventV2': (
          triggerKind: DeployedTriggerKind.event,
          platform: 'gcfv2',
          state: null,
          runServiceId: 'eventv2',
        ),
        'scheduled': (
          triggerKind: DeployedTriggerKind.other,
          platform: 'gcfv2',
          state: null,
          runServiceId: 'scheduled',
        ),
        'queued': (
          triggerKind: DeployedTriggerKind.other,
          platform: 'gcfv2',
          state: null,
          runServiceId: 'queued',
        ),
        'blocking': (
          triggerKind: DeployedTriggerKind.other,
          platform: 'gcfv2',
          state: null,
          runServiceId: 'blocking',
        ),
        'connector': (
          triggerKind: DeployedTriggerKind.other,
          platform: 'gcfv2',
          state: null,
          runServiceId: 'connector',
        ),
        'noTrigger': (
          triggerKind: DeployedTriggerKind.other,
          platform: 'gcfv2',
          state: null,
          runServiceId: 'notrigger',
        ),
        'callableV1': (
          triggerKind: DeployedTriggerKind.callable,
          platform: 'gcfv1',
          state: 'UNKONWN',
          runServiceId: null,
        ),
        'emptyService': (
          triggerKind: DeployedTriggerKind.callable,
          platform: 'gcfv2',
          state: null,
          runServiceId: '',
        ),
      },
    );
    expect(
      FunctionsStep.parseDeployedFunctions(listed, region),
      <String, String?>{
        'callableActive': 'callableactive',
        'httpsNoState': 'httpsnostate',
        'eventV1': null,
        'eventV2': 'eventv2',
        'scheduled': 'scheduled',
        'queued': 'queued',
        'blocking': 'blocking',
        'connector': 'connector',
        'noTrigger': 'notrigger',
        'callableV1': null,
        'emptyService': '',
      },
    );
    for (final broken in const <CommandResult>[
      CommandResult(1, '', 'ERROR'),
      CommandResult(0, 'not json', ''),
      CommandResult(0, '{"status":"success","result":{}}', ''),
    ]) {
      expect(
        FunctionsStep.parseDeployedFunctionDetails(broken, region),
        isNull,
        reason: broken.stdout,
      );
      expect(
        FunctionsStep.parseDeployedFunctions(broken, region),
        isNull,
        reason: broken.stdout,
      );
    }
    expect(
      DeployedTriggerKind.values.where(
        (DeployedTriggerKind kind) => kind.isCalledByApp,
      ),
      <DeployedTriggerKind>[
        DeployedTriggerKind.callable,
        DeployedTriggerKind.https,
      ],
    );
  });

  /// 1세대 Auth 삭제 트리거 함수 `onUserDeleted` 의 목록 항목.
  Map<String, Object?> buildUserDeletedFunction(String state) =>
      buildListedFunction(
        'onUserDeleted',
        platform: 'gcfv1',
        triggerKey: 'eventTrigger',
        trigger: authDeleteTrigger,
        hasRunService: false,
        state: state,
      );

  test('T-19-FN-14: common 에 1세대 이벤트 트리거를 더한 저장소에서 ✓ · 그 함수 IAM '
      '0 · 바인딩 0', () async {
    writeModulesMarker();
    writeManifestWithExtraCommon('onUserDeleted');
    final List<String> appFunctions = listAppFunctions('onUserDeleted');
    final harness = _Harness(root, const <String?>[]);
    harness.fake
      ..on(secretsListKey, buildSecretsList(declaredSecrets))
      ..on(
        functionsListKey,
        buildFunctionsListOf(<Map<String, Object?>>[
          ...appFunctions.map(buildListedFunction),
          buildUserDeletedFunction('ACTIVE'),
        ]),
      );
    registerPublicPolicies(harness.fake, appFunctions);

    final int code = await harness.run();

    expect(code, wizardExitDone, reason: harness.output);
    expect(harness.output, contains('  ✓ ${FunctionsStep.stepTitle} — '));
    expect(
      harness.output,
      contains('앱이 부르는 함수 ${appFunctions.length}개 · 백그라운드 함수 1개는 배포만 확인'),
    );
    expect(
      harness.fake.calls.where(
        (FakeCall call) => call.key.contains('onuserdeleted'),
      ),
      isEmpty,
    );
    expect(countBindings(harness.fake), 0);
    expect(harness.fake.countMode(RunMode.stream), 0);
  });

  test('T-19-FN-15: 2세대 이벤트 트리거는 Cloud Run 서비스가 있어도 IAM 읽기 0 · '
      '바인딩 0', () async {
    writeModulesMarker();
    writeManifestWithExtraCommon('onProfileWritten');
    final List<String> appFunctions = listAppFunctions('onProfileWritten');
    final harness = _Harness(root, const <String?>[]);
    harness.fake
      ..on(secretsListKey, buildSecretsList(declaredSecrets))
      ..on(
        functionsListKey,
        buildFunctionsListOf(<Map<String, Object?>>[
          ...appFunctions.map(buildListedFunction),
          buildListedFunction(
            'onProfileWritten',
            triggerKey: 'eventTrigger',
            trigger: const <String, Object?>{
              'eventType': 'google.cloud.firestore.document.v1.written',
            },
          ),
        ]),
      );
    registerPublicPolicies(harness.fake, appFunctions);

    final int code = await harness.run();

    expect(code, wizardExitDone, reason: harness.output);
    expect(
      harness.fake.countCalls(
        RunMode.capture,
        buildIamKey(buildServiceId('onProfileWritten')),
      ),
      0,
    );
    expect(countBindings(harness.fake), 0);
  });

  test('T-19-FN-16: 목록에 있어도 상태가 ACTIVE 가 아니면(1세대 UNKONWN) 다시 '
      '배포한다', () async {
    writeModulesMarker();
    writeManifestWithExtraCommon('onUserDeleted');
    final List<String> appFunctions = listAppFunctions('onUserDeleted');

    /// 공통 함수와 상태가 [state] 인 `onUserDeleted` 의 목록.
    CommandResult buildListWith(String state) =>
        buildFunctionsListOf(<Map<String, Object?>>[
          ...appFunctions.map(buildListedFunction),
          buildUserDeletedFunction(state),
        ]);

    final harness = _Harness(root, const <String?>['y']);
    harness.fake
      ..on(secretsListKey, buildSecretsList(declaredSecrets))
      ..on(functionsListKey, buildListWith('UNKONWN'))
      ..on(functionsListKey, buildListWith('UNKONWN'))
      ..on(functionsListKey, buildListWith('ACTIVE'))
      ..on(
        deployKey,
        buildDeployOutput(<String>[...appFunctions, 'onUserDeleted']),
      );
    registerPublicPolicies(harness.fake, appFunctions);

    final int code = await harness.run();

    expect(code, wizardExitDone, reason: harness.output);
    expect(
      readChecklistReason(harness.output),
      contains('onUserDeleted(상태 UNKONWN)'),
    );
    expect(harness.fake.countCalls(RunMode.stream, deployKey), 1);
  });

  test('T-19-FN-17: 빌드 실패 뒤 다시 시도는 상태 UNKNOWN · 서비스 없는 목록을 다시 '
      '배포해 ✓ 로 끝난다', () async {
    writeModulesMarker();
    final harness = _Harness(root, const <String?>['y', '1']);
    harness.fake
      ..on(secretsListKey, buildSecretsList(declaredSecrets))
      ..on(functionsListKey, buildFunctionsList(const <String>[]))
      ..on(functionsListKey, buildFunctionsList(const <String>[]))
      ..on(
        functionsListKey,
        buildFunctionsListOf(
          commonFunctions.map(
            (String id) =>
                buildListedFunction(id, hasRunService: false, state: 'UNKNOWN'),
          ),
        ),
      )
      ..on(functionsListKey, buildFunctionsList(commonFunctions))
      ..on(
        deployKey,
        buildDeployOutput(
          commonFunctions,
          exitCode: 1,
          lastLine: 'Error: There was an error deploying functions',
          stderr: '$batchFailLine\n',
        ),
      )
      ..on(deployKey, buildDeployOutput(commonFunctions));
    registerPublicPolicies(harness.fake, commonFunctions);

    final int code = await harness.run();

    expect(code, wizardExitDone, reason: harness.output);
    expect(harness.fake.countCalls(RunMode.stream, deployKey), 2);
    expect(harness.output, contains('  ✓ ${FunctionsStep.stepTitle} — '));
    expect(
      harness.output,
      isNot(
        contains(
          FunctionsStep.buildNoRunServiceReason(commonFunctions.first, 'gcfv2'),
        ),
      ),
    );
  });

  /// 공통 함수 첫째만 [first] 항목으로 바꾼 목록.
  CommandResult buildListWithFirst(Map<String, Object?> first) =>
      buildFunctionsListOf(<Map<String, Object?>>[
        first,
        ...commonFunctions.skip(1).map(buildListedFunction),
      ]);

  test('T-19-FN-18: 앱이 부르는 2세대 함수에 Cloud Run 서비스가 없으면 다시 배포한다', () async {
    writeModulesMarker();
    final String first = commonFunctions.first;
    final CommandResult missing = buildListWithFirst(
      buildListedFunction(first, hasRunService: false, state: 'ACTIVE'),
    );
    final harness = _Harness(root, const <String?>['y']);
    harness.fake
      ..on(secretsListKey, buildSecretsList(declaredSecrets))
      ..on(functionsListKey, missing)
      ..on(functionsListKey, missing)
      ..on(functionsListKey, buildFunctionsList(commonFunctions))
      ..on(deployKey, buildDeployOutput(commonFunctions));
    registerPublicPolicies(harness.fake, commonFunctions);

    final int code = await harness.run();

    expect(code, wizardExitDone, reason: harness.output);
    expect(
      readChecklistReason(harness.output),
      contains('$first(Cloud Run 서비스 없음)'),
    );
    expect(harness.fake.countCalls(RunMode.stream, deployKey), 1);
  });

  test('T-19-FN-19: 앱이 부르는 함수가 2세대가 아니라 서비스가 없으면 확인할 수 없음 '
      '· 배포 0 · IAM 0', () async {
    writeModulesMarker();
    final String first = commonFunctions.first;
    final harness = _Harness(root, const <String?>['y', '2']);
    harness.fake
      ..on(secretsListKey, buildSecretsList(declaredSecrets))
      ..on(
        functionsListKey,
        buildListWithFirst(
          buildListedFunction(
            first,
            platform: 'gcfv1',
            hasRunService: false,
            state: 'ACTIVE',
          ),
        ),
      );
    registerPublicPolicies(harness.fake, commonFunctions);

    final int code = await harness.run();

    expect(code, wizardExitStopped);
    expect(
      readChecklistReason(harness.output),
      FunctionsStep.buildNoRunServiceReason(first, 'gcfv1'),
    );
    expect(harness.fake.countCalls(RunMode.stream, deployKey), 0);
    expect(
      harness.fake.countCalls(
        RunMode.capture,
        buildIamKey(buildServiceId(first)),
      ),
      0,
    );
  });

  test('T-19-FN-20: httpsTrigger 함수도 앱이 부르는 함수라 공개 호출을 붙인다', () async {
    writeModulesMarker();
    final String first = commonFunctions.first;
    final String service = buildServiceId(first);
    final harness = _Harness(root, const <String?>['y']);
    harness.fake
      ..on(secretsListKey, buildSecretsList(declaredSecrets))
      ..on(
        functionsListKey,
        buildListWithFirst(
          buildListedFunction(first, triggerKey: 'httpsTrigger'),
        ),
      )
      ..on(buildIamKey(service), privatePolicy)
      ..on(buildIamKey(service), privatePolicy)
      ..on(buildIamKey(service), publicPolicy)
      ..on(buildBindKey(service), _ok);
    registerPublicPolicies(harness.fake, commonFunctions.skip(1).toList());

    final int code = await harness.run();

    expect(code, wizardExitDone, reason: harness.output);
    expect(harness.fake.countCalls(RunMode.stream, buildBindKey(service)), 1);
  });

  /// 빌드 계정 fixture 의 빌드 실패 줄(셋째 줄).
  String readBuildAccountErrorLine() =>
      File(buildAccountFixturePath).readAsLinesSync()[2];

  /// 위저드가 프로젝트 역할 · 조직 정책 · API 를 바꾸는 명령을 실행한 호출.
  Iterable<FakeCall> findProjectPolicyCalls(FakeCommandRunner fake) =>
      fake.calls.where(
        (FakeCall call) =>
            call.key.startsWith('gcloud projects ') ||
            call.key.startsWith('gcloud org-policies ') ||
            call.key.startsWith('gcloud services '),
      );

  test('T-19-FN-21: 배포 출력에 빌드 계정 역할 없음이 있으면 정리 정책 재시도 없이 '
      '원인과 역할 명령을 보이고, 위저드는 역할 · 정책을 바꾸지 않는다', () async {
    writeModulesMarker();
    final harness = _Harness(root, const <String?>['y', '2']);
    harness.fake
      ..on(secretsListKey, buildSecretsList(declaredSecrets))
      ..on(functionsListKey, buildFunctionsList(const <String>[]))
      ..on(deployKey, buildFixtureDeployResult(buildAccountFixturePath));

    final int code = await harness.run();

    expect(code, wizardExitStopped);
    final String output = harness.output;
    final String summary = FunctionsStep.buildComputeAccountFailureSummary(
      projectId,
    );
    final String errorLine = readBuildAccountErrorLine();
    expect(output, contains(summary));
    expect(output.indexOf(summary), greaterThan(output.lastIndexOf(errorLine)));
    expect(
      output.indexOf(summary),
      greaterThan(output.lastIndexOf(batchFailLine)),
    );
    expect(countText(output, errorLine), 1);
    for (final String role in FunctionsStep.computeAccountRoles) {
      expect(countText(output, role), greaterThanOrEqualTo(1), reason: role);
    }
    expect(harness.fake.countCalls(RunMode.stream, cleanupKey), 0);
    expect(output, isNot(contains(FunctionsStep.cleanupPolicyNotice)));
    expect(harness.fake.countCalls(RunMode.stream, deployKey), 1);
    expect(findProjectPolicyCalls(harness.fake), isEmpty);
    expect(output, isNot(contains(FunctionsStep.orgPolicyGuidance)));
  });

  test('T-19-FN-22: 정리 정책 재시도 뒤 둘째 배포가 빌드 계정 역할 없음이면 그 '
      '안내로 멈춘다', () async {
    writeModulesMarker();
    final harness = _Harness(root, const <String?>['y', '2']);
    harness.fake
      ..on(secretsListKey, buildSecretsList(declaredSecrets))
      ..on(functionsListKey, buildFunctionsList(const <String>[]))
      ..on(
        deployKey,
        buildDeployOutput(
          commonFunctions,
          exitCode: 1,
          lastLine: cleanupPolicyErrorLine,
          stderr: '$batchFailLine\n',
        ),
      )
      ..on(
        deployKey,
        buildDeployOutput(
          commonFunctions,
          exitCode: 1,
          lastLine: readBuildAccountErrorLine(),
          stderr: '$batchFailLine\n',
        ),
      )
      ..on(cleanupKey, _ok);

    final int code = await harness.run();

    expect(code, wizardExitStopped);
    final List<String> streamed = harness.fake.calls
        .where((FakeCall call) => call.mode == RunMode.stream)
        .map((FakeCall call) => call.key)
        .toList();
    expect(streamed, <String>[deployKey, cleanupKey, deployKey]);
    expect(
      harness.output,
      contains(FunctionsStep.buildComputeAccountFailureSummary(projectId)),
    );
  });

  test('T-19-FN-23: 공개 호출 차단과 빌드 계정 역할 없음이 함께 나오면 공개 호출 '
      '차단 안내가 먼저다', () async {
    writeModulesMarker();
    final harness = _Harness(root, const <String?>['y', '2']);
    harness.fake
      ..on(secretsListKey, buildSecretsList(declaredSecrets))
      ..on(functionsListKey, buildFunctionsList(const <String>[]))
      ..on(
        deployKey,
        buildDeployOutput(
          commonFunctions,
          exitCode: 1,
          lastLine:
              '${readBuildAccountErrorLine()}\n'
              'Unable to set the invoker for the IAM policy on the following '
              'functions:\n\tping($region)',
          stderr: '$batchFailLine\n',
        ),
      );

    final int code = await harness.run();

    expect(code, wizardExitStopped);
    expect(
      harness.output,
      contains(FunctionsStep.buildOrgPolicyFailureSummary(projectId)),
    );
    expect(
      harness.output,
      isNot(contains(FunctionsStep.computeAccountGuidance)),
    );
    expect(harness.fake.countCalls(RunMode.stream, cleanupKey), 0);
  });

  test('T-19-FN-24: 빌드 계정 fixture 에 이메일 · 실제 프로젝트 ID · 번호 모양 '
      '문자열이 없다', () {
    final String fixture = File(buildAccountFixturePath).readAsStringSync();

    expect(
      RegExp(
        r'[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}',
      ).hasMatch(fixture),
      isFalse,
    );
    expect(fixture, isNot(contains('slimpumpkin')));
    expect(
      <String>{
        for (final RegExpMatch match in RegExp(
          r'--project (\S+)',
        ).allMatches(fixture))
          match.group(1)!,
      },
      <String>{projectId},
    );
    expect(
      <String>{
        for (final RegExpMatch match in RegExp(
          'project=([0-9]+)',
        ).allMatches(fixture))
          match.group(1)!,
      },
      <String>{'000000000000'},
    );
    expect(
      countText(fixture, 'missing permission on the build service account'),
      1,
    );
    expect(countText(fixture, 'could not set up cleanup policy'), 1);
    expect(countText(fixture, '\tping($region)'), 1);
  });

  test('T-19-FN-25: 조직 정책 안내 뒤에 관리자 예외 명령 · 문서 주소가 순서대로 '
      '나오고, 위저드는 실행하지 않는다', () async {
    final String summary = FunctionsStep.buildOrgPolicyFailureSummary(
      projectId,
    );
    final List<String> commands = FunctionsStep.buildOrgPolicyExceptionCommands(
      projectId,
    );

    /// [output] 에 요약 전체가 있고 조각이 순서대로 나오는지 단언한다.
    void expectOrderedSummary(String output, String label) {
      expect(output, contains(summary), reason: label);
      var previous = output.indexOf(FunctionsStep.orgPolicyGuidance);
      expect(previous, greaterThanOrEqualTo(0), reason: label);
      for (final piece in <String>[
        FunctionsStep.orgPolicyAdminLead,
        ...commands,
        FunctionsStep.orgPolicyDocUrl,
      ]) {
        final int index = output.indexOf(piece, previous);
        expect(index, greaterThan(previous), reason: '$label · $piece');
        previous = index;
      }
    }

    // (a) 배포 출력의 공개 호출 차단.
    writeModulesMarker();
    final deployed = _Harness(root, const <String?>['y', '2']);
    deployed.fake
      ..on(secretsListKey, buildSecretsList(declaredSecrets))
      ..on(functionsListKey, buildFunctionsList(const <String>[]))
      ..on(deployKey, buildFixtureDeployResult());
    expect(await deployed.run(), wizardExitStopped);
    expectOrderedSummary(deployed.output, 'deploy');
    expect(findProjectPolicyCalls(deployed.fake), isEmpty);

    // (b) 공개 호출 추가의 permitted customer 거절.
    final String rejected = buildServiceId(commonFunctions.first);
    final bound = _Harness(root, const <String?>['y', '2']);
    bound.fake
      ..on(secretsListKey, buildSecretsList(declaredSecrets))
      ..on(functionsListKey, buildFunctionsList(commonFunctions))
      ..on(
        buildBindKey(rejected),
        const CommandResult(1, '', '$permittedCustomerErrorLine\n'),
      );
    for (final id in commonFunctions) {
      final String service = buildServiceId(id);
      bound.fake.on(
        buildIamKey(service),
        service == rejected ? emptyPolicy : publicPolicy,
      );
    }
    expect(await bound.run(), wizardExitStopped);
    expectOrderedSummary(bound.output, 'bind');
    expect(findProjectPolicyCalls(bound.fake), isEmpty);

    // (c) 명령 꼴.
    expect(
      commands[2],
      'gcloud org-policies set-policy allowed-policy-member-domains.yaml',
    );
    expect(
      commands[1],
      contains('projects/$projectId/policies/iam.allowedPolicyMemberDomains'),
    );
    expect(commands[1], contains('allowAll: true'));

    // (d) 규칙에 맞지 않는 프로젝트 ID 는 명령에 넣지 않는다.
    const unsafeId = 'bad id; rm -rf ~';
    for (final text in <String>[
      FunctionsStep.buildOrgPolicyFailureSummary(unsafeId),
      FunctionsStep.buildComputeAccountFailureSummary(unsafeId),
    ]) {
      expect(text, contains('<your-project-id>'));
      expect(text, isNot(contains('rm -rf')));
    }
  });
}
