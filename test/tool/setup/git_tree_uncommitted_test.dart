import 'dart:io';
import 'dart:math';

import 'package:test/test.dart';

import '../../../tool/setup/git_tree.dart';
import '../../../tool/setup/redactor.dart';
import '../../../tool/setup/terminal.dart';
import '../../../tool/setup/wizard.dart';
import 'fake_rest_client.dart';
import 'fakes.dart';
import 'home_icon_fixture.dart';

/// 임시 저장소 [root] 의 [relativePath] 에 [content] 를 쓴다.
void writeRepoText(String root, String relativePath, String content) {
  File('$root/$relativePath')
    ..parent.createSync(recursive: true)
    ..writeAsStringSync(content);
}

void main() {
  late Directory base;
  late String root;
  late IconFlowRunner runner;
  late WizardContext context;

  setUp(() {
    base = Directory.systemTemp.createTempSync('git_tree_uncommitted_');
    root = '${base.path}/repo';
    Directory(root).createSync();
    runner = IconFlowRunner(root, FakeCommandRunner());
    final log = MemoryLogSink(Redactor());
    context = WizardContext(
      projectRoot: root,
      runner: runner,
      terminal: RedactingTerminal(
        ScriptedTerminal(const <String?>[]),
        log.redactor,
        log,
      ),
      redactor: log.redactor,
      log: log,
      rest: FakeRestClient(),
      homeDirectory: noKeystoreTestHome,
      random: Random(fixedTestRandomSeed),
      now: () => fixedTestNow,
    );
  });

  tearDown(() => base.deleteSync(recursive: true));

  test('T-28-GIT-01: 수정한 tracked · 추적 안 된 새 파일은 잡고 깨끗한 tracked · '
      '목록 밖 · gitignored 는 잡지 않는다', () async {
    initGitFixture(root);
    writeRepoText(root, '.gitignore', 'ignored.png\n');
    writeRepoText(root, 'icons/changed.png', 'a');
    writeRepoText(root, 'icons/clean.png', 'b');
    writeRepoText(root, 'outside/changed.png', 'c');
    commitGitFixture(root, 'init');
    writeRepoText(root, 'icons/changed.png', 'a2');
    writeRepoText(root, 'outside/changed.png', 'c2');
    writeRepoText(root, 'icons/new/fresh.png', 'd');
    writeRepoText(root, 'outside/fresh.png', 'e');
    writeRepoText(root, 'ignored.png', 'f');

    final List<String> found = await findUncommittedFiles(context, <String>[
      'icons/changed.png',
      'icons/clean.png',
      'icons/new/fresh.png',
      'ignored.png',
    ]);

    expect(
      found,
      unorderedEquals(<String>['icons/changed.png', 'icons/new/fresh.png']),
    );
    expect(runner.gitKeys, hasLength(1));
    expect(runner.gitKeys.single, contains('--untracked-files=all'));
    expect(runner.gitWorkingDirectories.single, root);
  });

  test('T-28-GIT-02: 공백이 든 경로는 따옴표를 떼고 ./ 로 시작한 경로도 맞춘다', () async {
    initGitFixture(root);
    writeRepoText(root, 'dir with space/icon file.png', 'a');
    commitGitFixture(root, 'init');
    writeRepoText(root, 'dir with space/icon file.png', 'a2');
    writeRepoText(root, 'new dir/new icon.png', 'b');

    final List<String> found = await findUncommittedFiles(context, <String>[
      './dir with space/icon file.png',
      'new dir/new icon.png',
    ]);

    expect(
      found,
      unorderedEquals(<String>[
        'dir with space/icon file.png',
        'new dir/new icon.png',
      ]),
    );
    expect(await findUncommittedFiles(context, const <String>[]), isEmpty);
  });

  test('T-28-GIT-03: git 이 실패하면 GitTreeException', () async {
    writeRepoText(root, 'icons/a.png', 'a');

    await expectLater(
      findUncommittedFiles(context, const <String>['icons/a.png']),
      throwsA(isA<GitTreeException>()),
    );
    expect(runner.gitKeys, hasLength(1));
  });
}
