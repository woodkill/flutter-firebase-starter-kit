// Phase 16.5 — see ROADMAP.md
//
// Naver 로그인 결과 — 경로별 자격증명 variant (D-13 · assumption-delta promote).
// 단일 클래스(access token 전용)를 sealed 기저로 승격했다: 1-tap(SDK) 과 킷 웹
// 흐름이 서버에 넘기는 자격증명이 서로 다르고, 호출부가 exhaustive switch 로
// callable 을 고르게 하기 위해서다.
import 'package:flutter/foundation.dart';

/// Naver 로그인 결과 — 경로에 따라 서버에 넘길 자격증명이 다르다.
///
/// `AuthRepository` 의 로그인 · 재인증 2곳이 `switch` expression 으로
/// callable(`naverCustomToken` | `naverWebCustomToken`) 과 payload 를 고른다.
/// 새 variant 가 생기면 그 switch 가 컴파일 단계에서 깨진다 — 조용한 오배선이
/// 구조적으로 불가능하다 (P-03 「시끄러운 실패는 빌드가 가드」).
///
/// optional 필드 병존(`accessToken?` + `code?`) 대신 sealed 를 쓰는 이유: 「둘
/// 다 null」 · 「둘 다 non-null」 상태를 타입이 허용하지 않게 하기 위해서다.
@immutable
sealed class NaverSignInResult {
  /// 하위 variant 전용 생성자.
  const NaverSignInResult();
}

/// 1-tap 경로 — NAVER 앱(SDK wrapper) 이 돌려준 access token.
///
/// Phase 13 D-57 1회성 토큰 — `AuthRepository` 가 Cloud Function
/// `naverCustomToken` 에 그대로 넘기고, finally 에서 기기 토큰을 즉시 지운다.
final class NaverAppSignIn extends NaverSignInResult {
  /// [accessToken] (Naver OAuth 2.0 Access Token) 묶음.
  const NaverAppSignIn({required this.accessToken});

  /// Naver Access Token (Cloud Function `/v1/nid/me` Bearer 검증 대상).
  final String accessToken;
}

/// 킷 웹 경로 — authorization code 와 클라이언트가 생성 · 검증한 state.
///
/// Phase 16.5 D-13 — 서버(`naverWebCustomToken`) 가 [code] 를 access token 으로
/// 교환한다. `client_secret` 은 서버에만 있다. [state] 는 클라이언트가 콜백의
/// 값과 이미 대조한 값이며(D-14 CSRF), 서버는 교환 파라미터로만 쓴다.
///
/// 두 필드 모두 1회용 비밀이다 — 로그 · 문자열 보간에 싣지 않는다 (WR-05).
final class NaverWebSignIn extends NaverSignInResult {
  /// [code] (authorization code) + [state] (CSRF 대조 완료 값) 묶음.
  const NaverWebSignIn({required this.code, required this.state});

  /// 콜백 URL 의 `code` — 서버가 token 엔드포인트에서 교환한다 (1회성).
  final String code;

  /// authorize 요청에 실었고 콜백에서 대조를 마친 `state`.
  final String state;
}
