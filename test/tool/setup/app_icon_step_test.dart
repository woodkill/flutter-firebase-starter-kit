import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:image/image.dart' as img;
import 'package:test/test.dart';

import '../../../tool/setup/command_runner.dart';
import '../../../tool/setup/git_tree.dart';
import '../../../tool/setup/icons/home_icon_specs.dart';
import '../../../tool/setup/icons/icon_pipeline.dart';
import '../../../tool/setup/providers/icon_specs.dart';
import '../../../tool/setup/redactor.dart';
import '../../../tool/setup/step.dart';
import '../../../tool/setup/steps/app_icon_step.dart';
import '../../../tool/setup/terminal.dart';
import '../../../tool/setup/wizard.dart';
import 'fake_rest_client.dart';
import 'fakes.dart';
import 'home_icon_fixture.dart';

/// 세 선택지 줄.
const String threeChoiceLines = '  1) 진행\n  2) 지금 안 함\n  3) 멈춤';

/// 원본 질문 전 미커밋 검사 git 명령의 키.
String buildDirtyKey() => FakeCommandRunner.buildKey(
  buildUncommittedFilesCommand(AppIconStep.listWritePaths()),
);

/// [path] 크기 읽기 명령의 키.
String buildProbeKey(String path) =>
    FakeCommandRunner.buildKey(AppIconStep.buildProbeCommand(path));

/// [source] 를 작업 폴더의 `source.png` 로 바꾸는 명령의 키.
String buildConvertKey(String root, String source) =>
    FakeCommandRunner.buildKey(
      AppIconStep.buildConvertCommand(
        source,
        '$root/$iconWorkDirectory/source.png',
        display: '',
      ),
    );

/// Finder 열기 명령의 키.
String buildOpenKey(String root) =>
    FakeCommandRunner.buildKey(AppIconStep.buildOpenCommand(root));

/// `sips -g pixelWidth -g pixelHeight -g format` 의 정상 결과(종료 코드 0).
CommandResult buildProbeResult(
  String path,
  int width,
  int height, {
  String format = 'png',
}) => CommandResult(
  0,
  '$path\n  pixelWidth: $width\n  pixelHeight: $height\n  format: $format\n',
  '',
);

/// 성공한 빈 출력 결과.
CommandResult buildOkResult([String stdout = '']) =>
    CommandResult(0, stdout, '');

/// [bytes] 의 sha256 소문자 16진.
String digestOf(List<int> bytes) => sha256.convert(bytes).toString();

/// 변환 결과 [converted] 에서 단계가 만들 채운 그림을 같은 함수로 만든다.
img.Image buildExpectedFilled(
  Uint8List converted, {
  int backgroundRgb = defaultBackgroundRgb,
}) => buildFilledIcon(
  normalizeIcon(decodeIconPng(converted)!),
  backgroundRgb: backgroundRgb,
);

/// 칠한 그림 원본의 adaptive 배경색을 승인 규칙으로 구한다.
int findPaintedBackgroundRgb(img.Image filled) => switch (paintedBackground) {
  PaintedBackground.edge => averageEdgeRgb(filled),
  PaintedBackground.white => defaultBackgroundRgb,
};

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
  String get iconsPath => '$root/$iconsDirectory';

  /// 홈 아래 [relative] 에 [bytes] 를 쓴 파일을 만들고 절대 경로를 돌려준다.
  String writeHomeFile(String relative, List<int> bytes) {
    final file = File('$home/$relative')
      ..createSync(recursive: true)
      ..writeAsBytesSync(bytes);
    return file.path;
  }

  /// 저장소 상대 경로 [relativePath] 의 파일.
  File repoFile(String relativePath) => File('$root/$relativePath');

  /// 홈 화면 아이콘 20장의 경로 → 바이트.
  Map<String, List<int>> readHomeIcons() => <String, List<int>>{
    for (final HomeIconFile file in homeIconFiles)
      file.relativePath: repoFile(file.relativePath).readAsBytesSync(),
  };

  /// 정리한다.
  void dispose() => base.deleteSync(recursive: true);
}

/// 한 번의 위저드 실행 — 로그인 수단 대역 + 아이콘 단계.
final class _Harness {
  _Harness(
    this.box,
    List<String?> inputs, {
    this.kitDigests,
    WizardSession? session,
  }) : screen = ScriptedTerminal(inputs),
       session = session ?? WizardSession();

  final _Sandbox box;

  /// 켠 로그인 수단.
  final Set<String> enabled = const <String>{'kakao'};

  /// 단계에 주입할 킷 기본 지문 — 없으면 킷이 담은 지문.
  final Map<String, String>? kitDigests;
  final WizardSession session;
  final ScriptedTerminal screen;
  final FakeCommandRunner runner = FakeCommandRunner();
  final MemoryLogSink log = MemoryLogSink(Redactor());

  /// 변환 효과가 불린 순간 작업 폴더가 있었는지(순서대로).
  final List<bool> isWorkDirectoryAtEffect = <bool>[];

  /// 화면 출력 전체.
  String get output => screen.output.toString();

  /// 화면 줄들.
  List<String> get lines => output.split('\n');

  /// 미커밋 검사 결과를 [stdout] 으로 등록한다.
  void registerDirty([String stdout = '']) =>
      runner.on(buildDirtyKey(), buildOkResult(stdout));

  /// 원본 [source] 의 크기 읽기 결과를 등록한다.
  void registerProbe(String source, {int side = 1024}) =>
      runner.on(buildProbeKey(source), buildProbeResult(source, side, side));

  /// [source] 변환이 작업 폴더 `source.png` 에 [converted] 를 쓰게 등록한다.
  void registerConvert(
    String source,
    List<int> converted, {
    CommandResult? result,
  }) {
    final String key = buildConvertKey(box.root, source);
    runner
      ..on(key, result ?? buildOkResult())
      ..onEffect(key, () {
        final dir = Directory('${box.root}/$iconWorkDirectory');
        isWorkDirectoryAtEffect.add(dir.existsSync());
        if (result != null && !result.isSuccess) return;
        File('${dir.path}/source.png').writeAsBytesSync(converted);
      });
  }

  /// Finder 열기 결과를 등록한다.
  void registerOpen([CommandResult? result]) =>
      runner.on(buildOpenKey(box.root), result ?? buildOkResult());

  /// sips 호출 수.
  int countSipsCalls() => runner.calls
      .where((FakeCall call) => call.key.startsWith('/usr/bin/sips '))
      .length;

  /// Finder 열기 호출 수.
  int countOpenCalls() =>
      runner.countCalls(RunMode.stream, buildOpenKey(box.root));

  /// 위저드를 돌린다.
  Future<int> run() => runWizard(
    WizardContext(
      projectRoot: box.root,
      runner: runner,
      terminal: RedactingTerminal(screen, log.redactor, log),
      redactor: log.redactor,
      log: log,
      rest: FakeRestClient(),
      session: session,
      homeDirectory: box.home,
      random: Random(fixedTestRandomSeed),
      now: () => fixedTestNow,
    ),
    <Step>[
      providersStandIn,
      AppIconStep(enabledProviders: enabled, kitDefaultDigests: kitDigests),
    ],
  );
}

void main() {
  late _Sandbox box;

  setUp(() => box = _Sandbox());
  tearDown(() => box.dispose());

  test('T-28-ICON-01: 킷 기본 → 원본 하나 → 홈 화면 · adaptive · 콘솔 · 표식 → '
      '다시 판정 ✓', () async {
    final Map<String, String> kit = writeKitDefaultHomeIcons(box.root);
    final Uint8List sourceBytes = buildOpaqueRgbaIconPng();
    final String source = box.writeHomeFile(
      'My Logos/app icon.png',
      sourceBytes,
    );
    final h = _Harness(box, <String?>[
      '1',
      '${source.replaceAll(' ', r'\ ')} ',
    ], kitDigests: kit)..registerDirty();
    h
      ..registerProbe(source)
      ..registerConvert(source, sourceBytes)
      ..registerOpen();

    final int code = await h.run();

    expect(code, wizardExitDone);
    expect(h.output, contains('  ✗ 앱 아이콘 — 킷 기본 아이콘입니다 — 원본 이미지를 묻습니다'));
    expect(h.output, contains(threeChoiceLines));
    expect(h.output, contains(AppIconStep.sourceGuide));
    expect(
      h.screen.asks.where((String q) => q == AppIconStep.sourceQuestion),
      hasLength(1),
    );
    expect(h.screen.asks.where((String q) => q.startsWith('배경색')), isEmpty);
    expect(h.isWorkDirectoryAtEffect, <bool>[true]);
    expect(h.runner.countCalls(RunMode.capture, buildDirtyKey()), 1);

    final img.Image filled = buildExpectedFilled(sourceBytes);
    final Uint8List ios1024 = box.repoFile(ios1024Path).readAsBytesSync();
    expect(ios1024, encodeSquareIcon(filled, 1024));
    final PngHeader? header = readPngHeader(ios1024);
    expect(header?.width, 1024);
    expect(header?.colorType, 2);
    for (final HomeIconFile file in homeIconFiles) {
      final Uint8List bytes = box.repoFile(file.relativePath).readAsBytesSync();
      expect(
        bytes,
        encodeSquareIcon(filled, file.side),
        reason: file.side.toString(),
      );
      expect(digestOf(bytes), isNot(kit[file.relativePath]));
    }
    for (final AdaptiveDensity density in adaptiveDensities) {
      final Uint8List bytes = box
          .repoFile(density.foregroundPath)
          .readAsBytesSync();
      expect(readPngHeader(bytes)?.width, density.canvasSide);
      expect(readPngHeader(bytes)?.colorType, 6);
    }
    expect(
      box.repoFile(adaptiveDensities.last.foregroundPath).readAsBytesSync(),
      encodeAdaptiveForeground(
        filled,
        canvasSide: 432,
        logoDp: paintedForegroundDp,
      ),
    );
    expect(
      box.repoFile(adaptiveIconXmlPath).readAsStringSync(),
      buildAdaptiveIconXml(),
    );
    expect(
      box.repoFile(adaptiveBackgroundPath).readAsStringSync(),
      buildAdaptiveBackgroundXml(findPaintedBackgroundRgb(filled)),
    );
    final IconSpec kakao = findIconSpec('kakao')!;
    expect(
      box.repoFile(kakao.relativePath).readAsBytesSync(),
      encodeSquareIcon(filled, 128),
    );
    expect(
      box.repoFile(homeIconMarkerPath).readAsStringSync().trim(),
      digestOf(ios1024),
    );
    expect(Directory('${box.root}/$iconWorkDirectory').existsSync(), isFalse);
    expect(h.output, contains('── ${AppIconStep.summaryTitle} ──'));
    expect(
      h.output,
      contains(
        '  ✓ 앱 아이콘 — 내 아이콘 · Kakao 콘솔용 1개 · 바꾸려면: ./setup.sh --app-icon',
      ),
    );
    expect(h.countOpenCalls(), 1);
    expect(h.output, isNot(contains(box.home)));
  });

  test('T-28-ICON-02: 쓰기 대상에 미커밋 변경 · 추적 안 된 파일 → 원본 질문 0 · '
      'sips 0 · 쓰기 0', () async {
    final Map<String, String> kit = writeKitDefaultHomeIcons(box.root);
    final Map<String, List<int>> before = box.readHomeIcons();
    final String foreground = adaptiveDensities.last.foregroundPath;
    final h = _Harness(box, <String?>['1', '2'], kitDigests: kit)
      ..registerDirty(' M $ios1024Path\n?? $foreground\n');

    final int code = await h.run();

    expect(code, wizardExitStopped);
    expect(h.screen.asks, isNot(contains(AppIconStep.sourceQuestion)));
    expect(h.countSipsCalls(), 0);
    expect(h.countOpenCalls(), 0);
    expect(h.output, contains(AppIconStep.dirtyReason));
    expect(h.lines, contains('    $ios1024Path'));
    expect(h.lines, contains('    $foreground'));
    expect(box.readHomeIcons(), before);
    for (final String path in listAdaptiveFilePaths()) {
      expect(box.repoFile(path).existsSync(), isFalse, reason: path);
    }
    expect(Directory(box.iconsPath).existsSync(), isFalse);
  });

  group('명령 · 파서 · 원본 규격', () {
    test('변환 · 열기 · 크기 읽기 명령', () {
      const root = '/repo';
      final Command convert = AppIconStep.buildConvertCommand(
        '/x/a b.png',
        '/repo/$iconWorkDirectory/source.png',
        display: '~/a b.png',
      );
      expect(convert.executable, '/usr/bin/sips');
      expect(convert.arguments, <String>[
        '-s',
        'format',
        'png',
        '-m',
        srgbProfilePath,
        '/x/a b.png',
        '--out',
        '/repo/$iconWorkDirectory/source.png',
      ]);
      expect(convert.arguments, isNot(contains('-z')));
      expect(convert.render(), contains("'~/a b.png'"));
      expect(convert.render(), contains('$iconWorkDirectory/source.png'));
      final Command open = AppIconStep.buildOpenCommand(root);
      expect(open.executable, '/usr/bin/open');
      expect(open.arguments, <String>['/repo/.setup/icons']);
      expect(open.render(), 'open .setup/icons');
      final Command probe = AppIconStep.buildProbeCommand('/x/a b.png');
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

    test('크기 읽기 세 모양', () {
      expect(
        AppIconStep.parseProbe(buildProbeResult('/x/logo.png', 1024, 1024)),
        (width: 1024, height: 1024, format: 'png'),
      );
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

    test('쓰기 대상 = 홈 화면 20장 · adaptive 7개', () {
      expect(AppIconStep.listWritePaths(), <String>[
        for (final HomeIconFile file in homeIconFiles) file.relativePath,
        ...listAdaptiveFilePaths(),
      ]);
    });

    test('⌘⇧G 안내 줄은 받은 경로를 그대로 넣는다', () {
      expect(
        AppIconStep.buildUploadGuide('/Users/kit-user/dev/my_app/.setup/icons'),
        '브라우저의 파일 선택 창에서 ⌘⇧G 로 /Users/kit-user/dev/my_app/.setup/icons '
        '경로를 붙여 넣거나 열린 Finder 창에서 끌어다 놓으세요',
      );
    });
  });
}
