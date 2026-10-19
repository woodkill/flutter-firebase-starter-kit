import 'dart:io';
import 'dart:math';

import 'package:test/test.dart';

import '../../../tool/setup/flavor.dart';
import '../../../tool/setup/providers/apple_key_input.dart';
import '../../../tool/setup/redactor.dart';
import '../../../tool/setup/step.dart';
import '../../../tool/setup/steps/apns_step.dart';
import '../../../tool/setup/steps/apple_android_step.dart';
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

/// 값 표 머리 줄.
const String summaryTitleLine = '── Firebase 콘솔에 올릴 APNs 인증 키 ──';

/// 가짜 번들 ID 의 공통 앞부분(실행 시점 조립).
final String baseBundleId = <String>['com', 'example', 'kit'].join('.');

/// 가짜 dev 번들 ID.
final String devBundleId = '$baseBundleId${Flavor.dev.suffix}';

/// 가짜 stg 번들 ID.
final String stgBundleId = '$baseBundleId${Flavor.stg.suffix}';

/// 한 번의 위저드 실행.
final class _Harness {
  _Harness(
    this.root,
    List<String?> inputs, {
    WizardSession? session,
    this.flavor = Flavor.dev,
  }) : screen = ScriptedTerminal(inputs),
       session = session ?? WizardSession();

  final String root;
  final Flavor flavor;
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

  /// 값 표 머리 줄 바로 다음 줄(첫 행).
  String get firstSummaryRow {
    final List<String> lines = output.split('\n');
    final int title = lines.indexOf(summaryTitleLine);
    if (title < 0 || title + 1 >= lines.length) return '';
    return lines[title + 1];
  }

  /// [label] 로 시작하는 값 표 행의 줄 번호(없으면 -1).
  int indexOfRow(String label) =>
      output.split('\n').indexWhere((String l) => l.startsWith('  $label'));

  /// APNs 단계 하나로 위저드를 돌린다.
  Future<int> run() => runWizard(
    WizardContext(
      projectRoot: root,
      flavor: flavor,
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

/// [root] 아래 [flavor] 의 사용자 xcconfig 에 [bundleId] 를 쓰고 그 내용을 돌려준다.
String writeXcconfig(String root, Flavor flavor, String bundleId) {
  final content = 'PRODUCT_BUNDLE_IDENTIFIER = $bundleId\n';
  File('$root/${FlavorPaths(flavor).xcconfig}')
    ..createSync(recursive: true)
    ..writeAsStringSync(content);
  return content;
}

/// 안내 바퀴의 공통 기대 — `.p8` 본문 · PEM 머리 0 · `?` 줄 그대로 · 호출 0 ·
/// 파일 목록이 [filesBefore] 그대로.
void _expectGuideWithoutSecretOrWrite(
  _Harness h,
  Directory dir,
  List<String> filesBefore,
) {
  expect(h.output, isNot(contains(pemPrivateKeyHeader)));
  expect(h.output, isNot(contains(bodyLine)));
  expect(h.remainingLines, <String>[apnsLine]);
  expect(h.output, isNot(contains('  ✓ ')));
  expect(h.rest.requests, isEmpty);
  expect(h.runner.calls, isEmpty);
  expect(listFiles(dir), unorderedEquals(filesBefore));
}

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

  group('T-20-APNS-04: 값 표 첫 행 = 그 flavor 의 iOS 번들 ID · 앱 여럿 안내', () {
    test('행 라벨 · 안내 줄 문구', () {
      expect(ApnsStep.targetAppRowLabel, 'iOS 앱 (번들 ID)');
      expect(
        ApnsStep.multipleAppsNote,
        'Firebase 프로젝트에 iOS 앱이 여럿이면 위 번들 ID 의 앱에 올리기',
      );
    });

    test('dev 문맥 · dev xcconfig → 첫 행 = dev 번들 ID · .p8 행보다 앞 · '
        '안내 줄은 할 일 줄 다음', () async {
      final String xcconfig = writeXcconfig(root, Flavor.dev, devBundleId);
      final List<String> filesBefore = listFiles(tempDir);
      final h = _Harness(root, const <String?>[
        '1',
        '',
      ], session: buildEnteredSession());

      final int code = await h.run();

      expect(code, wizardExitDone);
      expect(h.firstSummaryRow, startsWith('  ${ApnsStep.targetAppRowLabel}'));
      expect(h.firstSummaryRow, endsWith('  $devBundleId'));
      expect(
        h.indexOfRow(ApnsStep.targetAppRowLabel),
        lessThan(h.indexOfRow('.p8')),
      );
      expect(
        h.output,
        contains(
          '  · ${ApnsStep.uploadTodoLine}\n'
          '  · ${ApnsStep.multipleAppsNote}\n',
        ),
      );
      _expectGuideWithoutSecretOrWrite(h, tempDir, filesBefore);
      expect(
        File(
          '$root/${const FlavorPaths(Flavor.dev).xcconfig}',
        ).readAsStringSync(),
        xcconfig,
      );
    });

    test('stg 문맥 · stg xcconfig 만 → stg 번들 ID · dev 번들 ID 0회', () async {
      writeXcconfig(root, Flavor.stg, stgBundleId);
      final List<String> filesBefore = listFiles(tempDir);
      final h = _Harness(
        root,
        const <String?>['1', ''],
        session: buildEnteredSession(),
        flavor: Flavor.stg,
      );

      final int code = await h.run();

      expect(code, wizardExitDone);
      expect(h.firstSummaryRow, startsWith('  ${ApnsStep.targetAppRowLabel}'));
      expect(h.firstSummaryRow, endsWith('  $stgBundleId'));
      expect(h.output, isNot(contains(devBundleId)));
      expect(h.output, contains('  · ${ApnsStep.multipleAppsNote}\n'));
      _expectGuideWithoutSecretOrWrite(h, tempDir, filesBefore);
    });

    test('xcconfig 없음 → 첫 행 값 (읽지 못했습니다) · 파일 0', () async {
      final h = _Harness(root, const <String?>[
        '1',
        '',
      ], session: buildEnteredSession());

      final int code = await h.run();

      expect(code, wizardExitDone);
      expect(h.firstSummaryRow, startsWith('  ${ApnsStep.targetAppRowLabel}'));
      expect(h.firstSummaryRow, endsWith('  ${AppleAndroidStep.unreadValue}'));
      expect(h.output, contains('  · ${ApnsStep.multipleAppsNote}\n'));
      _expectGuideWithoutSecretOrWrite(h, tempDir, const <String>[]);
    });
  });
}
