// debug reauth-login-auto-merge (2026-09-17) — Custom Token callable caller 판정.
//
// 4 Custom Token callable (kakao / naver / line / yahoojp) 은 미인증 · 익명 ·
// 정식 로그인 caller 를 모두 받는다. 익명 caller 는 "익명 → 소셜 승격" 이라
// 새 identity 를 caller uid 에 등록하는 것이 설계지만, 정식 로그인 caller 가
// 같은 경로를 타면 사용자 동의 없는 provider 연결 + 프로필 덮어쓰기가 된다
// (재인증 로그인 화면에서 실제 도달). `resolveIdentity` 가 두 caller 를
// 구분할 수 있도록 판정을 한 곳에 둔다.

/**
 * onCall `request.auth` 중 caller 판정에 필요한 부분 shape.
 *
 * firebase-functions v2 `CallableRequest.auth` 는 `{uid, token, rawToken}` 이며
 * `token` 은 검증된 Firebase ID Token (DecodedIdToken) 이다.
 */
type CallerAuthLike = {
  uid: string;
  token?: {firebase?: {sign_in_provider?: string}};
};

/**
 * caller 세션이 익명 로그인인지 판정한다.
 *
 * Firebase ID Token 의 `firebase.sign_in_provider` claim 이 `"anonymous"` 일
 * 때만 `true` 다 (`link_custom_token_provider.ts` 의 익명 거부와 같은 claim).
 * claim 이 없거나 다른 값이면 `false` — 호출자는 이를 **비익명** 으로 다뤄
 * 가드를 적용한다 (fail-closed). 미인증 호출(`auth` 부재)은 caller 가 없으므로
 * `false` 를 돌려주며, `callerUid` 도 없어 가드 대상이 아니다.
 *
 * @param {CallerAuthLike | undefined} auth onCall `request.auth`.
 * @return {boolean} 익명 로그인 세션이면 true.
 */
export function isAnonymousCaller(auth: CallerAuthLike | undefined): boolean {
  return auth?.token?.firebase?.sign_in_provider === "anonymous";
}
