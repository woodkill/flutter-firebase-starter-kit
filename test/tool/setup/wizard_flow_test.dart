import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:test/test.dart';

import '../../../bin/rename.dart' as rename;
import '../../../tool/setup/command_runner.dart';
import '../../../tool/setup/completion.dart';
import '../../../tool/setup/config_files.dart';
import '../../../tool/setup/firebase_app_files.dart';
import '../../../tool/setup/flavor.dart';
import '../../../tool/setup/git_tree.dart';
import '../../../tool/setup/providers/fingerprints.dart';
import '../../../tool/setup/providers/icon_specs.dart';
import '../../../tool/setup/providers/keyed_provider_step.dart';
import '../../../tool/setup/providers/provider_catalog.dart';
import '../../../tool/setup/providers/provider_selection.dart';
import '../../../tool/setup/providers/sign_in_counts.dart';
import '../../../tool/setup/redactor.dart';
import '../../../tool/setup/rest_client.dart';
import '../../../tool/setup/secret_store.dart';
import '../../../tool/setup/step.dart';
import '../../../tool/setup/steps/apis_step.dart';
import '../../../tool/setup/steps/apns_step.dart';
import '../../../tool/setup/steps/app_check_step.dart';
import '../../../tool/setup/steps/app_icon_step.dart';
import '../../../tool/setup/steps/billing_step.dart';
import '../../../tool/setup/steps/configure_step.dart';
import '../../../tool/setup/steps/dev_steps.dart';
import '../../../tool/setup/steps/device_check_step.dart';
import '../../../tool/setup/steps/firebase_project_step.dart';
import '../../../tool/setup/steps/firestore_step.dart';
import '../../../tool/setup/steps/flavor_steps.dart';
import '../../../tool/setup/steps/functions_step.dart';
import '../../../tool/setup/steps/identity_step.dart';
import '../../../tool/setup/steps/kakao_step.dart';
import '../../../tool/setup/steps/login_step.dart';
import '../../../tool/setup/steps/play_integrity_step.dart';
import '../../../tool/setup/steps/rules_step.dart';
import '../../../tool/setup/steps/run_step.dart';
import '../../../tool/setup/steps/sign_in_step.dart';
import '../../../tool/setup/steps/storage_step.dart';
import '../../../tool/setup/steps/token_creator_step.dart';
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

/// Kakao 로그인 수단의 함수 목록(가짜 manifest).
const List<String> kakaoFunctions = <String>[
  'kakaoCustomToken',
  'linkKakaoProvider',
  'disconnectKakaoProvider',
];

/// Secret Manager 의 Kakao 네이티브 앱 키 이름.
const String kakaoNativeSecret = 'KAKAO_NATIVE_APP_KEY';

/// Secret Manager 의 Kakao 어드민 키 이름.
const String kakaoAdminSecret = 'KAKAO_ADMIN_KEY';

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

/// 실행 시점에 조립하는 가짜 Kakao 네이티브 앱 키(소문자 16진수 32자).
String buildFakeKakaoNativeKey() => 'a' * 32;

/// 실행 시점에 조립하는 가짜 Kakao 어드민 키(16진수 32자).
String buildFakeKakaoAdminKey() => 'b' * 32;

/// 화면 · 기록에서 [needle] 이 나온 횟수를 센다.
int countText(String haystack, String needle) =>
    haystack.split(needle).length - 1;

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

/// 디버그 키스토어가 없는 홈에서 보이는 Kakao Android 쪽 줄.
const String kakaoAndroidUnavailableLine =
    '  ✗ Kakao — Android 쪽 — $unavailableFingerprintGuide';

/// 디버그 키스토어가 없는 홈에서 보이는 Play Integrity 줄(SHA-256 등록만 남음).
const String playIntegrityDeferredLine =
    '  ✗ ${PlayIntegrityStep.stepTitle} — '
    '${PlayIntegrityStep.fingerprintDeferredReason}';

/// APNs 키 줄 — 늘 확인할 수 없다.
const String apnsUnverifiableLine =
    '  ? ${ApnsStep.stepTitle} — ${ApnsStep.unverifiableNote}';

/// 모든 단계가 끝난 저장소의 DeviceCheck Key ID(실행 시점 조립).
final String finishedDeviceCheckKeyId = 'K' * 10;

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

  /// config 의 켠 로그인 수단으로 만든 단계 목록(로그인 수단 0개면 기본 20단계)
  /// 으로 위저드를 돌린다 — 로그인 수단이 바뀌면 같은 함수로 목록을 다시 만든다.
  Future<int> run({Future<void> Function(WizardContext)? onCompleted}) =>
      runWizard(
        context,
        buildCurrentSteps(),
        onCompleted: onCompleted,
        rebuildSteps: buildCurrentSteps,
      );

  /// config 를 다시 읽어 단계 목록을 만든다.
  List<Step> buildCurrentSteps() => buildSteps(
    flavor: Flavor.dev,
    enabledProviders: readEnabledProviders(context.resolve(context.paths.json)),
  );

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

  final config = jsonDecode(jsonExample)! as Map<String, Object?>;
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
  // 이름 바꾸기가 끝난 저장소의 configure 스크립트 prefix 상수.
  writeFixture(
    root,
    ConfigureStep.scriptPath,
    '#!/usr/bin/env bash\n'
    'PROJECT_ID_PREFIX="${name.replaceAll('_', '-')}"\n'
    'IOS_BUNDLE_ID_PREFIX="$org.myApp"\n'
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

/// Kakao 식별 문서가 생긴 기준 시각(가짜).
final DateTime kakaoIndexCreatedAt = DateTime.utc(2031, 5, 6, 7, 8, 9);

/// Kakao 식별 문서 주인 uid(실행 시점 조립 · 가짜).
final String kakaoOwnerUid = 'owner-kakao-${'d' * 6}';

/// Kakao 로그인 기록 문서 하나가 있는 identity_index 응답 본문.
///
/// 문서 ID · 주인 uid 는 실행 시점에 조립한 가짜 값이고, 문서 메타데이터
/// `createTime` 은 기준 시각 [kakaoIndexCreatedAt] 이다.
String buildKakaoIndexBody() => jsonEncode(<String, Object?>{
  'documents': <Object?>[
    <String, Object?>{
      'name':
          'projects/$projectId/databases/(default)/documents/identity_index/'
          'kakao:${'d' * 8}',
      'fields': <String, Object?>{
        'provider': <String, Object?>{'stringValue': 'kakao'},
        'firebaseUid': <String, Object?>{'stringValue': kakaoOwnerUid},
      },
      'createTime': kakaoIndexCreatedAt.toIso8601String(),
      'updateTime': kakaoIndexCreatedAt.toIso8601String(),
    },
  ],
});

/// 인증된 이메일 사용자 한 명과 Kakao 문서 주인이 있는 batchGet 응답 본문.
///
/// Kakao 문서 주인은 문서가 생긴 뒤 Custom Token 으로 로그인한 사용자 모양이다
/// — 이메일 · 비밀번호 정보가 없어 인증된 이메일 사용자 수는 그대로 1 이다.
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
    <String, Object?>{
      'localId': kakaoOwnerUid,
      'customAuth': true,
      'lastLoginAt': kakaoIndexCreatedAt
          .add(const Duration(seconds: 2))
          .millisecondsSinceEpoch
          .toString(),
      'createdAt': kakaoIndexCreatedAt.millisecondsSinceEpoch.toString(),
    },
  ],
});

/// Cloud Run 서비스 이름(함수 이름 그대로).
String buildServiceId(String function) => function;

/// 배포된 함수 목록 응답(공통 + [extra]).
CommandResult buildFunctionsListResult({
  List<String> extra = const <String>[],
}) => ok(
  jsonEncode(<String, Object?>{
    'status': 'success',
    'result': <Object?>[
      for (final String function in <String>[...commonFunctions, ...extra])
        <String, Object?>{
          'id': function,
          'region': region,
          'runServiceId': buildServiceId(function),
        },
    ],
  }),
);

/// 공개 호출이 붙은 IAM 정책 결과.
CommandResult buildPublicPolicyResult() => ok(
  jsonEncode(<String, Object?>{
    'bindings': <Object?>[
      <String, Object?>{
        'role': FunctionsStep.invokerRole,
        'members': <String>[FunctionsStep.invokerMember],
      },
    ],
  }),
);

/// Firebase CLI 가 없는 secret 을 읽을 때의 결과 — 오류가 표준 출력에 나온다.
CommandResult buildSecretMissingResult(String name) => CommandResult(
  1,
  '\nError: Request to https://secretmanager.googleapis.com/v1/projects/'
      '$projectId/secrets/$name/versions/latest:access had HTTP Error: 404, '
      'Secret [projects/000000000000/secrets/$name] not found or has no '
      'versions.\n',
  '',
);

/// Kakao 로그인 수단의 함수가 있는 함수 목록 파일을 쓴다.
void writeKakaoManifest(String root) => writeFixture(
  root,
  FunctionsStep.manifestPath,
  '${jsonEncode(<String, Object?>{
    'common': commonFunctions,
    'providers': <String, Object?>{'kakao': kakaoFunctions},
  })}\n',
);

/// 함수 런타임 서비스 계정(가짜 — 12자리 프로젝트 번호의 기본 Compute 계정).
String buildFakeRuntimeServiceAccount() =>
    '${'1' * 12}-compute@developer.gserviceaccount.com';

/// 런타임 서비스 계정에 그 계정 자신을 구성원으로 한 Token Creator 가 붙은
/// 서비스 계정 IAM 정책 결과.
CommandResult buildTokenCreatorPolicyResult() => ok(
  jsonEncode(<String, Object?>{
    'bindings': <Object?>[
      <String, Object?>{
        'role': TokenCreatorStep.tokenCreatorRole,
        'members': <String>[
          TokenCreatorStep.buildMember(buildFakeRuntimeServiceAccount()),
        ],
      },
    ],
  }),
);

/// 바인딩이 없는 서비스 계정 IAM 정책 결과.
CommandResult buildEmptyServiceAccountPolicyResult() => ok('{}');

/// Kakao 함수 서비스마다 런타임 서비스 계정(같은 가짜 계정)과 그 계정의 IAM
/// 정책 [policies](등록 순서대로 쓰고 마지막을 되풀이)를 등록한다.
///
/// [policies] 를 주지 않으면 Token Creator 가 이미 붙은 정책 하나다.
void _registerTokenCreator(_Harness h, {List<CommandResult>? policies}) {
  final String account = buildFakeRuntimeServiceAccount();
  for (final String function in kakaoFunctions) {
    h.onCommand(
      TokenCreatorStep.buildServiceAccountCommand(
        buildServiceId(function),
        region,
        projectId,
      ),
      ok('$account\n'),
    );
  }
  for (final CommandResult policy
      in policies ?? <CommandResult>[buildTokenCreatorPolicyResult()]) {
    h.onCommand(
      TokenCreatorStep.buildPolicyCommand(account, projectId),
      policy,
    );
  }
}

/// Kakao 함수의 Cloud Run 서비스 IAM 정책(공개 호출 붙음)과 런타임 서비스 계정 ·
/// 그 계정의 IAM 정책을 등록한다.
///
/// [tokenCreatorPolicies] 는 [_registerTokenCreator] 에 넘긴다.
void _registerKakaoPolicies(
  _Harness h, {
  List<CommandResult>? tokenCreatorPolicies,
}) {
  for (final String function in kakaoFunctions) {
    h.onCommand(
      FunctionsStep.buildIamPolicyCommand(
        buildServiceId(function),
        region,
        projectId,
      ),
      buildPublicPolicyResult(),
    );
  }
  _registerTokenCreator(h, policies: tokenCreatorPolicies);
}

/// Kakao 를 고르는 첫 실행의 입력 — 로그인 수단 · 체크 목록 · 값 표 · 앱 아이콘 ·
/// Kakao 단계 · 키 두 개 · Functions 단계 순서다.
List<String?> buildKakaoFirstRunInputs(String nativeKey, String adminKey) =>
    <String?>[
      'y', // 로그인 수단 단계
      '4', // 체크 목록 — Kakao
      'y', // 값 표
      '2', // 앱 아이콘 — 지금 안 함(이 흐름은 아이콘을 만들지 않는다)
      'y', // Kakao 단계(다시 짠 뒤)
      '1', // 콘솔에서 키를 받았다
      nativeKey,
      adminKey,
      'y', // Functions 단계
    ];

/// Kakao 를 고르는 첫 실행의 함수 목록 파일 · 응답을 등록한다.
///
/// [tokenCreatorPolicies] 는 런타임 서비스 계정 IAM 정책 응답(등록 순서대로)으로,
/// 주지 않으면 Token Creator 가 이미 붙은 정책 하나다.
void _prepareKakaoFirstRun(
  _Harness h, {
  required String nativeKey,
  required String adminKey,
  List<CommandResult>? tokenCreatorPolicies,
}) {
  writeKakaoManifest(h.root);
  h.context.session.isProviderSelectionRequested = true;
  _registerFinished(h);
  h.onRest(
    buildIdentityIndexRequest(projectId, basis: SignInBasis.signedIn),
    RestResponse(200, buildKakaoIndexBody()),
  );
  h
    ..onCommand(
      FunctionsStep.buildFunctionsListCommand(projectId),
      buildFunctionsListResult(),
    )
    ..onCommand(
      FunctionsStep.buildFunctionsListCommand(projectId),
      buildFunctionsListResult(extra: kakaoFunctions),
    );
  _registerKakaoPolicies(h, tokenCreatorPolicies: tokenCreatorPolicies);
  for (final (String name, String value) in <(String, String)>[
    (kakaoNativeSecret, nativeKey),
    (kakaoAdminSecret, adminKey),
  ]) {
    final Command read = buildSecretReadCommand(name, projectId);
    h
      ..onCommand(read, buildSecretMissingResult(name))
      ..onCommand(read, buildSecretMissingResult(name))
      ..onCommand(read, ok('$value\n'))
      ..onCommand(
        buildSecretWriteCommand(name, projectId, value: value, valueLabel: ''),
        ok(),
      );
  }
  h
    ..onCommand(
      FunctionsStep.buildDeployCommand(),
      // 배포 출력에 어드민 키를 섞어 가림을 확인한다.
      ok('i  secret check $adminKey\nDEPLOY OK dev functions=5 batches=1\n'),
    )
    ..on(gitStatusKey, ok())
    ..on(untrackedKey, ok());
  h.rest.onExternal(
    'GET',
    KakaoStep.adminKeyCheckUrl,
    const RestResponse(200, '{"elements":[1]}'),
  );
}

/// 모든 단계의 「끝남」 응답을 등록한다.
///
/// [noise] 가 있으면 민감하지 않은 출력 몇 곳에 섞는다(가림 확인용).
/// [deployedExtra] 는 배포된 함수 목록에 공통 함수 뒤로 더할 함수다.
void _registerFinished(
  _Harness h, {
  String noise = '',
  List<String> deployedExtra = const <String>[],
}) {
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
    // 8. API — 출시용 Play Integrity API 도 켜져 있다(같은 목록 명령).
    ..onCommand(
      ApisStep.buildEnabledListCommand(projectId),
      ok(
        '${<String>[...ApisStep.requiredServices, PlayIntegrityStep.serviceName].join('\n')}\n',
      ),
    )
    // 9. Firestore
    ..onCommand(FirestoreStep.buildDescribeCommand(projectId), ok('$region\n'))
    // 13. 앱 등록
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
    // 16. Functions
    ..onCommand(
      FunctionsStep.buildSecretsListCommand(projectId),
      ok('projects/000000000000/secrets/$declaredSecret\n'),
    )
    ..onCommand(
      FunctionsStep.buildFunctionsListCommand(projectId),
      buildFunctionsListResult(extra: deployedExtra),
    );
  for (final String function in commonFunctions) {
    h.onCommand(
      FunctionsStep.buildIamPolicyCommand(
        buildServiceId(function),
        region,
        projectId,
      ),
      buildPublicPolicyResult(),
    );
  }

  // 10. Storage · 14. rules 의 bucket 이름
  h.onRest(
    StorageStep.buildGetRequest(projectId),
    RestResponse(200, buildBucketBody(echo: noise)),
  );
  // 11. 로그인 수단(이메일 · 익명) — 12. 로그인 수단 고르기는 config 만 읽는다.
  h.onRest(
    SignInStep.buildGetRequest(projectId),
    RestResponse(200, buildSignInBody()),
  );
  // 14. rules
  const firestoreRuleset = 'projects/$projectId/rulesets/fs';
  const storageRuleset = 'projects/$projectId/rulesets/st';
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
  // 15. App Check
  for (final appId in <String>[iosAppId, androidAppId]) {
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
  // 17. 앱 실행 · 로그인 확인
  h.onRest(
    RunStep.buildBatchGetRequest(projectId),
    RestResponse(200, buildVerifiedUsersBody()),
  );
  // 출시용 단계 — Play Integrity 완화 설정(지문 없는 홈이라 질문 없는 ✗) ·
  // DeviceCheck 키 등록됨 · APNs 는 늘 확인할 수 없다.
  h
    ..onRest(
      PlayIntegrityStep.buildGetRequest(projectId, androidAppId),
      RestResponse(200, buildRelaxedPlayIntegrityBody()),
    )
    ..onRest(
      DeviceCheckStep.buildGetRequest(projectId, iosAppId),
      RestResponse(200, buildRegisteredDeviceCheckBody()),
    );
}

/// dev · stg 판정 기준으로 바뀐 Play Integrity 설정 응답 본문.
String buildRelaxedPlayIntegrityBody() => jsonEncode(<String, Object?>{
  'name': 'projects/$projectId/apps/$androidAppId/playIntegrityConfig',
  'tokenTtl': '3600s',
  'appIntegrity': <String, Object?>{'allowUnrecognizedVersion': true},
  'deviceIntegrity': <String, Object?>{
    'minDeviceRecognitionLevel':
        PlayIntegrityStep.relaxedDeviceRecognitionLevel,
  },
});

/// Apple 키가 들어간 DeviceCheck 설정 응답 본문.
String buildRegisteredDeviceCheckBody() => jsonEncode(<String, Object?>{
  'name': 'projects/$projectId/apps/$iosAppId/deviceCheckConfig',
  'keyId': finishedDeviceCheckKeyId,
  'privateKeySet': true,
  'tokenTtl': '3600s',
});

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

/// 가짜 이미지 파일 바이트 [length] 개를 만든다(실행 시점 조립 · 내용 무관).
List<int> _buildFakeIconBytes(int length) =>
    List<int>.generate(length, (int i) => (i * 7 + 3) % 256);

/// [path] 의 정사각 [side] PNG 크기 읽기 결과(`sips -g` 정상 출력 꼴).
CommandResult _buildIconProbeResult(String path, int side) =>
    ok('$path\n  pixelWidth: $side\n  pixelHeight: $side\n  format: png\n');

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

  test('T-19-FLOW-01: buildDevSteps() id 순서가 20단계 그대로다', () {
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
        'providers',
        'configure',
        'rules',
        'app_check',
        'functions',
        'run',
        'play_integrity',
        'device_check',
        'apns',
      ],
    );
  });

  test('T-19-FLOW-02: 모든 단계가 끝난 저장소 재실행 → ✓ 18줄 · 출시용 ✗ · ? 끝 목록 · '
      '질문 · 쓰기 0', () async {
    final h = _Harness(root, const <String?>[]);
    _registerFinished(h);

    final int code = await h.run();

    expect(code, wizardExitDone);
    final List<String> lines = const LineSplitter().convert(h.output);
    expect(
      lines.where((String line) => line.startsWith('  ✓ ')),
      hasLength(18),
    );
    // 지문 없는 홈 — Play Integrity 만 할 수 없는 ✗(점검표 · 끝 목록 한 줄씩).
    expect(lines.where((String line) => line.startsWith('  ✗ ')), <String>[
      playIntegrityDeferredLine,
      playIntegrityDeferredLine,
    ]);
    expect(h.output, isNot(contains(allDoneLine)));
    final int remaining = lines.indexOf(remainingHeading);
    expect(lines[remaining - 1], remainingDoneLine);
    expect(lines.sublist(remaining + 1), <String>[
      playIntegrityDeferredLine,
      apnsUnverifiableLine,
    ]);
    expect(h.countStepQuestions(), 0);
    expect(h.screen.asks, isEmpty);
    expect(h.runner.countMode(RunMode.interactive), 0);
    expect(h.runner.countMode(RunMode.stream), 0);
    expect(countWriteRequests(h.rest), 0);
  });

  test('T-19-FLOW-03: 익명 로그인만 꺼짐 → 그 단계 하나만 묻고 PATCH 1회', () async {
    final h = _Harness(root, const <String?>['y']);
    final anonymousOff = RestResponse(
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
    // 지문 없는 홈의 Play Integrity ✗(질문 없음)는 묻는 할 일이 아니다.
    final todoLines = <String>[
      for (final String line in const LineSplitter().convert(h.output))
        if (line.startsWith('  ✗ ') && line != playIntegrityDeferredLine) line,
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
    final noise = 'token=$token key=$apiKey debug=$debugToken';
    final h = _Harness(root, const <String?>[]);
    _registerFinished(h, noise: noise);

    final int code = await h.run();

    expect(code, wizardExitDone);
    for (final text in <String>[h.output, h.log.text]) {
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
      final h = _Harness(root, const <String?>[]);
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
          r'  $ git add .firebaserc functions/src/shared/region.ts '
          '&& git commit -m "$commitHintMessage"',
        ),
      );
      expect(output.indexOf(remainingDoneLine), isNonNegative);
      expect(
        output.indexOf(remainingDoneLine),
        lessThan(output.indexOf(commitHintHeading)),
      );
      final gitKeys = <String>[
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
      final h = _Harness(root, const <String?>[]);
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
        final oldKotlinFile =
            'android/app/src/main/kotlin/'
            '${rename.currentOrg.replaceAll('.', '/')}/'
            '${rename.currentPackageName}/MainActivity.kt';
        const newKotlinFile = '$newKotlinDir/MainActivity.kt';
        final h = _Harness(root, const <String?>[]);
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
            .singleWhere((String line) => line.startsWith(r'  $ git add '));
        expect(addLine, contains(oldKotlinFile));
        expect(addLine, contains(newKotlinFile));
        expect(addLine, contains('.firebaserc'));
        // git 은 저장소 루트에서 실행한다 — 가짜 실행기 키에는 cwd 가 없다.
        final List<FakeCall> gitCalls = h.runner.calls
            .where((FakeCall call) => call.key.startsWith('git '))
            .toList();
        expect(gitCalls, isNotEmpty);
        for (final call in gitCalls) {
          expect(call.workingDirectory, root, reason: call.key);
        }
      },
    );

    test('git 상태를 읽지 못하면 한 줄 안내 · 종료 코드 0 그대로', () async {
      final h = _Harness(root, const <String?>[]);
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
      final runner = FakeCommandRunner()
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

  test(
    'T-20-FLOW-01: --providers 로 Kakao 를 고르면 같은 실행에서 Kakao 키를 받아 네 자리에 쓰고 Kakao 함수까지 배포한다',
    () async {
      final String nativeKey = buildFakeKakaoNativeKey();
      final String adminKey = buildFakeKakaoAdminKey();
      final h = _Harness(root, buildKakaoFirstRunInputs(nativeKey, adminKey));
      // 큐 세기 — Secret Manager 읽기는 이름마다 [다시 짠 점검표 · Kakao 단계 머리
      // 재검사 · 실행 뒤 재검사] 3회(다시 짜기 전 목록에는 Kakao 단계가 없다).
      // functions:list 는 [다시 짜기 전 점검표 · Functions 단계 머리 재검사 ·
      // 배포 뒤 공개 호출 확인 · 실행 뒤 재검사(마지막 응답 반복) · Custom Token
      // 서명 권한 단계 머리 검사(바인딩이 있어 ✓ — 실행 뒤 재검사 없음)] — 다시 짠
      // 점검표에서 Functions 는 Kakao 를, 서명 권한 단계는 Functions 를 기다리는
      // ? 라 부르지 않는다.
      // identity_index 는 소셜 로그인 확인 단계 머리 1회(다시 짠 점검표에서는
      // 실행 단계를 기다리는 ? 라 부르지 않는다).
      _prepareKakaoFirstRun(h, nativeKey: nativeKey, adminKey: adminKey);

      final int code = await h.run(onCompleted: showCompletionSummary);
      final String output = h.output;

      expect(code, wizardExitDone, reason: output);
      final configPath = '$root/${UserFilesStep.jsonUserPath}';
      expect(readJsonString(configPath, enabledProvidersKey), 'kakao');
      expect(readJsonString(configPath, 'kakaoNativeAppKey'), nativeKey);
      expect(
        readXcconfigValue(
          '$root/${UserFilesStep.xcconfigUserPath}',
          'KAKAO_NATIVE_APP_KEY',
        ),
        nativeKey,
      );
      final writes = <FakeCall>[
        for (final FakeCall call in h.runner.calls)
          if (call.key.startsWith('firebase functions:secrets:set ')) call,
      ];
      expect(writes.map((FakeCall call) => call.key), <String>[
        'firebase functions:secrets:set $kakaoNativeSecret --project $projectId --data-file -',
        'firebase functions:secrets:set $kakaoAdminSecret --project $projectId --data-file -',
      ]);
      expect(writes.map((FakeCall call) => call.stdinText), <String>[
        nativeKey,
        adminKey,
      ]);
      expect(writes.every((FakeCall call) => call.isOutputSensitive), isTrue);
      for (final name in <String>[kakaoNativeSecret, kakaoAdminSecret]) {
        expect(
          h.runner.countCalls(
            RunMode.capture,
            FakeCommandRunner.buildKey(buildSecretReadCommand(name, projectId)),
          ),
          3,
          reason: name,
        );
      }
      expect(
        h.runner.countCalls(
          RunMode.capture,
          FakeCommandRunner.buildKey(
            FunctionsStep.buildFunctionsListCommand(projectId),
          ),
        ),
        5,
      );
      expect(h.rest.externalRequests, hasLength(1));
      final ExternalRequest check = h.rest.externalRequests.single;
      expect(check.headers['Authorization'], 'KakaoAK $adminKey');
      expect(check.url.query, isNot(contains(adminKey)));
      expect(check.displayCurl(), contains('KakaoAK <Kakao 어드민 키>'));
      expect(
        h.runner.countCalls(
          RunMode.stream,
          FakeCommandRunner.buildKey(FunctionsStep.buildDeployCommand()),
        ),
        1,
      );
      for (final text in <String>[output, h.log.text]) {
        expect(countText(text, adminKey), 0);
        expect(countText(text, Redactor.mask), greaterThanOrEqualTo(1));
      }
      expect(h.log.text, contains('(비밀 값 32자)'));
      expect(h.screen.secretAsks, hasLength(1));
      expect(h.screen.asks, contains(consoleReadyQuestion));
      expect(h.screen.asks, contains(providerChoiceQuestion));
      final List<String> lines = const LineSplitter().convert(output);
      final checklists = <int>[
        for (int i = 0; i < lines.length; i++)
          if (lines[i] == checklistHeading) i,
      ];
      expect(checklists, hasLength(2));
      expect(output, contains(replanLine));
      expect(
        lines
            .skip(checklists.last)
            .any(
              (String line) => line.startsWith('  ✗ ${KakaoStep.stepTitle} — '),
            ),
        isTrue,
      );
      expect(
        lines
            .take(checklists.last)
            .any((String line) => line.contains(KakaoStep.stepTitle)),
        isFalse,
      );
      expect(output, contains(providersHintLine));
      // 지문을 계산할 수 없는 홈 — Android 쪽 줄만 ✗ 로 끝 목록에 든다.
      expect(
        lines.skip(checklists.last),
        contains(kakaoAndroidUnavailableLine),
      );
      final int remaining = lines.lastIndexOf(remainingHeading);
      expect(remaining, greaterThan(checklists.last));
      expect(lines.skip(remaining + 1), contains(kakaoAndroidUnavailableLine));
    },
  );

  test('T-20-FLOW-02: Kakao 를 켠 저장소를 다시 실행하면 Kakao 질문 · 쓰기가 0 이다', () async {
    final String nativeKey = buildFakeKakaoNativeKey();
    final String adminKey = buildFakeKakaoAdminKey();
    writeKakaoManifest(root);
    // 아이콘 파일이 있으면 앱 아이콘 단계는 질문 없이 ✓ 다(내용은 검사하지 않는다).
    writeFixture(root, findIconSpec('kakao')!.relativePath, 'icon');
    writeFixture(root, '$iconsDirectory/source.png', 'source');
    final configPath = '$root/${UserFilesStep.jsonUserPath}';
    replaceJsonString(configPath, enabledProvidersKey, 'kakao');
    replaceJsonString(configPath, 'kakaoNativeAppKey', nativeKey);
    replaceXcconfigValue(
      '$root/${UserFilesStep.xcconfigUserPath}',
      'KAKAO_NATIVE_APP_KEY',
      nativeKey,
    );
    final h = _Harness(root, const <String?>[]);
    _registerFinished(h, deployedExtra: kakaoFunctions);
    _registerKakaoPolicies(h);
    h.onRest(
      buildIdentityIndexRequest(projectId, basis: SignInBasis.signedIn),
      RestResponse(200, buildKakaoIndexBody()),
    );
    h
      ..onCommand(
        buildSecretReadCommand(kakaoNativeSecret, projectId),
        ok('$nativeKey\n'),
      )
      ..onCommand(
        buildSecretReadCommand(kakaoAdminSecret, projectId),
        ok('$adminKey\n'),
      );

    final int code = await h.run();

    expect(code, wizardExitDone, reason: h.output);
    final List<String> lines = const LineSplitter().convert(h.output);
    expect(
      lines.where((String line) => line.startsWith('  ✓ ')),
      hasLength(22),
    );
    expect(
      lines.where(
        (String line) => line.startsWith('  ✓ ${AppIconStep.stepTitle} — '),
      ),
      hasLength(1),
    );
    expect(
      lines.where(
        (String line) =>
            line.startsWith('  ✓ ${TokenCreatorStep.stepTitle} — '),
      ),
      hasLength(1),
    );
    expect(
      lines.where(
        (String line) => line.startsWith('  ✓ ${KakaoStep.stepTitle} — '),
      ),
      hasLength(1),
    );
    expect(h.output, isNot(contains(replanLine)));
    expect(h.screen.asks, isEmpty);
    expect(h.screen.secretAsks, isEmpty);
    expect(
      h.runner.calls.where(
        (FakeCall call) =>
            call.key.startsWith('firebase functions:secrets:set'),
      ),
      isEmpty,
    );
    expect(h.rest.externalRequests, isEmpty);
    expect(h.runner.countMode(RunMode.stream), 0);
    expect(countWriteRequests(h.rest), 0);
    // 지문을 계산할 수 없는 홈 — 점검표 · 끝 목록의 Android 쪽 ✗ 줄 하나씩.
    expect(
      lines.where((String line) => line == kakaoAndroidUnavailableLine),
      hasLength(2),
    );
    final int remaining = lines.indexOf(remainingHeading);
    expect(remaining, greaterThan(lines.indexOf(kakaoAndroidUnavailableLine)));
    expect(lines[remaining + 1], kakaoAndroidUnavailableLine);
    expect(lines, isNot(contains(allDoneLine)));
  });

  test(
    'T-20-FLOW-03: Kakao 를 고른 첫 실행이 함수 배포 뒤 런타임 서비스 계정에 Token Creator 를 붙이고 ✓ 로 끝난다',
    () async {
      final String nativeKey = buildFakeKakaoNativeKey();
      final String adminKey = buildFakeKakaoAdminKey();
      final h = _Harness(root, <String?>[
        ...buildKakaoFirstRunInputs(nativeKey, adminKey),
        'y', // Custom Token 서명 권한 단계
      ]);
      _prepareKakaoFirstRun(
        h,
        nativeKey: nativeKey,
        adminKey: adminKey,
        tokenCreatorPolicies: <CommandResult>[
          buildEmptyServiceAccountPolicyResult(),
          buildTokenCreatorPolicyResult(),
        ],
      );
      final String account = buildFakeRuntimeServiceAccount();
      final Command grant = TokenCreatorStep.buildGrantCommand(
        account,
        projectId,
      );
      h.onCommand(
        grant,
        ok('Updated IAM policy for serviceAccount [$account].\n'),
      );

      final int code = await h.run(onCompleted: showCompletionSummary);
      final String output = h.output;

      expect(code, wizardExitDone, reason: output);
      final configPath = '$root/${UserFilesStep.jsonUserPath}';
      expect(readJsonString(configPath, enabledProvidersKey), 'kakao');
      expect(readJsonString(configPath, 'kakaoNativeAppKey'), nativeKey);
      for (final name in <String>[kakaoNativeSecret, kakaoAdminSecret]) {
        expect(
          h.runner.countCalls(
            RunMode.capture,
            FakeCommandRunner.buildKey(buildSecretReadCommand(name, projectId)),
          ),
          3,
          reason: name,
        );
      }
      expect(h.rest.externalRequests, hasLength(1));
      expect(
        h.runner.countCalls(
          RunMode.stream,
          FakeCommandRunner.buildKey(FunctionsStep.buildDeployCommand()),
        ),
        1,
      );
      final List<String> lines = const LineSplitter().convert(output);
      expect(
        lines.where((String line) => line == checklistHeading),
        hasLength(2),
      );
      final int deployed = lines.indexWhere(
        (String line) =>
            line.startsWith('  \$ bash ${FunctionsStep.deployScriptPath}'),
      );
      final int header = lines.indexOf('▶ ${TokenCreatorStep.stepTitle}');
      expect(deployed, greaterThanOrEqualTo(0));
      expect(header, greaterThan(deployed));
      expect(
        lines.where(
          (String line) =>
              line.startsWith('  ✓ ${TokenCreatorStep.stepTitle} — '),
        ),
        hasLength(1),
      );
      expect(
        h.runner.countCalls(
          RunMode.capture,
          FakeCommandRunner.buildKey(
            FunctionsStep.buildFunctionsListCommand(projectId),
          ),
        ),
        6,
      );
      for (final String function in kakaoFunctions) {
        expect(
          h.runner.countCalls(
            RunMode.capture,
            FakeCommandRunner.buildKey(
              TokenCreatorStep.buildServiceAccountCommand(
                buildServiceId(function),
                region,
                projectId,
              ),
            ),
          ),
          2,
          reason: function,
        );
      }
      expect(
        h.runner.countCalls(
          RunMode.capture,
          FakeCommandRunner.buildKey(
            TokenCreatorStep.buildPolicyCommand(account, projectId),
          ),
        ),
        2,
      );
      expect(
        h.runner.countCalls(RunMode.stream, FakeCommandRunner.buildKey(grant)),
        1,
      );
      expect(h.runner.countMode(RunMode.stream), 2);
    },
  );

  test(
    'T-20.1-WIRE-01: 아이콘 대상을 켰을 때만 로그인 수단 단계 바로 다음에 앱 아이콘 단계가 한 번 있고 flavor 마다 같다',
    () {
      const allProviders = <String>{
        'google',
        'apple',
        'facebook',
        'kakao',
        'naver',
        'line',
      };
      for (final Flavor flavor in Flavor.values) {
        List<Step> build(Set<String> enabled) =>
            buildSteps(flavor: flavor, enabledProviders: enabled);
        List<String> listIds(List<Step> steps) => <String>[
          for (final Step step in steps) step.id,
        ];

        final List<String> kakao = listIds(build(<String>{'kakao'}));
        expect(
          kakao.indexOf(AppIconStep.stepId),
          kakao.indexOf('providers') + 1,
          reason: '$flavor',
        );

        final List<String> googleKakao = listIds(
          build(<String>{'google', 'kakao'}),
        );
        final int start = googleKakao.indexOf('providers');
        expect(googleKakao.sublist(start, start + 3), <String>[
          'providers',
          AppIconStep.stepId,
          'google',
        ], reason: '$flavor');

        final List<Step> all = build(allProviders);
        expect(
          listIds(all).where((String id) => id == AppIconStep.stepId),
          hasLength(1),
          reason: '$flavor',
        );
        final AppIconStep icon = all.whereType<AppIconStep>().single;
        expect(icon.targets.map((IconSpec spec) => spec.token), <String>[
          'google',
          'facebook',
          'kakao',
          'naver',
          'line',
        ], reason: '$flavor');
        // 미뤄도 뒤 단계가 기다리지 않는다 — 어떤 단계도 앱 아이콘을 기다리지 않는다.
        expect(
          all.where((Step step) => step.dependsOn.contains(AppIconStep.stepId)),
          isEmpty,
          reason: '$flavor',
        );

        expect(
          build(<String>{'google', 'kakao'})
              .whereType<AppIconStep>()
              .single
              .targets
              .map((IconSpec spec) => spec.token),
          <String>['google', 'kakao'],
          reason: '$flavor',
        );
        expect(
          listIds(build(<String>{})),
          isNot(contains(AppIconStep.stepId)),
          reason: '$flavor',
        );
        expect(
          listIds(build(<String>{'apple'})),
          isNot(contains(AppIconStep.stepId)),
          reason: '$flavor',
        );
      }
    },
  );

  test(
    'T-20.1-WIRE-02: --providers 로 Kakao 를 고른 같은 실행에서 끌어다 놓은 원본으로 앱 아이콘을 만들고 Kakao 값 표가 그 경로를 보인 뒤 배포까지 간다',
    () async {
      final String nativeKey = buildFakeKakaoNativeKey();
      final String adminKey = buildFakeKakaoAdminKey();
      // 저장소 밖 원본 — 이름에 공백이 있어 Terminal 끌어다 놓기는 백슬래시를 붙인다.
      final Directory sourceDir = Directory.systemTemp.createTempSync(
        'wizard_icon_source_',
      );
      addTearDown(() {
        if (sourceDir.existsSync()) sourceDir.deleteSync(recursive: true);
      });
      final sourcePath = '${sourceDir.path}/my icon.png';
      File(sourcePath).writeAsBytesSync(_buildFakeIconBytes(64));
      final h = _Harness(root, <String?>[
        'y', // 로그인 수단 단계
        '4', // 체크 목록 — Kakao
        'y', // 값 표
        '1', // 앱 아이콘 — 진행
        '${sourceDir.path}/my\\ icon.png ', // 원본 — 끌어다 놓은 모양
        'y', // Kakao 단계(다시 짠 뒤)
        '1', // 콘솔에서 키를 받았다
        nativeKey,
        adminKey,
        'y', // Functions 단계
      ]);
      _prepareKakaoFirstRun(h, nativeKey: nativeKey, adminKey: adminKey);
      final IconSpec kakaoSpec = findIconSpec('kakao')!;
      final outputPath = '$root/${kakaoSpec.relativePath}';
      final Command resize = AppIconStep.buildResizeCommand(
        root,
        'source.png',
        kakaoSpec,
      );
      final Command open = AppIconStep.buildOpenCommand(root);
      h
        ..onCommand(
          AppIconStep.buildProbeCommand(sourcePath),
          _buildIconProbeResult(sourcePath, 1024),
        )
        ..onCommand(resize, ok())
        ..onCommand(
          AppIconStep.buildProbeCommand(outputPath),
          _buildIconProbeResult(outputPath, kakaoSpec.side),
        )
        ..onCommand(open, ok());
      h.runner.onEffect(
        FakeCommandRunner.buildKey(resize),
        () => File(outputPath).writeAsBytesSync(_buildFakeIconBytes(32)),
      );

      final int code = await h.run(onCompleted: showCompletionSummary);
      final String output = h.output;

      expect(code, wizardExitDone, reason: output);
      expect(File(outputPath).existsSync(), isTrue);
      expect(File('$root/$iconsDirectory/source.png').existsSync(), isTrue);
      final List<String> lines = const LineSplitter().convert(output);
      expect(
        lines,
        contains('  ✓ 앱 아이콘 — Kakao 용 1개 · 바꾸려면 .setup/icons 를 지우고 다시 실행'),
      );
      final int iconHeader = lines.indexOf('▶ ${AppIconStep.stepTitle}');
      expect(iconHeader, greaterThanOrEqualTo(0));
      expect(iconHeader, lessThan(lines.indexOf('▶ ${KakaoStep.stepTitle}')));
      final List<String> rows = collectSummaryRows(
        lines,
        '── Kakao 콘솔에 넣을 값 — dev ──',
      );
      expect(rows, isNotEmpty);
      expect(rows.last, contains(kakaoSpec.rowLabel));
      expect(rows.last, contains(kakaoSpec.relativePath));
      expect(kakaoSpec.rowLabel, '앱 아이콘 올리기 · 선택');
      for (final streamed in <Command>[
        resize,
        open,
        FunctionsStep.buildDeployCommand(),
      ]) {
        expect(
          h.runner.countCalls(
            RunMode.stream,
            FakeCommandRunner.buildKey(streamed),
          ),
          1,
          reason: streamed.render(),
        );
      }
      final configPath = '$root/${UserFilesStep.jsonUserPath}';
      expect(readJsonString(configPath, enabledProvidersKey), 'kakao');
      expect(readJsonString(configPath, 'kakaoNativeAppKey'), nativeKey);
    },
  );
}
