import 'dart:io';

import 'package:test/test.dart';

import '../../../tool/setup/secret_names.dart';

/// 매뉴얼 「켜기」 ④ secret 반복문의 `for s in … ; do` 머리(이름은 줄 이음 `\` 을
/// 넘어 이어진다) — 매뉴얼 계약 테스트와 같은 정규식이다.
final RegExp manualSecretLoopPattern = RegExp(
  r'^for s in ([\s\S]*?); do$',
  multiLine: true,
);

/// 매뉴얼 경로(저장소 상대).
const String manualPath = 'docs/manual.md';

void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('secret_names_test_');
  });

  tearDown(() {
    tempDir.deleteSync(recursive: true);
  });

  /// 임시 저장소의 [relativePath] 에 [content] 를 쓴다(부모 디렉터리를 만든다).
  void writeFixture(String relativePath, String content) {
    File('${tempDir.path}/$relativePath')
      ..parent.createSync(recursive: true)
      ..writeAsStringSync(content);
  }

  test('T-19-SECRET-01: 저장소 functions/src 의 선언 집합 == 매뉴얼 ④ 반복문 집합', () {
    final String root = Directory.current.path;

    final List<String> declared = extractDeclaredSecretNames(root);

    final String manual = File('$root/$manualPath').readAsStringSync();
    final List<RegExpMatch> loops = manualSecretLoopPattern
        .allMatches(manual)
        .toList();
    expect(loops, hasLength(1), reason: '매뉴얼에 secret 반복문이 1개가 아니다');
    final List<String> manualNames =
        loops.single
            .group(1)!
            .split(RegExp(r'[\s\\]+'))
            .where((String token) => token.isNotEmpty)
            .toList()
          ..sort();

    expect(declared, isNotEmpty);
    expect(declared, manualNames);
    expect(declared.toSet(), hasLength(declared.length));
  });

  test('T-19-SECRET-02: 여러 줄 선언을 읽고 test 디렉터리 · .test.ts 선언은 뺀다', () {
    writeFixture(
      'functions/src/shared/multi_line.ts',
      'import { defineSecret } from "firebase-functions/params";\n'
          'export const A_B = defineSecret(\n'
          '  "A_B"\n'
          ');\n'
          '// defineSecret().value() 는 선언이 아니다.\n',
    );
    writeFixture(
      'functions/src/test/helper.ts',
      'export const X = defineSecret("IN_TEST_DIR");\n',
    );
    writeFixture(
      'functions/src/shared/thing.test.ts',
      'export const Y = defineSecret("IN_TEST_FILE");\n',
    );
    writeFixture(
      'functions/src/shared/notes.md',
      'defineSecret("NOT_TYPESCRIPT")\n',
    );

    expect(extractDeclaredSecretNames(tempDir.path), <String>['A_B']);
  });

  test('T-19-SECRET-03: 같은 이름을 두 번 선언해도 결과에는 한 번만 · 정렬', () {
    writeFixture(
      'functions/src/one.ts',
      'export const Z = defineSecret("ZETA_KEY");\n'
          'export const D = defineSecret("DUP_KEY");\n',
    );
    writeFixture(
      'functions/src/nested/two.ts',
      'export const D2 = defineSecret( "DUP_KEY" );\n',
    );

    expect(extractDeclaredSecretNames(tempDir.path), <String>[
      'DUP_KEY',
      'ZETA_KEY',
    ]);
  });

  test('functions/src 가 없으면 빈 목록', () {
    expect(extractDeclaredSecretNames(tempDir.path), isEmpty);
  });
}
