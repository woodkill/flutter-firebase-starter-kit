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

/**
 * 신뢰할 수 없는 callable 입력을 [TermsAcceptanceJson] 으로 좁힌다 (WR-02).
 *
 * `TermsAcceptanceJson` 은 **컴파일타임 타입일 뿐**이고 callable arg 는 임의
 * JSON 이다. 16-14 로 이 경로가 실제 트래픽을 받기 시작했으므로 mirror 직전에
 * 런타임 검증이 필요하다. 미검증 시 다음이 가능했다.
 *
 * - `service: "yes"` / `version: 999` 같은 임의 값이 그대로
 *   `users/{uid}.termsAccepted` 에 착지 (Firestore schema 오염).
 * - `version` 위조로 client 가 `TermsNotifier._loadFromFirestore` 의
 *   `restored.version >= currentVersion` 재동의 강제 로직을 스스로 무력화
 *   (약관 개정 후 재동의 회피).
 * - `acceptedAt` 이 파싱 불가 문자열이면 `Timestamp.fromDate(Invalid Date)`
 *   가 throw → `HttpsError('internal')` 로 **로그인 전체가 실패** (payload
 *   형태 하나로 자기 계정 로그인 영구 차단).
 *
 * **fail-open 정책 (의도적):** 검증 실패 시 `null` 을 반환해 호출자가 필드를
 * **무시**하고 로그인은 계속하게 한다. 약관 mirror 는 보조 경로이며 (client
 * 측 `mirrorToFirestore` 가 별도 보장), 잘못된 payload 로 로그인을 막는 것이
 * 사용자 피해가 더 크다. 같은 파일의 `idToken` / `nonce` 검증과 달리 이 값은
 * 인증 결정에 쓰이지 않는다.
 *
 * @param {unknown} value callable arg 의 `termsAcceptanceSnapshot` 원본.
 * @return {TermsAcceptanceJson | null} 5 필드가 모두 계약 타입을 만족하면
 *   좁혀진 값, 하나라도 어긋나면 `null`.
 */
export function parseTermsAcceptanceJson(
  value: unknown,
): TermsAcceptanceJson | null {
  if (typeof value !== "object" || value === null) return null;
  const o = value as Record<string, unknown>;
  const {version, service, privacy, marketing, acceptedAt} = o;
  if (typeof version !== "number" || !Number.isInteger(version)) return null;
  if (typeof service !== "boolean") return null;
  if (typeof privacy !== "boolean") return null;
  if (typeof marketing !== "boolean") return null;
  if (typeof acceptedAt !== "string") return null;
  // `new Date(...)` 가 Invalid Date 를 만들면 Timestamp.fromDate 가 throw.
  if (Number.isNaN(new Date(acceptedAt).getTime())) return null;
  // 계약 5 키만 통과시킨다 — 여분 키가 Firestore 에 착지하지 않는다.
  return {version, service, privacy, marketing, acceptedAt};
}
