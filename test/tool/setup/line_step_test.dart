import 'dart:io';
import 'dart:math';

import 'package:test/test.dart';

import '../../../tool/setup/command_runner.dart';
import '../../../tool/setup/config_files.dart';
import '../../../tool/setup/confirm.dart';
import '../../../tool/setup/flavor.dart';
import '../../../tool/setup/providers/fingerprints.dart';
import '../../../tool/setup/providers/keyed_provider_step.dart';
import '../../../tool/setup/redactor.dart';
import '../../../tool/setup/rest_client.dart';
import '../../../tool/setup/secret_store.dart';
import '../../../tool/setup/step.dart';
import '../../../tool/setup/steps/flavor_steps.dart';
import '../../../tool/setup/steps/functions_step.dart';
import '../../../tool/setup/steps/kakao_step.dart';
import '../../../tool/setup/steps/line_step.dart';
import '../../../tool/setup/steps/naver_step.dart';
import '../../../tool/setup/steps/provider_android_step.dart';
import '../../../tool/setup/terminal.dart';
import '../../../tool/setup/wizard.dart';
import 'fake_rest_client.dart';
import 'fakes.dart';

/// 테스트 프로젝트 ID.
const String projectId = 'line-p';

/// fixture Gradle 의 applicationId.
const String applicationId = 'com.example.line_app';

/// fixture xcconfig 의 번들 ID 앞부분(flavor 접미사 전).
const String bundleBase = 'com.example.lineApp';

/// Secret Manager 의 Channel ID 이름.
const String channelIdSecret = 'LINE_CHANNEL_ID';

/// Secret Manager 의 Channel Secret 이름.
const String channelSecretSecret = 'LINE_CHANNEL_SECRET';

/// 가짜 SHA-1(소문자 hex 40자).
const String fakeSha1Hex = 'ab500584b25ed636c9c91b0370546c3831850f16';

/// 짝이 맞을 때 돌아오는 응답 안의 가짜 액세스 토큰.
const String fakeAccessToken = 'fake-line-access-token-fixture';

/// Channel ID 가 틀렸을 때의 응답 본문.
const String wrongChannelIdBody =
    '{"error":"invalid_request","error_description":"invalid '
    "'client_id'.\"}";

/// Channel ID 를 가리키지 않는 다른 오류 응답 본문.
const String otherErrorBody =
    '{"error":"invalid_client","error_description":"other-error-fixture"}';

/// 실행 시점에 조립하는 가짜 Channel ID(숫자 10자).
String buildChannelId([String digit = '1']) => digit * 10;

/// 실행 시점에 조립하는 가짜 Channel Secret(영숫자 32자).
String buildChannelSecret([String pair = 'Ls']) => pair * 16;

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

/// 이미 끝난 앞 단계 — LINE 단계의 의존 단계를 대신한다.
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

/// 실행 기록에 실제 REST 실행기처럼 외부 요청 · 응답 줄을 남기는 REST 실행기.
final class _LoggingRest implements RestClient {
  _LoggingRest(this.inner, this.log);

  final FakeRestClient inner;
  final MemoryLogSink log;

  @override
  Future<RestResponse> send(RestRequest request) => inner.send(request);

  @override
  Future<RestResponse> sendExternal(ExternalRequest request) async {
    final RestResponse response = await inner.sendExternal(request);
    log.write(
      'rest',
      '${request.method} ${request.url} → ${response.statusCode}',
    );
    if (response.body.isNotEmpty) {
      log.write(
        'rest',
        request.isResponseSensitive
            ? HttpRestClient.sensitiveResponseNotice
            : response.body,
      );
    }
    return response;
  }
}

/// LINE 단계 한 번 실행에 쓰는 가짜 실행기 · REST · 화면 · 기록 묶음.
final class _Harness {
  _Harness(this.root, List<String?> inputs)
    : runner = FakeCommandRunner(),
      rest = FakeRestClient(),
      screen = ScriptedTerminal(inputs),
      log = MemoryLogSink(Redactor());

  final String root;
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
      rest.onExternal('POST', LineStep.pairCheckUrl, response);
    }
  }

  /// 두 이름 모두 「없음 · 없음 · 쓴 값」 으로 등록한다.
  void registerFreshSecrets(String channelId, String channelSecret) {
    this
      ..onSecretReads(channelIdSecret, <CommandResult>[
        buildSecretMissing(channelIdSecret),
        buildSecretMissing(channelIdSecret),
        ok('$channelId\n'),
      ])
      ..onSecretReads(channelSecretSecret, <CommandResult>[
        buildSecretMissing(channelSecretSecret),
        buildSecretMissing(channelSecretSecret),
        ok('$channelSecret\n'),
      ])
      ..onSecretWrite(channelIdSecret)
      ..onSecretWrite(channelSecretSecret);
  }

  /// Secret Manager 쓰기 호출.
  List<FakeCall> get secretWrites => <FakeCall>[
    for (final FakeCall call in runner.calls)
      if (call.key.startsWith('firebase functions:secrets:set ')) call,
  ];

  /// dev 문맥으로 위저드를 만든다 — 키스토어가 없는 홈 · 기록을 남기는 REST 를
  /// 쓴다.
  WizardContext buildContext({WizardSession? session}) => WizardContext(
    projectRoot: root,
    runner: runner,
    terminal: RedactingTerminal(screen, log.redactor, log),
    redactor: log.redactor,
    log: log,
    rest: _LoggingRest(rest, log),
    session: session,
    homeDirectory: noKeystoreTestHome,
    random: Random(fixedTestRandomSeed),
    now: () => fixedTestNow,
  );

  /// 앞 단계(끝남) · LINE 단계로 위저드를 돌린다.
  Future<int> run() => runWizard(buildContext(), <Step>[
    _FinishedStep('providers', '로그인 수단'),
    _FinishedStep('configure', '앱 등록 · 설정 파일'),
    _FinishedStep('apis', '필요한 Google Cloud API'),
    LineStep(),
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
      LineStep.token,
    );
    replaceXcconfigValue(
      xcconfigPathOf(flavor),
      'PRODUCT_BUNDLE_IDENTIFIER',
      '$bundleBase${flavor.suffix}',
    );
  }

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('line_step_test_');
    root = tempDir.path;
    prepareFlavorFiles(Flavor.dev);
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

  /// dev config 의 Channel ID.
  String? readConfigChannelId() =>
      readJsonString(configPathOf(Flavor.dev), 'lineChannelId');

  /// dev xcconfig 의 Channel ID.
  String? readXcconfigChannelId() =>
      readXcconfigValue(xcconfigPathOf(Flavor.dev), 'LINE_CHANNEL_ID');

  /// 화면 질문 가운데 [label] 로 시작하는 것의 수.
  int countQuestions(_Harness h, String label) =>
      h.screen.asks.where((String ask) => ask.startsWith(label)).length;

  /// 숨김 Channel Secret 질문.
  final secretQuestion =
      '${LineStep.channelSecretField.label} $hiddenInputHint';

  group('T-20-LINE-01: 값 표에 번들 ID · line3rdp scheme · 패키지명 · 대문자 콜론 SHA-1 · '
      '할 일 · 매뉴얼 절이 있다', () {
    /// 세션 [fingerprints] 로 dev 값 표를 라벨 → 값으로 모은다.
    Map<String, String> buildRows(DebugFingerprints? fingerprints) {
      final session = WizardSession()..debugFingerprints = fingerprints;
      final h = _Harness(root, const <String?>[]);
      return <String, String>{
        for (final SummaryRow row in LineStep().buildValueRows(
          h.buildContext(session: session),
        ))
          row.label: row.value,
      };
    }

    test('지문 있음 · 계산할 수 없음 · 계산 전 세 갈래', () {
      expect(
        buildRows(
          const FingerprintsAvailable(
            sha1Hex: fakeSha1Hex,
            sha256Hex: '',
            keyHash: 'q1AFhLJe1jbJyRsDcFRsODGFDxY=',
          ),
        ),
        <String, String>{
          'iOS 번들 ID': '$bundleBase.dev',
          LineStep.iosSchemeRowLabel: 'line3rdp.$bundleBase.dev',
          'Android 패키지명': '$applicationId.dev',
          LineStep.sha1RowLabel:
              'AB:50:05:84:B2:5E:D6:36:C9:C9:1B:03:70:54:6C:38:31:85:0F:16',
        },
      );
      expect(
        buildRows(
          const FingerprintsUnavailable('keytool 을 찾지 못했습니다'),
        )[LineStep.sha1RowLabel],
        KakaoStep.keyHashUnavailableValue,
      );
      expect(buildRows(null).keys, <String>[
        'iOS 번들 ID',
        LineStep.iosSchemeRowLabel,
        'Android 패키지명',
      ]);
    });

    test('실행 화면에 콘솔 주소 · 할 일 · 매뉴얼 절이 있다', () async {
      final String channelId = buildChannelId();
      final String channelSecret = buildChannelSecret();
      final h = _Harness(root, <String?>['y', '1', channelId, channelSecret]);
      h
        ..registerFreshSecrets(channelId, channelSecret)
        ..onPairCheck(<RestResponse>[const RestResponse(200, '{}')]);

      final int code = await h.run();
      final String output = h.output;

      expect(code, wizardExitDone, reason: output);
      expect(output, contains('── LINE 콘솔에 넣을 값 — dev ──'));
      expect(output, contains('https://developers.line.biz/console/'));
      for (final String line in LineStep().todoLines) {
        expect(output, contains(line));
      }
      expect(output, contains('OpenID Connect'));
      expect(output, contains('테스터'));
      expect(output, contains('매뉴얼 「LINE Login」'));
      expect(output, contains('line3rdp.$bundleBase.dev'));
      for (final text in <String>[output, h.log.text]) {
        expect(RegExp(r'\bD-[0-9]{2}\b').hasMatch(text), isFalse);
        expect(RegExp('Phase [0-9]').hasMatch(text), isFalse);
      }
    });
  });

  test('T-20-LINE-02: 입력 → 토큰 요청 200 → config 1 · xcconfig 1 · Secret Manager 2 · '
      '응답 토큰 · secret 은 화면 · 기록 0회 · 기록에 민감 응답 생략', () async {
    final String channelId = buildChannelId();
    final String channelSecret = buildChannelSecret();
    final h = _Harness(root, <String?>['y', '1', channelId, channelSecret]);
    h
      ..registerFreshSecrets(channelId, channelSecret)
      ..onPairCheck(<RestResponse>[
        const RestResponse(
          200,
          '{"access_token":"$fakeAccessToken","expires_in":900,'
          '"token_type":"Bearer"}',
        ),
      ]);

    final int code = await h.run();

    expect(code, wizardExitDone, reason: h.output);
    expect(readConfigChannelId(), channelId);
    expect(readXcconfigChannelId(), channelId);
    expect(h.secretWrites.map((FakeCall call) => call.key), <String>[
      'firebase functions:secrets:set $channelIdSecret --project $projectId --data-file -',
      'firebase functions:secrets:set $channelSecretSecret --project $projectId --data-file -',
    ]);
    expect(h.secretWrites.map((FakeCall call) => call.stdinText), <String>[
      channelId,
      channelSecret,
    ]);
    expect(h.screen.secretAsks, <String>[secretQuestion]);
    expect(h.rest.externalRequests, hasLength(1));
    final ExternalRequest request = h.rest.externalRequests.single;
    expect(request.method, 'POST');
    expect(request.url.toString(), LineStep.pairCheckUrl);
    expect(request.url.query, isEmpty);
    expect(request.formBody, <String, String>{
      'grant_type': 'client_credentials',
      'client_id': channelId,
      'client_secret': channelSecret,
    });
    expect(request.formDisplay, contains('<LINE Channel Secret>'));
    expect(request.formDisplay, isNot(contains(channelSecret)));
    expect(request.isResponseSensitive, isTrue);
    expect(h.log.text, contains(HttpRestClient.sensitiveResponseNotice));
    for (final text in <String>[h.output, h.log.text]) {
      expect(countText(text, fakeAccessToken), 0);
      expect(countText(text, channelSecret), 0);
    }
  });

  group('T-20-LINE-03: 400 응답이 client_id 를 가리키면 Channel ID 만, 아니면 Channel '
      'Secret 만 다시 묻는다', () {
    test('응답이 client_id 를 가리킨다', () async {
      final String wrongId = buildChannelId('2');
      final String channelId = buildChannelId();
      final String channelSecret = buildChannelSecret();
      final h = _Harness(root, <String?>[
        'y',
        '1',
        wrongId,
        channelSecret,
        channelId,
      ]);
      h
        ..registerFreshSecrets(channelId, channelSecret)
        ..onPairCheck(<RestResponse>[
          const RestResponse(400, wrongChannelIdBody),
          const RestResponse(200, '{}'),
        ]);

      final int code = await h.run();

      expect(code, wizardExitDone, reason: h.output);
      expect(
        h.output,
        contains('${LineStep.channelIdMismatchMessage} — HTTP 400'),
      );
      expect(h.screen.asks, <String>[
        stepConfirmQuestion,
        consoleReadyQuestion,
        LineStep.channelIdField.label,
        secretQuestion,
        LineStep.channelIdField.label,
      ]);
      expect(
        h.rest.externalRequests.map(
          (ExternalRequest request) => request.formBody!['client_id'],
        ),
        <String>[wrongId, channelId],
      );
      expect(readConfigChannelId(), channelId);
      for (final text in <String>[h.output, h.log.text]) {
        expect(countText(text, 'invalid_request'), 0);
        expect(countText(text, channelSecret), 0);
      }
    });

    test('응답이 다른 오류다', () async {
      final String wrongSecret = buildChannelSecret('Wx');
      final String channelId = buildChannelId();
      final String channelSecret = buildChannelSecret();
      final h = _Harness(root, <String?>[
        'y',
        '1',
        channelId,
        wrongSecret,
        channelSecret,
      ]);
      h
        ..registerFreshSecrets(channelId, channelSecret)
        ..onPairCheck(<RestResponse>[
          const RestResponse(400, otherErrorBody),
          const RestResponse(200, '{}'),
        ]);

      final int code = await h.run();

      expect(code, wizardExitDone, reason: h.output);
      expect(
        h.output,
        contains('${LineStep.channelSecretMismatchMessage} — HTTP 400'),
      );
      expect(h.screen.asks, <String>[
        stepConfirmQuestion,
        consoleReadyQuestion,
        LineStep.channelIdField.label,
        secretQuestion,
        secretQuestion,
      ]);
      expect(
        h.rest.externalRequests.map(
          (ExternalRequest request) => request.formBody!['client_secret'],
        ),
        <String>[wrongSecret, channelSecret],
      );
      expect(h.secretWrites.last.stdinText, channelSecret);
      for (final text in <String>[h.output, h.log.text]) {
        expect(countText(text, 'other-error-fixture'), 0);
        expect(countText(text, wrongSecret), 0);
        expect(countText(text, channelSecret), 0);
      }
    });
  });

  group('T-20-LINE-04: 토큰 요청이 상태 0 · 500 이면 아무것도 쓰지 않고 실패로 끝난다', () {
    for (final status in <int>[0, 500]) {
      test('상태 $status', () async {
        final String channelId = buildChannelId();
        final String channelSecret = buildChannelSecret();
        final String configBefore = File(
          configPathOf(Flavor.dev),
        ).readAsStringSync();
        final String xcconfigBefore = File(
          xcconfigPathOf(Flavor.dev),
        ).readAsStringSync();
        final h = _Harness(root, <String?>[
          'y',
          '1',
          channelId,
          channelSecret,
          '2', // 실패 뒤 멈춤
        ]);
        h
          ..registerFreshSecrets(channelId, channelSecret)
          ..onPairCheck(<RestResponse>[RestResponse(status, '')]);

        final int code = await h.run();

        expect(code, wizardExitStopped, reason: h.output);
        expect(h.output, contains('서버에서 확인하지 못했습니다'));
        expect(h.screen.asks.last, failureChoiceQuestion);
        expect(h.secretWrites, isEmpty);
        expect(File(configPathOf(Flavor.dev)).readAsStringSync(), configBefore);
        expect(
          File(xcconfigPathOf(Flavor.dev)).readAsStringSync(),
          xcconfigBefore,
        );
        expect(countText(h.output, channelSecret), 0);
      });
    }
  });

  test('T-20-LINE-05: Channel ID 에 숫자 아닌 글자가 있으면 그 값만 다시 묻는다', () async {
    final String channelId = buildChannelId();
    final String channelSecret = buildChannelSecret();
    final h = _Harness(root, <String?>[
      'y',
      '1',
      '12345abcde',
      channelId,
      channelSecret,
    ]);
    h
      ..registerFreshSecrets(channelId, channelSecret)
      ..onPairCheck(<RestResponse>[const RestResponse(200, '{}')]);

    final int code = await h.run();

    expect(code, wizardExitDone, reason: h.output);
    expect(
      h.output,
      contains('${LineStep.channelIdField.label} 형식이 맞지 않습니다 — 10자'),
    );
    expect(countQuestions(h, LineStep.channelIdField.label), 2);
    expect(h.screen.secretAsks, hasLength(1));
    expect(h.rest.externalRequests, hasLength(1));
    expect(readConfigChannelId(), channelId);
  });

  test('T-20-LINE-06: 켠 순서 kakao · naver · line 이면 단계 목록이 각 수단 뒤에 Android 쪽 '
      '줄을 두고 Functions 는 세 수단만 기다린다', () {
    final List<Step> steps = buildSteps(
      flavor: Flavor.dev,
      enabledProviders: <String>{
        LineStep.token,
        NaverStep.token,
        KakaoStep.token,
      },
    );
    final ids = <String>[for (final Step step in steps) step.id];
    final FunctionsStep functions = steps.whereType<FunctionsStep>().single;
    final int start = ids.indexOf(KakaoStep.token);

    expect(ids.sublist(start, start + 7), <String>[
      'kakao',
      'kakao_android',
      'naver',
      'naver_android',
      'line',
      'line_android',
      functions.id,
    ]);
    expect(
      functions.dependsOn,
      containsAll(<String>[KakaoStep.token, NaverStep.token, LineStep.token]),
    );
    for (final side in <String>[
      'kakao_android',
      'naver_android',
      'line_android',
    ]) {
      expect(functions.dependsOn, isNot(contains(side)));
    }
    final kinds = <String, AndroidFingerprintKind>{
      for (final ProviderAndroidSideStep side
          in steps.whereType<ProviderAndroidSideStep>())
        side.id: side.kind,
    };
    expect(kinds, <String, AndroidFingerprintKind>{
      'kakao_android': AndroidFingerprintKind.keyHash,
      'naver_android': AndroidFingerprintKind.keyHash,
      'line_android': AndroidFingerprintKind.sha1Colon,
    });
    final Step lineStep = steps.firstWhere(
      (Step step) => step.id == LineStep.token,
    );
    expect(lineStep.dependsOn, <String>['providers', 'configure', 'apis']);
  });
}
