import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:test/test.dart';

import '../../../tool/setup/command_runner.dart';
import '../../../tool/setup/flavor.dart';
import '../../../tool/setup/redactor.dart';
import '../../../tool/setup/rest_client.dart';
import '../../../tool/setup/step.dart';
import '../../../tool/setup/steps/apis_step.dart';
import '../../../tool/setup/steps/billing_step.dart';
import '../../../tool/setup/steps/dev_steps.dart';
import '../../../tool/setup/steps/run_step.dart';
import '../../../tool/setup/steps/storage_step.dart';
import '../../../tool/setup/steps/user_files_step.dart';
import '../../../tool/setup/terminal.dart';
import '../../../tool/setup/wizard.dart';
import 'fake_rest_client.dart';
import 'fakes.dart';

/// 테스트 프로젝트 ID(가짜).
const String projectId = 'demo-p';

/// 가짜 iOS 시뮬레이터 id — UUID 모양(실제 시뮬레이터 UDID 와 같은 꼴).
const String simulatorId = '0A1B2C3D-4E5F-4A6B-8C7D-9E0F1A2B3C4D';

/// 가짜 Android 에뮬레이터 id.
const String androidEmulatorId = 'emulator-5554';

/// 가짜 iOS 실기기 id.
const String iosDeviceId = '00008140-0011223344556677';

/// 끝난 앞 단계 stub — 검사는 늘 끝남이다.
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

/// `flutter devices --machine` 항목 하나를 만든다(키 구조는 Flutter 출력과 같다).
Map<String, Object?> buildDevice({
  required String name,
  required String id,
  required String targetPlatform,
  required bool isEmulator,
  bool isSupported = true,
}) => <String, Object?>{
  'name': name,
  'id': id,
  'isSupported': isSupported,
  'targetPlatform': targetPlatform,
  'emulator': isEmulator,
  'sdk': 'sdk',
  'capabilities': <String, Object?>{'hotReload': true},
};

/// iOS 시뮬레이터 항목.
Map<String, Object?> buildSimulator() => buildDevice(
  name: 'iPhone 17',
  id: simulatorId,
  targetPlatform: 'ios',
  isEmulator: true,
);

/// macOS 데스크톱 항목.
Map<String, Object?> buildMacOs() => buildDevice(
  name: 'macOS',
  id: 'macos',
  targetPlatform: 'darwin',
  isEmulator: false,
);

/// Chrome 항목.
Map<String, Object?> buildChrome() => buildDevice(
  name: 'Chrome',
  id: 'chrome',
  targetPlatform: 'web-javascript',
  isEmulator: false,
);

/// 기기 목록을 `devices --machine` 성공 출력으로 만든다.
CommandResult buildDevicesOutput(List<Map<String, Object?>> devices) =>
    CommandResult(0, jsonEncode(devices), '');

/// 가짜 iPhone 시뮬레이터 UDID — 대문자 UUID 모양(simctl 출력과 같은 꼴).
const String iphoneUdid = '1A2B3C4D-5E6F-4A7B-8C9D-0E1F2A3B4C5D';

/// 두 번째 가짜 iPhone 시뮬레이터 UDID.
const String otherIphoneUdid = '2B3C4D5E-6F70-4B8C-9DAE-1F2A3B4C5D6E';

/// 가짜 iPad 시뮬레이터 UDID.
const String ipadUdid = '3C4D5E6F-7081-4C9D-AEBF-2A3B4C5D6E7F';

/// [n] 번째 가짜 시뮬레이터 UDID — 대문자 UUID 모양.
String buildUdid(int n) =>
    'ABCDEF01-2345-4678-9ABC-${n.toString().padLeft(12, '0')}';

/// simctl iOS 런타임 키를 만든다(`…SimRuntime.iOS-<주>-<부>`).
String buildIosRuntimeKey(int major, int minor) =>
    'com.apple.CoreSimulator.SimRuntime.iOS-$major-$minor';

/// simctl watchOS 런타임 키를 만든다.
String buildWatchRuntimeKey(int major, int minor) =>
    'com.apple.CoreSimulator.SimRuntime.watchOS-$major-$minor';

/// `simctl list devices available -j` 기기 항목 하나를 만든다(키 구조는 simctl
/// 출력과 같다).
Map<String, Object?> buildSimDevice({
  required String name,
  required String udid,
  String deviceType = 'iPhone-17',
  String state = 'Shutdown',
  bool isAvailable = true,
}) => <String, Object?>{
  'dataPath': '/sim/$udid/data',
  'dataPathSize': 0,
  'deviceTypeIdentifier': 'com.apple.CoreSimulator.SimDeviceType.$deviceType',
  'isAvailable': isAvailable,
  'logPath': '/sim/$udid/log',
  'name': name,
  'state': state,
  'udid': udid,
};

/// simctl 기기 목록 출력(런타임 키 → 기기 배열)을 문자열로 만든다.
String buildSimctlJson(Map<String, List<Map<String, Object?>>> runtimes) =>
    const JsonEncoder.withIndent(
      '  ',
    ).convert(<String, Object?>{'devices': runtimes});

/// simctl 기기 목록을 성공 출력으로 만든다.
CommandResult buildSimctlOutput(
  Map<String, List<Map<String, Object?>>> runtimes,
) => CommandResult(0, buildSimctlJson(runtimes), '');

/// [base] 아래 가짜 Xcode 의 개발자 디렉터리(`xcode-select -p` 가 돌려주는 꼴).
String buildDeveloperDir(String base) => '$base/Xcode.app/Contents/Developer';

/// [base] 아래 가짜 Xcode 의 DeviceHub 화면 앱 경로.
String buildDeviceHubPath(String base) =>
    '$base/Xcode.app/Contents/Applications/DeviceHub.app';

/// [base] 아래 가짜 Xcode 의 Simulator 화면 앱 경로(이전 Xcode 의 위치).
String buildSimulatorAppPath(String base) =>
    '${buildDeveloperDir(base)}/Applications/Simulator.app';

/// 시뮬레이터 켜기 경로의 명령(simctl · xcode-select · open) 호출 수를 센다.
int countSimulatorStartCalls(FakeCommandRunner runner) => runner.calls
    .where(
      (FakeCall call) =>
          call.key.startsWith('xcrun simctl') ||
          call.key.startsWith('open ') ||
          call.key == 'xcode-select -p',
    )
    .length;

/// Flutter 에뮬레이터 명령 호출 수를 센다(실행 대상 찾기에 쓰지 않는다).
int countEmulatorCommandCalls(FakeCommandRunner runner) => runner.calls
    .where((FakeCall call) => call.key.contains('emulators'))
    .length;

/// batchGet 사용자 한 명을 만든다.
Map<String, Object?> buildUser({
  required String localId,
  String? email,
  bool isEmailVerified = false,
  List<String> providers = const <String>[],
  String? displayName,
}) => <String, Object?>{
  'localId': localId,
  'email': ?email,
  'emailVerified': isEmailVerified,
  'displayName': ?displayName,
  'providerUserInfo': <Object?>[
    for (final String provider in providers)
      <String, Object?>{
        'providerId': provider,
        'email': ?email,
        'rawId': ?email,
      },
  ],
};

/// 인증된 이메일 사용자 한 명.
Map<String, Object?> buildVerifiedUser(String localId) => buildUser(
  localId: localId,
  email: '$localId@example.invalid',
  isEmailVerified: true,
  providers: const <String>['password'],
);

/// batchGet 응답 본문을 만든다.
RestResponse buildPage(
  List<Map<String, Object?>> users, {
  String? nextPageToken,
}) => RestResponse(
  200,
  jsonEncode(<String, Object?>{
    'kind': 'identitytoolkit#DownloadAccountResponse',
    if (users.isNotEmpty) 'users': users,
    'nextPageToken': ?nextPageToken,
  }),
);

/// 위저드 한 번 실행에 쓰는 가짜 실행기 · 화면 · 기록 · REST 묶음.
final class _Harness {
  _Harness(this.root, List<String?> inputs)
    : runner = FakeCommandRunner(),
      rest = FakeRestClient(),
      screen = ScriptedTerminal(inputs);

  final String root;
  final FakeCommandRunner runner;
  final FakeRestClient rest;
  final ScriptedTerminal screen;
  final List<Duration> delays = <Duration>[];
  late final WizardContext context = buildTestContext(
    projectRoot: root,
    runner: runner,
    terminal: screen,
    rest: rest,
  );

  /// 화면 출력 전체.
  String get output => screen.output.toString();

  /// 실행 기록 전체.
  String get logText => (context.log as MemoryLogSink).text;

  /// 첫 페이지 batchGet 주소.
  String get firstPageUrl =>
      RunStep.buildBatchGetRequest(projectId).url.toString();

  /// 앞 단계(끝남) · 실행 단계로 위저드를 돌린다.
  Future<int> run() => runWizard(context, <Step>[
    _FinishedStep('configure', '앱 등록 · 설정 파일'),
    _FinishedStep('sign_in', '로그인 수단 (이메일 · 익명)'),
    _FinishedStep('rules', 'Firestore · Storage rules'),
    _FinishedStep('app_check', 'App Check 디버그 토큰'),
    _FinishedStep('functions', 'Cloud Functions 배포'),
    RunStep(
      delay: (Duration duration) async {
        delays.add(duration);
      },
    ),
  ]);

  /// 할 일 경로의 앞 명령(pub get · 코드 생성)을 성공으로 등록한다.
  void registerPreparation() {
    runner
      ..on(
        FakeCommandRunner.buildKey(RunStep.buildPubGetCommand()),
        const CommandResult(0, 'Got dependencies!\n', ''),
      )
      ..on(
        FakeCommandRunner.buildKey(RunStep.buildCodegenCommand()),
        const CommandResult(0, 'Built with build_runner\n', ''),
      );
  }

  /// 기기 목록 명령의 결과 큐에 [result] 를 더한다.
  void registerDevices(CommandResult result) {
    runner.on(
      FakeCommandRunner.buildKey(RunStep.buildDevicesCommand()),
      result,
    );
  }

  /// [deviceId] 로 실행하는 명령의 결과를 등록한다.
  void registerRun(String deviceId, int exitCode) {
    runner.on(
      FakeCommandRunner.buildKey(RunStep.buildRunCommand(deviceId)),
      CommandResult(exitCode, '', ''),
    );
  }

  /// simctl 기기 목록 명령의 결과를 등록한다.
  void registerSimulatorList(CommandResult result) {
    runner.on(FakeCommandRunner.buildKey(RunStep.simulatorListCommand), result);
  }

  /// `xcode-select -p` 가 [developerDir] 를 돌려주게 등록한다.
  void registerDeveloperDir(String developerDir) {
    runner.on(
      FakeCommandRunner.buildKey(RunStep.developerDirCommand),
      CommandResult(0, '$developerDir\n', ''),
    );
  }

  /// [udid] 시뮬레이터를 켜는 명령의 결과를 등록한다.
  void registerBoot(String udid, CommandResult result) {
    runner.on(
      FakeCommandRunner.buildKey(RunStep.buildBootSimulatorCommand(udid)),
      result,
    );
  }

  /// [appPath] 화면 앱을 여는 명령의 결과를 등록한다.
  void registerOpen(String appPath, CommandResult result) {
    runner.on(
      FakeCommandRunner.buildKey(RunStep.buildOpenScreenAppCommand(appPath)),
      result,
    );
  }

  /// stream 으로 부른 명령 키(순서대로).
  List<String> get streamKeys => <String>[
    for (final FakeCall call in runner.calls)
      if (call.mode == RunMode.stream) call.key,
  ];
}

/// 화면 앱 디렉터리를 만든다 — 테스트 임시 디렉터리 아래에서만 부른다.
void createScreenApp(String appPath) {
  Directory(appPath).createSync(recursive: true);
}

void main() {
  late Directory tempDir;
  late String root;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('run_step_test_');
    root = tempDir.path;
    File('$root/${UserFilesStep.jsonUserPath}')
      ..parent.createSync(recursive: true)
      ..writeAsStringSync(
        '${jsonEncode(<String, Object?>{'firebaseProjectId': projectId, 'enabledAuthProviders': ''})}\n',
      );
  });

  tearDown(() {
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  test('단계 모양 · 목록 위치 — functions 바로 뒤 · 마지막', () {
    final RunStep step = RunStep();
    expect(step.id, 'run');
    expect(step.title, '앱 실행 · 로그인 확인');
    expect(
      step.dependsOn,
      containsAll(<String>[
        'functions',
        'app_check',
        'sign_in',
        'rules',
        'configure',
      ]),
    );
    final List<String> ids = <String>[
      for (final Step devStep in buildDevSteps()) devStep.id,
    ];
    expect(ids.indexOf('run'), ids.indexOf('functions') + 1);
  });

  test('명령 · 요청 모양 — dev config · 시뮬레이터 · 민감 응답', () {
    expect(
      FakeCommandRunner.buildKey(RunStep.buildRunCommand('x')),
      'fvm flutter run --flavor dev '
      '--dart-define-from-file=config/dev.json -d x',
    );
    expect(
      FakeCommandRunner.buildKey(RunStep.simulatorListCommand),
      'xcrun simctl list devices available -j',
    );
    expect(
      FakeCommandRunner.buildKey(RunStep.buildBootSimulatorCommand('x')),
      'xcrun simctl boot x',
    );
    expect(
      FakeCommandRunner.buildKey(RunStep.developerDirCommand),
      'xcode-select -p',
    );
    expect(
      FakeCommandRunner.buildKey(
        RunStep.buildOpenScreenAppCommand('/x/DeviceHub.app'),
      ),
      'open -a /x/DeviceHub.app',
    );
    // 공백이 든 경로도 셸 없이 인자 하나로 넘긴다.
    expect(
      RunStep.buildOpenScreenAppCommand('/x y/DeviceHub.app').arguments,
      <String>['-a', '/x y/DeviceHub.app'],
    );
    final RestRequest first = RunStep.buildBatchGetRequest(projectId);
    expect(first.method, 'GET');
    expect(
      first.url.toString(),
      'https://identitytoolkit.googleapis.com/v1/projects/$projectId/'
      'accounts:batchGet?maxResults=1000',
    );
    expect(first.isResponseSensitive, isTrue);
    expect(first.quotaProject, projectId);
    expect(
      RunStep.buildBatchGetRequest(projectId, pageToken: 'a/b=').url.toString(),
      'https://identitytoolkit.googleapis.com/v1/projects/$projectId/'
      'accounts:batchGet?maxResults=1000&nextPageToken=a%2Fb%3D',
    );
  });

  test('T-19-RUN-01: 인증 password 1 · 미인증 1 · 익명 1 → ✓ 1명 · 실행 0', () async {
    final _Harness harness = _Harness(root, const <String?>[]);
    harness.rest.on(
      'GET',
      harness.firstPageUrl,
      buildPage(<Map<String, Object?>>[
        buildVerifiedUser('u1'),
        buildUser(
          localId: 'u2',
          email: 'u2@example.invalid',
          providers: const <String>['password'],
        ),
        buildUser(localId: 'u3'),
      ]),
    );

    final int code = await harness.run();

    expect(code, wizardExitDone);
    expect(harness.output, contains('  ✓ 앱 실행 · 로그인 확인 — 인증된 이메일 사용자 1명'));
    expect(harness.runner.countMode(RunMode.stream), 0);
    expect(harness.runner.countMode(RunMode.interactive), 0);
    expect(harness.runner.countMode(RunMode.capture), 0);
  });

  test('T-19-RUN-01 보강: 인증됐어도 password provider 가 없으면 세지 않는다', () async {
    final _Harness harness = _Harness(root, const <String?>[null]);
    harness.rest.on(
      'GET',
      harness.firstPageUrl,
      buildPage(<Map<String, Object?>>[
        buildUser(
          localId: 'g1',
          email: 'g1@example.invalid',
          isEmailVerified: true,
          providers: const <String>['google.com'],
        ),
      ]),
    );

    final int code = await harness.run();

    expect(code, wizardExitStopped);
    expect(harness.output, contains('  ✗ 앱 실행 · 로그인 확인 — 인증된 이메일 사용자가 없습니다'));
  });

  test('T-19-RUN-02: nextPageToken 두 페이지 → 두 페이지 모두 요청 · 합계', () async {
    final _Harness harness = _Harness(root, const <String?>[]);
    const String token = 'page/2+=';
    harness.rest
      ..on(
        'GET',
        harness.firstPageUrl,
        buildPage(<Map<String, Object?>>[
          buildVerifiedUser('u1'),
        ], nextPageToken: token),
      )
      ..on(
        'GET',
        RunStep.buildBatchGetRequest(
          projectId,
          pageToken: token,
        ).url.toString(),
        buildPage(<Map<String, Object?>>[
          buildVerifiedUser('u2'),
          buildVerifiedUser('u3'),
        ]),
      );

    final int code = await harness.run();

    expect(code, wizardExitDone);
    expect(harness.output, contains('인증된 이메일 사용자 3명'));
    expect(harness.rest.countRequests('GET', harness.firstPageUrl), 1);
    expect(
      harness.rest.countRequests(
        'GET',
        'https://identitytoolkit.googleapis.com/v1/projects/$projectId/'
            'accounts:batchGet?maxResults=1000&nextPageToken=page%2F2%2B%3D',
      ),
      1,
    );
    for (final RestRequest request in harness.rest.requests) {
      expect(request.isResponseSensitive, isTrue);
    }
  });

  test('T-19-RUN-03: 0명 → y → pub get → 코드 생성 → iOS 만 고르기 · 기본 1번 → '
      '할 일 → interactive 실행 → 1명 ✓', () async {
    final _Harness harness = _Harness(root, const <String?>['y', '']);
    harness.rest
      ..on(
        'GET',
        harness.firstPageUrl,
        buildPage(const <Map<String, Object?>>[]),
      )
      ..on(
        'GET',
        harness.firstPageUrl,
        buildPage(const <Map<String, Object?>>[]),
      )
      ..on(
        'GET',
        harness.firstPageUrl,
        buildPage(<Map<String, Object?>>[buildVerifiedUser('u1')]),
      );
    harness
      ..registerPreparation()
      ..registerDevices(
        buildDevicesOutput(<Map<String, Object?>>[
          buildSimulator(),
          buildMacOs(),
          buildChrome(),
        ]),
      )
      ..registerRun(simulatorId, 0);

    final int code = await harness.run();
    final String output = harness.output;

    expect(code, wizardExitDone);
    expect(output, contains('  ✗ 앱 실행 · 로그인 확인 — 인증된 이메일 사용자가 없습니다'));
    final List<String> streamKeys = <String>[
      for (final FakeCall call in harness.runner.calls)
        if (call.mode == RunMode.stream) call.key,
    ];
    expect(streamKeys, <String>[
      'fvm flutter pub get',
      'fvm dart run build_runner build --delete-conflicting-outputs',
    ]);
    expect(
      harness.runner.countCalls(
        RunMode.capture,
        'fvm flutter devices --machine',
      ),
      1,
    );
    expect(harness.screen.asks, contains(RunStep.targetChoiceQuestion));
    expect(output, contains('  1) iPhone 17 (iOS 시뮬레이터)'));
    expect(output, isNot(contains('  2) ')));
    expect(output, isNot(contains('macOS (')));
    expect(output, isNot(contains('Chrome (')));
    expect(output, contains('스팸함'));
    expect(output, contains(RunStep.quitLine));
    expect(
      harness.runner.countCalls(
        RunMode.interactive,
        'fvm flutter run --flavor dev --dart-define-from-file=config/dev.json '
        '-d $simulatorId',
      ),
      1,
    );
    // 대상이 처음부터 있으면 시뮬레이터를 켜지 않는다.
    expect(countSimulatorStartCalls(harness.runner), 0);
    expect(countEmulatorCommandCalls(harness.runner), 0);
    expect(output.indexOf('스팸함'), lessThan(output.lastIndexOf('✓ 앱 실행')));
    expect(output, contains('  ✓ 앱 실행 · 로그인 확인 — 인증된 이메일 사용자 1명'));
    // 시뮬레이터 UDID 는 고르기 목록에 보이지 않는다.
    expect(output, isNot(contains(simulatorId)));
  });

  test('T-19-RUN-03 변형: 기본값 = 목록의 첫 iOS 시뮬레이터 · iOS 실기기만 있으면 1번', () async {
    final _Harness mixed = _Harness(root, const <String?>['y', '']);
    mixed.rest
      ..on('GET', mixed.firstPageUrl, buildPage(const <Map<String, Object?>>[]))
      ..on('GET', mixed.firstPageUrl, buildPage(const <Map<String, Object?>>[]))
      ..on(
        'GET',
        mixed.firstPageUrl,
        buildPage(<Map<String, Object?>>[buildVerifiedUser('u1')]),
      );
    mixed
      ..registerPreparation()
      ..registerDevices(
        buildDevicesOutput(<Map<String, Object?>>[
          buildDevice(
            name: 'Test iPhone',
            id: iosDeviceId,
            targetPlatform: 'ios',
            isEmulator: false,
          ),
          buildDevice(
            name: 'sdk gphone64 arm64',
            id: androidEmulatorId,
            targetPlatform: 'android-arm64',
            isEmulator: true,
          ),
          buildDevice(
            name: 'Unsupported Phone',
            id: 'unsupported',
            targetPlatform: 'android-arm64',
            isEmulator: false,
            isSupported: false,
          ),
          buildSimulator(),
          buildMacOs(),
        ]),
      )
      ..registerRun(simulatorId, 0);

    expect(await mixed.run(), wizardExitDone);
    expect(mixed.output, contains('  1) Test iPhone (iOS 기기)'));
    expect(mixed.output, contains('  2) sdk gphone64 arm64 (Android 에뮬레이터)'));
    expect(mixed.output, contains('  3) iPhone 17 (iOS 시뮬레이터)'));
    expect(mixed.output, isNot(contains('Unsupported Phone')));
    expect(mixed.output, isNot(contains('  4) ')));
    expect(
      mixed.runner.countCalls(
        RunMode.interactive,
        FakeCommandRunner.buildKey(RunStep.buildRunCommand(simulatorId)),
      ),
      1,
    );

    final Directory other = Directory.systemTemp.createTempSync(
      'run_step_dev_',
    );
    addTearDown(() => other.deleteSync(recursive: true));
    File('${other.path}/${UserFilesStep.jsonUserPath}')
      ..parent.createSync(recursive: true)
      ..writeAsStringSync(
        '${jsonEncode(<String, Object?>{'firebaseProjectId': projectId})}\n',
      );
    final _Harness deviceOnly = _Harness(other.path, const <String?>['y', '']);
    deviceOnly.rest
      ..on(
        'GET',
        deviceOnly.firstPageUrl,
        buildPage(const <Map<String, Object?>>[]),
      )
      ..on(
        'GET',
        deviceOnly.firstPageUrl,
        buildPage(const <Map<String, Object?>>[]),
      )
      ..on(
        'GET',
        deviceOnly.firstPageUrl,
        buildPage(<Map<String, Object?>>[buildVerifiedUser('u1')]),
      );
    deviceOnly
      ..registerPreparation()
      ..registerDevices(
        buildDevicesOutput(<Map<String, Object?>>[
          buildDevice(
            name: 'Test iPhone',
            id: iosDeviceId,
            targetPlatform: 'ios',
            isEmulator: false,
          ),
          buildMacOs(),
          buildChrome(),
        ]),
      )
      ..registerRun(iosDeviceId, 0);

    expect(await deviceOnly.run(), wizardExitDone);
    expect(deviceOnly.output, contains('  1) Test iPhone (iOS 기기)'));
    expect(countSimulatorStartCalls(deviceOnly.runner), 0);
    expect(countEmulatorCommandCalls(deviceOnly.runner), 0);
    expect(
      deviceOnly.runner.countCalls(
        RunMode.interactive,
        FakeCommandRunner.buildKey(RunStep.buildRunCommand(iosDeviceId)),
      ),
      1,
    );
  });

  test('T-19-RUN-04: 대상 0 → simctl 목록 → iPhone 켜기 → 화면 앱 열기 → 기다린 뒤 '
      '재조회 → 대상 1 → 진행', () async {
    final _Harness harness = _Harness(root, const <String?>['y', '']);
    harness.rest
      ..on(
        'GET',
        harness.firstPageUrl,
        buildPage(const <Map<String, Object?>>[]),
      )
      ..on(
        'GET',
        harness.firstPageUrl,
        buildPage(const <Map<String, Object?>>[]),
      )
      ..on(
        'GET',
        harness.firstPageUrl,
        buildPage(<Map<String, Object?>>[buildVerifiedUser('u1')]),
      );
    final String deviceHub = buildDeviceHubPath(root);
    createScreenApp(deviceHub);
    harness
      ..registerPreparation()
      ..registerDevices(
        buildDevicesOutput(<Map<String, Object?>>[buildMacOs(), buildChrome()]),
      )
      ..registerDevices(
        buildDevicesOutput(<Map<String, Object?>>[buildMacOs()]),
      )
      ..registerDevices(
        buildDevicesOutput(<Map<String, Object?>>[
          buildMacOs(),
          buildSimulator(),
        ]),
      )
      ..registerSimulatorList(
        buildSimctlOutput(<String, List<Map<String, Object?>>>{
          buildIosRuntimeKey(26, 4): <Map<String, Object?>>[
            buildSimDevice(name: 'Sim iPhone A', udid: iphoneUdid),
            buildSimDevice(name: 'Sim iPhone B', udid: otherIphoneUdid),
            buildSimDevice(
              name: 'Sim iPad',
              udid: ipadUdid,
              deviceType: 'iPad-Air-11-inch-M3',
            ),
          ],
        }),
      )
      ..registerDeveloperDir(buildDeveloperDir(root))
      ..registerBoot(iphoneUdid, const CommandResult(0, '', ''))
      ..registerOpen(deviceHub, const CommandResult(0, '', ''))
      ..registerRun(simulatorId, 0);

    final int code = await harness.run();
    final String output = harness.output;

    expect(code, wizardExitDone);
    expect(harness.streamKeys, <String>[
      'fvm flutter pub get',
      'fvm dart run build_runner build --delete-conflicting-outputs',
      'xcrun simctl boot $iphoneUdid',
      'open -a $deviceHub',
    ]);
    expect(
      harness.runner.countCalls(
        RunMode.capture,
        'xcrun simctl list devices available -j',
      ),
      1,
    );
    expect(harness.runner.countCalls(RunMode.capture, 'xcode-select -p'), 1);
    expect(countEmulatorCommandCalls(harness.runner), 0);
    expect(
      harness.runner.countCalls(
        RunMode.capture,
        'fvm flutter devices --machine',
      ),
      3,
    );
    expect(harness.delays, hasLength(2));
    expect(harness.delays.first, RunStep.launchPollInterval);
    expect(output, contains('iOS 시뮬레이터를 켜고 화면 앱을 엽니다 — Sim iPhone A'));
    expect(output, contains('  1) iPhone 17 (iOS 시뮬레이터)'));
    expect(output, contains('인증된 이메일 사용자 1명'));
    // 시뮬레이터 UDID 는 화면에 쓰지 않는다(가려진 자리표시도 없다).
    for (final String udid in <String>[iphoneUdid, otherIphoneUdid, ipadUdid]) {
      expect(output, isNot(contains(udid)));
    }
    expect(output, isNot(contains(Redactor.mask)));
  });

  test('T-19-RUN-04 보강: 켜고 화면 앱을 연 뒤에도 대상이 끝내 없으면 실패 · 실행 0', () async {
    final _Harness harness = _Harness(root, const <String?>['y', '']);
    harness.rest.on(
      'GET',
      harness.firstPageUrl,
      buildPage(const <Map<String, Object?>>[]),
    );
    final String deviceHub = buildDeviceHubPath(root);
    createScreenApp(deviceHub);
    harness
      ..registerPreparation()
      ..registerDevices(
        buildDevicesOutput(<Map<String, Object?>>[buildMacOs()]),
      )
      ..registerSimulatorList(
        buildSimctlOutput(<String, List<Map<String, Object?>>>{
          buildIosRuntimeKey(26, 4): <Map<String, Object?>>[
            buildSimDevice(name: 'Sim iPhone A', udid: iphoneUdid),
          ],
        }),
      )
      ..registerDeveloperDir(buildDeveloperDir(root))
      ..registerBoot(iphoneUdid, const CommandResult(0, '', ''))
      ..registerOpen(deviceHub, const CommandResult(0, '', ''));

    final int code = await harness.run();

    expect(code, wizardExitStopped);
    expect(harness.delays, hasLength(RunStep.maxLaunchPolls));
    expect(
      harness.runner.countCalls(
        RunMode.stream,
        'xcrun simctl boot $iphoneUdid',
      ),
      1,
    );
    expect(harness.runner.countCalls(RunMode.stream, 'open -a $deviceHub'), 1);
    expect(harness.output, contains('  실패 — ${RunStep.noTargetSummary}'));
    expect(harness.runner.countMode(RunMode.interactive), 0);
  });

  test('시뮬레이터 켜기 · 화면 앱 열기 실패 → 그 결과 원문과 함께 실패 · 재조회 · 실행 0', () async {
    for (final bool isBootFailing in <bool>[true, false]) {
      final _Harness harness = _Harness(root, const <String?>['y', '']);
      harness.rest.on(
        'GET',
        harness.firstPageUrl,
        buildPage(const <Map<String, Object?>>[]),
      );
      final String deviceHub = buildDeviceHubPath(root);
      createScreenApp(deviceHub);
      harness
        ..registerPreparation()
        ..registerDevices(
          buildDevicesOutput(<Map<String, Object?>>[buildMacOs()]),
        )
        ..registerSimulatorList(
          buildSimctlOutput(<String, List<Map<String, Object?>>>{
            buildIosRuntimeKey(26, 4): <Map<String, Object?>>[
              buildSimDevice(name: 'Sim iPhone A', udid: iphoneUdid),
            ],
          }),
        )
        ..registerDeveloperDir(buildDeveloperDir(root))
        ..registerBoot(
          iphoneUdid,
          isBootFailing
              ? const CommandResult(149, '', 'boot error text\n')
              : const CommandResult(0, '', ''),
        )
        ..registerOpen(
          deviceHub,
          const CommandResult(1, '', 'open error text\n'),
        );

      final int code = await harness.run();

      expect(code, wizardExitStopped);
      expect(
        harness.output,
        contains(
          isBootFailing
              ? '  실패 — iOS 시뮬레이터를 켜지 못했습니다'
              : '  실패 — 시뮬레이터 화면 앱을 열지 못했습니다',
        ),
      );
      expect(
        harness.output,
        contains(isBootFailing ? 'boot error text' : 'open error text'),
      );
      expect(
        harness.runner.countCalls(RunMode.stream, 'open -a $deviceHub'),
        isBootFailing ? 0 : 1,
      );
      expect(harness.delays, isEmpty);
      expect(harness.runner.countMode(RunMode.interactive), 0);
    }
  });

  test('T-19-RUN-07: 켜진 iPhone 이 있으면 boot 없이 화면 앱만 열고 재조회 뒤 진행', () async {
    final _Harness harness = _Harness(root, const <String?>['y', '']);
    harness.rest
      ..on(
        'GET',
        harness.firstPageUrl,
        buildPage(const <Map<String, Object?>>[]),
      )
      ..on(
        'GET',
        harness.firstPageUrl,
        buildPage(const <Map<String, Object?>>[]),
      )
      ..on(
        'GET',
        harness.firstPageUrl,
        buildPage(<Map<String, Object?>>[buildVerifiedUser('u1')]),
      );
    final String deviceHub = buildDeviceHubPath(root);
    createScreenApp(deviceHub);
    harness
      ..registerPreparation()
      ..registerDevices(
        buildDevicesOutput(<Map<String, Object?>>[buildMacOs()]),
      )
      ..registerDevices(
        buildDevicesOutput(<Map<String, Object?>>[
          buildMacOs(),
          buildSimulator(),
        ]),
      )
      ..registerSimulatorList(
        buildSimctlOutput(<String, List<Map<String, Object?>>>{
          buildIosRuntimeKey(27, 0): <Map<String, Object?>>[
            buildSimDevice(name: 'Sim iPhone New', udid: otherIphoneUdid),
          ],
          buildIosRuntimeKey(26, 4): <Map<String, Object?>>[
            buildSimDevice(
              name: 'Sim iPhone Booted',
              udid: iphoneUdid,
              state: 'Booted',
            ),
          ],
        }),
      )
      ..registerDeveloperDir(buildDeveloperDir(root))
      ..registerOpen(deviceHub, const CommandResult(0, '', ''))
      ..registerRun(simulatorId, 0);

    final int code = await harness.run();

    expect(code, wizardExitDone);
    expect(harness.streamKeys, <String>[
      'fvm flutter pub get',
      'fvm dart run build_runner build --delete-conflicting-outputs',
      'open -a $deviceHub',
    ]);
    expect(
      harness.output,
      contains('이미 켜진 iOS 시뮬레이터의 화면 앱을 엽니다 — Sim iPhone Booted'),
    );
    expect(harness.delays, hasLength(1));
    expect(harness.output, contains('인증된 이메일 사용자 1명'));
  });

  test('T-19-RUN-08: 쓸 수 있는 iPhone 이 없거나 목록을 못 읽으면 boot · open 없이 '
      '안내와 함께 실패', () async {
    final Map<String, List<Map<String, Object?>>> noIphone =
        <String, List<Map<String, Object?>>>{
          buildWatchRuntimeKey(11, 0): <Map<String, Object?>>[
            buildSimDevice(
              name: 'Sim Watch',
              udid: buildUdid(1),
              deviceType: 'Apple-Watch-Series-11-46mm',
            ),
          ],
          buildIosRuntimeKey(26, 4): <Map<String, Object?>>[
            buildSimDevice(
              name: 'Sim iPad',
              udid: ipadUdid,
              deviceType: 'iPad-Air-11-inch-M3',
            ),
            buildSimDevice(
              name: 'Sim iPhone Broken',
              udid: iphoneUdid,
              isAvailable: false,
            ),
          ],
        };
    for (final CommandResult list in <CommandResult>[
      buildSimctlOutput(noIphone),
      const CommandResult(1, '', 'simctl list error text\n'),
    ]) {
      final _Harness harness = _Harness(root, const <String?>['y', '']);
      harness.rest.on(
        'GET',
        harness.firstPageUrl,
        buildPage(const <Map<String, Object?>>[]),
      );
      harness
        ..registerPreparation()
        ..registerDevices(
          buildDevicesOutput(<Map<String, Object?>>[buildMacOs()]),
        )
        ..registerSimulatorList(list);

      final int code = await harness.run();

      expect(code, wizardExitStopped);
      expect(harness.output, contains('  실패 — ${RunStep.noSimulatorSummary}'));
      expect(
        RunStep.noSimulatorSummary,
        startsWith('쓸 수 있는 iPhone 시뮬레이터가 없습니다'),
      );
      // 목록 명령 하나만 불렀다 — 개발자 디렉터리 · 켜기 · 열기 0.
      expect(countSimulatorStartCalls(harness.runner), 1);
      expect(harness.delays, isEmpty);
      expect(harness.runner.countMode(RunMode.interactive), 0);
      if (!list.isSuccess) {
        expect(harness.output, contains('simctl list error text'));
      }
    }
  });

  test('T-19-RUN-09: 화면 앱 = DeviceHub.app → Simulator.app 순서 · 둘 다 없으면 '
      'boot 없이 실패', () async {
    final String both = '$root/both';
    createScreenApp(buildDeviceHubPath(both));
    createScreenApp(buildSimulatorAppPath(both));
    expect(
      RunStep.findScreenAppPath('${buildDeveloperDir(both)}\n'),
      buildDeviceHubPath(both),
    );
    expect(
      RunStep.findScreenAppPath('${buildDeveloperDir(both)}/'),
      buildDeviceHubPath(both),
    );
    expect(RunStep.findScreenAppPath(''), isNull);
    expect(RunStep.findScreenAppPath('Xcode.app/Contents/Developer'), isNull);

    // 이전 Xcode — 개발자 디렉터리 아래 Simulator.app 만 있다.
    final String old = '$root/old';
    createScreenApp(buildSimulatorAppPath(old));
    expect(
      RunStep.findScreenAppPath(buildDeveloperDir(old)),
      buildSimulatorAppPath(old),
    );
    final _Harness oldXcode = _Harness(root, const <String?>['y', '']);
    oldXcode.rest
      ..on(
        'GET',
        oldXcode.firstPageUrl,
        buildPage(const <Map<String, Object?>>[]),
      )
      ..on(
        'GET',
        oldXcode.firstPageUrl,
        buildPage(const <Map<String, Object?>>[]),
      )
      ..on(
        'GET',
        oldXcode.firstPageUrl,
        buildPage(<Map<String, Object?>>[buildVerifiedUser('u1')]),
      );
    oldXcode
      ..registerPreparation()
      ..registerDevices(
        buildDevicesOutput(<Map<String, Object?>>[buildMacOs()]),
      )
      ..registerDevices(
        buildDevicesOutput(<Map<String, Object?>>[buildSimulator()]),
      )
      ..registerSimulatorList(
        buildSimctlOutput(<String, List<Map<String, Object?>>>{
          buildIosRuntimeKey(26, 4): <Map<String, Object?>>[
            buildSimDevice(name: 'Sim iPhone A', udid: iphoneUdid),
          ],
        }),
      )
      ..registerDeveloperDir(buildDeveloperDir(old))
      ..registerBoot(iphoneUdid, const CommandResult(0, '', ''))
      ..registerOpen(buildSimulatorAppPath(old), const CommandResult(0, '', ''))
      ..registerRun(simulatorId, 0);
    expect(await oldXcode.run(), wizardExitDone);
    expect(oldXcode.streamKeys.last, 'open -a ${buildSimulatorAppPath(old)}');

    // 화면 앱이 없다 — 켜지 않는다.
    final String none = '$root/none';
    final _Harness noApp = _Harness(root, const <String?>['y', '']);
    noApp.rest.on(
      'GET',
      noApp.firstPageUrl,
      buildPage(const <Map<String, Object?>>[]),
    );
    noApp
      ..registerPreparation()
      ..registerDevices(
        buildDevicesOutput(<Map<String, Object?>>[buildMacOs()]),
      )
      ..registerSimulatorList(
        buildSimctlOutput(<String, List<Map<String, Object?>>>{
          buildIosRuntimeKey(26, 4): <Map<String, Object?>>[
            buildSimDevice(name: 'Sim iPhone A', udid: iphoneUdid),
          ],
        }),
      )
      ..registerDeveloperDir(buildDeveloperDir(none));
    expect(await noApp.run(), wizardExitStopped);
    expect(noApp.output, contains('  실패 — ${RunStep.noScreenAppSummary}'));
    expect(
      noApp.runner.calls.where(
        (FakeCall call) =>
            call.key.startsWith('xcrun simctl boot') ||
            call.key.startsWith('open '),
      ),
      isEmpty,
    );
    expect(noApp.runner.countCalls(RunMode.capture, 'xcode-select -p'), 1);
    expect(noApp.delays, isEmpty);
    expect(noApp.runner.countMode(RunMode.interactive), 0);
  });

  test('T-19-RUN-10: pickSimulator — 켜진 iPhone 우선 · 가장 높은 iOS 판의 첫 '
      '쓸 수 있는 iPhone · 해석 실패는 null', () {
    // JSON 키 순서는 판 순서가 아니다 — 판 번호를 숫자로 비교한다.
    final SimulatorPick? latest = RunStep.pickSimulator(
      buildSimctlJson(<String, List<Map<String, Object?>>>{
        buildWatchRuntimeKey(11, 0): <Map<String, Object?>>[
          // watchOS 런타임 아래 항목은 보지 않는다(켜져 있어도).
          buildSimDevice(
            name: 'Sim Under Watch',
            udid: buildUdid(1),
            state: 'Booted',
          ),
        ],
        buildIosRuntimeKey(26, 4): <Map<String, Object?>>[
          buildSimDevice(name: 'Sim iPhone 26.4', udid: buildUdid(2)),
        ],
        buildIosRuntimeKey(27, 0): <Map<String, Object?>>[
          buildSimDevice(
            name: 'Sim iPad 27',
            udid: buildUdid(3),
            deviceType: 'iPad-Pro-13-inch-M5',
          ),
          buildSimDevice(
            name: 'Sim iPhone 27 Broken',
            udid: buildUdid(4),
            isAvailable: false,
          ),
          buildSimDevice(name: 'Sim iPhone 27', udid: buildUdid(5)),
          buildSimDevice(name: 'Sim iPhone 27 Second', udid: buildUdid(6)),
        ],
        buildIosRuntimeKey(26, 5): <Map<String, Object?>>[
          buildSimDevice(name: 'Sim iPhone 26.5', udid: buildUdid(7)),
        ],
      }),
    );
    expect(latest?.name, 'Sim iPhone 27');
    expect(latest?.udid, buildUdid(5));
    expect(latest?.isBooted, isFalse);

    // 두 자리 판도 숫자로 비교한다(9 < 10).
    expect(
      RunStep.pickSimulator(
        buildSimctlJson(<String, List<Map<String, Object?>>>{
          buildIosRuntimeKey(9, 3): <Map<String, Object?>>[
            buildSimDevice(name: 'Sim iPhone 9.3', udid: buildUdid(8)),
          ],
          buildIosRuntimeKey(10, 0): <Map<String, Object?>>[
            buildSimDevice(name: 'Sim iPhone 10.0', udid: buildUdid(9)),
          ],
        }),
      )?.name,
      'Sim iPhone 10.0',
    );

    // 가장 높은 판에 iPhone 이 없으면 다음 판으로 내려간다.
    expect(
      RunStep.pickSimulator(
        buildSimctlJson(<String, List<Map<String, Object?>>>{
          buildIosRuntimeKey(27, 0): <Map<String, Object?>>[
            buildSimDevice(
              name: 'Sim iPad 27',
              udid: buildUdid(10),
              deviceType: 'iPad-Air-11-inch-M3',
            ),
          ],
          buildIosRuntimeKey(26, 4): <Map<String, Object?>>[
            buildSimDevice(name: 'Sim iPhone 26.4', udid: buildUdid(11)),
          ],
        }),
      )?.name,
      'Sim iPhone 26.4',
    );

    // 켜진(또는 켜지는 중인) iPhone 은 낮은 판에 있어도 먼저 고른다.
    for (final String state in <String>['Booted', 'Booting']) {
      final SimulatorPick? running = RunStep.pickSimulator(
        buildSimctlJson(<String, List<Map<String, Object?>>>{
          buildIosRuntimeKey(27, 0): <Map<String, Object?>>[
            buildSimDevice(name: 'Sim iPhone 27', udid: buildUdid(12)),
          ],
          buildIosRuntimeKey(26, 4): <Map<String, Object?>>[
            buildSimDevice(
              name: 'Sim iPhone Running',
              udid: buildUdid(13),
              state: state,
            ),
          ],
        }),
      );
      expect(running?.name, 'Sim iPhone Running');
      expect(running?.isBooted, isTrue);
    }

    for (final String broken in <String>[
      'not json',
      '[]',
      '{}',
      '{"devices": []}',
      buildSimctlJson(const <String, List<Map<String, Object?>>>{}),
    ]) {
      expect(RunStep.pickSimulator(broken), isNull, reason: broken);
    }
  });

  test('계획 줄 — simctl 목록 · 개발자 디렉터리 · boot · 화면 앱 표시형 · '
      'Flutter 에뮬레이터 명령 0 · UDID 0', () async {
    final FakeRestClient rest = FakeRestClient()
      ..on(
        'GET',
        RunStep.buildBatchGetRequest(projectId).url.toString(),
        buildPage(const <Map<String, Object?>>[]),
      );
    final WizardContext context = buildTestContext(
      projectRoot: root,
      rest: rest,
    );
    final RunStep step = RunStep();

    expect(await step.check(context), isA<Todo>());
    final List<String> lines = step.plannedCommandLines(context);

    expect(
      lines,
      containsAllInOrder(<String>[
        'fvm flutter devices --machine',
        'xcrun simctl list devices available -j',
        'xcode-select -p',
        'xcrun simctl boot <고른 iPhone 시뮬레이터>',
        'open -a <Xcode 의 시뮬레이터 화면 앱>',
      ]),
    );
    expect(
      lines.where((String line) => line.contains('iPhone 시뮬레이터 하나를 켜고')),
      hasLength(1),
    );
    expect(lines.where((String line) => line.contains('emulators')), isEmpty);
    expect(
      lines.where(
        (String line) =>
            Redactor.patterns.any((RegExp pattern) => pattern.hasMatch(line)),
      ),
      isEmpty,
    );
  });

  test('T-19-RUN-05: flutter run exit 1 → 실패 「앱 실행이 실패했습니다」', () async {
    final _Harness harness = _Harness(root, const <String?>['y', '', '']);
    harness.rest.on(
      'GET',
      harness.firstPageUrl,
      buildPage(const <Map<String, Object?>>[]),
    );
    harness
      ..registerPreparation()
      ..registerDevices(
        buildDevicesOutput(<Map<String, Object?>>[buildSimulator()]),
      )
      ..registerRun(simulatorId, 1);

    final int code = await harness.run();

    expect(code, wizardExitStopped);
    expect(harness.output, contains('  실패 — 앱 실행이 실패했습니다'));
    expect(harness.screen.asks, contains(failureChoiceQuestion));
    // 실패한 실행 뒤에는 다시 세지 않는다(검사 = 점검표 · 단계 시작 2회).
    expect(harness.rest.countRequests('GET', harness.firstPageUrl), 2);
  });

  test('T-19-RUN-05 보강: 코드 생성 실패 → 실패 · 기기 조회 · 실행 0', () async {
    final _Harness harness = _Harness(root, const <String?>['y', '']);
    harness.rest.on(
      'GET',
      harness.firstPageUrl,
      buildPage(const <Map<String, Object?>>[]),
    );
    harness.runner
      ..on(
        FakeCommandRunner.buildKey(RunStep.buildPubGetCommand()),
        const CommandResult(0, '', ''),
      )
      ..on(
        FakeCommandRunner.buildKey(RunStep.buildCodegenCommand()),
        const CommandResult(1, '', 'build_runner failed\n'),
      );

    expect(await harness.run(), wizardExitStopped);
    expect(harness.output, contains('  실패 — 코드 생성이 실패했습니다'));
    expect(
      harness.runner.countCalls(
        RunMode.capture,
        'fvm flutter devices --machine',
      ),
      0,
    );
    expect(harness.runner.countMode(RunMode.interactive), 0);
  });

  test('T-19-RUN-06: 응답의 이메일 · uid · 표시 이름이 화면 · 기록에 0', () async {
    const String email = 'kit-person@example.invalid';
    const String uid = 'Xk3uidValue0123456789abcd';
    const String displayName = 'Kit Person Name';
    final _Harness harness = _Harness(root, const <String?>['y', '']);
    final RestResponse sensitive = buildPage(<Map<String, Object?>>[
      buildUser(
        localId: uid,
        email: email,
        isEmailVerified: true,
        providers: const <String>['password'],
        displayName: displayName,
      ),
    ]);
    harness.rest
      ..on(
        'GET',
        harness.firstPageUrl,
        buildPage(<Map<String, Object?>>[
          buildUser(
            localId: 'pending$uid',
            email: 'pending-$email',
            providers: const <String>['password'],
            displayName: displayName,
          ),
        ]),
      )
      ..on(
        'GET',
        harness.firstPageUrl,
        buildPage(<Map<String, Object?>>[
          buildUser(
            localId: 'pending$uid',
            email: 'pending-$email',
            providers: const <String>['password'],
            displayName: displayName,
          ),
        ]),
      )
      ..on('GET', harness.firstPageUrl, sensitive);
    harness
      ..registerPreparation()
      ..registerDevices(
        buildDevicesOutput(<Map<String, Object?>>[buildSimulator()]),
      )
      ..registerRun(simulatorId, 0);

    expect(await harness.run(), wizardExitDone);
    for (final String text in <String>[harness.output, harness.logText]) {
      expect(text, isNot(contains(email)));
      expect(text, isNot(contains(uid)));
      expect(text, isNot(contains(displayName)));
      expect(text, isNot(contains('example.invalid')));
    }
    expect(harness.output, contains('인증된 이메일 사용자 1명'));
  });

  test('요청 실패 → 할 일 사유 · 실행은 원문과 함께 실패(앱 실행 0)', () async {
    final _Harness harness = _Harness(root, const <String?>['y', '']);
    harness.rest.on(
      'GET',
      harness.firstPageUrl,
      const RestResponse(403, '{"error":{"status":"PERMISSION_DENIED"}}'),
    );

    expect(await harness.run(), wizardExitStopped);
    expect(harness.output, contains('사용자 목록을 읽지 못했습니다 — HTTP 403'));
    expect(harness.output, contains('PERMISSION_DENIED'));
    expect(harness.runner.countMode(RunMode.stream), 0);
    expect(harness.runner.countMode(RunMode.interactive), 0);
  });

  test('프로젝트 ID 를 읽지 못하면 할 일 · 요청 0', () async {
    File('$root/${UserFilesStep.jsonUserPath}').deleteSync();
    final _Harness harness = _Harness(root, const <String?>[null]);

    expect(await harness.run(), wizardExitStopped);
    expect(harness.output, contains('에서 프로젝트 ID 를 읽지 못했습니다'));
    expect(harness.rest.requests, isEmpty);
  });

  group('flavor 문맥', () {
    /// stg config 의 프로젝트 ID(가짜) — dev 와 다르다.
    const String stgProjectId = 'demo-stg';
    late FakeCommandRunner runner;
    late FakeRestClient rest;
    late ScriptedTerminal screen;

    /// [projectIdValue] 를 담은 [flavor] 사용자 config 를 쓴다.
    void writeFlavorConfig(Flavor flavor, String projectIdValue) {
      File('$root/${FlavorPaths(flavor).json}').writeAsStringSync(
        '${jsonEncode(<String, Object?>{'firebaseProjectId': projectIdValue, 'enabledAuthProviders': ''})}\n',
      );
    }

    /// [flavor] 문맥을 만든다 — 화면은 가림 터미널로 감싼다.
    WizardContext buildFlavorContext(
      Flavor flavor, [
      List<String?> inputs = const <String?>[],
    ]) {
      final MemoryLogSink log = MemoryLogSink(Redactor());
      screen = ScriptedTerminal(inputs);
      return WizardContext(
        projectRoot: root,
        runner: runner,
        terminal: RedactingTerminal(screen, log.redactor, log),
        redactor: log.redactor,
        log: log,
        rest: rest,
        flavor: flavor,
        random: Random(fixedTestRandomSeed),
        now: () => fixedTestNow,
      );
    }

    setUp(() {
      runner = FakeCommandRunner();
      rest = FakeRestClient();
      writeFlavorConfig(Flavor.stg, stgProjectId);
    });

    test(
      'T-20-FLAVOR-08: stg 실행 단계는 stg config 의 프로젝트로 사용자를 세고 stg flavor 로 앱을 띄운다',
      () async {
        final String stgPageUrl = RunStep.buildBatchGetRequest(
          stgProjectId,
        ).url.toString();
        rest
          ..on('GET', stgPageUrl, buildPage(const <Map<String, Object?>>[]))
          ..on('GET', stgPageUrl, buildPage(const <Map<String, Object?>>[]))
          ..on(
            'GET',
            stgPageUrl,
            buildPage(<Map<String, Object?>>[buildVerifiedUser('u1')]),
          );
        runner
          ..on(
            FakeCommandRunner.buildKey(RunStep.buildPubGetCommand()),
            const CommandResult(0, '', ''),
          )
          ..on(
            FakeCommandRunner.buildKey(RunStep.buildCodegenCommand()),
            const CommandResult(0, '', ''),
          )
          ..on(
            FakeCommandRunner.buildKey(RunStep.buildDevicesCommand()),
            buildDevicesOutput(<Map<String, Object?>>[buildSimulator()]),
          )
          // stg 키만 등록한다 — dev 명령을 부르면 StateError 로 실패한다.
          ..on(
            FakeCommandRunner.buildKey(
              RunStep.buildRunCommand(simulatorId, flavor: Flavor.stg),
            ),
            const CommandResult(0, '', ''),
          );
        final WizardContext context = buildFlavorContext(
          Flavor.stg,
          const <String?>['y', ''],
        );

        final int code = await runWizard(context, <Step>[
          _FinishedStep('configure', '앱 등록 · 설정 파일'),
          _FinishedStep('sign_in', '로그인 수단 (이메일 · 익명)'),
          _FinishedStep('rules', 'Firestore · Storage rules'),
          _FinishedStep('app_check', 'App Check 디버그 토큰'),
          _FinishedStep('functions', 'Cloud Functions 배포'),
          RunStep(delay: (Duration duration) async {}),
        ]);

        final String output = screen.output.toString();
        expect(code, wizardExitDone);
        expect(
          runner.countCalls(
            RunMode.interactive,
            'fvm flutter run --flavor stg '
            '--dart-define-from-file=config/stg.json -d $simulatorId',
          ),
          1,
        );
        expect(
          output,
          contains(
            'fvm flutter run --flavor stg '
            '--dart-define-from-file=config/stg.json -d <고른 기기>',
          ),
        );
        expect(output, isNot(contains('--flavor dev')));
        expect(output, isNot(contains('config/dev.json')));
        expect(rest.countRequests('GET', stgPageUrl), 3);
        expect(
          rest.requests.every(
            (RestRequest request) =>
                request.url.toString() == stgPageUrl &&
                request.quotaProject == stgProjectId,
          ),
          isTrue,
        );
        expect(output, contains('  ✓ 앱 실행 · 로그인 확인 — 인증된 이메일 사용자 1명'));
      },
    );

    test(
      'T-20-FLAVOR-08: stg 계획 줄 · 명령 키는 stg flavor 와 stg config 를 쓴다',
      () async {
        rest.on(
          'GET',
          RunStep.buildBatchGetRequest(stgProjectId).url.toString(),
          buildPage(const <Map<String, Object?>>[]),
        );
        final WizardContext context = buildFlavorContext(Flavor.stg);
        final RunStep step = RunStep();

        expect(await step.check(context), isA<Todo>());
        final List<String> lines = step.plannedCommandLines(context);

        expect(
          lines,
          contains(
            'fvm flutter run --flavor stg '
            '--dart-define-from-file=config/stg.json -d <고른 기기>',
          ),
        );
        expect(
          lines,
          contains(RunStep.buildBatchGetRequest(stgProjectId).displayCurl()),
        );
        expect(
          FakeCommandRunner.buildKey(
            RunStep.buildRunCommand('x', flavor: Flavor.prod),
          ),
          'fvm flutter run --flavor prod '
          '--dart-define-from-file=config/prod.json -d x',
        );
      },
    );

    test(
      'T-20-FLAVOR-09: stg 결제 · API 단계는 stg config 의 프로젝트 ID 로만 명령을 만든다',
      () async {
        runner
          ..on(
            FakeCommandRunner.buildKey(
              BillingStep.billingInfoCommand(stgProjectId),
            ),
            const CommandResult(0, '{"billingEnabled": false}', ''),
          )
          ..on(
            FakeCommandRunner.buildKey(
              ApisStep.buildEnabledListCommand(stgProjectId),
            ),
            const CommandResult(0, 'firestore.googleapis.com\n', ''),
          );
        final WizardContext context = buildFlavorContext(Flavor.stg);
        final BillingStep billing = BillingStep();
        final ApisStep apis = ApisStep();

        expect(await billing.check(context), isA<Todo>());
        expect(await apis.check(context), isA<Todo>());
        final List<String> lines = <String>[
          ...billing.plannedCommandLines(context),
          ...apis.plannedCommandLines(context),
        ];

        expect(
          lines,
          contains(
            'gcloud billing projects link $stgProjectId '
            '--billing-account=<결제 계정 ID>',
          ),
        );
        expect(
          lines,
          contains(
            ApisStep.buildEnableCommand(
              stgProjectId,
              ApisStep.requiredServices.skip(1).toList(),
            ).render(),
          ),
        );
        expect(lines.where((String line) => line.contains(projectId)), isEmpty);
        expect(
          runner.calls.every(
            (FakeCall call) =>
                call.key.contains(stgProjectId) &&
                !call.key.contains(' $projectId'),
          ),
          isTrue,
        );
        expect(runner.calls, hasLength(2));
      },
    );

    test(
      'T-20-FLAVOR-09: stg config 가 자리표시면 결제 · API · Storage · 실행 단계는 stg 경로로 할 일을 알리고 요청하지 않는다',
      () async {
        writeFlavorConfig(Flavor.stg, Flavor.stg.placeholderProjectId);
        final WizardContext context = buildFlavorContext(Flavor.stg);

        for (final Step step in <Step>[
          BillingStep(),
          ApisStep(),
          StorageStep(),
          RunStep(),
        ]) {
          expect(
            await step.check(context),
            isA<Todo>().having(
              (Todo todo) => todo.reason,
              'reason',
              'config/stg.json 에서 프로젝트 ID 를 읽지 못했습니다',
            ),
            reason: step.id,
          );
        }
        expect(runner.calls, isEmpty);
        expect(rest.requests, isEmpty);
      },
    );

    test('T-20-FLAVOR-10: dev 문맥의 실행 명령 · 계획 줄 · 자리표시 판정은 그대로다', () async {
      expect(
        FakeCommandRunner.buildKey(RunStep.buildRunCommand('x')),
        'fvm flutter run --flavor dev '
        '--dart-define-from-file=config/dev.json -d x',
      );
      rest.on(
        'GET',
        RunStep.buildBatchGetRequest(projectId).url.toString(),
        buildPage(const <Map<String, Object?>>[]),
      );
      final WizardContext context = buildFlavorContext(Flavor.dev);
      final RunStep step = RunStep();

      expect(await step.check(context), isA<Todo>());
      expect(
        step.plannedCommandLines(context),
        contains(
          'fvm flutter run --flavor dev '
          '--dart-define-from-file=config/dev.json -d <고른 기기>',
        ),
      );

      writeFlavorConfig(Flavor.dev, 'your-project-dev');
      for (final Step placeholderStep in <Step>[
        BillingStep(),
        ApisStep(),
        StorageStep(),
      ]) {
        expect(
          await placeholderStep.check(context),
          isA<Todo>().having(
            (Todo todo) => todo.reason,
            'reason',
            'config/dev.json 에서 프로젝트 ID 를 읽지 못했습니다',
          ),
          reason: placeholderStep.id,
        );
      }
    });
  });
}
