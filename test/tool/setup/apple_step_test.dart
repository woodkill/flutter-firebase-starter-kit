import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:test/test.dart';

import '../../../tool/setup/config_files.dart';
import '../../../tool/setup/flavor.dart';
import '../../../tool/setup/providers/idp_config.dart';
import '../../../tool/setup/redactor.dart';
import '../../../tool/setup/rest_client.dart';
import '../../../tool/setup/step.dart';
import '../../../tool/setup/steps/apple_step.dart';
import '../../../tool/setup/terminal.dart';
import '../../../tool/setup/wizard.dart';
import 'fake_rest_client.dart';
import 'fakes.dart';

/// 테스트 프로젝트 ID.
const String projectId = 'ap';

/// fixture dev 번들 ID(대문자 포함 — 실제 번들 ID 처럼).
const String devBundleId = 'com.example.appleApp.dev';

/// 다른 flavor 의 번들 ID.
const String stgBundleId = 'com.example.appleApp.stg';

/// Firebase Apple 로그인 설정 GET 주소.
const String idpGetUrl =
    '$idpConfigUrlPrefix$projectId/defaultSupportedIdpConfigs/apple.com';

/// Firebase Apple 로그인 설정 생성 주소.
const String idpCreateUrl =
    '$idpConfigUrlPrefix$projectId/defaultSupportedIdpConfigs?idpId=apple.com';

/// iOS 쪽 PATCH 주소.
const String iosPatchUrl =
    '$idpGetUrl?updateMask=enabled,appleSignInConfig.bundleIds';

/// 매뉴얼의 iOS 서명 절 머리 줄 원문.
const String iosSigningHeading = '### iOS 서명 — Apple 을 꺼도 필요한 capability';

/// 실행 시점에 조립하는 PEM 개인 키 머리 줄.
String buildPemHeader() =>
    <String>['-----BEGIN', ' PRIVATE', ' KEY-----'].join();

/// 실행 시점에 조립하는 PEM 개인 키 끝 줄.
String buildPemFooter() => <String>['-----END', ' PRIVATE', ' KEY-----'].join();

/// [seed] 글자로 만든 가짜 base64 본문 줄 3개(각 64자).
List<String> buildBodyLines(String seed) => <String>[
  for (var i = 0; i < 3; i++) '${seed * 30}Qz0$i',
];

/// [seed] 본문 줄로 조립한 가짜 `.p8` 내용.
String buildPemContent(String seed) => <String>[
  buildPemHeader(),
  ...buildBodyLines(seed),
  buildPemFooter(),
  '',
].join('\n');

/// 실행 시점에 조립하는 가짜 client secret(가림 최소 길이보다 길다).
String buildClientSecret() => 'apple-secret-${'s' * 16}';

/// [haystack] 에서 [needle] 이 나타나는 횟수를 센다.
int countText(String haystack, String needle) =>
    haystack.split(needle).length - 1;

/// 설정이 아직 없을 때의 응답.
final RestResponse missingResponse = RestResponse(
  404,
  jsonEncode(<String, Object?>{
    'error': <String, Object?>{
      'code': 404,
      'message': 'CONFIGURATION_NOT_FOUND',
      'status': 'NOT_FOUND',
    },
  }),
);

/// Apple 로그인 설정 응답을 만든다.
///
/// [codeFlow] 를 주면 `appleSignInConfig.codeFlowConfig` 로, [clientId] 를 주면
/// 최상위 `clientId` 로 싣는다. [withSecret] 이면 최상위 `clientSecret` 을 싣는다.
RestResponse buildAppleResponse({
  bool enabled = true,
  List<String> bundleIds = const <String>[devBundleId],
  String? clientId,
  Map<String, Object?>? codeFlow,
  bool withSecret = false,
}) => RestResponse(
  200,
  jsonEncode(<String, Object?>{
    'name': 'projects/$projectId/defaultSupportedIdpConfigs/apple.com',
    'enabled': enabled,
    'clientId': ?clientId,
    if (withSecret) 'clientSecret': buildClientSecret(),
    'appleSignInConfig': <String, Object?>{
      'bundleIds': bundleIds,
      'codeFlowConfig': ?codeFlow,
    },
  }),
);

/// 이미 끝난 앞 단계 — Apple 단계의 의존 단계를 대신한다.
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
    log.write('rest', request.displayCurl());
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

/// Apple 단계 실행에 쓰는 가짜 REST · 화면 · 기록 묶음.
final class _Harness {
  _Harness(this.root, List<String?> inputs)
    : rest = FakeRestClient(),
      screen = ScriptedTerminal(inputs),
      log = MemoryLogSink(Redactor());

  final String root;
  final FakeRestClient rest;
  final ScriptedTerminal screen;
  final MemoryLogSink log;

  /// 위저드 세션 — 키 · Team ID 를 미리 넣을 때 쓴다.
  WizardSession session = WizardSession();

  /// 홈 디렉터리 — `~` 경로 시험이 바꾼다.
  String homeDirectory = noKeystoreTestHome;

  /// 화면 출력 전체.
  String get output => screen.output.toString();

  /// Firebase Apple 설정 GET 응답 큐에 [responses] 를 더한다.
  void onIdpGets(List<RestResponse> responses) {
    for (final response in responses) {
      rest.on('GET', idpGetUrl, response);
    }
  }

  /// [method] · [url] 로 받은 요청들.
  List<RestRequest> findRequests(String method, String url) => <RestRequest>[
    for (final RestRequest request in rest.requests)
      if (request.method == method && request.url.toString() == url) request,
  ];

  /// dev 문맥으로 위저드 문맥을 만든다 — 기록을 남기는 REST 를 쓴다.
  WizardContext buildContext() => WizardContext(
    projectRoot: root,
    runner: FakeCommandRunner(),
    terminal: RedactingTerminal(screen, log.redactor, log),
    redactor: log.redactor,
    log: log,
    rest: _LoggingRest(rest, log),
    session: session,
    homeDirectory: homeDirectory,
    random: Random(fixedTestRandomSeed),
    now: () => fixedTestNow,
  );

  /// 앞 단계(끝남) · iOS 쪽 단계로 위저드를 돌린다.
  Future<int> runIos() => runSteps(<Step>[
    _FinishedStep('providers', '로그인 수단'),
    _FinishedStep('configure', '앱 등록'),
    AppleStep(),
  ]);

  /// [steps] 로 위저드를 돌린다.
  Future<int> runSteps(List<Step> steps) => runWizard(buildContext(), steps);

  /// 화면 · 기록 두 버퍼에 [seed] 키의 PEM 머리 · 본문 · 끝 줄과 가짜 client
  /// secret 이 없는지 본다.
  void expectNoSecrets(String seed) {
    for (final buffer in <String>[output, log.text]) {
      expect(countText(buffer, buildPemHeader()), 0);
      expect(countText(buffer, buildPemFooter()), 0);
      expect(countText(buffer, buildClientSecret()), 0);
      for (final line in buildBodyLines(seed)) {
        expect(countText(buffer, line), 0);
      }
    }
  }
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

  /// dev config 절대 경로.
  String configPath() => '$root/${const FlavorPaths(Flavor.dev).json}';

  /// dev xcconfig 절대 경로.
  String xcconfigPath() => '$root/${const FlavorPaths(Flavor.dev).xcconfig}';

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('apple_step_test_');
    root = tempDir.path;
    const paths = FlavorPaths(Flavor.dev);
    writeFixture(paths.json, File(paths.jsonExample).readAsStringSync());
    writeFixture(
      paths.xcconfig,
      File(paths.xcconfigExample).readAsStringSync(),
    );
    replaceJsonString(configPath(), 'firebaseProjectId', projectId);
    replaceJsonString(configPath(), 'enabledAuthProviders', AppleStep.token);
    replaceXcconfigValue(
      xcconfigPath(),
      'PRODUCT_BUNDLE_IDENTIFIER',
      devBundleId,
    );
  });

  tearDown(() {
    tempDir.deleteSync(recursive: true);
  });

  group('T-20-APPLE-01: 설정이 없으면 Apple 로그인을 켜고 그 flavor 번들 ID 로 '
      '만든다', () {
    test('404 → ✗ · POST 본문 enabled · bundleIds · 재검사 ✓ · 질문은 단계 '
        '진행 하나', () async {
      final h = _Harness(root, const <String?>['y'])
        ..onIdpGets(<RestResponse>[
          missingResponse,
          missingResponse,
          buildAppleResponse(),
        ])
        ..rest.on('POST', idpCreateUrl, buildAppleResponse());

      expect(await h.runIos(), wizardExitDone);

      expect(
        h.output,
        contains('  ✗ ${AppleStep.stepTitle} — Firebase 에 Apple 로그인 설정이 없습니다'),
      );
      final List<RestRequest> posts = h.findRequests('POST', idpCreateUrl);
      expect(posts, hasLength(1));
      expect(jsonDecode(posts.single.body!), <String, Object?>{
        'enabled': true,
        'appleSignInConfig': <String, Object?>{
          'bundleIds': <String>[devBundleId],
        },
      });
      expect(posts.single.isResponseSensitive, isTrue);
      expect(
        h.output,
        contains(
          '  ✓ ${AppleStep.stepTitle} — Firebase Apple 로그인 켜짐 · '
          '번들 ID $devBundleId · ${AppleStep.capabilityNotice}',
        ),
      );
      expect(h.screen.asks, <String>[stepConfirmQuestion]);
    });

    test('config 에 프로젝트 ID 가 없으면 ✗ · 실행하면 실패 · 요청 0', () async {
      replaceJsonString(configPath(), 'firebaseProjectId', '');
      final h = _Harness(root, const <String?>['y']);

      expect(await h.runIos(), wizardExitStopped);

      expect(h.output, contains('에서 프로젝트 ID 를 읽지 못했습니다'));
      expect(h.rest.requests, isEmpty);
    });
  });

  group('T-20-APPLE-02: 다른 flavor 번들만 있으면 PATCH 로 번들 ID 를 더하고 '
      '민감 응답은 가린다', () {
    test('PATCH updateMask=enabled,appleSignInConfig.bundleIds · 기존 번들 '
        '유지 · 중첩 privateKey 두 버퍼 0회', () async {
      final codeFlow = <String, Object?>{
        'teamId': 'TEAMID1234',
        'keyId': 'ABCDE12345',
        'privateKey': buildPemContent('Ef'),
      };
      final RestResponse before = buildAppleResponse(
        bundleIds: <String>[stgBundleId],
        clientId: 'com.example.appleapp.signin',
        codeFlow: codeFlow,
        withSecret: true,
      );
      final h = _Harness(root, const <String?>['y'])
        ..onIdpGets(<RestResponse>[
          before,
          before,
          buildAppleResponse(
            bundleIds: <String>[stgBundleId, devBundleId],
            codeFlow: codeFlow,
          ),
        ])
        ..rest.on(
          'PATCH',
          iosPatchUrl,
          buildAppleResponse(
            bundleIds: <String>[stgBundleId, devBundleId],
            codeFlow: codeFlow,
            withSecret: true,
          ),
        );

      expect(await h.runIos(), wizardExitDone);

      expect(
        h.output,
        contains('Firebase Apple 로그인 설정에 번들 ID $devBundleId 가 없습니다'),
      );
      final List<RestRequest> patches = h.findRequests('PATCH', iosPatchUrl);
      expect(patches, hasLength(1));
      final Object? body = jsonDecode(patches.single.body!);
      expect(body, <String, Object?>{
        'enabled': true,
        'appleSignInConfig': <String, Object?>{
          'bundleIds': <String>[stgBundleId, devBundleId],
        },
      });
      expect(h.findRequests('POST', idpCreateUrl), isEmpty);
      expect(h.output, contains('  ✓ ${AppleStep.stepTitle} — '));
      h.expectNoSecrets('Ef');
      for (final line in buildBodyLines('Ef')) {
        expect(h.log.redactor.apply(line), Redactor.mask);
      }
    });

    test('꺼져 있으면 같은 번들로 켠다', () async {
      final RestResponse disabled = buildAppleResponse(enabled: false);
      final h = _Harness(root, const <String?>['y'])
        ..onIdpGets(<RestResponse>[disabled, disabled, buildAppleResponse()])
        ..rest.on('PATCH', iosPatchUrl, buildAppleResponse());

      expect(await h.runIos(), wizardExitDone);

      expect(h.output, contains('Firebase 에서 Apple 로그인이 꺼져 있습니다'));
      final RestRequest patch = h.findRequests('PATCH', iosPatchUrl).single;
      expect(jsonDecode(patch.body!), <String, Object?>{
        'enabled': true,
        'appleSignInConfig': <String, Object?>{
          'bundleIds': <String>[devBundleId],
        },
      });
    });

    test('PATCH 실패 → 상태와 가린 원문 · 다시 시도 멈춤', () async {
      final RestResponse before = buildAppleResponse(
        bundleIds: <String>[stgBundleId],
      );
      final h = _Harness(root, const <String?>['y', '2'])
        ..onIdpGets(<RestResponse>[before])
        ..rest.on(
          'PATCH',
          iosPatchUrl,
          RestResponse(
            403,
            jsonEncode(<String, Object?>{
              'error': <String, Object?>{
                'code': 403,
                'details': <Object?>[
                  <String, Object?>{'privateKey': buildPemContent('Gh')},
                ],
              },
            }),
          ),
        );

      expect(await h.runIos(), wizardExitStopped);

      expect(h.output, contains('Firebase Apple 로그인 설정을 쓰지 못했습니다 — HTTP 403'));
      h.expectNoSecrets('Gh');
    });

    test('읽기 403 → ✗ 사유에 상태 · 실행하면 실패', () async {
      final h = _Harness(root, const <String?>['y', '2'])
        ..onIdpGets(<RestResponse>[
          RestResponse(
            403,
            jsonEncode(<String, Object?>{
              'error': <String, Object?>{'code': 403},
            }),
          ),
        ]);

      expect(await h.runIos(), wizardExitStopped);

      expect(
        h.output,
        contains('Firebase apple.com 로그인 설정을 읽지 못했습니다 — HTTP 403'),
      );
      expect(h.output, contains('(응답 원문을 보입니다)'));
      expect(h.findRequests('PATCH', iosPatchUrl), isEmpty);
    });
  });

  group('T-20-APPLE-03: 이미 켜져 있고 번들 ID 가 있으면 ✓ 요약에 capability '
      '안내 · 쓰기 0', () {
    test('점검표 ✓ · 요청은 GET 만 · 질문 0', () async {
      final h = _Harness(root, const <String?>[])
        ..onIdpGets(<RestResponse>[
          buildAppleResponse(bundleIds: <String>[stgBundleId, devBundleId]),
        ]);

      expect(await h.runIos(), wizardExitDone);

      expect(
        h.output,
        contains(
          '  ✓ ${AppleStep.stepTitle} — Firebase Apple 로그인 켜짐 · '
          '번들 ID $devBundleId · ${AppleStep.capabilityNotice}',
        ),
      );
      expect(h.output, contains('자동 서명이면 Xcode 가 켭니다'));
      expect(
        h.rest.requests.where((RestRequest r) => r.method != 'GET'),
        isEmpty,
      );
      expect(h.screen.asks, isEmpty);
    });
  });

  group('T-20-APPLE-04: 계획 줄에 iOS 서명 매뉴얼 절과 자동 서명 안내가 '
      '보인다', () {
    test('생성 계획 줄 = curl 표시형 + capability 안내 줄', () async {
      final h = _Harness(root, const <String?>[])
        ..onIdpGets(<RestResponse>[missingResponse]);

      expect(await h.runIos(), wizardExitStopped);

      expect(
        h.output,
        contains(
          '  \$ curl -s -X POST "$idpCreateUrl" -H "Authorization: Bearer '
          '$accessTokenExpression" -H "x-goog-user-project: $projectId"',
        ),
      );
      expect(
        h.output,
        contains(
          '    (App ID 의 Sign in with Apple capability 는 자동 서명이면 '
          'Xcode 가 켭니다 — 매뉴얼 「iOS 서명 — Apple 을 꺼도 필요한 '
          'capability」)',
        ),
      );
    });

    test('매뉴얼 절 머리는 매뉴얼 원문과 같다', () {
      expect(AppleStep.iosSigningManualHeading, iosSigningHeading);
      final List<String> manualLines = File('docs/manual.md').readAsLinesSync();
      expect(manualLines, contains(iosSigningHeading));
      expect(AppleStep.capabilityNotice, contains('iOS 서명'));
      expect(AppleStep.capabilityNotice, contains('자동 서명이면 Xcode 가 켭니다'));
    });
  });
}
