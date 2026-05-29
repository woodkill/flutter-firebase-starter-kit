// Phase 16 — see ROADMAP.md (Plan 16-02 Task 2.2).
//
// Pattern 4 (RESEARCH § Pattern 4 lookupSignInMethods line 606~692):
//   D-09 native branch + D-10 3층 — native (Google/Apple/Facebook/Email)
//   account-exists-with-different-credential catch path 의 server-side
//   provider lookup. App Check + UID 별 rate limit + log alarm 3층 방어.
//
// 5층 안전망 §7-A/B/C:
// - §7-A: admin.auth().getUserByEmail + Firestore identity_index where query
//   공식 함수만 사용 (자체 verifier 0).
// - §7-B: T-16-NEW-02 (email enumeration) / T-16-NEW-07 (PII) mitigation.
// - §7-C: jest mock 한계 — 실 단말 backend tier UAT (Plan 16-07 A1/A4)
//   가 ground truth.
import {getAuth} from "firebase-admin/auth";
import {getFirestore, FieldValue, Timestamp} from "firebase-admin/firestore";
import {onCall, HttpsError} from "firebase-functions/https";
import * as logger from "firebase-functions/logger";

import {fingerprintError} from "./identity_index";

type LookupSignInMethodsRequest = {
  /** lookup 대상 이메일. */
  email: string;
};

type LookupSignInMethodsResponse = {
  /**
   * 매핑된 provider 슬러그 (`google` / `apple` / `facebook` / `email` /
   * `kakao` / `naver` / `line` / `yahoojp`) 또는 미존재 시 `null`.
   */
  existingProvider: string | null;
};

/** Firebase Auth providerId → ProviderId enum 슬러그 매핑 (native 4종). */
const NATIVE_PROVIDER_MAP: Record<string, string> = {
  "google.com": "google",
  "apple.com": "apple",
  "facebook.com": "facebook",
  "password": "email",
};

/** Custom Token provider 4종 — identity_index 의 `provider` 필드 값. */
const CUSTOM_TOKEN_PROVIDERS = ["kakao", "naver", "line", "yahoojp"] as const;

/** D-10 rate limit — UID 별 10 / 60s. */
const RATE_LIMIT = 10;
const RATE_WINDOW_SEC = 60;

/**
 * 이메일 → 기존 sign-in provider 조회 callable (Phase 16 D-09 + D-10).
 *
 * 흐름 (RESEARCH Pattern 4 verbatim):
 *   Step 0: input + request.auth 검증 (enforceAppCheck:true — D-10 1층).
 *   Step 1: D-10 rate limit — UID 별 10/min Firestore counter
 *           (Phase 9.1 race-fix 패턴 mirror). 초과 시 logger.warn
 *           `email_enumeration_suspected` (D-10 3층) + throw resource-exhausted.
 *   Step 2: D-09 — admin.auth().getUserByEmail + providerData 매핑.
 *           native (google/apple/facebook/password) 우선.
 *   Step 3: providerData 비어있다 → identity_index where firebaseUid +
 *           provider in [kakao,naver,line,yahoojp] limit 1 → Custom Token user.
 *   Step 4: auth/user-not-found catch → return {existingProvider: null}
 *           (silent — caller falls back to unknown).
 *
 * **PII 금지 (T-16-NEW-07 mitigation)**: logger payload 는 `{event, uid, code}`
 * 만. email 본문 / err.message 절대 노출 금지.
 *
 * @param {{data: LookupSignInMethodsRequest, auth?: {uid: string}}} request
 *     onCall request.
 * @return {Promise<LookupSignInMethodsResponse>} `{existingProvider}`.
 */
export const lookupSignInMethods = onCall<LookupSignInMethodsRequest>(
  {enforceAppCheck: true},
  async (request): Promise<LookupSignInMethodsResponse> => {
    // Step 0: auth + input validation.
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "errorUnauthenticated");
    }
    const callerUid = request.auth.uid;
    const email = request.data?.email;
    if (!email || typeof email !== "string") {
      throw new HttpsError("invalid-argument", "errorInvalidArgument");
    }

    const db = getFirestore();

    // Step 1: D-10 — rate limit (UID 별 10/min).
    // Phase 9.1 race-fix counter 패턴 mirror — Firestore transaction-protected.
    const rateRef = db
      .collection("rate_limits")
      .doc(`lookupSignInMethods:${callerUid}`);
    try {
      await db.runTransaction(async (tx) => {
        const snap = await tx.get(rateRef);
        const now = Timestamp.now();
        const data = snap.exists ?
          (snap.data() as {count: number; windowStart: Timestamp}) :
          null;
        if (!data || now.seconds - data.windowStart.seconds > RATE_WINDOW_SEC) {
          tx.set(rateRef, {count: 1, windowStart: now});
        } else if (data.count >= RATE_LIMIT) {
          // D-10 3층 — email enumeration suspected alarm.
          // PII 금지 — email 본문 미노출, uid + count 만.
          logger.warn(
            {
              event: "email_enumeration_suspected",
              uid: callerUid,
              count: data.count,
            },
            "rate limit exceeded",
          );
          throw new HttpsError(
            "resource-exhausted",
            "errorTooManyRequests",
          );
        } else {
          tx.update(rateRef, {count: FieldValue.increment(1)});
        }
      });
    } catch (err: unknown) {
      if (err instanceof HttpsError) {
        throw err;
      }
      const errCode = fingerprintError(err);
      logger.warn(
        {event: "lookup_rate_limit_failed", uid: callerUid, code: errCode},
        "rate limit transaction threw",
      );
      throw new HttpsError("internal", "errorUnknown");
    }

    // Step 2: D-09 native branch + Step 3 Custom Token fallback.
    try {
      const user = await getAuth().getUserByEmail(email);
      const providerData = user.providerData || [];

      // (Step 2) native provider 우선 매핑.
      const knownProviderIds = Object.keys(NATIVE_PROVIDER_MAP);
      const foundNative = providerData.find((p) =>
        knownProviderIds.includes(p.providerId),
      );
      if (foundNative) {
        return {
          existingProvider: NATIVE_PROVIDER_MAP[foundNative.providerId] ?? null,
        };
      }

      // (Step 3) providerData 가 비어있거나 native 매칭 0 → Custom Token user
      // 추정. identity_index where firebaseUid == user.uid + provider in
      // [4 Custom Token provider] limit 1.
      const idxSnap = await db
        .collection("identity_index")
        .where("firebaseUid", "==", user.uid)
        .where("provider", "in", CUSTOM_TOKEN_PROVIDERS)
        .limit(1)
        .get();
      if (!idxSnap.empty) {
        const idxData = idxSnap.docs[0].data() as {provider?: string};
        return {existingProvider: idxData.provider ?? null};
      }
      return {existingProvider: null};
    } catch (err: unknown) {
      const errCode = fingerprintError(err);
      if (errCode === "auth/user-not-found") {
        // Step 4 — expected silent path (caller falls back to unknown).
        return {existingProvider: null};
      }
      // PII 금지 — email 본문 미노출, code fingerprint 만.
      logger.warn(
        {event: "lookup_sign_in_methods_failed", code: errCode},
        "getUserByEmail threw",
      );
      throw new HttpsError("internal", "errorUnknown");
    }
  },
);
