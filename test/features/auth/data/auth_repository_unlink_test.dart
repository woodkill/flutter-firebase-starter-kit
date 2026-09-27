// Phase 16.8 D-01 · D-02 · D-06 — AuthRepository 연결 해제 두 메서드.
//
// native (`unlinkNativeProvider`):
//   N1 happy — `User.unlink` → `reload()` → 갱신된 providerData 로 User 반환 ·
//      진행 플래그 begin 0 · 가입 수단 recorder 호출 0 (D-01)
//   N2~N5 FirebaseAuthException code → AppException 매핑
//   N6 · N7 caller 부재 · 익명 → UnknownException (unlink 미호출)
//   N8 비-Auth 예외 → ServiceUnavailable
//   N9 unlink 확정 뒤 reload 실패 → Success 유지 (review WR-01)
//
// Custom Token wrapper (`unlinkCustomTokenProvider`):
//   C1 happy — callable 'unlinkCustomTokenProvider' payload {provider} ·
//      {ok: true} → reload · 진행 플래그 begin 0 · recorder 호출 0 (D-01)
//   C2 · C3 `failed-precondition` reason 선분기 쌍 (RESEARCH Pitfall 4)
//   C4~C8 code → AppException 매핑 (C5 · C6 `unauthenticated` ·
//      `permission-denied` → ServiceUnavailable — review IN-06) ·
//      C9 `{ok: false}` 계약 위반
//   C10 caller 부재 · 익명 → UnknownException (callable 미호출)
//   C11 비-Functions 예외 → ServiceUnavailable
//   C12 `{ok: true}` 확정 뒤 reload 실패 → Success 유지 (review WR-01)
//
// fixture 는 합성 값만 쓴다 (`uid-1` · `me@example.com`).

import 'package:cloud_functions/cloud_functions.dart' hide Result;
import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:flutter_facebook_auth/flutter_facebook_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:mocktail/mocktail.dart';

import 'package:flutter_starter_kit/core/error/app_exception.dart';
import 'package:flutter_starter_kit/core/error/result.dart';
import 'package:flutter_starter_kit/features/auth/application/social_link_in_progress.dart';
import 'package:flutter_starter_kit/features/auth/data/auth_repository.dart';
import 'package:flutter_starter_kit/features/auth/data/kakao_sdk_client.dart';
import 'package:flutter_starter_kit/features/auth/data/line_sdk_client.dart';
import 'package:flutter_starter_kit/features/auth/data/naver_sdk_client.dart';
import 'package:flutter_starter_kit/features/auth/domain/user.dart';

class _MockFirebaseAuth extends Mock implements fb.FirebaseAuth {}

class _MockFbUser extends Mock implements fb.User {}

class _MockUserMetadata extends Mock implements fb.UserMetadata {}

class _MockUserInfo extends Mock implements fb.UserInfo {}

class _MockGoogleSignIn extends Mock implements GoogleSignIn {}

class _MockFacebookAuth extends Mock implements FacebookAuth {}

class _MockSocialLinkInProgress extends Mock implements SocialLinkInProgress {}

class _MockKakaoSdkClient extends Mock implements KakaoSdkClient {}

class _MockNaverSdkClient extends Mock implements NaverSdkClient {}

class _MockLineSdkClient extends Mock implements LineSdkClient {}

class _MockFirebaseFunctions extends Mock implements FirebaseFunctions {}

class _MockHttpsCallable extends Mock implements HttpsCallable {}

class _MockHttpsCallableResult extends Mock
    implements HttpsCallableResult<Map<String, dynamic>> {}

/// [providerId] 를 돌려주는 [fb.UserInfo] mock 을 만든다.
_MockUserInfo _buildUserInfo(String providerId) {
  final info = _MockUserInfo();
  when(() => info.providerId).thenReturn(providerId);
  return info;
}

/// [result] 가 [Failure] 임을 단언하고 담긴 [AppException] 을 돌려준다.
AppException _failureOf(Result<User> result) {
  expect(result, isA<Failure<dynamic>>());
  return (result as Failure<dynamic>).exception;
}

void main() {
  late _MockFirebaseAuth mockAuth;
  late _MockSocialLinkInProgress mockSocialLinkInProgress;
  late _MockFirebaseFunctions mockFunctions;
  late _MockHttpsCallable mockCallable;
  late _MockHttpsCallableResult mockResult;
  late _MockFbUser mockCurrentUser;
  late _MockUserMetadata mockMetadata;
  late AuthRepository repository;

  /// 가입 수단 recorder 호출 기록 — 해제 경로는 비어 있어야 한다 (D-01).
  final recorded = <(String, String)>[];

  /// `mockCurrentUser.providerData` 가 돌려주는 현재 목록.
  late List<fb.UserInfo> providerInfos;

  setUpAll(() {
    registerFallbackValue(<String, dynamic>{});
  });

  setUp(() {
    recorded.clear();
    mockAuth = _MockFirebaseAuth();
    mockSocialLinkInProgress = _MockSocialLinkInProgress();
    mockFunctions = _MockFirebaseFunctions();
    mockCallable = _MockHttpsCallable();
    mockResult = _MockHttpsCallableResult();
    mockCurrentUser = _MockFbUser();
    mockMetadata = _MockUserMetadata();

    repository = AuthRepository(
      mockAuth,
      _MockGoogleSignIn(),
      _MockFacebookAuth(),
      mockSocialLinkInProgress,
      _MockKakaoSdkClient(),
      mockFunctions,
      _MockNaverSdkClient(),
      _MockLineSdkClient(),
      () async {},
      recordSignUpMethod: (uid, id) async => recorded.add((uid, id)),
    );

    // _mapFirebaseUser 가 참조하는 fb.User getter default stub.
    providerInfos = <fb.UserInfo>[
      _buildUserInfo('google.com'),
      _buildUserInfo('password'),
    ];
    when(() => mockCurrentUser.uid).thenReturn('uid-1');
    when(() => mockCurrentUser.email).thenReturn('me@example.com');
    when(() => mockCurrentUser.emailVerified).thenReturn(true);
    when(() => mockCurrentUser.displayName).thenReturn(null);
    when(() => mockCurrentUser.photoURL).thenReturn(null);
    when(() => mockCurrentUser.isAnonymous).thenReturn(false);
    when(() => mockCurrentUser.metadata).thenReturn(mockMetadata);
    when(() => mockMetadata.creationTime).thenReturn(DateTime.utc(2026, 1, 1));
    when(() => mockCurrentUser.providerData).thenAnswer((_) => providerInfos);
    when(() => mockCurrentUser.reload()).thenAnswer((_) async {});
    when(() => mockAuth.currentUser).thenReturn(mockCurrentUser);

    // unlinkCustomTokenProvider callable default wiring — {ok: true}.
    when(
      () => mockFunctions.httpsCallable(
        'unlinkCustomTokenProvider',
        options: any(named: 'options'),
      ),
    ).thenReturn(mockCallable);
    when(() => mockResult.data).thenReturn(<String, dynamic>{'ok': true});
    when(
      () => mockCallable.call<Map<String, dynamic>>(any()),
    ).thenAnswer((_) async => mockResult);
  });

  /// native `unlink` 이 [code] 로 거부되도록 stub 한다.
  void stubUnlinkThrows(String code) {
    when(
      () => mockCurrentUser.unlink('google.com'),
    ).thenThrow(fb.FirebaseAuthException(code: code));
  }

  /// callable 이 [code] (+ [details]) 로 거부되도록 stub 한다.
  void stubCallableThrows(String code, {Object? details}) {
    when(() => mockCallable.call<Map<String, dynamic>>(any())).thenThrow(
      FirebaseFunctionsException(
        code: code,
        message: 'server-message',
        details: details,
      ),
    );
  }

  group('Phase 16.8 D-02 · D-06 — unlinkNativeProvider', () {
    test(
      'N1: unlink → reload → 갱신된 providerData · 진행 플래그 0 · recorder 0',
      () async {
        when(() => mockCurrentUser.unlink('google.com')).thenAnswer((_) async {
          // Firebase 가 해제 후 providerData 에서 해당 provider 를 뺀 상태.
          providerInfos = <fb.UserInfo>[_buildUserInfo('password')];
          return mockCurrentUser;
        });

        final result = await repository.unlinkNativeProvider('google.com');

        expect(result, isA<Success<User>>());
        final user = (result as Success<User>).data;
        expect(user.providerIds, isNot(contains('google.com')));
        expect(user.providerIds, <String>['password']);
        verify(() => mockCurrentUser.unlink('google.com')).called(1);
        verify(() => mockCurrentUser.reload()).called(1);
        // 해제는 currentUser == null 창이 없다 — 진행 플래그를 감싸지 않는다.
        verifyNever(() => mockSocialLinkInProgress.begin());
        // D-01 — 해제 경로는 가입 수단(signUpProviderId)을 쓰지 않는다.
        expect(recorded, isEmpty);
      },
    );

    test('N2: no-such-provider → ProviderNotLinked', () async {
      stubUnlinkThrows('no-such-provider');

      final result = await repository.unlinkNativeProvider('google.com');

      expect(_failureOf(result), isA<ProviderNotLinked>());
    });

    test(
      'N3: requires-recent-login → ReauthenticationRequiredException',
      () async {
        stubUnlinkThrows('requires-recent-login');

        final result = await repository.unlinkNativeProvider('google.com');

        expect(_failureOf(result), isA<ReauthenticationRequiredException>());
      },
    );

    test('N4: network-request-failed → NoInternetConnection', () async {
      stubUnlinkThrows('network-request-failed');

      final result = await repository.unlinkNativeProvider('google.com');

      expect(_failureOf(result), isA<NoInternetConnection>());
    });

    test('N5: too-many-requests → TooManyRequests', () async {
      stubUnlinkThrows('too-many-requests');

      final result = await repository.unlinkNativeProvider('google.com');

      expect(_failureOf(result), isA<TooManyRequests>());
    });

    test('N6: currentUser null → UnknownException · unlink 미호출', () async {
      when(() => mockAuth.currentUser).thenReturn(null);

      final result = await repository.unlinkNativeProvider('google.com');

      expect(_failureOf(result), isA<UnknownException>());
      verifyNever(() => mockCurrentUser.unlink(any()));
    });

    test('N7: 익명 caller → UnknownException · unlink 미호출', () async {
      when(() => mockCurrentUser.isAnonymous).thenReturn(true);

      final result = await repository.unlinkNativeProvider('google.com');

      expect(_failureOf(result), isA<UnknownException>());
      verifyNever(() => mockCurrentUser.unlink(any()));
    });

    test('N8: 비-Auth 예외 → ServiceUnavailable', () async {
      when(
        () => mockCurrentUser.unlink('google.com'),
      ).thenThrow(StateError('x'));

      final result = await repository.unlinkNativeProvider('google.com');

      expect(_failureOf(result), isA<ServiceUnavailable>());
    });

    test('N9: unlink 확정 뒤 reload 가 throw 해도 Success (WR-01)', () async {
      when(() => mockCurrentUser.unlink('google.com')).thenAnswer((_) async {
        providerInfos = <fb.UserInfo>[_buildUserInfo('password')];
        return mockCurrentUser;
      });
      when(
        () => mockCurrentUser.reload(),
      ).thenThrow(fb.FirebaseAuthException(code: 'network-request-failed'));

      final result = await repository.unlinkNativeProvider('google.com');

      expect(result, isA<Success<User>>());
      expect((result as Success<User>).data.providerIds, <String>['password']);
      verify(() => mockCurrentUser.reload()).called(1);
    });
  });

  group('Phase 16.8 D-02 · D-06 — unlinkCustomTokenProvider', () {
    test(
      'C1: payload {provider: kakao} · ok → reload · 진행 플래그 0 · recorder 0',
      () async {
        final result = await repository.unlinkCustomTokenProvider('kakao');

        expect(result, isA<Success<User>>());
        final captured =
            verify(
                  () => mockCallable.call<Map<String, dynamic>>(captureAny()),
                ).captured.single
                as Map<String, dynamic>;
        expect(captured, <String, dynamic>{'provider': 'kakao'});
        verify(() => mockCurrentUser.reload()).called(1);
        verifyNever(() => mockSocialLinkInProgress.begin());
        // D-01 — CT wrapper 경로도 가입 수단을 쓰지 않는다 (서버가 원장 정리).
        expect(recorded, isEmpty);
      },
    );

    test(
      'C2: failed-precondition + reason last_credential → UnlinkLastCredentialRejected',
      () async {
        stubCallableThrows(
          'failed-precondition',
          details: const <String, dynamic>{'reason': 'last_credential'},
        );

        final result = await repository.unlinkCustomTokenProvider('kakao');

        expect(_failureOf(result), isA<UnlinkLastCredentialRejected>());
      },
    );

    test(
      'C3: failed-precondition reason 없음 → ServiceUnavailable (기존 매핑)',
      () async {
        stubCallableThrows('failed-precondition');

        final result = await repository.unlinkCustomTokenProvider('kakao');

        expect(_failureOf(result), isA<ServiceUnavailable>());
      },
    );

    test('C4: not-found → ProviderNotLinked', () async {
      stubCallableThrows('not-found');

      final result = await repository.unlinkCustomTokenProvider('kakao');

      expect(_failureOf(result), isA<ProviderNotLinked>());
    });

    // review IN-06 — App Check 차단은 `unauthenticated` 로 오고 재로그인으로
    // 해소되지 않는다. 해제는 재인증이 없으므로(D-06) 두 code 모두 일반
    // 오류(ServiceUnavailable → 「잠시 후 다시 시도」)로 흘린다.
    test('C5: unauthenticated → ServiceUnavailable (재로그인 유도 0)', () async {
      stubCallableThrows('unauthenticated');

      final result = await repository.unlinkCustomTokenProvider('kakao');

      final exception = _failureOf(result);
      expect(exception, isA<ServiceUnavailable>());
      expect(exception, isNot(isA<ReauthenticationRequiredException>()));
    });

    test('C6: permission-denied → ServiceUnavailable (재로그인 유도 0)', () async {
      stubCallableThrows('permission-denied');

      final result = await repository.unlinkCustomTokenProvider('kakao');

      final exception = _failureOf(result);
      expect(exception, isA<ServiceUnavailable>());
      expect(exception, isNot(isA<ReauthenticationRequiredException>()));
    });

    test('C7: resource-exhausted → TooManyRequests', () async {
      stubCallableThrows('resource-exhausted');

      final result = await repository.unlinkCustomTokenProvider('kakao');

      expect(_failureOf(result), isA<TooManyRequests>());
    });

    test('C8: unavailable → NoInternetConnection', () async {
      stubCallableThrows('unavailable');

      final result = await repository.unlinkCustomTokenProvider('kakao');

      expect(_failureOf(result), isA<NoInternetConnection>());
    });

    test('C9: 응답 ok false → UnknownException · reload 미호출', () async {
      when(() => mockResult.data).thenReturn(<String, dynamic>{'ok': false});

      final result = await repository.unlinkCustomTokenProvider('kakao');

      expect(_failureOf(result), isA<UnknownException>());
      verifyNever(() => mockCurrentUser.reload());
    });

    test('C10: caller 부재 · 익명 → UnknownException · callable 미호출', () async {
      when(() => mockAuth.currentUser).thenReturn(null);
      final nullCaller = await repository.unlinkCustomTokenProvider('kakao');
      expect(_failureOf(nullCaller), isA<UnknownException>());

      when(() => mockAuth.currentUser).thenReturn(mockCurrentUser);
      when(() => mockCurrentUser.isAnonymous).thenReturn(true);
      final anonymousCaller = await repository.unlinkCustomTokenProvider(
        'kakao',
      );
      expect(_failureOf(anonymousCaller), isA<UnknownException>());

      verifyNever(
        () => mockFunctions.httpsCallable(
          'unlinkCustomTokenProvider',
          options: any(named: 'options'),
        ),
      );
    });

    test('C11: 비-Functions 예외 → ServiceUnavailable', () async {
      when(
        () => mockCallable.call<Map<String, dynamic>>(any()),
      ).thenThrow(StateError('x'));

      final result = await repository.unlinkCustomTokenProvider('kakao');

      expect(_failureOf(result), isA<ServiceUnavailable>());
    });

    test('C12: ok 확정 뒤 reload 가 throw 해도 Success (WR-01)', () async {
      when(
        () => mockCurrentUser.reload(),
      ).thenThrow(fb.FirebaseAuthException(code: 'network-request-failed'));

      final result = await repository.unlinkCustomTokenProvider('kakao');

      expect(result, isA<Success<User>>());
      verify(() => mockCurrentUser.reload()).called(1);
    });
  });
}
