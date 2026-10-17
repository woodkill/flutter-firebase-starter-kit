import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

import '../../../tool/setup/config_files.dart';

/// 저장소에 추적되는 JSON example — fixture 원본.
const String trackedJsonExample = 'config/dev.example.json';

/// 저장소에 추적되는 xcconfig example — fixture 원본.
const String trackedXcconfigExample = 'ios/Flutter/dev.example.xcconfig';

/// 손으로 쓰는 작은 xcconfig example — 주석 묶음 · 빈 값 변수를 담는다.
const String smallXcconfigExample =
    '// 첫 변수 설명\n'
    'ALPHA = a\n'
    'BETA = b\n'
    '// 감마 설명 1\n'
    '// 감마 설명 2\n'
    'GAMMA = c\n'
    'DELTA =\n';

void main() {
  late Directory tempDir;
  late String examplePath;
  late String userPath;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('config_files_test_');
    examplePath = '${tempDir.path}/dev.example.json';
    userPath = '${tempDir.path}/dev.json';
    File(trackedJsonExample).copySync(examplePath);
  });

  tearDown(() {
    tempDir.deleteSync(recursive: true);
  });

  /// example 본문에서 [keys] 줄을 지운 사용자 JSON 본문을 만든다.
  ///
  /// 마지막 키 줄을 지우면 그 앞 줄 끝의 쉼표도 지워 올바른 JSON 으로 둔다.
  String removeJsonKeys(String example, List<String> keys) {
    final List<String> lines = example.split('\n');
    final List<String> kept = lines
        .where(
          (String line) =>
              !keys.any((String key) => line.trimLeft().startsWith('"$key"')),
        )
        .toList();
    final int closeIndex = kept.lastIndexOf('}');
    final int lastKeyIndex = closeIndex - 1;
    final String lastKeyLine = kept[lastKeyIndex];
    if (lastKeyLine.endsWith(',')) {
      kept[lastKeyIndex] = lastKeyLine.substring(0, lastKeyLine.length - 1);
    }
    return kept.join('\n');
  }

  test('T-19-CFG-01 빠진 키 2개를 example 순서로 더하고 기존 줄은 마지막 키 줄의 쉼표 하나만 바꾼다', () {
    final String example = File(examplePath).readAsStringSync();
    final String original = removeJsonKeys(example, const <String>[
      'brandColor',
      'appCheckDebugToken',
    ]).replaceFirst('"your-project-dev"', '"acme-real-dev"');
    File(userPath).writeAsStringSync(original);

    expect(
      findMissingJsonKeys(examplePath: examplePath, userPath: userPath),
      <String>['brandColor', 'appCheckDebugToken'],
    );

    addMissingJsonKeys(examplePath: examplePath, userPath: userPath);

    final String updated = File(userPath).readAsStringSync();
    final List<String> originalLines = original.split('\n');
    final int closeIndex = originalLines.lastIndexOf('}');
    final expectedLines = <String>[
      ...originalLines.sublist(0, closeIndex - 1),
      '${originalLines[closeIndex - 1]},',
      '  "brandColor": "#673AB7",',
      '  "appCheckDebugToken": ""',
      ...originalLines.sublist(closeIndex),
    ];
    expect(updated, expectedLines.join('\n'));

    final Object? decoded = jsonDecode(updated);
    final Object? exampleDecoded = jsonDecode(example);
    expect(decoded, isA<Map<String, Object?>>());
    final merged = decoded! as Map<String, Object?>;
    expect(merged['firebaseProjectId'], 'acme-real-dev');
    expect(merged['brandColor'], '#673AB7');
    expect(merged['appCheckDebugToken'], '');
    expect(
      merged.keys.toSet(),
      (exampleDecoded! as Map<String, Object?>).keys.toSet(),
    );
    expect(
      findMissingJsonKeys(examplePath: examplePath, userPath: userPath),
      isEmpty,
    );
    // 임시 파일이 남지 않는다.
    expect(
      tempDir.listSync().map((FileSystemEntity e) => e.uri.pathSegments.last),
      unorderedEquals(<String>['dev.example.json', 'dev.json']),
    );
  });

  test('T-19-CFG-02 빠진 키가 없으면 파일 바이트를 바꾸지 않는다', () {
    File(examplePath).copySync(userPath);
    final List<int> before = File(userPath).readAsBytesSync();

    expect(
      findMissingJsonKeys(examplePath: examplePath, userPath: userPath),
      isEmpty,
    );
    addMissingJsonKeys(examplePath: examplePath, userPath: userPath);

    expect(File(userPath).readAsBytesSync(), before);
  });

  test('T-19-CFG-03 사용자 JSON 이 깨지면 FormatException 이고 파일은 그대로다', () {
    const broken = '{\n  "flavor": "dev",\n';
    File(userPath).writeAsStringSync(broken);

    expect(
      () => findMissingJsonKeys(examplePath: examplePath, userPath: userPath),
      throwsFormatException,
    );
    expect(
      () => addMissingJsonKeys(examplePath: examplePath, userPath: userPath),
      throwsFormatException,
    );
    expect(File(userPath).readAsStringSync(), broken);

    // 최상위가 객체가 아닌 JSON 도 같은 실패다.
    File(userPath).writeAsStringSync('[1, 2]\n');
    expect(
      () => findMissingJsonKeys(examplePath: examplePath, userPath: userPath),
      throwsFormatException,
    );
  });

  test('T-19-CFG-04 빠진 xcconfig 변수는 바로 위 주석 묶음과 함께 파일 끝에 붙는다', () {
    final smallExamplePath = '${tempDir.path}/small.example.xcconfig';
    final smallUserPath = '${tempDir.path}/small.xcconfig';
    File(smallExamplePath).writeAsStringSync(smallXcconfigExample);
    // 끝 개행이 없는 사용자 파일 — 붙이기 전에 개행을 보장해야 한다.
    File(smallUserPath).writeAsStringSync('ALPHA = mine');

    expect(
      findMissingXcconfigVars(
        examplePath: smallExamplePath,
        userPath: smallUserPath,
      ),
      <String>['BETA', 'GAMMA', 'DELTA'],
    );

    addMissingXcconfigVars(
      examplePath: smallExamplePath,
      userPath: smallUserPath,
    );

    expect(
      File(smallUserPath).readAsStringSync(),
      'ALPHA = mine\n'
      'BETA = b\n'
      '// 감마 설명 1\n'
      '// 감마 설명 2\n'
      'GAMMA = c\n'
      'DELTA =\n',
    );
    expect(readXcconfigValue(smallUserPath, 'ALPHA'), 'mine');
    expect(readXcconfigValue(smallUserPath, 'DELTA'), '');
    expect(readXcconfigValue(smallUserPath, 'MISSING'), isNull);

    // 추적되는 example 그대로인 사용자 파일은 빠진 변수가 없고 바뀌지 않는다.
    final trackedExamplePath = '${tempDir.path}/dev.example.xcconfig';
    final trackedUserPath = '${tempDir.path}/dev.xcconfig';
    File(trackedXcconfigExample).copySync(trackedExamplePath);
    File(trackedXcconfigExample).copySync(trackedUserPath);
    final List<int> before = File(trackedUserPath).readAsBytesSync();
    expect(
      findMissingXcconfigVars(
        examplePath: trackedExamplePath,
        userPath: trackedUserPath,
      ),
      isEmpty,
    );
    addMissingXcconfigVars(
      examplePath: trackedExamplePath,
      userPath: trackedUserPath,
    );
    expect(File(trackedUserPath).readAsBytesSync(), before);
  });

  test('T-19-CFG-05 값 치환은 그 키 값 · 그 줄만 바꾸고 나머지 바이트는 그대로다', () {
    File(examplePath).copySync(userPath);
    final String original = File(userPath).readAsStringSync();

    replaceJsonString(userPath, 'appName', 'My App Dev');
    expect(
      File(userPath).readAsStringSync(),
      original.replaceFirst(
        '"appName": "StarterKit Dev"',
        '"appName": "My App Dev"',
      ),
    );
    expect(readJsonString(userPath, 'appName'), 'My App Dev');
    expect(readJsonString(userPath, 'noSuchKey'), isNull);
    expect(
      () => replaceJsonString(userPath, 'noSuchKey', 'x'),
      throwsStateError,
    );

    // 따옴표 · 역슬래시는 JSON 이스케이프로 들어가 다시 읽어도 같은 값이다.
    replaceJsonString(userPath, 'appName', r'A "q" \ b');
    final Object? decoded = jsonDecode(File(userPath).readAsStringSync());
    expect((decoded! as Map<String, Object?>)['appName'], r'A "q" \ b');
    expect(readJsonString(userPath, 'appName'), r'A "q" \ b');

    final xcconfigPath = '${tempDir.path}/dev.xcconfig';
    File(trackedXcconfigExample).copySync(xcconfigPath);
    final String xcconfigOriginal = File(xcconfigPath).readAsStringSync();
    replaceXcconfigValue(xcconfigPath, 'DISPLAY_NAME', 'My App Dev');
    expect(
      File(xcconfigPath).readAsStringSync(),
      xcconfigOriginal.replaceFirst(
        'DISPLAY_NAME = FSK Dev',
        'DISPLAY_NAME = My App Dev',
      ),
    );
    expect(readXcconfigValue(xcconfigPath, 'DISPLAY_NAME'), 'My App Dev');
    expect(
      () => replaceXcconfigValue(xcconfigPath, 'NO_SUCH_VAR', 'x'),
      throwsStateError,
    );

    // 값이 빈 줄(`NAME =`)에도 공백 하나를 두고 값을 쓴다.
    replaceXcconfigValue(xcconfigPath, 'DEVELOPMENT_TEAM', 'ABCDE12345');
    expect(
      File(xcconfigPath).readAsStringSync(),
      contains('\nDEVELOPMENT_TEAM = ABCDE12345\n'),
    );
  });
}
