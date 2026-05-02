import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_starter_kit/core/auth/provider_id.dart';
import 'package:flutter_starter_kit/core/auth/strategies/facebook_auth_strategy.dart';

void main() {
  group('FacebookAuthStrategy', () {
    const strategy = FacebookAuthStrategy();

    test('providerId 는 kProviderIdFacebook 이다', () {
      expect(strategy.providerId, kProviderIdFacebook);
    });

    test('labelKey 는 authFacebookSignIn 이다', () {
      expect(strategy.labelKey, 'authFacebookSignIn');
    });

    test('iconAsset 는 facebook 이다', () {
      expect(strategy.iconAsset, 'facebook');
    });

    test('defaultPriorityFor 는 Phase 11 placeholder 0 을 반환한다', () {
      expect(strategy.defaultPriorityFor(const Locale('en')), 0);
      expect(strategy.defaultPriorityFor(const Locale('ko')), 0);
    });
  });
}
