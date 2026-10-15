import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:test/test.dart';

import '../../../bin/rename.dart' as rename;
import '../../../tool/setup/command_runner.dart';
import '../../../tool/setup/completion.dart';
import '../../../tool/setup/firebase_app_files.dart';
import '../../../tool/setup/git_tree.dart';
import '../../../tool/setup/redactor.dart';
import '../../../tool/setup/rest_client.dart';
import '../../../tool/setup/step.dart';
import '../../../tool/setup/steps/apis_step.dart';
import '../../../tool/setup/steps/app_check_step.dart';
import '../../../tool/setup/steps/billing_step.dart';
import '../../../tool/setup/steps/configure_step.dart';
import '../../../tool/setup/steps/dev_steps.dart';
import '../../../tool/setup/steps/firebase_project_step.dart';
import '../../../tool/setup/steps/firestore_step.dart';
import '../../../tool/setup/steps/functions_step.dart';
import '../../../tool/setup/steps/identity_step.dart';
import '../../../tool/setup/steps/login_step.dart';
import '../../../tool/setup/steps/rules_step.dart';
import '../../../tool/setup/steps/run_step.dart';
import '../../../tool/setup/steps/sign_in_step.dart';
import '../../../tool/setup/steps/storage_step.dart';
import '../../../tool/setup/steps/user_files_step.dart';
import '../../../tool/setup/terminal.dart';
import '../../../tool/setup/wizard.dart';
import 'fake_rest_client.dart';
import 'fakes.dart';
import 'firebase_options_fixture.dart';

/// 흐름 fixture 의 프로젝트 ID(가짜).
const String projectId = 'my-app-dev';

/// 흐름 fixture 의 Functions 리전 — example config 의 값 그대로.
const String region = 'asia-northeast3';

/// 흐름 fixture 의 org · name (앱 정체성 단계가 쓰는 값).
const String org = 'com.acme';

/// 흐름 fixture 의 name.
const String name = 'my_app';

/// 흐름 fixture 의 Android 앱 ID.
const String applicationId = '$org.$name';

/// 흐름 fixture 의 dev iOS 번들 ID.
const String devBundleId = '$org.myApp.dev';

/// 흐름 fixture 의 표시 이름.
const String displayName = 'My App Dev';

/// 가짜 iOS Firebase 앱 ID.
const String iosAppId = '1:111111111111:ios:aaaaaaaaaaaaaaaa';

/// 가짜 Android Firebase 앱 ID.
const String androidAppId = '1:111111111111:android:bbbbbbbbbbbbbbbb';

/// 가짜 App Check 디버그 토큰(UUID4 · config 값).
const String debugToken = '6f1c2b3a-4d5e-4f60-8a7b-9c0d1e2f3a4b';

/// 가짜 로그인 계정.
const String accountEmail = 'kit-dev@example.invalid';

/// 공통 함수 목록(가짜 manifest).
const List<String> commonFunctions = <String>['ping', 'echo'];

/// 선언된 secret 이름(가짜 functions 소스).
const String declaredSecret = 'KIT_SAMPLE_SECRET';

/// 끝 요약 git 상태 명령 키.
const String gitStatusKey = 'git status --porcelain --untracked-files=no';

/// 새 Kotlin 패키지 디렉터리(앱 정체성이 옮긴 곳).
const String newKotlinDir = 'android/app/src/main/kotlin/com/acme/my_app';

/// 새 Kotlin 디렉터리의 untracked 질의 키.
const String untrackedKey =
    'git status --porcelain --untracked-files=all -- $newKotlinDir';

/// 가짜 Firestore rules 원문.
const String firestoreRules =
    "rules_version = '2';\nservice cloud.firestore {}\n";

/// 가짜 Storage rules 원문.
const String storageRules =
    "rules_version = '2';\nservice firebase.storage {}\n";

/// 실행 시점에 조립하는 가짜 액세스 토큰 — 리터럴로 두지 않는다.
String buildFakeAccessToken() => 'ya29.${'A' * 40}';

/// 실행 시점에 조립하는 가짜 API 키 — 리터럴로 두지 않는다.
String buildFakeApiKey() => 'AIza${'x' * 35}';

/// 실행 기록 · 화면에 실제 실행기처럼 쓰는 실행기 — 결과는 가짜 실행기가 준다.
///
/// 캡처 실행은 `[cmd]` · `[exit]` · 출력(민감 출력이면 생략 표시)을, 흘리는
/// 실행은 명령 줄과 출력을 화면에 쓴다. 실제 프로세스는 띄우지 않는다.
final class _LoggingRunner implements CommandRunner {
  _LoggingRunner(this.inner, this.terminal, this.log);

  final FakeCommandRunner inner;
  final Terminal terminal;
  final MemoryLogSink log;

  @override
  Future<CommandResult> capture(Command command) async {
    log.write('cmd', command.render());
    final CommandResult result = await inner.capture(command);
    log.write('exit', '${result.exitCode}');
    for (final MapEntry<String, String> entry in <String, String>{
      'stdout': result.stdout,
      'stderr': result.stderr,
    }.entries) {
      if (entry.value.isEmpty) continue;
      log.write(
        entry.key,
        command.isOutputSensitive
            ? ProcessCommandRunner.sensitiveOutputNotice
            : entry.value,
      );
    }
    return result;
  }

  @override
  Future<int> interactive(Command command) async {
    terminal.writeCommand(command.render());
    log.write('cmd', command.render());
    final int code = await inner.interactive(command);
    log.write('exit', '$code');
    return code;
  }

  @override
  Future<CommandResult> stream(Command command) async {
    terminal.writeCommand(command.render());
    log.write('cmd', command.render());
    final CommandResult result = await inner.stream(command);
    for (final String text in <String>[result.stdout, result.stderr]) {
      if (text.isEmpty) continue;
      terminal.writeRaw(text.endsWith('\n') ? text : '$text\n');
    }
    log.write('exit', '${result.exitCode}');
    return result;
  }
}

/// 실행 기록에 실제 REST 실행기처럼 요청 · 응답을 남기는 REST 실행기.
final class _LoggingRest implements RestClient {
  _LoggingRest(this.inner, this.log);

  final FakeRestClient inner;
  final MemoryLogSink log;

  @override
  Future<RestResponse> send(RestRequest request) async {
    final RestResponse response = await inner.send(request);
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

/// 흐름 한 번에 쓰는 가짜 실행기 · REST · 화면 · 기록 묶음.
final class _Harness {
  _Harness(this.root, List<String?> inputs)
    : runner = FakeCommandRunner(),
      rest = FakeRestClient(),
      screen = ScriptedTerminal(inputs),
      log = MemoryLogSink(Redactor()) {
    terminal = RedactingTerminal(screen, log.redactor, log);
    context = WizardContext(
      projectRoot: root,
      runner: _LoggingRunner(runner, terminal, log),
      terminal: terminal,
      redactor: log.redactor,
      log: log,
      rest: _LoggingRest(rest, log),
      random: Random(fixedTestRandomSeed),
      now: () => fixedTestNow,
    );
  }

  final String root;
  final FakeCommandRunner runner;
  final FakeRestClient rest;
  final ScriptedTerminal screen;
  final MemoryLogSink log;
  late final RedactingTerminal terminal;
  late final WizardContext context;

  /// 화면 출력 전체.
  String get output => screen.output.toString();

  /// [key] 명령의 결과 큐에 [result] 를 더한다.
  void on(String key, CommandResult result) => runner.on(key, result);

  /// [command] 의 결과 큐에 [result] 를 더한다.
  void onCommand(Command command, CommandResult result) =>
      runner.on(FakeCommandRunner.buildKey(command), result);

  /// [request] 의 응답 큐에 [response] 를 더한다.
  void onRest(RestRequest request, RestResponse response) =>
      rest.on(request.method, request.url.toString(), response);

  /// 16단계 목록으로 위저드를 돌린다.
  Future<int> run({Future<void> Function(WizardContext)? onCompleted}) =>
      runWizard(context, buildDevSteps(), onCompleted: onCompleted);

  /// 화면에서 진행 질문 수를 센다.
  int countStepQuestions() => screen.asks
      .where((String question) => question == stepConfirmQuestion)
      .length;
}

/// 성공 결과.
CommandResult ok([String stdout = '']) => CommandResult(0, stdout, '');

/// 저장소 상대 경로에 내용을 쓴다(부모 디렉터리를 만든다).
void writeFixture(String root, String relativePath, String content) {
  File('$root/$relativePath')
    ..parent.createSync(recursive: true)
    ..writeAsStringSync(content);
}

/// 모든 단계가 끝난 저장소 모양을 [root] 에 만든다.
///
/// 킷의 추적 example 두 개만 저장소에서 읽고, 나머지는 가짜 값으로 쓴다.
void writeFinishedFixture(String root) {
  final String jsonExample = File(
    UserFilesStep.jsonExamplePath,
  ).readAsStringSync();
  final String xcconfigExample = File(
    UserFilesStep.xcconfigExamplePath,
  ).readAsStringSync();
  writeFixture(root, UserFilesStep.jsonExamplePath, jsonExample);
  writeFixture(root, UserFilesStep.xcconfigExamplePath, xcconfigExample);

  final Map<String, Object?> config =
      jsonDecode(jsonExample)! as Map<String, Object?>;
  config
    ..[FirebaseProjectStep.projectIdKey] = projectId
    ..['appName'] = displayName
    ..[AppCheckStep.tokenKey] = debugToken;
  writeFixture(
    root,
    UserFilesStep.jsonUserPath,
    '${const JsonEncoder.withIndent('  ').convert(config)}\n',
  );
  writeFixture(
    root,
    UserFilesStep.xcconfigUserPath,
    xcconfigExample
        .replaceFirst(
          RegExp('PRODUCT_BUNDLE_IDENTIFIER = .*'),
          'PRODUCT_BUNDLE_IDENTIFIER = $devBundleId',
        )
        .replaceFirst(
          RegExp('DISPLAY_NAME = .*'),
          'DISPLAY_NAME = $displayName',
        ),
  );

  writeFixture(
    root,
    IdentityStep.gradlePath,
    'android {\n'
    '    defaultConfig {\n'
    '        applicationId = "$applicationId"\n'
    '    }\n'
    '    productFlavors {\n'
    '        create("dev") { applicationIdSuffix = ".dev" }\n'
    '    }\n'
    '}\n',
  );
  writeFixture(
    root,
    '$newKotlinDir/MainActivity.kt',
    'package $applicationId\n\nclass MainActivity\n',
  );
  writeFixture(
    root,
    FirebaseProjectStep.firebasercPath,
    '${jsonEncode(<String, Object?>{
      'projects': <String, String>{'default': projectId, 'dev': projectId},
    })}\n',
  );
  writeFixture(
    root,
    FirestoreStep.regionTsPath,
    'export const REGION = "$region";\n',
  );
  writeFixture(
    root,
    FirestoreStep.appConfigPath,
    'abstract final class AppConfig {\n'
    "  static const String defaultFunctionsRegion = '$region';\n"
    '}\n',
  );
  writeFinishedFirebaseFiles(root);
  writeFixture(root, RulesStep.firestoreRulesPath, firestoreRules);
  writeFixture(root, RulesStep.storageRulesPath, storageRules);
  writeFixture(
    root,
    FunctionsStep.manifestPath,
    '${jsonEncode(<String, Object?>{'common': commonFunctions})}\n',
  );
  writeFixture(
    root,
    'functions/src/index.ts',
    'const kitSecret = defineSecret("$declaredSecret");\n',
  );
  writeFixture(root, FunctionsStep.modulesMarkerPath, '');
}

/// configure 스크립트가 만든 모양의 설정 파일 3개를 쓴다(가짜 키는 실행 시점 조립).
void writeFinishedFirebaseFiles(String root) {
  final String apiKey = buildFakeApiKey();
  writeFixture(
    root,
    FirebaseAppFiles.optionsPath,
    buildGeneratedOptionsSource(
      projectId: projectId,
      apiKey: apiKey,
      androidAppId: androidAppId,
      iosAppId: iosAppId,
      iosBundleId: devBundleId,
    ),
  );
  writeFixture(
    root,
    FirebaseAppFiles.iosPlistPath,
    '<plist><dict>\n'
    '<key>API_KEY</key>\n<string>$apiKey</string>\n'
    '<key>PROJECT_ID</key>\n<string>$projectId</string>\n'
    '<key>BUNDLE_ID</key>\n<string>$devBundleId</string>\n'
    '<key>GOOGLE_APP_ID</key>\n<string>$iosAppId</string>\n'
    '</dict></plist>\n',
  );
  writeFixture(
    root,
    FirebaseAppFiles.androidJsonPath,
    jsonEncode(<String, Object?>{
      'project_info': <String, Object?>{'project_id': projectId},
      'client': <Object?>[
        <String, Object?>{
          'client_info': <String, Object?>{
            'mobilesdk_app_id': androidAppId,
            'android_client_info': <String, Object?>{
              'package_name': '$applicationId$devPackageSuffix',
            },
          },
          'api_key': <Object?>[
            <String, Object?>{'current_key': apiKey},
          ],
        },
      ],
    }),
  );
}

/// 기본 bucket 응답 본문 — [echo] 가 있으면 본문에 섞는다(가림 확인용).
String buildBucketBody({String echo = ''}) => jsonEncode(<String, Object?>{
  'name': 'projects/$projectId/defaultBucket',
  'location': region,
  'bucket': <String, Object?>{
    'name': 'projects/$projectId/buckets/$projectId.firebasestorage.app',
  },
  if (echo.isNotEmpty) 'echo': echo,
});

/// 로그인 설정 응답 본문 — [isAnonymousEnabled] 가 false 면 익명만 꺼짐.
String buildSignInBody({bool isAnonymousEnabled = true}) =>
    jsonEncode(<String, Object?>{
      'signIn': <String, Object?>{
        'email': <String, Object?>{'enabled': true, 'passwordRequired': true},
        'anonymous': <String, Object?>{'enabled': isAnonymousEnabled},
      },
    });

/// 인증된 이메일 사용자 한 명이 있는 batchGet 응답 본문.
String buildVerifiedUsersBody() => jsonEncode(<String, Object?>{
  'users': <Object?>[
    <String, Object?>{
      'localId': 'uidFlowUser0001',
      'email': 'flow-user@example.invalid',
      'emailVerified': true,
      'providerUserInfo': <Object?>[
        <String, Object?>{'providerId': 'password'},
      ],
    },
  ],
});

/// Cloud Run 서비스 이름(함수 이름 그대로).
String buildServiceId(String function) => function;

/// 모든 단계의 「끝남」 응답을 등록한다.
///
/// [noise] 가 있으면 민감하지 않은 출력 몇 곳에 섞는다(가림 확인용).
void _registerFinished(_Harness h, {String noise = ''}) {
  final String token = buildFakeAccessToken();
  // 1. Xcode 준비
  h
    ..on('xcode-select -p', ok('/Applications/Xcode.app/Contents/Developer\n'))
    ..on('xcodebuild -license check', ok(noise))
    ..on('xcodebuild -checkFirstLaunchStatus', ok())
    ..on(
      'xcrun simctl list runtimes -j',
      ok(
        jsonEncode(<String, Object?>{
          'runtimes': <Object?>[
            <String, Object?>{
              'platform': 'iOS',
              'isAvailable': true,
              'note': noise,
            },
          ],
        }),
      ),
    )
    // 2. 개발 도구
    ..on('node --version', ok('v22.11.0\n'))
    ..on('pnpm --version', ok('10.4.1\n'))
    ..on('firebase --version', ok('15.29.0\n'))
    ..on('gcloud --version', ok('Google Cloud SDK 540.0.0\n'))
    ..on('jq --version', ok('jq-1.7.1\n'))
    ..on("ruby -e require 'xcodeproj'", ok())
    ..on('fvm dart pub global list', ok('flutterfire_cli 1.3.1\n'))
    // 5. 로그인
    ..onCommand(
      LoginStep.firebaseAccountsCommand,
      ok(
        jsonEncode(<String, Object?>{
          'status': 'success',
          'result': <Object?>[
            <String, Object?>{
              'user': <String, Object?>{'email': accountEmail},
            },
          ],
        }),
      ),
    )
    ..onCommand(AccessTokenSource.tokenCommand, ok('$token\n'))
    ..onCommand(LoginStep.gcloudAccountCommand, ok('$accountEmail\n'))
    // 6. 프로젝트
    ..onCommand(
      FirebaseProjectStep.projectsListCommand,
      ok(
        jsonEncode(<String, Object?>{
          'status': 'success',
          'result': <Object?>[
            <String, Object?>{
              'projectId': projectId,
              'displayName': projectId,
              'note': noise,
            },
          ],
        }),
      ),
    )
    // 7. 결제
    ..onCommand(
      BillingStep.billingInfoCommand(projectId),
      ok('{"billingEnabled":true}'),
    )
    // 8. API
    ..onCommand(
      ApisStep.buildEnabledListCommand(projectId),
      ok('${ApisStep.requiredServices.join('\n')}\n'),
    )
    // 9. Firestore
    ..onCommand(FirestoreStep.buildDescribeCommand(projectId), ok('$region\n'))
    // 12. 앱 등록
    ..onCommand(
      ConfigureStep.buildAppsListCommand(projectId),
      ok(
        jsonEncode(<String, Object?>{
          'status': 'success',
          'result': <Object?>[
            <String, Object?>{'appId': iosAppId, 'platform': 'IOS'},
            <String, Object?>{'appId': androidAppId, 'platform': 'ANDROID'},
          ],
        }),
      ),
    )
    // 15. Functions
    ..onCommand(
      FunctionsStep.buildSecretsListCommand(projectId),
      ok('projects/000000000000/secrets/$declaredSecret\n'),
    )
    ..onCommand(
      FunctionsStep.buildFunctionsListCommand(projectId),
      ok(
        jsonEncode(<String, Object?>{
          'status': 'success',
          'result': <Object?>[
            for (final String function in commonFunctions)
              <String, Object?>{
                'id': function,
                'region': region,
                'runServiceId': buildServiceId(function),
              },
          ],
        }),
      ),
    );
  for (final String function in commonFunctions) {
    h.onCommand(
      FunctionsStep.buildIamPolicyCommand(
        buildServiceId(function),
        region,
        projectId,
      ),
      ok(
        jsonEncode(<String, Object?>{
          'bindings': <Object?>[
            <String, Object?>{
              'role': FunctionsStep.invokerRole,
              'members': <String>[FunctionsStep.invokerMember],
            },
          ],
        }),
      ),
    );
  }

  // 10. Storage · 13. rules 의 bucket 이름
  h.onRest(
    StorageStep.buildGetRequest(projectId),
    RestResponse(200, buildBucketBody(echo: noise)),
  );
  // 11. 로그인 수단
  h.onRest(
    SignInStep.buildGetRequest(projectId),
    RestResponse(200, buildSignInBody()),
  );
  // 13. rules
  final String firestoreRuleset = 'projects/$projectId/rulesets/fs';
  final String storageRuleset = 'projects/$projectId/rulesets/st';
  h
    ..onRest(
      RulesStep.buildReleaseRequest(projectId, RulesStep.firestoreRelease),
      RestResponse(
        200,
        jsonEncode(<String, String>{'rulesetName': firestoreRuleset}),
      ),
    )
    ..onRest(
      RulesStep.buildReleaseRequest(
        projectId,
        '${RulesStep.storageReleasePrefix}/$projectId.firebasestorage.app',
      ),
      RestResponse(
        200,
        jsonEncode(<String, String>{'rulesetName': storageRuleset}),
      ),
    )
    ..onRest(
      RulesStep.buildRulesetRequest(projectId, firestoreRuleset),
      RestResponse(200, buildRulesetBody(firestoreRules)),
    )
    ..onRest(
      RulesStep.buildRulesetRequest(projectId, storageRuleset),
      RestResponse(200, buildRulesetBody(storageRules)),
    );
  // 14. App Check
  for (final String appId in <String>[iosAppId, androidAppId]) {
    h.onRest(
      AppCheckStep.buildListRequest(projectId, appId),
      RestResponse(
        200,
        jsonEncode(<String, Object?>{
          'debugTokens': <Object?>[
            <String, Object?>{
              'name': 'projects/$projectId/apps/$appId/debugTokens/t1',
              'displayName': AppCheckStep.displayName,
            },
          ],
        }),
      ),
    );
  }
  // 16. 앱 실행 · 로그인 확인
  h.onRest(
    RunStep.buildBatchGetRequest(projectId),
    RestResponse(200, buildVerifiedUsersBody()),
  );
}

/// ruleset 응답 본문.
String buildRulesetBody(String content) => jsonEncode(<String, Object?>{
  'source': <String, Object?>{
    'files': <Object?>[
      <String, Object?>{'name': 'rules', 'content': content},
    ],
  },
});

/// 쓰기 요청(POST · PATCH · DELETE) 수를 센다.
int countWriteRequests(FakeRestClient rest) => rest.requests
    .where(
      (RestRequest request) =>
          request.method == 'POST' ||
          request.method == 'PATCH' ||
          request.method == 'DELETE',
    )
    .length;

void main() {
  late Directory tempDir;
  late String root;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('wizard_flow_test_');
    root = tempDir.path;
    writeFinishedFixture(root);
  });

  tearDown(() {
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  test('T-19-FLOW-01: buildDevSteps() id 순서가 16단계 그대로다', () {
    expect(
      <String>[for (final Step step in buildDevSteps()) step.id],
      <String>[
        'xcode',
        'tools',
        'user_files',
        'identity',
        'login',
        'firebase_project',
        'billing',
        'apis',
        'firestore',
        'storage',
        'sign_in',
        'configure',
        'rules',
        'app_check',
        'functions',
        'run',
      ],
    );
  });

  test('T-19-FLOW-02: 모든 단계가 끝난 저장소 재실행 → ✓ 16줄 · 질문 · 쓰기 0', () async {
    final _Harness h = _Harness(root, const <String?>[]);
    _registerFinished(h);

    final int code = await h.run();

    expect(code, wizardExitDone);
    final List<String> lines = const LineSplitter().convert(h.output);
    expect(
      lines.where((String line) => line.startsWith('  ✓ ')),
      hasLength(16),
    );
    expect(lines.where((String line) => line.startsWith('  ✗ ')), isEmpty);
    expect(h.output, contains(allDoneLine));
    expect(h.countStepQuestions(), 0);
    expect(h.screen.asks, isEmpty);
    expect(h.runner.countMode(RunMode.interactive), 0);
    expect(h.runner.countMode(RunMode.stream), 0);
    expect(countWriteRequests(h.rest), 0);
  });

  test('T-19-FLOW-03: 익명 로그인만 꺼짐 → 그 단계 하나만 묻고 PATCH 1회', () async {
    final _Harness h = _Harness(root, const <String?>['y']);
    final RestResponse anonymousOff = RestResponse(
      200,
      buildSignInBody(isAnonymousEnabled: false),
    );
    // 「꺼짐」 두 번(점검표 · 단계 시작)을 _registerFinished 의 「켜짐」 앞에 둔다.
    h
      ..onRest(SignInStep.buildGetRequest(projectId), anonymousOff)
      ..onRest(SignInStep.buildGetRequest(projectId), anonymousOff);
    _registerFinished(h);
    h.onRest(
      SignInStep.buildPatchRequest(projectId),
      const RestResponse(200, '{}'),
    );

    final int code = await h.run();

    expect(code, wizardExitDone);
    final List<String> todoLines = <String>[
      for (final String line in const LineSplitter().convert(h.output))
        if (line.startsWith('  ✗ ')) line,
    ];
    expect(todoLines, hasLength(1));
    expect(todoLines.single, startsWith('  ✗ ${SignInStep.stepTitle}'));
    expect(h.countStepQuestions(), 1);
    expect(h.screen.asks, <String>[stepConfirmQuestion]);
    expect(
      h.rest.countRequests(
        'PATCH',
        SignInStep.buildPatchRequest(projectId).url.toString(),
      ),
      1,
    );
    expect(countWriteRequests(h.rest), 1);
    expect(h.runner.countMode(RunMode.stream), 0);
    expect(h.runner.countMode(RunMode.interactive), 0);
  });

  test('T-19-FLOW-04: 가짜 출력 · 응답의 토큰 · API 키 · 디버그 토큰이 화면 · 기록에 0', () async {
    final String token = buildFakeAccessToken();
    final String apiKey = buildFakeApiKey();
    final String noise = 'token=$token key=$apiKey debug=$debugToken';
    final _Harness h = _Harness(root, const <String?>[]);
    _registerFinished(h, noise: noise);

    final int code = await h.run();

    expect(code, wizardExitDone);
    for (final String text in <String>[h.output, h.log.text]) {
      expect(text, isNot(contains(token)));
      expect(text, isNot(contains(apiKey)));
      expect(text, isNot(contains(debugToken)));
      expect(text, isNot(contains(accountEmail)));
    }
    // 대조: 섞은 출력이 실제로 기록까지 갔고 가려졌다.
    expect(h.log.text, contains('token=${Redactor.mask}'));
    expect(h.log.text, contains('key=${Redactor.mask}'));
    expect(h.log.text, contains('debug=${Redactor.mask}'));
  });

  group('T-19-FLOW-05: 끝 요약(showCommitHint)', () {
    test('바뀐 추적 파일 두 개 → 경로 · git add 명령 줄 · git 쓰기 실행 0', () async {
      final _Harness h = _Harness(root, const <String?>[]);
      _registerFinished(h);
      h
        ..on(
          gitStatusKey,
          ok(' M .firebaserc\n M functions/src/shared/region.ts\n'),
        )
        ..on(untrackedKey, ok());

      final int code = await h.run(onCompleted: showCommitHint);

      expect(code, wizardExitDone);
      final String output = h.output;
      expect(output, contains(commitHintHeading));
      expect(output, contains('\n  .firebaserc\n'));
      expect(output, contains('\n  functions/src/shared/region.ts\n'));
      expect(
        output,
        contains(
          '  \$ git add .firebaserc functions/src/shared/region.ts '
          '&& git commit -m "$commitHintMessage"',
        ),
      );
      expect(
        output.indexOf(allDoneLine),
        lessThan(output.indexOf(commitHintHeading)),
      );
      final List<String> gitKeys = <String>[
        for (final FakeCall call in h.runner.calls)
          if (call.key.startsWith('git ')) call.key,
      ];
      expect(gitKeys, <String>[gitStatusKey, untrackedKey]);
      expect(
        h.runner.calls.where(
          (FakeCall call) =>
              call.key.startsWith('git add') ||
              call.key.startsWith('git commit'),
        ),
        isEmpty,
      );
    });

    test('변경 0 → 안내 절 0 · 종료 코드 0', () async {
      final _Harness h = _Harness(root, const <String?>[]);
      _registerFinished(h);
      h
        ..on(gitStatusKey, ok())
        ..on(untrackedKey, ok());

      expect(await h.run(onCompleted: showCommitHint), wizardExitDone);
      expect(h.output, isNot(contains(commitHintHeading)));
      expect(h.output, isNot(contains('git add')));
    });

    test(
      'Kotlin 패키지 이동 → 옛 경로 삭제 · 새 경로 untracked 가 목록과 git add 줄에 모두',
      () async {
        final String oldKotlinFile =
            'android/app/src/main/kotlin/'
            '${rename.currentOrg.replaceAll('.', '/')}/'
            '${rename.currentPackageName}/MainActivity.kt';
        const String newKotlinFile = '$newKotlinDir/MainActivity.kt';
        final _Harness h = _Harness(root, const <String?>[]);
        _registerFinished(h);
        h
          ..on(gitStatusKey, ok(' M .firebaserc\n D $oldKotlinFile\n'))
          ..on(untrackedKey, ok('?? $newKotlinFile\n'));

        expect(await h.run(onCompleted: showCommitHint), wizardExitDone);
        final String output = h.output;
        expect(output, contains('\n  $oldKotlinFile\n'));
        expect(output, contains('\n  $newKotlinFile\n'));
        final String addLine = const LineSplitter()
            .convert(output)
            .singleWhere((String line) => line.startsWith('  \$ git add '));
        expect(addLine, contains(oldKotlinFile));
        expect(addLine, contains(newKotlinFile));
        expect(addLine, contains('.firebaserc'));
      },
    );

    test('git 상태를 읽지 못하면 한 줄 안내 · 종료 코드 0 그대로', () async {
      final _Harness h = _Harness(root, const <String?>[]);
      _registerFinished(h);
      h.on(
        gitStatusKey,
        const CommandResult(128, '', 'fatal: not a git repository\n'),
      );

      expect(await h.run(onCompleted: showCommitHint), wizardExitDone);
      expect(h.output, contains(completionFailedPrefix));
      expect(h.output, isNot(contains(commitHintHeading)));
    });

    test('showCommitHint 단독 — git 실패는 GitTreeException', () async {
      final FakeCommandRunner runner = FakeCommandRunner()
        ..on(gitStatusKey, const CommandResult(1, '', 'boom\n'));
      final WizardContext context = buildTestContext(
        projectRoot: root,
        runner: runner,
      );
      await expectLater(
        showCommitHint(context),
        throwsA(isA<GitTreeException>()),
      );
    });
  });
}
