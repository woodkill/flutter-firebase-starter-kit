import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_starter_kit/core/auth/provider_id.dart';
import 'package:flutter_starter_kit/core/config/app_config.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AppConfig.authProviders 평탄화 (Pitfall 2)', () {
    test('미주입 키는 false 안전 default 를 반환한다 (D-21)', () {
      // dart-define-from-file 미적용 상태 (test 환경) → 모두 false
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
  });

  group('config JSON 무결성 (D-19, Pitfall 2)', () {
    for (final flavor in const <String>['dev', 'stg', 'prod']) {
      test('$flavor.json 의 가독성 authProviders 객체와 평탄 키가 일치한다', () {
        final raw = File('config/$flavor.json').readAsStringSync();
        final json = jsonDecode(raw) as Map<String, dynamic>;

        // 가독성 객체 검증
        expect(json.containsKey('authProviders'), isTrue);
        final readable = json['authProviders'] as Map<String, dynamic>;
        expect(readable.keys.toSet(), kAllProviderIds.toSet());

        // 평탄 키 검증 + 가독성 객체와 동일 값
        for (final id in kAllProviderIds) {
          final flatKey = 'authProvider_${id}_enabled';
          expect(
            json.containsKey(flatKey),
            isTrue,
            reason: '$flavor.json missing $flatKey',
          );
          expect(
            json[flatKey],
            readable[id],
            reason: '$flavor.json: $flatKey != authProviders.$id',
          );
        }
      });

      test('$flavor.json 의 D-19 기본값 (google/apple/facebook=true, 나머지=false)',
          () {
        final raw = File('config/$flavor.json').readAsStringSync();
        final json = jsonDecode(raw) as Map<String, dynamic>;
        expect(json['authProvider_${kProviderIdGoogle}_enabled'], true);
        expect(json['authProvider_${kProviderIdApple}_enabled'], true);
        expect(json['authProvider_${kProviderIdFacebook}_enabled'], true);
        for (final id in const <String>[
          kProviderIdKakao,
          kProviderIdNaver,
          kProviderIdLine,
          kProviderIdYahooJp,
          kProviderIdWeChat,
        ]) {
          expect(
            json['authProvider_${id}_enabled'],
            false,
            reason: '$flavor.json: $id should be false (Phase 12-16)',
          );
        }
      });
    }
  });
}
