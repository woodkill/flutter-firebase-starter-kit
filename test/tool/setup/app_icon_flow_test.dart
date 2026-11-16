// 앱 아이콘 단계 흐름 시험 — 실제 git 임시 저장소에서 첫 실행 → 다시 실행 →
// 커밋하지 않은 채 `--app-icon` 멈춤 → 커밋 뒤 `--app-icon` 다시 만들기를 잇고,
// 콘솔 칸 수단이 없는 저장소는 홈 화면 아이콘만 만드는지 본다.
//
// git 은 실제로 돌리고 sips · open 은 가짜 실행기에 등록한 대로다. 변환 효과는
// 작업 폴더의 `source.png` 에 진짜 PNG 를 쓴다. `--app-icon` 실행은 진입점이
// 하는 일(세션 플래그 · 아이콘 단계 하나 · 아이콘 끝 요약)을 그대로 짜 맞춘다.
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:test/test.dart';

import '../../../tool/setup/command_runner.dart';
import '../../../tool/setup/completion.dart';
import '../../../tool/setup/icons/home_icon_specs.dart';
import '../../../tool/setup/icons/icon_pipeline.dart';
import '../../../tool/setup/providers/icon_specs.dart';
import '../../../tool/setup/redactor.dart';
import '../../../tool/setup/step.dart';
import '../../../tool/setup/steps/app_icon_step.dart';
import '../../../tool/setup/steps/flavor_steps.dart';
import '../../../tool/setup/terminal.dart';
import '../../../tool/setup/wizard.dart';
import 'fake_rest_client.dart';
import 'fakes.dart';
import 'home_icon_fixture.dart';

/// Kakao 콘솔 아이콘 경로 — 저장소 루트 기준.
final String kakaoIconPath = findIconSpec('kakao')!.relativePath;

/// 「내 아이콘」 · Kakao 콘솔 아이콘이 끝난 상태의 점검표 줄.
const String mineKakaoCheckLine =
    '  ✓ 앱 아이콘 — 내 아이콘 · Kakao 콘솔용 1개 · 바꾸려면: ./setup.sh --app-icon';

/// 실제 git 저장소 · 임시 홈 한 쌍 — `.setup/` 는 gitignored 다.
final class _GitSandbox {
  _GitSandbox() : base = Directory.systemTemp.createTempSync('app_icon_flow_') {
    Directory(root).createSync();
    Directory(home).createSync();
    initGitFixture(root);
    File('$root/.gitignore').writeAsStringSync('.setup/\n');
  }

  /// 임시 디렉터리 바닥.
  final Directory base;

  /// 저장소 root.
  String get root => '${base.path}/repo';

  /// 사용자 홈.
  String get home => '${base.path}/home';

  /// 저장소 상대 경로 [relativePath] 의 파일 객체를 연다(디스크는 건드리지 않는다).
  File openRepoFile(String relativePath) => File('$root/$relativePath');

  /// 홈 아래 [name] 에 [bytes] 를 쓴 원본을 만들고 절대 경로를 돌려준다.
  String writeSource(String name, List<int> bytes) {
    final file = File('$home/$name')
      ..createSync(recursive: true)
      ..writeAsBytesSync(bytes);
    return file.path;
  }

  /// 쓰기 대상 27경로의 지금 바이트 — 없는 경로는 null.
  Map<String, List<int>?> readWriteTargets() => <String, List<int>?>{
    for (final String path in AppIconStep.listWritePaths())
      path: openRepoFile(path).existsSync()
          ? openRepoFile(path).readAsBytesSync()
          : null,
  };

  /// 추적 안 된 파일까지 보인 `git status --porcelain` 줄들(정렬).
  List<String> readStatusLines() {
    final ProcessResult result = runFixtureGit(root, const <String>[
      'status',
      '--porcelain',
      '--untracked-files=all',
    ]);
    return (result.stdout as String)
        .split('\n')
        .where((String line) => line.isNotEmpty)
        .toList()
      ..sort();
  }

  /// 정리한다.
  void dispose() => base.deleteSync(recursive: true);
}

/// 실제 git 저장소에서의 위저드 한 번.
final class _GitRun {
  _GitRun(this.box, List<String?> inputs, {WizardSession? session})
    : screen = ScriptedTerminal(inputs),
      session = session ?? WizardSession() {
    runner = IconFlowRunner(box.root, fake);
  }

  final _GitSandbox box;
  final WizardSession session;
  final ScriptedTerminal screen;
  final FakeCommandRunner fake = FakeCommandRunner();
  final MemoryLogSink log = MemoryLogSink(Redactor());
  late final IconFlowRunner runner;

  /// 화면 줄들.
  List<String> get lines => screen.output.toString().split('\n');

  /// 원본 [source] 의 크기 읽기 · 변환 · Finder 열기를 등록한다 — 변환은 작업
  /// 폴더의 `source.png` 에 [converted] 를 쓴다.
  void registerSource(String source, Uint8List converted) {
    final String convertKey = FakeCommandRunner.buildKey(
      AppIconStep.buildConvertCommand(
        source,
        '${box.root}/$iconWorkDirectory/source.png',
        display: '',
      ),
    );
    fake
      ..on(
        FakeCommandRunner.buildKey(AppIconStep.buildProbeCommand(source)),
        CommandResult(
          0,
          '$source\n  pixelWidth: 1024\n  pixelHeight: 1024\n  format: png\n',
          '',
        ),
      )
      ..on(convertKey, const CommandResult(0, '', ''))
      ..onEffect(convertKey, () {
        File(
          '${box.root}/$iconWorkDirectory/source.png',
        ).writeAsBytesSync(converted);
      })
      ..on(
        FakeCommandRunner.buildKey(AppIconStep.buildOpenCommand(box.root)),
        const CommandResult(0, '', ''),
      );
  }

  /// sips 호출 수.
  int countSipsCalls() => fake.calls
      .where((FakeCall call) => call.key.startsWith('/usr/bin/sips '))
      .length;

  /// Finder 열기 호출 수.
  int countOpenCalls() => fake.calls
      .where((FakeCall call) => call.key.startsWith('/usr/bin/open '))
      .length;

  /// [steps] 를 [onCompleted] 끝 요약과 함께 돌린다.
  Future<int> run(List<Step> steps, WizardCompletion onCompleted) => runWizard(
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
    steps,
    onCompleted: onCompleted,
  );
}

/// 보통 실행의 단계 목록 — 로그인 수단 대역 뒤에 아이콘 단계.
List<Step> buildNormalSteps(
  Set<String> enabledProviders,
  Map<String, String> kitDigests,
) => <Step>[
  providersStandIn,
  AppIconStep(
    enabledProviders: enabledProviders,
    kitDefaultDigests: kitDigests,
  ),
];

/// `--app-icon` 실행 — 세션 플래그를 켜고 아이콘 단계 하나 · 아이콘 끝 요약.
Future<int> _runAppIconOnly(_GitRun run) {
  run.session.isAppIconRebuildRequested = true;
  return run.run(
    buildAppIconSteps(enabledProviders: const <String>{'kakao'}),
    showAppIconCompletionSummary,
  );
}

/// 끝 요약 커밋 안내 블록 — 머리 줄 · 경로 줄들 · `git add … && git commit` 줄.
List<String> buildCommitHintBlock(List<String> paths) {
  final sorted = List<String>.of(paths)..sort();
  final command =
      '  \$ git add ${sorted.map(quoteForShellDisplay).join(' ')} '
      '&& git commit -m "$commitHintMessage"';
  return <String>[
    commitHintHeading,
    for (final String path in sorted) '  $path',
    command,
  ];
}

/// [lines] 에서 커밋 안내 머리 줄부터 git 명령 줄까지를 자른다 — 없으면 빈 목록.
List<String> readCommitHintBlock(List<String> lines) {
  final int start = lines.indexOf(commitHintHeading);
  if (start < 0) return const <String>[];
  final int end = lines.indexWhere(
    (String line) => line.startsWith(r'  $ git add '),
    start,
  );
  if (end < 0) return lines.sublist(start);
  return lines.sublist(start, end + 1);
}

/// 홈 화면 20장 경로.
List<String> listHomeIconPaths() => <String>[
  for (final HomeIconFile file in homeIconFiles) file.relativePath,
];

/// 첫 실행 뒤 기대하는 상태 줄 — tracked 20장 수정 · adaptive 7개 새 파일.
List<String> buildFirstRunStatus() => <String>[
  for (final String path in listHomeIconPaths()) ' M $path',
  for (final String path in listAdaptiveFilePaths()) '?? $path',
]..sort();

void main() {
  group('실제 git 같은 저장소 — 첫 실행 · 다시 실행 · 미커밋 멈춤 · 커밋 뒤 다시 만들기', () {
    late _GitSandbox box;
    late Map<String, String> kit;
    late Map<String, List<int>?> afterFirstRun;

    setUpAll(() {
      box = _GitSandbox();
      kit = writeKitDefaultHomeIcons(box.root);
      commitGitFixture(box.root, 'kit default icons');
    });
    tearDownAll(() => box.dispose());

    test('T-28-FLOW-01: 킷 기본 첫 보통 실행 · Kakao 켬 → 27경로 미커밋 · '
        '끝 요약에 안내 줄 · 새 adaptive 파일까지 담은 커밋 안내', () async {
      final Uint8List sourceBytes = buildOpaqueRgbaIconPng();
      final String source = box.writeSource('painted.png', sourceBytes);
      final run = _GitRun(box, <String?>['1', source])
        ..registerSource(source, sourceBytes);

      final int code = await run.run(
        buildNormalSteps(const <String>{'kakao'}, kit),
        showCompletionSummary,
      );

      expect(code, wizardExitDone);
      expect(box.readStatusLines(), buildFirstRunStatus());
      final List<String> lines = run.lines;
      final int providersAt = lines.indexOf(providersHintLine);
      expect(providersAt, greaterThan(0));
      expect(lines[providersAt - 1], '');
      expect(lines[providersAt + 1], appIconHintLine);
      expect(
        readCommitHintBlock(lines),
        buildCommitHintBlock(<String>[
          ...listHomeIconPaths(),
          ...listAdaptiveFilePaths(),
        ]),
      );
      expect(box.openRepoFile(kakaoIconPath).existsSync(), isTrue);
      expect(
        box.openRepoFile(homeIconMarkerPath).readAsStringSync(),
        buildHomeIconMarkerText(box.root, const <String>['kakao']),
      );
      expect(run.countOpenCalls(), 1);
      afterFirstRun = box.readWriteTargets();
      expect(afterFirstRun.values.whereType<List<int>>(), hasLength(27));
    });

    test('T-28-FLOW-02: 커밋 안 한 채 두 번째 보통 실행 → ✓ 줄 · 질문 0 · '
        '27경로 바이트 그대로', () async {
      final run = _GitRun(box, const <String?>[]);

      final int code = await run.run(
        buildNormalSteps(const <String>{'kakao'}, kit),
        showCompletionSummary,
      );

      expect(code, wizardExitDone);
      expect(run.lines, contains(mineKakaoCheckLine));
      expect(run.screen.asks, isEmpty);
      expect(box.readWriteTargets(), afterFirstRun);
      expect(run.countSipsCalls(), 0);
      expect(run.countOpenCalls(), 0);
    });

    test('T-28-FLOW-03: 커밋 안 한 채 --app-icon → 원본 질문 · sips 없이 '
        '미커밋 실패 → 멈춤 · 27경로 바이트 그대로', () async {
      final run = _GitRun(box, const <String?>['1', '2']);

      final int code = await _runAppIconOnly(run);

      expect(code, wizardExitStopped);
      final List<String> lines = run.lines;
      final int failAt = lines.indexOf('  실패 — ${AppIconStep.dirtyReason}');
      expect(failAt, greaterThanOrEqualTo(0));
      for (final String path in AppIconStep.listWritePaths()) {
        expect(lines, contains('    $path'), reason: path);
      }
      expect(run.screen.asks, isNot(contains(AppIconStep.sourceQuestion)));
      expect(run.screen.asks.last, failureChoiceQuestion);
      expect(run.countSipsCalls(), 0);
      expect(run.countOpenCalls(), 0);
      expect(box.readWriteTargets(), afterFirstRun);
      expect(box.readStatusLines(), buildFirstRunStatus());
    });

    test('T-28-FLOW-04: 커밋 뒤 --app-icon → 투명 로고 · #1a2b3c 로 다시 만듦 · '
        '끝 요약에 안내 줄만 · 바뀐 adaptive 파일까지 커밋 안내', () async {
      commitGitFixture(box.root, 'my icons');
      final List<int> kakaoBefore = box
          .openRepoFile(kakaoIconPath)
          .readAsBytesSync();
      final List<int> ios1024Before = box
          .openRepoFile(ios1024Path)
          .readAsBytesSync();
      final Uint8List logo = buildTransparentLogoPng();
      final String source = box.writeSource('logo.png', logo);
      final run = _GitRun(box, <String?>['1', source, '#1a2b3c'])
        ..registerSource(source, logo);

      final int code = await _runAppIconOnly(run);

      expect(code, wizardExitDone);
      final Uint8List ios1024 = box.openRepoFile(ios1024Path).readAsBytesSync();
      expect(ios1024, isNot(ios1024Before));
      expect(readPngHeader(ios1024)?.colorType, 2);
      expect(
        box.openRepoFile(adaptiveBackgroundPath).readAsStringSync(),
        contains('<color name="ic_launcher_background">#1A2B3C</color>'),
      );
      expect(
        box.openRepoFile(kakaoIconPath).readAsBytesSync(),
        isNot(kakaoBefore),
      );
      expect(
        box.openRepoFile(homeIconMarkerPath).readAsStringSync(),
        buildHomeIconMarkerText(box.root, const <String>['kakao']),
      );
      expect(run.session.isAppIconRebuildRequested, isFalse);
      final List<String> lines = run.lines;
      expect(lines, contains(appIconHintLine));
      expect(lines, isNot(contains(providersHintLine)));
      // adaptive XML 은 내용이 늘 같아 다시 써도 바뀐 파일로 잡히지 않는다.
      expect(
        readCommitHintBlock(lines),
        buildCommitHintBlock(<String>[
          ...listHomeIconPaths(),
          for (final String path in listAdaptiveFilePaths())
            if (path != adaptiveIconXmlPath) path,
        ]),
      );
    });
  });

  test('T-28-FLOW-05: 콘솔 칸 수단 0 · 킷 기본 → 홈 화면 27경로만 · '
      '.setup/icons · Finder 0', () async {
    final box = _GitSandbox();
    addTearDown(box.dispose);
    final Map<String, String> kit = writeKitDefaultHomeIcons(box.root);
    commitGitFixture(box.root, 'kit default icons');
    final Uint8List sourceBytes = buildOpaqueRgbaIconPng();
    final String source = box.writeSource('painted.png', sourceBytes);
    final run = _GitRun(box, <String?>['1', source])
      ..registerSource(source, sourceBytes);

    final int code = await run.run(
      buildNormalSteps(const <String>{}, kit),
      showCompletionSummary,
    );

    expect(code, wizardExitDone);
    expect(box.readStatusLines(), buildFirstRunStatus());
    expect(Directory('${box.root}/$iconsDirectory').existsSync(), isFalse);
    expect(run.countOpenCalls(), 0);
  });
}
