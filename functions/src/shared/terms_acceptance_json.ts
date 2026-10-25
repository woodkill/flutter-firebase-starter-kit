// Phase 16 — see ROADMAP.md (Plan 16-03 Task 3.2).
//
// TermsAcceptance snapshot JSON — client Freezed model 5 필드 verbatim mirror
// (lib/features/terms/domain/terms_acceptance.dart).
//
// **Schema invariant (Pitfall 4 회피)**: 5 필드 (version: int / service: bool /
// privacy: bool / marketing: bool / acceptedAt: ISO 8601 string) 는 client 의
// TermsAcceptance Freezed model 5 필드 verbatim mirror. 변경 시 client toJson
// 출력과 server set payload 양쪽 동시 갱신 의무 (server set payload =
// `functions/src/auth/mirror_terms.ts` 의 `mirrorTermsAccepted` — 4 Custom
// Token endpoint 가 쓴다).
//
// 3 Custom Token provider (kakao/naver/line) 의 callable arg
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
/**
 * 서버가 신뢰하는 약관 최신 버전 (client `TermsNotifier.currentVersion` mirror).
 *
 * **동시 갱신 의무 (schema invariant)**: 약관 개정 시
 * `lib/features/terms/presentation/terms_notifier.dart` 의
 * `TermsNotifier.currentVersion` 과 **반드시 같은 커밋에서** bump 한다.
 *
 * 현재 값 1 = `TermsNotifier.currentVersion` (terms_notifier.dart:45) 과 일치.
 *
 * **성격: 형식 정규화이지 보안 통제가 아니다 (WR-12, Phase 15 리뷰).**
 * client 는 `TermsNotifier.mirrorToFirestore` (terms_notifier.dart) 로
 * `users/{uid}.termsAccepted` 를 Firestore SDK 로 직접 쓴다. `firestore.rules`
 * 는 이 키를 client write 화이트리스트에 두고 `termsShape` · `termsOk` 로
 * 5 필드 정확 · 타입 · 필수 동의 true · `acceptedAt` 미래 금지 · version
 * 비감소를 검사하지만 version 상한은 두지 않는다. 그래서
 * `{version: 999}` 같은 미래 버전은 client 직접 쓰기로 그대로 들어올 수 있다.
 * 본 상한은 서버 경유 경로(4 Custom Token endpoint 의 새 계정 첫 기록)에
 * 들어오는 snapshot 의 형식만 정규화한다 — **정직한 client 의 실수와 서버
 * 경유 경로의 스키마 오염만** 막고 위조는 막지 못한다.
 * **후속 phase 가 이 상수를 위조 방어라고 믿고 설계하지 말 것.**
 */
export const SERVER_TERMS_CURRENT_VERSION = 1;

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
 * - `version` 이 서버가 아는 최신 버전을 넘는 값으로 들어오는 것을
 *   `SERVER_TERMS_CURRENT_VERSION` 상한으로 차단 (형식 정규화). **단, 이것은
 *   위조 방어가 아니다** — client 는 Firestore SDK 로 같은 필드를 직접 쓸 수
 *   있다 (WR-12, 해당 상수 docstring 참조).
 * - 필수 동의 `service` / `privacy` 가 `false` 인 채로 `termsAccepted` 가
 *   mirror 되어 동의 기록 무결성이 깨짐 — `!== true` 로 차단.
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
  // 서버가 아는 최신 버전을 넘는 값은 신뢰하지 않는다 (WR-02 형식 정규화).
  // WR-12: 이 검사는 서버 경유 경로의 스키마 오염만 막는다. client 가
  // Firestore SDK 로 같은 필드를 직접 쓰는 경로는 firestore.rules 책임이다
  // (SERVER_TERMS_CURRENT_VERSION docstring 참조).
  if (version < 1 || version > SERVER_TERMS_CURRENT_VERSION) return null;
  if (typeof service !== "boolean") return null;
  if (typeof privacy !== "boolean") return null;
  if (typeof marketing !== "boolean") return null;
  // 필수 동의 무결성 (WR-02) — service/privacy 는 약관 플로우상 true 로만
  // 성립한다. false 인 채 `termsAccepted` 로 mirror 되면 "필수 동의 없이 동의
  // 기록 존재" 라는 모순 상태가 남는다 (동의 기록 무결성).
  if (service !== true || privacy !== true) return null;
  if (typeof acceptedAt !== "string") return null;
  // `new Date(...)` 가 Invalid Date 를 만들면 Timestamp.fromDate 가 throw.
  if (Number.isNaN(new Date(acceptedAt).getTime())) return null;
  // 계약 5 키만 통과시킨다 — 여분 키가 Firestore 에 착지하지 않는다.
  return {version, service, privacy, marketing, acceptedAt};
}
