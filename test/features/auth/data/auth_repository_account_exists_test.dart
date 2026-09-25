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
// ignore: unused_import -- 16-13 Custom Token group 의 Failure<User> 캐스트용.
import 'package:flutter_starter_kit/features/auth/domain/user.dart';
import 'package:flutter_starter_kit/features/auth/data/line_sdk_client.dart';
import 'package:flutter_starter_kit/features/auth/data/naver_sdk_client.dart';

class _MockFirebaseAuth extends Mock implements fb.FirebaseAuth {}

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

class _FakeHttpsCallableOptions extends Fake implements HttpsCallableOptions {}

void main() {
  late _MockFirebaseAuth mockAuth;
  late _MockGoogleSignIn mockGoogleSignIn;
  late _MockFacebookAuth mockFacebookAuth;
  late _MockSocialLinkInProgress mockSocialLinkInProgress;
  late _MockKakaoSdkClient mockKakaoSdkClient;
  late _MockNaverSdkClient mockNaverSdkClient;
  late _MockLineSdkClient mockLineSdkClient;
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
    test(
      'R1: account-exists + callable success (existingProvider=kakao) → '
      'AccountExistsWithDifferentCredential.existingProvider == kakao',
      () async {
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
      },
    );

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

        await triggerAccountExists(collisionEmail: 'pii-sensitive@example.com');

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

    // WR-07 (Phase 7 review): AuthRepository 는 keepAlive 라 앱 생명주기 내내
    // 동일 인스턴스이고 cache key 는 평문 이메일이다. 로그아웃/계정 전환에서
    // 무효화하지 않으면 (1) 이전 사용자 이메일이 최대 TTL 5분 잔류하고
    // (2) 같은 window 안에서 stale existingProvider 응답이 재사용된다.
    test('WR-07: signOut() 이 _accountExistsCache 를 비운다 — 계정 경계에서 '
        'PII 잔류 + stale provider 응답 차단', () async {
      stubLookupResponse(existingProvider: 'kakao');
      when(() => mockAuth.signOut()).thenAnswer((_) async {});

      // 사용자 A 세션 — cache 적재 (callable 1회).
      await triggerAccountExists(collisionEmail: 'a@example.com');
      verify(
        () => mockLookupCallable.call<Map<String, dynamic>>(any()),
      ).called(1);

      // 로그아웃 — 계정 경계.
      await repository.signOut();

      // 사용자 B 세션에서 동일 이메일 충돌 — TTL 은 남아 있으나 cache 가
      // 비워졌으므로 callable 이 다시 호출되어야 한다.
      clearInteractions(mockLookupCallable);
      await triggerAccountExists(collisionEmail: 'a@example.com');
      verify(
        () => mockLookupCallable.call<Map<String, dynamic>>(any()),
      ).called(1);
    });
  });

  // 16-13 (A4 gap closure) — Custom Token already-exists path 의
  // _mapFunctionsException details 추출. 서버(16-13 Task 1)가 HttpsError
  // details.existingProvider 를 전달하므로 client 가 이를 읽어
  // AccountExistsWithDifferentCredential.existingProvider 에 매핑한다.
  // native side(triggerAccountExists → lookupSignInMethods enrichment)와 달리
  // Custom Token side 는 server details 직독 (추가 callable round-trip 0).
  group('16-13 — Custom Token _mapFunctionsException details 추출', () {
    late _MockHttpsCallable mockCtCallable;

    setUp(() {
      mockCtCallable = _MockHttpsCallable();
      // kakao Custom Token sign-in path 의 SDK + finally logout stub.
      when(() => mockKakaoSdkClient.signIn()).thenAnswer(
        (_) async => const KakaoSignInResult(idToken: 'IDT', nonce: 'NONCE'),
      );
      when(() => mockKakaoSdkClient.logout()).thenAnswer((_) async {});
      when(
        () => mockFunctions.httpsCallable(
          'kakaoCustomToken',
          options: any(named: 'options'),
        ),
      ).thenReturn(mockCtCallable);
    });

    /// kakao Custom Token sign-in 을 trigger 하되 callable 이
    /// [details] 를 가진 already-exists [FirebaseFunctionsException] 을 throw
    /// 하도록 stub 한다 → [AuthRepository._mapFunctionsException] 경유.
    Future<AccountExistsWithDifferentCredential> triggerCustomTokenExists({
      required Object? details,
      String code = 'already-exists',
    }) async {
      when(() => mockCtCallable.call<Map<String, dynamic>>(any())).thenThrow(
        FirebaseFunctionsException(
          code: code,
          message: 'errorAccountExistsWithDifferentCredential',
          details: details,
        ),
      );

      final result = await repository.signInWithKakao();
      final failure = result! as Failure<User>;
      return failure.exception as AccountExistsWithDifferentCredential;
    }

    test(
      'CT-R1: details.existingProvider 각 slug → AccountProvider 매핑',
      () async {
        const cases = <String, AccountProvider>{
          'kakao': AccountProvider.kakao,
          'naver': AccountProvider.naver,
          'line': AccountProvider.line,
          'facebook': AccountProvider.facebook,
          'google': AccountProvider.google,
          'apple': AccountProvider.apple,
          'email': AccountProvider.email,
        };
        for (final entry in cases.entries) {
          final ex = await triggerCustomTokenExists(
            details: <String, dynamic>{'existingProvider': entry.key},
          );
          expect(
            ex.existingProvider,
            entry.value,
            reason: 'slug ${entry.key} → ${entry.value}',
          );
          // Custom Token path — 서버가 PII 로 email 미전달 → null 유지.
          expect(ex.email, isNull);
        }
      },
    );

    test('CT-R2a: details.existingProvider=null → existingProvider == null '
        '(R2 일반 배너 fallback)', () async {
      final ex = await triggerCustomTokenExists(
        details: <String, dynamic>{'existingProvider': null},
      );
      expect(ex.existingProvider, isNull);
      expect(ex.email, isNull);
    });

    test(
      'CT-R2b: details 자체 부재(null) → existingProvider == null + no throw',
      () async {
        final ex = await triggerCustomTokenExists(details: null);
        expect(ex.existingProvider, isNull);
        expect(ex.email, isNull);
      },
    );

    test('CT-R2c: unknown slug → existingProvider == null', () async {
      final ex = await triggerCustomTokenExists(
        details: <String, dynamic>{'existingProvider': 'unknown_slug_xyz'},
      );
      expect(ex.existingProvider, isNull);
    });

    test('CT-R3: details 가 Map 이 아님(String) → existingProvider == null + '
        'no throw', () async {
      final ex = await triggerCustomTokenExists(details: 'not-a-map');
      expect(ex.existingProvider, isNull);
      expect(ex.email, isNull);
    });

    test('CT-R3b: details 가 Map 이나 existingProvider 키 부재 → '
        'existingProvider == null', () async {
      final ex = await triggerCustomTokenExists(
        details: <String, dynamic>{'someOtherKey': 'value'},
      );
      expect(ex.existingProvider, isNull);
    });

    test('CT-R3c: existingProvider 값이 String 아님(int) → '
        'existingProvider == null + no throw', () async {
      final ex = await triggerCustomTokenExists(
        details: <String, dynamic>{'existingProvider': 42},
      );
      expect(ex.existingProvider, isNull);
    });
  });
}
