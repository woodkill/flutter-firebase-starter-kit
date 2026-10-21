import 'dart:io';
import 'dart:math';

import 'package:test/test.dart';

import '../../../tool/setup/command_runner.dart';
import '../../../tool/setup/flavor.dart';
import '../../../tool/setup/providers/icon_specs.dart';
import '../../../tool/setup/redactor.dart';
import '../../../tool/setup/step.dart';
import '../../../tool/setup/steps/app_icon_step.dart';
import '../../../tool/setup/terminal.dart';
import '../../../tool/setup/wizard.dart';
import 'fake_rest_client.dart';
import 'fakes.dart';

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

/// 쓰기 막힌 폴더의 파일도 지워지는 환경에서 지우기 실패 시험을 건너뛰는 까닭.
const String unblockedDeleteSkipReason =
    '이 환경은 쓰기 막힌 폴더의 파일도 지울 수 있어(root · 권한 무시 볼륨) '
    '지우기 실패를 만들 수 없다';

/// 시스템 임시 폴더에서 `555` 폴더 안 파일 지우기가 막히는지 시험해 건너뛸 까닭을 찾는다.
///
/// 지우기가 막히지 않으면 [unblockedDeleteSkipReason], 막히면 `null` 이다. 시험
/// 상자도 같은 시스템 임시 폴더에 만들어지므로 같은 볼륨의 성질을 본다. `chmod`
/// 자체가 실패하면 전제를 가를 수 없어 `null` 로 두고, 시험 본문의 종료 코드
/// 단언이 원인을 말하게 한다. 끝나면 권한을 되돌리고 임시 폴더를 지운다.
String? findUnblockedDeleteSkipReason() {
  final Directory dir = Directory.systemTemp.createTempSync(
    'app_icon_delete_probe_',
  );
  try {
    final probe = File('${dir.path}/probe')..writeAsBytesSync(const <int>[0]);
    final ProcessResult chmod = Process.runSync('/bin/chmod', <String>[
      '555',
      dir.path,
    ]);
    if (chmod.exitCode != 0) return null;
    try {
      probe.deleteSync();
      return unblockedDeleteSkipReason;
    } on FileSystemException {
      return null;
    }
  } finally {
    Process.runSync('/bin/chmod', <String>['755', dir.path]);
    dir.deleteSync(recursive: true);
  }
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
  _Harness(
    this.box,
    List<String?> inputs, {
    this.enabled = allProviderTokens,
    this.flavor = Flavor.dev,
  }) : screen = ScriptedTerminal(inputs);

  final _Sandbox box;
  final Set<String> enabled;
  final Flavor flavor;
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
  /// 등록한다 — 변환 순간 출력 경로에 [bytesFor] 바이트를 쓰고, 만든 뒤 크기는
  /// [probeSideFor] 로 읽힌다(없으면 규격 크기).
  void registerTargets(
    String sourceName,
    List<IconSpec> specs, {
    int Function(IconSpec spec)? bytesFor,
    int Function(IconSpec spec)? probeSideFor,
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
        ..on(
          buildProbeKey(out),
          buildProbeResult(
            out,
            probeSideFor?.call(spec) ?? spec.side,
            probeSideFor?.call(spec) ?? spec.side,
          ),
        );
    }
  }

  /// Finder 열기 결과를 등록한다.
  void registerOpen([CommandResult? result]) =>
      runner.on(buildOpenKey(box.root), result ?? buildOkResult());

  /// 위저드를 돌린다.
  Future<int> run() => runWizard(
    WizardContext(
      projectRoot: box.root,
      flavor: flavor,
      runner: runner,
      terminal: RedactingTerminal(screen, log.redactor, log),
      redactor: log.redactor,
      log: log,
      rest: FakeRestClient(),
      homeDirectory: box.home,
      random: Random(fixedTestRandomSeed),
      now: () => fixedTestNow,
    ),
    <Step>[providersStandIn, AppIconStep(enabledProviders: enabled)],
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
          enabledProviders: allProviderTokens,
        ).targets.map((IconSpec spec) => spec.token),
        <String>['google', 'facebook', 'kakao', 'naver', 'line'],
      );
      expect(findIconSpec('apple'), isNull);
      final step = AppIconStep(enabledProviders: allProviderTokens);
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

  group('T-20.1-ICON-04: 원본 거절 — 까닭 · 지금 크기 · 경로만 다시', () {
    test('없는 파일 · 비정사각 뒤 맞는 원본 → 셋째 답 뒤에만 변환', () async {
      final String wide = box.writeHomeFile('wide.png', buildFakeBytes(256));
      final String good = box.writeHomeFile('good.png', buildFakeBytes(512));
      final missing = '${box.home}/missing.png';
      final h = _Harness(box, <String?>['1', missing, wide, good]);
      h.runner
        ..on(buildProbeKey(wide), buildProbeResult(wide, 1920, 1080))
        ..on(buildProbeKey(good), buildProbeResult(good, 1024, 1024));
      h
        ..registerTargets('source.png', iconSpecs)
        ..registerOpen();

      final int code = await h.run();

      expect(code, wizardExitDone);
      final int missingAt = h.output.indexOf(
        '  ${AppIconStep.missingFileReason}~/missing.png',
      );
      final int wideAt = h.output.indexOf(
        '  ${AppIconStep.notSquareReason}1920x1080',
      );
      expect(missingAt, greaterThan(0));
      expect(wideAt, greaterThan(missingAt));
      expect(
        h.screen.asks.where((String q) => q == AppIconStep.sourceQuestion),
        hasLength(3),
      );
      expect(h.runner.countCalls(RunMode.capture, buildProbeKey(missing)), 0);
      final List<String> keys = h.runner.calls
          .map((FakeCall c) => c.key)
          .toList();
      final int goodProbeAt = keys.indexOf(buildProbeKey(good));
      final int firstResizeAt = keys.indexWhere(
        (String k) => k.startsWith('/usr/bin/sips -z '),
      );
      expect(goodProbeAt, greaterThan(keys.indexOf(buildProbeKey(wide))));
      expect(firstResizeAt, greaterThan(goodProbeAt));
      expect(h.output, contains(allDoneIconLine));
      expect(
        File('${box.iconsPath}/source.png').readAsBytesSync(),
        buildFakeBytes(512),
      );
      expect(h.output, isNot(contains(box.home)));
    });

    test('폴더를 넣으면 폴더라는 까닭 · 크기 읽기 0 · 경로만 다시', () async {
      final folder = '${box.home}/Logos';
      Directory(folder).createSync();
      final String good = box.writeHomeFile('good.png', buildFakeBytes(512));
      final h = _Harness(box, <String?>['1', folder, good]);
      h.runner.on(buildProbeKey(good), buildProbeResult(good, 1024, 1024));
      h
        ..registerTargets('source.png', iconSpecs)
        ..registerOpen();

      final int code = await h.run();

      expect(code, wizardExitDone);
      expect(h.output, contains('  ${AppIconStep.folderReason}~/Logos'));
      expect(
        h.output,
        isNot(contains('  ${AppIconStep.missingFileReason}~/Logos')),
      );
      expect(h.runner.countCalls(RunMode.capture, buildProbeKey(folder)), 0);
      expect(h.output, contains(allDoneIconLine));
    });

    // 풀면 비는 답 · 파일 경로로 바꿀 수 없는 `file://` 답 — 주소에는 시험 홈 아래
    // 경로를 담아 화면에 그 경로가 남지 않는지도 본다.
    final unusableAnswers =
        <({String name, String Function(_Sandbox box) build, String reason})>[
          (
            name: '조각 안 %2F 주소',
            build: (_Sandbox b) => 'file://${b.home}/a%2Fb.png',
            reason: AppIconStep.unconvertibleAddressReason,
          ),
          (
            name: '깨진 UTF-8 주소',
            build: (_Sandbox b) => 'file://${b.home}/a%FF.png',
            reason: AppIconStep.unconvertibleAddressReason,
          ),
          (
            name: '큰따옴표로 감싼 %2F 주소',
            build: (_Sandbox b) => '"file://${b.home}/a%2Fb.png"',
            reason: AppIconStep.unconvertibleAddressReason,
          ),
          (
            name: '작은따옴표로 감싼 %2F 주소',
            build: (_Sandbox b) => "'file://${b.home}/a%2Fb.png'",
            reason: AppIconStep.unconvertibleAddressReason,
          ),
          (
            name: '빈 큰따옴표',
            build: (_Sandbox _) => '""',
            reason: AppIconStep.emptyPathReason,
          ),
          (
            name: '빈 작은따옴표',
            build: (_Sandbox _) => "''",
            reason: AppIconStep.emptyPathReason,
          ),
        ];
    for (final item in unusableAnswers) {
      test('${item.name} → 경로 없는 까닭 한 줄 · 크기 읽기 0 · 맞는 원본은 ✓', () async {
        final String answer = item.build(box);
        final String good = box.writeHomeFile('good.png', buildFakeBytes(512));
        final h = _Harness(box, <String?>['1', answer, good]);
        h.runner.on(buildProbeKey(good), buildProbeResult(good, 1024, 1024));
        h
          ..registerTargets('source.png', iconSpecs)
          ..registerOpen();

        final int code = await h.run();

        expect(code, wizardExitDone);
        expect(
          h.output.split('\n').where((String l) => l == '  ${item.reason}'),
          hasLength(1),
        );
        expect(h.output, isNot(contains(AppIconStep.missingFileReason)));
        expect(h.output, isNot(contains(box.home)));
        expect(h.output, isNot(contains(answer)));
        expect(
          h.runner.calls
              .where((FakeCall c) => c.mode == RunMode.capture)
              .map((FakeCall c) => c.key)
              .where((String k) => !k.contains(box.iconsPath)),
          <String>[buildProbeKey(good)],
        );
        expect(
          h.screen.asks.where((String q) => q == AppIconStep.sourceQuestion),
          hasLength(2),
        );
        expect(h.output, contains(allDoneIconLine));
      });
    }

    // 따옴표로 감싼 `file://` 답은 따옴표를 벗긴 뒤 한 번 더 바꿔 그 원본을 쓴다.
    for (final quote in <String>['"', "'"]) {
      test('$quote 로 감싼 file:// 주소 → 까닭 줄 0 · 그 원본 크기 읽기 · ✓', () async {
        final String good = box.writeHomeFile('good.png', buildFakeBytes(512));
        final answer = '${quote}file://$good$quote';
        final h = _Harness(box, <String?>['1', answer]);
        h.runner.on(buildProbeKey(good), buildProbeResult(good, 1024, 1024));
        h
          ..registerTargets('source.png', iconSpecs)
          ..registerOpen();

        final int code = await h.run();

        expect(code, wizardExitDone);
        expect(
          h.output,
          isNot(contains(AppIconStep.unconvertibleAddressReason)),
        );
        expect(h.output, isNot(contains(AppIconStep.emptyPathReason)));
        expect(h.output, isNot(contains(AppIconStep.missingFileReason)));
        expect(h.runner.countCalls(RunMode.capture, buildProbeKey(good)), 1);
        expect(
          h.screen.asks.where((String q) => q == AppIconStep.sourceQuestion),
          hasLength(1),
        );
        expect(
          File('${box.iconsPath}/source.png').readAsBytesSync(),
          buildFakeBytes(512),
        );
        expect(h.output, contains(allDoneIconLine));
        expect(h.output, isNot(contains(box.home)));
      });
    }

    test('경로 없는 까닭으로 다시 묻기도 상한에 센다 → 멈춤 · 만들기 0', () async {
      final h = _Harness(box, <String?>[
        '1',
        '""',
        'file://${box.home}/a%2Fb.png',
        "''",
      ]);

      final int code = await h.run();

      expect(code, wizardExitStopped);
      expect(
        h.screen.asks.where((String q) => q == AppIconStep.sourceQuestion),
        hasLength(AppIconStep.maxSourceAttempts),
      );
      expect(h.output, contains(stopLine));
      expect(h.runner.calls, isEmpty);
      expect(Directory(box.iconsPath).existsSync(), isFalse);
    });

    test('비이미지 · 1024 미만 · 상한 초과 세 번 → 멈춤 · 만들기 0', () async {
      final String text = box.writeHomeFile('notes.txt', buildFakeBytes(16));
      final String small = box.writeHomeFile('small.png', buildFakeBytes(64));
      final String huge = box.writeHomeFile('huge.png', buildFakeBytes(64));
      final h = _Harness(box, <String?>['1', text, small, huge]);
      h.runner
        ..on(
          buildProbeKey(text),
          CommandResult(
            0,
            '$text\n  pixelWidth: <nil>\n  pixelHeight: <nil>\n'
                '  format: txt\n',
            '',
          ),
        )
        ..on(buildProbeKey(small), buildProbeResult(small, 512, 512))
        ..on(buildProbeKey(huge), buildProbeResult(huge, 20000, 20000));

      final int code = await h.run();

      expect(code, wizardExitStopped);
      expect(h.output, contains('  ${AppIconStep.notImageReason}~/notes.txt'));
      expect(h.output, contains('  1024x1024 이상이 필요합니다 — 지금 512x512'));
      expect(h.output, contains('  너무 큰 이미지입니다 — 지금 20000x20000'));
      expect(
        h.screen.asks.where((String q) => q == AppIconStep.sourceQuestion),
        hasLength(AppIconStep.maxSourceAttempts),
      );
      expect(h.output, contains(stopLine));
      expect(Directory(box.iconsPath).existsSync(), isFalse);
      expect(h.runner.countMode(RunMode.stream), 0);
    });

    test('크기 읽기 도구 자체가 실패하면 이미지 판정 대신 실패', () async {
      final String good = box.writeHomeFile('good.png', buildFakeBytes(512));
      final h = _Harness(box, <String?>['1', good]);
      h.runner.on(
        buildProbeKey(good),
        const CommandResult(127, '', 'No such file or directory'),
      );

      final int code = await h.run();

      expect(code, wizardExitStopped);
      expect(h.output, contains('  실패 — 원본 이미지 크기를 읽지 못했습니다 — sips 종료 코드 127'));
      expect(h.output, isNot(contains(AppIconStep.notImageReason)));
      expect(
        h.screen.asks.where((String q) => q == AppIconStep.sourceQuestion),
        hasLength(1),
      );
      expect(Directory(box.iconsPath).existsSync(), isFalse);
      expect(h.output, isNot(contains(box.home)));
    });

    test('한 변만 상한을 넘어도 「너무 큰」 이 먼저', () {
      expect(
        AppIconStep.findSourceProblem((
          width: 1024,
          height: 20000,
          format: 'png',
        )),
        '${AppIconStep.tooLargeReason}1024x20000',
      );
      expect(
        AppIconStep.findSourceProblem((
          width: 2000,
          height: 1000,
          format: 'png',
        )),
        '${AppIconStep.notSquareReason}2000x1000',
      );
      expect(
        AppIconStep.findSourceProblem((
          width: 1024,
          height: 1024,
          format: 'png',
        )),
        isNull,
      );
    });

    test('원본 안내 · 질문에 상한 숫자가 없다', () {
      for (final text in <String>[
        AppIconStep.sourceGuide,
        AppIconStep.sourceQuestion,
      ]) {
        expect(text, isNot(contains('16384')));
        expect(text, isNot(contains('16,384')));
        expect(text, isNot(contains('$maxSourceSide')));
      }
    });
  });

  group('T-20.1-ICON-05: 지금 안 함 · 입력 끝', () {
    const deferredLine = '  ✗ 앱 아이콘 — 지금 안 함';

    test('세 선택지 2 → ✗ · 끝 목록 · 종료 0 · 다음 실행은 다시 묻는다', () async {
      final h = _Harness(box, const <String?>['2']);

      final int code = await h.run();

      expect(code, wizardExitDone);
      expect(h.output.split('\n').where((String l) => l == deferredLine), [
        deferredLine,
        deferredLine,
      ]);
      expect(h.remainingLines, <String>[deferredLine]);
      expect(Directory(box.iconsPath).existsSync(), isFalse);
      expect(h.runner.calls, isEmpty);

      final again = _Harness(box, const <String?>['2']);
      expect(await again.run(), wizardExitDone);
      expect(
        again.screen.asks.where((String q) => q == failureChoiceQuestion),
        hasLength(1),
      );
    });

    test('경로 질문에 빈 값 → 같은 ✗ 줄 · 종료 0 · 만들기 0', () async {
      final h = _Harness(box, const <String?>['1', '']);

      final int code = await h.run();

      expect(code, wizardExitDone);
      expect(h.remainingLines, <String>[deferredLine]);
      expect(Directory(box.iconsPath).existsSync(), isFalse);
      expect(h.runner.calls, isEmpty);
    });

    test('경로 질문에서 입력 끝 → 멈춤', () async {
      final h = _Harness(box, const <String?>['1']);

      final int code = await h.run();

      expect(code, wizardExitStopped);
      expect(h.output, contains(stopLine));
      expect(h.runner.calls, isEmpty);
    });
  });

  group('T-20.1-ICON-06: 보관한 사본으로 없는 파일만 만든다', () {
    const kakaoNaver = <String>{'kakao', 'naver'};

    test('사본이 있으면 경로 질문 0 · Naver 만 변환 · Kakao 그대로', () async {
      final List<int> kakaoBytes = buildFakeBytes(48);
      box
        ..writeIcon('source.jpeg', buildFakeBytes(900))
        ..writeIcon('kakao-128x128.png', kakaoBytes);
      final copy = '${box.iconsPath}/source.jpeg';
      final h = _Harness(box, const <String?>['1'], enabled: kakaoNaver);
      h.runner.on(
        buildProbeKey(copy),
        buildProbeResult(copy, 1024, 1024, format: 'jpeg'),
      );
      h
        ..registerTargets('source.jpeg', <IconSpec>[findIconSpec('naver')!])
        ..registerOpen();

      final int code = await h.run();

      expect(code, wizardExitDone);
      expect(
        h.output,
        contains('  ✗ 앱 아이콘 — Naver 용 파일이 없습니다 — 보관한 원본으로 만듭니다'),
      );
      expect(
        h.output,
        contains(
          r'  $ sips -z 140 140 -s format png .setup/icons/source.jpeg '
          '--out .setup/icons/naver-140x140.png',
        ),
      );
      expect(h.output, contains(r'  $ open .setup/icons'));
      expect(h.screen.asks, isNot(contains(AppIconStep.sourceQuestion)));
      expect(h.runner.countCalls(RunMode.capture, buildProbeKey(copy)), 1);
      expect(listStreamKeys(h.runner), <String>[
        buildResizeKey(box.root, 'source.jpeg', 'naver', 140),
        buildOpenKey(box.root),
      ]);
      expect(
        File('${box.iconsPath}/kakao-128x128.png').readAsBytesSync(),
        kakaoBytes,
      );
      expect(
        h.output,
        contains(
          '  ✓ 앱 아이콘 — Kakao · Naver 용 2개 · 바꾸려면 .setup/icons 를 지우고 '
          '다시 실행',
        ),
      );
    });

    test('사본이 맞지 않으면 실패 · 변환 0', () async {
      box.writeIcon('source.jpeg', buildFakeBytes(900));
      final copy = '${box.iconsPath}/source.jpeg';
      final h = _Harness(box, const <String?>['1'], enabled: kakaoNaver);
      h.runner.on(
        buildProbeKey(copy),
        buildProbeResult(copy, 512, 512, format: 'jpeg'),
      );

      final int code = await h.run();

      expect(code, wizardExitStopped);
      expect(
        h.output,
        contains('  실패 — 보관한 원본 .setup/icons/source.jpeg 이 맞지 않습니다 — '),
      );
      expect(h.output, contains('지금 512x512'));
      expect(h.runner.countMode(RunMode.stream), 0);
    });

    test('경로를 묻는 실행도 이미 있는 파일은 그대로 둔다', () async {
      final List<int> kakaoBytes = buildFakeBytes(48);
      box.writeIcon('kakao-128x128.png', kakaoBytes);
      final String source = box.writeHomeFile('logo.png', buildFakeBytes(700));
      final h = _Harness(box, <String?>['1', source], enabled: kakaoNaver);
      h.runner.on(buildProbeKey(source), buildProbeResult(source, 1024, 1024));
      h
        ..registerTargets('source.png', <IconSpec>[findIconSpec('naver')!])
        ..registerOpen();

      final int code = await h.run();

      expect(code, wizardExitDone);
      expect(listStreamKeys(h.runner), <String>[
        buildResizeKey(box.root, 'source.png', 'naver', 140),
        buildOpenKey(box.root),
      ]);
      expect(
        File('${box.iconsPath}/kakao-128x128.png').readAsBytesSync(),
        kakaoBytes,
      );
    });
  });

  group('T-20.1-ICON-07: 만든 뒤 확인 · 변환 실패', () {
    late String source;

    setUp(() {
      source = box.writeHomeFile('logo.png', buildFakeBytes(700));
    });

    test('용량 상한 초과 → 규격과 다르다는 실패 · 멈춤', () async {
      final h = _Harness(
        box,
        <String?>['1', source],
        enabled: const <String>{'naver'},
      );
      h.runner.on(buildProbeKey(source), buildProbeResult(source, 1024, 1024));
      h.registerTargets('source.png', <IconSpec>[
        findIconSpec('naver')!,
      ], bytesFor: (IconSpec spec) => spec.maxBytes + 1);

      final int code = await h.run();

      expect(code, wizardExitStopped);
      expect(
        h.output,
        contains(
          '  실패 — Naver 아이콘이 규격과 다릅니다 — .setup/icons/naver-140x140.png: '
          '지금 140x140 png · 500001 바이트 (규격 140x140 png · 500000 바이트 이하)',
        ),
      );
      expect(File('${box.iconsPath}/naver-140x140.png').existsSync(), isFalse);
      expect(h.output, isNot(contains(AppIconStep.discardFailedReason)));
      expect(h.runner.countCalls(RunMode.stream, buildOpenKey(box.root)), 0);
    });

    // 전제 — 555 폴더 안 파일 지우기가 막혀야 한다. root · 권한 무시 볼륨처럼 막히지
    // 않는 환경이면 선언 때 그 전제를 시험해 보고 건너뛴다(거짓 실패 대신 skip).
    test('확인에 걸린 파일을 지우지 못하면 상대 경로 · 직접 지우라는 한 줄', () async {
      final spec = findIconSpec('naver')!;
      final out = '${box.iconsPath}/${spec.fileName}';
      final h = _Harness(
        box,
        <String?>['1', source],
        enabled: const <String>{'naver'},
      );
      h.runner.on(buildProbeKey(source), buildProbeResult(source, 1024, 1024));
      h.registerTargets('source.png', <IconSpec>[
        spec,
      ], probeSideFor: (IconSpec _) => 120);
      // 만든 뒤 크기를 읽는 순간 폴더 쓰기 권한을 빼 지우기가 실패하게 한다 —
      // 임시 폴더 정리보다 먼저 권한을 되돌린다(addTearDown 은 나중 등록이 먼저).
      addTearDown(
        () => Process.runSync('/bin/chmod', <String>['755', box.iconsPath]),
      );
      h.runner.onEffect(buildProbeKey(out), () {
        final ProcessResult chmod = Process.runSync('/bin/chmod', <String>[
          '555',
          box.iconsPath,
        ]);
        expect(chmod.exitCode, 0);
      });

      final int code = await h.run();

      expect(code, wizardExitStopped);
      expect(
        h.output,
        contains('  실패 — Naver 아이콘이 규격과 다릅니다 — ${spec.relativePath}'),
      );
      expect(File(out).existsSync(), isTrue);
      final List<String> notes = h.output
          .split('\n')
          .where((String l) => l.contains(AppIconStep.discardFailedReason))
          .toList();
      expect(notes, hasLength(1));
      expect(
        notes.single,
        startsWith(
          '  ${AppIconStep.discardFailedReason}${spec.relativePath} '
          '${AppIconStep.discardFailedHint}',
        ),
      );
      expect(spec.relativePath.allMatches(notes.single), hasLength(1));
      expect(AppIconStep.discardFailedHint.allMatches(h.output), hasLength(1));
      expect(h.output, isNot(contains(box.home)));
      expect(h.output, isNot(contains(box.root)));
    }, skip: findUnblockedDeleteSkipReason());

    test('만든 파일 크기가 다르면 같은 꼴의 실패', () async {
      final h = _Harness(
        box,
        <String?>['1', source],
        enabled: const <String>{'naver'},
      );
      h.runner.on(buildProbeKey(source), buildProbeResult(source, 1024, 1024));
      h.registerTargets('source.png', <IconSpec>[
        findIconSpec('naver')!,
      ], probeSideFor: (IconSpec spec) => 120);

      final int code = await h.run();

      expect(code, wizardExitStopped);
      expect(
        h.output,
        contains(
          '  실패 — Naver 아이콘이 규격과 다릅니다 — .setup/icons/naver-140x140.png: '
          '지금 120x120 png · 64 바이트 (규격 140x140 png · 500000 바이트 이하)',
        ),
      );
    });

    test('만든 뒤 크기 읽기가 0 이 아닌 종료 코드 → 원문과 함께 실패', () async {
      const errorText = 'sips: unexpected failure\n';
      final h = _Harness(
        box,
        <String?>['1', source],
        enabled: const <String>{'naver'},
      );
      h.runner.on(buildProbeKey(source), buildProbeResult(source, 1024, 1024));
      // 결과 큐는 앞에서부터 쓰므로 실패를 정상 결과보다 먼저 넣는다.
      h.runner.on(
        buildProbeKey('${box.iconsPath}/naver-140x140.png'),
        const CommandResult(1, '', errorText),
      );
      h.registerTargets('source.png', <IconSpec>[findIconSpec('naver')!]);

      final int code = await h.run();

      expect(code, wizardExitStopped);
      expect(
        h.output,
        contains(
          '  실패 — Naver 아이콘 크기를 읽지 못했습니다 — '
          '.setup/icons/naver-140x140.png\n$errorText',
        ),
      );
    });

    test('변환이 0 이 아닌 종료 코드 → 실패 줄과 원문', () async {
      const errorText =
          "Error: Can't write format: org.webmproject.webp\n"
          'Error 13: an unknown error occurred\n';
      final h = _Harness(
        box,
        <String?>['1', source],
        enabled: const <String>{'kakao'},
      );
      h.runner
        ..on(buildProbeKey(source), buildProbeResult(source, 1024, 1024))
        ..on(
          buildResizeKey(box.root, 'source.png', 'kakao', 128),
          const CommandResult(13, '', errorText),
        );

      final int code = await h.run();

      expect(code, wizardExitStopped);
      expect(h.output, contains('  실패 — Kakao 아이콘을 만들지 못했습니다\n$errorText'));
      expect(h.runner.countCalls(RunMode.stream, buildOpenKey(box.root)), 0);
    });

    test('대상 둘 · 두 번째 변환 실패 → 남은 첫 파일은 이미 확인을 거쳤다', () async {
      const errorText = 'Error 13: an unknown error occurred\n';
      final kakaoPath = '${box.iconsPath}/kakao-128x128.png';
      final h = _Harness(
        box,
        <String?>['1', source],
        enabled: const <String>{'kakao', 'naver'},
      );
      h.runner
        ..on(buildProbeKey(source), buildProbeResult(source, 1024, 1024))
        ..on(
          buildResizeKey(box.root, 'source.png', 'naver', 140),
          const CommandResult(13, '', errorText),
        );
      h.registerTargets('source.png', <IconSpec>[findIconSpec('kakao')!]);

      final int code = await h.run();

      expect(code, wizardExitStopped);
      expect(h.output, contains('  실패 — Naver 아이콘을 만들지 못했습니다\n$errorText'));
      expect(File(kakaoPath).existsSync(), isTrue);
      final List<String> keys = h.runner.calls
          .map((FakeCall c) => c.key)
          .toList();
      final int kakaoProbeAt = keys.indexOf(buildProbeKey(kakaoPath));
      expect(kakaoProbeAt, greaterThan(0));
      expect(
        kakaoProbeAt,
        lessThan(
          keys.indexOf(buildResizeKey(box.root, 'source.png', 'naver', 140)),
        ),
      );
      expect(File('${box.iconsPath}/naver-140x140.png').existsSync(), isFalse);
    });

    test('대상 둘 · 첫 확인 실패 → 두 번째 파일은 만들지 않는다', () async {
      final h = _Harness(
        box,
        <String?>['1', source],
        enabled: const <String>{'kakao', 'naver'},
      );
      h.runner.on(buildProbeKey(source), buildProbeResult(source, 1024, 1024));
      h.registerTargets(
        'source.png',
        <IconSpec>[findIconSpec('kakao')!, findIconSpec('naver')!],
        probeSideFor: (IconSpec spec) =>
            spec.token == 'kakao' ? 120 : spec.side,
      );

      final int code = await h.run();

      expect(code, wizardExitStopped);
      expect(
        h.output,
        contains('  실패 — Kakao 아이콘이 규격과 다릅니다 — .setup/icons/kakao-128x128.png'),
      );
      expect(File('${box.iconsPath}/kakao-128x128.png').existsSync(), isFalse);
      expect(File('${box.iconsPath}/naver-140x140.png').existsSync(), isFalse);
      expect(
        h.runner.countCalls(
          RunMode.stream,
          buildResizeKey(box.root, 'source.png', 'naver', 140),
        ),
        0,
      );
    });
  });

  test('T-20.1-ICON-08: Finder 열기 실패는 한 줄 뒤 ✓', () async {
    final String source = box.writeHomeFile('logo.png', buildFakeBytes(700));
    final h = _Harness(box, <String?>['1', source]);
    h.runner.on(buildProbeKey(source), buildProbeResult(source, 1024, 1024));
    h
      ..registerTargets('source.png', iconSpecs)
      ..registerOpen(
        CommandResult(1, '', 'The file ${box.iconsPath} does not exist.\n'),
      );

    final int code = await h.run();

    expect(code, wizardExitDone);
    expect(
      h.output
          .split('\n')
          .where((String l) => l == '  ${AppIconStep.openFailedNote}'),
      hasLength(1),
    );
    expect(
      AppIconStep.openFailedNote,
      'Finder 를 열지 못했습니다 — 파일은 .setup/icons 에 있습니다',
    );
    expect(h.output, contains(allDoneIconLine));
    expect(
      h.screen.asks.where((String q) => q == failureChoiceQuestion),
      hasLength(1),
    );
    expect(h.output, isNot(contains(retryOption)));
  });

  group('T-20.1-ICON-09: flavor 공통 · 사본 여럿', () {
    test('dev 로 만든 파일 그대로 stg 문맥 → ✓ · 질문 0 · 호출 0', () async {
      for (final IconSpec spec in iconSpecs) {
        box.writeIcon(spec.fileName, buildFakeBytes(32));
      }
      box.writeIcon('source.png', buildFakeBytes(900));
      final h = _Harness(box, const <String?>[], flavor: Flavor.stg);

      final int code = await h.run();

      expect(code, wizardExitDone);
      expect(h.output, contains(allDoneIconLine));
      expect(h.screen.asks, isEmpty);
      expect(h.runner.calls, isEmpty);
    });

    test('사본이 둘이면 실행 없는 ✗ · 끝 목록 · 종료 0', () async {
      box
        ..writeIcon('source.png', buildFakeBytes(900))
        ..writeIcon('source.heic', buildFakeBytes(900));
      final h = _Harness(box, const <String?>[]);

      final int code = await h.run();

      const line = '  ✗ 앱 아이콘 — ${AppIconStep.multipleSourcesReason}';
      expect(code, wizardExitDone);
      expect(h.output, contains('$line\n'));
      expect(h.remainingLines, <String>[line]);
      expect(h.screen.asks, isEmpty);
      expect(h.runner.calls, isEmpty);
    });

    test('source.png.orig 같은 이름은 사본으로 세지 않는다', () async {
      final List<int> origBytes = buildFakeBytes(40);
      box
        ..writeIcon('source.png', buildFakeBytes(900))
        ..writeIcon('source.png.orig', origBytes);
      final copy = '${box.iconsPath}/source.png';
      final h = _Harness(
        box,
        const <String?>['1'],
        enabled: const <String>{'naver'},
      );
      h.runner.on(buildProbeKey(copy), buildProbeResult(copy, 1024, 1024));
      h
        ..registerTargets('source.png', <IconSpec>[findIconSpec('naver')!])
        ..registerOpen();

      final int code = await h.run();

      expect(code, wizardExitDone);
      expect(h.output, isNot(contains(AppIconStep.multipleSourcesReason)));
      expect(
        h.output,
        contains('  ✗ 앱 아이콘 — Naver 용 파일이 없습니다 — 보관한 원본으로 만듭니다'),
      );
      expect(File('${box.iconsPath}/naver-140x140.png').existsSync(), isTrue);
      expect(
        File('${box.iconsPath}/source.png.orig').readAsBytesSync(),
        origBytes,
      );
    });
  });
}
