// ignore_for_file: lines_longer_than_80_chars
//
// Phase 16.10 plan 06 Task 2 — Naver 재로그인 끊기 step.
//
//   NV1: 1-tap 탈퇴 — payload {accessToken} · 재로그인 끊기 timeout(WR-03) · 순서
//   NV2: 웹 — payload {code, state} · 같은 재로그인 끊기 timeout(WR-03)
//   NV3: SDK 취소(null) → Cancelled · callable 0 · logout 1
//   NV4: 응답 uid 다름 → IdentityMismatch · signInWithCustomToken 0
//   NV5: 서버 permission-denied + caller_identity_mismatch → IdentityMismatch
//   NV6: 해제(false) → signInWithCustomToken 0 · Done
//   NV7: resource-exhausted → Failed(TooManyRequests)
//   NV8: 로그인 사용자 부재 → Failed(UnknownException) · SDK 0
//   NV9: SDK signIn 이 ServiceUnavailable → Failed(ServiceUnavailable) · logout 1
//   NV10: (review IN-03) 서버 끊기 뒤 signInWithCustomToken 거부 → Done · logout 1

import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:mocktail/mocktail.dart';

import 'package:flutter_starter_kit/core/auth/provider_id.dart';
import 'package:flutter_starter_kit/core/auth/strategies/naver_auth_strategy.dart';
import 'package:flutter_starter_kit/core/error/app_exception.dart';
import 'package:flutter_starter_kit/features/auth/data/naver_sdk_client.dart';
import 'package:flutter_starter_kit/features/auth/data/naver_sign_in_result.dart';
import 'package:flutter_starter_kit/features/settings/data/disconnect/disconnect_step.dart';
import 'package:flutter_starter_kit/features/settings/data/disconnect/naver_disconnect_step.dart';

class _MockFirebaseAuth extends Mock implements fb.FirebaseAuth {}

class _MockFbUser extends Mock implements fb.User {}

class _MockUserCredential extends Mock implements fb.UserCredential {}

class _MockGoogleSignIn extends Mock implements GoogleSignIn {}

class _MockNaverSdkClient extends Mock implements NaverSdkClient {}

class _MockFirebaseFunctions extends Mock implements FirebaseFunctions {}

class _MockHttpsCallable extends Mock implements HttpsCallable {}

class _MockHttpsCallableResult extends Mock
    implements HttpsCallableResult<Map<String, dynamic>> {}

const String _currentUid = 'U';

/// 서버 직렬 외부 호출 최악 예산 (review WR-03) — Naver 웹: code 교환 5s → 프로필 5s → revoke 5s.
///
/// 각 호출은 서버 `FETCH_TIMEOUT_MS`(5000) `AbortSignal.timeout` 상한이다.
/// client timeout 은 이보다 커야 서버 성공을 실패로 오표시하지 않는다.
const Duration _serverWorstExternalBudget = Duration(seconds: 15);

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
    // step 은 자기 SDK client 를 deps.read 로 얻는다 (review WR-04).
    final container = ProviderContainer.test(
      overrides: [naverSdkClientProvider.overrideWithValue(mockNaver)],
    );
    deps = DisconnectDeps(
      auth: mockAuth,
      functions: mockFunctions,
      googleSignIn: _MockGoogleSignIn(),
      platform: TargetPlatform.android,
      read: container.read,
    );
  });

  test('행 메타 — provider naver · 재로그인 행 · Naver strategy', () {
    expect(_step.provider, AccountProvider.naver);
    expect(_step.kind, DisconnectKind.relogin);
    expect(_step.signInStrategy, isA<NaverAuthStrategy>());
  });

  test(
    'NV1: 1-tap 탈퇴 — {accessToken} · 재로그인 끊기 timeout(WR-03) · callable → 세션 갱신 → logout 순서',
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
      // WR-03: 서버 최악 외부 예산(1-tap 10s · 웹 15s)보다 길고 두 모양이 같다.
      final timeout = capturedTimeout();
      expect(timeout, kReloginDisconnectCallableTimeout);
      expect(timeout, greaterThan(_serverWorstExternalBudget));
    },
  );

  test('NV2: 웹 — {code, state} · 재로그인 끊기 timeout(WR-03)', () async {
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
    final timeout = capturedTimeout();
    expect(timeout, kReloginDisconnectCallableTimeout);
    expect(timeout, greaterThan(_serverWorstExternalBudget));
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

  test(
    'NV10 (review IN-03): 서버 끊기 뒤 signInWithCustomToken 실패 → Done(provider 측 해제됨) · logout 1',
    () async {
      stubAppSignIn();
      stubCallableResponse(_okResponse);
      when(
        () => mockAuth.signInWithCustomToken('ct-U'),
      ).thenThrow(fb.FirebaseAuthException(code: 'network-request-failed'));

      final outcome = await _step.run(deps, reloginForFreshness: true);

      expect(outcome, isA<DisconnectDone>());
      verify(() => mockAuth.signInWithCustomToken('ct-U')).called(1);
      verify(() => mockNaver.logout()).called(1);
    },
  );
}
