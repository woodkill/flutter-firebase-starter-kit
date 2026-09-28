// Phase 16.10 D-02 · D-13 — Kakao 어드민 키 secret 선언 단일 진실원.
//
// 배포 전 의무:
//   firebase functions:secrets:set KAKAO_ADMIN_KEY
// 값은 Kakao Developers 콘솔 → [앱] > [어드민 키] 다.
//
// provider 제거 시: 이 파일 + 사용처 callable 파일 + `index.ts` export 1줄을
// 함께 지우고, 배포된 함수 · secret 을 정리한다 (C-08).
import {defineSecret} from "firebase-functions/params";

/**
 * Kakao 어드민 키 (Phase 16.10 D-02 · C-04).
 *
 * **사용처:** `disconnectKakaoProvider`(`auth/disconnect_kakao_provider.ts`)가
 * `POST https://kapi.kakao.com/v1/user/unlink` 의
 * `Authorization: KakaoAK <키>` 헤더로 보낸다. 탈퇴 함수
 * (`deleteUserAccount`)는 바인딩하지 않는다 — Kakao 를 쓰지 않는 클론에 키
 * 설정을 강제하지 않기 위해서다 (D-13 · WR-04 「사용처 0 secret 선언 금지」).
 *
 * **콘솔 조건 (plan 01 Wave 0 실측):**
 * - `KAKAO_NATIVE_APP_KEY` 와 **같은 앱** 의 어드민 키여야 한다 — 다른 앱의
 *   키면 회원번호가 그 앱에 연결돼 있지 않아 끊기가 실패한다.
 * - 어드민 키 「사용 가능 API」 에 연결 끊기를 허용한다.
 * - 「호출 허용 IP 주소」 는 등록하지 않는다 — Cloud Functions 의 egress IP
 *   는 고정돼 있지 않다.
 *
 * **서버 전용 키:** Kakao 원문 「어드민 키를 사용하는 API는 서버에서만
 * 호출해야 합니다」. client `config/<flavor>.json` 에 두지 않는다. 값은
 * 함수 본문 실행 시점에만 `.value()` 로 읽는다 (module scope 금지).
 */
export const KAKAO_ADMIN_KEY = defineSecret("KAKAO_ADMIN_KEY");
