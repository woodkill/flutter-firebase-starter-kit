// rate limit 문서 id 용 클라이언트 IP 해시 — IP 축 counter 를 쓰는 callable
// (`lookupSignInMethods` · `sendPasswordResetMail`)이 같은 함수를 쓴다.
// 한쪽만 바뀌어(예: salt 도입) IP 축 counter 모양이 갈리는 일을 막는다.
import {createHash} from "node:crypto";

/**
 * rate limit 문서 id 에 넣는 해시 앞부분 길이 (hex 자리 수).
 *
 * IP 해시와 이메일 해시(`email/email_hash.ts` `hashEmail`)가 같은 값을 쓴다.
 */
export const HASH_HEX_LENGTH = 32;

/**
 * 클라이언트 IP 를 rate limit 문서 id 용 해시로 바꾼다.
 *
 * IP 는 개인정보로 취급될 수 있으므로 원문을 Firestore 문서 id 에 남기지
 * 않는다. 충돌 저항만 있으면 되고 역산 방지가 목적이 아니므로 salt 없는
 * SHA-256 의 앞 [HASH_HEX_LENGTH] hex 만 쓴다.
 *
 * @param {string} ip 클라이언트 IP.
 * @return {string} 32자 hex 해시.
 */
export function hashClientIp(ip: string): string {
  return createHash("sha256")
    .update(ip)
    .digest("hex")
    .slice(0, HASH_HEX_LENGTH);
}
