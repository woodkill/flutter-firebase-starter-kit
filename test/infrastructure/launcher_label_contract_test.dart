// 홈 화면 런처 이름이 설정 위저드의 표시 이름을 따르는지 소스 계약으로 잠근다.
//
// 설정 위저드 「앱 정체성」 단계는 표시 이름을 `config/<flavor>.json` 의 `appName`
// 과 `ios/Flutter/<flavor>.xcconfig` 의 `DISPLAY_NAME` 에 쓴다. Android 는 Gradle
// 이 dart-define `appName` 을 string 리소스 `app_name` 으로 넣고, application label
// 이 쓰는 manifest placeholder 가 그 리소스를 가리킨다. iOS 는 Info.plist 의
// `CFBundleDisplayName` 이 flavor xcconfig 의 `DISPLAY_NAME` 빌드 변수를 쓴다. 어느 한 곳이라도 리터럴로 돌아가면
// 위저드에 넣은 이름이 홈 화면에 닿지 않는다. 예시 파일 두 곳의 기본 표시 이름이
// 서로 다르면 위저드 「앱 정체성」 단계 전에 빌드한 앱의 Android · iOS 런처 이름이
// 갈린다.
//
// 다른 언어의 홈 화면 이름은 ARB `appTitle` 에서 빌드 때 만든다. 「홈 화면 이름 생성
// 배선」 group 은 Gradle 생성 task · Xcode Run Script 단계가 저장소 루트의
// `tool/launcher_names.dart` 를 부르는 연결과, 정적 설정 파일에 언어 목록 · 언어별
// 이름을 적지 않는다는 약속을 잠근다 — 언어를 더할 때 바뀌는 파일은 ARB 하나다.
//
// 주석을 걷어낸 뒤 본다 — 설명 주석이 값 문자열을 언급하면 단언이 공허하게 참이
// 되기 때문이다(`test/helpers/source_text.dart` 머리 주석).

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import '../helpers/source_text.dart';

/// Android 앱 manifest 경로.
const String _manifestPath = 'android/app/src/main/AndroidManifest.xml';

/// Android 앱 모듈 Gradle 빌드 파일 경로.
const String _gradlePath = 'android/app/build.gradle.kts';

/// iOS 앱 Info.plist 경로.
const String _infoPlistPath = 'ios/Runner/Info.plist';

/// 킷의 세 flavor.
const List<String> _flavors = <String>['dev', 'stg', 'prod'];

/// flavor xcconfig 를 include 하는 빌드 구성 이름 앞부분.
const List<String> _buildModes = <String>['Debug', 'Profile', 'Release'];

/// Info.plist 에서 [key] 의 값이 [value] 문자열인지 보는 공백 무관 패턴을 만든다.
RegExp plistStringPattern(String key, String value) => RegExp(
  '<key>${RegExp.escape(key)}</key>\\s*'
  '<string>${RegExp.escape(value)}</string>',
);

/// 행 주석 · 블록 주석을 걷어낸 Android 앱 모듈 Gradle 빌드 파일을 읽는다.
String _readGradleCode() =>
    stripBlockComments(stripSlashComments(readTrackedFile(_gradlePath)));

/// [source] 에서 [opener](여는 괄호로 끝나는 호출 머리)부터 짝이 맞는 닫는 괄호
/// 앞까지의 인자 원문을 돌려준다.
///
/// 인자 안에 `get()` 같은 괄호가 있어도 짝을 세어 호출 전체를 읽는다. [opener] 가
/// 없거나 괄호 짝이 맞지 않으면 빈 문자열이다(호출자가 양성 대조를 먼저 세운다).
String _readCallArguments(String source, String opener) {
  final int start = source.indexOf(opener);
  if (start == -1) {
    return '';
  }
  final int argumentStart = start + opener.length;
  var depth = 1;
  for (var i = argumentStart; i < source.length; i++) {
    final String char = source[i];
    if (char == '(') {
      depth++;
    } else if (char == ')') {
      depth--;
      if (depth == 0) {
        return source.substring(argumentStart, i);
      }
    }
  }
  return '';
}

void main() {
  group('홈 화면 런처 이름 배선', () {
    test('Android 의 application label 은 리터럴이 아니라 appName placeholder 다', () {
      final String manifest = stripXmlComments(readTrackedFile(_manifestPath));
      final RegExpMatch? applicationTag = RegExp(
        r'<application\b[^>]*>',
      ).firstMatch(manifest);
      expect(applicationTag, isNotNull, reason: 'application 선언을 찾지 못했다');
      final String tag = applicationTag!.group(0)!;

      expect(
        countOccurrences(tag, 'android:label='),
        1,
        reason: 'application 의 label 속성은 정확히 1개여야 한다',
      );
      expect(
        tag,
        contains(r'android:label="${appName}"'),
        reason: '런처 이름은 Gradle 이 넘기는 appName placeholder 여야 한다',
      );
      // 양성 대조군 — 같은 태그 범위에서 기존 placeholder 참조를 잡는다.
      expect(tag, contains(r'android:name="${applicationName}"'));
    });

    test(
      'Gradle 은 appName placeholder 를 @string/app_name 으로 두고 기본 이름을 resValue app_name 으로 넣는다',
      () {
        final String gradle = stripBlockComments(
          stripSlashComments(readTrackedFile(_gradlePath)),
        );
        expect(
          countOccurrences(gradle, 'manifestPlaceholders["appName"]'),
          1,
          reason: 'appName placeholder 는 정확히 1곳에서 채운다',
        );
        expect(
          RegExp(
            r'manifestPlaceholders\["appName"\]\s*=\s*"@string/app_name"',
          ).hasMatch(gradle),
          isTrue,
          reason:
              '런처 이름은 언어별 값을 가질 수 있는 string 리소스 app_name 을 '
              '가리켜야 한다',
        );
        expect(
          RegExp(
            r'resValue\(\s*"string",\s*"app_name",\s*'
            r'dartDefines\["appName"\]\s*\?:\s*"[^"]+"\s*\)',
          ).hasMatch(gradle),
          isTrue,
          reason:
              '기본 언어 app_name 은 config 의 appName 이고, dart-define 없이도 '
              '리소스가 비어 있지 않은 기본 이름을 가져야 한다',
        );
      },
    );

    test('iOS 의 CFBundleDisplayName 은 리터럴이 아니라 DISPLAY_NAME 빌드 변수다', () {
      final String plist = stripXmlComments(readTrackedFile(_infoPlistPath));
      expect(countOccurrences(plist, '<key>CFBundleDisplayName</key>'), 1);
      expect(
        plistStringPattern(
          'CFBundleDisplayName',
          r'$(DISPLAY_NAME)',
        ).hasMatch(plist),
        isTrue,
        reason: '런처 이름은 flavor xcconfig 의 DISPLAY_NAME 이어야 한다',
      );
      // 양성 대조군 — 같은 패턴 함수가 기존 빌드 변수 참조를 잡는다.
      expect(
        plistStringPattern(
          'CFBundleIdentifier',
          r'$(PRODUCT_BUNDLE_IDENTIFIER)',
        ).hasMatch(plist),
        isTrue,
      );
    });

    test(
      'flavor 빌드 구성 9개는 flavor xcconfig 를 읽고 예시 xcconfig 셋은 DISPLAY_NAME 값을 둔다',
      () {
        final displayNameLine = RegExp(
          r'^DISPLAY_NAME[ \t]*=[ \t]*\S',
          multiLine: true,
        );
        for (final flavor in _flavors) {
          final String example = stripSlashComments(
            readTrackedFile('ios/Flutter/$flavor.example.xcconfig'),
          );
          expect(
            displayNameLine.allMatches(example).length,
            1,
            reason: '$flavor 예시 xcconfig 에 값이 있는 DISPLAY_NAME 줄이 1개여야 한다',
          );
          for (final mode in _buildModes) {
            final String wrapper = readTrackedFile(
              'ios/Flutter/$mode-$flavor.xcconfig',
            );
            expect(
              countExactLines(wrapper, '#include "$flavor.xcconfig"'),
              1,
              reason: '$mode-$flavor 구성이 $flavor.xcconfig 를 읽어야 한다',
            );
          }
        }
      },
    );

    test('예시 xcconfig 셋의 DISPLAY_NAME 은 같은 flavor 예시 json 의 appName 과 같다', () {
      final displayNameValue = RegExp(
        r'^DISPLAY_NAME[ \t]*=[ \t]*(.*?)[ \t]*$',
        multiLine: true,
      );
      for (final flavor in _flavors) {
        final String xcconfig = stripSlashComments(
          readTrackedFile('ios/Flutter/$flavor.example.xcconfig'),
        );
        final String? displayName = displayNameValue
            .firstMatch(xcconfig)
            ?.group(1);
        final Object? config = jsonDecode(
          readTrackedFile('config/$flavor.example.json'),
        );
        final Object? appName = config is Map<String, Object?>
            ? config['appName']
            : null;
        expect(
          displayName,
          isNotNull,
          reason: '$flavor 예시 xcconfig 에 DISPLAY_NAME 줄이 있어야 한다',
        );
        expect(
          appName,
          isA<String>(),
          reason: '$flavor 예시 json 에 문자열 appName 이 있어야 한다',
        );
        expect(
          displayName,
          appName,
          reason: '$flavor 예시의 DISPLAY_NAME 과 appName 이 다르면 런처 이름이 갈린다',
        );
      }
    });
  });

  group('홈 화면 이름 생성 배선', () {
    test(
      'T-22-WIRE-01: Gradle 생성 task 가 Flutter SDK dart 로 생성기 android 모드를 부르고 결과를 생성 res 로 붙인다',
      () {
        final String gradle = _readGradleCode();
        for (final token in <String>[
          'abstract class GenerateLauncherNamesTask',
          'onVariants',
          'addGeneratedSourceDirectory(',
          '"../tool/launcher_names.dart"',
          '"../l10n.yaml"',
          '"../lib/l10n"',
          '@get:OutputDirectory',
        ]) {
          expect(
            countOccurrences(gradle, token),
            1,
            reason: 'Gradle 에 $token 이 정확히 1번 있어야 한다',
          );
        }
        for (final token in <String>[
          'ExecOperations',
          'flutter.sdk',
          '/bin/dart',
        ]) {
          expect(
            countOccurrences(gradle, token),
            greaterThanOrEqualTo(1),
            reason: 'Gradle 에 $token 이 있어야 한다',
          );
        }
        expect(
          RegExp(r'getProperty\(\s*"flutter\.sdk"\s*\)').hasMatch(gradle),
          isTrue,
          reason: 'dart 경로는 local.properties 의 flutter.sdk 에서 읽어야 한다',
        );
        expect(
          RegExp(
            r'addGeneratedSourceDirectory\(\s*task,\s*'
            r'GenerateLauncherNamesTask::outputDirectory\s*\)',
          ).hasMatch(gradle),
          isTrue,
          reason: '생성 task 의 출력 디렉터리를 variant 의 생성 res 로 붙여야 한다',
        );
        expect(
          RegExp(
            r'commandLine\(\s*dartExecutable\.get\(\),\s*'
            r'generator\.get\(\)\.asFile\.absolutePath,\s*"android",',
          ).hasMatch(gradle),
          isTrue,
          reason: '생성기 경로 바로 뒤 첫 인자는 "android" 여야 한다',
        );
      },
    );

    test('T-22-WIRE-02: 생성기는 dart run 이 아니라 주입한 ExecOperations 로 바로 실행한다', () {
      final String gradle = _readGradleCode();
      // 양성 대조 — 실행 호출이 각각 1곳에 있다.
      expect(countOccurrences(gradle, 'commandLine('), 1);
      expect(countOccurrences(gradle, 'execOperations.exec'), 1);
      final String arguments = _readCallArguments(gradle, 'commandLine(');
      expect(
        countOccurrences(arguments, '"android"'),
        1,
        reason: '명령 인자 전체를 읽어야 한다(양성 대조)',
      );

      expect(
        RegExp(r'commandLine\([^)]*"run"').hasMatch(gradle),
        isFalse,
        reason: 'dart run 은 빌드 중 패키지 해석을 끼워 넣는다',
      );
      expect(
        countOccurrences(arguments, '"run"'),
        0,
        reason: '명령 인자 어디에도 "run" 이 없어야 한다',
      );
      expect(
        countOccurrences(gradle, 'project.exec'),
        0,
        reason: 'Gradle 9 에서 없어진 project.exec 대신 ExecOperations 를 쓴다',
      );
    });

    test('T-22-WIRE-03: 파일 머리에서 import 한 Java 클래스를 본문은 짧은 이름으로만 쓴다', () {
      final String gradle = _readGradleCode();
      expect(
        countExactLines(gradle, 'import java.io.ByteArrayOutputStream'),
        1,
      );
      expect(countExactLines(gradle, 'import java.util.Properties'), 1);

      final String body = gradle
          .split('\n')
          .where((String line) => !line.startsWith('import'))
          .join('\n');
      // 양성 대조 — 본문이 두 클래스를 짧은 이름으로 쓴다.
      expect(countOccurrences(body, 'ByteArrayOutputStream()'), 1);
      expect(countOccurrences(body, 'Properties()'), greaterThanOrEqualTo(1));

      expect(
        countOccurrences(body, 'java.io.'),
        0,
        reason: 'Kotlin 스크립트 본문의 java.io 완전 이름은 import 로 옮긴다',
      );
      expect(
        countOccurrences(body, 'java.util.Properties('),
        0,
        reason: 'Kotlin 스크립트 본문의 java.util.Properties 완전 이름은 import 로 옮긴다',
      );
    });

    test('T-22-WIRE-04: dartDefines 는 android 블록보다 앞의 파일 최상위에서 만든다', () {
      final String gradle = _readGradleCode();
      final int definesAt = gradle.indexOf('val dartDefines');
      final int? androidAt = RegExp(
        r'^android\s*\{',
        multiLine: true,
      ).firstMatch(gradle)?.start;
      expect(definesAt, greaterThanOrEqualTo(0));
      expect(androidAt, isNotNull, reason: '줄 머리 android 블록이 있어야 한다');
      expect(
        RegExp(r'^val dartDefines\b', multiLine: true).hasMatch(gradle),
        isTrue,
        reason: '생성 task 등록도 읽으므로 dartDefines 는 최상위 선언이어야 한다',
      );
      expect(
        definesAt < androidAt!,
        isTrue,
        reason: 'dartDefines 는 android 블록보다 앞에 있어야 한다',
      );
    });

    test('T-22-WIRE-05: Android 13 앱별 언어 설정 키는 Gradle · manifest 에 두지 않는다', () {
      // 이 시험 소스가 두 낱말을 그대로 담지 않게 조각을 잇는다.
      final perAppLocaleKeys = <String>[
        '${'locale'}Config',
        'generate${'Locale'}Config',
      ];
      final String gradle = _readGradleCode();
      final String manifest = stripXmlComments(readTrackedFile(_manifestPath));
      // 양성 대조 — 두 파일에서 같은 API 가 기존 설정을 잡는다.
      expect(countOccurrences(gradle, 'resValues = true'), 1);
      expect(
        countOccurrences(manifest, 'android:label='),
        greaterThanOrEqualTo(1),
      );

      for (final key in perAppLocaleKeys) {
        expect(
          countOccurrences(gradle, key),
          0,
          reason: 'Gradle 에 $key 가 없어야 한다',
        );
        expect(
          countOccurrences(manifest, key),
          0,
          reason: 'manifest 에 $key 가 없어야 한다',
        );
      }
    });

    test('T-22-WIRE-06: 정적 Info.plist 는 언어 목록을 적지 않고 SDK 표시 이름은 기본 이름 하나다', () {
      final String plist = stripXmlComments(readTrackedFile(_infoPlistPath));
      // 양성 대조 — 같은 꼴의 키를 같은 API 가 잡는다.
      expect(countOccurrences(plist, '<key>CFBundleDisplayName</key>'), 1);
      expect(
        countOccurrences(plist, '<key>CFBundleLocalizations</key>'),
        0,
        reason: '지원 언어 목록은 빌드된 Info.plist 에만 넣는다',
      );
      expect(countOccurrences(plist, 'CFBundleLocalizations'), 0);

      for (final key in <String>['FacebookDisplayName', 'NidAppName']) {
        expect(countOccurrences(plist, '<key>$key</key>'), 1);
        expect(
          plistStringPattern(key, r'$(DISPLAY_NAME)').hasMatch(plist),
          isTrue,
          reason: '$key 는 flavor xcconfig 의 DISPLAY_NAME 하나여야 한다',
        );
      }
    });
  });
}
