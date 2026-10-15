import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:test/test.dart';

import '../../../bin/rename.dart' as rename;
import '../../../tool/setup/command_runner.dart';
import '../../../tool/setup/completion.dart';
import '../../../tool/setup/firebase_app_files.dart';
import '../../../tool/setup/redactor.dart';
import '../../../tool/setup/rest_client.dart';
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

/// 흐름에서 앱 정체성 단계에 넣는 org.
const String newOrg = 'com.acme';

/// 흐름에서 앱 정체성 단계에 넣는 name.
const String newName = 'my_app';

/// 흐름이 만드는 Firebase 프로젝트 ID — configure 스크립트 prefix(name 에서 계산) + `-dev`.
const String projectId = 'my-app-dev';

/// 기본 Functions 리전(example config 의 값).
const String region = 'asia-northeast3';

/// 흐름 뒤 Android 앱 ID.
const String newApplicationId = '$newOrg.$newName';

/// 흐름 뒤 dev iOS 번들 ID.
const String newDevBundleId = '$newOrg.myApp.dev';

/// 가짜 iOS Firebase 앱 ID.
const String iosAppId = '1:222222222222:ios:cccccccccccccccc';

/// 가짜 Android Firebase 앱 ID.
const String androidAppId = '1:222222222222:android:dddddddddddddddd';

/// 가짜 로그인 계정.
const String accountEmail = 'blank-dev@example.invalid';

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

/// 사용자가 pbxproj 끝에 덧붙이는 번들 ID 밖 줄.
const String localEditLine = '/* local edit */';

/// 옛 Kotlin 패키지 디렉터리 — 킷 기본 식별자는 rename 상수로만 만든다.
final String oldKotlinDir =
    'android/app/src/main/kotlin/'
    '${rename.currentOrg.replaceAll('.', '/')}/${rename.currentPackageName}';

/// 새 Kotlin 패키지 디렉터리.
const String newKotlinDir = 'android/app/src/main/kotlin/com/acme/my_app';

/// 실행 시점에 조립하는 가짜 액세스 토큰 — 리터럴로 두지 않는다.
String buildFakeAccessToken() => 'ya29.${'B' * 40}';

/// 실행 시점에 조립하는 가짜 API 키 — 리터럴로 두지 않는다.
String buildFakeApiKey() => 'AIza${'y' * 35}';

/// fixture 저장소 하나 — 임시 디렉터리 · 임시 홈 · 호스트 설정과 뗀 git 환경.
final class _Fixture {
  _Fixture()
    : repo = Directory.systemTemp.createTempSync('wizard_blank_repo_'),
      home = Directory.systemTemp.createTempSync('wizard_blank_home_') {
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

  /// 저장소 상대 경로에 내용을 쓴다(부모 디렉터리를 만든다).
  void write(String relativePath, String content) {
    File('$root/$relativePath')
      ..parent.createSync(recursive: true)
      ..writeAsStringSync(content);
  }

  /// 저장소 상대 경로의 내용을 읽는다.
  String read(String relativePath) =>
      File('$root/$relativePath').readAsStringSync();

  /// 두 임시 디렉터리를 지운다.
  void delete() {
    for (final Directory directory in <Directory>[repo, home]) {
      if (directory.existsSync()) directory.deleteSync(recursive: true);
    }
  }
}

/// 킷 기본 모양의 백지 저장소를 쓰고 초기 커밋한다.
///
/// 킷 식별자는 rename 상수로 만들고, 사용자 파일(`config/dev.json` 등)은 두지
/// 않는다. 추적 example 두 개만 저장소에서 복사한다.
void _writeBlankFixture(_Fixture fixture) {
  fixture
    ..write(
      UserFilesStep.jsonExamplePath,
      File(UserFilesStep.jsonExamplePath).readAsStringSync(),
    )
    ..write(
      UserFilesStep.xcconfigExamplePath,
      File(UserFilesStep.xcconfigExamplePath).readAsStringSync(),
    )
    ..write(
      '.gitignore',
      '${UserFilesStep.jsonUserPath}\n'
          '${UserFilesStep.xcconfigUserPath}\n'
          '${FirebaseAppFiles.androidJsonPath}\n'
          'functions/node_modules/\n'
          '.setup/\n',
    )
    ..write(
      IdentityStep.gradlePath,
      'android {\n'
      '    namespace = "${rename.currentAndroidPackage}"\n'
      '    defaultConfig {\n'
      '        applicationId = "${rename.currentAndroidPackage}"\n'
      '    }\n'
      '    productFlavors {\n'
      '        create("dev") { applicationIdSuffix = ".dev" }\n'
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
      FirebaseAppFiles.optionsPath,
      '// placeholder-dev\n'
      "throw UnsupportedError('configure 를 먼저 실행하세요');\n",
    )
    ..write(
      FirebaseAppFiles.iosPlistPath,
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
    );
  fixture
    ..runGitChecked(<String>['init', '-q'])
    ..runGitChecked(<String>['add', '--all'])
    ..runGitChecked(<String>[
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
      'init',
    ]);
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
    return switch (mode) {
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

/// 위저드 한 번 실행 묶음.
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

  /// 화면 출력 전체.
  String get output => screen.output.toString();

  /// [key] 의 결과 큐에 [results] 를 차례로 더한다.
  void on(String key, List<CommandResult> results) {
    for (final CommandResult result in results) {
      fake.on(key, result);
    }
  }

  /// [command] 의 결과 큐에 [results] 를 차례로 더한다.
  void onCommand(Command command, List<CommandResult> results) =>
      on(FakeCommandRunner.buildKey(command), results);

  /// [request] 의 응답 큐에 [responses] 를 차례로 더한다.
  void onRest(RestRequest request, List<RestResponse> responses) {
    for (final RestResponse response in responses) {
      rest.on(request.method, request.url.toString(), response);
    }
  }

  /// [command] 실행 순간에 [effect] 를 부른다.
  void onEffect(Command command, void Function() effect) =>
      runner.effects[FakeCommandRunner.buildKey(command)] = effect;

  /// 16단계 · 끝 요약으로 위저드를 돌린다.
  Future<int> run() =>
      runWizard(context, buildDevSteps(), onCompleted: showCommitHint);

  /// 진행 질문 수를 센다.
  int countStepQuestions() => screen.asks
      .where((String question) => question == stepConfirmQuestion)
      .length;
}

/// 성공 결과.
CommandResult ok([String stdout = '']) => CommandResult(0, stdout, '');

/// 실패 결과.
CommandResult fail([String stderr = '']) => CommandResult(1, '', stderr);

/// 앞 단계(Xcode · 도구 · 로그인)를 등록한다.
///
/// [isResumed] 면 이미 끝난 상태, 아니면 「처음 할 일 → 실행 → 끝남」 순서다.
/// Xcode 단계는 `.app/Contents/Developer` 로 끝나는 가짜 선택 경로를 돌려줘
/// 호스트의 Xcode 디렉터리를 보지 않고, 할 일은 라이선스 검사로 만든다.
void _registerEarlySteps(_Run run, {required bool isResumed}) {
  final String token = buildFakeAccessToken();
  run
    ..on('xcode-select -p', <CommandResult>[
      ok('/Applications/Xcode.app/Contents/Developer\n'),
    ])
    // 점검표 · 단계 시작 = 동의 안 됨, 실행 뒤 = 동의됨.
    ..on(
      'xcodebuild -license check',
      isResumed ? <CommandResult>[ok()] : <CommandResult>[fail(), fail(), ok()],
    )
    ..on('sudo xcodebuild -license accept', <CommandResult>[ok()])
    ..on('xcodebuild -checkFirstLaunchStatus', <CommandResult>[ok()])
    ..on('xcrun simctl list runtimes -j', <CommandResult>[
      ok('{"runtimes":[{"platform":"iOS","isAvailable":true}]}'),
    ])
    ..on('node --version', <CommandResult>[ok('v22.11.0\n')])
    ..on('pnpm --version', <CommandResult>[ok('10.4.1\n')])
    ..on('firebase --version', <CommandResult>[ok('15.29.0\n')])
    ..on('gcloud --version', <CommandResult>[ok('Google Cloud SDK 540.0.0\n')])
    // 도구 단계 시작 = jq 없음, 설치 뒤 = 있음.
    ..on(
      'jq --version',
      isResumed
          ? <CommandResult>[ok('jq-1.7.1\n')]
          : <CommandResult>[
              const CommandResult(127, '', 'jq: not found'),
              ok('jq-1.7.1\n'),
            ],
    )
    ..on('brew --prefix', <CommandResult>[ok('brew-prefix\n')])
    ..on('brew install jq', <CommandResult>[ok()])
    ..on("ruby -e require 'xcodeproj'", <CommandResult>[ok()])
    ..on('fvm dart pub global list', <CommandResult>[
      ok('flutterfire_cli 1.3.1\n'),
    ]);
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
    ..onCommand(
      LoginStep.firebaseAccountsCommand,
      isResumed
          ? <CommandResult>[account]
          : <CommandResult>[ok('{"status":"success","result":[]}'), account],
    )
    ..onCommand(LoginStep.firebaseLoginCommand, <CommandResult>[ok()])
    ..onCommand(AccessTokenSource.tokenCommand, <CommandResult>[ok('$token\n')])
    ..onCommand(LoginStep.gcloudAccountCommand, <CommandResult>[
      ok('$accountEmail\n'),
    ]);
}

/// 실제 Firebase CLI 가 Firebase 추가에 실패할 때 표준 오류에 쓰는 한 줄.
const String addFirebaseFailedLine =
    'Error: Failed to add Firebase to Google Cloud Platform project. '
    'See firebase-debug.log for more info.';

/// Firebase 추가 실패 결과 — 출력은 실제 CLI 의 실패 줄 하나다.
CommandResult buildAddFirebaseFailure() =>
    const CommandResult(1, '', '$addFirebaseFailedLine\n');

/// 내 계정의 Firebase 프로젝트 목록 응답 — [hasProject] 면 흐름의 프로젝트를 담는다.
CommandResult buildProjectsList({required bool hasProject}) => ok(
  jsonEncode(<String, Object?>{
    'status': 'success',
    'result': <Object?>[
      if (hasProject)
        <String, Object?>{'projectId': projectId, 'displayName': projectId},
    ],
  }),
);

/// 프로젝트 ~ 로그인 수단 단계를 「처음 할 일 → 실행 → 끝남」 순서로 등록한다.
///
/// 프로젝트 단계의 결과 큐는 갈래마다 바꿀 수 있다. 기본값은 새로 만들기가
/// 한 번에 끝나는 갈래다 — describe 없음 → create → addfirebase → 목록에 있음.
/// 큐는 그 실행에서 실제로 불리는 check · apply 순서대로 적는다(가짜 실행기는
/// 앞에서부터 쓰다 마지막 값을 되풀이한다).
void _registerCloudSteps(
  _Run run, {
  List<CommandResult>? describeResults,
  List<CommandResult>? addFirebaseResults,
  List<CommandResult>? listResults,
}) {
  run
    ..onCommand(
      FirebaseProjectStep.buildDescribeCommand(projectId),
      describeResults ?? <CommandResult>[fail('NOT_FOUND')],
    )
    ..onCommand(
      FirebaseProjectStep.buildCreateCommand(projectId),
      <CommandResult>[ok()],
    )
    ..onCommand(
      FirebaseProjectStep.buildAddFirebaseCommand(projectId),
      addFirebaseResults ?? <CommandResult>[ok()],
    )
    ..onCommand(
      FirebaseProjectStep.projectsListCommand,
      listResults ?? <CommandResult>[buildProjectsList(hasProject: true)],
    )
    // 결제: 연결 안 됨 → 계정 고르기 → 연결 → 연결됨.
    ..onCommand(BillingStep.billingInfoCommand(projectId), <CommandResult>[
      ok('{"billingEnabled":false}'),
      ok('{"billingEnabled":true}'),
    ])
    ..onCommand(BillingStep.openAccountsCommand, <CommandResult>[
      ok(
        '[{"name":"billingAccounts/000000-AAAAAA-BBBBBB",'
        '"displayName":"Kit Billing","open":true}]',
      ),
    ])
    ..onCommand(
      BillingStep.buildLinkCommand(projectId, '000000-AAAAAA-BBBBBB'),
      <CommandResult>[ok()],
    )
    // API: secret manager 만 꺼짐 → 켜기 → 모두 켜짐.
    ..onCommand(ApisStep.buildEnabledListCommand(projectId), <CommandResult>[
      ok(
        '${ApisStep.requiredServices.where((String s) => s != 'secretmanager.googleapis.com').join('\n')}\n',
      ),
      ok('${ApisStep.requiredServices.join('\n')}\n'),
    ])
    ..onCommand(
      ApisStep.buildEnableCommand(projectId, <String>[
        'secretmanager.googleapis.com',
      ]),
      <CommandResult>[ok()],
    )
    // Firestore: 없음 → 만들기(기본 리전) → 있음. Storage 의 위치 읽기도 같은 명령이다.
    ..onCommand(FirestoreStep.buildDescribeCommand(projectId), <CommandResult>[
      const CommandResult(1, '', 'ERROR: NOT_FOUND: database does not exist'),
      ok('$region\n'),
    ])
    ..onCommand(
      FirestoreStep.buildCreateCommand(region, projectId),
      <CommandResult>[ok()],
    )
    // Storage: 기본 bucket 없음 → 만들기 → 있음(rules 단계도 이 응답을 읽는다).
    ..onRest(StorageStep.buildGetRequest(projectId), <RestResponse>[
      const RestResponse(404, '{"error":{"code":404}}'),
      RestResponse(
        200,
        jsonEncode(<String, Object?>{
          'location': region,
          'bucket': <String, Object?>{
            'name':
                'projects/$projectId/buckets/$projectId.firebasestorage.app',
          },
        }),
      ),
    ])
    ..onRest(StorageStep.buildCreateRequest(projectId, region), <RestResponse>[
      const RestResponse(200, '{}'),
    ])
    // 로그인 수단: 꺼짐 → PATCH → 켜짐.
    ..onRest(SignInStep.buildGetRequest(projectId), <RestResponse>[
      const RestResponse(200, '{"signIn":{}}'),
      const RestResponse(
        200,
        '{"signIn":{"email":{"enabled":true,"passwordRequired":true},'
        '"anonymous":{"enabled":true}}}',
      ),
    ])
    ..onRest(SignInStep.buildPatchRequest(projectId), <RestResponse>[
      const RestResponse(200, '{}'),
    ]);
}

/// configure 스크립트 효과 — 설정 파일 3개를 실 값 모양으로 쓰고 skip-worktree 를
/// 건 뒤, pbxproj · firebase.json 을 바꿨다가 실행 전 바이트로 되돌린다.
void _runConfigureScriptEffect(_Fixture fixture) {
  final String apiKey = buildFakeApiKey();
  final String bundleId = readDevBundleId(fixture.root)!;
  final String packageName = readDevAndroidPackage(fixture.root)!;
  fixture
    ..write(
      FirebaseAppFiles.optionsPath,
      buildGeneratedOptionsSource(
        projectId: projectId,
        apiKey: apiKey,
        androidAppId: androidAppId,
        iosAppId: iosAppId,
        iosBundleId: bundleId,
      ),
    )
    ..write(
      FirebaseAppFiles.iosPlistPath,
      '<plist><dict>\n'
      '<key>API_KEY</key>\n<string>$apiKey</string>\n'
      '<key>PROJECT_ID</key>\n<string>$projectId</string>\n'
      '<key>BUNDLE_ID</key>\n<string>$bundleId</string>\n'
      '<key>GOOGLE_APP_ID</key>\n<string>$iosAppId</string>\n'
      '</dict></plist>\n',
    )
    ..write(
      FirebaseAppFiles.androidJsonPath,
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
    )
    ..runGitChecked(<String>[
      'update-index',
      '--skip-worktree',
      FirebaseAppFiles.optionsPath,
      FirebaseAppFiles.iosPlistPath,
    ]);
  for (final String path in <String>[
    ConfigureStep.pbxprojPath,
    ConfigureStep.firebaseJsonPath,
  ]) {
    final File file = File('${fixture.root}/$path');
    final List<int> before = file.readAsBytesSync();
    file
      ..writeAsStringSync(
        '// FlutterFire CLI 가 잠시 바꾼 내용\n',
        mode: FileMode.append,
      )
      ..writeAsBytesSync(before);
  }
}

/// configure 스크립트가 설정 파일을 다 쓰고도 비0 으로 끝난 결과.
const CommandResult configureExitFailure = CommandResult(
  1,
  'FlutterFire configure\n',
  'configure: unexpected exit\n',
);

/// configure ~ 앱 실행 단계를 「처음 할 일 → 실행 → 끝남」 순서로 등록한다.
///
/// [configureResults] 가 있으면 configure 스크립트의 결과만 그것으로 바꾼다 —
/// 설정 파일을 쓰는 효과는 그대로 실행 순간에 일어난다.
void _registerAppSteps(_Run run, {List<CommandResult>? configureResults}) {
  final String apiKey = buildFakeApiKey();
  run
    ..onCommand(
      ConfigureStep.buildConfigureCommand(),
      configureResults ??
          <CommandResult>[
            ok(
              'FlutterFire configure (apiKey: $apiKey)\n'
              '${ConfigureStep.completeLine}\n',
            ),
          ],
    )
    ..onEffect(
      ConfigureStep.buildConfigureCommand(),
      () => _runConfigureScriptEffect(run.fixture),
    )
    ..onCommand(ConfigureStep.buildAppsListCommand(projectId), <CommandResult>[
      ok(
        jsonEncode(<String, Object?>{
          'status': 'success',
          'result': <Object?>[
            <String, Object?>{'appId': iosAppId},
            <String, Object?>{'appId': androidAppId},
          ],
        }),
      ),
    ]);

  // rules: 배포 안 됨 → 배포 → 저장소 파일과 같음.
  final String firestoreRuleset = 'projects/$projectId/rulesets/fs';
  final String storageRuleset = 'projects/$projectId/rulesets/st';
  run
    ..onRest(
      RulesStep.buildReleaseRequest(projectId, RulesStep.firestoreRelease),
      <RestResponse>[
        const RestResponse(404, '{}'),
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
        const RestResponse(404, '{}'),
        RestResponse(
          200,
          jsonEncode(<String, String>{'rulesetName': storageRuleset}),
        ),
      ],
    )
    ..onRest(
      RulesStep.buildRulesetRequest(projectId, firestoreRuleset),
      <RestResponse>[RestResponse(200, buildRulesetBody(firestoreRules))],
    )
    ..onRest(
      RulesStep.buildRulesetRequest(projectId, storageRuleset),
      <RestResponse>[RestResponse(200, buildRulesetBody(storageRules))],
    )
    ..onCommand(RulesStep.buildDeployCommand(projectId), <CommandResult>[ok()]);

  // App Check: 토큰 없음 → 만들기(목록 비었음 · 등록) → 등록됨.
  for (final String appId in <String>[iosAppId, androidAppId]) {
    run
      ..onRest(AppCheckStep.buildListRequest(projectId, appId), <RestResponse>[
        const RestResponse(200, '{}'),
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
      ])
      ..onRest(
        AppCheckStep.buildCreateRequest(projectId, appId, ''),
        <RestResponse>[const RestResponse(200, '{}')],
      );
  }

  // Functions: 설치 안 됨 · secret 없음 → 설치 · secret · 배포 → 공개 호출 확인.
  run
    ..onCommand(
      FunctionsStep.buildSecretsListCommand(projectId),
      <CommandResult>[
        ok(),
        ok('projects/000000000000/secrets/$declaredSecret\n'),
      ],
    )
    ..onCommand(FunctionsStep.buildInstallCommand(), <CommandResult>[ok()])
    ..onEffect(
      FunctionsStep.buildInstallCommand(),
      () => run.fixture.write(FunctionsStep.modulesMarkerPath, ''),
    )
    ..onCommand(
      FunctionsStep.buildSecretSetCommand(declaredSecret, projectId),
      <CommandResult>[ok()],
    )
    ..onCommand(FunctionsStep.buildDeployCommand(), <CommandResult>[
      ok('DEPLOY OK dev functions=${commonFunctions.length} batches=1\n'),
    ])
    ..onCommand(
      FunctionsStep.buildFunctionsListCommand(projectId),
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

  // 앱 실행 · 로그인 확인: 0명 → 실행 → 1명.
  final String simulatorId = '0A1B2C3D-4E5F-4A6B-8C7D-9E0F1A2B3C4D';
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
    ..onCommand(RunStep.buildRunCommand(simulatorId), <CommandResult>[ok()])
    // 점검표에서는 앞 단계 대기라 검사는 단계 시작 · 실행 뒤 두 번이다.
    ..onRest(RunStep.buildBatchGetRequest(projectId), <RestResponse>[
      const RestResponse(200, '{}'),
      const RestResponse(
        200,
        '{"users":[{"localId":"u1","emailVerified":true,'
        '"providerUserInfo":[{"providerId":"password"}]}]}',
      ),
    ]);
}

/// ruleset 응답 본문.
String buildRulesetBody(String content) => jsonEncode(<String, Object?>{
  'source': <String, Object?>{
    'files': <Object?>[
      <String, Object?>{'name': 'rules', 'content': content},
    ],
  },
});

/// 첫 실행에서 xcode ~ 앱 정체성까지의 입력.
const List<String> earlyInputs = <String>[
  'y', // Xcode
  'y', // 개발 도구
  'y', // 사용자 설정 파일
  'y', // 앱 정체성
  newOrg,
  newName,
  '1', // 이대로 진행
  'y', // 확인 표
];

/// 프로젝트 단계에서 새로 만들기를 고르고 새 프로젝트 표까지 답하는 입력.
const List<String> projectCreateInputs = <String>[
  'y', // 프로젝트
  '1', // 새로 만들기
  '', // 기본 ID
  'y', // 확인 표
];

/// 프로젝트 단계 뒤 결제 ~ 로그인 수단까지의 입력.
const List<String> afterProjectInputs = <String>[
  'y', // 결제
  '1', // 결제 계정
  'y', // 확인 표
  'y', // API
  'y', // Firestore
  '', // 기본 위치
  'y', // 확인 표
  'y', // Storage
  'y', // 확인 표
  'y', // 로그인 수단
];

/// 프로젝트 ~ configure 진행까지의 입력.
const List<String> cloudInputs = <String>[
  ...projectCreateInputs,
  ...afterProjectInputs,
];

/// 앱 등록 ~ 앱 실행까지 모두 진행하는 입력.
const List<String> appInputs = <String>[
  'y', // 앱 등록
  'y', // rules
  'y', // App Check
  'y', // Functions
  'y', // 앱 실행
  '', // 기본 실행 대상
];

/// [text] 안에 [pattern] 이 나오는 횟수를 센다.
int _countOccurrences(String text, String pattern) =>
    pattern.allMatches(text).length;

/// 질문 기록에서 [question] 이 나온 횟수를 센다.
int _countAsks(_Run run, String question) =>
    run.screen.asks.where((String asked) => asked == question).length;

/// 저장소 루트를 작업 디렉터리로 받아야 하는 명령 키의 앞부분.
const List<String> cwdDependentPrefixes = <String>[
  'bash scripts/',
  'pnpm -C ',
  'fvm flutter ',
  'fvm dart run ',
  'firebase deploy ',
];

void main() {
  late _Fixture fixture;

  setUp(() {
    fixture = _Fixture();
    _writeBlankFixture(fixture);
  });

  tearDown(() => fixture.delete());

  test(
    'T-19-FLOW-06: 백지 → 16단계 끝까지 · configure 가 앞 단계 변경 위에서 진행 · 끝 요약',
    () async {
      final _Run run = _Run(fixture, <String?>[
        ...earlyInputs,
        'y', // 로그인
        ...cloudInputs,
        'y', // 앱 등록
        'y', // rules
        'y', // App Check
        'y', // Functions
        'y', // 앱 실행
        '', // 기본 실행 대상
      ]);
      _registerEarlySteps(run, isResumed: false);
      _registerCloudSteps(run);
      _registerAppSteps(run);

      final int code = await run.run();
      final String output = run.output;

      expect(code, wizardExitDone, reason: output);
      final List<String> lines = const LineSplitter().convert(output);
      final int firstChecklistEnd = lines.indexWhere(
        (String line) => line.startsWith('▶ '),
      );
      expect(
        lines
            .take(firstChecklistEnd)
            .where((String line) => line.startsWith('  ✓ ')),
        isEmpty,
      );
      expect(run.countStepQuestions(), 16);
      expect(
        run.fake.countCalls(
          RunMode.stream,
          FakeCommandRunner.buildKey(ConfigureStep.buildConfigureCommand()),
        ),
        1,
      );
      expect(output, isNot(contains('되돌리지 못했습니다')));
      expect(output, contains(allDoneLine));

      final List<String> status = const LineSplitter().convert(
        fixture.runGitChecked(<String>['status', '--porcelain']),
      );
      expect(
        status.where(
          (String line) => line == ' M ${ConfigureStep.pbxprojPath}',
        ),
        hasLength(1),
      );

      final int hintStart = output.indexOf(commitHintHeading);
      expect(hintStart, greaterThan(output.indexOf(allDoneLine)));
      final String hint = output.substring(hintStart);
      for (final String path in <String>[
        ConfigureStep.pbxprojPath,
        FirebaseProjectStep.firebasercPath,
        '$oldKotlinDir/MainActivity.kt',
        '$newKotlinDir/MainActivity.kt',
      ]) {
        expect(hint, contains('\n  $path\n'));
      }
      expect(hint, isNot(contains(FirebaseAppFiles.optionsPath)));
      expect(hint, isNot(contains(FirebaseAppFiles.iosPlistPath)));
      final String addLine = const LineSplitter()
          .convert(hint)
          .singleWhere((String line) => line.startsWith('  \$ git add '));
      expect(addLine, contains('$newKotlinDir/MainActivity.kt'));
      expect(addLine, contains('$oldKotlinDir/MainActivity.kt'));

      for (final String key in run.runner.gitKeys) {
        expect(key, isNot(startsWith('git add')));
        expect(key, isNot(startsWith('git commit')));
      }
      for (final String text in <String>[output, run.log.text]) {
        expect(text, isNot(contains(buildFakeAccessToken())));
        expect(text, isNot(contains(buildFakeApiKey())));
      }
      expect(fixture.read(IdentityStep.gradlePath), contains(newApplicationId));
      expect(readDevBundleId(fixture.root), newDevBundleId);
      // 작업 디렉터리에 기대는 명령(스크립트 · pnpm · fvm · 배포)은 저장소 루트에서
      // 실행한다 — 가짜 실행기 키에는 cwd 가 없으므로 기록으로 따로 본다.
      final List<FakeCall> rootBound = run.fake.calls
          .where(
            (FakeCall call) => cwdDependentPrefixes.any(call.key.startsWith),
          )
          .toList();
      expect(
        rootBound,
        hasLength(greaterThanOrEqualTo(cwdDependentPrefixes.length)),
      );
      for (final FakeCall call in rootBound) {
        expect(call.workingDirectory, fixture.root, reason: call.key);
      }
    },
  );

  test(
    'T-19-FLOW-07: 사용자가 pbxproj 의 번들 ID 밖 줄을 고쳐 두면 configure 에서 멈춘다',
    () async {
      final _Run first = _Run(fixture, <String?>[...earlyInputs]);
      _registerEarlySteps(first, isResumed: false);
      expect(await first.run(), wizardExitStopped);
      expect(first.screen.asks.last, stepConfirmQuestion);
      expect(first.output, contains('▶ ${LoginStep.stepTitle}'));

      File(
        '${fixture.root}/${ConfigureStep.pbxprojPath}',
      ).writeAsStringSync('$localEditLine\n', mode: FileMode.append);

      final _Run second = _Run(fixture, <String?>[
        ...cloudInputs,
        'y', // 앱 등록
        '', // 실패 뒤 기본 = 멈춤
      ]);
      _registerEarlySteps(second, isResumed: true);
      _registerCloudSteps(second);
      _registerAppSteps(second);

      final int code = await second.run();
      final String output = second.output;

      expect(code, wizardExitStopped, reason: output);
      final List<String> checklist = const LineSplitter()
          .convert(output)
          .takeWhile((String line) => !line.startsWith('▶ '))
          .toList();
      for (final String title in <String>[
        'Xcode 준비',
        '개발 도구',
        '사용자 설정 파일',
        '앱 정체성',
      ]) {
        expect(
          checklist.where((String line) => line.startsWith('  ✓ $title — ')),
          hasLength(1),
        );
      }
      expect(output, contains('  실패 — 앱 등록이 고칠 파일에 커밋하지 않은 변경이 있습니다'));
      expect(output, contains('\n    ${ConfigureStep.pbxprojPath}\n'));
      expect(
        second.fake.countCalls(
          RunMode.stream,
          FakeCommandRunner.buildKey(ConfigureStep.buildConfigureCommand()),
        ),
        0,
      );
      expect(second.screen.asks.last, failureChoiceQuestion);
      expect(output, isNot(contains(commitHintHeading)));
    },
  );

  test(
    'T-19-FLOW-08: Firebase 추가 실패 → 콘솔 안내 → Enter 재검사(아직 → ✓) → 16단계 끝까지',
    () async {
      final _Run run = _Run(fixture, <String?>[
        ...earlyInputs,
        'y', // 로그인
        ...projectCreateInputs,
        '', // Enter — 아직 Firebase 가 추가되지 않음
        '', // Enter — 추가됨
        ...afterProjectInputs,
        ...appInputs,
      ]);
      _registerEarlySteps(run, isResumed: false);
      // 앞 check 두 번(점검표 · 단계 머리)은 config 가 자리표시라 목록 · describe 를
      // 부르지 않는다. describe = 만들기 판단(없음) → Enter#1 재검사(내 프로젝트),
      // 목록 = Enter#1(없음) → Enter#2(있음).
      _registerCloudSteps(
        run,
        describeResults: <CommandResult>[fail('NOT_FOUND'), ok('$projectId\n')],
        addFirebaseResults: <CommandResult>[buildAddFirebaseFailure()],
        listResults: <CommandResult>[
          buildProjectsList(hasProject: false),
          buildProjectsList(hasProject: true),
        ],
      );
      _registerAppSteps(run);

      final int code = await run.run();
      final String output = run.output;

      expect(code, wizardExitDone, reason: output);
      final String guide = FirebaseProjectStep.buildAddFirebaseGuide(projectId);
      expect(output, contains(const LineSplitter().convert(guide).first));
      expect(output, contains(FirebaseProjectStep.firebaseConsoleUrl));
      expect(_countOccurrences(output, addFirebaseFailedLine), 1);
      expect(_countOccurrences(output, '  아직 끝나지 않았습니다 — '), 1);
      expect(_countAsks(run, waitForEnterMessage), 2);
      expect(_countAsks(run, failureChoiceQuestion), 0);
      expect(_countAsks(run, FirebaseProjectStep.projectChoiceQuestion), 1);
      expect(_countAsks(run, FirebaseProjectStep.idQuestion), 1);
      expect(
        _countOccurrences(output, '── ${FirebaseProjectStep.confirmTitle} ──'),
        1,
      );
      expect(
        _countOccurrences(
          output,
          '── ${FirebaseProjectStep.addFirebaseConfirmTitle} ──',
        ),
        0,
      );
      for (final Command command in <Command>[
        FirebaseProjectStep.buildCreateCommand(projectId),
        FirebaseProjectStep.buildAddFirebaseCommand(projectId),
      ]) {
        expect(
          run.fake.countCalls(
            RunMode.stream,
            FakeCommandRunner.buildKey(command),
          ),
          1,
        );
      }
      for (final Command command in <Command>[
        FirebaseProjectStep.buildDescribeCommand(projectId),
        FirebaseProjectStep.projectsListCommand,
      ]) {
        expect(
          run.fake.countCalls(
            RunMode.capture,
            FakeCommandRunner.buildKey(command),
          ),
          2,
        );
      }
      expect(output, contains(allDoneLine));

      final List<String> status = const LineSplitter().convert(
        fixture.runGitChecked(<String>['status', '--porcelain']),
      );
      expect(status, contains(' M ${FirebaseProjectStep.firebasercPath}'));
      final int hintStart = output.indexOf(commitHintHeading);
      expect(hintStart, greaterThan(output.indexOf(allDoneLine)));
      expect(
        output.substring(hintStart),
        contains('\n  ${FirebaseProjectStep.firebasercPath}\n'),
      );
      for (final String text in <String>[output, run.log.text]) {
        expect(text, isNot(contains(buildFakeAccessToken())));
        expect(text, isNot(contains(buildFakeApiKey())));
      }
    },
  );

  test(
    'T-19-FLOW-09: Firebase 추가 실패 뒤 멈추면 다시 실행이 같은 ID 에 확인 표 뒤 Firebase 를 추가해 끝까지 간다',
    () async {
      final _Run first = _Run(fixture, <String?>[
        ...earlyInputs,
        'y', // 로그인
        ...projectCreateInputs,
        // Enter 자리에서 입력이 끝난다.
      ]);
      _registerEarlySteps(first, isResumed: false);
      _registerCloudSteps(
        first,
        describeResults: <CommandResult>[fail('NOT_FOUND')],
        addFirebaseResults: <CommandResult>[buildAddFirebaseFailure()],
        listResults: <CommandResult>[buildProjectsList(hasProject: false)],
      );

      expect(await first.run(), wizardExitStopped, reason: first.output);
      expect(first.screen.asks.last, waitForEnterMessage);
      // 자리표시 check 두 번 · Enter 없이 멈춤이라 목록은 한 번도 부르지 않는다.
      expect(
        first.fake.countCalls(
          RunMode.capture,
          FakeCommandRunner.buildKey(FirebaseProjectStep.projectsListCommand),
        ),
        0,
      );
      expect(
        jsonDecode(fixture.read(UserFilesStep.jsonUserPath)),
        containsPair(FirebaseProjectStep.projectIdKey, projectId),
      );
      expect(
        const LineSplitter().convert(
          fixture.runGitChecked(<String>['status', '--porcelain']),
        ),
        contains(' M ${FirebaseProjectStep.firebasercPath}'),
      );

      final _Run second = _Run(fixture, <String?>[
        'y', // 프로젝트
        'y', // Firebase 추가 확인 표
        ...afterProjectInputs,
        ...appInputs,
      ]);
      _registerEarlySteps(second, isResumed: true);
      // config 의 ID 가 실제 값이라 점검표 · 단계 머리 check 도 목록을 부른다 —
      // 목록 = 점검표(없음) → 단계 머리(없음) → 실행 뒤(있음).
      _registerCloudSteps(
        second,
        describeResults: <CommandResult>[ok('$projectId\n')],
        addFirebaseResults: <CommandResult>[ok()],
        listResults: <CommandResult>[
          buildProjectsList(hasProject: false),
          buildProjectsList(hasProject: false),
          buildProjectsList(hasProject: true),
        ],
      );
      _registerAppSteps(second);

      final int code = await second.run();
      final String output = second.output;

      expect(code, wizardExitDone, reason: output);
      final List<String> checklist = const LineSplitter()
          .convert(output)
          .takeWhile((String line) => !line.startsWith('▶ '))
          .toList();
      final String projectLinePrefix =
          '  ✗ ${FirebaseProjectStep.stepTitle} — ';
      final String projectLine = checklist.singleWhere(
        (String line) => line.startsWith(projectLinePrefix),
      );
      final String reason = projectLine.substring(projectLinePrefix.length);
      expect(reason, contains('Firebase'));
      expect(reason, contains(projectId));
      for (final String title in <String>[
        'Xcode 준비',
        '개발 도구',
        '사용자 설정 파일',
        '앱 정체성',
        LoginStep.stepTitle,
      ]) {
        expect(
          checklist.where((String line) => line.startsWith('  ✓ $title — ')),
          hasLength(1),
        );
      }
      expect(_countAsks(second, FirebaseProjectStep.projectChoiceQuestion), 0);
      expect(_countAsks(second, FirebaseProjectStep.idQuestion), 0);
      expect(_countAsks(second, failureChoiceQuestion), 0);
      expect(
        _countOccurrences(
          output,
          '── ${FirebaseProjectStep.addFirebaseConfirmTitle} ──',
        ),
        1,
      );
      expect(
        _countOccurrences(output, '── ${FirebaseProjectStep.confirmTitle} ──'),
        0,
      );
      expect(
        second.fake.countCalls(
          RunMode.stream,
          FakeCommandRunner.buildKey(
            FirebaseProjectStep.buildAddFirebaseCommand(projectId),
          ),
        ),
        1,
      );
      expect(
        second.fake.countCalls(
          RunMode.stream,
          FakeCommandRunner.buildKey(
            FirebaseProjectStep.buildCreateCommand(projectId),
          ),
        ),
        0,
      );
      expect(output, isNot(contains('고칠 파일에 커밋하지 않은 변경이 있습니다')));
      expect(output, contains(allDoneLine));
      final int hintStart = output.indexOf(commitHintHeading);
      expect(hintStart, greaterThan(output.indexOf(allDoneLine)));
      expect(
        output.substring(hintStart),
        contains('\n  ${FirebaseProjectStep.firebasercPath}\n'),
      );
    },
  );

  test(
    'T-19-FLOW-10: configure 스크립트가 파일을 다 쓰고 비0 으로 끝나면 다시 시도가 재검사 ✓ 로 넘어간다',
    () async {
      final _Run run = _Run(fixture, <String?>[
        ...earlyInputs,
        'y', // 로그인
        ...cloudInputs,
        'y', // 앱 등록
        '1', // 실패 뒤 다시 시도
        'y', // rules
        'y', // App Check
        'y', // Functions
        'y', // 앱 실행
        '', // 기본 실행 대상
      ]);
      _registerEarlySteps(run, isResumed: false);
      _registerCloudSteps(run);
      _registerAppSteps(
        run,
        configureResults: const <CommandResult>[configureExitFailure],
      );

      final int code = await run.run();
      final String output = run.output;

      expect(code, wizardExitDone, reason: output);
      expect(
        run.fake.countCalls(
          RunMode.stream,
          FakeCommandRunner.buildKey(ConfigureStep.buildConfigureCommand()),
        ),
        1,
      );
      expect(_countAsks(run, failureChoiceQuestion), 1);
      final List<String> lines = const LineSplitter().convert(output);
      final int failureLine = lines.indexWhere(
        (String line) => line.startsWith('  실패 — configure 스크립트가 실패했습니다'),
      );
      expect(failureLine, isNonNegative);
      final int doneLine = lines.indexWhere(
        (String line) => line.startsWith('  ✓ ${ConfigureStep.stepTitle} — '),
      );
      expect(doneLine, greaterThan(failureLine));
      expect(output, isNot(contains('되돌리지 못했습니다')));
      expect(output, contains(allDoneLine));
      for (final String text in <String>[output, run.log.text]) {
        expect(text, isNot(contains(buildFakeAccessToken())));
        expect(text, isNot(contains(buildFakeApiKey())));
      }
    },
  );
}
