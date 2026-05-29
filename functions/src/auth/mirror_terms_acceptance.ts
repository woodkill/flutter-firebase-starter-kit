// Phase 16 — see ROADMAP.md (Plan 16-02 Task 2.2).
//
// Pattern 5 (RESEARCH § Pattern 5 mirrorTermsAcceptanceSnapshot line 696~762):
//   D-13 / D-14 — native (Google/Apple/Facebook/Email) sign-in 후 client 1회
//   호출. admin.firestore() users/{uid}.termsAccepted = snapshot atomic mirror.
//
// 5층 안전망 §7-A/B/C:
// - §7-A: Firestore set merge 공식 함수만 사용 (자체 verifier 0).
// - §7-B: T-16-NEW-07 (PII) / T-16-NEW-08 (schema drift) mitigation.
// - §7-C: jest mock 한계 — 실 단말 backend tier UAT (Plan 16-07 A9)
//   가 ground truth.
//
// **Schema invariant (Pitfall 4 회피)**: TermsAcceptanceJson 의 5 필드
// (version: int / service: bool / privacy: bool / marketing: bool /
// acceptedAt: ISO 8601 string) 는 client 의 TermsAcceptance Freezed model
// (lib/features/terms/domain/terms_acceptance.dart) 5 필드 verbatim mirror.
// 변경 시 client toJson 출력과 server set payload 양쪽 동시 갱신 의무.
import {getFirestore, Timestamp} from "firebase-admin/firestore";
import {onCall, HttpsError} from "firebase-functions/https";
import * as logger from "firebase-functions/logger";

import {TermsAcceptanceJson} from "../shared/terms_acceptance_json";
import {fingerprintError} from "./identity_index";

type MirrorTermsAcceptanceSnapshotRequest = {
  /** TermsAcceptance 5 필드 snapshot. */
  snapshot: TermsAcceptanceJson;
};

type MirrorTermsAcceptanceSnapshotResponse = {
  ok: true;
};

/**
 * Terms acceptance snapshot Firestore mirror callable (Phase 16 D-13/D-14).
 *
 * 흐름 (RESEARCH Pattern 5 verbatim):
 *   Step 0: input + request.auth 검증.
 *   Step 1: Firestore users/{uid}.termsAccepted = 5 필드 atomic set merge.
 *           acceptedAt 은 Timestamp.fromDate(new Date(ISO)) 로 변환.
 *
 * **PII 금지 (T-16-NEW-07 mitigation)**: logger payload 는 `{event, uid}` 만.
 * snapshot 본문 / err.message 절대 노출 금지.
 *
 * @param {{
 *   data: MirrorTermsAcceptanceSnapshotRequest,
 *   auth?: {uid: string},
 * }} request onCall request.
 * @return {Promise<MirrorTermsAcceptanceSnapshotResponse>} `{ok: true}`.
 */
export const mirrorTermsAcceptanceSnapshot = onCall<
  MirrorTermsAcceptanceSnapshotRequest
>(
  {enforceAppCheck: true},
  async (request): Promise<MirrorTermsAcceptanceSnapshotResponse> => {
    // Step 0: auth + input validation.
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "errorUnauthenticated");
    }
    const callerUid = request.auth.uid;
    const snapshot = request.data?.snapshot;
    if (!snapshot) {
      throw new HttpsError("invalid-argument", "errorInvalidArgument");
    }

    // Step 1: Firestore atomic set merge — 5 필드 verbatim
    // (Pitfall 4 schema drift 회피).
    try {
      await getFirestore()
        .collection("users")
        .doc(callerUid)
        .set(
          {
            termsAccepted: {
              version: snapshot.version,
              service: snapshot.service,
              privacy: snapshot.privacy,
              marketing: snapshot.marketing,
              acceptedAt: Timestamp.fromDate(new Date(snapshot.acceptedAt)),
            },
          },
          {merge: true},
        );
    } catch (err: unknown) {
      // PII 금지 — snapshot 본문 미노출, code fingerprint 만.
      const errCode = fingerprintError(err);
      logger.error(
        {
          event: "mirror_terms_acceptance_snapshot_failed",
          uid: callerUid,
          code: errCode,
        },
        "set merge threw",
      );
      throw new HttpsError("internal", "errorUnknown");
    }

    logger.info(
      {event: "mirror_terms_acceptance_snapshot_done", uid: callerUid},
      "terms mirrored",
    );
    return {ok: true};
  },
);
