import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

import '../../../tool/setup/command_runner.dart';
import '../../../tool/setup/config_files.dart';
import '../../../tool/setup/confirm.dart';
import '../../../tool/setup/redactor.dart';
import '../../../tool/setup/rest_client.dart';
import '../../../tool/setup/step.dart';
import '../../../tool/setup/steps/dev_steps.dart';
import '../../../tool/setup/steps/storage_step.dart';
import '../../../tool/setup/steps/user_files_step.dart';
import '../../../tool/setup/wizard.dart';
import 'fake_rest_client.dart';
import 'fakes.dart';

/// 테스트 프로젝트 ID.
const String projectId = 'p';

/// 기본 bucket 주소.
const String bucketUrl =
    'https://firebasestorage.googleapis.com/v1alpha/projects/$projectId/defaultBucket';

/// Firestore 위치를 읽는 가짜 실행기 키.
const String describeKey =
    'gcloud firestore databases describe --database=(default) '
    '--project $projectId --format=value(locationId)';

/// 기본 bucket 이 있을 때의 응답.
final RestResponse bucketFound = RestResponse(
  200,
  jsonEncode(<String, Object?>{
    'name': 'projects/$projectId/defaultBucket',
    'location': 'asia-northeast3',
    'bucket': <String, Object?>{
      'name': 'projects/$projectId/buckets/$projectId.firebasestorage.app',
    },
    'storageClass': 'STANDARD',
  }),
);

/// 기본 bucket 이 없을 때의 응답.
const RestResponse bucketMissing = RestResponse(
  404,
  '{"error":{"code":404,"message":"Not found","status":"NOT_FOUND"}}',
);

/// describe 가 [location] 을 내는 결과.
CommandResult buildLocation(String location) =>
    CommandResult(0, '$location\n', '');

/// 이미 끝난 앞 단계 — 기본 bucket 단계의 의존 단계를 대신한다.
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

/// [text] 안에 [pattern] 이 몇 번 나오는지 센다.
int countOccurrences(String text, String pattern) =>
    pattern.allMatches(text).length;

void main() {
  late Directory tempDir;
  late String root;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('storage_step_test_');
    root = tempDir.path;
    final File config = File('$root/${UserFilesStep.jsonUserPath}')
      ..parent.createSync(recursive: true);
    File(UserFilesStep.jsonExamplePath).copySync(config.path);
    replaceJsonString(config.path, 'firebaseProjectId', projectId);
  });

  tearDown(() {
    tempDir.deleteSync(recursive: true);
  });

  /// 위치(끝남) · 기본 bucket 단계로 위저드를 돌린다.
  Future<int> runStorageStep(
    FakeCommandRunner runner,
    FakeRestClient rest,
    ScriptedTerminal terminal, {
    Redactor? redactor,
  }) => runWizard(
    buildTestContext(
      projectRoot: root,
      runner: runner,
      rest: rest,
      terminal: terminal,
      redactor: redactor,
    ),
    <Step>[_FinishedStep('firestore', '위치 · Firestore'), StorageStep()],
  );

  /// 없음 → 없음 → 있음 순서로 GET 을, 성공으로 POST 를 등록한 가짜 REST 를 만든다.
  FakeRestClient buildCreatingRest() {
    final FakeRestClient rest = FakeRestClient()
      ..on('POST', bucketUrl, bucketFound);
    registerResponses(rest, 'GET', bucketUrl, <RestResponse>[
      bucketMissing,
      bucketMissing,
      bucketFound,
    ]);
    return rest;
  }

  test('T-19-BUCKET-01 기본 bucket 이 있으면 ✓ · 만들기 요청 0', () async {
    final FakeRestClient rest = FakeRestClient()
      ..on('GET', bucketUrl, bucketFound);
    final FakeCommandRunner runner = FakeCommandRunner();
    final ScriptedTerminal terminal = ScriptedTerminal(const <String?>[]);

    final int code = await runStorageStep(runner, rest, terminal);

    expect(code, wizardExitDone);
    expect(
      terminal.output.toString(),
      contains('  ✓ ${StorageStep.stepTitle} — '),
    );
    expect(terminal.asks, isEmpty);
    expect(rest.countRequests('POST', bucketUrl), 0);
    expect(rest.requests.first.quotaProject, projectId);
  });

  test(
    'T-19-BUCKET-02 없으면 Firestore 와 같은 asia-northeast3 · Always Free 경고 · y 뒤 POST · 재검사 ✓',
    () async {
      final FakeRestClient rest = buildCreatingRest();
      final FakeCommandRunner runner = FakeCommandRunner()
        ..on(describeKey, buildLocation('asia-northeast3'));
      final ScriptedTerminal terminal = ScriptedTerminal(const <String?>[
        'y',
        'y',
      ]);

      final int code = await runStorageStep(runner, rest, terminal);

      final String output = terminal.output.toString();
      expect(code, wizardExitDone);
      expect(output, contains('  ✗ ${StorageStep.stepTitle} — '));
      expect(output, contains('── ${StorageStep.confirmTitle} ──'));
      expect(output, contains('asia-northeast3'));
      expect(output, contains('  ! ${StorageStep.alwaysFreeWarning}'));
      expect(
        StorageStep.alwaysFreeWarning,
        '이 위치의 기본 bucket 은 Always Free 사용량이 없습니다 — '
        '저장 · 다운로드 사용량이 처음부터 청구됩니다.',
      );
      expect(terminal.asks, contains(summaryConfirmQuestion));
      final List<RestRequest> posts = rest.requests
          .where((RestRequest request) => request.method == 'POST')
          .toList();
      expect(posts, hasLength(1));
      expect(posts.single.url.toString(), bucketUrl);
      expect(posts.single.body, '{"location":"asia-northeast3"}');
      expect(posts.single.quotaProject, projectId);
      expect(output, contains('  ✓ ${StorageStep.stepTitle} — '));
    },
  );

  test(
    'T-19-BUCKET-03 Firestore 가 us-central1 이면 Always Free 경고 줄이 없다',
    () async {
      final FakeRestClient rest = buildCreatingRest();
      final FakeCommandRunner runner = FakeCommandRunner()
        ..on(describeKey, buildLocation('us-central1'));
      final ScriptedTerminal terminal = ScriptedTerminal(const <String?>[
        'y',
        'y',
      ]);

      final int code = await runStorageStep(runner, rest, terminal);

      final String output = terminal.output.toString();
      expect(code, wizardExitDone);
      expect(output, contains('── ${StorageStep.confirmTitle} ──'));
      expect(output, isNot(contains(StorageStep.alwaysFreeWarning)));
      expect(output, isNot(contains('Always Free')));
      expect(
        rest.requests
            .where((RestRequest request) => request.method == 'POST')
            .single
            .body,
        '{"location":"us-central1"}',
      );
    },
  );

  test('T-19-BUCKET-04 확인 표에서 N 이면 만들기 요청 0', () async {
    final FakeRestClient rest = FakeRestClient()
      ..on('GET', bucketUrl, bucketMissing);
    final FakeCommandRunner runner = FakeCommandRunner()
      ..on(describeKey, buildLocation('asia-northeast3'));
    final ScriptedTerminal terminal = ScriptedTerminal(const <String?>[
      'y',
      'n',
    ]);

    final int code = await runStorageStep(runner, rest, terminal);

    expect(code, wizardExitStopped);
    expect(terminal.asks, contains(summaryConfirmQuestion));
    expect(rest.countRequests('POST', bucketUrl), 0);
  });

  test('T-19-BUCKET-05 POST 가 400 이면 실패 · 상태 코드와 응답 원문(가림 적용)을 보인다', () async {
    final String fakeToken = <String>['ya29', '.not-a-real', '-token'].join();
    final String errorBody =
        '{"error":{"code":400,"message":"Invalid location ($fakeToken)",'
        '"status":"INVALID_ARGUMENT"}}';
    final FakeRestClient rest = FakeRestClient()
      ..on('GET', bucketUrl, bucketMissing)
      ..on('POST', bucketUrl, RestResponse(400, errorBody));
    final FakeCommandRunner runner = FakeCommandRunner()
      ..on(describeKey, buildLocation('asia-northeast3'));
    final ScriptedTerminal terminal = ScriptedTerminal(const <String?>[
      'y',
      'y',
    ]);

    final int code = await runStorageStep(
      runner,
      rest,
      terminal,
      redactor: Redactor(),
    );

    final String output = terminal.output.toString();
    expect(code, wizardExitStopped);
    expect(output, contains('  실패 — '));
    expect(output, contains('HTTP 400'));
    expect(output, contains('"status":"INVALID_ARGUMENT"'));
    expect(output, contains(Redactor.mask));
    expect(output, isNot(contains(fakeToken)));
    expect(terminal.asks, contains(failureChoiceQuestion));
  });

  test(
    'T-19-BUCKET-06 Firestore 가 다중 리전 nam5 면 config 의 functionsRegion(asia-northeast3)을 위치로 쓴다',
    () async {
      final FakeRestClient rest = buildCreatingRest();
      final FakeCommandRunner runner = FakeCommandRunner()
        ..on(describeKey, buildLocation('nam5'));
      final ScriptedTerminal terminal = ScriptedTerminal(const <String?>[
        'y',
        'y',
      ]);

      final int code = await runStorageStep(runner, rest, terminal);

      final String output = terminal.output.toString();
      expect(code, wizardExitDone);
      expect(output, contains('nam5'));
      expect(
        rest.requests
            .where((RestRequest request) => request.method == 'POST')
            .single
            .body,
        '{"location":"asia-northeast3"}',
      );
    },
  );

  test('T-19-BUCKET-07 화면에 만들기 요청의 curl 표시형이 한 번 보인다', () async {
    final FakeRestClient rest = buildCreatingRest();
    final FakeCommandRunner runner = FakeCommandRunner()
      ..on(describeKey, buildLocation('asia-northeast3'));
    final ScriptedTerminal terminal = ScriptedTerminal(const <String?>[
      'y',
      'y',
    ]);

    await runStorageStep(runner, rest, terminal);

    final String output = terminal.output.toString();
    expect(
      countOccurrences(
        output,
        'curl -s -X POST "https://firebasestorage.googleapis.com/v1alpha/'
        'projects/p/defaultBucket"',
      ),
      1,
    );
    expect(output, contains(accessTokenExpression));
    expect(output, contains('x-goog-user-project: $projectId'));
  });

  group('T-19-BUCKET-08 값 표 재확인 안내는 확인 표를 보이는 모드에서만 붙는다', () {
    test('T-19-BUCKET-08 bucket 만들기 모드는 안내가 붙는다', () async {
      final FakeRestClient rest = FakeRestClient()
        ..on('GET', bucketUrl, bucketMissing);
      final FakeCommandRunner runner = FakeCommandRunner()
        ..on(describeKey, buildLocation('asia-northeast3'));
      final ScriptedTerminal terminal = ScriptedTerminal(const <String?>['n']);

      final int code = await runStorageStep(runner, rest, terminal);

      final String output = terminal.output.toString();
      expect(code, wizardExitStopped);
      expect(output, contains('▶ ${StorageStep.stepTitle}'));
      expect(output.contains('    $costlyStepNotice'), isTrue);
      expect(rest.countRequests('POST', bucketUrl), 0);
    });

    test('T-19-BUCKET-08 요청 실패 전용 모드는 안내가 붙지 않는다', () async {
      const RestResponse failure = RestResponse(500, '{"error":"boom"}');
      final FakeRestClient rest = FakeRestClient()
        ..on('GET', bucketUrl, failure);
      final FakeCommandRunner runner = FakeCommandRunner();
      final ScriptedTerminal terminal = ScriptedTerminal(const <String?>['y']);

      final int code = await runStorageStep(runner, rest, terminal);

      final String output = terminal.output.toString();
      final String reason =
          '기본 bucket 을 확인하지 못했습니다 — ${describeRestStatus(failure)}';
      expect(code, wizardExitStopped);
      // 단계 머리 사유가 제목의 모드를 고정한다 — 안내 없는 다른 모드로
      // 바뀌어도 통과하지 않게 한다.
      expect(output, contains('▶ ${StorageStep.stepTitle}\n  $reason'));
      expect(output.contains('    $costlyStepNotice'), isFalse);
    });
  });

  test('buildDevSteps 는 위치 · Firestore 다음에 기본 bucket 단계를 둔다', () {
    final List<String> ids = buildDevSteps()
        .map((Step step) => step.id)
        .toList();

    expect(ids.indexOf('storage'), ids.indexOf('firestore') + 1);
  });
}
