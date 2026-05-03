import 'dart:ui';

import 'package:firebase_remote_config/firebase_remote_config.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:flutter_starter_kit/core/auth/auth_strategies_registry.dart';
import 'package:flutter_starter_kit/core/auth/provider_id.dart';
import 'package:flutter_starter_kit/core/config/app_config.dart';
import 'package:flutter_starter_kit/core/providers/firebase_providers.dart';

class _MockRC extends Mock implements FirebaseRemoteConfig {}

class _MockRCValue extends Mock implements RemoteConfigValue {}

void main() {
  late _MockRC rc;
  const locale = Locale('en');

  setUp(() {
    rc = _MockRC();
  });

  /// RC stub helper.
  ///
  /// `keys[k] == null` 인 항목은 `getAll()` 에서 누락 (RC 키 없음 시뮬레이션).
  /// 그 외 항목은 `getAll()` 에 포함되며, `getBool(k)` 는 해당 boolean 값.
  void stubRc(Map<String, bool?> keys) {
    final all = <String, RemoteConfigValue>{};
    for (final entry in keys.entries) {
      if (entry.value == null) continue; // 키 없음 (default fallback 경로)
      all[entry.key] = _MockRCValue();
    }
    when(rc.getAll).thenReturn(all);
    for (final entry in keys.entries) {
      when(() => rc.getBool(entry.key)).thenReturn(entry.value ?? false);
    }
  }

  ProviderContainer makeContainer({
    required Map<String, bool> staticMap,
    required Map<String, bool?> rcMap,
  }) {
    stubRc(rcMap);
    final container = ProviderContainer(
      overrides: [
        staticAuthProvidersProvider.overrideWithValue(staticMap),
        firebaseRemoteConfigProvider.overrideWithValue(rc),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  group('activeStrategies overlay 합산 (D-26 truth table — Pitfall 5)', () {
    test('case 1: 정적T + RC T → enabled', () {
      final c = makeContainer(
        staticMap: {
          kProviderIdGoogle: true,
          kProviderIdApple: false,
          kProviderIdFacebook: false,
        },
        rcMap: {'auth_provider_google_enabled': true},
      );
      final result = c.read(activeStrategiesProvider(locale));
      expect(result.map((s) => s.providerId), [kProviderIdGoogle]);
    });

    test('case 2: 정적T + RC F → disabled (kill switch)', () {
      final c = makeContainer(
        staticMap: {
          kProviderIdGoogle: true,
          kProviderIdApple: false,
          kProviderIdFacebook: false,
        },
        rcMap: {'auth_provider_google_enabled': false},
      );
      final result = c.read(activeStrategiesProvider(locale));
      expect(result.map((s) => s.providerId), isEmpty);
    });

    test(
      'case 3: 정적F + RC T → disabled (정적 false 절대 우위, D-26 핵심)',
      () {
        final c = makeContainer(
          staticMap: {
            kProviderIdGoogle: false,
            kProviderIdApple: false,
            kProviderIdFacebook: false,
          },
          rcMap: {'auth_provider_google_enabled': true},
        );
        final result = c.read(activeStrategiesProvider(locale));
        expect(
          result.map((s) => s.providerId),
          isEmpty,
          reason: '정적 false 는 RC true 로도 켤 수 없음 (D-26)',
        );
      },
    );

    test('case 4: 정적F + RC 키 없음 → disabled', () {
      final c = makeContainer(
        staticMap: {
          kProviderIdGoogle: false,
          kProviderIdApple: false,
          kProviderIdFacebook: false,
        },
        rcMap: {'auth_provider_google_enabled': null},
      );
      final result = c.read(activeStrategiesProvider(locale));
      expect(result.map((s) => s.providerId), isEmpty);
    });
  });

  group('RC 키 미존재 fallback (D-25, T-11-RC-03)', () {
    test('정적 true + RC 키 없음 → enabled (default true)', () {
      final c = makeContainer(
        staticMap: {
          kProviderIdGoogle: true,
          kProviderIdApple: false,
          kProviderIdFacebook: false,
        },
        rcMap: {'auth_provider_google_enabled': null}, // 키 없음 시뮬레이션
      );
      final result = c.read(activeStrategiesProvider(locale));
      expect(result.map((s) => s.providerId), [kProviderIdGoogle]);
    });
  });

  group('등록 순서 보존 (D-13 — Phase 16.1 정렬 placeholder)', () {
    test('staticMap 모두 true + RC 모두 true → Google → Apple → Facebook 순', () {
      final c = makeContainer(
        staticMap: {
          kProviderIdGoogle: true,
          kProviderIdApple: true,
          kProviderIdFacebook: true,
        },
        rcMap: {
          'auth_provider_google_enabled': true,
          'auth_provider_apple_enabled': true,
          'auth_provider_facebook_enabled': true,
        },
      );
      final result = c.read(activeStrategiesProvider(locale));
      expect(result.map((s) => s.providerId), [
        kProviderIdGoogle,
        kProviderIdApple,
        kProviderIdFacebook,
      ]);
    });
  });

  group('staticMap 미주입 안전 default (D-21)', () {
    test('Strategy 의 providerId 가 staticMap 에 없으면 disabled', () {
      final c = makeContainer(
        staticMap: <String, bool>{}, // 모든 키 미주입
        rcMap: {},
      );
      final result = c.read(activeStrategiesProvider(locale));
      expect(result, isEmpty);
    });
  });
}
