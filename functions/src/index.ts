import {setGlobalOptions} from "firebase-functions";
import {onCall, HttpsError} from "firebase-functions/https";
import * as logger from "firebase-functions/logger";

import {REGION} from "./shared/region";

// 전역 region + 비용 가드 (D-04, Pitfall 3 — region 변경 불가).
setGlobalOptions({
  region: REGION,
  maxInstances: 10,
  memory: "256MiB",
  timeoutSeconds: 30,
});

/**
 * Phase 11 ping stub (D-01).
 *
 * Phase 12~16 Custom Token 함수가 복제할 패턴:
 * - request.auth null check (T-11-FN-02, V4 Access Control)
 * - HttpsError 표준 코드 매핑 (D-07, V7 Error Handling)
 * - structured logger + uid 만 (D-08, T-11-FN-01 PII 금지)
 */
export const ping = onCall((request) => {
  if (!request.auth) {
    logger.warn({event: "ping_unauthenticated"}, "ping called without auth");
    throw new HttpsError("unauthenticated", "errorUnauthenticated");
  }
  const uid = request.auth.uid;
  logger.info({event: "ping_invoked", uid}, "ping invoked");
  return {
    ok: true,
    region: REGION,
    serverTime: new Date().toISOString(),
  };
});

// Phase 12 D-06 — Kakao OIDC ID Token → Firebase Custom Token.
export {kakaoCustomToken} from "./auth/kakao_custom_token";
