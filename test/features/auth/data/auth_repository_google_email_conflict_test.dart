// debug google-gmail-email-arm-merge — signInWithGoogle 익명 승격 충돌의
// `email-already-in-use` arm 계약.
//
// **서버 계약 (단위 테스트로 재현 불가 — 근거만 기록):**
// Google 은 @gmail.com 주소에 한해 Firebase trusted provider 다. 같은 email 의
// 기존 계정이 있을 때 **새 로그인**(`signInWithCredential`)을 하면 서버가
// account-exists 로 거부하지 않고 google.com 을 그 계정에 자동 연결하면서
// displayName · photoUrl 을 Google 값으로 교체하고 세션을 그 계정으로 바꾼다.
// - firebase.google.com/docs/auth/users 「Verified email addresses」 — trusted
//   provider 「Google (for @gmail.com addresses)」, 자동 연결 규칙은 "signs in"
//   대상.
// - iOS 실기기 실측(2026-09-17, iPhone Air · HEAD f44d97de) — 이 arm 의 새
//   로그인 직후 원장에서 같은 email 기존 계정의 providerUserInfo 에 google.com
//   추가 · displayName · photoUrl 교체 · 세션 전환, 시트 · 배너 0
//   (.planning/debug/google-gmail-email-arm-merge.md Evidence 14).
//
// 그래서 이 arm 의 불변식은 「새 로그인 호출 0」 이다. mock 은 새 로그인에
// 성공을 돌려줄 수 있지만 production 에선 그 성공이 곧 자동 합류이므로,
// 결과값이 아니라 **호출 자체의 부재**를 단언한다.
//
// **fixture 근거 — 플랫폼마다 payload 가 다르다:**
// - iOS: Firebase iOS SDK 12.12.0 `AuthBackend.swift`
//   `case "EMAIL_EXISTS": return AuthErrorUtils.emailAlreadyInUseError(email: nil)`
//   → email · credential 모두 null (provider 무관).
// - Android: firebase-auth 24.0.1 이 verifyAssertion 응답의 email · credential
//   을 FirebaseAuthUserCollisionException 에 싣고, firebase_auth 플러그인이
//   `FirebaseAuthException.email` · `credential` 로 넘긴다 (소스 분석 — 런타임
//   미실측).
// 두 fixture 를 모두 고정해 어느 플랫폼에서도 계정 연결 시트 입력(email ·
// pendingCredential)이 채워짐을 보장한다.

import 'package:cloud_functions/cloud_functions.dart' hide Result;
import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:flutter/foundation.dart' show DebugPrintCallback, debugPrint;
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
import 'package:flutter_starter_kit/features/auth/data/yahoojp_sdk_client.dart';
import 'package:flutter_starter_kit/features/auth/domain/user.dart';

class _MockFirebaseAuth extends Mock implements fb.FirebaseAuth {}

class _MockFbUser extends Mock implements fb.User {}

class _MockGoogleSignIn extends Mock implements GoogleSignIn {}

class _MockGoogleSignInAccount extends Mock implements GoogleSignInAccount {}

class _MockFacebookAuth extends Mock implements FacebookAuth {}

class _MockSocialLinkInProgress extends Mock implements SocialLinkInProgress {}

class _MockKakaoSdkClient extends Mock implements KakaoSdkClient {}

class _MockNaverSdkClient extends Mock implements NaverSdkClient {}

class _MockLineSdkClient extends Mock implements LineSdkClient {}

class _MockYahoojpSdkClient extends Mock implements YahoojpSdkClient {}

class _MockFirebaseFunctions extends Mock implements FirebaseFunctions {}

class _MockHttpsCallable extends Mock implements HttpsCallable {}

class _MockHttpsCallableResult extends Mock
    implements HttpsCallableResult<Map<String, dynamic>> {}

class _FakeAuthCredential extends Fake implements fb.AuthCredential {}

class _FakeHttpsCallableOptions extends Fake implements HttpsCallableOptions {}

/// Google 계정 선택 결과로 받은 로컬 idToken (fixture).
const _localIdToken = 'google-id-token-fixture';

/// Google 계정 선택 결과의 로컬 email (fixture).
const _localEmail = 'local-google-fixture@gmail.com';

void main() {
  late _MockFirebaseAuth mockAuth;
  late _MockFbUser mockAnonymous;
  late _MockGoogleSignIn mockGoogleSignIn;
  late _MockGoogleSignInAccount mockAccount;
  late _MockSocialLinkInProgress mockSocialLinkInProgress;
  late _MockFirebaseFunctions mockFunctions;
  late _MockHttpsCallable mockLookupCallable;
  late AuthRepository repository;
  late List<String> logs;
  late DebugPrintCallback originalDebugPrint;

  setUpAll(() {
    registerFallbackValue(_FakeAuthCredential());
    registerFallbackValue(const <String>[]);
    registerFallbackValue(<String, dynamic>{});
    registerFallbackValue(_FakeHttpsCallableOptions());
  });

  setUp(() {
    mockAuth = _MockFirebaseAuth();
    mockAnonymous = _MockFbUser();
    mockGoogleSignIn = _MockGoogleSignIn();
    mockAccount = _MockGoogleSignInAccount();
    mockSocialLinkInProgress = _MockSocialLinkInProgress();
    mockFunctions = _MockFirebaseFunctions();
    mockLookupCallable = _MockHttpsCallable();

    repository = AuthRepository(
      mockAuth,
      mockGoogleSignIn,
      _MockFacebookAuth(),
      mockSocialLinkInProgress,
      _MockKakaoSdkClient(),
      mockFunctions,
      _MockNaverSdkClient(),
      _MockLineSdkClient(),
      _MockYahoojpSdkClient(),
      () async {},
    );

    when(
      () => mockAccount.authentication,
    ).thenReturn(const GoogleSignInAuthentication(idToken: _localIdToken));
    when(() => mockAccount.email).thenReturn(_localEmail);
    when(
      () => mockGoogleSignIn.authenticate(scopeHint: any(named: 'scopeHint')),
    ).thenAnswer((_) async => mockAccount);

    when(() => mockAnonymous.isAnonymous).thenReturn(true);
    when(() => mockAuth.currentUser).thenReturn(mockAnonymous);
    // 익명 삭제는 성공 stub, 새 로그인은 StateError stub 이다. 새 로그인이
    // 불리면 흐름이 account-exists 로 끝나지 못해 결과 단언이 먼저 깨지고,
    // verifyNever 가 호출 자체를 한 번 더 잡는다.
    when(() => mockAnonymous.delete()).thenAnswer((_) async {});
    when(
      () => mockAuth.signInWithCredential(any()),
    ).thenThrow(StateError('새 로그인 호출 금지 — 자동 합류 경로'));
    when(
      () => mockFunctions.httpsCallable(
        'lookupSignInMethods',
        options: any(named: 'options'),
      ),
    ).thenReturn(mockLookupCallable);

    logs = <String>[];
    originalDebugPrint = debugPrint;
    debugPrint = (String? message, {int? wrapWidth}) {
      if (message != null) logs.add(message);
    };
  });

  tearDown(() {
    debugPrint = originalDebugPrint;
  });

  /// `lookupSignInMethods` 응답의 existingProvider slug 를 stub 한다.
  void stubLookup(String? slug) {
    final mockLookupResult = _MockHttpsCallableResult();
    when(
      () => mockLookupResult.data,
    ).thenReturn(<String, dynamic>{'existingProvider': slug});
    when(
      () => mockLookupCallable.call<Map<String, dynamic>>(any()),
    ).thenAnswer((_) async => mockLookupResult);
  }

  /// 링크 실패 예외를 stub 하고 [AuthRepository.signInWithGoogle] 결과의
  /// [AccountExistsWithDifferentCredential] 을 돌려준다.
  Future<AccountExistsWithDifferentCredential> triggerEmailConflict({
    String? email,
    fb.AuthCredential? credential,
  }) async {
    when(() => mockAnonymous.linkWithCredential(any())).thenThrow(
      fb.FirebaseAuthException(
        code: 'email-already-in-use',
        email: email,
        credential: credential,
      ),
    );

    final result = await repository.signInWithGoogle();

    expect(result, isA<Failure<User>>());
    final exception = (result! as Failure<User>).exception;
    expect(exception, isA<AccountExistsWithDifferentCredential>());
    return exception as AccountExistsWithDifferentCredential;
  }

  /// 자동 합류 방아쇠(새 로그인) · 익명 손실이 모두 없었음을 단언한다.
  void verifyNoMergeTrigger() {
    verifyNever(() => mockAuth.signInWithCredential(any()));
    verifyNever(() => mockAnonymous.delete());
  }

  /// pendingCredential 이 로컬 Google 계정 선택으로 만든 credential 인지.
  final isLocalGoogleCredential = isA<fb.OAuthCredential>()
      .having((c) => c.providerId, 'providerId', 'google.com')
      .having((c) => c.idToken, 'idToken', _localIdToken);

  group('signInWithGoogle email-already-in-use — 새 로그인 없이 계정 연결 안내', () {
    test('iOS 실측 fixture(email · credential null): 로컬 email 로 기존 provider 를 '
        '조회하고 로컬 credential 을 보존한다 · 새 로그인 · 익명 삭제 0회', () async {
      stubLookup('apple');

      final exception = await triggerEmailConflict();

      expect(exception.email, _localEmail);
      expect(exception.existingProvider, AccountProvider.apple);
      expect(exception.pendingCredential, isLocalGoogleCredential);
      verify(
        () => mockLookupCallable.call<Map<String, dynamic>>(<String, dynamic>{
          'email': _localEmail,
        }),
      ).called(1);
      verifyNoMergeTrigger();
      verify(() => mockSocialLinkInProgress.begin()).called(1);
      verify(() => mockSocialLinkInProgress.end()).called(1);
    });

    test('Android fixture(email · credential 동봉): 서버 충돌 email 을 우선하고 '
        'pendingCredential 은 로컬 credential 을 쓴다', () async {
      // 실제 payload 에서는 두 email 이 같다. 우선순위를 관측하려고 fixture 만
      // 다른 문자열을 쓴다.
      stubLookup('naver');

      final exception = await triggerEmailConflict(
        email: 'server-collision-fixture@gmail.com',
        credential: _FakeAuthCredential(),
      );

      expect(exception.email, 'server-collision-fixture@gmail.com');
      expect(exception.existingProvider, AccountProvider.naver);
      expect(exception.pendingCredential, isLocalGoogleCredential);
      verify(
        () => mockLookupCallable.call<Map<String, dynamic>>(<String, dynamic>{
          'email': 'server-collision-fixture@gmail.com',
        }),
      ).called(1);
      verifyNoMergeTrigger();
    });

    test('빈 문자열 email 은 없는 것으로 보고 로컬 email 로 조회한다', () async {
      stubLookup('kakao');

      final exception = await triggerEmailConflict(email: '');

      expect(exception.email, _localEmail);
      expect(exception.existingProvider, AccountProvider.kakao);
      verify(
        () => mockLookupCallable.call<Map<String, dynamic>>(<String, dynamic>{
          'email': _localEmail,
        }),
      ).called(1);
      verifyNoMergeTrigger();
    });

    test('기존 계정에 식별 가능한 provider 가 없으면(lookup null) unknown 안내로 '
        '끝나고 여전히 새 로그인 0회', () async {
      stubLookup(null);

      final exception = await triggerEmailConflict();

      expect(exception.email, _localEmail);
      expect(exception.existingProvider, isNull);
      expect(exception.pendingCredential, isLocalGoogleCredential);
      verifyNoMergeTrigger();
    });

    test('debug 로그는 code 와 bool 만 싣는다 (PII invariant)', () async {
      stubLookup(null);

      await triggerEmailConflict();

      final googleLogs = logs
          .where((l) => l.startsWith('AuthRepository.signInWithGoogle: '))
          .toList();
      expect(googleLogs, hasLength(1));
      expect(
        googleLogs.single,
        'AuthRepository.signInWithGoogle: email-already-in-use — 익명 유지 + '
        '자동 합류 차단 (hasEmail: false, hasCredential: false)',
      );
      for (final log in logs) {
        expect(log, isNot(contains('local-google-fixture')));
        expect(log, isNot(contains(_localIdToken)));
      }
    });

    test(
      'Android fixture 로그는 payload 존재를 bool 로만 남긴다 (PII invariant)',
      () async {
        stubLookup(null);

        await triggerEmailConflict(
          email: 'pii-google-payload@gmail.com',
          credential: _FakeAuthCredential(),
        );

        final googleLogs = logs
            .where((l) => l.startsWith('AuthRepository.signInWithGoogle: '))
            .toList();
        expect(googleLogs, hasLength(1));
        expect(
          googleLogs.single,
          'AuthRepository.signInWithGoogle: email-already-in-use — 익명 유지 + '
          '자동 합류 차단 (hasEmail: true, hasCredential: true)',
        );
        for (final log in logs) {
          expect(log, isNot(contains('pii-google-payload')));
        }
      },
    );
  });
}
