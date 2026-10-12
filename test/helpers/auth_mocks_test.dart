// buildAuthRepository 시그니처 계약.
//
// AuthRepository 생성자에 인자가 늘거나 바뀌면 이 파일과 auth_mocks.dart
// 두 곳만 깨진다 — 생성자를 부르는 다른 테스트는 헬퍼를 거치므로 그대로다.

import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_starter_kit/core/config/app_config.dart';
import 'package:flutter_starter_kit/core/crashlytics/crashlytics_service.dart';
import 'package:flutter_starter_kit/features/auth/data/auth_repository.dart';

import 'auth_mocks.dart';

void main() {
  group('buildAuthRepository', () {
    test('T-18-HELPER-01: 인자 없이 부르면 AuthRepository 를 만든다', () {
      expect(buildAuthRepository(), isA<AuthRepository>());
    });

    test('T-18-HELPER-02: 이름 인자 17개를 모두 넘겨도 AuthRepository 를 만든다', () {
      final fixedNow = DateTime.utc(2026);

      final repository = buildAuthRepository(
        auth: MockFirebaseAuth(),
        googleSignIn: MockGoogleSignIn(),
        facebookAuth: MockFacebookAuth(),
        socialLinkInProgress: MockSocialLinkInProgress(),
        kakaoSdkClient: MockKakaoSdkClient(),
        functions: MockFirebaseFunctions(),
        naverSdkClient: MockNaverSdkClient(),
        lineSdkClient: MockLineSdkClient(),
        onResetOnboarding: () async {},
        now: () => fixedNow,
        readTermsAcceptanceSnapshot: () => null,
        recordSignUpMethod: (_, _) async {},
        crashlytics: const CrashlyticsService(null, isEnabled: false),
        onSignOutCleanup: () async {},
        staticProviders: <String, bool>{},
        emailDeliveryMode: EmailDeliveryMode.firebase,
        readLanguageCode: () => 'ko',
      );

      expect(repository, isA<AuthRepository>());
    });
  });
}
