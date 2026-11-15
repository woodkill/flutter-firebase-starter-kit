/// 실제 macOS sips 로 앱 아이콘 단계를 돌리는 호스트 검사 — sips 가 없으면
/// 건너뛴다 · 쓰기는 시스템 임시 디렉터리뿐.
///
/// 시험 실행기는 실행 파일이 `/usr/bin/sips` 인 명령만 실제 프로세스로 넘기고,
/// `/usr/bin/open` 은 실행하지 않고 호출만 센다. 쓰기 전 미커밋 검사 git 명령은
/// 실행하지 않고 빈 성공 결과로 답한다. 그 밖의 실행 파일은 [StateError] 다.
/// 원본 PNG 는 시험이 `package:image` 로 만든다.
///
/// 환경 변수 `SETUP_ICON_SIPS_KEEP` 이 `1` 이면 작업 루트를
/// `<시스템 임시 디렉터리>/setup_icon_sips_keep` 로 두고 끝나도 지우지 않는다 —
/// 만든 아이콘 · 화면 출력 · `summary.txt` 요약 줄을 셸 단계가 옮겨 남긴다.
library;

import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
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

/// 실제 sips 만 실행하고 Finder 열기 · 미커밋 검사는 세기만 하는 실행기.
final class _RealSipsRunner implements CommandRunner {
  _RealSipsRunner(Terminal terminal, LogSink log)
    : _real = ProcessCommandRunner(terminal, log: log);

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
          File('${dir.repo}/$homeIconMarkerPath').readAsStringSync().trim(),
          readHomeIconDigest(dir.repo),
        );
        expect(
          Directory('${dir.repo}/$iconWorkDirectory').existsSync(),
          isFalse,
        );
        expect(File(source).readAsBytesSync(), sourceBytes);
        expect(run.runner.uncommittedCount, 1);
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
    },
  );
}
