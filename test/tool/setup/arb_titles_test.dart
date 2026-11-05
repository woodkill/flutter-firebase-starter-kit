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

/// 시험 트리의 한국어 ARB 상대 경로.
const String koArbPath = 'lib/l10n/app_ko.arb';

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

  /// 임시 트리의 `lib/l10n/app_ko.arb` 에 [content] 를 쓰고 절대 경로를 돌려준다.
  String writeKoArb(String content) {
    writeTreeFile(tree.path, koArbPath, content);
    return '${tree.path}/$koArbPath';
  }

  test('T-23-ARB-02: readArbTitle 은 문자열 값만 돌려주고 나머지는 null', () {
    expect(
      readArbTitle(writeKoArb('{"@@locale": "ko", "appTitle": "마이앱"}')),
      '마이앱',
    );
    expect(readArbTitle(writeKoArb('{"@@locale": "ko"}')), isNull);
    expect(
      readArbTitle(writeKoArb('{"@@locale": "ko", "appTitle": 12}')),
      isNull,
    );
    expect(readArbTitle(writeKoArb('{"appTitle": ')), isNull);
    expect(readArbTitle('${tree.path}/lib/l10n/app_none.arb'), isNull);
  });

  test('T-23-ARB-03: findInvalidArbTitle 은 깨진 JSON · 최상위 · 문자열 아님을 사유로', () {
    final String broken = findInvalidArbTitle(
      writeKoArb('{"appTitle": '),
      koArbPath,
    )!;
    expect(broken, startsWith('$koArbPath 이 올바른 JSON 이 아닙니다('));
    expect(broken, endsWith(') — 따옴표 · 쉼표 · 괄호를 고친 뒤 다시 실행하세요'));

    expect(
      findInvalidArbTitle(writeKoArb('["마이앱"]'), koArbPath),
      '$koArbPath 의 최상위가 JSON 객체가 아닙니다',
    );
    expect(
      findInvalidArbTitle(
        writeKoArb('{"@@locale": "ko", "appTitle": 12}'),
        koArbPath,
      ),
      '$koArbPath 의 appTitle 이 문자열이 아닙니다',
    );
    expect(
      findInvalidArbTitle(writeKoArb('{"@@locale": "ko"}'), koArbPath),
      isNull,
    );
    expect(
      findInvalidArbTitle(
        writeKoArb('{"@@locale": "ko", "appTitle": "마이앱"}'),
        koArbPath,
      ),
      isNull,
    );
  });

  test('T-23-ARB-03: findInvalidJson 은 객체면 null', () {
    expect(findInvalidJson(writeKoArb('{"a": 1}'), koArbPath), isNull);
  });

  group('T-23-ARB-04: writeArbTitle 은 삽입 · 값 교체 두 분기', () {
    test('T-23-ARB-04: 키가 없으면 @@locale 뒤에 넣는다(+2줄)', () {
      const original = '{\n  "@@locale": "ko",\n\n  "commonOk": "확인"\n}\n';
      final String path = writeKoArb(original);

      writeArbTitle(path, '마이앱');

      final String updated = File(path).readAsStringSync();
      expect(updated.split('\n').length, original.split('\n').length + 2);
      expect(readArbTitle(path), '마이앱');
      expect(updated, contains('  "commonOk": "확인"\n}\n'));
    });

    test('T-23-ARB-04: 문자열 값이 있으면 그 값만 바꾼다(줄 수 그대로)', () {
      const original =
          '{\n  "@@locale": "ko",\n  "appTitle": "옛 앱",\n  "commonOk": "확인"\n}\n';
      final String path = writeKoArb(original);

      writeArbTitle(path, '마이앱');

      expect(
        File(path).readAsStringSync(),
        '{\n  "@@locale": "ko",\n  "appTitle": "마이앱",\n  "commonOk": "확인"\n}\n',
      );
    });

    test('T-23-ARB-04: 문자열 아닌 값도 통째로 문자열로 바꾼다(줄 수 그대로)', () {
      const original =
          '{\n  "@@locale": "ko",\n  "appTitle": 12,\n  "commonOk": "확인"\n}\n';
      final String path = writeKoArb(original);

      writeArbTitle(path, '마이앱');

      final String updated = File(path).readAsStringSync();
      expect(
        updated,
        '{\n  "@@locale": "ko",\n  "appTitle": "마이앱",\n  "commonOk": "확인"\n}\n',
      );
      expect(updated.split('\n').length, original.split('\n').length);
    });
  });

  test('T-23-ARB-04: formatArbPaths 는 첫 경로 뒤를 파일 이름만 잇는다', () {
    expect(
      formatArbPaths(<String>['lib/l10n/app_ja.arb', 'lib/l10n/app_ko.arb']),
      'lib/l10n/app_ja.arb · app_ko.arb',
    );
    expect(
      formatArbPaths(<String>['lib/l10n/app_ko.arb']),
      'lib/l10n/app_ko.arb',
    );
  });
}
