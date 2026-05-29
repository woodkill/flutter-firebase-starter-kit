// Phase 16 — see ROADMAP.md (Plan 16-02 가 본체 채움 — Wave 0 sentinel placeholder).
//
// Pattern 2 (RESEARCH § Recommended Project Structure line 346~393 +
// § Pattern 2 linkCustomTokenProvider Example line 436~514):
//   D-04 hybrid 2nd branch — 기존 인증 사용자가 추가 provider 를 link 할 때
//   서버에서 Custom Token 을 발급하여 client 가 linkWithCredential 호출하도록 한다.
//
// 본 file 은 Wave 0 sentinel placeholder — Plan 16-02 가 본체 채움.
// Cloud Function 호출 시 HttpsError("unimplemented") fail-safe throw 로 deploy
// 되어도 client 호출이 명시적으로 실패한다 (T-16-W0-02 mitigation).
import {onCall, HttpsError} from "firebase-functions/https";

type LinkCustomTokenProviderRequest = {
  provider: string;
  credential: string;
};

type LinkCustomTokenProviderResponse = {
  customToken: string;
};

/**
 * 기존 인증 사용자에게 추가 provider link 용 Custom Token 발급
 * (Phase 16 D-04 hybrid 2nd branch).
 *
 * **Wave 0 sentinel placeholder** — Plan 16-02 가 본체 채움.
 *
 * 본체 구현 시 mirror source: functions/src/auth/line_custom_token.ts (Phase 14).
 * - request.auth null check → HttpsError "unauthenticated".
 * - enforceAppCheck: true (Phase 12 D-11 carry-forward).
 * - admin.auth().createCustomToken(uid) 1h 만료.
 */
export const linkCustomTokenProvider = onCall<
  LinkCustomTokenProviderRequest,
  Promise<LinkCustomTokenProviderResponse>
>({enforceAppCheck: true}, async (request) => {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "errorUnauthenticated");
  }
  throw new HttpsError(
    "unimplemented",
    "Plan 16-02 가 본체를 채움 — sentinel placeholder",
  );
});
