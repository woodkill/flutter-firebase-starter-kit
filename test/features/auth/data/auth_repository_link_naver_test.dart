// ignore_for_file: lines_longer_than_80_chars
//
// Phase 16.9 Plan 16.9-02 Task 2 — Naver proactive account linking
// (`AuthRepository.linkNaverProviderArm()`) 단위 테스트 (D-04).
//
// 설정 Surface D 「네이버 연결」 → `NaverSdkClient.signIn()` 상속(1-tap/웹
// 라우팅 · state · 취소) → caller fresh ID Token → callable
// `linkNaverProvider` payload → `{ok:true}` → reload 계약을 mock 으로 잠근다.
// 서버 계약(callable 이름 · payload 키 · code 분기)은 plan 16.9-01 과 같다.
//
// 케이스:
//   R1: 1-tap 성공 — payload 키 {idToken, accessToken} · timeout 10s · reload · logout
//   R2: 웹 성공 — payload 키 {idToken, code, state} · timeout 20s
//   R3: 취소 (signIn null) — null · callable/getIdToken 미호출 · logout
//   R4: unauthenticated + details.reason 'reauthentication_required' ·
//       permission-denied → ReauthenticationRequiredException / reason 없는
//       unauthenticated (Naver 거부 · code 교환 거부 · App Check 차단) →
//       ServiceUnavailable (16.9 review WR-01) / 다른 code + reauth reason 은
//       재로그인 아님 (code anchor · iteration 2 IN-01)
//   R5: already-exists → AccountAlreadyLinked / + reason provider_already_linked
//       → ProviderAlreadyLinkedToThisAccount (16.9 review IN-03)
//   R6: unavailable → NoInternetConnection · failed-precondition → ServiceUnavailable
//   R7: ok:false · currentUser null · 익명 → UnknownException (WR-06) —
//       null · 익명은 signIn 전에 거부 (16.9 review IN-02) · NAVER 왕복 중
//       current user 가 null · 익명 · 다른 uid 로 바뀌어도 거부
//       (16.9 review iteration 2 WR-01) · 같은 uid 의 새 인스턴스로 바뀌면
//       통과 — 새 인스턴스 토큰으로 연결 (uid 대조 시맨틱 · iteration 3 IN-05)
//   R8: signIn 이 ServiceUnavailable throw → 그대로 전달 · callable 미호출
//   R9: SocialLinkInProgress begin/end 1회 — 성공 · 취소 · SDK 오류
//
// 모든 케이스는 finally 의 Naver SDK logout 1회를 단언한다 (C-05 1회성 토큰).
// PII: payload 는 키 · 고정 fixture 값만 단언한다 (T-16.9-08).

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
import 'package:flutter_starter_kit/features/auth/data/naver_sign_in_result.dart';

class _MockFirebaseAuth extends Mock implements fb.FirebaseAuth {}

class _MockFbUser extends Mock implements fb.User {}

class _MockUserMetadata extends Mock implements fb.UserMetadata {}

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

void main() {
  late _MockFirebaseAuth mockAuth;
  late _MockSocialLinkInProgress mockSocialLinkInProgress;
  late _MockNaverSdkClient mockNaverSdkClient;
  late _MockFirebaseFunctions mockFunctions;
  late _MockHttpsCallable mockLinkCallable;
  late _MockHttpsCallableResult mockResult;
  late _MockFbUser mockCurrentUser;
  late _MockUserMetadata mockMetadata;
  late AuthRepository repository;

  setUpAll(() {
    registerFallbackValue(<String, dynamic>{});
  });

  setUp(() {
    mockAuth = _MockFirebaseAuth();
    mockSocialLinkInProgress = _MockSocialLinkInProgress();
    mockNaverSdkClient = _MockNaverSdkClient();
    mockFunctions = _MockFirebaseFunctions();
    mockLinkCallable = _MockHttpsCallable();
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
      mockNaverSdkClient,
      _MockLineSdkClient(),
      () async {},
    );

    // _mapFirebaseUser 가 참조하는 fb.User getter default stub.
    when(() => mockCurrentUser.uid).thenReturn('linked-uid');
    when(() => mockCurrentUser.email).thenReturn('user@example.com');
    when(() => mockCurrentUser.emailVerified).thenReturn(true);
    when(() => mockCurrentUser.displayName).thenReturn('User');
    when(() => mockCurrentUser.photoURL).thenReturn(null);
    when(() => mockCurrentUser.isAnonymous).thenReturn(false);
    when(() => mockCurrentUser.metadata).thenReturn(mockMetadata);
    when(() => mockMetadata.creationTime).thenReturn(DateTime.utc(2026, 1, 1));
    when(() => mockCurrentUser.providerData).thenReturn(const []);
    when(() => mockCurrentUser.reload()).thenAnswer((_) async {});
    when(
      () => mockCurrentUser.getIdToken(any()),
    ).thenAnswer((_) async => 'caller-fresh-id-token');

    when(() => mockAuth.currentUser).thenReturn(mockCurrentUser);

    // C-05 1회성 토큰 — finally logout default stub.
    when(() => mockNaverSdkClient.logout()).thenAnswer((_) async {});

    // linkNaverProvider callable default wiring — {ok:true}.
    when(
      () => mockFunctions.httpsCallable(
        'linkNaverProvider',
        options: any(named: 'options'),
      ),
    ).thenReturn(mockLinkCallable);
    when(() => mockResult.data).thenReturn(<String, dynamic>{'ok': true});
    when(
      () => mockLinkCallable.call<Map<String, dynamic>>(any()),
    ).thenAnswer((_) async => mockResult);
  });

  /// 1-tap 경로 fixture — NAVER 앱이 돌려준 access token.
  void stubAppSignIn() {
    when(() => mockNaverSdkClient.signIn()).thenAnswer(
      (_) async => const NaverAppSignIn(accessToken: 'naver-app-token'),
    );
  }

  /// 킷 웹 경로 fixture — authorization code + 대조 완료 state.
  void stubWebSignIn() {
    when(
      () => mockNaverSdkClient.signIn(),
    ).thenAnswer((_) async => const NaverWebSignIn(code: 'c', state: 's'));
  }

  /// callable 이 [code] (· 선택 [details]) 로 거부하도록 stub 한다.
  void stubCallableThrows(String code, {Object? details}) {
    when(() => mockLinkCallable.call<Map<String, dynamic>>(any())).thenThrow(
      FirebaseFunctionsException(
        code: code,
        message: 'server-token',
        details: details,
      ),
    );
  }

  /// 서버 `reauthenticationRequired()` 의 details 모양.
  const reauthDetails = <String, Object?>{
    'reason': 'reauthentication_required',
  };

  /// [result] 가 [Failure] 이면 그 예외를 돌려준다.
  AppException failureOf(Result<dynamic>? result) {
    expect(result, isA<Failure<dynamic>>());
    return (result! as Failure<dynamic>).exception;
  }

  /// 왕복 중 교체된 current user — [uid] · [isAnonymous] 만 다르다.
  fb.User buildSwappedUser({required String uid, required bool isAnonymous}) {
    final user = _MockFbUser();
    when(() => user.uid).thenReturn(uid);
    when(() => user.isAnonymous).thenReturn(isAnonymous);
    when(() => user.getIdToken(any())).thenAnswer((_) async => 'swapped-token');
    return user;
  }

  /// 왕복 중 SDK 가 새로 만든 **같은 uid** 의 current user wrapper.
  ///
  /// 실제 SDK 는 `currentUser` 를 읽을 때마다 새 [fb.User] 를 만든다
  /// (firebase_auth 6.7.0 `User._(this, _delegate.currentUser!)`). 연결 성공
  /// 경로까지 진행하므로 `_mapFirebaseUser` 가 읽는 getter 와 `reload` 까지
  /// stub 한다 — [buildSwappedUser] 는 거부 경로 전용이라 이 getter 가 없다.
  fb.User buildSameUidReplacement() {
    final user = _MockFbUser();
    when(() => user.uid).thenReturn('linked-uid');
    when(() => user.isAnonymous).thenReturn(false);
    when(() => user.email).thenReturn('user@example.com');
    when(() => user.emailVerified).thenReturn(true);
    when(() => user.displayName).thenReturn('User');
    when(() => user.photoURL).thenReturn(null);
    when(() => user.metadata).thenReturn(mockMetadata);
    when(() => user.providerData).thenReturn(const []);
    when(() => user.reload()).thenAnswer((_) async {});
    when(() => user.getIdToken(any())).thenAnswer((_) async => 'swapped-token');
    return user;
  }

  test(
    'R1: 1-tap 성공 — payload {idToken, accessToken} · timeout 10s · reload · logout 1',
    () async {
      stubAppSignIn();

      final result = await repository.linkNaverProviderArm();

      expect(result, isA<Success<dynamic>>());
      final captured =
          verify(
                () => mockLinkCallable.call<Map<String, dynamic>>(captureAny()),
              ).captured.single
              as Map<String, dynamic>;
      expect(captured.keys.toSet(), <String>{'idToken', 'accessToken'});
      expect(captured['idToken'], 'caller-fresh-id-token');
      expect(captured['accessToken'], 'naver-app-token');
      final options =
          verify(
                () => mockFunctions.httpsCallable(
                  'linkNaverProvider',
                  options: captureAny(named: 'options'),
                ),
              ).captured.single
              as HttpsCallableOptions;
      expect(options.timeout, const Duration(seconds: 10));
      verify(() => mockCurrentUser.getIdToken(true)).called(1);
      verify(() => mockCurrentUser.reload()).called(1);
      verify(() => mockNaverSdkClient.logout()).called(1);
    },
  );

  test(
    'R2: 웹 성공 — payload {idToken, code, state} · timeout 20s · logout 1',
    () async {
      stubWebSignIn();

      final result = await repository.linkNaverProviderArm();

      expect(result, isA<Success<dynamic>>());
      final captured =
          verify(
                () => mockLinkCallable.call<Map<String, dynamic>>(captureAny()),
              ).captured.single
              as Map<String, dynamic>;
      expect(captured.keys.toSet(), <String>{'idToken', 'code', 'state'});
      expect(captured.containsKey('accessToken'), isFalse);
      expect(captured['idToken'], 'caller-fresh-id-token');
      expect(captured['code'], 'c');
      expect(captured['state'], 's');
      final options =
          verify(
                () => mockFunctions.httpsCallable(
                  'linkNaverProvider',
                  options: captureAny(named: 'options'),
                ),
              ).captured.single
              as HttpsCallableOptions;
      expect(options.timeout, const Duration(seconds: 20));
      verify(() => mockNaverSdkClient.logout()).called(1);
    },
  );

  test(
    'R3: 취소 — signIn null → null · callable · getIdToken 미호출 · logout 1',
    () async {
      when(() => mockNaverSdkClient.signIn()).thenAnswer((_) async => null);

      final result = await repository.linkNaverProviderArm();

      expect(result, isNull);
      verifyNever(() => mockLinkCallable.call<Map<String, dynamic>>(any()));
      verifyNever(() => mockCurrentUser.getIdToken(any()));
      verify(() => mockNaverSdkClient.logout()).called(1);
    },
  );

  group('R4 — 재로그인 유도는 서버 표시(reason)만 (16.9 review WR-01)', () {
    for (final stub in <void Function()>[stubAppSignIn, stubWebSignIn]) {
      test('R4: unauthenticated + reason reauthentication_required → '
          'ReauthenticationRequiredException · logout 1', () async {
        stub();
        stubCallableThrows('unauthenticated', details: reauthDetails);

        final result = await repository.linkNaverProviderArm();

        expect(failureOf(result), isA<ReauthenticationRequiredException>());
        verifyNever(() => mockCurrentUser.reload());
        verify(() => mockNaverSdkClient.logout()).called(1);
      });
    }

    test(
      'R4: permission-denied (idToken uid 불일치) → ReauthenticationRequiredException',
      () async {
        stubAppSignIn();
        stubCallableThrows('permission-denied');

        final result = await repository.linkNaverProviderArm();

        expect(failureOf(result), isA<ReauthenticationRequiredException>());
        verify(() => mockNaverSdkClient.logout()).called(1);
      },
    );

    test('R4: 1-tap unauthenticated · reason 없음 (/v1/nid/me 거부 · App Check 차단) '
        '→ ServiceUnavailable (재로그인 아님)', () async {
      stubAppSignIn();
      stubCallableThrows('unauthenticated');

      final result = await repository.linkNaverProviderArm();

      final exception = failureOf(result);
      expect(exception, isA<ServiceUnavailable>());
      expect(exception, isNot(isA<ReauthenticationRequiredException>()));
      verify(() => mockNaverSdkClient.logout()).called(1);
    });

    test('R4: 웹 unauthenticated · reason 없음 (code 교환 invalid_grant) '
        '→ ServiceUnavailable (재로그인 아님)', () async {
      stubWebSignIn();
      stubCallableThrows('unauthenticated');

      final result = await repository.linkNaverProviderArm();

      expect(failureOf(result), isA<ServiceUnavailable>());
      verify(() => mockNaverSdkClient.logout()).called(1);
    });

    test(
      'R4: unauthenticated · 다른 reason → ServiceUnavailable (fail-closed)',
      () async {
        stubAppSignIn();
        stubCallableThrows(
          'unauthenticated',
          details: const <String, Object?>{'reason': 'other'},
        );

        final result = await repository.linkNaverProviderArm();

        expect(failureOf(result), isA<ServiceUnavailable>());
      },
    );

    test(
      'R4: already-exists + reason reauthentication_required → '
      'AccountAlreadyLinked (code anchor · 재로그인 아님 · iteration 2 IN-01)',
      () async {
        stubAppSignIn();
        stubCallableThrows('already-exists', details: reauthDetails);

        final result = await repository.linkNaverProviderArm();

        final exception = failureOf(result);
        expect(exception, isA<AccountAlreadyLinked>());
        expect(exception, isNot(isA<ReauthenticationRequiredException>()));
        verify(() => mockNaverSdkClient.logout()).called(1);
      },
    );
  });

  test(
    'R5: already-exists → AccountAlreadyLinked (다른 계정 소유) · logout 1',
    () async {
      stubAppSignIn();
      stubCallableThrows('already-exists');

      final result = await repository.linkNaverProviderArm();

      expect(failureOf(result), isA<AccountAlreadyLinked>());
      verify(() => mockNaverSdkClient.logout()).called(1);
    },
  );

  test(
    'R5: already-exists + reason provider_already_linked → '
    'ProviderAlreadyLinkedToThisAccount (다른 Naver 신원이 이미 이 계정에 · IN-03)',
    () async {
      stubAppSignIn();
      stubCallableThrows(
        'already-exists',
        details: const <String, Object?>{'reason': 'provider_already_linked'},
      );

      final result = await repository.linkNaverProviderArm();

      final exception = failureOf(result);
      expect(exception, isA<ProviderAlreadyLinkedToThisAccount>());
      // 의미가 정반대인 「다른 계정 소유」 로 뭉개지지 않는다.
      expect(exception, isNot(isA<AccountAlreadyLinked>()));
      verify(() => mockNaverSdkClient.logout()).called(1);
    },
  );

  group('R6 — _mapFunctionsException 경유', () {
    test('R6: unavailable → NoInternetConnection · logout 1', () async {
      stubAppSignIn();
      stubCallableThrows('unavailable');

      final result = await repository.linkNaverProviderArm();

      expect(failureOf(result), isA<NoInternetConnection>());
      verify(() => mockNaverSdkClient.logout()).called(1);
    });

    test('R6: failed-precondition → ServiceUnavailable · logout 1', () async {
      stubAppSignIn();
      stubCallableThrows('failed-precondition');

      final result = await repository.linkNaverProviderArm();

      expect(failureOf(result), isA<ServiceUnavailable>());
      verify(() => mockNaverSdkClient.logout()).called(1);
    });
  });

  group('R7 — 결정적 실패 UnknownException (WR-06)', () {
    test('R7: 응답 ok:false → UnknownException · reload 미호출', () async {
      stubAppSignIn();
      when(() => mockResult.data).thenReturn(<String, dynamic>{'ok': false});

      final result = await repository.linkNaverProviderArm();

      expect(failureOf(result), isA<UnknownException>());
      verifyNever(() => mockCurrentUser.reload());
      verify(() => mockNaverSdkClient.logout()).called(1);
    });

    test('R7: currentUser null → UnknownException · callable 미호출', () async {
      stubAppSignIn();
      when(() => mockAuth.currentUser).thenReturn(null);

      final result = await repository.linkNaverProviderArm();

      expect(failureOf(result), isA<UnknownException>());
      // 16.9 review IN-02: 결정적 실패는 NAVER 왕복 전에 검사한다.
      verifyNever(() => mockNaverSdkClient.signIn());
      verifyNever(
        () =>
            mockFunctions.httpsCallable(any(), options: any(named: 'options')),
      );
      verify(() => mockNaverSdkClient.logout()).called(1);
    });

    test('R7: 익명 caller → UnknownException · callable 미호출', () async {
      stubAppSignIn();
      when(() => mockCurrentUser.isAnonymous).thenReturn(true);

      final result = await repository.linkNaverProviderArm();

      expect(failureOf(result), isA<UnknownException>());
      // 16.9 review IN-02: 익명 사용자는 브라우저 인증 전에 거부된다.
      verifyNever(() => mockNaverSdkClient.signIn());
      verifyNever(() => mockCurrentUser.getIdToken(any()));
      verifyNever(() => mockLinkCallable.call<Map<String, dynamic>>(any()));
      verify(() => mockNaverSdkClient.logout()).called(1);
    });

    // 16.9 review iteration 2 WR-01: 왕복 전 검사를 통과해도 NAVER 왕복 동안
    // 세션이 바뀌면 결정적 실패다. `User.getIdToken` 은 호출 시점의 native
    // current user 토큰을 만들므로 캡처 객체로 진행하면 안 된다. signIn() mock
    // 안에서 currentUser stub 을 바꿔 arm 내부 읽기 횟수와 무관하게 「왕복 뒤」
    // 시점만 교체한다. 익명 케이스는 uid 를 같게 두어 uid 대조와 독립적으로
    // isAnonymous 분기를 잠근다.
    for (final (label, buildReplacement) in <(String, fb.User? Function())>[
      ('null (sign-out)', () => null),
      (
        '익명 (Splash 익명 재진입)',
        () => buildSwappedUser(uid: 'linked-uid', isAnonymous: true),
      ),
      (
        '다른 uid 정식 계정',
        () => buildSwappedUser(uid: 'other-uid', isAnonymous: false),
      ),
    ]) {
      test('R7: NAVER 왕복 중 current user 가 $label 로 교체 → UnknownException '
          '· getIdToken · callable 미호출 · logout 1 · end 1', () async {
        final replacement = buildReplacement();
        when(() => mockNaverSdkClient.signIn()).thenAnswer((_) async {
          when(() => mockAuth.currentUser).thenReturn(replacement);
          return const NaverAppSignIn(accessToken: 'naver-app-token');
        });

        final result = await repository.linkNaverProviderArm();

        expect(failureOf(result), isA<UnknownException>());
        verify(() => mockNaverSdkClient.signIn()).called(1);
        verifyNever(() => mockCurrentUser.getIdToken(any()));
        if (replacement != null) {
          verifyNever(() => replacement.getIdToken(any()));
        }
        verifyNever(
          () => mockFunctions.httpsCallable(
            any(),
            options: any(named: 'options'),
          ),
        );
        verifyNever(() => mockCurrentUser.reload());
        verify(() => mockNaverSdkClient.logout()).called(1);
        verify(() => mockSocialLinkInProgress.begin()).called(1);
        verify(() => mockSocialLinkInProgress.end()).called(1);
      });
    }

    // 16.9 review iteration 3 IN-05: 재확인은 객체 identity 가 아니라 uid
    // 대조다. 실제 SDK 는 `currentUser` 를 읽을 때마다 새 wrapper 를 만들므로
    // 같은 uid 의 다른 인스턴스는 통과해야 하고, 토큰 · reload 는 캡처 객체가
    // 아니라 재확인한 인스턴스에서 받아야 한다.
    test('R7: NAVER 왕복 중 같은 uid 의 새 인스턴스로 교체 → 연결 성공 '
        '· 새 인스턴스 토큰 · 캡처 객체 getIdToken 미호출', () async {
      final replacement = buildSameUidReplacement();
      when(() => mockNaverSdkClient.signIn()).thenAnswer((_) async {
        when(() => mockAuth.currentUser).thenReturn(replacement);
        return const NaverAppSignIn(accessToken: 'naver-app-token');
      });

      final result = await repository.linkNaverProviderArm();

      expect(result, isA<Success<dynamic>>());
      final captured =
          verify(
                () => mockLinkCallable.call<Map<String, dynamic>>(captureAny()),
              ).captured.single
              as Map<String, dynamic>;
      expect(captured['idToken'], 'swapped-token');
      expect(captured['accessToken'], 'naver-app-token');
      verify(() => replacement.getIdToken(true)).called(1);
      verify(() => replacement.reload()).called(1);
      verifyNever(() => mockCurrentUser.getIdToken(any()));
      verifyNever(() => mockCurrentUser.reload());
      verify(() => mockNaverSdkClient.logout()).called(1);
      verify(() => mockSocialLinkInProgress.begin()).called(1);
      verify(() => mockSocialLinkInProgress.end()).called(1);
    });
  });

  test(
    'R8: signIn 이 ServiceUnavailable throw → 그대로 전달 · callable 미호출 · logout 1',
    () async {
      final sdkError = ServiceUnavailable(cause: StateError('naver-sdk'));
      when(() => mockNaverSdkClient.signIn()).thenThrow(sdkError);

      final result = await repository.linkNaverProviderArm();

      final exception = failureOf(result);
      expect(exception, isA<ServiceUnavailable>());
      expect(identical(exception, sdkError), isTrue);
      verifyNever(() => mockLinkCallable.call<Map<String, dynamic>>(any()));
      verify(() => mockNaverSdkClient.logout()).called(1);
    },
  );

  group('R9 — SocialLinkInProgress begin/end 1:1', () {
    test('R9: 성공 경로 begin 1 · end 1', () async {
      stubAppSignIn();

      await repository.linkNaverProviderArm();

      verify(() => mockSocialLinkInProgress.begin()).called(1);
      verify(() => mockSocialLinkInProgress.end()).called(1);
      verify(() => mockNaverSdkClient.logout()).called(1);
    });

    test('R9: 취소 경로 begin 1 · end 1', () async {
      when(() => mockNaverSdkClient.signIn()).thenAnswer((_) async => null);

      await repository.linkNaverProviderArm();

      verify(() => mockSocialLinkInProgress.begin()).called(1);
      verify(() => mockSocialLinkInProgress.end()).called(1);
      verify(() => mockNaverSdkClient.logout()).called(1);
    });

    test('R9: SDK 오류 경로 begin 1 · end 1', () async {
      when(
        () => mockNaverSdkClient.signIn(),
      ).thenThrow(const ServiceUnavailable());

      await repository.linkNaverProviderArm();

      verify(() => mockSocialLinkInProgress.begin()).called(1);
      verify(() => mockSocialLinkInProgress.end()).called(1);
      verify(() => mockNaverSdkClient.logout()).called(1);
    });
  });
}
