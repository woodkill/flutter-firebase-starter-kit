// Phase 16 — see ROADMAP.md (Plan 16-02 가 본체 채움 — Wave 0 sentinel placeholder).
//
// Pattern 5 (RESEARCH § Pattern 5 mirrorTermsAcceptanceSnapshot Example
// line 696~762):
//   D-14 native callable — terms acceptance snapshot Firestore mirror.
//
// 본 file 은 Wave 0 sentinel placeholder — Plan 16-02 가 본체 채움.
import {onCall, HttpsError} from "firebase-functions/https";

type MirrorTermsAcceptanceRequest = {
  acceptedAt: string;
  termsVersion: string;
};

type MirrorTermsAcceptanceResponse = {
  mirrored: boolean;
};

/**
 * 약관 동의 snapshot 을 Firestore 에 mirror (Phase 16 D-14 native callable).
 *
 * **Wave 0 sentinel placeholder** — Plan 16-02 가 본체 채움.
 *
 * 본체 구현 시 mirror source: functions/src/auth/line_custom_token.ts (Phase 14).
 * - request.auth null check → HttpsError "unauthenticated".
 * - enforceAppCheck: true (Phase 12 D-11 carry-forward).
 * - Firestore users/{uid}.termsAcceptedAt = acceptedAt server timestamp.
 */
export const mirrorTermsAcceptanceSnapshot = onCall<
  MirrorTermsAcceptanceRequest,
  Promise<MirrorTermsAcceptanceResponse>
>({enforceAppCheck: true}, async (request) => {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "errorUnauthenticated");
  }
  throw new HttpsError(
    "unimplemented",
    "Plan 16-02 가 본체를 채움 — sentinel placeholder",
  );
});
