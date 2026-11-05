import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

import '../../../tool/setup/command_runner.dart';
import '../../../tool/setup/step.dart';
import '../../../tool/setup/steps/app_names_step.dart';
import '../../../tool/setup/wizard.dart';
import 'fakes.dart';

const String _gitStatusKey = 'git status --porcelain --untracked-files=no';
const CommandResult _cleanTree = CommandResult(0, '', '');

/// 시험 fixture 의 기본 원어 이름 표 — 킷 lib 표와 같은 세 항목.
const Map<String, String> kitEndonyms = <String, String>{
  'en': 'English',
  'ko': '한국어',
  'ja': '日本語',
};

/// 시험 fixture 의 `l10n.yaml` 본문(두 줄).
const String fixtureL10nYaml =
    'arb-dir: lib/l10n\n'
    'template-arb-file: app_en.arb\n';

/// ko · ja 질문이 모두 끝난 뒤 확인 표 머리 줄.
const String confirmHeading = '── 언어별 앱 이름 — 확인 ──';

/// 홈 화면 golden 시험 파일의 저장소 상대 경로.
const String goldenTestFixturePath =
    'test/features/home/home_announcement_golden_test.dart';

/// 단계 실행 직후 화면에 보일 golden 갱신 안내 줄(들여쓰기 포함).
const String goldenHintText =
    '  ko 이름이 기본 이름과 다르므로 홈 화면 golden 2장이 다시 찍혀야 합니다: '
    'fvm flutter test --update-goldens '
    'test/features/home/home_announcement_golden_test.dart';

/// [root] 아래 [relativePath] 에 [content] 를 쓴다 — 상위 디렉터리는 만든다.
void writeFixtureFile(String root, String relativePath, String content) {
  File('$root/$relativePath')
    ..parent.createSync(recursive: true)
    ..writeAsStringSync(content);
}

/// `appTitle` 값이 [appTitle] 인 영어 ARB fixture 본문을 만든다.
String buildEnglishArb(String appTitle) =>
    '{\n'
    '  "@@locale": "en",\n'
    '\n'
    '  "appTitle": ${jsonEncode(appTitle)},\n'
    '  "@appTitle": {\n'
    '    "description": "App name on the home screen"\n'
    '  },\n'
    '\n'
    '  "commonOk": "OK",\n'
    '  "@commonOk": {\n'
    '    "description": "Confirm button"\n'
    '  }\n'
    '}\n';

/// [locale] ARB fixture 본문을 만든다 — [titleJson] 이 있으면 `appTitle` 줄을 둔다.
///
/// [titleJson] 은 JSON 값 글자 그대로다(`"마이앱"` · `12`).
String buildLocalizedArb(String locale, {String? titleJson}) =>
    '{\n'
    '  "@@locale": "$locale",\n'
    '${titleJson == null ? '' : '  "appTitle": $titleJson,\n'}'
    '\n'
    '  "commonOk": "확인"\n'
    '}\n';

/// 원어 이름 표 [endonyms] 를 담은 lib 소스 사본 본문을 만든다.
String buildEndonymsSource(Map<String, String> endonyms) =>
    "import 'package:flutter/widgets.dart' show Locale;\n"
    '\n'
    'const Map<String, String> kLocaleEndonyms = <String, String>{\n'
    '${endonyms.entries.map((MapEntry<String, String> entry) => "  '${entry.key}': '${entry.value}',\n").join()}'
    '};\n'
    '\n'
    'String localeDisplayName(Locale locale) =>\n'
    '    kLocaleEndonyms[locale.languageCode] ?? locale.languageCode;\n';

/// 언어별 앱 이름 단계 fixture 를 [root] 에 쓴다.
///
/// [localizedTitles] 의 locale 마다 ARB 를 두고, 값이 null 이 아니면 그 문자열을
/// `appTitle` 로 넣는다. [endonyms] 가 null 이면 원어 이름 표 사본을 두지 않고,
/// [appName] 이 null 이면 `config/dev.json` 을 두지 않는다. [withGoldenTest] 가
/// true 면 홈 화면 golden 시험 파일(빈 파일)을 둔다.
void writeAppNamesFixture(
  String root, {
  Map<String, String?> localizedTitles = const <String, String?>{
    'ja': null,
    'ko': null,
  },
  String englishTitle = 'My App',
  String? appName = 'My App Dev',
  Map<String, String>? endonyms = kitEndonyms,
  bool withL10nYaml = true,
  bool withGoldenTest = true,
}) {
  if (withL10nYaml) writeFixtureFile(root, 'l10n.yaml', fixtureL10nYaml);
  if (withGoldenTest) writeFixtureFile(root, goldenTestFixturePath, '');
  writeFixtureFile(root, 'lib/l10n/app_en.arb', buildEnglishArb(englishTitle));
  for (final MapEntry<String, String?> entry in localizedTitles.entries) {
    final String? title = entry.value;
    writeFixtureFile(
      root,
      'lib/l10n/app_${entry.key}.arb',
      buildLocalizedArb(
        entry.key,
        titleJson: title == null ? null : jsonEncode(title),
      ),
    );
  }
  if (endonyms != null) {
    writeFixtureFile(
      root,
      'lib/core/l10n/locale_display_names.dart',
      buildEndonymsSource(endonyms),
    );
  }
  if (appName != null) {
    writeFixtureFile(
      root,
      'config/dev.json',
      '{\n  "appName": ${jsonEncode(appName)}\n}\n',
    );
  }
}

/// [root] 아래 모든 파일의 저장소 상대 경로 → 바이트 사본을 만든다.
Map<String, List<int>> snapshotTree(String root) => <String, List<int>>{
  for (final File file in Directory(
    root,
  ).listSync(recursive: true).whereType<File>())
    file.path.substring(root.length + 1): file.readAsBytesSync(),
};

/// [terminal] 이 [question] 을 물은 횟수.
int countAsks(ScriptedTerminal terminal, String question) =>
    terminal.asks.where((String ask) => ask == question).length;

/// [terminal] 이 물은 질문 가운데 언어별 이름 질문만 순서대로 모은다.
List<String> collectNameAsks(ScriptedTerminal terminal) =>
    terminal.asks.where((String ask) => ask.contains(' 앱 이름')).toList();

/// [reason] 사유의 [Todo] 와 맞는 matcher.
Matcher isTodo(Object? reason) =>
    isA<Todo>().having((Todo result) => result.reason, 'reason', reason);

/// [summary] 요약의 [Done] 과 맞는 matcher.
Matcher isDone(Object? summary) =>
    isA<Done>().having((Done result) => result.summary, 'summary', summary);

void main() {
  late Directory tempDir;
  late String root;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('app_names_step_test_');
    root = tempDir.path;
  });

  tearDown(() {
    tempDir.deleteSync(recursive: true);
  });

  String readFile(String relativePath) =>
      File('$root/$relativePath').readAsStringSync();

  /// 깨끗한 작업 트리를 돌려주는 가짜 실행기를 만든다.
  FakeCommandRunner buildCleanRunner() =>
      FakeCommandRunner()..on(_gitStatusKey, _cleanTree);

  /// 앱 정체성 대역 · 언어별 앱 이름 단계로 위저드를 돌린다.
  Future<int> runAppNamesStep(
    FakeCommandRunner runner,
    ScriptedTerminal terminal,
  ) => runWizard(
    buildTestContext(projectRoot: root, runner: runner, terminal: terminal),
    <Step>[
      const DoneStandInStep(id: 'identity', title: '앱 정체성'),
      AppNamesStep(),
    ],
  );

  /// 단계 하나를 직접 검사한다.
  Future<CheckResult> checkStep(AppNamesStep step) =>
      step.check(buildTestContext(projectRoot: root));

  test(
    'T-23-NAMES-01 appTitle 없는 ja · ko 를 묻고 확인 표 뒤 삽입해 다시 검사하면 ✓ 다',
    () async {
      writeAppNamesFixture(root);
      final String englishBefore = readFile('lib/l10n/app_en.arb');
      final int koLinesBefore = readFile(
        'lib/l10n/app_ko.arb',
      ).split('\n').length;

      expect(
        await checkStep(AppNamesStep()),
        isTodo('lib/l10n/app_ja.arb · app_ko.arb 에 appTitle 이 없습니다'),
      );

      final terminal = ScriptedTerminal(const <String?>[
        'y',
        'マイアプリ',
        '마이앱',
        '1',
      ]);
      final int code = await runAppNamesStep(buildCleanRunner(), terminal);
      final output = terminal.output.toString();

      expect(code, wizardExitDone);
      expect(output, contains('▶ 언어별 앱 이름'));
      expect(
        output,
        contains(
          '  기본 이름은 "My App" 입니다. flavor 접미사(" Dev")는 빌드가 붙이므로 '
          '접미사 없는 이름을 입력하고,\n'
          '  기본 이름 그대로 쓰려면 Enter 를 누릅니다.\n',
        ),
      );
      expect(collectNameAsks(terminal), <String>[
        '  ja (日本語) 앱 이름',
        '  ko (한국어) 앱 이름',
      ]);
      expect(output, contains(confirmHeading));
      expect(
        RegExp(r'^  ja \(日本語\) +マイアプリ$', multiLine: true).hasMatch(output),
        isTrue,
      );
      expect(
        RegExp(r'^  ko \(한국어\) +마이앱$', multiLine: true).hasMatch(output),
        isTrue,
      );
      expect(output, contains('  · dev 빌드에서는 뒤에 " Dev" 가 붙어 보입니다'));
      expect(
        output,
        contains(
          '이 값으로 진행할까요, 고칠까요?\n'
          '  1) 이대로 진행\n'
          '  2) ja 고치기\n'
          '  3) ko 고치기\n',
        ),
      );
      expect(output, contains('  ✓ 언어별 앱 이름 — ja マイアプリ · ko 마이앱'));

      expect(
        readFile('lib/l10n/app_ko.arb'),
        '{\n'
        '  "@@locale": "ko",\n'
        '\n'
        '  "appTitle": "마이앱",\n'
        '\n'
        '  "commonOk": "확인"\n'
        '}\n',
      );
      expect(
        readFile('lib/l10n/app_ko.arb').split('\n').length,
        koLinesBefore + 2,
      );
      expect(
        readFile('lib/l10n/app_ja.arb'),
        '{\n'
        '  "@@locale": "ja",\n'
        '\n'
        '  "appTitle": "マイアプリ",\n'
        '\n'
        '  "commonOk": "확인"\n'
        '}\n',
      );
      expect(readFile('lib/l10n/app_en.arb'), englishBefore);
    },
  );

  test('T-23-NAMES-02 Enter 는 기본 이름을 값으로 기록하고 다시 실행하면 질문 없이 ✓ 다', () async {
    writeAppNamesFixture(root);
    final terminal = ScriptedTerminal(const <String?>['y', '', '', '1']);
    expect(await runAppNamesStep(buildCleanRunner(), terminal), wizardExitDone);
    expect(readFile('lib/l10n/app_ja.arb'), contains('"appTitle": "My App"'));
    expect(readFile('lib/l10n/app_ko.arb'), contains('"appTitle": "My App"'));

    expect(await checkStep(AppNamesStep()), isDone('ja My App · ko My App'));

    final Map<String, List<int>> snapshot = snapshotTree(root);
    final again = ScriptedTerminal(const <String?>[]);
    expect(await runAppNamesStep(FakeCommandRunner(), again), wizardExitDone);
    expect(again.asks, isEmpty);
    expect(snapshotTree(root), snapshot);
  });

  test('T-23-NAMES-03 config 이름이 접미사로 끝나지 않으면 머리 안내 한 줄 · 접미사 노트 없음', () async {
    writeAppNamesFixture(root, appName: 'My App');
    final terminal = ScriptedTerminal(const <String?>[
      'y',
      'マイアプリ',
      '마이앱',
      '1',
    ]);
    expect(await runAppNamesStep(buildCleanRunner(), terminal), wizardExitDone);
    final output = terminal.output.toString();
    expect(
      output,
      contains('  기본 이름은 "My App" 입니다. 기본 이름 그대로 쓰려면 Enter 를 누릅니다.\n'),
    );
    expect(output, isNot(contains('flavor 접미사')));
    expect(output, contains(confirmHeading));
    expect(output, isNot(contains('빌드에서는 뒤에')));
  });

  test('T-23-NAMES-04 계획 줄은 대상 ARB 를 적은 안내 한 줄이고 끝난 뒤에는 없다', () async {
    writeAppNamesFixture(root);
    final step = AppNamesStep();
    final WizardContext context = buildTestContext(projectRoot: root);
    expect(await step.check(context), isA<Todo>());
    const expectedLine =
        '(lib/l10n/app_ja.arb · app_ko.arb 의 appTitle 에 입력한 이름을 씀 — '
        '키가 없으면 더하고 있으면 바꾸며, 다음 pub get · 빌드가 '
        'lib/l10n/generated/ 를 다시 만듭니다)';
    expect(step.plannedCommandLines(context), <String>[expectedLine]);

    final terminal = ScriptedTerminal(const <String?>['y', '', '', '1']);
    await runAppNamesStep(buildCleanRunner(), terminal);
    final doneStep = AppNamesStep();
    expect(await doneStep.check(context), isA<Done>());
    expect(doneStep.plannedCommandLines(context), isEmpty);
  });

  test('T-23-NAMES-05 원어 이름 표가 없으면 코드만 보이고 진행은 같다', () async {
    writeAppNamesFixture(root, endonyms: null);
    final terminal = ScriptedTerminal(const <String?>[
      'y',
      'マイアプリ',
      '마이앱',
      '1',
    ]);
    expect(await runAppNamesStep(buildCleanRunner(), terminal), wizardExitDone);
    expect(collectNameAsks(terminal), <String>['  ja 앱 이름', '  ko 앱 이름']);
    expect(
      terminal.output.toString(),
      contains('  ✓ 언어별 앱 이름 — ja マイアプリ · ko 마이앱'),
    );
  });

  test('T-23-NAMES-05 표에 없는 언어는 코드만 · 있는 언어는 원어 이름을 붙인다', () async {
    writeAppNamesFixture(
      root,
      localizedTitles: const <String, String?>{
        'fr': null,
        'ja': null,
        'ko': null,
      },
      endonyms: const <String, String>{'ko': '한국어'},
    );
    final terminal = ScriptedTerminal(const <String?>[
      'y',
      'Mon App',
      'マイアプリ',
      '마이앱',
      '1',
    ]);
    expect(await runAppNamesStep(buildCleanRunner(), terminal), wizardExitDone);
    expect(collectNameAsks(terminal), <String>[
      '  fr 앱 이름',
      '  ja 앱 이름',
      '  ko (한국어) 앱 이름',
    ]);
  });

  const jaQuestion = '  ja (日本語) 앱 이름';
  const koQuestion = '  ko (한국어) 앱 이름';

  test('T-23-NAMES-06 접미사로 끝나는 입력은 안내 뒤 그 언어만 다시 묻는다', () async {
    writeAppNamesFixture(root);
    final terminal = ScriptedTerminal(const <String?>[
      'y',
      'マイアプリ',
      '마이앱 Dev',
      '마이앱 Stg',
      '마이앱',
      '1',
    ]);
    expect(await runAppNamesStep(buildCleanRunner(), terminal), wizardExitDone);
    final output = terminal.output.toString();
    expect(output, contains('  " Dev" 는 dev 빌드가 붙이므로 접미사 없는 이름을 입력하세요\n'));
    expect(output, contains('  " Stg" 는 stg 빌드가 붙이므로 접미사 없는 이름을 입력하세요\n'));
    expect(countAsks(terminal, jaQuestion), 1);
    expect(countAsks(terminal, koQuestion), 3);
    expect(readFile('lib/l10n/app_ko.arb'), contains('"appTitle": "마이앱",'));
    expect(output, contains('  ✓ 언어별 앱 이름 — ja マイアプリ · ko 마이앱'));
  });

  test('T-23-NAMES-07 이어진 공백은 안내 뒤 다시 묻고 기본 이름과 같은 입력은 그대로 기록한다', () async {
    writeAppNamesFixture(root);
    final terminal = ScriptedTerminal(const <String?>[
      'y',
      'My App',
      '마이  앱',
      '마이앱',
      '1',
    ]);
    expect(await runAppNamesStep(buildCleanRunner(), terminal), wizardExitDone);
    final output = terminal.output.toString();
    expect(output, contains('  낱말 사이 공백은 한 칸으로 둡니다\n'));
    expect(countAsks(terminal, jaQuestion), 1);
    expect(countAsks(terminal, koQuestion), 2);
    expect(readFile('lib/l10n/app_ja.arb'), contains('"appTitle": "My App",'));
    expect(output, contains('  ✓ 언어별 앱 이름 — ja My App · ko 마이앱'));
  });

  test('T-23-NAMES-08 한 언어가 3회 틀리면 실패하고 어떤 ARB 도 쓰지 않는다', () async {
    writeAppNamesFixture(root);
    final Map<String, List<int>> before = snapshotTree(root);
    final terminal = ScriptedTerminal(const <String?>[
      'y',
      'マイ  アプリ',
      'マイ  アプリ',
      'マイ  アプリ',
      '2',
    ]);
    expect(
      await runAppNamesStep(buildCleanRunner(), terminal),
      wizardExitStopped,
    );
    expect(
      terminal.output.toString(),
      contains('  실패 — 언어별 앱 이름 형식이 맞지 않아 진행하지 않았습니다\n'),
    );
    expect(countAsks(terminal, jaQuestion), 3);
    expect(countAsks(terminal, koQuestion), 0);
    expect(snapshotTree(root), before);
  });

  test('T-23-NAMES-08 실패 뒤 다시 시도를 고르면 처음부터 다시 묻는다', () async {
    writeAppNamesFixture(root);
    final terminal = ScriptedTerminal(const <String?>[
      'y',
      'マイ  アプリ',
      'マイ  アプリ',
      'マイ  アプリ',
      '1',
      'マイアプリ',
      '마이앱',
      '1',
    ]);
    expect(await runAppNamesStep(buildCleanRunner(), terminal), wizardExitDone);
    expect(countAsks(terminal, jaQuestion), 4);
    expect(countAsks(terminal, koQuestion), 1);
    expect(
      terminal.output.toString(),
      contains('  ✓ 언어별 앱 이름 — ja マイアプリ · ko 마이앱'),
    );
  });

  test('T-23-NAMES-09 확인 표의 고치기는 그 언어만 다시 묻고 표를 다시 보인다', () async {
    writeAppNamesFixture(root);
    final terminal = ScriptedTerminal(const <String?>[
      'y',
      'マイアプリ',
      '마이앱',
      '3',
      '마이 앱',
      '1',
    ]);
    expect(await runAppNamesStep(buildCleanRunner(), terminal), wizardExitDone);
    final output = terminal.output.toString();
    expect(confirmHeading.allMatches(output).length, 2);
    expect(countAsks(terminal, jaQuestion), 1);
    expect(countAsks(terminal, koQuestion), 2);
    expect(
      RegExp(r'^  ko \(한국어\) +마이 앱$', multiLine: true).hasMatch(output),
      isTrue,
    );
    expect(readFile('lib/l10n/app_ja.arb'), contains('"appTitle": "マイアプリ",'));
    expect(readFile('lib/l10n/app_ko.arb'), contains('"appTitle": "마이 앱",'));
    expect(output, contains('  ✓ 언어별 앱 이름 — ja マイアプリ · ko 마이 앱'));
  });

  test('T-23-NAMES-10 이어진 공백 값은 Todo 이고 그 언어만 다시 물어 값을 바꾼다', () async {
    writeAppNamesFixture(
      root,
      localizedTitles: const <String, String?>{'ja': 'マイアプリ', 'ko': '마이  앱'},
    );
    expect(
      await checkStep(AppNamesStep()),
      isTodo('lib/l10n/app_ko.arb 의 appTitle "마이  앱" 의 공백이 이어집니다'),
    );
    final terminal = ScriptedTerminal(const <String?>['y', '마이앱', '1']);
    expect(await runAppNamesStep(buildCleanRunner(), terminal), wizardExitDone);
    expect(collectNameAsks(terminal), <String>[
      '  ko (한국어) 앱 이름(지금 값 "마이  앱")',
    ]);
    expect(
      readFile('lib/l10n/app_ko.arb'),
      buildLocalizedArb('ko', titleJson: '"마이앱"'),
    );
    expect(await checkStep(AppNamesStep()), isDone('ja マイアプリ · ko 마이앱'));
  });

  test('T-23-NAMES-10 앞뒤 공백 값 · 빈 값도 Todo 이고 다시 물어 끝까지 간다', () async {
    writeAppNamesFixture(
      root,
      localizedTitles: const <String, String?>{'ja': 'マイアプリ', 'ko': ' 마이앱'},
    );
    expect(
      await checkStep(AppNamesStep()),
      isTodo('lib/l10n/app_ko.arb 의 appTitle " 마이앱" 의 앞뒤에 공백이 있습니다'),
    );
    final terminal = ScriptedTerminal(const <String?>['y', '마이앱', '1']);
    expect(await runAppNamesStep(buildCleanRunner(), terminal), wizardExitDone);
    expect(await checkStep(AppNamesStep()), isDone('ja マイアプリ · ko 마이앱'));

    writeFixtureFile(
      root,
      'lib/l10n/app_ko.arb',
      buildLocalizedArb('ko', titleJson: '""'),
    );
    expect(
      await checkStep(AppNamesStep()),
      isTodo('lib/l10n/app_ko.arb 의 appTitle 이 비어 있습니다'),
    );
    final again = ScriptedTerminal(const <String?>['y', '', '1']);
    expect(await runAppNamesStep(buildCleanRunner(), again), wizardExitDone);
    expect(collectNameAsks(again), <String>['  ko (한국어) 앱 이름(지금 값 "")']);
    expect(await checkStep(AppNamesStep()), isDone('ja マイアプリ · ko My App'));
  });

  test('T-23-NAMES-10 문자열 아닌 값은 Todo 이고 값 전체를 문자열로 바꾼다', () async {
    writeAppNamesFixture(
      root,
      localizedTitles: const <String, String?>{'ja': 'マイアプリ'},
    );
    writeFixtureFile(
      root,
      'lib/l10n/app_ko.arb',
      buildLocalizedArb('ko', titleJson: '12'),
    );
    expect(
      await checkStep(AppNamesStep()),
      isTodo('lib/l10n/app_ko.arb 의 appTitle 이 문자열이 아닙니다'),
    );
    final terminal = ScriptedTerminal(const <String?>['y', '마이앱', '1']);
    expect(await runAppNamesStep(buildCleanRunner(), terminal), wizardExitDone);
    expect(collectNameAsks(terminal), <String>['  ko (한국어) 앱 이름(지금 값 12)']);
    expect(
      readFile('lib/l10n/app_ko.arb'),
      buildLocalizedArb('ko', titleJson: '"마이앱"'),
    );
    expect(await checkStep(AppNamesStep()), isDone('ja マイアプリ · ko 마이앱'));
  });

  test('T-23-NAMES-10 접미사로 끝나는 기존 값은 Done 이고 묻지 않는다', () async {
    writeAppNamesFixture(
      root,
      localizedTitles: const <String, String?>{'ja': 'マイアプリ', 'ko': '마이앱 Dev'},
    );
    expect(await checkStep(AppNamesStep()), isDone('ja マイアプリ · ko 마이앱 Dev'));
    final terminal = ScriptedTerminal(const <String?>[]);
    expect(
      await runAppNamesStep(FakeCommandRunner(), terminal),
      wizardExitDone,
    );
    expect(terminal.asks, isEmpty);
  });

  test('T-23-NAMES-11 영어 ARB 만 있으면 Done 이고 질문 · 명령 · 계획 줄이 없다', () async {
    writeAppNamesFixture(root, localizedTitles: const <String, String?>{});
    final step = AppNamesStep();
    final WizardContext context = buildTestContext(projectRoot: root);
    expect(
      await step.check(context),
      isDone('lib/l10n 에 영어 ARB 만 있어 물을 언어가 없습니다'),
    );
    expect(step.plannedCommandLines(context), isEmpty);

    final runner = FakeCommandRunner();
    final terminal = ScriptedTerminal(const <String?>[]);
    expect(await runAppNamesStep(runner, terminal), wizardExitDone);
    expect(terminal.asks, isEmpty);
    expect(runner.calls, isEmpty);
  });

  test('T-23-NAMES-12 변형 locale 은 파일 이름 순으로 묻고 언어 부분의 원어 이름을 쓴다', () async {
    writeAppNamesFixture(
      root,
      localizedTitles: const <String, String?>{
        'ja': null,
        'ko': null,
        'pt': null,
        'pt_BR': null,
        'zh_Hant': null,
      },
      endonyms: const <String, String>{
        'en': 'English',
        'ko': '한국어',
        'ja': '日本語',
        'pt': 'Português',
        'zh': '中文',
      },
    );
    final terminal = ScriptedTerminal(const <String?>[
      'y',
      'マイアプリ',
      '마이앱',
      'Meu App',
      'Meu App BR',
      '我的應用',
      '1',
    ]);
    expect(await runAppNamesStep(buildCleanRunner(), terminal), wizardExitDone);
    expect(collectNameAsks(terminal), <String>[
      '  ja (日本語) 앱 이름',
      '  ko (한국어) 앱 이름',
      '  pt (Português) 앱 이름',
      '  pt_BR (Português) 앱 이름',
      '  zh_Hant (中文) 앱 이름',
    ]);
    expect(
      await checkStep(AppNamesStep()),
      isDone(
        'ja マイアプリ · ko 마이앱 · pt Meu App · pt_BR Meu App BR · '
        'zh_Hant 我的應用',
      ),
    );
  });

  test('T-23-NAMES-13 입력이 끝나면 위저드가 멈추고 파일을 바꾸지 않는다', () async {
    writeAppNamesFixture(root);
    final Map<String, List<int>> before = snapshotTree(root);
    final terminal = ScriptedTerminal(const <String?>['y', 'マイアプリ']);
    expect(
      await runAppNamesStep(buildCleanRunner(), terminal),
      wizardExitStopped,
    );
    expect(terminal.output.toString(), contains(stopLine));
    expect(snapshotTree(root), before);
  });

  test('T-23-NAMES-14 고칠 ARB 에 미커밋 변경이 있으면 실패하고 쓰지 않는다', () async {
    writeAppNamesFixture(root);
    final Map<String, List<int>> before = snapshotTree(root);
    final runner = FakeCommandRunner()
      ..on(
        _gitStatusKey,
        const CommandResult(0, ' M lib/l10n/app_ko.arb\n', ''),
      );
    final terminal = ScriptedTerminal(const <String?>[
      'y',
      'マイアプリ',
      '마이앱',
      '1',
      '2',
    ]);
    expect(await runAppNamesStep(runner, terminal), wizardExitStopped);
    expect(
      terminal.output.toString(),
      contains(
        '  실패 — 고칠 파일에 커밋하지 않은 변경이 있습니다 — 커밋하거나 되돌린 뒤 다시 시도하세요\n'
        '    lib/l10n/app_ko.arb\n',
      ),
    );
    expect(snapshotTree(root), before);
  });

  test('T-23-NAMES-15 l10n.yaml 이 없으면 Todo 이고 실행은 질문 없이 같은 사유로 실패한다', () async {
    writeAppNamesFixture(root, withL10nYaml: false);
    final Map<String, List<int>> before = snapshotTree(root);
    expect(
      await checkStep(AppNamesStep()),
      isTodo(startsWith('언어별 ARB 목록을 읽지 못했습니다 — ')),
    );
    final terminal = ScriptedTerminal(const <String?>['y', '2']);
    expect(
      await runAppNamesStep(buildCleanRunner(), terminal),
      wizardExitStopped,
    );
    expect(
      terminal.output.toString(),
      contains('  실패 — 언어별 ARB 목록을 읽지 못했습니다 — '),
    );
    expect(collectNameAsks(terminal), isEmpty);
    expect(snapshotTree(root), before);
  });

  test('T-23-NAMES-15 올바른 JSON 이 아닌 ARB 는 Todo 이고 실행은 질문 없이 실패한다', () async {
    writeAppNamesFixture(root);
    writeFixtureFile(root, 'lib/l10n/app_ko.arb', '{ "@@locale": "ko", ');
    final Map<String, List<int>> before = snapshotTree(root);
    const brokenReason = 'lib/l10n/app_ko.arb 이 올바른 JSON 이 아닙니다';
    expect(await checkStep(AppNamesStep()), isTodo(contains(brokenReason)));
    final terminal = ScriptedTerminal(const <String?>['y', '2']);
    expect(
      await runAppNamesStep(buildCleanRunner(), terminal),
      wizardExitStopped,
    );
    expect(terminal.output.toString(), contains('  실패 — $brokenReason'));
    expect(collectNameAsks(terminal), isEmpty);
    expect(snapshotTree(root), before);
  });

  test('T-23-NAMES-15 단계 제목 · 의존 · 비용 표시 값', () {
    final step = AppNamesStep();
    expect(step.title, AppNamesStep.stepTitle);
    expect(step.title, '언어별 앱 이름');
    expect(step.id, 'app_names');
    expect(step.dependsOn, <String>['identity']);
    expect(step.isCostlyOrIrreversible, isFalse);
  });

  /// [output] 에서 golden 갱신 안내 줄의 개수를 센다.
  int countGoldenHints(String output) =>
      output.split('\n').where((String line) => line == goldenHintText).length;

  test(
    'T-23-NAMES-16 ko 가 기본 이름과 다르면 실행 직후 ✓ 줄 앞에 golden 안내 한 줄 · 실행 0',
    () async {
      writeAppNamesFixture(root);
      final FakeCommandRunner runner = buildCleanRunner();
      final terminal = ScriptedTerminal(const <String?>[
        'y',
        'マイアプリ',
        '마이앱',
        '1',
      ]);
      expect(await runAppNamesStep(runner, terminal), wizardExitDone);

      final List<String> lines = terminal.output.toString().split('\n');
      expect(countGoldenHints(terminal.output.toString()), 1);
      final int hintIndex = lines.indexOf(goldenHintText);
      final int doneIndex = lines.indexWhere(
        (String line) => line.startsWith('  ✓ 언어별 앱 이름'),
      );
      expect(doneIndex, greaterThan(hintIndex));
      expect(hintIndex, greaterThan(-1));
      // 위저드는 안내만 하고 golden 갱신 명령을 실행하지 않는다.
      expect(runner.calls.map((FakeCall call) => call.key), <String>[
        _gitStatusKey,
      ]);
      expect(runner.countCalls(RunMode.capture, _gitStatusKey), 1);
    },
  );

  /// 직접 판정용 문맥을 만든다.
  WizardContext buildHintContext() => buildTestContext(projectRoot: root);

  test('T-23-NAMES-17 ko 를 Enter 로 기본 이름 그대로 두면 안내 0 · 판정 false', () async {
    writeAppNamesFixture(root);
    final terminal = ScriptedTerminal(const <String?>['y', 'マイアプリ', '', '1']);
    expect(await runAppNamesStep(buildCleanRunner(), terminal), wizardExitDone);
    expect(readFile('lib/l10n/app_ko.arb'), contains('"appTitle": "My App"'));
    expect(countGoldenHints(terminal.output.toString()), 0);
    expect(AppNamesStep.needsGoldenHint(buildHintContext()), isFalse);
  });

  test('T-23-NAMES-17 ja 만 다른 값이면 안내 0 · 판정 false', () async {
    writeAppNamesFixture(
      root,
      localizedTitles: const <String, String?>{'ja': null, 'ko': 'My App'},
    );
    final terminal = ScriptedTerminal(const <String?>['y', 'マイアプリ', '1']);
    expect(await runAppNamesStep(buildCleanRunner(), terminal), wizardExitDone);
    expect(readFile('lib/l10n/app_ja.arb'), contains('"appTitle": "マイアプリ"'));
    expect(countGoldenHints(terminal.output.toString()), 0);
    expect(AppNamesStep.needsGoldenHint(buildHintContext()), isFalse);
  });

  test('T-23-NAMES-17 golden 시험 파일이 없으면 ko 가 달라도 안내 0 · 판정 false', () async {
    writeAppNamesFixture(root, withGoldenTest: false);
    final terminal = ScriptedTerminal(const <String?>[
      'y',
      'マイアプリ',
      '마이앱',
      '1',
    ]);
    expect(await runAppNamesStep(buildCleanRunner(), terminal), wizardExitDone);
    expect(readFile('lib/l10n/app_ko.arb'), contains('"appTitle": "마이앱"'));
    expect(countGoldenHints(terminal.output.toString()), 0);
    expect(AppNamesStep.needsGoldenHint(buildHintContext()), isFalse);
  });

  test('T-23-NAMES-17 판정은 ko 가 다르고 golden 시험 파일이 있을 때만 true · 안내 줄 원문', () {
    writeAppNamesFixture(
      root,
      localizedTitles: const <String, String?>{'ja': null, 'ko': '마이앱'},
    );
    expect(AppNamesStep.needsGoldenHint(buildHintContext()), isTrue);
    expect('  ${AppNamesStep.goldenHintLine}', goldenHintText);

    // l10n.yaml 을 읽지 못하면 판정은 false 다.
    File('$root/l10n.yaml').deleteSync();
    expect(AppNamesStep.needsGoldenHint(buildHintContext()), isFalse);
  });
}
