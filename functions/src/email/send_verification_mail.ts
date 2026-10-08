// Phase 17.5 — see ROADMAP.md (D-11 · D-12 · D-15 · 17 D-26) — kit 모드 인증
// 메일 callable. `emailDelivery=kit` 일 때만 배포한다(manifest `email.kit`).
//
// Firebase Console 은 인증 메일 본문을 바꿀 수 없으므로 kit 모드는 함수가
// 직접 보낸다: Admin `generateEmailVerificationLink` → `lang` 부착 →
// `renderMail` → Firestore `mail/` add(Trigger Email 확장이 발송). callable
// 성공 = `mail/` 기록까지다(D-12) — 실제 SMTP 전달은 확장이 맡는다.
//
// - 수신 주소는 검증된 ID token 의 `email` 뿐이다. 요청 본문은 `locale` 만
//   읽는다 — `email` · `appName` 같은 값을 실어 보내도 무시한다(17 D-26).
// - 브랜드 값은 함수 env(`readMailBrand`)만 쓴다(피싱 문구 위조 차단).
// - 남용 방어: uid 축 · 이메일 해시 축 rate limit 을 한 transaction 에서
//   판정한다. 문서 id 에 이메일 원문을 남기지 않는다.
//
// **IN-04**: 아래 `HttpsError` 들의 message 는 ARB 키가 아니라 taxonomy
// 토큰이다. client 는 `code` 로만 분기하며 서버 message 를 렌더하지 않는다.
import {getAuth} from "firebase-admin/auth";
import {getFirestore} from "firebase-admin/firestore";
import {onCall, HttpsError} from "firebase-functions/https";
import * as logger from "firebase-functions/logger";

import {fingerprintError} from "../auth/identity_index";
import {isAnonymousCaller} from "../shared/caller_auth";
import {ANONYMOUS_CALLER_REASON} from "../shared/custom_token_errors";
import {consumeRateLimitAxes} from "../shared/rate_limit";
import type {ExceededRateAxis} from "../shared/rate_limit";
import {readMailBrand} from "./brand";
import {hashEmail} from "./email_hash";
import {resolveMailLocale} from "./mail_locale";
import {attachLang, renderMail} from "./render_mail";

/** 요청 본문 — `locale` 만 읽는다 (그 밖 키는 무시). */
type SendVerificationMailRequest = {
  /** 앱 로케일 (`ko` · `en` · `ja` · `ko-KR` 류). 없으면 `en`. */
  locale?: unknown;
};

type SendVerificationMailResponse = {
  ok: true;
};

/** 커스터마이징 포인트 — uid 별 창당 허용 횟수. */
const UID_RATE_LIMIT = 5;

/** 커스터마이징 포인트 — 같은 주소(이메일 해시) 별 창당 허용 횟수. */
const EMAIL_RATE_LIMIT = 5;

/** 커스터마이징 포인트 — 두 축 공통 창 길이 (초). */
const RATE_WINDOW_SEC = 600;

/** rate limit 문서 id 접두 — `<접두><uid>` · `<접두><이메일 해시>`. */
const UID_DOC_PREFIX = "sendVerificationMail:";
const EMAIL_DOC_PREFIX = "sendVerificationMailEmail:";

/**
 * kit 모드 인증 메일 callable (Phase 17.5 D-11).
 *
 * 호출 조건: App Check 필수 · 정식 로그인 세션(익명 거부) · ID token 에
 * 이메일이 있어야 한다.
 *
 * 흐름:
 *   Step 0: `request.auth` 없음 → `unauthenticated` · 익명 →
 *           `failed-precondition` + `{reason: "anonymous_caller"}` · 토큰
 *           email 없음 → `failed-precondition` · 이미 인증 → 메일 없이
 *           `{ok: true}`.
 *   Step 1: 브랜드 env 미설정(`readMailBrand()` null) → `internal`.
 *   Step 2: uid · 이메일 해시 2축 rate limit (한 transaction) — 초과 축마다
 *           `verification_mail_rate_limited` 알람 + `resource-exhausted`.
 *   Step 3: Admin 링크 → `attachLang` → `renderMail("verifyEmail")` →
 *           `mail/` add → `{ok: true}`. 실패는 `internal`.
 *
 * **PII 금지:** logger payload 는 `{event, uid, axis, count, code, locale}`
 * 뿐이다. 이메일 · 링크 · oobCode · `err.message` 를 싣지 않는다.
 *
 * @param {{auth?: {uid: string, token: Record<string, unknown>}, data:
 *     SendVerificationMailRequest}} request onCall request.
 * @return {Promise<SendVerificationMailResponse>} `{ok: true}`.
 */
export const sendVerificationMail = onCall<SendVerificationMailRequest>(
  {enforceAppCheck: true},
  async (request): Promise<SendVerificationMailResponse> => {
    // Step 0: 호출자 검증 — 값 원천은 검증된 ID token 뿐이다.
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "errorUnauthenticated");
    }
    if (isAnonymousCaller(request.auth)) {
      throw new HttpsError(
        "failed-precondition",
        "errorAnonymousCallerNotAllowed",
        {reason: ANONYMOUS_CALLER_REASON},
      );
    }
    const uid = request.auth.uid;
    const tokenEmail: unknown = request.auth.token.email;
    if (typeof tokenEmail !== "string" || tokenEmail.trim() === "") {
      throw new HttpsError("failed-precondition", "errorMissingEmail");
    }
    const email = tokenEmail;
    if (request.auth.token.email_verified === true) {
      // 이미 인증된 주소 — 보낼 메일이 없다. 클라이언트에는 성공과 같다.
      logger.info(
        {event: "verification_mail_already_verified", uid},
        "sendVerificationMail skipped (already verified)",
      );
      return {ok: true};
    }

    // Step 1: 서버 브랜드 값 — 앱 이름이 없으면 메일 헤더 · 제목이 깨진다.
    const brand = readMailBrand();
    if (brand === null) {
      logger.error(
        {event: "email_brand_unset"},
        "EMAIL_APP_NAME is not configured",
      );
      throw new HttpsError("internal", "errorUnknown");
    }
    const locale = resolveMailLocale(request.data?.locale);

    // Step 2: 남용 방어 — 링크 생성 전에 판정한다.
    const db = getFirestore();
    let exceeded: ExceededRateAxis[];
    try {
      exceeded = await consumeRateLimitAxes(db, [
        {
          axis: "uid",
          docId: `${UID_DOC_PREFIX}${uid}`,
          limit: UID_RATE_LIMIT,
          windowSec: RATE_WINDOW_SEC,
        },
        {
          axis: "email",
          docId: `${EMAIL_DOC_PREFIX}${hashEmail(email)}`,
          limit: EMAIL_RATE_LIMIT,
          windowSec: RATE_WINDOW_SEC,
        },
      ]);
    } catch (err: unknown) {
      logger.warn(
        {
          event: "verification_mail_rate_limit_failed",
          uid,
          code: fingerprintError(err),
        },
        "rate limit transaction threw",
      );
      throw new HttpsError("internal", "errorUnknown");
    }
    if (exceeded.length > 0) {
      for (const hit of exceeded) {
        logger.warn(
          {
            event: "verification_mail_rate_limited",
            uid,
            axis: hit.axis,
            count: hit.count,
          },
          "sendVerificationMail rate limit exceeded",
        );
      }
      throw new HttpsError("resource-exhausted", "errorTooManyRequests");
    }

    // Step 3: 링크 → lang → 렌더 → mail/ 큐 기록.
    try {
      // actionCodeSettings 없음 — continueUrl 을 싣지 않는다(D-17).
      const link = await getAuth().generateEmailVerificationLink(email);
      const message = renderMail("verifyEmail", {
        locale,
        email,
        link: attachLang(link, locale),
        brand,
      });
      await db.collection("mail").add({to: [email], message});
    } catch (err: unknown) {
      logger.warn(
        {event: "verification_mail_failed", uid, code: fingerprintError(err)},
        "sendVerificationMail failed",
      );
      throw new HttpsError("internal", "errorUnknown");
    }

    logger.info(
      {event: "verification_mail_queued", uid, locale},
      "sendVerificationMail queued",
    );
    return {ok: true};
  },
);
