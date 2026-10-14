import 'dart:io';

import 'package:test/test.dart';

import '../../../tool/setup/step.dart';
import '../../../tool/setup/steps/dev_steps.dart';
import '../../../tool/setup/steps/user_files_step.dart';
import '../../../tool/setup/wizard.dart';
import 'fakes.dart';

void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('user_files_step_test_');
    Directory('${tempDir.path}/config').createSync(recursive: true);
    Directory('${tempDir.path}/ios/Flutter').createSync(recursive: true);
    // 추적되는 example 두 파일을 임시 저장소로 복사한다.
    File(
      UserFilesStep.jsonExamplePath,
    ).copySync('${tempDir.path}/${UserFilesStep.jsonExamplePath}');
    File(
      UserFilesStep.xcconfigExamplePath,
    ).copySync('${tempDir.path}/${UserFilesStep.xcconfigExamplePath}');
  });

  tearDown(() {
    tempDir.deleteSync(recursive: true);
  });

  File userFile(String relativePath) => File('${tempDir.path}/$relativePath');

  /// 사용자 설정 파일 단계 하나로 위저드를 돌린다.
  Future<int> runUserFilesStep(ScriptedTerminal terminal) => runWizard(
    buildTestContext(projectRoot: tempDir.path, terminal: terminal),
    <Step>[UserFilesStep()],
  );

  test(
    'T-19-FILES-01 사용자 파일이 둘 다 없으면 ✗ 이고 y 뒤 example 과 같은 두 파일이 생긴다',
    () async {
      final ScriptedTerminal terminal = ScriptedTerminal(const <String?>['y']);

      final int code = await runUserFilesStep(terminal);

      final String output = terminal.output.toString();
      expect(code, wizardExitDone);
      expect(output, contains('  ✗ 사용자 설정 파일 — '));
      expect(
        output,
        contains(r'  $ cp config/dev.example.json config/dev.json'),
      );
      expect(
        output,
        contains(
          r'  $ cp ios/Flutter/dev.example.xcconfig ios/Flutter/dev.xcconfig',
        ),
      );
      expect(output, contains('  ✓ 사용자 설정 파일 — '));
      expect(
        userFile(UserFilesStep.jsonUserPath).readAsBytesSync(),
        userFile(UserFilesStep.jsonExamplePath).readAsBytesSync(),
      );
      expect(
        userFile(UserFilesStep.xcconfigUserPath).readAsBytesSync(),
        userFile(UserFilesStep.xcconfigExamplePath).readAsBytesSync(),
      );
      expect(terminal.asks, <String>[stepConfirmQuestion]);
    },
  );

  test(
    'T-19-FILES-02 실 값이 든 사용자 JSON 에 키 하나만 없으면 그 키만 example 값으로 더하고 값을 묻지 않는다',
    () async {
      final String example = userFile(
        UserFilesStep.jsonExamplePath,
      ).readAsStringSync();
      final String original = example
          .replaceFirst(',\n  "appCheckDebugToken": ""', '')
          .replaceFirst('"your-project-dev"', '"acme-real-dev"');
      expect(original, isNot(contains('appCheckDebugToken')));
      userFile(UserFilesStep.jsonUserPath).writeAsStringSync(original);
      userFile(
        UserFilesStep.xcconfigExamplePath,
      ).copySync(userFile(UserFilesStep.xcconfigUserPath).path);
      final ScriptedTerminal terminal = ScriptedTerminal(const <String?>['y']);

      final int code = await runUserFilesStep(terminal);

      final String output = terminal.output.toString();
      final String updated = userFile(
        UserFilesStep.jsonUserPath,
      ).readAsStringSync();
      expect(code, wizardExitDone);
      expect(output, contains('  ✗ 사용자 설정 파일 — '));
      expect(output, contains('appCheckDebugToken'));
      expect(output, contains('  ✓ 사용자 설정 파일 — '));
      expect(updated, contains('"firebaseProjectId": "acme-real-dev"'));
      expect(updated, endsWith('  "appCheckDebugToken": ""\n}\n'));
      expect(
        updated.replaceFirst(',\n  "appCheckDebugToken": ""', ''),
        original,
      );
      // 단계 진행 질문 하나뿐 — 키 값을 묻지 않는다.
      expect(terminal.asks, <String>[stepConfirmQuestion]);
    },
  );

  test('T-19-FILES-03 빠진 키가 없으면 ✓ 이고 아무것도 묻지 않는다', () async {
    userFile(
      UserFilesStep.jsonExamplePath,
    ).copySync(userFile(UserFilesStep.jsonUserPath).path);
    userFile(
      UserFilesStep.xcconfigExamplePath,
    ).copySync(userFile(UserFilesStep.xcconfigUserPath).path);
    final ScriptedTerminal terminal = ScriptedTerminal(const <String?>[]);

    final int code = await runUserFilesStep(terminal);

    expect(code, wizardExitDone);
    expect(terminal.output.toString(), contains('  ✓ 사용자 설정 파일 — '));
    expect(terminal.asks, isEmpty);
  });

  test('T-19-FILES-04 사용자 JSON 이 깨지면 ✗ 이고 y 뒤 실패하며 원본은 그대로다', () async {
    const String broken = '{\n  "flavor": "dev",\n  "appName": \n';
    userFile(UserFilesStep.jsonUserPath).writeAsStringSync(broken);
    final ScriptedTerminal terminal = ScriptedTerminal(const <String?>['y']);

    final int code = await runUserFilesStep(terminal);

    final String output = terminal.output.toString();
    expect(code, wizardExitStopped);
    expect(
      output,
      contains('  ✗ 사용자 설정 파일 — config/dev.json 을 JSON 으로 읽지 못했습니다'),
    );
    expect(output, contains('  실패 — '));
    expect(output, contains('손으로 고친 뒤'));
    expect(userFile(UserFilesStep.jsonUserPath).readAsStringSync(), broken);
    // 다른 사용자 파일도 만들지 않는다.
    expect(userFile(UserFilesStep.xcconfigUserPath).existsSync(), isFalse);
  });

  test('buildDevSteps 는 Xcode 준비 다음에 사용자 설정 파일 단계를 둔다', () {
    final List<String> ids = buildDevSteps()
        .map((Step step) => step.id)
        .toList();

    expect(ids, contains('user_files'));
    expect(ids.indexOf('user_files'), greaterThan(ids.indexOf('xcode')));
  });
}
