// Phase 16.10 D-07 — 끊기 callable 의 재로그인 custom token 발급 helper.
//
// 재로그인이 필요한 provider(Naver · LINE)의 끊기 callable 은 소유 대조와
// provider 측 끊기가 끝난 뒤 caller uid 로 custom token 을 만들어 돌려준다.
// client 는 탈퇴 진행 화면에서만 그 토큰으로 `signInWithCustomToken` 을 해
// `auth_time` 을 갱신한다 — 탈퇴 5분 신선도를 이 로그인이 겸한다 (D-07 ·
// RESEARCH Q3). 해제(D-09)는 신선도가 필요 없어 토큰을 쓰지 않는다.
//
// **재로그인일 뿐 가입 · 연결이 아니다 (quick 260928-jwe 원칙):** developer
// claims 0 · 프로필(displayName · photoURL · email) 갱신 0 · identity_index ·
// users 문서 write 0. 발급 대상 uid 는 호출자가 `request.auth.uid` 로만
// 넘긴다 (입력 uid 0 — T-16.10-12).
//
// **PII 금지 (C-06):** 발급한 토큰 문자열 · uid 는 로그에 싣지 않는다. 실패
// 로그 payload 는 `{event, provider, code}` 뿐이다.
import {getAuth} from "firebase-admin/auth";
import * as logger from "firebase-functions/logger";

import {serverFailure} from "./custom_token_errors";

/**
 * 끊기 callable 이 돌려줄 재로그인 custom token 을 발급한다 (Phase 16.10
 * D-07).
 *
 * `getAuth().createCustomToken(uid)` 만 호출한다 — developer claims ·
 * 프로필 갱신 없음. 발급 실패는 Admin SDK 결함이므로 `internal` 로 매핑하고
 * `err.name` 만 fingerprint 로 남긴다 (`err.message` 미로깅).
 *
 * @param {{uid: string, provider: string}} args 발급 대상 uid
 *     (`request.auth.uid`) 와 로그 축 provider 슬러그.
 * @return {Promise<string>} 발급된 custom token — 호출자 응답에만 싣는다.
 * @throws {HttpsError} 발급 실패 → `internal` / `errorUnknown`.
 */
export async function mintReloginToken(args: {
  uid: string;
  provider: string;
}): Promise<string> {
  try {
    return await getAuth().createCustomToken(args.uid);
  } catch (err: unknown) {
    logger.error(
      {
        event: "disconnect_relogin_token_failed",
        provider: args.provider,
        code: err instanceof Error ? err.name : "unknown",
      },
      "createCustomToken threw",
    );
    throw serverFailure();
  }
}
