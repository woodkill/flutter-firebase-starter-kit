// ignore_for_file: lines_longer_than_80_chars
//
// Phase 16 Plan 16-09 Task 1 — reactive Custom Token account linking.
//
// `linkCustomTokenProviderArm({required AccountProvider targetProvider})` 검증.
// Custom Token 충돌(Kakao/LINE) 시 sheet 버튼 탭 → target provider 토큰
// fresh 재획득 + caller fresh ID Token(getIdToken(true)) + deployed
// `linkCustomTokenProvider` callable 호출({idToken, targetProvider,
// targetProviderToken, nonce} → {ok:true}) 로 실제 link.
//
// 8 behavior:
//   T1: line target → LineSdkClient.signIn() fresh 토큰 → getIdToken(true) →
//       httpsCallable('linkCustomTokenProvider')(...) → {ok:true} → success
//   T2: target SDK signIn 사용자 취소(null) → null (silent cancel, link 미호출)
//   T3: callable 'unauthenticated'/'errorReauthenticationRequired' →
//       ReauthenticationRequiredException
//   T4: callable 'already-exists'/'errorAccountAlreadyLinked' → AccountAlreadyLinked
//   T5: callable 'failed-precondition'/'errorAnonymousLinkNotAllowed' → 적절 매핑
//   T6 (PII sentinel): catch path debugPrint 가 idToken/targetProviderToken/email
//       본문 미포함 (code/runtimeType-only)
//   T7 (token freshness): callable payload idToken 은 getIdToken(true) 결과
//       (forceRefresh=true 호출 검증)
//   T8 (1회성 토큰): target SDK 가 finally logout 호출 (verify logout 1회)

import 'package:cloud_functions/cloud_functions.dart' hide Result;
import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:flutter/foundation.dart';
import 'package:flutter_facebook_auth/flutter_facebook_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:mocktail/mocktail.dart';

import 'package:flutter_starter_kit/core/auth/provider_id.dart';
import 'package:flutter_starter_kit/core/error/app_exception.dart';
import 'package:flutter_starter_kit/core/error/result.dart';
import 'package:flutter_starter_kit/features/auth/application/social_link_in_progress.dart';
import 'package:flutter_starter_kit/features/auth/data/auth_repository.dart';
import 'package:flutter_starter_kit/features/auth/data/kakao_sdk_client.dart';
import 'package:flutter_starter_kit/features/auth/data/line_sdk_client.dart';
import 'package:flutter_starter_kit/features/auth/data/naver_sdk_client.dart';

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
  late _MockGoogleSignIn mockGoogleSignIn;
  late _MockFacebookAuth mockFacebookAuth;
  late _MockSocialLinkInProgress mockSocialLinkInProgress;
  late _MockKakaoSdkClient mockKakaoSdkClient;
  late _MockNaverSdkClient mockNaverSdkClient;
  late _MockLineSdkClient mockLineSdkClient;
  late _MockFirebaseFunctions mockFunctions;
  late _MockHttpsCallable mockLinkCallable;
  late _MockFbUser mockCurrentUser;
  late _MockUserMetadata mockMetadata;
  late AuthRepository repository;

  setUpAll(() {
    registerFallbackValue(<String, dynamic>{});
  });

  setUp(() {
    mockAuth = _MockFirebaseAuth();
    mockGoogleSignIn = _MockGoogleSignIn();
    mockFacebookAuth = _MockFacebookAuth();
    mockSocialLinkInProgress = _MockSocialLinkInProgress();
    mockKakaoSdkClient = _MockKakaoSdkClient();
    mockNaverSdkClient = _MockNaverSdkClient();
    mockLineSdkClient = _MockLineSdkClient();
    mockFunctions = _MockFirebaseFunctions();
    mockLinkCallable = _MockHttpsCallable();
    mockCurrentUser = _MockFbUser();
    mockMetadata = _MockUserMetadata();

    repository = AuthRepository(
      mockAuth,
      mockGoogleSignIn,
      mockFacebookAuth,
      mockSocialLinkInProgress,
      mockKakaoSdkClient,
      mockFunctions,
      mockNaverSdkClient,
      mockLineSdkClient,
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

    // 1회성 토큰 finally logout default stub.
    when(() => mockKakaoSdkClient.logout()).thenAnswer((_) async {});
    when(() => mockLineSdkClient.logout()).thenAnswer((_) async {});

    // linkCustomTokenProvider callable default wiring — {ok:true}.
    when(
      () => mockFunctions.httpsCallable(
        'linkCustomTokenProvider',
        options: any(named: 'options'),
      ),
    ).thenReturn(mockLinkCallable);
    final mockResult = _MockHttpsCallableResult();
    when(() => mockResult.data).thenReturn(<String, dynamic>{'ok': true});
    when(
      () => mockLinkCallable.call<Map<String, dynamic>>(any()),
    ).thenAnswer((_) async => mockResult);
  });

  /// LINE target signIn 성공 fixture — fresh idToken + nonce 재획득.
  void stubLineSignInSuccess() {
    when(() => mockLineSdkClient.signIn()).thenAnswer(
      (_) async => const LineSignInResult(
        idToken: 'line-fresh-id-token',
        nonce: 'line-nonce',
      ),
    );
  }

  group('T1 — linkCustomTokenProviderArm(line) 실제 link', () {
    test(
      'LINE signIn fresh 토큰 → callable {idToken, line, targetProviderToken, nonce} → {ok:true} → Result.success',
      () async {
        stubLineSignInSuccess();

        final result = await repository.linkCustomTokenProviderArm(
          targetProvider: AccountProvider.line,
        );

        expect(result, isA<Success<dynamic>>());
        // deployed contract: targetProvider slug 'line' + fresh target token.
        final captured =
            verify(
                  () =>
                      mockLinkCallable.call<Map<String, dynamic>>(captureAny()),
                ).captured.single
                as Map<String, dynamic>;
        expect(captured['targetProvider'], 'line');
        expect(captured['targetProviderToken'], 'line-fresh-id-token');
        expect(captured['nonce'], 'line-nonce');
        expect(captured['idToken'], 'caller-fresh-id-token');
      },
    );
  });

  group('T2 — target SDK 사용자 취소 → null (silent)', () {
    test('LINE signIn null → null + callable 미호출', () async {
      when(() => mockLineSdkClient.signIn()).thenAnswer((_) async => null);

      final result = await repository.linkCustomTokenProviderArm(
        targetProvider: AccountProvider.line,
      );

      expect(result, isNull);
      verifyNever(() => mockLinkCallable.call<Map<String, dynamic>>(any()));
    });
  });

  group(
    'T3 — callable unauthenticated → ReauthenticationRequiredException',
    () {
      test('unauthenticated → ReauthenticationRequiredException', () async {
        stubLineSignInSuccess();
        when(
          () => mockLinkCallable.call<Map<String, dynamic>>(any()),
        ).thenThrow(
          FirebaseFunctionsException(
            code: 'unauthenticated',
            message: 'errorReauthenticationRequired',
          ),
        );

        final result = await repository.linkCustomTokenProviderArm(
          targetProvider: AccountProvider.line,
        );

        expect(result, isA<Failure<dynamic>>());
        final failure = result! as Failure<dynamic>;
        expect(failure.exception, isA<ReauthenticationRequiredException>());
      });
    },
  );

  group('T4 — callable already-exists → AccountAlreadyLinked', () {
    test('already-exists → AccountAlreadyLinked', () async {
      stubLineSignInSuccess();
      when(() => mockLinkCallable.call<Map<String, dynamic>>(any())).thenThrow(
        FirebaseFunctionsException(
          code: 'already-exists',
          message: 'errorAccountAlreadyLinked',
        ),
      );

      final result = await repository.linkCustomTokenProviderArm(
        targetProvider: AccountProvider.line,
      );

      expect(result, isA<Failure<dynamic>>());
      final failure = result! as Failure<dynamic>;
      expect(failure.exception, isA<AccountAlreadyLinked>());
    });
  });

  group('T5 — callable failed-precondition (anonymous) → 적절 매핑', () {
    test('failed-precondition → AppException Failure', () async {
      stubLineSignInSuccess();
      when(() => mockLinkCallable.call<Map<String, dynamic>>(any())).thenThrow(
        FirebaseFunctionsException(
          code: 'failed-precondition',
          message: 'errorAnonymousLinkNotAllowed',
        ),
      );

      final result = await repository.linkCustomTokenProviderArm(
        targetProvider: AccountProvider.line,
      );

      expect(result, isA<Failure<dynamic>>());
      final failure = result! as Failure<dynamic>;
      expect(failure.exception, isA<AppException>());
    });
  });

  group('T6 — PII sentinel (catch path 토큰/email 본문 미포함)', () {
    test('callable throw 시 debugPrint 본문에 토큰/email 미포함', () async {
      stubLineSignInSuccess();
      // 임의의 비-Functions 예외 → catch (Object) path 의 debugPrint 경유.
      when(
        () => mockLinkCallable.call<Map<String, dynamic>>(any()),
      ).thenThrow(Exception('boom'));

      final logs = <String?>[];
      final original = debugPrint;
      debugPrint = (String? message, {int? wrapWidth}) => logs.add(message);
      addTearDown(() => debugPrint = original);

      final result = await repository.linkCustomTokenProviderArm(
        targetProvider: AccountProvider.line,
      );

      expect(result, isA<Failure<dynamic>>());
      final joined = logs.whereType<String>().join('\n');
      expect(joined.contains('line-fresh-id-token'), isFalse);
      expect(joined.contains('caller-fresh-id-token'), isFalse);
      expect(joined.contains('user@example.com'), isFalse);
    });
  });

  group('T7 — token freshness (getIdToken(true))', () {
    test('callable payload idToken 은 getIdToken(forceRefresh=true) 결과', () async {
      stubLineSignInSuccess();

      await repository.linkCustomTokenProviderArm(
        targetProvider: AccountProvider.line,
      );

      // forceRefresh=true 로 caller ID Token 발급 (server-side auth_time boundary).
      verify(() => mockCurrentUser.getIdToken(true)).called(1);
    });
  });

  group('T8 — 1회성 토큰 (finally logout)', () {
    test('LINE link 성공 후 LineSdkClient.logout 1회 호출', () async {
      stubLineSignInSuccess();

      await repository.linkCustomTokenProviderArm(
        targetProvider: AccountProvider.line,
      );

      verify(() => mockLineSdkClient.logout()).called(1);
      // race-fix invariant 보존.
      verify(() => mockSocialLinkInProgress.begin()).called(1);
      verify(() => mockSocialLinkInProgress.end()).called(1);
    });
  });

  group('T9 — WR-06: 익명 caller client-side 가드 (defense-in-depth)', () {
    test('currentUser.isAnonymous == true → Result.failure(UnknownException) + '
        'getIdToken/callable 미호출 (서버 failed-precondition 의존 회피)', () async {
      stubLineSignInSuccess();
      // 익명 caller — upstream 로직 오류 시뮬레이션.
      when(() => mockCurrentUser.isAnonymous).thenReturn(true);

      final result = await repository.linkCustomTokenProviderArm(
        targetProvider: AccountProvider.line,
      );

      expect(result, isA<Failure<dynamic>>());
      final failure = result! as Failure<dynamic>;
      // 2차 리뷰 WR-06: 결정적 실패이므로 transientFailure ("잠시 후 다시
      // 시도") 로 안내되면 안 된다. ServiceUnavailable 이면 하류
      // _mapLinkFailure 가 transientFailure 로 떨어뜨려 무한 재시도 루프를
      // 유도한다 (매 시도 SDK OAuth 왕복 포함).
      expect(failure.exception, isA<UnknownException>());
      expect(failure.exception, isNot(isA<ServiceUnavailable>()));
      // client 에서 loud fail — callable round-trip / caller token 발급 회피.
      verifyNever(() => mockCurrentUser.getIdToken(any()));
      verifyNever(() => mockLinkCallable.call<Map<String, dynamic>>(any()));
      // race-fix invariant + 1회성 토큰 logout 보존.
      verify(() => mockSocialLinkInProgress.begin()).called(1);
      verify(() => mockSocialLinkInProgress.end()).called(1);
      verify(() => mockLineSdkClient.logout()).called(1);
    });
  });

  group('T10 — WR-06: 결정적 실패는 transientFailure 로 분류되지 않는다', () {
    test('callable 응답 ok != true → Result.failure(UnknownException) '
        '(재시도 유도 문구 회피)', () async {
      stubLineSignInSuccess();
      when(() => mockCurrentUser.isAnonymous).thenReturn(false);
      final notOkResult = _MockHttpsCallableResult();
      when(() => notOkResult.data).thenReturn(<String, dynamic>{'ok': false});
      when(
        () => mockLinkCallable.call<Map<String, dynamic>>(any()),
      ).thenAnswer((_) async => notOkResult);

      final result = await repository.linkCustomTokenProviderArm(
        targetProvider: AccountProvider.line,
      );

      expect(result, isA<Failure<dynamic>>());
      final failure = result! as Failure<dynamic>;
      // 서버 계약 위반 — 재시도로 해소되지 않는다.
      expect(failure.exception, isA<UnknownException>());
      expect(failure.exception, isNot(isA<ServiceUnavailable>()));
    });
  });
}
