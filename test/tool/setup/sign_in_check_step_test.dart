import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:test/test.dart';

import '../../../tool/setup/command_runner.dart';
import '../../../tool/setup/flavor.dart';
import '../../../tool/setup/providers/sign_in_counts.dart';
import '../../../tool/setup/redactor.dart';
import '../../../tool/setup/rest_client.dart';
import '../../../tool/setup/step.dart';
import '../../../tool/setup/steps/flavor_steps.dart';
import '../../../tool/setup/steps/run_step.dart';
import '../../../tool/setup/steps/sign_in_check_step.dart';
import '../../../tool/setup/steps/user_files_step.dart';
import '../../../tool/setup/terminal.dart';
import '../../../tool/setup/wizard.dart';
import 'fake_rest_client.dart';
import 'fakes.dart';

/// 테스트 프로젝트 ID(가짜).
const String projectId = 'demo-signin';

/// 가짜 iOS 시뮬레이터 id — UUID 모양.
const String simulatorId = '0A1B2C3D-4E5F-4A6B-8C7D-9E0F1A2B3C4D';

/// 다시 실행할 때 부르는 대화형 실행 명령 키.
const String runKey =
    'fvm flutter run --flavor dev --dart-define-from-file=config/dev.json '
    '-d $simulatorId';

/// 패키지 받기 명령 키.
final String pubGetKey = FakeCommandRunner.buildKey(
  RunStep.buildPubGetCommand(),
);

/// 코드 생성 명령 키.
final String codegenKey = FakeCommandRunner.buildKey(
  RunStep.buildCodegenCommand(),
);

/// 기기 목록 명령 키.
final String devicesKey = FakeCommandRunner.buildKey(
  RunStep.buildDevicesCommand(),
);

/// 점검표 · 단계 머리의 고르기 선택지 세 줄.
const String choiceLines = '  1) 앱을 다시 실행\n  2) 나중에\n  3) 멈춤\n';

/// 가짜 사용자 이메일 — 화면 · 기록에 나오면 안 된다.
const String fakeEmail = 'signin-user-1@example.invalid';

/// 가짜 uid — 화면 · 기록에 나오면 안 된다(실행 시점 조립).
final String fakeUid = 'uid-${'f' * 8}';

/// [provider] 의 [n] 번째 가짜 identity_index 문서 ID(실행 시점 조립).
String buildDocId(String provider, int n) => '$provider:${'e' * 8}$n';

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

/// 검사에서 한 번 할 일을 내고, 실행하면 끝나는 단계 — 앞 단계가 위저드를 멈추지
/// 않았는지 본다.
final class _PendingStep implements Step {
  _PendingStep(this.id);

  @override
  final String id;

  /// 실행 횟수.
  int applyCount = 0;

  @override
  String get title => '다음 단계';

  @override
  List<String> get dependsOn => const <String>[];

  @override
  bool get isCostlyOrIrreversible => false;

  @override
  Future<CheckResult> check(WizardContext context) async =>
      applyCount == 0 ? const Todo('할 일') : const Done('끝남');

  @override
  List<String> plannedCommandLines(WizardContext context) => const <String>[];

  @override
  Future<StepOutcome> apply(WizardContext context) async {
    applyCount++;
    return const Applied();
  }
}

/// 실제 REST 실행기처럼 요청 · 응답 줄을 기록에 남기는 REST 실행기.
///
/// 민감 응답이면 생략 표시를, 아니면 응답 본문을 그대로 기록한다.
final class _LoggingRest implements RestClient {
  _LoggingRest(this.inner, this.log);

  final FakeRestClient inner;
  final MemoryLogSink log;

  @override
  Future<RestResponse> send(RestRequest request) async {
    final RestResponse response = await inner.send(request);
    _writeResponse(
      '${request.method} ${request.url}',
      request.isResponseSensitive,
      response,
    );
    return response;
  }

  @override
  Future<RestResponse> sendExternal(ExternalRequest request) async {
    final RestResponse response = await inner.sendExternal(request);
    _writeResponse(
      '${request.method} ${request.url}',
      request.isResponseSensitive,
      response,
    );
    return response;
  }

  /// 요청 줄과 (민감 응답이 아니면) 응답 본문을 기록한다.
  void _writeResponse(String target, bool isSensitive, RestResponse response) {
    log.write('rest', '$target → ${response.statusCode}');
    if (response.body.isEmpty) return;
    log.write(
      'rest',
      isSensitive ? HttpRestClient.sensitiveResponseNotice : response.body,
    );
  }
}

/// 가짜 사용자 하나 — [providerIds] 의 로그인 수단으로 가입했다.
Map<String, Object?> buildUser(
  String uid,
  String email,
  List<String> providerIds,
) => <String, Object?>{
  'localId': uid,
  'email': email,
  'emailVerified': true,
  'providerUserInfo': <Object?>[
    for (final String id in providerIds)
      <String, Object?>{'providerId': id, 'email': email, 'rawId': uid},
  ],
};

/// identity_index 문서가 생긴 기준 시각(가짜) — 로그인 시각은 이 값에서 더하고 뺀다.
final DateTime indexCreatedAt = DateTime.utc(2031, 5, 6, 7, 8, 9);

/// 기준 시각 [indexCreatedAt] 의 RFC 3339 표기 — 문서 `createTime` 값.
final String indexCreateTime = indexCreatedAt.toIso8601String();

/// 한 수단에서 로그인 기록을 싣는 문서 주인 수(문서 번호 0 부터).
const int ownerSlots = 3;

/// [provider] 의 [n] 번째 문서 주인 uid(실행 시점 조립 · 가짜).
String buildOwnerUid(String provider, int n) => 'owner-$provider-${'o' * 6}$n';

/// [time] 을 Auth 사용자 기록의 epoch ms 문자열로 바꾼다.
String toEpochMs(DateTime time) => time.millisecondsSinceEpoch.toString();

/// 문서 주인 [uid] 의 Auth 사용자 기록 — 마지막 로그인 시각은 [lastLoginAt].
///
/// [isCustomAuth] 가 false 면 `customAuth` 를 싣지 않는다(익명 사용자 모양).
/// 로그인 수단 정보는 비어 있다 — 실행 단계 · Google 개수에 영향이 없다.
Map<String, Object?> buildOwner(
  String uid, {
  required DateTime lastLoginAt,
  bool isCustomAuth = true,
}) => <String, Object?>{
  'localId': uid,
  if (isCustomAuth) 'customAuth': true,
  'lastLoginAt': toEpochMs(lastLoginAt),
  'createdAt': toEpochMs(indexCreatedAt.subtract(const Duration(minutes: 5))),
  'providerUserInfo': const <Object?>[],
};

/// 가짜 identity_index 문서 하나 — 마스크 덕에 provider · 주인 uid 필드만 실린다.
///
/// [ownerUid] 가 있으면 `firebaseUid` 필드를, [createTime] 이 있으면 문서
/// 메타데이터 `createTime` · `updateTime` 을 싣는다.
Map<String, Object?> buildIndexDocument(
  String docId,
  String provider, {
  String? ownerUid,
  String? createTime,
}) => <String, Object?>{
  'name':
      'projects/$projectId/databases/(default)/documents/identity_index/'
      '$docId',
  'fields': <String, Object?>{
    'provider': <String, Object?>{'stringValue': provider},
    if (ownerUid != null)
      'firebaseUid': <String, Object?>{'stringValue': ownerUid},
  },
  'createTime': ?createTime,
  'updateTime': ?createTime,
};

/// Google 사용자 [count] 명과 문서 주인들이 든 사용자 목록 한 페이지(마지막 페이지).
///
/// 문서 주인은 Kakao · Naver · LINE 마다 [ownerSlots] 명이고 모두 문서가 생긴
/// 뒤(기준 + 2초)에 Custom Token 으로 로그인했다.
RestResponse buildGoogleUsersPage(int count) => RestResponse(
  200,
  jsonEncode(<String, Object?>{
    'users': <Object?>[
      for (var i = 0; i < count; i++)
        buildUser(
          i == 0 ? fakeUid : '$fakeUid$i',
          i == 0 ? fakeEmail : 'signin-user-${i + 1}@example.invalid',
          const <String>['google.com'],
        ),
      for (final String provider in identityIndexProviders)
        for (var i = 0; i < ownerSlots; i++)
          buildOwner(
            buildOwnerUid(provider, i),
            lastLoginAt: indexCreatedAt.add(const Duration(seconds: 2)),
          ),
    ],
  }),
);

/// Kakao 0 번 문서 주인만 든 사용자 목록 — 주인 모양은 [buildOwner] 의 인자 그대로.
RestResponse buildKakaoOwnerPage({
  required DateTime lastLoginAt,
  bool isCustomAuth = true,
}) => RestResponse(
  200,
  jsonEncode(<String, Object?>{
    'users': <Object?>[
      buildOwner(
        buildOwnerUid('kakao', 0),
        lastLoginAt: lastLoginAt,
        isCustomAuth: isCustomAuth,
      ),
    ],
  }),
);

/// provider → 문서 수 [counts] 만큼 identity_index 문서가 든 한 페이지.
///
/// 문서마다 주인 uid([buildOwnerUid])와 기준 시각 `createTime` 을 싣는다.
RestResponse buildIndexPage(Map<String, int> counts, {String? nextPageToken}) =>
    RestResponse(
      200,
      jsonEncode(<String, Object?>{
        'documents': <Object?>[
          for (final MapEntry<String, int> entry in counts.entries)
            for (var i = 0; i < entry.value; i++)
              buildIndexDocument(
                buildDocId(entry.key, i),
                entry.key,
                ownerUid: buildOwnerUid(entry.key, i),
                createTime: indexCreateTime,
              ),
        ],
        'nextPageToken': ?nextPageToken,
      }),
    );

/// 문서가 없는 identity_index 한 페이지.
RestResponse buildEmptyIndexPage() => const RestResponse(200, '{}');

/// 로그인 확인 단계 한 번 실행에 쓰는 가짜 실행기 · REST · 화면 · 기록 묶음.
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

  /// 로그인 확인 뒤의 단계.
  final _PendingStep next = _PendingStep('next');

  /// 화면 출력 전체.
  String get output => screen.output.toString();

  /// 화면 출력의 줄 목록.
  List<String> get lines => const LineSplitter().convert(output);

  /// dev 문맥 — 키스토어가 없는 홈 · 기록을 남기는 REST 를 쓴다.
  late final WizardContext context = WizardContext(
    projectRoot: root,
    runner: runner,
    terminal: RedactingTerminal(screen, log.redactor, log),
    redactor: log.redactor,
    log: log,
    rest: _LoggingRest(rest, log),
    homeDirectory: noKeystoreTestHome,
    random: Random(fixedTestRandomSeed),
    now: () => fixedTestNow,
  );

  /// 사용자 목록 첫 페이지 주소.
  String get usersUrl => RunStep.buildBatchGetRequest(projectId).url.toString();

  /// 로그인 대조 identity_index 페이지 주소 — [pageToken] 이 있으면 그 페이지.
  String buildIndexUrl({String? pageToken}) => buildIdentityIndexRequest(
    projectId,
    pageToken: pageToken,
    basis: SignInBasis.signedIn,
  ).url.toString();

  /// 사용자 목록 첫 페이지의 응답 큐에 [responses] 를 더한다.
  void onUsers(List<RestResponse> responses) {
    for (final response in responses) {
      rest.on('GET', usersUrl, response);
    }
  }

  /// identity_index 페이지의 응답 큐에 [responses] 를 더한다.
  void onIndex(List<RestResponse> responses, {String? pageToken}) {
    for (final response in responses) {
      rest.on('GET', buildIndexUrl(pageToken: pageToken), response);
    }
  }

  /// 앱을 띄우기 전의 패키지 받기 · 코드 생성 명령을 성공으로 등록한다.
  void registerPrepareBuild() {
    runner
      ..on(pubGetKey, const CommandResult(0, '', ''))
      ..on(codegenKey, const CommandResult(0, '', ''));
  }

  /// 다시 실행할 때의 준비 명령 · 기기 목록(시뮬레이터 하나) · 실행 명령을
  /// 등록한다.
  void registerLaunch() {
    registerPrepareBuild();
    runner
      ..on(
        FakeCommandRunner.buildKey(RunStep.buildDevicesCommand()),
        CommandResult(
          0,
          jsonEncode(<Object?>[
            <String, Object?>{
              'name': 'iPhone 17',
              'id': simulatorId,
              'isSupported': true,
              'targetPlatform': 'ios',
              'emulator': true,
              'sdk': 'sdk',
              'capabilities': <String, Object?>{'hotReload': true},
            },
          ]),
          '',
        ),
      )
      ..on(runKey, const CommandResult(0, '', ''));
  }

  /// 실행 단계(끝남) · 로그인 확인 · ([withNext] 면) 뒤 단계로 위저드를 돌린다.
  ///
  /// [launcher] 를 주면 로그인 확인이 그 실행 단계로 앱을 다시 띄운다.
  Future<int> run(
    Set<String> providers, {
    bool withNext = true,
    RunStep? launcher,
  }) => runWizard(context, <Step>[
    _FinishedStep('run', RunStep.stepTitle),
    SignInCheckStep(enabledProviders: providers, launcher: launcher),
    if (withNext) next,
  ]);

  /// 대화형 실행 명령 호출 수.
  int get launchCount => runner.countCalls(RunMode.interactive, runKey);

  /// 앞 단계(끝남) · 실제 실행 단계 · 로그인 확인으로 위저드를 돌린다.
  ///
  /// 로그인 확인은 목록의 실행 단계와 다른 [RunStep] 으로 앱을 다시 띄운다 —
  /// 실제 단계 목록과 같은 모양이다.
  Future<int> runWithRunStep(Set<String> providers) =>
      runWizard(context, <Step>[
        _FinishedStep('configure', '앱 등록 · 설정 파일'),
        _FinishedStep('sign_in', '로그인 수단 (이메일 · 익명)'),
        _FinishedStep('rules', 'Firestore · Storage rules'),
        _FinishedStep('app_check', 'App Check 디버그 토큰'),
        _FinishedStep('functions', 'Cloud Functions 배포'),
        RunStep(delay: (Duration duration) async {}),
        SignInCheckStep(
          enabledProviders: providers,
          launcher: RunStep(delay: (Duration duration) async {}),
        ),
      ]);
}

/// 인증된 이메일 사용자 1명과([hasGoogle] 면) Google 사용자 1명이 든 사용자 목록.
RestResponse buildPasswordUsersPage({required bool hasGoogle}) => RestResponse(
  200,
  jsonEncode(<String, Object?>{
    'users': <Object?>[
      buildUser(fakeUid, fakeEmail, const <String>['password']),
      if (hasGoogle)
        buildUser(
          '${fakeUid}g',
          'signin-user-g@example.invalid',
          const <String>['google.com'],
        ),
    ],
  }),
);

/// [text] 안에 [needle] 이 나온 횟수.
int countText(String text, String needle) => needle.allMatches(text).length;

void main() {
  late Directory tempDir;
  late String root;
  late String configPath;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('sign_in_check_test_');
    root = tempDir.path;
    configPath = '$root/${UserFilesStep.jsonUserPath}';
    File(configPath)
      ..parent.createSync(recursive: true)
      ..writeAsStringSync(
        '${jsonEncode(<String, Object?>{'firebaseProjectId': projectId, 'enabledAuthProviders': ''})}\n',
      );
  });

  tearDown(() {
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  test('T-20-SIGNIN-01: 켠 수단마다 1명 이상이면 표 순서로 개수만 보이는 ✓ · '
      '질문 0', () async {
    final harness = _Harness(root, const <String?>[]);
    harness
      ..onUsers(<RestResponse>[buildGoogleUsersPage(1)])
      ..onIndex(<RestResponse>[
        buildIndexPage(const <String, int>{'kakao': 2}),
      ]);

    final int code = await harness.run(const <String>{
      'kakao',
      'google',
    }, withNext: false);

    expect(code, wizardExitDone, reason: harness.output);
    expect(harness.lines, contains('  ✓ 소셜 로그인 확인 — Google 1명 · Kakao 2명'));
    expect(harness.screen.asks, isEmpty);
    expect(harness.launchCount, 0);
    for (final text in <String>[harness.output, harness.log.text]) {
      expect(countText(text, fakeEmail), 0);
      expect(countText(text, fakeUid), 0);
      expect(countText(text, buildDocId('kakao', 0)), 0);
    }
  });

  group('T-20-SIGNIN-02: 기록 없는 수단이 있으면', () {
    test('T-20-SIGNIN-02: ✗ 사유에 그 수단만 · 고르기 3 선택지', () async {
      final harness = _Harness(root, const <String?>[]);
      harness
        ..onUsers(<RestResponse>[buildGoogleUsersPage(1)])
        ..onIndex(<RestResponse>[buildEmptyIndexPage()]);

      final int code = await harness.run(const <String>{
        'google',
        'kakao',
        'line',
      });

      expect(code, wizardExitStopped, reason: harness.output);
      expect(
        harness.lines,
        contains('  ✗ 소셜 로그인 확인 — 아직 로그인 기록이 없습니다: Kakao · LINE'),
      );
      expect(harness.output, isNot(contains('Google 1명')));
      expect(harness.screen.asks, <String>[failureChoiceQuestion]);
      expect(harness.output, contains('$failureChoiceQuestion\n$choiceLines'));
      expect(harness.launchCount, 0);
    });

    test('T-20-SIGNIN-02: 미룰 수 있는 단계 · 라벨 · 실행 단계 뒤', () {
      final step = SignInCheckStep(enabledProviders: const <String>{'kakao'});

      expect(step, isA<DeferrableStep>());
      expect(step.id, 'sign_in_check');
      expect(step.title, SignInCheckStep.stepTitle);
      expect(SignInCheckStep.stepTitle, '소셜 로그인 확인');
      expect(step.dependsOn, <String>['run']);
      expect(step.proceedLabel, '앱을 다시 실행');
      expect(step.deferLabel, '나중에');
      expect(step.isCostlyOrIrreversible, isFalse);
      expect(step.enabledProviders, <String>{'kakao'});
    });
  });

  test('T-20-SIGNIN-03: 나중에 → ✗ 나중에 · 뒤 단계 진행 · 끝 목록 · 종료 0 · '
      '저장 0', () async {
    final String configBefore = File(configPath).readAsStringSync();
    final harness = _Harness(root, const <String?>['2', 'y']);
    harness
      ..onUsers(<RestResponse>[buildGoogleUsersPage(1)])
      ..onIndex(<RestResponse>[buildEmptyIndexPage()]);

    final int code = await harness.run(const <String>{
      'google',
      'kakao',
      'line',
    });
    final List<String> lines = harness.lines;

    expect(code, wizardExitDone, reason: harness.output);
    const deferredLine = '  ✗ 소셜 로그인 확인 — 나중에';
    expect(lines, contains(deferredLine));
    expect(harness.next.applyCount, 1);
    final int remaining = lines.indexOf(remainingHeading);
    expect(remaining, greaterThan(lines.indexOf(deferredLine)));
    expect(lines.skip(remaining + 1), contains(deferredLine));
    expect(harness.launchCount, 0);
    expect(
      harness.rest.requests.where((RestRequest r) => r.method != 'GET'),
      isEmpty,
    );
    expect(File(configPath).readAsStringSync(), configBefore);
    expect(harness.output, isNot(contains('  실패 — ')));
  });

  test('T-20-SIGNIN-04: 앱을 다시 실행 → 남은 수단 안내 · interactive 1회 · '
      '다시 센 뒤 ✓', () async {
    final harness = _Harness(root, const <String?>['1', '', 'y']);
    harness
      ..onUsers(<RestResponse>[buildGoogleUsersPage(1)])
      ..onIndex(<RestResponse>[
        buildEmptyIndexPage(),
        buildEmptyIndexPage(),
        buildIndexPage(const <String, int>{'kakao': 1, 'line': 1}),
      ])
      ..registerLaunch();

    final int code = await harness.run(const <String>{
      'google',
      'kakao',
      'line',
    });
    final List<String> lines = harness.lines;

    expect(code, wizardExitDone, reason: harness.output);
    expect(lines, contains('  Kakao · LINE 로 로그인한 뒤 q 로 끝내세요'));
    expect(harness.launchCount, 1);
    expect(harness.screen.asks, contains(RunStep.targetChoiceQuestion));
    expect(lines, contains('  ✓ 소셜 로그인 확인 — Google 1명 · Kakao 1명 · LINE 1명'));
    expect(harness.rest.countRequests('GET', harness.buildIndexUrl()), 4);
    expect(harness.runner.countMode(RunMode.stream), 2);
    expect(
      <String>[
        for (final FakeCall call in harness.runner.calls)
          if (call.mode == RunMode.stream) call.key,
      ],
      <String>[pubGetKey, codegenKey],
    );
    expect(harness.output, isNot(contains('  실패 — ')));
    expect(harness.output, isNot(contains(RunStep.quitLine)));
    expect(harness.next.applyCount, 1);
  });

  test('T-20-SIGNIN-05: 집계 실패(403) → ✗ 사유에 상태 · 진행하면 실패 원문 · '
      '이메일 · 문서 ID 두 버퍼 0회', () async {
    const pageToken = 'next-page-token-1';
    final harness = _Harness(root, const <String?>['1']);
    harness
      ..onUsers(<RestResponse>[buildGoogleUsersPage(1)])
      ..onIndex(<RestResponse>[
        buildIndexPage(const <String, int>{
          'kakao': 1,
        }, nextPageToken: pageToken),
      ])
      ..onIndex(<RestResponse>[
        const RestResponse(
          403,
          '{"error":{"code":403,"status":"PERMISSION_DENIED"}}',
        ),
      ], pageToken: pageToken);

    final int code = await harness.run(const <String>{'google', 'kakao'});
    final List<String> lines = harness.lines;

    expect(code, wizardExitStopped, reason: harness.output);
    expect(
      lines.where(
        (String line) =>
            line.startsWith('  ✗ 소셜 로그인 확인 — ') && line.contains('HTTP 403'),
      ),
      isNotEmpty,
    );
    expect(
      lines.where((String line) => line.startsWith('  실패 — ')),
      isNotEmpty,
    );
    expect(harness.output, contains('PERMISSION_DENIED'));
    expect(harness.launchCount, 0);
    for (final text in <String>[harness.output, harness.log.text]) {
      expect(countText(text, fakeEmail), 0);
      expect(countText(text, fakeUid), 0);
      expect(countText(text, buildDocId('kakao', 0)), 0);
    }
  });

  group('T-20-SIGNIN-06: 단계 목록', () {
    test('T-20-SIGNIN-06: 수단을 켜면 실행 단계 바로 다음에 로그인 확인', () {
      final List<Step> steps = buildSteps(
        flavor: Flavor.dev,
        enabledProviders: const <String>{'google', 'kakao'},
      );
      final ids = <String>[for (final Step step in steps) step.id];

      expect(ids.indexOf('sign_in_check'), ids.indexOf('run') + 1);
      final SignInCheckStep check = steps.whereType<SignInCheckStep>().single;
      expect(check.enabledProviders, <String>{'google', 'kakao'});
      expect(check.dependsOn, <String>['run']);
      expect(check, isA<DeferrableStep>());
      expect(check.proceedLabel, '앱을 다시 실행');
      expect(check.deferLabel, '나중에');
    });

    test('T-20-SIGNIN-06: 수단을 켜지 않으면 로그인 확인이 없다', () {
      final List<Step> steps = buildSteps(
        flavor: Flavor.dev,
        enabledProviders: const <String>{},
      );

      expect(
        steps.map((Step step) => step.id),
        isNot(contains('sign_in_check')),
      );
    });

    test('T-20-SIGNIN-06: 다시 실행 계획 줄 — 앱 실행 줄 · 다시 세는 요청 표시형', () async {
      final harness = _Harness(root, const <String?>[]);
      harness
        ..onUsers(<RestResponse>[buildGoogleUsersPage(1)])
        ..onIndex(<RestResponse>[buildEmptyIndexPage()]);
      final step = SignInCheckStep(
        enabledProviders: const <String>{'google', 'kakao'},
      );

      expect(await step.check(harness.context), isA<Todo>());
      final List<String> lines = step.plannedCommandLines(harness.context);
      const runLine =
          'fvm flutter run --flavor dev --dart-define-from-file=config/dev.json '
          '-d <고른 기기>';

      expect(
        lines,
        containsAllInOrder(<String>[
          'fvm flutter pub get',
          'fvm dart run build_runner build --delete-conflicting-outputs',
          'fvm flutter devices --machine',
          runLine,
          RunStep.buildBatchGetRequest(projectId).displayCurl(),
          buildIdentityIndexRequest(
            projectId,
            basis: SignInBasis.signedIn,
          ).displayCurl(),
        ]),
      );
    });
  });

  group('T-20-SIGNIN-07: 다시 실행 뒤에도 기록이 없으면 단계 안에서 다시 묻는다', () {
    test('T-20-SIGNIN-07: 나중에 → ✗ 나중에 · 실패 줄 0 · 다시 시도 0 · 종료 0', () async {
      final harness = _Harness(root, const <String?>['1', '', '2', 'y']);
      harness
        ..onUsers(<RestResponse>[buildGoogleUsersPage(1)])
        ..onIndex(<RestResponse>[buildEmptyIndexPage()])
        ..registerLaunch();

      final int code = await harness.run(const <String>{
        'google',
        'kakao',
        'line',
      });
      final List<String> lines = harness.lines;

      expect(code, wizardExitDone, reason: harness.output);
      expect(harness.launchCount, 1);
      expect(lines, contains('  아직 로그인 기록이 없습니다: Kakao · LINE'));
      expect(
        harness.screen.asks.where((String ask) => ask == failureChoiceQuestion),
        hasLength(2),
      );
      expect(
        countText(harness.output, '$failureChoiceQuestion\n$choiceLines'),
        2,
      );
      const deferredLine = '  ✗ 소셜 로그인 확인 — 나중에';
      expect(lines, contains(deferredLine));
      expect(harness.next.applyCount, 1);
      final int remaining = lines.indexOf(remainingHeading);
      expect(lines.skip(remaining + 1), contains(deferredLine));
      expect(harness.output, isNot(contains('  실패 — ')));
      expect(harness.output, isNot(contains(retryOption)));
    });

    test(
      'T-20-SIGNIN-07: 한 번 더 다시 실행 → 남은 수단만 안내 · interactive 2회 · ✓',
      () async {
        final harness = _Harness(root, const <String?>['1', '', '1', '', 'y']);
        harness
          ..onUsers(<RestResponse>[buildGoogleUsersPage(1)])
          ..onIndex(<RestResponse>[
            buildEmptyIndexPage(),
            buildEmptyIndexPage(),
            buildIndexPage(const <String, int>{'kakao': 1}),
            buildIndexPage(const <String, int>{'kakao': 1, 'line': 2}),
          ])
          ..registerLaunch();

        final int code = await harness.run(const <String>{
          'google',
          'kakao',
          'line',
        });
        final List<String> lines = harness.lines;

        expect(code, wizardExitDone, reason: harness.output);
        expect(harness.launchCount, 2);
        expect(lines, contains('  Kakao · LINE 로 로그인한 뒤 q 로 끝내세요'));
        expect(lines, contains('  아직 로그인 기록이 없습니다: LINE'));
        expect(lines, contains('  LINE 로 로그인한 뒤 q 로 끝내세요'));
        expect(
          lines,
          contains('  ✓ 소셜 로그인 확인 — Google 1명 · Kakao 1명 · LINE 2명'),
        );
        expect(harness.output, isNot(contains('  실패 — ')));
        expect(harness.next.applyCount, 1);
      },
    );
  });

  test('T-20-SIGNIN-08: 주입한 실행 단계의 대기를 쓴다 — 대상이 없으면 시뮬레이터를 '
      '켜고 실제로 기다리지 않고 정한 횟수만 다시 찾은 뒤 실패', () async {
    final developerDir = '$root/Xcode.app/Contents/Developer';
    final deviceHub = '$root/Xcode.app/Contents/Applications/DeviceHub.app';
    Directory(deviceHub).createSync(recursive: true);
    const simulatorUdid = '1A2B3C4D-5E6F-4A7B-8C9D-0E1F2A3B4C5D';
    final delays = <Duration>[];
    final harness = _Harness(root, const <String?>['1']);
    harness
      ..onUsers(<RestResponse>[const RestResponse(200, '{}')])
      ..onIndex(<RestResponse>[buildEmptyIndexPage()])
      ..registerPrepareBuild()
      ..runner.on(
        FakeCommandRunner.buildKey(RunStep.buildDevicesCommand()),
        const CommandResult(0, '[]', ''),
      )
      ..runner.on(
        FakeCommandRunner.buildKey(RunStep.simulatorListCommand),
        CommandResult(
          0,
          jsonEncode(<String, Object?>{
            'devices': <String, Object?>{
              'com.apple.CoreSimulator.SimRuntime.iOS-26-4': <Object?>[
                <String, Object?>{
                  'deviceTypeIdentifier':
                      'com.apple.CoreSimulator.SimDeviceType.iPhone-17',
                  'isAvailable': true,
                  'name': 'Sim iPhone A',
                  'state': 'Shutdown',
                  'udid': simulatorUdid,
                },
              ],
            },
          }),
          '',
        ),
      )
      ..runner.on(
        FakeCommandRunner.buildKey(RunStep.developerDirCommand),
        CommandResult(0, '$developerDir\n', ''),
      )
      ..runner.on(
        FakeCommandRunner.buildKey(
          RunStep.buildBootSimulatorCommand(simulatorUdid),
        ),
        const CommandResult(0, '', ''),
      )
      ..runner.on(
        FakeCommandRunner.buildKey(
          RunStep.buildOpenScreenAppCommand(deviceHub),
        ),
        const CommandResult(0, '', ''),
      );

    final int code = await harness.run(
      const <String>{'kakao'},
      launcher: RunStep(
        delay: (Duration duration) async {
          delays.add(duration);
        },
      ),
    );

    expect(code, wizardExitStopped, reason: harness.output);
    expect(delays, hasLength(RunStep.maxLaunchPolls));
    expect(harness.output, contains('  실패 — ${RunStep.noTargetSummary}'));
    expect(harness.launchCount, 0);
  });

  group('T-20-SIGNIN-09: 문서는 있지만 주인의 로그인 기록이 없으면 ✗', () {
    /// Kakao 를 켜고 위저드를 돌려 ✗ 줄 · 고르기 3 선택지를 본다.
    Future<void> expectNoKakaoRecord(_Harness harness) async {
      final int code = await harness.run(const <String>{'kakao'});

      expect(code, wizardExitStopped, reason: harness.output);
      expect(harness.lines, contains('  ✗ 소셜 로그인 확인 — 아직 로그인 기록이 없습니다: Kakao'));
      expect(harness.output, isNot(contains('Kakao 1명')));
      expect(harness.screen.asks, <String>[failureChoiceQuestion]);
      expect(harness.output, contains('$failureChoiceQuestion\n$choiceLines'));
      expect(harness.launchCount, 0);
    }

    test('T-20-SIGNIN-09: 주인 = 익명 사용자 모양(Custom Token 로그인 없음 · '
        '로그인 시각이 문서보다 앞섬) → ✗ Kakao · 고르기 3 선택지', () async {
      final harness = _Harness(root, const <String?>[]);
      harness
        ..onUsers(<RestResponse>[
          buildKakaoOwnerPage(
            lastLoginAt: indexCreatedAt.subtract(const Duration(seconds: 60)),
            isCustomAuth: false,
          ),
        ])
        ..onIndex(<RestResponse>[
          buildIndexPage(const <String, int>{'kakao': 1}),
        ]);

      await expectNoKakaoRecord(harness);
    });

    test('T-20-SIGNIN-09: 주인이 사용자 목록에 없음 → ✗ Kakao', () async {
      final harness = _Harness(root, const <String?>[]);
      harness
        ..onUsers(<RestResponse>[const RestResponse(200, '{}')])
        ..onIndex(<RestResponse>[
          buildIndexPage(const <String, int>{'kakao': 1}),
        ]);

      await expectNoKakaoRecord(harness);
    });
  });

  test('T-20-SIGNIN-10: 같은 문서의 주인에게 문서 뒤 Custom Token 로그인 기록이 '
      '있으면 ✓ Kakao 1명 · 질문 0', () async {
    final harness = _Harness(root, const <String?>[]);
    harness
      ..onUsers(<RestResponse>[
        buildKakaoOwnerPage(
          lastLoginAt: indexCreatedAt.add(const Duration(seconds: 2)),
        ),
      ])
      ..onIndex(<RestResponse>[
        buildIndexPage(const <String, int>{'kakao': 1}),
      ]);

    final int code = await harness.run(const <String>{
      'kakao',
    }, withNext: false);

    expect(code, wizardExitDone, reason: harness.output);
    expect(harness.lines, contains('  ✓ 소셜 로그인 확인 — Kakao 1명'));
    expect(harness.screen.asks, isEmpty);
    expect(harness.launchCount, 0);
  });

  group('T-20-SIGNIN-11: 로그인 대조 값은 화면 · 기록에 나오지 않는다', () {
    /// 두 버퍼에 주인 uid · 문서 ID · 문서 시각 · 로그인 시각 원문이 0회이고
    /// 요청이 모두 민감 응답인지 본다.
    void expectNoComparedValues(_Harness harness, DateTime lastLoginAt) {
      final values = <String>[
        buildOwnerUid('kakao', 0),
        buildDocId('kakao', 0),
        indexCreateTime,
        toEpochMs(lastLoginAt),
      ];
      for (final text in <String>[harness.output, harness.log.text]) {
        for (final value in values) {
          expect(countText(text, value), 0, reason: value);
        }
      }
      expect(
        harness.rest.countRequests('GET', harness.usersUrl),
        greaterThan(0),
      );
      expect(
        harness.rest.countRequests('GET', harness.buildIndexUrl()),
        greaterThan(0),
      );
      expect(
        harness.rest.requests.every((RestRequest r) => r.isResponseSensitive),
        isTrue,
      );
      expect(
        countText(harness.log.text, HttpRestClient.sensitiveResponseNotice),
        harness.rest.requests.length,
      );
    }

    test('T-20-SIGNIN-11: ✓ 줄은 수단 이름과 개수만', () async {
      final DateTime lastLoginAt = indexCreatedAt.add(
        const Duration(seconds: 2),
      );
      final harness = _Harness(root, const <String?>[]);
      harness
        ..onUsers(<RestResponse>[buildKakaoOwnerPage(lastLoginAt: lastLoginAt)])
        ..onIndex(<RestResponse>[
          buildIndexPage(const <String, int>{'kakao': 1}),
        ]);

      final int code = await harness.run(const <String>{
        'kakao',
      }, withNext: false);

      expect(code, wizardExitDone, reason: harness.output);
      expect(harness.lines, contains('  ✓ 소셜 로그인 확인 — Kakao 1명'));
      expectNoComparedValues(harness, lastLoginAt);
    });

    test('T-20-SIGNIN-11: Kakao 만 켜도 relaunch 계획 줄에 사용자 목록 · 로그인 대조 '
        'identity_index 표시형 · 비교 값 0회', () async {
      final DateTime lastLoginAt = indexCreatedAt.subtract(
        const Duration(seconds: 60),
      );
      final harness = _Harness(root, const <String?>[]);
      harness
        ..onUsers(<RestResponse>[
          buildKakaoOwnerPage(lastLoginAt: lastLoginAt, isCustomAuth: false),
        ])
        ..onIndex(<RestResponse>[
          buildIndexPage(const <String, int>{'kakao': 1}),
        ]);
      final String usersLine = RunStep.buildBatchGetRequest(
        projectId,
      ).displayCurl();
      final String signedInIndexLine = buildIdentityIndexRequest(
        projectId,
        basis: SignInBasis.signedIn,
      ).displayCurl();
      final String registeredIndexLine = buildIdentityIndexRequest(
        projectId,
      ).displayCurl();

      final int code = await harness.run(const <String>{'kakao'});

      expect(code, wizardExitStopped, reason: harness.output);
      expect(
        harness.lines,
        containsAllInOrder(<String>[
          '  \$ $usersLine',
          '  \$ $signedInIndexLine',
        ]),
      );
      expect(harness.output, isNot(contains(registeredIndexLine)));
      expectNoComparedValues(harness, lastLoginAt);
    });
  });

  test('T-20-SIGNIN-12: 생성 파일 없는 저장소에서 다시 실행 → 패키지 받기 → '
      '코드 생성 → 기기 목록 → 앱 실행 순 · 준비는 저장소 루트에서 · 다시 센 뒤 ✓', () async {
    // 새 clone 모양 — config 만 있고 패키지 설정 · 생성 파일이 없다.
    expect(Directory('$root/.dart_tool').existsSync(), isFalse);
    expect(Directory('$root/lib').existsSync(), isFalse);
    final harness = _Harness(root, const <String?>['1', '', 'y']);
    harness
      ..onUsers(<RestResponse>[buildGoogleUsersPage(1)])
      ..onIndex(<RestResponse>[
        buildEmptyIndexPage(),
        buildEmptyIndexPage(),
        buildIndexPage(const <String, int>{'kakao': 1}),
      ])
      ..registerLaunch();

    final int code = await harness.run(const <String>{'kakao'});
    final List<FakeCall> calls = harness.runner.calls;

    expect(code, wizardExitDone, reason: harness.output);
    expect(
      <(RunMode, String)>[
        for (final FakeCall call in calls) (call.mode, call.key),
      ],
      <(RunMode, String)>[
        (RunMode.stream, pubGetKey),
        (RunMode.stream, codegenKey),
        (RunMode.capture, devicesKey),
        (RunMode.interactive, runKey),
      ],
    );
    expect(calls[0].workingDirectory, root);
    expect(calls[1].workingDirectory, root);
    expect(harness.lines, contains('  ✓ 소셜 로그인 확인 — Kakao 1명'));
    expect(harness.output, isNot(contains('  실패 — ')));
    expect(harness.next.applyCount, 1);
  });

  group('T-20-SIGNIN-13: 다시 실행 준비가 실패하면 앱을 띄우지 않고 멈춤이 기본값', () {
    /// 준비 명령 결과를 [registerPreparation] 으로 등록하고 기록 없는 Kakao 로
    /// 다시 실행을 고른 뒤, 실패 질문에 빈 입력을 준다.
    ///
    /// 빈 입력 뒤의 `1`(다시 시도)은 실패 질문에 기본값이 없을 때만 쓰인다 —
    /// 기본값이 멈춤이면 쓰이지 않고 위저드가 멈춘다.
    Future<_Harness> runFailedPreparation(
      void Function(FakeCommandRunner runner) registerPreparation,
    ) async {
      final harness = _Harness(root, const <String?>['1', '', '1']);
      harness
        ..onUsers(<RestResponse>[buildGoogleUsersPage(1)])
        ..onIndex(<RestResponse>[buildEmptyIndexPage()]);
      registerPreparation(harness.runner);
      expect(
        await harness.run(const <String>{'kakao'}),
        wizardExitStopped,
        reason: harness.output,
      );
      return harness;
    }

    /// 실패 질문이 다시 시도 · 멈춤 두 선택지로 나왔는지 본다.
    void expectRetryOrStopQuestion(_Harness harness) {
      expect(
        harness.output,
        contains(
          '$failureChoiceQuestion\n  1) $retryOption\n  2) $stopOption\n',
        ),
      );
      expect(harness.next.applyCount, 0);
    }

    test('T-20-SIGNIN-13: 코드 생성 종료 코드 1 → 실패 문장 · 출력 원문 · '
        '앱 실행 0 · 빈 입력이면 멈춤', () async {
      final _Harness harness = await runFailedPreparation(
        (FakeCommandRunner runner) => runner
          ..on(pubGetKey, const CommandResult(0, '', ''))
          ..on(codegenKey, const CommandResult(1, '', 'build_runner failed\n')),
      );

      expect(harness.lines, contains('  실패 — 코드 생성이 실패했습니다'));
      expect(harness.output, contains('build_runner failed'));
      expect(harness.runner.countCalls(RunMode.stream, pubGetKey), 1);
      expect(harness.runner.countCalls(RunMode.stream, codegenKey), 1);
      expect(harness.runner.countCalls(RunMode.capture, devicesKey), 0);
      expect(harness.launchCount, 0);
      expectRetryOrStopQuestion(harness);
    });

    test('T-20-SIGNIN-13: 패키지 받기 실패 → 실패 문장 · 코드 생성 0 · '
        '앱 실행 0 · 빈 입력이면 멈춤', () async {
      final _Harness harness = await runFailedPreparation(
        (FakeCommandRunner runner) => runner.on(
          pubGetKey,
          const CommandResult(1, '', 'pub get failed\n'),
        ),
      );

      expect(harness.lines, contains('  실패 — 패키지를 받지 못했습니다'));
      expect(harness.output, contains('pub get failed'));
      expect(harness.runner.countCalls(RunMode.stream, pubGetKey), 1);
      expect(harness.runner.countCalls(RunMode.stream, codegenKey), 0);
      expect(harness.runner.countCalls(RunMode.capture, devicesKey), 0);
      expect(harness.launchCount, 0);
      expectRetryOrStopQuestion(harness);
    });
  });

  test('T-20-SIGNIN-14: 다시 실행 → 기록 없음 → 다시 실행 → ✓ 의 한 번 실행에서 '
      '패키지 받기 · 코드 생성 각 1회 · 앱 실행 2회', () async {
    final harness = _Harness(root, const <String?>['1', '', '1', '', 'y']);
    harness
      ..onUsers(<RestResponse>[buildGoogleUsersPage(1)])
      ..onIndex(<RestResponse>[
        buildEmptyIndexPage(),
        buildEmptyIndexPage(),
        buildEmptyIndexPage(),
        buildIndexPage(const <String, int>{'kakao': 1}),
      ])
      ..registerLaunch();

    final int code = await harness.run(const <String>{'kakao'});

    expect(code, wizardExitDone, reason: harness.output);
    expect(harness.runner.countCalls(RunMode.stream, pubGetKey), 1);
    expect(harness.runner.countCalls(RunMode.stream, codegenKey), 1);
    expect(harness.launchCount, 2);
    expect(harness.lines, contains('  아직 로그인 기록이 없습니다: Kakao'));
    expect(harness.lines, contains('  ✓ 소셜 로그인 확인 — Kakao 1명'));
  });

  group('T-21-SIGNIN-01: 준비를 마친 실행의 다시 실행', () {
    test('T-21-SIGNIN-01: 준비를 마친 세션이면 앱을 다시 실행해도 패키지 받기 · '
        '코드 생성 0 · 실행 1 · 계획 줄은 안내 한 줄', () async {
      final harness = _Harness(root, const <String?>['1', '']);
      harness.context.session.isAppBuildPrepared = true;
      harness
        ..onUsers(<RestResponse>[
          buildGoogleUsersPage(0),
          buildGoogleUsersPage(0),
          buildGoogleUsersPage(1),
        ])
        ..registerLaunch();

      final int code = await harness.run(const <String>{
        'google',
      }, withNext: false);

      expect(code, wizardExitDone, reason: harness.output);
      expect(harness.runner.countCalls(RunMode.stream, pubGetKey), 0);
      expect(harness.runner.countCalls(RunMode.stream, codegenKey), 0);
      expect(harness.launchCount, 1);
      expect(harness.output, contains('    ${RunStep.preparedPlanNote}\n'));
      expect(harness.output, isNot(contains(r'  $ fvm flutter pub get')));
      expect(harness.lines, contains('  ✓ 소셜 로그인 확인 — Google 1명'));
    });

    test('T-21-SIGNIN-01: 새 세션이면 지금처럼 준비 각 1회 뒤 준비를 마친 것으로 '
        '남긴다', () async {
      final harness = _Harness(root, const <String?>['1', '']);
      harness
        ..onUsers(<RestResponse>[
          buildGoogleUsersPage(0),
          buildGoogleUsersPage(0),
          buildGoogleUsersPage(1),
        ])
        ..registerLaunch();

      final int code = await harness.run(const <String>{
        'google',
      }, withNext: false);

      expect(code, wizardExitDone, reason: harness.output);
      expect(harness.runner.countCalls(RunMode.stream, pubGetKey), 1);
      expect(harness.runner.countCalls(RunMode.stream, codegenKey), 1);
      expect(harness.launchCount, 1);
      expect(harness.output, contains('  \$ fvm flutter pub get\n'));
      expect(harness.context.session.isAppBuildPrepared, isTrue);
    });
  });

  group('T-21-SIGNIN-02: 실행 단계가 다시 빌드한 실행의 소셜 로그인 확인', () {
    setUp(() {
      File(configPath).writeAsStringSync(
        '${jsonEncode(<String, Object?>{'firebaseProjectId': projectId, 'enabledAuthProviders': 'google'})}\n',
      );
    });

    /// 다시 빌드 안내 줄이 모두 화면에 있고 켠 수단 · 다음 단계를 말하는지 본다.
    void expectRebuildGuide(_Harness harness) {
      final List<String> guide = RunStep.buildRebuildGuideLines(
        harness.context,
      );
      expect(guide.first, contains('이메일 + Google'));
      expect(guide[1], contains('「소셜 로그인 확인」'));
      for (final line in guide) {
        expect(harness.output, contains('$line\n'));
      }
    }

    test('T-21-SIGNIN-02: 다시 빌드한 실행에서 로그인하면 소셜 로그인 확인은 세기만 하고 ✓ · '
        '준비 각 1회 · 실행 1회 · 다시 실행 질문 0', () async {
      // 실행 단계 진행 y → 기기 기본값.
      final harness = _Harness(root, const <String?>['y', '']);
      harness.context.session.hasRegisteredAppCheckToken = true;
      harness
        ..onUsers(<RestResponse>[
          buildPasswordUsersPage(hasGoogle: false),
          buildPasswordUsersPage(hasGoogle: false),
          buildPasswordUsersPage(hasGoogle: true),
        ])
        ..registerLaunch();

      final int code = await harness.runWithRunStep(const <String>{'google'});

      expect(code, wizardExitDone, reason: harness.output);
      expect(
        harness.output,
        contains(
          '  ${RunStep.rebuildReasonPrefix}${RunStep.appCheckTokenReason}\n',
        ),
      );
      expectRebuildGuide(harness);
      expect(harness.runner.countCalls(RunMode.stream, pubGetKey), 1);
      expect(harness.runner.countCalls(RunMode.stream, codegenKey), 1);
      expect(harness.launchCount, 1);
      expect(harness.output, isNot(contains(choiceLines)));
      expect(harness.lines, contains('  ✓ 소셜 로그인 확인 — Google 1명'));
    });

    test('T-21-SIGNIN-02: 기록이 아직 없으면 진행 · 미루기 · 멈춤을 묻고 앱을 다시 실행 → '
        '✓ · 준비 각 1회 · 실행 2회', () async {
      // 실행 단계 진행 y → 기기 기본값 → 앱을 다시 실행 → 기기 기본값.
      final harness = _Harness(root, const <String?>['y', '', '1', '']);
      harness.context.session.hasRegisteredAppCheckToken = true;
      harness
        ..onUsers(<RestResponse>[
          buildPasswordUsersPage(hasGoogle: false),
          buildPasswordUsersPage(hasGoogle: false),
          buildPasswordUsersPage(hasGoogle: false),
          buildPasswordUsersPage(hasGoogle: false),
          buildPasswordUsersPage(hasGoogle: true),
        ])
        ..registerLaunch();

      final int code = await harness.runWithRunStep(const <String>{'google'});

      expect(code, wizardExitDone, reason: harness.output);
      expectRebuildGuide(harness);
      expect(harness.output, contains(choiceLines));
      expect(harness.runner.countCalls(RunMode.stream, pubGetKey), 1);
      expect(harness.runner.countCalls(RunMode.stream, codegenKey), 1);
      expect(harness.launchCount, 2);
      expect(harness.lines, contains('  ✓ 소셜 로그인 확인 — Google 1명'));
    });
  });
}
