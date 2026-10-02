// Phase 17 — see ROADMAP.md (D-24 · D-43 · D-44) — callable App Check 판정
// helper 계약 + AuthRepository CT 로그인 관통.

import 'package:cloud_functions/cloud_functions.dart' hide Result;
import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:flutter_facebook_auth/flutter_facebook_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:mocktail/mocktail.dart';

import 'package:flutter_starter_kit/core/crashlytics/crashlytics_service.dart';
import 'package:flutter_starter_kit/core/error/app_exception.dart';
import 'package:flutter_starter_kit/core/error/result.dart';
import 'package:flutter_starter_kit/core/functions/callable_rejection.dart';
import 'package:flutter_starter_kit/features/auth/application/social_link_in_progress.dart';
import 'package:flutter_starter_kit/features/auth/data/auth_repository.dart';
import 'package:flutter_starter_kit/features/auth/data/kakao_sdk_client.dart';
import 'package:flutter_starter_kit/features/auth/data/line_sdk_client.dart';
import 'package:flutter_starter_kit/features/auth/data/naver_sdk_client.dart';
import 'package:flutter_starter_kit/features/auth/domain/user.dart';

/// [CrashlyticsService] mocktail 대역 — 기록 횟수 · reason 검증용.
class MockCrashlyticsService extends Mock implements CrashlyticsService {}

class _MockFirebaseAuth extends Mock implements fb.FirebaseAuth {}

class _MockGoogleSignIn extends Mock implements GoogleSignIn {}

class _MockFacebookAuth extends Mock implements FacebookAuth {}

class _MockSocialLinkInProgress extends Mock implements SocialLinkInProgress {}

class _MockKakaoSdkClient extends Mock implements KakaoSdkClient {}

class _MockNaverSdkClient extends Mock implements NaverSdkClient {}

class _MockLineSdkClient extends Mock implements LineSdkClient {}

class _MockFirebaseFunctions extends Mock implements FirebaseFunctions {}

class _MockHttpsCallable extends Mock implements HttpsCallable {}

class _FakeHttpsCallableOptions extends Fake implements HttpsCallableOptions {}

/// firebase-functions SDK 계층 거부와 같은 모양의 예외 — code
/// `unauthenticated` · message `Unauthenticated` · details 없음.
FirebaseFunctionsException _sdkRejection() => FirebaseFunctionsException(
  code: 'unauthenticated',
  message: 'Unauthenticated',
);

void main() {
  late MockCrashlyticsService crashlytics;

  setUpAll(() {
    registerFallbackValue(StackTrace.empty);
    registerFallbackValue(<String, dynamic>{});
    registerFallbackValue(_FakeHttpsCallableOptions());
  });

  setUp(() {
    crashlytics = MockCrashlyticsService();
    when(
      () => crashlytics.recordError(
        any(),
        any(),
        reason: any(named: 'reason'),
        fatal: any(named: 'fatal'),
      ),
    ).thenAnswer((_) async {});
  });

  /// [crashlytics] 에 기록이 하나도 없었는지 확인한다.
  void verifyNoRecord() {
    verifyNever(
      () => crashlytics.recordError(
        any(),
        any(),
        reason: any(named: 'reason'),
        fatal: any(named: 'fatal'),
      ),
    );
  }

  group('Phase 17 App Check 판정 (T-17-APPCHECK)', () {
    test('T-17-APPCHECK-01: SDK 거부 → AppCheckFailedException · 기록 1회', () {
      final e = _sdkRejection();

      final result = classifyAppCheckRejection(
        e,
        callable: 'kakaoCustomToken',
        crashlytics: crashlytics,
      );

      expect(result, isA<AppCheckFailedException>());
      expect(result!.cause, same(e));
      expect(isSdkLayerUnauthenticated(e), isTrue);
      verify(
        () => crashlytics.recordError(
          e,
          any(),
          reason: 'app_check_rejected_kakaoCustomToken',
          fatal: false,
        ),
      ).called(1);
    });

    test('T-17-APPCHECK-01: 기록 스택 = 예외의 원 스택 (리뷰 IN-08)', () {
      final original = StackTrace.fromString('#0 kakaoCustomToken call site');
      final e = FirebaseFunctionsException(
        code: 'unauthenticated',
        message: 'Unauthenticated',
        stackTrace: original,
      );

      classifyAppCheckRejection(
        e,
        callable: 'kakaoCustomToken',
        crashlytics: crashlytics,
      );

      final captured = verify(
        () => crashlytics.recordError(
          e,
          captureAny(),
          reason: 'app_check_rejected_kakaoCustomToken',
          fatal: false,
        ),
      ).captured;
      expect(captured.single, same(original));
    });

    group('T-17-APPCHECK-02: 비판정 4갈래 — null · 기록 0', () {
      final cases = <String, FirebaseFunctionsException>{
        '서버 taxonomy errorUnauthenticated': FirebaseFunctionsException(
          code: 'unauthenticated',
          message: 'errorUnauthenticated',
        ),
        '서버 taxonomy errorInvalidCredentials': FirebaseFunctionsException(
          code: 'unauthenticated',
          message: 'errorInvalidCredentials',
        ),
        'reason 있는 재인증 거부(SDK message 와 같아도)': FirebaseFunctionsException(
          code: 'unauthenticated',
          message: 'Unauthenticated',
          details: const <String, dynamic>{
            'reason': 'reauthentication_required',
          },
        ),
        'code permission-denied(SDK message 와 같아도)': FirebaseFunctionsException(
          code: 'permission-denied',
          message: 'Unauthenticated',
        ),
      };

      for (final entry in cases.entries) {
        test(entry.key, () {
          final result = classifyAppCheckRejection(
            entry.value,
            callable: 'kakaoCustomToken',
            crashlytics: crashlytics,
          );

          expect(result, isNull);
          expect(isSdkLayerUnauthenticated(entry.value), isFalse);
          verifyNoRecord();
        });
      }
    });

    group('T-17-APPCHECK-03: Kakao CT 로그인 관통', () {
      late _MockKakaoSdkClient kakao;
      late _MockFirebaseFunctions functions;
      late _MockHttpsCallable ctCallable;
      late AuthRepository repository;

      setUp(() {
        kakao = _MockKakaoSdkClient();
        functions = _MockFirebaseFunctions();
        ctCallable = _MockHttpsCallable();
        when(kakao.signIn).thenAnswer(
          (_) async => const KakaoSignInResult(idToken: 'IDT', nonce: 'NONCE'),
        );
        when(kakao.logout).thenAnswer((_) async {});
        when(
          () => functions.httpsCallable(
            'kakaoCustomToken',
            options: any(named: 'options'),
          ),
        ).thenReturn(ctCallable);
        repository = AuthRepository(
          _MockFirebaseAuth(),
          _MockGoogleSignIn(),
          _MockFacebookAuth(),
          _MockSocialLinkInProgress(),
          kakao,
          functions,
          _MockNaverSdkClient(),
          _MockLineSdkClient(),
          () async {},
          crashlytics: crashlytics,
        );
      });

      test('SDK 거부 → Failure(AppCheckFailedException) · 기록 1회', () async {
        when(
          () => ctCallable.call<Map<String, dynamic>>(any()),
        ).thenThrow(_sdkRejection());

        final result = await repository.signInWithKakao();

        expect(result, isA<Failure<User>>());
        expect(
          (result! as Failure<User>).exception,
          isA<AppCheckFailedException>(),
        );
        verify(
          () => crashlytics.recordError(
            any(that: isA<FirebaseFunctionsException>()),
            any(),
            reason: 'app_check_rejected_kakaoCustomToken',
            fatal: false,
          ),
        ).called(1);
      });

      test('서버 errorUnauthenticated → 기존 ServiceUnavailable · 기록 0', () async {
        when(() => ctCallable.call<Map<String, dynamic>>(any())).thenThrow(
          FirebaseFunctionsException(
            code: 'unauthenticated',
            message: 'errorUnauthenticated',
          ),
        );

        final result = await repository.signInWithKakao();

        expect(result, isA<Failure<User>>());
        expect((result! as Failure<User>).exception, isA<ServiceUnavailable>());
        verifyNoRecord();
      });
    });
  });
}
