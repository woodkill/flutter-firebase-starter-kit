// Phase 16 — see ROADMAP.md (Plan 16-02 Task 2.1).
//
// Pattern 2 (RESEARCH § Pattern 2 linkCustomTokenProvider line 436~514):
//   D-04 hybrid 2nd branch — Custom Token 관련 (native→Custom Token /
//   Custom Token→native / Custom Token↔Custom Token) link 처리.
//
// 본 callable 은 server-side admin SDK 가 identity_index/{provider}:{sub}→uid
// atomic create + users/{uid}.linkedProviders[] update + reauth ID Token
// 검증 (Firebase Admin SDK verifyIdToken) 을 수행한다.
//
// 5층 안전망 §7-A/B/C:
// - §7-A: RESEARCH Pattern 2 verbatim 채택 (자체 verifier 0,
//   memory feedback_oidc_mock_self_referential mirror).
// - §7-B: T-16-NEW-01 (ID Token replay) / T-16-NEW-02 / T-16-NEW-05 mitigation.
// - §7-C: jest mock 한계 — 실 단말 backend tier UAT (Plan 16-07 A6/A7)
//   가 ground truth (memory feedback_mock_transaction_constraint mirror).
import {getAuth} from "firebase-admin/auth";
import {getFirestore, FieldValue} from "firebase-admin/firestore";
import {onCall, HttpsError} from "firebase-functions/https";
import * as logger from "firebase-functions/logger";
import {defineSecret} from "firebase-functions/params";
import {errors as joseErrors} from "jose";

import {createOidcVerifier} from "../shared/oidc_verifier";
import {
  MAX_NONCE_ARG_LENGTH,
  requireStringArg,
} from "../shared/require_string_arg";
import {fingerprintError, identityIndexDocId} from "./identity_index";

// Phase 16 D-04 — 4 provider secret 재사용 (Phase 12/13/14/15 Custom Token
// endpoint 와 동일 secret 공유). target provider 별 OIDC verifier 분기 의무.
//
// Note: Naver 는 OIDC 미지원 (access_token / userinfo API 기반) 이므로 본
// linkCustomTokenProvider 의 target verifier 분기 는 OIDC provider 3종
// (kakao/line/yahoojp) 만 지원. naver target link 는 Plan 16-04 의 client-side
// access_token path 와 별도 phase 분리 (Phase 17+ carry-forward).
const KAKAO_NATIVE_APP_KEY = defineSecret("KAKAO_NATIVE_APP_KEY");
const LINE_CHANNEL_ID = defineSecret("LINE_CHANNEL_ID");
const YAHOOJP_CLIENT_ID = defineSecret("YAHOOJP_CLIENT_ID");

// 3 provider OIDC verifier — 모듈 로드 시점 singleton (JWKS cache 보존).
// Phase 12/14/15 의 inline verifier 정의 verbatim mirror.
const verifyKakaoIdToken = createOidcVerifier({
  issuer: "https://kauth.kakao.com",
  jwksUrl: "https://kauth.kakao.com/.well-known/jwks.json",
  audience: () => KAKAO_NATIVE_APP_KEY.value(),
  algorithms: ["RS256"],
  nonceHashing: "none",
});

const verifyLineIdToken = createOidcVerifier({
  issuer: "https://access.line.me",
  jwksUrl: "https://api.line.me/oauth2/v2.1/certs",
  audience: () => LINE_CHANNEL_ID.value(),
  algorithms: ["ES256"],
  nonceHashing: "none",
});

const verifyYahoojpIdToken = createOidcVerifier({
  issuer: "https://auth.login.yahoo.co.jp/yconnect/v2/",
  jwksUrl: "https://auth.login.yahoo.co.jp/yconnect/v2/jwks",
  audience: () => YAHOOJP_CLIENT_ID.value(),
  algorithms: ["RS256"],
  nonceHashing: "none",
});

/** target provider OIDC verifier dispatch — RESEARCH Pattern 2 verbatim. */
type TargetProvider = "kakao" | "line" | "yahoojp";

type LinkCustomTokenProviderRequest = {
  /** current Firebase user 의 fresh ID Token (reauth verify). */
  idToken: string;
  /** target provider 슬러그 — link 대상. */
  targetProvider: TargetProvider;
  /** target provider 의 OIDC ID Token (Custom Token endpoint 와 동일 format). */
  targetProviderToken: string;
  /** OIDC nonce — 3 provider 모두 의무. */
  nonce: string;
};

type LinkCustomTokenProviderResponse = {
  ok: true;
};

/**
 * Hybrid 2nd branch — Custom Token provider link 발급 callable
 * (Phase 16 D-04).
 *
 * 흐름 (RESEARCH Pattern 2 verbatim):
 *   Step 0: input + request.auth 검증.
 *   Step 1: reauth ID Token freshness verify
 *           (`getAuth().verifyIdToken(idToken, checkRevoked=true)` + auth_time
 *           300s boundary + uid === request.auth.uid).
 *   Step 2: anonymous caller 거부 (Open Question #2 채택 —
 *           익명 user 는 link 거부, 4 Custom Token endpoint 의 신규 sign-up
 *           path 로 routing).
 *   Step 3: target provider OIDC ID Token verify (createOidcVerifier
 *           helper 재사용 — 자체 verifier 0, memory
 *           feedback_oidc_mock_self_referential mirror).
 *   Step 4: Firestore runTransaction — identity_index atomic create +
 *           linkedProviders[] update. "all reads before all writes"
 *           invariant 의무 (Pitfall 2 회피).
 *   Step 5: structured log + return.
 *
 * **PII 금지 (T-16-NEW-07 mitigation)**: logger payload 는
 * `{event, uid, targetProvider}` 만. idToken / targetProviderToken /
 * decoded.email 절대 노출 금지 (Phase 12.1 D-40 PII regression sentinel mirror).
 *
 * @param {{data: LinkCustomTokenProviderRequest, auth?: {uid: string}}} request
 *     onCall request — data 의무, auth optional (Step 0 에서 검증).
 * @return {Promise<LinkCustomTokenProviderResponse>} `{ok: true}` on success.
 */
export const linkCustomTokenProvider = onCall<LinkCustomTokenProviderRequest>(
  {
    enforceAppCheck: true,
    secrets: [KAKAO_NATIVE_APP_KEY, LINE_CHANNEL_ID, YAHOOJP_CLIENT_ID],
  },
  async (request): Promise<LinkCustomTokenProviderResponse> => {
    // Step 0: auth + input validation.
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "errorUnauthenticated");
    }
    const callerUid = request.auth.uid;
    // WR-03 / IN-03: `as` 단언 + falsy-only 가드를 공용 타입 가드로 대체.
    // 특히 `nonce` 가 객체였을 때 verifier 의 `claimNonce !== expectedNonce`
    // 가 참조 비교라 **항상 참** 이 되어 정상 토큰까지 nonce 불일치로
    // 거부되던 구멍을 닫는다.
    const idToken = requireStringArg(request.data?.idToken);
    const targetProviderToken = requireStringArg(
      request.data?.targetProviderToken,
    );
    const nonce = requireStringArg(request.data?.nonce, MAX_NONCE_ARG_LENGTH);
    // targetProvider 는 문자열 여부 검증 후 closed union 으로 좁힌다 —
    // 아래 `if` 가 narrowing 을 수행하므로 `as` 단언이 필요 없다.
    const rawTargetProvider = requireStringArg(
      request.data?.targetProvider,
      MAX_NONCE_ARG_LENGTH,
    );
    if (
      rawTargetProvider !== "kakao" &&
      rawTargetProvider !== "line" &&
      rawTargetProvider !== "yahoojp"
    ) {
      throw new HttpsError("invalid-argument", "errorInvalidArgument");
    }
    const targetProvider: TargetProvider = rawTargetProvider;

    // Step 1: reauth ID Token freshness verify
    // (Firebase Admin SDK 공식 함수 — memory feedback_oidc_mock_self_referential
    // mirror, 자체 JWT decode 0).
    let decoded;
    try {
      decoded = await getAuth().verifyIdToken(idToken, true /* checkRevoked */);
    } catch (err: unknown) {
      // PII 금지 — fingerprintError helper 만 사용 (err.message 본문 노출 0).
      const errCode = fingerprintError(err);
      logger.warn(
        {event: "link_id_token_verify_failed", code: errCode},
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
    const authTime = decoded.auth_time;
    const nowSec = Math.floor(Date.now() / 1000);
    if (nowSec - authTime > 300 /* 5분 */) {
      throw new HttpsError(
        "unauthenticated",
        "errorReauthenticationRequired",
      );
    }

    // Step 2: anonymous caller 거부 (Open Question #2 채택).
    if (decoded.firebase?.sign_in_provider === "anonymous") {
      throw new HttpsError(
        "failed-precondition",
        "errorAnonymousLinkNotAllowed",
      );
    }

    // Step 3: target provider OIDC ID Token verify
    // (createOidcVerifier helper 재사용 — 4 Custom Token endpoint 와 동일
    // singleton. provider 별 dispatch).
    let targetSub: string | undefined;
    try {
      let payload;
      if (targetProvider === "kakao") {
        payload = await verifyKakaoIdToken(targetProviderToken, nonce);
      } else if (targetProvider === "line") {
        payload = await verifyLineIdToken(targetProviderToken, nonce);
      } else {
        payload = await verifyYahoojpIdToken(targetProviderToken, nonce);
      }
      const typedPayload = payload as {sub?: string};
      targetSub = typedPayload.sub;
    } catch (err: unknown) {
      // PII 금지 — jose error code/name 만 fingerprint (Pitfall 3 회피).
      let errCode = "unknown";
      if (err instanceof joseErrors.JOSEError) {
        errCode = err.code ?? err.name;
      } else if (err instanceof Error) {
        errCode = err.name;
      }
      logger.warn(
        {event: "link_target_token_verify_failed", code: errCode},
        "target ID Token verification failed",
      );
      throw new HttpsError("invalid-argument", "errorInvalidArgument");
    }
    if (!targetSub) {
      throw new HttpsError("invalid-argument", "errorInvalidArgument");
    }

    // Step 4: Firestore runTransaction — identity_index atomic create +
    // linkedProviders[] update.
    // "all reads before all writes" invariant 의무 (Pitfall 2 회피).
    const db = getFirestore();
    const idxRef = db
      .collection("identity_index")
      .doc(identityIndexDocId(targetProvider, targetSub));
    const userRef = db.collection("users").doc(callerUid);
    try {
      await db.runTransaction(async (tx) => {
        // (all reads first — invariant 의무, Pitfall 2 회피)
        const [idxSnap] = await Promise.all([
          tx.get(idxRef),
          tx.get(userRef),
        ]);
        // (writes second — read 종료 후만)
        if (idxSnap.exists) {
          throw new HttpsError("already-exists", "errorAccountAlreadyLinked");
        }
        tx.set(idxRef, {
          firebaseUid: callerUid,
          provider: targetProvider,
          providerUserId: targetSub,
          linkedAt: FieldValue.serverTimestamp(),
          lastSeenAt: FieldValue.serverTimestamp(),
        });
        tx.set(
          userRef,
          {
            linkedProviders: FieldValue.arrayUnion({
              providerId: targetProvider,
              providerUserId: targetSub,
            }),
            providerLinkedAt: {
              [targetProvider]: FieldValue.serverTimestamp(),
            },
          },
          {merge: true},
        );
      });
    } catch (err: unknown) {
      // HttpsError 는 그대로 propagate (already-exists 등 known HttpsError).
      if (err instanceof HttpsError) {
        throw err;
      }
      const errCode = fingerprintError(err);
      logger.error(
        {event: "link_transaction_failed", uid: callerUid, code: errCode},
        "runTransaction threw",
      );
      throw new HttpsError("internal", "errorUnknown");
    }

    // Step 5: structured log + return.
    // PII 금지 — {event, uid, targetProvider, isNewUser} 만.
    logger.info(
      {
        event: "link_custom_token_provider_succeeded",
        uid: callerUid,
        targetProvider,
        isNewUser: false,
      },
      "linked",
    );
    return {ok: true};
  },
);
