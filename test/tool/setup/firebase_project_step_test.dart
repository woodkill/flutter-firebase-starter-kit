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

/// 처음 쓰는 계정에서 `firebase projects:addfirebase` 가 실패할 때 화면에 남는 한 줄.
const CommandResult _addFirebaseFailed = CommandResult(
  2,
  '',
  'Error: Failed to add Firebase to Google Cloud Platform project. '
      'See firebase-debug.log for more info.\n',
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
        )
        ..on(describeKey(existingId), _notFound);
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

  test('T-19-PROJ-10 만들기 실패(Cloud 약관 미동의)는 원문과 Cloud 콘솔 약관 안내만 보인다', () async {
    writeProjectFixture(root);
    const String terms =
        'Operation [create_project.global.100200300] failed: 9: '
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
      final FakeCommandRunner stopped = FakeCommandRunner()
        ..on(_gitStatusKey, _cleanTree)
        ..on(describeKey(suggestedId), _notFound)
        ..on(createKey(suggestedId), _ok)
        ..on(addFirebaseKey(suggestedId), _addFirebaseFailed);
      final ScriptedTerminal stoppedTerminal = ScriptedTerminal(const <String?>[
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
      final FakeCommandRunner runner = FakeCommandRunner()
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
      final ScriptedTerminal terminal = ScriptedTerminal(const <String?>[
        'y',
        '1',
        '',
        'y',
        '',
        '',
      ]);

      final int code = await runProjectStep(runner, terminal);

      final String output = terminal.output.toString();
      final String guide = FirebaseProjectStep.buildAddFirebaseGuide(
        suggestedId,
      );
      int countAsks(String question) =>
          terminal.asks.where((String ask) => ask == question).length;
      expect(code, wizardExitDone);
      expect(output, contains(guide));
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
    final FakeCommandRunner runner = FakeCommandRunner()
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
  const Map<String, String> matchingAliases = <String, String>{
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
        final ScriptedTerminal terminal = ScriptedTerminal(const <String?>[
          'y',
          'y',
        ]);

        final int code = await runProjectStep(runner, terminal);

        final String output = terminal.output.toString();
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
        final ScriptedTerminal terminal = ScriptedTerminal(const <String?>[
          'y',
          '',
        ]);

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
        final ScriptedTerminal terminal = ScriptedTerminal(const <String?>[
          'y',
        ]);

        final int code = await runProjectStep(runner, terminal);

        final String output = terminal.output.toString();
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
        final ScriptedTerminal terminal = ScriptedTerminal(const <String?>[
          'y',
          'y',
        ]);

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
        final ScriptedTerminal declinedTerminal = ScriptedTerminal(
          const <String?>['y', 'n'],
        );

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
      final ScriptedTerminal firstTerminal = ScriptedTerminal(const <String?>[
        'y',
        'y',
      ]);

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
      final ScriptedTerminal secondTerminal = ScriptedTerminal(const <String?>[
        'y',
        'y',
      ]);

      final int secondCode = await runProjectStep(second, secondTerminal);

      final String output = secondTerminal.output.toString();
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
      final FakeCommandRunner runner = FakeCommandRunner()
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
      final ScriptedTerminal terminal = ScriptedTerminal(const <String?>[
        'y',
        '1',
        '',
        'y',
        '',
      ]);

      final int code = await runProjectStep(runner, terminal);

      final String output = terminal.output.toString();
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

  test('buildDevSteps 는 로그인 다음에 프로젝트 단계를 둔다', () {
    final List<String> ids = buildDevSteps()
        .map((Step step) => step.id)
        .toList();

    expect(ids.indexOf('firebase_project'), ids.indexOf('login') + 1);
  });
}
