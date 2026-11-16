// 앱 아이콘 단계의 쓰기 실패 갈래 시험 — 실제 git 임시 저장소에서 쓰다 만
// 홈 화면 아이콘을 되돌리는지, 같은 이름 리소스나 git 이 추적하지 않는 쓰기
// 대상이 있으면 묻기 전에 멈추는지, 제자리에 쓴 iOS 1024 를 다시 읽어 판정하는지
// 본다.
//
// git 은 실제로 돌리고 sips · open 은 가짜 실행기에 등록한 대로다. 변환 효과는
// 작업 폴더의 `source.png` 에 진짜 PNG 를 쓴다.
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:test/test.dart';

import '../../../tool/setup/command_runner.dart';
import '../../../tool/setup/icons/home_icon_specs.dart';
import '../../../tool/setup/providers/icon_specs.dart';
import '../../../tool/setup/redactor.dart';
import '../../../tool/setup/step.dart';
import '../../../tool/setup/steps/app_icon_step.dart';
import '../../../tool/setup/terminal.dart';
import '../../../tool/setup/wizard.dart';
import 'fake_rest_client.dart';
import 'fakes.dart';
import 'home_icon_fixture.dart';

/// 쓰다 실패한 뒤 되돌렸을 때의 실패 줄 머리.
const String rolledBackLineHead = '  실패 — 홈 화면 아이콘을 쓰지 못해 쓰기 전으로 되돌렸습니다 — ';

/// 같은 이름 리소스가 있을 때의 실패 줄 머리.
const String conflictLineHead = '  실패 — 같은 이름의 아이콘 리소스가 이미 있습니다';

/// 쓰기 대상에 git 이 추적하지 않는 파일이 있을 때의 실패 줄.
const String untrackedLineHead = '  실패 — ${AppIconStep.untrackedTargetReason}';

/// 실제 git 저장소 · 임시 홈 한 쌍.
final class _GitSandbox {
  _GitSandbox()
    : base = Directory.systemTemp.createTempSync('app_icon_rollback_') {
    Directory(root).createSync();
    Directory(home).createSync();
    initGitFixture(root);
  }

  /// 임시 디렉터리 바닥.
  final Directory base;

  /// 저장소 root.
  String get root => '${base.path}/repo';

  /// 사용자 홈.
  String get home => '${base.path}/home';

  /// 저장소 상대 경로 [relativePath] 의 파일.
  File repoFile(String relativePath) => File('$root/$relativePath');

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
      path: repoFile(path).existsSync()
          ? repoFile(path).readAsBytesSync()
          : null,
  };

  /// 실제 git 을 [arguments] 로 돌린 결과.
  ProcessResult git(List<String> arguments) => runFixtureGit(root, arguments);

  /// 추적 안 된 파일까지 보인 `git status --porcelain` 출력.
  String readStatus() =>
      git(const <String>[
            'status',
            '--porcelain',
            '--untracked-files=all',
          ]).stdout
          as String;

  /// 정리한다.
  void dispose() => base.deleteSync(recursive: true);
}

/// 실제 git 저장소에서의 위저드 한 번 — 로그인 수단 대역 + 아이콘 단계.
final class _GitRun {
  _GitRun(
    this.box,
    List<String?> inputs, {
    this.kitDigests,
    WizardSession? session,
  }) : screen = ScriptedTerminal(inputs),
       session = session ?? WizardSession() {
    runner = IconFlowRunner(box.root, fake);
  }

  final _GitSandbox box;

  /// 단계에 주입할 킷 기본 지문 — 없으면 킷이 담은 지문.
  final Map<String, String>? kitDigests;
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

  /// 실제로 돌린 `git checkout` 수.
  int countCheckouts() => runner.gitKeys
      .where((String key) => key.startsWith('git checkout'))
      .length;

  /// 위저드를 돌린다.
  ///
  /// [overrides] 를 주면 그 [IOOverrides] 안에서 돌린다. [failedLsFilesCall] 을
  /// 주면 그 차례(1부터)의 `git ls-files` 만 종료 코드 128 로 답한다.
  Future<int> run({IOOverrides? overrides, int? failedLsFilesCall}) {
    final CommandRunner used = failedLsFilesCall == null
        ? runner
        : _LsFilesFaultRunner(runner, failedLsFilesCall);
    Future<int> start() => _runWith(used);
    return overrides == null
        ? start()
        : IOOverrides.runWithIOOverrides(start, overrides);
  }

  /// 실행기 [used] 로 위저드를 돌린다.
  Future<int> _runWith(CommandRunner used) => runWizard(
    WizardContext(
      projectRoot: box.root,
      runner: used,
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
      AppIconStep(
        enabledProviders: const <String>{'kakao'},
        kitDefaultDigests: kitDigests,
      ),
    ],
  );
}

/// 고른 차례의 `git ls-files` 만 실패로 답하고 나머지는 [inner] 에 넘기는 실행기.
final class _LsFilesFaultRunner implements CommandRunner {
  _LsFilesFaultRunner(this.inner, this.failedCall);

  /// 실제로 돌릴 실행기.
  final CommandRunner inner;

  /// 실패로 답할 `git ls-files` 차례(1부터).
  final int failedCall;

  int _lsFilesCalls = 0;

  /// [command] 가 실패시킬 차례의 `git ls-files` 인지 센다.
  bool _isFailedCall(Command command) {
    if (command.executable != 'git' ||
        command.arguments.isEmpty ||
        command.arguments.first != 'ls-files') {
      return false;
    }
    _lsFilesCalls++;
    return _lsFilesCalls == failedCall;
  }

  @override
  Future<CommandResult> capture(Command command) async => _isFailedCall(command)
      ? const CommandResult(128, '', 'fatal: 주입한 실패')
      : await inner.capture(command);

  @override
  Future<int> interactive(Command command) => inner.interactive(command);

  @override
  Future<CommandResult> stream(Command command) => inner.stream(command);
}

void main() {
  late _GitSandbox box;

  setUp(() => box = _GitSandbox());
  tearDown(() => box.dispose());

  test('T-28-SAFE-01: 킷 기본 저장소 · 마지막 전경 자리에 빈 폴더 → 쓰기 실패 → '
      '20장 = HEAD · 새 adaptive 파일 0 · 빈 폴더 그대로 · 표식 · 콘솔 0', () async {
    final Map<String, String> kit = writeKitDefaultHomeIcons(box.root);
    commitGitFixture(box.root, 'kit default icons');
    final String blocked = adaptiveDensities.last.foregroundPath;
    Directory('${box.root}/$blocked').createSync(recursive: true);
    final Uint8List sourceBytes = buildOpaqueRgbaIconPng();
    final String source = box.writeSource('logo.png', sourceBytes);
    final run = _GitRun(box, <String?>['1', source, '2'], kitDigests: kit)
      ..registerSource(source, sourceBytes);

    final int code = await run.run();

    expect(code, wizardExitStopped);
    expect(
      run.lines.where((String line) => line.startsWith(rolledBackLineHead)),
      hasLength(1),
    );
    expect(
      run.lines.firstWhere(
        (String line) => line.startsWith(rolledBackLineHead),
      ),
      contains(blocked),
    );
    final ProcessResult diff = box.git(<String>[
      'diff',
      '--quiet',
      'HEAD',
      '--',
      for (final HomeIconFile file in homeIconFiles) file.relativePath,
    ]);
    expect(diff.exitCode, 0, reason: '홈 화면 20장이 HEAD 와 다르다');
    for (final HomeIconFile file in homeIconFiles) {
      expect(
        box.repoFile(file.relativePath).readAsStringSync(),
        'kit:${file.relativePath}',
        reason: file.relativePath,
      );
    }
    for (final String path in listAdaptiveFilePaths()) {
      expect(box.repoFile(path).existsSync(), isFalse, reason: path);
    }
    expect(Directory('${box.root}/$blocked').existsSync(), isTrue);
    expect(Directory('${box.root}/$blocked').listSync(), isEmpty);
    expect(box.repoFile(homeIconMarkerPath).existsSync(), isFalse);
    expect(
      box.repoFile(findIconSpec('kakao')!.relativePath).existsSync(),
      isFalse,
    );
    expect(Directory('${box.root}/$iconWorkDirectory').existsSync(), isFalse);
    expect(box.readStatus(), isEmpty);
    expect(run.countCheckouts(), 0);
    expect(
      run.fake.calls.where(
        (FakeCall call) => call.key.startsWith('/usr/bin/open '),
      ),
      isEmpty,
    );
  });

  group('T-28-SAFE-02: 같은 이름 리소스 → 원본 질문 · sips · 쓰기 0', () {
    late Map<String, String> kit;

    setUp(() => kit = writeKitDefaultHomeIcons(box.root));

    /// [relativePath] 에 [contents] 를 쓰고 커밋한 뒤 위저드를 돌려 멈춤을 본다.
    Future<void> expectStopsBefore(String relativePath, String contents) async {
      box.repoFile(relativePath)
        ..parent.createSync(recursive: true)
        ..writeAsStringSync(contents);
      commitGitFixture(box.root, 'existing adaptive resource');
      final Map<String, List<int>?> before = box.readWriteTargets();
      final run = _GitRun(box, <String?>['1', '2'], kitDigests: kit);

      expect(await run.run(), wizardExitStopped);
      expect(run.lines, contains(startsWith(conflictLineHead)));
      expect(run.lines, contains('    $relativePath'));
      expect(run.screen.asks, isNot(contains(AppIconStep.sourceQuestion)));
      expect(run.countSipsCalls(), 0);
      expect(box.readWriteTargets(), before);
      expect(box.readStatus(), isEmpty);
      expect(run.countCheckouts(), 0);
    }

    test('mipmap-hdpi 에 다른 확장자 전경', () async {
      await expectStopsBefore(
        '$androidResDirectory/mipmap-hdpi/ic_launcher_foreground.webp',
        'webp',
      );
    });

    test('values/colors.xml 이 같은 배경색 이름을 정의', () async {
      await expectStopsBefore(
        '$androidResDirectory/values/colors.xml',
        '<?xml version="1.0" encoding="utf-8"?>\n<resources>\n'
            '    <color name="ic_launcher_background">#123456</color>\n'
            '</resources>\n',
      );
    });

    test('찾은 경로를 정렬해 모두 돌려준다 · res 폴더가 없으면 빈 목록', () {
      expect(AppIconStep.findConflictingIconResources(box.home), isEmpty);
      for (final path in <String>[
        'values-night/colors.xml',
        'mipmap-xxhdpi/ic_launcher.webp',
        'mipmap-anydpi-v26/ic_launcher_foreground.xml',
      ]) {
        box.repoFile('$androidResDirectory/$path')
          ..parent.createSync(recursive: true)
          ..writeAsStringSync(
            path.endsWith('colors.xml')
                ? "<color name='ic_launcher_background'>#000000</color>"
                : 'x',
          );
      }
      expect(AppIconStep.findConflictingIconResources(box.root), <String>[
        '$androidResDirectory/mipmap-anydpi-v26/ic_launcher_foreground.xml',
        '$androidResDirectory/mipmap-xxhdpi/ic_launcher.webp',
        '$androidResDirectory/values-night/colors.xml',
      ]);
    });

    test('drawable 의 같은 이름 · 비슷한 이름 · 이 단계가 쓰는 파일은 막지 않는다', () async {
      for (final path in <String>[
        'drawable/ic_launcher_foreground.xml',
        'mipmap-hdpi/ic_launcher_round.png',
        'values/colors.xml',
        ...<String>[
          for (final String write in listAdaptiveFilePaths())
            write.substring('$androidResDirectory/'.length),
        ],
      ]) {
        box.repoFile('$androidResDirectory/$path')
          ..parent.createSync(recursive: true)
          ..writeAsStringSync(
            path == 'values/colors.xml'
                ? '<color name="ic_launcher_background_dark">#000000</color>'
                : 'x',
          );
      }
      commitGitFixture(box.root, 'similar resources');
      expect(AppIconStep.findConflictingIconResources(box.root), isEmpty);
      final Uint8List sourceBytes = buildOpaqueRgbaIconPng();
      final String source = box.writeSource('logo.png', sourceBytes);
      final run = _GitRun(box, <String?>['1', source], kitDigests: kit)
        ..registerSource(source, sourceBytes);

      expect(await run.run(), wizardExitDone);
      expect(
        box.repoFile(adaptiveIconXmlPath).readAsStringSync(),
        buildAdaptiveIconXml(),
      );
    });
  });

  test('T-28-SAFE-03: 제자리 iOS 1024 다시 읽기 — 1024 · color type 2 · 알파 '
      '없음만 통과', () {
    expect(
      AppIconStep.findPlacedIos1024Problem(buildOpaqueRgbIconPng()),
      isNull,
    );
    expect(
      AppIconStep.findPlacedIos1024Problem(buildOpaqueRgbaIconPng()),
      isNotNull,
    );
    expect(
      AppIconStep.findPlacedIos1024Problem(buildOpaqueRgbIconPng(side: 512)),
      isNotNull,
    );
    expect(
      AppIconStep.findPlacedIos1024Problem(
        Uint8List.fromList(const <int>[1, 2, 3]),
      ),
      isNotNull,
    );
  });

  test('T-28-SAFE-04: 내 아이콘 + adaptive 를 커밋한 저장소 · 다시 만들기 · '
      '마지막 전경 읽기 전용 → 쓰기 실패 → 27개 모두 커밋 바이트 · 지운 파일 0', () async {
    writeMyHomeIcons(box.root);
    for (final String path in listAdaptiveFilePaths()) {
      box.repoFile(path)
        ..parent.createSync(recursive: true)
        ..writeAsStringSync('committed:$path');
    }
    commitGitFixture(box.root, 'previous wizard run');
    final Map<String, List<int>?> before = box.readWriteTargets();
    expect(before.values.whereType<List<int>>(), hasLength(27));
    final String blocked = adaptiveDensities.last.foregroundPath;
    final ProcessResult chmod = Process.runSync('chmod', <String>[
      '0444',
      '${box.root}/$blocked',
    ]);
    expect(chmod.exitCode, 0);
    final Uint8List sourceBytes = buildOpaqueRgbaIconPng();
    final String source = box.writeSource('new logo.png', sourceBytes);
    final session = WizardSession()..isAppIconRebuildRequested = true;
    final run = _GitRun(box, <String?>['1', source, '2'], session: session)
      ..registerSource(source, sourceBytes);

    final int code = await run.run();

    expect(code, wizardExitStopped);
    expect(
      run.lines.firstWhere(
        (String line) => line.startsWith(rolledBackLineHead),
      ),
      contains(blocked),
    );
    expect(box.readWriteTargets(), before);
    expect(box.readStatus(), isEmpty);
    // 되돌림은 떠 둔 바이트로 한다 — 쓰기에 실패해 바뀌지 않은 읽기 전용 파일은
    // 다시 쓰지 않는다.
    expect(run.countCheckouts(), 0);
    expect(box.repoFile(homeIconMarkerPath).existsSync(), isFalse);
    expect(session.isAppIconRebuildRequested, isTrue);
  });

  // iOS 1024 자리를 '/dev/null' 링크로 두면 쓰기는 성공하고 다시 읽기만 빈 바이트가
  // 되는 자리가 생긴다 — 링크 꼴이라 macOS · Linux 에서만 돈다.
  test('T-28-SAFE-05: 킷 기본 저장소 · iOS 1024 자리 = /dev/null 링크 → 쓰기 성공 · '
      '다시 읽기 실패 → 20장 = HEAD · 새 adaptive 파일 0 · 링크 그대로 · 표식 · 콘솔 0', () async {
    final Map<String, String> kit = writeKitDefaultHomeIcons(box.root);
    final linkPath = '${box.root}/$ios1024Path';
    box.repoFile(ios1024Path).deleteSync();
    Link(linkPath).createSync('/dev/null');
    // 빈 바이트의 sha256 — 링크가 가리키는 /dev/null 을 킷 기본으로 본다.
    kit[ios1024Path] =
        'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855';
    commitGitFixture(box.root, 'kit default icons with null link');
    final Uint8List sourceBytes = buildOpaqueRgbaIconPng();
    final String source = box.writeSource('logo.png', sourceBytes);
    final run = _GitRun(box, <String?>['1', source, '2'], kitDigests: kit)
      ..registerSource(source, sourceBytes);

    final int code = await run.run();

    expect(code, wizardExitStopped);
    final Iterable<String> rolledBack = run.lines.where(
      (String line) => line.startsWith(rolledBackLineHead),
    );
    expect(rolledBack, hasLength(1));
    expect(rolledBack.single, contains('다시 읽은'));
    expect(rolledBack.single, contains(ios1024Path));
    final ProcessResult diff = box.git(<String>[
      'diff',
      '--quiet',
      'HEAD',
      '--',
      for (final HomeIconFile file in homeIconFiles) file.relativePath,
    ]);
    expect(diff.exitCode, 0, reason: '홈 화면 20장이 HEAD 와 다르다');
    for (final String path in listAdaptiveFilePaths()) {
      expect(box.repoFile(path).existsSync(), isFalse, reason: path);
    }
    expect(box.repoFile(homeIconMarkerPath).existsSync(), isFalse);
    expect(
      box.repoFile(findIconSpec('kakao')!.relativePath).existsSync(),
      isFalse,
    );
    expect(Directory('${box.root}/$iconWorkDirectory').existsSync(), isFalse);
    expect(box.readStatus(), isEmpty);
    expect(run.countCheckouts(), 0);
    expect(
      run.fake.calls.where(
        (FakeCall call) => call.key.startsWith('/usr/bin/open '),
      ),
      isEmpty,
    );
    expect(FileSystemEntity.isLinkSync(linkPath), isTrue);
  }, testOn: 'mac-os || linux');

  test('T-28-SAFE-06: 쓰다 실패한 경로 — 있던 경로는 되돌림 · 없던 파일만 지움 · '
      '없던 폴더 · 링크 · 없음은 그대로', () {
    FailedWriteUndo decide(bool existedBefore, FileSystemEntityType type) =>
        AppIconStep.decideFailedWriteUndo(
          existedBefore: existedBefore,
          currentType: type,
        );

    expect(decide(true, FileSystemEntityType.file), FailedWriteUndo.restore);
    expect(
      decide(true, FileSystemEntityType.notFound),
      FailedWriteUndo.restore,
    );
    expect(decide(false, FileSystemEntityType.file), FailedWriteUndo.delete);
    expect(decide(false, FileSystemEntityType.directory), FailedWriteUndo.keep);
    expect(decide(false, FileSystemEntityType.link), FailedWriteUndo.keep);
    expect(decide(false, FileSystemEntityType.notFound), FailedWriteUndo.keep);
  });

  test('T-28-SAFE-07: gitignored adaptive 배경 파일 → 원본 질문 · sips · 쓰기 '
      '없이 멈춤 · ignored 파일 = 원래 바이트 · 상태 빈 출력', () async {
    final Map<String, String> kit = writeKitDefaultHomeIcons(box.root);
    box.repoFile('.gitignore').writeAsStringSync('/$adaptiveBackgroundPath\n');
    const localOnly = '<resources><!-- 로컬에만 둔 배경색 --></resources>\n';
    box.repoFile(adaptiveBackgroundPath)
      ..parent.createSync(recursive: true)
      ..writeAsStringSync(localOnly);
    commitGitFixture(box.root, 'kit default icons · ignored background');
    final ProcessResult ignored = box.git(<String>[
      'check-ignore',
      '-q',
      adaptiveBackgroundPath,
    ]);
    expect(ignored.exitCode, 0, reason: '배경 파일이 gitignored 가 아니다');
    final Map<String, List<int>?> before = box.readWriteTargets();
    final run = _GitRun(box, <String?>['1', '2'], kitDigests: kit);

    final int code = await run.run();

    expect(code, wizardExitStopped);
    final int failAt = run.lines.indexOf(untrackedLineHead);
    expect(failAt, greaterThanOrEqualTo(0));
    // 계획 줄은 멈춤보다 먼저 보이고, 추적 여부를 단정하지 않고 덮어쓰는 쪽에 센다.
    final int planAt = run.lines.indexWhere(
      (String line) => line.startsWith('    (덮어쓰는 파일: '),
    );
    expect(planAt, inInclusiveRange(0, failAt - 1));
    expect(run.lines[planAt], contains(' · $adaptiveBackgroundPath — 새 파일: '));
    expect(run.lines[failAt + 1], '    $adaptiveBackgroundPath');
    expect(run.lines[failAt + 2], isNot(startsWith('    ')));
    expect(run.screen.asks, isNot(contains(AppIconStep.sourceQuestion)));
    expect(run.countSipsCalls(), 0);
    expect(box.repoFile(adaptiveBackgroundPath).readAsStringSync(), localOnly);
    expect(box.readWriteTargets(), before);
    expect(box.repoFile(homeIconMarkerPath).existsSync(), isFalse);
    expect(box.readStatus(), isEmpty);
    expect(run.countCheckouts(), 0);
  });

  group('되돌림 자체가 실패하는 갈래', () {
    late Map<String, String> kit;
    late Uint8List sourceBytes;
    late String source;

    setUp(() {
      kit = writeKitDefaultHomeIcons(box.root);
      commitGitFixture(box.root, 'kit default icons');
      sourceBytes = buildOpaqueRgbaIconPng();
      source = box.writeSource('logo.png', sourceBytes);
    });

    /// 마지막 전경 자리에 빈 폴더를 두어 쓰기를 실패시키고 그 경로를 돌려준다.
    String blockLastForeground() {
      final String blocked = adaptiveDensities.last.foregroundPath;
      Directory('${box.root}/$blocked').createSync(recursive: true);
      return blocked;
    }

    /// 실패 줄부터 다시 시도 질문 전까지의 줄.
    List<String> readFailureBlock(List<String> lines) {
      final int start = lines.indexWhere(
        (String line) => line.startsWith('  실패 — '),
      );
      expect(start, greaterThanOrEqualTo(0));
      final int end = lines.indexOf(failureChoiceQuestion, start + 1);
      expect(end, greaterThan(start));
      return lines.sublist(start, end);
    }

    test('T-28-SAFE-08: 추적 iOS 1024 를 떠 둔 바이트로 다시 쓰지 못함 → '
        '되돌리지도 못함 머리 · git checkout 안내 아래 그 경로', () async {
      blockLastForeground();
      final overrides = FileFaultOverrides(
        <String, ({FileFault fault, int call})>{
          '${box.root}/$ios1024Path': (fault: FileFault.failWrite, call: 2),
        },
      );
      final run = _GitRun(box, <String?>['1', source, '2'], kitDigests: kit)
        ..registerSource(source, sourceBytes);

      expect(await run.run(overrides: overrides), wizardExitStopped);

      expect(overrides.firedPaths, <String>['${box.root}/$ios1024Path']);
      final List<String> block = readFailureBlock(run.lines);
      expect(
        block.first,
        startsWith('  실패 — ${AppIconStep.restoreFailedReason}'),
      );
      expect(block.sublist(1), <String>[
        AppIconStep.restoreGuide,
        '    $ios1024Path',
      ]);
      for (final HomeIconFile file in homeIconFiles) {
        if (file.relativePath == ios1024Path) continue;
        expect(
          box.repoFile(file.relativePath).readAsStringSync(),
          'kit:${file.relativePath}',
          reason: file.relativePath,
        );
      }
      expect(
        box.repoFile(ios1024Path).readAsBytesSync(),
        isNot(utf8.encode('kit:$ios1024Path')),
      );
      for (final String path in listAdaptiveFilePaths()) {
        expect(box.repoFile(path).existsSync(), isFalse, reason: path);
      }
    });

    test('T-28-SAFE-09: 다시 쓰지 못한 뒤 추적 여부 읽기(git ls-files)도 실패 → '
        '모든 경로가 되살리지 못함 안내 아래 · git checkout 안내 0', () async {
      blockLastForeground();
      final overrides = FileFaultOverrides(
        <String, ({FileFault fault, int call})>{
          '${box.root}/$ios1024Path': (fault: FileFault.failWrite, call: 2),
        },
      );
      final run = _GitRun(box, <String?>['1', source, '2'], kitDigests: kit)
        ..registerSource(source, sourceBytes);

      // 첫 git ls-files 는 쓰기 전 추적 여부 대조, 둘째가 되돌림 안내 쪽이다.
      final int code = await run.run(
        overrides: overrides,
        failedLsFilesCall: 2,
      );

      expect(code, wizardExitStopped);
      final List<String> block = readFailureBlock(run.lines);
      expect(
        block.first,
        startsWith('  실패 — ${AppIconStep.restoreFailedReason}'),
      );
      expect(block.sublist(1), <String>[
        AppIconStep.unrestorableGuide,
        '    $ios1024Path',
      ]);
      expect(run.lines, isNot(contains(AppIconStep.restoreGuide)));
    });

    test('T-28-SAFE-10: 새 adaptive XML 을 지우지 못함 → 쓰기 전으로 되돌림 머리 · '
        '지우기 안내 아래 그 경로와 OS 까닭', () async {
      blockLastForeground();
      final overrides = FileFaultOverrides(
        <String, ({FileFault fault, int call})>{
          '${box.root}/$adaptiveIconXmlPath': (
            fault: FileFault.failDelete,
            call: 0,
          ),
        },
      );
      final run = _GitRun(box, <String?>['1', source, '2'], kitDigests: kit)
        ..registerSource(source, sourceBytes);

      expect(await run.run(overrides: overrides), wizardExitStopped);

      final List<String> block = readFailureBlock(run.lines);
      expect(block.first, startsWith(rolledBackLineHead));
      expect(block.sublist(1), <String>[
        AppIconStep.deleteGuide,
        '    $adaptiveIconXmlPath (주입한 실패)',
      ]);
      expect(box.repoFile(adaptiveIconXmlPath).existsSync(), isTrue);
      for (final HomeIconFile file in homeIconFiles) {
        expect(
          box.repoFile(file.relativePath).readAsStringSync(),
          'kit:${file.relativePath}',
          reason: file.relativePath,
        );
      }
    });

    test('T-28-SAFE-11: 있던 홈 화면 파일을 앞 절반만 쓰고 실패 → 그 파일도 '
        '떠 둔 바이트로 되돌림 · 27경로 = 실행 전', () async {
      final String broken = homeIconFiles[3].relativePath;
      final Map<String, List<int>?> before = box.readWriteTargets();
      final overrides = FileFaultOverrides(
        <String, ({FileFault fault, int call})>{
          '${box.root}/$broken': (fault: FileFault.partialWrite, call: 1),
        },
      );
      final run = _GitRun(box, <String?>['1', source, '2'], kitDigests: kit)
        ..registerSource(source, sourceBytes);

      expect(await run.run(overrides: overrides), wizardExitStopped);

      expect(overrides.firedPaths, <String>['${box.root}/$broken']);
      final List<String> block = readFailureBlock(run.lines);
      expect(block, hasLength(1));
      expect(block.single, startsWith(rolledBackLineHead));
      expect(block.single, contains('$broken (주입한 실패)'));
      expect(box.readWriteTargets(), before);
      expect(box.readStatus(), isEmpty);
    });
  });
}
