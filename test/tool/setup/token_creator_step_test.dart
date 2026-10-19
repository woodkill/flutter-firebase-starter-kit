import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:test/test.dart';

import '../../../tool/setup/command_runner.dart';
import '../../../tool/setup/config_files.dart';
import '../../../tool/setup/flavor.dart';
import '../../../tool/setup/providers/provider_catalog.dart';
import '../../../tool/setup/redactor.dart';
import '../../../tool/setup/step.dart';
import '../../../tool/setup/steps/firestore_step.dart';
import '../../../tool/setup/steps/flavor_steps.dart';
import '../../../tool/setup/steps/functions_step.dart';
import '../../../tool/setup/steps/token_creator_step.dart';
import '../../../tool/setup/steps/user_files_step.dart';
import '../../../tool/setup/terminal.dart';
import '../../../tool/setup/wizard.dart';
import 'fake_rest_client.dart';
import 'fakes.dart';

/// 테스트 프로젝트 ID(가짜).
const String projectId = 'demo-p';

/// stg 테스트 프로젝트 ID(가짜).
const String stgProjectId = 'demo-s';

/// 공통 함수 목록(가짜 함수 목록 파일).
const List<String> commonFunctions = <String>['ping'];

/// Custom Token 수단별 함수 — 저장소 함수 목록 파일의 그 세 항목과 같은 이름.
const Map<String, List<String>> providerFunctions = <String, List<String>>{
  'kakao': <String>[
    'kakaoCustomToken',
    'linkKakaoProvider',
    'disconnectKakaoProvider',
  ],
  'naver': <String>[
    'naverCustomToken',
    'naverWebCustomToken',
    'linkNaverProvider',
    'disconnectNaverProvider',
  ],
  'line': <String>[
    'lineCustomToken',
    'linkLineProvider',
    'disconnectLineProvider',
  ],
};

/// 성공 결과를 만든다.
CommandResult ok([String stdout = '']) => CommandResult(0, stdout, '');

/// [functionId] 의 Cloud Run 서비스 이름(가짜 — 소문자).
String buildServiceId(String functionId) => functionId.toLowerCase();

/// [digit] 을 12번 이은 프로젝트 번호의 기본 Compute 서비스 계정(가짜)을 만든다.
String buildFakeServiceAccount(String digit) =>
    '${digit * 12}-compute@developer.gserviceaccount.com';

/// [project] 에 배포된 함수 목록을 읽는 명령 키.
String buildFunctionsListKey(String project) => FakeCommandRunner.buildKey(
  FunctionsStep.buildFunctionsListCommand(project),
);

/// IAM 바인딩 하나를 만든다 — [condition] 이 있으면 조건을 붙인다.
Map<String, Object?> buildBinding(
  String role,
  List<String> members, {
  Map<String, Object?>? condition,
}) => <String, Object?>{
  'role': role,
  'members': members,
  'condition': ?condition,
};

/// [bindings] 를 담은 서비스 계정 IAM 정책 결과를 만든다.
CommandResult buildPolicyResult(List<Map<String, Object?>> bindings) =>
    ok(jsonEncode(<String, Object?>{'bindings': bindings, 'etag': 'BwYfake'}));

/// [account] 자신을 구성원으로 한 조건 없는 Token Creator 바인딩이 든 정책 결과.
CommandResult buildBoundPolicy(String account) =>
    buildPolicyResult(<Map<String, Object?>>[
      buildBinding(TokenCreatorStep.tokenCreatorRole, <String>[
        TokenCreatorStep.buildMember(account),
      ]),
    ]);

/// 바인딩이 없는 서비스 계정 IAM 정책 결과.
CommandResult buildEmptyPolicy() =>
    ok(jsonEncode(<String, Object?>{'etag': 'BwYfake'}));

/// 부여 명령 성공 결과.
CommandResult buildGrantOk(String account) =>
    ok('Updated IAM policy for serviceAccount [$account].\n');

/// [text] 에서 [needle] 이 나온 횟수를 센다.
int countText(String text, String needle) => needle.allMatches(text).length;

/// 이미 끝난 앞 단계 — 서명 권한 단계의 의존 단계를 대신한다.
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

/// 가짜 실행기에 넘기면서 흘리는 실행(stream)의 명령 줄과 출력을 실제 실행기처럼
/// 화면에 쓰는 실행기.
final class _EchoingRunner implements CommandRunner {
  _EchoingRunner(this.inner, this.terminal);

  /// 결과를 돌려주는 가짜 실행기.
  final FakeCommandRunner inner;

  /// 흘리는 출력을 쓸 화면.
  final Terminal terminal;

  @override
  Future<CommandResult> capture(Command command) => inner.capture(command);

  @override
  Future<int> interactive(Command command) => inner.interactive(command);

  @override
  Future<CommandResult> stream(Command command) async {
    terminal.writeCommand(command.render());
    final CommandResult result = await inner.stream(command);
    for (final text in <String>[result.stdout, result.stderr]) {
      if (text.isEmpty) continue;
      terminal.writeRaw(text.endsWith('\n') ? text : '$text\n');
    }
    return CommandResult(
      result.exitCode,
      result.stdout,
      result.stderr,
      isOutputShown: true,
    );
  }
}

/// 위저드 한 번 실행에 쓰는 가짜 실행기 · 화면 · 기록 묶음.
final class _Harness {
  _Harness(this.root, List<String?> inputs)
    : fake = FakeCommandRunner(),
      screen = ScriptedTerminal(inputs),
      log = MemoryLogSink(Redactor()) {
    terminal = RedactingTerminal(screen, log.redactor, log);
    runner = _EchoingRunner(fake, terminal);
  }

  final String root;
  final FakeCommandRunner fake;
  final ScriptedTerminal screen;
  final MemoryLogSink log;
  late final RedactingTerminal terminal;
  late final _EchoingRunner runner;

  /// 화면 출력 전체.
  String get output => screen.output.toString();

  /// 화면 출력의 줄 목록.
  List<String> get lines => const LineSplitter().convert(output);

  /// [command] 의 결과 큐에 [result] 를 더한다.
  void onCommand(Command command, CommandResult result) =>
      fake.on(FakeCommandRunner.buildKey(command), result);

  /// [command] 가 [mode] 로 불린 횟수를 센다.
  int count(RunMode mode, Command command) =>
      fake.countCalls(mode, FakeCommandRunner.buildKey(command));

  /// 호출 키 가운데 프로젝트 수준 명령(`gcloud projects …`)의 수를 센다.
  int countProjectLevelCalls() => fake.calls
      .where((FakeCall call) => call.key.startsWith('gcloud projects '))
      .length;

  /// 공통 함수와 [tokens] 수단의 함수가 [project] 에 배포된 목록을 등록한다.
  void registerDeployed(
    Set<String> tokens, {
    String project = projectId,
    required String region,
  }) {
    fake.on(
      buildFunctionsListKey(project),
      ok(
        jsonEncode(<String, Object?>{
          'status': 'success',
          'result': <Object?>[
            for (final String id in <String>[
              ...commonFunctions,
              for (final String token in tokens) ...?providerFunctions[token],
            ])
              <String, Object?>{
                'id': id,
                'project': project,
                'region': region,
                'platform': 'gcfv2',
                'runServiceId': buildServiceId(id),
              },
          ],
        }),
      ),
    );
  }

  /// [token] 수단 함수의 서비스마다 런타임 서비스 계정 [account] 를 등록한다.
  void registerAccount(
    String token,
    String account, {
    String project = projectId,
    required String region,
  }) {
    for (final String function in providerFunctions[token]!) {
      onCommand(
        TokenCreatorStep.buildServiceAccountCommand(
          buildServiceId(function),
          region,
          project,
        ),
        ok('$account\n'),
      );
    }
  }

  /// 함수 단계(끝남) 뒤에 [enabledProviders] 를 켠 서명 권한 단계로 위저드를
  /// [flavor] 문맥에서 돌린다.
  Future<int> run(Set<String> enabledProviders, {Flavor flavor = Flavor.dev}) =>
      runWizard(
        WizardContext(
          projectRoot: root,
          runner: runner,
          terminal: terminal,
          redactor: log.redactor,
          log: log,
          rest: FakeRestClient(),
          flavor: flavor,
          homeDirectory: noKeystoreTestHome,
          random: Random(fixedTestRandomSeed),
          now: () => fixedTestNow,
        ),
        <Step>[
          _FinishedStep('functions', FunctionsStep.stepTitle),
          TokenCreatorStep(enabledProviders: enabledProviders),
        ],
      );
}

void main() {
  late Directory tempDir;
  late String root;
  late String region;

  setUpAll(() {
    region = readJsonString(
      UserFilesStep.jsonExamplePath,
      FirestoreStep.functionsRegionKey,
    )!;
  });

  /// 저장소 상대 경로에 내용을 쓴다(부모 디렉터리를 만든다).
  void writeFixture(String relativePath, String content) {
    File('$root/$relativePath')
      ..parent.createSync(recursive: true)
      ..writeAsStringSync(content);
  }

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('token_creator_step_test_');
    root = tempDir.path;
    final config = File('$root/${UserFilesStep.jsonUserPath}')
      ..parent.createSync(recursive: true);
    File(UserFilesStep.jsonExamplePath).copySync(config.path);
    replaceJsonString(config.path, 'firebaseProjectId', projectId);
    writeFixture(
      FunctionsStep.manifestPath,
      '${jsonEncode(<String, Object?>{FunctionsStep.manifestCommonKey: commonFunctions, FunctionsStep.manifestProvidersKey: providerFunctions})}\n',
    );
  });

  tearDown(() {
    tempDir.deleteSync(recursive: true);
  });

  test('T-20-TC-01: 런타임 서비스 계정에 Token Creator 가 없으면 ✗ · 계획 줄의 부여 '
      '명령 · y 뒤 한 번 붙이고 재검사 ✓', () async {
    final String account = buildFakeServiceAccount('1');
    final h = _Harness(root, const <String?>['y']);
    h
      ..registerDeployed(const <String>{'kakao'}, region: region)
      ..registerAccount('kakao', account, region: region);
    final Command policy = TokenCreatorStep.buildPolicyCommand(
      account,
      projectId,
    );
    final Command grant = TokenCreatorStep.buildGrantCommand(
      account,
      projectId,
    );
    h
      ..onCommand(policy, buildEmptyPolicy())
      ..onCommand(policy, buildEmptyPolicy())
      ..onCommand(policy, buildBoundPolicy(account))
      ..onCommand(grant, buildGrantOk(account));

    final int code = await h.run(const <String>{'kakao'});

    expect(code, wizardExitDone, reason: h.output);
    expect(
      h.lines,
      contains(
        '  ✗ ${TokenCreatorStep.stepTitle} — ${TokenCreatorStep.stepTitle}'
        '(Token Creator)이 없는 함수 런타임 서비스 계정이 있습니다 (1개)',
      ),
    );
    expect(h.lines, contains('▶ ${TokenCreatorStep.stepTitle}'));
    expect(grant.render(), contains('--condition=None'));
    expect(countText(h.output, '  \$ ${grant.render()}'), 2);
    expect(h.count(RunMode.stream, grant), 1);
    for (final String function in providerFunctions['kakao']!) {
      expect(
        h.count(
          RunMode.capture,
          TokenCreatorStep.buildServiceAccountCommand(
            buildServiceId(function),
            region,
            projectId,
          ),
        ),
        3,
        reason: function,
      );
    }
    expect(h.count(RunMode.capture, policy), 3);
    final int granted = h.lines.lastIndexOf('  \$ ${grant.render()}');
    final int done = h.lines.indexOf(
      '  ✓ ${TokenCreatorStep.stepTitle} — 함수 런타임 서비스 계정 1개 · '
      'Token Creator 있음',
    );
    expect(done, greaterThan(granted));
    expect(h.countProjectLevelCalls(), 0);
  });

  group('T-20-TC-02: 단계 목록 — Custom Token 수단을 켰을 때만 Functions 바로 뒤', () {
    for (final token in <String>['kakao', 'naver', 'line']) {
      test('$token 을 켜면 functions 다음 · run 앞 · 의존 functions', () {
        final List<Step> steps = buildSteps(
          flavor: Flavor.dev,
          enabledProviders: <String>{token},
        );
        final ids = <String>[for (final Step step in steps) step.id];
        final int index = ids.indexOf(TokenCreatorStep.stepId);
        expect(index, ids.indexOf('functions') + 1);
        expect(ids[index + 1], 'run');
        final Step step = steps[index];
        expect(step.dependsOn, <String>['functions']);
        expect(step.isCostlyOrIrreversible, isFalse);
        expect(step.title, TokenCreatorStep.stepTitle);
      });
    }

    for (final tokens in <Set<String>>[
      const <String>{},
      const <String>{'google', 'apple', 'facebook'},
    ]) {
      test('${tokens.isEmpty ? '로그인 수단 0' : tokens.join(' · ')} 이면 없음', () {
        final ids = <String>[
          for (final Step step in buildSteps(
            flavor: Flavor.dev,
            enabledProviders: tokens,
          ))
            step.id,
        ];
        expect(ids, isNot(contains(TokenCreatorStep.stepId)));
        expect(TokenCreatorStep.isRequiredFor(tokens), isFalse);
      });
    }
  });

  /// [account] 의 정책 응답 [policies] 를 등록 순서대로 더한다.
  void registerPolicies(
    _Harness h,
    String account,
    List<CommandResult> policies, {
    String project = projectId,
  }) {
    for (final policy in policies) {
      h.onCommand(
        TokenCreatorStep.buildPolicyCommand(account, project),
        policy,
      );
    }
  }

  /// 부여 명령(어느 계정이든)이 불린 횟수를 센다.
  int countGrantCalls(_Harness h) => h.fake.calls
      .where(
        (FakeCall call) => call.key.startsWith(
          'gcloud iam service-accounts add-iam-policy-binding ',
        ),
      )
      .length;

  test('T-20-TC-03: 바인딩이 이미 있으면 점검표부터 ✓ · 질문 · 부여 · 흘려 실행 0', () async {
    final String account = buildFakeServiceAccount('1');
    final h = _Harness(root, const <String?>[]);
    h
      ..registerDeployed(const <String>{'kakao'}, region: region)
      ..registerAccount('kakao', account, region: region);
    registerPolicies(h, account, <CommandResult>[buildBoundPolicy(account)]);

    final int code = await h.run(const <String>{'kakao'});

    expect(code, wizardExitDone, reason: h.output);
    expect(
      h.lines,
      contains(
        '  ✓ ${TokenCreatorStep.stepTitle} — 함수 런타임 서비스 계정 1개 · '
        'Token Creator 있음',
      ),
    );
    expect(h.screen.asks, isEmpty);
    expect(countGrantCalls(h), 0);
    expect(h.fake.countMode(RunMode.stream), 0);
  });

  group('T-20-TC-04: 계정마다 한 번 · 빠진 계정에만 · stg 프로젝트', () {
    test('세 수단의 서비스가 한 계정이면 정책 읽기 · 부여가 검사마다 한 번', () async {
      final String account = buildFakeServiceAccount('1');
      final h = _Harness(root, const <String?>['y']);
      h.registerDeployed(const <String>{
        'kakao',
        'naver',
        'line',
      }, region: region);
      for (final token in providerFunctions.keys) {
        h.registerAccount(token, account, region: region);
      }
      registerPolicies(h, account, <CommandResult>[
        buildEmptyPolicy(),
        buildEmptyPolicy(),
        buildBoundPolicy(account),
      ]);
      final Command grant = TokenCreatorStep.buildGrantCommand(
        account,
        projectId,
      );
      h.onCommand(grant, buildGrantOk(account));

      final int code = await h.run(const <String>{'kakao', 'naver', 'line'});

      expect(code, wizardExitDone, reason: h.output);
      for (final List<String> functions in providerFunctions.values) {
        for (final function in functions) {
          expect(
            h.count(
              RunMode.capture,
              TokenCreatorStep.buildServiceAccountCommand(
                buildServiceId(function),
                region,
                projectId,
              ),
            ),
            3,
            reason: function,
          );
        }
      }
      expect(
        h.count(
          RunMode.capture,
          TokenCreatorStep.buildPolicyCommand(account, projectId),
        ),
        3,
      );
      expect(h.count(RunMode.stream, grant), 1);
      expect(countGrantCalls(h), 1);
    });

    test('서비스 하나만 다른 계정이고 그 계정만 빠지면 그 계정에만 붙인다', () async {
      final String shared = buildFakeServiceAccount('1');
      final String other = buildFakeServiceAccount('2');
      final h = _Harness(root, const <String?>['y']);
      h
        ..registerDeployed(const <String>{'kakao', 'line'}, region: region)
        ..registerAccount('kakao', shared, region: region);
      final List<String> lineFunctions = providerFunctions['line']!;
      for (final function in lineFunctions) {
        h.onCommand(
          TokenCreatorStep.buildServiceAccountCommand(
            buildServiceId(function),
            region,
            projectId,
          ),
          ok('${function == lineFunctions.first ? other : shared}\n'),
        );
      }
      registerPolicies(h, shared, <CommandResult>[buildBoundPolicy(shared)]);
      registerPolicies(h, other, <CommandResult>[
        buildEmptyPolicy(),
        buildEmptyPolicy(),
        buildBoundPolicy(other),
      ]);
      final Command grant = TokenCreatorStep.buildGrantCommand(
        other,
        projectId,
      );
      h.onCommand(grant, buildGrantOk(other));

      final int code = await h.run(const <String>{'kakao', 'line'});

      expect(code, wizardExitDone, reason: h.output);
      expect(
        h.lines,
        contains(
          '  ✗ ${TokenCreatorStep.stepTitle} — ${TokenCreatorStep.stepTitle}'
          '(Token Creator)이 없는 함수 런타임 서비스 계정이 있습니다 (1개)',
        ),
      );
      expect(h.count(RunMode.stream, grant), 1);
      expect(countGrantCalls(h), 1);
      expect(
        h.lines,
        contains(
          '  ✓ ${TokenCreatorStep.stepTitle} — 함수 런타임 서비스 계정 2개 · '
          'Token Creator 있음',
        ),
      );
    });

    test('stg 문맥이면 모든 명령이 stg 프로젝트 ID 를 쓴다', () async {
      const paths = FlavorPaths(Flavor.stg);
      final config = File('$root/${paths.json}')
        ..parent.createSync(recursive: true);
      File(paths.jsonExample).copySync(config.path);
      replaceJsonString(config.path, 'firebaseProjectId', stgProjectId);
      final String stgRegion = readJsonString(
        paths.jsonExample,
        FirestoreStep.functionsRegionKey,
      )!;
      final String account = buildFakeServiceAccount('3');
      final h = _Harness(root, const <String?>['y']);
      h
        ..registerDeployed(
          const <String>{'kakao'},
          project: stgProjectId,
          region: stgRegion,
        )
        ..registerAccount(
          'kakao',
          account,
          project: stgProjectId,
          region: stgRegion,
        );
      registerPolicies(h, account, project: stgProjectId, <CommandResult>[
        buildEmptyPolicy(),
        buildEmptyPolicy(),
        buildBoundPolicy(account),
      ]);
      final Command grant = TokenCreatorStep.buildGrantCommand(
        account,
        stgProjectId,
      );
      h.onCommand(grant, buildGrantOk(account));

      final int code = await h.run(const <String>{'kakao'}, flavor: Flavor.stg);

      expect(code, wizardExitDone, reason: h.output);
      expect(h.count(RunMode.stream, grant), 1);
      expect(h.fake.calls, isNotEmpty);
      for (final FakeCall call in h.fake.calls) {
        expect(call.key, contains('--project $stgProjectId'), reason: call.key);
        expect(call.key, isNot(contains(projectId)), reason: call.key);
      }
    });
  });

  group('T-20-TC-05: 바인딩 모양 — 역할 · 그 계정 자신 · 조건 없음 셋 다', () {
    final String account = buildFakeServiceAccount('1');
    final String stranger = buildFakeServiceAccount('2');
    final cases =
        <({String label, Map<String, Object?> binding, bool isPresent})>[
          (
            label: '구성원이 다른 서비스 계정뿐',
            binding: buildBinding(TokenCreatorStep.tokenCreatorRole, <String>[
              TokenCreatorStep.buildMember(stranger),
            ]),
            isPresent: false,
          ),
          (
            label: '같은 계정이지만 조건이 붙음',
            binding: buildBinding(
              TokenCreatorStep.tokenCreatorRole,
              <String>[TokenCreatorStep.buildMember(account)],
              condition: <String, Object?>{
                'title': 'temporary',
                'expression':
                    'request.time < timestamp("2100-01-01T00:00:00Z")',
              },
            ),
            isPresent: false,
          ),
          (
            label: '같은 계정 · 다른 역할',
            binding: buildBinding('roles/iam.serviceAccountUser', <String>[
              TokenCreatorStep.buildMember(account),
            ]),
            isPresent: false,
          ),
          (
            label: '같은 바인딩에 다른 구성원과 그 계정이 함께 있음',
            binding: buildBinding(TokenCreatorStep.tokenCreatorRole, <String>[
              TokenCreatorStep.buildMember(stranger),
              TokenCreatorStep.buildMember(account),
            ]),
            isPresent: true,
          ),
        ];

    for (final shape in cases) {
      test(
        '${shape.label} → ${shape.isPresent ? '있음 · 부여 0' : '없음 · 부여'}',
        () async {
          final CommandResult policy = buildPolicyResult(<Map<String, Object?>>[
            shape.binding,
          ]);
          expect(
            TokenCreatorStep.hasSelfTokenCreator(policy, account),
            shape.isPresent,
          );
          final h = _Harness(root, <String?>[if (!shape.isPresent) 'y']);
          h
            ..registerDeployed(const <String>{'kakao'}, region: region)
            ..registerAccount('kakao', account, region: region);
          registerPolicies(h, account, <CommandResult>[
            policy,
            if (!shape.isPresent) ...<CommandResult>[
              policy,
              buildBoundPolicy(account),
            ],
          ]);
          final Command grant = TokenCreatorStep.buildGrantCommand(
            account,
            projectId,
          );
          h.onCommand(grant, buildGrantOk(account));

          final int code = await h.run(const <String>{'kakao'});

          expect(code, wizardExitDone, reason: h.output);
          expect(h.count(RunMode.stream, grant), shape.isPresent ? 0 : 1);
          expect(h.countProjectLevelCalls(), 0);
        },
      );
    }
  });

  group('T-20-TC-06: 읽기 실패 — 사유의 ✗ · 원문 · 부여 0', () {
    final String account = buildFakeServiceAccount('1');
    final String firstService = buildServiceId(
      providerFunctions['kakao']!.first,
    );
    final String failureText = <String>['ERROR:', ' fake read failure'].join();

    /// 실패 갈래 하나를 돌려 화면 출력을 돌려준다.
    Future<String> runFailure(
      void Function(_Harness h) register,
      String reason, {
      bool isRawShown = false,
    }) async {
      final h = _Harness(root, const <String?>['y']);
      register(h);

      final int code = await h.run(const <String>{'kakao'});

      expect(code, wizardExitStopped, reason: h.output);
      expect(h.lines, contains('  ✗ ${TokenCreatorStep.stepTitle} — $reason'));
      final int failed = h.lines.indexOf('  실패 — $reason');
      expect(failed, greaterThanOrEqualTo(0), reason: h.output);
      if (isRawShown) {
        expect(
          h.lines
              .skip(failed + 1)
              .any((String line) => line.contains(failureText)),
          isTrue,
          reason: h.output,
        );
      }
      expect(countGrantCalls(h), 0);
      return h.output;
    }

    test('서비스 계정 읽기 실패(종료 코드 1) → 원문', () async {
      await runFailure(
        (_Harness h) {
          h.registerDeployed(const <String>{'kakao'}, region: region);
          h.onCommand(
            TokenCreatorStep.buildServiceAccountCommand(
              firstService,
              region,
              projectId,
            ),
            CommandResult(1, '', '$failureText\n'),
          );
        },
        '$firstService 서비스의 런타임 서비스 계정을 읽지 못했습니다',
        isRawShown: true,
      );
    });

    test('서비스 계정 읽기 빈 출력', () async {
      await runFailure((_Harness h) {
        h.registerDeployed(const <String>{'kakao'}, region: region);
        h.onCommand(
          TokenCreatorStep.buildServiceAccountCommand(
            firstService,
            region,
            projectId,
          ),
          ok('\n'),
        );
      }, '$firstService 서비스의 런타임 서비스 계정을 읽지 못했습니다');
    });

    test('정책 읽기 실패(종료 코드 1) → 원문', () async {
      await runFailure(
        (_Harness h) {
          h
            ..registerDeployed(const <String>{'kakao'}, region: region)
            ..registerAccount('kakao', account, region: region);
          registerPolicies(h, account, <CommandResult>[
            CommandResult(1, '', '$failureText\n'),
          ]);
        },
        '서비스 계정 $account 의 IAM 정책을 읽지 못했습니다',
        isRawShown: true,
      );
    });

    test('정책이 JSON 이 아님 → 원문', () async {
      await runFailure(
        (_Harness h) {
          h
            ..registerDeployed(const <String>{'kakao'}, region: region)
            ..registerAccount('kakao', account, region: region);
          registerPolicies(h, account, <CommandResult>[ok('$failureText\n')]);
        },
        '서비스 계정 $account 의 IAM 정책을 읽지 못했습니다',
        isRawShown: true,
      );
    });

    test('함수 목록에 켠 수단의 함수가 없음', () async {
      await runFailure((_Harness h) {
        h.registerDeployed(const <String>{}, region: region);
      }, '배포된 함수 목록에 ${providerFunctions['kakao']!.first} 함수가 없습니다');
    });

    test('config 의 리전 키가 비어 있음', () async {
      replaceJsonString(
        '$root/${UserFilesStep.jsonUserPath}',
        FirestoreStep.functionsRegionKey,
        '',
      );
      await runFailure(
        (_Harness h) {},
        '${UserFilesStep.jsonUserPath} 에서 Functions '
        '리전(${FirestoreStep.functionsRegionKey})을 읽지 못했습니다',
      );
    });
  });

  test(
    'T-20-TC-07: 부여가 거절되면 흘린 원문 뒤 할 일 · 남은 계정 부여 0 · 프로젝트 수준 0 · 멈춤',
    () async {
      final String first = buildFakeServiceAccount('1');
      final String second = buildFakeServiceAccount('2');
      final List<String> kakaoFunctions = providerFunctions['kakao']!;
      final h = _Harness(root, const <String?>['y']);
      h.registerDeployed(const <String>{'kakao'}, region: region);
      for (final function in kakaoFunctions) {
        h.onCommand(
          TokenCreatorStep.buildServiceAccountCommand(
            buildServiceId(function),
            region,
            projectId,
          ),
          ok('${function == kakaoFunctions.first ? first : second}\n'),
        );
      }
      registerPolicies(h, first, <CommandResult>[buildEmptyPolicy()]);
      registerPolicies(h, second, <CommandResult>[buildEmptyPolicy()]);
      final String rejection = <String>[
        'fake rejection:',
        ' the caller may not change this policy',
      ].join();
      final Command firstGrant = TokenCreatorStep.buildGrantCommand(
        first,
        projectId,
      );
      final Command secondGrant = TokenCreatorStep.buildGrantCommand(
        second,
        projectId,
      );
      h
        ..onCommand(firstGrant, CommandResult(1, '', '$rejection\n'))
        ..onCommand(secondGrant, buildGrantOk(second));

      final int code = await h.run(const <String>{'kakao'});

      expect(code, wizardExitStopped, reason: h.output);
      expect(countText(h.output, rejection), 1);
      final int raw = h.lines.indexOf(rejection);
      final int failed = h.lines.indexWhere(
        (String line) => line.startsWith(
          '  실패 — 함수 런타임 서비스 계정에 Token Creator 를 붙이지 못했습니다 '
          '(종료 코드 1) — ${TokenCreatorStep.grantFailureGuidance}',
        ),
      );
      expect(raw, greaterThanOrEqualTo(0), reason: h.output);
      expect(failed, greaterThan(raw), reason: h.output);
      expect(h.count(RunMode.stream, firstGrant), 1);
      expect(h.count(RunMode.stream, secondGrant), 0);
      expect(h.countProjectLevelCalls(), 0);
      expect(h.lines.last, stopLine);
    },
  );

  group('T-20-TC-08: 부여 뒤 반영 대기 안내', () {
    test('부여가 모두 성공하면 켠 수단 이름을 넣은 안내 줄이 한 번', () async {
      final String account = buildFakeServiceAccount('1');
      final h = _Harness(root, const <String?>['y']);
      h.registerDeployed(const <String>{'kakao', 'line'}, region: region);
      for (final token in <String>['kakao', 'line']) {
        h.registerAccount(token, account, region: region);
      }
      registerPolicies(h, account, <CommandResult>[
        buildEmptyPolicy(),
        buildEmptyPolicy(),
        buildBoundPolicy(account),
      ]);
      h.onCommand(
        TokenCreatorStep.buildGrantCommand(account, projectId),
        buildGrantOk(account),
      );

      final int code = await h.run(const <String>{'line', 'kakao'});

      expect(code, wizardExitDone, reason: h.output);
      final String notice = TokenCreatorStep.buildPropagationNotice(<String>[
        'Kakao',
        'LINE',
      ]);
      expect(notice, contains('Kakao · LINE'));
      expect(countText(h.output, notice), 1);
    });

    test('이미 있으면 안내 줄 0', () async {
      final String account = buildFakeServiceAccount('1');
      final h = _Harness(root, const <String?>[]);
      h
        ..registerDeployed(const <String>{'kakao'}, region: region)
        ..registerAccount('kakao', account, region: region);
      registerPolicies(h, account, <CommandResult>[buildBoundPolicy(account)]);

      final int code = await h.run(const <String>{'kakao'});

      expect(code, wizardExitDone, reason: h.output);
      expect(
        countText(
          h.output,
          TokenCreatorStep.buildPropagationNotice(<String>['Kakao']),
        ),
        0,
      );
    });
  });

  test('T-20-TC-09: 매뉴얼 「켜기」 ⑦ 의 명령 줄이 위저드 명령과 같고 거절 안내가 그 단계를 가리킨다', () async {
    const manualPath = 'docs/manual.md';
    const account = '<service-account-email>';
    const project = '<your-project-id>';
    final List<String> manual = File(manualPath).readAsLinesSync();
    final int start = manual.indexOf(providersManualHeading);
    expect(start, greaterThanOrEqualTo(0));
    final int next = manual.indexWhere(
      (String line) => line.startsWith('## '),
      start + 1,
    );
    final List<String> section = manual.sublist(
      start,
      next < 0 ? manual.length : next,
    );
    int countLines(bool Function(String line) isMatch) =>
        section.where(isMatch).length;

    expect(countLines((String line) => line.startsWith('**⑦ ')), 1);
    expect(countLines((String line) => line.startsWith('**⑧ ')), 1);
    final int seventh = section.indexWhere(
      (String line) => line.startsWith('**⑦ '),
    );
    final int eighth = section.indexWhere(
      (String line) => line.startsWith('**⑧ '),
    );
    expect(eighth, greaterThan(seventh));
    final String paragraph = section.sublist(seventh, eighth).join('\n');
    expect(paragraph, contains(TokenCreatorStep.tokenCreatorRole));
    expect(paragraph, contains('--condition=None'));
    final String policyKey = FakeCommandRunner.buildKey(
      TokenCreatorStep.buildPolicyCommand(account, project),
    );
    final String grantKey = FakeCommandRunner.buildKey(
      TokenCreatorStep.buildGrantCommand(account, project),
    );
    final String describeKey = FakeCommandRunner.buildKey(
      TokenCreatorStep.buildServiceAccountCommand(
        'kakaocustomtoken',
        region,
        project,
      ),
    );
    expect(countLines((String line) => line == policyKey), 1);
    expect(countLines((String line) => line == grantKey), 1);
    expect(
      countLines((String line) => line.replaceAll("'", '') == describeKey),
      1,
    );

    final String target = buildFakeServiceAccount('1');
    final h = _Harness(root, const <String?>['y']);
    h
      ..registerDeployed(const <String>{'kakao'}, region: region)
      ..registerAccount('kakao', target, region: region);
    registerPolicies(h, target, <CommandResult>[buildEmptyPolicy()]);
    h.onCommand(
      TokenCreatorStep.buildGrantCommand(target, projectId),
      const CommandResult(1, '', 'denied\n'),
    );

    final int code = await h.run(const <String>{'kakao'});

    expect(code, wizardExitStopped, reason: h.output);
    final String failure = h.lines.singleWhere(
      (String line) => line.startsWith('  실패 — '),
    );
    expect(failure, contains('「켜기」 ⑦'));
    expect(failure, contains('로그인 수단 켜고 끄기'));
  });
}
