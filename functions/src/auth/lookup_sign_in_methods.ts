// Phase 16 — see ROADMAP.md (Plan 16-02 가 본체 채움 — Wave 0 sentinel placeholder).
//
// Pattern 4 (RESEARCH § Pattern 4 lookupSignInMethods Example line 606~692):
//   D-09 native branch + D-10 3층 — 이메일 충돌 시 기존 provider 조회 + 가이드.
//
// 본 file 은 Wave 0 sentinel placeholder — Plan 16-02 가 본체 채움.
import {onCall, HttpsError} from "firebase-functions/https";

type LookupSignInMethodsRequest = {
  email: string;
};

type LookupSignInMethodsResponse = {
  providers: string[];
};

/**
 * 이메일 충돌 시 기존 provider 조회
 * (Phase 16 D-09 native branch + D-10 3층 fallback).
 *
 * **Wave 0 sentinel placeholder** — Plan 16-02 가 본체 채움.
 *
 * 본체 구현 시 mirror source: functions/src/auth/line_custom_token.ts (Phase 14).
 * - request.auth null check → HttpsError "unauthenticated".
 * - enforceAppCheck: true (Phase 12 D-11 carry-forward).
 * - admin.auth().getUserByEmail(email) + provider list 추출.
 */
export const lookupSignInMethods = onCall<
  LookupSignInMethodsRequest,
  Promise<LookupSignInMethodsResponse>
>({enforceAppCheck: true}, async (request) => {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "errorUnauthenticated");
  }
  throw new HttpsError(
    "unimplemented",
    "Plan 16-02 가 본체를 채움 — sentinel placeholder",
  );
});
