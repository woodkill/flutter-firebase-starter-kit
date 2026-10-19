import 'dart:convert';
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
import '../../../tool/setup/steps/firebase_project_step.dart';
import '../../../tool/setup/steps/user_files_step.dart';
import '../../../tool/setup/terminal.dart';
import '../../../tool/setup/wizard.dart';
import 'fake_rest_client.dart';
import 'fakes.dart';

const String _gitStatusKey = 'git status --porcelain --untracked-files=no';
const String _projectsListKey = 'firebase projects:list --json';
const CommandResult _ok = CommandResult(0, '', '');
const CommandResult _cleanTree = CommandResult(0, '', '');
const CommandResult _notFound = CommandResult(
  1,
  '',
  'ERROR: (gcloud.projects.describe) NOT_FOUND: Project not found\n',
);

/// 처음 쓰는 계정에서 `firebase projects:addfirebase` 가 실패할 때 화면에 남는 한 줄.
const CommandResult _addFirebaseFailed = CommandResult(
  2,
  '',
  'Error: Failed to add Firebase to Google Cloud Platform project. '
      'See firebase-debug.log for more info.\n',
);

/// Firebase 추가 콘솔 안내가 「」 로 감싸 옮기는 Firebase 콘솔 화면 라벨 원문(등장 순서).
const List<String> _consoleGuideLabels = <String>[
  'Firebase 프로젝트를 설정하여 시작하기',
  'Google Cloud 프로젝트에 Firebase를 추가할 때 유의해야 할 사항',
  '계속',
  'Firebase 프로젝트를 위한 Google 애널리틱스',
  '이 프로젝트에서 Google 애널리틱스 사용 설정',
  'Google 애널리틱스 구성',
  'Google 애널리틱스 약관에 동의합니다.',
  'Firebase 추가',
  'Firebase 프로젝트가 준비되었습니다.',
];

/// 애널리틱스를 켜 둔 채 진행하면 체크해야 하는 Firebase 콘솔 체크박스 라벨 원문.
const String _analyticsTermsLabel = 'Google 애널리틱스 약관에 동의합니다.';

/// 테스트 configure 상수의 프로젝트 prefix.
const String fixturePrefix = 'my-app';

/// prefix 로 제안되는 새 프로젝트 ID.
const String suggestedId = '$fixturePrefix-dev';

/// 이미 있는 가짜 프로젝트 ID.
const String existingId = 'acme-dev';

/// `gcloud projects describe` 가짜 실행기 키.
String describeKey(String id) =>
    'gcloud projects describe $id --format=value(projectId)';

/// `gcloud projects create` 가짜 실행기 키.
String createKey(String id) => 'gcloud projects create $id --name=$id';

/// `firebase projects:addfirebase` 가짜 실행기 키.
String addFirebaseKey(String id) => 'firebase projects:addfirebase $id';

/// `firebase projects:list --json` 모양(최상위 `status` · `result`, 항목
/// `projectId` · `displayName` …)을 만든다.
CommandResult buildProjectsResult(Map<String, String> projects) =>
    CommandResult(
      0,
      jsonEncode(<String, Object?>{
        'status': 'success',
        'result': <Object?>[
          for (final MapEntry<String, String> entry in projects.entries)
            <String, Object?>{
              'projectId': entry.key,
              'projectNumber': '100200300',
              'displayName': entry.value,
              'name': 'projects/${entry.key}',
              'resources': <String, Object?>{},
              'state': 'ACTIVE',
              'etag': '1_fixture',
            },
        ],
      }),
      '',
    );

/// 이미 끝난 앞 단계 — 프로젝트 단계의 의존 단계를 대신한다.
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

/// [root] 아래에 프로젝트 단계가 읽고 쓰는 파일 fixture 를 쓴다.
///
/// 사용자 설정 파일은 추적되는 example 을 복사해 만들고, [projectId] 가 있으면
/// `firebaseProjectId` 를 그 값으로 바꾼다. `.firebaserc` 는 저장소와 같은
/// 모양(2칸 들여쓰기)으로 [aliases] 를 쓴다.
void writeProjectFixture(
  String root, {
  String? projectId,
  Map<String, String> aliases = const <String, String>{
    'default': 'old-kit-dev',
    'dev': 'old-kit-dev',
  },
}) {
  final config = File('$root/${UserFilesStep.jsonUserPath}')
    ..parent.createSync(recursive: true);
  File(UserFilesStep.jsonExamplePath).copySync(config.path);
  if (projectId != null) {
    replaceJsonString(config.path, 'firebaseProjectId', projectId);
  }
  File('$root/.firebaserc').writeAsStringSync(
    '${const JsonEncoder.withIndent('  ').convert(<String, Object?>{'projects': aliases})}\n',
  );
  File('$root/scripts/firebase-configure.sh')
    ..parent.createSync(recursive: true)
    ..writeAsStringSync(
      <String>[
        '#!/usr/bin/env bash',
        'PROJECT_ID_PREFIX="$fixturePrefix"',
        'IOS_BUNDLE_ID_PREFIX="com.example.myApp"',
        'ANDROID_PACKAGE_PREFIX="com.example.my_app"',
        r'PROJECT_ID="${PROJECT_ID_PREFIX}-${FLAVOR}"',
        '',
      ].join('\n'),
    );
}

/// 스트림으로 실행된 명령 키를 순서대로 모은다.
List<String> listStreamKeys(FakeCommandRunner runner) => runner.calls
    .where((FakeCall call) => call.mode == RunMode.stream)
    .map((FakeCall call) => call.key)
    .toList();

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

void main() {
  late Directory tempDir;
  late String root;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('project_step_test_');
    root = tempDir.path;
  });

  tearDown(() {
    tempDir.deleteSync(recursive: true);
  });

  String readConfigProjectId() => readJsonString(
    '$root/${UserFilesStep.jsonUserPath}',
    'firebaseProjectId',
  )!;

  Map<String, Object?> readAliases() {
    final Object? decoded = jsonDecode(
      File('$root/.firebaserc').readAsStringSync(),
    );
    return (decoded! as Map<String, Object?>)['projects']!
        as Map<String, Object?>;
  }

  /// 로그인 · 앱 정체성(끝남) · 프로젝트 단계로 위저드를 돌린다.
  ///
  /// [step] 을 주지 않으면 기본 생성자로 만든 프로젝트 단계를 쓴다.
  Future<int> runProjectStep(
    FakeCommandRunner runner,
    ScriptedTerminal terminal, {
    FirebaseProjectStep? step,
  }) => runWizard(
    buildTestContext(projectRoot: root, runner: runner, terminal: terminal),
    <Step>[
      _FinishedStep('login', 'Firebase · Google Cloud 로그인'),
      _FinishedStep('identity', '앱 정체성'),
      step ?? FirebaseProjectStep(),
    ],
  );

  /// [runProjectStep] 과 같은 단계를 실제 터미널 모양으로 돌린다.
  ///
  /// 화면은 번호 질문의 기본값 안내(`번호를 고르세요 [n]: `)까지 [output] 에
  /// 쓰고, 답은 [inputs] 에서 차례로 읽는다(떨어지면 입력 끝).
  Future<int> runProjectStepOnStdio(
    FakeCommandRunner runner,
    List<String> inputs,
    StringBuffer output,
    FirebaseProjectStep step,
  ) {
    final answers = List<String>.of(inputs);
    final redactor = Redactor();
    final log = MemoryLogSink(redactor);
    return runWizard(
      WizardContext(
        projectRoot: root,
        runner: runner,
        terminal: RedactingTerminal(
          StdioTerminal(
            readLine: () => answers.isEmpty ? null : answers.removeAt(0),
            output: output,
          ),
          redactor,
          log,
        ),
        redactor: redactor,
        log: log,
        rest: FakeRestClient(),
        homeDirectory: noKeystoreTestHome,
        random: Random(fixedTestRandomSeed),
        now: () => fixedTestNow,
      ),
      <Step>[
        _FinishedStep('login', 'Firebase · Google Cloud 로그인'),
        _FinishedStep('identity', '앱 정체성'),
        step,
      ],
    );
  }

  test(
    'T-19-PROJ-01 config 에 실제 ID 가 있고 목록 · .firebaserc 가 맞으면 묻지 않고 ✓',
    () async {
      writeProjectFixture(
        root,
        projectId: existingId,
        aliases: const <String, String>{
          'default': existingId,
          'dev': existingId,
        },
      );
      final runner = FakeCommandRunner()
        ..on(
          _projectsListKey,
          buildProjectsResult(const <String, String>{existingId: 'Acme Dev'}),
        );
      final terminal = ScriptedTerminal(const <String?>[]);

      final int code = await runProjectStep(runner, terminal);

      expect(code, wizardExitDone);
      expect(
        terminal.output.toString(),
        contains('  ✓ ${FirebaseProjectStep.stepTitle} — $existingId'),
      );
      expect(terminal.asks, isEmpty);
      expect(runner.countMode(RunMode.stream), 0);
    },
  );

  test(
    'T-19-PROJ-02 config 의 ID 가 내 목록에 없으면 ✗ · y 뒤 계정 · 권한 안내 실패이고 만들기 · 고르기를 묻지 않는다',
    () async {
      writeProjectFixture(root, projectId: existingId);
      final runner = FakeCommandRunner()
        ..on(
          _projectsListKey,
          buildProjectsResult(const <String, String>{'other-dev': 'Other'}),
        )
        ..on(describeKey(existingId), _notFound);
      final terminal = ScriptedTerminal(const <String?>['y']);

      final int code = await runProjectStep(runner, terminal);

      final output = terminal.output.toString();
      expect(code, wizardExitStopped);
      expect(output, contains('  ✗ ${FirebaseProjectStep.stepTitle} — '));
      expect(output, contains(FirebaseProjectStep.accountPermissionGuidance));
      expect(
        terminal.asks,
        isNot(contains(FirebaseProjectStep.projectChoiceQuestion)),
      );
      expect(terminal.asks, isNot(contains(FirebaseProjectStep.idQuestion)));
      expect(runner.countMode(RunMode.stream), 0);
      expect(readConfigProjectId(), existingId);
    },
  );

  test(
    'T-19-PROJ-03 자리표시면 새로 만들기 · 제안 ID 그대로 · 확인 표 y 뒤 만들기 → Firebase 추가 → config · .firebaserc',
    () async {
      writeProjectFixture(root);
      final runner = FakeCommandRunner()
        ..on(_gitStatusKey, _cleanTree)
        ..on(describeKey(suggestedId), _notFound)
        ..on(createKey(suggestedId), _ok)
        ..on(addFirebaseKey(suggestedId), _ok)
        ..on(
          _projectsListKey,
          buildProjectsResult(const <String, String>{suggestedId: suggestedId}),
        );
      final terminal = ScriptedTerminal(const <String?>['y', '1', '', 'y']);

      final int code = await runProjectStep(runner, terminal);

      final output = terminal.output.toString();
      expect(code, wizardExitDone);
      expect(output, contains(FirebaseProjectStep.idQuestion));
      expect(terminal.asks, contains(summaryConfirmQuestion));
      expect(output, contains('  ! ${FirebaseProjectStep.permanentIdWarning}'));
      expect(
        FirebaseProjectStep.permanentIdWarning,
        '프로젝트 ID 는 만든 뒤 바꿀 수 없고, 지운 뒤에도 다시 쓸 수 없습니다.',
      );
      expect(listStreamKeys(runner), <String>[
        createKey(suggestedId),
        addFirebaseKey(suggestedId),
      ]);
      expect(readConfigProjectId(), suggestedId);
      expect(readAliases(), <String, Object?>{
        'default': suggestedId,
        'dev': suggestedId,
      });
      final String rc = File('$root/.firebaserc').readAsStringSync();
      expect(rc, contains('\n  "projects": {\n    "default": '));
      expect(rc.endsWith('}\n'), isTrue);
      expect(output, contains('  ✓ ${FirebaseProjectStep.stepTitle} — '));
    },
  );

  test('T-19-PROJ-04 확인 표에서 N 이면 외부 쓰기 명령 0 · 파일 그대로', () async {
    writeProjectFixture(root);
    final before = <String, String>{
      for (final String path in <String>[
        UserFilesStep.jsonUserPath,
        '.firebaserc',
      ])
        path: File('$root/$path').readAsStringSync(),
    };
    final runner = FakeCommandRunner()..on(_gitStatusKey, _cleanTree);
    final terminal = ScriptedTerminal(const <String?>['y', '1', '', 'n']);

    final int code = await runProjectStep(runner, terminal);

    expect(code, wizardExitStopped);
    expect(terminal.asks, contains(summaryConfirmQuestion));
    expect(runner.countMode(RunMode.stream), 0);
    expect(runner.countMode(RunMode.interactive), 0);
    for (final MapEntry<String, String> entry in before.entries) {
      expect(
        File('$root/${entry.key}').readAsStringSync(),
        entry.value,
        reason: entry.key,
      );
    }
  });

  test(
    'T-19-PROJ-05 형식에 맞지 않는 ID(짧음 · 대문자 · 30자 초과)는 다시 묻고 끝까지 틀리면 만들지 않는다',
    () async {
      writeProjectFixture(root);
      final tooLong = 'a${'b' * 30}';
      final runner = FakeCommandRunner()..on(_gitStatusKey, _cleanTree);
      final terminal = ScriptedTerminal(<String?>[
        '1',
        'ab',
        'My-App',
        tooLong,
      ]);
      final WizardContext context = buildTestContext(
        projectRoot: root,
        runner: runner,
        terminal: terminal,
      );
      final step = FirebaseProjectStep();

      await step.check(context);
      final StepOutcome outcome = await step.apply(context);

      expect(outcome, isA<Failed>());
      expect(
        terminal.asks
            .where((String ask) => ask == FirebaseProjectStep.idQuestion)
            .length,
        FirebaseProjectStep.maxInputAttempts,
      );
      expect(
        RegExp(
          RegExp.escape(FirebaseProjectStep.invalidIdMessage),
        ).allMatches(terminal.output.toString()).length,
        3,
      );
      expect(runner.countMode(RunMode.stream), 0);
      expect(FirebaseProjectStep.isValidProjectId('ab'), isFalse);
      expect(FirebaseProjectStep.isValidProjectId('My-App'), isFalse);
      expect(FirebaseProjectStep.isValidProjectId(tooLong), isFalse);
      expect(FirebaseProjectStep.isValidProjectId('my-app-'), isFalse);
      expect(FirebaseProjectStep.isValidProjectId('a${'b' * 29}'), isTrue);
      expect(FirebaseProjectStep.isValidProjectId(suggestedId), isTrue);
    },
  );

  // 1차는 gcloud 가 409 를 바꿔 보이는 실제 문구(SDK surface/projects/create.py),
  // 보조는 gcloud 가 치환하기 전의 API 원문이다.
  const conflictOutputs = <String, String>{
    'gcloud 문구':
        'ERROR: (gcloud.projects.create) Project creation failed. The project '
        'ID you specified is already in use by another project. Please try an '
        'alternative ID.\n',
    'API 원문':
        'ERROR: (gcloud.projects.create) Resource in projects [my-app-dev] '
        'is the subject of a conflict: Requested entity already exists\n',
  };
  for (final MapEntry<String, String> conflictCase in conflictOutputs.entries) {
    test('T-19-PROJ-06 이미 쓰이는 ID 면(${conflictCase.key}) 원문과 다른 ID 안내로 '
        '실패하고 다시 시도에서 새 ID 로 진행한다', () async {
      writeProjectFixture(root);
      const retryId = 'my-app-dev2';
      final String conflict = conflictCase.value;
      final runner = FakeCommandRunner()
        ..on(_gitStatusKey, _cleanTree)
        ..on(describeKey(suggestedId), _notFound)
        ..on(createKey(suggestedId), CommandResult(1, '', conflict))
        ..on(describeKey(retryId), _notFound)
        ..on(createKey(retryId), _ok)
        ..on(addFirebaseKey(retryId), _ok)
        ..on(
          _projectsListKey,
          buildProjectsResult(const <String, String>{retryId: retryId}),
        );
      final terminal = ScriptedTerminal(const <String?>[
        'y',
        '1',
        '',
        'y',
        '1',
        '1',
        retryId,
        'y',
      ]);

      final int code = await runProjectStep(runner, terminal);

      final output = terminal.output.toString();
      expect(code, wizardExitDone);
      expect(output, contains(conflict));
      expect(output, contains(FirebaseProjectStep.idTakenGuidance));
      expect(output, isNot(contains(FirebaseProjectStep.cloudTermsGuidance)));
      expect(listStreamKeys(runner), <String>[
        createKey(suggestedId),
        createKey(retryId),
        addFirebaseKey(retryId),
      ]);
      expect(readConfigProjectId(), retryId);
      expect(readAliases()['dev'], retryId);
    });
  }

  test('T-19-PROJ-07 내 계정에 이미 있는 프로젝트면 만들기를 건너뛰고 Firebase 추가만 한다', () async {
    writeProjectFixture(root);
    final runner = FakeCommandRunner()
      ..on(_gitStatusKey, _cleanTree)
      ..on(
        describeKey(suggestedId),
        const CommandResult(0, '$suggestedId\n', ''),
      )
      ..on(addFirebaseKey(suggestedId), _ok)
      ..on(
        _projectsListKey,
        buildProjectsResult(const <String, String>{suggestedId: suggestedId}),
      );
    final terminal = ScriptedTerminal(const <String?>['y', '1', '', 'y']);

    final int code = await runProjectStep(runner, terminal);

    expect(code, wizardExitDone);
    expect(
      terminal.output.toString(),
      contains(FirebaseProjectStep.existingProjectNotice),
    );
    expect(listStreamKeys(runner), <String>[addFirebaseKey(suggestedId)]);
    expect(runner.countCalls(RunMode.stream, createKey(suggestedId)), 0);
    expect(readConfigProjectId(), suggestedId);
  });

  test(
    'T-19-PROJ-08 기존 프로젝트에서 고르기 — 목록 2번을 고르면 확인 표 없이 config · .firebaserc 를 쓰고 다른 별칭은 그대로',
    () async {
      writeProjectFixture(
        root,
        aliases: const <String, String>{
          'default': 'old-kit-dev',
          'dev': 'old-kit-dev',
          'stg': 'keep-stg',
        },
      );
      final runner = FakeCommandRunner()
        ..on(_gitStatusKey, _cleanTree)
        ..on(
          _projectsListKey,
          buildProjectsResult(const <String, String>{
            'first-dev': 'First',
            'second-dev': 'Second',
          }),
        );
      final terminal = ScriptedTerminal(const <String?>['y', '2', '2']);

      final int code = await runProjectStep(runner, terminal);

      final output = terminal.output.toString();
      expect(code, wizardExitDone);
      expect(output, contains('second-dev (Second)'));
      expect(terminal.asks, isNot(contains(summaryConfirmQuestion)));
      expect(runner.countMode(RunMode.stream), 0);
      expect(readConfigProjectId(), 'second-dev');
      expect(readAliases(), <String, Object?>{
        'default': 'second-dev',
        'dev': 'second-dev',
        'stg': 'keep-stg',
      });
    },
  );

  test(
    'T-19-PROJ-09 .firebaserc 에 커밋하지 않은 변경이 있으면 묻지 않고 실패하며 .firebaserc 는 그대로',
    () async {
      writeProjectFixture(root);
      final String before = File('$root/.firebaserc').readAsStringSync();
      final runner = FakeCommandRunner()
        ..on(_gitStatusKey, const CommandResult(0, ' M .firebaserc\n', ''));
      final terminal = ScriptedTerminal(const <String?>['y']);

      final int code = await runProjectStep(runner, terminal);

      final output = terminal.output.toString();
      expect(code, wizardExitStopped);
      expect(output, contains('    .firebaserc'));
      expect(
        terminal.asks,
        isNot(contains(FirebaseProjectStep.projectChoiceQuestion)),
      );
      expect(runner.countMode(RunMode.stream), 0);
      expect(File('$root/.firebaserc').readAsStringSync(), before);
    },
  );

  test('T-19-PROJ-10 만들기 실패(Cloud 약관 미동의)는 원문과 Cloud 콘솔 약관 안내만 보인다', () async {
    writeProjectFixture(root);
    const terms =
        'Operation [create_project.global.100200300] failed: 9: '
        'Callers must accept Terms of Service\n';
    final runner = FakeCommandRunner()
      ..on(_gitStatusKey, _cleanTree)
      ..on(describeKey(suggestedId), _notFound)
      ..on(createKey(suggestedId), const CommandResult(1, '', terms));
    final terminal = ScriptedTerminal(const <String?>['y', '1', '', 'y']);

    final int code = await runProjectStep(runner, terminal);

    final output = terminal.output.toString();
    expect(code, wizardExitStopped);
    expect(output, contains(terms));
    expect(output, contains(FirebaseProjectStep.cloudTermsGuidance));
    expect(
      FirebaseProjectStep.cloudTermsGuidance,
      contains('console.cloud.google.com'),
    );
    expect(
      FirebaseProjectStep.cloudTermsGuidance,
      isNot(contains('console.firebase.google.com')),
    );
    expect(runner.countCalls(RunMode.stream, addFirebaseKey(suggestedId)), 0);
    expect(readConfigProjectId(), 'your-project-dev');
  });

  test(
    'T-19-PROJ-11 새로 만들기 뒤 Firebase 추가가 실패하면 ID 는 이미 기록돼 있고 콘솔 안내 → Enter 재검사(아직 → ✓)',
    () async {
      // 먼저 Enter 에서 입력이 끝나는 실행 — 실패 뒤에도 만든 ID 가 남아 있다.
      writeProjectFixture(root);
      final stopped = FakeCommandRunner()
        ..on(_gitStatusKey, _cleanTree)
        ..on(describeKey(suggestedId), _notFound)
        ..on(createKey(suggestedId), _ok)
        ..on(addFirebaseKey(suggestedId), _addFirebaseFailed);
      final stoppedTerminal = ScriptedTerminal(const <String?>[
        'y',
        '1',
        '',
        'y',
      ]);

      final int stoppedCode = await runProjectStep(stopped, stoppedTerminal);

      expect(stoppedCode, wizardExitStopped);
      expect(listStreamKeys(stopped), <String>[
        createKey(suggestedId),
        addFirebaseKey(suggestedId),
      ]);
      expect(readConfigProjectId(), suggestedId);
      expect(readAliases(), <String, Object?>{
        'default': suggestedId,
        'dev': suggestedId,
      });

      // 같은 처음 상태에서 Enter 두 번 — 아직 → 콘솔에서 끝낸 뒤 ✓.
      writeProjectFixture(root);
      final runner = FakeCommandRunner()
        ..on(_gitStatusKey, _cleanTree)
        ..on(createKey(suggestedId), _ok)
        ..on(addFirebaseKey(suggestedId), _addFirebaseFailed);
      registerQueue(runner, describeKey(suggestedId), <CommandResult>[
        _notFound,
        const CommandResult(0, '$suggestedId\n', ''),
      ]);
      registerQueue(runner, _projectsListKey, <CommandResult>[
        buildProjectsResult(const <String, String>{'other-dev': 'Other'}),
        buildProjectsResult(const <String, String>{suggestedId: suggestedId}),
      ]);
      final terminal = ScriptedTerminal(const <String?>[
        'y',
        '1',
        '',
        'y',
        '',
        '',
      ]);

      final int code = await runProjectStep(runner, terminal);

      final output = terminal.output.toString();
      final String guide = FirebaseProjectStep.buildAddFirebaseGuide(
        suggestedId,
      );
      int countAsks(String question) =>
          terminal.asks.where((String ask) => ask == question).length;
      expect(code, wizardExitDone);
      expect(output, contains(guide));
      expect(output, contains(_analyticsTermsLabel));
      expect(guide, contains('https://console.firebase.google.com/'));
      expect(guide, contains(suggestedId));
      expect(RegExp('아직 끝나지 않았습니다').allMatches(output).length, 1);
      expect(output, contains('  ✓ ${FirebaseProjectStep.stepTitle} — '));
      expect(countAsks(FirebaseProjectStep.projectChoiceQuestion), 1);
      expect(countAsks(FirebaseProjectStep.idQuestion), 1);
      expect(countAsks(summaryConfirmQuestion), 1);
      expect(countAsks(waitForEnterMessage), 2);
      expect(countAsks(failureChoiceQuestion), 0);
      expect(runner.countCalls(RunMode.stream, createKey(suggestedId)), 1);
      expect(runner.countCalls(RunMode.stream, addFirebaseKey(suggestedId)), 1);
      expect(runner.countCalls(RunMode.capture, describeKey(suggestedId)), 2);
      expect(readConfigProjectId(), suggestedId);
      expect(readAliases()['dev'], suggestedId);
    },
  );

  /// [output] 에서 확인 표 머리 줄 `── [title] ──` 의 수를 센다.
  int countTitleLines(String output, String title) =>
      RegExp(RegExp.escape('── $title ──')).allMatches(output).length;

  /// config 와 `.firebaserc` 의 지금 바이트를 읽는다.
  Map<String, String> readProjectFiles() => <String, String>{
    for (final String path in <String>[
      UserFilesStep.jsonUserPath,
      '.firebaserc',
    ])
      path: File('$root/$path').readAsStringSync(),
  };

  /// Firebase 목록에는 없고 내 Cloud 프로젝트인 [existingId] 를 등록한다.
  ///
  /// [lists] 는 검사마다 차례로 돌려줄 목록 결과다(마지막 값은 되풀이).
  FakeCommandRunner buildAddFirebaseRunner({
    required List<CommandResult> lists,
    CommandResult added = _ok,
  }) {
    final runner = FakeCommandRunner()
      ..on(describeKey(existingId), const CommandResult(0, '$existingId\n', ''))
      ..on(addFirebaseKey(existingId), added);
    registerQueue(runner, _projectsListKey, lists);
    return runner;
  }

  final CommandResult listWithout = buildProjectsResult(const <String, String>{
    'other-dev': 'Other',
  });
  final CommandResult listWith = buildProjectsResult(const <String, String>{
    existingId: 'Acme Dev',
  });
  const matchingAliases = <String, String>{
    'default': existingId,
    'dev': existingId,
  };

  group(
    'T-19-PROJ-12 config ID 가 내 Cloud 프로젝트이고 Firebase 가 없으면 확인 표 뒤에만 Firebase 를 추가한다',
    () {
      test('별칭이 맞으면 미커밋 검사 없이 표 y → 추가 → ✓', () async {
        writeProjectFixture(
          root,
          projectId: existingId,
          aliases: matchingAliases,
        );
        final FakeCommandRunner runner = buildAddFirebaseRunner(
          lists: <CommandResult>[listWithout, listWithout, listWith],
        );
        final terminal = ScriptedTerminal(const <String?>['y', 'y']);

        final int code = await runProjectStep(runner, terminal);

        final output = terminal.output.toString();
        expect(code, wizardExitDone);
        expect(
          RegExp(
            '  ✗ ${RegExp.escape(FirebaseProjectStep.stepTitle)} — .*Firebase',
          ).hasMatch(output),
          isTrue,
        );
        expect(output, contains('  \$ ${addFirebaseKey(existingId)}'));
        expect(
          terminal.asks,
          isNot(contains(FirebaseProjectStep.projectChoiceQuestion)),
        );
        expect(terminal.asks, isNot(contains(FirebaseProjectStep.idQuestion)));
        expect(countTitleLines(output, FirebaseProjectStep.confirmTitle), 0);
        expect(
          countTitleLines(output, FirebaseProjectStep.addFirebaseConfirmTitle),
          1,
        );
        expect(
          RegExp('프로젝트 ID +${RegExp.escape(existingId)}').hasMatch(output),
          isTrue,
        );
        expect(
          output,
          contains('  ! ${FirebaseProjectStep.addFirebaseIrreversibleWarning}'),
        );
        expect(
          terminal.asks.where((String ask) => ask == summaryConfirmQuestion),
          hasLength(1),
        );
        expect(runner.countCalls(RunMode.capture, _gitStatusKey), 0);
        expect(listStreamKeys(runner), <String>[addFirebaseKey(existingId)]);
        expect(output, contains('  ✓ ${FirebaseProjectStep.stepTitle} — '));
      });

      test('표에서 Enter(기본 N)면 추가 0 · 파일 그대로 · 멈춤', () async {
        writeProjectFixture(
          root,
          projectId: existingId,
          aliases: matchingAliases,
        );
        final Map<String, String> before = readProjectFiles();
        final FakeCommandRunner runner = buildAddFirebaseRunner(
          lists: <CommandResult>[listWithout],
        );
        final terminal = ScriptedTerminal(const <String?>['y', '']);

        final int code = await runProjectStep(runner, terminal);

        expect(code, wizardExitStopped);
        expect(
          countTitleLines(
            terminal.output.toString(),
            FirebaseProjectStep.addFirebaseConfirmTitle,
          ),
          1,
        );
        expect(runner.countMode(RunMode.stream), 0);
        expect(readProjectFiles(), before);
      });

      test('별칭이 다르고 .firebaserc 에 미커밋 변경이 있으면 표 없이 실패 · 추가 0', () async {
        writeProjectFixture(root, projectId: existingId);
        final Map<String, String> before = readProjectFiles();
        final FakeCommandRunner runner = buildAddFirebaseRunner(
          lists: <CommandResult>[listWithout],
        )..on(_gitStatusKey, const CommandResult(0, ' M .firebaserc\n', ''));
        final terminal = ScriptedTerminal(const <String?>['y']);

        final int code = await runProjectStep(runner, terminal);

        final output = terminal.output.toString();
        expect(code, wizardExitStopped);
        expect(output, contains('    .firebaserc'));
        expect(
          countTitleLines(output, FirebaseProjectStep.addFirebaseConfirmTitle),
          0,
        );
        expect(runner.countMode(RunMode.stream), 0);
        expect(readProjectFiles(), before);
      });

      test('별칭이 다르고 깨끗하면 표 y 뒤 별칭을 먼저 쓰고 추가한다 · 표 거절이면 별칭도 그대로', () async {
        // 표 y → 별칭 쓰기 → 추가 실패 → Enter 에서 입력 끝: 별칭은 이미 새 ID.
        writeProjectFixture(root, projectId: existingId);
        final FakeCommandRunner runner = buildAddFirebaseRunner(
          lists: <CommandResult>[listWithout],
          added: _addFirebaseFailed,
        )..on(_gitStatusKey, _cleanTree);
        final terminal = ScriptedTerminal(const <String?>['y', 'y']);

        final int code = await runProjectStep(runner, terminal);

        expect(code, wizardExitStopped);
        expect(listStreamKeys(runner), <String>[addFirebaseKey(existingId)]);
        expect(readAliases(), <String, Object?>{
          'default': existingId,
          'dev': existingId,
        });

        // 표 거절 — 별칭을 쓰지 않는다.
        writeProjectFixture(root, projectId: existingId);
        final Map<String, String> before = readProjectFiles();
        final FakeCommandRunner declined = buildAddFirebaseRunner(
          lists: <CommandResult>[listWithout],
        )..on(_gitStatusKey, _cleanTree);
        final declinedTerminal = ScriptedTerminal(const <String?>['y', 'n']);

        final int declinedCode = await runProjectStep(
          declined,
          declinedTerminal,
        );

        expect(declinedCode, wizardExitStopped);
        expect(declined.countMode(RunMode.stream), 0);
        expect(readProjectFiles(), before);
      });
    },
  );

  test(
    'T-19-PROJ-13 Firebase 추가가 실패해 멈춘 뒤 다시 실행하면 같은 ID 로 확인 표 → 추가 → ✓ (고르기 · ID 질문 0)',
    () async {
      writeProjectFixture(
        root,
        projectId: existingId,
        aliases: matchingAliases,
      );
      final Map<String, String> before = readProjectFiles();
      final FakeCommandRunner first = buildAddFirebaseRunner(
        lists: <CommandResult>[listWithout],
        added: _addFirebaseFailed,
      );
      final firstTerminal = ScriptedTerminal(const <String?>['y', 'y']);

      final int firstCode = await runProjectStep(first, firstTerminal);

      expect(firstCode, wizardExitStopped);
      expect(
        firstTerminal.output.toString(),
        contains(FirebaseProjectStep.buildAddFirebaseGuide(existingId)),
      );
      expect(readProjectFiles(), before);

      final FakeCommandRunner second = buildAddFirebaseRunner(
        lists: <CommandResult>[listWithout, listWithout, listWith],
      );
      final secondTerminal = ScriptedTerminal(const <String?>['y', 'y']);

      final int secondCode = await runProjectStep(second, secondTerminal);

      final output = secondTerminal.output.toString();
      expect(secondCode, wizardExitDone);
      expect(
        secondTerminal.asks,
        isNot(contains(FirebaseProjectStep.projectChoiceQuestion)),
      );
      expect(
        secondTerminal.asks,
        isNot(contains(FirebaseProjectStep.idQuestion)),
      );
      expect(
        countTitleLines(output, FirebaseProjectStep.addFirebaseConfirmTitle),
        1,
      );
      expect(listStreamKeys(second), <String>[addFirebaseKey(existingId)]);
      expect(output, contains('  ✓ ${FirebaseProjectStep.stepTitle} — '));
      expect(readConfigProjectId(), existingId);
    },
  );

  test(
    'T-19-PROJ-14 새로 만들기에서 이미 있는 ID 면 만들기 없이 Firebase 추가 → 실패 → 콘솔 안내 → Enter → ✓',
    () async {
      writeProjectFixture(root);
      final runner = FakeCommandRunner()
        ..on(_gitStatusKey, _cleanTree)
        ..on(
          describeKey(suggestedId),
          const CommandResult(0, '$suggestedId\n', ''),
        )
        ..on(addFirebaseKey(suggestedId), _addFirebaseFailed)
        ..on(
          _projectsListKey,
          buildProjectsResult(const <String, String>{suggestedId: suggestedId}),
        );
      final terminal = ScriptedTerminal(const <String?>['y', '1', '', 'y', '']);

      final int code = await runProjectStep(runner, terminal);

      final output = terminal.output.toString();
      expect(code, wizardExitDone);
      expect(output, contains(FirebaseProjectStep.existingProjectNotice));
      expect(
        output,
        contains(FirebaseProjectStep.buildAddFirebaseGuide(suggestedId)),
      );
      expect(runner.countCalls(RunMode.stream, createKey(suggestedId)), 0);
      expect(listStreamKeys(runner), <String>[addFirebaseKey(suggestedId)]);
      expect(
        terminal.asks.where((String ask) => ask == summaryConfirmQuestion),
        hasLength(1),
      );
      expect(
        countTitleLines(output, FirebaseProjectStep.addFirebaseConfirmTitle),
        0,
      );
      expect(
        terminal.asks.where((String ask) => ask == waitForEnterMessage),
        hasLength(1),
      );
      expect(output, contains('  ✓ ${FirebaseProjectStep.stepTitle} — '));
      expect(readConfigProjectId(), suggestedId);
    },
  );

  test(
    'T-19-PROJ-15 기존 프로젝트 고르기는 기본값이 없어 Enter 만으로 고르지 않고 번호를 직접 받는다',
    () async {
      CommandResult buildPickList() => buildProjectsResult(
        const <String, String>{'demo-dev': '데모 프로젝트', 'mine-dev': 'Mine'},
      );

      // 빈 답 3번 — 고르지 않고 멈추며 파일은 그대로다.
      writeProjectFixture(root);
      final Map<String, String> before = readProjectFiles();
      final stopped = FakeCommandRunner()
        ..on(_gitStatusKey, _cleanTree)
        ..on(_projectsListKey, buildPickList());
      final stoppedTerminal = ScriptedTerminal(const <String?>[
        'y',
        '2',
        '',
        '',
        '',
      ]);

      final int stoppedCode = await runProjectStep(stopped, stoppedTerminal);

      expect(stoppedCode, wizardExitStopped);
      expect(stoppedTerminal.asks, contains(FirebaseProjectStep.pickQuestion));
      expect(readProjectFiles(), before);

      // 빈 답 한 번 뒤 2 — 둘째 프로젝트를 기록한다.
      final runner = FakeCommandRunner()
        ..on(_gitStatusKey, _cleanTree)
        ..on(_projectsListKey, buildPickList());
      final terminal = ScriptedTerminal(const <String?>['y', '2', '', '2']);

      final int code = await runProjectStep(runner, terminal);

      expect(code, wizardExitDone);
      expect(readConfigProjectId(), 'mine-dev');
      expect(readAliases()['default'], 'mine-dev');
      expect(
        terminal.output.toString(),
        contains('  ✓ ${FirebaseProjectStep.stepTitle} — mine-dev'),
      );
    },
  );

  test(
    'T-19-PROJ-16 Firebase 추가 콘솔 안내는 화면 원문 라벨만 순서대로 쓰고 애널리틱스를 켜 둔 경우의 약관 체크를 6단계로 알린다',
    () {
      final String guide = FirebaseProjectStep.buildAddFirebaseGuide(
        suggestedId,
      );
      final List<String> lines = guide.split('\n');
      final List<String> labels = RegExp(
        '「([^」]+)」',
      ).allMatches(guide).map((RegExpMatch match) => match.group(1)!).toList();
      final List<int> stepNumbers = RegExp(r'^ +([0-9]+)\. ', multiLine: true)
          .allMatches(guide)
          .map((RegExpMatch match) => int.parse(match.group(1)!))
          .toList();
      // 「[label]」 이 든 안내 줄의 위치를 모두 찾는다.
      List<int> findLabelLines(String label) => <int>[
        for (int index = 0; index < lines.length; index++)
          if (lines[index].contains('「$label」')) index,
      ];

      // 라벨은 화면 원문 목록과 순서까지 같고, 단계 번호는 1 ~ 7 연속이다.
      expect(labels, _consoleGuideLabels);
      expect(stepNumbers, <int>[1, 2, 3, 4, 5, 6, 7]);

      // 애널리틱스 화면 단계는 켜든 끄든 위저드 진행과 관계없다는 사실을 남긴다.
      final List<int> analyticsLines = findLabelLines(
        'Firebase 프로젝트를 위한 Google 애널리틱스',
      );
      expect(analyticsLines, hasLength(1));
      expect(lines[analyticsLines.single], contains('켜든 끄든 위저드 진행과 관계없습니다'));

      // 약관 체크 단계는 6단계 한 줄에 조건 · 화면 · 체크 · 버튼을 담는다.
      final List<int> termsLines = findLabelLines(_analyticsTermsLabel);
      expect(termsLines, hasLength(1));
      final String termsLine = lines[termsLines.single];
      expect(termsLine, startsWith('    6. '));
      expect(termsLine, contains('「이 프로젝트에서 Google 애널리틱스 사용 설정」'));
      expect(termsLine, contains('켜 둔 채'));
      expect(termsLine, contains('「Google 애널리틱스 구성」'));
      expect(termsLine, contains('체크해야'));
      expect(termsLine, contains('「Firebase 추가」'));

      // 줄 순서: 애널리틱스 화면 < 약관 체크 < 준비 완료.
      final List<int> readyLines = findLabelLines('Firebase 프로젝트가 준비되었습니다.');
      expect(readyLines, hasLength(1));
      expect(analyticsLines.single, lessThan(termsLines.single));
      expect(termsLines.single, lessThan(readyLines.single));

      // 첫 줄 · 콘솔 주소 · 프로젝트 ID · 끝 줄은 그대로다.
      expect(
        lines.first,
        '  Firebase 를 추가하지 못했습니다 — 처음 쓰는 Google 계정이면 '
        'Firebase 콘솔에서 이 프로젝트에 Firebase 를 추가하면서 약관에 동의해야 '
        '합니다.',
      );
      expect(guide, contains('https://console.firebase.google.com/'));
      expect(guide, contains(suggestedId));
      expect(lines.last, '  다 끝내고 Enter 를 누르면 위저드가 $suggestedId 를 다시 확인합니다.');
    },
  );

  group('T-19-PROJ-17 값 표 재확인 안내는 확인 표를 보이는 모드에서만 붙는다', () {
    test('T-19-PROJ-17 Firebase 추가 모드는 안내가 붙는다', () async {
      writeProjectFixture(
        root,
        projectId: existingId,
        aliases: matchingAliases,
      );
      final FakeCommandRunner runner = buildAddFirebaseRunner(
        lists: <CommandResult>[listWithout],
      );
      final terminal = ScriptedTerminal(const <String?>['n']);

      final int code = await runProjectStep(runner, terminal);

      final output = terminal.output.toString();
      expect(code, wizardExitStopped);
      expect(output, contains('▶ ${FirebaseProjectStep.stepTitle}'));
      expect(output.contains('    $costlyStepNotice'), isTrue);
    });

    test('T-19-PROJ-17 내 목록에 없는 실패 전용 모드는 안내가 붙지 않는다', () async {
      writeProjectFixture(root, projectId: existingId);
      final runner = FakeCommandRunner()
        ..on(
          _projectsListKey,
          buildProjectsResult(const <String, String>{'other-dev': 'Other'}),
        )
        ..on(describeKey(existingId), _notFound);
      final terminal = ScriptedTerminal(const <String?>['y']);

      final int code = await runProjectStep(runner, terminal);

      final output = terminal.output.toString();
      const reason = '$existingId 가 내 계정의 Firebase 프로젝트 목록에 없습니다';
      expect(code, wizardExitStopped);
      // 단계 머리 사유가 제목의 모드를 고정한다 — 안내 없는 다른 모드로
      // 바뀌어도 통과하지 않게 한다.
      expect(output, contains('▶ ${FirebaseProjectStep.stepTitle}\n  $reason'));
      expect(output.contains('    $costlyStepNotice'), isFalse);
    });
  });

  group('Firebase 추가 직후 프로젝트 목록 반영 대기', () {
    test('T-20-PROJ-01: 추가 뒤 목록에 늦게 보이면 정한 간격으로 다시 확인하다가 '
        '보이는 순간 ✓ 이고 실패 질문은 없다', () async {
      writeProjectFixture(
        root,
        projectId: existingId,
        aliases: matchingAliases,
      );
      // 목록 = 점검표 검사(없음) → 단계 머리(없음) → 추가 뒤 1차(없음) →
      // 2차(없음) → 3차(있음) → 실행 뒤 재검사(있음 되풀이).
      final FakeCommandRunner runner = buildAddFirebaseRunner(
        lists: <CommandResult>[
          listWithout,
          listWithout,
          listWithout,
          listWithout,
          listWith,
        ],
      );
      final delays = <Duration>[];
      final step = FirebaseProjectStep(
        delay: (Duration duration) async {
          delays.add(duration);
        },
      );
      final terminal = ScriptedTerminal(const <String?>['y', 'y']);

      final int code = await runProjectStep(runner, terminal, step: step);

      final output = terminal.output.toString();
      expect(code, wizardExitDone, reason: output);
      expect(delays, <Duration>[
        FirebaseProjectStep.listPollInterval,
        FirebaseProjectStep.listPollInterval,
      ]);
      expect(
        RegExp(
          RegExp.escape(FirebaseProjectStep.listWaitLine),
        ).allMatches(output).length,
        1,
      );
      expect(
        output,
        contains('  ✓ ${FirebaseProjectStep.stepTitle} — $existingId'),
      );
      expect(terminal.asks, isNot(contains(failureChoiceQuestion)));
      expect(output, isNot(contains(retryOption)));
      expect(runner.countCalls(RunMode.stream, addFirebaseKey(existingId)), 1);
    });

    test('T-20-PROJ-02: 정한 횟수 안에 끝내 안 보이면 지금처럼 재검사 실패 · '
        '실패 질문(기본값 [2])이고 빈 입력이면 멈춘다', () async {
      writeProjectFixture(
        root,
        projectId: existingId,
        aliases: matchingAliases,
      );
      final FakeCommandRunner runner = buildAddFirebaseRunner(
        lists: <CommandResult>[listWithout],
      );
      final delays = <Duration>[];
      final step = FirebaseProjectStep(
        delay: (Duration duration) async {
          delays.add(duration);
        },
      );
      final output = StringBuffer();
      final stopwatch = Stopwatch()..start();

      final int code = await runProjectStepOnStdio(
        runner,
        const <String>['y', 'y', ''],
        output,
        step,
      );

      stopwatch.stop();
      final shown = output.toString();
      expect(code, wizardExitStopped, reason: shown);
      expect(
        delays,
        List<Duration>.filled(
          FirebaseProjectStep.maxListPolls - 1,
          FirebaseProjectStep.listPollInterval,
        ),
      );
      expect(delays, hasLength(11));
      expect(
        RegExp(
          RegExp.escape(FirebaseProjectStep.listWaitLine),
        ).allMatches(shown).length,
        1,
      );
      expect(shown, contains('  실패 — $existingId 에 아직 Firebase 가 추가되지 않았습니다'));
      expect(
        shown,
        contains(
          '$failureChoiceQuestion\n  1) $retryOption\n  2) $stopOption\n'
          '번호를 고르세요 [2]: ',
        ),
      );
      expect(runner.countCalls(RunMode.stream, addFirebaseKey(existingId)), 1);
      expect(stopwatch.elapsed, lessThan(const Duration(seconds: 10)));
    });

    group('T-20-PROJ-03: 첫 확인에서 보이면 기다리지 않고 계획 줄에 반영 대기 안내가 붙는다', () {
      test('T-20-PROJ-03: 새로 만들기 → 추가 뒤 첫 확인에서 있음 → 대기 0 · 대기 안내 줄 0 · '
          '✓ · 계획 줄 안내 1개', () async {
        writeProjectFixture(root);
        final runner = FakeCommandRunner()
          ..on(_gitStatusKey, _cleanTree)
          ..on(describeKey(suggestedId), _notFound)
          ..on(createKey(suggestedId), _ok)
          ..on(addFirebaseKey(suggestedId), _ok)
          ..on(
            _projectsListKey,
            buildProjectsResult(const <String, String>{
              suggestedId: suggestedId,
            }),
          );
        final delays = <Duration>[];
        final step = FirebaseProjectStep(
          delay: (Duration duration) async {
            delays.add(duration);
          },
        );
        final terminal = ScriptedTerminal(const <String?>['y', '1', '', 'y']);

        final int code = await runProjectStep(runner, terminal, step: step);

        final output = terminal.output.toString();
        expect(code, wizardExitDone, reason: output);
        expect(delays, isEmpty);
        expect(output, isNot(contains(FirebaseProjectStep.listWaitLine)));
        expect(
          output,
          contains('  ✓ ${FirebaseProjectStep.stepTitle} — $suggestedId'),
        );
        expect(
          RegExp(
            RegExp.escape(FirebaseProjectStep.listWaitPlanLine),
          ).allMatches(output).length,
          1,
        );
        expect(terminal.asks, isNot(contains(failureChoiceQuestion)));
        // 화면 문구 원문 — 숫자는 간격 · 횟수 상수에서 나온다.
        const planLine =
            '(Firebase 를 추가한 뒤 프로젝트 목록에 보일 때까지 5초 간격으로 '
            '최대 55초 다시 확인합니다)';
        expect(FirebaseProjectStep.listWaitPlanLine, planLine);
        expect(
          FirebaseProjectStep.listWaitLine,
          '  Firebase 프로젝트 목록에 반영되기를 기다립니다(최대 55초)',
        );
      });

      test(
        'T-20-PROJ-03: Firebase 추가 모드 계획 줄에도 안내가 하나 붙고 별칭 쓰기 모드 줄은 그대로다',
        () async {
          writeProjectFixture(
            root,
            projectId: existingId,
            aliases: matchingAliases,
          );
          final step = FirebaseProjectStep();
          final WizardContext addContext = buildTestContext(
            projectRoot: root,
            runner: buildAddFirebaseRunner(lists: <CommandResult>[listWithout]),
          );

          expect(await step.check(addContext), isA<Todo>());
          final List<String> addLines = step.plannedCommandLines(addContext);

          expect(addLines.first, addFirebaseKey(existingId));
          expect(
            addLines.where(
              (String line) => line == FirebaseProjectStep.listWaitPlanLine,
            ),
            hasLength(1),
          );

          writeProjectFixture(root, projectId: existingId);
          final WizardContext aliasContext = buildTestContext(
            projectRoot: root,
            runner: FakeCommandRunner()..on(_projectsListKey, listWith),
          );

          expect(await step.check(aliasContext), isA<Todo>());
          expect(step.plannedCommandLines(aliasContext), <String>[
            '(.firebaserc 의 default · dev 를 $existingId 로 씀)',
          ]);
        },
      );
    });
  });

  test('buildDevSteps 는 로그인 다음에 프로젝트 단계를 둔다', () {
    final List<String> ids = buildDevSteps()
        .map((Step step) => step.id)
        .toList();

    expect(ids.indexOf('firebase_project'), ids.indexOf('login') + 1);
  });

  group('flavor 문맥', () {
    /// stg 프로젝트 ID(가짜).
    const stgId = 'acme-stg';
    late FakeCommandRunner runner;
    late ScriptedTerminal screen;

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

    /// stg config 를 example 에서 만들고 [projectId] 가 있으면 그 값으로 둔다.
    void writeStgConfig({String? projectId}) {
      const paths = FlavorPaths(Flavor.stg);
      File(paths.jsonExample).copySync('$root/${paths.json}');
      if (projectId != null) {
        replaceJsonString(
          '$root/${paths.json}',
          'firebaseProjectId',
          projectId,
        );
      }
    }

    /// stg config 의 프로젝트 ID.
    String readStgProjectId() => readJsonString(
      '$root/${const FlavorPaths(Flavor.stg).json}',
      'firebaseProjectId',
    )!;

    setUp(() {
      runner = FakeCommandRunner()..on(_gitStatusKey, _cleanTree);
    });

    test(
      'T-20-FLAVOR-11: stg 프로젝트를 고르면 .firebaserc 에 stg 별칭만 더하고 default · dev 와 다른 별칭은 그대로다',
      () async {
        writeProjectFixture(
          root,
          projectId: existingId,
          aliases: const <String, String>{
            'default': existingId,
            'dev': existingId,
            'qa': 'acme-qa',
          },
        );
        writeStgConfig();
        final List<int> devConfigBefore = File(
          '$root/${UserFilesStep.jsonUserPath}',
        ).readAsBytesSync();
        runner.on(
          _projectsListKey,
          buildProjectsResult(const <String, String>{
            existingId: 'Acme Dev',
            stgId: 'Acme Stg',
          }),
        );
        final WizardContext context = buildFlavorContext(
          Flavor.stg,
          const <String?>['2', '2'],
        );
        final step = FirebaseProjectStep();

        expect(await step.check(context), isA<Todo>());
        final List<String> lines = step.plannedCommandLines(context);
        final StepOutcome outcome = await step.apply(context);

        expect(
          lines,
          contains(
            '(config/stg.json 의 firebaseProjectId · .firebaserc 의 '
            'stg 를 정한 ID 로 씀)',
          ),
        );
        expect(outcome, isA<Applied>());
        expect(readStgProjectId(), stgId);
        expect(readAliases(), <String, Object?>{
          'default': existingId,
          'dev': existingId,
          'qa': 'acme-qa',
          'stg': stgId,
        });
        expect(
          File('$root/${UserFilesStep.jsonUserPath}').readAsBytesSync(),
          devConfigBefore,
        );
        // 재검사는 stg 별칭만 본다.
        expect(
          await step.check(context),
          isA<Done>().having((Done done) => done.summary, 'summary', stgId),
        );
      },
    );

    test(
      'T-20-FLAVOR-11: stg config 의 ID 가 목록에 있고 stg 별칭만 없으면 stg 별칭만 쓰는 할 일이다',
      () async {
        writeProjectFixture(
          root,
          projectId: existingId,
          aliases: const <String, String>{
            'default': existingId,
            'dev': existingId,
          },
        );
        writeStgConfig(projectId: stgId);
        runner.on(
          _projectsListKey,
          buildProjectsResult(const <String, String>{stgId: 'Acme Stg'}),
        );
        final WizardContext context = buildFlavorContext(
          Flavor.stg,
          const <String?>[],
        );
        final step = FirebaseProjectStep();

        final CheckResult before = await step.check(context);
        final List<String> lines = step.plannedCommandLines(context);
        final StepOutcome outcome = await step.apply(context);

        expect(
          before,
          isA<Todo>().having(
            (Todo todo) => todo.reason,
            'reason',
            '.firebaserc 의 stg 가 $stgId 가 아닙니다',
          ),
        );
        expect(lines, <String>['(.firebaserc 의 stg 를 $stgId 로 씀)']);
        expect(outcome, isA<Applied>());
        expect(readAliases(), <String, Object?>{
          'default': existingId,
          'dev': existingId,
          'stg': stgId,
        });
        expect(await step.check(context), isA<Done>());
        expect(screen.asks, isEmpty);
      },
    );

    test(
      'T-20-FLAVOR-12: stg 문맥에서 .firebaserc 가 없으면 stg 별칭 하나만 담아 만들고 default 는 만들지 않는다',
      () async {
        writeProjectFixture(root, projectId: existingId);
        File('$root/.firebaserc').deleteSync();
        writeStgConfig(projectId: stgId);
        runner.on(
          _projectsListKey,
          buildProjectsResult(const <String, String>{stgId: 'Acme Stg'}),
        );
        final WizardContext context = buildFlavorContext(
          Flavor.stg,
          const <String?>[],
        );
        final step = FirebaseProjectStep();

        expect(await step.check(context), isA<Todo>());
        expect(await step.apply(context), isA<Applied>());

        expect(readAliases(), <String, Object?>{'stg': stgId});
        expect(await step.check(context), isA<Done>());
      },
    );

    test('T-20-FLAVOR-13: stg 자리표시는 미설정이고 새로 만들기 제안 ID 는 -stg 로 끝난다', () async {
      writeProjectFixture(root, projectId: existingId);
      writeStgConfig();
      final List<int> firebasercBefore = File(
        '$root/.firebaserc',
      ).readAsBytesSync();
      final WizardContext context = buildFlavorContext(
        Flavor.stg,
        const <String?>['1', '', 'n'],
      );
      final step = FirebaseProjectStep();

      final CheckResult before = await step.check(context);
      final StepOutcome outcome = await step.apply(context);

      expect(readStgProjectId(), Flavor.stg.placeholderProjectId);
      expect(
        before,
        isA<Todo>().having(
          (Todo todo) => todo.reason,
          'reason',
          'Firebase 프로젝트가 아직 정해지지 않았습니다',
        ),
      );
      expect(outcome, isA<Declined>());
      expect(screen.asks, <String>[
        FirebaseProjectStep.projectChoiceQuestion,
        FirebaseProjectStep.idQuestion,
        summaryConfirmQuestion,
      ]);
      const suggested = '$fixturePrefix-stg';
      expect(suggested, endsWith(Flavor.stg.projectIdSuffix));
      expect(screen.output.toString(), contains(suggested));
      // 목록을 읽지 않았고 거절 뒤 어떤 파일도 바뀌지 않았다.
      expect(runner.countCalls(RunMode.capture, _projectsListKey), 0);
      expect(readStgProjectId(), Flavor.stg.placeholderProjectId);
      expect(File('$root/.firebaserc').readAsBytesSync(), firebasercBefore);
    });

    test('T-20-FLAVOR-15: dev 문맥의 자리표시 · 제안 접미사 · 안내문 · 별칭 줄은 그대로다', () async {
      expect(FirebaseProjectStep.placeholderProjectId, 'your-project-dev');
      expect(FirebaseProjectStep.devSuffix, '-dev');
      expect(
        FirebaseProjectStep.accountPermissionGuidance,
        '로그인한 계정이 이 프로젝트에 접근할 수 있는지(계정 · 권한) 확인하세요 — '
        '다른 프로젝트를 쓰려면 config/dev.json 의 firebaseProjectId 를 고친 뒤 '
        '다시 실행하세요',
      );
      writeProjectFixture(root, projectId: existingId);
      runner.on(
        _projectsListKey,
        buildProjectsResult(const <String, String>{existingId: 'Acme Dev'}),
      );
      final WizardContext context = buildFlavorContext(
        Flavor.dev,
        const <String?>[],
      );
      final step = FirebaseProjectStep();

      expect(
        await step.check(context),
        isA<Todo>().having(
          (Todo todo) => todo.reason,
          'reason',
          '.firebaserc 의 default · dev 가 $existingId 가 아닙니다',
        ),
      );
      expect(step.plannedCommandLines(context), <String>[
        '(.firebaserc 의 default · dev 를 $existingId 로 씀)',
      ]);
    });
  });
}
