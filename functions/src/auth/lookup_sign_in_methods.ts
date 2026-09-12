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
//
// **IN-04**: 아래 `HttpsError` 들의 message 는 ARB 키가 아니라 taxonomy
// 토큰이다. client 는 `code` 로만 분기하며 서버 message 를 렌더하지 않는다.
// 계약 전문은 `shared/custom_token_errors.ts` 헤더 참조.
import {createHash} from "node:crypto";

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
 * WR-08 (Phase 15 리뷰) — 클라이언트 IP 별 상한.
 *
 * D-10 의 UID 별 상한은 `request.auth` 만 요구하는데 **익명 사용자도 이를
 * 만족** 하고, 익명 UID 는 `signInAnonymously` 로 무제한 생성 가능하다.
 * 공격자는 lookup 10회마다 새 익명 UID 를 발급받아 카운터를 리셋할 수 있어,
 * UID 층은 사실상 "요청당 왕복 1회 추가 비용" 이상의 방어를 제공하지 못했고
 * 3층 알람(`email_enumeration_suspected`) 도 발화하지 않았다.
 *
 * IP 층은 UID 회전으로 리셋되지 않으므로 그 우회로를 닫는다. NAT / 회사망
 * 공유를 고려해 UID 층보다 넉넉하게 잡는다 — 정상 사용자는 한 번의 충돌
 * 화면에서 한 번 호출하며, client 가 TTL 5분 캐시까지 갖고 있다.
 */
const IP_RATE_LIMIT = 60;

/** rate limit counter 문서의 해석 결과. */
type RateCounterState = {
  /** 현재 창의 카운트 (창이 만료됐으면 의미 없음). */
  count: number;
  /** 창이 없거나 만료됨 → 새 창으로 리셋해야 한다. */
  expired: boolean;
};

/**
 * rate limit counter 문서를 방어적으로 해석한다 (WR-08 부수 결함).
 *
 * 이전 구현은 `data.windowStart.seconds` 를 직접 읽어서, 문서에
 * `windowStart` 가 없으면 (부분 write / 수동 편집 / 스키마 변경 잔재)
 * `TypeError` 로 터졌다. 그 예외를 바깥 catch 가 `internal` 로 바꿨기 때문에
 * **해당 UID 의 lookup 이 영구 실패** 했다 — 문서가 자기치유되지 않았다.
 * 이제 형태가 어긋난 문서는 "만료된 창" 으로 간주해 다음 write 에서 정상
 * 문서로 덮어쓴다.
 *
 * @param {{exists: boolean, data: function(): (object|undefined)}} snap
 *     counter 문서 스냅샷.
 * @param {Timestamp} now 현재 시각.
 * @return {RateCounterState} 카운트 + 창 만료 여부.
 */
function readCounter(
  snap: {exists: boolean; data(): Record<string, unknown> | undefined},
  now: Timestamp,
): RateCounterState {
  if (!snap.exists) return {count: 0, expired: true};
  const data = snap.data();
  const windowStart = data?.windowStart;
  const rawCount = data?.count;
  // `Timestamp` 는 클래스지만 여기서 `instanceof` 를 쓰지 않는다 — 필요한
  // 것은 `seconds` 하나뿐이고, duck typing 이 Firestore Timestamp 와 그
  // 직렬화된 형태를 모두 받아준다.
  const startSeconds = (windowStart as {seconds?: unknown} | undefined)
    ?.seconds;
  if (typeof startSeconds !== "number" || !Number.isFinite(startSeconds)) {
    return {count: 0, expired: true};
  }
  if (now.seconds - startSeconds > RATE_WINDOW_SEC) {
    return {count: 0, expired: true};
  }
  const count = typeof rawCount === "number" && Number.isFinite(rawCount) ?
    rawCount :
    0;
  return {count, expired: false};
}

/**
 * 클라이언트 IP 를 rate limit 문서 ID 용 해시로 변환한다 (WR-08).
 *
 * IP 는 개인정보로 취급될 수 있으므로 원문을 Firestore 문서 ID 에 남기지
 * 않는다. 충돌 저항만 있으면 되고 역산 방지가 목적이 아니므로 salt 없는
 * SHA-256 의 앞 32 hex 만 쓴다.
 *
 * @param {string} ip 클라이언트 IP.
 * @return {string} 32자 hex 해시.
 */
function hashClientIp(ip: string): string {
  return createHash("sha256").update(ip).digest("hex").slice(0, 32);
}

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

    // Step 1: D-10 — rate limit.
    // Phase 9.1 race-fix counter 패턴 mirror — Firestore transaction-protected.
    //
    // WR-08: UID 층 하나만으로는 익명 UID 회전으로 우회되므로 IP 층을 함께
    // 평가한다. 두 counter 를 **같은 transaction** 안에서 처리하므로 왕복은
    // 그대로 1회다 ("all reads before all writes" 계약 보존 — 아래 read 를
    // 모두 끝낸 뒤에만 write 한다).
    const rateRef = db
      .collection("rate_limits")
      .doc(`lookupSignInMethods:${callerUid}`);
    // IP 는 원문을 저장하지 않는다 (PII 최소화) — 해시를 문서 ID 로 쓴다.
    // 프록시/런타임 사정으로 IP 를 못 얻으면 IP 층은 건너뛴다 (fail-open —
    // 정당한 로그인을 IP 부재만으로 막지 않는다).
    const clientIp = request.rawRequest?.ip;
    const ipRef = clientIp ?
      db
        .collection("rate_limits")
        .doc(`lookupSignInMethodsIp:${hashClientIp(clientIp)}`) :
      null;
    try {
      await db.runTransaction(async (tx) => {
        // --- reads (모두 write 앞) ---
        const uidSnap = await tx.get(rateRef);
        const ipSnap = ipRef ? await tx.get(ipRef) : null;
        const now = Timestamp.now();

        const uidState = readCounter(uidSnap, now);
        const ipState = ipSnap ? readCounter(ipSnap, now) : null;

        // --- 한도 판정 (write 전에 모두 끝낸다) ---
        const uidExceeded = !uidState.expired && uidState.count >= RATE_LIMIT;
        const ipExceeded =
          ipState !== null &&
          !ipState.expired &&
          ipState.count >= IP_RATE_LIMIT;
        if (uidExceeded || ipExceeded) {
          // D-10 3층 — email enumeration suspected alarm.
          // PII 금지 — email 본문 / IP 원문 미노출. uid + count + 어느 축이
          // 걸렸는지만 기록한다.
          logger.warn(
            {
              event: "email_enumeration_suspected",
              uid: callerUid,
              count: uidExceeded ? uidState.count : ipState?.count,
              axis: uidExceeded ? "uid" : "ip",
            },
            "rate limit exceeded",
          );
          throw new HttpsError(
            "resource-exhausted",
            "errorTooManyRequests",
          );
        }

        // --- writes ---
        if (uidState.expired) {
          tx.set(rateRef, {count: 1, windowStart: now});
        } else {
          tx.update(rateRef, {count: FieldValue.increment(1)});
        }
        if (ipRef && ipState) {
          if (ipState.expired) {
            tx.set(ipRef, {count: 1, windowStart: now});
          } else {
            tx.update(ipRef, {count: FieldValue.increment(1)});
          }
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
