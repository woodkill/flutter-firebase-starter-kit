/**
 * yahoojpCustomToken — Yahoo!JP OIDC ID Token → Firebase Custom Token onCall.
 *
 * Phase 15 SOCL-04. OIDC verifier helper 세 번째 사용처 (Phase 12 D-08 의무
 * 두 번째 자연 이행 — Phase 14 LINE 첫 번째 → Phase 15 Yahoo!JP).
 *
 * **Cross-verify (RESEARCH §"Cross-Verify Evidence Matrix" §D-YJP-04/05/09,
 * 5층 안전망 §7-A baseline 첫 적용):**
 * - issuer: `"https://auth.login.yahoo.co.jp/yconnect/v2/"` trailing slash 포함
 *   [VERIFIED: configuration.html OpenID Provider Metadata verbatim — D-YJP-05.
 *   id_token.html 본문 prose 표기 (trailing slash 없는 형태) 는 trap, 진실원은
 *   configuration.html `"issuer"` 필드. Plan 15-06 UAT A1 의 실 단말 token
 *   decode 결과로 final LOCK 검증.]
 * - algorithms: RS256 only [VERIFIED: id_token.html "Yahoo! ID連携 v2はRSA-
 *   SHA256のみのサポート" verbatim — D-YJP-04. LINE 의 ES256, Kakao 의 RS256
 *   과 비교 — Yahoo!JP = Kakao 와 동일 alg.]
 * - nonceHashing: "none" — raw transit + raw claim embed
 *   [VERIFIED: 5-source — AppAuth-iOS OIDAuthorizationRequest.m
 *   `[query addParameter:kNonceKey value:_nonce]` + AppAuth-Android
 *   AuthorizationRequest.java:863-872 "passed through unmodified" + Yahoo!JP
 *   authorization.html + id_token.html "Payloadのnonce値が ... 一致している
 *   ことを検証します" + flutter_appauth pub.dev example.dart — D-YJP-04.]
 * - scope = "openid + profile" only (D-YJP-09 정정 lock — UserInfo API 審査
 *   의무 회피, manual.md Plan 15-05 §(4) production 전환 절차 위임). email
 *   claim 부재 → typedPayload type 에 `email?` 미포함, developerClaims
 *   undefined.
 *
 * **흐름 (line_custom_token.ts 직접 mirror — 5 deltas 외 동일):**
 * 1. App Check enforcement (Phase 11 D-11 carry-forward) — request.auth=null
 *    허용과 양립.
 * 2. createOidcVerifier helper 가 jwtVerify (issuer + audience + RS256 서명)
 *    + raw nonce === claim.nonce 비교 흡수. 위반 시 joseErrors.* throw.
 * 3. Identity Index lookup-first transaction (Phase 12.1 D-31~D-34 자동 상속).
 * 4. admin.auth().createCustomToken(uid) — 1h 만료.
 *
 * **PII 금지 (Phase 12.1 D-40 + Phase 14 WR-01 fix, Pitfall 1/7):** logger
 * payload 는 {event, uid, isNewUser} 만. idToken / payload 본문 (sub / name /
 * picture) / raw nonce 절대 금지. debugMock/logMock 채널까지 PII regression
 * sentinel (Test 10).
 *
 * **App Check + 미인증 양립 (Phase 11 D-11 mirror):** request.auth = null
 * 분기 = 재설치 후 첫 진입. App Check 토큰은 디바이스 attestation 으로
 * abuse 방어.
 *
 * **HttpsError 매핑 (Phase 11 D-07 carry-forward):**
 * - jose.JOSEError / payload.sub 누락 / data 누락 → invalid-argument.
 * - 그 외 catch → internal.
 *
 * **email 미발급 (D-YJP-09 정정 lock):** Yahoo!JP 본 단계 scope = openid +
 * profile 만. UserInfo API 審査 의무 회피. payload 에서 email 추출 X,
 * resolveIdentity 의 userInfo.email undefined, createCustomToken 의
 * developerClaims undefined.
 *
 * @see .planning/phases/15-yahoo-japan-login/15-RESEARCH.md §"Cross-Verify
 *     Evidence Matrix"
 * @see .planning/phases/14.1-line-oidc-nonce-hotfix/14.1-RESEARCH.md §7-A
 *     5층 안전망
 */
// Phase 15 — see ROADMAP.md
import {getAuth} from "firebase-admin/auth";
import {getFirestore} from "firebase-admin/firestore";
import {onCall, HttpsError} from "firebase-functions/https";
import * as logger from "firebase-functions/logger";
import {defineSecret} from "firebase-functions/params";
import {errors as joseErrors} from "jose";

import {createOidcVerifier} from "../shared/oidc_verifier";
import {resolveIdentity} from "./identity_index";

// Phase 15 D-YJP-03 — Secret Manager 주입.
// 배포 전 의무:
//   firebase functions:secrets:set YAHOOJP_CLIENT_ID
//
// YAHOOJP_CLIENT_ID 는 OIDC ID Token audience 검증 (aud claim) 의 정답값으로
// runtime 시점에 사용된다. Yahoo Developers Console 의 "クライアントサイド・
// アプリケーション" 등록 유형 — client_secret 0 (D-YJP-03), config/dev.json
// 공개 + Firebase Secret Manager 이중 등록 (manual.md Plan 15-05 6 절차).
const YAHOOJP_CLIENT_ID = defineSecret("YAHOOJP_CLIENT_ID");

// Phase 15 D-YJP-04 / D-YJP-05 — OIDC verifier factory 호출.
// helper 가 issuer / aud / alg / nonce 검증 모두 흡수한다. Yahoo!JP 특화 분기:
//  - issuer  = "https://auth.login.yahoo.co.jp/yconnect/v2/" — trailing slash
//    포함 (configuration.html OpenID Provider Metadata `"issuer"` 필드
//    verbatim, D-YJP-05). id_token.html 본문 prose 의 trailing slash 없는
//    표기는 trap.
//  - jwksUrl = "https://auth.login.yahoo.co.jp/yconnect/v2/jwks" (JWKS endpoint)
//  - audience = YAHOOJP_CLIENT_ID.value() — lazy invoke (secret 은 onCall
//    진입 시점에만 evaluate 가능, 모듈 로드 시점은 미주입)
//  - algorithms = ["RS256"] — Yahoo!JP id_token.html "RSA-SHA256のみのサポート"
//    verbatim (D-YJP-04). LINE 의 ES256 와 alg 분리.
//  - nonceHashing = "none" — flutter_appauth → AppAuth-iOS/Android 가 raw
//    nonce 를 변환 없이 Yahoo!JP authorization endpoint 에 transmit + ID Token
//    nonce claim = raw 동일값 (5-source cross-verified, RESEARCH §D-YJP-04).
//    LINE / Kakao 와 동일 비교 모드.
//
// Pitfall 3 sentinel — jose 의 JWKS remote set 생성 호출처가 functions/src/ 의
// helper 단일 파일 (oidc_verifier.ts) 만 남아야 한다. 본 caller 는 jose import
// 시 errors 만 사용 (instanceof 분기용) — 직접 JWKS factory 호출 0건.
const verifyYahoojpIdToken = createOidcVerifier({
  issuer: "https://auth.login.yahoo.co.jp/yconnect/v2/",
  jwksUrl: "https://auth.login.yahoo.co.jp/yconnect/v2/jwks",
  audience: () => YAHOOJP_CLIENT_ID.value(),
  algorithms: ["RS256"],
  nonceHashing: "none",
});

type YahoojpCustomTokenRequest = {idToken: string; nonce: string};
type YahoojpCustomTokenResponse = {
  customToken: string;
  uid: string;
  isNewUser: boolean;
};

/**
 * Yahoo!JP OIDC ID Token → Firebase Custom Token 발급
 * (Phase 15 D-YJP-03/04/05/09).
 *
 * @param {{data: YahoojpCustomTokenRequest, auth?: {uid: string}}} request
 *     onCall request — data.idToken / data.nonce 의무, auth optional.
 * @return {Promise<YahoojpCustomTokenResponse>} customToken + uid + isNewUser.
 */
export const yahoojpCustomToken = onCall<YahoojpCustomTokenRequest>(
  {
    enforceAppCheck: true,
    secrets: [YAHOOJP_CLIENT_ID],
  },
  async (request): Promise<YahoojpCustomTokenResponse> => {
    // Step 0: input validation (Phase 11 D-07 standard message 매핑).
    const data = request.data ?? ({} as YahoojpCustomTokenRequest);
    const idToken = data.idToken;
    const nonce = data.nonce;
    if (!idToken || !nonce) {
      throw new HttpsError("invalid-argument", "errorInvalidArgument");
    }

    // Step 1: ID Token JWT 자체 검증 — helper 호출.
    let yahoojpSub: string | undefined;
    let yahoojpDisplayName: string | undefined;
    let yahoojpPictureUrl: string | undefined;
    try {
      // helper 가 issuer / aud / alg / nonce 검증 모두 흡수. nonce 는 raw
      // 그대로 claim 과 비교 (D-YJP-04 5-source cross-verified). 위반 시
      // joseErrors.JWTClaimValidationFailed / 기타 JOSEError throw.
      const payload = await verifyYahoojpIdToken(idToken, nonce);
      const typedPayload = payload as {
        sub?: string;
        // D-YJP-09 정정 lock: scope openid+profile 만 — email claim 비채택.
        // UserInfo API 審査 의무 회피. OIDC 표준 userinfo claim — Yahoo!JP
        // 사용자 표시명 + 프로필 이미지 (사용자 동의 시 포함). 미동의 시
        // undefined → Firebase Auth user record 미갱신.
        name?: string;
        picture?: string;
      };
      yahoojpSub = typedPayload.sub;
      yahoojpDisplayName = typedPayload.name;
      yahoojpPictureUrl = typedPayload.picture;
    } catch (err: unknown) {
      // PII 금지 (Pitfall 1 / 7 / Phase 12.1 D-40 carry-forward) — jose 에러
      // code 비-PII 로깅. err.message / err.payload / err.claim / err.reason
      // 본문 절대 금지. err.code (jose 6.x stable public API) / err.name 만
      // short fingerprint 로 노출.
      let errCode = "unknown";
      if (err instanceof joseErrors.JOSEError) {
        errCode = err.code ?? err.name;
      } else if (err instanceof Error) {
        errCode = err.name;
      }
      logger.warn(
        {event: "yahoojp_jwt_verify_failed", code: errCode},
        "Yahoo!JP ID Token verification failed",
      );
      if (err instanceof joseErrors.JOSEError) {
        throw new HttpsError("invalid-argument", "errorInvalidCredentials");
      }
      throw new HttpsError("internal", "errorUnknown");
    }
    if (!yahoojpSub) {
      throw new HttpsError("invalid-argument", "errorInvalidCredentials");
    }

    // Step 2: Identity Index resolve — Phase 12.1 helper 자동 상속.
    // D-YJP-09: email 미발급 → userInfo.email 미설정. displayName / photoURL
    // 만 helper 에 전달, helper 가 createUser / updateUser 시점에 Firebase Auth
    // user record 의 displayName / photoURL 에 propagate.
    const callerUid = request.auth?.uid; // unauthenticated 허용.
    const userInfo: {email?: string; displayName?: string; photoURL?: string} =
      {};
    if (yahoojpDisplayName) userInfo.displayName = yahoojpDisplayName;
    if (yahoojpPictureUrl) userInfo.photoURL = yahoojpPictureUrl;
    let resolution;
    try {
      resolution = await resolveIdentity(getFirestore(), {
        provider: "yahoojp", // D-YJP-09 — provider 슬러그
        providerUserId: yahoojpSub,
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
      // D-YJP-09 (email scope 미채택) 라 자체 trigger 가능성은 0 이지만
      // Phase 9.2 Gap B (callerUid + userInfo.email) path 와 정책 일관성
      // 확보 — caller switch 분기 항상 보존.
      logger.warn(
        {event: "yahoojp_email_collision"},
        "Yahoo!JP email collides with existing account",
      );
      throw new HttpsError(
        "already-exists",
        "errorAccountExistsWithDifferentCredential",
      );
    case "anonymous_existing_collision":
      // 익명 사용자가 기존 yahoojp identity 로 로그인 시도 — anonymous
      // Firestore 데이터 손실 / UID hijack 위험 차단. Phase 17 (Account
      // Linking) 가 자동 마이그레이션 처리. 사용자에게는 안전 메시지
      // (Phase 12.1 D-34).
      logger.warn(
        {event: "yahoojp_anonymous_conflict"},
        "Anonymous user attempted to login with existing Yahoo!JP identity",
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
    // D-YJP-09: email 미발급 → developerClaims undefined. Phase 17 (Account
    // Linking) 가 link 시점에 email 통합 처리.
    //
    // err.message 본문 미노출 (PII 금지) — err.name 만 fingerprint.
    let customToken: string;
    try {
      customToken = await getAuth().createCustomToken(uid);
    } catch (err: unknown) {
      const errCode = err instanceof Error ? err.name : "unknown";
      logger.error(
        {event: "yahoojp_custom_token_create_failed", code: errCode},
        "createCustomToken threw",
      );
      throw new HttpsError("internal", "errorUnknown");
    }

    // Step 4: structured log — uid + isNewUser 만 (PII 금지).
    logger.info(
      {event: "yahoojp_custom_token_issued", uid, isNewUser},
      "Yahoo!JP custom token issued",
    );

    return {customToken, uid, isNewUser};
  },
);
