// Phase 16 — see ROADMAP.md (Plan 16-02 Task 2.1).
//
// Pattern 3 (RESEARCH § Pattern 3 deleteUserAccount line 518~600):
//   D-06 + D-07 + D-08 — hard delete callable. fresh ID Token verify +
//   Firestore batched delete + admin.auth().deleteUser (idempotent retry-safe).
//
// 5층 안전망 §7-A/B/C:
// - §7-A: Firebase Admin SDK 공식 함수만 사용 (verifyIdToken / deleteUser /
//   runTransaction). 자체 JWT decode 0 (Pitfall 3 회피).
// - §7-B: T-16-NEW-03 (transaction order) / T-16-NEW-04 (deleteUser
//   non-idempotent) / T-16-NEW-07 (PII) mitigation.
// - §7-C: jest mock 한계 — 실 단말 backend tier UAT (Plan 16-07 A2/A5/A8)
//   가 ground truth (memory feedback_mock_transaction_constraint mirror).
import {getAuth} from "firebase-admin/auth";
import {getFirestore} from "firebase-admin/firestore";
import {onCall, HttpsError} from "firebase-functions/https";
import * as logger from "firebase-functions/logger";

import {assertFreshAuth} from "../shared/reauth";
import {fingerprintError} from "./identity_index";

type DeleteUserAccountRequest = {
  /** current Firebase user 의 fresh ID Token (5분 이내 로그인 의무). */
  idToken: string;
};

type DeleteUserAccountResponse = {
  ok: true;
};

/**
 * 사용자 회원탈퇴 (hard delete) callable (Phase 16 D-06/D-07/D-08).
 *
 * 흐름 (RESEARCH Pattern 3 verbatim):
 *   Step 0: input + request.auth 검증.
 *   Step 1: D-06 reauth ID Token freshness verify
 *           (`verifyIdToken(idToken, checkRevoked=true)` + auth_time 300s
 *           boundary + uid === request.auth.uid).
 *   Step 2: D-07 Firestore batched delete — "all reads before all writes"
 *           invariant. identity_index where query 는 transaction **외부** 의무
 *           (Pitfall 2 회피, collection query 는 transaction 안 금지).
 *   Step 3: D-08 admin.auth().deleteUser — idempotent retry-safe.
 *           auth/user-not-found catch 는 success path treat (Pitfall 1 회피).
 *
 * **PII 금지 (T-16-NEW-07 mitigation)**: logger payload 는 `{event, uid}` 만.
 * idToken / decoded.email / err.message 본문 절대 노출 금지
 * (Phase 12.1 D-40 PII regression sentinel mirror).
 *
 * @param {{data: DeleteUserAccountRequest, auth?: {uid: string}}} request
 *     onCall request — data 의무, auth optional (Step 0 에서 검증).
 * @return {Promise<DeleteUserAccountResponse>} `{ok: true}` on success.
 */
export const deleteUserAccount = onCall<DeleteUserAccountRequest>(
  {enforceAppCheck: true},
  async (request): Promise<DeleteUserAccountResponse> => {
    // Step 0: auth + input validation.
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "errorUnauthenticated");
    }
    const callerUid = request.auth.uid;
    const idToken = request.data?.idToken;
    if (!idToken) {
      throw new HttpsError("invalid-argument", "errorInvalidArgument");
    }

    // Step 1: D-06 — ID Token freshness verify (5분 boundary).
    let decoded;
    try {
      decoded = await getAuth().verifyIdToken(idToken, true /* checkRevoked */);
    } catch (err: unknown) {
      const errCode = fingerprintError(err);
      logger.warn(
        {event: "delete_user_id_token_verify_failed", code: errCode},
        "verifyIdToken threw",
      );
      throw new HttpsError(
        "unauthenticated",
        "errorReauthenticationRequired",
      );
    }
    if (decoded.uid !== callerUid) {
      throw new HttpsError("permission-denied", "errorUnauthenticated");
    }
    // WR-11: 누락 / 미래값 / 상한을 공용 helper 로 한 번에 검사한다.
    // 이전 인라인 구현은 auth_time 이 없으면 NaN > 300 === false 로
    // **통과** 했고, 미래값(시계 오차)도 무조건 통과했다.
    assertFreshAuth(decoded.auth_time);

    // Step 2: D-07 — Firestore batched delete.
    //
    // Pitfall 2 (memory feedback_mock_transaction_constraint) 회피:
    //   identity_index where query 는 transaction 외부 실행 (collection query
    //   는 transaction 안 금지). transaction body 안은 tx.delete (write) 만.
    const db = getFirestore();
    const userRef = db.collection("users").doc(callerUid);
    let identityCount = 0;
    try {
      // (transaction 외부 read — collection query 는 transaction 금지)
      const idxSnaps = await db
        .collection("identity_index")
        .where("firebaseUid", "==", callerUid)
        .get();
      const idxDocIds = idxSnaps.docs.map((d) => d.id);
      identityCount = idxDocIds.length;

      // (transaction 안은 write only — Pitfall 2 invariant 의무)
      await db.runTransaction(async (tx) => {
        for (const idxDocId of idxDocIds) {
          tx.delete(db.collection("identity_index").doc(idxDocId));
        }
        tx.delete(userRef);
      });
      logger.info(
        {
          event: "delete_user_firestore_done",
          uid: callerUid,
          identityCount,
        },
        "Firestore cleaned",
      );
    } catch (err: unknown) {
      const errCode = fingerprintError(err);
      logger.error(
        {event: "delete_user_firestore_failed", uid: callerUid, code: errCode},
        "Firestore delete threw",
      );
      throw new HttpsError("internal", "errorUnknown");
    }

    // Step 3: D-08 — admin.auth().deleteUser (idempotent retry-safe).
    //
    // Pitfall 1 (admin.auth().deleteUser non-idempotent) 회피:
    //   auth/user-not-found 의 catch 는 success path treat — 이미 삭제된 user
    //   의 두 번째 호출 (client retry) 도 {ok: true} 반환. Cloud Logging 의
    //   delete_user_auth_already_done event 가 retry 시 indicator.
    try {
      await getAuth().deleteUser(callerUid);
      logger.info(
        {event: "delete_user_auth_done", uid: callerUid},
        "Auth user deleted",
      );
    } catch (err: unknown) {
      const errCode = fingerprintError(err);
      if (errCode === "auth/user-not-found") {
        logger.info(
          {event: "delete_user_auth_already_done", uid: callerUid},
          "Auth user already deleted (idempotent retry path)",
        );
        return {ok: true};
      }
      logger.error(
        {event: "delete_user_auth_failed", uid: callerUid, code: errCode},
        "deleteUser threw",
      );
      throw new HttpsError("internal", "errorUnknown");
    }

    return {ok: true};
  },
);
