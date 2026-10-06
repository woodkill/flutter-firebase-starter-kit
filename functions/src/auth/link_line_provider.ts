// Phase 17.3 — see ROADMAP.md.
//
// LINE 계정 연결 callable. provider 제거 = 본 파일 삭제 + `index.ts` export
// 1줄 + `scripts/functions_manifest.json` 1줄 + 배포 정리(`firebase
// functions:delete linkLineProvider`).
import {LINE_CHANNEL_ID} from "../shared/oidc_providers";
import {buildLinkOidcProviderCallable} from "./link_oidc_provider";

/**
 * LINE 신원을 호출자의 기존 계정에 연결하는 callable (Phase 17.3 D-01).
 *
 * LINE OIDC ID token 을 issuer `https://access.line.me` verifier 로 검증한
 * 뒤 공용 연결 transaction 을 탄다(흐름 · PII 금지는
 * `buildLinkOidcProviderCallable` 참조). secret 은 `LINE_CHANNEL_ID` 하나만
 * binding 한다(`LINE_CHANNEL_SECRET` 은 `disconnectLineProvider` 전용) — LINE
 * 을 끈 프로젝트는 이 함수를 배포하지 않는다.
 */
export const linkLineProvider = buildLinkOidcProviderCallable(
  "line",
  [LINE_CHANNEL_ID],
);
