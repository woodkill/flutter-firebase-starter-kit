import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_starter_kit/core/auth/provider_id.dart';
import 'package:flutter_starter_kit/core/auth/strategies/apple_auth_strategy.dart';

void main() {
  group('AppleAuthStrategy', () {
    const strategy = AppleAuthStrategy();

    test('providerId 는 kProviderIdApple 이다', () {
      expect(strategy.providerId, kProviderIdApple);
    });

    test('labelKey 는 authAppleSignIn 이다', () {
      expect(strategy.labelKey, 'authAppleSignIn');
    });

    test('iconAsset 는 apple 이다', () {
      expect(strategy.iconAsset, 'apple');
    });

    test('defaultPriorityFor 는 Phase 11 placeholder 0 을 반환한다', () {
      expect(strategy.defaultPriorityFor(const Locale('en')), 0);
      expect(strategy.defaultPriorityFor(const Locale('ko')), 0);
    });
  });
}
