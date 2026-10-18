import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:test/test.dart';

import '../../../tool/setup/command_runner.dart';
import '../../../tool/setup/config_files.dart';
import '../../../tool/setup/confirm.dart';
import '../../../tool/setup/flavor.dart';
import '../../../tool/setup/providers/fingerprints.dart';
import '../../../tool/setup/providers/idp_config.dart';
import '../../../tool/setup/providers/keyed_provider_step.dart';
import '../../../tool/setup/redactor.dart';
import '../../../tool/setup/rest_client.dart';
import '../../../tool/setup/secret_store.dart';
import '../../../tool/setup/step.dart';
import '../../../tool/setup/steps/facebook_step.dart';
import '../../../tool/setup/steps/flavor_steps.dart';
import '../../../tool/setup/steps/functions_step.dart';
import '../../../tool/setup/steps/kakao_step.dart';
import '../../../tool/setup/steps/provider_android_step.dart';
import '../../../tool/setup/terminal.dart';
import '../../../tool/setup/wizard.dart';
import 'fake_rest_client.dart';
import 'fakes.dart';

/// 테스트 프로젝트 ID.
const String projectId = 'fb-p';

/// fixture Gradle 의 applicationId.
const String applicationId = 'com.example.fb_app';

/// fixture Gradle 의 namespace — applicationId 와 다르게 둔다.
const String gradleNamespace = 'com.example.fbspace';

/// fixture xcconfig 의 번들 ID 앞부분(flavor 접미사 전).
const String bundleBase = 'com.example.fbApp';

/// Secret Manager 의 App ID 이름.
const String appIdSecret = 'FACEBOOK_APP_ID';

/// Secret Manager 의 App Secret 이름.
const String appSecretSecret = 'FACEBOOK_APP_SECRET';

/// 가짜 키 해시.
const String fakeKeyHash = 'q1AFhLJe1jbJyRsDcFRsODGFDxY=';

/// App ID 가 틀렸을 때의 응답 본문.
final String invalidAppIdBody = jsonEncode(<String, Object?>{
  'error': <String, Object?>{
    'message': 'Invalid Client ID',
    'type': 'OAuthException',
    'code': 101,
  },
});

/// App ID 를 가리키지 않는 다른 오류 응답 본문.
final String otherErrorBody = jsonEncode(<String, Object?>{
  'error': <String, Object?>{
    'message': 'other-error-fixture',
    'type': 'OAuthException',
    'code': 1,
  },
});

/// 실행 시점에 조립하는 가짜 App ID(숫자 15자).
String buildAppId([String digit = '1']) => digit * 15;

/// 실행 시점에 조립하는 가짜 Client Token(소문자 16진수 32자).
String buildClientToken([String letter = 'c']) => letter * 32;

/// 실행 시점에 조립하는 가짜 App Secret(16진수 32자).
String buildAppSecret([String letter = 'a']) => letter * 32;

/// 짝이 맞을 때 돌아오는 가짜 앱 토큰(`<App ID>|<App Secret>` 모양).
String buildAppToken(String appId, String appSecret) => '$appId|$appSecret';

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

/// Firebase Facebook 설정 GET 주소.
const String idpGetUrl =
    '$idpConfigUrlPrefix$projectId/defaultSupportedIdpConfigs/facebook.com';

/// Firebase Facebook 설정 생성 주소.
const String idpCreateUrl =
    '$idpConfigUrlPrefix$projectId/defaultSupportedIdpConfigs'
    '?idpId=facebook.com';

/// Firebase Facebook 설정 PATCH 주소.
const String idpPatchUrl =
    '$idpGetUrl?updateMask=enabled,clientId,clientSecret';

/// Firebase Facebook 설정 응답 본문.
RestResponse buildIdpResponse(String appId, String appSecret) => RestResponse(
  200,
  jsonEncode(<String, Object?>{
    'name': 'projects/$projectId/defaultSupportedIdpConfigs/facebook.com',
    'enabled': true,
    'clientId': appId,
    'clientSecret': appSecret,
  }),
);

/// 이미 끝난 앞 단계 — Facebook 단계의 의존 단계를 대신한다.
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

/// 실제 REST 실행기처럼 요청 · 응답 줄을 기록에 남기는 REST 실행기.
///
/// 민감 응답이면 생략 표시를, 아니면 응답 본문을 그대로 기록한다.
final class _LoggingRest implements RestClient {
  _LoggingRest(this.inner, this.log);

  final FakeRestClient inner;
  final MemoryLogSink log;

  @override
  Future<RestResponse> send(RestRequest request) async {
    final RestResponse response = await inner.send(request);
    _writeResponse(
      '${request.method} ${request.url}',
      request.isResponseSensitive,
      response,
    );
    return response;
  }

  @override
  Future<RestResponse> sendExternal(ExternalRequest request) async {
    final RestResponse response = await inner.sendExternal(request);
    _writeResponse(
      '${request.method} ${request.url}',
      request.isResponseSensitive,
      response,
    );
    return response;
  }

  /// 요청 줄과 (민감 응답이 아니면) 응답 본문을 기록한다.
  void _writeResponse(String target, bool isSensitive, RestResponse response) {
    log.write('rest', '$target → ${response.statusCode}');
    if (response.body.isEmpty) return;
    log.write(
      'rest',
      isSensitive ? HttpRestClient.sensitiveResponseNotice : response.body,
    );
  }
}

/// Facebook 단계 한 번 실행에 쓰는 가짜 실행기 · REST · 화면 · 기록 묶음.
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
      rest.onExternal('POST', FacebookStep.pairCheckUrl, response);
    }
  }

  /// Firebase Facebook 설정 GET 응답 큐에 [responses] 를 더한다.
  void onIdpGets(List<RestResponse> responses) {
    for (final response in responses) {
      rest.on('GET', idpGetUrl, response);
    }
  }

  /// 두 이름 모두 「없음 · 없음 · 쓴 값」 으로 등록한다.
  void registerFreshSecrets(String appId, String appSecret) {
    this
      ..onSecretReads(appIdSecret, <CommandResult>[
        buildSecretMissing(appIdSecret),
        buildSecretMissing(appIdSecret),
        ok('$appId\n'),
      ])
      ..onSecretReads(appSecretSecret, <CommandResult>[
        buildSecretMissing(appSecretSecret),
        buildSecretMissing(appSecretSecret),
        ok('$appSecret\n'),
      ])
      ..onSecretWrite(appIdSecret)
      ..onSecretWrite(appSecretSecret);
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

  /// 앞 단계(끝남) · Facebook 단계로 위저드를 돌린다.
  Future<int> run() => runWizard(buildContext(), <Step>[
    _FinishedStep('providers', '로그인 수단'),
    _FinishedStep('configure', '앱 등록 · 설정 파일'),
    _FinishedStep('apis', '필요한 Google Cloud API'),
    FacebookStep(),
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

  /// dev config 절대 경로.
  String configPath() => '$root/${const FlavorPaths(Flavor.dev).json}';

  /// dev xcconfig 절대 경로.
  String xcconfigPath() => '$root/${const FlavorPaths(Flavor.dev).xcconfig}';

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('facebook_step_test_');
    root = tempDir.path;
    const paths = FlavorPaths(Flavor.dev);
    copyTracked(paths.jsonExample, paths.jsonExample);
    copyTracked(paths.xcconfigExample, paths.xcconfigExample);
    copyTracked(paths.jsonExample, paths.json);
    copyTracked(paths.xcconfigExample, paths.xcconfig);
    replaceJsonString(configPath(), 'firebaseProjectId', projectId);
    replaceJsonString(configPath(), 'enabledAuthProviders', FacebookStep.token);
    replaceXcconfigValue(
      xcconfigPath(),
      'PRODUCT_BUNDLE_IDENTIFIER',
      '$bundleBase.dev',
    );
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

  /// config · xcconfig 에 App ID · Client Token 을 미리 둔다.
  void prepareLocalValues(String appId, String clientToken) {
    replaceJsonString(configPath(), 'facebookAppId', appId);
    replaceJsonString(configPath(), 'facebookClientToken', clientToken);
    replaceXcconfigValue(xcconfigPath(), 'FACEBOOK_APP_ID', appId);
    replaceXcconfigValue(xcconfigPath(), 'FACEBOOK_CLIENT_TOKEN', clientToken);
  }

  /// 화면 질문 가운데 [label] 로 시작하는 것의 수.
  int countQuestions(_Harness h, String label) =>
      h.screen.asks.where((String ask) => ask.startsWith(label)).length;

  /// 숨김 App Secret 질문.
  final secretQuestion =
      '${FacebookStep.appSecretField.label} $hiddenInputHint';

  group('T-20-FB-01: 값 표에 패키지명 · 클래스 이름 · 번들 ID · redirect URI · '
      '키 해시 · 할 일이 있다', () {
    /// 세션 [fingerprints] 로 dev 값 표를 라벨 → 값으로 모은다.
    Map<String, String> buildRows(DebugFingerprints? fingerprints) {
      final session = WizardSession()..debugFingerprints = fingerprints;
      final h = _Harness(root, const <String?>[]);
      return <String, String>{
        for (final SummaryRow row in FacebookStep().buildValueRows(
          h.buildContext(session: session),
        ))
          row.label: row.value,
      };
    }

    test('지문 있음 · 계산할 수 없음 · 계산 전 세 갈래', () {
      expect(
        buildRows(
          const FingerprintsAvailable(
            sha1Hex: '',
            sha256Hex: '',
            keyHash: fakeKeyHash,
          ),
        ),
        <String, String>{
          'iOS 번들 ID': '$bundleBase.dev',
          'Android 패키지명': '$applicationId.dev',
          'Android 클래스 이름': '$gradleNamespace.MainActivity',
          KakaoStep.keyHashRowLabel: fakeKeyHash,
          FacebookStep.redirectUriRowLabel:
              'https://$projectId.firebaseapp.com/__/auth/handler',
        },
      );
      expect(
        buildRows(
          const FingerprintsUnavailable('keytool 을 찾지 못했습니다'),
        )[KakaoStep.keyHashRowLabel],
        KakaoStep.keyHashUnavailableValue,
      );
      expect(buildRows(null).containsKey(KakaoStep.keyHashRowLabel), isFalse);
    });

    test('실행 화면에 Meta 콘솔 주소 · 할 일(앱 역할) · 매뉴얼 절이 있다', () async {
      final String appId = buildAppId();
      final String clientToken = buildClientToken();
      final String appSecret = buildAppSecret();
      final h = _Harness(root, <String?>[
        'y',
        '1',
        appId,
        clientToken,
        appSecret,
      ]);
      h
        ..registerFreshSecrets(appId, appSecret)
        ..onPairCheck(<RestResponse>[const RestResponse(200, '{}')])
        ..onIdpGets(<RestResponse>[
          const RestResponse(404, ''),
          buildIdpResponse(appId, appSecret),
        ]);
      h.rest.on('POST', idpCreateUrl, buildIdpResponse(appId, appSecret));

      final int code = await h.run();
      final String output = h.output;

      expect(code, wizardExitDone, reason: output);
      expect(output, contains('── Facebook 콘솔에 넣을 값 — dev ──'));
      expect(output, contains('콘솔: https://developers.facebook.com/apps'));
      for (final String line in FacebookStep().todoLines) {
        expect(output, contains(line));
      }
      expect(output, contains('앱 역할'));
      expect(output, contains('매뉴얼 「로그인 수단 켜고 끄기」'));
      expect(output, contains('매뉴얼 「로그인 수단에서 이메일 받기」'));
      expect(
        output,
        contains('https://$projectId.firebaseapp.com/__/auth/handler'),
      );
      expect(FacebookStep().todoLines.length, lessThanOrEqualTo(5));
      for (final text in <String>[output, h.log.text]) {
        expect(RegExp(r'\bD-[0-9]{2}\b').hasMatch(text), isFalse);
        expect(RegExp('Phase [0-9]').hasMatch(text), isFalse);
      }
    });
  });

  test('T-20-FB-02: 입력 → 짝 확인 200 → 여섯 자리 · Firebase 설정 생성 · '
      '재검사 맞음 · App Secret · 앱 토큰 0회', () async {
    final String appId = buildAppId();
    final String clientToken = buildClientToken();
    final String appSecret = buildAppSecret();
    final String appToken = buildAppToken(appId, appSecret);
    final h = _Harness(root, <String?>[
      'y',
      '1',
      appId,
      clientToken,
      appSecret,
    ]);
    h
      ..registerFreshSecrets(appId, appSecret)
      ..onPairCheck(<RestResponse>[
        RestResponse(200, '{"access_token":"$appToken","token_type":"bearer"}'),
      ])
      ..onIdpGets(<RestResponse>[
        const RestResponse(404, ''),
        buildIdpResponse(appId, appSecret),
      ]);
    h.rest.on('POST', idpCreateUrl, buildIdpResponse(appId, appSecret));

    final int code = await h.run();

    expect(code, wizardExitDone, reason: h.output);
    expect(readJsonString(configPath(), 'facebookAppId'), appId);
    expect(readJsonString(configPath(), 'facebookClientToken'), clientToken);
    expect(readXcconfigValue(xcconfigPath(), 'FACEBOOK_APP_ID'), appId);
    expect(
      readXcconfigValue(xcconfigPath(), 'FACEBOOK_CLIENT_TOKEN'),
      clientToken,
    );
    expect(h.secretWrites.map((FakeCall call) => call.key), <String>[
      'firebase functions:secrets:set $appIdSecret --project $projectId --data-file -',
      'firebase functions:secrets:set $appSecretSecret --project $projectId --data-file -',
    ]);
    expect(h.secretWrites.map((FakeCall call) => call.stdinText), <String>[
      appId,
      appSecret,
    ]);
    expect(h.screen.secretAsks, <String>[secretQuestion]);

    final ExternalRequest pair = h.rest.externalRequests.single;
    expect(pair.url.toString(), FacebookStep.pairCheckUrl);
    expect(pair.url.query, isEmpty);
    expect(pair.formBody, <String, String>{
      'grant_type': 'client_credentials',
      'client_id': appId,
      'client_secret': appSecret,
    });
    expect(pair.formDisplay, contains('<Facebook App Secret>'));
    expect(pair.formDisplay, isNot(contains(appSecret)));
    expect(pair.isResponseSensitive, isTrue);

    expect(h.rest.countRequests('POST', idpCreateUrl), 1);
    expect(h.rest.countRequests('PATCH', idpPatchUrl), 0);
    expect(h.rest.countRequests('GET', idpGetUrl), 2);
    final RestRequest create = h.rest.requests.firstWhere(
      (RestRequest request) => request.method == 'POST',
    );
    expect(jsonDecode(create.body!), <String, Object?>{
      'enabled': true,
      'clientId': appId,
      'clientSecret': appSecret,
    });
    expect(create.bodyDisplay, contains('<Facebook App Secret>'));
    expect(create.bodyDisplay, isNot(contains(appSecret)));
    expect(create.isResponseSensitive, isTrue);
    expect(h.output, contains('✓ Facebook 로그인'));

    expect(h.log.text, contains(HttpRestClient.sensitiveResponseNotice));
    for (final text in <String>[h.output, h.log.text]) {
      expect(countText(text, appSecret), 0);
      expect(countText(text, appToken), 0);
    }
  });

  test('T-20-FB-03: Firebase 설정의 clientSecret 이 다르면 그 자리만 할 일 · '
      '질문 0 · PATCH 1회', () async {
    final String appId = buildAppId();
    final String clientToken = buildClientToken();
    final String appSecret = buildAppSecret();
    final String staleSecret = buildAppSecret('d');
    prepareLocalValues(appId, clientToken);
    final h = _Harness(root, <String?>['y']);
    h
      ..onSecretReads(appIdSecret, <CommandResult>[ok('$appId\n')])
      ..onSecretReads(appSecretSecret, <CommandResult>[ok('$appSecret\n')])
      ..onIdpGets(<RestResponse>[
        buildIdpResponse(appId, staleSecret),
        buildIdpResponse(appId, staleSecret),
        buildIdpResponse(appId, staleSecret),
        buildIdpResponse(appId, appSecret),
      ])
      ..onPairCheck(<RestResponse>[const RestResponse(200, '{}')]);
    h.rest.on('PATCH', idpPatchUrl, buildIdpResponse(appId, appSecret));

    final int code = await h.run();

    expect(code, wizardExitDone, reason: h.output);
    expect(
      h.output,
      contains(
        '✗ Facebook 로그인 — $alignReasonPrefix'
        '${FacebookStep.remotePlaceName}',
      ),
    );
    for (final KeyField field in FacebookStep().fields) {
      expect(countQuestions(h, field.label), 0);
    }
    expect(h.screen.secretAsks, isEmpty);
    // 맞춤 전 짝 확인 1회 — Secret Manager 의 App Secret 을 메모리로 넘긴다.
    expect(h.rest.externalRequests.single.formBody, <String, String>{
      'grant_type': 'client_credentials',
      'client_id': appId,
      'client_secret': appSecret,
    });
    expect(h.secretWrites, isEmpty);
    expect(h.rest.countRequests('PATCH', idpPatchUrl), 1);
    expect(h.rest.countRequests('POST', idpCreateUrl), 0);
    final RestRequest patch = h.rest.requests.firstWhere(
      (RestRequest request) => request.method == 'PATCH',
    );
    expect(jsonDecode(patch.body!), <String, Object?>{
      'enabled': true,
      'clientId': appId,
      'clientSecret': appSecret,
    });
    expect(patch.bodyDisplay, contains('<Facebook App Secret>'));
    for (final text in <String>[h.output, h.log.text]) {
      expect(countText(text, appSecret), 0);
      expect(countText(text, staleSecret), 0);
    }
  });

  group('T-20-FB-04: 짝 확인 갈래 — 101 은 App ID · 다른 400 은 App Secret · '
      '상태 0 은 쓰기 0 실패', () {
    test('400 code 101 이면 App ID 만 다시 묻는다', () async {
      final String wrongAppId = buildAppId('2');
      final String appId = buildAppId();
      final String clientToken = buildClientToken();
      final String appSecret = buildAppSecret();
      final h = _Harness(root, <String?>[
        'y',
        '1',
        wrongAppId,
        clientToken,
        appSecret,
        appId,
      ]);
      h
        ..registerFreshSecrets(appId, appSecret)
        ..onPairCheck(<RestResponse>[
          RestResponse(400, invalidAppIdBody),
          const RestResponse(200, '{}'),
        ])
        ..onIdpGets(<RestResponse>[
          const RestResponse(404, ''),
          buildIdpResponse(appId, appSecret),
        ]);
      h.rest.on('POST', idpCreateUrl, buildIdpResponse(appId, appSecret));

      final int code = await h.run();

      expect(code, wizardExitDone, reason: h.output);
      expect(
        h.output,
        contains('${FacebookStep.appIdMismatchMessage} — HTTP 400'),
      );
      expect(countQuestions(h, FacebookStep.appIdField.label), 2);
      expect(countQuestions(h, FacebookStep.clientTokenField.label), 1);
      expect(h.screen.secretAsks, hasLength(1));
      expect(h.rest.externalRequests, hasLength(2));
      expect(readJsonString(configPath(), 'facebookAppId'), appId);
      expect(countText(h.output, 'Invalid Client ID'), 0);
    });

    test('다른 400 이면 App Secret 만 다시 묻는다', () async {
      final String appId = buildAppId();
      final String clientToken = buildClientToken();
      final String wrongSecret = buildAppSecret('b');
      final String appSecret = buildAppSecret();
      final h = _Harness(root, <String?>[
        'y',
        '1',
        appId,
        clientToken,
        wrongSecret,
        appSecret,
      ]);
      h
        ..registerFreshSecrets(appId, appSecret)
        ..onPairCheck(<RestResponse>[
          RestResponse(400, otherErrorBody),
          const RestResponse(200, '{}'),
        ])
        ..onIdpGets(<RestResponse>[
          const RestResponse(404, ''),
          buildIdpResponse(appId, appSecret),
        ]);
      h.rest.on('POST', idpCreateUrl, buildIdpResponse(appId, appSecret));

      final int code = await h.run();

      expect(code, wizardExitDone, reason: h.output);
      expect(
        h.output,
        contains('${FacebookStep.appSecretMismatchMessage} — HTTP 400'),
      );
      expect(countQuestions(h, FacebookStep.appIdField.label), 1);
      expect(h.screen.secretAsks, <String>[secretQuestion, secretQuestion]);
      expect(h.secretWrites.last.stdinText, appSecret);
      for (final text in <String>[h.output, h.log.text]) {
        expect(countText(text, wrongSecret), 0);
        expect(countText(text, appSecret), 0);
      }
    });

    test('상태 0 이면 아무것도 쓰지 않고 실패한다', () async {
      final String appId = buildAppId();
      final String clientToken = buildClientToken();
      final String appSecret = buildAppSecret();
      final h = _Harness(root, <String?>[
        'y',
        '1',
        appId,
        clientToken,
        appSecret,
      ]);
      h
        ..registerFreshSecrets(appId, appSecret)
        ..onPairCheck(<RestResponse>[const RestResponse(0, '')]);

      final int code = await h.run();

      expect(code, isNot(wizardExitDone));
      expect(
        h.output,
        contains('App ID · App Secret 을 서버에서 확인하지 못했습니다 — 요청하지 못했습니다'),
      );
      expect(
        readJsonString(configPath(), 'facebookAppId'),
        'YOUR_FACEBOOK_APP_ID_HERE',
      );
      expect(h.secretWrites, isEmpty);
      expect(h.rest.requests, isEmpty);
    });
  });

  test('T-20-FB-05: Firebase 설정 PATCH 실패 → 가린 원문 · 로컬 자리는 그대로 · '
      '다시 검사하면 원격 자리만 할 일', () async {
    final String appId = buildAppId();
    final String clientToken = buildClientToken();
    final String appSecret = buildAppSecret();
    final String staleSecret = buildAppSecret('e');
    final h = _Harness(root, <String?>[
      'y',
      '1',
      appId,
      clientToken,
      appSecret,
    ]);
    h
      ..registerFreshSecrets(appId, appSecret)
      ..onPairCheck(<RestResponse>[const RestResponse(200, '{}')])
      ..onIdpGets(<RestResponse>[buildIdpResponse(appId, staleSecret)]);
    h.rest.on(
      'PATCH',
      idpPatchUrl,
      RestResponse(
        403,
        jsonEncode(<String, Object?>{
          'error': <String, Object?>{
            'code': 403,
            'status': 'PERMISSION_DENIED',
            'details': <Object?>[
              <String, Object?>{'clientSecret': staleSecret},
            ],
          },
        }),
      ),
    );

    final int code = await h.run();

    expect(code, isNot(wizardExitDone));
    expect(
      h.output,
      contains('${FacebookStep.remotePlaceName} 을 쓰지 못했습니다 — HTTP 403'),
    );
    expect(h.output, contains('PERMISSION_DENIED'));
    expect(readJsonString(configPath(), 'facebookAppId'), appId);
    expect(readXcconfigValue(xcconfigPath(), 'FACEBOOK_APP_ID'), appId);
    expect(h.secretWrites, hasLength(2));
    for (final text in <String>[h.output, h.log.text]) {
      expect(countText(text, appSecret), 0);
      expect(countText(text, staleSecret), 0);
    }

    final CheckResult again = await FacebookStep().check(h.buildContext());
    expect(again, isA<Todo>());
    expect(
      (again as Todo).reason,
      '$alignReasonPrefix${FacebookStep.remotePlaceName}',
    );
  });

  group('T-20-FB-06: 단계 목록 · 재실행', () {
    test('켰으면 facebook · facebook_android 가 있고 Functions 는 facebook 만 '
        '기다린다', () {
      final List<Step> steps = buildSteps(
        flavor: Flavor.dev,
        enabledProviders: <String>{KakaoStep.token, FacebookStep.token},
      );
      final ids = <String>[for (final Step step in steps) step.id];
      final FunctionsStep functions = steps.whereType<FunctionsStep>().single;
      final int start = ids.indexOf(FacebookStep.token);

      expect(ids.sublist(start, start + 5), <String>[
        'facebook',
        'facebook_android',
        'kakao',
        'kakao_android',
        functions.id,
      ]);
      expect(functions.dependsOn, contains(FacebookStep.token));
      expect(functions.dependsOn, isNot(contains('facebook_android')));
      final ProviderAndroidSideStep side = steps
          .whereType<ProviderAndroidSideStep>()
          .firstWhere(
            (ProviderAndroidSideStep s) => s.id == 'facebook_android',
          );
      expect(side.kind, AndroidFingerprintKind.keyHash);
      final Step facebook = steps.firstWhere(
        (Step step) => step.id == FacebookStep.token,
      );
      expect(facebook.title, 'Facebook 로그인');
      expect(facebook.dependsOn, <String>['providers', 'configure', 'apis']);
      expect(
        buildSteps(
          flavor: Flavor.dev,
          enabledProviders: <String>{KakaoStep.token},
        ).map((Step step) => step.id),
        isNot(contains(FacebookStep.token)),
      );
    });

    test('모든 자리가 맞으면 질문 0 · 쓰기 0', () async {
      final String appId = buildAppId();
      final String clientToken = buildClientToken();
      final String appSecret = buildAppSecret();
      prepareLocalValues(appId, clientToken);
      final h = _Harness(root, const <String?>[]);
      h
        ..onSecretReads(appIdSecret, <CommandResult>[ok('$appId\n')])
        ..onSecretReads(appSecretSecret, <CommandResult>[ok('$appSecret\n')])
        ..onIdpGets(<RestResponse>[buildIdpResponse(appId, appSecret)]);

      final int code = await h.run();

      expect(code, wizardExitDone, reason: h.output);
      expect(h.screen.asks, isEmpty);
      expect(h.secretWrites, isEmpty);
      expect(h.rest.externalRequests, isEmpty);
      expect(h.rest.countRequests('PATCH', idpPatchUrl), 0);
      expect(h.rest.countRequests('POST', idpCreateUrl), 0);
      expect(h.output, contains('✓ Facebook 로그인'));
      for (final text in <String>[h.output, h.log.text]) {
        expect(countText(text, appSecret), 0);
      }
    });
  });
}
