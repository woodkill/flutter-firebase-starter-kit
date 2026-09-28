// Phase 14 — see ROADMAP.md
import {getAuth} from "firebase-admin/auth";
import {getFirestore} from "firebase-admin/firestore";
import {onCall} from "firebase-functions/https";
import * as logger from "firebase-functions/logger";

import {isAnonymousCaller} from "../shared/caller_auth";
import {
  callerIdentityMismatch,
  fingerprintJoseError,
  idpCredentialRejected,
  mapOidcVerifyError,
  serverFailure,
} from "../shared/custom_token_errors";
import {
  LINE_CHANNEL_ID,
  OIDC_VERIFIERS,
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

// Phase 14 D-LINE-01 / D-LINE-03 / D-LINE-05 — OIDC verifier.
// WR-06 (Phase 15 리뷰): issuer / jwksUrl / algorithms / nonceHashing 리터럴과
// LINE_CHANNEL_ID secret 선언은 shared/oidc_providers.ts 단일 진실원으로
// 이동했다 (해당 파일에 provider 별 근거 verbatim 보존). 이전에는 같은
// 4-튜플이 본 파일과 link_custom_token_provider.ts 에 각각 존재해 drift
// 위험 + provider 당 JWKS 캐시 2개 문제가 있었다.
const verifyLineIdToken = OIDC_VERIFIERS.line;

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
 * picture / email) 절대 금지.
 *
 * **App Check + 미인증 양립 (D-LINE-D11):** request.auth = null 분기 = 재설치
 * 후 첫 진입. App Check 토큰은 디바이스 attestation 으로 abuse 방어.
 *
 * **HttpsError 매핑 (WR-01 / WR-02 — 4 endpoint 공용 표,
 * shared/custom_token_errors.ts):**
 * - IdP 가 토큰 거부 (서명/클레임/만료/sub 부재) → `unauthenticated` /
 *   `errorInvalidCredentials`.
 * - IdP 도달 실패 (JWKS timeout / non-200 / DNS / ECONNREFUSED) →
 *   `unavailable` / `errorServiceUnavailable` (transient — 재시도 안내).
 * - 입력 계약 위반 → `invalid-argument` / `errorInvalidArgument`.
 * - 서버 자체 결함 (Firestore / admin SDK) → `internal` / `errorUnknown`.
 *
 * **email (quick 260928-luw — D-LINE-21 개정):** 클라이언트는 openid +
 * profile + email 을 요청한다 (D-1). payload `email` 은 채널에 email 권한이
 * 있고 · 사용자가 동의했고 · LINE 계정에 이메일이 등록된 경우에만 온다.
 * 있으면 userInfo.email + emailVerified=true · developerClaims
 * `{email, email_verified: true}`, 없으면 이전과 같다 (userInfo.email 미설정 ·
 * `createCustomToken(uid)` 1-인자).
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
    // WR-03 / IN-03: `as` 단언 + falsy-only 가드를 공용 타입 가드로 대체.
    // 비-string payload 가 jose 단계까지 내려가 "자격증명 무효" 로
    // 오분류되던 경로를 입력 오류로 정확히 분류한다.
    const idToken = requireStringArg(request.data?.idToken);
    const nonce = requireStringArg(request.data?.nonce, MAX_NONCE_ARG_LENGTH);

    // Step 1: ID Token JWT 자체 검증 — helper 호출.
    let lineUserId: string | undefined;
    let lineDisplayName: string | undefined;
    let linePictureUrl: string | undefined;
    let lineEmail: string | undefined;
    try {
      // helper 가 issuer / aud / alg / nonce 검증 모두 흡수. nonce 는 raw
      // 그대로 claim 과 비교 (Phase 14.1 D-14.1-02 — line-sdk-android
      // LineIdToken.java verbatim "the same value as in the authentication
      // request"). 위반 시 joseErrors.JWTClaimValidationFailed / 기타
      // JOSEError throw.
      const payload = await verifyLineIdToken(idToken, nonce);
      // LINE ID token payload 필드 = iss · sub · aud · exp · iat ·
      // auth_time · nonce · amr · name · picture · email — `email_verified`
      // 는 없다 (<https://developers.line.biz/en/docs/line-login/verify-id-token/>).
      // email 은 scope 에 email 이 있고 채널 email 권한 + 사용자 동의가 있을
      // 때만 포함된다 (quick 260928-luw). 반드시 위 검증 성공 뒤에만 읽는다.
      const typedPayload = payload as {
        sub?: string;
        // OIDC 표준 userinfo claim — LINE 사용자 표시명 + 프로필 이미지
        // (사용자 동의 시 포함). 미동의 시 undefined → Firebase Auth user
        // record 미갱신.
        name?: string;
        picture?: string;
        // 신뢰 경계 — 타입을 가정하지 않고 아래 타입 가드로 좁힌다.
        email?: unknown;
      };
      lineUserId = typedPayload.sub;
      lineDisplayName = typedPayload.name;
      linePictureUrl = typedPayload.picture;
      // 비어 있지 않은 문자열만 채택 — 빈 문자열 · 비문자열은 「없음」.
      const rawEmail = typedPayload.email;
      if (typeof rawEmail === "string" && rawEmail.length > 0) {
        lineEmail = rawEmail;
      }
    } catch (err: unknown) {
      // PII 금지 (Pitfall 1 / 7 / D-LINE-40 carry-forward) — jose 에러 code
      // 비-PII 로깅. err.message / err.payload / err.claim / err.reason 본문
      // 절대 금지. err.code (jose 6.x stable public API) / err.name 만 short
      // fingerprint 로 노출.
      const errCode = fingerprintJoseError(err);
      logger.warn(
        {event: "line_jwt_verify_failed", code: errCode},
        "LINE ID Token verification failed",
      );
      // WR-01 / WR-02: 4 endpoint 공용 매핑. JWKS 도달 실패 (timeout / non-200)
      // 는 자격증명 무효가 아니라 transient (`unavailable`) 로 분류한다 —
      // 이전에는 정상 토큰이 IdP 인프라 장애만으로 영구 실패처럼 보였다.
      throw mapOidcVerifyError(err);
    }
    if (!lineUserId) {
      // WR-01: IdP 가 sub 없는 토큰을 준 경우도 "자격증명 사용 불가" 축으로
      // 통일한다 (4 endpoint 공용 매핑 표).
      throw idpCredentialRejected();
    }

    // Step 2: Identity Index resolve — Phase 12.1 helper 자동 상속.
    // email (quick 260928-luw) · displayName · photoURL 을 helper 에 전달하고,
    // helper 가 createUser / updateUser 시점에 Firebase Auth user record 에
    // propagate 한다. email 이 있으면 helper 의 같은-이메일 충돌 감지
    // (email_in_use) 도 LINE 에서 동작한다. 없으면 userInfo.email 미설정.
    const callerUid = request.auth?.uid; // unauthenticated 허용.
    // debug reauth-login-auto-merge — 정식 로그인 caller 는 자기 계정에 매핑된
    // identity 로만 통과한다 (resolveIdentity 비익명 caller 가드, fail-closed).
    const callerIsAnonymous = isAnonymousCaller(request.auth);
    const userInfo: {
      email?: string;
      emailVerified?: boolean;
      displayName?: string;
      photoURL?: string;
    } = {};
    if (lineEmail) userInfo.email = lineEmail;
    // LINE ID token 에는 email_verified claim 이 없다 → 아래 developerClaims
    // 주석과 **같은 가정** (「payload 에 email 이 있으면 verified」) 을 user
    // record 에도 적용한다 (Naver WR-04 선례). 가정을 뒤집으려면 두 곳을
    // 함께 바꿀 것.
    if (lineEmail) userInfo.emailVerified = true;
    if (lineDisplayName) userInfo.displayName = lineDisplayName;
    if (linePictureUrl) userInfo.photoURL = linePictureUrl;
    let resolution;
    try {
      resolution = await resolveIdentity(getFirestore(), {
        provider: "line", // D-LINE-09 — provider 슬러그
        providerUserId: lineUserId,
        callerUid,
        callerIsAnonymous,
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
      throw serverFailure();
    }

    // R3 exhaustive switch on conflictKind — TypeScript exhaustiveness check
    // 자동 강제 (default arm 미사용 → union type 누락 시 컴파일 에러).
    switch (resolution.conflictKind) {
    case "email_in_use":
      // quick 260928-luw — LINE ID token 에 email 이 있을 때 도달한다.
      // `resolveIdentity` 가 `email_in_use` 를 반환하는 두 경로:
      // (1) caller 가 있고 `userInfo.email` 이 있을 때 `getUserByEmail` 로
      //     다른 계정 (native providerData 또는 identity_index 역조회의
      //     Custom Token slug) 을 찾은 경우,
      // (2) caller 가 없을 때 `createUser` 가 `auth/email-already-in-use`.
      //
      // **ops 주의:** email 권한이 없는 채널 (킷 dev 채널 포함) 은 payload 에
      // email 이 없어 이 arm 이 발화하지 않는다. `line_email_collision` 을
      // 운영 지표로 쓸 때는 채널 email 권한 여부를 함께 볼 것.
      //
      // exhaustive switch 가 conflictKind union 변경을 컴파일 단계에서
      // 강제하고, Phase 9.2 Gap B (callerUid + userInfo.email) path 와의
      // 정책 일관성도 여기서 잠긴다.
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
    case "caller_identity_mismatch":
      // debug reauth-login-auto-merge — 정식 로그인 caller 가 자기 계정에
      // 매핑되지 않은 LINE identity 로 호출 (재인증 화면에서 다른 계정 ·
      // 미연결 계정 선택). identity 등록 · 프로필 변경 없이 거부한다.
      // already-exists 로 보내면 client 가 계정 연결 시트를 열어 다시 같은
      // callable 로 돌아오므로 전용 reason 으로 구분한다.
      logger.warn(
        {event: "line_caller_identity_mismatch"},
        "Signed-in caller used a LINE identity not mapped to it",
      );
      throw callerIdentityMismatch();
    case null:
      break; // 정상 flow.
    }

    const {uid, isNewUser} = resolution;

    // Step 3: Custom Token 발급 (admin SDK — 1h 만료).
    // quick 260928-luw — userInfo.email 이 있으면 developerClaims 로 client
    // 의 getIdTokenResult().claims.email 에 propagate 한다 (Kakao · Naver 옵션
    // C 와 같은 모양). 충돌 path 는 위 switch 가 먼저 throw 하므로 여기 미도달.
    //
    // LINE ID token 에는 `email_verified` claim 이 없다 → 본 starter-kit 은
    // **「payload 에 email 이 있으면 verified」** 정책을 채택하고
    // email_verified=true 를 명시 발급한다. 근거: LINE Help Center 의 이메일
    // 등록 절차 — 사용자가 그 주소로 온 인증 코드를 입력하거나 메일의 URL 을
    // 탭해야 등록된다
    // (<https://help.line.me/line/smartphone/?contentId=20000060&lang=en>).
    // fork 에서 미검증 취급으로 바꾸려면 이 단락의 `email_verified: true` 와
    // Step 2 의 `userInfo.emailVerified = true` 두 곳을 함께 false 로 (각 한
    // 줄) — 그러면 이메일 있는 LINE 사용자는 `/verify-email` 게이트
    // (auth_guard 분기 (4)) 를 거친다.
    //
    // **PII 정책**: developerClaims 는 ID token claim 으로만 전파되고 logger
    // 에는 싣지 않는다.
    //
    // email 이 없으면 developerClaims 없이 `createCustomToken(uid)` 1-인자
    // 호출을 그대로 둔다 (이메일 없음 = 이전과 동일).
    //
    // CR-01 carry-forward: admin SDK throw 도 internal + errorUnknown 매핑.
    // err.message 본문 미노출 (PII 금지) — err.name 만 fingerprint.
    const developerClaims = userInfo.email ?
      {email: userInfo.email, email_verified: true} :
      undefined;
    let customToken: string;
    try {
      customToken = developerClaims ?
        await getAuth().createCustomToken(uid, developerClaims) :
        await getAuth().createCustomToken(uid);
    } catch (err: unknown) {
      const errCode = err instanceof Error ? err.name : "unknown";
      logger.error(
        {event: "line_custom_token_create_failed", code: errCode},
        "createCustomToken threw",
      );
      throw serverFailure();
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
          successEvent: "line_terms_acceptance_mirrored",
          failureEvent: "line_terms_acceptance_mirror_failed",
        });
      } catch {
        // helper 가 이미 PII-safe fingerprint 로 logger.error 를 남겼다.
        throw serverFailure();
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
