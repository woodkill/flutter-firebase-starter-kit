// 홈 화면 런처 이름이 설정 위저드의 표시 이름을 따르는지 소스 계약으로 잠근다.
//
// 설정 위저드 「앱 정체성」 단계는 표시 이름을 `config/<flavor>.json` 의 `appName`
// 과 `ios/Flutter/<flavor>.xcconfig` 의 `DISPLAY_NAME` 에 쓴다. Android 는 Gradle
// 이 dart-define `appName` 을 manifest placeholder 로 넘기고 application label 이
// 그 placeholder 를 쓴다. iOS 는 Info.plist 의 `CFBundleDisplayName` 이 flavor
// xcconfig 의 `DISPLAY_NAME` 빌드 변수를 쓴다. 어느 한 곳이라도 리터럴로 돌아가면
// 위저드에 넣은 이름이 홈 화면에 닿지 않는다. 예시 파일 두 곳의 기본 표시 이름이
// 서로 다르면 위저드 「앱 정체성」 단계 전에 빌드한 앱의 Android · iOS 런처 이름이
// 갈린다.
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
      'Gradle 은 appName placeholder 를 dart-define appName 으로 채우고 없으면 기본 이름을 쓴다',
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
            r'manifestPlaceholders\["appName"\]\s*=\s*'
            r'dartDefines\["appName"\]\s*\?:\s*"[^"]+"',
          ).hasMatch(gradle),
          isTrue,
          reason:
              'dart-define 없이 빌드해도 manifest 병합이 placeholder 값을 '
              '얻도록 비어 있지 않은 기본 이름이 있어야 한다',
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
}
