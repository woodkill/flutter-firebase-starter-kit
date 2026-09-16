/**
 * onCall `request.auth` fixture helper (debug reauth-login-auto-merge).
 *
 * 4 Custom Token callable 은 caller 가 익명인지를
 * `request.auth.token.firebase.sign_in_provider` 로 판정한다. 실제 Firebase
 * ID Token 은 이 claim 을 항상 싣지만 (익명 로그인 = `"anonymous"`, Custom
 * Token 로그인 = `"custom"`), 기존 fixture 는 `{uid}` 만 담아 실제 요청과
 * 달랐다. 판정이 fail-closed(표시 없음 = 비익명) 이므로 익명 시나리오 fixture
 * 는 본 helper 로 claim 을 명시한다.
 */

/** onCall `request.auth` 의 테스트용 부분 shape. */
export type CallerAuthFixture = {
  uid: string;
  token: {firebase: {sign_in_provider: string}};
};

/**
 * 익명 로그인 세션 caller 의 `request.auth` fixture 를 만든다.
 *
 * @param {string} uid 익명 사용자 UID.
 * @return {CallerAuthFixture} `sign_in_provider: "anonymous"` claim 포함.
 */
export function anonymousCallerAuth(uid: string): CallerAuthFixture {
  return {uid, token: {firebase: {sign_in_provider: "anonymous"}}};
}

/**
 * 정식 로그인 세션 caller 의 `request.auth` fixture 를 만든다.
 *
 * @param {string} uid 정식 사용자 UID.
 * @param {string} signInProvider ID Token `firebase.sign_in_provider` 값
 *     (Custom Token 세션 기본값 `"custom"`).
 * @return {CallerAuthFixture} 비익명 claim 포함.
 */
export function signedInCallerAuth(
  uid: string,
  signInProvider = "custom",
): CallerAuthFixture {
  return {uid, token: {firebase: {sign_in_provider: signInProvider}}};
}
