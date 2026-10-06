// Phase 17.3 — see ROADMAP.md.
//
// Kakao 계정 연결 callable. provider 제거 = 본 파일 삭제 + `index.ts` export
// 1줄 + `scripts/functions_manifest.json` 1줄 + 배포 정리(`firebase
// functions:delete linkKakaoProvider`).
import {KAKAO_NATIVE_APP_KEY} from "../shared/oidc_providers";
import {buildLinkOidcProviderCallable} from "./link_oidc_provider";

/**
 * Kakao 신원을 호출자의 기존 계정에 연결하는 callable (Phase 17.3 D-01).
 *
 * Kakao OIDC ID token 을 issuer `https://kauth.kakao.com` verifier 로 검증한
 * 뒤 공용 연결 transaction 을 탄다(흐름 · PII 금지는
 * `buildLinkOidcProviderCallable` 참조). secret 은 `KAKAO_NATIVE_APP_KEY`
 * 하나만 binding 한다 — Kakao 를 끈 프로젝트는 이 함수를 배포하지 않는다.
 */
export const linkKakaoProvider = buildLinkOidcProviderCallable(
  "kakao",
  [KAKAO_NATIVE_APP_KEY],
);
