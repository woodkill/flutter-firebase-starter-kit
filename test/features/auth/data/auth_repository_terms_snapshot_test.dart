// ignore_for_file: lines_longer_than_80_chars
//
// Phase 16 Plan 16-14 — G-16-A9-1 gap closure.
//
// Custom Token callable payload 의 `termsAcceptanceSnapshot` 계약 테스트.
//
// 서버 진실원: `functions/src/shared/terms_acceptance_json.ts` 의
// `TermsAcceptanceJson` 5 키 (version / service / privacy / marketing /
// acceptedAt). 서버측 짝 sentinel:
// `functions/test/shared/terms_acceptance_json_contract.test.ts`.
// 한쪽 키 집합을 바꾸면 반대쪽도 반드시 함께 갱신해야 한다.
//
// **본 파일이 존재하는 이유 (A4/A9 공통 교훈):** producer(TermsNotifier) 와
// consumer(Cloud Function) 의 양 끝단 단위 테스트가 모두 GREEN 이어도 그 사이
// wiring 이 없으면 결함이 잡히지 않는다 (A9 실측: 서버는 수신·mirror 구현
// 완료였으나 client 가 값을 전송하지 않아 users/{uid}.termsAccepted 부재).
// 실제 전송 payload 를 키 단위로 단언하는 본 파일만이 그 계열을 막는다.
//
// TS1: line + snapshot 존재 → payload 3 키 + snapshot 키 집합 == 서버 5 키
// TS2: line + snapshot 부재 → payload {idToken, nonce} (add-only 회귀 가드)
// TS3/TS4: kakao + snapshot 유/무 (base {idToken, nonce})
// TS5/TS6: naver + snapshot 유/무 (base {accessToken} — provider 계약 차이)
// TS7/TS8: yahoojp + snapshot 유/무 (base {idToken, nonce})
// TS9: 4 provider 대칭 sentinel — snapshot 키 집합이 서로 동일 (drift 차단)

import 'package:cloud_functions/cloud_functions.dart' hide Result;
import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:flutter_facebook_auth/flutter_facebook_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:mocktail/mocktail.dart';

import 'package:flutter_starter_kit/core/error/result.dart';
import 'package:flutter_starter_kit/features/auth/application/social_link_in_progress.dart';
import 'package:flutter_starter_kit/features/auth/data/auth_repository.dart';
import 'package:flutter_starter_kit/features/auth/data/kakao_sdk_client.dart';
import 'package:flutter_starter_kit/features/auth/data/line_sdk_client.dart';
import 'package:flutter_starter_kit/features/auth/data/naver_sdk_client.dart';
import 'package:flutter_starter_kit/features/auth/data/yahoojp_sdk_client.dart';

class _MockFirebaseAuth extends Mock implements fb.FirebaseAuth {}

class _MockFbUser extends Mock implements fb.User {}

class _MockUserMetadata extends Mock implements fb.UserMetadata {}

class _MockUserCredential extends Mock implements fb.UserCredential {}

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

/// 서버 `TermsAcceptanceJson` 계약 키 집합 (진실원:
/// `functions/src/shared/terms_acceptance_json.ts`).
const _serverContractKeys = <String>{
  'version',
  'service',
  'privacy',
  'marketing',
  'acceptedAt',
};

/// device-local 동의 fixture — `TermsAcceptance.toJson()` 출력과 동형.
///
/// `acceptedAt` 은 서버가 `Timestamp.fromDate(new Date(...))` 로 파싱하므로
/// 반드시 ISO 8601 String 이어야 한다.
Map<String, dynamic> _snapshotFixture() => <String, dynamic>{
  'version': 1,
  'service': true,
  'privacy': true,
  'marketing': false,
  'acceptedAt': '2026-09-07T09:00:00.000Z',
};

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
  late _MockHttpsCallable mockCallable;
  late _MockUserCredential mockCredential;
  late _MockFbUser mockFbUser;
  late _MockUserMetadata mockMetadata;
  late AuthRepository repository;

  /// 테스트별로 교체 가능한 reader 반환값 (null = device-local 동의 부재).
  Map<String, dynamic>? injectedSnapshot;

  setUpAll(() {
    registerFallbackValue(<String, dynamic>{});
  });

  setUp(() {
    injectedSnapshot = null;

    mockAuth = _MockFirebaseAuth();
    mockGoogleSignIn = _MockGoogleSignIn();
    mockFacebookAuth = _MockFacebookAuth();
    mockSocialLinkInProgress = _MockSocialLinkInProgress();
    mockKakaoSdkClient = _MockKakaoSdkClient();
    mockNaverSdkClient = _MockNaverSdkClient();
    mockLineSdkClient = _MockLineSdkClient();
    mockYahoojpSdkClient = _MockYahoojpSdkClient();
    mockFunctions = _MockFirebaseFunctions();
    mockCallable = _MockHttpsCallable();
    mockCredential = _MockUserCredential();
    mockFbUser = _MockFbUser();
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
      mockYahoojpSdkClient,
      () async {},
      readTermsAcceptanceSnapshot: () => injectedSnapshot,
    );

    // Custom Token 4 흐름 공통 — SDK 1회성 토큰 finally logout.
    when(() => mockKakaoSdkClient.logout()).thenAnswer((_) async {});
    when(() => mockNaverSdkClient.logout()).thenAnswer((_) async {});
    when(() => mockLineSdkClient.logout()).thenAnswer((_) async {});
    when(() => mockYahoojpSdkClient.logout()).thenAnswer((_) async {});

    // callable 기본 wiring — customToken 응답.
    when(() => mockFunctions.httpsCallable(any())).thenReturn(mockCallable);
    final callableResult = _MockHttpsCallableResult();
    when(
      () => callableResult.data,
    ).thenReturn(<String, dynamic>{'customToken': 'CT'});
    when(
      () => mockCallable.call<Map<String, dynamic>>(any()),
    ).thenAnswer((_) async => callableResult);

    // signInWithCustomToken → 정식 사용자 credential.
    when(() => mockFbUser.uid).thenReturn('ct-uid');
    when(() => mockFbUser.email).thenReturn('user@example.com');
    // emailVerified=true 로 _autoSendEmailVerification 자연 no-op.
    when(() => mockFbUser.emailVerified).thenReturn(true);
    when(() => mockFbUser.displayName).thenReturn('User');
    when(() => mockFbUser.photoURL).thenReturn(null);
    when(() => mockFbUser.isAnonymous).thenReturn(false);
    when(() => mockFbUser.metadata).thenReturn(mockMetadata);
    when(() => mockMetadata.creationTime).thenReturn(DateTime.utc(2026));
    when(() => mockFbUser.providerData).thenReturn(const <fb.UserInfo>[]);
    when(() => mockCredential.user).thenReturn(mockFbUser);
    when(
      () => mockAuth.signInWithCustomToken('CT'),
    ).thenAnswer((_) async => mockCredential);

    // 4 provider SDK 성공 fixture.
    when(() => mockLineSdkClient.signIn()).thenAnswer(
      (_) async => const LineSignInResult(idToken: 'LIDT', nonce: 'LNONCE'),
    );
    when(() => mockKakaoSdkClient.signIn()).thenAnswer(
      (_) async => const KakaoSignInResult(idToken: 'KIDT', nonce: 'KNONCE'),
    );
    when(() => mockNaverSdkClient.signIn()).thenAnswer(
      (_) async => const NaverSignInResult(accessToken: 'NAT'),
    );
    when(() => mockYahoojpSdkClient.signIn()).thenAnswer(
      (_) async => const YahoojpSignInResult(idToken: 'YIDT', nonce: 'YNONCE'),
    );
  });

  /// callable 에 실제 전달된 payload 들을 순서대로 캡처한다 (wiring 단언의
  /// 유일한 형태 — 양 끝단 단위 테스트로는 대체 불가).
  List<Map<String, dynamic>> captureAllPayloads() {
    return verify(() => mockCallable.call<Map<String, dynamic>>(captureAny()))
        .captured
        .cast<Map<String, dynamic>>();
  }

  /// 단일 호출 payload 캡처.
  Map<String, dynamic> capturePayload() => captureAllPayloads().single;

  /// snapshot 존재 case 공통 단언 — 부착된 snapshot 이 서버 5-key 계약과
  /// 정확히 일치하고 `acceptedAt` 이 ISO 8601 String 임을 확인한다.
  Map<String, dynamic> expectContractSnapshot(Map<String, dynamic> payload) {
    final snapshot = payload['termsAcceptanceSnapshot'];
    expect(snapshot, isA<Map<String, dynamic>>());
    final snapshotMap = snapshot! as Map<String, dynamic>;
    expect(
      snapshotMap.keys.toSet(),
      _serverContractKeys,
      reason: 'client 전송 키 집합 == 서버 TermsAcceptanceJson 5 키',
    );
    final acceptedAt = snapshotMap['acceptedAt'];
    expect(acceptedAt, isA<String>());
    expect(
      () => DateTime.parse(acceptedAt! as String),
      returnsNormally,
      reason: 'acceptedAt 은 서버 Timestamp.fromDate 파싱 대상 (ISO 8601)',
    );
    return snapshotMap;
  }

  group('TS1 — line + snapshot 존재', () {
    test(
      'payload 가 {idToken, nonce, termsAcceptanceSnapshot} 이고 snapshot 키 집합이 서버 5 키와 동등',
      () async {
        injectedSnapshot = _snapshotFixture();

        final result = await repository.signInWithLine();

        expect(result, isA<Success<dynamic>>());
        final payload = capturePayload();
        expect(payload.keys.toSet(), <String>{
          'idToken',
          'nonce',
          'termsAcceptanceSnapshot',
        });
        // 기존 base 키 값 보존 (add-only).
        expect(payload['idToken'], 'LIDT');
        expect(payload['nonce'], 'LNONCE');

        expectContractSnapshot(payload);
      },
    );
  });

  group('TS2 — line + snapshot 부재', () {
    test('payload 키 집합이 {idToken, nonce} 그대로 (add-only 회귀 가드)', () async {
      injectedSnapshot = null;

      final result = await repository.signInWithLine();

      expect(result, isA<Success<dynamic>>());
      expect(capturePayload().keys.toSet(), <String>{'idToken', 'nonce'});
    });
  });

  group('TS3 — kakao + snapshot 존재', () {
    test('payload {idToken, nonce, termsAcceptanceSnapshot} + 5 키 계약', () async {
      injectedSnapshot = _snapshotFixture();

      final result = await repository.signInWithKakao();

      expect(result, isA<Success<dynamic>>());
      final payload = capturePayload();
      expect(payload.keys.toSet(), <String>{
        'idToken',
        'nonce',
        'termsAcceptanceSnapshot',
      });
      expect(payload['idToken'], 'KIDT');
      expect(payload['nonce'], 'KNONCE');
      expectContractSnapshot(payload);
    });
  });

  group('TS4 — kakao + snapshot 부재', () {
    test('payload 키 집합이 {idToken, nonce} 그대로', () async {
      injectedSnapshot = null;

      final result = await repository.signInWithKakao();

      expect(result, isA<Success<dynamic>>());
      expect(capturePayload().keys.toSet(), <String>{'idToken', 'nonce'});
    });
  });

  group('TS5 — naver + snapshot 존재', () {
    test('payload {accessToken, termsAcceptanceSnapshot} + 5 키 계약', () async {
      injectedSnapshot = _snapshotFixture();

      final result = await repository.signInWithNaver();

      expect(result, isA<Success<dynamic>>());
      final payload = capturePayload();
      // naver 는 base 키가 accessToken 단일 — provider 계약 차이이며
      // snapshot 부착 방식은 4 provider 동일.
      expect(payload.keys.toSet(), <String>{
        'accessToken',
        'termsAcceptanceSnapshot',
      });
      expect(payload['accessToken'], 'NAT');
      expectContractSnapshot(payload);
    });
  });

  group('TS6 — naver + snapshot 부재', () {
    test('payload 키 집합이 {accessToken} 단일 그대로', () async {
      injectedSnapshot = null;

      final result = await repository.signInWithNaver();

      expect(result, isA<Success<dynamic>>());
      expect(capturePayload().keys.toSet(), <String>{'accessToken'});
    });
  });

  group('TS7 — yahoojp + snapshot 존재', () {
    test('payload {idToken, nonce, termsAcceptanceSnapshot} + 5 키 계약', () async {
      injectedSnapshot = _snapshotFixture();

      final result = await repository.signInWithYahoojp();

      expect(result, isA<Success<dynamic>>());
      final payload = capturePayload();
      expect(payload.keys.toSet(), <String>{
        'idToken',
        'nonce',
        'termsAcceptanceSnapshot',
      });
      expect(payload['idToken'], 'YIDT');
      expect(payload['nonce'], 'YNONCE');
      expectContractSnapshot(payload);
    });
  });

  group('TS8 — yahoojp + snapshot 부재', () {
    test('payload 키 집합이 {idToken, nonce} 그대로', () async {
      injectedSnapshot = null;

      final result = await repository.signInWithYahoojp();

      expect(result, isA<Success<dynamic>>());
      expect(capturePayload().keys.toSet(), <String>{'idToken', 'nonce'});
    });
  });

  group('TS9 — 4 provider 대칭 sentinel', () {
    test(
      'kakao/naver/line/yahoojp 의 termsAcceptanceSnapshot 키 집합이 서로 동일하고 모두 서버 5 키와 동등',
      () async {
        injectedSnapshot = _snapshotFixture();

        await repository.signInWithKakao();
        await repository.signInWithNaver();
        await repository.signInWithLine();
        await repository.signInWithYahoojp();

        final payloads = captureAllPayloads();
        expect(payloads, hasLength(4), reason: '4 provider 모두 callable 호출');

        final keySets = payloads.map(expectContractSnapshot).map(
          (snapshot) => snapshot.keys.toSet(),
        );
        for (final keySet in keySets) {
          expect(
            keySet,
            _serverContractKeys,
            reason: 'provider 별 payload drift 차단 — 4 provider 동일 키 집합',
          );
        }
      },
    );
  });
}
