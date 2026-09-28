// ignore_for_file: lines_longer_than_80_chars
//
// Phase 16.10 plan 05 Task 2 — Google 재로그인 끊기 step.
//
//   G1: 연결 계정 · 탈퇴 — authenticate → reauthenticate → disconnect 순서 → Done
//   G2: 해제(reloginForFreshness: false) — reauthenticate 0 · disconnect 1 → Done
//   G3: 연결 안 된 계정 → IdentityMismatch · reauthenticate 0 · disconnect 0 (D-08)
//   G4: GoogleSignInException(canceled) → Cancelled · disconnect 0 (D-11)
//   G5: reauthenticate 가 user-mismatch → IdentityMismatch · disconnect 0
//   G6: idToken null → Failed(ServiceUnavailable) · disconnect 0
//   G7: disconnect 던짐 → Failed(ServiceUnavailable)
//   G8: 로그인 사용자 부재 · 익명 → Failed(UnknownException) · authenticate 0

import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:mocktail/mocktail.dart';

import 'package:flutter_starter_kit/core/auth/provider_id.dart';
import 'package:flutter_starter_kit/core/auth/strategies/google_auth_strategy.dart';
import 'package:flutter_starter_kit/core/error/app_exception.dart';
import 'package:flutter_starter_kit/features/auth/data/line_sdk_client.dart';
import 'package:flutter_starter_kit/features/auth/data/naver_sdk_client.dart';
import 'package:flutter_starter_kit/features/settings/data/disconnect/disconnect_step.dart';
import 'package:flutter_starter_kit/features/settings/data/disconnect/disconnect_steps.dart';
import 'package:flutter_starter_kit/features/settings/data/disconnect/google_disconnect_step.dart';

class _MockFirebaseAuth extends Mock implements fb.FirebaseAuth {}

class _MockFbUser extends Mock implements fb.User {}

class _MockUserInfo extends Mock implements fb.UserInfo {}

class _MockUserCredential extends Mock implements fb.UserCredential {}

class _MockGoogleSignIn extends Mock implements GoogleSignIn {}

class _MockGoogleSignInAccount extends Mock implements GoogleSignInAccount {}

class _MockGoogleSignInAuthentication extends Mock
    implements GoogleSignInAuthentication {}

class _MockFirebaseFunctions extends Mock implements FirebaseFunctions {}

class _MockLineSdkClient extends Mock implements LineSdkClient {}

class _MockNaverSdkClient extends Mock implements NaverSdkClient {}

class _FakeAuthCredential extends Fake implements fb.AuthCredential {}

const String _linkedGoogleSub = 'google-sub-of-U';
const GoogleDisconnectStep _step = GoogleDisconnectStep();

void main() {
  late _MockFirebaseAuth mockAuth;
  late _MockFbUser mockUser;
  late _MockGoogleSignIn mockGoogleSignIn;
  late _MockGoogleSignInAuthentication mockGoogleAuth;
  late DisconnectDeps deps;

  setUpAll(() {
    registerFallbackValue(_FakeAuthCredential());
  });

  setUp(() {
    mockAuth = _MockFirebaseAuth();
    mockUser = _MockFbUser();
    mockGoogleSignIn = _MockGoogleSignIn();
    mockGoogleAuth = _MockGoogleSignInAuthentication();

    final linkedInfo = _MockUserInfo();
    when(() => linkedInfo.providerId).thenReturn('google.com');
    when(() => linkedInfo.uid).thenReturn(_linkedGoogleSub);
    when(() => mockAuth.currentUser).thenReturn(mockUser);
    when(() => mockUser.isAnonymous).thenReturn(false);
    when(() => mockUser.providerData).thenReturn(<fb.UserInfo>[linkedInfo]);
    when(
      () => mockUser.reauthenticateWithCredential(any()),
    ).thenAnswer((_) async => _MockUserCredential());
    when(() => mockGoogleSignIn.disconnect()).thenAnswer((_) async {});
    when(() => mockGoogleAuth.idToken).thenReturn('google-id-token');

    deps = DisconnectDeps(
      auth: mockAuth,
      functions: _MockFirebaseFunctions(),
      googleSignIn: mockGoogleSignIn,
      lineSdkClient: _MockLineSdkClient(),
      naverSdkClient: _MockNaverSdkClient(),
      platform: TargetPlatform.android,
    );
  });

  void stubSelectedAccount(String accountId) {
    final account = _MockGoogleSignInAccount();
    when(() => account.id).thenReturn(accountId);
    when(() => account.authentication).thenReturn(mockGoogleAuth);
    when(
      () => mockGoogleSignIn.authenticate(),
    ).thenAnswer((_) async => account);
  }

  AppException failureOf(DisconnectOutcome outcome) {
    expect(outcome, isA<DisconnectFailed>());
    return (outcome as DisconnectFailed).exception;
  }

  test(
    'G0: 재로그인 행 계약 — provider google · kind relogin · GoogleAuthStrategy · 레지스트리 등록',
    () {
      expect(_step.provider, AccountProvider.google);
      expect(_step.kind, DisconnectKind.relogin);
      expect(_step.signInStrategy, isA<GoogleAuthStrategy>());
      expect(
        disconnectStepFor(kDisconnectSteps, AccountProvider.google),
        isA<GoogleDisconnectStep>(),
      );
    },
  );

  test(
    'G1: 연결 계정 · 탈퇴 — authenticate → reauthenticate → disconnect 순서 → Done',
    () async {
      stubSelectedAccount(_linkedGoogleSub);
      // verifyInOrder 가 호출을 verified 로 표시하므로 인자는 stub 에서 잡는다.
      fb.AuthCredential? reauthCredential;
      when(() => mockUser.reauthenticateWithCredential(any())).thenAnswer((
        invocation,
      ) async {
        reauthCredential =
            invocation.positionalArguments.first as fb.AuthCredential;
        return _MockUserCredential();
      });

      final outcome = await _step.run(deps, reloginForFreshness: true);

      expect(outcome, isA<DisconnectDone>());
      verifyInOrder([
        () => mockGoogleSignIn.authenticate(),
        () => mockUser.reauthenticateWithCredential(any()),
        () => mockGoogleSignIn.disconnect(),
      ]);
      expect(reauthCredential, isA<fb.OAuthCredential>());
      expect(reauthCredential!.providerId, 'google.com');
      expect(
        (reauthCredential! as fb.OAuthCredential).idToken,
        'google-id-token',
      );
    },
  );

  test(
    'G2: 해제(reloginForFreshness: false) — reauthenticate 0 · disconnect 1 → Done',
    () async {
      stubSelectedAccount(_linkedGoogleSub);

      final outcome = await _step.run(deps, reloginForFreshness: false);

      expect(outcome, isA<DisconnectDone>());
      verifyNever(() => mockUser.reauthenticateWithCredential(any()));
      verify(() => mockGoogleSignIn.disconnect()).called(1);
    },
  );

  test(
    'G3: 연결 안 된 Google 계정 → IdentityMismatch · reauthenticate 0 · disconnect 0',
    () async {
      stubSelectedAccount('google-sub-of-someone-else');

      final outcome = await _step.run(deps, reloginForFreshness: true);

      expect(outcome, isA<DisconnectIdentityMismatch>());
      verifyNever(() => mockUser.reauthenticateWithCredential(any()));
      verifyNever(() => mockGoogleSignIn.disconnect());
    },
  );

  test('G4: 계정 선택 취소(canceled) → Cancelled · disconnect 0', () async {
    when(() => mockGoogleSignIn.authenticate()).thenThrow(
      const GoogleSignInException(code: GoogleSignInExceptionCode.canceled),
    );

    final outcome = await _step.run(deps, reloginForFreshness: true);

    expect(outcome, isA<DisconnectCancelled>());
    verifyNever(() => mockGoogleSignIn.disconnect());
  });

  test('G4: canceled 가 아닌 SDK 오류 → Failed(ServiceUnavailable)', () async {
    when(() => mockGoogleSignIn.authenticate()).thenThrow(
      const GoogleSignInException(
        code: GoogleSignInExceptionCode.providerConfigurationError,
      ),
    );

    final outcome = await _step.run(deps, reloginForFreshness: true);

    expect(failureOf(outcome), isA<ServiceUnavailable>());
    verifyNever(() => mockGoogleSignIn.disconnect());
  });

  test(
    'G5: reauthenticate 가 user-mismatch → IdentityMismatch · disconnect 0',
    () async {
      stubSelectedAccount(_linkedGoogleSub);
      when(
        () => mockUser.reauthenticateWithCredential(any()),
      ).thenThrow(fb.FirebaseAuthException(code: 'user-mismatch'));

      final outcome = await _step.run(deps, reloginForFreshness: true);

      expect(outcome, isA<DisconnectIdentityMismatch>());
      verifyNever(() => mockGoogleSignIn.disconnect());
    },
  );

  test(
    'G6: idToken null → Failed(ServiceUnavailable) · disconnect 0',
    () async {
      stubSelectedAccount(_linkedGoogleSub);
      when(() => mockGoogleAuth.idToken).thenReturn(null);

      final outcome = await _step.run(deps, reloginForFreshness: true);

      expect(failureOf(outcome), isA<ServiceUnavailable>());
      verifyNever(() => mockUser.reauthenticateWithCredential(any()));
      verifyNever(() => mockGoogleSignIn.disconnect());
    },
  );

  test('G7: disconnect 가 던짐 → Failed(ServiceUnavailable)', () async {
    stubSelectedAccount(_linkedGoogleSub);
    when(
      () => mockGoogleSignIn.disconnect(),
    ).thenThrow(StateError('revokeAccess failed'));

    final outcome = await _step.run(deps, reloginForFreshness: false);

    expect(failureOf(outcome), isA<ServiceUnavailable>());
  });

  test(
    'G8: 로그인 사용자 부재 · 익명 → Failed(UnknownException) · authenticate 0',
    () async {
      when(() => mockAuth.currentUser).thenReturn(null);
      expect(
        failureOf(await _step.run(deps, reloginForFreshness: true)),
        isA<UnknownException>(),
      );

      when(() => mockAuth.currentUser).thenReturn(mockUser);
      when(() => mockUser.isAnonymous).thenReturn(true);
      expect(
        failureOf(await _step.run(deps, reloginForFreshness: true)),
        isA<UnknownException>(),
      );

      verifyNever(() => mockGoogleSignIn.authenticate());
    },
  );
}
