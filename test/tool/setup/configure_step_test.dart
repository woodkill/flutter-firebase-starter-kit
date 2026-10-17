import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:test/test.dart';

import '../../../tool/setup/command_runner.dart';
import '../../../tool/setup/config_files.dart';
import '../../../tool/setup/firebase_app_files.dart';
import '../../../tool/setup/redactor.dart';
import '../../../tool/setup/step.dart';
import '../../../tool/setup/steps/configure_step.dart';
import '../../../tool/setup/steps/dev_steps.dart';
import '../../../tool/setup/steps/user_files_step.dart';
import '../../../tool/setup/terminal.dart';
import '../../../tool/setup/wizard.dart';
import 'fake_rest_client.dart';
import 'fakes.dart';
import 'firebase_options_fixture.dart';

/// 테스트 프로젝트 ID.
const String projectId = 'p';

/// fixture 앱 정체성의 iOS 번들 ID 기반 값(끝 `.dev` 를 뗀 값).
const String bundleBase = 'com.example.app';

/// fixture Gradle 의 applicationId.
const String applicationId = 'com.example.app_android';

/// fixture iOS 앱 ID.
const String iosAppId = '1:000:ios:fake';

/// fixture Android 앱 ID.
const String androidAppId = '1:000:android:fake';

/// 앱 목록 명령 키.
const String appsListKey = 'firebase apps:list --json --project $projectId';

/// configure 스크립트 명령 키.
const String configureKey = 'bash scripts/firebase-configure.sh dev';

/// 깨끗한 트리 검사 명령 키.
const String statusKey = 'git status --porcelain --untracked-files=no';

/// pbxproj 원문 줄 diff 명령 키.
const String diffKey =
    'git diff --no-color --no-ext-diff --no-textconv --text --unified=0 '
    '-- ios/Runner.xcodeproj/project.pbxproj';

/// pbxproj 저장소 상대 경로.
const String pbxprojPath = 'ios/Runner.xcodeproj/project.pbxproj';

/// configure 스크립트의 성공 출력(마지막 줄 계약).
const String configureSuccessStdout =
    '  project:       p\n'
    '  · git update-index --skip-worktree lib/core/firebase/firebase_options_dev.dart\n'
    '\n'
    '✓ Firebase configure complete for dev\n';

/// 실행 시점에 조립한 가짜 API 키 — 소스에 완형을 두지 않는다.
final String fakeApiKey = 'AIza${'x' * 35}';

const CommandResult _ok = CommandResult(0, '', '');

/// 이미 끝난 앞 단계 — 앱 등록 단계의 의존 단계를 대신한다.
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

/// 가짜 실행기에 넘기면서, configure 스크립트가 실행되는 순간 [onConfigure] 를
/// 불러 스크립트가 파일을 바꾸는 것을 흉내 내는 실행기.
final class _ConfigureCallbackRunner implements CommandRunner {
  _ConfigureCallbackRunner(this.inner, this.onConfigure);

  /// 결과를 돌려주는 가짜 실행기.
  final FakeCommandRunner inner;

  /// configure 스크립트 실행 순간에 부를 콜백.
  final void Function() onConfigure;

  /// configure 실행에 넘어간 작업 디렉터리(실행 순서대로).
  final List<String?> workingDirectories = <String?>[];

  @override
  Future<CommandResult> capture(Command command) => inner.capture(command);

  @override
  Future<int> interactive(Command command) => inner.interactive(command);

  @override
  Future<CommandResult> stream(Command command) {
    if (FakeCommandRunner.buildKey(command) == configureKey) {
      workingDirectories.add(command.workingDirectory);
      onConfigure();
    }
    return inner.stream(command);
  }
}

/// `firebase apps:list --json` 성공 출력을 만든다.
CommandResult buildAppsList(List<String> appIds) => CommandResult(
  0,
  jsonEncode(<String, Object?>{
    'status': 'success',
    'result': <Object?>[
      for (final String appId in appIds)
        <String, Object?>{
          'appId': appId,
          'displayName': 'fixture',
          'platform': appId.contains(':ios:') ? 'IOS' : 'ANDROID',
        },
    ],
  }),
  '',
);

void main() {
  late Directory tempDir;
  late String root;
  late File pbxproj;
  late File firebaseJson;

  /// 저장소 상대 경로에 내용을 쓴다(부모 디렉터리를 만든다).
  void writeFixture(String relativePath, String content) {
    File('$root/$relativePath')
      ..parent.createSync(recursive: true)
      ..writeAsStringSync(content);
  }

  /// FlutterFire 생성본 모양의 Dart 설정 파일을 쓴다(미지원 플랫폼 예외 포함).
  void writeRealOptions({String project = projectId}) {
    writeFixture(
      FirebaseAppFiles.optionsPath,
      buildGeneratedOptionsSource(
        projectId: project,
        apiKey: fakeApiKey,
        androidAppId: androidAppId,
        iosAppId: iosAppId,
        iosBundleId: '$bundleBase.dev',
      ),
    );
  }

  /// 저장소 자리표시 모양의 Dart 설정 파일을 쓴다.
  void writePlaceholderOptions() {
    writeFixture(
      FirebaseAppFiles.optionsPath,
      'class DefaultFirebaseOptions {\n'
      '  static FirebaseOptions get currentPlatform {\n'
      '    throw UnsupportedError(\n'
      "      'dev 환경 Firebase 프로젝트가 아직 연결되지 않았습니다.',\n"
      '    );\n'
      '  }\n'
      '}\n',
    );
  }

  /// iOS plist 를 쓴다.
  void writePlist({
    String project = projectId,
    String bundleId = '$bundleBase.dev',
    String appId = iosAppId,
  }) {
    writeFixture(
      FirebaseAppFiles.iosPlistPath,
      '<?xml version="1.0" encoding="UTF-8"?>\n'
      '<plist version="1.0">\n'
      '<dict>\n'
      '\t<key>API_KEY</key>\n'
      '\t<string>$fakeApiKey</string>\n'
      '\t<key>GCM_SENDER_ID</key>\n'
      '\t<string>000</string>\n'
      '\t<key>BUNDLE_ID</key>\n'
      '\t<string>$bundleId</string>\n'
      '\t<key>PROJECT_ID</key>\n'
      '\t<string>$project</string>\n'
      '\t<key>IS_GCM_ENABLED</key>\n'
      '\t<true/>\n'
      '\t<key>GOOGLE_APP_ID</key>\n'
      '\t<string>$appId</string>\n'
      '</dict>\n'
      '</plist>\n',
    );
  }

  /// Android google-services.json 을 쓴다.
  void writeGoogleServices({String project = projectId}) {
    writeFixture(
      FirebaseAppFiles.androidJsonPath,
      const JsonEncoder.withIndent('  ').convert(<String, Object?>{
        'project_info': <String, Object?>{
          'project_number': '000',
          'project_id': project,
          'storage_bucket': '$project.firebasestorage.app',
        },
        'client': <Object?>[
          <String, Object?>{
            'client_info': <String, Object?>{
              'mobilesdk_app_id': androidAppId,
              'android_client_info': <String, Object?>{
                'package_name': '$applicationId.dev',
              },
            },
            'oauth_client': <Object?>[],
            'api_key': <Object?>[
              <String, Object?>{'current_key': fakeApiKey},
            ],
          },
        ],
        'configuration_version': '1',
      }),
    );
  }

  /// 실 값 모양 설정 파일 3개를 쓴다.
  void writeRealFiles() {
    writeRealOptions();
    writePlist();
    writeGoogleServices();
  }

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('configure_step_test_');
    root = tempDir.path;
    final config = File('$root/${UserFilesStep.jsonUserPath}')
      ..parent.createSync(recursive: true);
    File(UserFilesStep.jsonExamplePath).copySync(config.path);
    replaceJsonString(config.path, 'firebaseProjectId', projectId);
    writeFixture(
      UserFilesStep.xcconfigUserPath,
      'PRODUCT_BUNDLE_IDENTIFIER = $bundleBase.dev\nFLAVOR = dev\n',
    );
    writeFixture(
      'android/app/build.gradle.kts',
      'android {\n'
          '    defaultConfig {\n'
          '        applicationId = "$applicationId"\n'
          '    }\n'
          '    productFlavors {\n'
          '        create("dev") { applicationIdSuffix = ".dev" }\n'
          '    }\n'
          '}\n',
    );
    writeFixture(
      pbxprojPath,
      '// fixture\n'
      '\t\t\t\tPRODUCT_BUNDLE_IDENTIFIER = $bundleBase.dev;\n'
      '\t\t\t\tPRODUCT_BUNDLE_IDENTIFIER = $bundleBase.RunnerTests;\n',
    );
    writeFixture('firebase.json', '{"flutter":{"platforms":{}}}\n');
    pbxproj = File('$root/$pbxprojPath');
    firebaseJson = File('$root/firebase.json');
  });

  tearDown(() {
    tempDir.deleteSync(recursive: true);
  });

  /// 앞 단계(끝남) · 앱 등록 단계로 위저드를 돌린다.
  Future<int> runConfigureStep(
    CommandRunner runner,
    ScriptedTerminal terminal, {
    MemoryLogSink? log,
  }) {
    final Redactor redactor = log?.redactor ?? Redactor();
    final MemoryLogSink usedLog = log ?? MemoryLogSink(redactor);
    final context = WizardContext(
      projectRoot: root,
      runner: runner,
      terminal: RedactingTerminal(terminal, redactor, usedLog),
      redactor: redactor,
      log: usedLog,
      rest: FakeRestClient(),
      random: Random(fixedTestRandomSeed),
      now: () => fixedTestNow,
    );
    return runWizard(context, <Step>[
      _FinishedStep('firebase_project', 'Firebase 프로젝트'),
      _FinishedStep('identity', '앱 정체성'),
      _FinishedStep('tools', '개발 도구'),
      ConfigureStep(),
    ]);
  }

  /// 점검표의 앱 등록 단계 사유를 꺼낸다.
  String readChecklistReason(String output) => output
      .split('\n')
      .firstWhere(
        (String line) => line.startsWith('  ✗ ${ConfigureStep.stepTitle} — '),
      )
      .substring('  ✗ ${ConfigureStep.stepTitle} — '.length);

  test('T-19-CONF-01 설정 파일 3개가 실 값 모양이고 앱 목록에 두 앱이 있으면 ✓ · 실행 0', () async {
    writeRealFiles();
    final runner = FakeCommandRunner()
      ..on(appsListKey, buildAppsList(<String>[androidAppId, iosAppId]));
    final terminal = ScriptedTerminal(const <String?>[]);

    final int code = await runConfigureStep(runner, terminal);

    expect(code, wizardExitDone);
    expect(
      terminal.output.toString(),
      contains('  ✓ ${ConfigureStep.stepTitle} — '),
    );
    expect(terminal.asks, isEmpty);
    expect(runner.countMode(RunMode.stream), 0);
    expect(runner.countCalls(RunMode.capture, appsListKey), 1);
    expect(
      runner.calls
          .firstWhere((FakeCall call) => call.key == appsListKey)
          .isOutputSensitive,
      isTrue,
    );
  });

  test(
    'T-19-CONF-02 Dart 설정 파일이 자리표시면 ✗ · y 뒤 configure 스크립트 1회 · 마지막 줄 계약 · 바이트 같음 · 재검사 ✓',
    () async {
      writePlaceholderOptions();
      final List<int> pbxprojBefore = pbxproj.readAsBytesSync();
      final List<int> firebaseJsonBefore = firebaseJson.readAsBytesSync();
      final runner = _ConfigureCallbackRunner(
        FakeCommandRunner()
          ..on(statusKey, _ok)
          ..on(configureKey, const CommandResult(0, configureSuccessStdout, ''))
          ..on(appsListKey, buildAppsList(<String>[iosAppId, androidAppId])),
        writeRealFiles,
      );
      final terminal = ScriptedTerminal(const <String?>['y']);

      final int code = await runConfigureStep(runner, terminal);

      final output = terminal.output.toString();
      expect(code, wizardExitDone);
      expect(readChecklistReason(output), contains('자리표시'));
      expect(output, contains('\$ $configureKey'));
      expect(runner.inner.countCalls(RunMode.stream, configureKey), 1);
      expect(runner.workingDirectories, <String?>[root]);
      expect(runner.inner.countCalls(RunMode.capture, diffKey), 0);
      expect(pbxproj.readAsBytesSync(), pbxprojBefore);
      expect(firebaseJson.readAsBytesSync(), firebaseJsonBefore);
      expect(output, contains('  ✓ ${ConfigureStep.stepTitle} — '));
    },
  );

  test('T-19-CONF-03 exit 0 이어도 마지막 줄이 완료 줄이 아니면 실패', () async {
    writePlaceholderOptions();
    final runner = FakeCommandRunner()
      ..on(statusKey, _ok)
      ..on(
        configureKey,
        const CommandResult(
          0,
          '✓ Firebase configure complete for dev\nextra\n',
          '',
        ),
      );
    final terminal = ScriptedTerminal(const <String?>['y']);

    final int code = await runConfigureStep(runner, terminal);

    final output = terminal.output.toString();
    expect(code, wizardExitStopped);
    expect(output, contains('  실패 — '));
    expect(output, contains(ConfigureStep.completeLine));
    expect(runner.countCalls(RunMode.stream, configureKey), 1);
    expect(runner.countCalls(RunMode.capture, appsListKey), 0);
  });

  test('T-19-CONF-04 exit 1 이면 실패 · stderr 원문을 그대로 보인다', () async {
    const rubyError =
        "✗ ruby 의 'xcodeproj' gem 을 찾을 수 없다 (ruby: /usr/bin/ruby).\n"
        '\n'
        '  해결 (둘 중 하나):\n'
        '    1) gem install xcodeproj\n';
    writePlaceholderOptions();
    final runner = FakeCommandRunner()
      ..on(statusKey, _ok)
      ..on(configureKey, const CommandResult(1, '', rubyError));
    final terminal = ScriptedTerminal(const <String?>['y']);

    final int code = await runConfigureStep(runner, terminal);

    final output = terminal.output.toString();
    expect(code, wizardExitStopped);
    expect(output, contains('  실패 — '));
    expect(output, contains(rubyError));
  });

  test(
    'T-19-CONF-05 스크립트가 firebase.json 을 되돌리지 않으면 실패 · 파일 이름 · 되돌리지 못함 문구',
    () async {
      writePlaceholderOptions();
      final List<int> pbxprojBefore = pbxproj.readAsBytesSync();
      final runner = _ConfigureCallbackRunner(
        FakeCommandRunner()
          ..on(statusKey, _ok)
          ..on(configureKey, const CommandResult(0, configureSuccessStdout, ''))
          ..on(appsListKey, buildAppsList(<String>[iosAppId, androidAppId])),
        () {
          writeRealFiles();
          firebaseJson.writeAsStringSync('{"flutter":{"changed":true}}\n');
        },
      );
      final terminal = ScriptedTerminal(const <String?>['y']);

      final int code = await runConfigureStep(runner, terminal);

      final output = terminal.output.toString();
      final String failureLine = output
          .split('\n')
          .firstWhere((String line) => line.startsWith('  실패 — '));
      expect(code, wizardExitStopped);
      expect(failureLine, contains('firebase.json'));
      expect(failureLine, contains('실행 전 내용으로 되돌리지 못했습니다'));
      expect(failureLine, isNot(contains(pbxprojPath)));
      expect(output, contains('git diff -- firebase.json'));
      expect(pbxproj.readAsBytesSync(), pbxprojBefore);
      expect(output, isNot(contains('  ✓ ${ConfigureStep.stepTitle} — ')));
    },
  );

  test(
    'T-19-CONF-06 pbxproj 변경이 앱 정체성 단계의 번들 ID 줄뿐이면 멈추지 않고 실행 · 실행 뒤 바이트가 실행 전과 같으면 ✓',
    () async {
      writePlaceholderOptions();
      final List<int> pbxprojBefore = pbxproj.readAsBytesSync();
      const identityDiff =
          'diff --git a/$pbxprojPath b/$pbxprojPath\n'
          'index 1111111..2222222 100644\n'
          '--- a/$pbxprojPath\n'
          '+++ b/$pbxprojPath\n'
          '@@ -10 +10 @@\n'
          '-\t\t\t\tPRODUCT_BUNDLE_IDENTIFIER = com.slimpumpkin.flutterStarterKit.dev;\n'
          '+\t\t\t\tPRODUCT_BUNDLE_IDENTIFIER = $bundleBase.dev;\n'
          '@@ -20 +20 @@\n'
          '-\t\t\t\tPRODUCT_BUNDLE_IDENTIFIER = com.slimpumpkin.flutterStarterKit.RunnerTests;\n'
          '+\t\t\t\tPRODUCT_BUNDLE_IDENTIFIER = $bundleBase.RunnerTests;\n'
          '@@ -30 +30 @@\n'
          '-\t\t\t\tPRODUCT_BUNDLE_IDENTIFIER = com.slimpumpkin.flutterStarterKit;\n'
          '+\t\t\t\tPRODUCT_BUNDLE_IDENTIFIER = $bundleBase;\n';
      final duringRun = <List<int>>[];
      final runner = _ConfigureCallbackRunner(
        FakeCommandRunner()
          ..on(statusKey, const CommandResult(0, ' M $pbxprojPath\n', ''))
          ..on(diffKey, const CommandResult(0, identityDiff, ''))
          ..on(configureKey, const CommandResult(0, configureSuccessStdout, ''))
          ..on(appsListKey, buildAppsList(<String>[iosAppId, androidAppId])),
        () {
          writeRealFiles();
          // 스크립트의 CLI 가 pbxproj 를 바꿨다가 스냅샷으로 되돌리는 것을 흉내 낸다.
          pbxproj.writeAsStringSync('// changed by cli\n');
          duringRun.add(pbxproj.readAsBytesSync());
          pbxproj.writeAsBytesSync(pbxprojBefore);
        },
      );
      final terminal = ScriptedTerminal(const <String?>['y']);

      final int code = await runConfigureStep(runner, terminal);

      final output = terminal.output.toString();
      expect(code, wizardExitDone);
      expect(runner.inner.countCalls(RunMode.capture, diffKey), 1);
      expect(runner.inner.countCalls(RunMode.stream, configureKey), 1);
      expect(duringRun, hasLength(1));
      expect(duringRun.single, isNot(pbxprojBefore));
      expect(pbxproj.readAsBytesSync(), pbxprojBefore);
      expect(output, contains('  ✓ ${ConfigureStep.stepTitle} — '));
    },
  );

  group('T-19-CONF-08 pbxproj 변경이 앞 단계 모양이 아니면 실행하지 않고 멈춘다', () {
    const header =
        'diff --git a/$pbxprojPath b/$pbxprojPath\n'
        'index 1111111..2222222 100644\n'
        '--- a/$pbxprojPath\n'
        '+++ b/$pbxprojPath\n';
    const diffs = <String, String>{
      '(a) 번들 ID 밖 줄이 함께 바뀜':
          '$header'
          '@@ -10 +10 @@\n'
          '-\t\t\t\tPRODUCT_BUNDLE_IDENTIFIER = com.slimpumpkin.flutterStarterKit.dev;\n'
          '+\t\t\t\tPRODUCT_BUNDLE_IDENTIFIER = $bundleBase.dev;\n'
          '@@ -40,0 +41 @@\n'
          '+\t\t\t\tshellScript = "echo extra";\n',
      '(b) 새 번들 ID 가 지금 앱 정체성과 다름':
          '$header'
          '@@ -10 +10 @@\n'
          '-\t\t\t\tPRODUCT_BUNDLE_IDENTIFIER = com.slimpumpkin.flutterStarterKit.dev;\n'
          '+\t\t\t\tPRODUCT_BUNDLE_IDENTIFIER = com.other.app.dev;\n',
      '(c) 모드만 바뀌어 바뀐 줄이 없음':
          'diff --git a/$pbxprojPath b/$pbxprojPath\n'
          'old mode 100644\n'
          'new mode 100755\n',
      '(d) 번들 ID 줄이 지워지기만 함':
          '$header'
          '@@ -10 +9,0 @@\n'
          '-\t\t\t\tPRODUCT_BUNDLE_IDENTIFIER = com.slimpumpkin.flutterStarterKit.dev;\n',
    };

    for (final MapEntry<String, String> entry in diffs.entries) {
      test(entry.key, () async {
        writePlaceholderOptions();
        final runner = FakeCommandRunner()
          ..on(statusKey, const CommandResult(0, ' M $pbxprojPath\n', ''))
          ..on(diffKey, CommandResult(0, entry.value, ''));
        final terminal = ScriptedTerminal(const <String?>['y']);

        final int code = await runConfigureStep(runner, terminal);

        final output = terminal.output.toString();
        final String failureLine = output
            .split('\n')
            .firstWhere((String line) => line.startsWith('  실패 — '));
        expect(code, wizardExitStopped);
        expect(failureLine, contains('커밋하지 않은 변경'));
        expect(output, contains('    $pbxprojPath'));
        expect(runner.countMode(RunMode.stream), 0);
        expect(runner.countCalls(RunMode.capture, diffKey), 1);
      });
    }
  });

  test('T-19-CONF-09 firebase.json 에 미커밋 변경이 있으면 실패 · 실행 0 · diff 0', () async {
    writePlaceholderOptions();
    final runner = FakeCommandRunner()
      ..on(
        statusKey,
        const CommandResult(0, ' M firebase.json\n M $pbxprojPath\n', ''),
      );
    final terminal = ScriptedTerminal(const <String?>['y']);

    final int code = await runConfigureStep(runner, terminal);

    final output = terminal.output.toString();
    expect(code, wizardExitStopped);
    expect(output, contains('    firebase.json'));
    expect(runner.countMode(RunMode.stream), 0);
    expect(runner.countCalls(RunMode.capture, diffKey), 0);
  });

  test('T-19-CONF-11 앱 목록 명령이 실패하면 오류 원문만 보이고 민감 출력(표준 출력)은 보이지 않는다', () async {
    writeRealFiles();
    const stdoutMarker = 'apps-list-stdout-marker';
    const stderrLine = 'Error: Failed to list Firebase apps.';
    final runner = FakeCommandRunner()
      ..on(
        appsListKey,
        const CommandResult(1, '{"status":"$stdoutMarker"}', '$stderrLine\n'),
      );
    final terminal = ScriptedTerminal(const <String?>['y']);
    final log = MemoryLogSink(Redactor());

    final int code = await runConfigureStep(runner, terminal, log: log);

    final output = terminal.output.toString();
    expect(code, wizardExitStopped);
    expect(output, contains('  실패 — '));
    expect(output, contains(stderrLine));
    expect(output, isNot(contains(stdoutMarker)));
    expect(log.text, isNot(contains(stdoutMarker)));
    expect(runner.countMode(RunMode.stream), 0);
  });

  test(
    'T-19-CONF-07 iOS 설정 파일의 프로젝트가 다르면 ✗ 사유 「다른 프로젝트」 · 화면 · 기록에 키 · 앱 ID 0',
    () async {
      writeRealOptions();
      writePlist(project: 'someone-else');
      writeGoogleServices();
      final runner = FakeCommandRunner()
        ..on(appsListKey, buildAppsList(<String>[iosAppId, androidAppId]));
      final terminal = ScriptedTerminal(const <String?>[]);
      final log = MemoryLogSink(Redactor());

      final int code = await runConfigureStep(runner, terminal, log: log);

      final output = terminal.output.toString();
      expect(code, wizardExitStopped);
      expect(readChecklistReason(output), contains('다른 프로젝트'));
      for (final secret in <String>[
        fakeApiKey,
        iosAppId,
        androidAppId,
        'someone-else',
      ]) {
        expect(output, isNot(contains(secret)));
        expect(log.text, isNot(contains(secret)));
      }
      expect(runner.countMode(RunMode.stream), 0);
    },
  );

  test(
    'T-19-CONF-10 configure 스크립트가 실제 생성본 모양(예외 throw 5곳)을 쓰면 재검사 ✓ · 스크립트 1회 · 재검사에 자리표시 사유 0 · 화면 · 기록에 키 · 앱 ID 0',
    () async {
      writePlaceholderOptions();
      final runner = _ConfigureCallbackRunner(
        FakeCommandRunner()
          ..on(statusKey, _ok)
          ..on(configureKey, const CommandResult(0, configureSuccessStdout, ''))
          ..on(appsListKey, buildAppsList(<String>[iosAppId, androidAppId])),
        writeRealFiles,
      );
      final terminal = ScriptedTerminal(const <String?>['y']);
      final log = MemoryLogSink(Redactor());

      final int code = await runConfigureStep(runner, terminal, log: log);

      final output = terminal.output.toString();
      final String written = File(
        '$root/${FirebaseAppFiles.optionsPath}',
      ).readAsStringSync();
      expect(written, startsWith('// File generated by FlutterFire CLI.\n'));
      expect('throw UnsupportedError('.allMatches(written), hasLength(5));
      expect(code, wizardExitDone);
      expect(runner.inner.countCalls(RunMode.stream, configureKey), 1);
      expect(output, contains('  ✓ ${ConfigureStep.stepTitle} — '));
      // 자리표시 사유는 실행 전 점검에만 있다 — 스크립트 실행 뒤 재검사에는 없다.
      final String afterRun = output.substring(
        output.indexOf('\$ $configureKey'),
      );
      expect(afterRun, isNot(contains('저장소 자리표시')));
      expect(output, isNot(contains('  실패 — ')));
      for (final secret in <String>[fakeApiKey, iosAppId, androidAppId]) {
        expect(output, isNot(contains(secret)));
        expect(log.text, isNot(contains(secret)));
      }
    },
  );

  test('FirebaseAppFiles 는 파일이 없으면 null · 자리표시로 본다', () {
    final FirebaseAppFiles files = FirebaseAppFiles.read(root);

    expect(files.isOptionsPlaceholder, isTrue);
    expect(files.optionsProjectId, isNull);
    expect(files.iosProjectId, isNull);
    expect(files.iosBundleId, isNull);
    expect(files.iosAppId, isNull);
    expect(files.androidProjectId, isNull);
    expect(files.androidAppIdFor('$applicationId.dev'), isNull);
  });

  test('FirebaseAppFiles 는 실 값 모양 파일에서 프로젝트 · 번들 · 앱 ID 를 읽는다', () {
    writeRealFiles();

    final FirebaseAppFiles files = FirebaseAppFiles.read(root);

    expect(files.isOptionsPlaceholder, isFalse);
    expect(files.optionsProjectId, projectId);
    expect(files.iosProjectId, projectId);
    expect(files.iosBundleId, '$bundleBase.dev');
    expect(files.iosAppId, iosAppId);
    expect(files.androidProjectId, projectId);
    expect(files.androidAppIdFor('$applicationId.dev'), androidAppId);
    expect(files.androidAppIdFor(applicationId), isNull);
    expect(readDevBundleId(root), '$bundleBase.dev');
    expect(readDevAndroidPackage(root), '$applicationId.dev');
  });

  test('buildDevSteps 는 로그인 수단 단계 다음에 앱 등록 단계를 둔다', () {
    final List<String> ids = buildDevSteps()
        .map((Step step) => step.id)
        .toList();

    expect(ids.indexOf('configure'), ids.indexOf('providers') + 1);
  });
}
