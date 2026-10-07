import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

import '../../bin/rename.dart';

/// 킷 원본 `scripts/firebase-configure.sh` 의 상수 3줄(현재 값).
const _kitFirebaseConfigureConstants = <String>[
  'PROJECT_ID_PREFIX="slimpumpkin-starter-kit"',
  'IOS_BUNDLE_ID_PREFIX="com.slimpumpkin.flutterStarterKit"',
  'ANDROID_PACKAGE_PREFIX="com.slimpumpkin.flutter_starter_kit"',
];

/// `--org com.example --name my_app` 로 rename 한 뒤의 상수 3줄.
const _renamedFirebaseConfigureConstants = <String>[
  'PROJECT_ID_PREFIX="my-app"',
  'IOS_BUNDLE_ID_PREFIX="com.example.myApp"',
  'ANDROID_PACKAGE_PREFIX="com.example.my_app"',
];

/// [root] 아래에 `scripts/firebase-configure.sh` fixture 를 쓰고 그 파일을 돌려준다.
///
/// 상수 3줄([constants]) 앞뒤에 rename 과 무관한 줄을 1개씩 둔다.
File _writeFirebaseConfigureFixture(String root, List<String> constants) {
  Directory('$root/scripts').createSync(recursive: true);
  return File('$root/scripts/firebase-configure.sh')..writeAsStringSync(
    [
      '#!/usr/bin/env bash',
      '# === starter-kit fork 시 아래 3개 prefix 를 수정 ===',
      ...constants,
      r'PROJECT_ID="${PROJECT_ID_PREFIX}-${FLAVOR}"',
      '',
    ].join('\n'),
  );
}

void main() {
  group('validateInputs', () {
    test('유효한 org와 name이면 성공을 반환한다', () {
      final result = validateInputs('com.example', 'my_app');
      expect(result.isValid, isTrue);
      expect(result.error, isNull);
    });

    test('org가 역순 도메인 형식이 아니면 에러를 반환한다', () {
      // 단일 세그먼트
      expect(validateInputs('example', 'my_app').isValid, isFalse);

      // 대문자 포함
      expect(validateInputs('Com.example', 'my_app').isValid, isFalse);

      // 하이픈 포함
      expect(validateInputs('com.my-company', 'my_app').isValid, isFalse);

      // 빈 세그먼트
      expect(validateInputs('com..example', 'my_app').isValid, isFalse);

      // 숫자로 시작하는 세그먼트
      expect(validateInputs('com.1example', 'my_app').isValid, isFalse);
    });

    test('org에 3개 이상 세그먼트도 허용한다', () {
      expect(
        validateInputs('com.example.subdivision', 'my_app').isValid,
        isTrue,
      );
    });

    test('name이 snake_case가 아니면 에러를 반환한다', () {
      // PascalCase
      expect(validateInputs('com.example', 'MyApp').isValid, isFalse);

      // 하이픈
      expect(validateInputs('com.example', 'my-app').isValid, isFalse);

      // 대문자 포함
      expect(validateInputs('com.example', 'myApp').isValid, isFalse);

      // 빈 문자열
      expect(validateInputs('com.example', '').isValid, isFalse);

      // 숫자로 시작
      expect(validateInputs('com.example', '1app').isValid, isFalse);

      // 연속 언더스코어
      expect(validateInputs('com.example', 'my__app').isValid, isFalse);

      // 언더스코어로 끝남
      expect(validateInputs('com.example', 'my_app_').isValid, isFalse);
    });

    test('유효한 snake_case name을 허용한다', () {
      expect(validateInputs('com.example', 'my_app').isValid, isTrue);
      expect(validateInputs('com.example', 'app').isValid, isTrue);
      expect(validateInputs('com.example', 'my_cool_app2').isValid, isTrue);
    });
  });

  group('validateProjectPrefix', () {
    test('소문자 · 숫자 · 하이픈 2~25자 prefix 를 허용한다', () {
      expect(validateProjectPrefix('my-app').isValid, isTrue);
      expect(validateProjectPrefix('ab').isValid, isTrue);
      expect(validateProjectPrefix('acme-app2').isValid, isTrue);
      // 25자 — -prod 를 붙이면 Firebase 프로젝트 ID 상한 30자
      expect(validateProjectPrefix('a' * 25).isValid, isTrue);
    });

    test('규칙을 어긴 prefix 는 영어 에러를 반환한다', () {
      const invalidPrefixes = <String>[
        'My-app', // 대문자
        '-ab', // 하이픈으로 시작
        'ab-', // 하이픈으로 끝남
        'a', // 2자 미만
        'my_app', // 밑줄
        r'a$(id)', // 셸 메타문자
        '1app', // 숫자로 시작
      ];
      for (final prefix in invalidPrefixes) {
        final result = validateProjectPrefix(prefix);
        expect(result.isValid, isFalse, reason: prefix);
        expect(result.error, contains('Invalid project prefix'));
      }
      // 26자 — 상한 25자 초과
      expect(validateProjectPrefix('a' * 26).isValid, isFalse);
    });
  });

  group('toUpperCamelCase', () {
    test('snake_case를 UpperCamelCase로 변환한다', () {
      expect(toUpperCamelCase('my_app'), equals('MyApp'));
      expect(
        toUpperCamelCase('flutter_starter_kit'),
        equals('FlutterStarterKit'),
      );
      expect(toUpperCamelCase('app'), equals('App'));
    });
  });

  group('toLowerCamelCase', () {
    test('snake_case를 lowerCamelCase로 변환한다', () {
      expect(toLowerCamelCase('my_app'), equals('myApp'));
      expect(
        toLowerCamelCase('flutter_starter_kit'),
        equals('flutterStarterKit'),
      );
      expect(toLowerCamelCase('app'), equals('app'));
    });
  });

  group('toTitleCase', () {
    test('snake_case를 Title Case(공백 구분)로 변환한다', () {
      expect(toTitleCase('my_app'), equals('My App'));
      expect(toTitleCase('flutter_starter_kit'), equals('Flutter Starter Kit'));
      expect(toTitleCase('app'), equals('App'));
    });
  });

  group('collectChanges', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('rename_test_');

      // pubspec.yaml 생성
      File(
        '${tempDir.path}/pubspec.yaml',
      ).writeAsStringSync('name: flutter_starter_kit\nversion: 1.0.0\n');

      // android/app/build.gradle.kts 생성
      Directory('${tempDir.path}/android/app').createSync(recursive: true);
      File('${tempDir.path}/android/app/build.gradle.kts').writeAsStringSync('''
plugins {
    id("com.android.application")
}

android {
    namespace = "com.slimpumpkin.flutter_starter_kit"

    defaultConfig {
        applicationId = "com.slimpumpkin.flutter_starter_kit"
    }
}
''');

      // Kotlin MainActivity 생성
      Directory(
        '${tempDir.path}/android/app/src/main/kotlin/com/slimpumpkin/flutter_starter_kit',
      ).createSync(recursive: true);
      File(
        '${tempDir.path}/android/app/src/main/kotlin/com/slimpumpkin/flutter_starter_kit/MainActivity.kt',
      ).writeAsStringSync(
        'package com.slimpumpkin.flutter_starter_kit\n\n'
        'import io.flutter.embedding.android.FlutterActivity\n\n'
        'class MainActivity : FlutterActivity()\n',
      );

      // iOS project.pbxproj 생성
      Directory(
        '${tempDir.path}/ios/Runner.xcodeproj',
      ).createSync(recursive: true);
      File(
        '${tempDir.path}/ios/Runner.xcodeproj/project.pbxproj',
      ).writeAsStringSync('''
/* Begin section */
PRODUCT_BUNDLE_IDENTIFIER = com.slimpumpkin.flutterStarterKit;
PRODUCT_BUNDLE_IDENTIFIER = com.slimpumpkin.flutterStarterKit.RunnerTests;
PRODUCT_BUNDLE_IDENTIFIER = com.slimpumpkin.flutterStarterKit;
/* End section */
''');

      // lib/*.dart 생성
      Directory('${tempDir.path}/lib/core').createSync(recursive: true);
      File('${tempDir.path}/lib/main.dart').writeAsStringSync(
        "import 'package:flutter_starter_kit/core/bootstrap.dart';\n"
        "import 'package:flutter_starter_kit/app.dart';\n",
      );
      File('${tempDir.path}/lib/core/bootstrap.dart').writeAsStringSync(
        "import 'package:flutter_starter_kit/core/firebase/firebase_initializer.dart';\n",
      );

      // test/*.dart 생성
      Directory('${tempDir.path}/test/core').createSync(recursive: true);
      File(
        '${tempDir.path}/test/widget_test.dart',
      ).writeAsStringSync("import 'package:flutter_starter_kit/main.dart';\n");

      // config/*.json 생성
      Directory('${tempDir.path}/config').createSync(recursive: true);
      File('${tempDir.path}/config/dev.json').writeAsStringSync(
        '{"flavor":"dev","appName":"StarterKit Dev","appSuffix":".dev"}\n',
      );
      File('${tempDir.path}/config/prod.json').writeAsStringSync(
        '{"flavor":"prod","appName":"StarterKit","appSuffix":""}\n',
      );
      // 킷 추적 example 파일 — rename 대상이 아니다 (D-34 범위 확인)
      File('${tempDir.path}/config/dev.example.json').writeAsStringSync(
        '{"flavor":"dev","appName":"StarterKit Dev","appSuffix":".dev"}\n',
      );

      // scripts/firebase-configure.sh 생성 (상수 3줄 + 무관한 줄)
      _writeFirebaseConfigureFixture(
        tempDir.path,
        _kitFirebaseConfigureConstants,
      );
    });

    tearDown(() {
      tempDir.deleteSync(recursive: true);
    });

    test('모든 변경 대상 카테고리를 수집한다', () {
      final changes = collectChanges(tempDir.path, 'com.example', 'my_app');

      // pubspec.yaml 은 수집하지 않는다 (D-34 — Dart 패키지명 유지)
      final pubspecChanges = changes.where(
        (c) => c.filePath.endsWith('pubspec.yaml'),
      );
      expect(pubspecChanges, isEmpty);

      // build.gradle.kts 변경 포함 확인
      final gradleChanges = changes.where(
        (c) => c.filePath.endsWith('build.gradle.kts'),
      );
      expect(gradleChanges, isNotEmpty);

      // project.pbxproj 변경 포함 확인
      final pbxprojChanges = changes.where(
        (c) => c.filePath.endsWith('project.pbxproj'),
      );
      expect(pbxprojChanges, isNotEmpty);

      // Kotlin 디렉토리 이동 포함 확인
      final kotlinChanges = changes.where((c) => c.type == ChangeType.move);
      expect(kotlinChanges, isNotEmpty);

      // lib/*.dart import 는 수집하지 않는다 (D-34)
      final libChanges = changes.where(
        (c) => c.filePath.contains('/lib/') && c.type == ChangeType.replace,
      );
      expect(libChanges, isEmpty);

      // test/*.dart import 는 수집하지 않는다 (D-34)
      final testChanges = changes.where(
        (c) => c.filePath.contains('/test/') && c.type == ChangeType.replace,
      );
      expect(testChanges, isEmpty);

      // config/*.json 변경 포함 확인
      final configChanges = changes.where(
        (c) => c.filePath.contains('/config/'),
      );
      expect(configChanges, isNotEmpty);

      // scripts/firebase-configure.sh 상수 3줄 변경 포함 확인
      final firebaseConfigureChanges = changes.where(
        (c) => c.filePath.endsWith('scripts/firebase-configure.sh'),
      );
      expect(firebaseConfigureChanges, hasLength(3));
    });

    test('pubspec.yaml 의 name 과 Dart import 는 바꾸지 않는다', () {
      final pubspecFile = File('${tempDir.path}/pubspec.yaml');
      final dartFiles = [
        File('${tempDir.path}/lib/main.dart'),
        File('${tempDir.path}/lib/core/bootstrap.dart'),
        File('${tempDir.path}/test/widget_test.dart'),
      ];
      final before = {
        for (final file in [pubspecFile, ...dartFiles])
          file.path: file.readAsStringSync(),
      };

      final changes = collectChanges(tempDir.path, 'com.example', 'my_app');

      // 수집 결과에 pubspec · Dart 파일 경로가 없다
      final touchedPaths = changes.map((c) => c.filePath).toSet();
      for (final path in before.keys) {
        expect(touchedPaths, isNot(contains(path)));
      }
      // 어떤 변경도 Dart 패키지명을 새 이름으로 바꾸지 않는다
      for (final change in changes) {
        expect(change.newValue, isNot(contains('package:my_app/')));
        expect(change.newValue, isNot(contains('name: my_app')));
      }

      // replace 를 적용해도 fixture 내용은 그대로다
      applyChanges(changes.where((c) => c.type == ChangeType.replace).toList());
      for (final entry in before.entries) {
        expect(File(entry.key).readAsStringSync(), entry.value);
      }
    });

    test('scripts/firebase-configure.sh 의 상수 3줄을 앱 ID 로 바꾼다', () {
      final changes = collectChanges(tempDir.path, 'com.example', 'my_app');
      final firebaseConfigureChanges = changes
          .where((c) => c.filePath.endsWith('scripts/firebase-configure.sh'))
          .toList();

      expect(firebaseConfigureChanges, hasLength(3));
      expect(
        firebaseConfigureChanges.every((c) => c.type == ChangeType.replace),
        isTrue,
      );
      final pairs = {
        for (final change in firebaseConfigureChanges)
          change.oldValue: change.newValue,
      };
      expect(pairs, <String, String>{
        'PROJECT_ID_PREFIX="slimpumpkin-starter-kit"':
            'PROJECT_ID_PREFIX="my-app"',
        'IOS_BUNDLE_ID_PREFIX="com.slimpumpkin.flutterStarterKit"':
            'IOS_BUNDLE_ID_PREFIX="com.example.myApp"',
        'ANDROID_PACKAGE_PREFIX="com.slimpumpkin.flutter_starter_kit"':
            'ANDROID_PACKAGE_PREFIX="com.example.my_app"',
      });
    });

    test('config/*.example.json 은 바꾸지 않는다 (킷 추적 파일)', () {
      final exampleFile = File('${tempDir.path}/config/dev.example.json');
      final exampleBefore = exampleFile.readAsStringSync();

      final changes = collectChanges(tempDir.path, 'com.example', 'my_app');
      final configChanges = changes
          .where((c) => c.filePath.contains('/config/'))
          .toList();

      expect(
        configChanges.where((c) => c.filePath.endsWith('.example.json')),
        isEmpty,
      );
      expect(
        configChanges.where((c) => c.filePath.endsWith('/config/dev.json')),
        hasLength(1),
      );

      applyChanges(changes.where((c) => c.type == ChangeType.replace).toList());
      expect(exampleFile.readAsStringSync(), exampleBefore);
    });

    test('build.gradle.kts의 namespace와 applicationId를 변경한다', () {
      final changes = collectChanges(tempDir.path, 'com.example', 'my_app');
      final gradleChanges = changes
          .where((c) => c.filePath.endsWith('build.gradle.kts'))
          .toList();

      // namespace + applicationId 모두 변경
      final allOld = gradleChanges.map((c) => c.oldValue).join(' ');
      final allNew = gradleChanges.map((c) => c.newValue).join(' ');

      expect(allOld, contains('com.slimpumpkin.flutter_starter_kit'));
      expect(allNew, contains('com.example.my_app'));
    });

    test('project.pbxproj의 모든 PRODUCT_BUNDLE_IDENTIFIER를 변경한다', () {
      final changes = collectChanges(tempDir.path, 'com.example', 'my_app');
      final pbxprojChanges = changes
          .where((c) => c.filePath.endsWith('project.pbxproj'))
          .toList();

      expect(pbxprojChanges, isNotEmpty);

      for (final change in pbxprojChanges) {
        expect(change.oldValue, contains('com.slimpumpkin.flutterStarterKit'));
        expect(change.newValue, contains('com.example.myApp'));
      }
    });

    test('config/*.json의 appName을 Title Case로 변경한다', () {
      final changes = collectChanges(tempDir.path, 'com.example', 'my_app');
      final configChanges = changes
          .where((c) => c.filePath.contains('/config/'))
          .toList();

      expect(configChanges.length, greaterThanOrEqualTo(2));

      for (final change in configChanges) {
        expect(change.newValue, contains('My App'));
      }
    });

    test('Kotlin 디렉토리 이동과 package 선언 변경을 포함한다', () {
      final changes = collectChanges(tempDir.path, 'com.example', 'my_app');

      final moveChange = changes.firstWhere((c) => c.type == ChangeType.move);
      expect(
        moveChange.oldValue,
        contains('com/slimpumpkin/flutter_starter_kit'),
      );
      expect(moveChange.newValue, contains('com/example/my_app'));

      // Kotlin package 선언 변경
      final kotlinReplace = changes.firstWhere(
        (c) => c.filePath.endsWith('.kt') && c.type == ChangeType.replace,
      );
      expect(
        kotlinReplace.oldValue,
        contains('com.slimpumpkin.flutter_starter_kit'),
      );
      expect(kotlinReplace.newValue, contains('com.example.my_app'));
    });

    test('같은 패키지의 모든 Kotlin 파일 package 선언을 변경한다', () {
      // Phase 16.5 — MainActivity 가 참조하는 NaverHostChannel.kt 같은 동료
      // 파일이 옛 package 에 남으면 rename 뒤 컴파일이 깨진다.
      File(
        '${tempDir.path}/android/app/src/main/kotlin/com/slimpumpkin/flutter_starter_kit/NaverHostChannel.kt',
      ).writeAsStringSync(
        'package com.slimpumpkin.flutter_starter_kit\n\n'
        'class NaverHostChannel\n',
      );

      final changes = collectChanges(tempDir.path, 'com.example', 'my_app');
      final kotlinTargets =
          changes
              .where(
                (c) =>
                    c.filePath.endsWith('.kt') && c.type == ChangeType.replace,
              )
              .map((c) => c.filePath.split('/').last)
              .toList()
            ..sort();

      expect(kotlinTargets, <String>['MainActivity.kt', 'NaverHostChannel.kt']);
      for (final change in changes.where(
        (c) => c.filePath.endsWith('.kt') && c.type == ChangeType.replace,
      )) {
        expect(change.filePath, contains('com/example/my_app'));
        expect(change.newValue, 'package com.example.my_app');
      }
    });
  });

  group('dry-run 모드', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('rename_dryrun_');

      // 최소 구조 생성
      File(
        '${tempDir.path}/pubspec.yaml',
      ).writeAsStringSync('name: flutter_starter_kit\nversion: 1.0.0\n');
    });

    tearDown(() {
      tempDir.deleteSync(recursive: true);
    });

    test('dry-run 모드에서 실제 파일이 변경되지 않는다', () {
      collectChanges(tempDir.path, 'com.example', 'my_app');

      // dry-run에서는 applyChanges를 호출하지 않아야 함
      // 원본 파일이 변경되지 않았는지 확인
      final content = File('${tempDir.path}/pubspec.yaml').readAsStringSync();
      expect(content, contains('flutter_starter_kit'));
      expect(content, isNot(contains('my_app')));
    });
  });

  group('applyChanges', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('rename_apply_');

      // pubspec.yaml 생성
      File(
        '${tempDir.path}/pubspec.yaml',
      ).writeAsStringSync('name: flutter_starter_kit\nversion: 1.0.0\n');

      // lib dart 파일 생성
      Directory('${tempDir.path}/lib').createSync(recursive: true);
      File(
        '${tempDir.path}/lib/main.dart',
      ).writeAsStringSync("import 'package:flutter_starter_kit/app.dart';\n");

      // config json 생성
      Directory('${tempDir.path}/config').createSync(recursive: true);
      File('${tempDir.path}/config/dev.json').writeAsStringSync(
        '{"flavor":"dev","appName":"StarterKit Dev","appSuffix":".dev"}\n',
      );

      // scripts/firebase-configure.sh 생성
      _writeFirebaseConfigureFixture(
        tempDir.path,
        _kitFirebaseConfigureConstants,
      );
    });

    tearDown(() {
      tempDir.deleteSync(recursive: true);
    });

    test('apply 시 파일 내용이 실제로 변경된다', () {
      final changes = collectChanges(tempDir.path, 'com.example', 'my_app');

      // replace 타입만 필터 (move는 디렉토리가 없으면 에러 발생하므로 제외)
      final replaceChanges = changes
          .where((c) => c.type == ChangeType.replace)
          .toList();
      applyChanges(replaceChanges);

      // pubspec.yaml 은 그대로 (D-34 — Dart 패키지명 유지)
      final pubspec = File('${tempDir.path}/pubspec.yaml').readAsStringSync();
      expect(pubspec, contains('name: flutter_starter_kit'));
      expect(pubspec, isNot(contains('my_app')));

      // lib/main.dart import 도 그대로
      final mainDart = File('${tempDir.path}/lib/main.dart').readAsStringSync();
      expect(mainDart, contains('package:flutter_starter_kit/'));
      expect(mainDart, isNot(contains('package:my_app/')));

      // scripts/firebase-configure.sh 상수 3줄은 새 값
      final firebaseConfigure = File(
        '${tempDir.path}/scripts/firebase-configure.sh',
      ).readAsStringSync();
      for (final line in _renamedFirebaseConfigureConstants) {
        expect(firebaseConfigure.split('\n'), contains(line));
      }
      for (final line in _kitFirebaseConfigureConstants) {
        expect(firebaseConfigure, isNot(contains(line)));
      }

      // config/dev.json 확인
      final devJson = File(
        '${tempDir.path}/config/dev.json',
      ).readAsStringSync();
      expect(devJson, contains('My App'));
    });
  });

  group('CLI integration', () {
    late Directory tempDir;
    late String projectRoot;

    setUp(() {
      // 프로젝트 루트는 setUp 호출 시점의 cwd로 고정 (Process.start 시 cwd가
      // tempDir로 바뀌므로 binPath 결정에 사용)
      projectRoot = Directory.current.path;
      tempDir = Directory.systemTemp.createTempSync('rename_cli_eie_');

      // 최소 프로젝트 골격 (pubspec.yaml + lib/main.dart)
      File(
        '${tempDir.path}/pubspec.yaml',
      ).writeAsStringSync('name: flutter_starter_kit\nversion: 1.0.0\n');
      Directory('${tempDir.path}/lib').createSync(recursive: true);
      File(
        '${tempDir.path}/lib/main.dart',
      ).writeAsStringSync("import 'package:flutter_starter_kit/app.dart';\n");
      // 앱 ID 변경 대상 — 킷 원본 상수 3줄
      _writeFirebaseConfigureFixture(
        tempDir.path,
        _kitFirebaseConfigureConstants,
      );
    });

    tearDown(() {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    Future<({int exitCode, String stdout, String stderr})> runCli(
      List<String> args, {
      String? stdinInput,
    }) async {
      final binPath = '$projectRoot/bin/rename.dart';
      final proc = await Process.start(
        'fvm',
        ['dart', 'run', binPath, ...args],
        workingDirectory: tempDir.path,
        environment: {...Platform.environment, 'NO_COLOR': '1'},
      );
      if (stdinInput != null) {
        proc.stdin.writeln(stdinInput);
      }
      await proc.stdin.close();

      // CRITICAL: exitCode await 전에 stdout/stderr 드레이닝 시작.
      // 파이프 버퍼 포화로 인한 데드락 방지 (Pitfall 5).
      final outFuture = proc.stdout.transform(utf8.decoder).join();
      final errFuture = proc.stderr.transform(utf8.decoder).join();

      final code = await proc.exitCode.timeout(
        const Duration(seconds: 30),
        onTimeout: () =>
            throw TimeoutException('rename CLI did not exit within 30s'),
      );
      return (exitCode: code, stdout: await outFuture, stderr: await errFuture);
    }

    test('dry-run은 영어 출력과 [DRY RUN] prefix를 보여준다', () async {
      final result = await runCli(['--org', 'com.example', '--name', 'my_app']);
      expect(result.exitCode, 0);
      expect(result.stdout, contains('[DRY RUN]'));
      expect(
        result.stdout,
        contains(
          '[DRY RUN] App ID rename: '
          'com.slimpumpkin.flutter_starter_kit -> com.example.my_app',
        ),
      );
      expect(result.stdout, isNot(contains('Package rename:')));
      expect(result.stdout, contains('Changes to apply:'));
      expect(result.stdout, contains('Run with --apply to execute'));
      // F1: 한국어 문자열이 남아있지 않아야 한다
      expect(result.stdout, isNot(contains('변경 대상')));
      expect(result.stdout, isNot(contains('다음 단계')));
      // F1 회귀 가드: CJK Hangul Syllables 블록 전체 차단
      // (FileChange.description 필드까지 포함)
      expect(
        result.stdout,
        isNot(matches(RegExp(r'[\uAC00-\uD7AF]'))),
        reason:
            'CLI stdout must contain no Korean characters '
            '(F1 regression guard)',
      );
    });

    test("--apply without --yes는 prompt를 띄우고 'n'에서 중단한다", () async {
      final result = await runCli([
        '--org',
        'com.example',
        '--name',
        'my_app',
        '--apply',
      ], stdinInput: 'n');
      expect(result.exitCode, 0);
      expect(result.stdout, contains('Apply'));
      expect(result.stdout, contains('[y/N]'));
      expect(result.stdout, contains('Aborted by user.'));
      // F1 회귀 가드: --apply 경로도 printDryRun을 먼저 호출하므로 stdout에
      // FileChange.description이 흐른다. 한글 유니코드 블록 전체 차단.
      expect(
        result.stdout,
        isNot(matches(RegExp(r'[\uAC00-\uD7AF]'))),
        reason:
            'CLI stdout must contain no Korean characters '
            '(F1 regression guard)',
      );
      // 파일 미변경 (F2 + F4)
      expect(
        File('${tempDir.path}/pubspec.yaml').readAsStringSync(),
        contains('name: flutter_starter_kit'),
      );
      final firebaseConfigure = File(
        '${tempDir.path}/scripts/firebase-configure.sh',
      ).readAsStringSync();
      for (final line in _kitFirebaseConfigureConstants) {
        expect(firebaseConfigure.split('\n'), contains(line));
      }
    });

    test('--apply --yes는 prompt 없이 변경을 적용한다', () async {
      final result = await runCli([
        '--org',
        'com.example',
        '--name',
        'my_app',
        '--apply',
        '--yes',
      ]);
      expect(result.exitCode, 0);
      expect(result.stdout, isNot(contains('[y/N]')));
      expect(result.stdout, contains('Done!'));
      // F1 회귀 가드: --apply --yes 경로도 printDryRun을 먼저 호출하므로
      // stdout에 FileChange.description이 흐른다. 한글 유니코드 블록 전체 차단.
      expect(
        result.stdout,
        isNot(matches(RegExp(r'[\uAC00-\uD7AF]'))),
        reason:
            'CLI stdout must contain no Korean characters '
            '(F1 regression guard)',
      );
      // D-34: Dart 패키지명 · import 는 그대로, 앱 ID 만 바뀐다
      expect(
        File('${tempDir.path}/pubspec.yaml').readAsStringSync(),
        contains('name: flutter_starter_kit'),
      );
      expect(
        File('${tempDir.path}/lib/main.dart').readAsStringSync(),
        contains('package:flutter_starter_kit/'),
      );
      expect(
        File(
          '${tempDir.path}/scripts/firebase-configure.sh',
        ).readAsStringSync().split('\n'),
        contains('ANDROID_PACKAGE_PREFIX="com.example.my_app"'),
      );
    });

    test('잘못된 --org는 영어 에러로 exit 1', () async {
      final result = await runCli(['--org', 'Invalid', '--name', 'my_app']);
      expect(result.exitCode, 1);
      expect(result.stderr, contains('Invalid org format'));
      expect(result.stderr, isNot(contains('잘못된')));
    });

    test('필수 옵션 누락 시 스택 트레이스 대신 영어 에러', () async {
      final result = await runCli(const []);
      expect(result.exitCode, 1);
      expect(result.stderr, contains('--org and --name are required'));
      // BUG-ARGS: 스택 트레이스가 사용자에게 노출되면 안 된다
      expect(result.stderr, isNot(contains('Unhandled exception')));
      expect(result.stderr, isNot(contains('package:args/src')));
    });

    test('0건 변경 케이스는 진단 힌트를 출력한다', () async {
      // 이미 rename된 프로젝트 시뮬레이션 — 앱 ID 상수가 이미 새 값이다.
      // (pubspec · import 는 rename 대상이 아니므로 0건 판정과 무관하다)
      _writeFirebaseConfigureFixture(
        tempDir.path,
        _renamedFirebaseConfigureConstants,
      );
      final result = await runCli(['--org', 'com.example', '--name', 'my_app']);
      expect(result.exitCode, 0);
      expect(result.stdout, contains('No changes to apply.'));
      expect(result.stdout, contains('Possible reasons'));
      expect(
        result.stdout,
        contains('current app ID: com.slimpumpkin.flutter_starter_kit'),
      );
    });

    test('--project-prefix 로 PROJECT_ID_PREFIX 를 정한다', () async {
      final result = await runCli([
        '--org',
        'com.example',
        '--name',
        'my_app',
        '--project-prefix',
        'acme-app',
      ]);
      expect(result.exitCode, 0);
      expect(result.stdout, contains('-> PROJECT_ID_PREFIX="acme-app"'));
      expect(result.stdout, isNot(contains('PROJECT_ID_PREFIX="my-app"')));
      // dry-run 이므로 파일은 그대로다
      expect(
        File(
          '${tempDir.path}/scripts/firebase-configure.sh',
        ).readAsStringSync().split('\n'),
        contains('PROJECT_ID_PREFIX="slimpumpkin-starter-kit"'),
      );
    });

    test('잘못된 --project-prefix 는 영어 에러로 exit 1', () async {
      final result = await runCli([
        '--org',
        'com.example',
        '--name',
        'my_app',
        '--project-prefix',
        'Bad_Prefix',
      ]);
      expect(result.exitCode, 1);
      expect(result.stderr, contains('Invalid project prefix'));
      expect(
        result.stderr + result.stdout,
        isNot(matches(RegExp(r'[가-힯]'))),
        reason: 'CLI output must contain no Korean (F1 regression guard)',
      );
    });

    test('기본 project prefix 가 너무 길면 --project-prefix 를 안내한다', () async {
      // 기본 prefix = name 의 _ → - (30자) — 상한 25자 초과
      final result = await runCli([
        '--org',
        'com.example',
        '--name',
        'a_very_long_application_name_x',
      ]);
      expect(result.exitCode, 1);
      expect(result.stderr, contains('default project prefix'));
      expect(result.stderr, contains('--project-prefix'));
      expect(result.stdout, isNot(contains('[DRY RUN]')));
    });

    test('--help 는 앱 ID 도구 설명과 --project-prefix 를 보여준다', () async {
      final result = await runCli(['--help']);
      expect(result.exitCode, 0);
      expect(result.stdout, contains('Starter Kit App ID Rename Tool'));
      expect(result.stdout, contains('--project-prefix'));
      expect(
        result.stdout,
        contains('The Dart package name stays flutter_starter_kit'),
      );
      expect(result.stdout, isNot(contains('Package Rename Tool')));
      expect(
        result.stdout,
        isNot(matches(RegExp(r'[가-힯]'))),
        reason: 'CLI output must contain no Korean (F1 regression guard)',
      );
    });
  });
}
