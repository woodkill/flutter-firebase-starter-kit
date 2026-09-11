import 'dart:io';

import 'package:flutter_starter_kit/core/config/app_config.dart';
import 'package:flutter_starter_kit/core/firebase/firebase_initializer.dart';
import 'package:flutter_test/flutter_test.dart';

/// `firebase_initializer.dart` 의 flavor 분기 계약을 검증한다.
///
/// [Firebase.initializeApp] 은 Flutter 엔진 바인딩과 네이티브 플랫폼 채널을
/// 요구하므로 순수 dart 테스트에서 실행할 수 없다. 따라서
/// (1) flavor 해석 단계까지만 도달하는 실행 계약 (미주입 시 [StateError]) 과
/// (2) 소스 문자열 기반 계약 (switch 3 arm 명시 / silent fallback 부재) 을
/// 함께 검증한다 — `bootstrap_crashlytics_test.dart` 패턴 일관.
void main() {
  group('initializeFirebase 실행 계약', () {
    test('테스트 환경은 flavor dart-define 미주입 → 빈 문자열', () {
      expect(
        AppConfig.flavor,
        isEmpty,
        reason: '이 테스트 파일의 나머지 기대값은 flavor 미주입을 전제한다.',
      );
    });

    test('flavor 미주입 시 dev 로 흡수하지 않고 StateError 를 던진다', () {
      // CR-01: `_ => dev` silent fallback 회귀 가드. placeholder 의
      // UnsupportedError(= false 반환) 와 명확히 구분되어야 한다.
      expect(
        initializeFirebase,
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            allOf(contains('flavor'), contains('dart-define')),
          ),
        ),
      );
    });
  });

  group('firebase_initializer.dart 소스 계약', () {
    late String source;

    setUpAll(() async {
      source = await File(
        'lib/core/firebase/firebase_initializer.dart',
      ).readAsString();
    });

    test('flavor 를 자체 String.fromEnvironment 로 재해석하지 않는다', () {
      expect(
        source.contains("String.fromEnvironment('flavor'"),
        isFalse,
        reason: 'flavor 의 단일 진실원은 AppConfig.flavor 이다 (WR-07 hotfix).',
      );
      expect(
        source.contains("defaultValue: 'dev'"),
        isFalse,
        reason: "defaultValue: 'dev' 는 미주입 빌드를 dev 로 흡수한다.",
      );
    });

    test('AppConfig.flavor 를 switch 대상으로 사용한다', () {
      // dart-format.md 3항 — whitespace-insensitive 매칭.
      expect(
        RegExp(r'switch\s*\(\s*AppConfig\.flavor\s*\)').hasMatch(source),
        isTrue,
        reason: 'switch 대상은 AppConfig.flavor 여야 한다.',
      );
    });

    test("switch 에 'dev'/'stg'/'prod' 3 arm 이 명시된다", () {
      for (final flavor in const ['dev', 'stg', 'prod']) {
        expect(
          RegExp("'$flavor'\\s*=>").hasMatch(source),
          isTrue,
          reason: "'$flavor' arm 이 명시되어야 한다.",
        );
      }
    });

    test('미지원 flavor 는 기본 분기로 흡수되지 않고 StateError 로 간다', () {
      expect(
        RegExp(r'final\s+unknown\s*=>\s*throw\s+StateError').hasMatch(source),
        isTrue,
        reason: 'default arm 은 dev fallback 이 아니라 StateError 여야 한다.',
      );
      expect(
        RegExp(r'^\s*_\s*=>').hasMatch(source),
        isFalse,
        reason: '익명 기본 분기(`_ =>`)는 오타 flavor 를 조용히 흡수한다.',
      );
    });
  });
}
