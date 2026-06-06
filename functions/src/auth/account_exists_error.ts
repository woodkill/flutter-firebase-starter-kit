import {HttpsError} from "firebase-functions/https";

import {ProviderId} from "./identity_index";

/**
 * Custom Token collision (`email_in_use` / `anonymous_existing_collision`) 시
 * client 로 던질 표준 `already-exists` HttpsError 를 생성한다 (DRY 공유 helper).
 *
 * 4 Custom Token endpoint (kakao / naver / line / yahoojp) 의 두 collision
 * case throw 를 본 helper 한 곳으로 통일 — message / code 표기 drift 방지 +
 * `existingProvider` slug 를 `details` 에 일관 전달.
 *
 * **D-33 layering 경계**: `resolveIdentity` 가 위치한 `identity_index.ts` 는
 * 의도적으로 `firebase-functions/https` 를 import 하지 않는 도메인 layer
 * (identity_index.ts:425-427 주석 참고). 본 helper 는 HTTP 응답 layer 책임
 * (`HttpsError` 생성) 이므로 identity_index.ts 가 아니라 별도 파일에 둔다.
 *
 * **PII slug-only 정책 (D-51 / T-16-13-01)**: `details` 에는 `existingProvider`
 * slug ('google' / 'kakao' / 'unknown' 등) *한 값* 만 담는다. email / uid /
 * displayName / IdP token 본문은 절대 포함하지 않는다. `existingProvider` 가
 * `undefined` (resolveIdentity 가 미설정) 인 경우 `{existingProvider: undefined}`
 * 가 직렬화되어 client `_mapFunctionsException` 의 `tryParse(null)` → null →
 * R2 일반 배너 fallback 으로 graceful 처리된다 (회귀 안전).
 *
 * @param {(ProviderId | "unknown" | undefined)} existingProvider 충돌한 기존
 *     계정의 provider slug. `resolveIdentity` 의 `IdentityResolution.
 *     existingProvider` 를 그대로 전달. 미설정 시 `undefined`.
 * @return {HttpsError} code='already-exists',
 *     message='errorAccountExistsWithDifferentCredential',
 *     details={existingProvider} 의 HttpsError.
 */
export function buildAccountExistsError(
  existingProvider: ProviderId | "unknown" | undefined,
): HttpsError {
  return new HttpsError(
    "already-exists",
    "errorAccountExistsWithDifferentCredential",
    {existingProvider},
  );
}
