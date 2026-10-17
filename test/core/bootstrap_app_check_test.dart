// App Check 디버그 토큰 주입 계약 (T-19-APPCHECK-APP-01 ~ 04).
//
// config 의 `appCheckDebugToken` 키가 `--dart-define-from-file` →
// [AppConfig.appCheckDebugToken] → bootstrap 의 debug provider 인자까지
// 이어지는지 확인한다. 실 SDK 의 activate 는 Firebase 없이 실행할 수 없으므로
// bootstrap 은 소스 문자열 계약으로 검증한다(주석 줄 제거 후 매칭 · 공백 무관
// RegExp — 포매터가 인자를 다음 줄로 나눠도 같은 결과).
//
// T-19-APPCHECK-APP-01: getter 가 dart-define 값을 그대로 읽고, 빈 값이면
//   [AppConfig.appCheckDebugTokenOrNull] 이 null 이다.
// T-19-APPCHECK-APP-02: define 이 있을 때만 돈다 — OrNull 이 null 이 아니다.
// T-19-APPCHECK-APP-03: 토큰 인자는 `kDebugMode` 삼항의 debug 쪽에만 있고
//   release provider 는 그대로다.
// T-19-APPCHECK-APP-04: example 3종의 `appCheckDebugToken` 은 빈 문자열이고
//   마지막 키다.

import 'dart:convert';

import 'package:flutter_starter_kit/core/config/app_config.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/source_text.dart';

/// bootstrap 소스 경로.
const String _bootstrapPath = 'lib/core/bootstrap.dart';

/// [source] 에서 [pattern] 이 나타나는 횟수를 센다.
int _countMatches(String source, Pattern pattern) =>
    pattern.allMatches(source).length;

void main() {
  group('App Check 디버그 토큰 주입 (T-19-APPCHECK-APP)', () {
    test('T-19-APPCHECK-APP-01: appCheckDebugToken 은 dart-define 값이고 '
        '빈 값이면 OrNull 이 null 이다', () {
      const defined = String.fromEnvironment('appCheckDebugToken');
      expect(AppConfig.appCheckDebugToken, defined);
      if (defined.isEmpty) {
        expect(AppConfig.appCheckDebugTokenOrNull, isNull);
      } else {
        expect(AppConfig.appCheckDebugTokenOrNull, defined);
      }
    });

    test(
      'T-19-APPCHECK-APP-02: define 이 있으면 OrNull 이 그 값이다',
      () {
        expect(AppConfig.appCheckDebugTokenOrNull, isNotNull);
        expect(
          AppConfig.appCheckDebugTokenOrNull,
          AppConfig.appCheckDebugToken,
        );
      },
      skip: AppConfig.appCheckDebugToken.isEmpty
          ? 'appCheckDebugToken define 없음'
          : false,
    );

    test('T-19-APPCHECK-APP-03: 토큰 인자는 debug provider 에만 있고 '
        'release provider 는 그대로다', () {
      final String code = stripSlashComments(readTrackedFile(_bootstrapPath));

      expect(
        _countMatches(
          code,
          RegExp(
            r'AndroidDebugProvider\(\s*'
            r'debugToken:\s*AppConfig\.appCheckDebugTokenOrNull',
          ),
        ),
        1,
        reason: 'Android debug provider 에 config 토큰 인자가 1회 있어야 한다',
      );
      expect(
        _countMatches(
          code,
          RegExp(
            r'AppleDebugProvider\(\s*'
            r'debugToken:\s*AppConfig\.appCheckDebugTokenOrNull',
          ),
        ),
        1,
        reason: 'Apple debug provider 에 config 토큰 인자가 1회 있어야 한다',
      );
      expect(
        _countMatches(code, RegExp(r'AndroidPlayIntegrityProvider\(\s*\)')),
        1,
        reason: 'release Android provider 가 인자 없이 1회 있어야 한다',
      );
      expect(
        _countMatches(code, RegExp(r'AppleDeviceCheckProvider\(\s*\)')),
        1,
        reason: 'release Apple provider 가 인자 없이 1회 있어야 한다',
      );
      expect(
        _countMatches(code, RegExp(r'const\s+AndroidDebugProvider\(\s*\)')),
        0,
        reason: '인자 없는 Android debug provider 가 남아 있다',
      );
      expect(
        _countMatches(code, RegExp(r'const\s+AppleDebugProvider\(\s*\)')),
        0,
        reason: '인자 없는 Apple debug provider 가 남아 있다',
      );
      expect(
        _countMatches(code, RegExp('debugToken:')),
        2,
        reason: '토큰 인자는 debug provider 두 곳에만 있어야 한다',
      );
      expect(
        RegExp(
          r'kDebugMode\s*\?\s*AndroidDebugProvider\(\s*debugToken:[^:]*:\s*'
          r'const\s+AndroidPlayIntegrityProvider\(\s*\)',
        ).hasMatch(code),
        isTrue,
        reason: 'Android 토큰 인자가 kDebugMode 삼항의 debug 쪽에 있어야 한다',
      );
      expect(
        RegExp(
          r'kDebugMode\s*\?\s*AppleDebugProvider\(\s*debugToken:[^:]*:\s*'
          r'const\s+AppleDeviceCheckProvider\(\s*\)',
        ).hasMatch(code),
        isTrue,
        reason: 'Apple 토큰 인자가 kDebugMode 삼항의 debug 쪽에 있어야 한다',
      );
    });

    test('T-19-APPCHECK-APP-04: example 3종의 appCheckDebugToken 은 빈 문자열이고 '
        '마지막 키다', () {
      for (final flavor in const <String>['dev', 'stg', 'prod']) {
        final path = 'config/$flavor.example.json';
        final json = jsonDecode(readTrackedFile(path)) as Map<String, Object?>;
        expect(
          json['appCheckDebugToken'],
          '',
          reason: '$path 의 appCheckDebugToken 이 빈 문자열이 아니다',
        );
        expect(
          json.keys.last,
          'appCheckDebugToken',
          reason: '$path 의 마지막 키가 appCheckDebugToken 이 아니다',
        );
      }
    });
  });
}
