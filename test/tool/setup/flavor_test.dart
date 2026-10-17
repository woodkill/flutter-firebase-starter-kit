import 'dart:io';

import 'package:test/test.dart';

import '../../../tool/setup/config_files.dart';
import '../../../tool/setup/flavor.dart';

/// 저장소에 추적되는 [flavor] 의 example config 에서 [key] 문자열을 읽는다.
String readExampleJson(Flavor flavor, String key) {
  final String? value = readJsonString(FlavorPaths(flavor).jsonExample, key);
  if (value == null) {
    throw StateError('${FlavorPaths(flavor).jsonExample} 에 $key 가 없습니다');
  }
  return value;
}

void main() {
  test(
    'T-20-FLAVOR-01: 접미사 · 자리표시 프로젝트 ID · 표시 이름 접미사 · 경로가 저장소 example 과 맞는다',
    () {
      // 접미사가 없는 prod 의 앱 이름이 표시 이름의 바탕이다.
      final String baseAppName = readExampleJson(Flavor.prod, 'appName');
      final String gradle = File(
        'android/app/build.gradle.kts',
      ).readAsStringSync();
      for (final Flavor flavor in Flavor.values) {
        final paths = FlavorPaths(flavor);
        expect(
          flavor.placeholderProjectId,
          readExampleJson(flavor, 'firebaseProjectId'),
          reason: flavor.name,
        );
        expect(
          flavor.suffix,
          readExampleJson(flavor, 'appSuffix'),
          reason: flavor.name,
        );
        expect(
          readExampleJson(flavor, 'appName'),
          '$baseAppName${flavor.displayNameSuffix}',
          reason: flavor.name,
        );
        expect(flavor.projectIdSuffix, '-${flavor.name}');
        expect(
          flavor.placeholderProjectId,
          endsWith(flavor.projectIdSuffix),
          reason: flavor.name,
        );
        // Gradle productFlavors 의 접미사와도 같다(prod 는 접미사 줄이 없다).
        final RegExpMatch? gradleSuffix = RegExp(
          'create\\("${flavor.name}"\\)\\s*\\{\\s*'
          'applicationIdSuffix\\s*=\\s*"([^"]*)"',
        ).firstMatch(gradle);
        expect(
          gradleSuffix?.group(1) ?? '',
          flavor.suffix,
          reason: flavor.name,
        );
        // xcconfig example 의 번들 ID 도 같은 접미사로 끝난다.
        final String? bundleId = readXcconfigValue(
          paths.xcconfigExample,
          'PRODUCT_BUNDLE_IDENTIFIER',
        );
        expect(bundleId, isNotNull, reason: flavor.name);
        expect(bundleId, endsWith(flavor.suffix), reason: flavor.name);

        expect(File(paths.jsonExample).existsSync(), isTrue);
        expect(File(paths.xcconfigExample).existsSync(), isTrue);
        expect(paths.json, paths.jsonExample.replaceFirst('.example', ''));
        expect(
          paths.xcconfig,
          paths.xcconfigExample.replaceFirst('.example', ''),
        );
        expect(paths.json, startsWith('config/'));
        expect(paths.xcconfig, startsWith('ios/Flutter/'));
        expect(paths.iosPlist, contains('/${flavor.name}/'));
        expect(paths.androidJson, contains('/${flavor.name}/'));
        expect(paths.dartOptions, endsWith('_${flavor.name}.dart'));
      }
      // 세 flavor 의 경로는 서로 겹치지 않는다.
      final jsonPaths = <String>{
        for (final Flavor flavor in Flavor.values) FlavorPaths(flavor).json,
      };
      expect(jsonPaths, hasLength(Flavor.values.length));
    },
  );

  test('T-20-FLAVOR-02: 모르는 이름 · 빈 값 · 대소문자가 다른 이름은 flavor 가 아니다', () {
    expect(Flavor.tryParse('qa'), isNull);
    expect(Flavor.tryParse(''), isNull);
    for (final Flavor flavor in Flavor.values) {
      expect(Flavor.tryParse(flavor.name), flavor);
      expect(Flavor.tryParse(flavor.name.toUpperCase()), isNull);
      expect(Flavor.tryParse(' ${flavor.name}'), isNull);
    }
  });
}
