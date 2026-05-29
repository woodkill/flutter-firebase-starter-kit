import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_starter_kit/core/auth/provider_id.dart';
import 'package:flutter_starter_kit/core/error/app_exception.dart';

/// Phase 16 Task 4.1 — `AccountExistsWithDifferentCredential.existingProvider`
/// 필드 (D-12 wiring 후 채워짐) 검증.
void main() {
  group('AccountExistsWithDifferentCredential — existingProvider 필드', () {
    test('existingProvider 미지정 시 null (R2 unknown fallback 회귀 가드)', () {
      const ex = AccountExistsWithDifferentCredential(email: 'a@example.com');
      expect(ex.existingProvider, isNull);
    });

    test('existingProvider 명시 시 enum 보존', () {
      const ex = AccountExistsWithDifferentCredential(
        email: 'a@example.com',
        existingProvider: AccountProvider.kakao,
      );
      expect(ex.existingProvider, AccountProvider.kakao);
    });

    test('email 미지정 + existingProvider 미지정 시 둘 다 null', () {
      const ex = AccountExistsWithDifferentCredential();
      expect(ex.email, isNull);
      expect(ex.existingProvider, isNull);
    });

    test('userMessage 는 기존 ARB key 보존 (Phase 9.2 anchor)', () {
      const ex = AccountExistsWithDifferentCredential(
        existingProvider: AccountProvider.google,
      );
      expect(ex.userMessage, 'errorAccountExistsWithDifferentCredential');
    });
  });
}
