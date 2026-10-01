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
//
// Phase 17 — see ROADMAP.md (D-16 · D-40). 삭제 순서는
//   검증 → Storage `users/{uid}/` (D-40 · 실패 = 탈퇴 중단)
//   → Auth (WR-09) → Firestore → `users/{uid}/fcmTokens` 재귀 삭제 (D-02).
import {getAuth} from "firebase-admin/auth";
import {getFirestore} from "firebase-admin/firestore";
import {getStorage} from "firebase-admin/storage";
import {onCall, HttpsError} from "firebase-functions/https";
import * as logger from "firebase-functions/logger";

import {reauthenticationRequired} from "../shared/custom_token_errors";
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
 * Firestore transaction 1건이 수행할 수 있는 write 상한 (WR-09).
 *
 * Firestore 제약은 500 이며, 본 함수는 identity_index 문서들 + `users/{uid}`
 * 1건을 함께 지우므로 청크 크기는 여기서 1을 뺀 값을 쓴다.
 */
const MAX_DELETES_PER_TRANSACTION = 500;

/**
 * Storage 정리 실패로 탈퇴를 중단할 때 `HttpsError.details.reason` 값
 * (Phase 17 D-40).
 *
 * 클라이언트는 이 reason 으로 「일시적 오류 — 다시 시도」 를 구분한다
 * (`SettingsRepository._mapDeleteError` 의 reason arm → `ServiceUnavailable`
 * — Phase 17 plan 11).
 */
export const STORAGE_CLEANUP_FAILED_REASON = "storage_cleanup_failed";

/**
 * 문서 ID 배열을 [size] 이하 청크로 나눈다 (WR-09 상한 가드).
 *
 * 입력이 비어 있어도 **빈 청크 1개** 를 돌려준다 — 호출부가 identity_index
 * 문서가 하나도 없을 때에도 `users/{uid}` 삭제를 반드시 수행해야 하기
 * 때문이다.
 *
 * @param {Array<string>} docIds 삭제 대상 문서 ID 목록.
 * @param {number} size 청크 최대 크기 (1 이상).
 * @return {Array<Array<string>>} 최소 1개 이상의 청크.
 */
function chunkDocIds(docIds: string[], size: number): string[][] {
  if (docIds.length === 0) return [[]];
  const chunks: string[][] = [];
  for (let i = 0; i < docIds.length; i += size) {
    chunks.push(docIds.slice(i, i + size));
  }
  return chunks;
}

/**
 * 사용자 회원탈퇴 (hard delete) callable (Phase 16 D-06/D-07/D-08).
 *
 * 흐름 (RESEARCH Pattern 3 verbatim):
 *   Step 0: input + request.auth 검증.
 *   Step 1: D-06 reauth ID Token freshness verify
 *           (`verifyIdToken(idToken, checkRevoked=true)` + auth_time 300s
 *           boundary + uid === request.auth.uid).
 *   Step 1.5: Phase 17 D-40 — Cloud Storage `users/{uid}/` prefix 삭제.
 *           실패 시 `unavailable` + `details.reason`
 *           `storage_cleanup_failed` 로 탈퇴를 **중단**한다 (Auth · Firestore
 *           무변경 → 사용자 재시도 가능).
 *   Step 2: D-08 admin.auth().deleteUser — idempotent retry-safe.
 *           auth/user-not-found catch 는 success path treat (Pitfall 1 회피).
 *   Step 3: D-07 Firestore cleanup — "all reads before all writes" invariant.
 *           identity_index where query 는 transaction **외부** 의무
 *           (Pitfall 2 회피, collection query 는 transaction 안 금지).
 *   Step 4: Phase 17 D-02 정정 — `users/{uid}/fcmTokens` 서브컬렉션을
 *           `db.recursiveDelete` 로 지운다. 실패해도 `ok: true` (orphan 로그 ·
 *           TTL D-33 이 30일 안에 정리). 트랜잭션 **밖** 단계라 jest mock 이
 *           reads-before-writes 를 강제하지 않는 한계(memory
 *           feedback_mock_transaction_constraint)에 새 위험을 더하지 않는다.
 *
 * **삭제 순서 (Phase 17 — see ROADMAP.md, D-16 · D-40)**: 검증 → Storage
 * (D-40 · 실패 = 중단) → Auth (WR-09) → Firestore → fcmTokens. Storage 를 Auth 뒤에 두면
 * Storage 실패 시 계정이 이미 없어 사용자가 재시도할 수 없고 개인 사진이
 * 영구 잔존하므로 Storage 는 Auth **앞**에 둔다. 사진만 지워지고 Auth 삭제가
 * 실패한 상태는 D-40 이 수용한다 (소셜 사진 fallback · 재업로드 가능).
 *
 * **WR-09 (Phase 15 리뷰) 순서 계약**: Auth 삭제가 Firestore 삭제보다 **먼저**
 * 다. Auth 삭제 실패 시에는 Firestore 가 아무것도 지워지지 않아 (Storage 는
 * Step 1.5 에서 이미 정리 — D-40 수용) 사용자가 그대로 재시도할 수 있고,
 * Firestore cleanup 실패 시에는 계정 없는 uid 를 가리키는 고아 문서만 남는다.
 * 순서를 되돌리면 "탈퇴 실패 메시지 + 데이터는 이미 소실 + 계정 분열" 이라는
 * 최악의 상태가 재현된다.
 *
 * **PII 금지 (T-16-NEW-07 mitigation)**: logger payload 는 `{event, uid}` 만.
 * idToken / decoded.email / err.message 본문 절대 노출 금지
 * (Phase 12.1 D-40 PII regression sentinel mirror).
 *
 * **삭제 범위 (IN-08, Phase 15 리뷰 · Phase 17 D-16 갱신) — 확장 시 추가
 * 의무:**
 * - Cloud Storage `users/{uid}/` prefix 아래 객체 전부 (프로필 사진 등 —
 *   Step 1.5 · 슬래시 종결 prefix 로 `users/{uid}2/…` 오매칭 방지)
 * - `identity_index` 중 `firebaseUid == uid` 인 문서 전부
 * - `users/{uid}` **문서 1건**
 * - `users/{uid}/fcmTokens/*` 서브컬렉션 (Step 4 · `recursiveDelete` · 실패 =
 *   `delete_user_fcm_tokens_orphan` 로그)
 *
 * 아래는 **삭제되지 않는다.**
 * - 위에 명시하지 않은 `users/{uid}` 의 **서브컬렉션** — Firestore 특성상
 *   부모 문서 삭제로 지워지지 않는다. 기능을 확장해 서브컬렉션을 추가하면
 *   조용히 고아 데이터가 남으므로 `db.recursiveDelete(...)` 단계를 여기에
 *   추가할 것.
 * - `users/{uid}/` 밖 경로의 Cloud Storage 객체 — 다른 경로에 사용자 파일을
 *   저장하도록 확장하면 Step 1.5 에 그 prefix 를 함께 추가할 것.
 *
 * 스타터킷 사용자가 데이터 모델을 확장할 때 이 항목들을 함께 갱신하지 않으면
 * 탈퇴 후에도 개인정보가 남는다.
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
      // details.reason 으로 재로그인 분기를 표시한다 (16.9 review WR-01) —
      // 같은 code 의 IdP 거부 · App Check 차단은 reason 이 없다.
      throw reauthenticationRequired();
    }
    if (decoded.uid !== callerUid) {
      throw new HttpsError("permission-denied", "errorUnauthenticated");
    }
    // WR-11: 누락 / 미래값 / 상한을 공용 helper 로 한 번에 검사한다.
    // 이전 인라인 구현은 auth_time 이 없으면 NaN > 300 === false 로
    // **통과** 했고, 미래값(시계 오차)도 무조건 통과했다.
    assertFreshAuth(decoded.auth_time);

    // Step 1.5: Phase 17 D-40 — Cloud Storage `users/{uid}/` prefix 삭제.
    //
    // Auth 삭제 **앞**에 둔다. 여기서 실패하면 아무것도 지우지 않은 채
    // 재시도 가능한 오류로 멈춘다 — Auth 뒤에 두면 실패 시 계정이 이미 없어
    // 재시도 경로가 사라지고 개인 사진이 영구 잔존한다.
    // - prefix 는 슬래시로 끝나야 한다 (`users/<uid>2/…` 오매칭 방지).
    // - `force: true` — 첫 오류에서 멈추지 않고 전부 시도한 뒤 실패 목록을
    //   `Error[]` 로 reject 한다 (재시도 1회당 진척 최대 · 멱등).
    // - 빈 prefix (사진 없음 · 이전 시도에서 이미 삭제) 는 그대로 resolve.
    // - PII: 로그에 파일 경로 · prefix 를 싣지 않는다 (uid · 오류 code 만).
    try {
      await getStorage().bucket().deleteFiles({
        prefix: `users/${callerUid}/`,
        force: true,
      });
      logger.info(
        {event: "delete_user_storage_done", uid: callerUid},
        "Storage user prefix deleted",
      );
    } catch (err: unknown) {
      const failed = Array.isArray(err) ? err : [err];
      logger.error(
        {
          event: "delete_user_storage_failed",
          uid: callerUid,
          code: fingerprintError(failed[0]),
          failedCount: failed.length,
        },
        "Storage cleanup failed — withdrawal aborted",
      );
      // 이 시점에 Auth · Firestore 는 아직 온전하다 — 사용자는 재시도 가능.
      throw new HttpsError("unavailable", "errorServiceUnavailable", {
        reason: STORAGE_CLEANUP_FAILED_REASON,
      });
    }

    // Step 2: D-08 — admin.auth().deleteUser (idempotent retry-safe).
    //
    // **WR-09 (Phase 15 리뷰) — 순서 역전:** 이전에는 Firestore 삭제를 먼저
    // 커밋하고 Auth 삭제를 뒤에 했다. Auth 삭제가 실패하면 `internal` 을
    // 반환하는데 Firestore 삭제는 **이미 되돌릴 수 없었다**. 결과 상태가
    // 최악이었다.
    // - 사용자는 여전히 로그인 가능한데 (Auth user 생존) 프로필 · 약관 동의 ·
    //   연동 provider 기록이 전부 소실 — "탈퇴 실패" 메시지를 받았는데 데이터는
    //   사라진 상태 (data loss).
    // - identity_index 가 지워졌으므로 Custom Token 재로그인 시
    //   resolveIdentity 가 신규 등록 경로를 타 **또 다른 Firebase user** 를
    //   만들거나 기존 uid 에 재매핑한다 — 탈퇴 실패가 계정 분열로 이어진다.
    //
    // Auth 를 먼저 지우면 실패 시 **아무것도 지워지지 않는다** (사용자는 그대로
    // 재시도 가능). 성공 후 Firestore cleanup 이 실패하면 계정 없는 uid 를
    // 가리키는 고아 문서만 남는다 — 아래 Step 3 참조.
    //
    // Pitfall 1 (admin.auth().deleteUser non-idempotent) 회피:
    //   auth/user-not-found 의 catch 는 success path treat — 이미 삭제된 user
    //   의 두 번째 호출 (client retry) 도 정상 진행. Cloud Logging 의
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
        // Firestore cleanup 은 계속 진행한다 — 이전 시도가 Auth 삭제 직후
        // 중단됐다면 고아 문서가 남아 있을 수 있고, cleanup 은 멱등하다.
      } else {
        logger.error(
          {event: "delete_user_auth_failed", uid: callerUid, code: errCode},
          "deleteUser threw",
        );
        // 이 시점에 Firestore 는 아직 온전하다 — 사용자는 재시도 가능.
        throw new HttpsError("internal", "errorUnknown");
      }
    }

    // Step 3: D-07 — Firestore cleanup (멱등, 재호출로 수렴).
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

      // WR-09: Firestore transaction 은 write 500건 상한이 있다. provider 수가
      // 유한해 현실적으로 도달하기 어렵지만 상한 가드 자체가 없었으므로,
      // users 문서 1건을 더한 뒤에도 상한을 넘지 않도록 청크 단위로 나눈다.
      const chunks = chunkDocIds(idxDocIds, MAX_DELETES_PER_TRANSACTION - 1);
      for (let i = 0; i < chunks.length; i += 1) {
        const chunk = chunks[i];
        const isLastChunk = i === chunks.length - 1;
        // (transaction 안은 write only — Pitfall 2 invariant 의무)
        await db.runTransaction(async (tx) => {
          for (const idxDocId of chunk) {
            tx.delete(db.collection("identity_index").doc(idxDocId));
          }
          // users 문서는 마지막 청크에서 한 번만 지운다.
          if (isLastChunk) tx.delete(userRef);
        });
      }
      logger.info(
        {
          event: "delete_user_firestore_done",
          uid: callerUid,
          identityCount,
        },
        "Firestore cleaned",
      );
    } catch (err: unknown) {
      // WR-09: 여기서 실패해도 **계정은 이미 삭제됐다**. 사용자 관점의 목표
      // (탈퇴) 는 달성됐고, caller 는 인증 수단을 잃어 재시도할 수도 없다.
      // 따라서 사용자에게 실패를 알리는 대신 ops 가 수거할 수 있도록 전용
      // event 로 error 로깅하고 성공을 반환한다. 남는 것은 존재하지 않는 uid
      // 를 가리키는 고아 문서뿐이다 (로그인 가능한 계정에 데이터만 사라지는
      // 이전 실패 모드보다 명확히 안전하다).
      logger.error(
        {
          event: "delete_user_firestore_orphan",
          uid: callerUid,
          code: fingerprintError(err),
        },
        "Auth user deleted but Firestore cleanup failed — orphan docs remain",
      );
    }

    // Step 4: Phase 17 D-02 정정 — `users/{uid}/fcmTokens` 서브컬렉션 재귀 삭제.
    //
    // 부모 `users/{uid}` 문서 삭제로는 서브컬렉션이 지워지지 않는다. Step 3
    // 트랜잭션 **뒤** 별도 try 로 둔다 — 토큰 삭제 실패가 더 중요한
    // identity_index · users 문서 삭제를 건너뛰게 하지 않기 위해서다
    // (RESEARCH §R-07 의 「identity_index 조회 앞」 안과 다른 위치).
    // 실패 정책은 Step 3 과 같다: 계정은 이미 삭제됐으므로 orphan 로그 +
    // `ok: true`. 남은 토큰 문서는 TTL(D-33)이 30일 안에 지운다.
    try {
      await db.recursiveDelete(userRef.collection("fcmTokens"));
    } catch (err: unknown) {
      logger.error(
        {
          event: "delete_user_fcm_tokens_orphan",
          uid: callerUid,
          code: fingerprintError(err),
        },
        "Auth user deleted but FCM token cleanup failed — TTL will expire",
      );
    }

    return {ok: true};
  },
);
