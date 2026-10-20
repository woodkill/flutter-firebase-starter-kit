// debug apple-authorizationerror-1000 — signInWithApple 이 Apple 인가 실패
// (`ASAuthorizationError.unknown` · 1000) 를 서버 장애 문구로 보이지 않게 하는
// 매핑 계약.
//
// **fixture 근거 — firebase_auth 6.7.0 iOS 플러그인:**
// `FLTFirebaseAuthPlugin.swift` `authorizationController(didCompleteWithError:)`
// 는 1001~1004 를 고정 code 로 넘기고 그 밖(1000 등)은
// `AuthErrors.convertAppleAuthorizationErrorToFlutterError` 로 보낸다. 결과는
// code `unknown` + message `<설명> (Domain=<d> Code=<c>[, Underlying Domain=<ud>
// Code=<uc>])` 이고, platform interface 는 details(nativeErrorCode) 를 버린다.
// [_kAppleUnknownMessage] 는 그 규칙을 호스트 probe 로 재현한 값이다
// (Phase 20 VM UAT 20-16 GAP 11 의 밑 오류 AKAuthenticationError -7022 포함).
//
// oracle: specified — 사용자 결정(errorUnknown 재사용) · Apple 문서
// 「The authorization attempt failed for an unknown reason.」

import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:flutter/foundation.dart' show DebugPrintCallback, debugPrint;
import 'package:flutter_starter_kit/core/error/app_exception.dart';
import 'package:flutter_starter_kit/core/error/result.dart';
import 'package:flutter_starter_kit/features/auth/data/auth_repository.dart';
import 'package:flutter_starter_kit/features/auth/domain/user.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../../../helpers/auth_mocks.dart';

class _MockFbUser extends Mock implements fb.User {}

const _kAppleDomain = 'com.apple.AuthenticationServices.AuthorizationError';

const _kAppleUnknownMessage =
    'The operation couldn’t be completed. ($_kAppleDomain error 1000.) '
    '(Domain=$_kAppleDomain Code=1000, '
    'Underlying Domain=AKAuthenticationError Code=-7022)';

const _kAppleUnknownLog =
    'AuthRepository: Apple 인가 실패(AuthorizationError 1000) '
    '→ UnknownException: code=unknown';

void main() {
  late MockFirebaseAuth mockAuth;
  late AuthRepository repository;
  late List<String> logs;
  late DebugPrintCallback originalDebugPrint;

  setUpAll(() {
    registerFallbackValue(fb.AppleAuthProvider());
  });

  setUp(() {
    mockAuth = MockFirebaseAuth();
    repository = buildAuthRepository(
      auth: mockAuth,
      socialLinkInProgress: MockSocialLinkInProgress(),
    );
    when(() => mockAuth.currentUser).thenReturn(null);

    logs = <String>[];
    originalDebugPrint = debugPrint;
    debugPrint = (String? message, {int? wrapWidth}) {
      if (message != null) logs.add(message);
    };
  });

  tearDown(() {
    debugPrint = originalDebugPrint;
  });

  /// [AuthRepository.signInWithApple] 을 실행해 실패 [AppException] 을 꺼낸다.
  Future<AppException> signInAndReadFailure() async {
    final result = await repository.signInWithApple();
    expect(result, isA<Failure<User>>());
    return (result! as Failure<User>).exception;
  }

  group('AuthorizationError 1000 → UnknownException (errorUnknown)', () {
    test('signInWithProvider 실측 fixture: 폴백 로그 없음 · message 미기록', () async {
      final error = fb.FirebaseAuthException(
        code: 'unknown',
        message: _kAppleUnknownMessage,
      );
      when(() => mockAuth.signInWithProvider(any())).thenThrow(error);

      final exception = await signInAndReadFailure();

      expect(exception, isA<UnknownException>());
      expect(exception.userMessage, 'errorUnknown');
      expect(exception.cause, same(error));
      expect(logs, contains(_kAppleUnknownLog));
      expect(logs.where((l) => l.contains('ServiceUnavailable 폴백')), isEmpty);
      // PII invariant: e.message 원문을 로그에 싣지 않는다.
      for (final log in logs) {
        expect(log, isNot(contains('AKAuthenticationError')));
      }
    });

    test('익명 linkWithProvider 경로(밑 오류 없음): 같은 매핑 · 새 로그인 · '
        '익명 삭제 0', () async {
      final anonymous = _MockFbUser();
      when(() => anonymous.isAnonymous).thenReturn(true);
      when(() => mockAuth.currentUser).thenReturn(anonymous);
      when(() => anonymous.linkWithProvider(any())).thenThrow(
        fb.FirebaseAuthException(
          code: 'unknown',
          message:
              'The operation couldn’t be completed. '
              '(Domain=$_kAppleDomain Code=1000)',
        ),
      );

      expect(await signInAndReadFailure(), isA<UnknownException>());
      expect(logs, contains(_kAppleUnknownLog));
      verifyNever(() => mockAuth.signInWithProvider(any()));
      verifyNever(anonymous.delete);
    });
  });

  group('경계 이웃 — 기존 매핑 유지', () {
    test('1001 실측(code canceled) → null (silent 취소)', () async {
      when(() => mockAuth.signInWithProvider(any())).thenThrow(
        fb.FirebaseAuthException(
          code: 'canceled',
          message: 'The user canceled the authorization attempt.',
        ),
      );

      expect(await repository.signInWithApple(), isNull);
    });

    final neighbors = <({String name, String code, String? message})>[
      (
        name: 'Code=1001 접미사',
        code: 'unknown',
        message: 'x (Domain=$_kAppleDomain Code=1001)',
      ),
      (
        name: 'Code=10000',
        code: 'unknown',
        message: 'x (Domain=$_kAppleDomain Code=10000)',
      ),
      (
        name: '다른 Domain',
        code: 'unknown',
        message: 'x (Domain=AKAuthenticationError Code=1000)',
      ),
      (
        name: '밑 오류에만 1000',
        code: 'unknown',
        message:
            'x (Domain=NSCocoaErrorDomain Code=4, '
            'Underlying Domain=$_kAppleDomain Code=1000)',
      ),
      (name: 'message null', code: 'unknown', message: null),
      (
        name: '접미사 없는 unknown',
        code: 'unknown',
        message: 'An internal error has occurred.',
      ),
      (
        name: 'code≠unknown + 1000 접미사',
        code: 'internal-error',
        message: 'x (Domain=$_kAppleDomain Code=1000)',
      ),
    ];
    for (final neighbor in neighbors) {
      test('${neighbor.name} → ServiceUnavailable', () async {
        when(() => mockAuth.signInWithProvider(any())).thenThrow(
          fb.FirebaseAuthException(
            code: neighbor.code,
            message: neighbor.message,
          ),
        );

        expect(await signInAndReadFailure(), isA<ServiceUnavailable>());
        expect(logs, isNot(contains(_kAppleUnknownLog)));
      });
    }
  });
}
