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
//   T3: callable 'unauthenticated' + details.reason 'reauthentication_required'
//       · 'permission-denied' → ReauthenticationRequiredException / reason 없는
//       'unauthenticated' (서버 taxonomy — IdP ID token 거부) → ServiceUnavailable
//       (16.9 review WR-01 — linkNaverProviderArm 과 같은 판정) / 다른 code +
//       reauth reason 은 재로그인 아님 (code anchor · iteration 2 IN-01)
//   T-17-APPCHECK-04: SDK 계층 거부(App Check 차단) → AppCheckFailedException
//       · Crashlytics 1회 / reason 분기가 helper 보다 먼저 (Phase 17 D-43)
//   T4: callable 'already-exists'/'errorAccountAlreadyLinked' → AccountAlreadyLinked
//       · + details.reason 'provider_already_linked' →
//       ProviderAlreadyLinkedToThisAccount (16.9 review IN-03)
//   T5: callable 'failed-precondition'/'errorAnonymousLinkNotAllowed' → 적절 매핑
//   T6 (PII sentinel): catch path debugPrint 가 idToken/targetProviderToken/email
//       본문 미포함 (code/runtimeType-only)
//   T7 (token freshness): callable payload idToken 은 getIdToken(true) 결과
//       (forceRefresh=true 호출 검증)
//   T8 (1회성 토큰): target SDK 가 finally logout 호출 (verify logout 1회)
//   T9 (WR-06 · 16.9 review IN-02 / iteration 2 WR-01): caller null · 익명은
//       SDK 왕복 전에, Kakao/LINE 왕복 중 current user 가 null · 익명 · 다른
//       uid 로 바뀌면 왕복 뒤에 UnknownException (getIdToken · callable 미호출)
//       · 같은 uid 의 새 인스턴스로 바뀌면 통과 — 새 인스턴스 토큰으로 연결
//       (uid 대조 시맨틱 · iteration 3 IN-05)

import 'package:cloud_functions/cloud_functions.dart' hide Result;
import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:flutter/foundation.dart';
import 'package:flutter_facebook_auth/flutter_facebook_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:mocktail/mocktail.dart';

import 'package:flutter_starter_kit/core/auth/provider_id.dart';
import 'package:flutter_starter_kit/core/crashlytics/crashlytics_service.dart';
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

class _MockCrashlyticsService extends Mock implements CrashlyticsService {}

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
        accessToken: 'line-at',
      ),
    );
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

  group('T3 — 재로그인 유도는 서버 표시(reason)만 (16.9 review WR-01)', () {
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

    /// [result] 가 [Failure] 이면 그 예외를 돌려준다.
    AppException failureOf(Result<dynamic>? result) {
      expect(result, isA<Failure<dynamic>>());
      return (result! as Failure<dynamic>).exception;
    }

    test(
      'unauthenticated + reason reauthentication_required → ReauthenticationRequiredException',
      () async {
        stubLineSignInSuccess();
        stubCallableThrows(
          'unauthenticated',
          details: const <String, Object?>{
            'reason': 'reauthentication_required',
          },
        );

        final result = await repository.linkCustomTokenProviderArm(
          targetProvider: AccountProvider.line,
        );

        expect(failureOf(result), isA<ReauthenticationRequiredException>());
      },
    );

    test(
      'permission-denied (idToken uid 불일치) → ReauthenticationRequiredException',
      () async {
        stubLineSignInSuccess();
        stubCallableThrows('permission-denied');

        final result = await repository.linkCustomTokenProviderArm(
          targetProvider: AccountProvider.line,
        );

        expect(failureOf(result), isA<ReauthenticationRequiredException>());
      },
    );

    test(
      'unauthenticated · reason 없음 (LINE ID token 거부 · 서버 taxonomy) → ServiceUnavailable',
      () async {
        stubLineSignInSuccess();
        stubCallableThrows('unauthenticated');

        final result = await repository.linkCustomTokenProviderArm(
          targetProvider: AccountProvider.line,
        );

        final exception = failureOf(result);
        expect(exception, isA<ServiceUnavailable>());
        expect(exception, isNot(isA<ReauthenticationRequiredException>()));
        // 1회성 토큰 정책 · race-fix invariant 는 실패 경로에서도 유지.
        verify(() => mockLineSdkClient.logout()).called(1);
        verify(() => mockSocialLinkInProgress.end()).called(1);
      },
    );

    test(
      'already-exists + reason reauthentication_required → AccountAlreadyLinked '
      '(code anchor · 재로그인 아님 · 16.9 review iteration 2 IN-01)',
      () async {
        stubLineSignInSuccess();
        stubCallableThrows(
          'already-exists',
          details: const <String, Object?>{
            'reason': 'reauthentication_required',
          },
        );

        final result = await repository.linkCustomTokenProviderArm(
          targetProvider: AccountProvider.line,
        );

        final exception = failureOf(result);
        expect(exception, isA<AccountAlreadyLinked>());
        expect(exception, isNot(isA<ReauthenticationRequiredException>()));
      },
    );
  });

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

    test('already-exists + reason provider_already_linked → '
        'ProviderAlreadyLinkedToThisAccount (16.9 review IN-03)', () async {
      stubLineSignInSuccess();
      when(() => mockLinkCallable.call<Map<String, dynamic>>(any())).thenThrow(
        FirebaseFunctionsException(
          code: 'already-exists',
          message: 'errorProviderAlreadyLinked',
          details: const <String, Object?>{'reason': 'provider_already_linked'},
        ),
      );

      final result = await repository.linkCustomTokenProviderArm(
        targetProvider: AccountProvider.line,
      );

      expect(result, isA<Failure<dynamic>>());
      final failure = result! as Failure<dynamic>;
      expect(failure.exception, isA<ProviderAlreadyLinkedToThisAccount>());
      expect(failure.exception, isNot(isA<AccountAlreadyLinked>()));
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

      // forceRefresh=true 로 caller ID Token 발급 (재확인한 caller 의 토큰 — 서버 auth_time 신선도 검사 없음 · quick 260928-cxs).
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
      // client 에서 loud fail — SDK 왕복 (16.9 review IN-02) / callable
      // round-trip / caller token 발급 회피.
      verifyNever(() => mockLineSdkClient.signIn());
      verifyNever(() => mockCurrentUser.getIdToken(any()));
      verifyNever(() => mockLinkCallable.call<Map<String, dynamic>>(any()));
      // race-fix invariant + 1회성 토큰 logout 보존.
      verify(() => mockSocialLinkInProgress.begin()).called(1);
      verify(() => mockSocialLinkInProgress.end()).called(1);
      verify(() => mockLineSdkClient.logout()).called(1);
    });

    test('currentUser == null → Result.failure(UnknownException) + '
        'target SDK signIn 미호출 (16.9 review IN-02)', () async {
      stubLineSignInSuccess();
      when(() => mockAuth.currentUser).thenReturn(null);

      final result = await repository.linkCustomTokenProviderArm(
        targetProvider: AccountProvider.line,
      );

      expect(result, isA<Failure<dynamic>>());
      final failure = result! as Failure<dynamic>;
      expect(failure.exception, isA<UnknownException>());
      verifyNever(() => mockLineSdkClient.signIn());
      verifyNever(() => mockLinkCallable.call<Map<String, dynamic>>(any()));
      verify(() => mockSocialLinkInProgress.end()).called(1);
    });

    // 16.9 review iteration 2 WR-01: 왕복 전 검사를 통과해도 target SDK 왕복
    // 동안 세션이 바뀌면 결정적 실패다. `User.getIdToken` 은 호출 시점의
    // native current user 토큰을 만들므로 캡처 객체로 진행하면 안 된다.
    // signIn() mock 안에서 currentUser stub 을 바꿔 arm 내부 읽기 횟수와
    // 무관하게 「왕복 뒤」 시점만 교체한다. 익명 케이스는 uid 를 같게 두어
    // uid 대조와 독립적으로 isAnonymous 분기를 잠근다.
    for (final targetProvider in <AccountProvider>[
      AccountProvider.kakao,
      AccountProvider.line,
    ]) {
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
        test('${targetProvider.slug} 왕복 중 current user 가 $label 로 교체 → '
            'UnknownException · getIdToken · callable 미호출 · logout 1 · '
            'end 1', () async {
          final replacement = buildReplacement();
          void swapCaller() =>
              when(() => mockAuth.currentUser).thenReturn(replacement);
          if (targetProvider == AccountProvider.kakao) {
            when(() => mockKakaoSdkClient.signIn()).thenAnswer((_) async {
              swapCaller();
              return const KakaoSignInResult(
                idToken: 'kakao-fresh-id-token',
                nonce: 'kakao-nonce',
              );
            });
          } else {
            when(() => mockLineSdkClient.signIn()).thenAnswer((_) async {
              swapCaller();
              return const LineSignInResult(
                idToken: 'line-fresh-id-token',
                nonce: 'line-nonce',
                accessToken: 'line-at',
              );
            });
          }

          final result = await repository.linkCustomTokenProviderArm(
            targetProvider: targetProvider,
          );

          expect(result, isA<Failure<dynamic>>());
          final failure = result! as Failure<dynamic>;
          // WR-06: 결정적 실패 — transientFailure 로 떨어지지 않는다.
          expect(failure.exception, isA<UnknownException>());
          expect(failure.exception, isNot(isA<ServiceUnavailable>()));
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
          // race-fix invariant + 1회성 토큰 logout 보존.
          verify(() => mockSocialLinkInProgress.begin()).called(1);
          verify(() => mockSocialLinkInProgress.end()).called(1);
          if (targetProvider == AccountProvider.kakao) {
            verify(() => mockKakaoSdkClient.signIn()).called(1);
            verify(() => mockKakaoSdkClient.logout()).called(1);
          } else {
            verify(() => mockLineSdkClient.signIn()).called(1);
            verify(() => mockLineSdkClient.logout()).called(1);
          }
        });
      }
    }

    // 16.9 review iteration 3 IN-05: 재확인은 객체 identity 가 아니라 uid
    // 대조다. 실제 SDK 는 `currentUser` 를 읽을 때마다 새 wrapper 를 만들므로
    // 같은 uid 의 다른 인스턴스는 통과해야 하고, 토큰 · reload 는 캡처 객체가
    // 아니라 재확인한 인스턴스에서 받아야 한다.
    for (final targetProvider in <AccountProvider>[
      AccountProvider.kakao,
      AccountProvider.line,
    ]) {
      test('${targetProvider.slug} 왕복 중 current user 가 같은 uid 의 새 '
          '인스턴스로 교체 → 연결 성공 · 새 인스턴스 토큰 · 캡처 객체 '
          'getIdToken 미호출', () async {
        final replacement = buildSameUidReplacement();
        void swapCaller() =>
            when(() => mockAuth.currentUser).thenReturn(replacement);
        if (targetProvider == AccountProvider.kakao) {
          when(() => mockKakaoSdkClient.signIn()).thenAnswer((_) async {
            swapCaller();
            return const KakaoSignInResult(
              idToken: 'kakao-fresh-id-token',
              nonce: 'kakao-nonce',
            );
          });
        } else {
          when(() => mockLineSdkClient.signIn()).thenAnswer((_) async {
            swapCaller();
            return const LineSignInResult(
              idToken: 'line-fresh-id-token',
              nonce: 'line-nonce',
              accessToken: 'line-at',
            );
          });
        }

        final result = await repository.linkCustomTokenProviderArm(
          targetProvider: targetProvider,
        );

        expect(result, isA<Success<dynamic>>());
        final captured =
            verify(
                  () =>
                      mockLinkCallable.call<Map<String, dynamic>>(captureAny()),
                ).captured.single
                as Map<String, dynamic>;
        expect(captured['idToken'], 'swapped-token');
        expect(captured['targetProvider'], targetProvider.slug);
        verify(() => replacement.getIdToken(true)).called(1);
        verify(() => replacement.reload()).called(1);
        verifyNever(() => mockCurrentUser.getIdToken(any()));
        verifyNever(() => mockCurrentUser.reload());
        verify(() => mockSocialLinkInProgress.begin()).called(1);
        verify(() => mockSocialLinkInProgress.end()).called(1);
      });
    }
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

  group('T-17-APPCHECK-04: 연결 callable App Check 판정 (Phase 17 D-43)', () {
    late _MockCrashlyticsService crashlytics;
    late AuthRepository appCheckRepository;

    setUpAll(() {
      registerFallbackValue(StackTrace.empty);
    });

    setUp(() {
      crashlytics = _MockCrashlyticsService();
      when(
        () => crashlytics.recordError(
          any(),
          any(),
          reason: any(named: 'reason'),
          fatal: any(named: 'fatal'),
        ),
      ).thenAnswer((_) async {});
      appCheckRepository = AuthRepository(
        mockAuth,
        mockGoogleSignIn,
        mockFacebookAuth,
        mockSocialLinkInProgress,
        mockKakaoSdkClient,
        mockFunctions,
        mockNaverSdkClient,
        mockLineSdkClient,
        () async {},
        crashlytics: crashlytics,
      );
      stubLineSignInSuccess();
    });

    /// callable 이 SDK message `Unauthenticated` 로 거부하도록 stub 한다.
    void stubSdkMessage(String code, {Object? details}) {
      when(() => mockLinkCallable.call<Map<String, dynamic>>(any())).thenThrow(
        FirebaseFunctionsException(
          code: code,
          message: 'Unauthenticated',
          details: details,
        ),
      );
    }

    /// [result] 의 실패 예외를 돌려준다.
    AppException failureOf(Result<dynamic>? result) {
      expect(result, isA<Failure<dynamic>>());
      return (result! as Failure<dynamic>).exception;
    }

    test('SDK 거부 → AppCheckFailedException · 기록 1회 · logout 유지', () async {
      stubSdkMessage('unauthenticated');

      final result = await appCheckRepository.linkCustomTokenProviderArm(
        targetProvider: AccountProvider.line,
      );

      final exception = failureOf(result);
      expect(exception, isA<AppCheckFailedException>());
      expect(exception, isNot(isA<ReauthenticationRequiredException>()));
      verify(
        () => crashlytics.recordError(
          any(that: isA<FirebaseFunctionsException>()),
          any(),
          reason: 'app_check_rejected_linkCustomTokenProvider',
          fatal: false,
        ),
      ).called(1);
      verify(() => mockLineSdkClient.logout()).called(1);
    });

    test('reason reauthentication_required 가 먼저 — 재인증 예외 · 기록 0', () async {
      stubSdkMessage(
        'unauthenticated',
        details: const <String, Object?>{'reason': 'reauthentication_required'},
      );

      final result = await appCheckRepository.linkCustomTokenProviderArm(
        targetProvider: AccountProvider.line,
      );

      expect(failureOf(result), isA<ReauthenticationRequiredException>());
      verifyNever(
        () => crashlytics.recordError(
          any(),
          any(),
          reason: any(named: 'reason'),
          fatal: any(named: 'fatal'),
        ),
      );
    });

    test('reason provider_already_linked 는 기존 그대로 · 기록 0', () async {
      stubSdkMessage(
        'already-exists',
        details: const <String, Object?>{'reason': 'provider_already_linked'},
      );

      final result = await appCheckRepository.linkCustomTokenProviderArm(
        targetProvider: AccountProvider.line,
      );

      expect(failureOf(result), isA<ProviderAlreadyLinkedToThisAccount>());
      verifyNever(
        () => crashlytics.recordError(
          any(),
          any(),
          reason: any(named: 'reason'),
          fatal: any(named: 'fatal'),
        ),
      );
    });
  });
}
