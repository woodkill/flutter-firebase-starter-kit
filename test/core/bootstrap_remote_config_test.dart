import 'dart:io';

import 'package:flutter_starter_kit/core/auth/provider_id.dart';
import 'package:flutter_starter_kit/core/config/app_config.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('bootstrap Remote Config 통합 (D-24, D-25)', () {
    test('AppConfig.authProviders 가 8 providerId 모두 포함한다 (setDefaults 입력)', () {
      final map = AppConfig.authProviders;
      expect(map.keys.toSet(), kAllProviderIds.toSet());
    });

    test('setDefaults 인자 형태가 auth_provider_{id}_enabled 평탄 키 패턴이다', () {
      // bootstrap.dart 의 for-comprehension 미러 — 키 prefix 회귀 가드
      final defaults = <String, Object>{
        for (final entry in AppConfig.authProviders.entries)
          'auth_provider_${entry.key}_enabled': entry.value,
      };
      expect(defaults.length, kAllProviderIds.length);
      for (final id in kAllProviderIds) {
        expect(
          defaults.containsKey('auth_provider_${id}_enabled'),
          isTrue,
          reason: 'missing default key for $id',
        );
      }
    });

    test('bootstrap.dart 의 RC 코드 블록이 try / on Object catch 로 D-25 폴백 의무를 표현한다',
        () {
      // 회귀 가드: bootstrap 의 RC 블록 코드 패턴 정합 확인
      // (bootstrap.dart 자체를 string 으로 read 후 grep 기반 invariant 검증)
      final source = File('lib/core/bootstrap.dart').readAsStringSync();
      expect(source.contains('FirebaseRemoteConfig.instance'), isTrue);
      expect(source.contains('setDefaults'), isTrue);
      expect(source.contains('fetchAndActivate'), isTrue);
      expect(
        source.contains('on Object catch'),
        isTrue,
        reason: 'D-25 폴백: try / on Object catch 가 RC 블록을 감싸야 한다',
      );
      // RC 호출이 isFirebaseInitialized 블록 내부에 위치 (D-13)
      final initIdx = source.indexOf('if (isFirebaseInitialized)');
      final fetchIdx = source.indexOf('fetchAndActivate');
      expect(initIdx, greaterThan(0));
      expect(
        fetchIdx,
        greaterThan(initIdx),
        reason: 'fetchAndActivate 는 isFirebaseInitialized 블록 안에 있어야 한다',
      );
    });

    test('RC fetch 주기: dev=0, 그 외=12h (D-23)', () {
      final source = File('lib/core/bootstrap.dart').readAsStringSync();
      expect(source.contains("flavor == 'dev'"), isTrue);
      expect(source.contains('Duration.zero'), isTrue);
      expect(source.contains('Duration(hours: 12)'), isTrue);
    });
  });
}
