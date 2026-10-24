import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:test/test.dart';

import '../../../tool/setup/build_inputs.dart';
import '../../../tool/setup/command_runner.dart';
import '../../../tool/setup/config_files.dart';
import '../../../tool/setup/firebase_app_files.dart';
import '../../../tool/setup/flavor.dart';
import '../../../tool/setup/rebuild_markers.dart';
import '../../../tool/setup/redactor.dart';
import '../../../tool/setup/rest_client.dart';
import '../../../tool/setup/setup_entry.dart';
import '../../../tool/setup/step.dart';
import '../../../tool/setup/steps/app_check_step.dart';
import '../../../tool/setup/steps/dev_steps.dart';
import '../../../tool/setup/steps/run_step.dart';
import '../../../tool/setup/steps/user_files_step.dart';
import '../../../tool/setup/terminal.dart';
import '../../../tool/setup/uuid.dart';
import '../../../tool/setup/wizard.dart';
import 'fake_rest_client.dart';
import 'fakes.dart';
import 'firebase_options_fixture.dart';

/// 테스트 프로젝트 ID.
const String projectId = 'p';

/// fixture Gradle 의 applicationId.
const String applicationId = 'com.example.app_android';

/// fixture iOS 앱 ID.
const String iosAppId = '1:000:ios:fake';

/// fixture Android 앱 ID.
const String androidAppId = '1:000:android:fake';

/// App Check API 주소의 앞부분.
const String appCheckPrefix = 'https://firebaseappcheck.googleapis.com/v1/';

/// iOS 앱 디버그 토큰 목록 주소.
const String iosTokensUrl =
    '${appCheckPrefix}projects/$projectId/apps/$iosAppId/debugTokens';

/// Android 앱 디버그 토큰 목록 주소.
const String androidTokensUrl =
    '${appCheckPrefix}projects/$projectId/apps/$androidAppId/debugTokens';

/// 위저드가 쓰는 고정 표시 이름.
const String wizardDisplayName = 'setup-wizard-dev';

/// stg 테스트 프로젝트 ID.
const String stgProjectId = 'p-stg';

/// fixture stg iOS 앱 ID.
const String stgIosAppId = '1:111:ios:stg';

/// fixture stg Android 앱 ID.
const String stgAndroidAppId = '1:111:android:stg';

/// stg iOS 앱 디버그 토큰 목록 주소.
const String stgIosTokensUrl =
    '${appCheckPrefix}projects/$stgProjectId/apps/$stgIosAppId/debugTokens';

/// stg Android 앱 디버그 토큰 목록 주소.
const String stgAndroidTokensUrl =
    '${appCheckPrefix}projects/$stgProjectId/apps/$stgAndroidAppId/debugTokens';

/// stg 실행이 쓰는 표시 이름.
const String stgDisplayName = 'setup-wizard-stg';

/// stg 실행의 요청 표시형에서 토큰 자리에 보이는 글자.
const String stgTokenDisplay = '<config/stg.json 의 appCheckDebugToken>';

/// 실행 시점에 조립한 가짜 API 키 — 소스에 완형을 두지 않는다.
final String fakeApiKey = 'AIza${'x' * 35}';

/// 이미 끝난 앞 단계 — App Check 단계의 의존 단계를 대신한다.
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

/// 실행하면 실패하는 할 일 단계 — 앞 실행이 중간에 멈추는 모양을 만든다.
final class _FailingStep implements Step {
  _FailingStep(this.id, this.title);

  @override
  final String id;

  @override
  final String title;

  @override
  List<String> get dependsOn => const <String>[];

  @override
  bool get isCostlyOrIrreversible => false;

  @override
  Future<CheckResult> check(WizardContext context) async =>
      const Todo('배포할 함수가 있습니다');

  @override
  List<String> plannedCommandLines(WizardContext context) => const <String>[];

  @override
  Future<StepOutcome> apply(WizardContext context) async =>
      const Failed('배포가 실패했습니다');
}

/// 디버그 토큰 목록 응답을 만든다 — [names] 는 `<표시 이름>:<id>` 꼴.
RestResponse buildTokenList(String tokensUrl, List<String> names) =>
    RestResponse(
      200,
      jsonEncode(<String, Object?>{
        if (names.isNotEmpty)
          'debugTokens': <Object?>[
            for (final String entry in names)
              <String, Object?>{
                'name':
                    '${tokensUrl.substring(appCheckPrefix.length)}/'
                    '${entry.split(':').last}',
                'displayName': entry.split(':').first,
                'updateTime': '2030-01-01T00:00:00Z',
              },
          ],
      }),
    );

/// 토큰을 새로 만드는 흐름의 REST 응답을 등록한 가짜 REST 실행기를 만든다.
///
/// iOS 앱에는 옛 고정 이름 항목이 있어 지운 뒤 등록하고, Android 앱은 빈
/// 목록에서 등록한다. 재검사 목록에는 두 앱 모두 새 항목이 있다.
FakeRestClient buildCreateFlowRest() => FakeRestClient()
  ..on(
    'GET',
    iosTokensUrl,
    buildTokenList(iosTokensUrl, <String>[
      '$wizardDisplayName:old1',
      'manual:keep',
    ]),
  )
  ..on(
    'GET',
    iosTokensUrl,
    buildTokenList(iosTokensUrl, <String>[
      'manual:keep',
      '$wizardDisplayName:new1',
    ]),
  )
  ..on('GET', androidTokensUrl, buildTokenList(androidTokensUrl, []))
  ..on(
    'GET',
    androidTokensUrl,
    buildTokenList(androidTokensUrl, <String>['$wizardDisplayName:new2']),
  )
  ..on('DELETE', '$iosTokensUrl/old1', const RestResponse(200, '{}'))
  ..on('POST', iosTokensUrl, const RestResponse(200, '{}'))
  ..on('POST', androidTokensUrl, const RestResponse(200, '{}'));

/// 실행 단계 시험의 가짜 iOS 시뮬레이터 id — UUID 모양(실제 UDID 와 같은 꼴).
const String runSimulatorId = '0A1B2C3D-4E5F-4A6B-8C7D-9E0F1A2B3C4D';

/// 인증된 이메일 · 비밀번호 사용자 [count] 명이 든 사용자 목록(batchGet) 응답을
/// 만든다.
RestResponse buildVerifiedUsersPage(int count) => RestResponse(
  200,
  jsonEncode(<String, Object?>{
    'kind': 'identitytoolkit#DownloadAccountResponse',
    'users': <Object?>[
      for (var i = 0; i < count; i++)
        <String, Object?>{
          'localId': 'u$i',
          'email': 'u$i@example.invalid',
          'emailVerified': true,
          'providerUserInfo': <Object?>[
            <String, Object?>{
              'providerId': 'password',
              'email': 'u$i@example.invalid',
              'rawId': 'u$i@example.invalid',
            },
          ],
        },
    ],
  }),
);

/// iOS 시뮬레이터 하나 · macOS 데스크톱 하나가 든 기기 목록 성공 출력을 만든다.
CommandResult buildRunDevicesOutput() => CommandResult(
  0,
  jsonEncode(<Object?>[
    <String, Object?>{
      'name': 'iPhone 17',
      'id': runSimulatorId,
      'isSupported': true,
      'targetPlatform': 'ios',
      'emulator': true,
      'sdk': 'sdk',
    },
    <String, Object?>{
      'name': 'macOS',
      'id': 'macos',
      'isSupported': true,
      'targetPlatform': 'darwin',
      'emulator': false,
      'sdk': 'sdk',
    },
  ]),
  '',
);

/// 실행 단계의 준비(패키지 받기 · 코드 생성) · 기기 목록 · 앱 실행을 성공으로
/// 등록한다.
void registerRunCommands(FakeCommandRunner runner) {
  runner
    ..on(
      FakeCommandRunner.buildKey(RunStep.buildPubGetCommand()),
      const CommandResult(0, 'Got dependencies!\n', ''),
    )
    ..on(
      FakeCommandRunner.buildKey(RunStep.buildCodegenCommand()),
      const CommandResult(0, 'Built with build_runner\n', ''),
    )
    ..on(
      FakeCommandRunner.buildKey(RunStep.buildDevicesCommand()),
      buildRunDevicesOutput(),
    )
    ..on(
      FakeCommandRunner.buildKey(RunStep.buildRunCommand(runSimulatorId)),
      const CommandResult(0, '', ''),
    );
}

void main() {
  late Directory tempDir;
  late String root;
  late File config;

  /// 저장소 상대 경로에 내용을 쓴다(부모 디렉터리를 만든다).
  void writeFixture(String relativePath, String content) {
    File('$root/$relativePath')
      ..parent.createSync(recursive: true)
      ..writeAsStringSync(content);
  }

  /// 앱 등록이 끝난 모양의 설정 파일 3개를 쓴다(Dart 설정 파일 = FlutterFire 생성본 모양).
  ///
  /// [flavor] 를 주면 그 flavor 경로에 [project] · [ios] · [android] 값으로 쓴다.
  void writeAppFiles({
    Flavor flavor = Flavor.dev,
    String project = projectId,
    String ios = iosAppId,
    String android = androidAppId,
  }) {
    final paths = FlavorPaths(flavor);
    writeFixture(
      paths.dartOptions,
      buildGeneratedOptionsSource(
        projectId: project,
        apiKey: fakeApiKey,
        androidAppId: android,
        iosAppId: ios,
      ),
    );
    writeFixture(
      paths.iosPlist,
      '<plist version="1.0">\n'
      '<dict>\n'
      '\t<key>API_KEY</key>\n'
      '\t<string>$fakeApiKey</string>\n'
      '\t<key>PROJECT_ID</key>\n'
      '\t<string>$project</string>\n'
      '\t<key>GOOGLE_APP_ID</key>\n'
      '\t<string>$ios</string>\n'
      '</dict>\n'
      '</plist>\n',
    );
    writeFixture(
      paths.androidJson,
      jsonEncode(<String, Object?>{
        'project_info': <String, Object?>{'project_id': project},
        'client': <Object?>[
          <String, Object?>{
            'client_info': <String, Object?>{
              'mobilesdk_app_id': android,
              'android_client_info': <String, Object?>{
                'package_name': '$applicationId${flavor.suffix}',
              },
            },
            'api_key': <Object?>[
              <String, Object?>{'current_key': fakeApiKey},
            ],
          },
        ],
      }),
    );
  }

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('app_check_step_test_');
    root = tempDir.path;
    config = File('$root/${UserFilesStep.jsonUserPath}')
      ..parent.createSync(recursive: true);
    File(UserFilesStep.jsonExamplePath).copySync(config.path);
    replaceJsonString(config.path, 'firebaseProjectId', projectId);
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

  /// config 의 디버그 토큰 값.
  String readToken() =>
      readJsonString(config.path, AppCheckStep.tokenKey) ?? '<없음>';

  /// 앞 단계(끝남) · App Check 단계로 위저드를 돌린다.
  ///
  /// [session] 을 주면 그 세션으로 돌린다 — 실행 뒤 세션 상태를 읽을 때 쓴다.
  Future<int> runAppCheckStep(
    FakeRestClient rest,
    ScriptedTerminal terminal, {
    FakeCommandRunner? runner,
    MemoryLogSink? log,
    Random? random,
    WizardSession? session,
  }) => runWizard(
    buildTestContext(
      projectRoot: root,
      runner: runner,
      terminal: terminal,
      log: log,
      rest: rest,
      random: random,
      session: session,
    ),
    <Step>[
      _FinishedStep('configure', '앱 등록 · 설정 파일'),
      _FinishedStep('apis', '필요한 Google Cloud API'),
      AppCheckStep(),
    ],
  );

  /// stg config(example 복사 · stg 프로젝트 ID)와 stg 앱 설정 파일 3개를 쓴다.
  File writeStgFixture() {
    const paths = FlavorPaths(Flavor.stg);
    final stgConfig = File('$root/${paths.json}')
      ..parent.createSync(recursive: true);
    File(paths.jsonExample).copySync(stgConfig.path);
    replaceJsonString(stgConfig.path, 'firebaseProjectId', stgProjectId);
    writeAppFiles(
      flavor: Flavor.stg,
      project: stgProjectId,
      ios: stgIosAppId,
      android: stgAndroidAppId,
    );
    return stgConfig;
  }

  /// 앞 단계(끝남) · App Check 단계를 stg 문맥으로 돌린다.
  Future<int> runStgAppCheckStep(
    FakeRestClient rest,
    ScriptedTerminal terminal, {
    MemoryLogSink? log,
  }) {
    final MemoryLogSink usedLog = log ?? MemoryLogSink(Redactor());
    return runWizard(
      WizardContext(
        projectRoot: root,
        runner: FakeCommandRunner(),
        terminal: RedactingTerminal(terminal, usedLog.redactor, usedLog),
        redactor: usedLog.redactor,
        log: usedLog,
        rest: rest,
        flavor: Flavor.stg,
        random: Random(fixedTestRandomSeed),
        now: () => fixedTestNow,
      ),
      <Step>[
        _FinishedStep('configure', '앱 등록 · 설정 파일'),
        _FinishedStep('apis', '필요한 Google Cloud API'),
        AppCheckStep(),
      ],
    );
  }

  /// [method] 요청만 모은다.
  List<RestRequest> listRequests(FakeRestClient rest, String method) => rest
      .requests
      .where((RestRequest request) => request.method == method)
      .toList();

  test(
    'T-19-APPCHECK-01 config 토큰이 UUID4 이고 두 앱 목록에 고정 이름이 있으면 ✓ · POST 0',
    () async {
      writeAppFiles();
      replaceJsonString(
        config.path,
        AppCheckStep.tokenKey,
        generateUuidV4(Random(7)),
      );
      final rest = FakeRestClient()
        ..on(
          'GET',
          iosTokensUrl,
          buildTokenList(iosTokensUrl, <String>['$wizardDisplayName:a1']),
        )
        ..on(
          'GET',
          androidTokensUrl,
          buildTokenList(androidTokensUrl, <String>[
            'someone:b0',
            '$wizardDisplayName:b1',
          ]),
        );
      final terminal = ScriptedTerminal(const <String?>[]);
      final session = WizardSession();

      final int code = await runAppCheckStep(rest, terminal, session: session);

      expect(code, wizardExitDone);
      expect(
        terminal.output.toString(),
        contains('  ✓ ${AppCheckStep.stepTitle} — '),
      );
      expect(terminal.asks, isEmpty);
      expect(listRequests(rest, 'POST'), isEmpty);
      expect(listRequests(rest, 'DELETE'), isEmpty);
      // 이미 끝난 단계는 새 토큰을 등록하지 않았으므로 다시 빌드 신호를 남기지 않는다.
      expect(session.hasRegisteredAppCheckToken, isFalse);
      expect(
        File(
          '$root/${buildAppCheckPendingMarkerPath(Flavor.dev)}',
        ).existsSync(),
        isFalse,
      );
    },
  );

  group('토큰을 새로 만드는 흐름', () {
    late FakeRestClient rest;
    late ScriptedTerminal terminal;
    late MemoryLogSink log;
    late FakeCommandRunner runner;
    late WizardSession session;
    late int code;

    setUp(() async {
      writeAppFiles();
      expect(readToken(), '');
      rest = buildCreateFlowRest();
      terminal = ScriptedTerminal(const <String?>['y']);
      log = MemoryLogSink(Redactor());
      runner = FakeCommandRunner();
      session = WizardSession();
      code = await runAppCheckStep(
        rest,
        terminal,
        runner: runner,
        log: log,
        session: session,
      );
    });

    test('토큰을 새로 만들어 등록하면 세션에 다시 빌드 신호를 남긴다', () {
      expect(code, wizardExitDone);
      expect(session.hasRegisteredAppCheckToken, isTrue);
    });

    test(
      'T-19-APPCHECK-02 빈 토큰 → y 뒤 config 에 UUID4 · 두 앱 옛 고정 이름 항목 DELETE · POST 본문에 새 토큰 · 재검사 ✓',
      () {
        final String token = readToken();
        final output = terminal.output.toString();
        expect(code, wizardExitDone);
        expect(isUuidV4(token), isTrue);
        expect(rest.countRequests('DELETE', '$iosTokensUrl/old1'), 1);
        expect(listRequests(rest, 'DELETE'), hasLength(1));
        final List<RestRequest> posts = listRequests(rest, 'POST');
        expect(
          posts.map((RestRequest request) => request.url.toString()).toSet(),
          <String>{iosTokensUrl, androidTokensUrl},
        );
        for (final post in posts) {
          expect(jsonDecode(post.body!), <String, Object?>{
            'displayName': wizardDisplayName,
            'token': token,
          });
          expect(post.quotaProject, projectId);
        }
        final int deleteAt = rest.requests.indexWhere(
          (RestRequest request) => request.method == 'DELETE',
        );
        final int iosPostAt = rest.requests.indexWhere(
          (RestRequest request) =>
              request.method == 'POST' &&
              request.url.toString() == iosTokensUrl,
        );
        expect(deleteAt, lessThan(iosPostAt));
        expect(output, contains(AppCheckStep.rebuildNotice));
        expect(
          AppCheckStep.rebuildNotice,
          '앱을 다시 빌드해야 새 토큰이 들어갑니다 — 마지막 단계가 빌드합니다.',
        );
        expect(output, contains('  ✓ ${AppCheckStep.stepTitle} — '));
      },
    );

    test(
      'T-19-APPCHECK-03 화면 · 기록 · 실행기 인자에 토큰 0 · 화면은 표시형 · 토큰은 POST 본문에만',
      () {
        final String token = readToken();
        final output = terminal.output.toString();
        expect(token.length, 36);
        expect(output, isNot(contains(token)));
        expect(output, isNot(contains(token.toUpperCase())));
        expect(log.text, isNot(contains(token)));
        expect(output, contains('"token":"${AppCheckStep.tokenDisplay}"'));
        expect(
          AppCheckStep.tokenDisplay,
          '<config/dev.json 의 appCheckDebugToken>',
        );
        expect(runner.calls, isEmpty);
        for (final RestRequest request in rest.requests) {
          expect(request.url.toString(), isNot(contains(token)));
          expect(request.bodyDisplay ?? '', isNot(contains(token)));
          if (request.method != 'POST') {
            expect(request.body ?? '', isNot(contains(token)));
          }
        }
        expect(
          listRequests(
            rest,
            'POST',
          ).every((RestRequest request) => request.body!.contains(token)),
          isTrue,
        );
        for (final secret in <String>[iosAppId, androidAppId]) {
          expect(output, isNot(contains(secret)));
          expect(log.text, isNot(contains(secret)));
        }
      },
    );
  });

  test('T-21-RUN-01 같은 실행에서 토큰을 새로 만들면 인증된 사용자가 있어도 실행 단계가 '
      '다시 빌드 사유를 보이고 준비 · 실행 각 1회 뒤 ✓ · 종료 0', () async {
    writeAppFiles();
    final rest = buildCreateFlowRest()
      ..on(
        'GET',
        RunStep.buildBatchGetRequest(projectId).url.toString(),
        buildVerifiedUsersPage(1),
      );
    final runner = FakeCommandRunner();
    registerRunCommands(runner);
    // App Check 진행 y → 실행 단계 진행 y → 기기 고르기 기본값.
    final terminal = ScriptedTerminal(const <String?>['y', 'y', '']);
    final log = MemoryLogSink(Redactor());
    final WizardContext context = buildTestContext(
      projectRoot: root,
      runner: runner,
      terminal: terminal,
      log: log,
      rest: rest,
    );

    final int code = await runWizard(context, <Step>[
      _FinishedStep('configure', '앱 등록 · 설정 파일'),
      _FinishedStep('apis', '필요한 Google Cloud API'),
      AppCheckStep(),
      _FinishedStep('functions', 'Cloud Functions 배포'),
      _FinishedStep('sign_in', '로그인 수단 (이메일 · 익명)'),
      _FinishedStep('rules', 'Firestore · Storage rules'),
      RunStep(delay: (Duration duration) async {}),
    ]);

    final output = terminal.output.toString();
    expect(code, wizardExitDone);

    // App Check 안내가 실행 단계 머리보다 앞에 있다.
    final int noticeAt = output.indexOf(AppCheckStep.rebuildNotice);
    final int runHeadAt = output.indexOf('▶ ${RunStep.stepTitle}');
    expect(noticeAt, greaterThanOrEqualTo(0));
    expect(runHeadAt, greaterThan(noticeAt));

    // 사용자가 1명 있어도 실행 단계가 다시 빌드 사유로 할 일이 된다.
    expect(
      output,
      contains(
        '▶ ${RunStep.stepTitle}\n'
        '  ${RunStep.rebuildReasonPrefix}${RunStep.appCheckTokenReason}\n',
      ),
    );
    expect(
      RunStep.rebuildReasonPrefix + RunStep.appCheckTokenReason,
      '앱을 다시 빌드해야 합니다 — 이번 실행에서 App Check 디버그 토큰을 등록했습니다',
    );

    // 안내는 다시 빌드 안내 그대로 — 가입 안내 · 가입 확인 끝줄은 보이지 않는다.
    final List<String> guideLines = RunStep.buildRebuildGuideLines(context);
    expect(guideLines, hasLength(2));
    expect(guideLines.first, contains('(이메일만)'));
    expect(guideLines.last, '  ${RunStep.rebuildQuitLine}');
    for (final line in guideLines) {
      expect(output, contains('$line\n'));
    }
    expect(output, isNot(contains(RunStep.quitLine)));
    expect(output, isNot(contains(RunStep.signUpGuideLines.first)));

    // 준비(패키지 받기 → 코드 생성)와 앱 실행이 각 1회다.
    final streamKeys = <String>[
      for (final FakeCall call in runner.calls)
        if (call.mode == RunMode.stream) call.key,
    ];
    expect(streamKeys, <String>[
      'fvm flutter pub get',
      'fvm dart run build_runner build --delete-conflicting-outputs',
    ]);
    expect(runner.countMode(RunMode.interactive), 1);
    expect(
      runner.countCalls(
        RunMode.interactive,
        FakeCommandRunner.buildKey(RunStep.buildRunCommand(runSimulatorId)),
      ),
      1,
    );

    // 다시 빌드한 뒤의 재검사는 사유 없이 ✓ 로 끝난다.
    expect(output, contains('  ✓ 앱 실행 · 로그인 확인 — 인증된 이메일 사용자 1명'));
    expect(context.session.hasRegisteredAppCheckToken, isTrue);
    final Map<String, String?>? launched = context.session.launchedBuildInputs;
    expect(launched, isNotNull);
    const paths = FlavorPaths(Flavor.dev);
    expect(launched!.keys.toList(), <String>[
      paths.json,
      paths.xcconfig,
      paths.dartOptions,
      paths.iosPlist,
      paths.androidJson,
    ]);
    expect(launched[paths.json], isNotNull);
    expect(launched[paths.xcconfig], isNull);
    // 지문은 세션 메모리에만 있고 화면 · 기록에는 쓰지 않는다.
    for (final String? digest in launched.values) {
      if (digest == null) continue;
      expect(output, isNot(contains(digest)));
      expect(log.text, isNot(contains(digest)));
    }
  });

  test(
    'T-19-APPCHECK-04 토큰이 있고 Android 앱에만 항목이 없으면 Android POST 1회 · DELETE 0 · iOS 는 목록 GET 만',
    () async {
      writeAppFiles();
      final String token = generateUuidV4(Random(8));
      replaceJsonString(config.path, AppCheckStep.tokenKey, token);
      final rest = FakeRestClient()
        ..on(
          'GET',
          iosTokensUrl,
          buildTokenList(iosTokensUrl, <String>['$wizardDisplayName:a1']),
        )
        ..on('GET', androidTokensUrl, buildTokenList(androidTokensUrl, []))
        ..on('GET', androidTokensUrl, buildTokenList(androidTokensUrl, []))
        ..on(
          'GET',
          androidTokensUrl,
          buildTokenList(androidTokensUrl, <String>['$wizardDisplayName:b1']),
        )
        ..on('POST', androidTokensUrl, const RestResponse(200, '{}'));
      final terminal = ScriptedTerminal(const <String?>['y']);
      final session = WizardSession();

      final int code = await runAppCheckStep(rest, terminal, session: session);

      expect(code, wizardExitDone);
      expect(readToken(), token);
      // 빠진 앱에 등록만 해도 새 빌드가 필요하다는 신호를 남긴다.
      expect(session.hasRegisteredAppCheckToken, isTrue);
      expect(rest.countRequests('POST', androidTokensUrl), 1);
      expect(rest.countRequests('POST', iosTokensUrl), 0);
      expect(listRequests(rest, 'DELETE'), isEmpty);
      final List<RestRequest> iosRequests = rest.requests
          .where(
            (RestRequest request) => request.url.toString() == iosTokensUrl,
          )
          .toList();
      expect(iosRequests, isNotEmpty);
      expect(
        iosRequests.every((RestRequest request) => request.method == 'GET'),
        isTrue,
      );
      expect(
        jsonDecode(listRequests(rest, 'POST').single.body!),
        <String, Object?>{'displayName': wizardDisplayName, 'token': token},
      );
    },
  );

  test('T-19-APPCHECK-05 POST 400(한도) 면 실패 · 상태 코드 · 응답 원문', () async {
    writeAppFiles();
    const limitBody =
        '{"error":{"code":400,"message":"An app can have at most 20 debug tokens.","status":"FAILED_PRECONDITION"}}';
    final rest = FakeRestClient()
      ..on('GET', iosTokensUrl, buildTokenList(iosTokensUrl, []))
      ..on('GET', androidTokensUrl, buildTokenList(androidTokensUrl, []))
      ..on('POST', iosTokensUrl, const RestResponse(400, limitBody));
    final terminal = ScriptedTerminal(const <String?>['y']);
    final log = MemoryLogSink(Redactor());
    final session = WizardSession();

    final int code = await runAppCheckStep(
      rest,
      terminal,
      log: log,
      session: session,
    );

    final output = terminal.output.toString();
    final String token = readToken();
    expect(code, wizardExitStopped);
    expect(output, contains('  실패 — '));
    expect(output, contains('HTTP 400'));
    expect(output, contains(limitBody));
    expect(output, isNot(contains(token)));
    expect(log.text, isNot(contains(token)));
    // 등록이 실패했으면 다시 빌드 신호를 남기지 않는다.
    expect(session.hasRegisteredAppCheckToken, isFalse);
    expect(
      File('$root/${buildAppCheckPendingMarkerPath(Flavor.dev)}').existsSync(),
      isFalse,
    );
  });

  test(
    'T-19-APPCHECK-09 옛 항목 DELETE 가 403 이면 config 토큰은 빈 값 그대로 · 다시 시도의 재검사가 create 로 다시 지운 뒤 등록한다',
    () async {
      writeAppFiles();
      final rest = FakeRestClient()
        ..on(
          'GET',
          iosTokensUrl,
          buildTokenList(iosTokensUrl, <String>['$wizardDisplayName:old1']),
        )
        ..on(
          'GET',
          iosTokensUrl,
          buildTokenList(iosTokensUrl, <String>['$wizardDisplayName:old1']),
        )
        ..on(
          'GET',
          iosTokensUrl,
          buildTokenList(iosTokensUrl, <String>['$wizardDisplayName:new1']),
        )
        ..on('GET', androidTokensUrl, buildTokenList(androidTokensUrl, []))
        ..on(
          'GET',
          androidTokensUrl,
          buildTokenList(androidTokensUrl, <String>['$wizardDisplayName:new2']),
        )
        ..on('DELETE', '$iosTokensUrl/old1', const RestResponse(403, '{}'))
        ..on('DELETE', '$iosTokensUrl/old1', const RestResponse(200, '{}'))
        ..on('POST', iosTokensUrl, const RestResponse(200, '{}'))
        ..on('POST', androidTokensUrl, const RestResponse(200, '{}'));
      // y → DELETE 403 실패 → 1(다시 시도).
      final terminal = ScriptedTerminal(const <String?>['y', '1']);
      final log = MemoryLogSink(Redactor());

      final int code = await runAppCheckStep(rest, terminal, log: log);

      final output = terminal.output.toString();
      final int firstPostAt = rest.requests.indexWhere(
        (RestRequest request) => request.method == 'POST',
      );
      final List<String> createChecks = log.text
          .split('\n')
          .where(
            (String line) =>
                line.contains('app_check ✗') && line.contains('디버그 토큰이 없습니다'),
          )
          .toList();
      expect(code, wizardExitDone);
      expect(output, contains('HTTP 403'));
      // 실패 전에는 POST 가 없고, 첫 POST 앞에 DELETE 가 두 번(실패 · 성공) 있다.
      expect(rest.countRequests('DELETE', '$iosTokensUrl/old1'), 2);
      expect(firstPostAt, greaterThan(0));
      expect(
        rest.requests
            .take(firstPostAt)
            .where((RestRequest request) => request.method == 'DELETE'),
        hasLength(2),
      );
      // 점검표 · 단계 진입 · 다시 시도의 재검사 세 번 모두 config 토큰이 없다는
      // create 판정이다 — 실패 뒤에도 config 에 새 토큰이 쓰이지 않았다.
      expect(createChecks, hasLength(3));
      final String token = readToken();
      expect(isUuidV4(token), isTrue);
      expect(
        listRequests(
          rest,
          'POST',
        ).map((RestRequest request) => jsonDecode(request.body!)),
        everyElement(<String, Object?>{
          'displayName': wizardDisplayName,
          'token': token,
        }),
      );
      expect(output, contains('  ✓ ${AppCheckStep.stepTitle} — '));
    },
  );

  test('T-19-APPCHECK-06 앱 등록 파일이 없으면 ✗ 사유 · 적용하지 않고 실패 · 요청 0', () async {
    final rest = FakeRestClient();
    final terminal = ScriptedTerminal(const <String?>['y']);

    final int code = await runAppCheckStep(rest, terminal);

    final output = terminal.output.toString();
    final String reason = output
        .split('\n')
        .firstWhere(
          (String line) => line.startsWith('  ✗ ${AppCheckStep.stepTitle} — '),
        );
    expect(code, wizardExitStopped);
    expect(reason, contains('앱 등록'));
    expect(output, contains('  실패 — '));
    expect(rest.requests, isEmpty);
    expect(readToken(), '');
  });

  test(
    'T-19-APPCHECK-07 토큰은 context.random 으로만 만든다 — 같은 씨앗이면 같은 값 · 외부 명령 0',
    () async {
      writeAppFiles();
      final rest = FakeRestClient()
        ..on('GET', iosTokensUrl, buildTokenList(iosTokensUrl, []))
        ..on('GET', androidTokensUrl, buildTokenList(androidTokensUrl, []))
        ..on('POST', iosTokensUrl, const RestResponse(200, '{}'))
        ..on('POST', androidTokensUrl, const RestResponse(200, '{}'));
      final runner = FakeCommandRunner();

      await runAppCheckStep(
        rest,
        ScriptedTerminal(const <String?>['y']),
        runner: runner,
        random: Random(42),
      );

      expect(readToken(), generateUuidV4(Random(42)));
      expect(runner.calls, isEmpty);
    },
  );

  test(
    'T-19-APPCHECK-08 Dart 설정 파일이 실제 생성본 모양(예외 throw 5곳)이면 두 앱 ID 를 읽어 ✓ · POST 0 · 화면 · 기록에 앱 ID 0',
    () async {
      writeAppFiles();
      final String written = File(
        '$root/${FirebaseAppFiles.optionsPath}',
      ).readAsStringSync();
      expect('throw UnsupportedError('.allMatches(written), hasLength(5));
      replaceJsonString(
        config.path,
        AppCheckStep.tokenKey,
        generateUuidV4(Random(8)),
      );
      final rest = FakeRestClient()
        ..on(
          'GET',
          iosTokensUrl,
          buildTokenList(iosTokensUrl, <String>['$wizardDisplayName:a1']),
        )
        ..on(
          'GET',
          androidTokensUrl,
          buildTokenList(androidTokensUrl, <String>['$wizardDisplayName:b1']),
        );
      final terminal = ScriptedTerminal(const <String?>[]);
      final log = MemoryLogSink(Redactor());

      final int code = await runAppCheckStep(rest, terminal, log: log);

      final output = terminal.output.toString();
      expect(code, wizardExitDone);
      expect(output, contains('  ✓ ${AppCheckStep.stepTitle} — '));
      expect(
        rest.requests
            .map((RestRequest request) => request.url.toString())
            .toSet(),
        <String>{iosTokensUrl, androidTokensUrl},
      );
      expect(listRequests(rest, 'POST'), isEmpty);
      for (final appId in <String>[iosAppId, androidAppId]) {
        expect(output, isNot(contains(appId)));
        expect(log.text, isNot(contains(appId)));
      }
    },
  );

  test('buildDevSteps 는 rules 다음에 App Check 단계를 둔다', () {
    final List<String> ids = buildDevSteps()
        .map((Step step) => step.id)
        .toList();

    expect(ids.indexOf('app_check'), ids.indexOf('rules') + 1);
  });

  test(
    'T-20-STG-05: stg · 토큰 없음 → config/stg.json 에 UUID · stg 두 앱에 setup-wizard-stg 생성 2개 · 표시형만 · 토큰 0회 · dev config 바이트 같음',
    () async {
      writeAppFiles();
      replaceJsonString(
        config.path,
        AppCheckStep.tokenKey,
        generateUuidV4(Random(3)),
      );
      final List<int> devBefore = config.readAsBytesSync();
      final File stgConfig = writeStgFixture();
      final rest = FakeRestClient()
        ..on(
          'GET',
          stgIosTokensUrl,
          buildTokenList(stgIosTokensUrl, <String>[
            '$wizardDisplayName:devold',
          ]),
        )
        ..on(
          'GET',
          stgIosTokensUrl,
          buildTokenList(stgIosTokensUrl, <String>[
            '$wizardDisplayName:devold',
            '$stgDisplayName:new1',
          ]),
        )
        ..on(
          'GET',
          stgAndroidTokensUrl,
          buildTokenList(stgAndroidTokensUrl, []),
        )
        ..on(
          'GET',
          stgAndroidTokensUrl,
          buildTokenList(stgAndroidTokensUrl, <String>['$stgDisplayName:new2']),
        )
        ..on('POST', stgIosTokensUrl, const RestResponse(200, '{}'))
        ..on('POST', stgAndroidTokensUrl, const RestResponse(200, '{}'));
      final terminal = ScriptedTerminal(const <String?>['y']);
      final log = MemoryLogSink(Redactor());

      final int code = await runStgAppCheckStep(rest, terminal, log: log);

      final output = terminal.output.toString();
      final String token =
          readJsonString(stgConfig.path, AppCheckStep.tokenKey) ?? '';
      expect(code, wizardExitDone);
      expect(isUuidV4(token), isTrue);
      expect(config.readAsBytesSync(), devBefore);
      final List<RestRequest> posts = listRequests(rest, 'POST');
      expect(
        posts.map((RestRequest request) => request.url.toString()).toSet(),
        <String>{stgIosTokensUrl, stgAndroidTokensUrl},
      );
      expect(posts, hasLength(2));
      for (final post in posts) {
        expect(jsonDecode(post.body!), <String, Object?>{
          'displayName': stgDisplayName,
          'token': token,
        });
        expect(jsonDecode(post.bodyDisplay!), <String, Object?>{
          'displayName': stgDisplayName,
          'token': stgTokenDisplay,
        });
        expect(post.quotaProject, stgProjectId);
      }
      // dev 이름의 항목은 stg 판정 · 삭제 대상이 아니다.
      expect(listRequests(rest, 'DELETE'), isEmpty);
      expect(output, contains('"token":"$stgTokenDisplay"'));
      expect(output, contains('($stgDisplayName)'));
      for (final text in <String>[output, log.text]) {
        expect(text, isNot(contains(token)));
        expect(text, isNot(contains(token.toUpperCase())));
      }
      for (final RestRequest request in rest.requests) {
        expect(request.url.toString(), contains('/projects/$stgProjectId/'));
        expect(
          request.url.toString(),
          isNot(contains('/projects/$projectId/')),
        );
      }
    },
  );

  group('T-20-STG-06: stg 판정은 setup-wizard-stg 항목만 본다', () {
    late File stgConfig;
    late String token;

    setUp(() {
      writeAppFiles();
      stgConfig = writeStgFixture();
      token = generateUuidV4(Random(9));
      replaceJsonString(stgConfig.path, AppCheckStep.tokenKey, token);
    });

    test('두 stg 앱에 setup-wizard-stg 가 있고 config 토큰도 있으면 ✓ · 쓰기 0', () async {
      final List<int> stgBefore = stgConfig.readAsBytesSync();
      final rest = FakeRestClient()
        ..on(
          'GET',
          stgIosTokensUrl,
          buildTokenList(stgIosTokensUrl, <String>['$stgDisplayName:a1']),
        )
        ..on(
          'GET',
          stgAndroidTokensUrl,
          buildTokenList(stgAndroidTokensUrl, <String>[
            '$wizardDisplayName:d1',
            '$stgDisplayName:b1',
          ]),
        );
      final terminal = ScriptedTerminal(const <String?>[]);

      final int code = await runStgAppCheckStep(rest, terminal);

      final output = terminal.output.toString();
      expect(code, wizardExitDone);
      expect(output, contains('  ✓ ${AppCheckStep.stepTitle} — '));
      expect(output, contains('($stgDisplayName)'));
      expect(terminal.asks, isEmpty);
      expect(listRequests(rest, 'POST'), isEmpty);
      expect(listRequests(rest, 'DELETE'), isEmpty);
      expect(stgConfig.readAsBytesSync(), stgBefore);
    });

    test(
      'iOS 앱에 setup-wizard-dev 항목만 있으면 미등록으로 보고 iOS 에만 stg 이름으로 등록',
      () async {
        final rest = FakeRestClient()
          ..on(
            'GET',
            stgIosTokensUrl,
            buildTokenList(stgIosTokensUrl, <String>['$wizardDisplayName:d1']),
          )
          ..on(
            'GET',
            stgIosTokensUrl,
            buildTokenList(stgIosTokensUrl, <String>['$wizardDisplayName:d1']),
          )
          ..on(
            'GET',
            stgIosTokensUrl,
            buildTokenList(stgIosTokensUrl, <String>[
              '$wizardDisplayName:d1',
              '$stgDisplayName:n1',
            ]),
          )
          ..on(
            'GET',
            stgAndroidTokensUrl,
            buildTokenList(stgAndroidTokensUrl, <String>['$stgDisplayName:b1']),
          )
          ..on('POST', stgIosTokensUrl, const RestResponse(200, '{}'));
        final terminal = ScriptedTerminal(const <String?>['y']);

        final int code = await runStgAppCheckStep(rest, terminal);

        expect(code, wizardExitDone);
        expect(rest.countRequests('POST', stgIosTokensUrl), 1);
        expect(rest.countRequests('POST', stgAndroidTokensUrl), 0);
        expect(listRequests(rest, 'DELETE'), isEmpty);
        expect(
          jsonDecode(listRequests(rest, 'POST').single.body!),
          <String, Object?>{'displayName': stgDisplayName, 'token': token},
        );
      },
    );
  });

  group('T-21-RUN-13: App Check 적용이 그 flavor 의 빌드 대기 표지를 쓴다', () {
    test('T-21-RUN-13: dev 토큰을 새로 만들어 등록하면 dev 대기 표지 · 0600 · '
        '디렉터리 0700 · stg 표지 없음', () async {
      writeAppFiles();
      final int code = await runAppCheckStep(
        buildCreateFlowRest(),
        ScriptedTerminal(const <String?>['y']),
      );

      expect(code, wizardExitDone);
      final pending = File(
        '$root/${buildAppCheckPendingMarkerPath(Flavor.dev)}',
      );
      expect(pending.existsSync(), isTrue);
      expect(pending.readAsStringSync(), isEmpty);
      expect(FileStat.statSync(pending.path).modeString(), 'rw-------');
      expect(
        FileStat.statSync('$root/$rebuildMarkerDirectory').modeString(),
        'rwx------',
      );
      expect(
        File(
          '$root/${buildAppCheckPendingMarkerPath(Flavor.stg)}',
        ).existsSync(),
        isFalse,
      );
    });

    test('T-21-RUN-13: stg 의 빠진 앱에 등록하면 stg 대기 표지만', () async {
      writeAppFiles();
      final File stgConfig = writeStgFixture();
      replaceJsonString(
        stgConfig.path,
        AppCheckStep.tokenKey,
        generateUuidV4(Random(5)),
      );
      final rest = FakeRestClient()
        ..on(
          'GET',
          stgIosTokensUrl,
          buildTokenList(stgIosTokensUrl, <String>['$stgDisplayName:i1']),
        )
        ..on(
          'GET',
          stgAndroidTokensUrl,
          buildTokenList(stgAndroidTokensUrl, []),
        )
        ..on(
          'GET',
          stgAndroidTokensUrl,
          buildTokenList(stgAndroidTokensUrl, []),
        )
        ..on(
          'GET',
          stgAndroidTokensUrl,
          buildTokenList(stgAndroidTokensUrl, <String>['$stgDisplayName:a1']),
        )
        ..on('POST', stgAndroidTokensUrl, const RestResponse(200, '{}'));

      final int code = await runStgAppCheckStep(
        rest,
        ScriptedTerminal(const <String?>['y']),
      );

      expect(code, wizardExitDone);
      expect(rest.countRequests('POST', stgAndroidTokensUrl), 1);
      expect(
        File(
          '$root/${buildAppCheckPendingMarkerPath(Flavor.stg)}',
        ).existsSync(),
        isTrue,
      );
      expect(
        File(
          '$root/${buildAppCheckPendingMarkerPath(Flavor.dev)}',
        ).existsSync(),
        isFalse,
      );
    });
  });

  test('T-21-RUN-14: G-21-6 — 실행 N 에서 토큰을 등록하고 배포 실패로 멈춘 뒤 새 '
      '세션의 실행 N+1 이 사용자가 있어도 다시 빌드 1회 · ✓ · 종료 0', () async {
    writeAppFiles();
    final batchGetUrl = RunStep.buildBatchGetRequest(projectId).url.toString();

    // 실행 N — App Check 진행 y → 배포 진행 y → 실패 뒤 멈춤.
    final restN = buildCreateFlowRest()
      ..on('GET', batchGetUrl, buildVerifiedUsersPage(1));
    final runnerN = FakeCommandRunner();
    final terminalN = ScriptedTerminal(const <String?>['y', 'y', '2']);
    final logN = MemoryLogSink(Redactor());
    final int codeN = await runSetupWizard(
      buildTestContext(
        projectRoot: root,
        runner: runnerN,
        terminal: terminalN,
        log: logN,
        rest: restN,
      ),
      <Step>[
        _FinishedStep('configure', '앱 등록 · 설정 파일'),
        _FinishedStep('apis', '필요한 Google Cloud API'),
        AppCheckStep(),
        _FailingStep('functions', 'Cloud Functions 배포'),
        _FinishedStep('sign_in', '로그인 수단 (이메일 · 익명)'),
        _FinishedStep('rules', 'Firestore · Storage rules'),
        RunStep(delay: (Duration duration) async {}),
      ],
    );
    final outputN = terminalN.output.toString();
    expect(codeN, wizardExitStopped, reason: outputN);
    expect(outputN, contains(AppCheckStep.rebuildNotice));
    expect(runnerN.countMode(RunMode.interactive), 0);
    final String token = readToken();
    expect(isUuidV4(token), isTrue);
    final pending = File('$root/${buildAppCheckPendingMarkerPath(Flavor.dev)}');
    expect(pending.existsSync(), isTrue);

    // 실행 N+1 — 새 세션 · 새 단계 객체. App Check 는 이미 끝남, 배포는 이번엔 끝남.
    final restN1 = FakeRestClient()
      ..on(
        'GET',
        iosTokensUrl,
        buildTokenList(iosTokensUrl, <String>['$wizardDisplayName:new1']),
      )
      ..on(
        'GET',
        androidTokensUrl,
        buildTokenList(androidTokensUrl, <String>['$wizardDisplayName:new2']),
      )
      ..on('GET', batchGetUrl, buildVerifiedUsersPage(1));
    final runnerN1 = FakeCommandRunner();
    registerRunCommands(runnerN1);
    // 실행 단계 진행 y → 기기 고르기 기본값.
    final terminalN1 = ScriptedTerminal(const <String?>['y', '']);
    final logN1 = MemoryLogSink(Redactor());
    final WizardContext contextN1 = buildTestContext(
      projectRoot: root,
      runner: runnerN1,
      terminal: terminalN1,
      log: logN1,
      rest: restN1,
    );
    final int codeN1 = await runSetupWizard(contextN1, <Step>[
      _FinishedStep('configure', '앱 등록 · 설정 파일'),
      _FinishedStep('apis', '필요한 Google Cloud API'),
      AppCheckStep(),
      _FinishedStep('functions', 'Cloud Functions 배포'),
      _FinishedStep('sign_in', '로그인 수단 (이메일 · 익명)'),
      _FinishedStep('rules', 'Firestore · Storage rules'),
      RunStep(delay: (Duration duration) async {}),
    ]);

    final outputN1 = terminalN1.output.toString();
    expect(codeN1, wizardExitDone, reason: outputN1);
    expect(contextN1.session.hasRegisteredAppCheckToken, isFalse);
    expect(outputN1, contains('  ✓ ${AppCheckStep.stepTitle} — '));
    expect(
      outputN1,
      contains(
        '▶ ${RunStep.stepTitle}\n'
        '  ${RunStep.rebuildReasonPrefix}'
        '${RunStep.pendingAppCheckTokenReason}\n',
      ),
    );
    expect(listRequests(restN1, 'POST'), isEmpty);
    final streamKeys = <String>[
      for (final FakeCall call in runnerN1.calls)
        if (call.mode == RunMode.stream) call.key,
    ];
    expect(streamKeys, <String>[
      'fvm flutter pub get',
      'fvm dart run build_runner build --delete-conflicting-outputs',
    ]);
    expect(runnerN1.countMode(RunMode.interactive), 1);
    expect(outputN1, contains('  ✓ 앱 실행 · 로그인 확인 — 인증된 이메일 사용자 1명'));
    expect(pending.existsSync(), isFalse);
    final String hash = File(
      '$root/${buildLastLaunchMarkerPath(Flavor.dev)}',
    ).readAsStringSync().trim();
    expect(hash, computeBuildInputsHash(readBuildInputDigests(contextN1)));

    // 두 실행의 화면 · 기록에 토큰 · 합성 해시 0(양성 대조: 토큰은 config 에 있다).
    for (final text in <String>[outputN, logN.text, outputN1, logN1.text]) {
      expect(text, isNot(contains(token)));
      expect(text, isNot(contains(hash)));
      expect(RegExp('[0-9a-f]{64}').hasMatch(text), isFalse);
    }
  });
}
