// ignore_for_file: lines_longer_than_80_chars
//
// Phase 16 Plan 16-04 Task 4.3 — auth_repository.dart 의 catch path
// account-exists provider enrichment (D-12 wiring) + client cache (Pitfall 5)
// + PII invariant (R7) 검증.

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
import 'package:flutter_starter_kit/features/auth/data/yahoojp_sdk_client.dart';

class _MockFirebaseAuth extends Mock implements fb.FirebaseAuth {}

class _MockGoogleSignIn extends Mock implements GoogleSignIn {}

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

class _FakeHttpsCallableOptions extends Fake implements HttpsCallableOptions {}

void main() {
  late _MockFirebaseAuth mockAuth;
  late _MockGoogleSignIn mockGoogleSignIn;
  late _MockFacebookAuth mockFacebookAuth;
  late _MockSocialLinkInProgress mockSocialLinkInProgress;
  late _MockKakaoSdkClient mockKakaoSdkClient;
  late _MockNaverSdkClient mockNaverSdkClient;
  late _MockLineSdkClient mockLineSdkClient;
  late _MockYahoojpSdkClient mockYahoojpSdkClient;
  late _MockFirebaseFunctions mockFunctions;
  late _MockHttpsCallable mockLookupCallable;
  late AuthRepository repository;
  // R5/R6 cache TTL 검증을 위한 결정성 시간 hook.
  late DateTime fakeNow;

  setUpAll(() {
    registerFallbackValue(<String, dynamic>{});
    registerFallbackValue(_FakeHttpsCallableOptions());
  });

  setUp(() {
    mockAuth = _MockFirebaseAuth();
    mockGoogleSignIn = _MockGoogleSignIn();
    mockFacebookAuth = _MockFacebookAuth();
    mockSocialLinkInProgress = _MockSocialLinkInProgress();
    mockKakaoSdkClient = _MockKakaoSdkClient();
    mockNaverSdkClient = _MockNaverSdkClient();
    mockLineSdkClient = _MockLineSdkClient();
    mockYahoojpSdkClient = _MockYahoojpSdkClient();
    mockFunctions = _MockFirebaseFunctions();
    mockLookupCallable = _MockHttpsCallable();
    fakeNow = DateTime.utc(2026, 5, 29, 10, 0, 0);

    repository = AuthRepository(
      mockAuth,
      mockGoogleSignIn,
      mockFacebookAuth,
      mockSocialLinkInProgress,
      mockKakaoSdkClient,
      mockFunctions,
      mockNaverSdkClient,
      mockLineSdkClient,
      mockYahoojpSdkClient,
      () async {},
      now: () => fakeNow,
    );

    // mockAuth.currentUser default — 비익명 경로.
    when(() => mockAuth.currentUser).thenReturn(null);

    // lookupSignInMethods callable factory default — 모든 테스트가 override 가능.
    when(
      () => mockFunctions.httpsCallable(
        'lookupSignInMethods',
        options: any(named: 'options'),
      ),
    ).thenReturn(mockLookupCallable);
  });

  /// signInWithEmail 의 account-exists path 를 trigger 한다.
  /// 본 테스트는 회귀 대신 enrichment wiring 검증이라 가장 단순한
  /// signInWithEmail 분기를 통해 R1~R4/R7 모두 trigger.
  Future<AccountExistsWithDifferentCredential> triggerAccountExists({
    required String collisionEmail,
  }) async {
    when(
      () => mockAuth.signInWithEmailAndPassword(
        email: any(named: 'email'),
        password: any(named: 'password'),
      ),
    ).thenThrow(
      fb.FirebaseAuthException(
        code: 'account-exists-with-different-credential',
        email: collisionEmail,
      ),
    );

    final result = await repository.signInWithEmail(
      email: collisionEmail,
      password: 'pw12345678',
    );
    final failure = result as Failure<dynamic>;
    return failure.exception as AccountExistsWithDifferentCredential;
  }

  /// lookupSignInMethods callable 응답 stub.
  void stubLookupResponse({String? existingProvider}) {
    final mockResult = _MockHttpsCallableResult();
    when(
      () => mockResult.data,
    ).thenReturn(<String, dynamic>{'existingProvider': existingProvider});
    when(
      () => mockLookupCallable.call<Map<String, dynamic>>(any()),
    ).thenAnswer((_) async => mockResult);
  }

  group('Phase 16 D-12 — catch path → lookupSignInMethods wiring', () {
    test('R1: account-exists + callable success (existingProvider=kakao) → '
        'AccountExistsWithDifferentCredential.existingProvider == kakao', () async {
      stubLookupResponse(existingProvider: 'kakao');

      final ex = await triggerAccountExists(
        collisionEmail: 'user1@example.com',
      );

      expect(ex.existingProvider, AccountProvider.kakao);
      expect(ex.email, 'user1@example.com');
      verify(
        () => mockLookupCallable.call<Map<String, dynamic>>(<String, dynamic>{
          'email': 'user1@example.com',
        }),
      ).called(1);
    });

    test('R2: account-exists + callable returns existingProvider=null → '
        'existingProvider == null (R2 fallback baseline)', () async {
      stubLookupResponse();

      final ex = await triggerAccountExists(
        collisionEmail: 'user2@example.com',
      );

      expect(ex.existingProvider, isNull);
      expect(ex.email, 'user2@example.com');
    });

    test('R3: account-exists + callable throws unauthenticated '
        '(App Check fail) → existingProvider == null (graceful)', () async {
      when(
        () => mockLookupCallable.call<Map<String, dynamic>>(any()),
      ).thenThrow(
        FirebaseFunctionsException(
          code: 'unauthenticated',
          message: 'App Check failed',
        ),
      );

      final ex = await triggerAccountExists(
        collisionEmail: 'user3@example.com',
      );

      expect(ex.existingProvider, isNull);
      expect(ex.email, 'user3@example.com');
    });

    test('R4: account-exists + callable throws resource-exhausted '
        '(rate limit) → existingProvider == null (graceful)', () async {
      when(
        () => mockLookupCallable.call<Map<String, dynamic>>(any()),
      ).thenThrow(
        FirebaseFunctionsException(
          code: 'resource-exhausted',
          message: 'Rate limit exceeded',
        ),
      );

      final ex = await triggerAccountExists(
        collisionEmail: 'user4@example.com',
      );

      expect(ex.existingProvider, isNull);
    });

    test('R5: cache hit — 동일 collisionEmail 두 번째 시도 (TTL 내) → '
        'callable 호출 0회 (Pitfall 5 cache)', () async {
      stubLookupResponse(existingProvider: 'kakao');

      // 1st trigger
      await triggerAccountExists(collisionEmail: 'cache@example.com');
      // 2nd trigger — TTL 내 (시간 진행 0)
      await triggerAccountExists(collisionEmail: 'cache@example.com');

      // callable 은 정확히 1 번만 호출됨.
      verify(
        () => mockLookupCallable.call<Map<String, dynamic>>(any()),
      ).called(1);
    });

    test('R6: cache TTL 만료 (5분+1초 경과) → callable 재호출', () async {
      stubLookupResponse(existingProvider: 'naver');

      // 1st trigger
      await triggerAccountExists(collisionEmail: 'ttl@example.com');
      // TTL 5분 + 1초 경과
      fakeNow = fakeNow.add(const Duration(minutes: 5, seconds: 1));
      // 2nd trigger
      await triggerAccountExists(collisionEmail: 'ttl@example.com');

      // callable 은 두 번 호출됨.
      verify(
        () => mockLookupCallable.call<Map<String, dynamic>>(any()),
      ).called(2);
    });

    test('R7: PII invariant — callable fail 시에도 debugPrint 가 '
        'collisionEmail 본문 미포함', () async {
      final logs = <String>[];
      final originalPrint = debugPrint;
      debugPrint = (String? message, {int? wrapWidth}) {
        if (message != null) logs.add(message);
      };

      try {
        when(
          () => mockLookupCallable.call<Map<String, dynamic>>(any()),
        ).thenThrow(
          FirebaseFunctionsException(
            code: 'unauthenticated',
            message: 'App Check failed',
          ),
        );

        await triggerAccountExists(
          collisionEmail: 'pii-sensitive@example.com',
        );

        // 모든 debugPrint payload 에 collisionEmail 본문 (local-part / domain
        // 어느 쪽도) 포함되지 않음 invariant (T-16-NEW-07 sentinel).
        for (final log in logs) {
          expect(log, isNot(contains('pii-sensitive')));
          expect(log, isNot(contains('pii-sensitive@example.com')));
        }
      } finally {
        debugPrint = originalPrint;
      }
    });

    test('R8 (WR-05): 만료 entry 는 read 시점에 evict — 만료 후 재조회 시 '
        'callable 재호출 (read-side eviction)', () async {
      stubLookupResponse(existingProvider: 'kakao');

      // 1st trigger — cache 적재.
      await triggerAccountExists(collisionEmail: 'evict@example.com');
      // TTL 초과 경과 → 다음 read 가 만료 entry 를 evict 후 재조회.
      fakeNow = fakeNow.add(const Duration(minutes: 5, seconds: 1));
      await triggerAccountExists(collisionEmail: 'evict@example.com');
      // evict 이후 동일 email 재조회 — 새 entry 가 TTL 내이므로 cache hit.
      await triggerAccountExists(collisionEmail: 'evict@example.com');

      // 호출 2회: 최초 + 만료 후 재호출 (3번째는 fresh entry cache hit).
      verify(
        () => mockLookupCallable.call<Map<String, dynamic>>(any()),
      ).called(2);
    });

    test('R9 (WR-05): cache 는 size cap (64) 으로 bound — 한도 초과 시 가장 '
        '오래된 entry evict 되어 재조회 시 callable 재호출', () async {
      stubLookupResponse(existingProvider: 'kakao');

      // 가장 먼저 적재할 email — 이후 cap 초과로 evict 대상.
      await triggerAccountExists(collisionEmail: 'oldest@example.com');

      // cap(64) 을 채우도록 추가 64 distinct email 적재 → oldest evict.
      for (var i = 0; i < 64; i++) {
        await triggerAccountExists(collisionEmail: 'fill$i@example.com');
      }

      // oldest 는 evict 되어 재조회 시 callable 재호출 (cache miss).
      clearInteractions(mockLookupCallable);
      await triggerAccountExists(collisionEmail: 'oldest@example.com');

      verify(
        () => mockLookupCallable.call<Map<String, dynamic>>(any()),
      ).called(1);
    });
  });
}
