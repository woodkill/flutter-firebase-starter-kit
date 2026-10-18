import 'dart:io';
import 'dart:math';

import 'package:test/test.dart';

import '../../../tool/setup/providers/apple_key_input.dart';
import '../../../tool/setup/redactor.dart';
import '../../../tool/setup/step.dart';
import '../../../tool/setup/steps/apns_step.dart';
import '../../../tool/setup/terminal.dart';
import '../../../tool/setup/wizard.dart';
import 'fake_rest_client.dart';
import 'fakes.dart';

/// 가짜 Key ID(실행 시점 조립).
final String keyId = 'K' * 10;

/// 가짜 Team ID(실행 시점 조립).
final String teamId = 'T' * 10;

/// 가짜 `.p8` 본문 줄.
final String bodyLine = '${'Ap' * 30}Qz00';

/// 가짜 `.p8` 내용.
final String pemContent = '$pemPrivateKeyHeader\n$bodyLine\n';

/// APNs 점검표 줄.
const String apnsLine = '  ? APNs 키 — 콘솔 업로드(확인은 실기기 알림)';

/// 한 번의 위저드 실행.
final class _Harness {
  _Harness(this.root, List<String?> inputs, {WizardSession? session})
    : screen = ScriptedTerminal(inputs),
      session = session ?? WizardSession();

  final String root;
  final ScriptedTerminal screen;
  final WizardSession session;
  final FakeCommandRunner runner = FakeCommandRunner();
  final FakeRestClient rest = FakeRestClient();
  final MemoryLogSink log = MemoryLogSink(Redactor());

  /// 화면 출력 전체.
  String get output => screen.output.toString();

  /// 끝 목록 머리 뒤의 줄들.
  List<String> get remainingLines {
    final List<String> lines = output.split('\n');
    final int start = lines.indexOf(remainingHeading);
    if (start < 0) return const <String>[];
    return lines.sublist(start + 1).where((String l) => l.isNotEmpty).toList();
  }

  /// APNs 단계 하나로 위저드를 돌린다.
  Future<int> run() => runWizard(
    WizardContext(
      projectRoot: root,
      runner: runner,
      terminal: RedactingTerminal(screen, log.redactor, log),
      redactor: log.redactor,
      log: log,
      rest: rest,
      session: session,
      homeDirectory: noKeystoreTestHome,
      random: Random(fixedTestRandomSeed),
      now: () => fixedTestNow,
    ),
    <Step>[ApnsStep()],
  );
}

/// 같은 실행에서 DeviceCheck 키를 넣은 세션.
WizardSession buildEnteredSession() => WizardSession()
  ..appleKeys[AppleKeyUse.deviceCheck] = AppleKey(
    keyId: keyId,
    privateKey: pemContent,
  )
  ..appleTeamId = teamId
  ..hasEnteredDeviceCheckKey = true;

/// [dir] 아래 파일 경로 목록.
List<String> listFiles(Directory dir) => dir
    .listSync(recursive: true)
    .whereType<File>()
    .map((File file) => file.path)
    .toList();

void main() {
  late Directory tempDir;
  late String root;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('apns_step_test_');
    root = tempDir.path;
  });

  tearDown(() {
    tempDir.deleteSync(recursive: true);
  });

  test('T-20-APNS-01: 세션 플래그 false → ? 줄 · 질문 0 · 끝 목록 1줄', () async {
    final h = _Harness(root, const <String?>[]);

    final int code = await h.run();

    expect(code, wizardExitDone);
    expect(h.output, startsWith('$checklistHeading\n$apnsLine\n'));
    expect(h.screen.asks, isEmpty);
    expect(h.remainingLines, <String>[apnsLine]);
    expect(h.output, isNot(contains(allDoneLine)));
    expect(h.output, isNot(contains('  ✓ ')));
  });

  test('T-20-APNS-02: 같은 실행에서 DeviceCheck 키를 넣음 → 할 일 · 1 → 값 표 · '
      'Enter → ? 줄 · ✓ 0 · 쓰기 0', () async {
    final h = _Harness(root, const <String?>[
      '1',
      '',
    ], session: buildEnteredSession());

    final int code = await h.run();

    expect(code, wizardExitDone);
    expect(h.output, contains('  ✗ ${ApnsStep.stepTitle} — '));
    expect(h.output, contains('  1) 업로드 안내 보기\n  2) 지금 안 함\n  3) 멈춤'));
    expect(h.output, contains('Key ID $keyId 의 .p8'));
    expect(h.output, contains('  Key ID'));
    expect(h.output, contains(keyId));
    expect(h.output, contains(teamId));
    expect(h.output, contains(ApnsStep.uploadTodoLine));
    expect(h.output, contains('FCM 알림'));
    expect(ApnsStep.manualHeading, '### FCM 알림');
    expect(h.output, isNot(contains('Cloud Messaging')));
    expect(h.session.isApnsGuideShown, isTrue);
    expect(h.remainingLines, <String>[apnsLine]);
    expect(h.output, isNot(contains('  ✓ ')));
    expect(h.output, isNot(contains(pemPrivateKeyHeader)));
    expect(h.output, isNot(contains(bodyLine)));
    expect(h.rest.requests, isEmpty);
    expect(h.runner.calls, isEmpty);
    expect(listFiles(tempDir), isEmpty);
  });

  group('T-20-APNS-03: 안내 중단 · 미루기', () {
    test('안내에서 입력 끝 → 멈춤(종료 1)', () async {
      final h = _Harness(root, const <String?>[
        '1',
      ], session: buildEnteredSession());

      final int code = await h.run();

      expect(code, wizardExitStopped);
      expect(h.output, contains(stopLine));
      expect(h.session.isApnsGuideShown, isFalse);
    });

    test('2(지금 안 함) → ✗ · 끝 목록', () async {
      final h = _Harness(root, const <String?>[
        '2',
      ], session: buildEnteredSession());

      final int code = await h.run();

      expect(code, wizardExitDone);
      expect(h.remainingLines, <String>['  ✗ ${ApnsStep.stepTitle} — 지금 안 함']);
      expect(h.session.isApnsGuideShown, isFalse);
    });
  });
}
