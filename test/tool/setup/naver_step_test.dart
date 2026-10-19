import 'dart:io';
import 'dart:math';

import 'package:test/test.dart';

import '../../../tool/setup/command_runner.dart';
import '../../../tool/setup/config_files.dart';
import '../../../tool/setup/confirm.dart';
import '../../../tool/setup/flavor.dart';
import '../../../tool/setup/providers/fingerprints.dart';
import '../../../tool/setup/providers/key_formats.dart';
import '../../../tool/setup/providers/keyed_provider_step.dart';
import '../../../tool/setup/redactor.dart';
import '../../../tool/setup/rest_client.dart';
import '../../../tool/setup/secret_store.dart';
import '../../../tool/setup/step.dart';
import '../../../tool/setup/steps/flavor_steps.dart';
import '../../../tool/setup/steps/kakao_step.dart';
import '../../../tool/setup/steps/naver_step.dart';
import '../../../tool/setup/steps/provider_android_step.dart';
import '../../../tool/setup/terminal.dart';
import '../../../tool/setup/wizard.dart';
import 'fake_rest_client.dart';
import 'fakes.dart';

/// 테스트 프로젝트 ID.
const String projectId = 'naver-p';

/// fixture Gradle 의 applicationId.
const String applicationId = 'com.example.naver_app';

/// fixture Gradle 의 namespace — applicationId 와 다르게 두어 클래스 이름이
/// namespace 를 읽는지 본다.
const String gradleNamespace = 'com.example.naver_ns';

/// fixture xcconfig 의 번들 ID 앞부분(flavor 접미사 전).
const String bundleBase = 'com.example.naverApp';

/// Secret Manager 의 Client ID 이름.
const String clientIdSecret = 'NAVER_CLIENT_ID';

/// Secret Manager 의 Client Secret 이름.
const String clientSecretSecret = 'NAVER_CLIENT_SECRET';

/// 가짜 키 해시(base64 28자).
const String fakeKeyHash = 'q1AFhLJe1jbJyRsDcFRsODGFDxY=';

/// 짝이 틀렸을 때 Naver 가 돌려주는 HTML 오류 페이지 꼴의 가짜 본문.
const String fakeErrorHtml =
    '<html><head><meta charset="euc-kr"><title>naver-error-page</title></head> '
    '<body>unauthorized_client-fixture</body></html>';

/// 실행 시점에 조립하는 가짜 Client ID(영숫자 20자).
String buildClientId([String letter = 'x']) => 'idN${letter * 17}';

/// 실행 시점에 조립하는 가짜 Client Secret(영숫자 10자).
String buildClientSecret([String pair = 'Q7']) => pair * 5;

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

/// 이미 끝난 앞 단계 — Naver 단계의 의존 단계를 대신한다.
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

/// Naver 단계 한 번 실행에 쓰는 가짜 실행기 · REST · 화면 · 기록 묶음.
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

  /// 짝 확인 응답 큐에 [responses] 를 더한다.
  void onPairCheck(List<RestResponse> responses) {
    for (final response in responses) {
      rest.onExternal('POST', NaverStep.pairCheckUrl, response);
    }
  }

  /// 두 이름 모두 「없음 · 없음 · 쓴 값」 으로 등록한다.
  void registerFreshSecrets(String clientId, String clientSecret) {
    this
      ..onSecretReads(clientIdSecret, <CommandResult>[
        buildSecretMissing(clientIdSecret),
        buildSecretMissing(clientIdSecret),
        ok('$clientId\n'),
      ])
      ..onSecretReads(clientSecretSecret, <CommandResult>[
        buildSecretMissing(clientSecretSecret),
        buildSecretMissing(clientSecretSecret),
        ok('$clientSecret\n'),
      ])
      ..onSecretWrite(clientIdSecret)
      ..onSecretWrite(clientSecretSecret);
  }

  /// Secret Manager 쓰기 호출.
  List<FakeCall> get secretWrites => <FakeCall>[
    for (final FakeCall call in runner.calls)
      if (call.key.startsWith('firebase functions:secrets:set ')) call,
  ];

  /// [flavor] 문맥으로 위저드를 만든다 — 키스토어가 없는 홈을 쓴다.
  WizardContext buildContext({WizardSession? session}) => WizardContext(
    projectRoot: root,
    runner: runner,
    terminal: RedactingTerminal(screen, log.redactor, log),
    redactor: log.redactor,
    log: log,
    rest: rest,
    flavor: flavor,
    session: session,
    homeDirectory: noKeystoreTestHome,
    random: Random(fixedTestRandomSeed),
    now: () => fixedTestNow,
  );

  /// 앞 단계(끝남) · Naver 단계로 위저드를 돌린다.
  Future<int> run() => runWizard(buildContext(), <Step>[
    _FinishedStep('providers', '로그인 수단'),
    _FinishedStep('configure', '앱 등록 · 설정 파일'),
    _FinishedStep('apis', '필요한 Google Cloud API'),
    NaverStep(),
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

  /// [flavor] 의 example 두 파일과 사용자 파일 두 개를 example 복사로 만들고
  /// 프로젝트 ID · 로그인 수단 · 번들 ID 를 둔다.
  void prepareFlavorFiles(Flavor flavor) {
    final paths = FlavorPaths(flavor);
    copyTracked(paths.jsonExample, paths.jsonExample);
    copyTracked(paths.xcconfigExample, paths.xcconfigExample);
    copyTracked(paths.jsonExample, paths.json);
    copyTracked(paths.xcconfigExample, paths.xcconfig);
    replaceJsonString(configPathOf(flavor), 'firebaseProjectId', projectId);
    replaceJsonString(
      configPathOf(flavor),
      'enabledAuthProviders',
      NaverStep.token,
    );
    replaceXcconfigValue(
      xcconfigPathOf(flavor),
      'PRODUCT_BUNDLE_IDENTIFIER',
      '$bundleBase${flavor.suffix}',
    );
  }

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('naver_step_test_');
    root = tempDir.path;
    prepareFlavorFiles(Flavor.dev);
    writeFixture(
      'android/app/build.gradle.kts',
      'android {\n'
          '    namespace = "$gradleNamespace"\n'
          '    defaultConfig {\n'
          '        applicationId = "$applicationId"\n'
          '    }\n'
          '}\n',
    );
  });

  tearDown(() {
    tempDir.deleteSync(recursive: true);
  });

  /// [flavor] config 의 [field] 값.
  String? readConfigValue(Flavor flavor, KeyField field) =>
      readJsonString(configPathOf(flavor), field.configKey!);

  /// [flavor] xcconfig 의 [field] 값.
  String? readXcconfigField(Flavor flavor, KeyField field) =>
      readXcconfigValue(xcconfigPathOf(flavor), field.xcconfigVar!);

  /// [flavor] config · xcconfig 의 [field] 값을 [value] 로 둔다.
  void setFieldValue(Flavor flavor, KeyField field, String value) {
    replaceJsonString(configPathOf(flavor), field.configKey!, value);
    replaceXcconfigValue(xcconfigPathOf(flavor), field.xcconfigVar!, value);
  }

  /// 화면 질문 가운데 [label] 로 시작하는 것의 수.
  int countQuestions(_Harness h, String label) =>
      h.screen.asks.where((String ask) => ask.startsWith(label)).length;

  /// [flavor] 문맥 · 세션 [fingerprints] 로 값 표를 라벨 → 값으로 모은다.
  Map<String, String> buildRows(
    Flavor flavor,
    DebugFingerprints? fingerprints,
  ) {
    final session = WizardSession()..debugFingerprints = fingerprints;
    final h = _Harness(root, const <String?>[], flavor: flavor);
    return <String, String>{
      for (final SummaryRow row in NaverStep().buildValueRows(
        h.buildContext(session: session),
      ))
        row.label: row.value,
    };
  }

  /// 숨김 Client Secret 질문.
  final secretQuestion =
      '${NaverStep.clientSecretField.label} $hiddenInputHint';

  group('T-20-NAVER-01: 값 표는 URL Scheme 제안 · 패키지명 두 행이고 콘솔에 없는 칸 행은 '
      '없으며 실행 화면에 매뉴얼 절이 있다', () {
    test('stg · dev 문맥의 값 표가 그 flavor 값이다', () {
      prepareFlavorFiles(Flavor.stg);
      const available = FingerprintsAvailable(
        sha1Hex: 'ab500584b25ed636c9c91b0370546c3831850f16',
        sha256Hex: '',
        keyHash: fakeKeyHash,
      );

      expect(buildRows(Flavor.stg, available), <String, String>{
        NaverStep.suggestedUrlSchemeRowLabel: 'starterkitnaverstg',
        'Android 패키지명': '$applicationId.stg',
      });
      expect(buildRows(Flavor.dev, available), <String, String>{
        NaverStep.suggestedUrlSchemeRowLabel: 'starterkitnaverdev',
        'Android 패키지명': '$applicationId.dev',
      });
    });

    test('지문이 있든 · 계산할 수 없든 · 계산 전이든 번들 ID · 클래스 이름 · 키 해시 행이 없다', () {
      final states = <DebugFingerprints?>[
        const FingerprintsAvailable(
          sha1Hex: 'ab500584b25ed636c9c91b0370546c3831850f16',
          sha256Hex: '',
          keyHash: fakeKeyHash,
        ),
        const FingerprintsUnavailable('keytool 을 찾지 못했습니다'),
        null,
      ];
      for (final state in states) {
        final Map<String, String> rows = buildRows(Flavor.dev, state);
        final reason = '$state';

        expect(rows.containsKey('iOS 번들 ID'), isFalse, reason: reason);
        expect(
          rows.containsKey(NaverStep.classNameRowLabel),
          isFalse,
          reason: reason,
        );
        expect(
          rows.containsKey(KakaoStep.keyHashRowLabel),
          isFalse,
          reason: reason,
        );
        expect(
          rows.values,
          isNot(contains(KakaoStep.keyHashUnavailableValue)),
          reason: reason,
        );
      }
    });

    test('config 의 URL Scheme 이 형식에 맞으면 그 값을 보이고 제안 행은 없다', () {
      replaceJsonString(
        configPathOf(Flavor.dev),
        NaverStep.urlSchemeField.configKey!,
        'myappnaverdev',
      );

      expect(buildRows(Flavor.dev, null), <String, String>{
        NaverStep.urlSchemeRowLabel: 'myappnaverdev',
        'Android 패키지명': '$applicationId.dev',
      });
    });

    test('URL Scheme 제안은 flavor 접미사를 떼고 소문자 영숫자 + naver + flavor 이름이다', () {
      final cases = <(String, Flavor), String>{
        ('StarterKit Dev', Flavor.dev): 'starterkitnaverdev',
        ('StarterKit Stg', Flavor.stg): 'starterkitnaverstg',
        ('StarterKit', Flavor.prod): 'starterkitnaverprod',
        ('My_App-2 Dev', Flavor.dev): 'myapp2naverdev',
        ('9Lives Dev', Flavor.dev): 'app9livesnaverdev',
        ('', Flavor.dev): 'appnaverdev',
        ('내 앱 Stg', Flavor.stg): 'appnaverstg',
      };
      for (final MapEntry<(String, Flavor), String> entry in cases.entries) {
        final String suggestion = NaverStep.buildSuggestedUrlScheme(
          entry.key.$1,
          entry.key.$2,
        );
        expect(suggestion, entry.value, reason: entry.key.$1);
        expect(naverUrlScheme.matches(suggestion), isTrue, reason: suggestion);
      }
    });

    test('실행 화면에 콘솔 주소 · 할 일 · 매뉴얼 절이 있고 Android 쪽 줄은 패키지명만 보인다', () async {
      final String clientId = buildClientId();
      final String clientSecret = buildClientSecret();
      final h = _Harness(root, <String?>[
        'y',
        '1',
        clientId,
        clientSecret,
        'myappnaverdev',
      ]);
      h
        ..registerFreshSecrets(clientId, clientSecret)
        ..onPairCheck(<RestResponse>[const RestResponse(200, '')]);

      final int code = await h.run();
      final String output = h.output;

      expect(code, wizardExitDone, reason: output);
      expect(output, contains('── Naver 콘솔에 넣을 값 — dev ──'));
      expect(output, contains('https://developers.naver.com'));
      for (final String line in NaverStep().todoLines) {
        expect(output, contains(line));
      }
      expect(output, contains('매뉴얼 「Naver Login」'));
      expect(output, contains('매뉴얼 「로그인 수단에서 이메일 받기」'));
      expect(output, isNot(contains('MainActivity')));
      expect(output, isNot(contains('Callback')));
      for (final text in <String>[output, h.log.text]) {
        expect(RegExp(r'\bD-[0-9]{2}\b').hasMatch(text), isFalse);
        expect(RegExp('Phase [0-9]').hasMatch(text), isFalse);
      }

      final List<Step> steps = buildSteps(
        flavor: Flavor.dev,
        enabledProviders: <String>{NaverStep.token},
      );
      final ids = <String>[for (final Step step in steps) step.id];
      expect(ids.indexOf('naver_android'), ids.indexOf(NaverStep.token) + 1);
      final ProviderAndroidSideStep androidSide = steps
          .whereType<ProviderAndroidSideStep>()
          .single;
      expect(androidSide.kind, AndroidFingerprintKind.packageNameOnly);
      expect(androidSide.title, 'Naver — Android 쪽');
    });
  });

  test('T-20-NAVER-02: 입력 → 짝 확인 200 → config 3 · xcconfig 3 · Secret Manager 2 에 '
      '같은 값 · 외부 요청 1 · 실제 secret 은 화면 · 기록 0회', () async {
    final String clientId = buildClientId();
    final String clientSecret = buildClientSecret();
    const urlScheme = 'myappnaverdev';
    final h = _Harness(root, <String?>[
      'y',
      '1',
      clientId,
      clientSecret,
      urlScheme,
    ]);
    h
      ..registerFreshSecrets(clientId, clientSecret)
      ..onPairCheck(<RestResponse>[const RestResponse(200, '')]);

    final int code = await h.run();

    expect(code, wizardExitDone, reason: h.output);
    final expected = <KeyField, String>{
      NaverStep.clientIdField: clientId,
      NaverStep.clientSecretField: clientSecret,
      NaverStep.urlSchemeField: urlScheme,
    };
    for (final MapEntry<KeyField, String> entry in expected.entries) {
      expect(readConfigValue(Flavor.dev, entry.key), entry.value);
      expect(readXcconfigField(Flavor.dev, entry.key), entry.value);
    }
    expect(h.secretWrites.map((FakeCall call) => call.key), <String>[
      'firebase functions:secrets:set $clientIdSecret --project $projectId --data-file -',
      'firebase functions:secrets:set $clientSecretSecret --project $projectId --data-file -',
    ]);
    expect(h.secretWrites.map((FakeCall call) => call.stdinText), <String>[
      clientId,
      clientSecret,
    ]);
    expect(h.screen.secretAsks, <String>[secretQuestion]);
    expect(h.rest.externalRequests, hasLength(1));
    final ExternalRequest request = h.rest.externalRequests.single;
    expect(request.method, 'POST');
    expect(request.url.toString(), NaverStep.pairCheckUrl);
    expect(request.url.query, isEmpty);
    expect(request.formBody!.keys, <String>[
      'client_id',
      'client_secret',
      'token',
      'token_type_hint',
    ]);
    expect(request.formBody!['client_id'], clientId);
    expect(request.formBody!['client_secret'], clientSecret);
    expect(request.formBody!['token'], matches(RegExp(r'^[A-Za-z0-9]{32}$')));
    expect(request.formBody!['token_type_hint'], 'access_token');
    expect(request.formDisplay, contains('<Naver Client Secret>'));
    expect(request.formDisplay, isNot(contains(clientSecret)));
    expect(request.displayCurl(), isNot(contains(clientSecret)));
    expect(request.isResponseSensitive, isTrue);
    for (final text in <String>[h.output, h.log.text]) {
      expect(countText(text, clientSecret), 0);
    }
  });

  test('T-20-NAVER-03: 짝 확인 401 → 짝이 맞지 않는다는 문장 뒤 Client ID · Secret 을 '
      '다시 묻고 두 번째 200 에 기록한다', () async {
    final String wrongId = buildClientId('w');
    final String wrongSecret = buildClientSecret('W1');
    final String clientId = buildClientId();
    final String clientSecret = buildClientSecret();
    const urlScheme = 'myappnaverdev';
    final h = _Harness(root, <String?>[
      'y',
      '1',
      wrongId,
      wrongSecret,
      urlScheme,
      clientId,
      clientSecret,
    ]);
    h
      ..registerFreshSecrets(clientId, clientSecret)
      ..onPairCheck(<RestResponse>[
        const RestResponse(401, fakeErrorHtml),
        const RestResponse(200, ''),
      ]);

    final int code = await h.run();

    expect(code, wizardExitDone, reason: h.output);
    expect(h.output, contains('${NaverStep.pairMismatchMessage} — HTTP 401'));
    expect(h.screen.asks, <String>[
      stepConfirmQuestion,
      consoleReadyQuestion,
      NaverStep.clientIdField.label,
      secretQuestion,
      NaverStep.urlSchemeField.label,
      NaverStep.clientIdField.label,
      secretQuestion,
    ]);
    expect(
      h.rest.externalRequests.map(
        (ExternalRequest request) => request.formBody!['client_id'],
      ),
      <String>[wrongId, clientId],
    );
    expect(readConfigValue(Flavor.dev, NaverStep.clientIdField), clientId);
    expect(
      readConfigValue(Flavor.dev, NaverStep.clientSecretField),
      clientSecret,
    );
    expect(readConfigValue(Flavor.dev, NaverStep.urlSchemeField), urlScheme);
    for (final text in <String>[h.output, h.log.text]) {
      expect(countText(text, 'naver-error-page'), 0);
      expect(countText(text, 'unauthorized_client-fixture'), 0);
      expect(countText(text, wrongSecret), 0);
      expect(countText(text, clientSecret), 0);
    }
  });

  group('T-20-NAVER-04: 짝 확인이 401 · 200 이 아니면 아무것도 쓰지 않고 실패로 끝난다', () {
    for (final (int status, String body) in <(int, String)>[
      (400, fakeErrorHtml),
      (0, ''),
    ]) {
      test('상태 $status', () async {
        final String clientId = buildClientId();
        final String clientSecret = buildClientSecret();
        final String configBefore = File(
          configPathOf(Flavor.dev),
        ).readAsStringSync();
        final String xcconfigBefore = File(
          xcconfigPathOf(Flavor.dev),
        ).readAsStringSync();
        final h = _Harness(root, <String?>[
          'y',
          '1',
          clientId,
          clientSecret,
          'myappnaverdev',
          '2', // 실패 뒤 멈춤
        ]);
        h
          ..registerFreshSecrets(clientId, clientSecret)
          ..onPairCheck(<RestResponse>[RestResponse(status, body)]);

        final int code = await h.run();

        expect(code, wizardExitStopped, reason: h.output);
        expect(h.output, contains('서버에서 확인하지 못했습니다'));
        expect(h.screen.asks.last, failureChoiceQuestion);
        expect(h.rest.externalRequests, hasLength(1));
        expect(h.secretWrites, isEmpty);
        expect(File(configPathOf(Flavor.dev)).readAsStringSync(), configBefore);
        expect(
          File(xcconfigPathOf(Flavor.dev)).readAsStringSync(),
          xcconfigBefore,
        );
        for (final text in <String>[h.output, h.log.text]) {
          expect(countText(text, 'naver-error-page'), 0);
          expect(countText(text, 'unauthorized_client-fixture'), 0);
          expect(countText(text, clientSecret), 0);
        }
      });
    }
  });

  test('T-20-NAVER-05: URL Scheme 에 대문자 · 밑줄이면 그 값만 다시 묻고 Enter 면 '
      '제안값을 쓴다', () async {
    final String clientId = buildClientId();
    final String clientSecret = buildClientSecret();
    const suggestion = 'starterkitnaverdev';
    final h = _Harness(root, <String?>[
      'y',
      '1',
      clientId,
      clientSecret,
      'My_App',
      '',
    ]);
    h
      ..registerFreshSecrets(clientId, clientSecret)
      ..onPairCheck(<RestResponse>[const RestResponse(200, '')]);

    final int code = await h.run();

    expect(code, wizardExitDone, reason: h.output);
    expect(
      h.output,
      contains('${NaverStep.urlSchemeField.label} 형식이 맞지 않습니다 — 6자'),
    );
    expect(countQuestions(h, NaverStep.urlSchemeField.label), 2);
    expect(countQuestions(h, NaverStep.clientIdField.label), 1);
    expect(h.screen.secretAsks, hasLength(1));
    expect(h.rest.externalRequests, hasLength(1));
    expect(readConfigValue(Flavor.dev, NaverStep.urlSchemeField), suggestion);
    expect(readXcconfigField(Flavor.dev, NaverStep.urlSchemeField), suggestion);
  });

  test('T-20-NAVER-06: 이미 끝난 저장소를 다시 실행하면 질문 · 쓰기 · 외부 요청이 0 이다', () async {
    final String clientId = buildClientId();
    final String clientSecret = buildClientSecret();
    setFieldValue(Flavor.dev, NaverStep.clientIdField, clientId);
    setFieldValue(Flavor.dev, NaverStep.clientSecretField, clientSecret);
    setFieldValue(Flavor.dev, NaverStep.urlSchemeField, 'myappnaverdev');
    final h = _Harness(root, const <String?>[]);
    h
      ..onSecretReads(clientIdSecret, <CommandResult>[ok('$clientId\n')])
      ..onSecretReads(clientSecretSecret, <CommandResult>[
        ok('$clientSecret\n'),
      ]);

    final int code = await h.run();

    expect(code, wizardExitDone, reason: h.output);
    expect(h.screen.asks, isEmpty);
    expect(h.secretWrites, isEmpty);
    expect(h.rest.externalRequests, isEmpty);
    expect(h.output, contains('  ✓ ${NaverStep.stepTitle} — '));
    expect(countText(h.output, clientSecret), 0);
  });

  test('T-20-NAVER-07: config · 다른 flavor config 에서 읽은 Client Secret 은 '
      '검사 뒤 가림 함수가 가리고 자리표시는 가리지 않는다', () async {
    final String devSecret = buildClientSecret();
    final String stgSecret = buildClientSecret('R8');
    final String placeholder = readConfigValue(
      Flavor.dev,
      NaverStep.clientSecretField,
    )!;
    prepareFlavorFiles(Flavor.stg);
    // 저장소의 세 example 은 config 자리표시가 같은 글자라, 임시 저장소의 stg
    // example 사본만 다른 자리표시로 바꿔 두 config 가드가 각자의 example 과
    // 대조되는지 따로 본다(저장소 example 은 그대로 · 첫 문맥 실 값과 무관).
    const stgPlaceholder = 'YOUR_STG_NAVER_CLIENT_SECRET';
    replaceJsonString(
      '$root/${const FlavorPaths(Flavor.stg).jsonExample}',
      NaverStep.clientSecretField.configKey!,
      stgPlaceholder,
    );
    // 가림 함수는 부분 문자열까지 가리므로 두 자리표시는 서로를 품지 않아야 한다.
    expect(
      placeholder.contains(stgPlaceholder) ||
          stgPlaceholder.contains(placeholder),
      isFalse,
      reason: 'dev · stg 자리표시가 서로의 부분 문자열',
    );
    // dev xcconfig 에는 config 를 고치기 전의 옛 실 값이 남아 있다(맞출 자리).
    final String xcconfigSecret = buildClientSecret('X3');
    final String xcconfigVar = NaverStep.clientSecretField.xcconfigVar!;
    final String xcconfigPlaceholder = readXcconfigValue(
      '$root/${const FlavorPaths(Flavor.dev).xcconfigExample}',
      xcconfigVar,
    )!;
    // 가림 함수는 minSecretLength 미만 값을 조용히 버리므로, 비등록 단언이
    // 공허해지지 않으려면 저장소 example 의 자리표시가 그 길이 이상이어야 한다.
    for (final MapEntry<String, String> entry in <String, String>{
      placeholder: 'dev config 자리표시',
      stgPlaceholder: 'stg example 사본 자리표시',
      xcconfigPlaceholder: 'dev xcconfig 자리표시',
    }.entries) {
      expect(
        entry.key.length,
        greaterThanOrEqualTo(Redactor.minSecretLength),
        reason: '${entry.value}가 minSecretLength 미만 — 비등록 단언이 공허해진다',
      );
    }
    setFieldValue(Flavor.dev, NaverStep.clientSecretField, devSecret);
    setFieldValue(Flavor.stg, NaverStep.clientSecretField, stgSecret);
    replaceXcconfigValue(
      xcconfigPathOf(Flavor.dev),
      xcconfigVar,
      xcconfigSecret,
    );

    /// Secret Manager 가 빈 하네스로 dev 검사를 한 번 돌린 문맥.
    Future<WizardContext> runCheck() async {
      // Secret Manager 는 비어 있다 — 가림 등록은 config · xcconfig 읽기에서만 온다.
      final h = _Harness(root, const <String?>[]);
      h
        ..onSecretReads(clientIdSecret, <CommandResult>[
          buildSecretMissing(clientIdSecret),
        ])
        ..onSecretReads(clientSecretSecret, <CommandResult>[
          buildSecretMissing(clientSecretSecret),
        ]);
      final WizardContext context = h.buildContext();
      await NaverStep().check(context);
      return context;
    }

    final WizardContext context = await runCheck();

    final reasons = <String, String>{
      devSecret: 'dev config',
      stgSecret: 'stg config',
      xcconfigSecret: 'dev xcconfig',
    };
    for (final MapEntry<String, String> entry in reasons.entries) {
      expect(
        context.redactor.apply('값 ${entry.key} 끝'),
        '값 ${Redactor.mask} 끝',
        reason: entry.value,
      );
    }

    // dev config · stg config · dev xcconfig 가 모두 제 example 의 자리표시
    // 그대로면 실 값이 아니라 가리지 않는다. config 가드는 dev config 단언이,
    // 다른 flavor config 가드는 stg config 단언이, xcconfig 가드는 xcconfig
    // 단언이 잡는다(dev 는 물을 자리가 되지만 check 만 부른다).
    replaceJsonString(
      configPathOf(Flavor.dev),
      NaverStep.clientSecretField.configKey!,
      placeholder,
    );
    replaceJsonString(
      configPathOf(Flavor.stg),
      NaverStep.clientSecretField.configKey!,
      stgPlaceholder,
    );
    replaceXcconfigValue(
      xcconfigPathOf(Flavor.dev),
      xcconfigVar,
      xcconfigPlaceholder,
    );
    final WizardContext placeholderContext = await runCheck();

    expect(
      placeholderContext.redactor.apply(placeholder),
      placeholder,
      reason: 'dev config 자리표시(config 가드)',
    );
    expect(
      placeholderContext.redactor.apply(stgPlaceholder),
      stgPlaceholder,
      reason: 'stg config 자리표시(다른 flavor config 가드)',
    );
    expect(
      placeholderContext.redactor.apply(xcconfigPlaceholder),
      xcconfigPlaceholder,
      reason: 'dev xcconfig 자리표시',
    );
  });

  test('T-20-NAVER-08: config · 다른 flavor config · xcconfig 에서 읽은 숨김 아닌 '
      'Client ID 는 가림 함수가 가리지 않는다', () async {
    final String devId = buildClientId('d');
    final String stgId = buildClientId('s');
    final String xcconfigId = buildClientId('c');
    prepareFlavorFiles(Flavor.stg);
    setFieldValue(Flavor.dev, NaverStep.clientIdField, devId);
    setFieldValue(Flavor.stg, NaverStep.clientIdField, stgId);
    // dev xcconfig 에는 config 와 다른 옛 값이 남아 있다(맞출 자리).
    replaceXcconfigValue(
      xcconfigPathOf(Flavor.dev),
      NaverStep.clientIdField.xcconfigVar!,
      xcconfigId,
    );
    // Secret Manager 는 비어 있다 — 가림 등록은 config · xcconfig 읽기에서만 온다.
    final h = _Harness(root, const <String?>[]);
    h
      ..onSecretReads(clientIdSecret, <CommandResult>[
        buildSecretMissing(clientIdSecret),
      ])
      ..onSecretReads(clientSecretSecret, <CommandResult>[
        buildSecretMissing(clientSecretSecret),
      ]);
    final WizardContext context = h.buildContext();

    await NaverStep().check(context);

    final reasons = <String, String>{
      devId: 'dev config',
      stgId: 'stg config',
      xcconfigId: 'dev xcconfig',
    };
    for (final MapEntry<String, String> entry in reasons.entries) {
      expect(
        context.redactor.apply('값 ${entry.key} 끝'),
        '값 ${entry.key} 끝',
        reason: entry.value,
      );
    }
  });

  test('T-20-NAVER-09: 할 일 줄은 로고 이미지 · 다운로드 URL · 임의 주소 · 이메일 · '
      '멤버관리 5줄이고 실행 화면의 콘솔 주소 다음 줄이 범위 안내다', () async {
    final List<String> lines = NaverStep().todoLines;

    expect(lines, <String>[
      '애플리케이션 등록 · 네이버 로그인 API 사용 · 로고 이미지 올리기(필수 — 없으면 저장되지 않습니다)',
      'iOS 환경에 다운로드 URL · URL Scheme · Android 환경에 다운로드 URL · 패키지명 등록',
      '다운로드 URL 은 스토어에 올리기 전이면 임의 주소(예: 개발사 홈페이지)를 넣고 출시 뒤 바꿉니다',
      '제공 정보에서 이메일 주소 받기 — 매뉴얼 「로그인 수단에서 이메일 받기」',
      '개발 중인 애플리케이션은 멤버관리에 등록한 관리자 · 테스터 ID 만 로그인할 수 있습니다',
    ]);
    for (final line in lines) {
      for (final absent in <String>['flavor 마다', '번들 ID', '클래스 이름', '키 해시']) {
        expect(line, isNot(contains(absent)), reason: line);
      }
    }
    for (final present in <String>[
      '로고 이미지',
      '다운로드 URL',
      '임의 주소',
      '멤버관리',
      '테스터 ID',
    ]) {
      expect(
        lines.where((String line) => line.contains(present)),
        isNotEmpty,
        reason: present,
      );
    }

    final String clientId = buildClientId();
    final String clientSecret = buildClientSecret();
    final h = _Harness(root, <String?>[
      'y',
      '1',
      clientId,
      clientSecret,
      'myappnaverdev',
    ]);
    h
      ..registerFreshSecrets(clientId, clientSecret)
      ..onPairCheck(<RestResponse>[const RestResponse(200, '')]);

    final int code = await h.run();
    final String output = h.output;
    final List<String> screenLines = output.split('\n');
    final int titleIndex = screenLines.indexOf('── Naver 콘솔에 넣을 값 — dev ──');
    final int consoleIndex = screenLines.indexWhere(
      (String line) => line.startsWith('  · 콘솔: '),
      titleIndex,
    );

    expect(code, wizardExitDone, reason: output);
    expect(titleIndex, isNot(-1), reason: output);
    expect(consoleIndex, isNot(-1), reason: output);
    expect(
      screenLines[consoleIndex + 1],
      '  · ${buildConsoleAppScopeNote(Flavor.dev)}',
    );
    for (final line in lines) {
      expect(output, contains(line));
    }
    expect(countText(output, KakaoStep.keyHashUnavailableValue), 0);
    expect(countText(output, KakaoStep.keyHashRowLabel), 0);
    for (final text in <String>[output, h.log.text]) {
      expect(countText(text, clientSecret), 0);
    }
  });
}
