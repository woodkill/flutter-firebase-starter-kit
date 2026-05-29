// Phase 16 — see ROADMAP.md (Plan 16-02 가 본체 채움 — Wave 0 sentinel placeholder).
//
// Pattern 3 (RESEARCH § Pattern 3 deleteUserAccount Example line 518~600):
//   D-06 / D-07 / D-08 — 사용자 탈퇴 (Firebase Auth + Firestore 사용자 doc 삭제).
//
// 본 file 은 Wave 0 sentinel placeholder — Plan 16-02 가 본체 채움.
import {onCall, HttpsError} from "firebase-functions/https";

type DeleteUserAccountRequest = {
  idToken: string;
};

type DeleteUserAccountResponse = {
  deleted: boolean;
};

/**
 * 사용자 탈퇴 — Firebase Auth account + Firestore user doc 삭제
 * (Phase 16 D-06 / D-07 / D-08).
 *
 * **Wave 0 sentinel placeholder** — Plan 16-02 가 본체 채움.
 *
 * 본체 구현 시 mirror source: functions/src/auth/line_custom_token.ts (Phase 14).
 * - request.auth null check → HttpsError "unauthenticated".
 * - enforceAppCheck: true (Phase 12 D-11 carry-forward).
 * - admin.auth().deleteUser(uid) + Firestore batch delete (D-08).
 */
export const deleteUserAccount = onCall<
  DeleteUserAccountRequest,
  Promise<DeleteUserAccountResponse>
>({enforceAppCheck: true}, async (request) => {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "errorUnauthenticated");
  }
  throw new HttpsError(
    "unimplemented",
    "Plan 16-02 가 본체를 채움 — sentinel placeholder",
  );
});
