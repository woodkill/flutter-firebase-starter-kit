import 'dart:io';

import 'package:test/test.dart';

import '../../../tool/setup/command_runner.dart';
import '../../../tool/setup/config_files.dart';
import '../../../tool/setup/confirm.dart';
import '../../../tool/setup/providers/fingerprints.dart';
import '../../../tool/setup/providers/keyed_provider_step.dart';
import '../../../tool/setup/redactor.dart';
import '../../../tool/setup/rest_client.dart';
import '../../../tool/setup/secret_store.dart';
import '../../../tool/setup/step.dart';
import '../../../tool/setup/steps/kakao_step.dart';
import '../../../tool/setup/steps/user_files_step.dart';
import '../../../tool/setup/terminal.dart';
import '../../../tool/setup/wizard.dart';
import 'fake_rest_client.dart';
import 'fakes.dart';

/// 테스트 프로젝트 ID.
const String projectId = 'kakao-p';

/// fixture Gradle 의 applicationId.
const String applicationId = 'com.example.kakao_app';

/// fixture xcconfig 의 dev 번들 ID.
const String devBundleId = 'com.example.kakaoApp.dev';

/// Secret Manager 의 네이티브 앱 키 이름.
const String nativeSecret = 'KAKAO_NATIVE_APP_KEY';

/// Secret Manager 의 어드민 키 이름.
const String adminSecret = 'KAKAO_ADMIN_KEY';

/// 실행 시점에 조립하는 가짜 네이티브 앱 키(소문자 16진수 32자).
String buildNativeKey([String letter = 'a']) => letter * 32;

/// 실행 시점에 조립하는 가짜 어드민 키(16진수 32자).
String buildAdminKey([String letter = 'b']) => letter * 32;

/// [haystack] 에서 [needle] 이 나타나는 횟수를 센다.
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

/// 이미 끝난 앞 단계 — Kakao 단계의 의존 단계를 대신한다.
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

/// Kakao 단계 한 번 실행에 쓰는 가짜 실행기 · REST · 화면 · 기록 묶음.
final class _Harness {
  _Harness(this.root, List<String?> inputs)
    : runner = FakeCommandRunner(),
      rest = FakeRestClient(),
      screen = ScriptedTerminal(inputs),
      log = MemoryLogSink(Redactor());

  final String root;
  final FakeCommandRunner runner;
  final FakeRestClient rest;
  final ScriptedTerminal screen;
  final MemoryLogSink log;

  /// 화면 출력 전체.
  String get output => screen.output.toString();

  /// [name] 읽기 결과 큐에 [results] 를 차례로 더한다.
  void onSecretReads(String name, List<CommandResult> results) {
    for (final result in results) {
      runner.on(
        FakeCommandRunner.buildKey(buildSecretReadCommand(name, projectId)),
        result,
      );
    }
  }

  /// [name] 쓰기를 성공으로 등록한다.
  void onSecretWrite(String name) => runner.on(
    FakeCommandRunner.buildKey(
      buildSecretWriteCommand(name, projectId, value: '', valueLabel: ''),
    ),
    ok(),
  );

  /// 어드민 키 서버 확인 응답 큐에 [responses] 를 더한다.
  void onAdminCheck(List<RestResponse> responses) {
    for (final response in responses) {
      rest.onExternal('GET', KakaoStep.adminKeyCheckUrl, response);
    }
  }

  /// Secret Manager 쓰기 호출.
  List<FakeCall> get secretWrites => <FakeCall>[
    for (final FakeCall call in runner.calls)
      if (call.key.startsWith('firebase functions:secrets:set ')) call,
  ];

  /// 앞 단계(끝남) · Kakao 단계로 위저드를 돌린다.
  Future<int> run() => runWizard(
    buildTestContext(
      projectRoot: root,
      runner: runner,
      terminal: screen,
      log: log,
      rest: rest,
    ),
    <Step>[
      _FinishedStep('providers', '로그인 수단'),
      _FinishedStep('configure', '앱 등록 · 설정 파일'),
      _FinishedStep('apis', '필요한 Google Cloud API'),
      KakaoStep(),
    ],
  );
}

void main() {
  late Directory tempDir;
  late String root;
  late String configPath;
  late String xcconfigPath;

  /// 저장소 상대 경로에 내용을 쓴다(부모 디렉터리를 만든다).
  void writeFixture(String relativePath, String content) {
    File('$root/$relativePath')
      ..parent.createSync(recursive: true)
      ..writeAsStringSync(content);
  }

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('kakao_step_test_');
    root = tempDir.path;
    writeFixture(
      UserFilesStep.jsonExamplePath,
      File(UserFilesStep.jsonExamplePath).readAsStringSync(),
    );
    writeFixture(
      UserFilesStep.xcconfigExamplePath,
      File(UserFilesStep.xcconfigExamplePath).readAsStringSync(),
    );
    configPath = '$root/${UserFilesStep.jsonUserPath}';
    xcconfigPath = '$root/${UserFilesStep.xcconfigUserPath}';
    writeFixture(
      UserFilesStep.jsonUserPath,
      File(UserFilesStep.jsonExamplePath).readAsStringSync(),
    );
    replaceJsonString(configPath, 'firebaseProjectId', projectId);
    replaceJsonString(configPath, 'enabledAuthProviders', 'kakao');
    writeFixture(
      UserFilesStep.xcconfigUserPath,
      File(UserFilesStep.xcconfigExamplePath).readAsStringSync(),
    );
    replaceXcconfigValue(
      xcconfigPath,
      'PRODUCT_BUNDLE_IDENTIFIER',
      devBundleId,
    );
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

  /// config 의 네이티브 앱 키.
  String? readConfigNativeKey() =>
      readJsonString(configPath, KakaoStep.nativeAppKeyField.configKey!);

  /// xcconfig 의 네이티브 앱 키.
  String? readXcconfigNativeKey() =>
      readXcconfigValue(xcconfigPath, KakaoStep.nativeAppKeyField.xcconfigVar!);

  /// 화면 질문 가운데 [label] 로 시작하는 것의 수.
  int countQuestions(_Harness h, String label) =>
      h.screen.asks.where((String ask) => ask.startsWith(label)).length;

  /// 두 이름 모두 「없음 · 없음 · 쓴 값」 으로 등록한다.
  void registerFreshSecrets(_Harness h, String nativeKey, String adminKey) {
    h
      ..onSecretReads(nativeSecret, <CommandResult>[
        buildSecretMissing(nativeSecret),
        buildSecretMissing(nativeSecret),
        ok('$nativeKey\n'),
      ])
      ..onSecretReads(adminSecret, <CommandResult>[
        buildSecretMissing(adminSecret),
        buildSecretMissing(adminSecret),
        ok('$adminKey\n'),
      ])
      ..onSecretWrite(nativeSecret)
      ..onSecretWrite(adminSecret);
  }

  test('T-20-KAKAO-01: 네이티브 앱 키 형식이 틀리면 그 값만 다시 묻고 맞는 값으로 진행한다', () async {
    final String nativeKey = buildNativeKey();
    final String adminKey = buildAdminKey();
    final h = _Harness(root, <String?>[
      'y',
      '1',
      'a' * 31,
      nativeKey,
      adminKey,
    ]);
    registerFreshSecrets(h, nativeKey, adminKey);
    h.onAdminCheck(<RestResponse>[const RestResponse(200, '{}')]);

    final int code = await h.run();

    expect(code, wizardExitDone, reason: h.output);
    expect(countQuestions(h, KakaoStep.nativeAppKeyField.label), 2);
    expect(h.screen.secretAsks, hasLength(1));
    expect(h.output, contains('형식이 맞지 않습니다 — 31자'));
    expect(
      h.output,
      contains('${KakaoStep.nativeAppKeyField.label} — 32자 · 형식 맞음'),
    );
    expect(readConfigNativeKey(), nativeKey);
    expect(readXcconfigNativeKey(), nativeKey);
    expect(h.secretWrites.map((FakeCall call) => call.stdinText), <String>[
      nativeKey,
      adminKey,
    ]);
  });

  test(
    'T-20-KAKAO-02: 어드민 키 서버 확인이 401 이면 어드민 키만 다시 묻고 두 번째 200 에 기록한다',
    () async {
      final String nativeKey = buildNativeKey();
      final String wrongAdmin = buildAdminKey('c');
      final String adminKey = buildAdminKey();
      final h = _Harness(root, <String?>[
        'y',
        '1',
        nativeKey,
        wrongAdmin,
        adminKey,
      ]);
      registerFreshSecrets(h, nativeKey, adminKey);
      h.onAdminCheck(<RestResponse>[
        const RestResponse(
          401,
          '{"msg":"appKey(x) does not exist","reason":"UNKNOWN","code":-401}',
        ),
        const RestResponse(200, '{}'),
      ]);

      final int code = await h.run();

      expect(code, wizardExitDone, reason: h.output);
      expect(h.output, contains(KakaoStep.adminKeyMismatchMessage));
      expect(h.output, isNot(contains('does not exist')));
      expect(countQuestions(h, KakaoStep.nativeAppKeyField.label), 1);
      expect(h.screen.secretAsks, hasLength(2));
      expect(h.rest.externalRequests, hasLength(2));
      expect(
        h.rest.externalRequests.map(
          (ExternalRequest request) => request.headers['Authorization'],
        ),
        <String>['KakaoAK $wrongAdmin', 'KakaoAK $adminKey'],
      );
      expect(h.secretWrites.last.stdinText, adminKey);
      for (final text in <String>[h.output, h.log.text]) {
        expect(countText(text, wrongAdmin), 0);
        expect(countText(text, adminKey), 0);
      }
    },
  );

  test('T-20-KAKAO-03: 어드민 키 서버 확인이 네트워크 실패면 아무것도 쓰지 않고 실패 → 멈춤', () async {
    final String nativeKey = buildNativeKey();
    final String adminKey = buildAdminKey();
    final String configBefore = File(configPath).readAsStringSync();
    final String xcconfigBefore = File(xcconfigPath).readAsStringSync();
    final h = _Harness(root, <String?>[
      'y',
      '1',
      nativeKey,
      adminKey,
      '2', // 실패 뒤 멈춤
    ]);
    registerFreshSecrets(h, nativeKey, adminKey);
    h.onAdminCheck(<RestResponse>[const RestResponse(0, '')]);

    final int code = await h.run();

    expect(code, wizardExitStopped);
    expect(h.output, contains('어드민 키를 서버에서 확인하지 못했습니다'));
    expect(h.screen.asks.last, failureChoiceQuestion);
    expect(h.secretWrites, isEmpty);
    expect(File(configPath).readAsStringSync(), configBefore);
    expect(File(xcconfigPath).readAsStringSync(), xcconfigBefore);
  });

  test(
    'T-20-KAKAO-04: 콘솔 질문에 아니요면 위저드 밖 작업 안내로 끝나고 입력 질문 · 쓰기가 0 이다',
    () async {
      final h = _Harness(root, const <String?>['y', '2']);
      registerFreshSecrets(h, buildNativeKey(), buildAdminKey());

      final int code = await h.run();

      expect(code, wizardExitForUser);
      expect(h.output, contains('./setup.sh --providers'));
      expect(h.output, contains(exitForUserTailLine));
      expect(h.screen.asks, <String>[
        stepConfirmQuestion,
        consoleReadyQuestion,
      ]);
      expect(h.screen.secretAsks, isEmpty);
      expect(h.secretWrites, isEmpty);
      expect(h.rest.externalRequests, isEmpty);
    },
  );

  group('T-20-KAKAO-05: 입력이 끝까지 맞지 않으면 쓰지 않고 멈춘다', () {
    test('형식이 3회 틀림', () async {
      final h = _Harness(root, <String?>['y', '1', 'zz', 'a' * 31, 'A' * 32]);
      registerFreshSecrets(h, buildNativeKey(), buildAdminKey());

      final int code = await h.run();

      expect(code, wizardExitStopped);
      expect(countQuestions(h, KakaoStep.nativeAppKeyField.label), 3);
      expect(h.screen.secretAsks, isEmpty);
      expect(h.secretWrites, isEmpty);
      expect(readConfigNativeKey(), 'YOUR_KAKAO_NATIVE_APP_KEY_HERE');
    });

    test('숨김 입력 중 입력 끝', () async {
      final h = _Harness(root, <String?>['y', '1', buildNativeKey()]);
      registerFreshSecrets(h, buildNativeKey(), buildAdminKey());

      final int code = await h.run();

      expect(code, wizardExitStopped);
      expect(h.screen.secretAsks, hasLength(1));
      expect(h.log.text, contains(RedactingTerminal.endOfInputRecord));
      expect(h.secretWrites, isEmpty);
      expect(h.rest.externalRequests, isEmpty);
      expect(readConfigNativeKey(), 'YOUR_KAKAO_NATIVE_APP_KEY_HERE');
    });
  });

  test('T-20-KAKAO-06: config 에 실 값 · xcconfig 자리표시 · 네이티브 앱 키 secret unset · '
      '어드민 키 있음 → 질문 없이 xcconfig · 네이티브 앱 키 secret 만 맞춘다', () async {
    final String nativeKey = buildNativeKey();
    final String adminKey = buildAdminKey();
    replaceJsonString(configPath, 'kakaoNativeAppKey', nativeKey);
    final String configBefore = File(configPath).readAsStringSync();
    final h = _Harness(root, const <String?>['y']);
    h
      ..onSecretReads(nativeSecret, <CommandResult>[
        ok('$secretPlaceholderValue\n'),
        ok('$secretPlaceholderValue\n'),
        ok('$nativeKey\n'),
      ])
      ..onSecretReads(adminSecret, <CommandResult>[ok('$adminKey\n')])
      ..onSecretWrite(nativeSecret)
      ..onAdminCheck(<RestResponse>[const RestResponse(200, '{}')]);

    final int code = await h.run();

    expect(code, wizardExitDone, reason: h.output);
    expect(h.screen.asks, <String>[stepConfirmQuestion]);
    expect(h.screen.secretAsks, isEmpty);
    expect(readXcconfigNativeKey(), nativeKey);
    expect(File(configPath).readAsStringSync(), configBefore);
    expect(h.secretWrites.map((FakeCall call) => call.key), <String>[
      'firebase functions:secrets:set $nativeSecret --project $projectId --data-file -',
    ]);
    expect(h.secretWrites.single.stdinText, nativeKey);
    // 맞춤 전 어드민 키 서버 확인 1회 — Secret Manager 값을 헤더에만 싣는다.
    expect(
      h.rest.externalRequests.single.headers['Authorization'],
      'KakaoAK $adminKey',
    );
    for (final text in <String>[h.output, h.log.text]) {
      expect(countText(text, adminKey), 0);
    }
    expect(h.output, contains('  ✓ ${KakaoStep.stepTitle} — '));
  });

  test('T-20-KAKAO-07: 값 표에 패키지명 · 번들 ID · 콘솔 주소 · docs/setup.md 절이 있고 비밀 값 · '
      '결정 ID 모양은 없다', () async {
    final String nativeKey = buildNativeKey();
    final String adminKey = buildAdminKey();
    final h = _Harness(root, <String?>['y', '1', nativeKey, adminKey]);
    registerFreshSecrets(h, nativeKey, adminKey);
    h.onAdminCheck(<RestResponse>[const RestResponse(200, '{}')]);

    final int code = await h.run();
    final String output = h.output;

    expect(code, wizardExitDone, reason: output);
    expect(output, contains('── Kakao 콘솔에 넣을 값 — dev ──'));
    expect(output, contains('$applicationId.dev'));
    expect(output, contains(devBundleId));
    expect(output, contains('https://developers.kakao.com/console/app'));
    expect(output, contains('docs/setup.md 「Kakao 로그인 켜기」'));
    expect(output, contains('docs/setup.md 「로그인 수단에서 이메일 받기」'));
    for (final text in <String>[output, h.log.text]) {
      expect(countText(text, adminKey), 0);
      expect(RegExp(r'\bD-[0-9]{2}\b').hasMatch(text), isFalse);
      expect(RegExp('Phase [0-9]').hasMatch(text), isFalse);
    }
    expect(h.log.text, contains('(비밀 값 32자)'));
  });

  test('T-20-KAKAO-08: 값 표의 Android 키 해시 행 — 계산함 · 계산할 수 없음 · 계산 전', () {
    /// 세션에 [fingerprints] 를 담은 문맥으로 값 표 행을 만든다.
    Map<String, String> buildRows(DebugFingerprints? fingerprints) {
      final session = WizardSession()..debugFingerprints = fingerprints;
      final List<SummaryRow> rows = KakaoStep().buildValueRows(
        buildTestContext(projectRoot: root, session: session),
      );
      return <String, String>{
        for (final SummaryRow row in rows) row.label: row.value,
      };
    }

    const keyHash = 'q1AFhLJe1jbJyRsDcFRsODGFDxY=';
    expect(
      buildRows(
        const FingerprintsAvailable(
          sha1Hex: 'ab500584b25ed636c9c91b0370546c3831850f16',
          sha256Hex: '',
          keyHash: keyHash,
        ),
      ),
      <String, String>{
        'Android 패키지명': '$applicationId.dev',
        'iOS 번들 ID': devBundleId,
        KakaoStep.keyHashRowLabel: keyHash,
      },
    );
    expect(
      buildRows(const FingerprintsUnavailable('keytool 을 찾지 못했습니다')),
      <String, String>{
        'Android 패키지명': '$applicationId.dev',
        'iOS 번들 ID': devBundleId,
        KakaoStep.keyHashRowLabel: KakaoStep.keyHashUnavailableValue,
      },
    );
    expect(buildRows(null).keys, <String>['Android 패키지명', 'iOS 번들 ID']);
  });

  test('T-20-KAKAO-09: 첫 할 일 줄은 애플리케이션 하나 · 키 해시 칸은 비워 두고 나중에 '
      '등록하라는 뜻', () async {
    final List<String> todo = KakaoStep().todoLines;

    expect(todo.first, '애플리케이션 새로 만들기');
    for (final line in todo) {
      expect(line, isNot(contains('flavor 마다')));
    }
    const String value = KakaoStep.keyHashUnavailableValue;
    for (final word in <String>['계산할 수 없음', '비워 두세요', 'Android 쪽 줄', '나중에']) {
      expect(value, contains(word));
    }
    expect(value, isNot(contains('지금은 계산할 수 없음')));

    final h = _Harness(root, const <String?>['y', '2']);
    registerFreshSecrets(h, buildNativeKey(), buildAdminKey());

    final int code = await h.run();

    expect(code, wizardExitForUser, reason: h.output);
    final String keyHashRow = h.output
        .split('\n')
        .firstWhere(
          (String line) => line.startsWith('  ${KakaoStep.keyHashRowLabel}'),
          orElse: () => '',
        );
    expect(keyHashRow, endsWith('  $value'));
  });

  test('T-20-KAKAO-10: 둘째 할 일 줄은 네이티브 앱 키 아래 세 칸 · 옛 플랫폼 경로 0 · '
      '네 줄 모두 화면에', () async {
    final List<String> todo = KakaoStep().todoLines;

    expect(todo, hasLength(4));
    expect(todo[1], '네이티브 앱 키에 Android 패키지명 · 키 해시 · iOS 번들 ID 등록');
    for (final line in todo) {
      expect(line, isNot(contains('Android 플랫폼')));
      expect(line, isNot(contains('iOS 플랫폼')));
    }

    final h = _Harness(root, const <String?>['y', '2']);
    registerFreshSecrets(h, buildNativeKey(), buildAdminKey());

    final int code = await h.run();

    expect(code, wizardExitForUser, reason: h.output);
    expect(h.output, contains(todo.map((String l) => '  · $l\n').join()));
    expect(h.output, contains('  Android 패키지명'));
    expect(h.output, contains('  iOS 번들 ID'));
    expect(h.output, contains('  ${KakaoStep.keyHashRowLabel}'));
  });

  group('어드민 키를 그대로 둘지 묻는 질문 — 고르는 조건 · 문구 원문', () {
    /// 이번에 입력한 네이티브 앱 키.
    final String enteredNative = buildNativeKey('1');

    /// Secret Manager 의 다른 네이티브 앱 키.
    final String storedNative = buildNativeKey('0');

    /// Secret Manager 의 어드민 키.
    final String storedAdmin = buildAdminKey('2');

    /// [entered] · [stored] 로 Kakao 단계의 질문 고르기를 부른다.
    List<StoredSecretQuestion> selectQuestions(
      Map<KeyField, String> entered,
      Map<String, String> stored,
    ) => KakaoStep().selectStoredSecretQuestions(entered, stored);

    test('입력한 네이티브 앱 키가 Secret Manager 의 것과 다르고 어드민 키가 있으면 '
        '어드민 키 질문 하나를 고른다', () {
      expect(
        selectQuestions(
          <KeyField, String>{KakaoStep.nativeAppKeyField: enteredNative},
          <String, String>{
            nativeSecret: storedNative,
            adminSecret: storedAdmin,
          },
        ),
        <StoredSecretQuestion>[KakaoStep.adminKeyStoredQuestion],
      );
    });

    test('네이티브 앱 키를 묻지 않은 실행은 고르지 않는다', () {
      expect(
        selectQuestions(const <KeyField, String>{}, <String, String>{
          nativeSecret: storedNative,
          adminSecret: storedAdmin,
        }),
        isEmpty,
      );
    });

    test('Secret Manager 의 네이티브 앱 키가 입력값과 같으면 고르지 않는다', () {
      expect(
        selectQuestions(
          <KeyField, String>{KakaoStep.nativeAppKeyField: enteredNative},
          <String, String>{
            nativeSecret: enteredNative,
            adminSecret: storedAdmin,
          },
        ),
        isEmpty,
      );
    });

    test('Secret Manager 에 네이티브 앱 키가 없으면 고르지 않는다', () {
      expect(
        selectQuestions(
          <KeyField, String>{KakaoStep.nativeAppKeyField: enteredNative},
          <String, String>{adminSecret: storedAdmin},
        ),
        isEmpty,
      );
    });

    test('Secret Manager 에 어드민 키가 없으면 고르지 않는다', () {
      expect(
        selectQuestions(
          <KeyField, String>{KakaoStep.nativeAppKeyField: enteredNative},
          <String, String>{nativeSecret: storedNative},
        ),
        isEmpty,
      );
    });

    test('질문 · 두 선택지 문구가 원문 그대로이고 질문 묶음이 그 문구를 쓴다', () {
      expect(
        KakaoStep.adminKeyAppQuestion,
        '입력한 네이티브 앱 키가 Secret Manager 의 네이티브 앱 키와 다릅니다 — '
        'Secret Manager 의 어드민 키가 입력한 키와 같은 Kakao 앱의 키인가요?',
      );
      expect(
        KakaoStep.adminKeyKeepOption,
        '네 — 같은 Kakao 앱입니다 · 어드민 키를 그대로 둡니다',
      );
      expect(
        KakaoStep.adminKeyRenewOption,
        '아니요 — 새 Kakao 앱입니다 · 어드민 키를 새로 입력합니다',
      );
      const StoredSecretQuestion question = KakaoStep.adminKeyStoredQuestion;
      expect(question.field, KakaoStep.adminKeyField);
      expect(question.question, KakaoStep.adminKeyAppQuestion);
      expect(question.keepOption, KakaoStep.adminKeyKeepOption);
      expect(question.renewOption, KakaoStep.adminKeyRenewOption);
    });
  });
}
