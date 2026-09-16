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
///
/// `hashNonceSha256Hex` 는 Facebook iOS Limited Login nonce 계약
/// (debug ios-facebook-limited-login) 의 해시 단계다. 기대값은 전부 구현
/// (crypto 패키지) 과 독립된 외부 상수이며 macOS `shasum -a 256` 로도 같은
/// 값을 교차 확인했다 — 구현 출력을 기대값으로 옮겨 적는 자기참조가 아니다.
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

    test('byteLength 32 → 43 chars (Kakao / Facebook 계약)', () {
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

  group('hashNonceSha256Hex', () {
    // Firebase iOS Limited Login 문서 예시의 sha256 은 digest 를 `%02x`
    // (소문자 2자리 hex) 로 이어 붙인다 → 소문자 hex 64자.
    final lowerHex64 = RegExp(r'^[0-9a-f]{64}$');

    test('FIPS 180-2 부록 B.1 벡터 — "abc"', () {
      expect(
        hashNonceSha256Hex('abc'),
        'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad',
      );
    });

    test('길이 0 입력 벡터 — 빈 문자열', () {
      expect(
        hashNonceSha256Hex(''),
        'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855',
      );
    });

    test('FIPS 180-2 부록 B.2 벡터 — 448 bit (2 블록 패딩) 메시지', () {
      expect(
        hashNonceSha256Hex(
          'abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq',
        ),
        '248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1',
      );
    });

    test('generateNonce 원문의 해시는 소문자 hex 64자이고 원문과 다르다', () {
      final rawNonce = generateNonce(byteLength: 32);

      final hashed = hashNonceSha256Hex(rawNonce);

      expect(lowerHex64.hasMatch(hashed), isTrue);
      expect(hashed, isNot(rawNonce));
    });
  });
}
