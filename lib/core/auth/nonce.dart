/// OIDC nonce 생성 단일 진실원 (IN-05 — Phase 7 review).
///
/// Kakao / LINE / Yahoo!JP 3개 SDK wrapper 가 `Random.secure()` +
/// `base64UrlEncode` + padding 제거로 **동일한** 구현을 각자 복제하고
/// 있었다. 알고리즘이 3곳에 흩어져 있으면 한 곳만 수정될 구조이므로
/// (예: padding 정책 변경) 본 helper 로 모은다.
library;

import 'dart:convert';
import 'dart:math';

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
///
/// 두 길이 모두 보안상 충분하며 값 차이는 도입 시점의 선택일 뿐 provider
/// 계약이 요구하는 제약이 아니다 — 통일이 필요해지면 본 문서와 호출부
/// 3곳만 보면 된다.
String generateNonce({required int byteLength}) {
  final random = Random.secure();
  final bytes = List<int>.generate(byteLength, (_) => random.nextInt(256));
  return base64UrlEncode(bytes).replaceAll('=', '');
}
