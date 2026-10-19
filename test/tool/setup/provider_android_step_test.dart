import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

import '../../../tool/setup/command_runner.dart';
import '../../../tool/setup/flavor.dart';
import '../../../tool/setup/providers/fingerprints.dart';
import '../../../tool/setup/providers/provider_catalog.dart';
import '../../../tool/setup/step.dart';
import '../../../tool/setup/steps/facebook_step.dart';
import '../../../tool/setup/steps/flavor_steps.dart';
import '../../../tool/setup/steps/functions_step.dart';
import '../../../tool/setup/steps/identity_step.dart';
import '../../../tool/setup/steps/kakao_step.dart';
import '../../../tool/setup/steps/line_step.dart';
import '../../../tool/setup/steps/naver_step.dart';
import '../../../tool/setup/steps/provider_android_step.dart';
import '../../../tool/setup/wizard.dart';
import 'fakes.dart';

/// fixture Gradle 의 applicationId.
const String applicationId = 'com.example.android_side';

/// 지문 fixture 의 바이트 — 실제 인증서가 아닌 고정 문자열이다.
final List<int> fixtureCertificateBytes = utf8.encode(
  'starter-kit-fingerprint-fixture',
);

/// fixture 바이트의 키 해시(`openssl dgst -sha1 -binary | openssl base64` 출력).
const String fixtureKeyHash = 'q1AFhLJe1jbJyRsDcFRsODGFDxY=';

/// fixture 바이트의 SHA-1(`shasum -a 1` 출력).
const String fixtureSha1Hex = 'ab500584b25ed636c9c91b0370546c3831850f16';

/// fixture SHA-1 의 대문자 · 콜론 표시형.
const String fixtureSha1Colon =
    'AB:50:05:84:B2:5E:D6:36:C9:C9:1B:03:70:54:6C:38:31:85:0F:16';

/// 이미 끝난 앞 단계.
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

/// Android 쪽 줄 뒤의 단계 — 실행되면 끝난다.
final class _NextStep implements Step {
  /// 실행 횟수.
  int applyCount = 0;

  @override
  String get id => 'next';

  @override
  String get title => '다음 단계';

  @override
  List<String> get dependsOn => const <String>['providers'];

  @override
  bool get isCostlyOrIrreversible => false;

  @override
  Future<CheckResult> check(WizardContext context) async =>
      applyCount > 0 ? const Done('끝') : const Todo('할 일');

  @override
  List<String> plannedCommandLines(WizardContext context) => const <String>[
    'run-next',
  ];

  @override
  Future<StepOutcome> apply(WizardContext context) async {
    applyCount++;
    return const Applied();
  }
}

void main() {
  late Directory tempDir;
  late String root;
  late String home;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('provider_android_test_');
    root = '${tempDir.path}/repo';
    home = '${tempDir.path}/home';
    File('$root/${IdentityStep.gradlePath}')
      ..createSync(recursive: true)
      ..writeAsStringSync(
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

  /// 홈에 빈 키스토어 자리 파일을 두고 keytool 이 fixture 인증서를 내보내게 한다.
  FakeCommandRunner buildRunnerWithCertificate() {
    final keystore = File('$home/$debugKeystoreRelativePath')
      ..createSync(recursive: true);
    final String pem = <String>[
      '-----BEGIN',
      ' CERTIFICATE-----\n',
      base64Encode(fixtureCertificateBytes),
      '\n-----END',
      ' CERTIFICATE-----\n',
    ].join();
    return FakeCommandRunner()..on(
      FakeCommandRunner.buildKey(buildExportCertificateCommand(keystore.path)),
      CommandResult(0, pem, ''),
    );
  }

  /// Kakao Android 쪽 단계.
  ProviderAndroidSideStep buildKakaoSide() => ProviderAndroidSideStep(
    findProvider(KakaoStep.token)!,
    AndroidFingerprintKind.keyHash,
  );

  test('T-20-AND-01: 지문 있음 → ✓ 키 해시 · 패키지명 · 콘솔 등록 안내 줄 · 질문 0', () async {
    final FakeCommandRunner runner = buildRunnerWithCertificate();
    final screen = ScriptedTerminal(const <String?>[]);

    final int code = await runWizard(
      buildTestContext(
        projectRoot: root,
        runner: runner,
        terminal: screen,
        homeDirectory: home,
      ),
      <Step>[
        _FinishedStep('providers', '로그인 수단'),
        _FinishedStep('identity', '앱 정체성'),
        buildKakaoSide(),
      ],
    );
    final List<String> lines = const LineSplitter().convert(
      screen.output.toString(),
    );

    expect(code, wizardExitDone, reason: screen.output.toString());
    expect(
      lines,
      contains(
        '  ✓ Kakao — Android 쪽 — 키 해시 $fixtureKeyHash · '
        '패키지명 $applicationId.dev (콘솔 등록은 로그인 검사로 확인)',
      ),
    );
    expect(lines, contains(allDoneLine));
    expect(screen.asks, isEmpty);
    expect(screen.secretAsks, isEmpty);
    expect(runner.calls, hasLength(1));
    expect(runner.calls.single.key, startsWith('keytool -exportcert -rfc '));
  });

  test('T-20-AND-02: 지문 없음 → 그 줄만 ✗ · 질문은 다음 단계만 · 끝 목록 · 종료 0', () async {
    final runner = FakeCommandRunner();
    final screen = ScriptedTerminal(const <String?>['y']);
    final next = _NextStep();

    final int code = await runWizard(
      buildTestContext(
        projectRoot: root,
        runner: runner,
        terminal: screen,
        homeDirectory: home,
      ),
      <Step>[
        _FinishedStep('providers', '로그인 수단'),
        _FinishedStep('identity', '앱 정체성'),
        buildKakaoSide(),
        next,
      ],
    );
    final output = screen.output.toString();
    final List<String> lines = const LineSplitter().convert(output);
    const failedLine = '  ✗ Kakao — Android 쪽 — $unavailableFingerprintGuide';

    expect(code, wizardExitDone, reason: output);
    expect(lines.first, checklistHeading);
    expect(lines, contains(failedLine));
    expect(screen.asks, <String>[stepConfirmQuestion]);
    expect(next.applyCount, 1);
    final int heading = lines.indexOf(remainingHeading);
    expect(heading, greaterThan(0));
    expect(lines.indexOf(remainingDoneLine), heading - 1);
    expect(lines.sublist(heading + 1), <String>[failedLine]);
    expect(lines, isNot(contains(allDoneLine)));
    expect(runner.calls, isEmpty);
  });

  test(
    'T-20-AND-03: Kakao 를 켠 단계 목록 → kakao 다음 kakao_android · 함수는 kakao 만 기다린다',
    () {
      final List<Step> steps = buildSteps(
        flavor: Flavor.dev,
        enabledProviders: <String>{KakaoStep.token},
      );
      final ids = <String>[for (final Step step in steps) step.id];
      final FunctionsStep functions = steps.whereType<FunctionsStep>().single;

      expect(ids.indexOf('kakao_android'), ids.indexOf(KakaoStep.token) + 1);
      expect(ids.indexOf('kakao_android'), lessThan(ids.indexOf(functions.id)));
      expect(functions.dependsOn, contains(KakaoStep.token));
      expect(functions.dependsOn, isNot(contains('kakao_android')));
      final ProviderAndroidSideStep side = steps
          .whereType<ProviderAndroidSideStep>()
          .single;
      expect(side.title, 'Kakao — Android 쪽');
      expect(side.dependsOn, <String>['providers', 'identity']);
      expect(side.kind, AndroidFingerprintKind.keyHash);

      final List<Step> blank = buildSteps(
        flavor: Flavor.dev,
        enabledProviders: const <String>{},
      );
      expect(blank.whereType<ProviderAndroidSideStep>(), isEmpty);
    },
  );

  test('T-20-AND-04: LINE 형식 → ✓ 값이 대문자 콜론 59자 · 콘솔 등록 안내로 끝난다', () async {
    final session = WizardSession()
      ..debugFingerprints = const FingerprintsAvailable(
        sha1Hex: fixtureSha1Hex,
        sha256Hex: '',
        keyHash: fixtureKeyHash,
      );
    final runner = FakeCommandRunner();
    final WizardContext context = buildTestContext(
      projectRoot: root,
      runner: runner,
      session: session,
      homeDirectory: home,
    );
    final step = ProviderAndroidSideStep(
      findProvider('line')!,
      AndroidFingerprintKind.sha1Colon,
    );

    final CheckResult result = await step.check(context);

    expect(step.id, 'line_android');
    expect(step.title, 'LINE — Android 쪽');
    expect(result, isA<Done>());
    final String summary = (result as Done).summary;
    expect(
      summary,
      'SHA-1 $fixtureSha1Colon · 패키지명 $applicationId.dev '
      '$consoleRegistrationNote',
    );
    expect(fixtureSha1Colon, hasLength(59));
    expect(summary, endsWith('(콘솔 등록은 로그인 검사로 확인)'));
    expect(summary, isNot(contains(fixtureKeyHash)));
    expect(runner.calls, isEmpty);
    expect(step.plannedCommandLines(context), isEmpty);
    expect(await step.apply(context), isA<Applied>());
  });

  /// 세션에 fixture 지문이 이미 계산된 문맥.
  WizardContext buildContextWithFingerprints(FakeCommandRunner runner) =>
      buildTestContext(
        projectRoot: root,
        runner: runner,
        session: WizardSession()
          ..debugFingerprints = const FingerprintsAvailable(
            sha1Hex: fixtureSha1Hex,
            sha256Hex: '',
            keyHash: fixtureKeyHash,
          ),
        homeDirectory: home,
      );

  test('T-20-AND-05: Naver Android 쪽 → 지문 없는 홈에서도 ✓ 패키지명 · keytool 0 · '
      '지문이 있어도 키 해시 0회', () async {
    final ProviderAndroidSideStep naverSide = buildSteps(
      flavor: Flavor.dev,
      enabledProviders: <String>{NaverStep.token},
    ).whereType<ProviderAndroidSideStep>().single;
    final runner = FakeCommandRunner();
    final screen = ScriptedTerminal(const <String?>[]);

    final int code = await runWizard(
      buildTestContext(
        projectRoot: root,
        runner: runner,
        terminal: screen,
        homeDirectory: home,
      ),
      <Step>[
        _FinishedStep('providers', '로그인 수단'),
        _FinishedStep('identity', '앱 정체성'),
        naverSide,
      ],
    );
    final output = screen.output.toString();
    final List<String> lines = const LineSplitter().convert(output);

    expect(code, wizardExitDone, reason: output);
    expect(
      lines,
      contains(
        '  ✓ Naver — Android 쪽 — 패키지명 $applicationId.dev '
        '(콘솔 등록은 로그인 검사로 확인)',
      ),
    );
    expect(lines, contains(allDoneLine));
    expect(lines, isNot(contains(remainingHeading)));
    expect(screen.asks, isEmpty);
    expect(screen.secretAsks, isEmpty);
    expect(runner.calls, isEmpty);
    expect(output, isNot(contains('키 해시')));
    expect(output, isNot(contains(unavailableFingerprintGuide)));

    // 세션 지문이 있어도 Naver 줄에는 지문 값이 실리지 않는다.
    final withFingerprints = FakeCommandRunner();
    final CheckResult result = await naverSide.check(
      buildContextWithFingerprints(withFingerprints),
    );

    expect(result, isA<Done>());
    final String summary = (result as Done).summary;
    expect(summary, '패키지명 $applicationId.dev $consoleRegistrationNote');
    expect(summary, isNot(contains(fixtureKeyHash)));
    expect(summary, isNot(contains('키 해시')));
    expect(withFingerprints.calls, isEmpty);
  });

  test('T-20-AND-06: 네 수단의 Android 쪽 종류 표 · Kakao · Facebook 은 지문이 없으면 '
      '미루고 있으면 키 해시를 보인다', () async {
    final List<ProviderAndroidSideStep> sides = buildSteps(
      flavor: Flavor.dev,
      enabledProviders: <String>{
        FacebookStep.token,
        KakaoStep.token,
        NaverStep.token,
        LineStep.token,
      },
    ).whereType<ProviderAndroidSideStep>().toList();

    expect(
      <String, AndroidFingerprintKind>{
        for (final ProviderAndroidSideStep side in sides) side.id: side.kind,
      },
      <String, AndroidFingerprintKind>{
        'facebook_android': AndroidFingerprintKind.keyHash,
        'kakao_android': AndroidFingerprintKind.keyHash,
        'naver_android': AndroidFingerprintKind.packageNameOnly,
        'line_android': AndroidFingerprintKind.sha1Colon,
      },
    );
    for (final id in <String>['kakao_android', 'facebook_android']) {
      final ProviderAndroidSideStep side = sides.singleWhere(
        (ProviderAndroidSideStep step) => step.id == id,
      );
      final runner = FakeCommandRunner();

      final CheckResult missing = await side.check(
        buildTestContext(
          projectRoot: root,
          runner: runner,
          homeDirectory: home,
        ),
      );

      expect(missing, isA<Deferred>(), reason: id);
      expect((missing as Deferred).reason, unavailableFingerprintGuide);
      expect(runner.calls, isEmpty, reason: id);

      final CheckResult available = await side.check(
        buildContextWithFingerprints(FakeCommandRunner()),
      );

      expect(available, isA<Done>(), reason: id);
      expect(
        (available as Done).summary,
        startsWith('키 해시 $fixtureKeyHash · 패키지명 '),
        reason: id,
      );
    }
  });
}
