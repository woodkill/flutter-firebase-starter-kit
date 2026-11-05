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
      throwsA(
        isA<ConfigEditException>().having(
          (ConfigEditException e) => e.message,
          'message',
          '$userPath 에 "noSuchKey" 문자열 값이 없습니다',
        ),
      ),
    );

    // 따옴표 · 역슬래시는 JSON 이스케이프로 들어가 다시 읽어도 같은 값이다.
    replaceJsonString(userPath, 'appName', r'A "q" \ b');
    final Object? decoded = jsonDecode(File(userPath).readAsStringSync());
    expect((decoded! as Map<String, Object?>)['appName'], r'A "q" \ b');
    expect(readJsonString(userPath, 'appName'), r'A "q" \ b');

    final xcconfigPath = '${tempDir.path}/dev.xcconfig';
    File(trackedXcconfigExample).copySync(xcconfigPath);
    final String xcconfigOriginal = File(xcconfigPath).readAsStringSync();
    // 기대값은 example 의 표시 이름 글자와 무관하게 DISPLAY_NAME 줄만 바꿔 만든다.
    final displayNameLine = RegExp(r'^DISPLAY_NAME = .*$', multiLine: true);
    expect(displayNameLine.allMatches(xcconfigOriginal), hasLength(1));
    replaceXcconfigValue(xcconfigPath, 'DISPLAY_NAME', 'My App Dev');
    expect(
      File(xcconfigPath).readAsStringSync(),
      xcconfigOriginal.replaceFirst(
        displayNameLine,
        'DISPLAY_NAME = My App Dev',
      ),
    );
    expect(readXcconfigValue(xcconfigPath, 'DISPLAY_NAME'), 'My App Dev');
    expect(
      () => replaceXcconfigValue(xcconfigPath, 'NO_SUCH_VAR', 'x'),
      throwsA(
        isA<ConfigEditException>().having(
          (ConfigEditException e) => e.message,
          'message',
          '$xcconfigPath 에 NO_SUCH_VAR 변수가 없습니다',
        ),
      ),
    );

    // 값이 빈 줄(`NAME =`)에도 공백 하나를 두고 값을 쓴다.
    replaceXcconfigValue(xcconfigPath, 'DEVELOPMENT_TEAM', 'ABCDE12345');
    expect(
      File(xcconfigPath).readAsStringSync(),
      contains('\nDEVELOPMENT_TEAM = ABCDE12345\n'),
    );
  });

  /// 시험 ARB [content] 를 임시 디렉터리에 쓰고 경로를 돌려준다.
  String writeArb(String content) {
    final path = '${tempDir.path}/app_ko.arb';
    File(path).writeAsStringSync(content);
    return path;
  }

  test('T-23-CFG-01 insertJsonString 은 @@locale 줄 · 빈 줄 다음에 새 줄과 빈 줄을 넣는다', () {
    const original =
        '{\n'
        '  "@@locale": "ko",\n'
        '\n'
        '  "commonOk": "확인"\n'
        '}\n';
    final String path = writeArb(original);

    insertJsonString(path, 'appTitle', '마이앱');

    final String updated = File(path).readAsStringSync();
    expect(
      updated,
      '{\n'
      '  "@@locale": "ko",\n'
      '\n'
      '  "appTitle": "마이앱",\n'
      '\n'
      '  "commonOk": "확인"\n'
      '}\n',
    );
    expect(updated.split('\n').length, original.split('\n').length + 2);
    final Object? decoded = jsonDecode(updated);
    expect(decoded, <String, Object?>{
      '@@locale': 'ko',
      'appTitle': '마이앱',
      'commonOk': '확인',
    });
  });

  test('T-23-CFG-02 insertJsonString 은 @@locale 이 마지막 키여도 같은 꼴로 넣는다', () {
    final String path = writeArb('{\n  "@@locale": "fr"\n}\n');

    insertJsonString(path, 'appTitle', 'Mon App');

    expect(
      File(path).readAsStringSync(),
      '{\n  "@@locale": "fr",\n\n  "appTitle": "Mon App"\n}\n',
    );
    expect(jsonDecode(File(path).readAsStringSync()), <String, Object?>{
      '@@locale': 'fr',
      'appTitle': 'Mon App',
    });
  });

  test('T-23-CFG-03 insertJsonString 은 키가 이미 있으면 거부하고 값은 이스케이프한다', () {
    const existing = '{\n  "@@locale": "ko",\n  "appTitle": "앱"\n}\n';
    final String path = writeArb(existing);

    expect(
      () => insertJsonString(path, 'appTitle', '새 앱'),
      throwsA(
        isA<ConfigEditException>().having(
          (ConfigEditException e) => e.message,
          'message',
          '$path 에 "appTitle" 가 이미 있습니다',
        ),
      ),
    );
    expect(File(path).readAsStringSync(), existing);

    File(path).writeAsStringSync('{\n  "@@locale": "ko"\n}\n');
    insertJsonString(path, 'appTitle', r'A "q" \ b');
    expect(
      File(path).readAsStringSync(),
      contains(r'  "appTitle": "A \"q\" \\ b"'),
    );
    expect(
      (jsonDecode(File(path).readAsStringSync())
          as Map<String, Object?>)['appTitle'],
      r'A "q" \ b',
    );
  });

  group('T-23-CFG-04 replaceJsonValue 는 값 토큰 전체를 문자열로 바꾼다', () {
    final cases = <({String label, String before, String after})>[
      (
        label: '숫자',
        before: '  "appTitle": 12,\n',
        after: '  "appTitle": "마이앱",\n',
      ),
      (
        label: '불',
        before: '  "appTitle": true,\n',
        after: '  "appTitle": "마이앱",\n',
      ),
      (
        label: 'null',
        before: '  "appTitle": null,\n',
        after: '  "appTitle": "마이앱",\n',
      ),
      (
        label: '객체',
        before: '  "appTitle": {"a": "b"},\n',
        after: '  "appTitle": "마이앱",\n',
      ),
      (
        label: '배열',
        before: '  "appTitle": ["x", "y"],\n',
        after: '  "appTitle": "마이앱",\n',
      ),
      (
        label: '문자열',
        before: '  "appTitle": "옛 앱",\n',
        after: '  "appTitle": "마이앱",\n',
      ),
      (
        label: '이스케이프 따옴표가 든 문자열',
        before: '  "appTitle": "마이\\"앱",\n',
        after: '  "appTitle": "마이앱",\n',
      ),
      (
        label: '괄호 글자가 든 문자열을 품은 중첩 값',
        before: '  "appTitle": {"a": "}]"},\n',
        after: '  "appTitle": "마이앱",\n',
      ),
    ];

    for (final c in cases) {
      test('T-23-CFG-04 ${c.label}', () {
        const head = '{\n  "@@locale": "ko",\n';
        const tail = '  "commonOk": "확인"\n}\n';
        final String path = writeArb('$head${c.before}$tail');

        replaceJsonValue(path, 'appTitle', '마이앱');

        final String updated = File(path).readAsStringSync();
        expect(updated, '$head${c.after}$tail');
        expect(jsonDecode(updated), <String, Object?>{
          '@@locale': 'ko',
          'appTitle': '마이앱',
          'commonOk': '확인',
        });
      });
    }

    test('T-23-CFG-04 쉼표 없이 닫는 괄호가 오는 마지막 키 값', () {
      final String path = writeArb(
        '{\n  "@@locale": "ko",\n  "appTitle": 12\n}\n',
      );

      replaceJsonValue(path, 'appTitle', '마이앱');

      expect(
        File(path).readAsStringSync(),
        '{\n  "@@locale": "ko",\n  "appTitle": "마이앱"\n}\n',
      );
    });

    test('T-23-CFG-04 키가 없으면 ConfigEditException 이고 파일은 그대로다', () {
      const original = '{\n  "@@locale": "ko"\n}\n';
      final String path = writeArb(original);

      expect(
        () => replaceJsonValue(path, 'appTitle', '마이앱'),
        throwsA(isA<ConfigEditException>()),
      );
      expect(File(path).readAsStringSync(), original);
    });
  });
}
