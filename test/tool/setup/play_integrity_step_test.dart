import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:test/test.dart';

import '../../../tool/setup/command_runner.dart';
import '../../../tool/setup/config_files.dart';
import '../../../tool/setup/flavor.dart';
import '../../../tool/setup/providers/fingerprints.dart';
import '../../../tool/setup/redactor.dart';
import '../../../tool/setup/rest_client.dart';
import '../../../tool/setup/step.dart';
import '../../../tool/setup/steps/play_integrity_step.dart';
import '../../../tool/setup/terminal.dart';
import '../../../tool/setup/wizard.dart';
import 'fake_rest_client.dart';
import 'fakes.dart';
import 'firebase_options_fixture.dart';

/// fixture Gradle 의 applicationId.
const String applicationId = 'com.example.play_integrity';

/// App Check API 주소의 앞부분.
const String appCheckPrefix = 'https://firebaseappcheck.googleapis.com/v1/';

/// Firebase Management API 주소의 앞부분.
const String managementPrefix = 'https://firebase.googleapis.com/v1beta1/';

/// dev · stg 의 완화 설정 본문 — 위저드가 보내야 하는 글자 그대로.
const String relaxedPatchBody =
    '{"appIntegrity":{"allowUnrecognizedVersion":true},'
    '"deviceIntegrity":{"minDeviceRecognitionLevel":"MEETS_DEVICE_INTEGRITY"}}';

/// 실행 시점에 조립한 가짜 API 키.
final String fakeApiKey = 'AIza${'x' * 35}';

/// 가짜 디버그 SHA-256(소문자 64자).
final String debugSha256 = 'ab' * 32;

/// 가짜 Play 앱 서명 키 SHA-256(소문자 64자).
final String playSha256 = 'ef01' * 16;

/// [flavor] 의 테스트 프로젝트 ID.
String buildProjectId(Flavor flavor) => 'p-${flavor.name}';

/// [flavor] 의 fixture Android 앱 ID.
String buildAndroidAppId(Flavor flavor) => '1:000:android:${flavor.name}';

/// [flavor] 의 Play Integrity 설정 주소.
String buildConfigUrl(Flavor flavor) =>
    '${appCheckPrefix}projects/${buildProjectId(flavor)}/apps/'
    '${buildAndroidAppId(flavor)}/playIntegrityConfig';

/// [flavor] 의 Play Integrity 설정 PATCH 주소.
String buildPatchUrl(Flavor flavor) =>
    '${buildConfigUrl(flavor)}?updateMask=app_integrity,device_integrity';

/// [flavor] 의 SHA 인증서 목록 주소.
String buildShaListUrl(Flavor flavor) =>
    '${managementPrefix}projects/${buildProjectId(flavor)}/androidApps/'
    '${buildAndroidAppId(flavor)}/sha';

/// [flavor] 프로젝트의 켜진 API 목록 명령 키.
String buildListKey(Flavor flavor) =>
    'gcloud services list --enabled --project ${buildProjectId(flavor)} '
    '--format=value(config.name)';

/// [flavor] 프로젝트에서 Play Integrity API 를 켜는 명령 키.
String buildEnableKey(Flavor flavor) =>
    'gcloud services enable playintegrity.googleapis.com '
    '--project ${buildProjectId(flavor)}';

/// 켜진 API 목록 결과 — [isEnabled] 면 Play Integrity API 줄이 있다.
CommandResult buildApiList({required bool isEnabled}) => CommandResult(
  0,
  isEnabled
      ? 'firestore.googleapis.com\nplayintegrity.googleapis.com\n'
      : 'firestore.googleapis.com\n',
  '',
);

/// 설정 응답 — [isRelaxed] 면 dev · stg 완화 설정, 아니면 기본값(필드 없음).
RestResponse buildConfigResponse({required bool isRelaxed}) => RestResponse(
  200,
  jsonEncode(<String, Object?>{
    'name': 'projects/p/apps/a/playIntegrityConfig',
    'tokenTtl': '3600s',
    if (isRelaxed) ...<String, Object?>{
      'appIntegrity': <String, Object?>{'allowUnrecognizedVersion': true},
      'deviceIntegrity': <String, Object?>{
        'minDeviceRecognitionLevel': 'MEETS_DEVICE_INTEGRITY',
      },
    },
  }),
);

/// SHA 인증서 목록 응답 — [hashes] 는 SHA-256 소문자 64자.
RestResponse buildShaList(List<String> hashes) => RestResponse(
  200,
  jsonEncode(<String, Object?>{
    if (hashes.isNotEmpty)
      'certificates': <Object?>[
        for (final String hash in hashes)
          <String, Object?>{
            'name': 'projects/p/androidApps/a/sha/$hash',
            'shaHash': hash,
            'certType': 'SHA_256',
          },
      ],
  }),
);

/// [hex] 를 대문자 · 콜론 표시형(Play Console 이 보이는 꼴)으로 바꾼다.
String formatUpperColon(String hex) => <String>[
  for (var i = 0; i < hex.length; i += 2) hex.substring(i, i + 2),
].join(':').toUpperCase();

/// 이미 끝난 앞 단계 — Play Integrity 단계의 의존 단계를 대신한다.
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

/// 뒤 단계 — 미룬 뒤에도 위저드가 다음 단계로 가는지 본다.
final class _AfterStep implements Step {
  bool isApplied = false;

  @override
  String get id => 'after';

  @override
  String get title => '뒤 단계';

  @override
  List<String> get dependsOn => const <String>[];

  @override
  bool get isCostlyOrIrreversible => false;

  @override
  Future<CheckResult> check(WizardContext context) async =>
      isApplied ? const Done('끝') : const Todo('뒤 할 일');

  @override
  List<String> plannedCommandLines(WizardContext context) => const <String>[];

  @override
  Future<StepOutcome> apply(WizardContext context) async {
    isApplied = true;
    return const Applied();
  }
}

/// 한 번의 위저드 실행 — 가짜 실행기 · REST · 화면 · 기록을 함께 둔다.
final class _Harness {
  _Harness(this.root, this.flavor, List<String?> inputs, {this.fingerprints})
    : screen = ScriptedTerminal(inputs);

  final String root;
  final Flavor flavor;
  final DebugFingerprints? fingerprints;
  final ScriptedTerminal screen;
  final FakeCommandRunner runner = FakeCommandRunner();
  final FakeRestClient rest = FakeRestClient();
  final MemoryLogSink log = MemoryLogSink(Redactor());

  /// 화면 출력 전체.
  String get output => screen.output.toString();

  /// 앞 단계(끝남) · Play Integrity 단계 · [extra] 로 위저드를 돌린다.
  Future<int> run({List<Step> extra = const <Step>[]}) => runWizard(
    WizardContext(
      projectRoot: root,
      runner: runner,
      terminal: RedactingTerminal(screen, log.redactor, log),
      redactor: log.redactor,
      log: log,
      rest: rest,
      flavor: flavor,
      session: WizardSession()..debugFingerprints = fingerprints,
      homeDirectory: noKeystoreTestHome,
      random: Random(fixedTestRandomSeed),
      now: () => fixedTestNow,
    ),
    <Step>[
      _FinishedStep('configure'),
      _FinishedStep('apis'),
      PlayIntegrityStep(),
      ...extra,
    ],
  );

  /// [method] 요청만 모은다.
  List<RestRequest> listRequests(String method) => rest.requests
      .where((RestRequest request) => request.method == method)
      .toList();

  /// SHA 목록 · 생성 요청 수.
  int countShaRequests() => rest.requests
      .where((RestRequest request) => request.url.path.endsWith('/sha'))
      .length;
}

/// 지문이 있는 세션 값.
final DebugFingerprints availableFingerprints = FingerprintsAvailable(
  sha1Hex: 'cd' * 20,
  sha256Hex: debugSha256,
  keyHash: '${'q' * 27}=',
);

void main() {
  late Directory tempDir;
  late String root;

  /// 저장소 상대 경로에 내용을 쓴다(부모 디렉터리를 만든다).
  void writeFixture(String relativePath, String content) {
    File('$root/$relativePath')
      ..parent.createSync(recursive: true)
      ..writeAsStringSync(content);
  }

  /// [flavor] 의 config(example 복사 · 프로젝트 ID)와 앱 설정 파일 3개를 쓴다.
  void writeFlavorFixture(Flavor flavor) {
    final paths = FlavorPaths(flavor);
    final config = File('$root/${paths.json}')
      ..parent.createSync(recursive: true);
    File(paths.jsonExample).copySync(config.path);
    replaceJsonString(config.path, 'firebaseProjectId', buildProjectId(flavor));
    writeFixture(
      paths.dartOptions,
      buildGeneratedOptionsSource(
        projectId: buildProjectId(flavor),
        apiKey: fakeApiKey,
        androidAppId: buildAndroidAppId(flavor),
        iosAppId: '1:000:ios:${flavor.name}',
      ),
    );
    writeFixture(
      paths.iosPlist,
      '<plist version="1.0">\n<dict>\n'
      '\t<key>GOOGLE_APP_ID</key>\n\t<string>1:000:ios:${flavor.name}</string>\n'
      '</dict>\n</plist>\n',
    );
    writeFixture(
      paths.androidJson,
      jsonEncode(<String, Object?>{
        'project_info': <String, Object?>{'project_id': buildProjectId(flavor)},
        'client': <Object?>[
          <String, Object?>{
            'client_info': <String, Object?>{
              'mobilesdk_app_id': buildAndroidAppId(flavor),
              'android_client_info': <String, Object?>{
                'package_name': '$applicationId${flavor.suffix}',
              },
            },
          },
        ],
      }),
    );
  }

  /// [flavor] 의 단계 머리 줄 머리(✓ · ✗ 뒤).
  String buildLinePrefix(String mark) =>
      '  $mark ${PlayIntegrityStep.stepTitle} — ';

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('play_integrity_test_');
    root = tempDir.path;
    writeFixture(
      'android/app/build.gradle.kts',
      'android {\n'
          '    defaultConfig {\n'
          '        applicationId = "$applicationId"\n'
          '    }\n'
          '}\n',
    );
    for (final Flavor flavor in Flavor.values) {
      writeFlavorFixture(flavor);
    }
  });

  tearDown(() {
    tempDir.deleteSync(recursive: true);
  });

  group('T-20-PI-01: 지문 없음', () {
    test('API 꺼짐 · 설정 기본 → 미룰 수 있는 ✗ · 2(지금 안 함) → 끝 목록', () async {
      final h = _Harness(root, Flavor.dev, const <String?>['2']);
      h.runner.on(buildListKey(Flavor.dev), buildApiList(isEnabled: false));
      h.rest.on(
        'GET',
        buildConfigUrl(Flavor.dev),
        buildConfigResponse(isRelaxed: false),
      );

      final int code = await h.run();

      expect(code, wizardExitDone);
      expect(h.screen.asks, <String>[failureChoiceQuestion]);
      expect(h.output, contains('  1) 진행\n  2) 지금 안 함\n  3) 멈춤'));
      final String ending = h.output.substring(
        h.output.indexOf(remainingHeading),
      );
      expect(ending, contains('${buildLinePrefix('✗')}지금 안 함'));
      expect(h.countShaRequests(), 0);
      expect(h.listRequests('PATCH'), isEmpty);
      expect(h.runner.countMode(RunMode.stream), 0);
    });

    test('1(진행) → API 켜기 · PATCH 뒤 재검사 Deferred ✗ · SHA 요청 0', () async {
      final h = _Harness(root, Flavor.dev, const <String?>['1']);
      h.runner
        ..on(buildListKey(Flavor.dev), buildApiList(isEnabled: false))
        ..on(buildListKey(Flavor.dev), buildApiList(isEnabled: false))
        ..on(buildListKey(Flavor.dev), buildApiList(isEnabled: true))
        ..on(buildEnableKey(Flavor.dev), const CommandResult(0, '', ''));
      h.rest
        ..on(
          'GET',
          buildConfigUrl(Flavor.dev),
          buildConfigResponse(isRelaxed: false),
        )
        ..on(
          'GET',
          buildConfigUrl(Flavor.dev),
          buildConfigResponse(isRelaxed: false),
        )
        ..on(
          'GET',
          buildConfigUrl(Flavor.dev),
          buildConfigResponse(isRelaxed: true),
        )
        ..on(
          'PATCH',
          buildPatchUrl(Flavor.dev),
          buildConfigResponse(isRelaxed: true),
        );

      final int code = await h.run();

      expect(code, wizardExitDone);
      expect(
        h.runner.countCalls(RunMode.stream, buildEnableKey(Flavor.dev)),
        1,
      );
      expect(h.listRequests('PATCH'), hasLength(1));
      expect(h.countShaRequests(), 0);
      final deferredLine =
          '${buildLinePrefix('✗')}'
          '${PlayIntegrityStep.fingerprintDeferredReason}';
      expect(
        PlayIntegrityStep.fingerprintDeferredReason,
        allOf(
          contains(unavailableFingerprintGuide),
          contains('Play Integrity 에는 SHA-256 지문이 있어야 합니다'),
        ),
      );
      final String ending = h.output.substring(
        h.output.indexOf(remainingHeading),
      );
      expect(ending, contains(deferredLine));
      expect(h.output, isNot(contains(buildLinePrefix('✓'))));
    });

    test('API · 설정 완료 → 처음부터 Deferred ✗ · 질문 0', () async {
      final h = _Harness(root, Flavor.dev, const <String?>[]);
      h.runner.on(buildListKey(Flavor.dev), buildApiList(isEnabled: true));
      h.rest.on(
        'GET',
        buildConfigUrl(Flavor.dev),
        buildConfigResponse(isRelaxed: true),
      );

      final int code = await h.run();

      expect(code, wizardExitDone);
      expect(h.screen.asks, isEmpty);
      expect(
        h.output,
        contains(
          '${buildLinePrefix('✗')}'
          '${PlayIntegrityStep.fingerprintDeferredReason}',
        ),
      );
      expect(h.output, contains(remainingHeading));
      expect(h.countShaRequests(), 0);
      expect(h.listRequests('PATCH'), isEmpty);
    });
  });

  test('T-20-PI-02: dev · API 꺼짐 · SHA 없음 · 설정 기본 → 켜기 · SHA_256 생성 · '
      'PATCH · 안내 · 재검사 ✓', () async {
    final h = _Harness(root, Flavor.dev, const <String?>[
      '1',
    ], fingerprints: availableFingerprints);
    h.runner
      ..on(buildListKey(Flavor.dev), buildApiList(isEnabled: false))
      ..on(buildListKey(Flavor.dev), buildApiList(isEnabled: false))
      ..on(buildListKey(Flavor.dev), buildApiList(isEnabled: true))
      ..on(buildEnableKey(Flavor.dev), const CommandResult(0, '', ''));
    h.rest
      ..on(
        'GET',
        buildConfigUrl(Flavor.dev),
        buildConfigResponse(isRelaxed: false),
      )
      ..on(
        'GET',
        buildConfigUrl(Flavor.dev),
        buildConfigResponse(isRelaxed: false),
      )
      ..on(
        'GET',
        buildConfigUrl(Flavor.dev),
        buildConfigResponse(isRelaxed: true),
      )
      ..on('GET', buildShaListUrl(Flavor.dev), buildShaList(const <String>[]))
      ..on('GET', buildShaListUrl(Flavor.dev), buildShaList(const <String>[]))
      ..on(
        'GET',
        buildShaListUrl(Flavor.dev),
        buildShaList(<String>[debugSha256]),
      )
      ..on('POST', buildShaListUrl(Flavor.dev), const RestResponse(200, '{}'))
      ..on(
        'PATCH',
        buildPatchUrl(Flavor.dev),
        buildConfigResponse(isRelaxed: true),
      );

    final int code = await h.run();

    expect(code, wizardExitDone);
    expect(h.runner.countCalls(RunMode.stream, buildEnableKey(Flavor.dev)), 1);
    final List<RestRequest> posts = h.listRequests('POST');
    expect(posts, hasLength(1));
    expect(jsonDecode(posts.single.body!), <String, Object?>{
      'shaHash': debugSha256,
      'certType': 'SHA_256',
    });
    final List<RestRequest> patches = h.listRequests('PATCH');
    expect(patches, hasLength(1));
    expect(patches.single.url.toString(), buildPatchUrl(Flavor.dev));
    expect(patches.single.body, relaxedPatchBody);
    expect(h.output, contains(PlayIntegrityStep.verdictDelayNotice));
    expect(PlayIntegrityStep.verdictDelayNotice, contains('1~2분'));
    expect(h.output, contains(buildLinePrefix('✓')));
    // 켜기 → SHA 생성 → PATCH 순서.
    final int enableIndex = h.runner.calls.indexWhere(
      (FakeCall call) => call.key == buildEnableKey(Flavor.dev),
    );
    expect(enableIndex, greaterThanOrEqualTo(0));
    expect(
      h.rest.requests.indexOf(posts.single),
      lessThan(h.rest.requests.indexOf(patches.single)),
    );
  });

  group('T-20-PI-03: flavor 별 PATCH', () {
    test('stg 도 dev 와 같은 완화 본문을 보낸다', () async {
      final h = _Harness(root, Flavor.stg, const <String?>[
        '1',
      ], fingerprints: availableFingerprints);
      h.runner.on(buildListKey(Flavor.stg), buildApiList(isEnabled: true));
      h.rest
        ..on(
          'GET',
          buildConfigUrl(Flavor.stg),
          buildConfigResponse(isRelaxed: false),
        )
        ..on(
          'GET',
          buildConfigUrl(Flavor.stg),
          buildConfigResponse(isRelaxed: false),
        )
        ..on(
          'GET',
          buildConfigUrl(Flavor.stg),
          buildConfigResponse(isRelaxed: true),
        )
        ..on(
          'GET',
          buildShaListUrl(Flavor.stg),
          buildShaList(<String>[debugSha256]),
        )
        ..on(
          'PATCH',
          buildPatchUrl(Flavor.stg),
          buildConfigResponse(isRelaxed: true),
        );

      final int code = await h.run();

      expect(code, wizardExitDone);
      final List<RestRequest> patches = h.listRequests('PATCH');
      expect(patches, hasLength(1));
      expect(patches.single.url.toString(), buildPatchUrl(Flavor.stg));
      expect(patches.single.body, relaxedPatchBody);
      expect(
        PlayIntegrityStep.buildPatchRequest(
          buildProjectId(Flavor.stg),
          buildAndroidAppId(Flavor.stg),
        ).body,
        relaxedPatchBody,
      );
      expect(h.listRequests('POST'), isEmpty);
      expect(h.output, contains(buildLinePrefix('✓')));
    });

    test('prod 는 할 일이 있어도 PATCH 0 — API 켜기만 한다', () async {
      final h = _Harness(root, Flavor.prod, const <String?>[
        '1',
      ], fingerprints: availableFingerprints);
      h.runner
        ..on(buildListKey(Flavor.prod), buildApiList(isEnabled: false))
        ..on(buildListKey(Flavor.prod), buildApiList(isEnabled: false))
        ..on(buildListKey(Flavor.prod), buildApiList(isEnabled: true))
        ..on(buildEnableKey(Flavor.prod), const CommandResult(0, '', ''));
      h.rest
        ..on(
          'GET',
          buildConfigUrl(Flavor.prod),
          buildConfigResponse(isRelaxed: false),
        )
        ..on(
          'GET',
          buildShaListUrl(Flavor.prod),
          buildShaList(<String>[debugSha256, playSha256]),
        );

      final int code = await h.run();

      expect(code, wizardExitDone);
      expect(
        h.runner.countCalls(RunMode.stream, buildEnableKey(Flavor.prod)),
        1,
      );
      expect(h.listRequests('PATCH'), isEmpty);
      expect(h.listRequests('POST'), isEmpty);
      expect(h.output, isNot(contains('playIntegrityConfig?updateMask')));
      expect(h.output, contains(buildLinePrefix('✓')));
    });
  });

  group('T-20-PI-04: prod · Play 앱 서명 키 SHA-256', () {
    /// prod 에 디버그 SHA-256 만 있는 응답을 등록한다 — 재검사는 [after] 목록.
    void registerProdTodo(_Harness h, {List<String>? after}) {
      h.runner.on(buildListKey(Flavor.prod), buildApiList(isEnabled: true));
      h.rest
        ..on(
          'GET',
          buildConfigUrl(Flavor.prod),
          buildConfigResponse(isRelaxed: false),
        )
        ..on(
          'GET',
          buildShaListUrl(Flavor.prod),
          buildShaList(<String>[debugSha256]),
        )
        ..on(
          'GET',
          buildShaListUrl(Flavor.prod),
          buildShaList(<String>[debugSha256]),
        )
        ..on('GET', buildShaListUrl(Flavor.prod), buildShaList(after ?? []))
        ..on(
          'POST',
          buildShaListUrl(Flavor.prod),
          const RestResponse(200, '{}'),
        );
    }

    test('안내 · 대문자 콜론 입력 → 소문자 64 로 SHA_256 생성 · 형식 틀림은 다시 묻기 · '
        '재검사 ✓', () async {
      final h = _Harness(root, Flavor.prod, <String?>[
        '1',
        'AB:CD',
        formatUpperColon(playSha256),
      ], fingerprints: availableFingerprints);
      registerProdTodo(h, after: <String>[debugSha256, playSha256]);

      final int code = await h.run();

      expect(code, wizardExitDone);
      expect(h.output, contains(PlayIntegrityStep.prodSigningKeyGuide));
      expect(
        PlayIntegrityStep.prodSigningKeyGuide,
        'Play 에 올린 뒤 Play 앱 서명 키의 SHA-256 을 등록해야 합니다 — 업로드 키가 아닙니다',
      );
      expect(
        h.screen.asks
            .where((String ask) => ask == PlayIntegrityStep.signingKeyQuestion)
            .length,
        2,
      );
      final List<RestRequest> posts = h.listRequests('POST');
      expect(posts, hasLength(1));
      expect(jsonDecode(posts.single.body!), <String, Object?>{
        'shaHash': playSha256,
        'certType': 'SHA_256',
      });
      expect(h.listRequests('PATCH'), isEmpty);
      expect(h.output, contains(buildLinePrefix('✓')));
    });

    test('빈 입력 → 지금 안 함과 같은 ✗ · 끝 목록 · 등록 0', () async {
      final h = _Harness(root, Flavor.prod, const <String?>[
        '1',
        '',
      ], fingerprints: availableFingerprints);
      registerProdTodo(h);

      final int code = await h.run();

      expect(code, wizardExitDone);
      final String ending = h.output.substring(
        h.output.indexOf(remainingHeading),
      );
      expect(ending, contains('${buildLinePrefix('✗')}지금 안 함'));
      expect(h.listRequests('POST'), isEmpty);
      expect(h.listRequests('PATCH'), isEmpty);
    });

    test('prod 설정이 이미 완화돼 있으면 바꾸지 않고 ✗ · 질문 0', () async {
      final h = _Harness(
        root,
        Flavor.prod,
        const <String?>[],
        fingerprints: availableFingerprints,
      );
      h.runner.on(buildListKey(Flavor.prod), buildApiList(isEnabled: true));
      h.rest
        ..on(
          'GET',
          buildConfigUrl(Flavor.prod),
          buildConfigResponse(isRelaxed: true),
        )
        ..on(
          'GET',
          buildShaListUrl(Flavor.prod),
          buildShaList(<String>[debugSha256, playSha256]),
        );

      final int code = await h.run();

      expect(code, wizardExitDone);
      expect(h.screen.asks, isEmpty);
      expect(
        h.output,
        contains(
          '${buildLinePrefix('✗')}${PlayIntegrityStep.prodRelaxedReason}',
        ),
      );
      expect(h.listRequests('PATCH'), isEmpty);
      expect(h.listRequests('POST'), isEmpty);
    });

    test('normalizeSha256 — 콜론 · 대소문자 허용 · 그 밖은 null', () {
      expect(
        PlayIntegrityStep.normalizeSha256(' ${formatUpperColon(playSha256)} '),
        playSha256,
      );
      expect(PlayIntegrityStep.normalizeSha256(playSha256), playSha256);
      expect(PlayIntegrityStep.normalizeSha256('ab' * 31), isNull);
      expect(PlayIntegrityStep.normalizeSha256('zz' * 32), isNull);
      expect(PlayIntegrityStep.normalizeSha256(''), isNull);
    });
  });

  test('T-20-PI-05: 2(지금 안 함) → ✗ · 다음 단계 · 저장 0', () async {
    final h = _Harness(root, Flavor.dev, const <String?>[
      '2',
      'y',
    ], fingerprints: availableFingerprints);
    h.runner.on(buildListKey(Flavor.dev), buildApiList(isEnabled: false));
    h.rest
      ..on(
        'GET',
        buildConfigUrl(Flavor.dev),
        buildConfigResponse(isRelaxed: false),
      )
      ..on('GET', buildShaListUrl(Flavor.dev), buildShaList(const <String>[]));
    final configPath = '$root/${const FlavorPaths(Flavor.dev).json}';
    final String before = File(configPath).readAsStringSync();
    final after = _AfterStep();

    final int code = await h.run(extra: <Step>[after]);

    expect(code, wizardExitDone);
    expect(after.isApplied, isTrue);
    expect(h.output, contains('${buildLinePrefix('✗')}지금 안 함'));
    expect(h.listRequests('POST'), isEmpty);
    expect(h.listRequests('PATCH'), isEmpty);
    expect(h.runner.countMode(RunMode.stream), 0);
    expect(File(configPath).readAsStringSync(), before);
  });

  test('T-20-PI-06: dev 이미 완화 · SHA 등록 · API 켜짐 → ✓ · 질문 0', () async {
    final h = _Harness(
      root,
      Flavor.dev,
      const <String?>[],
      fingerprints: availableFingerprints,
    );
    h.runner.on(buildListKey(Flavor.dev), buildApiList(isEnabled: true));
    h.rest
      ..on(
        'GET',
        buildConfigUrl(Flavor.dev),
        buildConfigResponse(isRelaxed: true),
      )
      ..on(
        'GET',
        buildShaListUrl(Flavor.dev),
        buildShaList(<String>[debugSha256]),
      );

    final int code = await h.run();

    expect(code, wizardExitDone);
    expect(h.screen.asks, isEmpty);
    expect(h.output, contains(buildLinePrefix('✓')));
    expect(h.output, contains(allDoneLine));
    expect(h.listRequests('PATCH'), isEmpty);
    expect(h.listRequests('POST'), isEmpty);
  });
}
