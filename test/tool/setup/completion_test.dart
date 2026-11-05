import 'dart:io';

import 'package:test/test.dart';

import '../../../tool/setup/command_runner.dart';
import '../../../tool/setup/completion.dart';
import '../../../tool/setup/steps/app_names_step.dart';
import 'fakes.dart';

const String _gitStatusKey = 'git status --porcelain --untracked-files=no';

/// 끝 요약에 보일 golden 갱신 안내 줄(들여쓰기 없음).
const String goldenSummaryLine =
    'ko 앱 이름(홈 화면 제목)이 마지막 커밋과 달라 홈 화면 golden 2장이 다시 '
    '찍혀야 합니다: fvm flutter test --update-goldens '
    'test/features/home/home_announcement_golden_test.dart';

/// 영어(template) ARB 의 저장소 상대 경로.
const String summaryEnglishArbPath = 'lib/l10n/app_en.arb';

/// ko ARB 의 저장소 상대 경로.
const String summaryKoArbPath = 'lib/l10n/app_ko.arb';

/// 커밋된 상태(HEAD)의 [relativePath] 파일을 읽는 git 명령 키를 만든다.
String buildSummaryGitShowKey(String relativePath) =>
    'git show HEAD:$relativePath';

/// `appTitle` 이 [title] 인 영어 ARB 본문을 만든다.
String buildSummaryEnglishArb(String title) =>
    '{\n  "@@locale": "en",\n  "appTitle": "$title"\n}\n';

/// ko ARB 본문을 만든다 — [title] 이 null 이면 `appTitle` 을 두지 않는다.
String buildSummaryKoArb(String? title) => title == null
    ? '{\n  "@@locale": "ko"\n}\n'
    : '{\n  "@@locale": "ko",\n  "appTitle": "$title"\n}\n';

/// [root] 아래 [relativePath] 에 [content] 를 쓴다 — 상위 디렉터리는 만든다.
void writeSummaryFixtureFile(String root, String relativePath, String content) {
  File('$root/$relativePath')
    ..parent.createSync(recursive: true)
    ..writeAsStringSync(content);
}

/// 끝 요약 fixture 를 [root] 에 쓴다 — Gradle 파일은 두지 않는다.
///
/// `arb-dir` 이 [arbDir] 인 `l10n.yaml` · 영어 ARB(`appTitle` = [englishTitle]) ·
/// ja ARB · `appTitle` 이 [koTitle] 인 ko ARB(null 이면 키 없음)를 두고,
/// [withGoldenTest] 가 true 면 홈 화면 golden 시험 파일(빈 파일)을 둔다. ARB
/// 파일은 언제나 `lib/l10n/` 아래에 둔다.
void writeCompletionFixture(
  String root, {
  String? koTitle = '마이앱',
  String englishTitle = 'My App',
  String arbDir = 'lib/l10n',
  bool withGoldenTest = true,
}) {
  writeSummaryFixtureFile(
    root,
    'l10n.yaml',
    'arb-dir: $arbDir\ntemplate-arb-file: app_en.arb\n',
  );
  writeSummaryFixtureFile(
    root,
    summaryEnglishArbPath,
    buildSummaryEnglishArb(englishTitle),
  );
  writeSummaryFixtureFile(
    root,
    'lib/l10n/app_ja.arb',
    '{\n  "@@locale": "ja",\n  "appTitle": "マイアプリ"\n}\n',
  );
  writeSummaryFixtureFile(root, summaryKoArbPath, buildSummaryKoArb(koTitle));
  if (withGoldenTest) {
    writeSummaryFixtureFile(
      root,
      'test/features/home/home_announcement_golden_test.dart',
      '',
    );
  }
}

/// 추적 파일 상태로 [statusOutput] 을 돌려주는 가짜 실행기를 만든다.
///
/// 커밋된 상태(HEAD)의 ko ARB 는 [committedKoTitle](null 이면 `appTitle` 없음),
/// 영어 ARB 는 `appTitle` 이 [committedEnglishTitle] 인 본문이다.
/// [isHeadReadable] 이 false 면 두 파일 모두 HEAD 에서 읽지 못한다.
FakeCommandRunner buildStatusRunner(
  String statusOutput, {
  String? committedKoTitle,
  String committedEnglishTitle = 'My App',
  bool isHeadReadable = true,
}) {
  const missing = CommandResult(
    128,
    '',
    "fatal: path does not exist in 'HEAD'",
  );
  return FakeCommandRunner()
    ..on(_gitStatusKey, CommandResult(0, statusOutput, ''))
    ..on(
      buildSummaryGitShowKey(summaryKoArbPath),
      isHeadReadable
          ? CommandResult(0, buildSummaryKoArb(committedKoTitle), '')
          : missing,
    )
    ..on(
      buildSummaryGitShowKey(summaryEnglishArbPath),
      isHeadReadable
          ? CommandResult(0, buildSummaryEnglishArb(committedEnglishTitle), '')
          : missing,
    );
}

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
    'T-23-SUM-01 ko ARB 가 바뀌어 ko 제목이 커밋된 것과 다르면 커밋 안내 뒤 golden 안내 한 줄 · git status 1회',
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
      // 위저드는 golden 갱신 명령을 실행하지 않는다 — git status 한 번과 커밋된
      // ko · 영어 ARB 읽기뿐이다.
      expect(runner.calls.map((FakeCall call) => call.key), <String>[
        _gitStatusKey,
        buildSummaryGitShowKey(summaryKoArbPath),
        buildSummaryGitShowKey(summaryEnglishArbPath),
      ]);
      expect(runner.countCalls(RunMode.capture, _gitStatusKey), 1);
    },
  );

  test('T-23-SUM-02 ko 제목이 커밋된 기본 이름과 같으면 golden 안내 0 · 그 밖 출력은 같다', () async {
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
  test(
    'T-23-SUM-05 영어 ARB 만 바뀌고 ko 에 이름이 없으면 ko 제목이 바뀌어 golden 안내 한 줄',
    () async {
      writeCompletionFixture(root, koTitle: null);
      final FakeCommandRunner runner = buildStatusRunner(
        ' M lib/l10n/app_en.arb\n',
        committedEnglishTitle: 'StarterKit',
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
          ...buildCommitHintLines(summaryEnglishArbPath),
          '',
          goldenSummaryLine,
        ]),
      );
    },
  );

  test('T-23-SUM-05 영어 ARB 가 바뀌어도 ko 제목이 커밋된 것과 같으면 golden 안내 0', () async {
    writeCompletionFixture(root, koTitle: null);
    final FakeCommandRunner runner = buildStatusRunner(
      ' M lib/l10n/app_en.arb\n',
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
        ...buildCommitHintLines(summaryEnglishArbPath),
      ]),
    );
  });

  test('T-23-SUM-05 커밋된 상태를 읽지 못하면 ko ARB 가 바뀌어도 golden 안내 0', () async {
    writeCompletionFixture(root);
    final FakeCommandRunner runner = buildStatusRunner(
      ' M lib/l10n/app_ko.arb\n',
      isHeadReadable: false,
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
        ...buildCommitHintLines(summaryKoArbPath),
      ]),
    );
  });
  test(
    'T-23-SUM-06 l10n.yaml 의 arb-dir 이 ./ 로 시작해도 ko ARB 변경을 알아보고 golden 안내 한 줄',
    () async {
      writeCompletionFixture(root, arbDir: './lib/l10n');
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
          ...buildCommitHintLines(summaryKoArbPath),
          '',
          goldenSummaryLine,
        ]),
      );
    },
  );
}
