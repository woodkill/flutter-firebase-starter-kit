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
import {errors as joseErrors} from "jose";

import {
  OIDC_VERIFIERS,
  YAHOOJP_CLIENT_ID,
} from "../shared/oidc_providers";
import {
  MAX_NONCE_ARG_LENGTH,
  requireStringArg,
} from "../shared/require_string_arg";
import {
  TermsAcceptanceJson,
  parseTermsAcceptanceJson,
} from "../shared/terms_acceptance_json";
import {buildAccountExistsError} from "./account_exists_error";
import {resolveIdentity} from "./identity_index";
import {mirrorTermsAccepted} from "./mirror_terms";

// Phase 15 D-YJP-04 / D-YJP-05 — OIDC verifier.
// WR-06 (Phase 15 리뷰): issuer (trailing slash 포함 — configuration.html
// verbatim) / jwksUrl / algorithms / nonceHashing 리터럴과 YAHOOJP_CLIENT_ID
// secret 선언은 shared/oidc_providers.ts 단일 진실원으로 이동했다 (해당
// 파일에 5-source cross-verify 근거 verbatim 보존). 이전에는 같은 4-튜플이
// 본 파일과 link_custom_token_provider.ts 에 각각 존재해, 한 글자 차이가
// 치명적인 trailing-slash issuer 가 두 곳에서 따로 관리되고 있었다.
const verifyYahoojpIdToken = OIDC_VERIFIERS.yahoojp;

type YahoojpCustomTokenRequest = {
  idToken: string;
  nonce: string;
  /**
   * Phase 16 D-13/D-14 (Plan 16-03 Task 3.2) — add-only optional.
   *
   * client (Plan 16-04) 의 Custom Token sign-up path 에서 신규 정식 UID 생성
   * 직후 termsAccepted Firestore mirror 의무. snapshot=undefined 일 때 기존
   * behavior 보존 (회귀 0).
   */
  termsAcceptanceSnapshot?: TermsAcceptanceJson;
};
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
    // WR-03 / IN-03: `as` 단언 + falsy-only 가드를 공용 타입 가드로 대체.
    // 비-string payload 가 jose 단계까지 내려가 "자격증명 무효" 로
    // 오분류되던 경로를 입력 오류로 정확히 분류한다.
    const idToken = requireStringArg(request.data?.idToken);
    const nonce = requireStringArg(request.data?.nonce, MAX_NONCE_ARG_LENGTH);

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
      // 16-13: existingProvider slug 를 details 로 전달 (client sheet 분기 wiring).
      throw buildAccountExistsError(resolution.existingProvider);
    case "anonymous_existing_collision":
      // 익명 사용자가 기존 yahoojp identity 로 로그인 시도 — anonymous
      // Firestore 데이터 손실 / UID hijack 위험 차단. Phase 17 (Account
      // Linking) 가 자동 마이그레이션 처리. 사용자에게는 안전 메시지
      // (Phase 12.1 D-34).
      logger.warn(
        {event: "yahoojp_anonymous_conflict"},
        "Anonymous user attempted to login with existing Yahoo!JP identity",
      );
      // 16-13: anonymous collision 도 resolution.existingProvider (= 호출
      // provider slug) 를 details 로 전달.
      throw buildAccountExistsError(resolution.existingProvider);
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

    // Step 3.5 (Phase 16 D-13/D-14 — Plan 16-03 Task 3.2):
    // termsAcceptanceSnapshot atomic mirror — Phase 14.1 A6 root cause fix
    // 의 Custom Token branch. {merge:true} 의무. snapshot=undefined 시 skip.
    // WR-02: callable arg 는 신뢰할 수 없는 임의 JSON 이다 — 5 필드 타입을
    // 런타임 검증해 좁힌다. 실패 시 null (필드 무시, 로그인은 계속).
    const termsSnapshot = parseTermsAcceptanceJson(
      request.data?.termsAcceptanceSnapshot,
    );
    // WR-01: isNewUser 게이트 — mirror 는 users/{uid} 문서가 새로
    // 만들어지는 시점에만 수행한다. 게이트 없이 매 Custom Token 로그인마다
    // set 하면, 기기에 device-local 동의가 남은 상태로 기존 계정에 재로그인할
    // 때 서버의 권위 있는 termsAccepted 가 device-local 값으로 덮어씌워진다
    // (acceptedAt 뿐 아니라 marketing opt-in 과 version 까지). client 측
    // TermsNotifier.mirrorToFirestore 의 pre-read + skip (Plan 10-12
    // multi-user invariant) 과 대칭인 서버측 가드다.
    if (termsSnapshot && isNewUser) {
      try {
        // WR-07: write + 로깅은 공용 helper 단일 진실원 (5회 verbatim 복제
        // 제거). 검증은 위의 parseTermsAcceptanceJson 이 이미 수행했다.
        await mirrorTermsAccepted({
          uid,
          snapshot: termsSnapshot,
          successEvent: "yahoojp_terms_acceptance_mirrored",
          failureEvent: "yahoojp_terms_acceptance_mirror_failed",
        });
      } catch {
        // helper 가 이미 PII-safe fingerprint 로 logger.error 를 남겼다.
        throw new HttpsError("internal", "errorUnknown");
      }
    }

    // Step 4: structured log — uid + isNewUser 만 (PII 금지).
    logger.info(
      {event: "yahoojp_custom_token_issued", uid, isNewUser},
      "Yahoo!JP custom token issued",
    );

    return {customToken, uid, isNewUser};
  },
);
