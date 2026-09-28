// Phase 16.10 plan 06 Task 1 — Custom Token 재로그인 응답 검증 helper.
//
//   MT1: 정상 응답 → customToken 반환
//   MT2: 응답 uid ≠ 현재 uid → ReauthUserMismatch
//   MT3: customToken 부재 → UnknownException
//   MT4: customToken 빈 문자열 → UnknownException
//   MT5: uid 가 문자열이 아님 → UnknownException

import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_starter_kit/core/error/app_exception.dart';
import 'package:flutter_starter_kit/features/auth/data/minted_custom_token.dart';

void main() {
  group('requireMintedCustomToken', () {
    test('MT1: 정상 응답 → customToken 반환', () {
      final token = requireMintedCustomToken(<String, dynamic>{
        'ok': true,
        'customToken': 'ct-U',
        'uid': 'U',
      }, currentUid: 'U');

      expect(token, 'ct-U');
    });

    test('MT2: 응답 uid 가 다른 계정 → ReauthUserMismatch', () {
      expect(
        () => requireMintedCustomToken(<String, dynamic>{
          'customToken': 'ct-OTHER',
          'uid': 'OTHER',
        }, currentUid: 'U'),
        throwsA(isA<ReauthUserMismatch>()),
      );
    });

    test('MT3: customToken 부재 → UnknownException', () {
      expect(
        () => requireMintedCustomToken(<String, dynamic>{
          'uid': 'U',
        }, currentUid: 'U'),
        throwsA(isA<UnknownException>()),
      );
    });

    test('MT4: customToken 빈 문자열 → UnknownException', () {
      expect(
        () => requireMintedCustomToken(<String, dynamic>{
          'customToken': '',
          'uid': 'U',
        }, currentUid: 'U'),
        throwsA(isA<UnknownException>()),
      );
    });

    test('MT5: uid 가 정수 → UnknownException (계약 위반)', () {
      expect(
        () => requireMintedCustomToken(<String, dynamic>{
          'customToken': 'ct-U',
          'uid': 42,
        }, currentUid: 'U'),
        throwsA(isA<UnknownException>()),
      );
    });
  });
}
