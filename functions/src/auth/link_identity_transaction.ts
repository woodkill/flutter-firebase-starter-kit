// Phase 16.9 D-01 — Custom Token 신원 연결 transaction 공용 helper.
//
// `link_custom_token_provider.ts` Step 4 (identity_index atomic create +
// users/{uid}.linkedProviders[] update) 를 동작 · 로그 event 이름 불변으로
// 옮겨 왔다. 두 연결 callable 이 공유한다.
// - `linkCustomTokenProvider` — OIDC ID token 을 검증하는 provider (kakao · line)
// - `linkNaverProvider` — Naver access token / authorization code 검증
//
// 「all reads before all writes」 invariant (Pitfall 2) — tx 안 read 는
// `identity_index` 1건뿐이고 write 는 그 뒤에만 한다. `tx.update` ·
// `FieldValue.delete` · 추가 read 를 넣지 않는다 (기존 link Jest 의 FieldValue
// mock 계약 · memory feedback_mock_transaction_constraint).
import {FieldValue} from "firebase-admin/firestore";
import type {Firestore} from "firebase-admin/firestore";
import {HttpsError} from "firebase-functions/https";
import * as logger from "firebase-functions/logger";

import {serverFailure} from "../shared/custom_token_errors";
import {fingerprintError, identityIndexDocId} from "./identity_index";
import type {ProviderId} from "./identity_index";

/** [linkCustomTokenIdentity] 입력. */
export type LinkCustomTokenIdentityArgs = {
  /** 호출자가 `getFirestore()` 로 넘기는 Firestore 인스턴스 (Jest mock 호환). */
  db: Firestore;
  /** 연결을 요청한 Firebase UID (`request.auth.uid` — 검증 완료). */
  callerUid: string;
  /** 연결 대상 provider 슬러그. */
  provider: ProviderId;
  /** 연결 대상 provider 가 검증한 사용자 식별자 (`sub` / Naver `id`). */
  providerUserId: string;
};

/**
 * identity_index 문서를 만들고 users/{uid} 의 연결 목록을 갱신한다.
 *
 * 흐름 (transaction 1회):
 *   1. `identity_index/{provider}:{providerUserId}` read 1건.
 *   2. 다른 uid 가 소유 → `already-exists` (`errorAccountAlreadyLinked`) ·
 *      write 0.
 *   3. 문서가 없을 때만 idx set — 같은 uid 재연결은 최초 `linkedAt` 보존
 *      (WR-10 멱등).
 *   4. users/{uid} 에 `linkedProviders` arrayUnion + `providerLinkedAt` merge
 *      set — 재연결에서도 실행해 부분 상태를 self-heal 한다.
 *
 * 연결은 가입 이벤트가 아니므로 `signUpProviderId` · 프로필 필드는 쓰지
 * 않는다 (Phase 16.7 D-14 · D-18).
 *
 * **PII 금지:** 실패 로그 payload 는 `{event, uid, code}` 만 —
 * `code` 는 `fingerprintError` 결과 (err.message 본문 노출 0).
 *
 * @param {LinkCustomTokenIdentityArgs} args Firestore · caller uid ·
 *     연결 대상 provider · provider 사용자 식별자.
 * @return {Promise<void>} 연결 기록이 커밋되면 resolve.
 * @throws {HttpsError} 타 uid 소유면 `already-exists`, 그 외 transaction
 *     실패는 `internal` (`serverFailure`).
 */
export async function linkCustomTokenIdentity(
  args: LinkCustomTokenIdentityArgs,
): Promise<void> {
  const {db, callerUid, provider, providerUserId} = args;
  const idxRef = db
    .collection("identity_index")
    .doc(identityIndexDocId(provider, providerUserId));
  const userRef = db.collection("users").doc(callerUid);
  try {
    await db.runTransaction(async (tx) => {
      // (all reads first — invariant 의무, Pitfall 2 회피)
      //
      // WR-10 (Phase 15 리뷰): 이전에는
      // `const [idxSnap] = await Promise.all([tx.get(idxRef),
      // tx.get(userRef)])` 로 **결과를 버리는 read** 가 있었다.
      // `tx.set(userRef, ..., {merge:true})` 는 선행 read 를 요구하지
      // 않으므로 그 read 는 불필요한 왕복이자 오독 유발 요인이었다.
      const idxSnap = await tx.get(idxRef);

      // WR-10: 같은 uid 로의 재연동은 **멱등** 이어야 한다. 이전 구현은
      // `idxSnap.exists` 만 보고 무조건 already-exists 를 던져서, 이미
      // 연동된 provider 를 사용자가 다시 누르거나 (client 10초 타임아웃
      // 이후) 재시도하면 자기 계정에 대해 "이미 다른 계정에 연동됨"
      // 계열 오류를 받았다 (client 의 AccountAlreadyLinked 매핑).
      const owner = idxSnap.exists ?
        (idxSnap.data() as {firebaseUid?: string} | undefined)?.firebaseUid :
        undefined;
      if (idxSnap.exists && owner !== callerUid) {
        throw new HttpsError("already-exists", "errorAccountAlreadyLinked");
      }

      // (writes second — read 종료 후만)
      // 재연동이면 idx 문서를 다시 쓰지 않는다 — 최초 linkedAt 보존.
      if (!idxSnap.exists) {
        tx.set(idxRef, {
          firebaseUid: callerUid,
          provider,
          providerUserId,
          linkedAt: FieldValue.serverTimestamp(),
          lastSeenAt: FieldValue.serverTimestamp(),
        });
      }
      // linkedProviders 는 arrayUnion 이라 멱등하다. 재연동 경로에서도
      // 실행해 "idx 문서는 있는데 users/{uid} 에는 반영이 빠진" 부분
      // 상태를 self-heal 한다.
      tx.set(
        userRef,
        {
          linkedProviders: FieldValue.arrayUnion({
            providerId: provider,
            providerUserId,
          }),
          providerLinkedAt: {
            [provider]: FieldValue.serverTimestamp(),
          },
        },
        {merge: true},
      );
    });
  } catch (err: unknown) {
    // HttpsError 는 그대로 propagate (already-exists 등 known HttpsError).
    if (err instanceof HttpsError) {
      throw err;
    }
    const errCode = fingerprintError(err);
    logger.error(
      {event: "link_transaction_failed", uid: callerUid, code: errCode},
      "runTransaction threw",
    );
    throw serverFailure();
  }
}
