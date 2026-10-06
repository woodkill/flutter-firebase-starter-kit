// Phase 16.8 SOCL-15 — Custom Token 신원 해제 callable (link 의 역연산).
//
// `identity_index` 는 firestore.rules 로 클라이언트 read/write 가 전면 차단되어
// 있어 Custom Token(CT) provider 의 연결 해제는 서버 경로가 필수다. 본
// callable 은 OIDC 연결 공용 팩토리 `link_oidc_provider.ts` 의 골격(App
// Check · 인자 가드 · 익명 거부 · catch 관례 · PII-0 로깅)을 미러하되, OIDC
// 검증 · secret 이 없는 더 짧은 함수다.
//
// 결정 (16.8-CONTEXT):
// - D-01: 가입 수단 필드는 읽지도 쓰지도 않는다 (표시 전용 — 서버 판정 제외).
// - D-03: 남은 자격증명 0 이면 거부 — 판정 근거는 Admin `providerData` ∪
//   tx 안에서 다시 읽은 `identity_index` 뿐이다. 클라이언트가 위조할 수 있는
//   `linkedProviders` 배열은 정리 대상일 뿐 판정에 쓰지 않는다.
// - D-04 · D-19: provider 슬러그는 `CUSTOM_TOKEN_PROVIDER_PRIORITY` 목록
//   참조로만 검증한다 — provider 리터럴 비교 · exhaustive switch 0. provider
//   를 추가해도 이 파일은 편집하지 않는다.
// - D-06: 재인증을 요구하지 않는다 (Step 1 주석 참조).
// - D-08: Firestore 에서 지우는 것은 3항목뿐 — 대상 `identity_index` 문서 ·
//   `linkedProviders` 의 해당 provider 항목 · `providerLinkedAt.<provider>` 키.
//
// **IN-04**: 아래 `HttpsError` 의 message 는 ARB 키가 아니라 taxonomy 토큰
// (`errorUnlinkLastCredential` · `errorProviderNotLinked` ·
// `errorAnonymousUnlinkNotAllowed`)이다. 클라이언트는 `code` +
// `details.reason` 으로만 분기한다 — `shared/custom_token_errors.ts` 헤더 참조.
import {getAuth} from "firebase-admin/auth";
import {getFirestore, FieldValue} from "firebase-admin/firestore";
import type {
  DocumentReference,
  DocumentSnapshot,
} from "firebase-admin/firestore";
import {onCall, HttpsError} from "firebase-functions/https";
import * as logger from "firebase-functions/logger";

import {invalidArgument, serverFailure} from "../shared/custom_token_errors";
import {isAnonymousCaller} from "../shared/caller_auth";
import {
  MAX_NONCE_ARG_LENGTH,
  requireStringArg,
} from "../shared/require_string_arg";
import {
  CUSTOM_TOKEN_PROVIDER_PRIORITY,
  fingerprintError,
} from "./identity_index";

type UnlinkCustomTokenProviderRequest = {
  /** 해제할 Custom Token provider 슬러그 — 목록 밖이면 invalid-argument. */
  provider?: unknown;
};

type UnlinkCustomTokenProviderResponse = {
  ok: true;
};

/** tx 결과 — 성공 로그의 계수 필드. */
type UnlinkCounts = {
  removedIdentityCount: number;
  removedLinkedEntryCount: number;
};

/**
 * 알 수 없는 Firestore 값에서 문자열 필드를 읽는다 (`any` 없이 좁힘).
 *
 * @param {unknown} data 문서 data (`snap.data()`).
 * @param {string} key 필드 이름.
 * @return {string | undefined} 문자열이면 그 값, 아니면 undefined.
 */
function readStringField(data: unknown, key: string): string | undefined {
  if (typeof data !== "object" || data === null) return undefined;
  const value = (data as Record<string, unknown>)[key];
  return typeof value === "string" ? value : undefined;
}

/**
 * `users/{uid}.linkedProviders` 배열을 원소 그대로 읽는다.
 *
 * 문서가 없거나 필드가 배열이 아니면 빈 배열이다. 원소 모양을 여기서 걸러
 * 버리지 않는다 — 해제 대상이 아닌 원소는 모양이 낯설어도 그대로 다시
 * 기록해야 D-08(지우는 것은 해당 provider 항목뿐)이 지켜진다.
 *
 * @param {DocumentSnapshot} snap tx 안에서 읽은 users 문서.
 * @return {unknown[]} 배열 원소 (타입 미확정).
 */
function readLinkedProviders(snap: DocumentSnapshot): unknown[] {
  if (!snap.exists) return [];
  const data: unknown = snap.data();
  if (typeof data !== "object" || data === null) return [];
  const linked = (data as Record<string, unknown>).linkedProviders;
  return Array.isArray(linked) ? linked : [];
}

/**
 * 배열 원소가 주어진 provider 의 연결 항목인지 판정한다.
 *
 * 항목 모양은 link callable 이 쓰는 `{providerId, providerUserId}` 다.
 * `providerId` 만 비교하므로 같은 provider 의 중복 · stale 항목도 함께
 * 정리된다 (provider 중립 — 리터럴 비교 0).
 *
 * @param {unknown} entry `linkedProviders` 원소.
 * @param {string} provider 해제 대상 provider 슬러그.
 * @return {boolean} 해제 대상 항목이면 true.
 */
function isEntryOf(entry: unknown, provider: string): boolean {
  return readStringField(entry, "providerId") === provider;
}

/**
 * Custom Token provider 연결 해제 callable (Phase 16.8 SOCL-15).
 *
 * 호출 조건: App Check 필수 · 로그인 필수 · 익명 caller 거부. 재인증은
 * 요구하지 않는다 (D-06). uid 는 `request.auth.uid` 만 쓰며 문서 id · uid 를
 * 입력으로 받지 않는다 (IDOR 차단).
 *
 * 흐름:
 *   Step 0: `request.auth` 검증.
 *   Step 1: 익명 caller 거부 (`failed-precondition` · reason
 *           `anonymous_caller`).
 *   Step 2: provider 슬러그 검증 — 목록 참조 (D-04 · D-19).
 *   Step 3: (tx 밖) Admin `getUser(uid)` + `identity_index` where 조회로
 *           후보 문서를 모은다 — collection query 는 tx 안 금지.
 *   Step 4: (tx) 후보 idx 문서 전부 + users 문서를 **먼저 모두 읽고**
 *           (소유 재확인 · 남은 자격증명 재계수 — CT↔CT 동시 해제 경합 차단)
 *           검증 뒤 write 한다 — 「all reads before all writes」.
 *           - 남은 자격증명 0 → `failed-precondition` · reason
 *             `last_credential` (D-03).
 *           - 소유 idx 0 이고 배열 항목 0 → `not-found`.
 *           - idx 는 없고 배열 항목만 남은 부분 상태 → 항목 정리 후 성공
 *             (self-heal).
 *   Step 5: 구조화 로그 + `{ok: true}`.
 *
 * **PII 금지 (D-51 · T-16-NEW-07)**: logger payload 는
 * `{event, uid, provider, 계수}` 또는 `{event, uid, code}` 뿐이다. provider
 * sub · email · 문서 id 는 로그 · HttpsError message/details 어디에도 넣지
 * 않는다. 실패는 `fingerprintError` 코드만 남긴다.
 *
 * @param {{data: UnlinkCustomTokenProviderRequest, auth?: {uid: string}}}
 *     request onCall request — auth 는 Step 0 에서 검증.
 * @return {Promise<UnlinkCustomTokenProviderResponse>} 성공 시 `{ok: true}`.
 */
export const unlinkCustomTokenProvider =
  onCall<UnlinkCustomTokenProviderRequest>(
    {enforceAppCheck: true},
    async (request): Promise<UnlinkCustomTokenProviderResponse> => {
      // Step 0: auth.
      if (!request.auth) {
        throw new HttpsError("unauthenticated", "errorUnauthenticated");
      }
      const uid = request.auth.uid;

      // Step 1: 익명 caller 거부.
      //
      // D-06 — 재인증 신선도 helper 를 쓰지 않는다 (link · delete 와 의도적
      // 차이). 해제는 계정에 새 접근 권한을 주지 않고, 가입 수단이 그대로
      // 남으며, 사용자가 언제든 다시 연결할 수 있다. 확인 다이얼로그가
      // 오조작 방어를 맡는다. 따라서 `idToken` 인자도 받지 않는다.
      if (isAnonymousCaller(request.auth)) {
        throw new HttpsError(
          "failed-precondition",
          "errorAnonymousUnlinkNotAllowed",
          {reason: "anonymous_caller"},
        );
      }

      // Step 2: provider 슬러그 — 목록 참조로만 좁힌다 (D-04 · D-19).
      const raw = requireStringArg(
        request.data?.provider,
        MAX_NONCE_ARG_LENGTH,
      );
      const provider = CUSTOM_TOKEN_PROVIDER_PRIORITY.find((p) => p === raw);
      if (!provider) {
        throw invalidArgument();
      }

      // Step 3: (tx 밖) 후보 수집 — collection query 는 tx 안 금지.
      const db = getFirestore();
      const userRef = db.collection("users").doc(uid);
      let nativeIds: string[];
      let candidateRefs: DocumentReference[];
      try {
        const [userRecord, idxSnaps] = await Promise.all([
          getAuth().getUser(uid),
          db.collection("identity_index").where("firebaseUid", "==", uid).get(),
        ]);
        nativeIds = userRecord.providerData
          .map((p) => p.providerId)
          .filter((id) => id !== "firebase");
        candidateRefs = idxSnaps.docs.map((d) => d.ref);
      } catch (err: unknown) {
        logger.error(
          {event: "unlink_precheck_failed", uid, code: fingerprintError(err)},
          "getUser or identity_index query threw",
        );
        throw serverFailure();
      }

      // Step 4: (tx) reads → 검증 → writes.
      let counts: UnlinkCounts;
      try {
        counts = await db.runTransaction(async (tx): Promise<UnlinkCounts> => {
          // (all reads first — 순서 강제 mock 이 회귀를 잡는다)
          const idxDocs = await Promise.all(
            candidateRefs.map((ref) => tx.get(ref)),
          );
          const userSnap = await tx.get(userRef);
          // (reads 끝)

          // 소유 재확인 — tx 밖 조회 뒤 소유자가 바뀐 문서는 건드리지 않는다.
          const ownedByMe = idxDocs.filter(
            (s) => s.exists && readStringField(s.data(), "firebaseUid") === uid,
          );
          const targets = ownedByMe.filter(
            (s) => readStringField(s.data(), "provider") === provider,
          );
          const remainingOthers = ownedByMe
            .map((s) => readStringField(s.data(), "provider"))
            .filter((p): p is string => p !== undefined && p !== provider);
          const remaining = new Set<string>([...nativeIds, ...remainingOthers]);
          if (remaining.size === 0) {
            throw new HttpsError(
              "failed-precondition",
              "errorUnlinkLastCredential",
              {reason: "last_credential"},
            );
          }

          const linked = readLinkedProviders(userSnap);
          const kept = linked.filter((e) => !isEntryOf(e, provider));
          const removedLinkedEntryCount = linked.length - kept.length;
          if (targets.length === 0 && removedLinkedEntryCount === 0) {
            throw new HttpsError("not-found", "errorProviderNotLinked");
          }

          // (writes second — reads 종료 후만)
          for (const s of targets) {
            tx.delete(s.ref);
          }
          // idx 를 지웠거나 항목이 있었으면 users 문서도 정리한다.
          // providerLinkedAt 은 dot 키 1개만 지운다 — 맵 통째 set 은 다른
          // provider 의 timestamp 를 지운다 (T-16.8-12).
          if (userSnap.exists) {
            tx.update(userRef, {
              linkedProviders: kept,
              [`providerLinkedAt.${provider}`]: FieldValue.delete(),
            });
          }
          return {
            removedIdentityCount: targets.length,
            removedLinkedEntryCount,
          };
        });
      } catch (err: unknown) {
        // HttpsError(last_credential · not-found)는 그대로 propagate.
        if (err instanceof HttpsError) {
          throw err;
        }
        logger.error(
          {
            event: "unlink_transaction_failed",
            uid,
            code: fingerprintError(err),
          },
          "runTransaction threw",
        );
        throw serverFailure();
      }

      // Step 5: 구조화 로그 + 반환 — PII 0.
      logger.info(
        {
          event: "unlink_custom_token_provider_succeeded",
          uid,
          provider,
          removedIdentityCount: counts.removedIdentityCount,
          removedLinkedEntryCount: counts.removedLinkedEntryCount,
        },
        "unlinked",
      );
      return {ok: true};
    },
  );
