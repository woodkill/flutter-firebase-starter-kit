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
import '../../../tool/setup/rest_client.dart';
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
    for (final result in results) {
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

  /// 어드민 키 서버 확인 응답 큐에 [responses] 를 더한다.
  void onAdminCheck(List<RestResponse> responses) {
    for (final response in responses) {
      rest.onExternal('GET', KakaoStep.adminKeyCheckUrl, response);
    }
  }

  /// 서버 확인에 실린 어드민 키 헤더(요청마다 하나).
  List<String?> get adminCheckHeaders => <String?>[
    for (final ExternalRequest request in rest.externalRequests)
      request.headers['Authorization'],
  ];

  /// Secret Manager 쓰기 호출.
  List<FakeCall> get secretWrites => <FakeCall>[
    for (final FakeCall call in runner.calls)
      if (call.key.startsWith('firebase functions:secrets:set ')) call,
  ];

  /// [flavor] 문맥으로 위저드를 만든다 — 화면은 가림 터미널로 감싸고, 홈은
  /// 키스토어가 없는 경로로 둔다(개발자 홈의 키스토어 · keytool 에 닿지 않는다).
  WizardContext buildContext() => WizardContext(
    projectRoot: root,
    runner: runner,
    terminal: RedactingTerminal(screen, log.redactor, log),
    redactor: log.redactor,
    log: log,
    rest: rest,
    flavor: flavor,
    homeDirectory: noKeystoreTestHome,
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
    final paths = FlavorPaths(flavor);
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
    final h = _Harness(root, const <String?>['y']);
    h
      ..onSecretReads(nativeSecret, <CommandResult>[ok('$nativeKey\n')])
      ..onSecretReads(adminSecret, <CommandResult>[ok('$adminKey\n')])
      ..onAdminCheck(<RestResponse>[const RestResponse(200, '{}')]);

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
    // 맞춤 전 짝 확인 1회 — Secret Manager 의 어드민 키(메모리)를 헤더에만 싣는다.
    expect(h.adminCheckHeaders, <String>['KakaoAK $adminKey']);
    for (final text in <String>[h.output, h.log.text]) {
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
    final h = _Harness(root, const <String?>['y']);
    h
      ..onSecretReads(nativeSecret, <CommandResult>[
        ok('$oldKey\n'),
        ok('$oldKey\n'),
        ok('$nativeKey\n'),
      ])
      ..onSecretReads(adminSecret, <CommandResult>[ok('$adminKey\n')])
      ..onSecretWrite(nativeSecret)
      ..onAdminCheck(<RestResponse>[const RestResponse(200, '{}')]);

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
    expect(h.adminCheckHeaders, <String>['KakaoAK $adminKey']);
    for (final text in <String>[h.output, h.log.text]) {
      expect(countText(text, oldKey), 0);
      expect(countText(text, nativeKey), 0);
      expect(countText(text, adminKey), 0);
    }
  });

  group('T-20-BASE-03: 서버 전용 어드민 키가 unset 이 아니면 묻지 않고 쓰지 않는다 — '
      '맞춤 실행은 그 Secret Manager 값으로 서버 확인을 한 번 한다', () {
    test('맞출 자리가 있을 때', () async {
      final String nativeKey = buildNativeKey();
      final String adminKey = buildAdminKey();
      setConfigNativeKey(Flavor.dev, nativeKey);
      final h = _Harness(root, const <String?>['y']);
      h
        ..onSecretReads(nativeSecret, <CommandResult>[
          ok('$secretPlaceholderValue\n'),
          ok('$secretPlaceholderValue\n'),
          ok('$nativeKey\n'),
        ])
        ..onSecretReads(adminSecret, <CommandResult>[ok('$adminKey\n')])
        ..onSecretWrite(nativeSecret)
        ..onAdminCheck(<RestResponse>[const RestResponse(200, '{}')]);

      final int code = await h.run();

      expect(code, wizardExitDone, reason: h.output);
      expect(countQuestions(h, KakaoStep.adminKeyField.label), 0);
      expect(h.screen.secretAsks, isEmpty);
      expect(h.adminCheckHeaders, <String>['KakaoAK $adminKey']);
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
      final h = _Harness(root, const <String?>[]);
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
    final h = _Harness(root, <String?>['y', '1', newKey], flavor: Flavor.stg);
    h
      ..onSecretReads(nativeSecret, <CommandResult>[
        buildSecretMissing(nativeSecret),
        buildSecretMissing(nativeSecret),
        ok('$newKey\n'),
      ])
      ..onSecretReads(adminSecret, <CommandResult>[ok('${buildAdminKey()}\n')])
      ..onSecretWrite(nativeSecret)
      ..onAdminCheck(<RestResponse>[const RestResponse(200, '{}')]);

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
    expect(h.adminCheckHeaders, <String>['KakaoAK ${buildAdminKey()}']);
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
      final h = _Harness(root, <String?>[
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
      final h = _Harness(root, <String?>[
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
        ..onSecretWrite(nativeSecret)
        ..onAdminCheck(<RestResponse>[const RestResponse(200, '{}')]);

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
    final step = _PairCheckedStep(const <KeyField>[
      KakaoStep.nativeAppKeyField,
    ], const PairMismatch(KakaoStep.nativeAppKeyField, '짝이 맞지 않습니다'));
    final h = _Harness(root, const <String?>['y', '2']);
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
      final h = _Harness(root, const <String?>[]);
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
      final step = _PairCheckedStep(const <KeyField>[
        looseField,
      ], const PairOk());
      final h = _Harness(root, const <String?>[]);

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
      final h = _Harness(root, const <String?>[]);
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

  group('T-20-BASE-08: 보이는 값은 제안 기본값을 받고 숨김 값은 기본값을 받지 않는다', () {
    test('Enter 면 제안값을 기록하고 숨김 값은 빈 답을 형식 오류로 다시 묻는다', () async {
      final String suggestion = buildNativeKey('9');
      final String adminKey = buildAdminKey();
      final h = _Harness(root, <String?>['y', '1', '', '', adminKey]);
      h
        ..onSecretReads(nativeSecret, <CommandResult>[
          buildSecretMissing(nativeSecret),
          buildSecretMissing(nativeSecret),
          ok('$suggestion\n'),
        ])
        ..onSecretReads(adminSecret, <CommandResult>[
          buildSecretMissing(adminSecret),
          buildSecretMissing(adminSecret),
          ok('$adminKey\n'),
        ])
        ..onSecretWrite(nativeSecret)
        ..onSecretWrite(adminSecret);

      final int code = await h.run(_SuggestingStep(suggestion));

      expect(code, wizardExitDone, reason: h.output);
      expect(readConfigNativeKey(Flavor.dev), suggestion);
      expect(readXcconfigNativeKey(Flavor.dev), suggestion);
      expect(countQuestions(h, KakaoStep.nativeAppKeyField.label), 1);
      expect(h.screen.secretAsks, hasLength(2));
      expect(
        h.output,
        contains('${KakaoStep.adminKeyField.label} 형식이 맞지 않습니다 — 0자'),
      );
      expect(h.secretWrites.map((FakeCall call) => call.stdinText), <String>[
        suggestion,
        adminKey,
      ]);
      expect(countText(h.output, adminKey), 0);
      expect(countText(h.log.text, adminKey), 0);
    });

    test('값을 입력하면 제안값이 아니라 입력값을 기록한다', () async {
      final String suggestion = buildNativeKey('9');
      final String typed = buildNativeKey('7');
      final String adminKey = buildAdminKey();
      final h = _Harness(root, <String?>['y', '1', typed, adminKey]);
      h
        ..onSecretReads(nativeSecret, <CommandResult>[
          buildSecretMissing(nativeSecret),
          buildSecretMissing(nativeSecret),
          ok('$typed\n'),
        ])
        ..onSecretReads(adminSecret, <CommandResult>[
          buildSecretMissing(adminSecret),
          buildSecretMissing(adminSecret),
          ok('$adminKey\n'),
        ])
        ..onSecretWrite(nativeSecret)
        ..onSecretWrite(adminSecret);

      final int code = await h.run(_SuggestingStep(suggestion));

      expect(code, wizardExitDone, reason: h.output);
      expect(readConfigNativeKey(Flavor.dev), typed);
      expect(readXcconfigNativeKey(Flavor.dev), typed);
      expect(h.secretWrites.first.stdinText, typed);
      expect(h.screen.secretAsks, hasLength(1));
    });

    test('제안 훅이 없는 단계는 Enter 를 빈 값으로 받아 형식 오류로 다시 묻는다', () async {
      final String nativeKey = buildNativeKey();
      final step = _PairCheckedStep(const <KeyField>[
        KakaoStep.nativeAppKeyField,
      ], const PairOk());
      final h = _Harness(root, <String?>['y', '1', '', nativeKey]);
      h
        ..onSecretReads(nativeSecret, <CommandResult>[
          buildSecretMissing(nativeSecret),
          buildSecretMissing(nativeSecret),
          ok('$nativeKey\n'),
        ])
        ..onSecretWrite(nativeSecret);

      final int code = await h.run(step);

      expect(code, wizardExitDone, reason: h.output);
      expect(
        h.output,
        contains('${KakaoStep.nativeAppKeyField.label} 형식이 맞지 않습니다 — 0자'),
      );
      expect(countQuestions(h, KakaoStep.nativeAppKeyField.label), 2);
      expect(readConfigNativeKey(Flavor.dev), nativeKey);
    });
  });

  group('T-20-BASE-09: 짝 불일치가 여러 값을 가리키면 이번에 물은 값만 순서대로 다시 묻는다', () {
    test('두 값을 가리키면 두 값을 다시 묻고 두 번째 확인이 맞으면 기록한다', () async {
      final String firstNative = buildNativeKey('1');
      final String firstAdmin = buildAdminKey('2');
      final String secondNative = buildNativeKey('3');
      final String secondAdmin = buildAdminKey('4');
      final adminQuestion = '${KakaoStep.adminKeyField.label} $hiddenInputHint';
      final step = _ScriptedPairStep(
        const <KeyField>[KakaoStep.nativeAppKeyField, KakaoStep.adminKeyField],
        const <PairCheck>[
          PairMismatch(
            KakaoStep.nativeAppKeyField,
            '짝이 맞지 않습니다',
            alsoFields: <KeyField>[KakaoStep.adminKeyField],
          ),
          PairOk(),
        ],
      );
      final h = _Harness(root, <String?>[
        'y',
        '1',
        firstNative,
        firstAdmin,
        secondNative,
        secondAdmin,
      ]);
      h
        ..onSecretReads(nativeSecret, <CommandResult>[
          buildSecretMissing(nativeSecret),
          buildSecretMissing(nativeSecret),
          ok('$secondNative\n'),
        ])
        ..onSecretReads(adminSecret, <CommandResult>[
          buildSecretMissing(adminSecret),
          buildSecretMissing(adminSecret),
          ok('$secondAdmin\n'),
        ])
        ..onSecretWrite(nativeSecret)
        ..onSecretWrite(adminSecret);

      final int code = await h.run(step);

      expect(code, wizardExitDone, reason: h.output);
      expect(h.screen.asks, <String>[
        stepConfirmQuestion,
        consoleReadyQuestion,
        KakaoStep.nativeAppKeyField.label,
        adminQuestion,
        KakaoStep.nativeAppKeyField.label,
        adminQuestion,
      ]);
      expect(countText(h.output, '  짝이 맞지 않습니다'), 1);
      expect(step.verifiedValues, hasLength(2));
      expect(step.verifiedValues.last, <KeyField, String>{
        KakaoStep.nativeAppKeyField: secondNative,
        KakaoStep.adminKeyField: secondAdmin,
      });
      expect(readConfigNativeKey(Flavor.dev), secondNative);
      expect(readXcconfigNativeKey(Flavor.dev), secondNative);
      expect(h.secretWrites.map((FakeCall call) => call.stdinText), <String>[
        secondNative,
        secondAdmin,
      ]);
      for (final text in <String>[h.output, h.log.text]) {
        expect(countText(text, firstAdmin), 0);
        expect(countText(text, secondAdmin), 0);
      }
    });

    test('가리킨 값이 모두 이번에 묻지 않은 값이면 쓰지 않고 실패로 끝난다', () async {
      final String nativeKey = buildNativeKey();
      final String adminKey = buildAdminKey();
      setConfigNativeKey(Flavor.dev, nativeKey);
      setXcconfigNativeKey(Flavor.dev, nativeKey);
      final step = _ScriptedPairStep(
        const <KeyField>[KakaoStep.nativeAppKeyField, KakaoStep.adminKeyField],
        const <PairCheck>[
          PairMismatch(
            KakaoStep.nativeAppKeyField,
            '짝이 맞지 않습니다',
            alsoFields: <KeyField>[looseField],
          ),
        ],
      );
      final h = _Harness(root, <String?>['y', '1', adminKey, '2']);
      h
        ..onSecretReads(nativeSecret, <CommandResult>[ok('$nativeKey\n')])
        ..onSecretReads(adminSecret, <CommandResult>[
          buildSecretMissing(adminSecret),
        ]);

      final int code = await h.run(step);

      expect(code, wizardExitStopped, reason: h.output);
      expect(countQuestions(h, KakaoStep.nativeAppKeyField.label), 0);
      expect(h.screen.secretAsks, hasLength(1));
      expect(step.verifiedValues, hasLength(1));
      expect(h.output, contains('짝이 맞지 않습니다'));
      expect(h.screen.asks.last, failureChoiceQuestion);
      expect(h.secretWrites, isEmpty);
      expect(countText(h.output, adminKey), 0);
    });

    test('맞춤 실행의 불일치 문장은 가리킨 값의 자리를 모두 적는다', () async {
      final String nativeKey = buildNativeKey();
      const secondValue = 'abc123';
      setConfigNativeKey(Flavor.dev, nativeKey);
      replaceJsonString(
        configPathOf(Flavor.dev),
        secondLooseField.configKey!,
        secondValue,
      );
      final String xcconfigBefore = File(
        xcconfigPathOf(Flavor.dev),
      ).readAsStringSync();
      final step = _ScriptedPairStep(
        const <KeyField>[KakaoStep.nativeAppKeyField, secondLooseField],
        const <PairCheck>[
          PairMismatch(
            KakaoStep.nativeAppKeyField,
            '짝이 맞지 않습니다',
            alsoFields: <KeyField>[secondLooseField],
          ),
        ],
      );
      final h = _Harness(root, const <String?>['y', '2']);
      h.onSecretReads(nativeSecret, <CommandResult>[ok('$nativeKey\n')]);

      final int code = await h.run(step);

      expect(code, wizardExitStopped, reason: h.output);
      expect(
        h.output,
        contains(
          '짝이 맞지 않습니다 — config/dev.json kakaoNativeAppKey · '
          'config/dev.json naverClientId 값을 고치거나',
        ),
      );
      expect(step.verifiedValues.single, <KeyField, String>{
        KakaoStep.nativeAppKeyField: nativeKey,
        secondLooseField: secondValue,
      });
      expect(h.screen.secretAsks, isEmpty);
      expect(h.secretWrites, isEmpty);
      expect(
        File(xcconfigPathOf(Flavor.dev)).readAsStringSync(),
        xcconfigBefore,
      );
    });
  });

  group('T-20-BASE-10: Secret Manager 의 서버 전용 secret 이 옛 값이면 서버 확인이 '
      '틀려 아무것도 쓰지 않고 그 자리 이름 · 되돌리는 방법을 보인다', () {
    /// 어드민 키가 틀렸을 때의 실패 안내 — 자리 이름과 되돌리는 방법.
    const staleGuide =
        'Secret Manager $adminSecret 값을 고치거나 $secretPlaceholderValue 으로 '
        '되돌린 뒤 다시 실행하면 새로 묻습니다 '
        '(매뉴얼 「로그인 수단 켜고 끄기」 「켜기」 ④)';

    test('입력 실행 — 새 네이티브 앱 키 + 옛 어드민 키', () async {
      final String newNative = buildNativeKey('5');
      final String staleAdmin = buildAdminKey('6');
      final String configBefore = File(
        configPathOf(Flavor.dev),
      ).readAsStringSync();
      final String xcconfigBefore = File(
        xcconfigPathOf(Flavor.dev),
      ).readAsStringSync();
      final h = _Harness(root, <String?>['y', '1', newNative, '2']);
      h
        ..onSecretReads(nativeSecret, <CommandResult>[
          buildSecretMissing(nativeSecret),
        ])
        ..onSecretReads(adminSecret, <CommandResult>[ok('$staleAdmin\n')])
        ..onAdminCheck(<RestResponse>[const RestResponse(401, '{}')]);

      final int code = await h.run();

      expect(code, wizardExitStopped, reason: h.output);
      expect(h.adminCheckHeaders, <String>['KakaoAK $staleAdmin']);
      expect(countQuestions(h, KakaoStep.adminKeyField.label), 0);
      expect(h.screen.secretAsks, isEmpty);
      expect(
        h.output,
        contains(
          '${KakaoStep.adminKeyMismatchMessage} — HTTP 401 — $staleGuide',
        ),
      );
      expect(h.screen.asks.last, failureChoiceQuestion);
      expect(h.secretWrites, isEmpty);
      expect(File(configPathOf(Flavor.dev)).readAsStringSync(), configBefore);
      expect(
        File(xcconfigPathOf(Flavor.dev)).readAsStringSync(),
        xcconfigBefore,
      );
      // 네이티브 앱 키는 보이는 입력이라 기록에 남는다 — 비밀 값만 센다.
      for (final text in <String>[h.output, h.log.text]) {
        expect(countText(text, staleAdmin), 0);
      }
    });

    test('맞춤 실행 — config 네이티브 앱 키 + 옛 어드민 키', () async {
      final String nativeKey = buildNativeKey();
      final String staleAdmin = buildAdminKey('6');
      setConfigNativeKey(Flavor.dev, nativeKey);
      final String xcconfigBefore = File(
        xcconfigPathOf(Flavor.dev),
      ).readAsStringSync();
      final h = _Harness(root, const <String?>['y', '2']);
      h
        ..onSecretReads(nativeSecret, <CommandResult>[ok('$nativeKey\n')])
        ..onSecretReads(adminSecret, <CommandResult>[ok('$staleAdmin\n')])
        ..onAdminCheck(<RestResponse>[const RestResponse(401, '{}')]);

      final int code = await h.run();

      expect(code, wizardExitStopped, reason: h.output);
      expect(h.adminCheckHeaders, <String>['KakaoAK $staleAdmin']);
      expect(h.screen.secretAsks, isEmpty);
      expect(
        h.output,
        contains(
          '${KakaoStep.adminKeyMismatchMessage} — HTTP 401 — $staleGuide',
        ),
      );
      expect(h.secretWrites, isEmpty);
      expect(
        File(xcconfigPathOf(Flavor.dev)).readAsStringSync(),
        xcconfigBefore,
      );
      for (final text in <String>[h.output, h.log.text]) {
        expect(countText(text, staleAdmin), 0);
        expect(countText(text, nativeKey), 0);
      }
    });
  });

  group('T-20-BASE-11: 콘솔 앱 범위 안내 — 이번 flavor 하나 · 다른 flavor 는 이름으로', () {
    /// 화면에서 콘솔 주소 줄 바로 다음 줄.
    String findLineAfterConsole(String output) {
      final List<String> lines = output.split('\n');
      final int console = lines.indexWhere(
        (String line) => line.startsWith('  · 콘솔: '),
      );
      if (console < 0 || console + 1 >= lines.length) return '';
      return lines[console + 1];
    }

    test('flavor 셋의 문구 — 이번 flavor 용 하나 · 나머지 둘은 순서대로', () {
      final String dev = buildConsoleAppScopeNote(Flavor.dev);
      final String stg = buildConsoleAppScopeNote(Flavor.stg);
      final String prod = buildConsoleAppScopeNote(Flavor.prod);

      expect(
        dev,
        '이번에 만들 콘솔 앱: dev 용 하나 — stg · prod 앱은 그 flavor 로 위저드를 '
        '실행할 때 따로 만듭니다',
      );
      expect(stg, contains('stg 용 하나'));
      expect(stg, contains('dev · prod'));
      expect(prod, contains('prod 용 하나'));
      expect(prod, contains('dev · stg'));
      for (final note in <String>[dev, stg, prod]) {
        expect(note, isNot(contains('flavor 마다')));
      }
    });

    test('일반 바퀴 — 값 표에서 콘솔 주소 줄 바로 다음 줄', () async {
      final h = _Harness(root, const <String?>['y', '2']);
      h
        ..onSecretReads(nativeSecret, <CommandResult>[
          buildSecretMissing(nativeSecret),
          buildSecretMissing(nativeSecret),
        ])
        ..onSecretReads(adminSecret, <CommandResult>[
          buildSecretMissing(adminSecret),
          buildSecretMissing(adminSecret),
        ]);

      final int code = await h.run();

      expect(code, wizardExitForUser, reason: h.output);
      expect(
        findLineAfterConsole(h.output),
        '  · ${buildConsoleAppScopeNote(Flavor.dev)}',
      );
      expect(h.output, isNot(contains('flavor 마다 새 앱 만들기:')));
    });

    test('중복 키 바퀴 — 범위 안내 줄이 있고 중복 안내 두 줄은 그대로', () async {
      final String devKey = buildNativeKey();
      prepareFlavorFiles(Flavor.stg);
      // stg 문맥은 stg config 의 프로젝트 ID 를 읽는다.
      replaceJsonString(
        configPathOf(Flavor.stg),
        'firebaseProjectId',
        projectId,
      );
      setConfigNativeKey(Flavor.dev, devKey);
      setXcconfigNativeKey(Flavor.dev, devKey);
      setConfigNativeKey(Flavor.stg, devKey);
      final h = _Harness(root, <String?>['y', '1', devKey], flavor: Flavor.stg);
      h
        ..onSecretReads(nativeSecret, <CommandResult>[
          buildSecretMissing(nativeSecret),
          buildSecretMissing(nativeSecret),
        ])
        ..onSecretReads(adminSecret, <CommandResult>[
          ok('${buildAdminKey()}\n'),
        ]);

      await h.run();

      expect(h.output, contains('── Kakao 콘솔에 넣을 값 — stg ──'));
      expect(
        findLineAfterConsole(h.output),
        '  · ${buildConsoleAppScopeNote(Flavor.stg)}',
      );
      expect(h.output, contains('  · flavor 마다 새 앱 만들기: '));
      expect(duplicateInputHint, 'flavor 마다 새 콘솔 앱의 키를 넣으세요');
      expect(countText(h.output, devDuplicateInputLine), 1);
      expect(h.secretWrites, isEmpty);
    });
  });
}

/// 맞춤 실행의 여러 값 불일치를 보려고 쓰는 둘째 느슨한 값 — config 에만 있다.
const KeyField secondLooseField = KeyField(
  label: '느슨한 둘째 키',
  format: KeyFormat(label: '느슨한 둘째 키', pattern: r'^.+$', description: '아무 글자'),
  configKey: 'naverClientId',
);

/// 모든 값에 같은 제안 기본값을 주는 시험용 로그인 수단 — 짝 확인은 늘 맞다.
///
/// 숨김 값에도 제안을 돌려줘 숨김 입력이 기본값을 받지 않는지 본다.
final class _SuggestingStep extends KeyedProviderStep {
  _SuggestingStep(this.suggestion);

  /// 모든 값에 돌려줄 제안.
  final String suggestion;

  @override
  String get id => 'suggesting';

  @override
  String get title => '제안 수단';

  @override
  List<String> get dependsOn => const <String>['providers'];

  @override
  ProviderEntry get entry => findProvider(KakaoStep.token)!;

  @override
  List<KeyField> get fields => const <KeyField>[
    KakaoStep.nativeAppKeyField,
    KakaoStep.adminKeyField,
  ];

  @override
  List<SummaryRow> buildValueRows(WizardContext context) =>
      const <SummaryRow>[];

  @override
  List<String> get todoLines => const <String>[];

  @override
  String? suggestValue(WizardContext context, KeyField field) => suggestion;

  @override
  Future<PairCheck> verifyPair(
    WizardContext context,
    Map<KeyField, String> values,
  ) async => const PairOk();
}

/// 정한 결과를 차례로 돌려주는 시험용 로그인 수단 — 마지막 결과는 되풀이한다.
final class _ScriptedPairStep extends KeyedProviderStep {
  _ScriptedPairStep(this.fieldList, List<PairCheck> results)
    : _results = List<PairCheck>.of(results);

  /// 다룰 값 목록.
  final List<KeyField> fieldList;

  final List<PairCheck> _results;

  /// 서버 확인에 넘어온 값(부를 때마다 한 묶음).
  final List<Map<KeyField, String>> verifiedValues = <Map<KeyField, String>>[];

  @override
  String get id => 'scripted_pair';

  @override
  String get title => '차례 짝 확인 수단';

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
    return _results.length > 1 ? _results.removeAt(0) : _results.first;
  }
}
