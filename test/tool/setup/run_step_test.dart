import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

import '../../../tool/setup/command_runner.dart';
import '../../../tool/setup/rest_client.dart';
import '../../../tool/setup/step.dart';
import '../../../tool/setup/steps/dev_steps.dart';
import '../../../tool/setup/steps/run_step.dart';
import '../../../tool/setup/steps/user_files_step.dart';
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
      FakeCommandRunner.buildKey(RunStep.buildLaunchSimulatorCommand()),
      'fvm flutter emulators --launch apple_ios_simulator',
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
    expect(
      harness.runner.countCalls(
        RunMode.stream,
        'fvm flutter emulators --launch apple_ios_simulator',
      ),
      0,
    );
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
    expect(
      deviceOnly.runner.countCalls(
        RunMode.stream,
        FakeCommandRunner.buildKey(RunStep.buildLaunchSimulatorCommand()),
      ),
      0,
    );
    expect(
      deviceOnly.runner.countCalls(
        RunMode.interactive,
        FakeCommandRunner.buildKey(RunStep.buildRunCommand(iosDeviceId)),
      ),
      1,
    );
  });

  test('T-19-RUN-04: 대상 0 → 시뮬레이터 띄우기 → 기다린 뒤 재조회 → 대상 1 → 진행', () async {
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
      ..registerRun(simulatorId, 0);
    harness.runner.on(
      FakeCommandRunner.buildKey(RunStep.buildLaunchSimulatorCommand()),
      const CommandResult(0, '', ''),
    );

    final int code = await harness.run();

    expect(code, wizardExitDone);
    expect(
      harness.runner.countCalls(
        RunMode.stream,
        'fvm flutter emulators --launch apple_ios_simulator',
      ),
      1,
    );
    expect(
      harness.runner.countCalls(
        RunMode.capture,
        'fvm flutter devices --machine',
      ),
      3,
    );
    expect(harness.delays, hasLength(2));
    expect(harness.delays.first, RunStep.launchPollInterval);
    expect(harness.output, contains('  1) iPhone 17 (iOS 시뮬레이터)'));
    expect(harness.output, contains('인증된 이메일 사용자 1명'));
  });

  test('T-19-RUN-04 보강: 띄운 뒤에도 대상이 끝내 없으면 실패 · 실행 0', () async {
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
      );
    harness.runner.on(
      FakeCommandRunner.buildKey(RunStep.buildLaunchSimulatorCommand()),
      const CommandResult(0, '', ''),
    );

    final int code = await harness.run();

    expect(code, wizardExitStopped);
    expect(harness.delays, hasLength(RunStep.maxLaunchPolls));
    expect(harness.output, contains('  실패 — ${RunStep.noTargetSummary}'));
    expect(harness.runner.countMode(RunMode.interactive), 0);
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
}
