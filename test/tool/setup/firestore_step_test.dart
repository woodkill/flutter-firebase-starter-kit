import 'dart:io';
import 'dart:math';

import 'package:test/test.dart';

import '../../../tool/setup/command_runner.dart';
import '../../../tool/setup/config_files.dart';
import '../../../tool/setup/confirm.dart';
import '../../../tool/setup/flavor.dart';
import '../../../tool/setup/redactor.dart';
import '../../../tool/setup/step.dart';
import '../../../tool/setup/steps/dev_steps.dart';
import '../../../tool/setup/steps/firestore_step.dart';
import '../../../tool/setup/steps/user_files_step.dart';
import '../../../tool/setup/terminal.dart';
import '../../../tool/setup/wizard.dart';
import 'fake_rest_client.dart';
import 'fakes.dart';

/// 테스트 프로젝트 ID.
const String projectId = 'p';

/// Firestore 위치를 읽는 가짜 실행기 키.
const String describeKey =
    'gcloud firestore databases describe --database=(default) '
    '--project $projectId --format=value(locationId)';

/// 추적 파일 변경을 읽는 가짜 실행기 키.
const String gitStatusKey = 'git status --porcelain --untracked-files=no';

/// 데이터베이스가 없을 때 gcloud 가 내는 오류(모양 — 실제 문구는 다를 수 있다).
const String notFoundError =
    'ERROR: (gcloud.firestore.databases.describe) NOT_FOUND: '
    'Project or database does not exist.\n';

const CommandResult _ok = CommandResult(0, '', '');

/// 앱 설정 최소 fixture — 실제 파일의 기본값 상수 모양만 담는다.
const String appConfigFixture = '''
/// 테스트용 최소 앱 설정.
abstract final class AppConfig {
  static const String functionsRegion = String.fromEnvironment(
    'functionsRegion',
    defaultValue: defaultFunctionsRegion,
  );

  static const String defaultFunctionsRegion = 'asia-northeast3';
}
''';

/// app_config 테스트가 region.ts 를 읽는 정규식과 같은 식.
final RegExp regionTsReadPattern = RegExp(r'''REGION\s*=\s*["']([^"']+)["']''');

/// 앱 설정 fixture 의 기본값을 읽는 식.
final RegExp appConfigReadPattern = RegExp(
  r"defaultFunctionsRegion\s*=\s*'([^']+)'",
);

/// [region] 에 데이터베이스를 만드는 가짜 실행기 키.
String createKey(String region) =>
    'gcloud firestore databases create --location=$region --project $projectId';

/// describe 가 [location] 을 내는 결과.
CommandResult buildLocation(String location) =>
    CommandResult(0, '$location\n', '');

/// describe 가 「없음」 으로 실패한 결과.
const CommandResult notFound = CommandResult(1, '', notFoundError);

/// 이미 끝난 앞 단계 — 위치 단계의 의존 단계를 대신한다.
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

void main() {
  late Directory tempDir;
  late String root;
  late File config;
  late File regionTs;
  late File appConfig;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('firestore_step_test_');
    root = tempDir.path;
    config = File('$root/${UserFilesStep.jsonUserPath}')
      ..parent.createSync(recursive: true);
    File(UserFilesStep.jsonExamplePath).copySync(config.path);
    replaceJsonString(config.path, 'firebaseProjectId', projectId);
    regionTs = File('$root/${FirestoreStep.regionTsPath}')
      ..parent.createSync(recursive: true);
    File(FirestoreStep.regionTsPath).copySync(regionTs.path);
    appConfig = File('$root/${FirestoreStep.appConfigPath}')
      ..parent.createSync(recursive: true)
      ..writeAsStringSync(appConfigFixture);
  });

  tearDown(() {
    tempDir.deleteSync(recursive: true);
  });

  /// API(끝남) · 위치 단계로 위저드를 돌린다.
  Future<int> runFirestoreStep(
    FakeCommandRunner runner,
    ScriptedTerminal terminal,
  ) => runWizard(
    buildTestContext(projectRoot: root, runner: runner, terminal: terminal),
    <Step>[_FinishedStep('apis', '필요한 Google Cloud API'), FirestoreStep()],
  );

  /// 세 파일의 지금 내용을 순서대로 읽는다.
  List<String> readRegionFiles() => <String>[
    config.readAsStringSync(),
    regionTs.readAsStringSync(),
    appConfig.readAsStringSync(),
  ];

  /// 세 파일의 리전 값을 순서대로 읽는다.
  List<String?> readRegionValues() => <String?>[
    readJsonString(config.path, 'functionsRegion'),
    regionTsReadPattern.firstMatch(regionTs.readAsStringSync())?.group(1),
    appConfigReadPattern.firstMatch(appConfig.readAsStringSync())?.group(1),
  ];

  test('T-19-LOC-01 위치가 asia-northeast3 이고 세 리전 값이 같으면 묻지 않고 ✓', () async {
    final runner = FakeCommandRunner()
      ..on(describeKey, buildLocation('asia-northeast3'));
    final terminal = ScriptedTerminal(const <String?>[]);

    final int code = await runFirestoreStep(runner, terminal);

    final output = terminal.output.toString();
    expect(code, wizardExitDone);
    expect(output, contains('  ✓ ${FirestoreStep.stepTitle} — '));
    expect(output, contains('Firestore 위치: asia-northeast3 (바꿀 수 없음)'));
    expect(terminal.asks, isEmpty);
    expect(runner.countMode(RunMode.stream), 0);
  });

  test(
    'T-19-LOC-02 데이터베이스가 없으면 기본(지금 config 값)을 골라 확인 표 y 뒤 만들고, 같은 값이라 세 파일은 그대로',
    () async {
      final List<String> before = readRegionFiles();
      final runner = FakeCommandRunner()..on(createKey('asia-northeast3'), _ok);
      registerQueue(runner, describeKey, <CommandResult>[
        notFound,
        notFound,
        buildLocation('asia-northeast3'),
      ]);
      final terminal = ScriptedTerminal(const <String?>['y', '', 'y']);

      final int code = await runFirestoreStep(runner, terminal);

      final output = terminal.output.toString();
      expect(code, wizardExitDone);
      expect(output, contains('  ✗ ${FirestoreStep.stepTitle} — '));
      expect(terminal.asks, contains(FirestoreStep.locationChoiceQuestion));
      expect(terminal.asks, contains(summaryConfirmQuestion));
      expect(output, contains('── ${FirestoreStep.confirmTitle} ──'));
      expect(output, contains('  ! ${FirestoreStep.locationImmutableWarning}'));
      expect(
        FirestoreStep.locationImmutableWarning,
        'Firestore 위치는 만든 뒤 바꿀 수 없습니다.',
      );
      expect(listStreamKeys(runner), <String>[createKey('asia-northeast3')]);
      expect(readRegionFiles(), before);
      expect(runner.countCalls(RunMode.capture, gitStatusKey), 0);
      expect(output, contains('  ✓ ${FirestoreStep.stepTitle} — '));
    },
  );

  test(
    'T-19-LOC-03 us-central1 을 고르면 세 파일이 함께 바뀌고 다른 바이트는 그대로 · 두 정규식으로 다시 읽어도 같은 값',
    () async {
      final List<String> before = readRegionFiles();
      final runner = FakeCommandRunner()
        ..on(gitStatusKey, _ok)
        ..on(createKey('us-central1'), _ok);
      registerQueue(runner, describeKey, <CommandResult>[
        notFound,
        notFound,
        buildLocation('us-central1'),
      ]);
      final terminal = ScriptedTerminal(const <String?>['y', '3', 'y']);

      final int code = await runFirestoreStep(runner, terminal);

      final output = terminal.output.toString();
      expect(code, wizardExitDone);
      expect(output, contains(FirestoreStep.regionFilesNotice));
      expect(
        FirestoreStep.regionFilesNotice,
        'Functions 리전을 바꾸면 config/dev.json · functions/src/shared/region.ts · '
        'lib/core/config/app_config.dart 세 곳이 함께 바뀝니다.',
      );
      expect(listStreamKeys(runner), <String>[createKey('us-central1')]);
      expect(runner.countCalls(RunMode.capture, gitStatusKey), 1);
      expect(readRegionValues(), <String>[
        'us-central1',
        'us-central1',
        'us-central1',
      ]);
      expect(readRegionFiles(), <String>[
        before[0].replaceFirst(
          '"functionsRegion": "asia-northeast3"',
          '"functionsRegion": "us-central1"',
        ),
        before[1].replaceFirst('asia-northeast3', 'us-central1'),
        before[2].replaceFirst('asia-northeast3', 'us-central1'),
      ]);
      expect(output, contains('  ✓ ${FirestoreStep.stepTitle} — '));
    },
  );

  test('T-19-LOC-04 확인 표에서 N 이면 만들지 않고 파일도 그대로', () async {
    final List<String> before = readRegionFiles();
    final runner = FakeCommandRunner()..on(describeKey, notFound);
    final terminal = ScriptedTerminal(const <String?>['y', '3', 'n']);

    final int code = await runFirestoreStep(runner, terminal);

    expect(code, wizardExitStopped);
    expect(terminal.asks, contains(summaryConfirmQuestion));
    expect(runner.countMode(RunMode.stream), 0);
    expect(runner.countCalls(RunMode.capture, gitStatusKey), 0);
    expect(readRegionFiles(), before);
  });

  test(
    'T-19-LOC-05 Firestore 가 다중 리전 nam5 로 있고 세 값이 같으면 위치를 묻지 않고 ✓',
    () async {
      final runner = FakeCommandRunner()
        ..on(describeKey, buildLocation('nam5'));
      final terminal = ScriptedTerminal(const <String?>[]);

      final int code = await runFirestoreStep(runner, terminal);

      final output = terminal.output.toString();
      expect(code, wizardExitDone);
      expect(output, contains('Firestore 위치: nam5 (바꿀 수 없음)'));
      expect(terminal.asks, isEmpty);
      expect(runner.countMode(RunMode.stream), 0);
    },
  );

  test(
    'T-19-LOC-06 Firestore 가 있고 region.ts 만 다르면 ✗ 다릅니다 · y 뒤 Functions 리전만 골라 확인 표 없이 세 곳을 맞춘다',
    () async {
      regionTs.writeAsStringSync(
        regionTs.readAsStringSync().replaceFirst(
          'asia-northeast3',
          'europe-west1',
        ),
      );
      final runner = FakeCommandRunner()
        ..on(describeKey, buildLocation('asia-northeast3'))
        ..on(gitStatusKey, _ok);
      final terminal = ScriptedTerminal(const <String?>['y', '']);

      final int code = await runFirestoreStep(runner, terminal);

      final output = terminal.output.toString();
      expect(code, wizardExitDone);
      expect(output, contains('  ✗ ${FirestoreStep.stepTitle} — '));
      expect(output, contains('다릅니다'));
      expect(output, contains('Firestore 위치: asia-northeast3 (바꿀 수 없음)'));
      expect(terminal.asks, contains(FirestoreStep.regionChoiceQuestion));
      expect(terminal.asks, isNot(contains(summaryConfirmQuestion)));
      expect(runner.countMode(RunMode.stream), 0);
      expect(readRegionValues(), <String>[
        'asia-northeast3',
        'asia-northeast3',
        'asia-northeast3',
      ]);
      expect(output, contains('  ✓ ${FirestoreStep.stepTitle} — '));
    },
  );

  test('T-19-LOC-07 region.ts 에 커밋하지 않은 변경이 있으면 리전을 바꾸지 않고 실패', () async {
    final List<String> before = readRegionFiles();
    final runner = FakeCommandRunner()
      ..on(describeKey, notFound)
      ..on(
        gitStatusKey,
        const CommandResult(0, ' M functions/src/shared/region.ts\n', ''),
      );
    final terminal = ScriptedTerminal(const <String?>['y', '3', 'y']);

    final int code = await runFirestoreStep(runner, terminal);

    final output = terminal.output.toString();
    expect(code, wizardExitStopped);
    expect(output, contains('  실패 — 고칠 파일에 커밋하지 않은 변경이 있습니다'));
    expect(output, contains('    functions/src/shared/region.ts'));
    expect(runner.countMode(RunMode.stream), 0);
    expect(readRegionFiles(), before);
  });

  test('T-19-LOC-08 고르기 목록은 단일 리전 6개이고 다중 리전이 없다', () async {
    expect(FirestoreStep.singleRegions.keys.toList(), <String>[
      'asia-northeast3',
      'asia-northeast1',
      'us-central1',
      'us-east1',
      'us-west1',
      'europe-west1',
    ]);
    final runner = FakeCommandRunner()..on(describeKey, notFound);
    final terminal = ScriptedTerminal(const <String?>['y']);

    final int code = await runFirestoreStep(runner, terminal);

    final output = terminal.output.toString();
    final List<String> optionLines = output
        .split('\n')
        .where((String line) => RegExp(r'^  [0-9]+\) ').hasMatch(line))
        .toList();
    expect(code, wizardExitStopped);
    expect(optionLines, hasLength(6));
    for (final String region in FirestoreStep.singleRegions.keys) {
      expect(
        optionLines.where((String line) => line.contains(region)),
        isNotEmpty,
      );
    }
    expect(output, isNot(contains('nam5')));
    expect(output, isNot(contains('eur3')));
    expect(runner.countMode(RunMode.stream), 0);
  });

  group('T-19-LOC-09 값 표 재확인 안내는 확인 표를 보이는 모드에서만 붙는다', () {
    test('T-19-LOC-09 데이터베이스 만들기 모드는 안내가 붙는다', () async {
      final runner = FakeCommandRunner()..on(describeKey, notFound);
      final terminal = ScriptedTerminal(const <String?>['n']);

      final int code = await runFirestoreStep(runner, terminal);

      final output = terminal.output.toString();
      expect(code, wizardExitStopped);
      expect(output, contains('▶ ${FirestoreStep.stepTitle}'));
      expect(output.contains('    $costlyStepNotice'), isTrue);
    });

    test('T-19-LOC-09 리전 맞추기 모드는 표 없이 고르기만 하므로 안내가 붙지 않는다', () async {
      // region.ts 값을 config 와 다르게 만들어 세 곳 불일치 상태를 만든다.
      regionTs.writeAsStringSync('export const REGION = "us-central1";\n');
      final runner = FakeCommandRunner()
        ..on(describeKey, buildLocation('asia-northeast3'));
      final terminal = ScriptedTerminal(const <String?>['n']);

      final int code = await runFirestoreStep(runner, terminal);

      final output = terminal.output.toString();
      expect(code, wizardExitStopped);
      expect(output, contains('▶ ${FirestoreStep.stepTitle}'));
      expect(output, contains('Functions 리전을 골라 세 파일에 같은 값을 씁니다'));
      expect(output.contains('    $costlyStepNotice'), isFalse);
      expect(runner.countMode(RunMode.stream), 0);
    });
  });

  test('describe 가 「없음」 밖의 이유로 실패하면 첫 줄을 사유로 보이고 만들지 않는다', () async {
    const denied =
        'ERROR: (gcloud.firestore.databases.describe) PERMISSION_DENIED: '
        'The caller does not have permission\nsecond line\n';
    final runner = FakeCommandRunner()
      ..on(describeKey, const CommandResult(1, '', denied));
    final terminal = ScriptedTerminal(const <String?>['y']);

    final int code = await runFirestoreStep(runner, terminal);

    final output = terminal.output.toString();
    expect(code, wizardExitStopped);
    expect(output, contains('PERMISSION_DENIED: The caller does not have'));
    expect(output, contains(denied));
    expect(
      terminal.asks,
      isNot(contains(FirestoreStep.locationChoiceQuestion)),
    );
    expect(runner.countMode(RunMode.stream), 0);
  });

  test('buildDevSteps 는 API 다음에 위치 · Firestore 단계를 둔다', () {
    final List<String> ids = buildDevSteps()
        .map((Step step) => step.id)
        .toList();

    expect(ids.indexOf('firestore'), ids.indexOf('apis') + 1);
  });

  group('flavor 문맥', () {
    /// stg 프로젝트 ID(가짜).
    const stgProjectId = 'p-stg';
    late FakeCommandRunner runner;
    late ScriptedTerminal screen;
    late File stgConfig;
    late String sharedRegion;
    late String otherRegion;

    /// stg 프로젝트의 Firestore 위치를 읽는 가짜 실행기 키.
    final String stgDescribeKey = FakeCommandRunner.buildKey(
      FirestoreStep.buildDescribeCommand(stgProjectId),
    );

    /// [flavor] 문맥을 만든다 — 화면은 가림 터미널로 감싼다.
    WizardContext buildFlavorContext(Flavor flavor, List<String?> inputs) {
      final log = MemoryLogSink(Redactor());
      screen = ScriptedTerminal(inputs);
      return WizardContext(
        projectRoot: root,
        runner: runner,
        terminal: RedactingTerminal(screen, log.redactor, log),
        redactor: log.redactor,
        log: log,
        rest: FakeRestClient(),
        flavor: flavor,
        random: Random(fixedTestRandomSeed),
        now: () => fixedTestNow,
      );
    }

    /// 추적 리전 파일 두 곳 · dev config 의 바이트 사본.
    Map<String, List<int>> snapshotSharedFiles() => <String, List<int>>{
      for (final File file in <File>[regionTs, appConfig, config])
        file.path: file.readAsBytesSync(),
    };

    setUp(() {
      runner = FakeCommandRunner();
      const paths = FlavorPaths(Flavor.stg);
      stgConfig = File('$root/${paths.json}');
      File(paths.jsonExample).copySync(stgConfig.path);
      replaceJsonString(stgConfig.path, 'firebaseProjectId', stgProjectId);
      // 기대 리전은 저장소의 region.ts 에서 읽는다.
      sharedRegion = regionTsReadPattern
          .firstMatch(File(FirestoreStep.regionTsPath).readAsStringSync())!
          .group(1)!;
      otherRegion = FirestoreStep.singleRegions.keys.firstWhere(
        (String region) => region != sharedRegion,
      );
      replaceJsonString(
        stgConfig.path,
        FirestoreStep.functionsRegionKey,
        otherRegion,
      );
    });

    test(
      'T-20-FLAVOR-14: stg 에 Firestore 가 없으면 묻지 않고 region.ts 의 리전으로 값 표 뒤 만들고 stg config 만 맞춘다',
      () async {
        final Map<String, List<int>> sharedBefore = snapshotSharedFiles();
        runner
          ..on(stgDescribeKey, notFound)
          ..on(
            FakeCommandRunner.buildKey(
              FirestoreStep.buildCreateCommand(sharedRegion, stgProjectId),
            ),
            _ok,
          );
        final WizardContext context = buildFlavorContext(
          Flavor.stg,
          const <String?>['y'],
        );
        final step = FirestoreStep();

        expect(await step.check(context), isA<Todo>());
        expect(step.isCostlyOrIrreversible, isTrue);
        final List<String> lines = step.plannedCommandLines(context);
        final StepOutcome outcome = await step.apply(context);

        final output = screen.output.toString();
        expect(
          lines,
          contains(
            FirestoreStep.buildCreateCommand(
              sharedRegion,
              stgProjectId,
            ).render(),
          ),
        );
        expect(outcome, isA<Applied>());
        expect(screen.asks, <String>[summaryConfirmQuestion]);
        expect(output, contains(FirestoreStep.sharedRegionNotice));
        expect(
          FirestoreStep.sharedRegionNotice,
          contains('Functions 리전은 모든 flavor 가 함께 씁니다'),
        );
        expect(
          output,
          contains('  ! ${FirestoreStep.locationImmutableWarning}'),
        );
        expect(output, contains('Firestore 위치'));
        expect(output, contains(sharedRegion));
        expect(listStreamKeys(runner), <String>[
          FakeCommandRunner.buildKey(
            FirestoreStep.buildCreateCommand(sharedRegion, stgProjectId),
          ),
        ]);
        expect(
          readJsonString(stgConfig.path, FirestoreStep.functionsRegionKey),
          sharedRegion,
        );
        // 추적 리전 파일 · dev config 는 그대로고 git 을 부르지 않는다.
        for (final MapEntry<String, List<int>> entry in sharedBefore.entries) {
          expect(
            File(entry.key).readAsBytesSync(),
            entry.value,
            reason: entry.key,
          );
        }
        expect(runner.countCalls(RunMode.capture, gitStatusKey), 0);
      },
    );

    test('T-20-FLAVOR-14: 값 표에서 N 이면 만들기 · 쓰기 0', () async {
      final Map<String, List<int>> sharedBefore = snapshotSharedFiles();
      final List<int> stgBefore = stgConfig.readAsBytesSync();
      runner.on(stgDescribeKey, notFound);
      final WizardContext context = buildFlavorContext(
        Flavor.prod,
        const <String?>['n'],
      );
      // prod 문맥도 같은 갈래다 — prod config 를 만든다.
      const prodPaths = FlavorPaths(Flavor.prod);
      stgConfig.copySync('$root/${prodPaths.json}');
      final step = FirestoreStep();

      expect(await step.check(context), isA<Todo>());
      expect(await step.apply(context), isA<Declined>());

      expect(screen.asks, <String>[summaryConfirmQuestion]);
      expect(listStreamKeys(runner), isEmpty);
      expect(File('$root/${prodPaths.json}').readAsBytesSync(), stgBefore);
      for (final MapEntry<String, List<int>> entry in sharedBefore.entries) {
        expect(File(entry.key).readAsBytesSync(), entry.value);
      }
    });

    test(
      'T-20-FLAVOR-16: stg · Firestore 있음 · 추적 리전 두 곳이 다르면 묻지 않고 실패한다',
      () async {
        appConfig.writeAsStringSync(
          appConfigFixture.replaceFirst("'asia-northeast3'", "'$otherRegion'"),
        );
        final Map<String, List<int>> sharedBefore = snapshotSharedFiles();
        final List<int> stgBefore = stgConfig.readAsBytesSync();
        runner.on(stgDescribeKey, buildLocation(sharedRegion));
        final WizardContext context = buildFlavorContext(
          Flavor.stg,
          const <String?>[],
        );
        final step = FirestoreStep();

        expect(await step.check(context), isA<Todo>());
        final StepOutcome outcome = await step.apply(context);

        expect(
          outcome,
          isA<Failed>().having(
            (Failed failed) => failed.summary,
            'summary',
            contains('dev 실행에서 Functions 리전을 먼저 맞춘 뒤 다시 실행하세요'),
          ),
        );
        expect(screen.asks, isEmpty);
        expect(stgConfig.readAsBytesSync(), stgBefore);
        for (final MapEntry<String, List<int>> entry in sharedBefore.entries) {
          expect(File(entry.key).readAsBytesSync(), entry.value);
        }
      },
    );

    test(
      'T-20-FLAVOR-16: stg · Firestore 있음 · 추적 리전이 같으면 값 표 뒤 stg config 리전만 맞춘다',
      () async {
        final Map<String, List<int>> sharedBefore = snapshotSharedFiles();
        runner.on(stgDescribeKey, buildLocation(sharedRegion));
        final WizardContext context = buildFlavorContext(
          Flavor.stg,
          const <String?>['y'],
        );
        final step = FirestoreStep();

        expect(await step.check(context), isA<Todo>());
        expect(step.plannedCommandLines(context), <String>[
          '(config/stg.json 의 functionsRegion 을 $sharedRegion 로 씀 — '
              'Firestore · 추적 리전 파일은 그대로)',
        ]);
        expect(await step.apply(context), isA<Applied>());

        expect(screen.asks, <String>[summaryConfirmQuestion]);
        expect(
          readJsonString(stgConfig.path, FirestoreStep.functionsRegionKey),
          sharedRegion,
        );
        for (final MapEntry<String, List<int>> entry in sharedBefore.entries) {
          expect(File(entry.key).readAsBytesSync(), entry.value);
        }
        expect(await step.check(context), isA<Done>());
      },
    );

    test('T-20-FLAVOR-16: stg · 추적 리전이 고를 수 있는 목록 밖이면 묻지 않고 실패한다', () async {
      const outsideRegion = 'southamerica-east1';
      expect(FirestoreStep.singleRegions, isNot(contains(outsideRegion)));
      regionTs.writeAsStringSync(
        regionTs.readAsStringSync().replaceFirst(
          '"$sharedRegion"',
          '"$outsideRegion"',
        ),
      );
      appConfig.writeAsStringSync(
        appConfigFixture.replaceFirst("'asia-northeast3'", "'$outsideRegion'"),
      );
      runner.on(stgDescribeKey, notFound);
      final WizardContext context = buildFlavorContext(
        Flavor.stg,
        const <String?>[],
      );
      final step = FirestoreStep();

      expect(await step.check(context), isA<Todo>());
      expect(await step.apply(context), isA<Failed>());
      expect(screen.asks, isEmpty);
      expect(listStreamKeys(runner), isEmpty);
    });

    test('T-20-FLAVOR-15: dev 문맥의 위치 단계는 위치를 묻고 세 곳 안내 · 계획 줄이 그대로다', () async {
      runner.on(describeKey, notFound);
      final WizardContext context = buildFlavorContext(
        Flavor.dev,
        const <String?>[null],
      );
      final step = FirestoreStep();

      expect(await step.check(context), isA<Todo>());
      expect(step.plannedCommandLines(context), <String>[
        '(위치를 고르고 확인 표 뒤에 아래 명령을 실행합니다)',
        'gcloud firestore databases create --location=<위치> '
            '--project $projectId',
        '(고른 위치가 지금 Functions 리전과 다르면 세 파일의 리전 값을 함께 바꿉니다)',
      ]);
      expect(await step.apply(context), isA<Declined>());
      expect(screen.asks, <String>[FirestoreStep.locationChoiceQuestion]);
      expect(
        screen.output.toString(),
        contains('  ${FirestoreStep.regionFilesNotice}'),
      );
    });
  });
}
