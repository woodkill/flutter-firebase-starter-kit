import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_starter_kit/core/auth/provider_id.dart';
import 'package:flutter_starter_kit/core/auth/strategies/google_auth_strategy.dart';

void main() {
  group('GoogleAuthStrategy', () {
    const strategy = GoogleAuthStrategy();

    test('providerId 는 kProviderIdGoogle 이다', () {
      expect(strategy.providerId, kProviderIdGoogle);
    });

    test('labelKey 는 authGoogleSignIn 이다', () {
      expect(strategy.labelKey, 'authGoogleSignIn');
    });
  });
}
