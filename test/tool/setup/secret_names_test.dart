import 'dart:io';

import 'package:test/test.dart';

import '../../../tool/setup/secret_names.dart';
import '../../helpers/planning_docs.dart';

/// 위저드 provider 단계 소스 디렉터리(저장소 상대).
const String providerStepsDirectory = 'tool/setup/steps';

/// 단계 소스의 secretNames 목록 — group 1 = 대괄호 안 글자.
final RegExp stepSecretNamesPattern = RegExp(
  r'secretNames: <String>\[([^\]]*)\]',
);

/// 대괄호 안의 작은따옴표 secret 이름 — group 1 = 이름.
final RegExp quotedSecretNamePattern = RegExp("'([A-Z0-9_]+)'");

/// [projectRoot] 의 위저드 provider 단계가 등록하는 secret 이름을 정렬 · 중복 제거해
/// 돌려준다.
///
/// [providerStepsDirectory] 의 `*_step.dart` 파일에서 secretNames 목록의 이름을
/// 모은다 — 위저드는 이 목록의 secret 에 값을 넣는다. 디렉터리가 없으면 빈 목록이다.
List<String> readStepSecretNames(String projectRoot) {
  final steps = Directory('$projectRoot/$providerStepsDirectory');
  if (!steps.existsSync()) return <String>[];
  final names = <String>{};
  for (final FileSystemEntity entity in steps.listSync()) {
    if (entity is! File || !entity.path.endsWith('_step.dart')) continue;
    for (final RegExpMatch list in stepSecretNamesPattern.allMatches(
      entity.readAsStringSync(),
    )) {
      for (final RegExpMatch name in quotedSecretNamePattern.allMatches(
        list.group(1)!,
      )) {
        names.add(name.group(1)!);
      }
    }
  }
  return names.toList()..sort();
}

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

  test('T-19-SECRET-01: 위저드 provider 단계의 secretNames 가 모두 functions/src 에 '
      '선언돼 있다', () {
    final String root = Directory.current.path;

    final List<String> stepNames = readStepSecretNames(root);
    // 양성 대조: 단계 소스에서 provider secret 을 실제로 읽었다.
    expect(stepNames.length, greaterThanOrEqualTo(8));
    expect(stepNames, contains('KAKAO_ADMIN_KEY'));

    final List<String> declared = extractDeclaredSecretNames(root);
    expect(declared, isNotEmpty);
    expect(declared.toSet(), hasLength(declared.length));
    final List<String> missing = stepNames
        .where((String name) => !declared.contains(name))
        .toList();
    expect(
      missing,
      isEmpty,
      reason: '위저드가 값을 넣는 secret 이 functions/src 에 선언돼 있지 않다',
    );
  });

  test('T-19-SECRET-04: functions/src 의 선언 집합 == 위저드 provider 단계의 secretNames '
      '합집합', () {
    final String root = Directory.current.path;
    final List<String> stepNames = readStepSecretNames(root);
    expect(stepNames, isNotEmpty);
    expect(
      extractDeclaredSecretNames(root),
      stepNames,
      reason: 'functions/src 가 선언한 secret 과 위저드가 값을 넣는 secret 이 다르다',
    );
  }, skip: skipUnlessMaintainerTree());

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
