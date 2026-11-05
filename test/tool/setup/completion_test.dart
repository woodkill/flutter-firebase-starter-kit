import 'dart:io';

import 'package:test/test.dart';

import '../../../tool/setup/command_runner.dart';
import '../../../tool/setup/completion.dart';
import '../../../tool/setup/steps/app_names_step.dart';
import 'fakes.dart';

const String _gitStatusKey = 'git status --porcelain --untracked-files=no';

/// 끝 요약에 보일 golden 갱신 안내 줄(들여쓰기 없음).
const String goldenSummaryLine =
    'ko 이름이 기본 이름과 다르므로 홈 화면 golden 2장이 다시 찍혀야 합니다: '
    'fvm flutter test --update-goldens '
    'test/features/home/home_announcement_golden_test.dart';

/// [root] 아래 [relativePath] 에 [content] 를 쓴다 — 상위 디렉터리는 만든다.
void writeSummaryFixtureFile(String root, String relativePath, String content) {
  File('$root/$relativePath')
    ..parent.createSync(recursive: true)
    ..writeAsStringSync(content);
}

/// 끝 요약 fixture 를 [root] 에 쓴다 — Gradle 파일은 두지 않는다.
///
/// `l10n.yaml` · 영어 ARB(`My App`) · ja ARB · `appTitle` 이 [koTitle] 인 ko
/// ARB 를 두고, [withGoldenTest] 가 true 면 홈 화면 golden 시험 파일(빈 파일)을
/// 둔다.
void writeCompletionFixture(
  String root, {
  String koTitle = '마이앱',
  bool withGoldenTest = true,
}) {
  writeSummaryFixtureFile(
    root,
    'l10n.yaml',
    'arb-dir: lib/l10n\ntemplate-arb-file: app_en.arb\n',
  );
  writeSummaryFixtureFile(
    root,
    'lib/l10n/app_en.arb',
    '{\n  "@@locale": "en",\n  "appTitle": "My App"\n}\n',
  );
  writeSummaryFixtureFile(
    root,
    'lib/l10n/app_ja.arb',
    '{\n  "@@locale": "ja",\n  "appTitle": "マイアプリ"\n}\n',
  );
  writeSummaryFixtureFile(
    root,
    'lib/l10n/app_ko.arb',
    '{\n  "@@locale": "ko",\n  "appTitle": "$koTitle"\n}\n',
  );
  if (withGoldenTest) {
    writeSummaryFixtureFile(
      root,
      'test/features/home/home_announcement_golden_test.dart',
      '',
    );
  }
}

/// 추적 파일 상태로 [statusOutput] 을 돌려주는 가짜 실행기를 만든다.
FakeCommandRunner buildStatusRunner(String statusOutput) =>
    FakeCommandRunner()..on(_gitStatusKey, CommandResult(0, statusOutput, ''));

/// 바뀐 파일이 [path] 하나일 때의 커밋 안내 줄들(앞 빈 줄 포함)을 만든다.
List<String> buildCommitHintLines(String path) => <String>[
  '',
  commitHintHeading,
  '  $path',
  '  \$ git add $path && git commit -m "$commitHintMessage"',
];

/// 끝 요약 출력 전체를 줄 목록 [lines] 로 이어 만든다.
String joinOutputLines(List<String> lines) =>
    lines.map((String line) => '$line\n').join();

void main() {
  late Directory tempDir;
  late String root;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('completion_test_');
    root = tempDir.path;
  });

  tearDown(() {
    tempDir.deleteSync(recursive: true);
  });

  test(
    'T-23-SUM-01 ko ARB 가 바뀌고 기본 이름과 다르면 커밋 안내 뒤 golden 안내 한 줄 · git status 1회',
    () async {
      writeCompletionFixture(root);
      final FakeCommandRunner runner = buildStatusRunner(
        ' M lib/l10n/app_ko.arb\n',
      );
      final terminal = ScriptedTerminal(const <String?>[]);

      await showCompletionSummary(
        buildTestContext(projectRoot: root, runner: runner, terminal: terminal),
      );

      expect(
        terminal.output.toString(),
        joinOutputLines(<String>[
          '',
          providersHintLine,
          ...buildCommitHintLines('lib/l10n/app_ko.arb'),
          '',
          goldenSummaryLine,
        ]),
      );
      expect(AppNamesStep.goldenHintLine, goldenSummaryLine);
      // 위저드는 golden 갱신 명령을 실행하지 않는다 — git status 한 번뿐이다.
      expect(runner.calls.map((FakeCall call) => call.key), <String>[
        _gitStatusKey,
      ]);
      expect(runner.countCalls(RunMode.capture, _gitStatusKey), 1);
    },
  );

  test('T-23-SUM-02 ko 이름이 기본 이름과 같으면 golden 안내 0 · 그 밖 출력은 같다', () async {
    writeCompletionFixture(root, koTitle: 'My App');
    final FakeCommandRunner runner = buildStatusRunner(
      ' M lib/l10n/app_ko.arb\n',
    );
    final terminal = ScriptedTerminal(const <String?>[]);

    await showCompletionSummary(
      buildTestContext(projectRoot: root, runner: runner, terminal: terminal),
    );

    expect(
      terminal.output.toString(),
      joinOutputLines(<String>[
        '',
        providersHintLine,
        ...buildCommitHintLines('lib/l10n/app_ko.arb'),
      ]),
    );
    expect(runner.countCalls(RunMode.capture, _gitStatusKey), 1);
  });

  test('T-23-SUM-03 ko ARB 가 바뀐 목록에 없으면 ko 가 달라도 golden 안내 0', () async {
    writeCompletionFixture(root);
    final FakeCommandRunner runner = buildStatusRunner(
      ' M lib/l10n/app_ja.arb\n',
    );
    final terminal = ScriptedTerminal(const <String?>[]);

    await showCompletionSummary(
      buildTestContext(projectRoot: root, runner: runner, terminal: terminal),
    );

    expect(
      terminal.output.toString(),
      joinOutputLines(<String>[
        '',
        providersHintLine,
        ...buildCommitHintLines('lib/l10n/app_ja.arb'),
      ]),
    );
    expect(runner.countCalls(RunMode.capture, _gitStatusKey), 1);
  });

  test('T-23-SUM-03 바뀐 파일이 없으면 커밋 안내 · golden 안내 모두 0', () async {
    writeCompletionFixture(root);
    final FakeCommandRunner runner = buildStatusRunner('');
    final terminal = ScriptedTerminal(const <String?>[]);

    await showCompletionSummary(
      buildTestContext(projectRoot: root, runner: runner, terminal: terminal),
    );

    expect(
      terminal.output.toString(),
      joinOutputLines(<String>['', providersHintLine]),
    );
    expect(runner.countCalls(RunMode.capture, _gitStatusKey), 1);
  });

  test('T-23-SUM-04 showCommitHint 를 직접 부르면 커밋 안내만 나오고 golden 줄은 없다', () async {
    writeCompletionFixture(root);
    final FakeCommandRunner runner = buildStatusRunner(
      ' M lib/l10n/app_ko.arb\n',
    );
    final terminal = ScriptedTerminal(const <String?>[]);

    await showCommitHint(
      buildTestContext(projectRoot: root, runner: runner, terminal: terminal),
    );

    expect(
      terminal.output.toString(),
      joinOutputLines(buildCommitHintLines('lib/l10n/app_ko.arb')),
    );
    expect(runner.countCalls(RunMode.capture, _gitStatusKey), 1);
  });
}
