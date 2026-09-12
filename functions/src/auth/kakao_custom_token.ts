import {getAuth} from "firebase-admin/auth";
import {getFirestore} from "firebase-admin/firestore";
import {onCall, HttpsError} from "firebase-functions/https";
import * as logger from "firebase-functions/logger";
import {errors as joseErrors} from "jose";

import {
  KAKAO_NATIVE_APP_KEY,
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

// Phase 14 D-LINE-02/04 — OIDC verifier helper 추출 + retroactive 마이그.
// WR-06 (Phase 15 리뷰): issuer / jwksUrl / algorithms / nonceHashing 리터럴과
// secret 선언은 shared/oidc_providers.ts 단일 진실원으로 이동했다. 이전에는
// 같은 4-튜플이 본 파일과 link_custom_token_provider.ts 에 각각 존재해
// drift 위험 + provider 당 JWKS 캐시 2개 문제가 있었다.
const verifyKakaoIdToken = OIDC_VERIFIERS.kakao;

type KakaoCustomTokenRequest = {
  idToken: string;
  nonce: string;
  /**
   * Phase 16 D-13/D-14 (Plan 16-03 Task 3.2) — add-only optional.
   *
   * client (Plan 16-04) 의 Custom Token sign-up path 에서 신규 정식 UID 생성
   * 직후 termsAccepted Firestore mirror 의무 — Phase 14.1 A6 termsAccepted flip
   * bug root cause fix 의 Custom Token branch. snapshot=undefined 일 때 기존
   * behavior 보존 (회귀 0).
   */
  termsAcceptanceSnapshot?: TermsAcceptanceJson;
};
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
 * Phase 14 — see ROADMAP.md
 * D-LINE-02 + D-LINE-04 retroactive 이행: jose verify 로직을
 * `createOidcVerifier` factory (functions/src/shared/oidc_verifier.ts) 로
 * 흡수. `kakao_jwks.ts` 폐기 — jose JWKS remote set 생성 호출처가 helper 1
 * 곳 (Pitfall 3 sentinel).
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
    // WR-03 / IN-03: `as` 단언 + falsy-only 가드를 공용 타입 가드로 대체.
    // `{idToken: 12345, nonce: {}}` 같은 페이로드가 jose 단계까지 내려가
    // "자격증명 무효" 로 오분류되던 경로를 입력 오류로 정확히 분류한다.
    const idToken = requireStringArg(request.data?.idToken);
    const nonce = requireStringArg(request.data?.nonce, MAX_NONCE_ARG_LENGTH);

    // Step 1: ID Token JWT 자체 검증.
    let kakaoUserId: string | undefined;
    let kakaoEmail: string | undefined;
    // IN-04: OIDC 표준 email_verified claim — Kakao 가 발급 시 (비즈 앱 +
    // email 필수 동의 + 이메일 인증 완료) true. 미발급 시 undefined → 기본
    // false 로 보수 매핑. 기존에는 userInfo.email 존재만으로 무조건
    // email_verified=true 발급해서 unverified Kakao email 이 Firebase Auth
    // 의 verified email 로 잘못 propagate 될 가능성이 있었음 (현재 Kakao
    // 정책상 unverified email 은 응답에 없지만 미래 정책 변경 대비).
    let kakaoEmailVerified: boolean | undefined;
    // R10: OIDC 표준 claim — 동의 항목 활성화 + 사용자 동의 시에만 포함.
    let kakaoNickname: string | undefined;
    let kakaoPicture: string | undefined;
    try {
      // Phase 14 D-LINE-02 — helper 가 issuer / aud / alg / nonce 검증 모두
      // 흡수 (raw nonce === claim.nonce, nonceHashing="none"). 위반 시
      // joseErrors.JWTClaimValidationFailed / 기타 JOSEError throw.
      const payload = (await verifyKakaoIdToken(idToken, nonce)) as {
        sub?: string;
        // OIDC 표준 claim — 비즈 앱 + 카카오계정(이메일) 필수 동의 시 포함.
        // 일반 앱 또는 사용자 미동의 시 undefined.
        email?: string;
        // IN-04: OIDC standard email_verified claim. Kakao 의 ID Token 에
        // 발급되면 그대로 propagate. 미발급 시 undefined.
        email_verified?: boolean;
        // R10: OIDC standard userinfo claim — Kakao Console 동의 항목 활성화
        // (닉네임 / 프로필 사진) + 사용자 동의 시 포함. 일반 앱 / 미동의 시
        // undefined (silent — Firebase Auth user record 갱신 안 함).
        nickname?: string;
        picture?: string;
      };
      kakaoUserId = payload.sub;
      kakaoEmail = payload.email;
      kakaoEmailVerified = payload.email_verified;
      kakaoNickname = payload.nickname;
      kakaoPicture = payload.picture;
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
    // R10: email + nickname + picture 모두 userInfo 에 묶어서 helper 에 전달.
    // helper 가 createUser/updateUser 시점에 Firebase Auth user record 의
    // email/displayName/photoURL 에 propagate. 부재 항목은 silent (undefined).
    const userInfo: {email?: string; displayName?: string; photoURL?: string} =
      {};
    if (kakaoEmail) userInfo.email = kakaoEmail;
    if (kakaoNickname) userInfo.displayName = kakaoNickname;
    if (kakaoPicture) userInfo.photoURL = kakaoPicture;
    let resolution;
    try {
      resolution = await resolveIdentity(getFirestore(), {
        provider: "kakao",
        providerUserId: kakaoUserId,
        callerUid,
        userInfo: Object.keys(userInfo).length > 0 ? userInfo : undefined,
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
      // 16-13: existingProvider slug 를 details 로 전달 (client sheet 분기 wiring).
      throw buildAccountExistsError(resolution.existingProvider);
    case "anonymous_existing_collision":
      // 익명 사용자가 기존 kakao identity 로 로그인 시도 — anonymous Firestore
      // 데이터 손실 / UID hijack 위험 차단. Phase 17 (Account Linking) 가
      // 자동 마이그레이션 처리. 사용자에게는 동일 안전 메시지로 안내.
      logger.warn(
        {event: "kakao_anonymous_conflict"},
        "Anonymous user attempted to login with existing Kakao identity",
      );
      // 16-13: anonymous collision 도 resolution.existingProvider (= 호출
      // provider slug) 를 details 로 전달.
      throw buildAccountExistsError(resolution.existingProvider);
    case null:
      break; // 정상 flow.
    }

    const {uid, isNewUser} = resolution;

    // Step 3: Custom Token 발급 (admin SDK — 1h 만료).
    // CR-01 (Phase 13 review carry-forward): admin SDK throw (auth/internal-
    // error, auth/insufficient-permission 등) 도 internal + errorUnknown 으로
    // 매핑. 미적용 시 raw err.message 가 Cloud Functions runtime 의 INTERNAL
    // 응답에 그대로 노출 — D-08 PII 정책 위반.
    //
    // (Phase 9.2 Gap B 옵션 C — HUMAN-UAT 2026-05-11):
    //
    // 비-충돌 정상 path 에서 createCustomToken 의 developerClaims 인자로
    // userInfo.email 명시 — Firebase Admin SDK 가 client 의
    // getIdTokenResult().claims.email 로 propagate. 사용자 user.email=null
    // 회귀 차단 (Gap B 의 비-충돌 신규 가입 path 보조).
    //
    // **scope 제약**: userInfo.email 가 validated 상태 (Kakao OIDC ID Token
    // email claim 정상 반환) 에서만 추가. 부재 시 undefined (Firebase Admin
    // SDK 기본 동작). 충돌 path (conflictKind!==null) 는 switch 가 throw 우선
    // 해서 createCustomToken 자체 미도달 → developerClaims 발급 0 (의도된
    // 동작).
    //
    // **PII 정책**: developerClaims 는 Firebase Auth user record 의 idToken
    // claim 으로만 propagate — logger 어디에도 email 본문 미노출 (D-08).
    //
    // Phase 17 (Account Linking) — see ROADMAP.md
    //
    // IN-04: email_verified 는 Kakao OIDC ID Token 의 email_verified claim
    // 을 그대로 propagate. claim 미발급 시 보수적으로 false 매핑
    // (이전에는 무조건 true 발급해서 미래 Kakao 정책 변경 시 unverified
    // email 이 verified 로 잘못 propagate 될 가능성이 있었음).
    const developerClaims = userInfo.email ?
      {email: userInfo.email, email_verified: kakaoEmailVerified ?? false} :
      undefined;
    let customToken: string;
    try {
      customToken = await getAuth().createCustomToken(uid, developerClaims);
    } catch (err: unknown) {
      // PII 금지 (D-08) — err.message 본문 미로깅. err.name 만 fingerprint.
      const errCode = err instanceof Error ? err.name : "unknown";
      logger.error(
        {event: "kakao_custom_token_create_failed", code: errCode},
        "createCustomToken threw",
      );
      throw new HttpsError("internal", "errorUnknown");
    }

    // Step 3.5 (Phase 16 D-13/D-14 — Plan 16-03 Task 3.2):
    // termsAcceptanceSnapshot atomic mirror — Phase 14.1 A6 termsAccepted
    // flip bug root cause fix (Custom Token branch). client (Plan 16-04) 가
    // Custom Token sign-up path 의 신규 정식 UID 생성 직후 termsAccepted 를
    // Firestore 에 즉시 atomic write → client routing transient flip 0.
    // {merge:true} 의무 (기존 users/{uid} 필드 보존). snapshot=undefined 시
    // skip (기존 behavior 보존, 회귀 0).
    //
    // **Schema invariant (Pitfall 4 회피)**: 5 필드 verbatim — client 의
    // TermsAcceptance Freezed model mirror (lib/features/terms/domain/
    // terms_acceptance.dart). 변경 시 양쪽 동시 갱신 의무.
    //
    // **PII 정책**: snapshot 5 필드 (version/service/privacy/marketing/
    // acceptedAt) 모두 PII 비대상 — logger payload 에 version 만 노출 가능
    // (본체 미노출). best-effort 실패 처리는 hard throw — termsAccepted
    // mirror 실패 시 client routing 회귀 (UI flip) 위험.
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
          successEvent: "kakao_terms_acceptance_mirrored",
          failureEvent: "kakao_terms_acceptance_mirror_failed",
        });
      } catch {
        // helper 가 이미 PII-safe fingerprint 로 logger.error 를 남겼다.
        // 여기서는 HTTP 응답 layer 매핑만 담당 (D-33 layering 경계).
        throw new HttpsError("internal", "errorUnknown");
      }
    }

    // Step 4: structured log — uid + isNewUser 만 (PII 금지).
    logger.info(
      {event: "kakao_custom_token_issued", uid, isNewUser},
      "Kakao custom token issued",
    );

    return {customToken, uid, isNewUser};
  },
);
