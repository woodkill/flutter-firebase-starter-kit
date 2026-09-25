/**
 * OIDC provider 설정 단일 진실원 sentinel (Phase 15 리뷰 WR-06).
 *
 * 이전에는 issuer / jwksUrl / algorithms / nonceHashing 4-튜플이 provider
 * 2종 × 2 파일 = 4개 리터럴로 존재해서 (각 Custom Token endpoint 1 +
 * link_custom_token_provider.ts 1) 두 가지 결함이 있었다.
 *
 * 1. drift — 한 곳만 고치면 "로그인은 되는데 연동은 안 되는" 부분 장애.
 *    issuer 의 trailing slash 처럼 한 글자 차이가 치명적인 값에서 특히
 *    위험하다.
 * 2. JWKS 캐시 이중화 — provider 당 createRemoteJWKSet 이 2번 호출되어
 *    oidc_verifier.ts 의 "JWKS singleton (Pitfall 3 sentinel)" 전제가 깨짐.
 *
 * 본 test 는 **factory 호출이 provider 당 정확히 1회** 임과 **2 provider 의
 * OIDC 메타데이터 verbatim** 을 동시에 잠근다.
 */

jest.mock("firebase-functions/params", () => ({
  defineSecret: (name: string) => ({value: () => `fake-${name}`}),
}));

// createOidcVerifier 호출 인자를 그대로 캡처한다 — 실제 jose 는 부르지 않는다.
const capturedConfigs: Array<Record<string, unknown>> = [];
jest.mock("../../src/shared/oidc_verifier", () => ({
  createOidcVerifier: jest.fn((config: Record<string, unknown>) => {
    capturedConfigs.push(config);
    return jest.fn();
  }),
}));

// eslint-disable-next-line import/first
import {
  OIDC_VERIFIERS,
  OidcProviderId,
} from "../../src/shared/oidc_providers";

describe("OIDC_VERIFIERS — WR-06 단일 진실원", () => {
  it("verifier factory 는 provider 당 정확히 1회만 호출된다", () => {
    // 2 = kakao + line. 3이 되면 JWKS 캐시 이중화 회귀다.
    expect(capturedConfigs).toHaveLength(2);
  });

  it("2 provider verifier 가 맵에 모두 존재한다", () => {
    const ids: OidcProviderId[] = ["kakao", "line"];
    expect(Object.keys(OIDC_VERIFIERS).sort()).toEqual([...ids].sort());
    for (const id of ids) {
      expect(typeof OIDC_VERIFIERS[id]).toBe("function");
    }
  });

  // 아래 값들은 공식 문서 verbatim 이다 — 변경은 동작 변경이다. issuer 는
  // 각 IdP 의 OpenID Provider Metadata `"issuer"` 필드가 진실원이다 —
  // trailing slash 한 글자 차이로 검증이 깨진다.
  const expectedConfigs: Array<[string, string, string, string[]]> = [
    [
      "kakao",
      "https://kauth.kakao.com",
      "https://kauth.kakao.com/.well-known/jwks.json",
      ["RS256"],
    ],
    [
      "line",
      "https://access.line.me",
      "https://api.line.me/oauth2/v2.1/certs",
      ["ES256"],
    ],
  ];
  it.each(expectedConfigs)(
    "%s 의 issuer / jwksUrl / algorithms / nonceHashing verbatim",
    (_id, issuer, jwksUrl, algorithms) => {
      const config = capturedConfigs.find((c) => c.issuer === issuer);
      expect(config).toBeDefined();
      expect(config?.jwksUrl).toBe(jwksUrl);
      expect(config?.algorithms).toEqual(algorithms);
      // 2 provider 모두 raw nonce 비교 mode (cross-verified).
      expect(config?.nonceHashing).toBe("none");
    },
  );

  it("audience 는 secret lazy invoke 콜백으로 전달된다", () => {
    // defineSecret().value() 는 onCall 진입 시점에만 evaluate 가능하므로
    // 모듈 로드 시점에 값을 읽으면 배포 환경에서 터진다.
    for (const config of capturedConfigs) {
      expect(typeof config.audience).toBe("function");
    }
  });
});
