// 로그 `code` 필드용 에러 fingerprint helper (WR-07 · Phase 20 리뷰 WR-06).
//
// `auth/identity_index.ts` 에서 옮겨 왔다 — `shared/` 의 helper(재로그인 토큰
// 발급 `relogin_token.ts`)도 같은 fingerprint 를 써야 하는데, `shared/` 는
// `../auth/` 를 import 하지 않는다 (shared → auth 역방향 의존 금지 — 16.9
// plan 01 결정 · `auth/identity_ownership.ts` 머리 주석). 기존 importer 는
// `auth/identity_index.ts` 의 re-export 로 그대로 쓴다.

/**
 * unknown 에러를 logger.code 필드용 fingerprint 문자열로 변환 (WR-07).
 *
 * 비-Error throw (Symbol / null / undefined / primitive) 도 명시 fingerprint
 * 부여하여 firebase-admin 비정상 throw 경로를 ops triage 에서 분간 가능하게
 * 한다. `err as {code?: string}` 식 unchecked assertion 패턴을 본 helper 로
 * 일원화 — cloud-functions-typescript.md "as 타입 단언 최소화" / "any 사용
 * 금지" 규칙 정합.
 *
 * **PII 정책 (D-51 / Pitfall 7)**: 본 함수는 fingerprint *문자열* 만 반환
 * 하며 err.message / payload / claim 등 본문은 절대 노출하지 않는다.
 *
 * **숫자 code (Phase 17 리뷰 IN-02)**: `@google-cloud/storage` 의 `ApiError.code`
 * 는 HTTP 상태 숫자(404 · 503 …)이고, Firestore Admin(google-gax
 * `GoogleError.code`)은 gRPC status 숫자다. 이전에는 문자열 code 만 써서 두
 * 경우 모두 `"Error"`/`"ApiError"` 로 뭉개졌다 — 이제 숫자를 문자열로 남겨
 * ops 가 「영구(404) vs 일시(503)」 를 가를 수 있다.
 *
 * @param {unknown} err catch (err: unknown) 의 err.
 * @return {string} logger.code 필드용 short fingerprint
 *     ('auth/user-not-found' / '503' / 'TypeError' / 'string-thrown' /
 *      'null-thrown' / 'non-error-thrown' / 'unknown' 등).
 */
export function fingerprintError(err: unknown): string {
  if (err instanceof Error) {
    // firebase-admin / firebase-functions Error 는 code 프로퍼티가 stable
    // public API. instanceof Error 가드 통과 후 code 안전 접근.
    const code = (err as Error & {code?: unknown}).code;
    if (typeof code === "string" && code.length > 0) return code;
    if (typeof code === "number" && Number.isFinite(code)) return String(code);
    return err.name;
  }
  if (typeof err === "string") return "string-thrown";
  if (err === null) return "null-thrown";
  if (err === undefined) return "undefined-thrown";
  return "non-error-thrown";
}
