// Phase 13 — see ROADMAP.md
import {onCall} from "firebase-functions/https";

import {isAnonymousCaller} from "../shared/caller_auth";
import {invalidArgument} from "../shared/custom_token_errors";
import {NAVER_CLIENT_SECRET} from "../shared/naver_secrets";
import {requireStringArg} from "../shared/require_string_arg";
import {
  TermsAcceptanceJson,
  parseTermsAcceptanceJson,
} from "../shared/terms_acceptance_json";
import {
  NaverCustomTokenResult,
  verifyNaverProfileAndIssueCustomToken,
} from "./naver_profile_to_custom_token";

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
type NaverCustomTokenResponse = NaverCustomTokenResult;

/**
 * Naver access_token → Firebase Custom Token 발급 (Phase 13 D-46~D-51).
 *
 * 흐름:
 * 1. App Check enforcement (D-49, Pitfall 6) — request.auth=null 허용과 양립.
 * 2. 입력 검증 (D-50) — accessToken 빈/누락 · 상한 초과 · CRLF/NUL →
 *    invalid-argument.
 * 3~7. Naver REST 검증 → identity index → conflictKind switch → Custom Token
 *    → terms mirror → issued log 는 Phase 16.5 D-13 부터 공용 helper
 *    `verifyNaverProfileAndIssueCustomToken` (naver_profile_to_custom_token.ts)
 *    가 수행한다 — 매핑 표 · PII 정책 · 로그 event 이름은 그 helper 문서 참조.
 *    본 callable 은 caller 정보 (`request.auth`) 와 terms snapshot 을 파싱해
 *    넘기고 결과를 그대로 반환한다 (동작 · 이벤트 불변).
 *
 * **App Check + 미인증 양립 (D-49):** request.auth = null 분기 = 재설치 후
 * 첫 진입. App Check 토큰은 디바이스 attestation 으로 abuse 방어.
 *
 * @param {{data: NaverCustomTokenRequest, auth?: {uid: string}}} request
 *     onCall request — data.accessToken 의무, auth optional.
 * @return {Promise<NaverCustomTokenResponse>} customToken + uid + isNewUser.
 */
export const naverCustomToken = onCall<NaverCustomTokenRequest>(
  {
    enforceAppCheck: true,
    // D-60 정책 일관용 — 실사용처는 naverWebCustomToken (shared/naver_secrets.ts).
    secrets: [NAVER_CLIENT_SECRET],
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

    // Step 2~6 (Phase 16.5 D-13): 공용 helper 위임 — 동작 · 이벤트 불변.
    // debug reauth-login-auto-merge — 정식 로그인 caller 는 자기 계정에 매핑된
    // identity 로만 통과한다 (resolveIdentity 비익명 caller 가드, fail-closed).
    // WR-02: callable arg 는 신뢰할 수 없는 임의 JSON 이다 — 5 필드 타입을
    // 런타임 검증해 좁힌다. 실패 시 null (필드 무시, 로그인은 계속).
    return verifyNaverProfileAndIssueCustomToken({
      accessToken,
      callerUid: request.auth?.uid, // unauthenticated 허용 (D-49).
      callerIsAnonymous: isAnonymousCaller(request.auth),
      termsSnapshot: parseTermsAcceptanceJson(
        request.data?.termsAcceptanceSnapshot,
      ),
      path: "app", // IN-02 — helper 로그 경로 구분 축.
    });
  },
);
