// Phase 13 — see ROADMAP.md
import {onCall} from "firebase-functions/https";
import {defineSecret} from "firebase-functions/params";

import {isAnonymousCaller} from "../shared/caller_auth";
import {invalidArgument} from "../shared/custom_token_errors";
import {requireStringArg} from "../shared/require_string_arg";
import {
  TermsAcceptanceJson,
  parseTermsAcceptanceJson,
} from "../shared/terms_acceptance_json";
import {
  NaverCustomTokenResult,
  verifyNaverProfileAndIssueCustomToken,
} from "./naver_profile_to_custom_token";

// Phase 13 D-60 — Secret Manager 주입.
// 배포 전 의무: `firebase functions:secrets:set NAVER_CLIENT_SECRET`.
// 본 Phase 13 단계에서 사용처 부재 (refresh / deauth 미사용 — Phase 17+ deferred)
// 이지만 secret 정책 일관성 / 시스템 보안 권장으로 미리 등록 (D-60).
//
// **IN-02 (Phase 15 리뷰) — LINE 과 정반대 정책인 이유 (의도된 비대칭):**
// 같은 "사용처 0건 secret" 상황에서 LINE 은 `LINE_CHANNEL_SECRET` 선언을
// **제거** 했다 (shared/oidc_providers.ts 의 해당 선언부 주석 참조). 두
// provider 의 결정이 갈린 이유는 운영자 부담의 비대칭이다.
// - Naver: `docs/manual.md` 단계 8 이 이미 등록 절차를 안내하고 있고, Naver
//   Developers 콘솔은 client secret 을 앱 생성과 동시에 발급하므로 운영자가
//   추가로 얻어야 할 값이 없다 → forward-prep 유지 (D-60).
// - LINE: 별도 채널 설정 화면에서 값을 찾아 1회성 더미 주입을 강제받는
//   부담이 있어 "최소 설정으로 시작" 가치와 충돌 → 선언 제거.
//
// Phase 17+ 에서 deauth / refresh flow 를 도입할 때 **두 provider 를 함께**
// 정렬한다 (그 시점에 LINE 은 재선언, Naver 는 실사용처 확보). 그 전까지 본
// 선언을 단순 "미사용" 으로 보고 제거하지 말 것 — D-60 결정을 되돌리는 것이다.
const NAVER_CLIENT_SECRET = defineSecret("NAVER_CLIENT_SECRET");

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
    });
  },
);
