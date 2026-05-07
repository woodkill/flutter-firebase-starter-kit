// Phase 13 — see ROADMAP.md
import {getAuth} from "firebase-admin/auth";
import {getFirestore} from "firebase-admin/firestore";
import {onCall, HttpsError} from "firebase-functions/https";
import * as logger from "firebase-functions/logger";
import {defineSecret} from "firebase-functions/params";

import {resolveIdentity} from "./identity_index";

// Phase 13 D-60 — Secret Manager 주입.
// 배포 전 의무: `firebase functions:secrets:set NAVER_CLIENT_SECRET`.
// 본 Phase 13 단계에서 사용처 부재 (refresh / deauth 미사용 — Phase 17+ deferred)
// 이지만 secret 정책 일관성 / 시스템 보안 권장으로 미리 등록 (D-60).
const NAVER_CLIENT_SECRET = defineSecret("NAVER_CLIENT_SECRET");

// Phase 13 D-46 / D-47 — Naver REST 검증 endpoint.
const NAVER_PROFILE_URL = "https://openapi.naver.com/v1/nid/me" as const;

// Phase 13 Pitfall 3 — Naver REST 5xx 무한 hang 방어.
// Cloud Function 30s timeout 까지 도달하기 전 5s 에서 abort.
const FETCH_TIMEOUT_MS = 5000;

type NaverCustomTokenRequest = {accessToken: string};
type NaverCustomTokenResponse = {
  customToken: string;
  uid: string;
  isNewUser: boolean;
};

// Naver `/v1/nid/me` 응답 본문 shape (D-47).
// resultcode='00' + response.id 가 정상 path. 본 Phase 13 단계에서는 email
// claim 만 (옵션) 사용 — name / nickname / profile_image / age / gender /
// birthday 등 추가 PII 는 의도적으로 미사용 (D-51 PII 최소 수집).
type NaverProfileResponse = {
  resultcode?: string;
  message?: string;
  response?: {
    id?: string;
    email?: string;
    // R10: 동의 항목 활성화 + 사용자 동의 시 포함 — Firebase Auth user.
    // displayName / photoURL 로 propagate.
    nickname?: string;
    profile_image?: string;
  };
};

/**
 * Naver access_token → Firebase Custom Token 발급 (Phase 13 D-46~D-51).
 *
 * 흐름:
 * 1. App Check enforcement (D-49, Pitfall 6) — request.auth=null 허용과 양립.
 * 2. 입력 검증 (D-50) — accessToken 빈/누락 → invalid-argument.
 * 3. Node 20 fetch + AbortController(5s) → Authorization: Bearer (D-46/D-48).
 *    - HTTP 401/403 → unauthenticated (errorInvalidCredentials)
 *    - HTTP 5xx → unavailable (errorServiceUnavailable)
 *    - HTTP 기타 4xx (예: 429) → unavailable (errorServiceUnavailable)
 *    - AbortError / network → unavailable (errorServiceUnavailable)
 * 4. JSON parse → resultcode='00' + response.id 검증 (D-47).
 *    - resultcode != '00' → unauthenticated (errorInvalidCredentials)
 *    - response.id 부재 → invalid-argument (errorInvalidCredentials)
 * 5. resolveIdentity helper (Phase 12.1 D-31~D-34 자동 상속).
 *    - resolveIdentity throw → internal (errorUnknown)
 * 6. caller switch on conflictKind (D-32 carry-forward).
 *    - 'email_in_use' → already-exists
 *      (errorAccountExistsWithDifferentCredential)
 *    - 'anonymous_existing_collision' → 동일
 * 7. createCustomToken — 1h 만료.
 *
 * **PII 금지 (D-51, Phase 11 D-08):** logger payload 는 {event, uid,
 * isNewUser, status?, resultcode?, code?} 만. Naver `/v1/nid/me` response
 * 본문 (id / email / name / nickname / profile_image / age / gender /
 * birthday) 은 절대 logger 인자에 포함 금지. err.message 미노출 — err.name
 * 만 fingerprint 로 노출 (Pitfall 1/7).
 *
 * **App Check + 미인증 양립 (D-49):** request.auth = null 분기 = 재설치 후
 * 첫 진입. App Check 토큰은 디바이스 attestation 으로 abuse 방어.
 *
 * Phase 14~16 (LINE/Yahoo!JP/WeChat) 진입 시 fetch + AbortController + REST
 * 검증 helper 추출 후보 (D-48, YAGNI — 본 Plan 은 verbatim 미러).
 *
 * @param {{data: NaverCustomTokenRequest, auth?: {uid: string}}} request
 *     onCall request — data.accessToken 의무, auth optional.
 * @return {Promise<NaverCustomTokenResponse>} customToken + uid + isNewUser.
 */
export const naverCustomToken = onCall<NaverCustomTokenRequest>(
  {
    enforceAppCheck: true,
    secrets: [NAVER_CLIENT_SECRET], // 사용처 0건 — D-60 정책 일관용
  },
  async (request): Promise<NaverCustomTokenResponse> => {
    // Step 1: 입력 검증 (D-50).
    const data = request.data ?? ({} as NaverCustomTokenRequest);
    const accessToken = data.accessToken;
    if (
      !accessToken ||
      typeof accessToken !== "string" ||
      accessToken.length === 0
    ) {
      throw new HttpsError("invalid-argument", "errorInvalidArgument");
    }

    // Step 2: Naver REST 검증 (D-46/D-47/D-48).
    let resp: Response;
    try {
      const controller = new AbortController();
      const timeoutId = setTimeout(
        () => controller.abort(),
        FETCH_TIMEOUT_MS,
      );
      try {
        resp = await fetch(NAVER_PROFILE_URL, {
          method: "GET",
          headers: {Authorization: `Bearer ${accessToken}`},
          signal: controller.signal,
        });
      } finally {
        clearTimeout(timeoutId);
      }
    } catch (err: unknown) {
      // PII 금지 (D-51) — err.message 본문 미로깅. err.name 만 fingerprint
      // (AbortError / TypeError / DNS 실패 등 분류 가능).
      const errCode = err instanceof Error ? err.name : "unknown";
      logger.warn(
        {event: "naver_fetch_failed", code: errCode},
        "Naver REST fetch failed",
      );
      // AbortError / TypeError(network) / DNS 실패 모두 unavailable.
      throw new HttpsError("unavailable", "errorServiceUnavailable");
    }

    if (resp.status === 401 || resp.status === 403) {
      logger.warn(
        {event: "naver_verify_unauthenticated", status: resp.status},
        "Naver access token rejected",
      );
      throw new HttpsError("unauthenticated", "errorInvalidCredentials");
    }
    if (resp.status >= 500) {
      logger.warn(
        {event: "naver_verify_unavailable", status: resp.status},
        "Naver REST 5xx",
      );
      throw new HttpsError("unavailable", "errorServiceUnavailable");
    }
    if (!resp.ok) {
      // 4xx 외 (예: 429 rate limit) — unavailable 로 일반화 + status fingerprint.
      logger.warn(
        {event: "naver_verify_failed", status: resp.status},
        "Naver REST non-OK",
      );
      throw new HttpsError("unavailable", "errorServiceUnavailable");
    }

    let responseBody: NaverProfileResponse;
    try {
      responseBody = (await resp.json()) as NaverProfileResponse;
    } catch (err: unknown) {
      const errCode = err instanceof Error ? err.name : "unknown";
      logger.warn(
        {event: "naver_parse_failed", code: errCode},
        "Naver REST JSON parse failed",
      );
      throw new HttpsError("internal", "errorUnknown");
    }

    if (responseBody.resultcode !== "00") {
      // resultcode 는 Naver 공식 코드 ('00' / '024' / '028' 등) — non-PII.
      logger.warn(
        {
          event: "naver_resultcode_non_success",
          resultcode: responseBody.resultcode,
        },
        "Naver resultcode not 00",
      );
      throw new HttpsError("unauthenticated", "errorInvalidCredentials");
    }

    const naverUserId = responseBody.response?.id;
    if (
      !naverUserId ||
      typeof naverUserId !== "string" ||
      naverUserId.length === 0
    ) {
      // Pitfall 4 — resultcode='00' but response.id missing →
      // undefined createCustomToken 방어.
      logger.error(
        {event: "naver_response_id_missing"},
        "Naver response.id missing",
      );
      throw new HttpsError("invalid-argument", "errorInvalidCredentials");
    }
    const naverEmail = responseBody.response?.email;
    // R10: response.nickname + response.profile_image 추출 → Firebase Auth
    // user record 의 displayName / photoURL 에 propagate. 동의 항목 활성화 +
    // 사용자 동의 시에만 응답에 포함 — 부재 시 undefined (silent).
    const naverNickname = responseBody.response?.nickname;
    const naverProfileImage = responseBody.response?.profile_image;

    // Step 3: Identity Index resolve (Phase 12.1 D-31~D-34 자동 상속).
    // helper 가 conflictKind 로 detect → caller 가 try/catch + switch 로 안전한
    // already-exists HttpsError 변환 (email enumeration 차단). helper 의
    // unexpected throw 는 internal 매핑 (D-32 fallback).
    const callerUid = request.auth?.uid; // unauthenticated 허용 (D-49).
    const userInfo: {email?: string; displayName?: string; photoURL?: string} =
      {};
    if (naverEmail) userInfo.email = naverEmail;
    if (naverNickname) userInfo.displayName = naverNickname;
    if (naverProfileImage) userInfo.photoURL = naverProfileImage;
    let resolution;
    try {
      resolution = await resolveIdentity(getFirestore(), {
        provider: "naver",
        providerUserId: naverUserId,
        callerUid,
        userInfo: Object.keys(userInfo).length > 0 ? userInfo : undefined,
      });
    } catch {
      // PII 보존 — catch parameter 생략 (D-40 / D-51, Phase 12 동일 패턴).
      // err 객체 접근 안 함 → 누구도 실수로 PII 로깅 못 함 (compile-time 보장).
      logger.error(
        {event: "identity_index_failed"},
        "resolveIdentity threw unexpected error",
      );
      throw new HttpsError("internal", "errorUnknown");
    }

    // Step 4: caller switch on conflictKind (Phase 12.1 D-32 carry-forward).
    // exhaustive switch — TypeScript 가 conflictKind union 의 모든 case 강제.
    switch (resolution.conflictKind) {
    case "email_in_use":
      logger.warn(
        {event: "naver_email_collision"},
        "Naver email collides with existing account",
      );
      throw new HttpsError(
        "already-exists",
        "errorAccountExistsWithDifferentCredential",
      );
    case "anonymous_existing_collision":
      logger.warn(
        {event: "naver_anonymous_conflict"},
        "Anonymous user attempted to login with existing Naver identity",
      );
      throw new HttpsError(
        "already-exists",
        "errorAccountExistsWithDifferentCredential",
      );
    case null:
      break; // 정상 flow.
    }

    const {uid, isNewUser} = resolution;

    // Step 5: Custom Token 발급 (admin SDK — 1h 만료).
    const customToken = await getAuth().createCustomToken(uid);

    // Step 6: structured log — uid + isNewUser 만 (PII 금지 D-51).
    logger.info(
      {event: "naver_custom_token_issued", uid, isNewUser},
      "Naver custom token issued",
    );

    return {customToken, uid, isNewUser};
  },
);
