// Phase 16.10 D-08 — Custom Token 신원 소유 대조 helper.
//
// 재로그인으로 얻은 provider 신원(sub)이 caller 계정에 연결된 신원인지 서버가
// `identity_index` 원장으로 확인한다. 끊기 callable 이 다른 계정의 provider
// 연결을 끊지 않게 하는 방어선이다 (IDOR 차단 · D-08).
//
// `shared/` 가 아니라 `auth/` 에 두는 이유: `identity_index.ts`
// (`identityIndexDocId` · `fingerprintError`)를 import 하므로, shared → auth
// 역방향 의존을 만들지 않는다 (16.9 plan 01 결정과 같은 원칙).
//
// **PII 금지 (C-04 · D-51):** providerUserId · 문서 id 는 로그 · HttpsError
// details 에 싣지 않는다. 로그 payload 는 `{event, uid, provider}` 또는
// `{event, provider, code}` 뿐이다.
import type {Firestore} from "firebase-admin/firestore";
import * as logger from "firebase-functions/logger";

import {
  callerIdentityMismatch,
  serverFailure,
} from "../shared/custom_token_errors";
import {fingerprintError, identityIndexDocId} from "./identity_index";

/**
 * 알 수 없는 Firestore 값에서 문자열 필드를 읽는다 (`any` 없이 좁힘).
 *
 * 16.8 `unlink_custom_token_provider.ts` 의 private 함수와 같은 본문이다 —
 * 그 파일을 byte 불변으로 두기 위해 이동 대신 사본을 export 한다.
 *
 * @param {unknown} data 문서 data (`snap.data()`).
 * @param {string} key 필드 이름.
 * @return {string | undefined} 문자열이면 그 값, 아니면 undefined.
 */
export function readStringField(
  data: unknown,
  key: string,
): string | undefined {
  if (typeof data !== "object" || data === null) return undefined;
  const value = (data as Record<string, unknown>)[key];
  return typeof value === "string" ? value : undefined;
}

/** [assertIdentityOwnedByCaller] 인자. */
type AssertIdentityOwnedByCallerArgs = {
  /** Firestore 인스턴스 (호출자가 `getFirestore()` 로 넘긴다). */
  db: Firestore;
  /** provider 슬러그 (예: `"kakao"`). */
  provider: string;
  /** provider 가 발급한 사용자 식별자 — 로그 금지. */
  providerUserId: string;
  /** `request.auth.uid`. */
  callerUid: string;
};

/**
 * provider 신원이 caller 계정 소유인지 `identity_index` 로 대조한다
 * (Phase 16.10 D-08).
 *
 * `identity_index/{provider}:{providerUserId}` 문서를 1회 읽는다 (tx 0 ·
 * write 0). 문서가 없거나 `firebaseUid` 가 caller 와 다르면 거부한다 —
 * 부재와 타인 소유를 같은 거부로 묶어 존재 여부를 드러내지 않는다.
 *
 * @param {AssertIdentityOwnedByCallerArgs} args db · provider ·
 *     providerUserId · callerUid.
 * @return {Promise<void>} 소유가 확인되면 resolve.
 * @throws {HttpsError} 읽기 실패 → `internal` ([serverFailure]) · 부재 또는
 *     타인 소유 → `permission-denied` ([callerIdentityMismatch]).
 */
export async function assertIdentityOwnedByCaller(
  args: AssertIdentityOwnedByCallerArgs,
): Promise<void> {
  const {db, provider, providerUserId, callerUid} = args;
  let ownerUid: string | undefined;
  try {
    const snap = await db
      .collection("identity_index")
      .doc(identityIndexDocId(provider, providerUserId))
      .get();
    ownerUid = snap.exists ?
      readStringField(snap.data(), "firebaseUid") :
      undefined;
  } catch (err: unknown) {
    logger.error(
      {
        event: "identity_ownership_read_failed",
        provider,
        code: fingerprintError(err),
      },
      "identity_index read threw",
    );
    throw serverFailure();
  }
  if (ownerUid !== callerUid) {
    logger.warn(
      {event: "identity_ownership_mismatch", uid: callerUid, provider},
      "identity not owned by caller",
    );
    throw callerIdentityMismatch();
  }
}
