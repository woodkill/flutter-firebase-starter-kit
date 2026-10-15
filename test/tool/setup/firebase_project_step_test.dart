import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

import '../../../tool/setup/command_runner.dart';
import '../../../tool/setup/config_files.dart';
import '../../../tool/setup/confirm.dart';
import '../../../tool/setup/step.dart';
import '../../../tool/setup/steps/dev_steps.dart';
import '../../../tool/setup/steps/firebase_project_step.dart';
import '../../../tool/setup/steps/user_files_step.dart';
import '../../../tool/setup/wizard.dart';
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
  final File config = File('$root/${UserFilesStep.jsonUserPath}')
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
  for (final CommandResult result in results) {
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
  Future<int> runProjectStep(
    FakeCommandRunner runner,
    ScriptedTerminal terminal,
  ) => runWizard(
    buildTestContext(projectRoot: root, runner: runner, terminal: terminal),
    <Step>[
      _FinishedStep('login', 'Firebase · Google Cloud 로그인'),
      _FinishedStep('identity', '앱 정체성'),
      FirebaseProjectStep(),
    ],
  );

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
      final FakeCommandRunner runner = FakeCommandRunner()
        ..on(
          _projectsListKey,
          buildProjectsResult(const <String, String>{existingId: 'Acme Dev'}),
        );
      final ScriptedTerminal terminal = ScriptedTerminal(const <String?>[]);

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
      final FakeCommandRunner runner = FakeCommandRunner()
        ..on(
          _projectsListKey,
          buildProjectsResult(const <String, String>{'other-dev': 'Other'}),
        );
      final ScriptedTerminal terminal = ScriptedTerminal(const <String?>['y']);

      final int code = await runProjectStep(runner, terminal);

      final String output = terminal.output.toString();
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
      final FakeCommandRunner runner = FakeCommandRunner()
        ..on(_gitStatusKey, _cleanTree)
        ..on(describeKey(suggestedId), _notFound)
        ..on(createKey(suggestedId), _ok)
        ..on(addFirebaseKey(suggestedId), _ok)
        ..on(
          _projectsListKey,
          buildProjectsResult(const <String, String>{suggestedId: suggestedId}),
        );
      final ScriptedTerminal terminal = ScriptedTerminal(const <String?>[
        'y',
        '1',
        '',
        'y',
      ]);

      final int code = await runProjectStep(runner, terminal);

      final String output = terminal.output.toString();
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
    final Map<String, String> before = <String, String>{
      for (final String path in <String>[
        UserFilesStep.jsonUserPath,
        '.firebaserc',
      ])
        path: File('$root/$path').readAsStringSync(),
    };
    final FakeCommandRunner runner = FakeCommandRunner()
      ..on(_gitStatusKey, _cleanTree);
    final ScriptedTerminal terminal = ScriptedTerminal(const <String?>[
      'y',
      '1',
      '',
      'n',
    ]);

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
      final String tooLong = 'a${'b' * 30}';
      final FakeCommandRunner runner = FakeCommandRunner()
        ..on(_gitStatusKey, _cleanTree);
      final ScriptedTerminal terminal = ScriptedTerminal(<String?>[
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
      final FirebaseProjectStep step = FirebaseProjectStep();

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

  test(
    'T-19-PROJ-06 이미 쓰이는 ID 면 원문과 다른 ID 안내로 실패하고 다시 시도에서 새 ID 로 진행한다',
    () async {
      writeProjectFixture(root);
      const String retryId = 'my-app-dev2';
      const String conflict =
          'ERROR: (gcloud.projects.create) Resource in projects [my-app-dev] '
          'is the subject of a conflict: Requested entity already exists\n';
      final FakeCommandRunner runner = FakeCommandRunner()
        ..on(_gitStatusKey, _cleanTree)
        ..on(describeKey(suggestedId), _notFound)
        ..on(createKey(suggestedId), const CommandResult(1, '', conflict))
        ..on(describeKey(retryId), _notFound)
        ..on(createKey(retryId), _ok)
        ..on(addFirebaseKey(retryId), _ok)
        ..on(
          _projectsListKey,
          buildProjectsResult(const <String, String>{retryId: retryId}),
        );
      final ScriptedTerminal terminal = ScriptedTerminal(const <String?>[
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

      final String output = terminal.output.toString();
      expect(code, wizardExitDone);
      expect(output, contains(conflict));
      expect(output, contains(FirebaseProjectStep.idTakenGuidance));
      expect(listStreamKeys(runner), <String>[
        createKey(suggestedId),
        createKey(retryId),
        addFirebaseKey(retryId),
      ]);
      expect(readConfigProjectId(), retryId);
      expect(readAliases()['dev'], retryId);
    },
  );

  test('T-19-PROJ-07 내 계정에 이미 있는 프로젝트면 만들기를 건너뛰고 Firebase 추가만 한다', () async {
    writeProjectFixture(root);
    final FakeCommandRunner runner = FakeCommandRunner()
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
    final ScriptedTerminal terminal = ScriptedTerminal(const <String?>[
      'y',
      '1',
      '',
      'y',
    ]);

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
      final FakeCommandRunner runner = FakeCommandRunner()
        ..on(_gitStatusKey, _cleanTree)
        ..on(
          _projectsListKey,
          buildProjectsResult(const <String, String>{
            'first-dev': 'First',
            'second-dev': 'Second',
          }),
        );
      final ScriptedTerminal terminal = ScriptedTerminal(const <String?>[
        'y',
        '2',
        '2',
      ]);

      final int code = await runProjectStep(runner, terminal);

      final String output = terminal.output.toString();
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
      final FakeCommandRunner runner = FakeCommandRunner()
        ..on(_gitStatusKey, const CommandResult(0, ' M .firebaserc\n', ''));
      final ScriptedTerminal terminal = ScriptedTerminal(const <String?>['y']);

      final int code = await runProjectStep(runner, terminal);

      final String output = terminal.output.toString();
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

  test('T-19-PROJ-10 만들기 실패(약관 미동의 모양)는 원문과 약관 안내를 함께 보인다', () async {
    writeProjectFixture(root);
    const String terms =
        'ERROR: (gcloud.projects.create) FAILED_PRECONDITION: '
        'Callers must accept Terms of Service\n';
    final FakeCommandRunner runner = FakeCommandRunner()
      ..on(_gitStatusKey, _cleanTree)
      ..on(describeKey(suggestedId), _notFound)
      ..on(createKey(suggestedId), const CommandResult(1, '', terms));
    final ScriptedTerminal terminal = ScriptedTerminal(const <String?>[
      'y',
      '1',
      '',
      'y',
    ]);

    final int code = await runProjectStep(runner, terminal);

    final String output = terminal.output.toString();
    expect(code, wizardExitStopped);
    expect(output, contains(terms));
    expect(output, contains(FirebaseProjectStep.termsGuidance));
    expect(
      FirebaseProjectStep.termsGuidance,
      contains(
        'console.cloud.google.com 과 console.firebase.google.com 을 '
        '브라우저에서 한 번 열어 약관에 동의한 뒤 다시 시도하세요',
      ),
    );
    expect(runner.countCalls(RunMode.stream, addFirebaseKey(suggestedId)), 0);
    expect(readConfigProjectId(), 'your-project-dev');
  });

  test('buildDevSteps 는 로그인 다음에 프로젝트 단계를 둔다', () {
    final List<String> ids = buildDevSteps()
        .map((Step step) => step.id)
        .toList();

    expect(ids.indexOf('firebase_project'), ids.indexOf('login') + 1);
  });
}
