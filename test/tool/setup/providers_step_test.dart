import 'dart:io';

import 'package:test/test.dart';

import '../../../tool/setup/config_files.dart';
import '../../../tool/setup/providers/provider_catalog.dart';
import '../../../tool/setup/providers/provider_selection.dart';
import '../../../tool/setup/step.dart';
import '../../../tool/setup/steps/providers_step.dart';
import '../../../tool/setup/steps/user_files_step.dart';
import '../../../tool/setup/wizard.dart';
import 'fakes.dart';

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
  _Harness(this.root, List<String?> inputs, {bool isRequested = false})
    : screen = ScriptedTerminal(inputs) {
    context = buildTestContext(projectRoot: root, terminal: screen);
    context.session.isProviderSelectionRequested = isRequested;
  }

  final String root;
  final ScriptedTerminal screen;
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
}

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
  });

  tearDown(() {
    tempDir.deleteSync(recursive: true);
  });

  /// config 의 로그인 수단 CSV.
  String? readCsv() => readJsonString(configPath, enabledProvidersKey);

  test('T-20-PROV-01: 체크 목록에 0 이면 CSV 를 빈 문자열로 쓰고 단계 목록을 다시 짠다 · '
      '다른 config 바이트는 그대로', () async {
    replaceJsonString(configPath, enabledProvidersKey, 'google,kakao');
    final String before = File(configPath).readAsStringSync();
    final h = _Harness(root, const <String?>['y', '0', 'y'], isRequested: true);

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
}
