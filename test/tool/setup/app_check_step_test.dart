import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:test/test.dart';

import '../../../tool/setup/config_files.dart';
import '../../../tool/setup/firebase_app_files.dart';
import '../../../tool/setup/redactor.dart';
import '../../../tool/setup/rest_client.dart';
import '../../../tool/setup/step.dart';
import '../../../tool/setup/steps/app_check_step.dart';
import '../../../tool/setup/steps/dev_steps.dart';
import '../../../tool/setup/steps/user_files_step.dart';
import '../../../tool/setup/uuid.dart';
import '../../../tool/setup/wizard.dart';
import 'fake_rest_client.dart';
import 'fakes.dart';
import 'firebase_options_fixture.dart';

/// 테스트 프로젝트 ID.
const String projectId = 'p';

/// fixture Gradle 의 applicationId.
const String applicationId = 'com.example.app_android';

/// fixture iOS 앱 ID.
const String iosAppId = '1:000:ios:fake';

/// fixture Android 앱 ID.
const String androidAppId = '1:000:android:fake';

/// App Check API 주소의 앞부분.
const String appCheckPrefix = 'https://firebaseappcheck.googleapis.com/v1/';

/// iOS 앱 디버그 토큰 목록 주소.
const String iosTokensUrl =
    '${appCheckPrefix}projects/$projectId/apps/$iosAppId/debugTokens';

/// Android 앱 디버그 토큰 목록 주소.
const String androidTokensUrl =
    '${appCheckPrefix}projects/$projectId/apps/$androidAppId/debugTokens';

/// 위저드가 쓰는 고정 표시 이름.
const String wizardDisplayName = 'setup-wizard-dev';

/// 실행 시점에 조립한 가짜 API 키 — 소스에 완형을 두지 않는다.
final String fakeApiKey = 'AIza${'x' * 35}';

/// 이미 끝난 앞 단계 — App Check 단계의 의존 단계를 대신한다.
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

/// 디버그 토큰 목록 응답을 만든다 — [names] 는 `<표시 이름>:<id>` 꼴.
RestResponse buildTokenList(String tokensUrl, List<String> names) =>
    RestResponse(
      200,
      jsonEncode(<String, Object?>{
        if (names.isNotEmpty)
          'debugTokens': <Object?>[
            for (final String entry in names)
              <String, Object?>{
                'name':
                    '${tokensUrl.substring(appCheckPrefix.length)}/'
                    '${entry.split(':').last}',
                'displayName': entry.split(':').first,
                'updateTime': '2030-01-01T00:00:00Z',
              },
          ],
      }),
    );

void main() {
  late Directory tempDir;
  late String root;
  late File config;

  /// 저장소 상대 경로에 내용을 쓴다(부모 디렉터리를 만든다).
  void writeFixture(String relativePath, String content) {
    File('$root/$relativePath')
      ..parent.createSync(recursive: true)
      ..writeAsStringSync(content);
  }

  /// 앱 등록이 끝난 모양의 설정 파일 3개를 쓴다(Dart 설정 파일 = FlutterFire 생성본 모양).
  void writeAppFiles() {
    writeFixture(
      FirebaseAppFiles.optionsPath,
      buildGeneratedOptionsSource(
        projectId: projectId,
        apiKey: fakeApiKey,
        androidAppId: androidAppId,
        iosAppId: iosAppId,
      ),
    );
    writeFixture(
      FirebaseAppFiles.iosPlistPath,
      '<plist version="1.0">\n'
      '<dict>\n'
      '\t<key>API_KEY</key>\n'
      '\t<string>$fakeApiKey</string>\n'
      '\t<key>PROJECT_ID</key>\n'
      '\t<string>$projectId</string>\n'
      '\t<key>GOOGLE_APP_ID</key>\n'
      '\t<string>$iosAppId</string>\n'
      '</dict>\n'
      '</plist>\n',
    );
    writeFixture(
      FirebaseAppFiles.androidJsonPath,
      jsonEncode(<String, Object?>{
        'project_info': <String, Object?>{'project_id': projectId},
        'client': <Object?>[
          <String, Object?>{
            'client_info': <String, Object?>{
              'mobilesdk_app_id': androidAppId,
              'android_client_info': <String, Object?>{
                'package_name': '$applicationId.dev',
              },
            },
            'api_key': <Object?>[
              <String, Object?>{'current_key': fakeApiKey},
            ],
          },
        ],
      }),
    );
  }

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('app_check_step_test_');
    root = tempDir.path;
    config = File('$root/${UserFilesStep.jsonUserPath}')
      ..parent.createSync(recursive: true);
    File(UserFilesStep.jsonExamplePath).copySync(config.path);
    replaceJsonString(config.path, 'firebaseProjectId', projectId);
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

  /// config 의 디버그 토큰 값.
  String readToken() =>
      readJsonString(config.path, AppCheckStep.tokenKey) ?? '<없음>';

  /// 앞 단계(끝남) · App Check 단계로 위저드를 돌린다.
  Future<int> runAppCheckStep(
    FakeRestClient rest,
    ScriptedTerminal terminal, {
    FakeCommandRunner? runner,
    MemoryLogSink? log,
    Random? random,
  }) => runWizard(
    buildTestContext(
      projectRoot: root,
      runner: runner,
      terminal: terminal,
      log: log,
      rest: rest,
      random: random,
    ),
    <Step>[
      _FinishedStep('configure', '앱 등록 · 설정 파일'),
      _FinishedStep('apis', '필요한 Google Cloud API'),
      AppCheckStep(),
    ],
  );

  /// [method] 요청만 모은다.
  List<RestRequest> listRequests(FakeRestClient rest, String method) => rest
      .requests
      .where((RestRequest request) => request.method == method)
      .toList();

  test(
    'T-19-APPCHECK-01 config 토큰이 UUID4 이고 두 앱 목록에 고정 이름이 있으면 ✓ · POST 0',
    () async {
      writeAppFiles();
      replaceJsonString(
        config.path,
        AppCheckStep.tokenKey,
        generateUuidV4(Random(7)),
      );
      final rest = FakeRestClient()
        ..on(
          'GET',
          iosTokensUrl,
          buildTokenList(iosTokensUrl, <String>['$wizardDisplayName:a1']),
        )
        ..on(
          'GET',
          androidTokensUrl,
          buildTokenList(androidTokensUrl, <String>[
            'someone:b0',
            '$wizardDisplayName:b1',
          ]),
        );
      final terminal = ScriptedTerminal(const <String?>[]);

      final int code = await runAppCheckStep(rest, terminal);

      expect(code, wizardExitDone);
      expect(
        terminal.output.toString(),
        contains('  ✓ ${AppCheckStep.stepTitle} — '),
      );
      expect(terminal.asks, isEmpty);
      expect(listRequests(rest, 'POST'), isEmpty);
      expect(listRequests(rest, 'DELETE'), isEmpty);
    },
  );

  group('토큰을 새로 만드는 흐름', () {
    late FakeRestClient rest;
    late ScriptedTerminal terminal;
    late MemoryLogSink log;
    late FakeCommandRunner runner;
    late int code;

    setUp(() async {
      writeAppFiles();
      expect(readToken(), '');
      rest = FakeRestClient()
        ..on(
          'GET',
          iosTokensUrl,
          buildTokenList(iosTokensUrl, <String>[
            '$wizardDisplayName:old1',
            'manual:keep',
          ]),
        )
        ..on(
          'GET',
          iosTokensUrl,
          buildTokenList(iosTokensUrl, <String>[
            'manual:keep',
            '$wizardDisplayName:new1',
          ]),
        )
        ..on('GET', androidTokensUrl, buildTokenList(androidTokensUrl, []))
        ..on(
          'GET',
          androidTokensUrl,
          buildTokenList(androidTokensUrl, <String>['$wizardDisplayName:new2']),
        )
        ..on('DELETE', '$iosTokensUrl/old1', const RestResponse(200, '{}'))
        ..on('POST', iosTokensUrl, const RestResponse(200, '{}'))
        ..on('POST', androidTokensUrl, const RestResponse(200, '{}'));
      terminal = ScriptedTerminal(const <String?>['y']);
      log = MemoryLogSink(Redactor());
      runner = FakeCommandRunner();
      code = await runAppCheckStep(rest, terminal, runner: runner, log: log);
    });

    test(
      'T-19-APPCHECK-02 빈 토큰 → y 뒤 config 에 UUID4 · 두 앱 옛 고정 이름 항목 DELETE · POST 본문에 새 토큰 · 재검사 ✓',
      () {
        final String token = readToken();
        final output = terminal.output.toString();
        expect(code, wizardExitDone);
        expect(isUuidV4(token), isTrue);
        expect(rest.countRequests('DELETE', '$iosTokensUrl/old1'), 1);
        expect(listRequests(rest, 'DELETE'), hasLength(1));
        final List<RestRequest> posts = listRequests(rest, 'POST');
        expect(
          posts.map((RestRequest request) => request.url.toString()).toSet(),
          <String>{iosTokensUrl, androidTokensUrl},
        );
        for (final post in posts) {
          expect(jsonDecode(post.body!), <String, Object?>{
            'displayName': wizardDisplayName,
            'token': token,
          });
          expect(post.quotaProject, projectId);
        }
        final int deleteAt = rest.requests.indexWhere(
          (RestRequest request) => request.method == 'DELETE',
        );
        final int iosPostAt = rest.requests.indexWhere(
          (RestRequest request) =>
              request.method == 'POST' &&
              request.url.toString() == iosTokensUrl,
        );
        expect(deleteAt, lessThan(iosPostAt));
        expect(output, contains(AppCheckStep.rebuildNotice));
        expect(
          AppCheckStep.rebuildNotice,
          '앱을 다시 빌드해야 새 토큰이 들어갑니다 — 마지막 단계가 빌드합니다.',
        );
        expect(output, contains('  ✓ ${AppCheckStep.stepTitle} — '));
      },
    );

    test(
      'T-19-APPCHECK-03 화면 · 기록 · 실행기 인자에 토큰 0 · 화면은 표시형 · 토큰은 POST 본문에만',
      () {
        final String token = readToken();
        final output = terminal.output.toString();
        expect(token.length, 36);
        expect(output, isNot(contains(token)));
        expect(output, isNot(contains(token.toUpperCase())));
        expect(log.text, isNot(contains(token)));
        expect(output, contains('"token":"${AppCheckStep.tokenDisplay}"'));
        expect(
          AppCheckStep.tokenDisplay,
          '<config/dev.json 의 appCheckDebugToken>',
        );
        expect(runner.calls, isEmpty);
        for (final RestRequest request in rest.requests) {
          expect(request.url.toString(), isNot(contains(token)));
          expect(request.bodyDisplay ?? '', isNot(contains(token)));
          if (request.method != 'POST') {
            expect(request.body ?? '', isNot(contains(token)));
          }
        }
        expect(
          listRequests(
            rest,
            'POST',
          ).every((RestRequest request) => request.body!.contains(token)),
          isTrue,
        );
        for (final secret in <String>[iosAppId, androidAppId]) {
          expect(output, isNot(contains(secret)));
          expect(log.text, isNot(contains(secret)));
        }
      },
    );
  });

  test(
    'T-19-APPCHECK-04 토큰이 있고 Android 앱에만 항목이 없으면 Android POST 1회 · DELETE 0 · iOS 는 목록 GET 만',
    () async {
      writeAppFiles();
      final String token = generateUuidV4(Random(8));
      replaceJsonString(config.path, AppCheckStep.tokenKey, token);
      final rest = FakeRestClient()
        ..on(
          'GET',
          iosTokensUrl,
          buildTokenList(iosTokensUrl, <String>['$wizardDisplayName:a1']),
        )
        ..on('GET', androidTokensUrl, buildTokenList(androidTokensUrl, []))
        ..on('GET', androidTokensUrl, buildTokenList(androidTokensUrl, []))
        ..on(
          'GET',
          androidTokensUrl,
          buildTokenList(androidTokensUrl, <String>['$wizardDisplayName:b1']),
        )
        ..on('POST', androidTokensUrl, const RestResponse(200, '{}'));
      final terminal = ScriptedTerminal(const <String?>['y']);

      final int code = await runAppCheckStep(rest, terminal);

      expect(code, wizardExitDone);
      expect(readToken(), token);
      expect(rest.countRequests('POST', androidTokensUrl), 1);
      expect(rest.countRequests('POST', iosTokensUrl), 0);
      expect(listRequests(rest, 'DELETE'), isEmpty);
      final List<RestRequest> iosRequests = rest.requests
          .where(
            (RestRequest request) => request.url.toString() == iosTokensUrl,
          )
          .toList();
      expect(iosRequests, isNotEmpty);
      expect(
        iosRequests.every((RestRequest request) => request.method == 'GET'),
        isTrue,
      );
      expect(
        jsonDecode(listRequests(rest, 'POST').single.body!),
        <String, Object?>{'displayName': wizardDisplayName, 'token': token},
      );
    },
  );

  test('T-19-APPCHECK-05 POST 400(한도) 면 실패 · 상태 코드 · 응답 원문', () async {
    writeAppFiles();
    const limitBody =
        '{"error":{"code":400,"message":"An app can have at most 20 debug tokens.","status":"FAILED_PRECONDITION"}}';
    final rest = FakeRestClient()
      ..on('GET', iosTokensUrl, buildTokenList(iosTokensUrl, []))
      ..on('GET', androidTokensUrl, buildTokenList(androidTokensUrl, []))
      ..on('POST', iosTokensUrl, const RestResponse(400, limitBody));
    final terminal = ScriptedTerminal(const <String?>['y']);
    final log = MemoryLogSink(Redactor());

    final int code = await runAppCheckStep(rest, terminal, log: log);

    final output = terminal.output.toString();
    final String token = readToken();
    expect(code, wizardExitStopped);
    expect(output, contains('  실패 — '));
    expect(output, contains('HTTP 400'));
    expect(output, contains(limitBody));
    expect(output, isNot(contains(token)));
    expect(log.text, isNot(contains(token)));
  });

  test(
    'T-19-APPCHECK-09 옛 항목 DELETE 가 403 이면 config 토큰은 빈 값 그대로 · 다시 시도의 재검사가 create 로 다시 지운 뒤 등록한다',
    () async {
      writeAppFiles();
      final rest = FakeRestClient()
        ..on(
          'GET',
          iosTokensUrl,
          buildTokenList(iosTokensUrl, <String>['$wizardDisplayName:old1']),
        )
        ..on(
          'GET',
          iosTokensUrl,
          buildTokenList(iosTokensUrl, <String>['$wizardDisplayName:old1']),
        )
        ..on(
          'GET',
          iosTokensUrl,
          buildTokenList(iosTokensUrl, <String>['$wizardDisplayName:new1']),
        )
        ..on('GET', androidTokensUrl, buildTokenList(androidTokensUrl, []))
        ..on(
          'GET',
          androidTokensUrl,
          buildTokenList(androidTokensUrl, <String>['$wizardDisplayName:new2']),
        )
        ..on('DELETE', '$iosTokensUrl/old1', const RestResponse(403, '{}'))
        ..on('DELETE', '$iosTokensUrl/old1', const RestResponse(200, '{}'))
        ..on('POST', iosTokensUrl, const RestResponse(200, '{}'))
        ..on('POST', androidTokensUrl, const RestResponse(200, '{}'));
      // y → DELETE 403 실패 → 1(다시 시도).
      final terminal = ScriptedTerminal(const <String?>['y', '1']);
      final log = MemoryLogSink(Redactor());

      final int code = await runAppCheckStep(rest, terminal, log: log);

      final output = terminal.output.toString();
      final int firstPostAt = rest.requests.indexWhere(
        (RestRequest request) => request.method == 'POST',
      );
      final List<String> createChecks = log.text
          .split('\n')
          .where(
            (String line) =>
                line.contains('app_check ✗') && line.contains('디버그 토큰이 없습니다'),
          )
          .toList();
      expect(code, wizardExitDone);
      expect(output, contains('HTTP 403'));
      // 실패 전에는 POST 가 없고, 첫 POST 앞에 DELETE 가 두 번(실패 · 성공) 있다.
      expect(rest.countRequests('DELETE', '$iosTokensUrl/old1'), 2);
      expect(firstPostAt, greaterThan(0));
      expect(
        rest.requests
            .take(firstPostAt)
            .where((RestRequest request) => request.method == 'DELETE'),
        hasLength(2),
      );
      // 점검표 · 단계 진입 · 다시 시도의 재검사 세 번 모두 config 토큰이 없다는
      // create 판정이다 — 실패 뒤에도 config 에 새 토큰이 쓰이지 않았다.
      expect(createChecks, hasLength(3));
      final String token = readToken();
      expect(isUuidV4(token), isTrue);
      expect(
        listRequests(
          rest,
          'POST',
        ).map((RestRequest request) => jsonDecode(request.body!)),
        everyElement(<String, Object?>{
          'displayName': wizardDisplayName,
          'token': token,
        }),
      );
      expect(output, contains('  ✓ ${AppCheckStep.stepTitle} — '));
    },
  );

  test('T-19-APPCHECK-06 앱 등록 파일이 없으면 ✗ 사유 · 적용하지 않고 실패 · 요청 0', () async {
    final rest = FakeRestClient();
    final terminal = ScriptedTerminal(const <String?>['y']);

    final int code = await runAppCheckStep(rest, terminal);

    final output = terminal.output.toString();
    final String reason = output
        .split('\n')
        .firstWhere(
          (String line) => line.startsWith('  ✗ ${AppCheckStep.stepTitle} — '),
        );
    expect(code, wizardExitStopped);
    expect(reason, contains('앱 등록'));
    expect(output, contains('  실패 — '));
    expect(rest.requests, isEmpty);
    expect(readToken(), '');
  });

  test(
    'T-19-APPCHECK-07 토큰은 context.random 으로만 만든다 — 같은 씨앗이면 같은 값 · 외부 명령 0',
    () async {
      writeAppFiles();
      final rest = FakeRestClient()
        ..on('GET', iosTokensUrl, buildTokenList(iosTokensUrl, []))
        ..on('GET', androidTokensUrl, buildTokenList(androidTokensUrl, []))
        ..on('POST', iosTokensUrl, const RestResponse(200, '{}'))
        ..on('POST', androidTokensUrl, const RestResponse(200, '{}'));
      final runner = FakeCommandRunner();

      await runAppCheckStep(
        rest,
        ScriptedTerminal(const <String?>['y']),
        runner: runner,
        random: Random(42),
      );

      expect(readToken(), generateUuidV4(Random(42)));
      expect(runner.calls, isEmpty);
    },
  );

  test(
    'T-19-APPCHECK-08 Dart 설정 파일이 실제 생성본 모양(예외 throw 5곳)이면 두 앱 ID 를 읽어 ✓ · POST 0 · 화면 · 기록에 앱 ID 0',
    () async {
      writeAppFiles();
      final String written = File(
        '$root/${FirebaseAppFiles.optionsPath}',
      ).readAsStringSync();
      expect('throw UnsupportedError('.allMatches(written), hasLength(5));
      replaceJsonString(
        config.path,
        AppCheckStep.tokenKey,
        generateUuidV4(Random(8)),
      );
      final rest = FakeRestClient()
        ..on(
          'GET',
          iosTokensUrl,
          buildTokenList(iosTokensUrl, <String>['$wizardDisplayName:a1']),
        )
        ..on(
          'GET',
          androidTokensUrl,
          buildTokenList(androidTokensUrl, <String>['$wizardDisplayName:b1']),
        );
      final terminal = ScriptedTerminal(const <String?>[]);
      final log = MemoryLogSink(Redactor());

      final int code = await runAppCheckStep(rest, terminal, log: log);

      final output = terminal.output.toString();
      expect(code, wizardExitDone);
      expect(output, contains('  ✓ ${AppCheckStep.stepTitle} — '));
      expect(
        rest.requests
            .map((RestRequest request) => request.url.toString())
            .toSet(),
        <String>{iosTokensUrl, androidTokensUrl},
      );
      expect(listRequests(rest, 'POST'), isEmpty);
      for (final appId in <String>[iosAppId, androidAppId]) {
        expect(output, isNot(contains(appId)));
        expect(log.text, isNot(contains(appId)));
      }
    },
  );

  test('buildDevSteps 는 rules 다음에 App Check 단계를 둔다', () {
    final List<String> ids = buildDevSteps()
        .map((Step step) => step.id)
        .toList();

    expect(ids.indexOf('app_check'), ids.indexOf('rules') + 1);
  });
}
