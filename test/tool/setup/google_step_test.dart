import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:test/test.dart';

import '../../../tool/setup/command_runner.dart';
import '../../../tool/setup/config_files.dart';
import '../../../tool/setup/flavor.dart';
import '../../../tool/setup/providers/fingerprints.dart';
import '../../../tool/setup/providers/icon_specs.dart';
import '../../../tool/setup/providers/idp_config.dart';
import '../../../tool/setup/redactor.dart';
import '../../../tool/setup/rest_client.dart';
import '../../../tool/setup/step.dart';
import '../../../tool/setup/steps/configure_step.dart';
import '../../../tool/setup/steps/flavor_steps.dart';
import '../../../tool/setup/steps/functions_step.dart';
import '../../../tool/setup/steps/google_android_step.dart';
import '../../../tool/setup/steps/google_ios_step.dart';
import '../../../tool/setup/steps/google_step.dart';
import '../../../tool/setup/steps/sign_in_step.dart';
import '../../../tool/setup/terminal.dart';
import '../../../tool/setup/wizard.dart';
import 'fake_rest_client.dart';
import 'fakes.dart';

/// 테스트 프로젝트 ID.
const String projectId = 'gp';

/// fixture config 의 앱 이름(example 파일 값).
const String appName = 'StarterKit Dev';

/// gcloud 계정이 돌려주는 가짜 지원 이메일 제안값.
const String suggestedEmail = 'owner@example.invalid';

/// 사용자가 고쳐 넣는 가짜 지원 이메일.
const String editedEmail = 'support@example.invalid';

/// config 의 Web client ID 자리표시(example 파일 값).
const String clientIdPlaceholder = 'YOUR_GOOGLE_SERVER_CLIENT_ID_HERE';

/// 계정 명령 키.
const String accountKey = 'gcloud config get-value account';

/// 프로젝트 describe 명령 키.
const String describeKey = 'gcloud projects describe $projectId --format=json';

/// 임시 config 로 auth 를 배포하는 명령 키.
const String deployKey =
    'firebase deploy --only auth --config .setup/auth-google.json '
    '--project $projectId --non-interactive';

/// Firebase Google 로그인 설정 GET 주소.
const String idpGetUrl =
    '$idpConfigUrlPrefix$projectId/defaultSupportedIdpConfigs/google.com';

/// fixture Gradle 의 applicationId.
const String applicationId = 'com.example.google_app';

/// fixture Android 설정 파일의 Firebase Android 앱 ID.
const String androidAppId = '1:000:android:google';

/// Firebase Android 앱 SHA 인증서 목록 주소.
const String shaUrl =
    'https://firebase.googleapis.com/v1beta1/projects/$projectId/androidApps/'
    '$androidAppId/sha';

/// 실행 시점에 조립하는 가짜 디버그 SHA-1(소문자 16진 40자).
String buildSha1() => 'ab' * 20;

/// SHA 인증서 목록 응답 — [hashes] 는 (해시, 종류) 쌍.
RestResponse buildShaList(List<(String, String)> hashes) => RestResponse(
  200,
  jsonEncode(<String, Object?>{
    if (hashes.isNotEmpty)
      'certificates': <Object?>[
        for (final (String hash, String type) in hashes)
          <String, Object?>{
            'name': 'projects/$projectId/androidApps/$androidAppId/sha/x',
            'shaHash': hash,
            'certType': type,
          },
      ],
  }),
);

/// 조직 경고 줄 원문.
const String organizationWarningText =
    '조직 밖 사용자가 Google 로그인을 하려면 동의 화면을 외부로 바꿔야 합니다 — '
    '매뉴얼 「로그인 수단 켜고 끄기」';

/// 실행 시점에 조립하는 가짜 Web client ID.
String buildWebClientId([String letter = 'a']) =>
    '${'1' * 12}-${letter * 32}.apps.googleusercontent.com';

/// 실행 시점에 조립하는 가짜 REVERSED_CLIENT_ID.
String buildReversedClientId([String letter = 'a']) =>
    'com.googleusercontent.apps.${'1' * 12}-${letter * 32}';

/// 실행 시점에 조립하는 가짜 client secret(가림 최소 길이보다 길다).
String buildClientSecret() => 'client-secret-${'s' * 16}';

/// [haystack] 에서 [needle] 이 나타나는 횟수를 센다.
int countText(String haystack, String needle) =>
    haystack.split(needle).length - 1;

/// 성공 결과.
CommandResult ok([String stdout = '']) => CommandResult(0, stdout, '');

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

/// 설정은 있지만 꺼져 있을 때의 응답.
final RestResponse disabledResponse = RestResponse(
  200,
  jsonEncode(<String, Object?>{
    'name': 'projects/$projectId/defaultSupportedIdpConfigs/google.com',
    'enabled': false,
  }),
);

/// 켜져 있을 때의 응답 — client secret 이 평문으로 실린다.
RestResponse buildEnabledResponse([String? clientId]) => RestResponse(
  200,
  jsonEncode(<String, Object?>{
    'name': 'projects/$projectId/defaultSupportedIdpConfigs/google.com',
    'enabled': true,
    'clientId': clientId ?? buildWebClientId(),
    'clientSecret': buildClientSecret(),
  }),
);

/// 상위가 [parentType] 인 가짜 describe 출력 — null 이면 상위 없음.
String buildDescribeOutput(String? parentType) => jsonEncode(<String, Object?>{
  'projectId': projectId,
  if (parentType != null)
    'parent': <String, Object?>{'type': parentType, 'id': '123'},
});

/// 이미 끝난 앞 단계 — Google 단계의 의존 단계를 대신한다.
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

/// 검사에서 한 번 할 일을 내고, 실행하면 끝나는 단계 — 앞 단계가 위저드를 멈추지
/// 않았는지 본다.
final class _PendingStep implements Step {
  _PendingStep(this.id);

  @override
  final String id;

  /// 실행 횟수.
  int applyCount = 0;

  @override
  String get title => '다음 단계';

  @override
  List<String> get dependsOn => const <String>[];

  @override
  bool get isCostlyOrIrreversible => false;

  @override
  Future<CheckResult> check(WizardContext context) async =>
      applyCount == 0 ? const Todo('할 일') : const Done('끝남');

  @override
  List<String> plannedCommandLines(WizardContext context) => const <String>[];

  @override
  Future<StepOutcome> apply(WizardContext context) async {
    applyCount++;
    return const Applied();
  }
}

/// 흘리는 명령이 실행되는 순간 등록한 함수를 부르는 실행기.
///
/// 결과는 감싼 가짜 실행기에 맡긴다 — 그 순간의 임시 파일 내용을 읽는 데 쓴다.
final class _StreamHookRunner implements CommandRunner {
  _StreamHookRunner(this.inner);

  final FakeCommandRunner inner;

  /// 명령 키 → 실행 순간에 부를 함수.
  final Map<String, void Function()> hooks = <String, void Function()>{};

  @override
  Future<CommandResult> capture(Command command) => inner.capture(command);

  @override
  Future<int> interactive(Command command) => inner.interactive(command);

  @override
  Future<CommandResult> stream(Command command) {
    hooks[FakeCommandRunner.buildKey(command)]?.call();
    return inner.stream(command);
  }
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

/// Google 단계 한 번 실행에 쓰는 가짜 실행기 · REST · 화면 · 기록 묶음.
final class _Harness {
  _Harness(this.root, List<String?> inputs)
    : runner = FakeCommandRunner(),
      rest = FakeRestClient(),
      screen = ScriptedTerminal(inputs),
      log = MemoryLogSink(Redactor()) {
    hookRunner = _StreamHookRunner(runner);
  }

  final String root;
  final FakeCommandRunner runner;
  late final _StreamHookRunner hookRunner;
  final FakeRestClient rest;
  final ScriptedTerminal screen;
  final MemoryLogSink log;

  /// 위저드 세션 — 지문 캐시를 미리 넣을 때 쓴다.
  WizardSession? session;

  /// 화면 출력 전체.
  String get output => screen.output.toString();

  /// Firebase Google 설정 GET 응답 큐에 [responses] 를 더한다.
  void onIdpGets(List<RestResponse> responses) {
    for (final response in responses) {
      rest.on('GET', idpGetUrl, response);
    }
  }

  /// 계정 · describe 명령 결과를 등록한다.
  void onLookups({CommandResult? account, CommandResult? describe}) {
    runner
      ..on(accountKey, account ?? ok('$suggestedEmail\n'))
      ..on(describeKey, describe ?? ok(buildDescribeOutput(null)));
  }

  /// 배포 결과를 [result] 로 등록하고, 실행 순간 임시 파일 내용을 [onDeploy] 에
  /// 넘긴다(파일이 없으면 null).
  void onDeploy(
    CommandResult result, {
    void Function(String? content)? onDeploy,
  }) {
    runner.on(deployKey, result);
    hookRunner.hooks[deployKey] = () {
      final file = File('$root/${GoogleStep.authConfigPath}');
      onDeploy?.call(file.existsSync() ? file.readAsStringSync() : null);
    };
  }

  /// dev 문맥으로 위저드를 만든다 — 키스토어가 없는 홈 · 기록을 남기는 REST 를
  /// 쓴다.
  WizardContext buildContext() => WizardContext(
    projectRoot: root,
    runner: hookRunner,
    terminal: RedactingTerminal(screen, log.redactor, log),
    redactor: log.redactor,
    log: log,
    rest: _LoggingRest(rest, log),
    session: session,
    homeDirectory: noKeystoreTestHome,
    random: Random(fixedTestRandomSeed),
    now: () => fixedTestNow,
  );

  /// 앞 단계(끝남) · Google 단계로 위저드를 돌린다.
  Future<int> run() => runSteps(<Step>[
    _FinishedStep('providers', '로그인 수단'),
    _FinishedStep('sign_in', SignInStep.stepTitle),
    GoogleStep(),
  ]);

  /// [steps] 로 위저드를 돌린다.
  Future<int> runSteps(List<Step> steps) => runWizard(buildContext(), steps);
}

void main() {
  late Directory tempDir;
  late String root;

  /// firebase.json fixture 내용.
  const firebaseJsonFixture =
      '{\n  "auth": {\n    "providers": {\n      "emailPassword": true\n'
      '    }\n  }\n}\n';

  /// 저장소 상대 경로에 내용을 쓴다(부모 디렉터리를 만든다).
  void writeFixture(String relativePath, String content) {
    File('$root/$relativePath')
      ..parent.createSync(recursive: true)
      ..writeAsStringSync(content);
  }

  /// dev config 절대 경로.
  String configPath() => '$root/${const FlavorPaths(Flavor.dev).json}';

  /// 임시 config 파일.
  File authConfigFile() => File('$root/${GoogleStep.authConfigPath}');

  /// 임시 디렉터리 안 모든 파일의 상대 경로 → 내용.
  Map<String, String> snapshotFiles() => <String, String>{
    for (final FileSystemEntity entity in Directory(
      root,
    ).listSync(recursive: true))
      if (entity is File)
        entity.path.substring(root.length + 1): entity.readAsStringSync(),
  };

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('google_step_test_');
    root = tempDir.path;
    const paths = FlavorPaths(Flavor.dev);
    writeFixture(paths.json, File(paths.jsonExample).readAsStringSync());
    replaceJsonString(configPath(), 'firebaseProjectId', projectId);
    replaceJsonString(configPath(), 'enabledAuthProviders', GoogleStep.token);
    writeFixture('firebase.json', firebaseJsonFixture);
  });

  tearDown(() {
    tempDir.deleteSync(recursive: true);
  });

  group('T-20-GOOGLE-01: 꺼져 있으면 값 표 확인 뒤 임시 config 로 켜고 '
      'Web client ID 를 config 에 쓴다', () {
    for (final (String label, RestResponse before) in <(String, RestResponse)>[
      ('설정 없음(404)', missingResponse),
      ('꺼짐(enabled: false)', disabledResponse),
    ]) {
      test(label, () async {
        final h = _Harness(root, const <String?>['y', '1'])
          ..onIdpGets(<RestResponse>[before, before, buildEnabledResponse()])
          ..onLookups();
        String? deployedContent;
        h.onDeploy(
          ok(),
          onDeploy: (String? content) => deployedContent = content,
        );

        expect(await h.run(), wizardExitDone);

        // 값 표 — 앱 이름 · 제안 이메일 · 안내 두 줄 · 고르기.
        expect(h.output, contains(appName));
        expect(h.output, contains(suggestedEmail));
        expect(h.output, contains('이미 동의 화면이 있으면 그 이름 · 이메일을 넣으세요'));
        expect(h.output, contains(SignInStep.defaultWebAppNotice));
        expect(h.output, contains('1) 이대로 진행'));
        expect(h.output, contains('2) 지원 이메일 고치기'));

        // 배포 — 흘리는 실행 1회 · 저장소 루트에서.
        expect(h.runner.countCalls(RunMode.stream, deployKey), 1);
        final FakeCall deploy = h.runner.calls.singleWhere(
          (FakeCall call) => call.key == deployKey,
        );
        expect(deploy.workingDirectory, root);

        // 실행 순간의 임시 파일 내용 = googleSignIn 블록(키 순서 그대로).
        expect(
          deployedContent,
          jsonEncode(<String, Object?>{
            'auth': <String, Object?>{
              'providers': <String, Object?>{
                'googleSignIn': <String, Object?>{
                  'oAuthBrandDisplayName': appName,
                  'supportEmail': suggestedEmail,
                },
              },
            },
          }),
        );
        expect(
          deployedContent,
          GoogleStep.buildAuthConfigContent(
            appName: appName,
            supportEmail: suggestedEmail,
          ),
        );

        // 실행 뒤 임시 파일 없음 · config 에 Web client ID.
        expect(authConfigFile().existsSync(), isFalse);
        expect(
          readJsonString(configPath(), 'googleServerClientId'),
          buildWebClientId(),
        );
        expect(h.output, contains('✓ Google 로그인'));
      });
    }
  });

  test('T-20-GOOGLE-02: 배포가 실패하면 실패 원문을 보이고 임시 파일을 지우며 '
      'config 를 쓰지 않는다', () async {
    final h = _Harness(root, const <String?>['y', '1', '2'])
      ..onIdpGets(<RestResponse>[missingResponse])
      ..onLookups();
    bool? existedAtDeploy;
    h.onDeploy(
      const CommandResult(1, 'deploy-error-fixture\n', ''),
      onDeploy: (String? content) => existedAtDeploy = content != null,
    );
    final String configBefore = File(configPath()).readAsStringSync();

    expect(await h.run(), wizardExitStopped);

    expect(existedAtDeploy, isTrue);
    expect(h.output, contains('실패 — Google 로그인을 켜지 못했습니다'));
    expect(h.output, contains('deploy-error-fixture'));
    expect(authConfigFile().existsSync(), isFalse);
    expect(File(configPath()).readAsStringSync(), configBefore);
    expect(
      readJsonString(configPath(), 'googleServerClientId'),
      clientIdPlaceholder,
    );
    // 검사 두 번 뒤 다시 읽지 않는다.
    expect(h.rest.countRequests('GET', idpGetUrl), 2);
  });

  test('T-20-GOOGLE-03: 지원 이메일 고치기는 형식이 틀리면 다시 묻고 고친 값을 '
      '임시 파일에 넣는다', () async {
    final h =
        _Harness(root, const <String?>[
            'y',
            '2',
            'not-an-email',
            editedEmail,
            '1',
          ])
          ..onIdpGets(<RestResponse>[
            missingResponse,
            missingResponse,
            buildEnabledResponse(),
          ])
          ..onLookups();
    String? deployedContent;
    h.onDeploy(ok(), onDeploy: (String? content) => deployedContent = content);

    expect(await h.run(), wizardExitDone);

    final List<String> emailAsks = h.screen.asks
        .where((String ask) => ask.startsWith('지원 이메일'))
        .toList();
    expect(emailAsks, hasLength(2));
    expect(h.output, contains('이메일 형식이 아닙니다'));
    final decoded = jsonDecode(deployedContent!) as Map<String, Object?>;
    final googleSignIn =
        ((decoded['auth']! as Map<String, Object?>)['providers']!
                as Map<String, Object?>)['googleSignIn']!
            as Map<String, Object?>;
    expect(googleSignIn['supportEmail'], editedEmail);
    expect(countText(deployedContent!, suggestedEmail), 0);
    // 고친 뒤 값 표를 다시 보인다.
    expect(countText(h.output, editedEmail), greaterThanOrEqualTo(1));
    expect(authConfigFile().existsSync(), isFalse);
  });

  group('T-20-GOOGLE-04: 프로젝트 상위가 조직이면 값 표에 조직 경고 한 줄을 '
      '보인다', () {
    /// describe 결과를 [describe] 로 두고 한 번 실행한 화면을 돌려준다.
    Future<String> runWithDescribe(CommandResult describe) async {
      final h = _Harness(root, const <String?>['y', '1'])
        ..onIdpGets(<RestResponse>[
          missingResponse,
          missingResponse,
          buildEnabledResponse(),
        ])
        ..onLookups(describe: describe);
      h.onDeploy(ok());
      expect(await h.run(), wizardExitDone);
      expect(h.runner.countCalls(RunMode.capture, describeKey), 1);
      return h.output;
    }

    test('상위 = organization → 경고 1줄', () async {
      final String output = await runWithDescribe(
        ok(buildDescribeOutput('organization')),
      );
      expect(countText(output, organizationWarningText), 1);
    });

    test('상위 = folder(조직 안) → 경고 1줄', () async {
      final String output = await runWithDescribe(
        ok(buildDescribeOutput('folder')),
      );
      expect(countText(output, organizationWarningText), 1);
    });

    test('상위 없음 → 경고 0', () async {
      final String output = await runWithDescribe(
        ok(buildDescribeOutput(null)),
      );
      expect(countText(output, organizationWarningText), 0);
    });

    test('describe 실패 → 경고 0 · 단계는 그대로 진행', () async {
      final String output = await runWithDescribe(
        const CommandResult(1, '', 'describe-error-fixture'),
      );
      expect(countText(output, organizationWarningText), 0);
    });
  });

  test('T-20-GOOGLE-05: client secret 은 화면 · 기록에 0회, 지원 이메일은 저장소 '
      '파일에 0회, firebase.json 은 무변경', () async {
    final Map<String, String> before = snapshotFiles();
    final h = _Harness(root, const <String?>['y', '1'])
      ..onIdpGets(<RestResponse>[
        missingResponse,
        missingResponse,
        buildEnabledResponse(),
      ])
      ..onLookups(describe: ok(buildDescribeOutput('organization')));
    h.onDeploy(ok());

    expect(await h.run(), wizardExitDone);

    final String secret = buildClientSecret();
    expect(countText(h.output, secret), 0);
    expect(countText(h.log.text, secret), 0);
    expect(
      countText(h.log.text, HttpRestClient.sensitiveResponseNotice),
      h.rest.countRequests('GET', idpGetUrl),
    );

    // 이메일이 실리는 두 명령은 민감 출력으로 실행한다.
    for (final key in <String>[accountKey, describeKey]) {
      final FakeCall call = h.runner.calls.singleWhere(
        (FakeCall call) => call.key == key,
      );
      expect(call.isOutputSensitive, isTrue, reason: key);
    }

    // 저장소 파일 — config 의 Web client ID 한 값만 바뀌고 이메일은 0회.
    final Map<String, String> after = snapshotFiles();
    expect(after.keys.toSet(), before.keys.toSet());
    expect(after['firebase.json'], firebaseJsonFixture);
    for (final MapEntry<String, String> entry in after.entries) {
      expect(countText(entry.value, suggestedEmail), 0, reason: entry.key);
      expect(countText(entry.value, secret), 0, reason: entry.key);
      if (entry.key == const FlavorPaths(Flavor.dev).json) continue;
      expect(entry.value, before[entry.key], reason: entry.key);
    }
    final String configPathKey = const FlavorPaths(Flavor.dev).json;
    expect(
      after[configPathKey],
      before[configPathKey]!.replaceFirst(
        clientIdPlaceholder,
        buildWebClientId(),
      ),
    );
    expect(countText(after[configPathKey]!, appName), 1);
  });

  group('T-20-GOOGLE-06: 켜져 있으면 배포하지 않는다', () {
    test('config 가 자리표시 → config 만 쓴다', () async {
      final h = _Harness(root, const <String?>['y'])
        ..onIdpGets(<RestResponse>[buildEnabledResponse()]);

      expect(await h.run(), wizardExitDone);

      expect(h.runner.calls, isEmpty);
      expect(
        readJsonString(configPath(), 'googleServerClientId'),
        buildWebClientId(),
      );
      expect(h.screen.asks, <String>[stepConfirmQuestion]);
    });

    test('config 가 같은 값 → ✓ · 질문 0', () async {
      replaceJsonString(
        configPath(),
        'googleServerClientId',
        buildWebClientId(),
      );
      final String configBefore = File(configPath()).readAsStringSync();
      final h = _Harness(root, const <String?>[])
        ..onIdpGets(<RestResponse>[buildEnabledResponse()]);

      expect(await h.run(), wizardExitDone);

      expect(h.runner.calls, isEmpty);
      expect(h.screen.asks, isEmpty);
      expect(File(configPath()).readAsStringSync(), configBefore);
      expect(h.output, contains('✓ Google 로그인'));
    });
  });

  group('T-20-GOOGLE-10: iOS 쪽 — 설정 파일의 REVERSED_CLIENT_ID 를 xcconfig 에 '
      '쓴다', () {
    const paths = FlavorPaths(Flavor.dev);

    /// xcconfig 절대 경로.
    String xcconfigPath() => '$root/${paths.xcconfig}';

    /// [reversedClientId] 를 담은 iOS 설정 파일을 쓴다(null 이면 키 없음).
    void writeIosPlist(String? reversedClientId) => writeFixture(
      paths.iosPlist,
      '<?xml version="1.0" encoding="UTF-8"?>\n'
      '<plist version="1.0">\n'
      '<dict>\n'
      '${reversedClientId == null ? '' : '\t<key>REVERSED_CLIENT_ID</key>\n\t<string>$reversedClientId</string>\n'}'
      '\t<key>PROJECT_ID</key>\n'
      '\t<string>$projectId</string>\n'
      '</dict>\n'
      '</plist>\n',
    );

    /// 앞 단계(끝남) · iOS 쪽 단계로 돌린다.
    Future<int> runIosSide(_Harness h) => h.runSteps(<Step>[
      _FinishedStep('google', GoogleStep.stepTitle),
      _FinishedStep('configure', '앱 등록 · 설정 파일'),
      GoogleIosStep(),
    ]);

    setUp(() {
      writeFixture(
        paths.xcconfig,
        File(paths.xcconfigExample).readAsStringSync(),
      );
    });

    test('다름 → ✗ · 실행하면 xcconfig 에 그 값 · 질문은 진행 확인 하나 · '
        '재검사 ✓', () async {
      writeIosPlist(buildReversedClientId());
      final h = _Harness(root, const <String?>['y']);

      expect(await runIosSide(h), wizardExitDone);

      expect(
        readXcconfigValue(xcconfigPath(), 'REVERSED_CLIENT_ID'),
        buildReversedClientId(),
      );
      expect(h.screen.asks, <String>[stepConfirmQuestion]);
      expect(h.output, contains('✓ ${GoogleIosStep.stepTitle}'));
      expect(h.runner.calls, isEmpty);
      expect(h.rest.requests, isEmpty);
    });

    test('같음 → ✓ · 질문 0', () async {
      writeIosPlist(buildReversedClientId());
      replaceXcconfigValue(
        xcconfigPath(),
        'REVERSED_CLIENT_ID',
        buildReversedClientId(),
      );
      final h = _Harness(root, const <String?>[]);

      expect(await runIosSide(h), wizardExitDone);

      expect(h.screen.asks, isEmpty);
      expect(h.output, contains('✓ ${GoogleIosStep.stepTitle}'));
    });

    for (final (String label, String? value) in <(String, String?)>[
      ('설정 파일에 없음', null),
      ('형식이 아님', 'com.example.not-reversed'),
    ]) {
      test('$label → 실행하면 실패 사유 · 매뉴얼 절 · xcconfig 무변경', () async {
        writeIosPlist(value);
        final String before = File(xcconfigPath()).readAsStringSync();
        final h = _Harness(root, const <String?>['y', '2']);

        expect(await runIosSide(h), wizardExitStopped);

        final String failureLine = h.output
            .split('\n')
            .firstWhere((String line) => line.startsWith('  실패 — '));
        expect(failureLine, contains('REVERSED_CLIENT_ID'));
        expect(failureLine, contains('매뉴얼 「로그인 수단 켜고 끄기」'));
        expect(File(xcconfigPath()).readAsStringSync(), before);
      });
    }
  });

  group('T-20-GOOGLE-11 ~ 13: Android 쪽 — 디버그 SHA-1 Firebase 등록', () {
    const paths = FlavorPaths(Flavor.dev);

    /// 지문 [fingerprints] 를 세션에 넣은 하네스를 만든다.
    _Harness buildAndroidHarness(
      List<String?> inputs,
      DebugFingerprints fingerprints,
    ) =>
        _Harness(root, inputs)
          ..session = (WizardSession()..debugFingerprints = fingerprints);

    /// 계산한 디버그 지문.
    FingerprintsAvailable buildAvailable() => FingerprintsAvailable(
      sha1Hex: buildSha1(),
      sha256Hex: 'cd' * 32,
      keyHash: 'q1AFhLJe1jbJyRsDcFRsODGFDxY=',
    );

    /// 앞 단계(끝남) · Android 쪽 단계 · [after] 로 돌린다.
    Future<int> runAndroidSide(_Harness h, {List<Step> after = const []}) =>
        h.runSteps(<Step>[
          _FinishedStep('google', GoogleStep.stepTitle),
          _FinishedStep('configure', '앱 등록 · 설정 파일'),
          GoogleAndroidStep(),
          ...after,
        ]);

    setUp(() {
      writeFixture(
        'android/app/build.gradle.kts',
        'android {\n'
            '    defaultConfig {\n'
            '        applicationId = "$applicationId"\n'
            '    }\n'
            '}\n',
      );
      writeFixture(
        paths.androidJson,
        jsonEncode(<String, Object?>{
          'project_info': <String, Object?>{'project_id': projectId},
          'client': <Object?>[
            <String, Object?>{
              'client_info': <String, Object?>{
                'mobilesdk_app_id': androidAppId,
                'android_client_info': <String, Object?>{
                  'package_name': '$applicationId.dev',
                },
              },
            },
          ],
        }),
      );
    });

    test('T-20-GOOGLE-11: 목록에 없으면 ✗ · 실행하면 SHA_1 소문자로 1회 등록 · '
        '재검사 ✓', () async {
      final h = buildAndroidHarness(const <String?>['y'], buildAvailable());
      h.rest
        ..on(
          'GET',
          shaUrl,
          buildShaList(<(String, String)>[('cd' * 32, 'SHA_256')]),
        )
        ..on(
          'GET',
          shaUrl,
          buildShaList(<(String, String)>[('cd' * 32, 'SHA_256')]),
        )
        ..on(
          'GET',
          shaUrl,
          buildShaList(<(String, String)>[
            ('cd' * 32, 'SHA_256'),
            (buildSha1(), 'SHA_1'),
          ]),
        )
        ..on('POST', shaUrl, const RestResponse(200, '{}'));

      expect(await runAndroidSide(h), wizardExitDone);

      final List<RestRequest> posts = h.rest.requests
          .where((RestRequest request) => request.method == 'POST')
          .toList();
      expect(posts, hasLength(1));
      expect(
        posts.single.body,
        '{"shaHash":"${buildSha1()}","certType":"SHA_1"}',
      );
      expect(h.output, contains('✓ ${GoogleAndroidStep.stepTitle}'));
      expect(h.screen.asks, <String>[stepConfirmQuestion]);
    });

    test('T-20-GOOGLE-12: 목록에 이미 있으면(대문자로 와도) ✓ · 쓰기 0', () async {
      final h = buildAndroidHarness(const <String?>[], buildAvailable());
      h.rest.on(
        'GET',
        shaUrl,
        buildShaList(<(String, String)>[(buildSha1().toUpperCase(), 'SHA_1')]),
      );

      expect(await runAndroidSide(h), wizardExitDone);

      expect(h.rest.countRequests('POST', shaUrl), 0);
      expect(h.screen.asks, isEmpty);
      expect(h.output, contains('✓ ${GoogleAndroidStep.stepTitle}'));
    });

    test('T-20-GOOGLE-13: 지문을 계산할 수 없으면 그 줄만 ✗ · SHA 요청 0 · 다음 '
        '단계 진행', () async {
      final h = buildAndroidHarness(const <String?>[
        'y',
      ], const FingerprintsUnavailable('fixture'));
      final next = _PendingStep('next');

      expect(await runAndroidSide(h, after: <Step>[next]), wizardExitDone);

      expect(h.rest.requests, isEmpty);
      expect(
        h.output,
        contains(
          '  ✗ ${GoogleAndroidStep.stepTitle} — $unavailableFingerprintGuide',
        ),
      );
      expect(next.applyCount, 1);
    });
  });

  group('T-20-GOOGLE-14: 단계 목록', () {
    test('켰으면 providers · google · configure · google_ios · google_android '
        '순서 · Functions 는 google · google_ios 를 기다린다', () {
      final List<Step> steps = buildSteps(
        flavor: Flavor.dev,
        enabledProviders: <String>{GoogleStep.token, 'facebook'},
      );
      final ids = <String>[for (final Step step in steps) step.id];
      final int start = ids.indexOf('providers');

      // Google · Facebook 콘솔에는 아이콘 칸이 있어 앱 아이콘 단계가 그 사이에 있다.
      expect(ids.sublist(start, start + 6), <String>[
        'providers',
        'app_icon',
        'google',
        'configure',
        'google_ios',
        'google_android',
      ]);
      expect(ids.where((String id) => id == 'configure'), hasLength(1));
      final ConfigureStep configure = steps.whereType<ConfigureStep>().single;
      expect(configure.requiresGoogleClient, isTrue);
      expect(configure.dependsOn, contains('google'));
      final FunctionsStep functions = steps.whereType<FunctionsStep>().single;
      expect(
        functions.dependsOn,
        containsAll(<String>['google', 'google_ios']),
      );
      expect(functions.dependsOn, contains('facebook'));
      expect(functions.dependsOn, isNot(contains('google_android')));
      final Step google = steps.firstWhere(
        (Step step) => step.id == GoogleStep.token,
      );
      expect(google.title, 'Google 로그인');
      expect(google.dependsOn, <String>['providers', 'sign_in']);
      for (final id in <String>['google_ios', 'google_android']) {
        expect(
          steps.firstWhere((Step step) => step.id == id).dependsOn,
          <String>['google', 'configure'],
        );
      }
    });

    test('켜지 않았으면 Google 단계 0 · 앱 등록은 Google 클라이언트를 요구하지 '
        '않는다', () {
      final List<Step> steps = buildSteps(
        flavor: Flavor.dev,
        enabledProviders: <String>{'kakao'},
      );
      final ids = <String>[for (final Step step in steps) step.id];

      expect(ids.where((String id) => id.startsWith('google')), isEmpty);
      // Kakao 콘솔에는 아이콘 칸이 있어 앱 아이콘 단계가 그 사이에 있다.
      expect(ids.indexOf('app_icon'), ids.indexOf('providers') + 1);
      expect(ids.indexOf('configure'), ids.indexOf('providers') + 2);
      final ConfigureStep configure = steps.whereType<ConfigureStep>().single;
      expect(configure.requiresGoogleClient, isFalse);
      expect(configure.dependsOn, <String>[
        'firebase_project',
        'identity',
        'tools',
      ]);
      expect(
        steps.whereType<FunctionsStep>().single.dependsOn,
        isNot(contains('google')),
      );
    });
  });

  group('T-20.1-ROW-03: 동의 화면 값 표에 로고 경로 행과 브랜드 인증 노트가 있고 '
      '앱 이름 · 지원 이메일 · 기존 노트는 그대로다', () {
    final IconSpec spec = findIconSpec(GoogleStep.token)!;
    const brandNote =
        '동의 화면 로고: 출시 전 선택입니다 — 올리면 Google 의 브랜드 인증을 거쳐야 동의 화면에 보입니다';

    /// 로고 파일 자리에 가짜 바이트를 둔다(크기 · 형식은 보지 않는다).
    void placeLogoFile() {
      File('$root/${spec.relativePath}')
        ..parent.createSync(recursive: true)
        ..writeAsBytesSync(const <int>[1, 2, 3]);
    }

    /// 화면 [lines] 의 동의 화면 표마다 행 줄(머리 다음 ~ 첫 노트 줄 앞)을 고른다.
    List<List<String>> selectValueTables(List<String> lines) => <List<String>>[
      for (var i = 0; i < lines.length; i++)
        if (lines[i] == '── ${GoogleStep.summaryTitle} ──')
          lines.sublist(
            i + 1,
            lines.indexWhere((String line) => line.startsWith('  · '), i),
          ),
    ];

    /// 표 행 [rows] 가 앱 이름 · 지원 이메일 · 로고([logoValue]) 세 행인지 본다.
    void expectTableRows(List<String> rows, String email, String logoValue) {
      /// [label] 과 [value] 가 한 줄에 있는 행 모양.
      RegExp buildRowPattern(String label, String value) =>
          RegExp('^  ${RegExp.escape(label)} +${RegExp.escape(value)}\$');

      expect(rows, hasLength(3), reason: rows.join('\n'));
      expect(
        rows[0],
        matches(buildRowPattern(GoogleStep.appNameRowLabel, appName)),
      );
      expect(
        rows[1],
        matches(buildRowPattern(GoogleStep.supportEmailRowLabel, email)),
      );
      expect(rows[2], matches(buildRowPattern(spec.rowLabel, logoValue)));
    }

    /// 화면 [lines] 의 노트가 기존 두 줄 다음 브랜드 인증 노트인지 본다.
    void expectNotes(List<String> lines, int tableCount) {
      final String output = lines.join('\n');
      expect(countText(output, '  · $brandNote'), tableCount);
      expect(
        countText(output, '  · ${GoogleStep.existingBrandNote}'),
        tableCount,
      );
      for (var i = 0; i < lines.length; i++) {
        if (lines[i] != '  · ${SignInStep.defaultWebAppNotice}') continue;
        expect(lines[i + 1], '  · $brandNote');
      }
    }

    /// 배포 순간 임시 파일 [content] 에 로고 경로 · 파일 이름이 없는지 본다.
    void expectNoLogoInDeploy(String? content) {
      expect(content, isNotNull);
      expect(content, isNot(contains(spec.fileName)));
      expect(content, isNot(contains(iconsDirectory)));
    }

    test('로고 파일이 없으면 「아직 없음」 문장과 노트를 보인다', () async {
      final h = _Harness(root, const <String?>['y', '1'])
        ..onIdpGets(<RestResponse>[
          missingResponse,
          missingResponse,
          buildEnabledResponse(),
        ])
        ..onLookups();
      String? deployedContent;
      h.onDeploy(
        ok(),
        onDeploy: (String? content) => deployedContent = content,
      );

      expect(await h.run(), wizardExitDone, reason: h.output);

      final List<String> lines = h.output.split('\n');
      final List<List<String>> tables = selectValueTables(lines);
      expect(spec.rowLabel, '동의 화면 로고 · 출시 전 선택');
      expect(tables, hasLength(1), reason: h.output);
      expectTableRows(tables.single, suggestedEmail, missingIconValue);
      expectNotes(lines, 1);
      expectNoLogoInDeploy(deployedContent);
    });

    test('로고 파일이 있으면 그 상대 경로를 보인다', () async {
      placeLogoFile();
      final h = _Harness(root, const <String?>['y', '1'])
        ..onIdpGets(<RestResponse>[
          missingResponse,
          missingResponse,
          buildEnabledResponse(),
        ])
        ..onLookups();
      String? deployedContent;
      h.onDeploy(
        ok(),
        onDeploy: (String? content) => deployedContent = content,
      );

      expect(await h.run(), wizardExitDone, reason: h.output);

      final List<String> lines = h.output.split('\n');
      final List<List<String>> tables = selectValueTables(lines);
      expect(spec.relativePath, '.setup/icons/google-120x120.png');
      expect(tables, hasLength(1), reason: h.output);
      expectTableRows(tables.single, suggestedEmail, spec.relativePath);
      expect(h.output, isNot(contains('$root/${spec.relativePath}')));
      expectNotes(lines, 1);
      expectNoLogoInDeploy(deployedContent);
    });

    test('지원 이메일을 고쳐 표가 다시 보여도 로고 행이 매번 있고 배포 임시 파일에는 '
        '로고 경로가 없다', () async {
      placeLogoFile();
      final h =
          _Harness(root, const <String?>[
              'y',
              '2',
              'not-an-email',
              editedEmail,
              '1',
            ])
            ..onIdpGets(<RestResponse>[
              missingResponse,
              missingResponse,
              buildEnabledResponse(),
            ])
            ..onLookups();
      String? deployedContent;
      h.onDeploy(
        ok(),
        onDeploy: (String? content) => deployedContent = content,
      );

      expect(await h.run(), wizardExitDone, reason: h.output);

      final List<String> lines = h.output.split('\n');
      final List<List<String>> tables = selectValueTables(lines);
      expect(tables, hasLength(2), reason: h.output);
      expectTableRows(tables[0], suggestedEmail, spec.relativePath);
      expectTableRows(tables[1], editedEmail, spec.relativePath);
      expectNotes(lines, 2);
      expectNoLogoInDeploy(deployedContent);
      expect(authConfigFile().existsSync(), isFalse);
    });
  });
}
