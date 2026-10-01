import 'dart:io';

import 'package:flutter_starter_kit/core/auth/provider_id.dart';
import 'package:flutter_starter_kit/core/bootstrap.dart';
import 'package:flutter_starter_kit/core/config/app_config.dart';
import 'package:flutter_starter_kit/core/remote_config/feature_flag.dart';
import 'package:flutter_test/flutter_test.dart';

/// [source] 에서 `//` 주석 줄을 뺀 코드 줄만 남긴다.
String _codeLines(String source) => source
    .split('\n')
    .where((line) => !line.trimLeft().startsWith('//'))
    .join('\n');

void main() {
  group('bootstrap Remote Config 통합 (D-24, D-25)', () {
    test('AppConfig.authProviders 가 6 providerId 모두 포함한다 (setDefaults 입력)', () {
      final map = AppConfig.authProviders;
      expect(map.keys.toSet(), kAllProviderIds.toSet());
    });

    test('setDefaults 키가 rcKeyForProvider 헬퍼와 정합한다 (D-28)', () {
      // bootstrap.dart 의 for-comprehension 미러 — 키 prefix 회귀 가드.
      // RC 매개변수 키 정책 (`[A-Za-z_][A-Za-z0-9_]*`) 회귀 가드 포함.
      final defaults = <String, Object>{
        for (final entry in AppConfig.authProviders.entries)
          rcKeyForProvider(entry.key): entry.value,
      };
      expect(defaults.length, kAllProviderIds.length);
      final rcKeyPattern = RegExp(r'^[A-Za-z_][A-Za-z0-9_]*$');
      for (final id in kAllProviderIds) {
        final key = rcKeyForProvider(id);
        expect(
          defaults.containsKey(key),
          isTrue,
          reason: 'missing default key for $id',
        );
        expect(
          rcKeyPattern.hasMatch(key),
          isTrue,
          reason: 'RC 매개변수 키 정책 위반 ($key) — 점/대시 등 금지',
        );
      }
      // 핵심 회귀 가드 (D-28): 도메인 ProviderId 가 slug 형식이므로 헬퍼는
      // 단순 prefix 결합만 수행해야 한다. Phase 11-04 hotfix 에서 OAuth URI
      // 형식 (`'google.com'` 등) 을 slug (`'google'`) 로 정규화함.
      expect(rcKeyForProvider('google'), 'auth_provider_google_enabled');
      expect(rcKeyForProvider('apple'), 'auth_provider_apple_enabled');
      expect(rcKeyForProvider('facebook'), 'auth_provider_facebook_enabled');
      expect(rcKeyForProvider('kakao'), 'auth_provider_kakao_enabled');
      // Phase 13 — see ROADMAP.md (Naver Custom Token).
      expect(rcKeyForProvider('naver'), 'auth_provider_naver_enabled');
    });

    test(
      'bootstrap.dart 의 RC 코드 블록이 try / on Object catch 로 D-25 폴백 의무를 표현한다',
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
      },
    );

    test('RC fetch 주기: dev=0, 그 외=12h (D-23, WR-07 hotfix)', () {
      final source = File('lib/core/bootstrap.dart').readAsStringSync();
      // WR-07 hotfix 후: hardcoded `flavor == 'dev'` 가 아닌
      // [AppConfig.isDev] 단일 진실원 사용 — silent fallback 차단.
      expect(
        source.contains('AppConfig.isDev'),
        isTrue,
        reason: 'D-23: bootstrap 은 AppConfig.isDev 헬퍼로 flavor 분기',
      );
      expect(source.contains('Duration.zero'), isTrue);
      expect(source.contains('Duration(hours: 12)'), isTrue);
    });

    test(
      'T-17-RC-06 setDefaults 맵 = provider kill switch + FeatureFlag 기본값 합산 (D-11)',
      () {
        final code = _codeLines(
          File('lib/core/bootstrap.dart').readAsStringSync(),
        );
        // 소스 계약 — 기존 provider 항목 1 · FeatureFlag 합산 1 · fetch 1.
        expect(
          RegExp(
            r'rcKeyForProvider\(entry\.key\):\s*entry\.value',
          ).allMatches(code).length,
          1,
        );
        expect(
          RegExp(
            r'for \(final flag in FeatureFlag\.values\)\s*flag\.key:\s*flag\.defaultValue',
          ).allMatches(code).length,
          1,
        );
        expect('fetchAndActivate()'.allMatches(code).length, 1);
        expect(
          RegExp(
            r'setDefaults\(\s*buildRemoteConfigDefaults\(\)\s*\)',
          ).hasMatch(code),
          isTrue,
          reason: 'RC 블록의 setDefaults 가 합산 맵을 쓴다',
        );

        // 동작 — 기존 키 · 값 그대로 + 새 4키.
        final defaults = buildRemoteConfigDefaults();
        for (final entry in AppConfig.authProviders.entries) {
          expect(defaults[rcKeyForProvider(entry.key)], entry.value);
        }
        for (final flag in FeatureFlag.values) {
          expect(defaults[flag.key], flag.defaultValue);
        }
        expect(
          defaults.length,
          AppConfig.authProviders.length + FeatureFlag.values.length,
        );

        // RC 템플릿 파일은 만들지 않는다 (D-11).
        expect(File('remoteconfig.template.json').existsSync(), isFalse);
      },
    );
  });
}
