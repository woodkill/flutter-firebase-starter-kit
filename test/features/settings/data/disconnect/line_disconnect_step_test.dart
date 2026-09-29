// ignore_for_file: lines_longer_than_80_chars
//
// Phase 16.10 plan 06 — LINE 재로그인 끊기 step.
//
//   LN1: 탈퇴 — payload · callable → signInWithCustomToken → logout 순서
//   LN2: 해제 — signInWithCustomToken 0 · logout 1 → Done
//   LN3: SDK 취소(null) → Cancelled · callable 0 · logout 1
//   LN4: 응답 uid 다름 → IdentityMismatch · signInWithCustomToken 0
//   LN5: 서버 permission-denied + caller_identity_mismatch → IdentityMismatch
//   LN6: unavailable → Failed(NoInternetConnection)
//   LN7: 응답 customToken 부재 → Failed(UnknownException) · 소비 0
//   LN8: 로그인 사용자 부재 · 익명 → Failed(UnknownException) · SDK 0
//   LN9: SDK signIn 이 ServiceUnavailable → Failed(ServiceUnavailable)
//   LN10: access token 빈 문자열 → Failed(ServiceUnavailable) · callable 0
//   LN11: signInWithCustomToken 거부 → Failed(ServiceUnavailable) · logout 1

import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:mocktail/mocktail.dart';

import 'package:flutter_starter_kit/core/auth/provider_id.dart';
import 'package:flutter_starter_kit/core/auth/strategies/line_auth_strategy.dart';
import 'package:flutter_starter_kit/core/error/app_exception.dart';
import 'package:flutter_starter_kit/features/auth/data/auth_repository.dart';
import 'package:flutter_starter_kit/features/auth/data/line_sdk_client.dart';
import 'package:flutter_starter_kit/features/settings/data/disconnect/disconnect_step.dart';
import 'package:flutter_starter_kit/features/settings/data/disconnect/line_disconnect_step.dart';

class _MockFirebaseAuth extends Mock implements fb.FirebaseAuth {}

class _MockFbUser extends Mock implements fb.User {}

class _MockUserCredential extends Mock implements fb.UserCredential {}

class _MockGoogleSignIn extends Mock implements GoogleSignIn {}

class _MockLineSdkClient extends Mock implements LineSdkClient {}

class _MockFirebaseFunctions extends Mock implements FirebaseFunctions {}

class _MockHttpsCallable extends Mock implements HttpsCallable {}

class _MockHttpsCallableResult extends Mock
    implements HttpsCallableResult<Map<String, dynamic>> {}

const String _currentUid = 'U';

const LineDisconnectStep _step = LineDisconnectStep();

void main() {
  late _MockFirebaseAuth mockAuth;
  late _MockFbUser mockUser;
  late _MockLineSdkClient mockLine;
  late _MockFirebaseFunctions mockFunctions;
  late _MockHttpsCallable mockCallable;
  late DisconnectDeps deps;

  /// 끊기 callable 이 [data] 로 응답하게 stub 한다.
  void stubCallableResponse(Map<String, dynamic> data) {
    final result = _MockHttpsCallableResult();
    when(() => result.data).thenReturn(data);
    when(
      () => mockCallable.call<Map<String, dynamic>>(any()),
    ).thenAnswer((_) async => result);
  }

  /// 끊기 callable 이 [code] (+ [details]) 로 거부하게 stub 한다.
  void stubCallableThrows(String code, {Object? details}) {
    when(() => mockCallable.call<Map<String, dynamic>>(any())).thenThrow(
      FirebaseFunctionsException(
        message: 'server message',
        code: code,
        details: details,
      ),
    );
  }

  /// [outcome] 이 [DisconnectFailed] 이고 원인이 [matcher] 인지 단언한다.
  void expectFailedWith(DisconnectOutcome outcome, Matcher matcher) {
    expect(outcome, isA<DisconnectFailed>());
    expect((outcome as DisconnectFailed).exception, matcher);
  }

  /// LINE SDK 로그인이 [accessToken] 을 돌려주게 stub 한다.
  void stubLineSignIn({String accessToken = 'line-at'}) {
    when(() => mockLine.signIn()).thenAnswer(
      (_) async => LineSignInResult(
        idToken: 'line-id',
        nonce: 'n',
        accessToken: accessToken,
      ),
    );
  }

  setUp(() {
    mockAuth = _MockFirebaseAuth();
    mockUser = _MockFbUser();
    mockLine = _MockLineSdkClient();
    mockFunctions = _MockFirebaseFunctions();
    mockCallable = _MockHttpsCallable();
    when(() => mockAuth.currentUser).thenReturn(mockUser);
    when(() => mockUser.isAnonymous).thenReturn(false);
    when(() => mockUser.uid).thenReturn(_currentUid);
    when(() => mockLine.logout()).thenAnswer((_) async {});
    when(
      () => mockFunctions.httpsCallable(
        'disconnectLineProvider',
        options: any(named: 'options'),
      ),
    ).thenReturn(mockCallable);
    when(
      () => mockAuth.signInWithCustomToken(any()),
    ).thenAnswer((_) async => _MockUserCredential());
    // step 은 자기 SDK client 를 deps.read 로 얻는다 (review WR-04).
    final container = ProviderContainer.test(
      overrides: [lineSdkClientProvider.overrideWithValue(mockLine)],
    );
    deps = DisconnectDeps(
      auth: mockAuth,
      functions: mockFunctions,
      googleSignIn: _MockGoogleSignIn(),
      platform: TargetPlatform.android,
      read: container.read,
    );
  });

  test('행 메타 — provider line · 재로그인 행 · LINE strategy', () {
    expect(_step.provider, AccountProvider.line);
    expect(_step.kind, DisconnectKind.relogin);
    expect(_step.signInStrategy, isA<LineAuthStrategy>());
  });

  test(
    'LN1: 탈퇴 — callable → signInWithCustomToken → logout 순서 · Done',
    () async {
      stubLineSignIn();
      stubCallableResponse(<String, dynamic>{
        'ok': true,
        'customToken': 'ct-U',
        'uid': _currentUid,
      });

      final outcome = await _step.run(deps, reloginForFreshness: true);

      expect(outcome, isA<DisconnectDone>());
      // Pitfall 1: logout 은 callable 응답 · 세션 갱신 뒤에만. 한 호출은 한 번만
      // 검증되므로 payload 단언도 순서 목록 안에서 한다.
      verifyInOrder(<void Function()>[
        () => mockCallable.call<Map<String, dynamic>>(<String, dynamic>{
          'accessToken': 'line-at',
        }),
        () => mockAuth.signInWithCustomToken('ct-U'),
        () => mockLine.logout(),
      ]);
      final options =
          verify(
                () => mockFunctions.httpsCallable(
                  'disconnectLineProvider',
                  options: captureAny(named: 'options'),
                ),
              ).captured.single
              as HttpsCallableOptions;
      expect(options.timeout, AuthRepository.customTokenCallableTimeout);
    },
  );

  test('LN2: 해제(false) — custom token 소비 0 · logout 1 · Done', () async {
    stubLineSignIn();
    stubCallableResponse(<String, dynamic>{
      'ok': true,
      'customToken': 'ct-U',
      'uid': _currentUid,
    });

    final outcome = await _step.run(deps, reloginForFreshness: false);

    expect(outcome, isA<DisconnectDone>());
    verifyNever(() => mockAuth.signInWithCustomToken(any()));
    verify(() => mockLine.logout()).called(1);
  });

  test('LN3: SDK 로그인 취소(null) → Cancelled · callable 0 · logout 1', () async {
    when(() => mockLine.signIn()).thenAnswer((_) async => null);

    final outcome = await _step.run(deps, reloginForFreshness: true);

    expect(outcome, isA<DisconnectCancelled>());
    verifyNever(
      () => mockFunctions.httpsCallable(any(), options: any(named: 'options')),
    );
    verify(() => mockLine.logout()).called(1);
  });

  test('LN4: 응답 uid 가 다른 계정 → IdentityMismatch · 소비 0 · logout 1', () async {
    stubLineSignIn();
    stubCallableResponse(<String, dynamic>{
      'ok': true,
      'customToken': 'ct-OTHER',
      'uid': 'OTHER',
    });

    final outcome = await _step.run(deps, reloginForFreshness: true);

    expect(outcome, isA<DisconnectIdentityMismatch>());
    verifyNever(() => mockAuth.signInWithCustomToken(any()));
    verify(() => mockLine.logout()).called(1);
  });

  test(
    'LN5: 서버 permission-denied + caller_identity_mismatch → IdentityMismatch · logout 1',
    () async {
      stubLineSignIn();
      stubCallableThrows(
        'permission-denied',
        details: const <String, dynamic>{'reason': 'caller_identity_mismatch'},
      );

      final outcome = await _step.run(deps, reloginForFreshness: true);

      expect(outcome, isA<DisconnectIdentityMismatch>());
      verifyNever(() => mockAuth.signInWithCustomToken(any()));
      verify(() => mockLine.logout()).called(1);
    },
  );

  test('LN6: unavailable → Failed(NoInternetConnection) · logout 1', () async {
    stubLineSignIn();
    stubCallableThrows('unavailable');

    final outcome = await _step.run(deps, reloginForFreshness: true);

    expectFailedWith(outcome, isA<NoInternetConnection>());
    verify(() => mockLine.logout()).called(1);
  });

  test('LN7: 응답 customToken 부재 → Failed(UnknownException) · 소비 0', () async {
    stubLineSignIn();
    stubCallableResponse(<String, dynamic>{'ok': true, 'uid': _currentUid});

    final outcome = await _step.run(deps, reloginForFreshness: true);

    expectFailedWith(outcome, isA<UnknownException>());
    verifyNever(() => mockAuth.signInWithCustomToken(any()));
    verify(() => mockLine.logout()).called(1);
  });

  group('LN8: 로그인 사용자 부재 · 익명 → Failed(UnknownException) · SDK 0', () {
    test('LN8a: currentUser null', () async {
      when(() => mockAuth.currentUser).thenReturn(null);

      final outcome = await _step.run(deps, reloginForFreshness: true);

      expectFailedWith(outcome, isA<UnknownException>());
      verifyNever(() => mockLine.signIn());
      verifyNever(
        () =>
            mockFunctions.httpsCallable(any(), options: any(named: 'options')),
      );
    });

    test('LN8b: 익명 사용자', () async {
      when(() => mockUser.isAnonymous).thenReturn(true);

      final outcome = await _step.run(deps, reloginForFreshness: true);

      expectFailedWith(outcome, isA<UnknownException>());
      verifyNever(() => mockLine.signIn());
    });
  });

  test(
    'LN9: SDK signIn 이 ServiceUnavailable → Failed(ServiceUnavailable) · logout 1',
    () async {
      when(() => mockLine.signIn()).thenThrow(const ServiceUnavailable());

      final outcome = await _step.run(deps, reloginForFreshness: true);

      expectFailedWith(outcome, isA<ServiceUnavailable>());
      verifyNever(
        () =>
            mockFunctions.httpsCallable(any(), options: any(named: 'options')),
      );
      verify(() => mockLine.logout()).called(1);
    },
  );

  test(
    'LN10: access token 빈 문자열 → Failed(ServiceUnavailable) · callable 0 · logout 1',
    () async {
      stubLineSignIn(accessToken: '');

      final outcome = await _step.run(deps, reloginForFreshness: true);

      expectFailedWith(outcome, isA<ServiceUnavailable>());
      verifyNever(
        () =>
            mockFunctions.httpsCallable(any(), options: any(named: 'options')),
      );
      verify(() => mockLine.logout()).called(1);
    },
  );

  test(
    'LN11: signInWithCustomToken 이 FirebaseAuthException → Failed(ServiceUnavailable) · logout 1',
    () async {
      stubLineSignIn();
      stubCallableResponse(<String, dynamic>{
        'ok': true,
        'customToken': 'ct-U',
        'uid': _currentUid,
      });
      when(
        () => mockAuth.signInWithCustomToken('ct-U'),
      ).thenThrow(fb.FirebaseAuthException(code: 'network-request-failed'));

      final outcome = await _step.run(deps, reloginForFreshness: true);

      expectFailedWith(outcome, isA<ServiceUnavailable>());
      verify(() => mockLine.logout()).called(1);
    },
  );
}
