// 위저드의 ARB `appTitle` 도우미(`tool/setup/arb_titles.dart`)를 임시 트리로
// 고정한다.
//
// 파일은 `Directory.systemTemp` 아래 임시 프로젝트에만 쓰고 시험마다 지운다 —
// 저장소의 ARB 는 읽지도 쓰지도 않는다.
import 'dart:io';

import 'package:test/test.dart';

import '../../../tool/launcher_names.dart' show GeneratorException;
import '../../../tool/setup/arb_titles.dart';

/// 시험 트리의 `l10n.yaml` 본문(킷과 같은 두 줄).
const String fixtureL10nYaml =
    'arb-dir: lib/l10n\n'
    'template-arb-file: app_en.arb\n';

/// [root] 아래 [relativePath] 에 [content] 를 쓴다 — 상위 디렉터리는 만든다.
void writeTreeFile(String root, String relativePath, String content) {
  File('$root/$relativePath')
    ..parent.createSync(recursive: true)
    ..writeAsStringSync(content);
}

/// [root] 에 `l10n.yaml` 과 [locales] 마다 `@@locale` 하나짜리 ARB 를 쓴다.
void writeArbTree(String root, List<String> locales) {
  writeTreeFile(root, 'l10n.yaml', fixtureL10nYaml);
  for (final locale in locales) {
    writeTreeFile(
      root,
      'lib/l10n/app_$locale.arb',
      '{\n  "@@locale": "$locale"\n}\n',
    );
  }
}

void main() {
  late Directory tree;

  setUp(() {
    tree = Directory.systemTemp.createTempSync('arb_titles_test_');
  });

  tearDown(() {
    if (tree.existsSync()) tree.deleteSync(recursive: true);
  });

  group('T-23-ARB-01: listLocalizedArbs 는 template 밖 ARB 를 locale 순으로', () {
    test('T-23-ARB-01: ja → ko → pt → pt_BR → zh_Hant · template 제외', () {
      writeArbTree(tree.path, <String>[
        'zh_Hant',
        'en',
        'pt_BR',
        'ko',
        'pt',
        'ja',
      ]);

      final List<LocalizedArb> arbs = listLocalizedArbs(tree.path);

      expect(
        <String>[for (final arb in arbs) arb.locale],
        <String>['ja', 'ko', 'pt', 'pt_BR', 'zh_Hant'],
      );
      expect(
        <String>[for (final arb in arbs) arb.relativePath],
        <String>[
          'lib/l10n/app_ja.arb',
          'lib/l10n/app_ko.arb',
          'lib/l10n/app_pt.arb',
          'lib/l10n/app_pt_BR.arb',
          'lib/l10n/app_zh_Hant.arb',
        ],
      );
      expect(arbs.first.absolutePath, '${tree.path}/lib/l10n/app_ja.arb');
      expect(File(arbs.last.absolutePath).existsSync(), isTrue);
    });

    test('T-23-ARB-01: 영어 ARB 만 있으면 빈 목록', () {
      writeArbTree(tree.path, <String>['en']);

      expect(listLocalizedArbs(tree.path), isEmpty);
    });

    test('T-23-ARB-01: l10n.yaml 이 없으면 GeneratorException', () {
      writeArbTree(tree.path, <String>['en', 'ko']);
      File('${tree.path}/l10n.yaml').deleteSync();

      expect(
        () => listLocalizedArbs(tree.path),
        throwsA(
          isA<GeneratorException>().having(
            (GeneratorException error) => error.message,
            'message',
            contains('l10n.yaml'),
          ),
        ),
      );
    });

    test('T-23-ARB-01: 파일 이름 꼴이 어긋나면 GeneratorException', () {
      writeArbTree(tree.path, <String>['en']);
      writeTreeFile(tree.path, 'lib/l10n/app-ko.arb', '{}');

      expect(
        () => listLocalizedArbs(tree.path),
        throwsA(
          isA<GeneratorException>().having(
            (GeneratorException error) => error.message,
            'message',
            contains('lib/l10n/app-ko.arb'),
          ),
        ),
      );
    });
  });
}
