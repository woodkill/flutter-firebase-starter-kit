import 'dart:convert';
import 'dart:io';

import 'package:flutter_starter_kit/core/config/auth_retry_config.dart';
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
        // CR-02 (Phase 13 review): config/{flavor}.json 은 .gitignore 대상.
        // fresh clone / CI 에서 missing 시 graceful skip — entire suite fail
        // 회피 (app_config_test 와 동일 정책).
        final file = File('config/$flavor.json');
        if (!file.existsSync()) {
          markTestSkipped(
            'config/$flavor.json missing — `cp config/$flavor.example.json '
            'config/$flavor.json` 실행 후 재시도.',
          );
          return;
        }
        final content = file.readAsStringSync();
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

  group('WR-10: minDuration 값 범위 계약', () {
    tearDown(() => SplashConfig.overrideMinDuration = null);

    test('허용 범위 상수가 0~10000ms 로 고정되어 있다', () {
      expect(SplashConfig.minAllowedMs, 0);
      expect(SplashConfig.maxAllowedMs, 10000);
    });

    test('주입값(2000ms)은 범위 안이므로 assert 없이 통과한다', () {
      // dart-define 미주입 테스트 환경의 기본값 경로.
      expect(SplashConfig.minDurationMs, 2000);
      expect(SplashConfig.minDuration, const Duration(milliseconds: 2000));
    });

    test('경계값 0 / 10000 은 clamp 되지 않는다', () {
      expect(
        0.clamp(SplashConfig.minAllowedMs, SplashConfig.maxAllowedMs),
        0,
        reason: '하한 경계는 그대로 통과해야 한다',
      );
      expect(
        10000.clamp(SplashConfig.minAllowedMs, SplashConfig.maxAllowedMs),
        10000,
        reason: '상한 경계는 그대로 통과해야 한다',
      );
    });

    test('범위 밖 값은 clamp 로 무해화된다 (release 경로 계약)', () {
      // 음수: Future.delayed 는 음수 Duration 을 즉시 완료로 처리하므로
      // 스플래시 최소 표시가 통째로 사라지고 D-23 이 깨진다.
      expect(
        (-1).clamp(SplashConfig.minAllowedMs, SplashConfig.maxAllowedMs),
        0,
      );
      // 과대값: 2000000ms = 33분 스플래시 = 사용자에게는 앱 정지.
      expect(
        2000000.clamp(SplashConfig.minAllowedMs, SplashConfig.maxAllowedMs),
        10000,
      );
    });

    test('minDuration 이 범위 검증 + clamp 를 수행하도록 유지된다 (소스 계약)', () async {
      // dart-define 은 컴파일 타임 상수라 테스트에서 범위 밖 값을 주입할 수
      // 없다. 검증 로직의 존재 자체를 소스 계약으로 잠근다.
      final source = await File(
        'lib/core/config/splash_config.dart',
      ).readAsString();
      final codeOnly = source
          .split('\n')
          .where((line) {
            final trimmed = line.trimLeft();
            return !trimmed.startsWith('//') && !trimmed.startsWith('///');
          })
          .join('\n');
      expect(
        RegExp(r'assert\(\s*\n?\s*ms >= minAllowedMs').hasMatch(codeOnly),
        isTrue,
        reason: 'WR-10: debug 범위 assert 가 사라졌다',
      );
      expect(
        RegExp(r'clamp\(minAllowedMs,\s*maxAllowedMs\)').hasMatch(codeOnly),
        isTrue,
        reason: 'WR-10: release clamp 가 사라졌다',
      );
    });

    test('overrideMinDuration 은 clamp 대상이 아니다 (명시적 테스트 seam)', () {
      // splash_screen_test 가 타임아웃 경로 검증에 5분을 주입한다.
      SplashConfig.overrideMinDuration = const Duration(minutes: 5);
      expect(SplashConfig.minDuration, const Duration(minutes: 5));
    });
  });

  group('IN-07: SplashConfig / AuthRetryConfig 책임 분리', () {
    tearDown(() => AuthRetryConfig.overrideBackoffSteps = null);

    test('retry 정책이 AuthRetryConfig 로 이전됐다', () {
      expect(AuthRetryConfig.backoffSteps, const <Duration>[
        Duration(seconds: 1),
        Duration(seconds: 2),
        Duration(seconds: 4),
      ]);
      expect(
        AuthRetryConfig.effectiveBackoffSteps,
        AuthRetryConfig.backoffSteps,
      );
    });

    test('AuthRetryConfig override seam 이 동작한다', () {
      AuthRetryConfig.overrideBackoffSteps = const [Duration(milliseconds: 1)];
      expect(AuthRetryConfig.effectiveBackoffSteps, const <Duration>[
        Duration(milliseconds: 1),
      ]);
      AuthRetryConfig.overrideBackoffSteps = null;
      expect(
        AuthRetryConfig.effectiveBackoffSteps,
        AuthRetryConfig.backoffSteps,
      );
    });

    test('splash_config.dart 에 retry 관련 선언이 남아 있지 않다 (소스 계약)', () async {
      final source = await File(
        'lib/core/config/splash_config.dart',
      ).readAsString();
      for (final symbol in const <String>[
        'backoffSteps',
        'overrideBackoffSteps',
        'effectiveBackoffSteps',
      ]) {
        expect(
          source.contains(symbol),
          isFalse,
          reason: 'IN-07: $symbol 은 AuthRetryConfig 소관이다',
        );
      }
    });

    test('assert-IIFE 중복이 writeIfDebug 헬퍼 1곳으로 모였다 (소스 계약)', () async {
      // 수정 전에는 동일한 IIFE 블록이 "WR-02 verbatim 복제" 라는 주석과 함께
      // 통째로 두 번 나타났다.
      for (final path in const <String>[
        'lib/core/config/splash_config.dart',
        'lib/core/config/auth_retry_config.dart',
      ]) {
        final source = await File(path).readAsString();
        final codeOnly = source
            .split('\n')
            .where((line) {
              final trimmed = line.trimLeft();
              return !trimmed.startsWith('//') && !trimmed.startsWith('///');
            })
            .join('\n');
        expect(
          RegExp(r'assert\(\s*\(\)\s*\{').hasMatch(codeOnly),
          isFalse,
          reason: 'IN-07: $path 에 assert-IIFE 가 다시 인라인됐다',
        );
        expect(
          codeOnly.contains('writeIfDebug'),
          isTrue,
          reason: 'IN-07: $path 는 공용 헬퍼를 사용해야 한다',
        );
      }
    });
  });
}
