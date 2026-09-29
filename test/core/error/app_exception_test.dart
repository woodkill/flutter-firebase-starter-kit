import 'package:flutter_starter_kit/core/auth/provider_id.dart';
import 'package:flutter_starter_kit/core/error/app_exception.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AppException sealed class 계층', () {
    // Test 1: AppException은 sealed class (직접 인스턴스화 불가)
    // -> sealed class는 컴파일 타임에 강제되므로, subclass만 인스턴스화 가능함을 검증
    test('AppException의 subclass만 인스턴스화 가능', () {
      // NetworkException, AuthException, ServerException만 생성 가능
      const AppException networkEx = ConnectionTimeout();
      const AppException authEx = InvalidCredentials();
      const AppException serverEx = InternalServerError();

      expect(networkEx, isA<AppException>());
      expect(authEx, isA<AppException>());
      expect(serverEx, isA<AppException>());
    });

    // Test 2: NetworkException의 모든 구체 subclass에 userMessage 필드 존재
    test('NetworkException subclass에 빈 문자열이 아닌 userMessage 존재', () {
      const exceptions = <NetworkException>[
        ConnectionTimeout(),
        NoInternetConnection(),
        RequestTimeout(),
      ];

      for (final ex in exceptions) {
        expect(ex.userMessage, isNotEmpty, reason: '${ex.runtimeType}');
        expect(ex, isA<AppException>());
      }
    });

    // Test 3: AuthException의 모든 구체 subclass에 userMessage 필드 존재
    test('AuthException subclass에 userMessage 존재', () {
      const exceptions = <AuthException>[
        InvalidCredentials(),
        UserNotFound(),
        EmailAlreadyInUse(),
        WeakPassword(),
        SessionExpired(),
        InvalidEmail(),
        UserDisabled(),
        TooManyRequests(),
      ];

      for (final ex in exceptions) {
        expect(ex.userMessage, isNotEmpty, reason: '${ex.runtimeType}');
        expect(ex, isA<AppException>());
      }
    });

    // Test 4: ServerException의 모든 구체 subclass에 userMessage 필드 존재
    test('ServerException subclass에 userMessage 존재', () {
      const exceptions = <ServerException>[
        InternalServerError(),
        ServiceUnavailable(),
        // 16.10 review IN-04 (iteration 3) — 서버 provider 설정 결함.
        ProviderMisconfigured(),
      ];

      for (final ex in exceptions) {
        expect(ex.userMessage, isNotEmpty, reason: '${ex.runtimeType}');
        expect(ex, isA<AppException>());
      }
    });

    // Test 5: AppException에 대한 switch 문이 exhaustive
    test('AppException switch 문이 exhaustive하게 동작', () {
      // IN-05: UnknownException 이 ServerException 하위에서 AppException
      // 직속 leaf 로 올라가면서 직속 하위가 3 → 4 종이 됐다. 캐치올을
      // 명시적으로 다루지 않으면 여기서 컴파일 에러가 난다 — 오분류가
      // 침묵하지 않는다는 것이 이 변경의 핵심이다.
      // WR-13: InvalidInput 이 추가되어 직속 하위가 4 → 5 종이 됐다.
      String classify(AppException exception) => switch (exception) {
        NetworkException() => 'network',
        AuthException() => 'auth',
        ServerException() => 'server',
        InvalidInput() => 'invalid-input',
        UnknownException() => 'unknown',
      };

      expect(classify(const ConnectionTimeout()), equals('network'));
      expect(classify(const InvalidCredentials()), equals('auth'));
      expect(classify(const InternalServerError()), equals('server'));
      // 수정 전에는 이 줄이 'server' 를 반환했다 — 클라이언트 측 원인까지
      // 흡수하는 캐치올이 서버 장애로 취급되어 재시도 정책과 문구가 틀어졌다.
      expect(classify(const UnknownException()), equals('unknown'));
      // WR-13: 입력/계약 위반은 서버 장애도 미분류도 아니다.
      expect(classify(const InvalidInput()), equals('invalid-input'));
    });

    // WR-13: 계약 위반을 ServiceUnavailable 로 표현하면 재시도 문구가 붙는다.
    test('InvalidInput 은 ServerException 이 아니다 (WR-13)', () {
      const ex = InvalidInput();
      expect(ex, isA<AppException>());
      expect(ex, isNot(isA<ServerException>()));
      expect(ex, isNot(isA<NetworkException>()));
      expect(ex, isNot(isA<AuthException>()));
      expect(ex, isNot(isA<UnknownException>()));
    });

    // IN-05: 캐치올은 서버 도메인이 아니다.
    test('UnknownException 은 ServerException 이 아니다 (IN-05)', () {
      const ex = UnknownException();
      expect(ex, isA<AppException>());
      expect(ex, isNot(isA<ServerException>()));
      expect(ex, isNot(isA<NetworkException>()));
      expect(ex, isNot(isA<AuthException>()));
    });

    // Test 6: cause 파라미터가 optional이며 원본 예외를 보존
    test('cause 파라미터가 optional이며 원본 예외를 보존', () {
      // cause 없이 생성
      const noCause = ConnectionTimeout();
      expect(noCause.cause, isNull);

      // cause와 함께 생성
      final originalError = Exception('원본 에러');
      final withCause = ConnectionTimeout(cause: originalError);
      expect(withCause.cause, equals(originalError));
      expect(withCause.cause, isA<Exception>());
    });

    // 보안 위협 T-02-01 대응: userMessage에 기술 상세 미포함
    test('userMessage에 기술 상세 정보가 포함되지 않음', () {
      const allExceptions = <AppException>[
        ConnectionTimeout(),
        NoInternetConnection(),
        RequestTimeout(),
        InvalidCredentials(),
        UserNotFound(),
        EmailAlreadyInUse(),
        WeakPassword(),
        SessionExpired(),
        InvalidEmail(),
        UserDisabled(),
        TooManyRequests(),
        InternalServerError(),
        ServiceUnavailable(),
        ProviderMisconfigured(),
      ];

      for (final ex in allExceptions) {
        // 스택 트레이스, 내부 에러 코드, DB 쿼리 등이 포함되지 않아야 함
        expect(
          ex.userMessage,
          isNot(contains('stack')),
          reason: '${ex.runtimeType} userMessage에 stack 정보 포함',
        );
        expect(
          ex.userMessage,
          isNot(contains('trace')),
          reason: '${ex.runtimeType} userMessage에 trace 정보 포함',
        );
        expect(
          ex.userMessage,
          isNot(contains('query')),
          reason: '${ex.runtimeType} userMessage에 query 정보 포함',
        );
        expect(
          ex.userMessage,
          isNot(contains('SELECT')),
          reason: '${ex.runtimeType} userMessage에 SQL 정보 포함',
        );
      }
    });
  });

  group('AuthException 신규 케이스', () {
    test('InvalidEmail userMessage는 errorInvalidEmail', () {
      const ex = InvalidEmail();
      expect(ex.userMessage, 'errorInvalidEmail');
      expect(ex, isA<AuthException>());
      expect(ex, isA<AppException>());
    });

    test('UserDisabled userMessage는 errorUserDisabled', () {
      const ex = UserDisabled();
      expect(ex.userMessage, 'errorUserDisabled');
      expect(ex, isA<AuthException>());
      expect(ex, isA<AppException>());
    });

    test('TooManyRequests userMessage는 errorTooManyRequests', () {
      const ex = TooManyRequests();
      expect(ex.userMessage, 'errorTooManyRequests');
      expect(ex, isA<AuthException>());
      expect(ex, isA<AppException>());
    });

    test('신규 3종 모두 cause 파라미터로 원본 예외를 보존한다', () {
      final originalError = Exception('Firebase original error');
      final invalidEmail = InvalidEmail(cause: originalError);
      final userDisabled = UserDisabled(cause: originalError);
      final tooMany = TooManyRequests(cause: originalError);

      expect(invalidEmail.cause, equals(originalError));
      expect(userDisabled.cause, equals(originalError));
      expect(tooMany.cause, equals(originalError));
    });
  });

  group('WR-07: toString() 진단 정보 + PII 화이트리스트', () {
    test('cause 없는 예외는 runtimeType + userMessage 를 담는다', () {
      const ex = ServiceUnavailable();
      // 수정 전에는 Dart 기본 구현이 "Instance of 'ServiceUnavailable'" 만
      // 반환해 Crashlytics 리포트가 원인 정보를 0비트 전달했다.
      expect(ex.toString(), 'ServiceUnavailable(errorServiceUnavailable)');
      expect(ex.toString(), isNot(contains('Instance of')));
    });

    test('cause 가 있으면 원본 예외 요약이 포함된다', () {
      final ex = InternalServerError(cause: Exception('upstream 503'));
      expect(ex.toString(), contains('InternalServerError'));
      expect(ex.toString(), contains('errorInternalServer'));
      expect(ex.toString(), contains('upstream 503'));
    });

    test('모든 서브타입이 Instance of 대신 진단 문자열을 반환한다', () {
      const all = <AppException>[
        ConnectionTimeout(),
        NoInternetConnection(),
        RequestTimeout(),
        InvalidCredentials(),
        UserNotFound(),
        EmailAlreadyInUse(),
        WeakPassword(),
        SessionExpired(),
        InvalidEmail(),
        UserDisabled(),
        TooManyRequests(),
        AccountExistsWithDifferentCredential(),
        AccountAlreadyLinked(),
        ProviderAlreadyLinkedToThisAccount(),
        ReauthenticationRequiredException(),
        UnauthenticatedException(),
        ReauthUserMismatch(),
        ReauthMethodUnavailable(),
        InternalServerError(),
        ServiceUnavailable(),
        ProviderMisconfigured(),
        InvalidInput(),
        UnknownException(),
      ];
      for (final ex in all) {
        expect(
          ex.toString(),
          isNot(contains('Instance of')),
          reason: '${ex.runtimeType} 가 진단 정보를 전달하지 않는다',
        );
        expect(ex.toString(), startsWith('${ex.runtimeType}('));
        expect(ex.toString(), contains(ex.userMessage));
      }
    });

    test(
      'AccountExistsWithDifferentCredential.email 은 toString 에 나타나지 않는다',
      () {
        // 화이트리스트 보장: 서브타입 고유 필드는 toString 에서 제외된다.
        // 필드를 일괄 출력하는 구현이 들어오면 여기서 RED 가 된다.
        const ex = AccountExistsWithDifferentCredential(
          email: 'victim@example.com',
          existingProvider: AccountProvider.google,
        );
        expect(ex.toString(), isNot(contains('victim@example.com')));
        expect(ex.toString(), isNot(contains('victim')));
        expect(ex.toString(), contains('AccountExistsWithDifferentCredential'));
      },
    );

    test('cause 문자열에 섞인 이메일은 redact 된다', () {
      // cause 는 대개 플랫폼 예외이고 그 메시지는 우리가 통제하지 않는다.
      final ex = InvalidEmail(
        cause: Exception(
          'The email address user@example.com is badly formatted',
        ),
      );
      expect(ex.toString(), isNot(contains('user@example.com')));
      expect(ex.toString(), contains('<redacted-email>'));
      // 나머지 진단 정보는 보존된다.
      expect(ex.toString(), contains('badly formatted'));
    });

    test('cause 에 이메일이 여러 개여도 전부 redact 된다', () {
      final ex = UnknownException(
        cause: Exception('a@b.co and c.d+tag@e-f.example.org'),
      );
      final rendered = ex.toString();
      expect(rendered, isNot(contains('a@b.co')));
      expect(rendered, isNot(contains('c.d+tag@e-f.example.org')));
      expect(
        '<redacted-email>'.allMatches(rendered).length,
        2,
        reason: '이메일 2건이 모두 치환되어야 한다',
      );
    });
  });
}
