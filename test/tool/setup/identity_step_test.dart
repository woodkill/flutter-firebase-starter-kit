import 'dart:io';
import 'dart:math';

import 'package:test/test.dart';

import '../../../bin/rename.dart' as rename;
import '../../../tool/setup/command_runner.dart';
import '../../../tool/setup/config_files.dart';
import '../../../tool/setup/flavor.dart';
import '../../../tool/setup/git_tree.dart';
import '../../../tool/setup/redactor.dart';
import '../../../tool/setup/step.dart';
import '../../../tool/setup/steps/dev_steps.dart';
import '../../../tool/setup/steps/identity_step.dart';
import '../../../tool/setup/steps/user_files_step.dart';
import '../../../tool/setup/terminal.dart';
import '../../../tool/setup/wizard.dart';
import 'fake_rest_client.dart';
import 'fakes.dart';

const String _gitStatusKey = 'git status --porcelain --untracked-files=no';
const CommandResult _cleanTree = CommandResult(0, '', '');

/// 킷 Kotlin 패키지 디렉터리(저장소 상대) — rename 상수로 조립한다.
final String kitKotlinDir =
    'android/app/src/main/kotlin/'
    '${rename.currentOrg.replaceAll('.', '/')}/${rename.currentPackageName}';

/// 이름 바꾸기 규칙대로 [applicationId] 에서 iOS 번들 ID prefix 를 만든다.
String buildIosBundleIdPrefix(String applicationId) {
  final int nameStart = applicationId.lastIndexOf('.');
  // 점이 없는 앱 ID 는 org 가 없어 그대로 쓴다.
  if (nameStart < 0) return applicationId;
  return '${applicationId.substring(0, nameStart)}.'
      '${rename.toLowerCamelCase(applicationId.substring(nameStart + 1))}';
}

/// prefix 상수 3줄이 있는 configure 스크립트 fixture 본문을 만든다.
String buildConfigureScript({
  required String iosBundleIdPrefix,
  required String androidPackagePrefix,
}) =>
    '#!/usr/bin/env bash\n'
    'PROJECT_ID_PREFIX="${rename.currentProjectIdPrefix}"\n'
    'IOS_BUNDLE_ID_PREFIX="$iosBundleIdPrefix"\n'
    'ANDROID_PACKAGE_PREFIX="$androidPackagePrefix"\n';

/// [root] 아래 [relativePath] 에 [content] 를 쓴다 — 상위 디렉터리는 만든다.
void writeFixtureFile(String root, String relativePath, String content) {
  File('$root/$relativePath')
    ..parent.createSync(recursive: true)
    ..writeAsStringSync(content);
}

/// 킷 앱 ID 를 담은 stg 자리표시 `google-services.json` 의 최소 본문을 만든다.
///
/// 저장소의 stg 자리표시 파일 값과 무관하다 — 위저드로 앱 ID 를 바꾼 저장소에서도
/// 같은 본문이다. `package_name` 줄은 이름 바꾸기가 찾는 옛 값과 글자 그대로 같다.
String buildStgPlaceholderJson() =>
    '{\n'
    '  "project_info": {\n'
    '    "project_id": "placeholder-stg"\n'
    '  },\n'
    '  "client": [\n'
    '    {\n'
    '      "client_info": {\n'
    '        "android_client_info": {\n'
    '          "package_name": "${rename.currentAndroidPackage}.stg"\n'
    '        }\n'
    '      }\n'
    '    }\n'
    '  ]\n'
    '}\n';

/// [root] 아래에 앱 정체성 단계가 읽고 고치는 파일 fixture 를 쓴다.
///
/// 사용자 설정 파일은 추적되는 example 을 복사해 만든다. [applicationId] 가 킷
/// 기본값이 아니면 이름 바꾸기가 끝난 추적 파일 모양(Kotlin 디렉터리 이동 ·
/// pbxproj 번들 ID · 스크립트 상수)으로 쓰고, 킷 Kotlin 디렉터리는 지운다.
void writeIdentityFixture(
  String root, {
  String applicationId = rename.currentAndroidPackage,
}) {
  final isKitDefault = applicationId == rename.currentAndroidPackage;
  final String iosBundleIdPrefix = isKitDefault
      ? rename.currentIosBundleId
      : buildIosBundleIdPrefix(applicationId);
  final String kotlinDir = isKitDefault
      ? kitKotlinDir
      : 'android/app/src/main/kotlin/${applicationId.replaceAll('.', '/')}';
  final kitKotlin = Directory('$root/$kitKotlinDir');
  if (!isKitDefault && kitKotlin.existsSync()) {
    kitKotlin.deleteSync(recursive: true);
  }

  writeFixtureFile(
    root,
    IdentityStep.gradlePath,
    'android {\n'
    '    namespace = "$applicationId"\n'
    '\n'
    '    defaultConfig {\n'
    '        applicationId = "$applicationId"\n'
    '    }\n'
    '}\n',
  );
  writeFixtureFile(
    root,
    '$kotlinDir/MainActivity.kt',
    'package $applicationId\n\nclass MainActivity\n',
  );
  writeFixtureFile(
    root,
    'ios/Runner.xcodeproj/project.pbxproj',
    'PRODUCT_BUNDLE_IDENTIFIER = $iosBundleIdPrefix.dev;\n',
  );
  writeFixtureFile(
    root,
    'scripts/firebase-configure.sh',
    buildConfigureScript(
      iosBundleIdPrefix: iosBundleIdPrefix,
      androidPackagePrefix: applicationId,
    ),
  );
  for (final path in <String>[
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

/// [terminal] 이 [question] 을 물은 횟수.
int countAsks(ScriptedTerminal terminal, String question) =>
    terminal.asks.where((String ask) => ask == question).length;

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
      final runner = FakeCommandRunner()..on(_gitStatusKey, _cleanTree);
      final terminal = ScriptedTerminal(const <String?>[
        'y',
        'com.acme',
        'my_app',
        '1',
        'y',
      ]);

      final int code = await runIdentityStep(runner, terminal);

      final output = terminal.output.toString();
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

  test(
    'T-19-ID-12 Kotlin 이동 검증이 어긋나면 프로세스를 끝내지 않고 실패 안내 · rename 원문 · 멈춤 줄을 보인다',
    () async {
      writeIdentityFixture(root);
      // 이동 대상에 미리 있는 파일이 대상 파일 수를 늘려 복사 검증을 어긋나게 한다.
      const targetDir = 'android/app/src/main/kotlin/com/acme/my_app';
      File('$root/$targetDir/Extra.kt')
        ..parent.createSync(recursive: true)
        ..writeAsStringSync('package com.acme.my_app\n');
      final runner = FakeCommandRunner()..on(_gitStatusKey, _cleanTree);
      final terminal = ScriptedTerminal(const <String?>[
        'y',
        'com.acme',
        'my_app',
        '1',
        'y',
      ]);

      final int code = await runIdentityStep(runner, terminal);

      final output = terminal.output.toString();
      expect(code, wizardExitStopped);
      expect(output, contains('  실패 — ${IdentityStep.moveFailedGuidance}'));
      expect(output, contains('copy verification failed'));
      expect(output, contains(stopLine));
      // 검증 실패면 원본 디렉터리는 지우지 않는다.
      expect(File('$root/$kitKotlinDir/MainActivity.kt').existsSync(), isTrue);
    },
  );

  test('T-19-ID-02 확인 표에서 Enter 면 진행하지 않고 파일을 하나도 바꾸지 않는다', () async {
    writeIdentityFixture(root);
    final Map<String, List<int>> before = snapshotTree(root);
    final runner = FakeCommandRunner()..on(_gitStatusKey, _cleanTree);
    final terminal = ScriptedTerminal(const <String?>[
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
    final runner = FakeCommandRunner()..on(_gitStatusKey, _cleanTree);
    final terminal = ScriptedTerminal(const <String?>[
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

    final output = terminal.output.toString();
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
    final runner = FakeCommandRunner()..on(_gitStatusKey, _cleanTree);
    final terminal = ScriptedTerminal(const <String?>[
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
      final runner = FakeCommandRunner()
        ..on(
          _gitStatusKey,
          const CommandResult(0, ' M android/app/build.gradle.kts\n', ''),
        );
      final terminal = ScriptedTerminal(const <String?>[
        'y',
        'com.acme',
        'my_app',
        '1',
        'y',
      ]);

      final int code = await runIdentityStep(runner, terminal);

      final output = terminal.output.toString();
      expect(code, wizardExitStopped);
      expect(output, contains('  실패 — '));
      expect(output, contains('    android/app/build.gradle.kts'));
      expect(output, contains(IdentityStep.dirtyTreeGuidance));
      expect(snapshotTree(root), before);
    });

    test('T-19-ID-05 고칠 파일 밖의 변경은 막지 않는다', () async {
      writeIdentityFixture(root);
      final runner = FakeCommandRunner()
        ..on(_gitStatusKey, const CommandResult(0, ' M README.md\n', ''));
      final terminal = ScriptedTerminal(const <String?>[
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
      final runner = FakeCommandRunner();
      final terminal = ScriptedTerminal(const <String?>['y', 'Acme Studio']);

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
      // 추적 파일 이름 바꾸기는 하지 않았다 — 앱 ID 파일 · 상수가 그대로이고
      // git 검사도 없다.
      expect(readFile(IdentityStep.gradlePath), gradleBefore);
      expect(readFile('scripts/firebase-configure.sh'), configureBefore);
      expect(runner.calls, isEmpty);
      // example 에서 복사한 사용자 xcconfig 의 킷 번들 ID 는 앱 ID 에 맞춘다.
      expect(
        readXcconfigValue(
          '$root/${UserFilesStep.xcconfigUserPath}',
          'PRODUCT_BUNDLE_IDENTIFIER',
        ),
        'com.acme.myApp.dev',
      );
    });

    test('T-19-ID-06 표시 이름 입력이 끝나면 번들 ID 도 바꾸지 않는다', () async {
      writeIdentityFixture(root, applicationId: 'com.acme.my_app');
      final Map<String, List<int>> before = snapshotTree(root);
      final terminal = ScriptedTerminal(const <String?>['y']);

      final int code = await runIdentityStep(FakeCommandRunner(), terminal);

      expect(code, wizardExitStopped);
      expect(countAsks(terminal, IdentityStep.displayNameQuestion), 1);
      expect(snapshotTree(root), before);
    });

    test('T-19-ID-06 표시 이름 형식이 상한까지 틀리면 번들 ID 도 바꾸지 않는다', () async {
      writeIdentityFixture(root, applicationId: 'com.acme.my_app');
      final Map<String, List<int>> before = snapshotTree(root);
      final terminal = ScriptedTerminal(<String?>[
        'y',
        for (int i = 0; i < IdentityStep.maxInputAttempts; i++) 'My-App!',
      ]);

      final int code = await runIdentityStep(FakeCommandRunner(), terminal);

      final output = terminal.output.toString();
      expect(code, wizardExitStopped);
      expect(
        countAsks(terminal, IdentityStep.displayNameQuestion),
        IdentityStep.maxInputAttempts,
      );
      expect(
        IdentityStep.invalidDisplayNameMessage.allMatches(output),
        hasLength(IdentityStep.maxInputAttempts),
      );
      expect(output, contains('표시 이름 형식이 맞지 않아 진행하지 않았습니다'));
      // 사용자 xcconfig 의 킷 번들 ID 를 포함해 어떤 파일도 바뀌지 않는다.
      expect(snapshotTree(root), before);
    });

    test('T-19-ID-06 Enter 면 앱 ID 에서 계산한 표시 이름을 쓴다', () async {
      writeIdentityFixture(root, applicationId: 'com.acme.my_app');
      final terminal = ScriptedTerminal(const <String?>['y', '']);

      final int code = await runIdentityStep(FakeCommandRunner(), terminal);

      expect(code, wizardExitDone);
      expect(
        readJsonString('$root/${UserFilesStep.jsonUserPath}', 'appName'),
        'My App Dev',
      );
    });
  });

  group('T-19-ID-16 표시 이름은 이미 바뀌고 사용자 xcconfig 번들 ID 만 킷 값', () {
    const stgUserPath = 'ios/Flutter/stg.xcconfig';
    const prodUserPath = 'ios/Flutter/prod.xcconfig';

    /// 표시 이름까지 바뀐 저장소에 example 복사본 사용자 xcconfig 를 둔다.
    void writeBundleIdOnlyFixture() {
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
    }

    String? readBundleId(String relativePath) =>
        readXcconfigValue('$root/$relativePath', 'PRODUCT_BUNDLE_IDENTIFIER');

    test('T-19-ID-16 묻지 않고 있는 파일의 번들 ID 만 맞춘 뒤 다시 검사하면 ✓', () async {
      writeBundleIdOnlyFixture();
      File('ios/Flutter/stg.example.xcconfig').copySync('$root/$stgUserPath');
      // 전제: dev · stg 는 킷 번들 ID 이고 prod 사용자 파일은 없다.
      expect(
        readBundleId(UserFilesStep.xcconfigUserPath),
        '${rename.currentIosBundleId}.dev',
      );
      expect(readBundleId(stgUserPath), '${rename.currentIosBundleId}.stg');
      expect(File('$root/$prodUserPath').existsSync(), isFalse);
      final runner = FakeCommandRunner();
      final terminal = ScriptedTerminal(const <String?>[]);
      final WizardContext context = buildTestContext(
        projectRoot: root,
        runner: runner,
        terminal: terminal,
      );
      final step = IdentityStep();

      final CheckResult before = await step.check(context);

      expect(
        before,
        isA<Todo>().having(
          (Todo todo) => todo.reason,
          'reason',
          '${UserFilesStep.xcconfigUserPath} · $stgUserPath '
              '의 번들 ID 가 킷 기본값입니다',
        ),
      );
      expect(step.isCostlyOrIrreversible, isFalse);
      final List<String> lines = step.plannedCommandLines(context);
      expect(lines, hasLength(2));
      expect(
        lines.every(
          (String line) => line.contains('PRODUCT_BUNDLE_IDENTIFIER'),
        ),
        isTrue,
      );

      final StepOutcome outcome = await step.apply(context);

      expect(outcome, isA<Applied>());
      expect(terminal.asks, isEmpty);
      expect(runner.calls, isEmpty);
      expect(
        readBundleId(UserFilesStep.xcconfigUserPath),
        'com.acme.myApp.dev',
      );
      expect(readBundleId(stgUserPath), 'com.acme.myApp.stg');
      expect(File('$root/$prodUserPath').existsSync(), isFalse);
      // 번들 ID 줄 밖은 그대로다.
      expect(
        readXcconfigValue(
          '$root/${UserFilesStep.xcconfigUserPath}',
          'DISPLAY_NAME',
        ),
        'My App Dev',
      );
      expect(await step.check(context), isA<Done>());
    });

    test('T-19-ID-16 위저드에서는 단계 진행 확인만 묻고 실행 뒤 재검사가 ✓', () async {
      writeBundleIdOnlyFixture();
      final terminal = ScriptedTerminal(const <String?>['y']);

      final int code = await runIdentityStep(FakeCommandRunner(), terminal);

      final output = terminal.output.toString();
      expect(code, wizardExitDone);
      expect(terminal.asks, <String>[stepConfirmQuestion]);
      expect(
        output,
        contains(
          '▶ 앱 정체성\n'
          '  ${UserFilesStep.xcconfigUserPath} 의 번들 ID 가 킷 기본값입니다',
        ),
      );
      expect(output.contains('    $costlyStepNotice'), isFalse);
      expect(output, contains('  ✓ 앱 정체성 — Android 앱 ID com.acme.my_app'));
      expect(
        readBundleId(UserFilesStep.xcconfigUserPath),
        'com.acme.myApp.dev',
      );
    });
  });

  group('T-19-ID-13 Gradle 앱 ID 만 바뀌고 스크립트 상수가 남으면 끝난 것으로 보지 않는다', () {
    for (final (String label, String iosPrefix, String androidPrefix)
        in <(String, String, String)>[
          ('Android 상수가 킷 값', 'com.acme.myApp', rename.currentAndroidPackage),
          ('iOS 상수가 킷 값', rename.currentIosBundleId, 'com.acme.my_app'),
        ]) {
      test('T-19-ID-13 $label 이면 ✗ 사유 · 실행은 실패 · 파일 변경 0', () async {
        writeIdentityFixture(root, applicationId: 'com.acme.my_app');
        replaceJsonString(
          '$root/${UserFilesStep.jsonUserPath}',
          'appName',
          'My App Dev',
        );
        File('$root/scripts/firebase-configure.sh').writeAsStringSync(
          buildConfigureScript(
            iosBundleIdPrefix: iosPrefix,
            androidPackagePrefix: androidPrefix,
          ),
        );
        final Map<String, List<int>> before = snapshotTree(root);
        final runner = FakeCommandRunner();
        final terminal = ScriptedTerminal(const <String?>['y']);

        final int code = await runIdentityStep(runner, terminal);

        final output = terminal.output.toString();
        expect(code, wizardExitStopped);
        expect(output, contains('  ✗ 앱 정체성 — 앱 정체성이 파일마다 다릅니다'));
        expect(output, contains(IdentityStep.inconsistentGuidance));
        expect(output, contains('  실패 — '));
        expect(snapshotTree(root), before);
        expect(runner.calls, isEmpty);
      });
    }

    test('T-19-ID-13 스크립트 상수는 바뀌고 stg placeholder 만 옛 package_name '
        '이면 ✗ 사유 · 실행은 실패 · 파일 변경 0', () async {
      const stgPlaceholder = 'android/app/src/stg/google-services.json';
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
      // 킷 앱 ID 를 담은 stg 자리표시를 시험 안에서 만든다 — 6번 쓰기 전에 끊긴
      // 모양(저장소 파일 값과 무관).
      writeFixtureFile(root, stgPlaceholder, buildStgPlaceholderJson());
      expect(
        readFile(stgPlaceholder),
        contains('"package_name": "${rename.currentAndroidPackage}.stg"'),
      );
      final Map<String, List<int>> before = snapshotTree(root);
      final runner = FakeCommandRunner();
      final terminal = ScriptedTerminal(const <String?>['y']);

      final int code = await runIdentityStep(runner, terminal);

      final output = terminal.output.toString();
      expect(code, wizardExitStopped);
      expect(output, contains('  ✗ 앱 정체성 — 앱 정체성이 파일마다 다릅니다'));
      expect(output, contains('옛 앱 ID 가 남은 파일: $stgPlaceholder.'));
      expect(output, contains(IdentityStep.inconsistentGuidance));
      expect(output, contains('  실패 — '));
      expect(snapshotTree(root), before);
      expect(runner.calls, isEmpty);
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
    replaceXcconfigValue(
      '$root/${UserFilesStep.xcconfigUserPath}',
      'PRODUCT_BUNDLE_IDENTIFIER',
      'com.acme.myApp.dev',
    );
    final terminal = ScriptedTerminal(const <String?>[]);

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
    final step = IdentityStep();

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

    // 표시 이름만 남은 저장소는 rename 명령 줄 없이 표시 이름 쓰기 줄만 있다.
    writeIdentityFixture(root, applicationId: 'com.acme.my_app');
    await step.check(context);
    final List<String> displayNameLines = step.plannedCommandLines(context);
    expect(
      displayNameLines.where((String line) => line.contains('bin/rename.dart')),
      isEmpty,
    );
    expect(
      displayNameLines.where((String line) => line.contains('appName')),
      isNotEmpty,
    );
    expect(
      displayNameLines.where(
        (String line) => line.contains('PRODUCT_BUNDLE_IDENTIFIER'),
      ),
      hasLength(1),
    );
  });

  group('T-19-ID-14 값 표 재확인 안내는 org · name 부터 진행할 때만 붙는다', () {
    for (final (
          String label,
          String applicationId,
          String reason,
          bool hasNotice,
        )
        in <(String, String, String, bool)>[
          (
            '앱 ID 가 킷 기본값',
            rename.currentAndroidPackage,
            'Android 앱 ID 가 킷 기본값입니다',
            true,
          ),
          ('표시 이름만 기본값', 'com.acme.my_app', '표시 이름이 킷 기본값입니다', false),
        ]) {
      test('T-19-ID-14 $label', () async {
        writeIdentityFixture(root, applicationId: applicationId);
        final terminal = ScriptedTerminal(const <String?>[]);

        final int code = await runIdentityStep(FakeCommandRunner(), terminal);

        final output = terminal.output.toString();
        expect(code, wizardExitStopped);
        expect(output, contains('▶ 앱 정체성\n  $reason'));
        expect(output.contains('    $costlyStepNotice'), hasNotice);
      });
    }
  });

  group('T-19-ID-15 점 없는 앱 ID 는 예외 없이 스크립트 상수만 대조하고 잔여 대조는 건너뛴다', () {
    const dotlessId = 'myapp';
    const stgPlaceholder = 'android/app/src/stg/google-services.json';

    /// 표시 이름까지 바뀐 점 없는 앱 ID 저장소와 킷 값 placeholder 잔여를 만든다.
    void writeDotlessFixture() {
      writeIdentityFixture(root, applicationId: dotlessId);
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
      writeFixtureFile(root, stgPlaceholder, buildStgPlaceholderJson());
    }

    test('T-19-ID-15 상수가 앱 ID 와 같으면 잔여가 있어도 ✓', () async {
      writeDotlessFixture();
      expect(
        readFile(stgPlaceholder),
        contains('"package_name": "${rename.currentAndroidPackage}.stg"'),
      );
      final terminal = ScriptedTerminal(const <String?>[]);

      final int code = await runIdentityStep(FakeCommandRunner(), terminal);

      expect(code, wizardExitDone);
      expect(
        terminal.output.toString(),
        contains('  ✓ 앱 정체성 — Android 앱 ID $dotlessId'),
      );
      expect(terminal.asks, isEmpty);
    });

    test('T-19-ID-15 iOS prefix 상수가 앱 ID 와 다르면 기대값이 앱 ID 인 사유로 ✗', () async {
      writeDotlessFixture();
      File('$root/scripts/firebase-configure.sh').writeAsStringSync(
        buildConfigureScript(
          iosBundleIdPrefix: 'com.other.app',
          androidPackagePrefix: dotlessId,
        ),
      );
      final terminal = ScriptedTerminal(const <String?>['y']);

      final int code = await runIdentityStep(FakeCommandRunner(), terminal);

      final output = terminal.output.toString();
      expect(code, wizardExitStopped);
      expect(output, contains('앱 정체성이 파일마다 다릅니다'));
      expect(
        output,
        contains('IOS_BUNDLE_ID_PREFIX 가 com.other.app 입니다(기대 $dotlessId)'),
      );
    });
  });

  group('T-19-ID-09 이동할 Kotlin 디렉터리 안의 변경', () {
    test('T-19-ID-09 디렉터리 안 파일이 바뀌어 있으면 그 경로를 보이고 멈춘다', () async {
      writeIdentityFixture(root);
      final Map<String, List<int>> before = snapshotTree(root);
      final runner = FakeCommandRunner()
        ..on(
          _gitStatusKey,
          CommandResult(0, ' M $kitKotlinDir/MainActivity.kt\n', ''),
        );
      final terminal = ScriptedTerminal(const <String?>[
        'y',
        'com.acme',
        'my_app',
        '1',
        'y',
      ]);

      final int code = await runIdentityStep(runner, terminal);

      final output = terminal.output.toString();
      expect(code, wizardExitStopped);
      expect(output, contains('    $kitKotlinDir/MainActivity.kt'));
      expect(snapshotTree(root), before);
    });

    test('T-19-ID-09 디렉터리 항목은 그 아래 파일만 잡고 앞부분만 같은 형제는 잡지 않는다', () async {
      final runner = FakeCommandRunner()
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
      final runner = FakeCommandRunner()
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
      final runner = FakeCommandRunner()
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

  test('T-19-ID-10 org 는 맞고 name 만 틀리면 name 만 다시 묻는다', () async {
    writeIdentityFixture(root);
    final runner = FakeCommandRunner()..on(_gitStatusKey, _cleanTree);
    final terminal = ScriptedTerminal(const <String?>[
      'y',
      'com.acme',
      'MyApp',
      'my_app',
      '1',
      'y',
    ]);

    final int code = await runIdentityStep(runner, terminal);

    final output = terminal.output.toString();
    expect(code, wizardExitDone);
    expect(countAsks(terminal, IdentityStep.orgQuestion), 1);
    expect(countAsks(terminal, IdentityStep.nameQuestion), 2);
    expect(IdentityStep.invalidNameMessage.allMatches(output).length, 1);
    expect(IdentityStep.invalidOrgMessage.allMatches(output).length, 0);
    expect(output, contains('  ✓ 앱 정체성 — Android 앱 ID com.acme.my_app'));
    expect(
      readFile(IdentityStep.gradlePath),
      contains('applicationId = "com.acme.my_app"'),
    );
  });

  group('T-19-ID-11 org 가 틀리면 org 부터 다시 묻고 시도 상한은 그대로다', () {
    test('T-19-ID-11 org 가 틀리면 다음 시도는 org 부터 묻는다', () async {
      writeIdentityFixture(root);
      final runner = FakeCommandRunner()..on(_gitStatusKey, _cleanTree);
      final terminal = ScriptedTerminal(const <String?>[
        'y',
        'Acme',
        'my_app',
        'com.acme',
        'my_app',
        '1',
        'y',
      ]);

      final int code = await runIdentityStep(runner, terminal);

      final output = terminal.output.toString();
      expect(code, wizardExitDone);
      expect(countAsks(terminal, IdentityStep.orgQuestion), 2);
      expect(countAsks(terminal, IdentityStep.nameQuestion), 2);
      expect(IdentityStep.invalidOrgMessage.allMatches(output).length, 1);
      expect(IdentityStep.invalidNameMessage.allMatches(output).length, 0);
      expect(
        readFile(IdentityStep.gradlePath),
        contains('applicationId = "com.acme.my_app"'),
      );
    });

    test('T-19-ID-11 name 이 상한까지 틀리면 실패하고 파일을 바꾸지 않는다', () async {
      writeIdentityFixture(root);
      final runner = FakeCommandRunner()..on(_gitStatusKey, _cleanTree);
      final terminal = ScriptedTerminal(const <String?>[
        'y',
        'com.acme',
        'MyApp',
        '1app',
        'my-app',
      ]);
      final Map<String, List<int>> before = snapshotTree(root);

      final int code = await runIdentityStep(runner, terminal);

      final output = terminal.output.toString();
      expect(code, wizardExitStopped);
      expect(countAsks(terminal, IdentityStep.orgQuestion), 1);
      expect(
        countAsks(terminal, IdentityStep.nameQuestion),
        IdentityStep.maxInputAttempts,
      );
      expect(IdentityStep.invalidOrgMessage.allMatches(output).length, 0);
      expect(output, contains('org · name 형식이 맞지 않아 진행하지 않았습니다'));
      expect(snapshotTree(root), before);
      expect(runner.countCalls(RunMode.capture, _gitStatusKey), 0);
    });
  });

  test('buildDevSteps 는 Xcode 준비 → 개발 도구 → 사용자 설정 파일 → 앱 정체성 순서로 시작한다', () {
    final List<String> ids = buildDevSteps()
        .map((Step step) => step.id)
        .toList();

    expect(ids.take(4).toList(), <String>[
      'xcode',
      'tools',
      'user_files',
      'identity',
    ]);
  });
  group('flavor 문맥', () {
    /// 이름 바꾸기가 끝난 저장소의 앱 ID(가짜).
    const renamedApplicationId = 'com.acme.my_app';
    late ScriptedTerminal screen;

    /// [flavor] 문맥을 만든다 — 화면은 가림 터미널로 감싼다.
    WizardContext buildFlavorContext(Flavor flavor, List<String?> inputs) {
      final log = MemoryLogSink(Redactor());
      screen = ScriptedTerminal(inputs);
      return WizardContext(
        projectRoot: root,
        runner: FakeCommandRunner(),
        terminal: RedactingTerminal(screen, log.redactor, log),
        redactor: log.redactor,
        log: log,
        rest: FakeRestClient(),
        flavor: flavor,
        random: Random(fixedTestRandomSeed),
        now: () => fixedTestNow,
      );
    }

    /// [flavor] 의 example 두 파일과 그 복사본 사용자 파일을 둔다.
    void writeFlavorUserFiles(Flavor flavor) {
      final paths = FlavorPaths(flavor);
      for (final (String example, String user) in <(String, String)>[
        (paths.jsonExample, paths.json),
        (paths.xcconfigExample, paths.xcconfig),
      ]) {
        File(example).copySync('$root/$example');
        File(example).copySync('$root/$user');
      }
    }

    for (final flavor in <Flavor>[Flavor.stg, Flavor.prod]) {
      test(
        'T-20-FLAVOR-07: ${flavor.name} 문맥 · 앱 ID 가 바뀐 저장소는 org · name 을 묻지 않고 '
        '그 flavor 파일의 번들 ID · 표시 이름만 맞춘다',
        () async {
          writeIdentityFixture(root, applicationId: renamedApplicationId);
          writeFlavorUserFiles(flavor);
          final paths = FlavorPaths(flavor);
          final devBefore = <String, List<int>>{
            for (final String path in <String>[
              UserFilesStep.jsonUserPath,
              UserFilesStep.xcconfigUserPath,
            ])
              path: File('$root/$path').readAsBytesSync(),
          };
          final WizardContext context = buildFlavorContext(
            flavor,
            const <String?>[''],
          );
          final step = IdentityStep();

          final CheckResult before = await step.check(context);
          final List<String> lines = step.plannedCommandLines(context);
          final StepOutcome outcome = await step.apply(context);

          final expectedName =
              '${rename.toTitleCase('my_app')}${flavor.displayNameSuffix}';
          expect(
            before,
            isA<Todo>().having(
              (Todo todo) => todo.reason,
              'reason',
              '표시 이름이 킷 기본값입니다',
            ),
          );
          expect(lines, <String>[
            '(${paths.xcconfig} 의 PRODUCT_BUNDLE_IDENTIFIER 를 앱 ID 에 맞춤)',
            '(${paths.json} 의 appName 을 표시 이름으로 바꿈)',
            '(${paths.xcconfig} 의 DISPLAY_NAME 을 표시 이름으로 바꿈)',
          ]);
          expect(outcome, isA<Applied>());
          expect(screen.asks, <String>[IdentityStep.displayNameQuestion]);
          expect(
            readXcconfigValue(
              '$root/${paths.xcconfig}',
              'PRODUCT_BUNDLE_IDENTIFIER',
            ),
            '${buildIosBundleIdPrefix(renamedApplicationId)}${flavor.suffix}',
          );
          expect(
            readXcconfigValue('$root/${paths.xcconfig}', 'DISPLAY_NAME'),
            expectedName,
          );
          expect(
            readJsonString('$root/${paths.json}', 'appName'),
            expectedName,
          );
          // dev 사용자 파일은 킷 번들 ID 가 남아 있어도 건드리지 않는다.
          for (final MapEntry<String, List<int>> entry in devBefore.entries) {
            expect(
              File('$root/${entry.key}').readAsBytesSync(),
              entry.value,
              reason: entry.key,
            );
          }
          expect(await step.check(context), isA<Done>());
        },
      );
    }

    test('T-20-FLAVOR-10: dev 문맥 정체성 단계의 계획 줄 · 표시 이름 제안은 그대로다', () async {
      writeIdentityFixture(root, applicationId: renamedApplicationId);
      final WizardContext context = buildFlavorContext(
        Flavor.dev,
        const <String?>[''],
      );
      final step = IdentityStep();

      await step.check(context);
      final List<String> lines = step.plannedCommandLines(context);
      await step.apply(context);

      expect(
        lines,
        containsAllInOrder(<String>[
          '(config/dev.json 의 appName 을 표시 이름으로 바꿈)',
          '(ios/Flutter/dev.xcconfig 의 DISPLAY_NAME 을 표시 이름으로 바꿈)',
        ]),
      );
      expect(
        readJsonString('$root/${UserFilesStep.jsonUserPath}', 'appName'),
        'My App Dev',
      );
    });
  });
}
