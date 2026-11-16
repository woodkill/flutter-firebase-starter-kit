/// 실제 [StdioTerminal] 입력 경계 → [RedactingTerminal] → 「앱 아이콘」 단계
/// 흐름 시험.
///
/// 터미널이 끌어다 놓은 경로를 bracketed paste 표시로 감싸 보내도 단계가 그
/// 원본을 받는지 본다. 기존 단계 시험의 가짜 터미널은 답 다듬기를 따로 구현해
/// 이 입력 경계를 거치지 않으므로, 여기서는 읽기 함수만 주입한 실제 터미널을 쓴다.
library;

import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:test/test.dart';

import '../../../tool/setup/command_runner.dart';
import '../../../tool/setup/git_tree.dart';
import '../../../tool/setup/icons/home_icon_specs.dart';
import '../../../tool/setup/redactor.dart';
import '../../../tool/setup/step.dart';
import '../../../tool/setup/steps/app_icon_step.dart';
import '../../../tool/setup/terminal.dart';
import '../../../tool/setup/wizard.dart';
import 'fake_rest_client.dart';
import 'fakes.dart';
import 'home_icon_fixture.dart';

/// 터미널이 붙여 넣거나 끌어다 놓은 글 앞에 붙이는 표시(시험 자신의 리터럴).
const String pasteStart = '\x1B[200~';

/// 터미널이 붙여 넣거나 끌어다 놓은 글 뒤에 붙이는 표시(시험 자신의 리터럴).
const String pasteEnd = '\x1B[201~';

/// 「내 아이콘」 · Kakao 콘솔 아이콘이 있는 ✓ 줄.
const String mineKakaoDoneLine =
    '  ✓ 앱 아이콘 — 내 아이콘 · Kakao 콘솔용 1개 · 바꾸려면: ./setup.sh --app-icon';

/// 홈 아래 원본 그림의 상대 경로 — 이름에 공백이 있다.
const String sourceRelativePath = 'src/logo 1024.png';

/// 터미널 끌어다 놓기처럼 [path] 의 공백 앞에 `\` 를 붙인다.
String escapeDroppedPath(String path) => path.replaceAll(' ', r'\ ');

/// 임시 저장소 · 임시 홈 한 쌍.
final class _Sandbox {
  _Sandbox() : base = Directory.systemTemp.createTempSync('paste_marker_') {
    Directory(root).createSync();
    Directory(home).createSync();
  }

  /// 임시 디렉터리 바닥.
  final Directory base;

  /// 저장소 root.
  String get root => '${base.path}/repo';

  /// 사용자 홈.
  String get home => '${base.path}/home';

  /// 정리한다.
  void dispose() => base.deleteSync(recursive: true);
}

/// 한 번의 실행 결과 — 종료 코드 · 화면 전문 · 실행 기록 · 가짜 실행기 · 원본 경로.
typedef PasteRun = ({
  int code,
  String screen,
  List<String> logLines,
  FakeCommandRunner runner,
  String source,
});

void main() {
  late _Sandbox box;

  setUp(() => box = _Sandbox());
  tearDown(() => box.dispose());

  /// 원본 크기 읽기 명령의 키.
  String buildProbeKey(String source) =>
      FakeCommandRunner.buildKey(AppIconStep.buildProbeCommand(source));

  /// 원본 경로 답을 [buildAnswer] 로 만들어 위저드를 한 번 돌린다.
  ///
  /// 읽기 대기열은 `1`(진행) 뒤 그 답 하나이고, 비면 입력 끝(null)이다.
  Future<PasteRun> runWithAnswer(String Function(String source) buildAnswer) {
    final String root = box.root;
    final Map<String, String> kit = writeKitDefaultHomeIcons(root);
    final Uint8List bytes = buildOpaqueRgbaIconPng();
    final file = File('${box.home}/$sourceRelativePath')
      ..createSync(recursive: true)
      ..writeAsBytesSync(bytes);
    final String source = file.path;

    final runner = FakeCommandRunner();
    final String convertKey = FakeCommandRunner.buildKey(
      AppIconStep.buildConvertCommand(
        source,
        '$root/$iconWorkDirectory/source.png',
        display: '',
      ),
    );
    runner
      ..on(
        FakeCommandRunner.buildKey(
          buildUncommittedFilesCommand(AppIconStep.listWritePaths()),
        ),
        const CommandResult(0, '', ''),
      )
      ..on(
        buildProbeKey(source),
        CommandResult(
          0,
          '$source\n  pixelWidth: 1024\n  pixelHeight: 1024\n  format: png\n',
          '',
        ),
      )
      ..on(convertKey, const CommandResult(0, '', ''))
      ..onEffect(convertKey, () {
        File('$root/$iconWorkDirectory/source.png')
          ..createSync(recursive: true)
          ..writeAsBytesSync(bytes);
      })
      ..on(
        FakeCommandRunner.buildKey(AppIconStep.buildOpenCommand(root)),
        const CommandResult(0, '', ''),
      );
    registerTrackedFiles(runner, root);

    final queue = <String>['1', buildAnswer(source)];
    final screen = StringBuffer();
    final stdio = StdioTerminal(
      readLine: () => queue.isEmpty ? null : queue.removeAt(0),
      output: screen,
    );
    final redactor = Redactor();
    final log = MemoryLogSink(redactor);

    return runWizard(
      WizardContext(
        projectRoot: root,
        runner: runner,
        terminal: RedactingTerminal(stdio, redactor, log),
        redactor: redactor,
        log: log,
        rest: FakeRestClient(),
        homeDirectory: box.home,
        random: Random(fixedTestRandomSeed),
        now: () => fixedTestNow,
      ),
      <Step>[
        providersStandIn,
        AppIconStep(
          enabledProviders: const <String>{'kakao'},
          kitDefaultDigests: kit,
        ),
      ],
    ).then(
      (int code) => (
        code: code,
        screen: screen.toString(),
        logLines: log.lines,
        runner: runner,
        source: source,
      ),
    );
  }

  /// [run] 이 원본을 한 번에 받아 끝났는지 본다 — 기록의 답은 [recorded].
  void expectAccepted(PasteRun run, String recorded) {
    expect(run.code, wizardExitDone);
    expect(run.screen, isNot(contains(AppIconStep.missingFileReason)));
    expect(run.screen, isNot(contains('\x1B')));
    expect(
      RegExp(
        RegExp.escape('${AppIconStep.sourceQuestion}: '),
      ).allMatches(run.screen).length,
      1,
    );
    expect(run.screen, contains(mineKakaoDoneLine));
    expect(
      run.runner.countCalls(RunMode.capture, buildProbeKey(run.source)),
      1,
    );
    expect(run.logLines.where((String line) => line.contains('\x1B')), isEmpty);
    expect(
      run.logLines.where((String line) => line == '[in] $recorded').length,
      1,
    );
  }

  group('T-28-PASTE-05: 실제 터미널 경계 — 「앱 아이콘」 원본 경로', () {
    test('표시로 감싼 끌어다 놓기 답 → 까닭 줄 0 · 원본 질문 1번 · ✓ · 기록에 ESC 0', () async {
      final PasteRun run = await runWithAnswer(
        (String source) => '$pasteStart${escapeDroppedPath(source)}$pasteEnd',
      );

      expectAccepted(run, escapeDroppedPath(run.source));
    });

    test('표시 없는 끌어다 놓기 답 → 까닭 줄 0 · 원본 질문 1번 · ✓ · 기록에 ESC 0', () async {
      final PasteRun run = await runWithAnswer(escapeDroppedPath);

      expectAccepted(run, escapeDroppedPath(run.source));
    });
  });
}
