import 'dart:io';

import 'package:test/test.dart';

import '../../../bin/rename.dart' as rename;
import '../../../tool/setup/command_runner.dart';
import '../../../tool/setup/config_files.dart';
import '../../../tool/setup/git_tree.dart';
import '../../../tool/setup/step.dart';
import '../../../tool/setup/steps/dev_steps.dart';
import '../../../tool/setup/steps/identity_step.dart';
import '../../../tool/setup/steps/user_files_step.dart';
import '../../../tool/setup/wizard.dart';
import 'fakes.dart';

const String _gitStatusKey = 'git status --porcelain --untracked-files=no';
const CommandResult _cleanTree = CommandResult(0, '', '');

/// 킷 Kotlin 패키지 디렉터리(저장소 상대) — rename 상수로 조립한다.
final String kitKotlinDir =
    'android/app/src/main/kotlin/'
    '${rename.currentOrg.replaceAll('.', '/')}/${rename.currentPackageName}';

/// [root] 아래에 앱 정체성 단계가 읽고 고치는 파일 fixture 를 쓴다.
///
/// 사용자 설정 파일은 추적되는 example 을 복사해 만든다.
void writeIdentityFixture(
  String root, {
  String applicationId = rename.currentAndroidPackage,
}) {
  void writeFile(String relativePath, String content) {
    File('$root/$relativePath')
      ..parent.createSync(recursive: true)
      ..writeAsStringSync(content);
  }

  writeFile(
    IdentityStep.gradlePath,
    'android {\n'
    '    namespace = "$applicationId"\n'
    '\n'
    '    defaultConfig {\n'
    '        applicationId = "$applicationId"\n'
    '    }\n'
    '}\n',
  );
  writeFile(
    '$kitKotlinDir/MainActivity.kt',
    'package ${rename.currentAndroidPackage}\n\nclass MainActivity\n',
  );
  writeFile(
    'ios/Runner.xcodeproj/project.pbxproj',
    'PRODUCT_BUNDLE_IDENTIFIER = ${rename.currentIosBundleId}.dev;\n',
  );
  writeFile(
    'scripts/firebase-configure.sh',
    '#!/usr/bin/env bash\n'
        'PROJECT_ID_PREFIX="${rename.currentProjectIdPrefix}"\n'
        'IOS_BUNDLE_ID_PREFIX="${rename.currentIosBundleId}"\n'
        'ANDROID_PACKAGE_PREFIX="${rename.currentAndroidPackage}"\n',
  );
  for (final String path in <String>[
    UserFilesStep.jsonExamplePath,
    UserFilesStep.xcconfigExamplePath,
  ]) {
    Directory('$root/$path').parent.createSync(recursive: true);
    File(path).copySync('$root/$path');
  }
  File(
    '$root/${UserFilesStep.jsonExamplePath}',
  ).copySync('$root/${UserFilesStep.jsonUserPath}');
  File(
    '$root/${UserFilesStep.xcconfigExamplePath}',
  ).copySync('$root/${UserFilesStep.xcconfigUserPath}');
}

/// [root] 아래 모든 파일의 저장소 상대 경로 → 바이트 사본을 만든다.
Map<String, List<int>> snapshotTree(String root) => <String, List<int>>{
  for (final File file in Directory(
    root,
  ).listSync(recursive: true).whereType<File>())
    file.path.substring(root.length + 1): file.readAsBytesSync(),
};

void main() {
  late Directory tempDir;
  late String root;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('identity_step_test_');
    root = tempDir.path;
  });

  tearDown(() {
    tempDir.deleteSync(recursive: true);
  });

  String readFile(String relativePath) =>
      File('$root/$relativePath').readAsStringSync();

  /// 사용자 설정 파일 · 앱 정체성 단계로 위저드를 돌린다.
  Future<int> runIdentityStep(
    FakeCommandRunner runner,
    ScriptedTerminal terminal,
  ) => runWizard(
    buildTestContext(projectRoot: root, runner: runner, terminal: terminal),
    <Step>[UserFilesStep(), IdentityStep()],
  );

  test(
    'T-19-ID-01 org · name 두 값과 확인 한 번으로 앱 ID · 번들 ID · prefix · 표시 이름이 바뀐다',
    () async {
      writeIdentityFixture(root);
      final FakeCommandRunner runner = FakeCommandRunner()
        ..on(_gitStatusKey, _cleanTree);
      final ScriptedTerminal terminal = ScriptedTerminal(const <String?>[
        'y',
        'com.acme',
        'my_app',
        '1',
        'y',
      ]);

      final int code = await runIdentityStep(runner, terminal);

      final String output = terminal.output.toString();
      expect(code, wizardExitDone);
      expect(output, contains('  ✗ 앱 정체성 — '));
      expect(output, contains('── ${IdentityStep.confirmTitle} ──'));
      expect(output, contains('  ! ${IdentityStep.storeWarning}'));
      expect(output, contains('com.acme.my_app(.dev)'));
      expect(output, contains('com.acme.myApp(.dev)'));
      expect(output, contains('  ✓ 앱 정체성 — Android 앱 ID com.acme.my_app'));
      expect(
        readFile(IdentityStep.gradlePath),
        contains('applicationId = "com.acme.my_app"'),
      );
      expect(
        readFile('scripts/firebase-configure.sh'),
        contains('PROJECT_ID_PREFIX="my-app"'),
      );
      expect(
        readJsonString('$root/${UserFilesStep.jsonUserPath}', 'appName'),
        'My App Dev',
      );
      expect(
        readXcconfigValue(
          '$root/${UserFilesStep.xcconfigUserPath}',
          'DISPLAY_NAME',
        ),
        'My App Dev',
      );
      expect(
        readXcconfigValue(
          '$root/${UserFilesStep.xcconfigUserPath}',
          'PRODUCT_BUNDLE_IDENTIFIER',
        ),
        'com.acme.myApp.dev',
      );
      expect(
        readFile('android/app/src/main/kotlin/com/acme/my_app/MainActivity.kt'),
        startsWith('package com.acme.my_app\n'),
      );
      // 예제 파일은 바꾸지 않는다.
      expect(
        File('$root/${UserFilesStep.jsonExamplePath}').readAsBytesSync(),
        File(UserFilesStep.jsonExamplePath).readAsBytesSync(),
      );
      expect(runner.countCalls(RunMode.capture, _gitStatusKey), 1);
    },
  );

  test('T-19-ID-02 확인 표에서 Enter 면 진행하지 않고 파일을 하나도 바꾸지 않는다', () async {
    writeIdentityFixture(root);
    final Map<String, List<int>> before = snapshotTree(root);
    final FakeCommandRunner runner = FakeCommandRunner()
      ..on(_gitStatusKey, _cleanTree);
    final ScriptedTerminal terminal = ScriptedTerminal(const <String?>[
      'y',
      'com.acme',
      'my_app',
      '1',
      '',
    ]);

    final int code = await runIdentityStep(runner, terminal);

    expect(code, wizardExitStopped);
    expect(snapshotTree(root), before);
    expect(runner.countCalls(RunMode.capture, _gitStatusKey), 0);
  });

  test('T-19-ID-03 프로젝트 prefix 를 고칠 수 있고 잘못된 prefix 는 오류 뒤 다시 묻는다', () async {
    writeIdentityFixture(root);
    final FakeCommandRunner runner = FakeCommandRunner()
      ..on(_gitStatusKey, _cleanTree);
    final ScriptedTerminal terminal = ScriptedTerminal(const <String?>[
      'y',
      'com.acme',
      'my_app',
      '2',
      'Acme_App',
      'acme-app',
      '1',
      'y',
    ]);

    final int code = await runIdentityStep(runner, terminal);

    final String output = terminal.output.toString();
    expect(code, wizardExitDone);
    expect(output, contains(IdentityStep.invalidPrefixMessage));
    expect(
      terminal.asks.where((String ask) => ask == IdentityStep.prefixQuestion),
      hasLength(2),
    );
    expect(
      readFile('scripts/firebase-configure.sh'),
      contains('PROJECT_ID_PREFIX="acme-app"'),
    );
  });

  test('T-19-ID-04 표시 이름은 영숫자 · 공백만 받는다', () async {
    writeIdentityFixture(root);
    final FakeCommandRunner runner = FakeCommandRunner()
      ..on(_gitStatusKey, _cleanTree);
    final ScriptedTerminal terminal = ScriptedTerminal(const <String?>[
      'y',
      'com.acme',
      'my_app',
      '3',
      'My-App!',
      'Acme Studio',
      '1',
      'y',
    ]);

    final int code = await runIdentityStep(runner, terminal);

    expect(code, wizardExitDone);
    expect(
      terminal.output.toString(),
      contains(IdentityStep.invalidDisplayNameMessage),
    );
    expect(
      readJsonString('$root/${UserFilesStep.jsonUserPath}', 'appName'),
      'Acme Studio',
    );
    expect(
      readXcconfigValue(
        '$root/${UserFilesStep.xcconfigUserPath}',
        'DISPLAY_NAME',
      ),
      'Acme Studio',
    );
  });

  group('T-19-ID-05 고칠 tracked 파일의 미커밋 변경', () {
    test('T-19-ID-05 고칠 파일이 바뀌어 있으면 그 경로를 보이고 멈춘다', () async {
      writeIdentityFixture(root);
      final Map<String, List<int>> before = snapshotTree(root);
      final FakeCommandRunner runner = FakeCommandRunner()
        ..on(
          _gitStatusKey,
          const CommandResult(0, ' M android/app/build.gradle.kts\n', ''),
        );
      final ScriptedTerminal terminal = ScriptedTerminal(const <String?>[
        'y',
        'com.acme',
        'my_app',
        '1',
        'y',
      ]);

      final int code = await runIdentityStep(runner, terminal);

      final String output = terminal.output.toString();
      expect(code, wizardExitStopped);
      expect(output, contains('  실패 — '));
      expect(output, contains('    android/app/build.gradle.kts'));
      expect(output, contains(IdentityStep.dirtyTreeGuidance));
      expect(snapshotTree(root), before);
    });

    test('T-19-ID-05 고칠 파일 밖의 변경은 막지 않는다', () async {
      writeIdentityFixture(root);
      final FakeCommandRunner runner = FakeCommandRunner()
        ..on(_gitStatusKey, const CommandResult(0, ' M README.md\n', ''));
      final ScriptedTerminal terminal = ScriptedTerminal(const <String?>[
        'y',
        'com.acme',
        'my_app',
        '1',
        'y',
      ]);

      final int code = await runIdentityStep(runner, terminal);

      expect(code, wizardExitDone);
      expect(
        readFile(IdentityStep.gradlePath),
        contains('applicationId = "com.acme.my_app"'),
      );
    });
  });

  group('T-19-ID-06 앱 ID 는 바뀌었고 표시 이름만 기본값', () {
    test('T-19-ID-06 표시 이름만 묻고 두 곳에 쓴다', () async {
      writeIdentityFixture(root, applicationId: 'com.acme.my_app');
      final String gradleBefore = readFile(IdentityStep.gradlePath);
      final String configureBefore = readFile('scripts/firebase-configure.sh');
      final FakeCommandRunner runner = FakeCommandRunner();
      final ScriptedTerminal terminal = ScriptedTerminal(const <String?>[
        'y',
        'Acme Studio',
      ]);

      final int code = await runIdentityStep(runner, terminal);

      expect(code, wizardExitDone);
      expect(terminal.asks, <String>[
        stepConfirmQuestion,
        IdentityStep.displayNameQuestion,
      ]);
      expect(
        readJsonString('$root/${UserFilesStep.jsonUserPath}', 'appName'),
        'Acme Studio',
      );
      expect(
        readXcconfigValue(
          '$root/${UserFilesStep.xcconfigUserPath}',
          'DISPLAY_NAME',
        ),
        'Acme Studio',
      );
      // rename 을 부르지 않았다 — 앱 ID 파일 · 상수가 그대로이고 git 검사도 없다.
      expect(readFile(IdentityStep.gradlePath), gradleBefore);
      expect(readFile('scripts/firebase-configure.sh'), configureBefore);
      expect(runner.calls, isEmpty);
    });

    test('T-19-ID-06 Enter 면 앱 ID 에서 계산한 표시 이름을 쓴다', () async {
      writeIdentityFixture(root, applicationId: 'com.acme.my_app');
      final ScriptedTerminal terminal = ScriptedTerminal(const <String?>[
        'y',
        '',
      ]);

      final int code = await runIdentityStep(FakeCommandRunner(), terminal);

      expect(code, wizardExitDone);
      expect(
        readJsonString('$root/${UserFilesStep.jsonUserPath}', 'appName'),
        'My App Dev',
      );
    });
  });

  test('T-19-ID-07 이미 끝난 저장소는 ✓ 이고 아무것도 묻지 않는다', () async {
    writeIdentityFixture(root, applicationId: 'com.acme.my_app');
    replaceJsonString(
      '$root/${UserFilesStep.jsonUserPath}',
      'appName',
      'My App Dev',
    );
    replaceXcconfigValue(
      '$root/${UserFilesStep.xcconfigUserPath}',
      'DISPLAY_NAME',
      'My App Dev',
    );
    final ScriptedTerminal terminal = ScriptedTerminal(const <String?>[]);

    final int code = await runIdentityStep(FakeCommandRunner(), terminal);

    expect(code, wizardExitDone);
    expect(
      terminal.output.toString(),
      contains('  ✓ 앱 정체성 — Android 앱 ID com.acme.my_app'),
    );
    expect(terminal.asks, isEmpty);
  });

  test('T-19-ID-08 계획 줄에 같은 일을 하는 rename 명령과 표시 이름 쓰기 줄이 있다', () async {
    writeIdentityFixture(root);
    final WizardContext context = buildTestContext(projectRoot: root);
    final IdentityStep step = IdentityStep();

    await step.check(context);
    final List<String> lines = step.plannedCommandLines(context);

    expect(
      lines.where(
        (String line) => line.startsWith('fvm dart run bin/rename.dart --org'),
      ),
      hasLength(1),
    );
    expect(lines.where((String line) => line.contains('appName')), isNotEmpty);
    expect(
      lines.where((String line) => line.contains('DISPLAY_NAME')),
      isNotEmpty,
    );

    // 표시 이름만 남은 저장소는 rename 명령 줄이 없다.
    writeIdentityFixture(root, applicationId: 'com.acme.my_app');
    await step.check(context);
    expect(
      step
          .plannedCommandLines(context)
          .where((String line) => line.contains('bin/rename.dart')),
      isEmpty,
    );
  });

  group('T-19-ID-09 이동할 Kotlin 디렉터리 안의 변경', () {
    test('T-19-ID-09 디렉터리 안 파일이 바뀌어 있으면 그 경로를 보이고 멈춘다', () async {
      writeIdentityFixture(root);
      final Map<String, List<int>> before = snapshotTree(root);
      final FakeCommandRunner runner = FakeCommandRunner()
        ..on(
          _gitStatusKey,
          CommandResult(0, ' M $kitKotlinDir/MainActivity.kt\n', ''),
        );
      final ScriptedTerminal terminal = ScriptedTerminal(const <String?>[
        'y',
        'com.acme',
        'my_app',
        '1',
        'y',
      ]);

      final int code = await runIdentityStep(runner, terminal);

      final String output = terminal.output.toString();
      expect(code, wizardExitStopped);
      expect(output, contains('    $kitKotlinDir/MainActivity.kt'));
      expect(snapshotTree(root), before);
    });

    test('T-19-ID-09 디렉터리 항목은 그 아래 파일만 잡고 앞부분만 같은 형제는 잡지 않는다', () async {
      final FakeCommandRunner runner = FakeCommandRunner()
        ..on(
          _gitStatusKey,
          CommandResult(
            0,
            ' M $kitKotlinDir/MainActivity.kt\n'
                ' M ${kitKotlinDir}_other/X.kt\n'
                'M  README.md\n',
            '',
          ),
        );
      final WizardContext context = buildTestContext(
        projectRoot: root,
        runner: runner,
      );

      expect(
        await findDirtyTrackedFiles(context, <String>[kitKotlinDir]),
        <String>['$kitKotlinDir/MainActivity.kt'],
      );
      expect(
        await findDirtyTrackedFiles(context, <String>['$kitKotlinDir/']),
        <String>['$kitKotlinDir/MainActivity.kt'],
      );
    });
  });

  group('git 작업 트리 읽기', () {
    test('이름 바꾸기 줄은 양쪽 경로를 · 따옴표 경로는 풀어서 본다', () async {
      final FakeCommandRunner runner = FakeCommandRunner()
        ..on(
          _gitStatusKey,
          const CommandResult(
            0,
            'R  docs/old.md -> android/app/build.gradle.kts\n'
                ' M "docs/\\355\\225\\234 \\"q\\".md"\n',
            '',
          ),
        );
      final WizardContext context = buildTestContext(
        projectRoot: root,
        runner: runner,
      );

      expect(await listChangedTrackedFiles(context), <String>[
        'docs/old.md',
        'android/app/build.gradle.kts',
        'docs/한 "q".md',
      ]);
      expect(
        await findDirtyTrackedFiles(context, <String>[
          'android/app/build.gradle.kts',
        ]),
        <String>['android/app/build.gradle.kts'],
      );
      expect(
        await findDirtyTrackedFiles(context, <String>['docs/old.md']),
        <String>['docs/old.md'],
      );
    });

    test('git 이 실패하면 GitTreeException 을 던진다', () async {
      final FakeCommandRunner runner = FakeCommandRunner()
        ..on(
          _gitStatusKey,
          const CommandResult(128, '', 'fatal: not a git repository'),
        );
      final WizardContext context = buildTestContext(
        projectRoot: root,
        runner: runner,
      );

      expect(
        () => findDirtyTrackedFiles(context, <String>['README.md']),
        throwsA(isA<GitTreeException>()),
      );
    });
  });

  test('buildDevSteps 는 Xcode 준비 → 개발 도구 → 사용자 설정 파일 → 앱 정체성 순서다', () {
    expect(buildDevSteps().map((Step step) => step.id).toList(), <String>[
      'xcode',
      'tools',
      'user_files',
      'identity',
    ]);
  });
}
