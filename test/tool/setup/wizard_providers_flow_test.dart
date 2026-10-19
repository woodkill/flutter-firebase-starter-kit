import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:test/test.dart';

import '../../../tool/setup/command_runner.dart';
import '../../../tool/setup/config_files.dart';
import '../../../tool/setup/firebase_app_files.dart';
import '../../../tool/setup/flavor.dart';
import '../../../tool/setup/providers/apple_key_input.dart';
import '../../../tool/setup/providers/fingerprints.dart';
import '../../../tool/setup/providers/idp_config.dart';
import '../../../tool/setup/providers/keyed_provider_step.dart';
import '../../../tool/setup/providers/provider_catalog.dart';
import '../../../tool/setup/providers/sign_in_counts.dart';
import '../../../tool/setup/redactor.dart';
import '../../../tool/setup/rest_client.dart';
import '../../../tool/setup/secret_store.dart';
import '../../../tool/setup/step.dart';
import '../../../tool/setup/steps/apis_step.dart';
import '../../../tool/setup/steps/apns_step.dart';
import '../../../tool/setup/steps/app_check_step.dart';
import '../../../tool/setup/steps/apple_android_step.dart';
import '../../../tool/setup/steps/billing_step.dart';
import '../../../tool/setup/steps/configure_step.dart';
import '../../../tool/setup/steps/device_check_step.dart';
import '../../../tool/setup/steps/facebook_step.dart';
import '../../../tool/setup/steps/firebase_project_step.dart';
import '../../../tool/setup/steps/firestore_step.dart';
import '../../../tool/setup/steps/flavor_steps.dart';
import '../../../tool/setup/steps/functions_step.dart';
import '../../../tool/setup/steps/google_step.dart';
import '../../../tool/setup/steps/identity_step.dart';
import '../../../tool/setup/steps/kakao_step.dart';
import '../../../tool/setup/steps/line_step.dart';
import '../../../tool/setup/steps/login_step.dart';
import '../../../tool/setup/steps/naver_step.dart';
import '../../../tool/setup/steps/play_integrity_step.dart';
import '../../../tool/setup/steps/provider_android_step.dart';
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
const String projectId = 'six-app-dev';

/// 흐름 fixture 의 Functions 리전 — example config 의 값 그대로.
const String region = 'asia-northeast3';

/// 흐름 fixture 의 Android applicationId.
const String applicationId = 'com.acme.six_app';

/// 흐름 fixture 의 dev iOS 번들 ID.
const String devBundleId = 'com.acme.sixApp.dev';

/// 흐름 fixture 의 표시 이름.
const String displayName = 'Six App Dev';

/// 가짜 iOS Firebase 앱 ID.
const String iosAppId = '1:444444444444:ios:aaaaaaaaaaaaaaaa';

/// 가짜 Android Firebase 앱 ID.
const String androidAppId = '1:444444444444:android:bbbbbbbbbbbbbbbb';

/// 가짜 App Check 디버그 토큰(UUID4 · config 값).
const String debugToken = '7a2b3c4d-5e6f-4a70-8b9c-0d1e2f3a4b5c';

/// 가짜 로그인 계정.
const String accountEmail = 'kit-six@example.invalid';

/// 켠 로그인 수단 여섯.
const String allProvidersCsv = 'google,apple,facebook,kakao,naver,line';

/// 공통 함수 목록(가짜 manifest).
const List<String> commonFunctions = <String>['ping', 'echo'];

/// 로그인 수단별 함수 목록(가짜 manifest).
const Map<String, List<String>> providerFunctions = <String, List<String>>{
  'google': <String>[],
  'apple': <String>[],
  'facebook': <String>[],
  'kakao': <String>['kakaoCustomToken'],
  'naver': <String>['naverCustomToken'],
  'line': <String>['lineCustomToken'],
};

/// 선언된 secret 이름(가짜 functions 소스).
const String declaredSecret = 'KIT_SAMPLE_SECRET';

/// 가짜 Firestore rules 원문.
const String firestoreRules =
    "rules_version = '2';\nservice cloud.firestore {}\n";

/// 가짜 Storage rules 원문.
const String storageRules =
    "rules_version = '2';\nservice firebase.storage {}\n";

/// 지문 없는 홈에서 SHA-256 등록만 남은 Play Integrity 줄.
const String playIntegrityDeferredLine =
    '  ✗ ${PlayIntegrityStep.stepTitle} — '
    '${PlayIntegrityStep.fingerprintDeferredReason}';

/// 배포 명령 키.
final String deployKey = FakeCommandRunner.buildKey(
  FunctionsStep.buildDeployCommand(),
);

/// 가짜 값 묶음 — 모두 실행 시점에 조립한다.
final class _Values {
  /// Facebook App ID(숫자 15자).
  final String facebookAppId = '1' * 15;

  /// Facebook Client Token(소문자 hex 32자).
  final String facebookClientToken = 'c' * 32;

  /// Facebook App Secret(hex 32자 · 비밀).
  final String facebookAppSecret = 'e' * 32;

  /// Kakao 네이티브 앱 키(소문자 hex 32자).
  final String kakaoNativeKey = 'a' * 32;

  /// Kakao 어드민 키(hex 32자 · 비밀).
  final String kakaoAdminKey = 'b' * 32;

  /// Naver Client ID.
  final String naverClientId = 'idN${'x' * 17}';

  /// Naver Client Secret(비밀).
  final String naverClientSecret = 'Q7' * 5;

  /// LINE Channel ID(숫자 10자).
  final String lineChannelId = '2' * 10;

  /// LINE Channel Secret(비밀).
  final String lineChannelSecret = 'Ls' * 16;

  /// Google Web client ID.
  final String googleClientId =
      '${'4' * 12}-${'g' * 32}.apps.googleusercontent.com';

  /// Google REVERSED_CLIENT_ID.
  final String googleReversedClientId =
      'com.googleusercontent.apps.${'4' * 12}-${'g' * 32}';

  /// Google 로그인 설정 응답의 client secret(비밀 · 화면 · 기록 0회).
  final String googleClientSecret = 'google-idp-${'s' * 16}';

  /// Apple Key ID.
  final String appleKeyId = 'K' * 10;

  /// Apple Team ID.
  final String appleTeamId = 'T' * 10;

  /// Apple Services ID.
  final String appleServicesId = '${devBundleId.toLowerCase()}.signin';

  /// `.p8` 본문 줄 3개.
  final List<String> p8BodyLines = <String>[
    for (var i = 0; i < 3; i++) '${'Pk' * 30}Qz0$i',
  ];

  /// 가짜 `.p8` 내용.
  String get p8Content => <String>[
    pemPrivateKeyHeader,
    ...p8BodyLines,
    <String>['-----END', ' PRIVATE', ' KEY-----'].join(),
    '',
  ].join('\n');

  /// 화면 · 기록에 나오면 안 되는 비밀 값.
  List<String> get secrets => <String>[
    facebookAppSecret,
    kakaoAdminKey,
    naverClientSecret,
    lineChannelSecret,
    googleClientSecret,
    ...p8BodyLines,
    pemPrivateKeyHeader,
  ];
}

/// 화면 · 기록에서 [needle] 이 나온 횟수를 센다.
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

/// 설정이 없을 때의 로그인 수단 응답.
final RestResponse idpMissing = RestResponse(
  404,
  jsonEncode(<String, Object?>{
    'error': <String, Object?>{'code': 404, 'status': 'NOT_FOUND'},
  }),
);

/// [idpId] 로그인 수단 설정 GET 주소.
String buildIdpUrl(String idpId) =>
    '$idpConfigUrlPrefix$projectId/defaultSupportedIdpConfigs/$idpId';

/// [idpId] 로그인 수단 설정 생성 주소.
String buildIdpCreateUrl(String idpId) =>
    '$idpConfigUrlPrefix$projectId/defaultSupportedIdpConfigs?idpId=$idpId';

/// 실행 기록 · 화면에 실제 실행기처럼 쓰는 실행기 — 결과는 가짜 실행기가 준다.
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
    for (final text in <String>[result.stdout, result.stderr]) {
      if (text.isEmpty) continue;
      log.write(
        'out',
        command.isOutputSensitive
            ? ProcessCommandRunner.sensitiveOutputNotice
            : text,
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
    for (final text in <String>[result.stdout, result.stderr]) {
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
    _write(
      '${request.method} ${request.url}',
      request.isResponseSensitive,
      response,
    );
    return response;
  }

  @override
  Future<RestResponse> sendExternal(ExternalRequest request) async {
    final RestResponse response = await inner.sendExternal(request);
    _write(
      '${request.method} ${request.url}',
      request.isResponseSensitive,
      response,
    );
    return response;
  }

  void _write(String target, bool isSensitive, RestResponse response) {
    log.write('rest', '$target → ${response.statusCode}');
    if (response.body.isEmpty) return;
    log.write(
      'rest',
      isSensitive ? HttpRestClient.sensitiveResponseNotice : response.body,
    );
  }
}

/// 흐름 한 번에 쓰는 가짜 실행기 · REST · 화면 · 기록 묶음.
final class _Harness {
  _Harness(this.root, List<String?> inputs)
    : runner = FakeCommandRunner(),
      rest = FakeRestClient(),
      screen = ScriptedTerminal(inputs),
      log = MemoryLogSink(Redactor()) {
    final terminal = RedactingTerminal(screen, log.redactor, log);
    context = WizardContext(
      projectRoot: root,
      runner: _LoggingRunner(runner, terminal, log),
      terminal: terminal,
      redactor: log.redactor,
      log: log,
      rest: _LoggingRest(rest, log),
      homeDirectory: noKeystoreTestHome,
      random: Random(fixedTestRandomSeed),
      now: () => fixedTestNow,
    );
  }

  final String root;
  final FakeCommandRunner runner;
  final FakeRestClient rest;
  final ScriptedTerminal screen;
  final MemoryLogSink log;
  late final WizardContext context;

  /// 화면 출력 전체.
  String get output => screen.output.toString();

  /// 화면 줄.
  List<String> get lines => const LineSplitter().convert(output);

  /// [command] 의 결과 큐에 [results] 를 차례로 더한다.
  void onCommand(Command command, List<CommandResult> results) {
    for (final result in results) {
      runner.on(FakeCommandRunner.buildKey(command), result);
    }
  }

  /// [request] 의 응답 큐에 [responses] 를 차례로 더한다.
  void onRest(RestRequest request, List<RestResponse> responses) {
    for (final response in responses) {
      rest.on(request.method, request.url.toString(), response);
    }
  }

  /// [method] · [url] 의 응답 큐에 [responses] 를 차례로 더한다.
  void onUrl(String method, String url, List<RestResponse> responses) {
    for (final response in responses) {
      rest.on(method, url, response);
    }
  }

  /// [name] secret 읽기 결과 큐에 [results] 를 차례로 더한다.
  void onSecretReads(String name, List<CommandResult> results) =>
      onCommand(buildSecretReadCommand(name, projectId), results);

  /// [name] secret 쓰기를 성공으로 등록한다.
  void onSecretWrite(String name) => onCommand(
    buildSecretWriteCommand(name, projectId, value: '', valueLabel: ''),
    <CommandResult>[ok()],
  );

  /// config 의 켠 로그인 수단으로 만든 단계 목록으로 위저드를 돌린다.
  Future<int> run() =>
      runWizard(context, buildCurrentSteps(), rebuildSteps: buildCurrentSteps);

  /// config 를 다시 읽어 단계 목록을 만든다.
  List<Step> buildCurrentSteps() => buildSteps(
    flavor: Flavor.dev,
    enabledProviders: readEnabledProviders(context.resolve(context.paths.json)),
  );

  /// 쓰기 REST 요청(POST · PATCH · DELETE) 수.
  int countWriteRequests() => rest.requests
      .where((RestRequest request) => request.method != 'GET')
      .length;

  /// Secret Manager 쓰기 호출 수.
  int countSecretWrites() => runner.calls
      .where(
        (FakeCall call) =>
            call.key.startsWith('firebase functions:secrets:set'),
      )
      .length;

  /// 실행 기록에서 [prefix] 로 시작하는 첫 줄의 위치 — 없으면 -1.
  int findLogLine(String prefix) =>
      log.lines.indexWhere((String line) => line.startsWith(prefix));
}

/// 저장소 상대 경로에 내용을 쓴다(부모 디렉터리를 만든다).
void writeFixture(String root, String relativePath, String content) {
  File('$root/$relativePath')
    ..parent.createSync(recursive: true)
    ..writeAsStringSync(content);
}

/// 앞 단계가 모두 끝나고 여섯 로그인 수단을 켠 저장소를 [root] 에 만든다.
///
/// 로그인 수단의 키 자리는 example 의 자리표시 그대로다. iOS 설정 파일은 Google
/// 로그인 정보(`CLIENT_ID` · `REVERSED_CLIENT_ID`)가 든 모양이다.
void _writeSixProviderFixture(String root, _Values values) {
  final String jsonExample = File(
    UserFilesStep.jsonExamplePath,
  ).readAsStringSync();
  final String xcconfigExample = File(
    UserFilesStep.xcconfigExamplePath,
  ).readAsStringSync();
  writeFixture(root, UserFilesStep.jsonExamplePath, jsonExample);
  writeFixture(root, UserFilesStep.xcconfigExamplePath, xcconfigExample);
  final config = jsonDecode(jsonExample)! as Map<String, Object?>;
  config
    ..[FirebaseProjectStep.projectIdKey] = projectId
    ..['appName'] = displayName
    ..[AppCheckStep.tokenKey] = debugToken
    ..[enabledProvidersKey] = allProvidersCsv;
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
    'android/app/src/main/kotlin/com/acme/six_app/MainActivity.kt',
    'package $applicationId\n\nclass MainActivity\n',
  );
  writeFixture(
    root,
    ConfigureStep.scriptPath,
    '#!/usr/bin/env bash\n'
    'PROJECT_ID_PREFIX="six-app"\n'
    'IOS_BUNDLE_ID_PREFIX="com.acme.sixApp"\n'
    'ANDROID_PACKAGE_PREFIX="$applicationId"\n',
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
  final apiKey = 'AIza${'x' * 35}';
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
    '<key>CLIENT_ID</key>\n<string>${values.googleClientId}</string>\n'
    '<key>REVERSED_CLIENT_ID</key>\n'
    '<string>${values.googleReversedClientId}</string>\n'
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
  writeFixture(root, RulesStep.firestoreRulesPath, firestoreRules);
  writeFixture(root, RulesStep.storageRulesPath, storageRules);
  writeFixture(
    root,
    FunctionsStep.manifestPath,
    '${jsonEncode(<String, Object?>{'common': commonFunctions, 'providers': providerFunctions})}\n',
  );
  writeFixture(
    root,
    'functions/src/index.ts',
    'const kitSecret = defineSecret("$declaredSecret");\n',
  );
  writeFixture(root, FunctionsStep.modulesMarkerPath, '');
}

/// ruleset 응답 본문.
String buildRulesetBody(String content) => jsonEncode(<String, Object?>{
  'source': <String, Object?>{
    'files': <Object?>[
      <String, Object?>{'name': 'rules', 'content': content},
    ],
  },
});

/// 배포된 함수 목록 결과 — [isProviderDeployed] 면 로그인 수단 함수까지.
CommandResult buildFunctionsList({required bool isProviderDeployed}) => ok(
  jsonEncode(<String, Object?>{
    'status': 'success',
    'result': <Object?>[
      for (final String function in <String>[
        ...commonFunctions,
        if (isProviderDeployed)
          for (final List<String> names in providerFunctions.values) ...names,
      ])
        <String, Object?>{
          'id': function,
          'region': region,
          'runServiceId': function,
        },
    ],
  }),
);

/// 앞 단계(Xcode ~ App Check · 앱 실행 · 로그인 확인)의 「끝남」 응답을 등록한다.
void _registerBaseFinished(_Harness h, {required bool isPlayIntegrityApiOn}) {
  final token = 'ya29.${'A' * 40}';
  for (final (String key, String stdout) in <(String, String)>[
    ('xcode-select -p', '/Applications/Xcode.app/Contents/Developer\n'),
    ('xcodebuild -license check', ''),
    ('xcodebuild -checkFirstLaunchStatus', ''),
    (
      'xcrun simctl list runtimes -j',
      jsonEncode(<String, Object?>{
        'runtimes': <Object?>[
          <String, Object?>{'platform': 'iOS', 'isAvailable': true},
        ],
      }),
    ),
    ('node --version', 'v22.11.0\n'),
    ('pnpm --version', '10.4.1\n'),
    ('firebase --version', '15.29.0\n'),
    ('gcloud --version', 'Google Cloud SDK 540.0.0\n'),
    ('jq --version', 'jq-1.7.1\n'),
    ("ruby -e require 'xcodeproj'", ''),
    ('fvm dart pub global list', 'flutterfire_cli 1.3.1\n'),
  ]) {
    h.runner.on(key, ok(stdout));
  }
  h
    ..onCommand(LoginStep.firebaseAccountsCommand, <CommandResult>[
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
    ])
    ..onCommand(AccessTokenSource.tokenCommand, <CommandResult>[ok('$token\n')])
    ..onCommand(LoginStep.gcloudAccountCommand, <CommandResult>[
      ok('$accountEmail\n'),
    ])
    ..onCommand(FirebaseProjectStep.projectsListCommand, <CommandResult>[
      ok(
        jsonEncode(<String, Object?>{
          'status': 'success',
          'result': <Object?>[
            <String, Object?>{'projectId': projectId, 'displayName': projectId},
          ],
        }),
      ),
    ])
    ..onCommand(BillingStep.billingInfoCommand(projectId), <CommandResult>[
      ok('{"billingEnabled":true}'),
    ])
    ..onCommand(ApisStep.buildEnabledListCommand(projectId), <CommandResult>[
      ok(
        '${<String>[...ApisStep.requiredServices, if (isPlayIntegrityApiOn) PlayIntegrityStep.serviceName].join('\n')}\n',
      ),
    ])
    ..onCommand(FirestoreStep.buildDescribeCommand(projectId), <CommandResult>[
      ok('$region\n'),
    ])
    ..onCommand(ConfigureStep.buildAppsListCommand(projectId), <CommandResult>[
      ok(
        jsonEncode(<String, Object?>{
          'status': 'success',
          'result': <Object?>[
            <String, Object?>{'appId': iosAppId, 'platform': 'IOS'},
            <String, Object?>{'appId': androidAppId, 'platform': 'ANDROID'},
          ],
        }),
      ),
    ])
    ..onCommand(
      FunctionsStep.buildSecretsListCommand(projectId),
      <CommandResult>[ok('projects/000000000000/secrets/$declaredSecret\n')],
    );
  for (final function in <String>[
    ...commonFunctions,
    for (final List<String> names in providerFunctions.values) ...names,
  ]) {
    h.onCommand(
      FunctionsStep.buildIamPolicyCommand(function, region, projectId),
      <CommandResult>[
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
      ],
    );
  }

  h
    ..onRest(StorageStep.buildGetRequest(projectId), <RestResponse>[
      RestResponse(
        200,
        jsonEncode(<String, Object?>{
          'name': 'projects/$projectId/defaultBucket',
          'location': region,
          'bucket': <String, Object?>{
            'name':
                'projects/$projectId/buckets/$projectId.firebasestorage.app',
          },
        }),
      ),
    ])
    ..onRest(SignInStep.buildGetRequest(projectId), <RestResponse>[
      RestResponse(
        200,
        jsonEncode(<String, Object?>{
          'signIn': <String, Object?>{
            'email': <String, Object?>{
              'enabled': true,
              'passwordRequired': true,
            },
            'anonymous': <String, Object?>{'enabled': true},
          },
        }),
      ),
    ]);
  const firestoreRuleset = 'projects/$projectId/rulesets/fs';
  const storageRuleset = 'projects/$projectId/rulesets/st';
  h
    ..onRest(
      RulesStep.buildReleaseRequest(projectId, RulesStep.firestoreRelease),
      <RestResponse>[
        RestResponse(
          200,
          jsonEncode(<String, String>{'rulesetName': firestoreRuleset}),
        ),
      ],
    )
    ..onRest(
      RulesStep.buildReleaseRequest(
        projectId,
        '${RulesStep.storageReleasePrefix}/$projectId.firebasestorage.app',
      ),
      <RestResponse>[
        RestResponse(
          200,
          jsonEncode(<String, String>{'rulesetName': storageRuleset}),
        ),
      ],
    )
    ..onRest(RulesStep.buildRulesetRequest(projectId, firestoreRuleset), [
      RestResponse(200, buildRulesetBody(firestoreRules)),
    ])
    ..onRest(RulesStep.buildRulesetRequest(projectId, storageRuleset), [
      RestResponse(200, buildRulesetBody(storageRules)),
    ]);
  for (final appId in <String>[iosAppId, androidAppId]) {
    h.onRest(AppCheckStep.buildListRequest(projectId, appId), <RestResponse>[
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
    ]);
  }
  // 앱 실행 · 소셜 로그인 확인 — Google · Apple · Facebook 은 사용자 정보,
  // Kakao · Naver · LINE 은 identity_index 문서와 그 주인의 Custom Token 로그인
  // 기록(문서가 생긴 뒤 로그인)으로 센다.
  final indexCreatedAt = DateTime.utc(2031, 5, 6, 7, 8, 9);
  h
    ..onRest(RunStep.buildBatchGetRequest(projectId), <RestResponse>[
      RestResponse(
        200,
        jsonEncode(<String, Object?>{
          'users': <Object?>[
            <String, Object?>{
              'localId': 'uidSixUser0001',
              'emailVerified': true,
              'providerUserInfo': <Object?>[
                for (final id in <String>[
                  'password',
                  'google.com',
                  'apple.com',
                  'facebook.com',
                ])
                  <String, Object?>{'providerId': id},
              ],
            },
            for (final provider in identityIndexProviders)
              <String, Object?>{
                'localId': _buildOwnerUid(provider),
                'customAuth': true,
                'lastLoginAt': indexCreatedAt
                    .add(const Duration(seconds: 2))
                    .millisecondsSinceEpoch
                    .toString(),
                'createdAt': indexCreatedAt.millisecondsSinceEpoch.toString(),
              },
          ],
        }),
      ),
    ])
    ..onRest(
      buildIdentityIndexRequest(projectId, basis: SignInBasis.signedIn),
      <RestResponse>[
        RestResponse(
          200,
          jsonEncode(<String, Object?>{
            'documents': <Object?>[
              for (final provider in <String>['kakao', 'naver', 'line'])
                <String, Object?>{
                  'name':
                      'projects/$projectId/databases/(default)/documents/'
                      'identity_index/$provider:${'d' * 8}',
                  'fields': <String, Object?>{
                    'provider': <String, Object?>{'stringValue': provider},
                    'firebaseUid': <String, Object?>{
                      'stringValue': _buildOwnerUid(provider),
                    },
                  },
                  'createTime': indexCreatedAt.toIso8601String(),
                  'updateTime': indexCreatedAt.toIso8601String(),
                },
            ],
          }),
        ),
      ],
    );
}

/// [provider] 식별 문서의 주인 uid(실행 시점 조립 · 가짜).
String _buildOwnerUid(String provider) => 'owner-$provider-${'d' * 6}';

/// Google 로그인 설정 응답(켜짐 · client secret 이 평문으로 실린다).
RestResponse _buildGoogleIdp(_Values values) => RestResponse(
  200,
  jsonEncode(<String, Object?>{
    'name': 'projects/$projectId/defaultSupportedIdpConfigs/google.com',
    'enabled': true,
    'clientId': values.googleClientId,
    'clientSecret': values.googleClientSecret,
  }),
);

/// Apple 로그인 설정 응답 — [hasCodeFlow] 면 Android 쪽 코드 흐름까지 채워져 있다.
RestResponse _buildAppleIdp(_Values values, {required bool hasCodeFlow}) =>
    RestResponse(
      200,
      jsonEncode(<String, Object?>{
        'name': 'projects/$projectId/defaultSupportedIdpConfigs/apple.com',
        'enabled': true,
        if (hasCodeFlow) 'clientId': values.appleServicesId,
        'appleSignInConfig': <String, Object?>{
          'bundleIds': <String>[devBundleId],
          if (hasCodeFlow)
            'codeFlowConfig': <String, Object?>{
              'teamId': values.appleTeamId,
              'keyId': values.appleKeyId,
              'privateKey': values.p8Content,
            },
        },
      }),
    );

/// Facebook 로그인 설정 응답.
RestResponse _buildFacebookIdp(_Values values) => RestResponse(
  200,
  jsonEncode(<String, Object?>{
    'name': 'projects/$projectId/defaultSupportedIdpConfigs/facebook.com',
    'enabled': true,
    'clientId': values.facebookAppId,
    'clientSecret': values.facebookAppSecret,
  }),
);

/// Play Integrity 설정 응답 — [isRelaxed] 면 dev 판정 기준.
RestResponse buildPlayIntegrity({required bool isRelaxed}) => RestResponse(
  200,
  jsonEncode(<String, Object?>{
    'name': 'projects/$projectId/apps/$androidAppId/playIntegrityConfig',
    'tokenTtl': '3600s',
    if (isRelaxed) ...<String, Object?>{
      'appIntegrity': <String, Object?>{'allowUnrecognizedVersion': true},
      'deviceIntegrity': <String, Object?>{
        'minDeviceRecognitionLevel':
            PlayIntegrityStep.relaxedDeviceRecognitionLevel,
      },
    },
  }),
);

/// DeviceCheck 설정 응답 — [keyId] 가 있으면 키가 들어가 있다.
RestResponse buildDeviceCheck({String? keyId}) => RestResponse(
  200,
  jsonEncode(<String, Object?>{
    'name': 'projects/$projectId/apps/$iosAppId/deviceCheckConfig',
    'tokenTtl': '3600s',
    if (keyId != null) ...<String, Object?>{
      'keyId': keyId,
      'privateKeySet': true,
    },
  }),
);

/// 키 자리표시 · Firebase IdP 없음 · secret 없음인 첫 실행의 응답을 등록한다.
///
/// 로그인 수단 단계는 점검표에서 앱 등록(Google 을 기다림)을 기다리므로 단계
/// 머리 · 실행 뒤 재검사 두 번만 검사된다 — secret 은 「없음 · 쓴 값」 이다.
void _registerFirstRun(_Harness h, _Values values) {
  _registerBaseFinished(h, isPlayIntegrityApiOn: false);
  // Google — 점검표 · 단계 머리는 없음, 켠 뒤 · 재검사는 켜짐.
  h
    ..onUrl('GET', buildIdpUrl(GoogleStep.idpId), <RestResponse>[
      idpMissing,
      idpMissing,
      _buildGoogleIdp(values),
    ])
    ..onCommand(GoogleStep.buildProjectDescribeCommand(projectId), [
      ok('{"projectId":"$projectId"}'),
    ])
    ..onCommand(GoogleStep.buildDeployCommand(projectId), <CommandResult>[
      ok(),
    ]);
  // Apple — iOS 쪽 만들기 · Android 쪽은 코드 흐름 없음(지금 안 함).
  h
    ..onUrl('GET', buildIdpUrl('apple.com'), <RestResponse>[
      idpMissing,
      _buildAppleIdp(values, hasCodeFlow: false),
    ])
    ..onUrl('POST', buildIdpCreateUrl('apple.com'), <RestResponse>[
      _buildAppleIdp(values, hasCodeFlow: false),
    ]);
  // Facebook — 짝 확인 · Firebase 설정 만들기.
  h
    ..onUrl('GET', buildIdpUrl('facebook.com'), <RestResponse>[
      idpMissing,
      _buildFacebookIdp(values),
    ])
    ..onUrl('POST', buildIdpCreateUrl('facebook.com'), <RestResponse>[
      _buildFacebookIdp(values),
    ]);
  h.rest
    ..onExternal(
      'POST',
      FacebookStep.pairCheckUrl,
      RestResponse(
        200,
        '{"access_token":"${values.facebookAppId}|'
        '${values.facebookAppSecret}","token_type":"bearer"}',
      ),
    )
    ..onExternal(
      'GET',
      KakaoStep.adminKeyCheckUrl,
      const RestResponse(200, '{"elements":[1]}'),
    )
    ..onExternal('POST', NaverStep.pairCheckUrl, const RestResponse(200, ''))
    ..onExternal(
      'POST',
      LineStep.pairCheckUrl,
      const RestResponse(
        200,
        '{"access_token":"fake-line-flow-token","expires_in":900,'
        '"token_type":"Bearer"}',
      ),
    );
  for (final (String name, String value) in <(String, String)>[
    ('FACEBOOK_APP_ID', values.facebookAppId),
    ('FACEBOOK_APP_SECRET', values.facebookAppSecret),
    ('KAKAO_NATIVE_APP_KEY', values.kakaoNativeKey),
    ('KAKAO_ADMIN_KEY', values.kakaoAdminKey),
    ('NAVER_CLIENT_ID', values.naverClientId),
    ('NAVER_CLIENT_SECRET', values.naverClientSecret),
    ('LINE_CHANNEL_ID', values.lineChannelId),
    ('LINE_CHANNEL_SECRET', values.lineChannelSecret),
  ]) {
    h
      ..onSecretReads(name, <CommandResult>[
        buildSecretMissing(name),
        ok('$value\n'),
      ])
      ..onSecretWrite(name);
  }
  // Functions — 단계 머리는 공통 함수만, 배포 뒤 · 재검사는 로그인 수단 함수까지.
  h
    ..onCommand(FunctionsStep.buildFunctionsListCommand(projectId), [
      buildFunctionsList(isProviderDeployed: false),
      buildFunctionsList(isProviderDeployed: true),
    ])
    ..onCommand(FunctionsStep.buildDeployCommand(), <CommandResult>[
      ok('DEPLOY OK dev functions=5 batches=1\n'),
    ]);
  // 출시용 — Play Integrity 기본 설정(지금 안 함) · DeviceCheck 미등록 → 등록.
  h
    ..onRest(
      PlayIntegrityStep.buildGetRequest(projectId, androidAppId),
      <RestResponse>[buildPlayIntegrity(isRelaxed: false)],
    )
    ..onRest(DeviceCheckStep.buildGetRequest(projectId, iosAppId), [
      buildDeviceCheck(),
      buildDeviceCheck(keyId: values.appleKeyId),
    ])
    ..onRest(
      DeviceCheckStep.buildTeamIdPatchRequest(
        projectId,
        iosAppId,
        values.appleTeamId,
      ),
      <RestResponse>[const RestResponse(200, '{}')],
    )
    ..onRest(
      DeviceCheckStep.buildPatchRequest(
        projectId,
        iosAppId,
        keyId: values.appleKeyId,
        privateKey: '',
      ),
      <RestResponse>[const RestResponse(200, '{}')],
    );
}

/// 같은 저장소의 재실행 — 모든 단계가 끝난 응답을 등록한다.
void _registerFinishedRun(_Harness h, _Values values) {
  _registerBaseFinished(h, isPlayIntegrityApiOn: true);
  h
    ..onUrl('GET', buildIdpUrl(GoogleStep.idpId), <RestResponse>[
      _buildGoogleIdp(values),
    ])
    ..onUrl('GET', buildIdpUrl('apple.com'), <RestResponse>[
      _buildAppleIdp(values, hasCodeFlow: true),
    ])
    ..onUrl('GET', buildIdpUrl('facebook.com'), <RestResponse>[
      _buildFacebookIdp(values),
    ])
    ..onCommand(FunctionsStep.buildFunctionsListCommand(projectId), [
      buildFunctionsList(isProviderDeployed: true),
    ])
    ..onRest(
      PlayIntegrityStep.buildGetRequest(projectId, androidAppId),
      <RestResponse>[buildPlayIntegrity(isRelaxed: true)],
    )
    ..onRest(DeviceCheckStep.buildGetRequest(projectId, iosAppId), [
      buildDeviceCheck(keyId: values.appleKeyId),
    ]);
  for (final (String name, String value) in <(String, String)>[
    ('FACEBOOK_APP_ID', values.facebookAppId),
    ('FACEBOOK_APP_SECRET', values.facebookAppSecret),
    ('KAKAO_NATIVE_APP_KEY', values.kakaoNativeKey),
    ('KAKAO_ADMIN_KEY', values.kakaoAdminKey),
    ('NAVER_CLIENT_ID', values.naverClientId),
    ('NAVER_CLIENT_SECRET', values.naverClientSecret),
    ('LINE_CHANNEL_ID', values.lineChannelId),
    ('LINE_CHANNEL_SECRET', values.lineChannelSecret),
  ]) {
    h.onSecretReads(name, <CommandResult>[ok('$value\n')]);
  }
}

/// 첫 실행 입력 — 단계 진행 순서대로.
List<String?> _buildFirstRunInputs(_Values values, String p8Path) => <String?>[
  'y', // Google 로그인
  '1', // 동의 화면 값 표 — 이대로 진행
  'y', // Google — iOS 쪽
  'y', // Apple 로그인 — iOS 쪽
  '2', // Apple 로그인 — Android 쪽 · 지금 안 함
  'y', // Facebook
  '1', // 콘솔에서 키를 받았다
  values.facebookAppId,
  values.facebookClientToken,
  values.facebookAppSecret,
  'y', // Kakao
  '1',
  values.kakaoNativeKey,
  values.kakaoAdminKey,
  'y', // Naver
  '1',
  values.naverClientId,
  values.naverClientSecret,
  '', // URL Scheme — 제안값
  'y', // LINE
  '1',
  values.lineChannelId,
  values.lineChannelSecret,
  'y', // Functions
  '2', // Play Integrity — 지금 안 함
  '1', // DeviceCheck — 진행
  p8Path,
  '', // Key ID — 파일 이름의 값
  values.appleTeamId,
  '1', // APNs — 업로드 안내 보기
  '', // 안내 확인
];

/// 첫 실행 결과 — 화면 · 기록 · 호출을 함께 둔다.
typedef _FirstRun = ({_Harness h, int code});

void main() {
  late Directory tempDir;
  late Directory keyDir;
  late String root;
  late _Values values;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('wizard_providers_flow_');
    keyDir = Directory.systemTemp.createTempSync('wizard_providers_keys_');
    root = tempDir.path;
    values = _Values();
    _writeSixProviderFixture(root, values);
    File(
      '${keyDir.path}/AuthKey_${values.appleKeyId}.p8',
    ).writeAsStringSync(values.p8Content);
  });

  tearDown(() {
    tempDir.deleteSync(recursive: true);
    keyDir.deleteSync(recursive: true);
  });

  /// 여섯 수단을 켠 저장소의 첫 실행을 돌린다.
  Future<_FirstRun> runFirst() async {
    final h = _Harness(
      root,
      _buildFirstRunInputs(
        values,
        '${keyDir.path}/AuthKey_${values.appleKeyId}.p8',
      ),
    );
    _registerFirstRun(h, values);
    final int code = await h.run();
    return (h: h, code: code);
  }

  test('T-20-ALL-01: 여섯 수단 첫 실행 — 비밀 값마다 숨김 질문 1번 · Apple Android 쪽 '
      '지금 안 함 · DeviceCheck 키 · Play Integrity 지금 안 함 · APNs 안내 · '
      '종료 0', () async {
    final _FirstRun first = await runFirst();
    final _Harness h = first.h;

    expect(first.code, wizardExitDone, reason: h.output);
    expect(h.screen.secretAsks, <String>[
      '${FacebookStep.appSecretField.label} $hiddenInputHint',
      '${KakaoStep.adminKeyField.label} $hiddenInputHint',
      '${NaverStep.clientSecretField.label} $hiddenInputHint',
      '${LineStep.channelSecretField.label} $hiddenInputHint',
    ]);
    expect(
      h.screen.asks.where((String ask) => ask == 'DeviceCheck 용 .p8 파일 경로'),
      hasLength(1),
    );
    expect(
      h.screen.asks.where((String ask) => ask == appleKeyIdQuestion),
      hasLength(1),
    );
    expect(
      h.screen.asks.where(
        (String ask) => ask == 'Sign in with Apple 용 .p8 파일 경로',
      ),
      isEmpty,
    );
    expect(h.output, contains('  ✗ ${AppleAndroidStep.stepTitle} — 지금 안 함'));
    expect(h.output, contains('  ✗ ${PlayIntegrityStep.stepTitle} — 지금 안 함'));
    expect(h.output, contains('  ✓ ${DeviceCheckStep.stepTitle} — '));
    expect(h.output, contains(ApnsStep.uploadTodoLine));
    expect(h.output, contains('Key ID ${values.appleKeyId} 의 .p8'));
    expect(h.context.session.hasEnteredDeviceCheckKey, isTrue);
    expect(h.context.session.isApnsGuideShown, isTrue);
    // 같은 실행에서 같은 키 두 번 입력 0 — 각 키 질문이 한 번씩이다.
    for (final field in <KeyField>[
      FacebookStep.appIdField,
      FacebookStep.clientTokenField,
      KakaoStep.nativeAppKeyField,
      NaverStep.clientIdField,
      LineStep.channelIdField,
    ]) {
      expect(
        h.screen.asks.where((String ask) => ask.startsWith(field.label)),
        hasLength(1),
        reason: field.label,
      );
    }
    expect(h.countSecretWrites(), 8);
    expect(
      readXcconfigValue(
        '$root/${UserFilesStep.xcconfigUserPath}',
        developmentTeamVariable,
      ),
      values.appleTeamId,
    );
  });

  test('T-20-ALL-02: 함수 배포는 1번 · iOS 쪽 로그인 수단이 모두 ✓ 인 뒤 · '
      'Apple Android 쪽 ✗ 는 배포를 막지 않는다', () async {
    final _FirstRun first = await runFirst();
    final _Harness h = first.h;

    expect(first.code, wizardExitDone, reason: h.output);
    expect(h.runner.countCalls(RunMode.stream, deployKey), 1);
    final int deployLine = h.findLogLine('[cmd] $deployKey');
    expect(deployLine, isNonNegative);
    for (final id in <String>[
      'google',
      'google_ios',
      'apple',
      'facebook',
      'kakao',
      'naver',
      'line',
    ]) {
      final int done = h.findLogLine('[check] $id ✓ ');
      expect(done, isNonNegative, reason: id);
      expect(done, lessThan(deployLine), reason: id);
    }
    final int androidDeferred = h.findLogLine(
      '[check] ${AppleAndroidStep.stepId} ✗ ',
    );
    expect(androidDeferred, isNonNegative);
    expect(androidDeferred, lessThan(deployLine));
    expect(h.findLogLine('[check] ${AppleAndroidStep.stepId} ✓ '), -1);
    expect(h.output, contains('  ✓ ${FunctionsStep.stepTitle} — '));
  });

  test('T-20-ALL-03: 끝 목록에 Apple Android 쪽 · Play Integrity · APNs · '
      '지문 수단의 Android 쪽 ✗ 줄이 있고 모두 끝남 줄이 없다', () async {
    final _FirstRun first = await runFirst();
    final _Harness h = first.h;

    expect(first.code, wizardExitDone, reason: h.output);
    expect(h.output, isNot(contains(allDoneLine)));
    final List<String> lines = h.lines;
    final int heading = lines.indexOf(remainingHeading);
    expect(heading, isNonNegative);
    expect(lines[heading - 1], remainingDoneLine);
    final List<String> remaining = lines.sublist(heading + 1);
    expect(remaining, <String>[
      '  ✗ Google — Android 쪽 — $unavailableFingerprintGuide',
      '  ✗ ${AppleAndroidStep.stepTitle} — 지금 안 함',
      for (final name in <String>['Facebook', 'Kakao', 'LINE'])
        '  ✗ $name — Android 쪽 — $unavailableFingerprintGuide',
      '  ✗ ${PlayIntegrityStep.stepTitle} — 지금 안 함',
      '  ? ${ApnsStep.stepTitle} — ${ApnsStep.unverifiableNote}',
    ]);
    expect(remaining.length, greaterThanOrEqualTo(3));
    // Naver 콘솔의 Android 칸은 패키지명만 받는다 — 지문이 없어도 ✓ 다.
    expect(
      lines,
      contains(
        '  ✓ Naver — Android 쪽 — 패키지명 '
        '$applicationId$devPackageSuffix $consoleRegistrationNote',
      ),
    );
  });

  test('T-20-ALL-04: 화면 · 기록 두 버퍼에 입력한 비밀 값 · .p8 본문 · PEM 머리 · '
      'IdP 응답 client secret 이 0회', () async {
    final _FirstRun first = await runFirst();
    final _Harness h = first.h;

    expect(first.code, wizardExitDone, reason: h.output);
    for (final buffer in <String>[h.output, h.log.text]) {
      for (final String secret in values.secrets) {
        expect(countText(buffer, secret), 0, reason: secret);
      }
    }
    // 대조: 비밀 값은 실제로 요청 · 쓰기에 실렸다.
    final RestRequest deviceCheck = h.rest.requests.singleWhere(
      (RestRequest request) =>
          request.method == 'PATCH' &&
          request.url.path.endsWith('/deviceCheckConfig'),
    );
    expect(deviceCheck.body, contains(values.p8BodyLines.first));
    expect(
      h.runner.calls.map((FakeCall call) => call.stdinText),
      contains(values.kakaoAdminKey),
    );
    expect(h.log.text, contains(HttpRestClient.sensitiveResponseNotice));
  });

  test('T-20-ALL-05: 같은 저장소 재실행 → 숨김 질문 · 키 질문 · 쓰기 · 단계 진행 '
      '질문 0', () async {
    final _FirstRun first = await runFirst();
    expect(first.code, wizardExitDone, reason: first.h.output);

    final h = _Harness(root, const <String?>[]);
    _registerFinishedRun(h, values);
    final int code = await h.run();

    expect(code, wizardExitDone, reason: h.output);
    expect(h.screen.asks, isEmpty);
    expect(h.screen.secretAsks, isEmpty);
    expect(h.countWriteRequests(), 0);
    expect(h.rest.externalRequests, isEmpty);
    expect(h.countSecretWrites(), 0);
    expect(h.runner.countMode(RunMode.stream), 0);
    expect(h.runner.countMode(RunMode.interactive), 0);
    final List<String> lines = h.lines;
    // 지문 없는 홈 — Android 쪽 · Play Integrity 는 질문 없는 ✗, APNs 는 ? 다.
    final int heading = lines.indexOf(remainingHeading);
    expect(lines.sublist(heading + 1), <String>[
      for (final name in <String>['Google', 'Facebook', 'Kakao', 'LINE'])
        '  ✗ $name — Android 쪽 — $unavailableFingerprintGuide',
      playIntegrityDeferredLine,
      '  ? ${ApnsStep.stepTitle} — ${ApnsStep.unverifiableNote}',
    ]);
    expect(lines, contains(startsWith('  ✓ ${DeviceCheckStep.stepTitle} — ')));
    expect(lines, contains(startsWith('  ✓ ${AppleAndroidStep.stepTitle} — ')));
  });
}
