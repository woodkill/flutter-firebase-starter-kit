// Phase 15 code review WR-07 / CR-01 — terms mirror 블록 단일 진실원.
//
// 본 helper 는 4 Custom Token endpoint(kakao · naver · naver web · line)의
// `users/{uid}.termsAccepted` set-merge 와 로깅을 맡는다. 호출 파일은
// `kakao_custom_token.ts` · `line_custom_token.ts` ·
// `naver_profile_to_custom_token.ts`(naver · naver web 공용) 셋이다.
//
// **입력 검증(`parseTermsAcceptanceJson`)은 호출부 책임이다.** 호출부는 모두
// fail-open 이다 — 검증에 실패하면 필드를 무시하고 로그인은 계속한다
// (`terms_acceptance_json.ts` docstring 의 의도된 정책). 호출부는
// `isNewUser` 일 때만(새 `users/{uid}` 문서) 본 helper 를 부른다.
//
// **Schema invariant (Pitfall 4 회피)**: `TermsAcceptanceJson` 5 필드
// (version / service / privacy / marketing / acceptedAt) 는 client 의
// TermsAcceptance Freezed model 5 필드 verbatim mirror
// (lib/features/terms/domain/terms_acceptance.dart). 변경 시 client toJson
// 출력과 본 helper 의 set payload 를 같은 커밋에서 동시 갱신할 것.
import {getFirestore, Timestamp} from "firebase-admin/firestore";
import * as logger from "firebase-functions/logger";

import {TermsAcceptanceJson} from "../shared/terms_acceptance_json";
import {fingerprintError} from "./identity_index";

/**
 * 검증이 끝난 terms snapshot 을 `users/{uid}.termsAccepted` 에 atomic mirror
 * 한다 (WR-07 — 5회 verbatim 복제 제거).
 *
 * `{merge: true}` 는 의무다 — `users/{uid}` 의 다른 필드
 * (`linkedProviders` / `providerLinkedAt` 등) 를 보존해야 한다.
 *
 * **입력 계약**: [snapshot] 은 반드시 `parseTermsAcceptanceJson` 을 통과한
 * 값이어야 한다. 본 helper 는 재검증하지 않는다 — 미검증 값을 넘기면
 * `Timestamp.fromDate(Invalid Date)` throw 또는 계약 외 필드 착지가 발생한다
 * (CR-01 이 정확히 그 경로였다).
 *
 * **PII 정책 (D-08 / D-51 / Pitfall 7)**: logger payload 에는 `uid` 와
 * `version` 만 노출한다. snapshot 본체 / err.message 는 절대 노출하지 않으며
 * 실패 fingerprint 는 `fingerprintError` 로만 만든다.
 *
 * **에러 정책**: 실패 시 [args.failureEvent] 로 logger.error 를 남기고 원본
 * 에러를 **그대로 재던진다**. `HttpsError` 매핑은 호출부 (HTTP 응답 layer)
 * 책임이다 — D-33 layering 경계 보존.
 *
 * @param {{uid: string, snapshot: TermsAcceptanceJson, successEvent: string,
 *     failureEvent: string}} args mirror 인자.
 *     `successEvent` / `failureEvent` 는 기존 provider 별 Cloud Logging
 *     event 이름을 그대로 유지하기 위한 매개변수다 (대시보드/알람 회귀 0).
 * @return {Promise<void>} set merge 완료 시 resolve.
 */
export async function mirrorTermsAccepted(args: {
  uid: string;
  snapshot: TermsAcceptanceJson;
  successEvent: string;
  failureEvent: string;
}): Promise<void> {
  const {uid, snapshot, successEvent, failureEvent} = args;
  try {
    await getFirestore()
      .collection("users")
      .doc(uid)
      .set(
        {
          termsAccepted: {
            version: snapshot.version,
            service: snapshot.service,
            privacy: snapshot.privacy,
            marketing: snapshot.marketing,
            acceptedAt: Timestamp.fromDate(new Date(snapshot.acceptedAt)),
          },
        },
        {merge: true},
      );
  } catch (err: unknown) {
    // PII 금지 — snapshot 본문 / err.message 미노출, code fingerprint 만.
    logger.error(
      {event: failureEvent, uid, code: fingerprintError(err)},
      "terms acceptance mirror set merge threw",
    );
    throw err;
  }

  logger.info(
    {
      event: successEvent,
      uid,
      terms_mirrored: true,
      version: snapshot.version,
    },
    "terms acceptance mirrored",
  );
}
