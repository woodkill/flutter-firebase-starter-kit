import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_starter_kit/core/auth/nonce.dart';

/// IN-05 (Phase 7 review) — Kakao / LINE / Yahoo!JP 에 3중 복제되어 있던
/// nonce 생성 알고리즘을 단일 helper 로 추출한 뒤의 계약 회귀 가드.
///
/// 기존 3 wrapper 의 테스트 (`kakao_sdk_client_test` / `line_sdk_client_test`
/// / `yahoojp_sdk_client_test`) 가 각자 길이·유일성을 검증하고 있었으므로,
/// 본 파일은 helper 자체의 계약 (길이 매핑 / base64url 문자셋 / padding 부재
/// / CSPRNG 유일성) 만 좁게 검증한다.
void main() {
  group('generateNonce', () {
    // base64url 알파벳 + padding(`=`) 부재.
    final base64UrlOnly = RegExp(r'^[A-Za-z0-9_-]+$');

    test('byteLength 16 → 22 chars (LINE / Yahoo!JP 계약)', () {
      final nonce = generateNonce(byteLength: 16);

      expect(nonce.length, 22);
      expect(base64UrlOnly.hasMatch(nonce), isTrue);
      expect(nonce, isNot(contains('=')));
    });

    test('byteLength 32 → 43 chars (Kakao 계약)', () {
      final nonce = generateNonce(byteLength: 32);

      expect(nonce.length, 43);
      expect(base64UrlOnly.hasMatch(nonce), isTrue);
      expect(nonce, isNot(contains('=')));
    });

    test('padding 을 복원하면 요청한 byteLength 로 정확히 디코딩된다', () {
      for (final byteLength in <int>[16, 32]) {
        final nonce = generateNonce(byteLength: byteLength);
        final padded = nonce.padRight((nonce.length + 3) ~/ 4 * 4, '=');

        expect(base64Url.decode(padded).length, byteLength);
      }
    });

    test('100 회 생성 시 모두 unique (Random.secure 검증)', () {
      final nonces = <String>{
        for (var i = 0; i < 100; i++) generateNonce(byteLength: 16),
      };

      expect(nonces.length, 100);
    });
  });
}
