import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:test/test.dart';

import '../../../tool/setup/config_files.dart';
import '../../../tool/setup/flavor.dart';
import '../../../tool/setup/providers/apple_key_input.dart';
import '../../../tool/setup/redactor.dart';
import '../../../tool/setup/rest_client.dart';
import '../../../tool/setup/step.dart';
import '../../../tool/setup/steps/device_check_step.dart';
import '../../../tool/setup/terminal.dart';
import '../../../tool/setup/wizard.dart';
import 'fake_rest_client.dart';
import 'fakes.dart';
import 'firebase_options_fixture.dart';

/// 테스트 프로젝트 ID.
const String projectId = 'p';

/// fixture iOS 앱 ID.
const String iosAppId = '1:000:ios:fake';

/// App Check API 주소의 앞부분.
const String appCheckPrefix = 'https://firebaseappcheck.googleapis.com/v1/';

/// Firebase Management API 주소의 앞부분.
const String managementPrefix = 'https://firebase.googleapis.com/v1beta1/';

/// DeviceCheck 설정 주소.
const String configUrl =
    '${appCheckPrefix}projects/$projectId/apps/$iosAppId/deviceCheckConfig';

/// DeviceCheck 등록 주소.
const String patchUrl = '$configUrl?updateMask=key_id,private_key';

/// iOS 앱 Team ID 쓰기 주소.
const String teamPatchUrl =
    '${managementPrefix}projects/$projectId/iosApps/$iosAppId'
    '?updateMask=team_id';

/// 가짜 Key ID(실행 시점 조립 · 대문자 영숫자 10자).
final String keyId = 'K' * 10;

/// 두 번째 가짜 Key ID.
final String otherKeyId = 'J' * 10;

/// 가짜 Team ID(실행 시점 조립 · 대문자 영숫자 10자).
final String teamId = 'T' * 10;

/// 실행 시점에 조립한 가짜 API 키.
final String fakeApiKey = 'AIza${'x' * 35}';

/// 가짜 `.p8` 본문 줄 3개(각 64자).
final List<String> bodyLines = <String>[
  for (var i = 0; i < 3; i++) '${'Dc' * 30}Qz0$i',
];

/// 실행 시점에 조립한 PEM 끝 줄.
final String pemFooter = <String>['-----END', ' PRIVATE', ' KEY-----'].join();

/// 가짜 `.p8` 내용.
final String pemContent = <String>[
  pemPrivateKeyHeader,
  ...bodyLines,
  pemFooter,
  '',
].join('\n');

/// 미등록 대조군 응답 — 200 이지만 키가 없다.
const RestResponse unregisteredResponse = RestResponse(
  200,
  '{"name":"projects/p/apps/a/deviceCheckConfig","tokenTtl":"3600s"}',
);

/// [registeredKeyId] 로 키가 들어간 응답.
RestResponse buildRegisteredResponse(String registeredKeyId) => RestResponse(
  200,
  jsonEncode(<String, Object?>{
    'name': 'projects/p/apps/a/deviceCheckConfig',
    'keyId': registeredKeyId,
    'privateKeySet': true,
    'tokenTtl': '3600s',
  }),
);

/// [haystack] 에서 [needle] 이 나타나는 횟수를 센다.
int countText(String haystack, String needle) =>
    haystack.split(needle).length - 1;

/// 이미 끝난 앞 단계 — DeviceCheck 단계의 의존 단계를 대신한다.
final class _FinishedStep implements Step {
  _FinishedStep(this.id);

  @override
  final String id;

  @override
  String get title => id;

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

/// 한 번의 위저드 실행.
final class _Harness {
  _Harness(this.root, List<String?> inputs, {WizardSession? session})
    : screen = ScriptedTerminal(inputs),
      session = session ?? WizardSession();

  final String root;
  final ScriptedTerminal screen;
  final WizardSession session;
  final FakeRestClient rest = FakeRestClient();
  final MemoryLogSink log = MemoryLogSink(Redactor());

  /// 화면 출력 전체.
  String get output => screen.output.toString();

  /// 앞 단계(끝남) · DeviceCheck 단계로 위저드를 돌린다.
  Future<int> run() => runWizard(
    WizardContext(
      projectRoot: root,
      runner: FakeCommandRunner(),
      terminal: RedactingTerminal(screen, log.redactor, log),
      redactor: log.redactor,
      log: log,
      rest: rest,
      session: session,
      homeDirectory: noKeystoreTestHome,
      random: Random(fixedTestRandomSeed),
      now: () => fixedTestNow,
    ),
    <Step>[
      _FinishedStep('configure'),
      _FinishedStep('apis'),
      DeviceCheckStep(),
    ],
  );

  /// [method] 요청만 모은다.
  List<RestRequest> listRequests(String method) => rest.requests
      .where((RestRequest request) => request.method == method)
      .toList();

  /// 화면 · 기록 두 버퍼에 PEM 머리 · 본문 · 끝 줄이 없는지 본다.
  void expectNoPem() {
    for (final buffer in <String>[output, log.text]) {
      expect(countText(buffer, pemPrivateKeyHeader), 0);
      expect(countText(buffer, pemFooter), 0);
      for (final String line in bodyLines) {
        expect(countText(buffer, line), 0);
      }
    }
  }
}

void main() {
  late Directory tempDir;
  late Directory keyDir;
  late String root;

  /// 저장소 상대 경로에 내용을 쓴다(부모 디렉터리를 만든다).
  void writeFixture(String relativePath, String content) {
    File('$root/$relativePath')
      ..parent.createSync(recursive: true)
      ..writeAsStringSync(content);
  }

  /// dev xcconfig 절대 경로.
  String xcconfigPath() => '$root/${const FlavorPaths(Flavor.dev).xcconfig}';

  /// 가짜 키 파일 경로(저장소 밖).
  String keyPath() => '${keyDir.path}/AuthKey_$keyId.p8';

  /// SIWA 자리에 키가 있는 세션.
  WizardSession buildSiwaSession() => WizardSession()
    ..appleKeys[AppleKeyUse.signInWithApple] = AppleKey(
      keyId: keyId,
      privateKey: pemContent,
    );

  /// 등록 흐름 응답(Team ID · DeviceCheck PATCH 200 · 재검사 [after])을 등록한다.
  void registerApplyFlow(_Harness h, RestResponse after) {
    h.rest
      ..on('GET', configUrl, unregisteredResponse)
      ..on('GET', configUrl, unregisteredResponse)
      ..on('GET', configUrl, after)
      ..on('PATCH', teamPatchUrl, const RestResponse(200, '{}'))
      ..on('PATCH', patchUrl, const RestResponse(200, '{}'));
  }

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('device_check_test_');
    keyDir = Directory.systemTemp.createTempSync('device_check_keys_');
    root = tempDir.path;
    const paths = FlavorPaths(Flavor.dev);
    final config = File('$root/${paths.json}')
      ..parent.createSync(recursive: true);
    File(paths.jsonExample).copySync(config.path);
    replaceJsonString(config.path, 'firebaseProjectId', projectId);
    writeFixture(
      paths.dartOptions,
      buildGeneratedOptionsSource(
        projectId: projectId,
        apiKey: fakeApiKey,
        androidAppId: '1:000:android:fake',
        iosAppId: iosAppId,
      ),
    );
    writeFixture(
      paths.iosPlist,
      '<plist version="1.0">\n<dict>\n'
      '\t<key>GOOGLE_APP_ID</key>\n\t<string>$iosAppId</string>\n'
      '</dict>\n</plist>\n',
    );
    writeFixture(
      paths.xcconfig,
      File(paths.xcconfigExample).readAsStringSync(),
    );
    replaceXcconfigValue(xcconfigPath(), developmentTeamVariable, teamId);
    File(keyPath()).writeAsStringSync(pemContent);
  });

  tearDown(() {
    tempDir.deleteSync(recursive: true);
    keyDir.deleteSync(recursive: true);
  });

  group('T-20-DC-01: 200 만으로 ✓ 아님 · 같은 키 · Team ID · 두 PATCH · '
      'privateKeySet 재검사', () {
    test('미등록 대조군 ✗ → 1 · 같은 키 → PATCH 둘 → ✓ · 세션 플래그', () async {
      final h = _Harness(root, const <String?>[
        '1',
        '1',
      ], session: buildSiwaSession());
      registerApplyFlow(h, buildRegisteredResponse(keyId));

      final int code = await h.run();

      expect(code, wizardExitDone);
      expect(
        h.output,
        contains('  ✗ ${DeviceCheckStep.stepTitle} — '),
        reason: '200 {name, tokenTtl} 은 등록되지 않은 것이다',
      );
      expect(h.output, contains('같은 키 (Key ID $keyId)'));
      final List<RestRequest> patches = h.listRequests('PATCH');
      expect(patches, hasLength(2));
      final RestRequest team = patches.first;
      expect(team.url.toString(), teamPatchUrl);
      expect(jsonDecode(team.body!), <String, Object?>{'teamId': teamId});
      final RestRequest deviceCheck = patches.last;
      expect(deviceCheck.url.toString(), patchUrl);
      expect(jsonDecode(deviceCheck.body!), <String, Object?>{
        'keyId': keyId,
        'privateKey': pemContent,
      });
      expect(
        deviceCheck.bodyDisplay,
        '{"keyId":"$keyId","privateKey":"<.p8 파일 내용>"}',
      );
      expect(deviceCheck.isResponseSensitive, isTrue);
      expect(h.output, contains('  ✓ ${DeviceCheckStep.stepTitle} — '));
      expect(h.output, contains('Key ID $keyId'));
      expect(h.session.hasEnteredDeviceCheckKey, isTrue);
      expect(h.screen.asks, isNot(contains(appleTeamIdQuestion)));
      h.expectNoPem();
    });

    test('계획 줄 · 이미 등록된 키 → 점검표 ✓ · 질문 0', () async {
      final h = _Harness(root, const <String?>[]);
      h.rest.on('GET', configUrl, buildRegisteredResponse(keyId));

      final int code = await h.run();

      expect(code, wizardExitDone);
      expect(h.screen.asks, isEmpty);
      expect(h.output, contains('  ✓ ${DeviceCheckStep.stepTitle} — '));
      expect(h.session.hasEnteredDeviceCheckKey, isFalse);
      expect(
        DeviceCheckStep.buildPatchRequest(
          projectId,
          iosAppId,
          keyId: '<Key ID>',
          privateKey: '',
        ).displayCurl(),
        contains('-d \'{"keyId":"<Key ID>","privateKey":"<.p8 파일 내용>"}\''),
      );
      expect(
        DeviceCheckStep.buildIosAppGetRequest(projectId, iosAppId).url,
        Uri.parse('${managementPrefix}projects/$projectId/iosApps/$iosAppId'),
      );
    });
  });

  test(
    'T-20-DC-02: 재검사 privateKeySet true · keyId 다름 → ✗ · 다시 시도 고르기',
    () async {
      final h = _Harness(root, const <String?>[
        '1',
        '1',
        '2',
      ], session: buildSiwaSession());
      registerApplyFlow(h, buildRegisteredResponse(otherKeyId));

      final int code = await h.run();

      expect(code, wizardExitStopped);
      expect(h.output, contains('  실패 — '));
      expect(h.output, contains('  1) $retryOption\n  2) $stopOption'));
      expect(h.output, isNot(contains('  ✓ ${DeviceCheckStep.stepTitle} — ')));
    },
  );

  test('T-20-DC-03: 세션 키 없음 → .p8 경로 · Key ID 질문 · 두 버퍼 PEM 0회', () async {
    final h = _Harness(root, <String?>['1', keyPath(), '']);
    registerApplyFlow(h, buildRegisteredResponse(keyId));

    final int code = await h.run();

    expect(code, wizardExitDone);
    expect(
      h.screen.asks.where((String ask) => ask == 'DeviceCheck 용 .p8 파일 경로'),
      hasLength(1),
    );
    expect(
      h.screen.asks.where((String ask) => ask == appleKeyIdQuestion),
      hasLength(1),
    );
    expect(h.output, contains('  ✓ ${DeviceCheckStep.stepTitle} — '));
    expect(h.session.appleKeys[AppleKeyUse.deviceCheck]?.keyId, keyId);
    expect(h.session.hasEnteredDeviceCheckKey, isTrue);
    h.expectNoPem();
  });

  test('T-20-DC-04: 2(지금 안 함) → ✗ · 저장 0 · 세션 플래그 false', () async {
    final h = _Harness(root, const <String?>['2'], session: buildSiwaSession());
    h.rest.on('GET', configUrl, unregisteredResponse);
    final String xcconfigBefore = File(xcconfigPath()).readAsStringSync();

    final int code = await h.run();

    expect(code, wizardExitDone);
    expect(
      h.output.substring(h.output.indexOf(remainingHeading)),
      contains('  ✗ ${DeviceCheckStep.stepTitle} — 지금 안 함'),
    );
    expect(h.listRequests('PATCH'), isEmpty);
    expect(h.session.hasEnteredDeviceCheckKey, isFalse);
    expect(File(xcconfigPath()).readAsStringSync(), xcconfigBefore);
  });
}
