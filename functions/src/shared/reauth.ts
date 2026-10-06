// Phase 15 code review WR-11 — 재인증 신선도 검사 단일 진실원.
//
// `deleteUserAccount` 와 당시의 OIDC 연결 callable(현 `linkKakaoProvider` ·
// `linkLineProvider`) 두 곳이 각각 아래 3줄을 인라인으로 갖고 있었다.
//
//   const authTime = decoded.auth_time;
//   const nowSec = Math.floor(Date.now() / 1000);
//   if (nowSec - authTime > 300) { throw ... }
//
// 결함이 셋이다.
// 1. **누락 가드 부재** — `auth_time` 이 없으면 `nowSec - undefined` 가 `NaN`
//    이고 `NaN > 300 === false` 이므로 **검사를 통과한다**. `DecodedIdToken`
//    타입상 항상 존재한다고 가정하지만, 이 값은 재인증 게이트의 유일한 신선도
//    근거이며 회원탈퇴·계정연동이라는 최고 위험 동작을 지킨다. 타입 신뢰만으로
//    방어를 생략할 자리가 아니다.
// 2. **하한 부재** — `auth_time` 이 미래값이면 (클라이언트/발급 측 시계 오차)
//    차이가 음수가 되어 무조건 통과한다.
// 3. 매직 넘버 `300` 이 두 파일에 각각 박혀 있어 정책 변경이 drift 를 만든다.
import {reauthenticationRequired} from "./custom_token_errors";

/**
 * 재인증 유효 시간 (초). 회원탈퇴 `deleteUserAccount` 의 정책 — 연결
 * callable 은 quick 260928-cxs 부터 호출하지 않는다(연결은 최근 로그인 불필요).
 */
export const REAUTH_MAX_AGE_SEC = 300;

/**
 * 허용 시계 오차 (초).
 *
 * `auth_time` 은 Firebase 가 발급하므로 정상 상황에서 미래값이 될 수 없지만,
 * 서버/클라이언트 시계 동기화 오차 정도는 흡수한다. 이 폭을 넘는 미래값은
 * 위조 또는 심각한 환경 이상이므로 거부한다.
 */
export const REAUTH_CLOCK_SKEW_SEC = 60;

/**
 * ID Token 의 `auth_time` 이 재인증 신선도 조건을 만족하는지 검사한다 (WR-11).
 *
 * @param {unknown} authTime `DecodedIdToken.auth_time` (epoch seconds).
 *     타입을 신뢰하지 않고 `unknown` 으로 받아 런타임 검증한다.
 * @return {void} 조건을 만족하면 아무것도 하지 않는다.
 * @throws {HttpsError} `unauthenticated` / `errorReauthenticationRequired` /
 *     `details.reason: "reauthentication_required"` (`reauthenticationRequired`
 *     — Phase 16.9 review WR-01) — 값이 숫자가 아니거나(누락 포함), 유한하지
 *     않거나, 허용 오차를 넘는 미래값이거나, [REAUTH_MAX_AGE_SEC] 보다
 *     오래된 경우.
 */
export function assertFreshAuth(authTime: unknown): void {
  const nowSec = Math.floor(Date.now() / 1000);
  if (
    typeof authTime !== "number" ||
    !Number.isFinite(authTime) ||
    authTime > nowSec + REAUTH_CLOCK_SKEW_SEC ||
    nowSec - authTime > REAUTH_MAX_AGE_SEC
  ) {
    // client 는 details.reason 으로만 재로그인 분기한다 — 같은 code 를
    // 쓰는 IdP 거부 · App Check 차단과 구분하기 위해서다 (WR-01).
    throw reauthenticationRequired();
  }
}
