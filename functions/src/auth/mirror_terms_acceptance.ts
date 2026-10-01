// Phase 16 — see ROADMAP.md (Plan 16-02 Task 2.2).
//
// Pattern 5 (RESEARCH § Pattern 5 mirrorTermsAcceptanceSnapshot line 696~762):
//   D-13 / D-14 — native (Google/Apple/Facebook/Email) sign-in 후 client 1회
//   호출. admin.firestore() users/{uid}.termsAccepted = snapshot atomic mirror.
//
// 5층 안전망 §7-A/B/C:
// - §7-A: Firestore set merge 공식 함수만 사용 (자체 verifier 0).
// - §7-B: T-16-NEW-07 (PII) / T-16-NEW-08 (schema drift) mitigation.
// - §7-C: jest mock 한계 — 실 단말 backend tier UAT (Plan 16-07 A9)
//   가 ground truth.
//
// **Schema invariant (Pitfall 4 회피)**: TermsAcceptanceJson 의 5 필드
// (version: int / service: bool / privacy: bool / marketing: bool /
// acceptedAt: ISO 8601 string) 는 client 의 TermsAcceptance Freezed model
// (lib/features/terms/domain/terms_acceptance.dart) 5 필드 verbatim mirror.
// 변경 시 client toJson 출력과 server set payload 양쪽 동시 갱신 의무.
//
// **IN-04**: 아래 `HttpsError` 들의 message 는 ARB 키가 아니라 taxonomy
// 토큰이다. client 는 `code` 로만 분기하며 서버 message 를 렌더하지 않는다.
// 계약 전문은 `shared/custom_token_errors.ts` 헤더 참조.
import {onCall, HttpsError} from "firebase-functions/https";

import {
  TermsAcceptanceJson,
  parseTermsAcceptanceJson,
} from "../shared/terms_acceptance_json";
import {mirrorTermsAccepted} from "./mirror_terms";

type MirrorTermsAcceptanceSnapshotRequest = {
  /** TermsAcceptance 5 필드 snapshot. */
  snapshot: TermsAcceptanceJson;
};

type MirrorTermsAcceptanceSnapshotResponse = {
  ok: true;
};

/**
 * Terms acceptance snapshot Firestore mirror callable (Phase 16 D-13/D-14).
 *
 * 킷 클라이언트 호출 0 — 서버 mirror 샘플. 계정 이메일 mirror(D-26)는
 * `mirrorAccountEmail` 이 맡는다(Phase 17).
 *
 * 흐름 (RESEARCH Pattern 5 verbatim):
 *   Step 0: input + request.auth 검증.
 *   Step 1: Firestore users/{uid}.termsAccepted = 5 필드 atomic set merge.
 *           acceptedAt 은 Timestamp.fromDate(new Date(ISO)) 로 변환.
 *
 * **PII 금지 (T-16-NEW-07 mitigation)**: logger payload 는 `{event, uid}` 만.
 * snapshot 본문 / err.message 절대 노출 금지.
 *
 * **입력 검증 정책 — fail-closed (CR-01, Phase 15 리뷰):** `TermsAcceptanceJson`
 * 은 **컴파일타임 타입일 뿐**이고 callable arg 는 임의 JSON 이다. 이전 구현은
 * `!snapshot` falsy 가드만 두어 `{snapshot: {}}` / `{acceptedAt: "not-a-date"}`
 * 로 `HttpsError('internal')` 을 유발하거나, `{version: 999, service: false}`
 * 로 필수 동의 없는 `termsAccepted` 를 기록해 client 의
 * `restored.version >= currentVersion` 재동의 강제 로직을 무력화할 수 있었다.
 * 이제 `parseTermsAcceptanceJson` 으로 5 키를 런타임 검증한다.
 *
 * 4 Custom Token endpoint 는 같은 검증 실패를 **fail-open** (필드 무시 +
 * 로그인 계속) 으로 처리하지만, 본 callable 은 mirror 자체가 유일한 책임이라
 * 조용히 성공을 반환하면 호출자가 기록되지 않은 동의를 기록됐다고 오인한다.
 * 따라서 여기서는 `invalid-argument` 로 거부한다 (정책 분기는 의도적이다).
 *
 * @param {{
 *   data: MirrorTermsAcceptanceSnapshotRequest,
 *   auth?: {uid: string},
 * }} request onCall request.
 * @return {Promise<MirrorTermsAcceptanceSnapshotResponse>} `{ok: true}`.
 */
export const mirrorTermsAcceptanceSnapshot = onCall<
  MirrorTermsAcceptanceSnapshotRequest
>(
  {enforceAppCheck: true},
  async (request): Promise<MirrorTermsAcceptanceSnapshotResponse> => {
    // Step 0: auth + input validation.
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "errorUnauthenticated");
    }
    const callerUid = request.auth.uid;
    // CR-01: 런타임 검증 (fail-closed). 4 Custom Token endpoint 와 동일한
    // `parseTermsAcceptanceJson` 계약을 적용해 5 키만 통과시킨다 — 계약 외
    // 여분 키가 users/{uid}.termsAccepted 에 착지하지 않는다.
    const snapshot = parseTermsAcceptanceJson(request.data?.snapshot);
    if (!snapshot) {
      throw new HttpsError("invalid-argument", "errorInvalidArgument");
    }

    // Step 1: Firestore atomic set merge — 5 필드 verbatim
    // (Pitfall 4 schema drift 회피). WR-07: write + 로깅은 공용 helper 단일
    // 진실원 (이전에는 4 endpoint 의 다섯 번째 verbatim 사본이었다).
    try {
      await mirrorTermsAccepted({
        uid: callerUid,
        snapshot,
        successEvent: "mirror_terms_acceptance_snapshot_done",
        failureEvent: "mirror_terms_acceptance_snapshot_failed",
      });
    } catch {
      // helper 가 이미 PII-safe fingerprint 로 logger.error 를 남겼다.
      throw new HttpsError("internal", "errorUnknown");
    }

    return {ok: true};
  },
);
