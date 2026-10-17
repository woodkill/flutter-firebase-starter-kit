// buildAuthRepository 시그니처 · 전달 계약.
//
// AuthRepository 생성자에 인자가 늘거나 바뀌면 이 파일과 auth_mocks.dart
// 두 곳만 깨진다 — 생성자를 부르는 다른 테스트는 헬퍼를 거치므로 그대로다.
// T-18-HELPER-03 은 로그아웃 경로로 관측되는 인자가 생성자에 실제로 닿는지
// 직접 잠근다. 나머지 인자의 전달은 그 인자를 쓰는 suite 가 잠근다.

import 'package:flutter_starter_kit/core/auth/provider_id.dart';
import 'package:flutter_starter_kit/core/config/app_config.dart';
import 'package:flutter_starter_kit/core/crashlytics/crashlytics_service.dart';
import 'package:flutter_starter_kit/features/auth/data/auth_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

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
        onSignOutCleanup: () async {},
        staticProviders: <String, bool>{},
        emailDeliveryMode: EmailDeliveryMode.firebase,
        readLanguageCode: () => 'ko',
      );

      expect(repository, isA<AuthRepository>());
    });

    test('T-18-HELPER-03: 로그아웃 경로의 협력 객체 · 콜백 · staticProviders 가 '
        '생성자에 전달된다', () async {
      final auth = MockFirebaseAuth();
      final googleSignIn = MockGoogleSignIn();
      when(auth.signOut).thenAnswer((_) async {});
      when(googleSignIn.signOut).thenAnswer((_) async {});
      var cleanupCalls = 0;
      var resetCalls = 0;

      // 테스트 빌드의 기본 정적 CSV 는 비어 있어 모든 provider 가 꺼져 있다 —
      // Google 을 켠 맵이 전달되지 않으면 Google 로그아웃은 0회가 된다.
      final repository = buildAuthRepository(
        auth: auth,
        googleSignIn: googleSignIn,
        onResetOnboarding: () async => resetCalls++,
        onSignOutCleanup: () async => cleanupCalls++,
        staticProviders: <String, bool>{
          for (final id in kAllProviderIds) id: id == kProviderIdGoogle,
        },
      );

      await repository.signOutAndResetOnboarding();

      expect(cleanupCalls, 1);
      expect(resetCalls, 1);
      verify(googleSignIn.signOut).called(1);
      verify(auth.signOut).called(1);
    });
  });
}
