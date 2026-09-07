// Phase 14 — see ROADMAP.md
import {getAuth} from "firebase-admin/auth";
import {getFirestore, Timestamp} from "firebase-admin/firestore";
import {onCall, HttpsError} from "firebase-functions/https";
import * as logger from "firebase-functions/logger";
import {defineSecret} from "firebase-functions/params";
import {errors as joseErrors} from "jose";

import {createOidcVerifier} from "../shared/oidc_verifier";
import {
  TermsAcceptanceJson,
  parseTermsAcceptanceJson,
} from "../shared/terms_acceptance_json";
import {buildAccountExistsError} from "./account_exists_error";
import {resolveIdentity} from "./identity_index";

// Phase 14 D-LINE-16 — Secret Manager 주입.
// 배포 전 의무:
//   firebase functions:secrets:set LINE_CHANNEL_ID
//
// LINE_CHANNEL_ID 는 OIDC ID Token audience 검증 (aud claim) 의 정답값으로
// runtime 시점에 사용된다.
//
// WR-04 (Phase 14 review): LINE_CHANNEL_SECRET 은 Phase 17+ refresh /
// verify-token / revoke API 진입 시점에 도입한다. 현 시점 사용처 0 인
// secret 을 declared 하면 운영자가 deploy 전 1회성 더미 주입을 강제받아
// starter-kit "최소 설정으로 시작" 가치와 충돌 → declaration 제거.
// Phase 17 진입 시 본 위치에 재선언 + onCall secrets 배열에 재포함 의무.
const LINE_CHANNEL_ID = defineSecret("LINE_CHANNEL_ID");

// Phase 14 D-LINE-01 / D-LINE-03 / D-LINE-05 — OIDC verifier factory 호출.
// helper 가 issuer / aud / alg / nonce 검증 모두 흡수한다. LINE 특화 분기:
//  - issuer  = "https://access.line.me" (LINE OIDC 공식 issuer)
//  - jwksUrl = "https://api.line.me/oauth2/v2.1/certs" (JWKS endpoint)
//  - audience = LINE_CHANNEL_ID.value() — lazy invoke (secret 은 onCall 진입
//    시점에만 evaluate 가능, 모듈 로드 시점은 미주입)
//  - algorithms = ["ES256"] — LINE native SDK 가 ES256 으로 서명 (RESEARCH
//    D-LINE-RES; Kakao 의 RS256 와 alg 분리)
//  - nonceHashing = "none" — LINE SDK 가 raw nonce 를 그대로 LINE 서버에
//    transmit + ID Token nonce claim = raw 동일값 (line-sdk-android
//    LineIdToken.java verbatim "the same value as in the authentication
//    request", Phase 14.1 D-14.1-02 cross-verified). Kakao 와 동일 비교 모드.
//
// Pitfall 3 sentinel — jose 의 JWKS remote set 생성 호출처가 functions/src/ 의
// helper 단일 파일 (oidc_verifier.ts) 만 남아야 한다. 본 caller 는 jose import
// 시 errors 만 사용 (instanceof 분기용) — 직접 JWKS factory 호출 0건.
const verifyLineIdToken = createOidcVerifier({
  issuer: "https://access.line.me",
  jwksUrl: "https://api.line.me/oauth2/v2.1/certs",
  audience: () => LINE_CHANNEL_ID.value(),
  algorithms: ["ES256"],
  nonceHashing: "none",
});

type LineCustomTokenRequest = {
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
 *    + raw nonce === claim.nonce 비교 흡수. 위반 시 joseErrors.* throw.
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
    secrets: [LINE_CHANNEL_ID],
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
      // helper 가 issuer / aud / alg / nonce 검증 모두 흡수. nonce 는 raw
      // 그대로 claim 과 비교 (Phase 14.1 D-14.1-02 — line-sdk-android
      // LineIdToken.java verbatim "the same value as in the authentication
      // request"). 위반 시 joseErrors.JWTClaimValidationFailed / 기타
      // JOSEError throw.
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
      // 16-13: existingProvider slug 를 details 로 전달 (client sheet 분기 wiring).
      throw buildAccountExistsError(resolution.existingProvider);
    case "anonymous_existing_collision":
      // 익명 사용자가 기존 line identity 로 로그인 시도 — anonymous Firestore
      // 데이터 손실 / UID hijack 위험 차단. Phase 17 (Account Linking) 가
      // 자동 마이그레이션 처리. 사용자에게는 안전 메시지 (Phase 12.1 D-34).
      logger.warn(
        {event: "line_anonymous_conflict"},
        "Anonymous user attempted to login with existing LINE identity",
      );
      // 16-13: anonymous collision 도 resolution.existingProvider (= 호출
      // provider slug) 를 details 로 전달.
      throw buildAccountExistsError(resolution.existingProvider);
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

    // Step 3.5 (Phase 16 D-13/D-14 — Plan 16-03 Task 3.2):
    // termsAcceptanceSnapshot atomic mirror — Phase 14.1 A6 root cause fix
    // 의 Custom Token branch. {merge:true} 의무. snapshot=undefined 시 skip.
    // WR-02: callable arg 는 신뢰할 수 없는 임의 JSON 이다 — 5 필드 타입을
    // 런타임 검증해 좁힌다. 실패 시 null (필드 무시, 로그인은 계속).
    const termsSnapshot = parseTermsAcceptanceJson(
      data.termsAcceptanceSnapshot,
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
        await getFirestore()
          .collection("users")
          .doc(uid)
          .set(
            {
              termsAccepted: {
                version: termsSnapshot.version,
                service: termsSnapshot.service,
                privacy: termsSnapshot.privacy,
                marketing: termsSnapshot.marketing,
                acceptedAt: Timestamp.fromDate(
                  new Date(termsSnapshot.acceptedAt),
                ),
              },
            },
            {merge: true},
          );
        logger.info(
          {
            event: "line_terms_acceptance_mirrored",
            uid,
            terms_mirrored: true,
            version: termsSnapshot.version,
          },
          "terms acceptance mirrored",
        );
      } catch (err: unknown) {
        const errCode = err instanceof Error ? err.name : "unknown";
        logger.error(
          {event: "line_terms_acceptance_mirror_failed", uid, code: errCode},
          "terms acceptance mirror set merge threw",
        );
        throw new HttpsError("internal", "errorUnknown");
      }
    }

    // Step 4: structured log — uid + isNewUser 만 (PII 금지).
    logger.info(
      {event: "line_custom_token_issued", uid, isNewUser},
      "LINE custom token issued",
    );

    return {customToken, uid, isNewUser};
  },
);
