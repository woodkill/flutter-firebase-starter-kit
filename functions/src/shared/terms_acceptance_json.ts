// Phase 16 — see ROADMAP.md (Plan 16-03 Task 3.2).
//
// TermsAcceptance snapshot JSON — client Freezed model 5 필드 verbatim mirror
// (lib/features/terms/domain/terms_acceptance.dart).
//
// **Schema invariant (Pitfall 4 회피)**: 5 필드 (version: int / service: bool /
// privacy: bool / marketing: bool / acceptedAt: ISO 8601 string) 는 client 의
// TermsAcceptance Freezed model 5 필드 verbatim mirror. 변경 시 client toJson
// 출력과 server set payload 양쪽 동시 갱신 의무 (Plan 16-02 mirror_terms_
// acceptance.ts + Plan 16-03 의 4 Custom Token endpoint 추가 import).
//
// 4 Custom Token endpoint (kakao/naver/line/yahoojp) 의 callable arg
// `termsAcceptanceSnapshot?: TermsAcceptanceJson` add-only 확장의 shared type.

/**
 * TermsAcceptance snapshot JSON — client Freezed model 5 필드 verbatim mirror
 * (lib/features/terms/domain/terms_acceptance.dart). RESEARCH §
 * Incompatibility #1 의 정정 채택 schema.
 *
 * **5 필드:**
 * - `version`: 약관 버전 (TermsNotifier.currentVersion 매칭) — int.
 * - `service`: 이용약관 동의 (필수) — bool.
 * - `privacy`: 개인정보처리방침 동의 (필수) — bool.
 * - `marketing`: 마케팅 정보 수신 동의 (선택) — bool.
 * - `acceptedAt`: 사용자 동의 시각 — ISO 8601 string (client toJson 직렬화
 *   후 server-side Timestamp.fromDate 변환).
 *
 * **PII 정책 (D-13/D-14 carry-forward)**: 5 필드 모두 PII 비대상 (sign-in
 * identifier 아님, Firestore 에 이미 mirror 되는 동일 데이터). 단 logger
 * payload 에는 version 만 노출 가능, 본체 미노출.
 */
export type TermsAcceptanceJson = {
  /** 약관 버전 (TermsNotifier.currentVersion 매칭). */
  version: number;
  /** 이용약관 동의 (필수). */
  service: boolean;
  /** 개인정보처리방침 동의 (필수). */
  privacy: boolean;
  /** 마케팅 정보 수신 동의 (선택). */
  marketing: boolean;
  /** 사용자 동의 시각 — ISO 8601 (client toJson 직렬화 후 Timestamp.fromDate). */
  acceptedAt: string;
};
