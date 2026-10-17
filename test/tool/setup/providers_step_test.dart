import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

import '../../../tool/setup/command_runner.dart';
import '../../../tool/setup/config_files.dart';
import '../../../tool/setup/providers/provider_catalog.dart';
import '../../../tool/setup/providers/provider_selection.dart';
import '../../../tool/setup/providers/sign_in_counts.dart';
import '../../../tool/setup/redactor.dart';
import '../../../tool/setup/rest_client.dart';
import '../../../tool/setup/step.dart';
import '../../../tool/setup/steps/firebase_project_step.dart';
import '../../../tool/setup/steps/functions_step.dart';
import '../../../tool/setup/steps/providers_step.dart';
import '../../../tool/setup/steps/run_step.dart';
import '../../../tool/setup/steps/user_files_step.dart';
import '../../../tool/setup/wizard.dart';
import 'fake_rest_client.dart';
import 'fakes.dart';

/// 테스트 프로젝트 ID(가짜).
const String projectId = 'demo-project';

/// 응답 fixture 에 넣는 가짜 사용자 값 — 화면 · 기록에 나오면 안 된다.
const List<String> fakePersonalValues = <String>[
  'user-1@example.invalid',
  'uid-fake-1',
  'kakao:fake-1',
  'kakao:fake-2',
];

/// 이미 끝난 앞 단계 — 로그인 수단 단계의 의존 단계를 대신한다.
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

/// 로그인 수단 단계 한 번 실행에 쓰는 화면 · 기록 묶음.
final class _Harness {
  _Harness(
    this.root,
    List<String?> inputs, {
    bool isRequested = false,
    FakeRestClient? rest,
    FakeCommandRunner? runner,
  }) : screen = ScriptedTerminal(inputs),
       rest = rest ?? FakeRestClient(),
       runner = runner ?? FakeCommandRunner() {
    context = buildTestContext(
      projectRoot: root,
      terminal: screen,
      rest: this.rest,
      runner: this.runner,
      log: log,
    );
    context.session.isProviderSelectionRequested = isRequested;
  }

  final String root;
  final ScriptedTerminal screen;
  final FakeRestClient rest;
  final FakeCommandRunner runner;
  final MemoryLogSink log = MemoryLogSink(Redactor());
  late final WizardContext context;

  /// 단계 목록을 다시 만든 횟수.
  int rebuildCount = 0;

  /// 화면 출력 전체.
  String get output => screen.output.toString();

  /// 앞 단계(끝남) · 로그인 수단 단계 목록을 만든다.
  List<Step> buildStepList() => <Step>[
    _FinishedStep('sign_in', '로그인 수단 (이메일 · 익명)'),
    _FinishedStep('firestore', '위치 · Firestore'),
    ProvidersStep(),
  ];

  /// 위저드를 돌린다 — 목록 다시 짜기는 같은 목록을 새로 만들고 횟수를 센다.
  Future<int> run() => runWizard(
    context,
    buildStepList(),
    rebuildSteps: () {
      rebuildCount++;
      return buildStepList();
    },
  );

  /// 체크 목록 질문 수.
  int countChoiceQuestions() =>
      screen.asks.where((String ask) => ask == providerChoiceQuestion).length;

  /// 화면 · 기록에 가짜 사용자 값이 나온 횟수.
  int countPersonalValues() => fakePersonalValues
      .map(
        (String value) =>
            value.allMatches(output).length + value.allMatches(log.text).length,
      )
      .fold(0, (int sum, int count) => sum + count);
}

/// 테스트 Functions 리전 — example config 의 값 그대로.
const String region = 'asia-northeast3';

/// 배포된 함수 목록 명령 키.
const String functionsListKey =
    'firebase functions:list --json --project $projectId';

/// Kakao 로그인 함수(함수 목록 파일 순서).
const List<String> kakaoFunctions = <String>[
  'kakaoCustomToken',
  'linkKakaoProvider',
  'disconnectKakaoProvider',
];

/// firebase-tools 원문 fixture — 지울 함수가 이미 없을 때의 삭제 출력.
const String deleteNoMatchFixturePath =
    'test/tool/setup/fixtures/functions_delete_no_match.txt';

/// firebase-tools 원문 fixture — 삭제 확인을 받지 못해 멈춘 삭제 출력.
const String deleteAbortedFixturePath =
    'test/tool/setup/fixtures/functions_delete_aborted.txt';

/// [names] 를 지우는 명령 키.
String buildDeleteKey(List<String> names) =>
    'firebase functions:delete ${names.join(' ')} --region $region '
    '--project $projectId --force --non-interactive';

/// `firebase functions:list --json` 성공 출력을 만든다 — [ids] 가 [region] 에 있다.
CommandResult buildFunctionsList(List<String> ids) => CommandResult(
  0,
  jsonEncode(<String, Object?>{
    'status': 'success',
    'result': <Object?>[
      for (final String id in ids)
        <String, Object?>{
          'id': id,
          'region': region,
          'runServiceId': id.toLowerCase(),
        },
    ],
  }),
  '',
);

/// 사용자 목록 한 페이지 응답 — [providerIds] 마다 가짜 사용자 하나.
RestResponse buildUsersPage(List<String> providerIds) => RestResponse(
  200,
  jsonEncode(<String, Object?>{
    'users': <Object?>[
      for (final String id in providerIds)
        <String, Object?>{
          'localId': 'uid-fake-1',
          'email': 'user-1@example.invalid',
          'providerUserInfo': <Object?>[
            <String, Object?>{'providerId': id},
          ],
        },
    ],
  }),
);

/// identity_index 한 페이지 응답 — [providers] 마다 가짜 문서 하나.
RestResponse buildIndexPage(List<String> providers) => RestResponse(
  200,
  jsonEncode(<String, Object?>{
    'documents': <Object?>[
      for (var i = 0; i < providers.length; i++)
        <String, Object?>{
          'name':
              'projects/$projectId/databases/(default)/documents/'
              'identity_index/${providers[i]}:fake-${i + 1}',
          'fields': <String, Object?>{
            'provider': <String, Object?>{'stringValue': providers[i]},
          },
        },
    ],
  }),
);

/// 사용자 목록 첫 페이지 주소.
String buildUsersUrl() =>
    RunStep.buildBatchGetRequest(projectId).url.toString();

/// identity_index 첫 페이지 주소.
String buildIndexUrl() => buildIdentityIndexRequest(projectId).url.toString();

void main() {
  late Directory tempDir;
  late String root;
  late String configPath;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('providers_step_test_');
    root = tempDir.path;
    configPath = '$root/${UserFilesStep.jsonUserPath}';
    File(configPath)
      ..parent.createSync(recursive: true)
      ..writeAsStringSync(
        File(UserFilesStep.jsonExamplePath).readAsStringSync(),
      );
    File('$root/${FunctionsStep.manifestPath}')
      ..parent.createSync(recursive: true)
      ..writeAsStringSync(File(FunctionsStep.manifestPath).readAsStringSync());
  });

  tearDown(() {
    tempDir.deleteSync(recursive: true);
  });

  /// config 의 로그인 수단 CSV.
  String? readCsv() => readJsonString(configPath, enabledProvidersKey);

  test('T-20-PROV-01: 체크 목록에 0 이면 CSV 를 빈 문자열로 쓰고 단계 목록을 다시 짠다 · '
      '다른 config 바이트는 그대로', () async {
    replaceJsonString(configPath, enabledProvidersKey, 'google,kakao');
    replaceJsonString(configPath, FirebaseProjectStep.projectIdKey, projectId);
    final String before = File(configPath).readAsStringSync();
    final rest = FakeRestClient()
      ..on('GET', buildUsersUrl(), const RestResponse(200, '{}'))
      ..on('GET', buildIndexUrl(), const RestResponse(200, '{}'));
    final runner = FakeCommandRunner()
      ..on(functionsListKey, buildFunctionsList(const <String>['ping']));
    final h = _Harness(
      root,
      const <String?>['y', '0', 'y'],
      isRequested: true,
      rest: rest,
      runner: runner,
    );

    final int code = await h.run();

    expect(code, wizardExitDone, reason: h.output);
    expect(readCsv(), '');
    expect(
      File(configPath).readAsStringSync(),
      before.replaceFirst(
        '"$enabledProvidersKey": "google,kakao"',
        '"$enabledProvidersKey": ""',
      ),
    );
    expect(h.rebuildCount, 1);
    expect(h.output, contains(replanLine));
    expect(h.output, contains('  ✓ ${ProvidersStep.stepTitle} — 이메일만 · '));
    expect(h.output, contains('뺀 것'));
    expect(h.context.session.isProviderSelectionRequested, isFalse);
  });

  test('T-20-PROV-02: 잘못된 번호는 이유 한 줄 뒤 다시 묻고 3회 넘으면 멈춘다 · CSV 그대로', () async {
    final String before = File(configPath).readAsStringSync();
    final h = _Harness(root, const <String?>[
      'y',
      '9',
      '1 x',
      '0 1',
    ], isRequested: true);

    final int code = await h.run();

    expect(code, wizardExitStopped);
    expect(h.countChoiceQuestions(), maxProviderChoiceAttempts);
    expect(h.output, contains('9 는 없습니다'));
    expect(h.output, contains('「x」 는 번호가 아닙니다'));
    expect(h.output, contains('0(이메일만)은 다른 번호와 함께 쓸 수 없습니다'));
    expect(File(configPath).readAsStringSync(), before);
    expect(h.rebuildCount, 0);
  });

  test('T-20-PROV-03: Enter 면 CSV 그대로 · 다시 짜기 없이 같은 실행의 재검사가 ✓ 다', () async {
    replaceJsonString(configPath, enabledProvidersKey, 'kakao');
    final String before = File(configPath).readAsStringSync();
    final h = _Harness(root, const <String?>['y', ''], isRequested: true);

    final int code = await h.run();

    expect(code, wizardExitDone, reason: h.output);
    expect(File(configPath).readAsStringSync(), before);
    expect(h.rebuildCount, 0);
    expect(h.output, isNot(contains(replanLine)));
    expect(h.output, contains('  4) [x] Kakao'));
    expect(
      h.output,
      contains(
        '  ✓ ${ProvidersStep.stepTitle} — 이메일 + Kakao · 바꾸기: '
        '${ProvidersStep.reopenCommand}',
      ),
    );
    expect(h.screen.asks, isNot(contains('이 값으로 진행할까요?')));
  });

  test(
    'T-20-PROV-04: CSV 에 모르는 토큰이 있으면 점검표 ✗ · 고른 결과로 고쳐 써 모르는 토큰을 지운다',
    () async {
      replaceJsonString(configPath, enabledProvidersKey, 'kakao,wechat');
      final h = _Harness(root, const <String?>['y', '', 'y']);

      final int code = await h.run();

      expect(code, wizardExitDone, reason: h.output);
      expect(
        h.output,
        contains('  ✗ ${ProvidersStep.stepTitle} — 알 수 없는 로그인 수단: wechat'),
      );
      expect(readCsv(), 'kakao');
      expect(h.output, contains('지울 토큰'));
      expect(h.rebuildCount, 0);
      expect(
        h.output,
        contains('  ✓ ${ProvidersStep.stepTitle} — 이메일 + Kakao · '),
      );
    },
  );

  group('T-20-PROV-05: 플래그 · 값 표 확인', () {
    test('플래그 없는 실행은 체크 목록을 열지 않고 ✓ 줄에 바꾸는 방법을 보인다', () async {
      final h = _Harness(root, const <String?>[]);

      final int code = await h.run();

      expect(code, wizardExitDone, reason: h.output);
      expect(h.screen.asks, isEmpty);
      expect(
        h.output,
        contains(
          '  ✓ ${ProvidersStep.stepTitle} — 이메일만 · 바꾸기: '
          '${ProvidersStep.reopenCommand}',
        ),
      );
    });

    test('값 표에서 아니요면 CSV 를 바꾸지 않고 멈춘다', () async {
      final String before = File(configPath).readAsStringSync();
      final h = _Harness(root, const <String?>[
        'y',
        '4',
        'n',
      ], isRequested: true);

      final int code = await h.run();

      expect(code, wizardExitStopped);
      expect(File(configPath).readAsStringSync(), before);
      expect(h.output, contains('더한 것'));
      expect(h.rebuildCount, 0);
    });
  });

  group('끄기 전 가입자 수 검사', () {
    setUp(() {
      replaceJsonString(
        configPath,
        FirebaseProjectStep.projectIdKey,
        projectId,
      );
    });

    test('T-20-OFF-01: 가입자가 있는 Kakao 를 빼면 CSV 를 그대로 두고 kill switch 를 안내한 뒤 '
        '위저드 밖으로 끝난다', () async {
      replaceJsonString(configPath, enabledProvidersKey, 'kakao');
      final String before = File(configPath).readAsStringSync();
      final rest = FakeRestClient()
        ..on(
          'GET',
          buildIndexUrl(),
          buildIndexPage(<String>['kakao', 'kakao']),
        );
      final h = _Harness(
        root,
        const <String?>['y', '0'],
        isRequested: true,
        rest: rest,
      );

      final int code = await h.run();

      expect(code, wizardExitForUser, reason: h.output);
      expect(File(configPath).readAsStringSync(), before);
      expect(h.output, contains('2명이 Kakao'));
      expect(h.output, contains('로그인 · 재인증 · 회원탈퇴를 못 합니다'));
      expect(h.output, contains('auth_provider_kakao_enabled'));
      expect(h.output, contains('RC Kill Switch'));
      expect(h.output, contains('테스트 계정'));
      expect(h.output, contains(exitForUserTailLine));
      expect(h.screen.asks, isNot(contains('이 값으로 진행할까요?')));
      expect(h.runner.calls, isEmpty);
      expect(h.rebuildCount, 0);
      expect(h.countPersonalValues(), 0);
    });

    test('T-20-OFF-02: Google · Kakao 를 함께 빼고 Kakao 만 가입자가 있어도 CSV 전체를 그대로 '
        '둔다', () async {
      replaceJsonString(configPath, enabledProvidersKey, 'google,kakao');
      final String before = File(configPath).readAsStringSync();
      final rest = FakeRestClient()
        ..on('GET', buildUsersUrl(), buildUsersPage(<String>['password']))
        ..on('GET', buildIndexUrl(), buildIndexPage(<String>['kakao']));
      final h = _Harness(
        root,
        const <String?>['y', '0'],
        isRequested: true,
        rest: rest,
      );

      final int code = await h.run();

      expect(code, wizardExitForUser, reason: h.output);
      expect(File(configPath).readAsStringSync(), before);
      expect(h.output, contains('1명이 Kakao'));
      expect(h.output, isNot(contains('명이 Google')));
      expect(h.output, contains('auth_provider_kakao_enabled'));
      expect(h.output, isNot(contains('auth_provider_google_enabled')));
      expect(h.runner.calls, isEmpty);
      expect(h.countPersonalValues(), 0);
    });

    test('T-20-OFF-03: 가입자 수를 세지 못하면 실패로 멈추고 CSV 를 그대로 둔다', () async {
      replaceJsonString(configPath, enabledProvidersKey, 'kakao');
      final String before = File(configPath).readAsStringSync();
      final rest = FakeRestClient()
        ..on(
          'GET',
          buildIndexUrl(),
          const RestResponse(403, '{"error":{"status":"PERMISSION_DENIED"}}'),
        );
      final h = _Harness(
        root,
        const <String?>['y', '0'],
        isRequested: true,
        rest: rest,
      );

      final int code = await h.run();

      expect(code, wizardExitStopped, reason: h.output);
      expect(File(configPath).readAsStringSync(), before);
      expect(h.output, contains('HTTP 403'));
      expect(h.output, contains('CSV 는 그대로입니다'));
      expect(h.screen.asks, isNot(contains('이 값으로 진행할까요?')));
      expect(h.runner.calls, isEmpty);
      expect(h.rebuildCount, 0);
    });
  });

  group('가입자 0명 끄기 — 함수 삭제 한 번 묻기', () {
    late String before;

    setUp(() {
      replaceJsonString(
        configPath,
        FirebaseProjectStep.projectIdKey,
        projectId,
      );
      replaceJsonString(configPath, enabledProvidersKey, 'kakao');
      before = File(configPath).readAsStringSync();
    });

    /// Kakao 0명 응답을 등록한 가짜 REST.
    FakeRestClient buildZeroKakaoRest() =>
        FakeRestClient()
          ..on('GET', buildIndexUrl(), const RestResponse(200, '{}'));

    /// CSV 에서 kakao 만 빠졌고 다른 config 바이트는 그대로인지 본다.
    void expectOnlyCsvChanged() {
      expect(readCsv(), '');
      expect(
        File(configPath).readAsStringSync(),
        before.replaceFirst(
          '"$enabledProvidersKey": "kakao"',
          '"$enabledProvidersKey": ""',
        ),
      );
    }

    test('T-20-OFF-04: Kakao 0명 · 배포 함수 3개 → CSV 에서 빼고 이름을 보인 뒤 한 번 묻는다 · '
        'Enter 면 지우지 않는다 · 키 · xcconfig · secret 쓰기 0', () async {
      final runner = FakeCommandRunner()
        ..on(
          functionsListKey,
          buildFunctionsList(<String>['ping', ...kakaoFunctions]),
        );
      final h = _Harness(
        root,
        const <String?>['y', '0', 'y', ''],
        isRequested: true,
        rest: buildZeroKakaoRest(),
        runner: runner,
      );

      final int code = await h.run();

      expect(code, wizardExitDone, reason: h.output);
      expectOnlyCsvChanged();
      for (final name in kakaoFunctions) {
        expect(h.output, contains(name));
      }
      expect(h.screen.asks.where((String a) => a == '지울까요?'), hasLength(1));
      expect(h.output, contains('지울까요? [y/N]'));
      expect(h.runner.countMode(RunMode.stream), 0);
      expect(h.runner.calls.map((FakeCall call) => call.key).toList(), <String>[
        functionsListKey,
      ]);
      expect(File('$root/ios/Flutter/dev.xcconfig').existsSync(), isFalse);
      expect(h.rebuildCount, 1);
      expect(h.output, contains(replanLine));
    });

    test('T-20-OFF-05: y 면 함수 목록 파일 순서 ∩ 배포 함수를 config 리전으로 한 번 지우고 '
        '단계 목록을 다시 짠다', () async {
      final expected = <String>['kakaoCustomToken', 'disconnectKakaoProvider'];
      final runner = FakeCommandRunner()
        ..on(
          functionsListKey,
          buildFunctionsList(<String>[
            'disconnectKakaoProvider',
            'ping',
            'kakaoCustomToken',
          ]),
        )
        ..on(buildDeleteKey(expected), const CommandResult(0, '', ''));
      final h = _Harness(
        root,
        const <String?>['y', '0', 'y', 'y'],
        isRequested: true,
        rest: buildZeroKakaoRest(),
        runner: runner,
      );

      final int code = await h.run();

      expect(code, wizardExitDone, reason: h.output);
      expectOnlyCsvChanged();
      expect(h.runner.countCalls(RunMode.stream, buildDeleteKey(expected)), 1);
      expect(h.runner.countMode(RunMode.stream), 1);
      expect(h.output, isNot(contains('linkKakaoProvider')));
      expect(h.rebuildCount, 1);
    });

    group('T-20-OFF-06: 삭제 출력 모양', () {
      test('지울 함수가 이미 없다는 출력이면 진행한다', () async {
        final runner = FakeCommandRunner()
          ..on(functionsListKey, buildFunctionsList(kakaoFunctions))
          ..on(
            buildDeleteKey(kakaoFunctions),
            CommandResult(
              1,
              '',
              File(deleteNoMatchFixturePath).readAsStringSync(),
            ),
          );
        final h = _Harness(
          root,
          const <String?>['y', '0', 'y', 'y'],
          isRequested: true,
          rest: buildZeroKakaoRest(),
          runner: runner,
        );

        final int code = await h.run();

        expect(code, wizardExitDone, reason: h.output);
        expectOnlyCsvChanged();
        expect(h.output, contains('이미 지워져 있습니다'));
        expect(h.rebuildCount, 1);
      });

      test('멈춤 출력이면 원문을 보이는 실패다', () async {
        final runner = FakeCommandRunner()
          ..on(functionsListKey, buildFunctionsList(kakaoFunctions))
          ..on(
            buildDeleteKey(kakaoFunctions),
            CommandResult(
              1,
              '',
              File(deleteAbortedFixturePath).readAsStringSync(),
            ),
          );
        final h = _Harness(
          root,
          const <String?>['y', '0', 'y', 'y'],
          isRequested: true,
          rest: buildZeroKakaoRest(),
          runner: runner,
        );

        final int code = await h.run();

        expect(code, wizardExitStopped, reason: h.output);
        expect(h.output, contains('함수를 지우지 못했습니다'));
        expect(h.output, contains('Error: Command aborted.'));
        expect(readCsv(), '');
        expect(h.rebuildCount, 0);
      });
    });

    test('T-20-OFF-07: 배포 함수가 없는 수단(Google · Apple)을 빼면 삭제 질문 · 함수 목록 '
        '요청이 없다', () async {
      replaceJsonString(configPath, enabledProvidersKey, 'google,apple');
      final rest = FakeRestClient()
        ..on('GET', buildUsersUrl(), buildUsersPage(<String>['password']));
      final h = _Harness(
        root,
        const <String?>['y', '0', 'y'],
        isRequested: true,
        rest: rest,
      );

      final int code = await h.run();

      expect(code, wizardExitDone, reason: h.output);
      expect(readCsv(), '');
      expect(h.screen.asks, isNot(contains('지울까요?')));
      expect(h.runner.calls, isEmpty);
      expect(h.rebuildCount, 1);
    });
  });
}
