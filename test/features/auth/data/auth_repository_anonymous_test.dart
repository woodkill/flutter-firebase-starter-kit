import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:flutter_starter_kit/core/error/app_exception.dart';
import 'package:flutter_starter_kit/core/error/result.dart';
import 'package:flutter_starter_kit/features/auth/data/auth_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../../../helpers/auth_mocks.dart';

class _MockUserCredential extends Mock implements fb.UserCredential {}

class _MockFbUser extends Mock implements fb.User {}

class _MockUserMetadata extends Mock implements fb.UserMetadata {}

void main() {
  late MockFirebaseAuth mockAuth;
  late _MockUserCredential mockCredential;
  late _MockFbUser mockUser;
  late _MockUserMetadata mockMetadata;
  late MockGoogleSignIn mockGoogleSignIn;
  late MockFacebookAuth mockFacebookAuth;
  late MockSocialLinkInProgress mockSocialLinkInProgress;
  late MockKakaoSdkClient mockKakaoSdkClient;
  late MockNaverSdkClient mockNaverSdkClient;
  late MockLineSdkClient mockLineSdkClient;
  late MockFirebaseFunctions mockFunctions;
  late AuthRepository repository;

  setUp(() {
    mockAuth = MockFirebaseAuth();
    mockCredential = _MockUserCredential();
    mockUser = _MockFbUser();
    mockMetadata = _MockUserMetadata();
    mockGoogleSignIn = MockGoogleSignIn();
    mockFacebookAuth = MockFacebookAuth();
    mockSocialLinkInProgress = MockSocialLinkInProgress();
    mockKakaoSdkClient = MockKakaoSdkClient();
    mockNaverSdkClient = MockNaverSdkClient();
    mockLineSdkClient = MockLineSdkClient();
    mockFunctions = MockFirebaseFunctions();
    repository = buildAuthRepository(
      auth: mockAuth,
      googleSignIn: mockGoogleSignIn,
      facebookAuth: mockFacebookAuth,
      socialLinkInProgress: mockSocialLinkInProgress,
      kakaoSdkClient: mockKakaoSdkClient,
      functions: mockFunctions,
      naverSdkClient: mockNaverSdkClient,
      lineSdkClient: mockLineSdkClient,
    );

    // 익명 사용자 기본 stub — uid 만 있고 email 은 빈 값, emailVerified=false.
    when(() => mockUser.uid).thenReturn('anon-uid');
    when(() => mockUser.email).thenReturn(null);
    when(() => mockUser.emailVerified).thenReturn(false);
    when(() => mockUser.displayName).thenReturn(null);
    when(() => mockUser.photoURL).thenReturn(null);
    when(() => mockUser.metadata).thenReturn(mockMetadata);
    when(() => mockMetadata.creationTime).thenReturn(DateTime.utc(2026, 4, 14));
    when(() => mockUser.providerData).thenReturn([]);
    when(() => mockCredential.user).thenReturn(mockUser);
  });

  group('AuthRepository.signInAnonymously', () {
    test('성공 시 Result.success(User) 를 반환한다', () async {
      when(
        () => mockAuth.signInAnonymously(),
      ).thenAnswer((_) async => mockCredential);

      final result = await repository.signInAnonymously();

      expect(result, isA<Success<dynamic>>());
      final user = (result as Success).data;
      expect(user.uid, 'anon-uid');
      expect(user.email, isNull);
      expect(user.emailVerified, isFalse);
      expect(user.providerIds, isEmpty);
      verify(() => mockAuth.signInAnonymously()).called(1);
    });

    test('UserCredential.user 가 null 이면 ServiceUnavailable 을 반환한다', () async {
      when(() => mockCredential.user).thenReturn(null);
      when(
        () => mockAuth.signInAnonymously(),
      ).thenAnswer((_) async => mockCredential);

      final result = await repository.signInAnonymously();

      expect(result, isA<Failure<dynamic>>());
      expect((result as Failure).exception, isA<ServiceUnavailable>());
    });

    test('operation-not-allowed → ServiceUnavailable 매핑 (A4 위험)', () async {
      when(
        () => mockAuth.signInAnonymously(),
      ).thenThrow(fb.FirebaseAuthException(code: 'operation-not-allowed'));

      final result = await repository.signInAnonymously();

      expect(result, isA<Failure<dynamic>>());
      expect((result as Failure).exception, isA<ServiceUnavailable>());
    });

    test(
      'network-request-failed → NoInternetConnection 매핑 (Pitfall 3)',
      () async {
        when(
          () => mockAuth.signInAnonymously(),
        ).thenThrow(fb.FirebaseAuthException(code: 'network-request-failed'));

        final result = await repository.signInAnonymously();

        expect(result, isA<Failure<dynamic>>());
        expect((result as Failure).exception, isA<NoInternetConnection>());
      },
    );

    test(
      '기타 FirebaseAuthException → ServiceUnavailable 매핑 (fallback)',
      () async {
        when(
          () => mockAuth.signInAnonymously(),
        ).thenThrow(fb.FirebaseAuthException(code: 'some-unknown-code'));

        final result = await repository.signInAnonymously();

        expect(result, isA<Failure<dynamic>>());
        expect((result as Failure).exception, isA<ServiceUnavailable>());
      },
    );

    test('비-Auth Object 예외 → ServiceUnavailable 매핑', () async {
      when(
        () => mockAuth.signInAnonymously(),
      ).thenThrow(Exception('platform crash'));

      final result = await repository.signInAnonymously();

      expect(result, isA<Failure<dynamic>>());
      expect((result as Failure).exception, isA<ServiceUnavailable>());
    });
  });

  // Phase 10.2 D-A5: 구 D-20 로그아웃-후-익명-재진입 cascade 메서드가
  // 완전 폐기되었다. 본 group (구 메서드 단위 테스트 3 케이스) 도 함께
  // 삭제됨. 신규 메서드 `signOutAndResetOnboarding` 의 회귀 가드는
  // `test/features/auth/data/auth_repository_test.dart` 의
  // `group('signOutAndResetOnboarding (Phase 10.2 D-A3)', ...)` 가 담당한다.
}
