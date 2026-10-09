// Phase 17.5 — see ROADMAP.md (D-10 · D-11 · D-12 · D-15 · D-23) — kit 모드 비밀번호
// 재설정 메일 callable. `emailDelivery=kit` 일 때만 배포한다(manifest
// `email.kit`).
//
// 인증 메일과 같은 템플릿 · 브랜드로 보낸다: Admin `generatePasswordResetLink`
// → 결과 페이지 링크로 재작성(`toResultPageLink` — 쿼리 보존 · `lang` 부착,
// D-22 ①) → `renderMail("resetPassword")` → Firestore `mail/` add
// (Trigger Email 확장이 발송). callable 성공 = `mail/` 기록까지다(D-12).
// 링크 호스트 · 경로는 함수 env(`readResultPageUrl`)만 쓰고(링크 위조 차단 ·
// D-22 ②), 값이 없으면 메일을 보내지 않는다(D-22 ③).
//
// **가입 여부 비노출 (D-10 · EEP 계약 — 앱 `forgot_password_notifier.dart`):**
// 없는 주소도 있는 주소와 같은 `{ok: true}` 를 돌려준다. rate limit 은 링크
// 생성 **전** 에 판정하므로 존재 여부와 무관하게 같은 제한이 걸린다. 결과
// 페이지 주소 env 판정도 rate limit · 링크 생성 전이라 env 가 빠진
// 프로젝트에서도 있는 주소 · 없는 주소 응답이 같다.
// 이메일 열거 보호가 켜진 프로젝트는 없는 주소의 링크 생성이
// `auth/internal-error` 로 실패하므로(계정 없음 코드가 아님), rate limit
// 뒤 · 링크 생성 전에 Admin `getUserByEmail` 로 계정 유무를 먼저 본다(D-23).
// 열거 보호를 꺼도 조회가 같은 `auth/user-not-found` 를 내므로 응답 · 로그가
// 같다.
// 비노출 범위는 **응답 모양 · 오류 코드 · 로그** 셋이다. 소요 시간은 맞추지
// 않는다 — 있는 주소는 링크 생성 · 렌더 · `mail/` 기록을 더 치러 늦게 돌아온다.
// 같은 방어층(App Check + `request.auth`) 아래 `lookupSignInMethods` 가 임의
// 주소의 가입 provider 를 이미 돌려주므로 소요 축을 맞춰도 계정 유무는 감춰지지
// 않고, rate limit(이메일 · uid · IP 3축)이 반복 측정의 비용만 올린다(리뷰
// WR-02 수용 결정 — 최소 응답 시간 하한은 두지 않는다).
//
// **익명 허용 (RESEARCH §R7):** 비밀번호 찾기 화면은 로그인 전이라 세션이
// 익명이거나(앱 시작 시 익명 로그인) 정식(재인증 흐름)이다. 그래서
// `request.auth` 만 요구하고 `isAnonymousCaller` 로 거르지 않는다. 익명 UID 는
// 무제한 발급되므로 uid 축만으로는 부족하다 — IP 해시 · 이메일 해시 축이 그
// 우회로를 닫는다(`lookup_sign_in_methods.ts` WR-08 과 같은 판단).
//
// **IN-04**: 아래 `HttpsError` 들의 message 는 ARB 키가 아니라 taxonomy
// 토큰이다. client 는 `code` 로만 분기하며 서버 message 를 렌더하지 않는다.
import {createHash} from "node:crypto";

import {getAuth} from "firebase-admin/auth";
import {getFirestore} from "firebase-admin/firestore";
import {onCall, HttpsError} from "firebase-functions/https";
import * as logger from "firebase-functions/logger";

import {fingerprintError} from "../auth/identity_index";
import {consumeRateLimitAxes} from "../shared/rate_limit";
import type {ExceededRateAxis, RateLimitAxis} from "../shared/rate_limit";
import {requireStringArg} from "../shared/require_string_arg";
import {readMailBrand, readResultPageUrl} from "./brand";
import {hashEmail} from "./email_hash";
import {resolveMailLocale} from "./mail_locale";
import {renderMail, toResultPageLink} from "./render_mail";

/** 요청 본문 — `email` · `locale` 만 읽는다 (그 밖 키는 무시). */
type SendPasswordResetMailRequest = {
  /** 재설정할 계정 이메일 (신뢰할 수 없는 입력). */
  email?: unknown;
  /** 앱 로케일 (`ko` · `en` · `ja` · `ko-KR` 류). 없으면 `en`. */
  locale?: unknown;
};

type SendPasswordResetMailResponse = {
  ok: true;
};

/** 이메일 주소 상한 (RFC 5321 경로 길이 기준 — 320자). */
const MAX_EMAIL_LENGTH = 320;

/** 커스터마이징 포인트 — uid 별 창당 허용 횟수 · 창 길이(초). */
const UID_RATE_LIMIT = 5;
const UID_RATE_WINDOW_SEC = 60;

/**
 * 커스터마이징 포인트 — 클라이언트 IP 별 창당 허용 횟수 · 창 길이(초).
 * NAT · 회사망 공유를 고려해 uid 축보다 넉넉하게 잡는다.
 */
const IP_RATE_LIMIT = 30;
const IP_RATE_WINDOW_SEC = 60;

/** 커스터마이징 포인트 — 같은 주소(이메일 해시) 별 창당 허용 횟수 · 창 길이(초). */
const EMAIL_RATE_LIMIT = 3;
const EMAIL_RATE_WINDOW_SEC = 600;

/** rate limit 문서 id 접두 — `<접두><uid>` · `<접두><해시>`. */
const UID_DOC_PREFIX = "sendPasswordResetMail:";
const IP_DOC_PREFIX = "sendPasswordResetMailIp:";
const EMAIL_DOC_PREFIX = "sendPasswordResetMailEmail:";

/** Admin 이 「계정 없음」 으로 답하는 코드 — 응답은 성공과 같다(D-10). */
const NO_ACCOUNT_CODES: readonly string[] = [
  "auth/email-not-found",
  "auth/user-not-found",
];

/**
 * 계정 없음 응답 — 메일 없이 있는 주소와 같은 `{ok: true}` 를 돌려준다.
 *
 * 계정 조회(Step 3)와 링크 생성 경합(Step 4) 두 곳이 같은 응답 · 같은 로그를
 * 내도록 한 곳에 모은다(D-10 · D-23). 로그에는 이메일을 싣지 않는다.
 *
 * @param {string} uid 호출자 uid.
 * @return {SendPasswordResetMailResponse} `{ok: true}`.
 */
function respondNoAccount(uid: string): SendPasswordResetMailResponse {
  logger.info(
    {event: "password_reset_mail_no_account", uid},
    "sendPasswordResetMail skipped",
  );
  return {ok: true};
}

/**
 * 클라이언트 IP 를 rate limit 문서 id 용 해시로 바꾼다.
 *
 * IP 원문을 문서 id 에 남기지 않는다 — salt 없는 SHA-256 앞 32 hex
 * (`lookup_sign_in_methods.ts` `hashClientIp` 와 같은 모양).
 *
 * @param {string} ip 클라이언트 IP.
 * @return {string} 32자 hex 해시.
 */
function hashClientIp(ip: string): string {
  return createHash("sha256").update(ip).digest("hex").slice(0, 32);
}

/**
 * 재설정 메일 rate limit 축 목록을 만든다 (uid · IP 해시 · 이메일 해시).
 *
 * IP 를 못 얻으면 IP 축은 건너뛴다(fail-open — 정당한 요청을 IP 부재만으로
 * 막지 않는다 · `lookupSignInMethods` 와 같은 규칙).
 *
 * @param {{uid: string, ip: (string|undefined), email: string}} caller
 *     호출 정보.
 * @return {Array<RateLimitAxis>} 판정할 축 목록.
 */
function buildRateAxes(caller: {
  uid: string;
  ip: string | undefined;
  email: string;
}): RateLimitAxis[] {
  const axes: RateLimitAxis[] = [
    {
      axis: "uid",
      docId: `${UID_DOC_PREFIX}${caller.uid}`,
      limit: UID_RATE_LIMIT,
      windowSec: UID_RATE_WINDOW_SEC,
    },
  ];
  if (caller.ip) {
    axes.push({
      axis: "ip",
      docId: `${IP_DOC_PREFIX}${hashClientIp(caller.ip)}`,
      limit: IP_RATE_LIMIT,
      windowSec: IP_RATE_WINDOW_SEC,
    });
  }
  axes.push({
    axis: "email",
    docId: `${EMAIL_DOC_PREFIX}${hashEmail(caller.email)}`,
    limit: EMAIL_RATE_LIMIT,
    windowSec: EMAIL_RATE_WINDOW_SEC,
  });
  return axes;
}

/**
 * kit 모드 비밀번호 재설정 메일 callable (Phase 17.5 D-10 · D-11).
 *
 * 호출 조건: App Check 필수 · `request.auth` 필수(익명 허용 — §R7).
 *
 * 흐름:
 *   Step 0: `request.auth` 없음 → `unauthenticated` · `email` 이 문자열이
 *           아니거나 비었거나 320자 초과 → `invalid-argument`.
 *   Step 1: 브랜드 env 미설정(`readMailBrand()` null) →
 *           `email_brand_unset` + `internal` · 결과 페이지 주소 env 미설정
 *           (`readResultPageUrl()` null) → `email_result_page_unset` +
 *           `internal` (rate limit · 계정 조회 전 — D-22 ③ · 비노출 유지).
 *   Step 2: uid 5/60s · IP 해시 30/60s · 이메일 해시 3/600s 를 한
 *           transaction 에서 판정 — 초과 축마다
 *           `password_reset_mail_rate_limited` 알람 + `resource-exhausted`.
 *   Step 3: Admin `getUserByEmail` 계정 조회 (D-23 — rate limit 뒤 · 링크
 *           생성 전) — 계정 없음(`auth/user-not-found`) → 메일 없이
 *           `{ok: true}` + `password_reset_mail_no_account` ·
 *           `auth/invalid-email` → `invalid-argument` · 그 밖 →
 *           `password_reset_mail_lookup_failed` + `internal`.
 *   Step 4: Admin 링크 — 계정 없음(조회와 생성 사이 삭제 경합) → 메일 없이
 *           `{ok: true}`(비노출) · `auth/invalid-email` →
 *           `invalid-argument` · 그 밖 → `password_reset_mail_failed` +
 *           `internal`.
 *   Step 5: `toResultPageLink`(결과 페이지 + `lang`) →
 *           `renderMail("resetPassword")` → `mail/` add → `{ok: true}`.
 *           실패(필수 쿼리 없는 링크 포함)는 `internal`.
 *
 * **PII 금지:** logger payload 는 `{event, uid, axis, count, code, locale}`
 * 뿐이다. 이메일 · 링크 · oobCode · IP 원문 · 결과 페이지 주소 ·
 * `err.message` 를 싣지 않는다.
 *
 * @param {{auth?: {uid: string}, rawRequest?: {ip?: string}, data:
 *     SendPasswordResetMailRequest}} request onCall request.
 * @return {Promise<SendPasswordResetMailResponse>} `{ok: true}` — 계정 유무와
 *     무관하게 같은 모양.
 */
export const sendPasswordResetMail = onCall<SendPasswordResetMailRequest>(
  {enforceAppCheck: true},
  async (request): Promise<SendPasswordResetMailResponse> => {
    // Step 0: 호출자 · 입력 검증 (익명 허용).
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "errorUnauthenticated");
    }
    const uid = request.auth.uid;
    const email = requireStringArg(
      request.data?.email,
      MAX_EMAIL_LENGTH,
    ).trim();
    if (email === "") {
      throw new HttpsError("invalid-argument", "errorInvalidArgument");
    }
    const locale = resolveMailLocale(request.data?.locale);

    // Step 1: 서버 브랜드 값 — 앱 이름이 없으면 메일 헤더 · 제목이 깨진다.
    const brand = readMailBrand();
    if (brand === null) {
      logger.error(
        {event: "email_brand_unset"},
        "EMAIL_APP_NAME is not configured",
      );
      throw new HttpsError("internal", "errorUnknown");
    }
    // 결과 페이지 주소 — 없으면 기본 핸들러 링크를 보내지 않고 멈춘다.
    // 계정 조회 전이라 있는 주소 · 없는 주소 응답이 같다(D-10).
    const resultPageUrl = readResultPageUrl();
    if (resultPageUrl === null) {
      logger.error(
        {event: "email_result_page_unset"},
        "EMAIL_RESULT_PAGE_URL is not configured",
      );
      throw new HttpsError("internal", "errorUnknown");
    }

    // Step 2: 남용 · enumeration 방어 — 계정 조회 · 링크 생성 전에 판정한다.
    const db = getFirestore();
    let exceeded: ExceededRateAxis[];
    try {
      exceeded = await consumeRateLimitAxes(
        db,
        buildRateAxes({uid, ip: request.rawRequest?.ip, email}),
      );
    } catch (err: unknown) {
      logger.warn(
        {
          event: "password_reset_mail_rate_limit_failed",
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
            event: "password_reset_mail_rate_limited",
            uid,
            axis: hit.axis,
            count: hit.count,
          },
          "sendPasswordResetMail rate limit exceeded",
        );
      }
      throw new HttpsError("resource-exhausted", "errorTooManyRequests");
    }

    // Step 3: 계정 조회 — 열거 보호가 켜진 프로젝트는 없는 주소의 링크
    // 생성이 계정 없음 코드가 아니라 auth/internal-error 로 실패하므로 링크
    // 생성 전에 유무를 판정한다(D-23). 레코드는 쓰지 않는다(유무만).
    try {
      await getAuth().getUserByEmail(email);
    } catch (err: unknown) {
      const code = fingerprintError(err);
      if (NO_ACCOUNT_CODES.includes(code)) {
        // 응답 모양 · 코드 · 로그만 있는 주소와 같다 — 소요 시간은 맞추지 않는다
        // (비노출 범위 · 근거는 파일 머리 「가입 여부 비노출」).
        return respondNoAccount(uid);
      }
      if (code === "auth/invalid-email") {
        throw new HttpsError("invalid-argument", "errorInvalidArgument");
      }
      // err.message 에는 이메일이 들어 있다 — code 만 싣는다.
      logger.warn(
        {event: "password_reset_mail_lookup_failed", uid, code},
        "getUserByEmail threw",
      );
      throw new HttpsError("internal", "errorUnknown");
    }

    // Step 4: Admin 링크 — 계정 없음(조회와 생성 사이 삭제 경합)은 성공과
    // 같은 응답(D-10 · D-23).
    let link: string;
    try {
      // actionCodeSettings 없음 — continueUrl 을 싣지 않는다(D-17).
      link = await getAuth().generatePasswordResetLink(email);
    } catch (err: unknown) {
      const code = fingerprintError(err);
      if (NO_ACCOUNT_CODES.includes(code)) {
        return respondNoAccount(uid);
      }
      if (code === "auth/invalid-email") {
        throw new HttpsError("invalid-argument", "errorInvalidArgument");
      }
      logger.warn(
        {event: "password_reset_mail_failed", uid, code},
        "generatePasswordResetLink threw",
      );
      throw new HttpsError("internal", "errorUnknown");
    }

    // Step 5: 결과 페이지 재작성(+ lang) → 렌더 → mail/ 큐 기록.
    try {
      const message = renderMail("resetPassword", {
        locale,
        email,
        link: toResultPageLink(link, resultPageUrl, locale),
        brand,
      });
      await db.collection("mail").add({to: [email], message});
    } catch (err: unknown) {
      logger.warn(
        {event: "password_reset_mail_failed", uid, code: fingerprintError(err)},
        "sendPasswordResetMail failed",
      );
      throw new HttpsError("internal", "errorUnknown");
    }

    logger.info(
      {event: "password_reset_mail_queued", uid, locale},
      "sendPasswordResetMail queued",
    );
    return {ok: true};
  },
);
