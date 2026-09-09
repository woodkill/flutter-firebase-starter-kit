import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_starter_kit/core/auth/provider_id.dart';
import 'package:flutter_starter_kit/core/config/app_config.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AppConfig.authProviders 단일 CSV 진실 (Pitfall 2, T-11-CONST-01)', () {
    test('미주입 키는 false 안전 default 를 반환한다 (D-21)', () {
      // dart-define-from-file 미적용 상태 (test 환경) → CSV 빈 문자열 →
      // 모든 8 슬러그 disabled.
      final map = AppConfig.authProviders;
      expect(map.length, kAllProviderIds.length);
      for (final id in kAllProviderIds) {
        expect(map.containsKey(id), isTrue, reason: 'missing $id');
        expect(map[id], isFalse, reason: '$id should default to false');
      }
    });

    test('staticAuthProvidersProvider 가 동일 맵을 반환한다', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final mapFromProvider = container.read(staticAuthProvidersProvider);
      expect(mapFromProvider, AppConfig.authProviders);
    });

    test('AppConfig.authProviders 키 셋이 kAllProviderIds 와 정합한다', () {
      // CSV 토큰이 어떤 값이든 키 셋은 항상 kAllProviderIds 와 동일해야 한다 —
      // 미등록 슬러그는 false 로, 미주입 슬러그도 false 로 노출 (D-21).
      expect(AppConfig.authProviders.keys.toSet(), kAllProviderIds.toSet());
      expect(AppConfig.authProviders.length, kAllProviderIds.length);
    });

    test('isEnabledStatically 가 authProviders[id] 와 동등하다', () {
      for (final id in kAllProviderIds) {
        expect(
          AppConfig.isEnabledStatically(id),
          AppConfig.authProviders[id],
          reason: '$id helper 와 map 결과 불일치',
        );
      }
      // 미등록 슬러그는 false (D-21).
      expect(AppConfig.isEnabledStatically('nonexistent'), isFalse);
    });
  });

  group('config JSON 무결성 (D-19, T-11-CONST-01)', () {
    for (final flavor in const <String>['dev', 'stg', 'prod']) {
      test('$flavor.json 의 enabledAuthProviders CSV 가 형식 정합한다', () {
        // CR-02 (Phase 13 review): config/{flavor}.json 은 .gitignore 대상.
        // fresh clone / CI 에서 `cp *.example.json *.json` 미실행 시
        // FileSystemException 으로 entire suite 가 fail 되는 것을 방지하기
        // 위해 missing 시 graceful skip. 본 contract 는 사용자가 실제 키를
        // 주입한 dev 환경에서만 검증되어야 하므로 skip 가 안전.
        final file = File('config/$flavor.json');
        if (!file.existsSync()) {
          markTestSkipped(
            'config/$flavor.json missing — `cp config/$flavor.example.json '
            'config/$flavor.json` 실행 후 재시도. fresh clone / CI 에서는 정상.',
          );
          return;
        }
        final raw = file.readAsStringSync();
        final json = jsonDecode(raw) as Map<String, dynamic>;

        // 단일 키 존재.
        expect(
          json.containsKey('enabledAuthProviders'),
          isTrue,
          reason: '$flavor.json missing enabledAuthProviders',
        );
        expect(
          json['enabledAuthProviders'],
          isA<String>(),
          reason: '$flavor.json: enabledAuthProviders must be String',
        );

        // CSV 토큰 모두 kAllProviderIds 멤버여야 한다 (오타 방지).
        final csv = json['enabledAuthProviders'] as String;
        final tokens = csv
            .split(',')
            .map((s) => s.trim())
            .where((s) => s.isNotEmpty)
            .toList();
        for (final token in tokens) {
          expect(
            kAllProviderIds.contains(token),
            isTrue,
            reason:
                '$flavor.json: enabledAuthProviders 의 "$token" 이 kAllProviderIds 에 없음',
          );
        }

        // dart-define 키 자체도 식별자 정책 (`[A-Za-z_][A-Za-z0-9_]*`) 정합.
        const flatKey = 'enabledAuthProviders';
        final dartDefinePattern = RegExp(r'^[A-Za-z_][A-Za-z0-9_]*$');
        expect(
          dartDefinePattern.hasMatch(flatKey),
          isTrue,
          reason: 'dart-define 키 정책 위반',
        );
      });

      test('$flavor.json 의 기본값 (google/apple/facebook/kakao 활성, '
          'flavor 별 Phase 13~16 Custom Token 정책)', () {
        // CR-02 (Phase 13 review): missing 시 graceful skip — 위 contract
        // test 와 동일 정책.
        final file = File('config/$flavor.json');
        if (!file.existsSync()) {
          markTestSkipped(
            'config/$flavor.json missing — `cp config/$flavor.example.json '
            'config/$flavor.json` 실행 후 재시도.',
          );
          return;
        }
        final raw = file.readAsStringSync();
        final json = jsonDecode(raw) as Map<String, dynamic>;
        final csv = (json['enabledAuthProviders'] as String? ?? '');
        final enabled = csv
            .split(',')
            .map((s) => s.trim())
            .where((s) => s.isNotEmpty)
            .toSet();

        // 활성: Google / Apple / Facebook (Phase 7~9) + Kakao (Phase 12 D-19).
        expect(enabled.contains(kProviderIdGoogle), isTrue);
        expect(enabled.contains(kProviderIdApple), isTrue);
        expect(enabled.contains(kProviderIdFacebook), isTrue);
        expect(enabled.contains(kProviderIdKakao), isTrue);

        // dev 는 Phase 진행에 따라 Custom Token 점진 활성화 (Phase 13:
        // naver, Phase 14: line, Phase 15: yahoojp).
        // stg/prod 는 Starter Kit 정책상 placeholder — Phase 13~16 모두 비활성.
        if (flavor == 'dev') {
          expect(
            enabled.contains(kProviderIdNaver),
            isTrue,
            reason: 'dev.json: naver should be enabled (Phase 13)',
          );
          expect(
            enabled.contains(kProviderIdLine),
            isTrue,
            reason: 'dev.json: line should be enabled (Phase 14)',
          );
          expect(
            enabled.contains(kProviderIdYahooJp),
            isTrue,
            reason: 'dev.json: yahoojp should be enabled (Phase 15)',
          );
        } else {
          for (final id in const <String>[
            kProviderIdNaver,
            kProviderIdLine,
            kProviderIdYahooJp,
          ]) {
            expect(
              enabled.contains(id),
              isFalse,
              reason:
                  '$flavor.json: $id should be disabled (placeholder policy)',
            );
          }
        }
      });
    }
  });

  group('Phase 12 — kakaoNativeAppKey (D-20)', () {
    test('AppConfig.kakaoNativeAppKey 는 dart-define 미주입 시 빈 문자열', () {
      // 테스트 환경에서는 --dart-define-from-file 미적용 → 빈 문자열 default.
      expect(AppConfig.kakaoNativeAppKey, isA<String>());
      expect(AppConfig.kakaoNativeAppKey, isEmpty);
    });

    for (final flavor in const <String>['dev', 'stg', 'prod']) {
      test('$flavor.json 에 kakaoNativeAppKey 키가 존재한다', () {
        // CR-02 (Phase 13 review): missing 시 graceful skip — fresh clone / CI
        // 에서는 정상.
        final file = File('config/$flavor.json');
        if (!file.existsSync()) {
          markTestSkipped(
            'config/$flavor.json missing — `cp config/$flavor.example.json '
            'config/$flavor.json` 실행 후 재시도.',
          );
          return;
        }
        final raw = file.readAsStringSync();
        final json = jsonDecode(raw) as Map<String, dynamic>;
        expect(
          json.containsKey('kakaoNativeAppKey'),
          isTrue,
          reason: '$flavor.json missing kakaoNativeAppKey',
        );
        expect(
          json['kakaoNativeAppKey'],
          isA<String>(),
          reason: '$flavor.json: kakaoNativeAppKey must be String',
        );
        // placeholder 또는 실 키 — 빈 문자열은 D-20 에서 silent fallback 회피.
        expect(
          (json['kakaoNativeAppKey'] as String).isNotEmpty,
          isTrue,
          reason: '$flavor.json: kakaoNativeAppKey 가 빈 문자열이면 silent failure',
        );
      });
    }
  });
}
