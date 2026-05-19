// Phase 14 — see ROADMAP.md
import {getAuth} from "firebase-admin/auth";
import {getFirestore} from "firebase-admin/firestore";
import {onCall, HttpsError} from "firebase-functions/https";
import * as logger from "firebase-functions/logger";
import {defineSecret} from "firebase-functions/params";
import {errors as joseErrors} from "jose";

import {createOidcVerifier} from "../shared/oidc_verifier";
import {resolveIdentity} from "./identity_index";

// Phase 14 D-LINE-16 — Secret Manager 주입.
// 배포 전 의무:
//   firebase functions:secrets:set LINE_CHANNEL_ID
//   firebase functions:secrets:set LINE_CHANNEL_SECRET
//
// LINE_CHANNEL_ID 는 OIDC ID Token audience 검증 (aud claim) 의 정답값으로
// runtime 시점에 사용된다. LINE_CHANNEL_SECRET 은 본 Plan 단계에서 사용처 0
// (Phase 17+ refresh / verify-token / revoke API 대비 — Phase 13
// NAVER_CLIENT_SECRET 와 동일한 secret 정책 일관용으로 미리 등록한다).
const LINE_CHANNEL_ID = defineSecret("LINE_CHANNEL_ID");
const LINE_CHANNEL_SECRET = defineSecret("LINE_CHANNEL_SECRET");

// Phase 14 D-LINE-01 / D-LINE-03 / D-LINE-05 — OIDC verifier factory 호출.
// helper 가 issuer / aud / alg / nonce 검증 모두 흡수한다. LINE 특화 분기:
//  - issuer  = "https://access.line.me" (LINE OIDC 공식 issuer)
//  - jwksUrl = "https://api.line.me/oauth2/v2.1/certs" (JWKS endpoint)
//  - audience = LINE_CHANNEL_ID.value() — lazy invoke (secret 은 onCall 진입
//    시점에만 evaluate 가능, 모듈 로드 시점은 미주입)
//  - algorithms = ["ES256"] — LINE native SDK 가 ES256 으로 서명 (RESEARCH
//    D-LINE-RES; Kakao 의 RS256 와 alg 분리)
//  - nonceHashing = "sha256" — LINE SDK 가 raw nonce 를 SHA256 hash 후 claim
//    에 embed (Kakao 의 raw nonce 그대로 비교 모드와 분리)
//
// Pitfall 3 sentinel — jose 의 JWKS remote set 생성 호출처가 functions/src/ 의
// helper 단일 파일 (oidc_verifier.ts) 만 남아야 한다. 본 caller 는 jose import
// 시 errors 만 사용 (instanceof 분기용) — 직접 JWKS factory 호출 0건.
const verifyLineIdToken = createOidcVerifier({
  issuer: "https://access.line.me",
  jwksUrl: "https://api.line.me/oauth2/v2.1/certs",
  audience: () => LINE_CHANNEL_ID.value(),
  algorithms: ["ES256"],
  nonceHashing: "sha256",
});

type LineCustomTokenRequest = {idToken: string; nonce: string};
type LineCustomTokenResponse = {
  customToken: string;
  uid: string;
  isNewUser: boolean;
};

/**
 * LINE OIDC ID Token → Firebase Custom Token 발급 (Phase 14 D-LINE-06).
 *
 * 흐름:
 * 1. App Check enforcement (D-LINE-D11 carry-forward) — request.auth=null
 *    허용과 양립.
 * 2. createOidcVerifier helper 가 jwtVerify (issuer + audience + ES256 서명)
 *    + nonce SHA256 hash 비교 흡수. 위반 시 joseErrors.* throw.
 * 3. Identity Index lookup-first transaction (Phase 12.1 D-31~D-34 자동 상속).
 * 4. admin.auth().createCustomToken(uid) — 1h 만료.
 *
 * **PII 금지 (D-LINE-40 carry-forward / Phase 11 D-08, Pitfall 1/7):** logger
 * payload 는 {event, uid, isNewUser} 만. idToken / payload 본문 (sub / name /
 * picture) 절대 금지.
 *
 * **App Check + 미인증 양립 (D-LINE-D11):** request.auth = null 분기 = 재설치
 * 후 첫 진입. App Check 토큰은 디바이스 attestation 으로 abuse 방어.
 *
 * **HttpsError 매핑 (Phase 11 D-07 carry-forward):**
 * - jose.JOSEError / payload.sub 누락 / data 누락 → invalid-argument.
 * - 그 외 catch → internal.
 *
 * **email 미발급 (D-LINE-21):** LINE 본 단계 scope = openid + profile 만.
 * payload 에서 email 추출 X, resolveIdentity 의 userInfo.email undefined,
 * createCustomToken 의 developerClaims undefined.
 *
 * @param {{data: LineCustomTokenRequest, auth?: {uid: string}}} request
 *     onCall request — data.idToken / data.nonce 의무, auth optional.
 * @return {Promise<LineCustomTokenResponse>} customToken + uid + isNewUser.
 */
export const lineCustomToken = onCall<LineCustomTokenRequest>(
  {
    enforceAppCheck: true,
    secrets: [LINE_CHANNEL_ID, LINE_CHANNEL_SECRET],
  },
  async (request): Promise<LineCustomTokenResponse> => {
    // Step 0: input validation (Phase 11 D-07 standard message 매핑).
    const data = request.data ?? ({} as LineCustomTokenRequest);
    const idToken = data.idToken;
    const nonce = data.nonce;
    if (!idToken || !nonce) {
      throw new HttpsError("invalid-argument", "errorInvalidArgument");
    }

    // Step 1: ID Token JWT 자체 검증 — helper 호출.
    let lineUserId: string | undefined;
    let lineDisplayName: string | undefined;
    let linePictureUrl: string | undefined;
    try {
      // helper 가 issuer / aud / alg / nonce 검증 모두 흡수. nonce 는 SHA256
      // hash 후 claim 과 비교 (LINE SDK 의 embed 정책 일치). 위반 시
      // joseErrors.JWTClaimValidationFailed / 기타 JOSEError throw.
      const payload = await verifyLineIdToken(idToken, nonce);
      const typedPayload = payload as {
        sub?: string;
        // D-LINE-21: scope openid+profile 만 — email claim 비채택. OIDC 표준
        // userinfo claim — LINE 사용자 표시명 + 프로필 이미지 (사용자 동의 시
        // 포함). 미동의 시 undefined → Firebase Auth user record 미갱신.
        name?: string;
        picture?: string;
      };
      lineUserId = typedPayload.sub;
      lineDisplayName = typedPayload.name;
      linePictureUrl = typedPayload.picture;
    } catch (err: unknown) {
      // PII 금지 (Pitfall 1 / 7 / D-LINE-40 carry-forward) — jose 에러 code
      // 비-PII 로깅. err.message / err.payload / err.claim / err.reason 본문
      // 절대 금지. err.code (jose 6.x stable public API) / err.name 만 short
      // fingerprint 로 노출.
      let errCode = "unknown";
      if (err instanceof joseErrors.JOSEError) {
        errCode = err.code ?? err.name;
      } else if (err instanceof Error) {
        errCode = err.name;
      }
      logger.warn(
        {event: "line_jwt_verify_failed", code: errCode},
        "LINE ID Token verification failed",
      );
      if (err instanceof joseErrors.JOSEError) {
        throw new HttpsError("invalid-argument", "errorInvalidCredentials");
      }
      throw new HttpsError("internal", "errorUnknown");
    }
    if (!lineUserId) {
      throw new HttpsError("invalid-argument", "errorInvalidCredentials");
    }

    // Step 2: Identity Index resolve — Phase 12.1 helper 자동 상속.
    // D-LINE-21: email 미발급 → userInfo.email 미설정. displayName / photoURL
    // 만 helper 에 전달, helper 가 createUser / updateUser 시점에 Firebase Auth
    // user record 의 displayName / photoURL 에 propagate.
    const callerUid = request.auth?.uid; // unauthenticated 허용.
    const userInfo: {email?: string; displayName?: string; photoURL?: string} =
      {};
    if (lineDisplayName) userInfo.displayName = lineDisplayName;
    if (linePictureUrl) userInfo.photoURL = linePictureUrl;
    let resolution;
    try {
      resolution = await resolveIdentity(getFirestore(), {
        provider: "line", // D-LINE-09 — provider 슬러그
        providerUserId: lineUserId,
        callerUid,
        userInfo: Object.keys(userInfo).length > 0 ? userInfo : undefined,
      });
    } catch {
      // helper unexpected error (firestore network, internal) → internal 매핑.
      // **Pitfall 1/7 (PII) 보존** — err 객체 접근 안 함 (optional catch
      // binding) → 누구도 실수로 PII 로깅 못 함 (compile-time 보장).
      logger.error(
        {event: "identity_index_failed"},
        "resolveIdentity threw unexpected error",
      );
      throw new HttpsError("internal", "errorUnknown");
    }

    // R3 exhaustive switch on conflictKind — TypeScript exhaustiveness check
    // 자동 강제 (default arm 미사용 → union type 누락 시 컴파일 에러).
    switch (resolution.conflictKind) {
    case "email_in_use":
      // !callerUid path 의 createUser auth/email-already-in-use rejection 으로
      // helper 가 detect. LINE D-LINE-21 (email scope 미채택) 라 자체 trigger
      // 가능성은 0 이지만 Phase 9.2 Gap B (callerUid + userInfo.email) path 와
      // 정책 일관성 확보 — caller switch 분기 항상 보존.
      logger.warn(
        {event: "line_email_collision"},
        "LINE email collides with existing account",
      );
      throw new HttpsError(
        "already-exists",
        "errorAccountExistsWithDifferentCredential",
      );
    case "anonymous_existing_collision":
      // 익명 사용자가 기존 line identity 로 로그인 시도 — anonymous Firestore
      // 데이터 손실 / UID hijack 위험 차단. Phase 17 (Account Linking) 가
      // 자동 마이그레이션 처리. 사용자에게는 안전 메시지 (Phase 12.1 D-34).
      logger.warn(
        {event: "line_anonymous_conflict"},
        "Anonymous user attempted to login with existing LINE identity",
      );
      throw new HttpsError(
        "already-exists",
        "errorAccountExistsWithDifferentCredential",
      );
    case null:
      break; // 정상 flow.
    }

    const {uid, isNewUser} = resolution;

    // Step 3: Custom Token 발급 (admin SDK — 1h 만료).
    // D-LINE-21: email 미발급 → developerClaims undefined (Phase 12 kakao 의
    // userInfo.email 있을 때 propagate 분기와 동등하게 LINE 은 email 부재로
    // undefined). Phase 17 (Account Linking) 가 link 시점에 email 통합 처리.
    //
    // CR-01 carry-forward: admin SDK throw 도 internal + errorUnknown 매핑.
    // err.message 본문 미노출 (PII 금지) — err.name 만 fingerprint.
    let customToken: string;
    try {
      customToken = await getAuth().createCustomToken(uid);
    } catch (err: unknown) {
      const errCode = err instanceof Error ? err.name : "unknown";
      logger.error(
        {event: "line_custom_token_create_failed", code: errCode},
        "createCustomToken threw",
      );
      throw new HttpsError("internal", "errorUnknown");
    }

    // Step 4: structured log — uid + isNewUser 만 (PII 금지).
    logger.info(
      {event: "line_custom_token_issued", uid, isNewUser},
      "LINE custom token issued",
    );

    return {customToken, uid, isNewUser};
  },
);
