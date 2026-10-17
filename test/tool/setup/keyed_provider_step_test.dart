import 'dart:io';
import 'dart:math';

import 'package:test/test.dart';

import '../../../tool/setup/command_runner.dart';
import '../../../tool/setup/config_files.dart';
import '../../../tool/setup/confirm.dart';
import '../../../tool/setup/flavor.dart';
import '../../../tool/setup/providers/key_formats.dart';
import '../../../tool/setup/providers/keyed_provider_step.dart';
import '../../../tool/setup/providers/provider_catalog.dart';
import '../../../tool/setup/redactor.dart';
import '../../../tool/setup/secret_store.dart';
import '../../../tool/setup/step.dart';
import '../../../tool/setup/steps/kakao_step.dart';
import '../../../tool/setup/terminal.dart';
import '../../../tool/setup/wizard.dart';
import 'fake_rest_client.dart';
import 'fakes.dart';

/// 테스트 프로젝트 ID.
const String projectId = 'keyed-p';

/// fixture Gradle 의 applicationId.
const String applicationId = 'com.example.keyed_app';

/// fixture xcconfig 의 dev 번들 ID.
const String devBundleId = 'com.example.keyedApp.dev';

/// Secret Manager 의 네이티브 앱 키 이름.
const String nativeSecret = 'KAKAO_NATIVE_APP_KEY';

/// Secret Manager 의 어드민 키 이름.
const String adminSecret = 'KAKAO_ADMIN_KEY';

/// 다른 flavor 와 같은 키를 입력했을 때 보이는 문장(dev 와 같을 때).
const String devDuplicateInputLine =
    'dev 의 키와 같습니다 — flavor 마다 새 콘솔 앱의 키를 넣으세요';

/// 실행 시점에 조립하는 가짜 네이티브 앱 키(소문자 16진수 32자).
String buildNativeKey([String letter = 'a']) => letter * 32;

/// 실행 시점에 조립하는 가짜 어드민 키(16진수 32자).
String buildAdminKey([String letter = 'b']) => letter * 32;

/// [haystack] 에서 [needle] 이 나타나는 횟수를 센다.
int countText(String haystack, String needle) =>
    haystack.split(needle).length - 1;

/// 성공 결과.
CommandResult ok([String stdout = '']) => CommandResult(0, stdout, '');

/// Firebase CLI 가 없는 secret 을 읽을 때의 결과 — 오류가 표준 출력에 나온다.
CommandResult buildSecretMissing(String name) => CommandResult(
  1,
  '\nError: Request to https://secretmanager.googleapis.com/v1/projects/'
      '$projectId/secrets/$name/versions/latest:access had HTTP Error: 404, '
      'Secret [projects/000000000000/secrets/$name] not found or has no '
      'versions.\n',
  '',
);

/// 이미 끝난 앞 단계 — 로그인 수단 단계의 의존 단계를 대신한다.
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

/// 서버 확인이 있는 시험용 로그인 수단 — 받은 값을 남기고 정한 결과를 돌려준다.
final class _PairCheckedStep extends KeyedProviderStep {
  _PairCheckedStep(this.fieldList, this.result);

  /// 다룰 값 목록.
  final List<KeyField> fieldList;

  /// 서버 확인이 돌려줄 결과.
  final PairCheck result;

  /// 서버 확인에 넘어온 값(부를 때마다 한 묶음).
  final List<Map<KeyField, String>> verifiedValues = <Map<KeyField, String>>[];

  @override
  String get id => 'pair_checked';

  @override
  String get title => '짝 확인 수단';

  @override
  List<String> get dependsOn => const <String>['providers'];

  @override
  ProviderEntry get entry => findProvider(KakaoStep.token)!;

  @override
  List<KeyField> get fields => fieldList;

  @override
  List<SummaryRow> buildValueRows(WizardContext context) =>
      const <SummaryRow>[];

  @override
  List<String> get todoLines => const <String>[];

  @override
  Future<PairCheck> verifyPair(
    WizardContext context,
    Map<KeyField, String> values,
  ) async {
    verifiedValues.add(Map<KeyField, String>.of(values));
    return result;
  }
}

/// 형식이 느슨한 시험용 값 — 자리표시 판정만 보려고 쓴다.
const KeyField looseField = KeyField(
  label: '느슨한 키',
  format: KeyFormat(label: '느슨한 키', pattern: r'^.+$', description: '아무 글자'),
  configKey: 'kakaoNativeAppKey',
);

/// 단계 하나 실행에 쓰는 가짜 실행기 · REST · 화면 · 기록 묶음.
final class _Harness {
  _Harness(this.root, List<String?> inputs, {this.flavor = Flavor.dev})
    : runner = FakeCommandRunner(),
      rest = FakeRestClient(),
      screen = ScriptedTerminal(inputs),
      log = MemoryLogSink(Redactor());

  final String root;
  final Flavor flavor;
  final FakeCommandRunner runner;
  final FakeRestClient rest;
  final ScriptedTerminal screen;
  final MemoryLogSink log;

  /// 화면 출력 전체.
  String get output => screen.output.toString();

  /// [name] 읽기 결과 큐에 [results] 를 차례로 더한다.
  void onSecretReads(String name, List<CommandResult> results) {
    for (final CommandResult result in results) {
      runner.on(
        FakeCommandRunner.buildKey(buildSecretReadCommand(name, projectId)),
        result,
      );
    }
  }

  /// [name] 쓰기를 성공으로 등록한다.
  void onSecretWrite(String name) => runner.on(
    FakeCommandRunner.buildKey(
      buildSecretWriteCommand(name, projectId, value: '', valueLabel: ''),
    ),
    ok(),
  );

  /// Secret Manager 쓰기 호출.
  List<FakeCall> get secretWrites => <FakeCall>[
    for (final FakeCall call in runner.calls)
      if (call.key.startsWith('firebase functions:secrets:set ')) call,
  ];

  /// [flavor] 문맥으로 위저드를 만든다 — 화면은 가림 터미널로 감싼다.
  WizardContext buildContext() => WizardContext(
    projectRoot: root,
    runner: runner,
    terminal: RedactingTerminal(screen, log.redactor, log),
    redactor: log.redactor,
    log: log,
    rest: rest,
    flavor: flavor,
    random: Random(fixedTestRandomSeed),
    now: () => fixedTestNow,
  );

  /// 앞 단계(끝남) · [step](없으면 Kakao 단계)으로 위저드를 돌린다.
  Future<int> run([Step? step]) => runWizard(buildContext(), <Step>[
    _FinishedStep('providers', '로그인 수단'),
    _FinishedStep('configure', '앱 등록 · 설정 파일'),
    _FinishedStep('apis', '필요한 Google Cloud API'),
    step ?? KakaoStep(),
  ]);
}

void main() {
  late Directory tempDir;
  late String root;

  /// 저장소 상대 경로에 내용을 쓴다(부모 디렉터리를 만든다).
  void writeFixture(String relativePath, String content) {
    File('$root/$relativePath')
      ..parent.createSync(recursive: true)
      ..writeAsStringSync(content);
  }

  /// 저장소의 tracked [source] 를 임시 저장소의 [target] 으로 복사한다.
  void copyTracked(String source, String target) =>
      writeFixture(target, File(source).readAsStringSync());

  /// [flavor] 의 config 절대 경로.
  String configPathOf(Flavor flavor) => '$root/${FlavorPaths(flavor).json}';

  /// [flavor] 의 xcconfig 절대 경로.
  String xcconfigPathOf(Flavor flavor) =>
      '$root/${FlavorPaths(flavor).xcconfig}';

  /// [flavor] 의 example 두 파일과 사용자 파일 두 개를 example 복사로 만든다.
  void prepareFlavorFiles(Flavor flavor) {
    final FlavorPaths paths = FlavorPaths(flavor);
    copyTracked(paths.jsonExample, paths.jsonExample);
    copyTracked(paths.xcconfigExample, paths.xcconfigExample);
    copyTracked(paths.jsonExample, paths.json);
    copyTracked(paths.xcconfigExample, paths.xcconfig);
  }

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('keyed_provider_step_test_');
    root = tempDir.path;
    prepareFlavorFiles(Flavor.dev);
    replaceJsonString(configPathOf(Flavor.dev), 'firebaseProjectId', projectId);
    replaceJsonString(
      configPathOf(Flavor.dev),
      'enabledAuthProviders',
      KakaoStep.token,
    );
    replaceXcconfigValue(
      xcconfigPathOf(Flavor.dev),
      'PRODUCT_BUNDLE_IDENTIFIER',
      devBundleId,
    );
    writeFixture(
      'android/app/build.gradle.kts',
      'android {\n'
          '    defaultConfig {\n'
          '        applicationId = "$applicationId"\n'
          '    }\n'
          '}\n',
    );
  });

  tearDown(() {
    tempDir.deleteSync(recursive: true);
  });

  /// [flavor] config 의 네이티브 앱 키를 [value] 로 둔다.
  void setConfigNativeKey(Flavor flavor, String value) => replaceJsonString(
    configPathOf(flavor),
    KakaoStep.nativeAppKeyField.configKey!,
    value,
  );

  /// [flavor] xcconfig 의 네이티브 앱 키를 [value] 로 둔다.
  void setXcconfigNativeKey(Flavor flavor, String value) =>
      replaceXcconfigValue(
        xcconfigPathOf(flavor),
        KakaoStep.nativeAppKeyField.xcconfigVar!,
        value,
      );

  /// [flavor] config 의 네이티브 앱 키.
  String? readConfigNativeKey(Flavor flavor) => readJsonString(
    configPathOf(flavor),
    KakaoStep.nativeAppKeyField.configKey!,
  );

  /// [flavor] xcconfig 의 네이티브 앱 키.
  String? readXcconfigNativeKey(Flavor flavor) => readXcconfigValue(
    xcconfigPathOf(flavor),
    KakaoStep.nativeAppKeyField.xcconfigVar!,
  );

  /// 화면 질문 가운데 [label] 로 시작하는 것의 수.
  int countQuestions(_Harness h, String label) =>
      h.screen.asks.where((String ask) => ask.startsWith(label)).length;

  /// 점검표 · 단계 머리의 ✗ 줄.
  String buildTodoLine(String reason) => '  ✗ ${KakaoStep.stepTitle} — $reason';

  test('T-20-BASE-01: config 실 값 · xcconfig 다름 · Secret Manager 같음 → '
      'xcconfig 자리 이름만 보이고 질문 없이 config 값으로 맞춘다', () async {
    final String nativeKey = buildNativeKey();
    final String adminKey = buildAdminKey();
    setConfigNativeKey(Flavor.dev, nativeKey);
    final String configBefore = File(
      configPathOf(Flavor.dev),
    ).readAsStringSync();
    final _Harness h = _Harness(root, const <String?>['y']);
    h
      ..onSecretReads(nativeSecret, <CommandResult>[ok('$nativeKey\n')])
      ..onSecretReads(adminSecret, <CommandResult>[ok('$adminKey\n')]);

    final int code = await h.run();

    expect(code, wizardExitDone, reason: h.output);
    expect(
      h.output,
      contains(
        buildTodoLine(
          'config 와 다른 자리: ios/Flutter/dev.xcconfig KAKAO_NATIVE_APP_KEY',
        ),
      ),
    );
    expect(h.output, isNot(contains('Secret Manager $nativeSecret')));
    expect(h.output, contains('── Kakao — config 값으로 맞출 자리 ──'));
    expect(h.output, isNot(contains('콘솔에 넣을 값')));
    expect(h.screen.asks, <String>[stepConfirmQuestion]);
    expect(h.screen.secretAsks, isEmpty);
    expect(readXcconfigNativeKey(Flavor.dev), nativeKey);
    expect(File(configPathOf(Flavor.dev)).readAsStringSync(), configBefore);
    expect(h.secretWrites, isEmpty);
    expect(h.rest.externalRequests, isEmpty);
    for (final String text in <String>[h.output, h.log.text]) {
      expect(countText(text, nativeKey), 0);
      expect(countText(text, adminKey), 0);
    }
    expect(h.output, contains('  ✓ ${KakaoStep.stepTitle} — '));
  });

  test('T-20-BASE-02: Secret Manager 네이티브 앱 키가 다른 실 값 → Secret Manager '
      '자리 이름 · 표준 입력으로 config 값 한 번 쓰기 · 옛 값 출력 0', () async {
    final String nativeKey = buildNativeKey();
    final String oldKey = buildNativeKey('c');
    final String adminKey = buildAdminKey();
    setConfigNativeKey(Flavor.dev, nativeKey);
    setXcconfigNativeKey(Flavor.dev, nativeKey);
    final _Harness h = _Harness(root, const <String?>['y']);
    h
      ..onSecretReads(nativeSecret, <CommandResult>[
        ok('$oldKey\n'),
        ok('$oldKey\n'),
        ok('$nativeKey\n'),
      ])
      ..onSecretReads(adminSecret, <CommandResult>[ok('$adminKey\n')])
      ..onSecretWrite(nativeSecret);

    final int code = await h.run();

    expect(code, wizardExitDone, reason: h.output);
    expect(
      h.output,
      contains(buildTodoLine('config 와 다른 자리: Secret Manager $nativeSecret')),
    );
    expect(h.screen.asks, <String>[stepConfirmQuestion]);
    expect(h.secretWrites, hasLength(1));
    expect(h.secretWrites.single.stdinText, nativeKey);
    expect(h.secretWrites.single.isOutputSensitive, isTrue);
    expect(h.rest.externalRequests, isEmpty);
    for (final String text in <String>[h.output, h.log.text]) {
      expect(countText(text, oldKey), 0);
      expect(countText(text, nativeKey), 0);
    }
  });

  group('T-20-BASE-03: 서버 전용 어드민 키가 unset 이 아니면 묻지 않고 서버 확인도 하지 않는다', () {
    test('맞출 자리가 있을 때', () async {
      final String nativeKey = buildNativeKey();
      final String adminKey = buildAdminKey();
      setConfigNativeKey(Flavor.dev, nativeKey);
      final _Harness h = _Harness(root, const <String?>['y']);
      h
        ..onSecretReads(nativeSecret, <CommandResult>[
          ok('$secretPlaceholderValue\n'),
          ok('$secretPlaceholderValue\n'),
          ok('$nativeKey\n'),
        ])
        ..onSecretReads(adminSecret, <CommandResult>[ok('$adminKey\n')])
        ..onSecretWrite(nativeSecret);

      final int code = await h.run();

      expect(code, wizardExitDone, reason: h.output);
      expect(countQuestions(h, KakaoStep.adminKeyField.label), 0);
      expect(h.screen.secretAsks, isEmpty);
      expect(h.rest.externalRequests, isEmpty);
      expect(
        h.secretWrites.map((FakeCall call) => call.key),
        everyElement(isNot(contains(adminSecret))),
      );
      expect(countText(h.output, adminKey), 0);
      expect(countText(h.log.text, adminKey), 0);
    });

    test('모두 맞을 때', () async {
      final String nativeKey = buildNativeKey();
      setConfigNativeKey(Flavor.dev, nativeKey);
      setXcconfigNativeKey(Flavor.dev, nativeKey);
      final _Harness h = _Harness(root, const <String?>[]);
      h
        ..onSecretReads(nativeSecret, <CommandResult>[ok('$nativeKey\n')])
        ..onSecretReads(adminSecret, <CommandResult>[
          ok('${buildAdminKey()}\n'),
        ]);

      final int code = await h.run();

      expect(code, wizardExitDone, reason: h.output);
      expect(h.screen.asks, isEmpty);
      expect(h.rest.externalRequests, isEmpty);
      expect(h.secretWrites, isEmpty);
      expect(h.output, contains('  ✓ ${KakaoStep.stepTitle} — '));
    });
  });

  test('T-20-BASE-04: stg 의 네이티브 앱 키가 dev 와 같으면 ✗ 뒤 콘솔 질문 → 새 값을 '
      '받아 stg config · xcconfig 에 쓰고 dev 파일은 그대로다', () async {
    final String devKey = buildNativeKey();
    final String newKey = buildNativeKey('d');
    prepareFlavorFiles(Flavor.stg);
    // stg 문맥은 stg config 의 프로젝트 ID 를 읽는다.
    replaceJsonString(configPathOf(Flavor.stg), 'firebaseProjectId', projectId);
    setConfigNativeKey(Flavor.dev, devKey);
    setXcconfigNativeKey(Flavor.dev, devKey);
    setConfigNativeKey(Flavor.stg, devKey);
    final String devConfigBefore = File(
      configPathOf(Flavor.dev),
    ).readAsStringSync();
    final String devXcconfigBefore = File(
      xcconfigPathOf(Flavor.dev),
    ).readAsStringSync();
    final _Harness h = _Harness(root, <String?>[
      'y',
      '1',
      newKey,
    ], flavor: Flavor.stg);
    h
      ..onSecretReads(nativeSecret, <CommandResult>[
        buildSecretMissing(nativeSecret),
        buildSecretMissing(nativeSecret),
        ok('$newKey\n'),
      ])
      ..onSecretReads(adminSecret, <CommandResult>[ok('${buildAdminKey()}\n')])
      ..onSecretWrite(nativeSecret);

    final int code = await h.run();

    expect(code, wizardExitDone, reason: h.output);
    expect(
      h.output,
      contains(
        buildTodoLine('dev 의 키와 같습니다 — ${KakaoStep.nativeAppKeyField.label}'),
      ),
    );
    expect(h.output, contains('── Kakao 콘솔에 넣을 값 — stg ──'));
    expect(h.output, contains('매뉴얼 「Kakao 검수」'));
    expect(h.screen.asks, <String>[
      stepConfirmQuestion,
      consoleReadyQuestion,
      KakaoStep.nativeAppKeyField.label,
    ]);
    expect(readConfigNativeKey(Flavor.stg), newKey);
    expect(readXcconfigNativeKey(Flavor.stg), newKey);
    expect(h.secretWrites.single.stdinText, newKey);
    expect(File(configPathOf(Flavor.dev)).readAsStringSync(), devConfigBefore);
    expect(
      File(xcconfigPathOf(Flavor.dev)).readAsStringSync(),
      devXcconfigBefore,
    );
    expect(countText(h.output, devDuplicateInputLine), 0);
  });

  group('T-20-BASE-05: 입력 값이 다른 flavor 값과 같으면 같은 문장으로 다시 묻는다', () {
    test('3회 같으면 쓰지 않고 멈춘다', () async {
      final String devKey = buildNativeKey();
      prepareFlavorFiles(Flavor.stg);
      // stg 문맥은 stg config 의 프로젝트 ID 를 읽는다.
      replaceJsonString(
        configPathOf(Flavor.stg),
        'firebaseProjectId',
        projectId,
      );
      setConfigNativeKey(Flavor.dev, devKey);
      final String stgConfigBefore = File(
        configPathOf(Flavor.stg),
      ).readAsStringSync();
      final String stgXcconfigBefore = File(
        xcconfigPathOf(Flavor.stg),
      ).readAsStringSync();
      final String devConfigBefore = File(
        configPathOf(Flavor.dev),
      ).readAsStringSync();
      final _Harness h = _Harness(root, <String?>[
        'y',
        '1',
        devKey,
        devKey,
        devKey,
      ], flavor: Flavor.stg);
      h
        ..onSecretReads(nativeSecret, <CommandResult>[
          buildSecretMissing(nativeSecret),
        ])
        ..onSecretReads(adminSecret, <CommandResult>[
          ok('${buildAdminKey()}\n'),
        ]);

      final int code = await h.run();

      expect(code, wizardExitStopped, reason: h.output);
      expect(countText(h.output, devDuplicateInputLine), 3);
      expect(countQuestions(h, KakaoStep.nativeAppKeyField.label), 3);
      expect(h.output, isNot(contains('형식 맞음')));
      expect(h.secretWrites, isEmpty);
      expect(
        File(configPathOf(Flavor.stg)).readAsStringSync(),
        stgConfigBefore,
      );
      expect(
        File(xcconfigPathOf(Flavor.stg)).readAsStringSync(),
        stgXcconfigBefore,
      );
      expect(
        File(configPathOf(Flavor.dev)).readAsStringSync(),
        devConfigBefore,
      );
    });

    test('같은 값 뒤 새 값이면 그 값으로 진행한다', () async {
      final String devKey = buildNativeKey();
      final String newKey = buildNativeKey('e');
      prepareFlavorFiles(Flavor.stg);
      // stg 문맥은 stg config 의 프로젝트 ID 를 읽는다.
      replaceJsonString(
        configPathOf(Flavor.stg),
        'firebaseProjectId',
        projectId,
      );
      setConfigNativeKey(Flavor.dev, devKey);
      final _Harness h = _Harness(root, <String?>[
        'y',
        '1',
        devKey,
        newKey,
      ], flavor: Flavor.stg);
      h
        ..onSecretReads(nativeSecret, <CommandResult>[
          buildSecretMissing(nativeSecret),
          buildSecretMissing(nativeSecret),
          ok('$newKey\n'),
        ])
        ..onSecretReads(adminSecret, <CommandResult>[
          ok('${buildAdminKey()}\n'),
        ])
        ..onSecretWrite(nativeSecret);

      final int code = await h.run();

      expect(code, wizardExitDone, reason: h.output);
      expect(countText(h.output, devDuplicateInputLine), 1);
      expect(countQuestions(h, KakaoStep.nativeAppKeyField.label), 2);
      expect(readConfigNativeKey(Flavor.stg), newKey);
      expect(h.secretWrites.single.stdinText, newKey);
    });
  });

  test('T-20-BASE-06: 서버 확인이 있는 수단의 맞춤 전 짝 확인이 틀리면 아무것도 쓰지 않고 '
      'config 를 고치라는 실패로 끝난다', () async {
    final String nativeKey = buildNativeKey();
    setConfigNativeKey(Flavor.dev, nativeKey);
    final String xcconfigBefore = File(
      xcconfigPathOf(Flavor.dev),
    ).readAsStringSync();
    final _PairCheckedStep step = _PairCheckedStep(const <KeyField>[
      KakaoStep.nativeAppKeyField,
    ], const PairMismatch(KakaoStep.nativeAppKeyField, '짝이 맞지 않습니다'));
    final _Harness h = _Harness(root, const <String?>['y', '2']);
    h.onSecretReads(nativeSecret, <CommandResult>[ok('$nativeKey\n')]);

    final int code = await h.run(step);

    expect(code, wizardExitStopped, reason: h.output);
    expect(h.output, contains('config 와 다른 자리: '));
    expect(step.verifiedValues, hasLength(1));
    expect(step.verifiedValues.single, <KeyField, String>{
      KakaoStep.nativeAppKeyField: nativeKey,
    });
    expect(h.output, contains('짝이 맞지 않습니다 — config/dev.json'));
    expect(h.screen.asks.last, failureChoiceQuestion);
    expect(h.screen.secretAsks, isEmpty);
    expect(h.secretWrites, isEmpty);
    expect(File(xcconfigPathOf(Flavor.dev)).readAsStringSync(), xcconfigBefore);
    expect(countText(h.output, nativeKey), 0);
  });

  group('T-20-BASE-07: 다른 flavor 파일이 없거나 그 값이 자리표시면 중복이 아니다', () {
    test('다른 flavor 파일이 없다', () async {
      final String nativeKey = buildNativeKey();
      setConfigNativeKey(Flavor.dev, nativeKey);
      setXcconfigNativeKey(Flavor.dev, nativeKey);
      final _Harness h = _Harness(root, const <String?>[]);
      h
        ..onSecretReads(nativeSecret, <CommandResult>[ok('$nativeKey\n')])
        ..onSecretReads(adminSecret, <CommandResult>[
          ok('${buildAdminKey()}\n'),
        ]);

      final int code = await h.run();

      expect(code, wizardExitDone, reason: h.output);
      expect(h.output, isNot(contains('의 키와 같습니다')));
      expect(h.output, contains('  ✓ ${KakaoStep.stepTitle} — '));
    });

    test('다른 flavor 값이 그 flavor 의 자리표시다', () async {
      prepareFlavorFiles(Flavor.stg);
      final String stgPlaceholder = readConfigNativeKey(Flavor.stg)!;
      setConfigNativeKey(Flavor.dev, stgPlaceholder);
      final _PairCheckedStep step = _PairCheckedStep(const <KeyField>[
        looseField,
      ], const PairOk());
      final _Harness h = _Harness(root, const <String?>[]);

      final int code = await h.run(step);

      expect(code, wizardExitDone, reason: h.output);
      expect(h.output, isNot(contains('의 키와 같습니다')));
      expect(h.output, contains('  ✓ 짝 확인 수단 — '));
      expect(step.verifiedValues, isEmpty);
    });

    test('다른 flavor 값이 다른 실 값이다', () async {
      final String nativeKey = buildNativeKey();
      prepareFlavorFiles(Flavor.stg);
      setConfigNativeKey(Flavor.stg, buildNativeKey('f'));
      setConfigNativeKey(Flavor.dev, nativeKey);
      setXcconfigNativeKey(Flavor.dev, nativeKey);
      final _Harness h = _Harness(root, const <String?>[]);
      h
        ..onSecretReads(nativeSecret, <CommandResult>[ok('$nativeKey\n')])
        ..onSecretReads(adminSecret, <CommandResult>[
          ok('${buildAdminKey()}\n'),
        ]);

      final int code = await h.run();

      expect(code, wizardExitDone, reason: h.output);
      expect(h.output, isNot(contains('의 키와 같습니다')));
    });
  });
}
