// Phase 17.5 — see ROADMAP.md (D-10 · D-11) — rate limit 문서 id 용 이메일 해시.
//
// kit 메일 callable 2개(`sendVerificationMail` · `sendPasswordResetMail`)가
// 같은 주소 축 counter 를 쓴다. 문서 id 에 이메일 원문을 남기지 않는다
// (`shared/rate_limit.ts` 헤더 · 로그 PII 0 계약과 같은 이유).
import {createHash} from "node:crypto";

// 해시 앞부분 길이는 IP 해시(`shared/client_ip_hash.ts`)와 같은 상수를 쓴다.
import {HASH_HEX_LENGTH} from "../shared/client_ip_hash";

/**
 * 이메일 주소를 rate limit 문서 id 용 해시로 바꾼다 (D-10 · D-11).
 *
 * 앞뒤 공백을 지우고 소문자로 맞춘 뒤 SHA-256 앞 32 hex 를 돌려준다 —
 * `A@Example.com` 과 ` a@example.com ` 은 같은 counter 를 쓴다. 충돌 저항만
 * 있으면 되고 역산 방지가 목적이 아니므로 salt 는 쓰지 않는다
 * (`shared/client_ip_hash.ts` 의 IP 해시와 같은 판단).
 *
 * @param {string} email 이메일 주소 (신뢰할 수 없는 입력이어도 된다).
 * @return {string} 32자 hex 해시.
 */
export function hashEmail(email: string): string {
  return createHash("sha256")
    .update(email.trim().toLowerCase())
    .digest("hex")
    .slice(0, HASH_HEX_LENGTH);
}
