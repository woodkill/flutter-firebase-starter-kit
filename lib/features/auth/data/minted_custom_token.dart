// Phase 16.10 — see ROADMAP.md
//
// Custom Token 재로그인 응답 검증 (D-07 · D-08 · RESEARCH Q3).
//
// 서버가 발급한 custom token 을 소비하기 전에 응답 계약(`{customToken, uid}`)
// 과 uid 를 대조한다. 기존 재인증 경로(`AuthRepository._reauthWithCustomToken`)
// 와 provider 측 끊기 step(LINE · Naver)이 같은 규칙을 공유하도록 순수 함수로
// 둔다 — step 이 [AuthRepository] 인스턴스에 의존하지 않고, 로그는 호출자가
// 자기 맥락(재인증 · 끊기)으로 남긴다.
import '../../../core/error/app_exception.dart';

/// Custom Token 재로그인 · 끊기 callable 응답 계약(`{customToken, uid}`)을
/// 검증하고 custom token 을 돌려준다 — 다른 계정 세션 전환 차단.
///
/// [currentUid] 는 지금 로그인한 Firebase 사용자 uid 다. 응답 uid 가 이것과
/// 같을 때만 토큰을 돌려주므로, 호출자가 이 반환값으로
/// `signInWithCustomToken` 을 불러도 세션 계정은 바뀌지 않는다(D-08).
/// 부수효과 · 로그가 없다.
///
/// Throws [UnknownException] — `customToken` 이 비어 있지 않은 문자열이
/// 아니거나 `uid` 가 문자열이 아니다(서버 계약 위반).
/// Throws [ReauthUserMismatch] — 응답 uid 가 [currentUid] 와 다르다.
String requireMintedCustomToken(
  Map<String, dynamic> data, {
  required String currentUid,
}) {
  final customToken = data['customToken'];
  final uid = data['uid'];
  if (customToken is! String || customToken.isEmpty || uid is! String) {
    throw const UnknownException();
  }
  if (uid != currentUid) {
    throw const ReauthUserMismatch();
  }
  return customToken;
}
