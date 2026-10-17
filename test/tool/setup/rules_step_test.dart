import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

import '../../../tool/setup/command_runner.dart';
import '../../../tool/setup/config_files.dart';
import '../../../tool/setup/rest_client.dart';
import '../../../tool/setup/step.dart';
import '../../../tool/setup/steps/dev_steps.dart';
import '../../../tool/setup/steps/rules_step.dart';
import '../../../tool/setup/steps/user_files_step.dart';
import '../../../tool/setup/wizard.dart';
import 'fake_rest_client.dart';
import 'fakes.dart';

/// 테스트 프로젝트 ID.
const String projectId = 'p';

/// 기본 bucket 응답의 bucket 이름.
const String bucketName = 'p-default-bucket';

/// 기본 bucket 관리 API 주소.
const String bucketUrl =
    'https://firebasestorage.googleapis.com/v1alpha/projects/$projectId/defaultBucket';

/// Firestore 릴리스 주소.
const String firestoreReleaseUrl =
    'https://firebaserules.googleapis.com/v1/projects/$projectId/releases/cloud.firestore';

/// 기본 bucket 의 Storage 릴리스 주소.
const String storageReleaseUrl =
    'https://firebaserules.googleapis.com/v1/projects/$projectId/releases/firebase.storage/$bucketName';

/// Firestore ruleset 이름 · 주소.
const String firestoreRuleset = 'projects/$projectId/rulesets/fs-1';
const String firestoreRulesetUrl =
    'https://firebaserules.googleapis.com/v1/$firestoreRuleset';

/// Storage ruleset 이름 · 주소.
const String storageRuleset = 'projects/$projectId/rulesets/st-1';
const String storageRulesetUrl =
    'https://firebaserules.googleapis.com/v1/$storageRuleset';

/// 배포 명령 키.
const String deployKey =
    'firebase deploy --only firestore:rules,firestore:indexes,storage '
    '--project $projectId --non-interactive';

/// 릴리스가 없을 때의 응답.
const RestResponse notFound = RestResponse(
  404,
  '{"error":{"code":404,"status":"NOT_FOUND"}}',
);

/// 이미 끝난 앞 단계 — rules 단계의 의존 단계를 대신한다.
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

/// 릴리스 GET 응답을 만든다.
RestResponse buildRelease(String releaseName, String rulesetName) =>
    RestResponse(
      200,
      jsonEncode(<String, Object?>{
        'name': 'projects/$projectId/releases/$releaseName',
        'rulesetName': rulesetName,
      }),
    );

/// ruleset GET 응답을 만든다.
RestResponse buildRuleset(String fileName, String content) => RestResponse(
  200,
  jsonEncode(<String, Object?>{
    'name': 'projects/$projectId/rulesets/x',
    'source': <String, Object?>{
      'files': <Object?>[
        <String, Object?>{
          'name': fileName,
          'content': content,
          'fingerprint': 'AAAA',
        },
      ],
    },
  }),
);

/// 기본 bucket GET 응답(이름 있음).
RestResponse buildBucket() => RestResponse(
  200,
  jsonEncode(<String, Object?>{
    'name': 'projects/$projectId/defaultBucket',
    'location': 'us-central1',
    'bucket': <String, Object?>{
      'name': 'projects/$projectId/buckets/$bucketName',
    },
  }),
);

void main() {
  late Directory tempDir;
  late String root;
  late String firestoreRules;
  late String storageRules;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('rules_step_test_');
    root = tempDir.path;
    final config = File('$root/${UserFilesStep.jsonUserPath}')
      ..parent.createSync(recursive: true);
    File(UserFilesStep.jsonExamplePath).copySync(config.path);
    replaceJsonString(config.path, 'firebaseProjectId', projectId);
    firestoreRules = File(
      'firestore.rules',
    ).copySync('$root/firestore.rules').readAsStringSync();
    storageRules = File(
      'storage.rules',
    ).copySync('$root/storage.rules').readAsStringSync();
  });

  tearDown(() {
    tempDir.deleteSync(recursive: true);
  });

  /// 두 릴리스 · ruleset 이 저장소 파일과 같은 응답을 등록한 가짜 REST.
  FakeRestClient buildMatchingRest() => FakeRestClient()
    ..on('GET', bucketUrl, buildBucket())
    ..on(
      'GET',
      firestoreReleaseUrl,
      buildRelease('cloud.firestore', firestoreRuleset),
    )
    ..on(
      'GET',
      firestoreRulesetUrl,
      buildRuleset('firestore.rules', firestoreRules),
    )
    ..on(
      'GET',
      storageReleaseUrl,
      buildRelease('firebase.storage/$bucketName', storageRuleset),
    )
    ..on('GET', storageRulesetUrl, buildRuleset('storage.rules', storageRules));

  /// 앞 단계(끝남) · rules 단계로 위저드를 돌린다.
  Future<int> runRulesStep(
    FakeCommandRunner runner,
    FakeRestClient rest,
    ScriptedTerminal terminal,
  ) => runWizard(
    buildTestContext(
      projectRoot: root,
      runner: runner,
      terminal: terminal,
      rest: rest,
    ),
    <Step>[
      _FinishedStep('firestore', '위치 · Firestore'),
      _FinishedStep('storage', '기본 Storage bucket'),
      RulesStep(),
    ],
  );

  /// 점검표의 rules 단계 사유를 꺼낸다.
  String readChecklistReason(String output) {
    const prefix = '  ✗ ${RulesStep.stepTitle} — ';
    return output
        .split('\n')
        .firstWhere((String line) => line.startsWith(prefix))
        .substring(prefix.length);
  }

  test('T-19-RULES-01 두 릴리스의 ruleset 원문이 저장소 파일과 같으면 ✓ · 배포 0', () async {
    final FakeRestClient rest = buildMatchingRest();
    final runner = FakeCommandRunner();
    final terminal = ScriptedTerminal(const <String?>[]);

    final int code = await runRulesStep(runner, rest, terminal);

    expect(code, wizardExitDone);
    expect(
      terminal.output.toString(),
      contains('  ✓ ${RulesStep.stepTitle} — '),
    );
    expect(terminal.asks, isEmpty);
    expect(runner.countMode(RunMode.stream), 0);
    expect(rest.countRequests('GET', storageReleaseUrl), 1);
    expect(
      rest.requests.every(
        (RestRequest request) => request.quotaProject == projectId,
      ),
      isTrue,
    );
  });

  test(
    'T-19-RULES-02 Firestore 릴리스가 404 면 ✗ 「배포되지 않았습니다」 · y 뒤 배포 1회 · 재검사 ✓',
    () async {
      // 점검표 · 단계 시작 검사는 404, 배포 뒤 재검사는 릴리스가 있다.
      final rest = FakeRestClient()
        ..on('GET', firestoreReleaseUrl, notFound)
        ..on('GET', firestoreReleaseUrl, notFound)
        ..on(
          'GET',
          firestoreReleaseUrl,
          buildRelease('cloud.firestore', firestoreRuleset),
        )
        ..on('GET', bucketUrl, buildBucket())
        ..on(
          'GET',
          firestoreRulesetUrl,
          buildRuleset('firestore.rules', firestoreRules),
        )
        ..on(
          'GET',
          storageReleaseUrl,
          buildRelease('firebase.storage/$bucketName', storageRuleset),
        )
        ..on(
          'GET',
          storageRulesetUrl,
          buildRuleset('storage.rules', storageRules),
        );
      final runner = FakeCommandRunner()
        ..on(deployKey, const CommandResult(0, '+  Deploy complete!\n', ''));
      final terminal = ScriptedTerminal(const <String?>['y']);

      final int code = await runRulesStep(runner, rest, terminal);

      final output = terminal.output.toString();
      expect(code, wizardExitDone);
      expect(readChecklistReason(output), contains('배포되지 않았습니다'));
      expect(output, contains('\$ $deployKey'));
      expect(runner.countCalls(RunMode.stream, deployKey), 1);
      expect(output, contains('  ✓ ${RulesStep.stepTitle} — '));
    },
  );

  test('T-19-RULES-03 Storage ruleset 원문이 다르면 ✗ 「저장소 파일과 다릅니다」', () async {
    final rest = FakeRestClient()
      ..on('GET', bucketUrl, buildBucket())
      ..on(
        'GET',
        firestoreReleaseUrl,
        buildRelease('cloud.firestore', firestoreRuleset),
      )
      ..on(
        'GET',
        firestoreRulesetUrl,
        buildRuleset('firestore.rules', firestoreRules),
      )
      ..on(
        'GET',
        storageReleaseUrl,
        buildRelease('firebase.storage/$bucketName', storageRuleset),
      )
      ..on(
        'GET',
        storageRulesetUrl,
        buildRuleset(
          'storage.rules',
          "rules_version = '2';\nservice firebase.storage {}\n",
        ),
      );
    final runner = FakeCommandRunner();
    final terminal = ScriptedTerminal(const <String?>[]);

    final int code = await runRulesStep(runner, rest, terminal);

    final String reason = readChecklistReason(terminal.output.toString());
    expect(code, wizardExitStopped);
    expect(reason, contains('Storage'));
    expect(reason, contains('저장소 파일과 다릅니다'));
    expect(reason, isNot(contains('Firestore')));
    expect(runner.countMode(RunMode.stream), 0);
  });

  test('T-19-RULES-04 양쪽 끝 개행 · 공백 차이만 있으면 같은 것으로 본다', () async {
    final rest = FakeRestClient()
      ..on('GET', bucketUrl, buildBucket())
      ..on(
        'GET',
        firestoreReleaseUrl,
        buildRelease('cloud.firestore', firestoreRuleset),
      )
      ..on(
        'GET',
        firestoreRulesetUrl,
        buildRuleset('firestore.rules', firestoreRules.trimRight()),
      )
      ..on(
        'GET',
        storageReleaseUrl,
        buildRelease('firebase.storage/$bucketName', storageRuleset),
      )
      ..on(
        'GET',
        storageRulesetUrl,
        buildRuleset('storage.rules', '\n$storageRules\n\n  '),
      );
    expect(firestoreRules.endsWith('\n'), isTrue);
    final runner = FakeCommandRunner();
    final terminal = ScriptedTerminal(const <String?>[]);

    final int code = await runRulesStep(runner, rest, terminal);

    expect(code, wizardExitDone);
    expect(
      terminal.output.toString(),
      contains('  ✓ ${RulesStep.stepTitle} — '),
    );
  });

  test('T-19-RULES-05 배포가 exit 1 이면 실패 · 원문을 그대로 보인다', () async {
    const deployError =
        'Error: Request to https://firebaserules.googleapis.com had HTTP Error: 403\n';
    final rest = FakeRestClient()
      ..on('GET', bucketUrl, buildBucket())
      ..on('GET', firestoreReleaseUrl, notFound)
      ..on(
        'GET',
        storageReleaseUrl,
        buildRelease('firebase.storage/$bucketName', storageRuleset),
      )
      ..on(
        'GET',
        storageRulesetUrl,
        buildRuleset('storage.rules', storageRules),
      );
    final runner = FakeCommandRunner()
      ..on(deployKey, const CommandResult(1, '', deployError));
    final terminal = ScriptedTerminal(const <String?>['y']);

    final int code = await runRulesStep(runner, rest, terminal);

    final output = terminal.output.toString();
    expect(code, wizardExitStopped);
    expect(output, contains('  실패 — '));
    expect(output, contains(deployError));
    expect(runner.countCalls(RunMode.stream, deployKey), 1);
  });

  test(
    'T-19-RULES-06 bucket 응답에 이름이 없으면 <p>.firebasestorage.app 릴리스를 찾는다',
    () async {
      const fallbackReleaseUrl =
          'https://firebaserules.googleapis.com/v1/projects/$projectId/releases/firebase.storage/$projectId.firebasestorage.app';
      final rest = FakeRestClient()
        ..on(
          'GET',
          bucketUrl,
          const RestResponse(200, '{"name":"projects/p/defaultBucket"}'),
        )
        ..on(
          'GET',
          firestoreReleaseUrl,
          buildRelease('cloud.firestore', firestoreRuleset),
        )
        ..on(
          'GET',
          firestoreRulesetUrl,
          buildRuleset('firestore.rules', firestoreRules),
        )
        ..on(
          'GET',
          fallbackReleaseUrl,
          buildRelease(
            'firebase.storage/$projectId.firebasestorage.app',
            storageRuleset,
          ),
        )
        ..on(
          'GET',
          storageRulesetUrl,
          buildRuleset('storage.rules', storageRules),
        );
      final runner = FakeCommandRunner();
      final terminal = ScriptedTerminal(const <String?>[]);

      final int code = await runRulesStep(runner, rest, terminal);

      expect(code, wizardExitDone);
      expect(rest.countRequests('GET', fallbackReleaseUrl), 1);
      expect(rest.countRequests('GET', storageReleaseUrl), 0);
    },
  );

  test('buildDevSteps 는 앱 등록 다음에 rules 단계를 둔다', () {
    final List<String> ids = buildDevSteps()
        .map((Step step) => step.id)
        .toList();

    expect(ids.indexOf('rules'), ids.indexOf('configure') + 1);
  });
}
