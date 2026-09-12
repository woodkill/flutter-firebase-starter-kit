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
  });
}
