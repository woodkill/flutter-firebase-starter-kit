import 'dart:convert';
import 'dart:io';

import 'package:flutter_starter_kit/core/config/splash_config.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SplashConfig', () {
    tearDown(() {
      // 테스트 간 격리를 위해 seam 해제
      SplashConfig.overrideMinDuration = null;
    });

    test('minDurationMs는 --dart-define 없으면 기본 2000ms 반환', () {
      expect(SplashConfig.minDurationMs, 2000);
    });

    test('minDuration은 Duration(milliseconds: minDurationMs)와 일치', () {
      expect(
        SplashConfig.minDuration,
        Duration(milliseconds: SplashConfig.minDurationMs),
      );
    });

    test('기본값은 정확히 2초 (AUTH-09 계약)', () {
      expect(SplashConfig.minDurationMs, equals(2000));
      expect(SplashConfig.minDuration.inSeconds, equals(2));
    });

    test(
      'overrideMinDuration 설정 시 minDuration이 오버라이드 값 반환 (WARNING #13 seam)',
      () {
        SplashConfig.overrideMinDuration = const Duration(milliseconds: 1);
        expect(SplashConfig.minDuration, const Duration(milliseconds: 1));
        SplashConfig.overrideMinDuration = null;
        expect(
          SplashConfig.minDuration,
          Duration(milliseconds: SplashConfig.minDurationMs),
        );
      },
    );
  });

  group('config JSON 무결성', () {
    for (final flavor in <String>['dev', 'stg', 'prod']) {
      test('$flavor.json은 splashMinDurationMs 키를 가진다', () {
        final content = File('config/$flavor.json').readAsStringSync();
        final json = jsonDecode(content) as Map<String, dynamic>;
        expect(
          json.containsKey('splashMinDurationMs'),
          isTrue,
          reason: 'config/$flavor.json에 splashMinDurationMs 키 누락',
        );
        expect(json['splashMinDurationMs'], 2000);
      });
    }
  });
}
