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
/// [appName] 이 null 이면 `config/dev.json` 을 두지 않는다.
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
}) {
  if (withL10nYaml) writeFixtureFile(root, 'l10n.yaml', fixtureL10nYaml);
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
}
