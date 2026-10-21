/// 실제 macOS sips 로 앱 아이콘 단계를 돌리는 호스트 검사 — sips 가 없으면
/// 건너뛴다 · 쓰기는 시스템 임시 디렉터리뿐.
///
/// 시험 실행기는 실행 파일이 `/usr/bin/sips` 인 명령만 실제 프로세스로 넘기고,
/// `/usr/bin/open` 은 실행하지 않고 호출만 센다. 그 밖의 실행 파일은
/// [StateError] 다. 원본 PNG 는 시험이 순수 Dart 로 만든다.
///
/// 환경 변수 `SETUP_ICON_SIPS_KEEP` 이 `1` 이면 작업 루트를
/// `<시스템 임시 디렉터리>/setup_icon_sips_keep` 로 두고 끝나도 지우지 않는다 —
/// 만든 아이콘 · 화면 출력 · `summary.txt` 요약 줄을 셸 단계가 옮겨 남긴다.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:test/test.dart';

import '../../../tool/setup/command_runner.dart';
import '../../../tool/setup/log_sink.dart';
import '../../../tool/setup/providers/icon_specs.dart';
import '../../../tool/setup/redactor.dart';
import '../../../tool/setup/step.dart';
import '../../../tool/setup/steps/app_icon_step.dart';
import '../../../tool/setup/terminal.dart';
import '../../../tool/setup/wizard.dart';
import 'fake_rest_client.dart';
import 'fakes.dart';

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

/// CRC32 표(다항식 0xEDB88320).
final List<int> _crcTable = List<int>.generate(256, (int n) {
  var c = n;
  for (var k = 0; k < 8; k++) {
    c = (c & 1) != 0 ? 0xEDB88320 ^ (c >> 1) : c >> 1;
  }
  return c;
});

/// [bytes] 의 CRC32 를 계산한다.
int _computeCrc(List<int> bytes) {
  var c = 0xFFFFFFFF;
  for (final b in bytes) {
    c = _crcTable[(c ^ b) & 0xFF] ^ (c >> 8);
  }
  return c ^ 0xFFFFFFFF;
}

/// [value] 를 4바이트 big-endian 으로 쓴다.
List<int> _encodeUint32(int value) => <int>[
  (value >> 24) & 0xFF,
  (value >> 16) & 0xFF,
  (value >> 8) & 0xFF,
  value & 0xFF,
];

/// PNG 청크 하나(길이 · 종류 · 내용 · CRC)를 [out] 에 덧붙인다.
void _addChunk(BytesBuilder out, String type, List<int> data) {
  final List<int> typeBytes = ascii.encode(type);
  out
    ..add(_encodeUint32(data.length))
    ..add(typeBytes)
    ..add(data)
    ..add(_encodeUint32(_computeCrc(<int>[...typeBytes, ...data])));
}

/// [path] 에 [width]x[height] RGBA 8비트 PNG 를 쓴다.
///
/// 테두리는 완전 투명이고 가운데 원만 불투명하다 — 알파 유지를 확인할 수 있다.
void writeRgbaPng(String path, int width, int height) {
  final rowLength = width * 4 + 1;
  final raw = Uint8List(rowLength * height);
  final double radius = min(width, height) * 0.3;
  final double cx = width / 2;
  final double cy = height / 2;
  for (var y = 0; y < height; y++) {
    final int row = y * rowLength;
    // 줄 머리 필터 바이트 0(None) — 나머지는 RGBA 그대로.
    raw[row] = 0;
    for (var x = 0; x < width; x++) {
      final double dx = x + 0.5 - cx;
      final double dy = y + 0.5 - cy;
      if (dx * dx + dy * dy > radius * radius) continue;
      final int at = row + 1 + x * 4;
      raw[at] = 30;
      raw[at + 1] = 120;
      raw[at + 2] = 220;
      raw[at + 3] = 255;
    }
  }
  final header = <int>[
    ..._encodeUint32(width),
    ..._encodeUint32(height),
    8, // 비트 깊이
    6, // 색 형식 RGBA
    0, // 압축
    0, // 필터
    0, // 인터레이스 없음
  ];
  final out = BytesBuilder(copy: false)
    ..add(const <int>[0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]);
  _addChunk(out, 'IHDR', header);
  _addChunk(out, 'IDAT', zlib.encode(raw));
  _addChunk(out, 'IEND', const <int>[]);
  File(path)
    ..createSync(recursive: true)
    ..writeAsBytesSync(out.takeBytes());
}

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

/// 실제 sips 만 실행하고 Finder 열기는 세기만 하는 실행기.
final class _RealSipsRunner implements CommandRunner {
  _RealSipsRunner(Terminal terminal, LogSink log)
    : _real = ProcessCommandRunner(terminal, log: log);

  final ProcessCommandRunner _real;

  /// 단계가 부른 명령(순서대로 · 실행 여부 무관).
  final List<Command> calls = <Command>[];

  /// 실제 프로세스로 넘긴 실행 파일(순서대로).
  final List<String> executedPaths = <String>[];

  /// 실행하지 않고 센 Finder 열기 호출 수.
  int openCount = 0;

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

  /// 케이스 이름(`png` 등).
  final String name;

  /// 케이스 디렉터리 절대 경로.
  final String path;

  /// 원본 이미지를 두는 폴더(이름에 공백).
  String get sourceDir => '$path/src dir';

  /// 저장소 root.
  String get repo => '$path/repo';

  /// 사용자 홈.
  String get home => '$path/home';

  /// 저장소의 아이콘 폴더 절대 경로.
  String get iconsPath => '$repo/$iconsDirectory';
}

/// 한 번의 위저드 실행 결과.
typedef _RunResult = ({int code, String output, _RealSipsRunner runner});

/// [dir] 저장소에서 로그인 수단 대역 + 앱 아이콘 단계를 [inputs] 로 돌린다.
///
/// 화면 출력은 케이스 디렉터리의 `screen.txt` 에도 남긴다.
Future<_RunResult> _runIconStep(_CaseDir dir, List<String?> inputs) async {
  final screen = ScriptedTerminal(inputs);
  final log = MemoryLogSink(Redactor());
  final terminal = RedactingTerminal(screen, log.redactor, log);
  final runner = _RealSipsRunner(terminal, log);
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
    <Step>[providersStandIn, AppIconStep(enabledProviders: allProviderTokens)],
  );
  final output = screen.output.toString();
  File('${dir.path}/screen.txt').writeAsStringSync(output);
  return (code: code, output: output, runner: runner);
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

      /// 원본 [source](sips 형식 [format]) 을 끌어다 놓기 답으로 넘겨 다섯
      /// 아이콘을 만들고, 독립 재측정으로 규격 · 알파 [alpha] 를 확인한다.
      Future<void> expectIconCase(
        _CaseDir dir,
        String source, {
        required String format,
        required String alpha,
      }) async {
        final List<int> sourceBytes = File(source).readAsBytesSync();

        final _RunResult run = await _runIconStep(dir, <String?>[
          '1',
          buildDroppedAnswer(source),
        ]);

        expect(run.code, wizardExitDone, reason: run.output);
        expect(
          run.output,
          contains('  ✓ ${AppIconStep.stepTitle} — '),
          reason: run.output,
        );
        for (final IconSpec spec in iconSpecs) {
          final out = '${dir.iconsPath}/${spec.fileName}';
          final MeasuredImage image = measureImage(out);
          final int bytes = File(out).lengthSync();
          appendSummary(
            'OUT ${dir.name} ${spec.token} '
            'size=${image.width}x${image.height} bytes=$bytes '
            'max=${spec.maxBytes} format=${image.format} alpha=${image.alpha}',
          );
          expect(image.width, spec.side, reason: spec.token);
          expect(image.height, spec.side, reason: spec.token);
          expect(image.format, 'png', reason: spec.token);
          expect(image.alpha, alpha, reason: spec.token);
          expect(bytes, lessThanOrEqualTo(spec.maxBytes), reason: spec.token);
        }
        expect(
          File(
            '${dir.iconsPath}/$sourceCopyBaseName.$format',
          ).readAsBytesSync(),
          sourceBytes,
        );
        expect(File(source).readAsBytesSync(), sourceBytes);
        expect(run.runner.openCount, 1);
        expect(run.runner.executedPaths, everyElement(sipsPath));
        expect(
          run.runner.calls.where((Command c) => c.executable == openPath),
          hasLength(1),
        );
      }

      /// [dir] 의 1024 PNG 에서 실제 sips 로 [format] 원본을 만들어 경로를
      /// 돌려준다 — 원본의 재측정 값은 작업 루트의 `sources.txt` 에 남긴다.
      String deriveSource(_CaseDir dir, String format, String extension) {
        final png = '${dir.sourceDir}/base.png';
        writeRgbaPng(png, 1024, 1024);
        final source = '${dir.sourceDir}/$sourceBaseName.$extension';
        final ProcessResult made = Process.runSync(sipsPath, <String>[
          '-s',
          'format',
          format,
          png,
          '--out',
          source,
        ]);
        expect(made.exitCode, 0, reason: '${made.stderr}');
        final MeasuredImage image = measureImage(source);
        File('${workRoot.path}/sources.txt').writeAsStringSync(
          'SRC ${dir.name} size=${image.width}x${image.height} '
          'format=${image.format} alpha=${image.alpha}\n',
          mode: FileMode.append,
        );
        expect(image.format, format);
        return source;
      }

      test('T-20.1-SIPS-01: 공백 든 PNG 원본을 끌어다 놓으면 실제 sips 가 '
          '다섯 provider 아이콘을 투명 배경 그대로 만든다', () async {
        final dir = _CaseDir(workRoot, 'png');
        final source = '${dir.sourceDir}/$sourceBaseName.png';
        writeRgbaPng(source, 1024, 1024);

        await expectIconCase(dir, source, format: 'png', alpha: 'yes');
      });

      test('T-20.1-SIPS-02: JPEG 원본도 다섯 provider 규격 PNG 가 되고 '
          '알파는 없다', () async {
        final dir = _CaseDir(workRoot, 'jpeg');
        final String source = deriveSource(dir, 'jpeg', 'jpg');

        await expectIconCase(dir, source, format: 'jpeg', alpha: 'no');
      });

      test('T-20.1-SIPS-02: HEIC 원본도 다섯 provider 규격 PNG 가 되고 '
          '투명 배경을 유지한다', () async {
        final dir = _CaseDir(workRoot, 'heic');
        final String source = deriveSource(dir, 'heic', 'heic');

        await expectIconCase(dir, source, format: 'heic', alpha: 'yes');
      });

      test('T-20.1-SIPS-03: 비정사각 · 1024 미만 원본은 실제 sips 값으로 '
          '지금 크기와 함께 거절되고 변환하지 않는다', () async {
        final dir = _CaseDir(workRoot, 'reject');
        final wide = '${dir.sourceDir}/wide 1920.png';
        final small = '${dir.sourceDir}/small 512.png';
        writeRgbaPng(wide, 1920, 1080);
        writeRgbaPng(small, 512, 512);
        final MeasuredImage wideImage = measureImage(wide);
        final MeasuredImage smallImage = measureImage(small);
        appendSummary(
          'REJECT ${dir.name} '
          'size=${wideImage.width}x${wideImage.height} reason=square',
        );
        appendSummary(
          'REJECT ${dir.name} '
          'size=${smallImage.width}x${smallImage.height} reason=small',
        );

        final _RunResult run = await _runIconStep(dir, <String?>[
          '1',
          buildDroppedAnswer(wide),
          buildDroppedAnswer(small),
          '',
        ]);

        expect(run.code, wizardExitDone, reason: run.output);
        final List<String> lines = run.output.split('\n');
        final int squareAt = lines.indexOf(
          '  ${AppIconStep.notSquareReason}1920x1080',
        );
        final int smallAt = lines.indexOf(
          '  ${AppIconStep.tooSmallReason}512x512',
        );
        expect(squareAt, greaterThanOrEqualTo(0), reason: run.output);
        expect(smallAt, greaterThan(squareAt), reason: run.output);
        expect(
          lines,
          contains('  ✗ ${AppIconStep.stepTitle} — 지금 안 함'),
          reason: run.output,
        );
        expect(Directory(dir.iconsPath).existsSync(), isFalse);
        expect(
          run.runner.calls.where((Command c) => c.arguments.contains('-z')),
          isEmpty,
        );
        expect(run.runner.executedPaths, <String>[sipsPath, sipsPath]);
        expect(run.runner.openCount, 0);
      });
    },
  );
}
