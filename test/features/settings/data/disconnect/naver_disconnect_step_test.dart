// ignore_for_file: lines_longer_than_80_chars
//
// Phase 16.10 plan 06 Task 2 — Naver 재로그인 끊기 step.
//
//   NV1: 1-tap 탈퇴 — payload {accessToken} · Custom Token timeout · 순서
//   NV2: 웹 — payload {code, state} · 웹 timeout
//   NV3: SDK 취소(null) → Cancelled · callable 0 · logout 1
//   NV4: 응답 uid 다름 → IdentityMismatch · signInWithCustomToken 0
//   NV5: 서버 permission-denied + caller_identity_mismatch → IdentityMismatch
//   NV6: 해제(false) → signInWithCustomToken 0 · Done
//   NV7: resource-exhausted → Failed(TooManyRequests)
//   NV8: 로그인 사용자 부재 → Failed(UnknownException) · SDK 0
//   NV9: SDK signIn 이 ServiceUnavailable → Failed(ServiceUnavailable) · logout 1

import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:mocktail/mocktail.dart';

import 'package:flutter_starter_kit/core/auth/provider_id.dart';
import 'package:flutter_starter_kit/core/auth/strategies/naver_auth_strategy.dart';
import 'package:flutter_starter_kit/core/error/app_exception.dart';
import 'package:flutter_starter_kit/features/auth/data/auth_repository.dart';
import 'package:flutter_starter_kit/features/auth/data/line_sdk_client.dart';
import 'package:flutter_starter_kit/features/auth/data/naver_sdk_client.dart';
import 'package:flutter_starter_kit/features/auth/data/naver_sign_in_result.dart';
import 'package:flutter_starter_kit/features/settings/data/disconnect/disconnect_step.dart';
import 'package:flutter_starter_kit/features/settings/data/disconnect/naver_disconnect_step.dart';

class _MockFirebaseAuth extends Mock implements fb.FirebaseAuth {}

class _MockFbUser extends Mock implements fb.User {}

class _MockUserCredential extends Mock implements fb.UserCredential {}

class _MockGoogleSignIn extends Mock implements GoogleSignIn {}

class _MockLineSdkClient extends Mock implements LineSdkClient {}

class _MockNaverSdkClient extends Mock implements NaverSdkClient {}

class _MockFirebaseFunctions extends Mock implements FirebaseFunctions {}

class _MockHttpsCallable extends Mock implements HttpsCallable {}

class _MockHttpsCallableResult extends Mock
    implements HttpsCallableResult<Map<String, dynamic>> {}

const String _currentUid = 'U';

const NaverDisconnectStep _step = NaverDisconnectStep();

/// 같은 uid 로 발급된 정상 끊기 응답.
const Map<String, dynamic> _okResponse = <String, dynamic>{
  'ok': true,
  'customToken': 'ct-U',
  'uid': _currentUid,
};

void main() {
  late _MockFirebaseAuth mockAuth;
  late _MockFbUser mockUser;
  late _MockNaverSdkClient mockNaver;
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

  /// Naver SDK 로그인이 1-tap access token 을 돌려주게 stub 한다.
  void stubAppSignIn() {
    when(
      () => mockNaver.signIn(),
    ).thenAnswer((_) async => const NaverAppSignIn(accessToken: 'naver-at'));
  }

  /// 끊기 callable 생성 시 넘긴 timeout 을 꺼낸다.
  Duration? capturedTimeout() {
    final options =
        verify(
              () => mockFunctions.httpsCallable(
                'disconnectNaverProvider',
                options: captureAny(named: 'options'),
              ),
            ).captured.single
            as HttpsCallableOptions;
    return options.timeout;
  }

  setUp(() {
    mockAuth = _MockFirebaseAuth();
    mockUser = _MockFbUser();
    mockNaver = _MockNaverSdkClient();
    mockFunctions = _MockFirebaseFunctions();
    mockCallable = _MockHttpsCallable();
    when(() => mockAuth.currentUser).thenReturn(mockUser);
    when(() => mockUser.isAnonymous).thenReturn(false);
    when(() => mockUser.uid).thenReturn(_currentUid);
    when(() => mockNaver.logout()).thenAnswer((_) async {});
    when(
      () => mockFunctions.httpsCallable(
        'disconnectNaverProvider',
        options: any(named: 'options'),
      ),
    ).thenReturn(mockCallable);
    when(
      () => mockAuth.signInWithCustomToken(any()),
    ).thenAnswer((_) async => _MockUserCredential());
    deps = DisconnectDeps(
      auth: mockAuth,
      functions: mockFunctions,
      googleSignIn: _MockGoogleSignIn(),
      lineSdkClient: _MockLineSdkClient(),
      naverSdkClient: mockNaver,
      platform: TargetPlatform.android,
    );
  });

  test('행 메타 — provider naver · 재로그인 행 · Naver strategy', () {
    expect(_step.provider, AccountProvider.naver);
    expect(_step.kind, DisconnectKind.relogin);
    expect(_step.signInStrategy, isA<NaverAuthStrategy>());
  });

  test(
    'NV1: 1-tap 탈퇴 — {accessToken} · Custom Token timeout · callable → 세션 갱신 → logout 순서',
    () async {
      stubAppSignIn();
      stubCallableResponse(_okResponse);

      final outcome = await _step.run(deps, reloginForFreshness: true);

      expect(outcome, isA<DisconnectDone>());
      // Pitfall 1: 한 호출은 한 번만 검증되므로 payload 단언도 순서 목록 안에서.
      verifyInOrder(<void Function()>[
        () => mockCallable.call<Map<String, dynamic>>(<String, dynamic>{
          'accessToken': 'naver-at',
        }),
        () => mockAuth.signInWithCustomToken('ct-U'),
        () => mockNaver.logout(),
      ]);
      expect(capturedTimeout(), AuthRepository.customTokenCallableTimeout);
    },
  );

  test('NV2: 웹 — {code, state} · naverWebCallableTimeout', () async {
    when(
      () => mockNaver.signIn(),
    ).thenAnswer((_) async => const NaverWebSignIn(code: 'c', state: 's'));
    stubCallableResponse(_okResponse);

    final outcome = await _step.run(deps, reloginForFreshness: true);

    expect(outcome, isA<DisconnectDone>());
    verify(
      () => mockCallable.call<Map<String, dynamic>>(<String, dynamic>{
        'code': 'c',
        'state': 's',
      }),
    ).called(1);
    expect(capturedTimeout(), AuthRepository.naverWebCallableTimeout);
    verify(() => mockNaver.logout()).called(1);
  });

  test('NV3: SDK 로그인 취소(null) → Cancelled · callable 0 · logout 1', () async {
    when(() => mockNaver.signIn()).thenAnswer((_) async => null);

    final outcome = await _step.run(deps, reloginForFreshness: true);

    expect(outcome, isA<DisconnectCancelled>());
    verifyNever(
      () => mockFunctions.httpsCallable(any(), options: any(named: 'options')),
    );
    verify(() => mockNaver.logout()).called(1);
  });

  test('NV4: 응답 uid 가 다른 계정 → IdentityMismatch · 소비 0 · logout 1', () async {
    stubAppSignIn();
    stubCallableResponse(<String, dynamic>{
      'ok': true,
      'customToken': 'ct-OTHER',
      'uid': 'OTHER',
    });

    final outcome = await _step.run(deps, reloginForFreshness: true);

    expect(outcome, isA<DisconnectIdentityMismatch>());
    verifyNever(() => mockAuth.signInWithCustomToken(any()));
    verify(() => mockNaver.logout()).called(1);
  });

  test(
    'NV5: 서버 permission-denied + caller_identity_mismatch → IdentityMismatch · 소비 0',
    () async {
      stubAppSignIn();
      stubCallableThrows(
        'permission-denied',
        details: const <String, dynamic>{'reason': 'caller_identity_mismatch'},
      );

      final outcome = await _step.run(deps, reloginForFreshness: true);

      expect(outcome, isA<DisconnectIdentityMismatch>());
      verifyNever(() => mockAuth.signInWithCustomToken(any()));
      verify(() => mockNaver.logout()).called(1);
    },
  );

  test('NV6: 해제(false) — custom token 소비 0 · logout 1 · Done', () async {
    stubAppSignIn();
    stubCallableResponse(_okResponse);

    final outcome = await _step.run(deps, reloginForFreshness: false);

    expect(outcome, isA<DisconnectDone>());
    verifyNever(() => mockAuth.signInWithCustomToken(any()));
    verify(() => mockNaver.logout()).called(1);
  });

  test('NV7: resource-exhausted → Failed(TooManyRequests)', () async {
    stubAppSignIn();
    stubCallableThrows('resource-exhausted');

    final outcome = await _step.run(deps, reloginForFreshness: true);

    expect(outcome, isA<DisconnectFailed>());
    expect((outcome as DisconnectFailed).exception, isA<TooManyRequests>());
    verify(() => mockNaver.logout()).called(1);
  });

  test('NV8: 로그인 사용자 부재 → Failed(UnknownException) · SDK 0', () async {
    when(() => mockAuth.currentUser).thenReturn(null);

    final outcome = await _step.run(deps, reloginForFreshness: true);

    expect(outcome, isA<DisconnectFailed>());
    expect((outcome as DisconnectFailed).exception, isA<UnknownException>());
    verifyNever(() => mockNaver.signIn());
    verifyNever(
      () => mockFunctions.httpsCallable(any(), options: any(named: 'options')),
    );
  });

  test(
    'NV9: SDK signIn 이 ServiceUnavailable → Failed(ServiceUnavailable) · logout 1',
    () async {
      when(() => mockNaver.signIn()).thenThrow(const ServiceUnavailable());

      final outcome = await _step.run(deps, reloginForFreshness: true);

      expect(outcome, isA<DisconnectFailed>());
      expect(
        (outcome as DisconnectFailed).exception,
        isA<ServiceUnavailable>(),
      );
      verifyNever(
        () =>
            mockFunctions.httpsCallable(any(), options: any(named: 'options')),
      );
      verify(() => mockNaver.logout()).called(1);
    },
  );
}
