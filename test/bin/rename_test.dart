import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

import '../../bin/rename.dart';

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
    });

    tearDown(() {
      tempDir.deleteSync(recursive: true);
    });

    test('모든 변경 대상 카테고리를 수집한다', () {
      final changes = collectChanges(tempDir.path, 'com.example', 'my_app');

      // pubspec.yaml 변경 포함 확인
      final pubspecChanges = changes.where(
        (c) => c.filePath.endsWith('pubspec.yaml'),
      );
      expect(pubspecChanges, isNotEmpty);

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

      // lib/*.dart import 변경 포함 확인
      final libChanges = changes.where(
        (c) => c.filePath.contains('/lib/') && c.type == ChangeType.replace,
      );
      expect(libChanges, isNotEmpty);

      // test/*.dart import 변경 포함 확인
      final testChanges = changes.where(
        (c) => c.filePath.contains('/test/') && c.type == ChangeType.replace,
      );
      expect(testChanges, isNotEmpty);

      // config/*.json 변경 포함 확인
      final configChanges = changes.where(
        (c) => c.filePath.contains('/config/'),
      );
      expect(configChanges, isNotEmpty);
    });

    test('pubspec.yaml의 name 필드를 새 이름으로 변경한다', () {
      final changes = collectChanges(tempDir.path, 'com.example', 'my_app');
      final pubspecChange = changes.firstWhere(
        (c) => c.filePath.endsWith('pubspec.yaml'),
      );

      expect(pubspecChange.oldValue, contains('flutter_starter_kit'));
      expect(pubspecChange.newValue, contains('my_app'));
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

      // pubspec.yaml 확인
      final pubspec = File('${tempDir.path}/pubspec.yaml').readAsStringSync();
      expect(pubspec, contains('name: my_app'));
      expect(pubspec, isNot(contains('flutter_starter_kit')));

      // lib/main.dart 확인
      final mainDart = File('${tempDir.path}/lib/main.dart').readAsStringSync();
      expect(mainDart, contains('package:my_app/'));
      expect(mainDart, isNot(contains('package:flutter_starter_kit/')));

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
      expect(
        File('${tempDir.path}/pubspec.yaml').readAsStringSync(),
        contains('name: my_app'),
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
      // 이미 rename된 프로젝트 시뮬레이션
      File(
        '${tempDir.path}/pubspec.yaml',
      ).writeAsStringSync('name: my_app\nversion: 1.0.0\n');
      File(
        '${tempDir.path}/lib/main.dart',
      ).writeAsStringSync("import 'package:my_app/app.dart';\n");
      final result = await runCli(['--org', 'com.example', '--name', 'my_app']);
      expect(result.exitCode, 0);
      expect(result.stdout, contains('No changes to apply.'));
      expect(result.stdout, contains('Possible reasons'));
    });
  });
}
