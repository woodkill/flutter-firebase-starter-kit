// Phase 17.5 D-09 · D-12 · D-15 · MAIL-01 — AuthRepository 메일 발송 모드 분기.
//
// 인증 메일은 private seam `_sendVerificationMail` 한 곳에서, 재설정 메일은
// `sendPasswordReset` 한 곳에서 모드(`firebase` | `kit`)로 갈린다.
//
// 인증 메일 재전송 (`sendEmailVerification()`):
//   REPO-01 firebase · 로케일 ko → setLanguageCode('ko') 뒤 FlutterFire 발송
//   REPO-02 firebase · setLanguageCode 실패 → 그래도 발송 · 성공
//   REPO-03 kit · 로케일 ja → getIdToken(true) 뒤 callable {locale: ja} ·
//           FlutterFire 발송 0
//   REPO-04 kit · callable resource-exhausted → TooManyRequests · 대체 발송 0
//   REPO-05 kit · 응답 {ok: false} → UnknownException · 대체 발송 0
//   REPO-06 currentUser null → ServiceUnavailable
//
// fixture 는 합성 값만 쓴다 (`uid-1` · `me@example.com`).

import 'package:cloud_functions/cloud_functions.dart' hide Result;
import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:flutter_facebook_auth/flutter_facebook_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:mocktail/mocktail.dart';

import 'package:flutter_starter_kit/core/config/app_config.dart';
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

/// [result] 가 [Failure] 임을 단언하고 담긴 [AppException] 을 돌려준다.
AppException _failureOf(Result<void> result) {
  expect(result, isA<Failure<void>>());
  return (result as Failure<void>).exception;
}

void main() {
  late _MockFirebaseAuth mockAuth;
  late _MockFbUser mockUser;
  late _MockUserMetadata mockMetadata;
  late _MockFacebookAuth mockFacebookAuth;
  late _MockSocialLinkInProgress mockSocialLinkInProgress;
  late _MockKakaoSdkClient mockKakaoSdkClient;
  late _MockNaverSdkClient mockNaverSdkClient;
  late _MockLineSdkClient mockLineSdkClient;
  late _MockFirebaseFunctions mockFunctions;
  late _MockHttpsCallable mockCallable;
  late _MockHttpsCallableResult mockResult;

  setUpAll(() {
    registerFallbackValue(<String, dynamic>{});
  });

  setUp(() {
    mockAuth = _MockFirebaseAuth();
    mockUser = _MockFbUser();
    mockMetadata = _MockUserMetadata();
    mockFacebookAuth = _MockFacebookAuth();
    mockSocialLinkInProgress = _MockSocialLinkInProgress();
    mockKakaoSdkClient = _MockKakaoSdkClient();
    mockNaverSdkClient = _MockNaverSdkClient();
    mockLineSdkClient = _MockLineSdkClient();
    mockFunctions = _MockFirebaseFunctions();
    mockCallable = _MockHttpsCallable();
    mockResult = _MockHttpsCallableResult();

    // _mapFirebaseUser 가 참조하는 fb.User getter default stub.
    when(() => mockUser.uid).thenReturn('uid-1');
    when(() => mockUser.email).thenReturn('me@example.com');
    when(() => mockUser.emailVerified).thenReturn(false);
    when(() => mockUser.displayName).thenReturn(null);
    when(() => mockUser.photoURL).thenReturn(null);
    when(() => mockUser.isAnonymous).thenReturn(false);
    when(() => mockUser.metadata).thenReturn(mockMetadata);
    when(() => mockMetadata.creationTime).thenReturn(DateTime.utc(2026));
    when(() => mockUser.providerData).thenReturn(<fb.UserInfo>[]);
    when(() => mockAuth.currentUser).thenReturn(mockUser);

    // firebase 모드 경로 default stub.
    when(() => mockAuth.setLanguageCode(any())).thenAnswer((_) async {});
    when(() => mockUser.sendEmailVerification()).thenAnswer((_) async {});

    // kit 모드 경로 default stub — 토큰 갱신 · callable {ok: true}.
    when(() => mockUser.getIdToken(true)).thenAnswer((_) async => 'id-token');
    when(
      () => mockFunctions.httpsCallable(any(), options: any(named: 'options')),
    ).thenReturn(mockCallable);
    when(() => mockResult.data).thenReturn(<String, dynamic>{'ok': true});
    when(
      () => mockCallable.call<Map<String, dynamic>>(any()),
    ).thenAnswer((_) async => mockResult);
  });

  /// [mode] · [languageCode] 를 주입한 [AuthRepository] 를 만든다.
  AuthRepository buildRepository({
    required EmailDeliveryMode mode,
    String languageCode = 'ko',
  }) {
    return AuthRepository(
      mockAuth,
      _MockGoogleSignIn(),
      mockFacebookAuth,
      mockSocialLinkInProgress,
      mockKakaoSdkClient,
      mockFunctions,
      mockNaverSdkClient,
      mockLineSdkClient,
      () async {},
      emailDeliveryMode: mode,
      readLanguageCode: () => languageCode,
    );
  }

  /// kit callable 이 [code] 로 거부되도록 stub 한다.
  void stubCallableThrows(String code) {
    when(() => mockCallable.call<Map<String, dynamic>>(any())).thenThrow(
      FirebaseFunctionsException(code: code, message: 'server-message'),
    );
  }

  group('sendEmailVerification() — 인증 메일 재전송 seam', () {
    test(
      'T-175-REPO-01: firebase · 로케일 ko → setLanguageCode 뒤 FlutterFire 발송',
      () async {
        final repository = buildRepository(mode: EmailDeliveryMode.firebase);

        final result = await repository.sendEmailVerification();

        expect(result, isA<Success<void>>());
        verifyInOrder([
          () => mockAuth.setLanguageCode('ko'),
          () => mockUser.sendEmailVerification(),
        ]);
        verifyNever(
          () => mockFunctions.httpsCallable(
            any(),
            options: any(named: 'options'),
          ),
        );
      },
    );

    test(
      'T-175-REPO-02: firebase · setLanguageCode 실패 → 발송은 계속 · 성공',
      () async {
        when(
          () => mockAuth.setLanguageCode(any()),
        ).thenThrow(fb.FirebaseAuthException(code: 'internal-error'));
        final repository = buildRepository(mode: EmailDeliveryMode.firebase);

        final result = await repository.sendEmailVerification();

        expect(result, isA<Success<void>>());
        verify(() => mockUser.sendEmailVerification()).called(1);
      },
    );

    test('T-175-REPO-03: kit · 로케일 ja → getIdToken(true) 뒤 callable · '
        'FlutterFire 발송 0', () async {
      final repository = buildRepository(
        mode: EmailDeliveryMode.kit,
        languageCode: 'ja',
      );

      final result = await repository.sendEmailVerification();

      expect(result, isA<Success<void>>());
      verifyInOrder([
        () => mockUser.getIdToken(true),
        () => mockFunctions.httpsCallable(
          'sendVerificationMail',
          options: any(named: 'options'),
        ),
        () => mockCallable.call<Map<String, dynamic>>(<String, dynamic>{
          'locale': 'ja',
        }),
      ]);
      verifyNever(() => mockUser.sendEmailVerification());
    });

    test('T-175-REPO-04: kit · callable resource-exhausted → TooManyRequests · '
        '대체 발송 0 (D-12)', () async {
      stubCallableThrows('resource-exhausted');
      final repository = buildRepository(mode: EmailDeliveryMode.kit);

      final result = await repository.sendEmailVerification();

      expect(_failureOf(result), isA<TooManyRequests>());
      verifyNever(() => mockUser.sendEmailVerification());
    });

    test(
      'T-175-REPO-05: kit · 응답 ok != true → UnknownException · 대체 발송 0',
      () async {
        when(() => mockResult.data).thenReturn(<String, dynamic>{'ok': false});
        final repository = buildRepository(mode: EmailDeliveryMode.kit);

        final result = await repository.sendEmailVerification();

        expect(_failureOf(result), isA<UnknownException>());
        verifyNever(() => mockUser.sendEmailVerification());
      },
    );

    test('T-175-REPO-06: currentUser null → ServiceUnavailable', () async {
      when(() => mockAuth.currentUser).thenReturn(null);
      final repository = buildRepository(mode: EmailDeliveryMode.kit);

      final result = await repository.sendEmailVerification();

      expect(_failureOf(result), isA<ServiceUnavailable>());
      verifyNever(
        () =>
            mockFunctions.httpsCallable(any(), options: any(named: 'options')),
      );
    });
  });
}
