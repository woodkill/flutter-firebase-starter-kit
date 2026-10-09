/**
 * `shared/client_ip_hash.ts` — IP 축 rate limit 문서 id 해시의 모양을 고정한다.
 *
 * `lookupSignInMethods` · `sendPasswordResetMail` 이 같은 함수를 쓰므로, 여기서
 * 값 모양(salt 없는 SHA-256 앞 32 hex)이 바뀌면 두 callable 의 IP 축 counter 가
 * 함께 바뀐다. 이메일 해시도 같은 길이 상수를 쓴다.
 */

import {createHash} from "node:crypto";

import {hashEmail} from "../../src/email/email_hash";
import {HASH_HEX_LENGTH, hashClientIp} from "../../src/shared/client_ip_hash";

describe("hashClientIp — rate limit 문서 id 용 IP 해시", () => {
  it("salt 없는 sha256 앞 32 hex 다", () => {
    const ip = "203.0.113.77";
    const hash = hashClientIp(ip);
    expect(HASH_HEX_LENGTH).toBe(32);
    expect(hash).toMatch(/^[0-9a-f]{32}$/);
    expect(hash).toBe(
      createHash("sha256").update(ip).digest("hex").slice(0, 32),
    );
    expect(hash).not.toContain(ip);
    expect(hashClientIp("203.0.113.78")).not.toBe(hash);
  });

  it("이메일 해시와 같은 길이 상수를 쓴다", () => {
    expect(hashEmail("a@example.com")).toHaveLength(HASH_HEX_LENGTH);
  });
});
