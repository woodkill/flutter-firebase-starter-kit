// ignore_for_file: lines_longer_than_80_chars
//
// Phase 16.10 plan 05 Task 2 — Apple 재로그인 끊기 step (플랫폼 분기 revoke).
//
//   AP1: iOS — authorizationCode → revokeTokenWithAuthorizationCode 1 · revokeAccessToken 0 → Done
//   AP2: Android — credential.accessToken → revokeAccessToken 1 · revokeTokenWithAuthorizationCode 0 (C-09)
//   AP3: Android access token null → Failed(ServiceUnavailable) · revoke 0
//   AP4: iOS authorizationCode null → Failed(ServiceUnavailable) · revoke 0
//   AP5: user-mismatch → IdentityMismatch · revoke 0 (D-08)
//   AP6: user-not-found → IdentityMismatch · revoke 0
//   AP7: canceled · web-context-canceled → Cancelled · revoke 0 (D-11)
//   AP8: revokeAccessToken 이 FirebaseAuthException → Failed(ServiceUnavailable)
//   AP9: 해제 모드(reloginForFreshness: false)도 reauthenticateWithProvider 1 → Done

import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:mocktail/mocktail.dart';

import 'package:flutter_starter_kit/core/auth/provider_id.dart';
import 'package:flutter_starter_kit/core/auth/strategies/apple_auth_strategy.dart';
import 'package:flutter_starter_kit/core/error/app_exception.dart';
import 'package:flutter_starter_kit/features/settings/data/disconnect/apple_disconnect_step.dart';
import 'package:flutter_starter_kit/features/settings/data/disconnect/disconnect_step.dart';
import 'package:flutter_starter_kit/features/settings/data/disconnect/disconnect_steps.dart';

class _MockFirebaseAuth extends Mock implements fb.FirebaseAuth {}

class _MockFbUser extends Mock implements fb.User {}

class _MockUserCredential extends Mock implements fb.UserCredential {}

class _MockAdditionalUserInfo extends Mock implements fb.AdditionalUserInfo {}

class _MockAuthCredential extends Mock implements fb.AuthCredential {}

class _MockGoogleSignIn extends Mock implements GoogleSignIn {}

class _MockFirebaseFunctions extends Mock implements FirebaseFunctions {}

const AppleDisconnectStep _step = AppleDisconnectStep();

void main() {
  late _MockFirebaseAuth mockAuth;
  late _MockFbUser mockUser;
  late _MockUserCredential mockCredential;
  late _MockAdditionalUserInfo mockAdditionalInfo;
  late _MockAuthCredential mockAuthCredential;

  setUpAll(() {
    registerFallbackValue(fb.AppleAuthProvider());
  });

  setUp(() {
    mockAuth = _MockFirebaseAuth();
    mockUser = _MockFbUser();
    mockCredential = _MockUserCredential();
    mockAdditionalInfo = _MockAdditionalUserInfo();
    mockAuthCredential = _MockAuthCredential();

    when(() => mockAuth.currentUser).thenReturn(mockUser);
    when(() => mockUser.isAnonymous).thenReturn(false);
    when(
      () => mockUser.reauthenticateWithProvider(any()),
    ).thenAnswer((_) async => mockCredential);
    when(
      () => mockCredential.additionalUserInfo,
    ).thenReturn(mockAdditionalInfo);
    when(() => mockCredential.credential).thenReturn(mockAuthCredential);
    when(() => mockAdditionalInfo.authorizationCode).thenReturn('apple-code-1');
    when(() => mockAuthCredential.accessToken).thenReturn('apple-at-1');
    when(
      () => mockAuth.revokeTokenWithAuthorizationCode(any()),
    ).thenAnswer((_) async {});
    when(() => mockAuth.revokeAccessToken(any())).thenAnswer((_) async {});
  });

  DisconnectDeps depsFor(TargetPlatform platform) => DisconnectDeps(
    auth: mockAuth,
    functions: _MockFirebaseFunctions(),
    googleSignIn: _MockGoogleSignIn(),
    platform: platform,
    read: ProviderContainer.test().read,
  );

  void expectNoRevoke() {
    verifyNever(() => mockAuth.revokeTokenWithAuthorizationCode(any()));
    verifyNever(() => mockAuth.revokeAccessToken(any()));
  }

  AppException failureOf(DisconnectOutcome outcome) {
    expect(outcome, isA<DisconnectFailed>());
    return (outcome as DisconnectFailed).exception;
  }

  test(
    'AP0: 재로그인 행 계약 — provider apple · kind relogin · AppleAuthStrategy · 레지스트리 등록',
    () {
      expect(_step.provider, AccountProvider.apple);
      expect(_step.kind, DisconnectKind.relogin);
      expect(_step.signInStrategy, isA<AppleAuthStrategy>());
      expect(
        disconnectStepFor(kDisconnectSteps, AccountProvider.apple),
        isA<AppleDisconnectStep>(),
      );
    },
  );

  test(
    'AP1: iOS — authorizationCode 로 revokeTokenWithAuthorizationCode 1 · revokeAccessToken 0 → Done',
    () async {
      final outcome = await _step.run(
        depsFor(TargetPlatform.iOS),
        reloginForFreshness: true,
      );

      expect(outcome, isA<DisconnectDone>());
      final provider =
          verify(
                () => mockUser.reauthenticateWithProvider(captureAny()),
              ).captured.single
              as fb.AppleAuthProvider;
      expect(provider.scopes, containsAll(<String>['email', 'name']));
      verify(
        () => mockAuth.revokeTokenWithAuthorizationCode('apple-code-1'),
      ).called(1);
      verifyNever(() => mockAuth.revokeAccessToken(any()));
    },
  );

  test(
    'AP2: Android — accessToken 으로 revokeAccessToken 1 · revokeTokenWithAuthorizationCode 0 (가짜 성공 함정) → Done',
    () async {
      final outcome = await _step.run(
        depsFor(TargetPlatform.android),
        reloginForFreshness: true,
      );

      expect(outcome, isA<DisconnectDone>());
      verify(() => mockAuth.revokeAccessToken('apple-at-1')).called(1);
      verifyNever(() => mockAuth.revokeTokenWithAuthorizationCode(any()));
    },
  );

  test(
    'AP3: Android access token null · 빈 값 → Failed(ServiceUnavailable) · revoke 0',
    () async {
      for (final token in <String?>[null, '']) {
        when(() => mockAuthCredential.accessToken).thenReturn(token);

        final outcome = await _step.run(
          depsFor(TargetPlatform.android),
          reloginForFreshness: true,
        );

        expect(failureOf(outcome), isA<ServiceUnavailable>(), reason: '$token');
      }
      // credential 자체가 null 이어도 같다.
      when(() => mockCredential.credential).thenReturn(null);
      final outcome = await _step.run(
        depsFor(TargetPlatform.android),
        reloginForFreshness: true,
      );
      expect(failureOf(outcome), isA<ServiceUnavailable>());
      expectNoRevoke();
    },
  );

  test(
    'AP4: iOS authorizationCode null → Failed(ServiceUnavailable) · revoke 0',
    () async {
      when(() => mockAdditionalInfo.authorizationCode).thenReturn(null);

      final outcome = await _step.run(
        depsFor(TargetPlatform.iOS),
        reloginForFreshness: true,
      );

      expect(failureOf(outcome), isA<ServiceUnavailable>());
      expectNoRevoke();
    },
  );

  test('AP5: 재인증 user-mismatch → IdentityMismatch · revoke 0', () async {
    when(
      () => mockUser.reauthenticateWithProvider(any()),
    ).thenThrow(fb.FirebaseAuthException(code: 'user-mismatch'));

    final outcome = await _step.run(
      depsFor(TargetPlatform.android),
      reloginForFreshness: true,
    );

    expect(outcome, isA<DisconnectIdentityMismatch>());
    expectNoRevoke();
  });

  test('AP6: 재인증 user-not-found → IdentityMismatch · revoke 0', () async {
    when(
      () => mockUser.reauthenticateWithProvider(any()),
    ).thenThrow(fb.FirebaseAuthException(code: 'user-not-found'));

    final outcome = await _step.run(
      depsFor(TargetPlatform.iOS),
      reloginForFreshness: true,
    );

    expect(outcome, isA<DisconnectIdentityMismatch>());
    expectNoRevoke();
  });

  test('AP7: canceled · web-context-canceled → Cancelled · revoke 0', () async {
    for (final code in <String>['canceled', 'web-context-canceled']) {
      when(
        () => mockUser.reauthenticateWithProvider(any()),
      ).thenThrow(fb.FirebaseAuthException(code: code));

      final outcome = await _step.run(
        depsFor(TargetPlatform.android),
        reloginForFreshness: true,
      );

      expect(outcome, isA<DisconnectCancelled>(), reason: code);
    }
    expectNoRevoke();
  });

  test(
    'AP8: revokeAccessToken 이 FirebaseAuthException → Failed(ServiceUnavailable)',
    () async {
      when(
        () => mockAuth.revokeAccessToken(any()),
      ).thenThrow(fb.FirebaseAuthException(code: 'invalid-credential'));

      final outcome = await _step.run(
        depsFor(TargetPlatform.android),
        reloginForFreshness: true,
      );

      expect(failureOf(outcome), isA<ServiceUnavailable>());
    },
  );

  test(
    'AP9: 해제 모드(reloginForFreshness: false)도 reauthenticateWithProvider 1 → Done',
    () async {
      final outcome = await _step.run(
        depsFor(TargetPlatform.android),
        reloginForFreshness: false,
      );

      expect(outcome, isA<DisconnectDone>());
      verify(() => mockUser.reauthenticateWithProvider(any())).called(1);
      verify(() => mockAuth.revokeAccessToken('apple-at-1')).called(1);
    },
  );

  test('AP9: 로그인 사용자 부재 → Failed(UnknownException) · 재인증 0', () async {
    when(() => mockAuth.currentUser).thenReturn(null);

    final outcome = await _step.run(
      depsFor(TargetPlatform.iOS),
      reloginForFreshness: false,
    );

    expect(failureOf(outcome), isA<UnknownException>());
    verifyNever(() => mockUser.reauthenticateWithProvider(any()));
  });
}
