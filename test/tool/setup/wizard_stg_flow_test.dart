import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:test/test.dart';

import '../../../bin/rename.dart' as rename;
import '../../../tool/setup/command_runner.dart';
import '../../../tool/setup/completion.dart';
import '../../../tool/setup/config_files.dart';
import '../../../tool/setup/flavor.dart';
import '../../../tool/setup/providers/icon_specs.dart';
import '../../../tool/setup/providers/keyed_provider_step.dart';
import '../../../tool/setup/providers/provider_catalog.dart';
import '../../../tool/setup/providers/provider_selection.dart';
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
import '../../../tool/setup/steps/user_files_step.dart';
import '../../../tool/setup/terminal.dart';
import '../../../tool/setup/uuid.dart';
import '../../../tool/setup/wizard.dart';
import 'fake_rest_client.dart';
import 'fakes.dart';
import 'firebase_options_fixture.dart';

/// dev 실행이 앱 정체성 단계에 넣은 org.
const String newOrg = 'com.acme';

/// dev 실행이 앱 정체성 단계에 넣은 name.
const String newName = 'my_app';

/// dev 실행이 만든 Firebase 프로젝트 ID.
const String devProjectId = 'my-app-dev';

/// stg 실행이 만드는 Firebase 프로젝트 ID — configure 스크립트 prefix + `-stg`.
const String stgProjectId = 'my-app-stg';

/// 기본 Functions 리전(example config 의 값).
const String region = 'asia-northeast3';

/// 앱 정체성 뒤 Android 앱 ID.
const String newApplicationId = '$newOrg.$newName';

/// 앱 정체성 뒤 dev iOS 번들 ID.
const String devBundleId = '$newOrg.myApp.dev';

/// 앱 정체성 뒤 stg iOS 번들 ID.
const String stgBundleId = '$newOrg.myApp.stg';

/// 앱 정체성 뒤 stg Android 패키지.
const String stgPackageName = '$newApplicationId.stg';

/// 가짜 dev iOS Firebase 앱 ID.
const String devIosAppId = '1:222222222222:ios:cccccccccccccccc';

/// 가짜 dev Android Firebase 앱 ID.
const String devAndroidAppId = '1:222222222222:android:dddddddddddddddd';

/// 가짜 stg iOS Firebase 앱 ID.
const String stgIosAppId = '1:333333333333:ios:eeeeeeeeeeeeeeee';

/// 가짜 stg Android Firebase 앱 ID.
const String stgAndroidAppId = '1:333333333333:android:ffffffffffffffff';

/// 가짜 로그인 계정.
const String accountEmail = 'stg-flow@example.invalid';

/// 가짜 공통 함수 목록.
const List<String> commonFunctions = <String>['ping', 'echo'];

/// 가짜 functions 소스가 선언하는 secret.
const String declaredSecret = 'KIT_SAMPLE_SECRET';

/// 가짜 Firestore rules 원문.
const String firestoreRules =
    "rules_version = '2';\nservice cloud.firestore {}\n";

/// 가짜 Storage rules 원문.
const String storageRules =
    "rules_version = '2';\nservice firebase.storage {}\n";

/// stg 실행이 등록하는 디버그 토큰 표시 이름.
const String stgTokenName = 'setup-wizard-stg';

/// 가짜 시뮬레이터 ID.
const String simulatorId = '0A1B2C3D-4E5F-4A6B-8C7D-9E0F1A2B3C4D';

/// 가짜 결제 계정 ID.
const String billingAccountId = '000000-AAAAAA-BBBBBB';

/// 실제 저장소와 같은 꼴의 fixture `.gitignore` — 모든 flavor 의 사용자 파일을
/// 무시하고 stg · prod Android 설정 파일 자리표시만 추적한다.
const String fixtureGitignore =
    'config/*.json\n'
    '!config/*.example.json\n'
    'ios/Flutter/dev.xcconfig\n'
    'ios/Flutter/stg.xcconfig\n'
    'ios/Flutter/prod.xcconfig\n'
    '**/android/app/src/*/google-services.json\n'
    '!**/android/app/src/stg/google-services.json\n'
    '!**/android/app/src/prod/google-services.json\n'
    'functions/node_modules/\n'
    '.setup/\n';

/// 옛 Kotlin 패키지 디렉터리 — 킷 기본 식별자는 rename 상수로만 만든다.
final String oldKotlinDir =
    'android/app/src/main/kotlin/'
    '${rename.currentOrg.replaceAll('.', '/')}/${rename.currentPackageName}';

/// 실행 시점에 조립하는 가짜 액세스 토큰 — 리터럴로 두지 않는다.
String buildFakeAccessToken() => 'ya29.${'C' * 40}';

/// 실행 시점에 조립하는 가짜 API 키 — 리터럴로 두지 않는다.
String buildFakeApiKey() => 'AIza${'z' * 35}';

/// fixture 저장소 하나 — 임시 디렉터리 · 임시 홈 · 호스트 설정과 뗀 git 환경.
final class _Fixture {
  _Fixture()
    : repo = Directory.systemTemp.createTempSync('wizard_stg_repo_'),
      home = Directory.systemTemp.createTempSync('wizard_stg_home_') {
    Directory('${home.path}/.config').createSync(recursive: true);
    environment = <String, String>{
      for (final MapEntry<String, String> entry in Platform.environment.entries)
        if (!entry.key.startsWith('GIT_')) entry.key: entry.value,
      'HOME': home.path,
      'XDG_CONFIG_HOME': '${home.path}/.config',
      'GIT_CONFIG_GLOBAL': '/dev/null',
      'GIT_CONFIG_NOSYSTEM': '1',
      'GIT_ATTR_NOSYSTEM': '1',
    };
  }

  /// fixture 저장소 디렉터리.
  final Directory repo;

  /// fixture 와 떨어진 임시 홈(그 아래 `.config`).
  final Directory home;

  /// git 실행 환경 — 부모의 `GIT_*` 를 빼고 사용자 · 시스템 설정을 끈다.
  late final Map<String, String> environment;

  /// 저장소 루트 경로.
  String get root => repo.path;

  /// [path] 가 fixture 저장소 안(루트 포함)이면 true.
  bool contains(String path) => path == root || path.startsWith('$root/');

  /// fixture 저장소에서 실제 git 을 실행한다 — fixture 밖이면 [StateError].
  ProcessResult runGit(List<String> arguments, {String? workingDirectory}) {
    final String directory = workingDirectory ?? root;
    if (!contains(directory)) {
      throw StateError('fixture 밖에서 git 을 실행하려 했습니다: $directory');
    }
    return Process.runSync(
      'git',
      arguments,
      workingDirectory: directory,
      environment: environment,
      includeParentEnvironment: false,
    );
  }

  /// 실제 git 을 실행하고 실패면 [StateError] 로 알린다.
  String runGitChecked(List<String> arguments) {
    final ProcessResult result = runGit(arguments);
    if (result.exitCode != 0) {
      throw StateError('git ${arguments.join(' ')} 실패: ${result.stderr}');
    }
    return result.stdout as String;
  }

  /// 작업 트리 전체를 스테이징해 [message] 로 커밋한다(호스트 설정 · 훅 없음).
  void commitAll(String message) {
    runGitChecked(<String>['add', '--all']);
    runGitChecked(<String>[
      '-c',
      'user.name=fixture',
      '-c',
      'user.email=fixture@example.invalid',
      '-c',
      'commit.gpgsign=false',
      '-c',
      'core.hooksPath=/dev/null',
      'commit',
      '-q',
      '-m',
      message,
    ]);
  }

  /// 저장소 상대 경로에 내용을 쓴다(부모 디렉터리를 만든다).
  void write(String relativePath, String content) {
    File('$root/$relativePath')
      ..parent.createSync(recursive: true)
      ..writeAsStringSync(content);
  }

  /// 저장소 상대 경로의 내용을 읽는다.
  String read(String relativePath) =>
      File('$root/$relativePath').readAsStringSync();

  /// 저장소 상대 경로의 바이트를 읽는다.
  List<int> readBytes(String relativePath) =>
      File('$root/$relativePath').readAsBytesSync();

  /// 실제 git 의 짧은 상태 줄.
  List<String> readStatus() => const LineSplitter().convert(
    runGitChecked(<String>['status', '--porcelain']),
  );

  /// 두 임시 디렉터리를 지운다.
  void delete() {
    for (final directory in <Directory>[repo, home]) {
      if (directory.existsSync()) directory.deleteSync(recursive: true);
    }
  }
}

/// [flavor] 의 앱 설정 파일 3개를 configure 스크립트가 쓴 실 값 모양으로 쓴다.
void _writeAppFiles(
  _Fixture fixture,
  Flavor flavor, {
  required String projectId,
  required String bundleId,
  required String packageName,
  required String iosAppId,
  required String androidAppId,
}) {
  final String apiKey = buildFakeApiKey();
  final paths = FlavorPaths(flavor);
  fixture
    ..write(
      paths.dartOptions,
      buildGeneratedOptionsSource(
        projectId: projectId,
        apiKey: apiKey,
        androidAppId: androidAppId,
        iosAppId: iosAppId,
        iosBundleId: bundleId,
      ),
    )
    ..write(
      paths.iosPlist,
      '<plist><dict>\n'
      '<key>API_KEY</key>\n<string>$apiKey</string>\n'
      '<key>PROJECT_ID</key>\n<string>$projectId</string>\n'
      '<key>BUNDLE_ID</key>\n<string>$bundleId</string>\n'
      '<key>GOOGLE_APP_ID</key>\n<string>$iosAppId</string>\n'
      '</dict></plist>\n',
    )
    ..write(
      paths.androidJson,
      jsonEncode(<String, Object?>{
        'project_info': <String, Object?>{'project_id': projectId},
        'client': <Object?>[
          <String, Object?>{
            'client_info': <String, Object?>{
              'mobilesdk_app_id': androidAppId,
              'android_client_info': <String, Object?>{
                'package_name': packageName,
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

/// 킷 기본 모양의 저장소를 쓰고 초기 커밋한 뒤, dev 실행이 끝까지 간 상태를
/// 만들어 커밋한다.
///
/// dev 의 앱 정체성은 위저드 앱 정체성 단계가 부르는 rename 함수를 그대로 불러
/// 바꾼다. dev 사용자 파일(config · xcconfig · Android 설정 파일)은 gitignored
/// 이고, 추적되는 dev 설정 파일 두 개는 configure 스크립트처럼 skip-worktree 로
/// 커밋 대상에서 뺀다. dev config 는 Google · Kakao 를 켠 값이다.
void _writeDevFinishedFixture(_Fixture fixture) {
  const devPaths = FlavorPaths(Flavor.dev);
  const stgPaths = FlavorPaths(Flavor.stg);
  // 저장소에 추적되는 example 4개 · stg 자리표시 설정 파일 3개는 그대로 복사한다.
  for (final path in <String>[
    devPaths.jsonExample,
    devPaths.xcconfigExample,
    stgPaths.jsonExample,
    stgPaths.xcconfigExample,
    stgPaths.dartOptions,
    stgPaths.iosPlist,
    stgPaths.androidJson,
  ]) {
    fixture.write(path, File(path).readAsStringSync());
  }
  fixture
    ..write('.gitignore', fixtureGitignore)
    ..write(
      IdentityStep.gradlePath,
      'android {\n'
      '    namespace = "${rename.currentAndroidPackage}"\n'
      '    defaultConfig {\n'
      '        applicationId = "${rename.currentAndroidPackage}"\n'
      '    }\n'
      '    productFlavors {\n'
      '        create("dev") { applicationIdSuffix = ".dev" }\n'
      '        create("stg") { applicationIdSuffix = ".stg" }\n'
      '        create("prod") { }\n'
      '    }\n'
      '}\n',
    )
    ..write(
      '$oldKotlinDir/MainActivity.kt',
      'package ${rename.currentAndroidPackage}\n\nclass MainActivity\n',
    )
    ..write(
      ConfigureStep.pbxprojPath,
      '// !\$*UTF8*\$!\n'
      '{\n'
      '\t\t\t\tPRODUCT_BUNDLE_IDENTIFIER = ${rename.currentIosBundleId}.dev;\n'
      '\t\t\t\tPRODUCT_BUNDLE_IDENTIFIER = ${rename.currentIosBundleId}.dev;\n'
      '\t\t\t\tPRODUCT_BUNDLE_IDENTIFIER = ${rename.currentIosBundleId}.dev;\n'
      '\t\t\t\tPRODUCT_BUNDLE_IDENTIFIER = '
      '${rename.currentIosBundleId}.RunnerTests;\n'
      '}\n',
    )
    ..write(
      FirebaseProjectStep.configureScriptPath,
      '#!/usr/bin/env bash\n'
      'PROJECT_ID_PREFIX="${rename.currentProjectIdPrefix}"\n'
      'IOS_BUNDLE_ID_PREFIX="${rename.currentIosBundleId}"\n'
      'ANDROID_PACKAGE_PREFIX="${rename.currentAndroidPackage}"\n',
    )
    ..write(
      devPaths.dartOptions,
      '// placeholder-dev\n'
      "throw UnsupportedError('configure 를 먼저 실행하세요');\n",
    )
    ..write(
      devPaths.iosPlist,
      '<!-- placeholder-dev -->\n<plist><dict>\n'
      '<key>BUNDLE_ID</key>\n'
      '<string>${rename.currentIosBundleId}.dev</string>\n'
      '</dict></plist>\n',
    )
    ..write(ConfigureStep.firebaseJsonPath, '{"flutter":{"platforms":{}}}\n')
    ..write(
      FirebaseProjectStep.firebasercPath,
      '${jsonEncode(<String, Object?>{
        'projects': <String, String>{'default': '${rename.currentProjectIdPrefix}-dev', 'dev': '${rename.currentProjectIdPrefix}-dev'},
      })}\n',
    )
    ..write(FirestoreStep.regionTsPath, 'export const REGION = "$region";\n')
    ..write(
      FirestoreStep.appConfigPath,
      'abstract final class AppConfig {\n'
      "  static const String defaultFunctionsRegion = '$region';\n"
      '}\n',
    )
    ..write(RulesStep.firestoreRulesPath, firestoreRules)
    ..write(RulesStep.storageRulesPath, storageRules)
    ..write(
      FunctionsStep.manifestPath,
      '${jsonEncode(<String, Object?>{'common': commonFunctions})}\n',
    )
    ..write(
      'functions/src/index.ts',
      'const kitSecret = defineSecret("$declaredSecret");\n',
    )
    ..runGitChecked(<String>['init', '-q'])
    ..commitAll('init');

  // dev 실행이 끝난 상태 — 사용자 파일 · 앱 정체성 · 프로젝트 · 설정 파일 · 의존성.
  fixture
    ..write(devPaths.json, fixture.read(devPaths.jsonExample))
    ..write(devPaths.xcconfig, fixture.read(devPaths.xcconfigExample));
  rename.applyChanges(rename.collectChanges(fixture.root, newOrg, newName));
  final devConfig = '${fixture.root}/${devPaths.json}';
  replaceJsonString(devConfig, FirebaseProjectStep.projectIdKey, devProjectId);
  replaceJsonString(devConfig, enabledProvidersKey, 'google,kakao');
  replaceJsonString(
    devConfig,
    AppCheckStep.tokenKey,
    generateUuidV4(Random(5)),
  );
  _writeAppFiles(
    fixture,
    Flavor.dev,
    projectId: devProjectId,
    bundleId: devBundleId,
    packageName: '$newApplicationId.dev',
    iosAppId: devIosAppId,
    androidAppId: devAndroidAppId,
  );
  fixture
    ..write(
      FirebaseProjectStep.firebasercPath,
      '${jsonEncode(<String, Object?>{
        'projects': <String, String>{'default': devProjectId, 'dev': devProjectId},
      })}\n',
    )
    ..write(FunctionsStep.modulesMarkerPath, '')
    ..runGitChecked(<String>[
      'update-index',
      '--skip-worktree',
      devPaths.dartOptions,
      devPaths.iosPlist,
    ])
    ..commitAll('dev');
}

/// 실행기 — 실행 파일이 git 이면 fixture 의 실제 git, 그 밖은 가짜 실행기에 넘긴다.
///
/// 실제 실행기처럼 실행 기록 · 화면에 쓰고, 명령 키별 효과 콜백을 실행 순간에
/// 부른다. git 은 작업 디렉터리가 fixture 안일 때만 실행한다.
final class _FlowRunner implements CommandRunner {
  _FlowRunner(this.fixture, this.fake, this.terminal, this.log);

  final _Fixture fixture;
  final FakeCommandRunner fake;
  final Terminal terminal;
  final MemoryLogSink log;

  /// 명령 키 → 실행 순간 부를 효과.
  final Map<String, void Function()> effects = <String, void Function()>{};

  /// 실제 git 으로 실행한 명령 키(순서대로).
  final List<String> gitKeys = <String>[];

  Future<CommandResult> _execute(RunMode mode, Command command) async {
    final String key = FakeCommandRunner.buildKey(command);
    if (command.executable == 'git') {
      final String? directory = command.workingDirectory;
      if (directory == null || !fixture.contains(directory)) {
        throw StateError('fixture 밖 git 실행: $key');
      }
      gitKeys.add(key);
      final ProcessResult result = fixture.runGit(
        command.arguments,
        workingDirectory: directory,
      );
      return CommandResult(
        result.exitCode,
        result.stdout as String,
        result.stderr as String,
      );
    }
    effects[key]?.call();
    return await switch (mode) {
      RunMode.capture => fake.capture(command),
      RunMode.stream => fake.stream(command),
      RunMode.interactive => CommandResult(
        await fake.interactive(command),
        '',
        '',
      ),
    };
  }

  @override
  Future<CommandResult> capture(Command command) async {
    log.write('cmd', command.render());
    final CommandResult result = await _execute(RunMode.capture, command);
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
    final CommandResult result = await _execute(RunMode.interactive, command);
    log.write('exit', '${result.exitCode}');
    return result.exitCode;
  }

  @override
  Future<CommandResult> stream(Command command) async {
    terminal.writeCommand(command.render());
    log.write('cmd', command.render());
    final CommandResult result = await _execute(RunMode.stream, command);
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
    _record(request.method, request.url, request.isResponseSensitive, response);
    return response;
  }

  @override
  Future<RestResponse> sendExternal(ExternalRequest request) async {
    final RestResponse response = await inner.sendExternal(request);
    _record(request.method, request.url, request.isResponseSensitive, response);
    return response;
  }

  /// 요청 줄과 응답(민감 응답이면 생략 표시)을 기록에 남긴다.
  void _record(
    String method,
    Uri url,
    bool isResponseSensitive,
    RestResponse response,
  ) {
    log.write('rest', '$method $url → ${response.statusCode}');
    if (response.body.isEmpty) return;
    log.write(
      'rest',
      isResponseSensitive
          ? HttpRestClient.sensitiveResponseNotice
          : response.body,
    );
  }
}

/// `--flavor stg` 위저드 한 번 실행 묶음 — 실제 진입점처럼 config 의 로그인
/// 수단으로 단계 목록을 만들고, 로그인 수단이 바뀌면 다시 만든다.
final class _Run {
  _Run(this.fixture, List<String?> inputs)
    : fake = FakeCommandRunner(),
      rest = FakeRestClient(),
      screen = ScriptedTerminal(inputs),
      log = MemoryLogSink(Redactor()) {
    terminal = RedactingTerminal(screen, log.redactor, log);
    runner = _FlowRunner(fixture, fake, terminal, log);
    context = WizardContext(
      projectRoot: fixture.root,
      runner: runner,
      terminal: terminal,
      redactor: log.redactor,
      log: log,
      rest: _LoggingRest(rest, log),
      flavor: Flavor.stg,
      homeDirectory: noKeystoreTestHome,
      random: Random(fixedTestRandomSeed),
      now: () => fixedTestNow,
    );
  }

  final _Fixture fixture;
  final FakeCommandRunner fake;
  final FakeRestClient rest;
  final ScriptedTerminal screen;
  final MemoryLogSink log;
  late final RedactingTerminal terminal;
  late final _FlowRunner runner;
  late final WizardContext context;

  /// 앱 등록 스크립트가 실행되는 순간의 `.firebaserc` git 상태 줄.
  final List<String> firebasercStatusAtConfigure = <String>[];

  /// 화면 출력 전체.
  String get output => screen.output.toString();

  /// [key] 의 결과 큐에 [results] 를 차례로 더한다.
  void on(String key, List<CommandResult> results) {
    for (final result in results) {
      fake.on(key, result);
    }
  }

  /// [command] 의 결과 큐에 [results] 를 차례로 더한다.
  void onCommand(Command command, List<CommandResult> results) =>
      on(FakeCommandRunner.buildKey(command), results);

  /// [request] 의 응답 큐에 [responses] 를 차례로 더한다.
  void onRest(RestRequest request, List<RestResponse> responses) {
    for (final response in responses) {
      rest.on(request.method, request.url.toString(), response);
    }
  }

  /// [command] 실행 순간에 [effect] 를 부른다.
  void onEffect(Command command, void Function() effect) =>
      runner.effects[FakeCommandRunner.buildKey(command)] = effect;

  /// 지금 stg config 의 로그인 수단으로 단계 목록을 만든다.
  List<Step> buildCurrentSteps() => buildSteps(
    flavor: Flavor.stg,
    enabledProviders: readEnabledProviders(context.resolve(context.paths.json)),
  );

  /// 실제 진입점과 같은 배선(끝 요약 · 단계 목록 다시 만들기)으로 돌린다.
  Future<int> run() => runWizard(
    context,
    buildCurrentSteps(),
    onCompleted: showCompletionSummary,
    rebuildSteps: buildCurrentSteps,
  );

  /// 진행 질문 수를 센다.
  int countStepQuestions() => screen.asks
      .where((String question) => question == stepConfirmQuestion)
      .length;

  /// 쓰기 REST 요청(POST · PATCH · DELETE) 수를 센다.
  int countWriteRequests() => rest.requests
      .where((RestRequest request) => request.method != 'GET')
      .length;
}

/// 성공 결과.
CommandResult ok([String stdout = '']) => CommandResult(0, stdout, '');

/// 실패 결과.
CommandResult fail([String stderr = '']) => CommandResult(1, '', stderr);

/// ruleset 응답 본문.
String buildRulesetBody(String content) => jsonEncode(<String, Object?>{
  'source': <String, Object?>{
    'files': <Object?>[
      <String, Object?>{'name': 'rules', 'content': content},
    ],
  },
});

/// 내 계정의 Firebase 프로젝트 목록 응답 — dev 프로젝트와 [hasStg] 면 stg 프로젝트.
CommandResult buildProjectsList({required bool hasStg}) => ok(
  jsonEncode(<String, Object?>{
    'status': 'success',
    'result': <Object?>[
      <String, Object?>{'projectId': devProjectId, 'displayName': devProjectId},
      if (hasStg)
        <String, Object?>{
          'projectId': stgProjectId,
          'displayName': stgProjectId,
        },
    ],
  }),
);

/// 앞 단계(Xcode · 도구 · 로그인)를 끝난 상태로 등록한다 — dev 실행이 이미 끝냈다.
void _registerEarlySteps(_Run run) {
  final CommandResult account = ok(
    jsonEncode(<String, Object?>{
      'status': 'success',
      'result': <Object?>[
        <String, Object?>{
          'user': <String, Object?>{'email': accountEmail},
        },
      ],
    }),
  );
  run
    ..on('xcode-select -p', <CommandResult>[
      ok('/Applications/Xcode.app/Contents/Developer\n'),
    ])
    ..on('xcodebuild -license check', <CommandResult>[ok()])
    ..on('xcodebuild -checkFirstLaunchStatus', <CommandResult>[ok()])
    ..on('xcrun simctl list runtimes -j', <CommandResult>[
      ok('{"runtimes":[{"platform":"iOS","isAvailable":true}]}'),
    ])
    ..on('node --version', <CommandResult>[ok('v22.11.0\n')])
    ..on('pnpm --version', <CommandResult>[ok('10.4.1\n')])
    ..on('firebase --version', <CommandResult>[ok('15.29.0\n')])
    ..on('gcloud --version', <CommandResult>[ok('Google Cloud SDK 540.0.0\n')])
    ..on('jq --version', <CommandResult>[ok('jq-1.7.1\n')])
    ..on('brew --prefix', <CommandResult>[ok('brew-prefix\n')])
    ..on("ruby -e require 'xcodeproj'", <CommandResult>[ok()])
    ..on('fvm dart pub global list', <CommandResult>[
      ok('flutterfire_cli 1.3.1\n'),
    ])
    ..onCommand(LoginStep.firebaseAccountsCommand, <CommandResult>[account])
    ..onCommand(AccessTokenSource.tokenCommand, <CommandResult>[
      ok('${buildFakeAccessToken()}\n'),
    ])
    ..onCommand(LoginStep.gcloudAccountCommand, <CommandResult>[
      ok('$accountEmail\n'),
    ]);
}

/// 프로젝트 ~ 로그인 수단(이메일 · 익명) 단계를 stg 프로젝트 기준으로 등록한다.
///
/// [isResumed] 면 이미 끝난 상태, 아니면 「처음 할 일 → 실행 → 끝남」 순서다.
void _registerCloudSteps(_Run run, {required bool isResumed}) {
  const firestoreMissing = CommandResult(
    1,
    '',
    'ERROR: NOT_FOUND: database does not exist',
  );
  final bucket = RestResponse(
    200,
    jsonEncode(<String, Object?>{
      'location': region,
      'bucket': <String, Object?>{
        'name':
            'projects/$stgProjectId/buckets/$stgProjectId.firebasestorage.app',
      },
    }),
  );
  const signInEnabled = RestResponse(
    200,
    '{"signIn":{"email":{"enabled":true,"passwordRequired":true},'
    '"anonymous":{"enabled":true}}}',
  );
  run
    ..onCommand(
      FirebaseProjectStep.buildDescribeCommand(stgProjectId),
      isResumed
          ? <CommandResult>[ok('$stgProjectId\n')]
          : <CommandResult>[fail('NOT_FOUND')],
    )
    ..onCommand(
      FirebaseProjectStep.buildCreateCommand(stgProjectId),
      <CommandResult>[ok()],
    )
    ..onCommand(
      FirebaseProjectStep.buildAddFirebaseCommand(stgProjectId),
      <CommandResult>[ok()],
    )
    ..onCommand(FirebaseProjectStep.projectsListCommand, <CommandResult>[
      buildProjectsList(hasStg: true),
    ])
    ..onCommand(
      BillingStep.billingInfoCommand(stgProjectId),
      isResumed
          ? <CommandResult>[ok('{"billingEnabled":true}')]
          : <CommandResult>[
              ok('{"billingEnabled":false}'),
              ok('{"billingEnabled":true}'),
            ],
    )
    ..onCommand(BillingStep.openAccountsCommand, <CommandResult>[
      ok(
        '[{"name":"billingAccounts/$billingAccountId",'
        '"displayName":"Kit Billing","open":true}]',
      ),
    ])
    ..onCommand(
      BillingStep.buildLinkCommand(stgProjectId, billingAccountId),
      <CommandResult>[ok()],
    )
    ..onCommand(
      ApisStep.buildEnabledListCommand(stgProjectId),
      // 재실행 fixture 는 출시용 Play Integrity API 까지 켜진 상태다.
      isResumed
          ? <CommandResult>[
              ok(
                '${<String>[...ApisStep.requiredServices, PlayIntegrityStep.serviceName].join('\n')}\n',
              ),
            ]
          : <CommandResult>[
              ok(
                '${ApisStep.requiredServices.where((String s) => s != 'secretmanager.googleapis.com').join('\n')}\n',
              ),
              ok('${ApisStep.requiredServices.join('\n')}\n'),
            ],
    )
    ..onCommand(
      ApisStep.buildEnableCommand(stgProjectId, <String>[
        'secretmanager.googleapis.com',
      ]),
      <CommandResult>[ok()],
    )
    ..onCommand(
      FirestoreStep.buildDescribeCommand(stgProjectId),
      isResumed
          ? <CommandResult>[ok('$region\n')]
          : <CommandResult>[firestoreMissing, ok('$region\n')],
    )
    ..onCommand(
      FirestoreStep.buildCreateCommand(region, stgProjectId),
      <CommandResult>[ok()],
    )
    ..onRest(
      StorageStep.buildGetRequest(stgProjectId),
      isResumed
          ? <RestResponse>[bucket]
          : <RestResponse>[
              const RestResponse(404, '{"error":{"code":404}}'),
              bucket,
            ],
    )
    ..onRest(
      StorageStep.buildCreateRequest(stgProjectId, region),
      <RestResponse>[const RestResponse(200, '{}')],
    )
    ..onRest(
      SignInStep.buildGetRequest(stgProjectId),
      isResumed
          ? <RestResponse>[signInEnabled]
          : <RestResponse>[
              const RestResponse(200, '{"signIn":{}}'),
              signInEnabled,
            ],
    )
    ..onRest(SignInStep.buildPatchRequest(stgProjectId), <RestResponse>[
      const RestResponse(200, '{}'),
    ]);
}

/// configure 스크립트 효과 — stg 설정 파일 3개를 실 값 모양으로 쓰고 추적
/// 자리표시 3개에 skip-worktree 를 건 뒤, pbxproj · firebase.json 을 바꿨다가
/// 실행 전 바이트로 되돌린다. 실행 순간의 `.firebaserc` git 상태도 남긴다.
void _runConfigureScriptEffect(_Run run) {
  final _Fixture fixture = run.fixture;
  const stgPaths = FlavorPaths(Flavor.stg);
  run.firebasercStatusAtConfigure.addAll(
    const LineSplitter().convert(
      fixture.runGitChecked(<String>[
        'status',
        '--porcelain',
        '--',
        FirebaseProjectStep.firebasercPath,
      ]),
    ),
  );
  _writeAppFiles(
    fixture,
    Flavor.stg,
    projectId: stgProjectId,
    bundleId: stgBundleId,
    packageName: stgPackageName,
    iosAppId: stgIosAppId,
    androidAppId: stgAndroidAppId,
  );
  fixture.runGitChecked(<String>[
    'update-index',
    '--skip-worktree',
    stgPaths.dartOptions,
    stgPaths.iosPlist,
    stgPaths.androidJson,
  ]);
  for (final path in <String>[
    ConfigureStep.pbxprojPath,
    ConfigureStep.firebaseJsonPath,
  ]) {
    final file = File('${fixture.root}/$path');
    final List<int> before = file.readAsBytesSync();
    file
      ..writeAsStringSync(
        '// FlutterFire CLI 가 잠시 바꾼 내용\n',
        mode: FileMode.append,
      )
      ..writeAsBytesSync(before);
  }
}

/// 앱 등록 ~ 앱 실행 단계를 stg 프로젝트 기준으로 등록한다.
///
/// [isResumed] 면 이미 끝난 상태, 아니면 「처음 할 일 → 실행 → 끝남」 순서다.
void _registerAppSteps(_Run run, {required bool isResumed}) {
  final Command configure = ConfigureStep.buildConfigureCommand(
    flavor: Flavor.stg,
  );
  run
    ..onCommand(configure, <CommandResult>[
      ok(
        'FlutterFire configure (apiKey: ${buildFakeApiKey()})\n'
        '${ConfigureStep.buildCompleteLine(Flavor.stg)}\n',
      ),
    ])
    ..onEffect(configure, () => _runConfigureScriptEffect(run))
    ..onCommand(
      ConfigureStep.buildAppsListCommand(stgProjectId),
      <CommandResult>[
        ok(
          jsonEncode(<String, Object?>{
            'status': 'success',
            'result': <Object?>[
              <String, Object?>{'appId': stgIosAppId},
              <String, Object?>{'appId': stgAndroidAppId},
            ],
          }),
        ),
      ],
    );

  // rules: 배포 안 됨 → 배포 → 저장소 파일과 같음.
  const firestoreRuleset = 'projects/$stgProjectId/rulesets/fs';
  const storageRuleset = 'projects/$stgProjectId/rulesets/st';
  final firestoreRelease = RestResponse(
    200,
    jsonEncode(<String, String>{'rulesetName': firestoreRuleset}),
  );
  final storageRelease = RestResponse(
    200,
    jsonEncode(<String, String>{'rulesetName': storageRuleset}),
  );
  run
    ..onRest(
      RulesStep.buildReleaseRequest(stgProjectId, RulesStep.firestoreRelease),
      isResumed
          ? <RestResponse>[firestoreRelease]
          : <RestResponse>[const RestResponse(404, '{}'), firestoreRelease],
    )
    ..onRest(
      RulesStep.buildReleaseRequest(
        stgProjectId,
        '${RulesStep.storageReleasePrefix}/$stgProjectId.firebasestorage.app',
      ),
      isResumed
          ? <RestResponse>[storageRelease]
          : <RestResponse>[const RestResponse(404, '{}'), storageRelease],
    )
    ..onRest(
      RulesStep.buildRulesetRequest(stgProjectId, firestoreRuleset),
      <RestResponse>[RestResponse(200, buildRulesetBody(firestoreRules))],
    )
    ..onRest(
      RulesStep.buildRulesetRequest(stgProjectId, storageRuleset),
      <RestResponse>[RestResponse(200, buildRulesetBody(storageRules))],
    )
    ..onCommand(RulesStep.buildDeployCommand(stgProjectId), <CommandResult>[
      ok(),
    ]);

  // App Check: 토큰 없음 → 만들기(목록 비었음 · 등록) → 등록됨.
  for (final appId in <String>[stgIosAppId, stgAndroidAppId]) {
    final registered = RestResponse(
      200,
      jsonEncode(<String, Object?>{
        'debugTokens': <Object?>[
          <String, Object?>{
            'name': 'projects/$stgProjectId/apps/$appId/debugTokens/t1',
            'displayName': stgTokenName,
          },
        ],
      }),
    );
    run
      ..onRest(
        AppCheckStep.buildListRequest(stgProjectId, appId),
        isResumed
            ? <RestResponse>[registered]
            : <RestResponse>[const RestResponse(200, '{}'), registered],
      )
      ..onRest(
        AppCheckStep.buildCreateRequest(
          stgProjectId,
          appId,
          '',
          flavor: Flavor.stg,
        ),
        <RestResponse>[const RestResponse(200, '{}')],
      );
  }

  // Functions: secret 없음 → secret · 배포 → 공개 호출 확인(의존성은 dev 가 설치).
  run
    ..onCommand(
      FunctionsStep.buildSecretsListCommand(stgProjectId),
      <CommandResult>[
        if (!isResumed) ok(),
        ok('projects/333333333333/secrets/$declaredSecret\n'),
      ],
    )
    ..onCommand(
      FunctionsStep.buildSecretSetCommand(declaredSecret, stgProjectId),
      <CommandResult>[ok()],
    )
    ..onCommand(
      FunctionsStep.buildDeployCommand(flavor: Flavor.stg),
      <CommandResult>[
        ok('DEPLOY OK stg functions=${commonFunctions.length} batches=1\n'),
      ],
    )
    ..onCommand(
      FunctionsStep.buildFunctionsListCommand(stgProjectId),
      <CommandResult>[
        ok(
          jsonEncode(<String, Object?>{
            'status': 'success',
            'result': <Object?>[
              for (final String function in commonFunctions)
                <String, Object?>{
                  'id': function,
                  'region': region,
                  'runServiceId': function,
                },
            ],
          }),
        ),
      ],
    );
  for (final String function in commonFunctions) {
    run.onCommand(
      FunctionsStep.buildIamPolicyCommand(function, region, stgProjectId),
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

  // 앱 실행 · 로그인 확인: 0명 → 실행 → 1명.
  const signedIn = RestResponse(
    200,
    '{"users":[{"localId":"u1","emailVerified":true,'
    '"providerUserInfo":[{"providerId":"password"}]}]}',
  );
  run
    ..onCommand(RunStep.buildPubGetCommand(), <CommandResult>[ok()])
    ..onCommand(RunStep.buildCodegenCommand(), <CommandResult>[ok()])
    ..onCommand(RunStep.buildDevicesCommand(), <CommandResult>[
      ok(
        jsonEncode(<Object?>[
          <String, Object?>{
            'name': 'iPhone 17',
            'id': simulatorId,
            'isSupported': true,
            'targetPlatform': 'ios',
            'emulator': true,
          },
        ]),
      ),
    ])
    ..onCommand(
      RunStep.buildRunCommand(simulatorId, flavor: Flavor.stg),
      <CommandResult>[ok()],
    )
    ..onRest(
      RunStep.buildBatchGetRequest(stgProjectId),
      isResumed
          ? <RestResponse>[signedIn]
          : <RestResponse>[const RestResponse(200, '{}'), signedIn],
    );

  // 출시용 단계 — 첫 실행: Play Integrity 기본 설정 · DeviceCheck 미등록(200) 이라
  // 둘 다 할 일(입력은 「지금 안 함」). 재실행: stg 설정 완화 · 키 등록됨(지문
  // 없는 홈이라 Play Integrity 는 질문 없는 ✗). APNs 는 늘 확인할 수 없는 줄.
  run
    ..onRest(
      PlayIntegrityStep.buildGetRequest(stgProjectId, stgAndroidAppId),
      <RestResponse>[
        RestResponse(
          200,
          jsonEncode(<String, Object?>{
            'name': 'playIntegrityConfig',
            'tokenTtl': '3600s',
            if (isResumed) ...<String, Object?>{
              'appIntegrity': <String, Object?>{
                'allowUnrecognizedVersion': true,
              },
              'deviceIntegrity': <String, Object?>{
                'minDeviceRecognitionLevel':
                    PlayIntegrityStep.relaxedDeviceRecognitionLevel,
              },
            },
          }),
        ),
      ],
    )
    ..onRest(
      DeviceCheckStep.buildGetRequest(stgProjectId, stgIosAppId),
      <RestResponse>[
        RestResponse(
          200,
          jsonEncode(<String, Object?>{
            'name': 'deviceCheckConfig',
            'tokenTtl': '3600s',
            if (isResumed) ...<String, Object?>{
              'keyId': 'K' * 10,
              'privateKeySet': true,
            },
          }),
        ),
      ],
    );
}

/// 지문 없는 홈의 Play Integrity 줄(SHA-256 등록만 남음).
const String playIntegrityDeferredLine =
    '  ✗ ${PlayIntegrityStep.stepTitle} — '
    '${PlayIntegrityStep.fingerprintDeferredReason}';

/// APNs 키 줄 — 늘 확인할 수 없다.
const String apnsUnverifiableLine =
    '  ? ${ApnsStep.stepTitle} — ${ApnsStep.unverifiableNote}';

/// 실패 뒤 다시 시도 · 멈춤 고르기 수를 센다 — 미룰 수 있는 단계의 진행 고르기는
/// 같은 질문 문구라 선택지 줄로 가른다.
int _countRetryChoices(_Run run) =>
    '  1) $retryOption\n  2) $stopOption\n'.allMatches(run.output).length;

/// 첫 stg 실행의 입력 — 체크 목록은 `0`(이메일만), 프로젝트는 새로 만들기.
const List<String> firstRunInputs = <String>[
  'y', // 사용자 설정 파일
  '0', // 로그인 수단 체크 목록 — 이메일만
  'y', // 앱 정체성(stg 사용자 파일)
  '', // 표시 이름 기본값
  'y', // 프로젝트
  '1', // 새로 만들기
  '', // 기본 ID
  'y', // 확인 표
  'y', // 결제
  '1', // 결제 계정
  'y', // 확인 표
  'y', // API
  'y', // Firestore
  'y', // 위치 값 표
  'y', // Storage
  'y', // 확인 표
  'y', // 로그인 수단(이메일 · 익명)
  'y', // 앱 등록
  'y', // rules
  'y', // App Check
  'y', // Functions
  'y', // 앱 실행
  '', // 기본 실행 대상
  '2', // Play Integrity — 지금 안 함
  '2', // DeviceCheck — 지금 안 함
];

/// 첫 stg 실행 결과와 실행 전에 읽어 둔 dev 사용자 파일 바이트.
typedef _FirstRun = ({_Run run, int code, Map<String, List<int>> devBytes});

/// dev 가 끝난 저장소에서 `--flavor stg` 를 처음 돌린다.
Future<_FirstRun> _runFirstStg(_Fixture fixture) async {
  const devPaths = FlavorPaths(Flavor.dev);
  final devBytes = <String, List<int>>{
    for (final path in <String>[devPaths.json, devPaths.xcconfig])
      path: fixture.readBytes(path),
  };
  final run = _Run(fixture, firstRunInputs);
  _registerEarlySteps(run);
  _registerCloudSteps(run, isResumed: false);
  _registerAppSteps(run, isResumed: false);
  final int code = await run.run();
  return (run: run, code: code, devBytes: devBytes);
}

/// 질문 기록에서 [question] 이 나온 횟수를 센다.
int _countAsks(_Run run, String question) =>
    run.screen.asks.where((String asked) => asked == question).length;

/// dev 의 Kakao 를 제안받아 고르는 첫 stg 실행을 준비한다.
///
/// 체크 목록은 Kakao 만 고르고, App Check 까지 첫 실행과 같이 간 뒤 Kakao
/// 단계에서 콘솔 작업을 미룬다. 실행 전에 dev 가 만든 Kakao 아이콘 · 원본 사본을
/// 둔다 — 파일이 있으면 앱 아이콘 단계는 질문 없이 ✓ 다(`.setup/` 은 gitignored).
_Run _prepareKakaoStgRun(_Fixture fixture) {
  final int checklist = firstRunInputs.indexOf(emailOnlyAnswer);
  final int kakaoNumber =
      providerCatalog.indexWhere(
        (ProviderEntry entry) => entry.token == KakaoStep.token,
      ) +
      1;
  // 첫 실행 입력의 끝 5개(Functions · 앱 실행 · 실행 대상 · 출시용 둘)는 Kakao
  // 단계 뒤라 쓰지 않는다.
  final inputs = <String?>[
    ...firstRunInputs.sublist(0, checklist),
    '$kakaoNumber',
    ...firstRunInputs.sublist(checklist + 1, firstRunInputs.length - 5),
    'y', // Kakao
    '2', // 콘솔 작업 뒤 다시 실행
  ];
  fixture
    ..write(findIconSpec(KakaoStep.token)!.relativePath, 'icon')
    ..write('$iconsDirectory/source.png', 'source');
  final run = _Run(fixture, inputs);
  _registerEarlySteps(run);
  _registerCloudSteps(run, isResumed: false);
  _registerAppSteps(run, isResumed: false);
  for (final name in <String>[
    ...KakaoStep.nativeAppKeyField.secretNames,
    ...KakaoStep.adminKeyField.secretNames,
  ]) {
    run.onCommand(buildSecretReadCommand(name, stgProjectId), <CommandResult>[
      CommandResult(
        1,
        'Error: HTTP Error: 404, Secret [projects/0/secrets/$name] not '
            'found or has no versions.\n',
        '',
      ),
    ]);
  }
  return run;
}

void main() {
  late _Fixture fixture;

  setUp(() {
    fixture = _Fixture();
    _writeDevFinishedFixture(fixture);
  });

  tearDown(() => fixture.delete());

  test(
    'T-20-STG-09: dev 가 끝난 저장소에서 --flavor stg 첫 실행 — 체크 목록(dev 선택 미리 체크) 0 · 새 프로젝트 · 결제 · 위치(질문 0) · 실행까지 종료 0',
    () async {
      expect(fixture.readStatus(), isEmpty);

      final _FirstRun first = await _runFirstStg(fixture);
      final _Run run = first.run;
      final String output = run.output;

      expect(first.code, wizardExitDone, reason: output);
      expect(output, contains(remainingDoneLine));
      final List<String> lines = const LineSplitter().convert(output);
      final int remaining = lines.indexOf(remainingHeading);
      expect(lines.sublist(remaining + 1, remaining + 4), <String>[
        '  ✗ ${PlayIntegrityStep.stepTitle} — 지금 안 함',
        '  ✗ ${DeviceCheckStep.stepTitle} — 지금 안 함',
        apnsUnverifiableLine,
      ]);
      // 체크 목록은 dev 의 Google · Kakao 를 미리 체크해 열렸다.
      expect(output, contains(UserFilesStep.newFlavorProvidersNotice));
      expect(output, contains('[x] Google'));
      expect(output, contains('[x] Kakao'));
      // 이메일만 — Kakao 단계 없이 진행했다.
      expect(output, isNot(contains('▶ Kakao')));
      // 위치는 묻지 않는다.
      expect(_countAsks(run, FirestoreStep.locationChoiceQuestion), 0);
      expect(_countAsks(run, FirestoreStep.regionChoiceQuestion), 0);
      expect(_countRetryChoices(run), 0);
      expect(
        run.fake.countCalls(
          RunMode.stream,
          FakeCommandRunner.buildKey(
            FirebaseProjectStep.buildCreateCommand(stgProjectId),
          ),
        ),
        1,
      );
      expect(
        run.fake.countCalls(
          RunMode.stream,
          FakeCommandRunner.buildKey(
            BillingStep.buildLinkCommand(stgProjectId, billingAccountId),
          ),
        ),
        1,
      );
      expect(
        run.fake.countCalls(
          RunMode.interactive,
          FakeCommandRunner.buildKey(
            RunStep.buildRunCommand(simulatorId, flavor: Flavor.stg),
          ),
        ),
        1,
      );
      // 끝 요약의 커밋 힌트에는 `.firebaserc` 만 — skip-worktree 설정 파일은 없다.
      final int hintStart = output.indexOf(commitHintHeading);
      expect(hintStart, greaterThan(output.indexOf(remainingDoneLine)));
      final String hint = output.substring(hintStart);
      expect(hint, contains('\n  ${FirebaseProjectStep.firebasercPath}\n'));
      const stgPaths = FlavorPaths(Flavor.stg);
      for (final path in <String>[
        stgPaths.dartOptions,
        stgPaths.iosPlist,
        stgPaths.androidJson,
      ]) {
        expect(hint, isNot(contains(path)));
      }
      for (final String key in run.runner.gitKeys) {
        expect(key, isNot(startsWith('git add')));
        expect(key, isNot(startsWith('git commit')));
      }
      for (final text in <String>[output, run.log.text]) {
        expect(text, isNot(contains(buildFakeAccessToken())));
        expect(text, isNot(contains(buildFakeApiKey())));
      }
    },
  );

  test(
    'T-20-STG-10: stg 실행의 모든 명령 키 · REST 주소에 dev 프로젝트 ID 0회 · stg 배포 · 실행 키 · 디버그 토큰 표시 이름 setup-wizard-stg',
    () async {
      final _FirstRun first = await _runFirstStg(fixture);
      final _Run run = first.run;
      expect(first.code, wizardExitDone, reason: run.output);

      final keys = <String>[
        for (final FakeCall call in run.fake.calls) call.key,
        ...run.runner.gitKeys,
      ];
      final urls = <String>[
        for (final RestRequest request in run.rest.requests)
          request.url.toString(),
        for (final ExternalRequest request in run.rest.externalRequests)
          request.url.toString(),
      ];
      expect(keys, isNotEmpty);
      expect(urls, isNotEmpty);
      for (final key in keys) {
        expect(key, isNot(contains(devProjectId)), reason: key);
      }
      for (final url in urls) {
        expect(url, isNot(contains(devProjectId)), reason: url);
        expect(url, contains(stgProjectId), reason: url);
      }
      for (final RestRequest request in run.rest.requests) {
        expect(request.quotaProject, stgProjectId);
      }
      // 프로젝트를 받는 명령은 모두 stg 프로젝트를 받는다.
      for (final key in keys.where((String key) => key.contains('--project'))) {
        expect(key, contains('--project $stgProjectId'), reason: key);
      }
      expect(
        run.fake.countCalls(
          RunMode.stream,
          'bash scripts/deploy_functions.sh stg --apply',
        ),
        1,
      );
      expect(
        keys.where((String key) => key.contains('deploy_functions.sh dev')),
        isEmpty,
      );
      expect(
        run.fake.countCalls(
          RunMode.stream,
          'bash scripts/firebase-configure.sh stg',
        ),
        1,
      );
      expect(
        keys.where(
          (String key) =>
              key.startsWith('fvm flutter run ') &&
              key.contains(
                '--flavor stg --dart-define-from-file=config/stg.json',
              ),
        ),
        hasLength(1),
      );
      final List<RestRequest> tokenPosts = run.rest.requests
          .where(
            (RestRequest request) =>
                request.method == 'POST' &&
                request.url.toString().endsWith('/debugTokens'),
          )
          .toList();
      expect(tokenPosts, hasLength(2));
      for (final post in tokenPosts) {
        expect(
          (jsonDecode(post.body!)! as Map<String, Object?>)['displayName'],
          stgTokenName,
        );
      }
      // secret 은 stg 프로젝트에만 만든다.
      expect(
        run.fake.calls
            .where(
              (FakeCall call) => call.key.contains('functions:secrets:set'),
            )
            .map((FakeCall call) => call.key),
        <String>[
          FakeCommandRunner.buildKey(
            FunctionsStep.buildSecretSetCommand(declaredSecret, stgProjectId),
          ),
        ],
      );
    },
  );

  test(
    'T-20-STG-11: 끝난 뒤 .firebaserc 에 stg 별칭 · default · dev 그대로 · dev 사용자 파일 바이트 같음 · stg config 로그인 수단 빈 값',
    () async {
      final _FirstRun first = await _runFirstStg(fixture);
      expect(first.code, wizardExitDone, reason: first.run.output);

      final Object? firebaserc = jsonDecode(
        fixture.read(FirebaseProjectStep.firebasercPath),
      );
      expect(
        (firebaserc! as Map<String, Object?>)['projects'],
        <String, Object?>{
          'default': devProjectId,
          'dev': devProjectId,
          'stg': stgProjectId,
        },
      );
      for (final MapEntry<String, List<int>> entry in first.devBytes.entries) {
        expect(fixture.readBytes(entry.key), entry.value, reason: entry.key);
      }
      const stgPaths = FlavorPaths(Flavor.stg);
      final stgConfig = '${fixture.root}/${stgPaths.json}';
      expect(readJsonString(stgConfig, enabledProvidersKey), '');
      expect(
        readJsonString(stgConfig, FirebaseProjectStep.projectIdKey),
        stgProjectId,
      );
      expect(
        readXcconfigValue(
          '${fixture.root}/${stgPaths.xcconfig}',
          'PRODUCT_BUNDLE_IDENTIFIER',
        ),
        stgBundleId,
      );
    },
  );

  test(
    'T-20-STG-12: 앞 단계가 남긴 커밋 안 된 .firebaserc 변경이 앱 등록 단계의 미커밋 검사를 막지 않는다(실제 git 상태)',
    () async {
      final _FirstRun first = await _runFirstStg(fixture);
      final _Run run = first.run;
      expect(first.code, wizardExitDone, reason: run.output);

      // 앱 등록 스크립트가 실행되는 순간 `.firebaserc` 는 실제로 수정됨 상태였다.
      expect(run.firebasercStatusAtConfigure, <String>[
        ' M ${FirebaseProjectStep.firebasercPath}',
      ]);
      expect(run.output, isNot(contains('앱 등록이 고칠 파일에 커밋하지 않은 변경이 있습니다')));
      expect(
        run.fake.countCalls(
          RunMode.stream,
          FakeCommandRunner.buildKey(
            ConfigureStep.buildConfigureCommand(flavor: Flavor.stg),
          ),
        ),
        1,
      );
      expect(
        run.runner.gitKeys.where(
          (String key) => key.startsWith('git status --porcelain'),
        ),
        isNotEmpty,
      );
      expect(
        fixture.readStatus(),
        contains(' M ${FirebaseProjectStep.firebasercPath}'),
      );
    },
  );

  test('T-20-STG-14: dev 의 Kakao 를 제안받아 고른 첫 stg 실행 — Android 쪽 줄이 아직 '
      '검사되지 않았어도 Kakao 값 표에 키 해시 행이 있다', () async {
    final _Run run = _prepareKakaoStgRun(fixture);

    final int code = await run.run();
    final String output = run.output;

    expect(code, wizardExitForUser, reason: output);
    expect(run.screen.asks.last, consoleReadyQuestion);
    final int table = output.indexOf('── Kakao 콘솔에 넣을 값 — stg ──');
    expect(table, greaterThanOrEqualTo(0), reason: output);
    final String tableText = output.substring(table);
    expect(tableText, contains(KakaoStep.keyHashRowLabel));
    expect(tableText, contains(KakaoStep.keyHashUnavailableValue));
  });

  test('T-20-STG-13: 같은 저장소 --flavor stg 재실행 → 질문 0 · 쓰기 0 · '
      '출시용 ✗ · ? 밖 모두 ✓', () async {
    final _FirstRun first = await _runFirstStg(fixture);
    expect(first.code, wizardExitDone, reason: first.run.output);
    const stgPaths = FlavorPaths(Flavor.stg);
    final watched = <String>[
      stgPaths.json,
      stgPaths.xcconfig,
      const FlavorPaths(Flavor.dev).json,
      FirebaseProjectStep.firebasercPath,
    ];
    final before = <String, List<int>>{
      for (final path in watched) path: fixture.readBytes(path),
    };
    final List<String> statusBefore = fixture.readStatus();

    final second = _Run(fixture, const <String?>[]);
    _registerEarlySteps(second);
    _registerCloudSteps(second, isResumed: true);
    _registerAppSteps(second, isResumed: true);
    final int code = await second.run();
    final String output = second.output;

    expect(code, wizardExitDone, reason: output);
    expect(second.screen.asks, isEmpty);
    expect(second.countStepQuestions(), 0);
    expect(second.fake.countMode(RunMode.stream), 0);
    expect(second.fake.countMode(RunMode.interactive), 0);
    expect(second.countWriteRequests(), 0);
    final List<String> checklist = const LineSplitter()
        .convert(output)
        .takeWhile((String line) => line != remainingDoneLine)
        .toList();
    expect(output, isNot(contains(allDoneLine)));
    // 지문 없는 홈 — Play Integrity 는 질문 없는 ✗, APNs 는 확인할 수 없는 ? 다.
    expect(checklist.where((String line) => line.startsWith('  ✗ ')), <String>[
      playIntegrityDeferredLine,
    ]);
    expect(checklist.where((String line) => line.startsWith('  ? ')), <String>[
      apnsUnverifiableLine,
    ]);
    expect(
      checklist.where((String line) => line.startsWith('  ✓ ')),
      hasLength(second.buildCurrentSteps().length - 2),
    );
    for (final path in watched) {
      expect(fixture.readBytes(path), before[path], reason: path);
    }
    expect(fixture.readStatus(), statusBefore);
  });

  test(
    'T-20.1-WIRE-04: dev 가 만든 아이콘이 있는 저장소의 첫 stg 실행은 앱 아이콘 단계를 묻지 않고 ✓ 이고 stg Kakao 값 표가 같은 파일을 보인다',
    () async {
      final _Run run = _prepareKakaoStgRun(fixture);

      final int code = await run.run();
      final String output = run.output;

      expect(code, wizardExitForUser, reason: output);
      final List<String> lines = const LineSplitter().convert(output);
      expect(
        lines,
        contains(startsWith('  ✓ ${AppIconStep.stepTitle} — Kakao 용 1개 · ')),
      );
      expect(lines, isNot(contains('▶ ${AppIconStep.stepTitle}')));
      expect(run.screen.asks, isNot(contains(AppIconStep.sourceQuestion)));
      final IconSpec kakaoSpec = findIconSpec(KakaoStep.token)!;
      final List<String> rows = collectSummaryRows(
        lines,
        '── Kakao 콘솔에 넣을 값 — stg ──',
      );
      expect(rows, isNotEmpty, reason: output);
      expect(rows.last, contains(kakaoSpec.rowLabel));
      expect(rows.last, contains(kakaoSpec.relativePath));
      expect(
        run.fake.calls.where(
          (FakeCall call) =>
              call.key.startsWith('/usr/bin/sips') ||
              call.key.startsWith('/usr/bin/open'),
        ),
        isEmpty,
      );
    },
  );
}
