import {getAuth} from "firebase-admin/auth";
import {getFirestore} from "firebase-admin/firestore";
import {onCall, HttpsError} from "firebase-functions/https";
import * as logger from "firebase-functions/logger";
import {defineSecret} from "firebase-functions/params";
import {jwtVerify, errors as joseErrors} from "jose";

import {KAKAO_ISSUER, KAKAO_JWKS} from "../shared/kakao_jwks";
import {resolveIdentity} from "./identity_index";

// Phase 11 D-05 — Secret Manager 주입.
// 배포 전 의무: `firebase functions:secrets:set KAKAO_NATIVE_APP_KEY`.
const KAKAO_NATIVE_APP_KEY = defineSecret("KAKAO_NATIVE_APP_KEY");

type KakaoCustomTokenRequest = {idToken: string; nonce: string};
type KakaoCustomTokenResponse = {
  customToken: string;
  uid: string;
  isNewUser: boolean;
};

/**
 * Kakao OIDC ID Token → Firebase Custom Token 발급 (Phase 12 D-06, D-10).
 *
 * 흐름:
 * 1. App Check enforcement (D-11, Pitfall 6) — request.auth=null 허용과 양립.
 * 2. jose.jwtVerify (issuer + audience + RS256 서명) + nonce fallback 비교.
 *    jose 6.x JWTClaimVerificationOptions 에 native nonce 옵션 부재 (verify
 *    헬퍼 내부 검증 미지원) — 클레임 직접 비교로 동등 효과 (D-06).
 * 3. Identity Index lookup-first transaction (D-09 ~ D-13).
 * 4. admin.auth().createCustomToken(uid) — 1h 만료.
 *
 * **PII 금지 (Phase 11 D-08, Pitfall 1/7):** logger payload 는
 * {event, uid, isNewUser} 만. idToken / payload 본문 절대 금지.
 *
 * **App Check + 미인증 양립 (D-11):** request.auth = null 분기 = 재설치 후
 * 첫 진입. App Check 토큰은 디바이스 attestation 으로 abuse 방어.
 *
 * **HttpsError 매핑 (Phase 11 D-07):**
 * - jose.JOSEError / payload.sub 누락 / data 누락 → invalid-argument.
 * - 그 외 catch → internal.
 *
 * Phase 14 LINE 진입 시 jose 검증 helper 추출 (D-08, YAGNI).
 *
 * @param {{data: KakaoCustomTokenRequest, auth?: {uid: string}}} request
 *     onCall request — data.idToken / data.nonce 의무, auth optional.
 * @return {Promise<KakaoCustomTokenResponse>} customToken + uid + isNewUser.
 */
export const kakaoCustomToken = onCall<KakaoCustomTokenRequest>(
  {
    enforceAppCheck: true,
    secrets: [KAKAO_NATIVE_APP_KEY],
  },
  async (request): Promise<KakaoCustomTokenResponse> => {
    const data = request.data ?? ({} as KakaoCustomTokenRequest);
    const idToken = data.idToken;
    const nonce = data.nonce;
    if (!idToken || !nonce) {
      throw new HttpsError("invalid-argument", "errorInvalidArgument");
    }

    // Step 1: ID Token JWT 자체 검증.
    let kakaoUserId: string | undefined;
    let kakaoEmail: string | undefined;
    try {
      const verified = await jwtVerify(idToken, KAKAO_JWKS, {
        issuer: KAKAO_ISSUER,
        audience: KAKAO_NATIVE_APP_KEY.value(),
        algorithms: ["RS256"],
      });
      const payload = verified.payload as {
        sub?: string;
        nonce?: string;
        // OIDC 표준 claim — 비즈 앱 + 카카오계정(이메일) 필수 동의 시 포함.
        // 일반 앱 또는 사용자 미동의 시 undefined.
        email?: string;
      };
      // jose 6.x JWTClaimVerificationOptions 에 nonce 옵션 부재 → fallback
      // 직접 비교 (Pitfall 2 — replay attack 방어).
      const claimNonce = payload.nonce;
      if (claimNonce !== nonce) {
        throw new joseErrors.JWTClaimValidationFailed(
          "unexpected nonce",
          verified.payload,
          "nonce",
          "check_failed",
        );
      }
      kakaoUserId = payload.sub;
      kakaoEmail = payload.email;
    } catch (err: unknown) {
      // R5 (Plan 12.1-07 / WR-03, D-40) — jose 에러 code 비-PII 로깅.
      // Pitfall 1 / 7 — err.message / err.payload / err.claim / err.reason
      // 본문 절대 금지. err.code (jose 6.x stable public API) / err.name 만
      // short fingerprint 로 노출 — 운영 시 JWKS 네트워크 / kid not found /
      // clock skew / signature mismatch 등 분류 가능 (PII 안전 + 진단 가능).
      let errCode = "unknown";
      if (err instanceof joseErrors.JOSEError) {
        errCode = err.code ?? err.name;
      } else if (err instanceof Error) {
        errCode = err.name;
      }
      logger.warn(
        {event: "kakao_jwt_verify_failed", code: errCode},
        "Kakao ID Token verification failed",
      );
      if (err instanceof joseErrors.JOSEError) {
        throw new HttpsError("invalid-argument", "errorInvalidCredentials");
      }
      throw new HttpsError("internal", "errorUnknown");
    }
    if (!kakaoUserId) {
      throw new HttpsError("invalid-argument", "errorInvalidCredentials");
    }

    // Step 2: Identity Index resolve (Task 2 helper).
    // R3 (Phase 12.1-06 / BL-04 + WR-06, D-32) — caller throw responsibility.
    // helper 가 conflictKind 로 detect → caller 가 try/catch + switch 로 안전한
    // already-exists HttpsError 변환 (email enumeration 차단). helper 의
    // unexpected throw 는 internal 매핑 (D-32 fallback).
    const callerUid = request.auth?.uid; // unauthenticated 허용 (D-11).
    let resolution;
    try {
      resolution = await resolveIdentity(getFirestore(), {
        provider: "kakao",
        providerUserId: kakaoUserId,
        callerUid,
        // 비즈 앱 + 카카오계정(이메일) 필수 동의 시 ID Token 의 email claim 을
        // Firebase Auth user.email 로 저장. 일반 앱 (현재 dev) 은 undefined.
        userInfo: kakaoEmail ? {email: kakaoEmail} : undefined,
      });
    } catch {
      // helper 의 unexpected error (e.g., firestore network, internal) 는
      // internal 매핑. **Pitfall 1/7 (PII) 보존** — err.message / err.payload
      // 절대 미로깅. catch parameter 자체 생략 (optional catch binding) —
      // err 객체 접근 안 함 → 누구도 실수로 PII 로깅 못 함 (compile-time 보장).
      logger.error(
        {event: "identity_index_failed"},
        "resolveIdentity threw unexpected error",
      );
      throw new HttpsError("internal", "errorUnknown");
    }

    // R3 (D-32) — exhaustive switch — TypeScript 가 conflictKind union type 의
    // 모든 case 를 강제 (default arm 미사용 → 누락 시 컴파일 에러). Phase 13~16
    // 가 동일 helper 재사용 시 caller 도 동일 switch 패턴 미러.
    switch (resolution.conflictKind) {
    case "email_in_use":
      // Kakao ID Token 의 email 이 기존 Firebase Auth 사용자와 일치 — 안전한
      // 메시지로 collapse (email 본문 미노출, Pitfall 1/7).
      logger.warn(
        {event: "kakao_email_collision"},
        "Kakao email collides with existing account",
      );
      throw new HttpsError(
        "already-exists",
        "errorAccountExistsWithDifferentCredential",
      );
    case "anonymous_existing_collision":
      // 익명 사용자가 기존 kakao identity 로 로그인 시도 — anonymous Firestore
      // 데이터 손실 / UID hijack 위험 차단. Phase 17 (Account Linking) 가
      // 자동 마이그레이션 처리. 사용자에게는 동일 안전 메시지로 안내.
      logger.warn(
        {event: "kakao_anonymous_conflict"},
        "Anonymous user attempted to login with existing Kakao identity",
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
    const customToken = await getAuth().createCustomToken(uid);

    // Step 4: structured log — uid + isNewUser 만 (PII 금지).
    logger.info(
      {event: "kakao_custom_token_issued", uid, isNewUser},
      "Kakao custom token issued",
    );

    return {customToken, uid, isNewUser};
  },
);
