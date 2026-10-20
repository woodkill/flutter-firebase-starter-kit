import 'dart:io';
import 'dart:math';

import 'package:test/test.dart';

import '../../../tool/setup/command_runner.dart';
import '../../../tool/setup/providers/icon_specs.dart';
import '../../../tool/setup/redactor.dart';
import '../../../tool/setup/step.dart';
import '../../../tool/setup/steps/app_icon_step.dart';
import '../../../tool/setup/terminal.dart';
import '../../../tool/setup/wizard.dart';
import 'fake_rest_client.dart';
import 'fakes.dart';

/// 아이콘 대상이 있는 로그인 수단 다섯과 Apple — 모든 수단을 켠 저장소.
const Set<String> allProviders = <String>{
  'google',
  'apple',
  'facebook',
  'kakao',
  'naver',
  'line',
};

/// 다섯 대상의 표시 이름(로그인 수단 표 순서).
const List<String> allTargetNames = <String>[
  'Google',
  'Facebook',
  'Kakao',
  'Naver',
  'LINE',
];

/// 다섯 대상을 모두 만든 뒤의 ✓ 줄.
const String allDoneIconLine =
    '  ✓ 앱 아이콘 — Google · Facebook · Kakao · Naver · LINE 용 5개 · '
    '바꾸려면 .setup/icons 를 지우고 다시 실행';

/// 결과 표 머리 줄.
const String summaryTitleLine = '── provider 콘솔에 올릴 앱 아이콘 ──';

/// 세 선택지 줄.
const String threeChoiceLines = '  1) 진행\n  2) 지금 안 함\n  3) 멈춤';

/// 가짜 이미지 파일 바이트 [length] 개를 만든다(실행 시점 조립).
List<int> buildFakeBytes(int length) =>
    List<int>.generate(length, (int i) => (i * 7 + 3) % 256);

/// `sips -g pixelWidth -g pixelHeight -g format` 의 정상 출력 꼴을 만든다.
String buildProbeStdout(
  String path,
  int width,
  int height, {
  String format = 'png',
}) =>
    '$path\n  pixelWidth: $width\n  pixelHeight: $height\n  format: $format\n';

/// [path] 의 크기 읽기 결과(종료 코드 0).
CommandResult buildProbeResult(
  String path,
  int width,
  int height, {
  String format = 'png',
}) =>
    CommandResult(0, buildProbeStdout(path, width, height, format: format), '');

/// 성공한 빈 출력 결과.
CommandResult buildOkResult() => const CommandResult(0, '', '');

/// [path] 크기 읽기 명령의 키.
String buildProbeKey(String path) =>
    '/usr/bin/sips -g pixelWidth -g pixelHeight -g format $path';

/// 사본 [sourceName] 에서 [token] 규격 [side] PNG 를 만드는 명령의 키.
String buildResizeKey(String root, String sourceName, String token, int side) =>
    '/usr/bin/sips -z $side $side -s format png $root/.setup/icons/$sourceName '
    '--out $root/.setup/icons/$token-${side}x$side.png';

/// Finder 열기 명령의 키.
String buildOpenKey(String root) => '/usr/bin/open $root/.setup/icons';

/// 스트림으로 실행된 명령 키를 순서대로 모은다.
List<String> listStreamKeys(FakeCommandRunner runner) => runner.calls
    .where((FakeCall call) => call.mode == RunMode.stream)
    .map((FakeCall call) => call.key)
    .toList();

/// 로그인 수단 단계 대역 — 늘 끝난 상태라 아이콘 단계가 검사된다.
final class _ProvidersStandIn implements Step {
  @override
  String get id => 'providers';

  @override
  String get title => '로그인 수단';

  @override
  List<String> get dependsOn => const <String>[];

  @override
  bool get isCostlyOrIrreversible => false;

  @override
  Future<CheckResult> check(WizardContext context) async => const Done('대역');

  @override
  List<String> plannedCommandLines(WizardContext context) => const <String>[];

  @override
  Future<StepOutcome> apply(WizardContext context) async => const Applied();
}

/// 임시 저장소 · 임시 홈 한 쌍.
final class _Sandbox {
  _Sandbox() : base = Directory.systemTemp.createTempSync('app_icon_step_') {
    Directory(root).createSync();
    Directory(home).createSync();
  }

  /// 임시 디렉터리 바닥.
  final Directory base;

  /// 저장소 root.
  String get root => '${base.path}/repo';

  /// 사용자 홈.
  String get home => '${base.path}/home';

  /// `.setup/icons` 절대 경로.
  String get iconsPath => '$root/.setup/icons';

  /// 홈 아래 [relative] 에 [bytes] 를 쓴 파일을 만들고 절대 경로를 돌려준다.
  String writeHomeFile(String relative, List<int> bytes) {
    final file = File('$home/$relative')
      ..createSync(recursive: true)
      ..writeAsBytesSync(bytes);
    return file.path;
  }

  /// `.setup/icons/<name>` 에 [bytes] 를 쓴다.
  void writeIcon(String name, List<int> bytes) {
    File('$iconsPath/$name')
      ..createSync(recursive: true)
      ..writeAsBytesSync(bytes);
  }

  /// 정리한다.
  void dispose() => base.deleteSync(recursive: true);
}

/// 한 번의 위저드 실행 — 로그인 수단 대역 + 아이콘 단계.
final class _Harness {
  _Harness(this.box, List<String?> inputs, {this.enabled = allProviders})
    : screen = ScriptedTerminal(inputs);

  final _Sandbox box;
  final Set<String> enabled;
  final ScriptedTerminal screen;
  final FakeCommandRunner runner = FakeCommandRunner();
  final MemoryLogSink log = MemoryLogSink(Redactor());

  /// 효과가 불린 순간 `.setup/icons` 가 디렉터리였는지(순서대로).
  final List<bool> isDirectoryAtEffect = <bool>[];

  /// 화면 출력 전체.
  String get output => screen.output.toString();

  /// 끝 목록 머리 뒤의 줄들.
  List<String> get remainingLines {
    final List<String> lines = output.split('\n');
    final int start = lines.indexOf(remainingHeading);
    if (start < 0) return const <String>[];
    return lines.sublist(start + 1).where((String l) => l.isNotEmpty).toList();
  }

  /// 원본 [sourceName] 에서 [specs] 를 만드는 가짜 변환 · 만든 뒤 크기 읽기를
  /// 등록한다 — 변환 순간 출력 경로에 [bytesFor] 바이트를 쓴다.
  void registerTargets(
    String sourceName,
    List<IconSpec> specs, {
    int Function(IconSpec spec)? bytesFor,
  }) {
    for (final spec in specs) {
      final key = buildResizeKey(box.root, sourceName, spec.token, spec.side);
      final out = '${box.iconsPath}/${spec.fileName}';
      runner
        ..on(key, buildOkResult())
        ..onEffect(key, () {
          isDirectoryAtEffect.add(Directory(box.iconsPath).existsSync());
          File(
            out,
          ).writeAsBytesSync(buildFakeBytes(bytesFor?.call(spec) ?? 64));
        })
        ..on(buildProbeKey(out), buildProbeResult(out, spec.side, spec.side));
    }
  }

  /// Finder 열기 결과를 등록한다.
  void registerOpen([CommandResult? result]) =>
      runner.on(buildOpenKey(box.root), result ?? buildOkResult());

  /// 위저드를 돌린다.
  Future<int> run() => runWizard(
    WizardContext(
      projectRoot: box.root,
      runner: runner,
      terminal: RedactingTerminal(screen, log.redactor, log),
      redactor: log.redactor,
      log: log,
      rest: FakeRestClient(),
      homeDirectory: box.home,
      random: Random(fixedTestRandomSeed),
      now: () => fixedTestNow,
    ),
    <Step>[_ProvidersStandIn(), AppIconStep(enabledProviders: enabled)],
  );
}

void main() {
  late _Sandbox box;

  setUp(() => box = _Sandbox());
  tearDown(() => box.dispose());

  test('T-20.1-ICON-01: 끌어다 놓은 원본 → 사본 → 다섯 PNG → 결과 표 → '
      'Finder → ✓', () async {
    final List<int> sourceBytes = buildFakeBytes(4096);
    final String source = box.writeHomeFile(
      'My Logos/app icon.png',
      sourceBytes,
    );
    final dropped = '${source.replaceAll(' ', r'\ ')} ';
    final h = _Harness(box, <String?>['1', dropped]);
    h.runner.on(buildProbeKey(source), buildProbeResult(source, 1024, 1024));
    h
      ..registerTargets('source.png', iconSpecs)
      ..registerOpen();

    final int code = await h.run();

    expect(code, wizardExitDone);
    expect(h.output, contains('  ✗ 앱 아이콘 — '));
    expect(h.output, contains('▶ 앱 아이콘'));
    expect(h.output, contains(threeChoiceLines));
    expect(h.output, contains(AppIconStep.sourceGuide));
    expect(
      h.screen.asks.where((String q) => q == AppIconStep.sourceQuestion),
      hasLength(1),
    );
    for (final IconSpec spec in iconSpecs) {
      expect(File('${box.iconsPath}/${spec.fileName}').existsSync(), isTrue);
    }
    expect(File('${box.iconsPath}/source.png').readAsBytesSync(), sourceBytes);
    expect(File(source).readAsBytesSync(), sourceBytes);
    expect(listStreamKeys(h.runner), <String>[
      for (final IconSpec spec in iconSpecs)
        buildResizeKey(box.root, 'source.png', spec.token, spec.side),
      buildOpenKey(box.root),
    ]);
    expect(h.isDirectoryAtEffect, <bool>[true, true, true, true, true]);
    expect(h.output, contains(summaryTitleLine));
    final List<String> lines = h.output.split('\n');
    for (final IconSpec spec in iconSpecs) {
      final String name = allTargetNames[iconSpecs.indexOf(spec)];
      expect(
        lines.where(
          (String l) =>
              l.startsWith('  $name — ${spec.rowLabel}') &&
              l.endsWith(spec.relativePath),
        ),
        hasLength(1),
        reason: spec.token,
      );
    }
    expect(
      h.output,
      contains(
        '  · 앱 아이콘(1024 x 1024): 앱을 게시할 때 필수이고 개발 모드 로그인에는 '
        '필요 없습니다',
      ),
    );
    expect(
      h.output,
      contains(
        '  · 동의 화면 로고: 출시 전 선택입니다 — 올리면 Google 의 브랜드 인증을 '
        '거쳐야 동의 화면에 보입니다',
      ),
    );
    expect(h.output, contains('  · ${AppIconStep.uploadGuide}'));
    expect(h.output, contains(allDoneIconLine));
    expect(h.output, contains(allDoneLine));
    expect(h.remainingLines, isEmpty);
    expect(h.output, isNot(contains(box.home)));
  });

  group('T-20.1-ICON-02: 대상 선택 · 파일이 모두 있으면 ✓', () {
    test('Apple 은 대상이 아니고 순서는 로그인 수단 표 순서', () {
      expect(AppIconStep.isRequiredFor(const <String>{}), isFalse);
      expect(AppIconStep.isRequiredFor(const <String>{'apple'}), isFalse);
      expect(AppIconStep.isRequiredFor(const <String>{'naver'}), isTrue);
      expect(
        AppIconStep(
          enabledProviders: allProviders,
        ).targets.map((IconSpec spec) => spec.token),
        <String>['google', 'facebook', 'kakao', 'naver', 'line'],
      );
      expect(findIconSpec('apple'), isNull);
      final step = AppIconStep(enabledProviders: allProviders);
      expect(step.id, 'app_icon');
      expect(step.dependsOn, <String>['providers']);
      expect(step.isCostlyOrIrreversible, isFalse);
    });

    test('규격 표 — 크기 · 파일 이름 · 용량 상한', () {
      expect(
        iconSpecs.map(
          (IconSpec s) => '${s.token} ${s.side} ${s.maxBytes} ${s.fileName}',
        ),
        <String>[
          'google 120 1000000 google-120x120.png',
          'facebook 1024 5000000 facebook-1024x1024.png',
          'kakao 128 250000 kakao-128x128.png',
          'naver 140 500000 naver-140x140.png',
          'line 512 3000000 line-512x512.png',
        ],
      );
    });

    test('대상 파일이 모두 있으면 점검표부터 ✓ · 질문 0 · 호출 0', () async {
      for (final IconSpec spec in iconSpecs) {
        box.writeIcon(spec.fileName, buildFakeBytes(32));
      }
      final h = _Harness(box, const <String?>[]);

      final int code = await h.run();

      expect(code, wizardExitDone);
      expect(h.output, contains(allDoneIconLine));
      expect(h.screen.asks, isEmpty);
      expect(h.runner.calls, isEmpty);
    });

    test('켠 대상의 파일만 본다 — Naver 하나면 Naver 파일 하나로 ✓', () async {
      box.writeIcon('naver-140x140.png', buildFakeBytes(32));
      final h = _Harness(
        box,
        const <String?>[],
        enabled: const <String>{'apple', 'naver'},
      );

      final int code = await h.run();

      expect(code, wizardExitDone);
      expect(
        h.output,
        contains('  ✓ 앱 아이콘 — Naver 용 1개 · 바꾸려면 .setup/icons 를 지우고 다시 실행'),
      );
      expect(h.screen.asks, isEmpty);
      expect(h.runner.calls, isEmpty);
    });
  });

  group('T-20.1-ICON-03: sips 명령 · 결과 파서', () {
    test('크기 읽기 세 모양', () {
      final ImageProbe? probe = AppIconStep.parseProbe(
        buildProbeResult('/x/logo.png', 1024, 1024),
      );
      expect(probe, (width: 1024, height: 1024, format: 'png'));
      expect(
        AppIconStep.parseProbe(
          const CommandResult(
            0,
            '/x/not-image.txt\n  pixelWidth: <nil>\n  pixelHeight: <nil>\n'
                '  format: txt\n',
            '',
          ),
        ),
        isNull,
      );
      expect(
        AppIconStep.parseProbe(
          const CommandResult(
            0,
            '',
            'Warning: missing.png not a valid file - skipping\n',
          ),
        ),
        isNull,
      );
    });

    test('변환 · 열기 · 크기 읽기 명령', () {
      const root = '/repo';
      final Command resize = AppIconStep.buildResizeCommand(
        root,
        'source.heic',
        findIconSpec('naver')!,
      );
      expect(resize.executable, '/usr/bin/sips');
      expect(resize.arguments, <String>[
        '-z',
        '140',
        '140',
        '-s',
        'format',
        'png',
        '/repo/.setup/icons/source.heic',
        '--out',
        '/repo/.setup/icons/naver-140x140.png',
      ]);
      expect(
        resize.render(),
        'sips -z 140 140 -s format png .setup/icons/source.heic '
        '--out .setup/icons/naver-140x140.png',
      );
      final Command open = AppIconStep.buildOpenCommand(root);
      expect(open.executable, '/usr/bin/open');
      expect(open.arguments, <String>['/repo/.setup/icons']);
      expect(open.render(), 'open .setup/icons');
      final Command probe = AppIconStep.buildProbeCommand('/x/a b.png');
      expect(probe.executable, '/usr/bin/sips');
      expect(probe.arguments, <String>[
        '-g',
        'pixelWidth',
        '-g',
        'pixelHeight',
        '-g',
        'format',
        '/x/a b.png',
      ]);
    });
  });
}
