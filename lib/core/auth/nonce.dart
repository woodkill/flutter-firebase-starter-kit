/// OIDC nonce 생성 · 해시 단일 진실원 (IN-05 — Phase 7 review).
///
/// Kakao / LINE / Yahoo!JP 3개 SDK wrapper 가 `Random.secure()` +
/// `base64UrlEncode` + padding 제거로 **동일한** 구현을 각자 복제하고
/// 있었다. 알고리즘이 3곳에 흩어져 있으면 한 곳만 수정될 구조이므로
/// (예: padding 정책 변경) 본 helper 로 모은다.
///
/// Facebook iOS Limited Login (debug ios-facebook-limited-login) 은 raw
/// nonce 의 SHA-256 hex 를 로그인 요청에 싣고 해시 전 원문을 Firebase 에
/// 넘기므로, 해시 helper [hashNonceSha256Hex] 도 같은 곳에 둔다.
library;

import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

/// 암호학적으로 안전한 raw nonce 를 생성한다.
///
/// [byteLength] 바이트를 `Random.secure()` (OS CSPRNG) 로 뽑아
/// base64url 로 인코딩하고 `=` padding 을 제거한 문자열을 반환한다.
///
/// **`Random()` (MT19937 — 예측 가능) 사용 금지.** nonce 예측이 가능하면
/// replay / token 주입 vector 가 열린다.
///
/// **provider 별 [byteLength] 차이 (근거 단일 기록):**
/// - Kakao — 32 bytes (43 chars). Phase 12 Pitfall 2 도입 시 채택한 값.
/// - LINE / Yahoo!JP — 16 bytes (22 chars). RFC 7636 의 PKCE
///   `code_verifier` 권장 하한과 동등 (D-LINE-06 / D-YJP-04).
/// - Facebook (iOS Limited Login) — 32 bytes (43 chars). Kakao 와 같은 값을
///   채택했다 (debug ios-facebook-limited-login).
/// - Naver 웹 경로 state — 16 bytes (22 chars). LINE / Yahoo!JP 와 동일
///   (Phase 16.5 D-14).
///
/// 길이 모두 보안상 충분하며 값 차이는 도입 시점의 선택일 뿐 provider
/// 계약이 요구하는 제약이 아니다 — 통일이 필요해지면 본 문서와 호출부만
/// 보면 된다.
String generateNonce({required int byteLength}) {
  final random = Random.secure();
  final bytes = List<int>.generate(byteLength, (_) => random.nextInt(256));
  return base64UrlEncode(bytes).replaceAll('=', '');
}

/// [rawNonce] 의 SHA-256 digest 를 소문자 hex 64자 문자열로 반환한다.
///
/// Firebase iOS 문서 "Implement Facebook Limited Login" 계약 (verbatim):
/// - "You will send the SHA-256 hash of the nonce with your sign-in request,
///   which Facebook will pass unchanged in the response."
/// - "Firebase validates the response by hashing the original nonce and
///   comparing it to the value passed by Facebook."
///
/// 따라서 로그인 요청 (`FacebookAuth.login(nonce:)`) 에는 본 함수의
/// 반환값을, Firebase credential 의 `rawNonce` 에는 **해시 전 원문**을
/// 넘긴다. 둘을 바꿔 넣으면 해시 비교가 어긋나 Firebase 가 거부한다
/// (firebase-ios-sdk #12976 — rawNonce 에 해시값을 넣은 실수 사례).
/// 문서 예시의 hex 포맷은 `%02x` (소문자) 다.
///
/// 입력은 UTF-8 로 인코딩한다. [generateNonce] 출력은 base64url ASCII 라
/// 인코딩 차이가 생기지 않는다.
String hashNonceSha256Hex(String rawNonce) {
  // crypto 의 Digest.toString() 은 소문자 hex 를 돌려준다 (KAT 테스트가 고정).
  return sha256.convert(utf8.encode(rawNonce)).toString();
}
