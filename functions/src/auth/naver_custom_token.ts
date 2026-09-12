// Phase 13 — see ROADMAP.md
import {getAuth} from "firebase-admin/auth";
import {getFirestore} from "firebase-admin/firestore";
import {onCall} from "firebase-functions/https";
import * as logger from "firebase-functions/logger";
import {defineSecret} from "firebase-functions/params";

import {
  idpCredentialRejected,
  idpUnavailable,
  invalidArgument,
  serverFailure,
} from "../shared/custom_token_errors";
import {requireStringArg} from "../shared/require_string_arg";
import {
  TermsAcceptanceJson,
  parseTermsAcceptanceJson,
} from "../shared/terms_acceptance_json";
import {buildAccountExistsError} from "./account_exists_error";
import {resolveIdentity} from "./identity_index";
import {mirrorTermsAccepted} from "./mirror_terms";

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

type NaverCustomTokenRequest = {
  accessToken: string;
  /**
   * Phase 16 D-13/D-14 (Plan 16-03 Task 3.2) — add-only optional.
   *
   * client (Plan 16-04) 의 Custom Token sign-up path 에서 신규 정식 UID 생성
   * 직후 termsAccepted Firestore mirror 의무. snapshot=undefined 일 때 기존
   * behavior 보존 (회귀 0).
   */
  termsAcceptanceSnapshot?: TermsAcceptanceJson;
};
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
 *    WR-01: 아래 매핑은 4 endpoint 공용 표
 *    (shared/custom_token_errors.ts) 를 따른다.
 *    - HTTP 401/403 → unauthenticated (errorInvalidCredentials)
 *    - HTTP 5xx → unavailable (errorServiceUnavailable)
 *    - HTTP 기타 4xx (예: 429) → unavailable (errorServiceUnavailable)
 *    - AbortError / network → unavailable (errorServiceUnavailable)
 * 4. JSON parse → resultcode='00' + response.id 검증 (D-47).
 *    - resultcode != '00' → unauthenticated (errorInvalidCredentials)
 *    - response.id 부재 → unauthenticated (errorInvalidCredentials)
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
 * Phase 14~15 (LINE/Yahoo!JP) 진입 시 fetch + AbortController + REST
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
    // WR-03 / IN-03: typeof + 길이 검사는 4 provider 공용 helper 로 일원화.
    // `as` 단언 제거 — request.data 를 좁히지 않고 값만 검증한다.
    const accessToken = requireStringArg(request.data?.accessToken);
    if (
      // HTTP 헤더 forbidden chars (CRLF / NUL) 차단 — undici 가 internal
      // 에서 throw 하기 전에 명시 거부. CRLF injection 회피 + 정확한
      // invalid-argument 분류 (WR-01). 매칭 정규식은 의도적으로 control
      // char 만 좁게 (token 본문은 base64url 등 가변).
      //
      // 본 필터는 Naver 전용으로 남는다 — 4 provider 중 Naver 만 값을 HTTP
      // 헤더(`Authorization: Bearer ...`)에 싣기 때문이다. 나머지 3종은 값을
      // jose 에만 넘기므로 헤더 injection 표면이 없다.
      // eslint-disable-next-line no-control-regex -- WR-01 의도된 CRLF/NUL 필터
      /[\r\n\x00]/.test(accessToken)
    ) {
      throw invalidArgument();
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
      // WR-01: 4 endpoint 공용 매핑 표 (IdP 도달 실패 = transient).
      throw idpUnavailable();
    }

    if (resp.status === 401 || resp.status === 403) {
      logger.warn(
        {event: "naver_verify_unauthenticated", status: resp.status},
        "Naver access token rejected",
      );
      throw idpCredentialRejected();
    }
    if (resp.status >= 500) {
      logger.warn(
        {event: "naver_verify_unavailable", status: resp.status},
        "Naver REST 5xx",
      );
      throw idpUnavailable();
    }
    if (!resp.ok) {
      // 4xx 외 (예: 429 rate limit) — unavailable 로 일반화 + status fingerprint.
      logger.warn(
        {event: "naver_verify_failed", status: resp.status},
        "Naver REST non-OK",
      );
      throw idpUnavailable();
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
      throw serverFailure();
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
      throw idpCredentialRejected();
    }

    const naverUserId = responseBody.response?.id;
    if (
      !naverUserId ||
      typeof naverUserId !== "string" ||
      naverUserId.length === 0
    ) {
      // Pitfall 4 — resultcode='00' but response.id missing →
      // undefined createCustomToken 방어. resultcode 도 함께 기록 (WR-06)
      // — Naver API 가 success code 를 반환했는데 id 가 누락된 케이스 vs.
      // 다른 unexpected status 로 분기 (어차피 본 분기는 resultcode='00'
      // 만 도달하지만 ops triage 시 fingerprint 일관성 + 회귀 가드).
      logger.error(
        {
          event: "naver_response_id_missing",
          resultcode: responseBody.resultcode,
        },
        "Naver response.id missing",
      );
      // WR-01: IdP 가 id 없는 응답을 준 경우도 "자격증명 사용 불가" 축으로
      // 통일한다 (4 endpoint 공용 매핑 표).
      throw idpCredentialRejected();
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
    const userInfo: {
      email?: string;
      emailVerified?: boolean;
      displayName?: string;
      photoURL?: string;
    } = {};
    if (naverEmail) userInfo.email = naverEmail;
    // WR-04: Naver `/v1/nid/me` 는 REST API 라 email_verified 표준 claim 이
    // 없다. 아래 developerClaims 주석과 **같은 가정** ("응답에 email 이 있으면
    // verified") 을 user record 에도 명시적으로 적용한다 — 두 곳이 서로 다른
    // 값을 쓰던 모순을 제거한다. 가정을 뒤집으려면 두 곳을 함께 바꿀 것.
    if (naverEmail) userInfo.emailVerified = true;
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
      throw serverFailure();
    }

    // Step 4: caller switch on conflictKind (Phase 12.1 D-32 carry-forward).
    // exhaustive switch — TypeScript 가 conflictKind union 의 모든 case 강제.
    switch (resolution.conflictKind) {
    case "email_in_use":
      logger.warn(
        {event: "naver_email_collision"},
        "Naver email collides with existing account",
      );
      // 16-13: existingProvider slug 를 details 로 전달 (client sheet 분기 wiring).
      throw buildAccountExistsError(resolution.existingProvider);
    case "anonymous_existing_collision":
      logger.warn(
        {event: "naver_anonymous_conflict"},
        "Anonymous user attempted to login with existing Naver identity",
      );
      // 16-13: anonymous collision 도 resolution.existingProvider (= 호출
      // provider slug) 를 details 로 전달.
      throw buildAccountExistsError(resolution.existingProvider);
    case null:
      break; // 정상 flow.
    }

    const {uid, isNewUser} = resolution;

    // Step 5: Custom Token 발급 (admin SDK — 1h 만료).
    // CR-01 (Phase 13 review): admin SDK throw (auth/internal-error,
    // auth/insufficient-permission 등) 도 internal + errorUnknown 으로 매핑.
    // 미적용 시 raw err.message 가 Cloud Functions runtime 의 INTERNAL 응답에
    // 그대로 노출 — D-08 PII 정책 위반.
    //
    // (Phase 9.2 Gap B 옵션 C — HUMAN-UAT 2026-05-11):
    //
    // 비-충돌 정상 path 에서 createCustomToken 의 developerClaims 인자로
    // userInfo.email 명시 — Firebase Admin SDK 가 client 의
    // getIdTokenResult().claims.email 로 propagate. 사용자 user.email=null
    // 회귀 차단 (Gap B 의 비-충돌 신규 가입 path 보조).
    //
    // **scope 제약**: userInfo.email 가 validated 상태 (Naver REST response.email
    // 정상 반환) 에서만 추가. 부재 시 undefined (Firebase Admin SDK 기본 동작).
    // 충돌 path (conflictKind!==null) 는 switch 가 throw 우선해서 createCustomToken
    // 자체 미도달 → developerClaims 발급 0 (의도된 동작).
    //
    // **PII 정책**: developerClaims 는 Firebase Auth user record 의 idToken
    // claim 으로만 propagate — logger 어디에도 email 본문 미노출 (D-51).
    //
    // Phase 17 (Account Linking) — see ROADMAP.md
    //
    // IN-04: Naver `/v1/nid/me` 는 OIDC 가 아니라 REST API 이며
    // email_verified 표준 claim 미제공. Naver 정책상 `email` 필드는 사용자
    // 동의 시 항상 반환되며 verification 상태 구분이 응답에 없다 — 따라서
    // 본 starter-kit 은 **"Naver 응답에 email 이 포함되어 있다면 verified"**
    // 라는 가정을 채택하고 email_verified=true 를 명시 발급. Naver 가
    // unverified email 도 응답에 포함하는 정책 변경 시 본 가정 재검토 필요
    // (Naver 개발자 공지 / Changelog 추적). Kakao 와 달리 IdP 측 grounding
    // claim 이 없으므로 starter-kit 측 정책 결정 영역 — 사용자 fork 시
    // 본 단락 한 줄 (`email_verified: true` → `false`) 변경 가능.
    const developerClaims = userInfo.email ?
      {email: userInfo.email, email_verified: true} :
      undefined;
    let customToken: string;
    try {
      customToken = await getAuth().createCustomToken(uid, developerClaims);
    } catch (err: unknown) {
      // PII 금지 (D-51) — err.message 본문 미로깅. err.name 만 fingerprint.
      const errCode = err instanceof Error ? err.name : "unknown";
      logger.error(
        {event: "naver_custom_token_create_failed", code: errCode},
        "createCustomToken threw",
      );
      throw serverFailure();
    }

    // Step 5.5 (Phase 16 D-13/D-14 — Plan 16-03 Task 3.2):
    // termsAcceptanceSnapshot atomic mirror — Phase 14.1 A6 root cause fix
    // 의 Custom Token branch. {merge:true} 의무. snapshot=undefined 시 skip.
    // PII 정책 보존 — snapshot 본체 미노출, version 만 logger payload 노출.
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
          successEvent: "naver_terms_acceptance_mirrored",
          failureEvent: "naver_terms_acceptance_mirror_failed",
        });
      } catch {
        // helper 가 이미 PII-safe fingerprint 로 logger.error 를 남겼다.
        throw serverFailure();
      }
    }

    // Step 6: structured log — uid + isNewUser 만 (PII 금지 D-51).
    logger.info(
      {event: "naver_custom_token_issued", uid, isNewUser},
      "Naver custom token issued",
    );

    return {customToken, uid, isNewUser};
  },
);
