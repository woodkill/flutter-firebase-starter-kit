// Phase 17.3 — see ROADMAP.md.
//
// OIDC ID token 을 주는 provider(Kakao · LINE)의 계정 연결 callable 공용
// 팩토리. provider 마다 전용 callable 파일이 이 팩토리를 1번 부르고 자기
// secret 만 넘긴다 — provider 를 끄면 그 provider 의 secret 없이 나머지 함수를
// 배포할 수 있다(on/off 계약). 연결 transaction 은
// `link_identity_transaction.ts` 를 공유한다.
//
// provider 는 팩토리 인자가 고정한다 — 요청 payload 로 검증할 provider ·
// secret 을 고르지 않는다(요청에 provider 필드가 와도 읽지 않는다).
//
// **IN-04**: 아래 `HttpsError` 들의 message 는 ARB 키가 아니라 taxonomy
// 토큰이다. client 는 `code` + `details.reason` 으로만 분기하며 서버 message
// 를 렌더하지 않는다 (재인증 필요 = `reason: reauthentication_required` —
// 16.9 review WR-01).
// 계약 전문은 `shared/custom_token_errors.ts` 헤더 참조.
import {getAuth} from "firebase-admin/auth";
import {getFirestore} from "firebase-admin/firestore";
import {onCall, HttpsError} from "firebase-functions/https";
import type {CallableFunction} from "firebase-functions/https";
import * as logger from "firebase-functions/logger";
import type {SecretParam} from "firebase-functions/params";

import {
  fingerprintJoseError,
  idpCredentialRejected,
  mapOidcVerifyError,
  reauthenticationRequired,
} from "../shared/custom_token_errors";
import {OIDC_VERIFIERS} from "../shared/oidc_providers";
import type {OidcProviderId} from "../shared/oidc_providers";
import {
  MAX_NONCE_ARG_LENGTH,
  requireStringArg,
} from "../shared/require_string_arg";
import {fingerprintError} from "./identity_index";
import {linkCustomTokenIdentity} from "./link_identity_transaction";

/** OIDC 연결 callable 요청 — provider 는 callable 이 고정하므로 싣지 않는다. */
export type LinkOidcProviderRequest = {
  /** current Firebase user 의 ID Token (caller 검증 — checkRevoked · uid 일치). */
  idToken: string;
  /** target provider 의 OIDC ID Token (Custom Token endpoint 와 동일 format). */
  targetProviderToken: string;
  /** OIDC nonce — 2 provider 모두 의무. */
  nonce: string;
};

/** OIDC 연결 callable 응답. */
export type LinkOidcProviderResponse = {
  ok: true;
};

/**
 * OIDC provider 계정 연결 callable 을 만든다 (Phase 17.3 D-01).
 *
 * 반환한 callable 의 흐름:
 *   Step 0: request.auth + 입력 검증 (`idToken` · `targetProviderToken` ·
 *           `nonce` 문자열 · nonce 길이 상한). provider 는 [provider] 인자로
 *           고정 — 요청 data 의 provider 필드는 읽지 않는다.
 *   Step 1: caller ID Token verify
 *           (`getAuth().verifyIdToken(idToken, checkRevoked=true)` + uid ===
 *           request.auth.uid). auth_time 신선도(300s)는 검사하지 않는다 —
 *           Firebase 는 계정 연결에 최근 로그인을 요구하지 않는다 (quick
 *           260928-cxs · `assertFreshAuth` 는 `deleteUserAccount` 만).
 *   Step 2: anonymous caller 거부 (`failed-precondition`) — 익명 user 는
 *           Custom Token endpoint 의 신규 sign-up 경로로 간다.
 *   Step 3: [provider] 의 OIDC verifier (`OIDC_VERIFIERS[provider]` — Custom
 *           Token endpoint 와 같은 singleton)로 target ID Token 검증 → `sub`.
 *   Step 4: `linkCustomTokenIdentity` — identity_index atomic create +
 *           linkedProviders[] update (all reads before all writes). 같은
 *           provider 의 다른 신원이 이미 연결돼 있으면 `already-exists` +
 *           reason `provider_already_linked` (16.9 review IN-03).
 *   Step 5: structured log + `{ok: true}`.
 *
 * **PII 금지:** logger payload 는 `{event, uid, code, isNewUser}` 만.
 * idToken · targetProviderToken · nonce · decoded.email · verifier payload
 * 본문은 로그 · 응답에 싣지 않는다.
 *
 * @param {OidcProviderId} provider 이 callable 이 검증할 OIDC provider —
 *     verifier · identity_index 문서 id · 로그 event 접두를 정한다.
 * @param {SecretParam[]} secrets 이 callable 에 binding 할 secret —
 *     [provider] 의 verifier 가 읽는 것만 넘긴다.
 * @return {CallableFunction<LinkOidcProviderRequest,
 *     Promise<LinkOidcProviderResponse>>} App Check 강제 callable.
 */
export function buildLinkOidcProviderCallable(
  provider: OidcProviderId,
  secrets: SecretParam[],
): CallableFunction<
  LinkOidcProviderRequest,
  Promise<LinkOidcProviderResponse>
> {
  return onCall<LinkOidcProviderRequest>(
    {
      enforceAppCheck: true,
      secrets,
    },
    async (request): Promise<LinkOidcProviderResponse> => {
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

      // Step 1: caller ID Token verify (신선도 검사 없음 — quick 260928-cxs)
      // (Firebase Admin SDK 공식 함수 — 자체 JWT decode 0).
      let decoded;
      try {
        decoded = await getAuth().verifyIdToken(
          idToken,
          true /* checkRevoked */,
        );
      } catch (err: unknown) {
        // PII 금지 — fingerprintError helper 만 사용 (err.message 본문 노출 0).
        logger.warn(
          {
            event: `link_${provider}_id_token_verify_failed`,
            code: fingerprintError(err),
          },
          "verifyIdToken threw",
        );
        // details.reason 으로 재로그인 분기를 표시한다 (16.9 review WR-01) —
        // 같은 code 의 IdP 거부 · App Check 차단은 reason 이 없다.
        throw reauthenticationRequired();
      }
      if (decoded.uid !== callerUid) {
        throw new HttpsError("permission-denied", "errorUnauthenticated");
      }

      // Step 2: anonymous caller 거부.
      if (decoded.firebase?.sign_in_provider === "anonymous") {
        throw new HttpsError(
          "failed-precondition",
          "errorAnonymousLinkNotAllowed",
        );
      }

      // Step 3: provider OIDC ID Token verify — provider 는 팩토리 인자라
      // 맵 조회가 총체적(total)이다.
      let targetSub: string | undefined;
      try {
        const payload = await OIDC_VERIFIERS[provider](
          targetProviderToken,
          nonce,
        );
        const typedPayload = payload as {sub?: string};
        targetSub = typedPayload.sub;
      } catch (err: unknown) {
        // PII 금지 — jose error code/name 만 fingerprint (Pitfall 3 회피).
        logger.warn(
          {
            event: `link_${provider}_target_token_verify_failed`,
            code: fingerprintJoseError(err),
          },
          "target ID Token verification failed",
        );
        // WR-01 / WR-02: Custom Token endpoint 와 동일한 공용 매핑 표.
        throw mapOidcVerifyError(err);
      }
      if (!targetSub) {
        // IdP 가 sub 없는 토큰을 준 경우 — 자격증명 사용 불가 축.
        throw idpCredentialRejected();
      }

      // Step 4: Firestore runTransaction — 공용 helper (16.9 D-01 · 동작 불변).
      await linkCustomTokenIdentity({
        db: getFirestore(),
        callerUid,
        provider,
        providerUserId: targetSub,
      });

      // Step 5: structured log + return. PII 금지 — {event, uid, isNewUser} 만.
      logger.info(
        {
          event: `link_${provider}_provider_succeeded`,
          uid: callerUid,
          isNewUser: false,
        },
        "linked",
      );
      return {ok: true};
    },
  );
}
