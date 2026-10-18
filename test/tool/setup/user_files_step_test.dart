import 'dart:io';
import 'dart:math';

import 'package:test/test.dart';

import '../../../tool/setup/config_files.dart';
import '../../../tool/setup/flavor.dart';
import '../../../tool/setup/providers/provider_catalog.dart';
import '../../../tool/setup/providers/provider_selection.dart';
import '../../../tool/setup/redactor.dart';
import '../../../tool/setup/step.dart';
import '../../../tool/setup/steps/dev_steps.dart';
import '../../../tool/setup/steps/user_files_step.dart';
import '../../../tool/setup/terminal.dart';
import '../../../tool/setup/wizard.dart';
import 'fake_rest_client.dart';
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
      final terminal = ScriptedTerminal(const <String?>['y']);

      final int code = await runUserFilesStep(terminal);

      final output = terminal.output.toString();
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
      final terminal = ScriptedTerminal(const <String?>['y']);

      final int code = await runUserFilesStep(terminal);

      final output = terminal.output.toString();
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
    final terminal = ScriptedTerminal(const <String?>[]);

    final int code = await runUserFilesStep(terminal);

    expect(code, wizardExitDone);
    expect(terminal.output.toString(), contains('  ✓ 사용자 설정 파일 — '));
    expect(terminal.asks, isEmpty);
  });

  test('T-19-FILES-04 사용자 JSON 이 깨지면 ✗ 이고 y 뒤 실패하며 원본은 그대로다', () async {
    const broken = '{\n  "flavor": "dev",\n  "appName": \n';
    userFile(UserFilesStep.jsonUserPath).writeAsStringSync(broken);
    final terminal = ScriptedTerminal(const <String?>['y']);

    final int code = await runUserFilesStep(terminal);

    final output = terminal.output.toString();
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

  group('flavor 문맥', () {
    late ScriptedTerminal screen;
    late MemoryLogSink log;

    setUp(() {
      // stg · prod example 도 임시 저장소로 복사한다.
      for (final flavor in <Flavor>[Flavor.stg, Flavor.prod]) {
        final paths = FlavorPaths(flavor);
        File(paths.jsonExample).copySync(userFile(paths.jsonExample).path);
        File(
          paths.xcconfigExample,
        ).copySync(userFile(paths.xcconfigExample).path);
      }
      log = MemoryLogSink(Redactor());
    });

    /// [flavor] 문맥을 만든다 — 화면은 가림 터미널로 감싼다.
    WizardContext buildFlavorContext(Flavor flavor, List<String?> inputs) {
      screen = ScriptedTerminal(inputs);
      return WizardContext(
        projectRoot: tempDir.path,
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

    /// dev 사용자 config 를 example 에서 만들고 켠 로그인 수단을 [csv] 로 둔다.
    File writeDevConfig(String csv) {
      final File devJson = userFile(const FlavorPaths(Flavor.dev).json);
      userFile(
        const FlavorPaths(Flavor.dev).jsonExample,
      ).copySync(devJson.path);
      replaceJsonString(devJson.path, enabledProvidersKey, csv);
      return devJson;
    }

    /// 체크 목록 단계를 한 번 실행한다 — 위저드처럼 검사 뒤 실행한다.
    Future<StepOutcome> runStep(WizardContext context) async {
      final step = UserFilesStep();
      await step.check(context);
      return await step.apply(context);
    }

    test(
      'T-20-FLAVOR-03: stg 의 새 config 를 만들면 dev 의 로그인 수단을 미리 체크해 묻고 Enter 면 그 값을 쓴다',
      () async {
        final File devJson = writeDevConfig('google,kakao');
        final List<int> devBytes = devJson.readAsBytesSync();
        const stgPaths = FlavorPaths(Flavor.stg);
        final WizardContext context = buildFlavorContext(
          Flavor.stg,
          const <String?>[''],
        );

        final step = UserFilesStep();
        await step.check(context);
        final List<String> planned = step.plannedCommandLines(context);
        final StepOutcome outcome = await step.apply(context);

        final output = screen.output.toString();
        expect(planned, <String>[
          'cp ${stgPaths.jsonExample} ${stgPaths.json}',
          'cp ${stgPaths.xcconfigExample} ${stgPaths.xcconfig}',
        ]);
        expect(outcome, isA<Replan>());
        expect(output, contains(UserFilesStep.newFlavorProvidersNotice));
        expect(output, contains(providerChecklistHeading));
        expect(output, contains('  1) [x] Google'));
        expect(output, contains('  4) [x] Kakao'));
        expect(output, contains('  2) [ ] Apple'));
        expect(screen.asks, <String>[providerChoiceQuestion]);
        expect(
          readJsonString(userFile(stgPaths.json).path, enabledProvidersKey),
          'google,kakao',
        );
        expect(
          userFile(stgPaths.xcconfig).readAsBytesSync(),
          userFile(stgPaths.xcconfigExample).readAsBytesSync(),
        );
        // CSV 밖의 바이트는 stg example 그대로다.
        expect(
          userFile(stgPaths.json).readAsStringSync(),
          userFile(stgPaths.jsonExample).readAsStringSync().replaceFirst(
            '"$enabledProvidersKey": ""',
            '"$enabledProvidersKey": "google,kakao"',
          ),
        );
        // dev 사용자 파일은 읽기만 한다.
        expect(devJson.readAsBytesSync(), devBytes);
        expect(
          userFile(const FlavorPaths(Flavor.dev).xcconfig).existsSync(),
          isFalse,
        );
      },
    );

    test(
      'T-20-FLAVOR-04: 체크 목록에서 0 을 고르면 stg CSV 는 빈 값이고 단계 목록을 다시 짜지 않는다',
      () async {
        writeDevConfig('google,kakao');
        final WizardContext context = buildFlavorContext(
          Flavor.stg,
          const <String?>[emailOnlyAnswer],
        );

        final StepOutcome outcome = await runStep(context);

        expect(outcome, isA<Applied>());
        expect(
          readJsonString(
            userFile(const FlavorPaths(Flavor.stg).json).path,
            enabledProvidersKey,
          ),
          '',
        );
        expect(screen.asks, <String>[providerChoiceQuestion]);
      },
    );

    test(
      'T-20-FLAVOR-04: 체크 목록에서 입력이 끝나면 stg CSV 는 example 값 그대로이고 실행은 끝난다',
      () async {
        writeDevConfig('google,kakao');
        final WizardContext context = buildFlavorContext(
          Flavor.prod,
          const <String?>[],
        );

        final StepOutcome outcome = await runStep(context);

        const prodPaths = FlavorPaths(Flavor.prod);
        expect(outcome, isA<Applied>());
        expect(
          userFile(prodPaths.json).readAsBytesSync(),
          userFile(prodPaths.jsonExample).readAsBytesSync(),
        );
        expect(screen.asks, <String>[providerChoiceQuestion]);
      },
    );

    group('T-20-FLAVOR-04: --providers 로 연 실행에서 dev 제안 체크 목록의 답', () {
      test('답을 쓰면 체크 목록 요청을 꺼 로그인 수단 단계가 다시 열지 않는다', () async {
        writeDevConfig('google,kakao');
        final WizardContext context = buildFlavorContext(
          Flavor.stg,
          const <String?>[''],
        );
        context.session.isProviderSelectionRequested = true;

        final StepOutcome outcome = await runStep(context);

        expect(outcome, isA<Replan>());
        expect(context.session.isProviderSelectionRequested, isFalse);
      });

      test('입력이 끝나면 체크 목록 요청을 그대로 둔다', () async {
        writeDevConfig('google,kakao');
        final WizardContext context = buildFlavorContext(
          Flavor.stg,
          const <String?>[],
        );
        context.session.isProviderSelectionRequested = true;

        final StepOutcome outcome = await runStep(context);

        expect(outcome, isA<Applied>());
        expect(context.session.isProviderSelectionRequested, isTrue);
      });
    });

    test(
      'T-20-FLAVOR-05: stg config 가 이미 있으면 체크 목록을 열지 않고 빠진 키만 채운다',
      () async {
        writeDevConfig('google,kakao');
        const stgPaths = FlavorPaths(Flavor.stg);
        final String withoutToken = userFile(
          stgPaths.jsonExample,
        ).readAsStringSync().replaceFirst(',\n  "appCheckDebugToken": ""', '');
        userFile(stgPaths.json).writeAsStringSync(withoutToken);
        final WizardContext context = buildFlavorContext(
          Flavor.stg,
          const <String?>[],
        );

        final StepOutcome outcome = await runStep(context);

        final String stgJson = userFile(stgPaths.json).readAsStringSync();
        expect(outcome, isA<Applied>());
        expect(screen.asks, isEmpty);
        expect(screen.output.toString(), isEmpty);
        expect(stgJson, contains('"appCheckDebugToken": ""'));
        expect(readJsonString(userFile(stgPaths.json).path, 'flavor'), 'stg');
        expect(
          readJsonString(userFile(stgPaths.json).path, enabledProvidersKey),
          '',
        );
      },
    );

    test(
      'T-20-FLAVOR-05: dev CSV 가 비었거나 dev config 가 없으면 체크 목록을 열지 않는다',
      () async {
        for (final hasDevConfig in <bool>[true, false]) {
          final File devJson = userFile(const FlavorPaths(Flavor.dev).json);
          if (hasDevConfig) {
            writeDevConfig('');
          } else if (devJson.existsSync()) {
            devJson.deleteSync();
          }
          for (final flavor in <Flavor>[Flavor.stg, Flavor.prod]) {
            final paths = FlavorPaths(flavor);
            for (final path in <String>[paths.json, paths.xcconfig]) {
              if (userFile(path).existsSync()) userFile(path).deleteSync();
            }
            final WizardContext context = buildFlavorContext(
              flavor,
              const <String?>[],
            );

            final StepOutcome outcome = await runStep(context);

            expect(outcome, isA<Applied>(), reason: flavor.name);
            expect(screen.asks, isEmpty, reason: flavor.name);
            expect(
              userFile(paths.json).readAsBytesSync(),
              userFile(paths.jsonExample).readAsBytesSync(),
              reason: flavor.name,
            );
          }
          expect(devJson.existsSync(), hasDevConfig);
        }
      },
    );

    test(
      'T-20-FLAVOR-06: dev 문맥은 dev 경로 · 문구 그대로이고 dev config 를 만들어도 체크 목록을 열지 않는다',
      () async {
        final WizardContext context = buildFlavorContext(
          Flavor.dev,
          const <String?>[],
        );

        final step = UserFilesStep();
        final CheckResult result = await step.check(context);
        final List<String> planned = step.plannedCommandLines(context);
        final StepOutcome outcome = await step.apply(context);

        expect(
          result,
          isA<Todo>().having(
            (Todo todo) => todo.reason,
            'reason',
            'config/dev.json 없음 · ios/Flutter/dev.xcconfig 없음',
          ),
        );
        expect(planned, <String>[
          'cp config/dev.example.json config/dev.json',
          'cp ios/Flutter/dev.example.xcconfig ios/Flutter/dev.xcconfig',
        ]);
        expect(outcome, isA<Applied>());
        expect(screen.asks, isEmpty);
        expect(screen.output.toString(), isEmpty);
        // 이미 끝난 dev 파일의 요약 글자도 그대로다.
        final CheckResult after = await step.check(context);
        expect(
          after,
          isA<Done>().having(
            (Done done) => done.summary,
            'summary',
            'config/dev.json · ios/Flutter/dev.xcconfig 에 example 의 키가 모두 있음',
          ),
        );
      },
    );
  });

  test('buildDevSteps 는 Xcode 준비 다음에 사용자 설정 파일 단계를 둔다', () {
    final List<String> ids = buildDevSteps()
        .map((Step step) => step.id)
        .toList();

    expect(ids, contains('user_files'));
    expect(ids.indexOf('user_files'), greaterThan(ids.indexOf('xcode')));
  });
}
