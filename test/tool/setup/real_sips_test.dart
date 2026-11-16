/// 실제 macOS sips 로 앱 아이콘 단계를 돌리는 호스트 검사 — sips 가 없으면
/// 건너뛴다 · 쓰기는 시스템 임시 디렉터리뿐.
///
/// 시험 실행기는 실행 파일이 `/usr/bin/sips` 인 명령만 실제 프로세스로 넘기고,
/// `/usr/bin/open` 은 실행하지 않고 호출만 센다. 쓰기 전 미커밋 검사 git 명령은
/// 실행하지 않고 빈 성공 결과로 답한다. 그 밖의 실행 파일은 [StateError] 다.
/// 원본 PNG 는 시험이 `package:image` 로 만들고, JPEG · HEIC · Display P3
/// 원본은 그 PNG 를 시험이 실제 sips 로 바꿔 만든다.
///
/// 환경 변수 `SETUP_ICON_SIPS_KEEP` 이 `1` 이면 작업 루트를
/// `<시스템 임시 디렉터리>/setup_icon_sips_keep` 로 두고 끝나도 지우지 않는다 —
/// 만든 아이콘 · 화면 출력 · `summary.txt` 요약 줄을 셸 단계가 옮겨 남긴다.
library;

import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:image/image.dart' as img;
import 'package:test/test.dart';

import '../../../tool/setup/command_runner.dart';
import '../../../tool/setup/git_tree.dart';
import '../../../tool/setup/icons/home_icon_specs.dart';
import '../../../tool/setup/log_sink.dart';
import '../../../tool/setup/providers/icon_specs.dart';
import '../../../tool/setup/redactor.dart';
import '../../../tool/setup/step.dart';
import '../../../tool/setup/steps/app_icon_step.dart';
import '../../../tool/setup/terminal.dart';
import '../../../tool/setup/wizard.dart';
import 'fake_rest_client.dart';
import 'fakes.dart';
import 'home_icon_fixture.dart';

/// 실제로 부르는 sips 실행 파일.
const String sipsPath = '/usr/bin/sips';

/// 실행하지 않고 호출만 세는 Finder 열기 실행 파일.
const String openPath = '/usr/bin/open';

/// 보존 모드를 켜는 환경 변수 이름.
const String keepEnvironmentName = 'SETUP_ICON_SIPS_KEEP';

/// 보존 모드 작업 루트의 이름(시스템 임시 디렉터리 아래).
const String keepDirectoryName = 'setup_icon_sips_keep';

/// 원본 이미지 파일 이름 앞부분(공백 포함 — 끌어다 놓기 escape 를 밟는다).
const String sourceBaseName = 'logo 1024';

/// 시험이 따로 다시 읽은 이미지 값.
typedef MeasuredImage = ({int width, int height, String format, String alpha});

/// [path] 이미지를 실제 sips 로 다시 읽는다(단계와 독립).
MeasuredImage measureImage(String path) {
  final ProcessResult result = Process.runSync(sipsPath, <String>[
    '-g',
    'pixelWidth',
    '-g',
    'pixelHeight',
    '-g',
    'format',
    '-g',
    'hasAlpha',
    path,
  ]);
  expect(result.exitCode, 0, reason: '$path\n${result.stderr}');
  final stdout = '${result.stdout}';
  String readValue(String key) =>
      RegExp(
        '^\\s*$key:\\s*(\\S+)\\s*\$',
        multiLine: true,
      ).firstMatch(stdout)?.group(1) ??
      '';
  return (
    width: int.tryParse(readValue('pixelWidth')) ?? -1,
    height: int.tryParse(readValue('pixelHeight')) ?? -1,
    format: readValue('format'),
    alpha: readValue('hasAlpha'),
  );
}

/// 실제 sips 만 실행하고 Finder 열기 · 미커밋 검사 · 추적 파일 대조는 세기만
/// 하는 실행기.
final class _RealSipsRunner implements CommandRunner {
  _RealSipsRunner(this._root, Terminal terminal, LogSink log)
    : _real = ProcessCommandRunner(terminal, log: log);

  /// 저장소 root — 추적 파일 대조의 키를 그 순간의 디스크 상태로 만든다.
  final String _root;

  final ProcessCommandRunner _real;

  /// 미커밋 검사 git 명령의 키 — 빈 성공 결과(변경 없음)로 답한다.
  static final String _uncommittedKey = FakeCommandRunner.buildKey(
    buildUncommittedFilesCommand(AppIconStep.listWritePaths()),
  );

  /// 단계가 부른 명령(순서대로 · 실행 여부 무관).
  final List<Command> calls = <Command>[];

  /// 실제 프로세스로 넘긴 실행 파일(순서대로).
  final List<String> executedPaths = <String>[];

  /// 실행하지 않고 센 Finder 열기 호출 수.
  int openCount = 0;

  /// 실행하지 않고 빈 결과로 답한 미커밋 검사 수.
  int uncommittedCount = 0;

  /// 실행하지 않고 지금 파일을 모두 추적 파일로 답한 대조 수.
  int trackedCount = 0;

  /// [command] 가 sips 가 아니면 [StateError] 를 던지고, 맞으면 기록한다.
  Command _requireSips(Command command) {
    if (command.executable != sipsPath) {
      throw StateError('실제 sips 시험이 허락하지 않은 명령: ${command.render()}');
    }
    executedPaths.add(command.executable);
    return command;
  }

  @override
  Future<CommandResult> capture(Command command) async {
    calls.add(command);
    if (FakeCommandRunner.buildKey(command) == _uncommittedKey) {
      uncommittedCount++;
      return const CommandResult(0, '', '');
    }
    final ({String key, CommandResult result})? tracked =
        buildTrackedTargetsAnswer(_root);
    if (tracked != null && FakeCommandRunner.buildKey(command) == tracked.key) {
      trackedCount++;
      return tracked.result;
    }
    return await _real.capture(_requireSips(command));
  }

  @override
  Future<int> interactive(Command command) async {
    calls.add(command);
    throw StateError('실제 sips 시험은 대화형 실행을 허락하지 않는다: ${command.render()}');
  }

  @override
  Future<CommandResult> stream(Command command) async {
    calls.add(command);
    if (command.executable == openPath) {
      openCount++;
      return const CommandResult(0, '', '');
    }
    return await _real.stream(_requireSips(command));
  }
}

/// 한 케이스의 작업 디렉터리 — 원본 폴더 · 저장소 · 홈.
final class _CaseDir {
  _CaseDir(Directory workRoot, this.name) : path = '${workRoot.path}/$name' {
    Directory(repo).createSync(recursive: true);
    Directory(home).createSync(recursive: true);
    Directory(sourceDir).createSync(recursive: true);
  }

  /// 케이스 이름(`kit` 등).
  final String name;

  /// 케이스 디렉터리 절대 경로.
  final String path;

  /// 원본 이미지를 두는 폴더(이름에 공백).
  String get sourceDir => '$path/src dir';

  /// 저장소 root.
  String get repo => '$path/repo';

  /// 사용자 홈.
  String get home => '$path/home';
}

/// 한 번의 위저드 실행 결과.
typedef _RunResult = ({int code, String output, _RealSipsRunner runner});

/// [dir] 저장소에서 로그인 수단 대역 + 앱 아이콘 단계를 [inputs] 로 돌린다.
///
/// 앱 아이콘 단계는 켠 수단 [enabledProviders] · 킷 기본 지문 [kitDigests] 로
/// 만든다. 화면 출력은 케이스 디렉터리의 `screen.txt` 에도 남긴다.
Future<_RunResult> _runIconStep(
  _CaseDir dir,
  List<String?> inputs, {
  required Set<String> enabledProviders,
  required Map<String, String> kitDigests,
}) async {
  final screen = ScriptedTerminal(inputs);
  final log = MemoryLogSink(Redactor());
  final terminal = RedactingTerminal(screen, log.redactor, log);
  final runner = _RealSipsRunner(dir.repo, terminal, log);
  final int code = await runWizard(
    WizardContext(
      projectRoot: dir.repo,
      runner: runner,
      terminal: terminal,
      redactor: log.redactor,
      log: log,
      rest: FakeRestClient(),
      homeDirectory: dir.home,
      random: Random(fixedTestRandomSeed),
      now: () => fixedTestNow,
    ),
    <Step>[
      providersStandIn,
      AppIconStep(
        enabledProviders: enabledProviders,
        kitDefaultDigests: kitDigests,
      ),
    ],
  );
  final output = screen.output.toString();
  File('${dir.path}/screen.txt').writeAsStringSync(output);
  return (code: code, output: output, runner: runner);
}

/// 원본을 Display P3 로 맞출 때 쓰는 macOS 기본 프로파일.
const String displayP3ProfilePath =
    '/System/Library/ColorSync/Profiles/Display P3.icc';

/// Display P3 시험 원본 가운데 색(sRGB) — `#F2B134`.
const List<int> p3SourceCenterRgb = <int>[242, 177, 52];

/// 실제 sips 로 [input] 을 [format] 형식의 [output] 으로 바꾼다(시험 원본 만들기).
void convertWithSips(String input, String output, String format) {
  final ProcessResult result = Process.runSync(sipsPath, <String>[
    '-s',
    'format',
    format,
    input,
    '--out',
    output,
  ]);
  expect(result.exitCode, 0, reason: '$output\n${result.stderr}');
}

/// [path] PNG 의 ([x], [y]) 픽셀 RGB.
List<int> readPixelRgb(String path, int x, int y) {
  final img.Image image = img.decodePng(File(path).readAsBytesSync())!;
  final img.Pixel pixel = image.getPixel(x, y);
  return <int>[pixel.r.toInt(), pixel.g.toInt(), pixel.b.toInt()];
}

/// 한 변 [side] 의 불투명 RGB PNG — 가장자리 띠는 파랑, 가운데는 [centerRgb].
List<int> buildCenterColorPng(int side, List<int> centerRgb) {
  final image = img.Image(width: side, height: side);
  final int band = side ~/ 8;
  for (var y = 0; y < side; y++) {
    for (var x = 0; x < side; x++) {
      final bool isEdge =
          x < band || y < band || x >= side - band || y >= side - band;
      if (isEdge) {
        image.setPixelRgb(x, y, 30, 90, 160);
      } else {
        image.setPixelRgb(x, y, centerRgb[0], centerRgb[1], centerRgb[2]);
      }
    }
  }
  return img.encodePng(image);
}

/// 터미널에 끌어다 놓은 모양의 답 — 공백 앞 백슬래시 · 끝 공백 하나.
String buildDroppedAnswer(String path) => '${path.replaceAll(' ', r'\ ')} ';

void main() {
  group(
    '실제 sips',
    skip: File(sipsPath).existsSync() ? false : '$sipsPath 가 없어 건너뜁니다',
    () {
      late Directory workRoot;
      late bool isKeep;

      setUpAll(() {
        isKeep = Platform.environment[keepEnvironmentName] == '1';
        if (isKeep) {
          workRoot = Directory(
            '${Directory.systemTemp.path}/$keepDirectoryName',
          );
          if (workRoot.existsSync()) workRoot.deleteSync(recursive: true);
          workRoot.createSync(recursive: true);
        } else {
          workRoot = Directory.systemTemp.createTempSync('setup_icon_sips_');
        }
      });

      tearDownAll(() {
        if (!isKeep) workRoot.deleteSync(recursive: true);
      });

      /// 요약 줄 [line] 을 작업 루트의 `summary.txt` 에 덧붙인다.
      void appendSummary(String line) => File(
        '${workRoot.path}/summary.txt',
      ).writeAsStringSync('$line\n', mode: FileMode.append);

      /// [dir] 저장소의 [relativePath] PNG 를 실제 sips 로 다시 읽어 한 변
      /// [side] · 알파 [alpha] 를 확인하고 요약 줄을 남긴다.
      void expectPng(
        _CaseDir dir,
        String relativePath, {
        required int side,
        required String alpha,
      }) {
        final out = '${dir.repo}/$relativePath';
        final MeasuredImage image = measureImage(out);
        appendSummary(
          'OUT ${dir.name} $relativePath '
          'size=${image.width}x${image.height} '
          'bytes=${File(out).lengthSync()} '
          'format=${image.format} alpha=${image.alpha}',
        );
        expect(image.width, side, reason: relativePath);
        expect(image.height, side, reason: relativePath);
        expect(image.format, 'png', reason: relativePath);
        expect(image.alpha, alpha, reason: relativePath);
      }

      test('T-28-SIPS-01: 킷 기본 저장소에서 공백 든 이름의 알파 채널 PNG 원본을 '
          '끌어다 놓으면 실제 sips 변환 뒤 홈 화면 · adaptive · Kakao 콘솔 '
          '아이콘 · 표식이 생기고 iOS 1024 는 알파가 없다', () async {
        final dir = _CaseDir(workRoot, 'kit');
        final Map<String, String> kitDigests = writeKitDefaultHomeIcons(
          dir.repo,
        );
        final source = '${dir.sourceDir}/$sourceBaseName.png';
        final List<int> sourceBytes = buildOpaqueRgbaIconPng();
        File(source).writeAsBytesSync(sourceBytes);

        final _RunResult run = await _runIconStep(
          dir,
          <String?>['1', buildDroppedAnswer(source)],
          enabledProviders: <String>{'kakao'},
          kitDigests: kitDigests,
        );

        expect(run.code, wizardExitDone, reason: run.output);
        expect(
          run.output,
          contains(
            '  ✓ ${AppIconStep.stepTitle} — 내 아이콘 · Kakao 콘솔용 1개 · '
            '${AppIconStep.replaceHint}',
          ),
          reason: run.output,
        );
        // 불투명 원본 — 배경색을 묻지 않는다.
        expect(run.output, isNot(contains(AppIconStep.backgroundQuestion)));
        for (final HomeIconFile file in homeIconFiles) {
          expectPng(dir, file.relativePath, side: file.side, alpha: 'no');
          expect(
            sha256
                .convert(
                  File('${dir.repo}/${file.relativePath}').readAsBytesSync(),
                )
                .toString(),
            isNot(kitDigests[file.relativePath]),
            reason: file.relativePath,
          );
        }
        expect(
          homeIconFiles.where(
            (HomeIconFile file) =>
                file.relativePath.startsWith(iosAppIconDirectory),
          ),
          hasLength(15),
        );
        expect(
          homeIconFiles.where(
            (HomeIconFile file) =>
                file.relativePath.startsWith(androidResDirectory),
          ),
          hasLength(5),
        );
        for (final AdaptiveDensity density in adaptiveDensities) {
          expectPng(
            dir,
            density.foregroundPath,
            side: density.canvasSide,
            alpha: 'yes',
          );
        }
        expect(adaptiveDensities, hasLength(5));
        expect(
          File('${dir.repo}/$adaptiveIconXmlPath').readAsStringSync(),
          buildAdaptiveIconXml(),
        );
        expect(
          File('${dir.repo}/$adaptiveBackgroundPath').existsSync(),
          isTrue,
        );
        final IconSpec kakao = findIconSpec('kakao')!;
        expectPng(dir, kakao.relativePath, side: kakao.side, alpha: 'no');
        expect(kakao.side, 128);
        expect(
          File('${dir.repo}/${kakao.relativePath}').lengthSync(),
          lessThanOrEqualTo(kakao.maxBytes),
        );
        final MeasuredImage ios1024 = measureImage('${dir.repo}/$ios1024Path');
        expect(ios1024.width, 1024);
        expect(ios1024.alpha, 'no');
        expect(
          File('${dir.repo}/$homeIconMarkerPath').readAsStringSync(),
          buildHomeIconMarkerText(dir.repo, const <String>['kakao']),
        );
        expect(
          Directory('${dir.repo}/$iconWorkDirectory').existsSync(),
          isFalse,
        );
        expect(File(source).readAsBytesSync(), sourceBytes);
        expect(run.runner.uncommittedCount, 1);
        expect(run.runner.trackedCount, 1);
        expect(run.runner.openCount, 1);
        expect(run.runner.executedPaths, isNotEmpty);
        expect(run.runner.executedPaths, everyElement(sipsPath));
        expect(
          run.runner.calls.where(
            (Command c) =>
                c.executable == sipsPath && c.arguments.contains('--out'),
          ),
          hasLength(1),
        );
      });

      /// [dir] 의 iOS 1024 를 실제 sips 로 다시 읽어 알파가 없음을 확인한다.
      void expectIos1024WithoutAlpha(_CaseDir dir) {
        final MeasuredImage ios1024 = measureImage('${dir.repo}/$ios1024Path');
        expect(ios1024.width, 1024);
        expect(ios1024.height, 1024);
        expect(ios1024.alpha, 'no');
      }

      test('T-28-SIPS-02: 투명 원본 → 배경색 Enter = 흰색 · iOS 1024 알파 없음 · '
          'adaptive 배경 흰색 · 투명하던 모서리는 흰색', () async {
        final dir = _CaseDir(workRoot, 'transparent');
        final Map<String, String> kitDigests = writeKitDefaultHomeIcons(
          dir.repo,
        );
        final source = '${dir.sourceDir}/$sourceBaseName.png';
        File(source).writeAsBytesSync(buildTransparentLogoPng());
        expect(measureImage(source).alpha, 'yes');

        final _RunResult run = await _runIconStep(
          dir,
          <String?>['1', buildDroppedAnswer(source), ''],
          enabledProviders: const <String>{},
          kitDigests: kitDigests,
        );

        expect(run.code, wizardExitDone, reason: run.output);
        expect(run.output, contains(AppIconStep.backgroundQuestion));
        expectIos1024WithoutAlpha(dir);
        expect(
          File('${dir.repo}/$adaptiveBackgroundPath').readAsStringSync(),
          buildAdaptiveBackgroundXml(0xFFFFFF),
        );
        expect(readPixelRgb('${dir.repo}/$ios1024Path', 0, 0), <int>[
          255,
          255,
          255,
        ]);
        appendSummary('OUT transparent corner=white');
      });

      test('T-28-SIPS-03: Display P3 로 맞춘 원본 → iOS 1024 가운데가 원래 sRGB '
          '값과 채널 차 2 이하', () async {
        final dir = _CaseDir(workRoot, 'display-p3');
        final Map<String, String> kitDigests = writeKitDefaultHomeIcons(
          dir.repo,
        );
        final srgb = '${dir.sourceDir}/srgb.png';
        File(
          srgb,
        ).writeAsBytesSync(buildCenterColorPng(1024, p3SourceCenterRgb));
        final source = '${dir.sourceDir}/$sourceBaseName p3.png';
        final ProcessResult matched = Process.runSync(sipsPath, <String>[
          '-m',
          displayP3ProfilePath,
          srgb,
          '--out',
          source,
        ]);
        expect(matched.exitCode, 0, reason: '${matched.stderr}');
        final List<int> p3Center = readPixelRgb(source, 512, 512);
        expect(p3Center, isNot(p3SourceCenterRgb));
        expect(readPixelRgb(srgb, 512, 512), p3SourceCenterRgb);

        final _RunResult run = await _runIconStep(
          dir,
          <String?>['1', buildDroppedAnswer(source)],
          enabledProviders: const <String>{},
          kitDigests: kitDigests,
        );

        expect(run.code, wizardExitDone, reason: run.output);
        expectIos1024WithoutAlpha(dir);
        final List<int> center = readPixelRgb(
          '${dir.repo}/$ios1024Path',
          512,
          512,
        );
        appendSummary('OUT display-p3 p3=$p3Center center=$center');
        for (var channel = 0; channel < 3; channel++) {
          expect(
            (center[channel] - p3SourceCenterRgb[channel]).abs(),
            lessThanOrEqualTo(2),
            reason: 'channel $channel: $center',
          );
        }
      });

      test('T-28-SIPS-04: 실제 sips 로 만든 JPEG 원본 → 배경색 질문 없이 홈 화면 '
          '20장 · adaptive 전경 5 · iOS 1024 알파 없음', () async {
        final dir = _CaseDir(workRoot, 'jpeg');
        final Map<String, String> kitDigests = writeKitDefaultHomeIcons(
          dir.repo,
        );
        final png = '${dir.sourceDir}/opaque.png';
        File(png).writeAsBytesSync(buildOpaqueRgbIconPng());
        final source = '${dir.sourceDir}/$sourceBaseName.jpg';
        convertWithSips(png, source, 'jpeg');
        expect(measureImage(source).format, 'jpeg');

        final _RunResult run = await _runIconStep(
          dir,
          <String?>['1', buildDroppedAnswer(source)],
          enabledProviders: const <String>{},
          kitDigests: kitDigests,
        );

        expect(run.code, wizardExitDone, reason: run.output);
        expect(run.output, isNot(contains(AppIconStep.backgroundQuestion)));
        for (final HomeIconFile file in homeIconFiles) {
          expectPng(dir, file.relativePath, side: file.side, alpha: 'no');
        }
        for (final AdaptiveDensity density in adaptiveDensities) {
          expectPng(
            dir,
            density.foregroundPath,
            side: density.canvasSide,
            alpha: 'yes',
          );
        }
        expectIos1024WithoutAlpha(dir);
      });

      test('T-28-SIPS-05: 투명 로고를 실제 sips 로 바꾼 HEIC 원본(알파 유지) → '
          '배경색 Enter = 흰색 · iOS 1024 알파 없음', () async {
        final dir = _CaseDir(workRoot, 'heic');
        final Map<String, String> kitDigests = writeKitDefaultHomeIcons(
          dir.repo,
        );
        final png = '${dir.sourceDir}/logo.png';
        File(png).writeAsBytesSync(buildTransparentLogoPng());
        final source = '${dir.sourceDir}/$sourceBaseName.heic';
        convertWithSips(png, source, 'heic');
        final MeasuredImage heic = measureImage(source);
        expect(heic.format, 'heic');
        expect(heic.alpha, 'yes');

        final _RunResult run = await _runIconStep(
          dir,
          <String?>['1', buildDroppedAnswer(source), ''],
          enabledProviders: const <String>{},
          kitDigests: kitDigests,
        );

        expect(run.code, wizardExitDone, reason: run.output);
        expect(run.output, contains(AppIconStep.backgroundQuestion));
        expectIos1024WithoutAlpha(dir);
        expect(
          File('${dir.repo}/$adaptiveBackgroundPath').readAsStringSync(),
          buildAdaptiveBackgroundXml(0xFFFFFF),
        );
      });

      test('T-28-SIPS-06: 비정사각 · 1024 미만 원본 → 실제 sips 가 읽은 크기와 '
          '함께 거절 · 변환 0 · 홈 화면 그대로', () async {
        final dir = _CaseDir(workRoot, 'reject');
        final Map<String, String> kitDigests = writeKitDefaultHomeIcons(
          dir.repo,
        );
        final wide = '${dir.sourceDir}/wide 1920.png';
        File(wide).writeAsBytesSync(
          img.encodePng(img.Image(width: 1920, height: 1080, numChannels: 4)),
        );
        final small = '${dir.sourceDir}/small 512.png';
        File(small).writeAsBytesSync(
          img.encodePng(img.Image(width: 512, height: 512, numChannels: 4)),
        );

        final _RunResult run = await _runIconStep(
          dir,
          <String?>[
            '1',
            buildDroppedAnswer(wide),
            buildDroppedAnswer(small),
            '',
          ],
          enabledProviders: const <String>{'kakao'},
          kitDigests: kitDigests,
        );

        expect(run.code, wizardExitDone, reason: run.output);
        final List<String> lines = run.output.split('\n');
        final int wideAt = lines.indexOf(
          '  ${AppIconStep.notSquareReason}1920x1080',
        );
        final int smallAt = lines.indexOf(
          '  ${AppIconStep.tooSmallReason}512x512',
        );
        expect(wideAt, greaterThan(0), reason: run.output);
        expect(smallAt, greaterThan(wideAt), reason: run.output);
        expect(lines, contains('  ✗ ${AppIconStep.stepTitle} — 지금 안 함'));
        final List<Command> sipsCalls = run.runner.calls
            .where((Command c) => c.executable == sipsPath)
            .toList();
        expect(sipsCalls, hasLength(2));
        expect(
          sipsCalls.where((Command c) => c.arguments.contains('--out')),
          isEmpty,
        );
        expect(run.runner.openCount, 0);
        for (final HomeIconFile file in homeIconFiles) {
          expect(
            sha256
                .convert(
                  File('${dir.repo}/${file.relativePath}').readAsBytesSync(),
                )
                .toString(),
            kitDigests[file.relativePath],
            reason: file.relativePath,
          );
        }
        for (final String path in listAdaptiveFilePaths()) {
          expect(File('${dir.repo}/$path').existsSync(), isFalse, reason: path);
        }
      });
    },
  );
}
