/**
 * createOidcVerifier helper 단위 테스트 (Phase 14 D-LINE-02/05/07).
 *
 * **Mock 한계 명시 (Phase 14.1 D-14.1-03):** 본 test 의 mock 은 helper 가정과
 * 일관되게 동작한다는 self-referential 검증이다 (memory
 * `feedback_oidc_mock_self_referential` §2). 실 LINE OIDC provider 의 nonce
 * claim embed 동작은 Phase 14.1 D-14.1-02 (line-sdk-android LineIdToken.java
 * verbatim "the same value as in the authentication request" + line-sdk-ios-
 * swift LoginProcess.swift verbatim `parameters["nonce"] = nonce`) 로 cross-
 * verify 했다. 실 단말 backend tier UAT (.planning/phases/14-line-login/14-
 * HUMAN-UAT.md §A1) 가 진짜 contract 검증.
 *
 * Kakao (nonceHashing="none") + LINE (nonceHashing="none" — Phase 14.1 후,
 * Kakao 와 동일 mode) 두 config 모두 verify 케이스 + 클레임 실패 + JWKS
 * singleton 보존 검증.
 *
 * **jest.mock hoist:** jest.mock 호출은 hoist 되므로 src import 보다 먼저
 * 정의되어야 한다 (firebase-functions-test 공식 권장 패턴 — ping.test.ts
 * 와 동일).
 *
 * **JOSEError instanceof 보존:** mock factory 가 jose 의 errors 클래스 계층을
 * 직접 재구성. 실제 jose 의 JWTClaimValidationFailed 는 (msg, payload, claim?,
 * reason?) 시그니처지만 mock 에서는 단일 인자도 허용.
 */

// jose mock — jwtVerify + createRemoteJWKSet + errors 클래스 보존.
jest.mock("jose", () => {
  /** Mock JOSEError — instanceof 분기 동작용. */
  class JOSEError extends Error {
    code?: string;
    /** @param {string} [message] error message. */
    constructor(message?: string) {
      super(message);
      this.name = "JOSEError";
    }
  }
  /** Mock JWTClaimValidationFailed — JOSEError 서브클래스. */
  class JWTClaimValidationFailed extends JOSEError {
    payload?: unknown;
    claim?: string;
    reason?: string;
    /**
     * @param {string} [message] error message.
     * @param {unknown} [payload] decoded JWT payload.
     * @param {string} [claim] offending claim name.
     * @param {string} [reason] failure reason code.
     */
    constructor(
      message?: string,
      payload?: unknown,
      claim?: string,
      reason?: string,
    ) {
      super(message);
      this.name = "JWTClaimValidationFailed";
      this.code = "ERR_JWT_CLAIM_VALIDATION_FAILED";
      this.payload = payload;
      this.claim = claim;
      this.reason = reason;
    }
  }
  return {
    jwtVerify: jest.fn(),
    createRemoteJWKSet: jest.fn(() => "MOCK_JWKS"),
    errors: {JOSEError, JWTClaimValidationFailed},
  };
});

// 위 mock 셋업 이후에 src import.
// eslint-disable-next-line import/first
import * as jose from "jose";
// eslint-disable-next-line import/first
import {createOidcVerifier} from "../../src/shared/oidc_verifier";

const jwtVerifyMock = jose.jwtVerify as unknown as jest.Mock;
const createRemoteJWKSetMock = jose.createRemoteJWKSet as unknown as jest.Mock;

// Kakao config (nonceHashing="none" — raw nonce 비교).
const kakaoConfig = {
  issuer: "https://kauth.kakao.com",
  jwksUrl: "https://kauth.kakao.com/.well-known/jwks.json",
  audience: () => "fake-kakao-aud",
  algorithms: ["RS256"],
  nonceHashing: "none" as const,
};

// LINE config (nonceHashing="none" — raw nonce 비교, Phase 14.1 D-14.1-02
// cross-verified: LINE SDK 가 raw nonce 를 변환 0 으로 LINE 서버 transmit
// + ID Token nonce claim = raw 동일값).
const lineConfig = {
  issuer: "https://access.line.me",
  jwksUrl: "https://api.line.me/oauth2/v2.1/certs",
  audience: () => "fake-line-aud",
  algorithms: ["ES256"],
  nonceHashing: "none" as const,
};

describe("createOidcVerifier", () => {
  beforeEach(() => {
    jest.clearAllMocks();
  });

  it(
    "Test 1: Kakao config (nonceHashing='none') — raw nonce 일치 시 payload 반환",
    async () => {
      const rawNonce = "kakao-raw-nonce-123";
      jwtVerifyMock.mockResolvedValue({
        payload: {sub: "kakao-user-1", nonce: rawNonce, email: "k@test.com"},
      });

      const verify = createOidcVerifier(kakaoConfig);
      const payload = await verify("FAKE_KAKAO_JWT", rawNonce);

      expect(payload.sub).toBe("kakao-user-1");
      // jwtVerify 호출 인자 검증 — issuer/audience/algorithms.
      expect(jwtVerifyMock).toHaveBeenCalledWith(
        "FAKE_KAKAO_JWT",
        "MOCK_JWKS",
        expect.objectContaining({
          issuer: "https://kauth.kakao.com",
          audience: "fake-kakao-aud",
          algorithms: ["RS256"],
        }),
      );
    },
  );

  it(
    "Test 2: LINE config (nonceHashing='none') — raw nonce 일치 시 payload 반환",
    async () => {
      // Phase 14.1 D-14.1-02 cross-verified — LINE SDK 가 raw nonce 를 변환
      // 없이 LINE 서버 transmit → ID Token nonce claim = raw 동일값.
      const rawNonce = "line-raw-nonce-xyz";
      jwtVerifyMock.mockResolvedValue({
        payload: {sub: "line-user-1", nonce: rawNonce},
      });

      const verify = createOidcVerifier(lineConfig);
      const payload = await verify("FAKE_LINE_JWT", rawNonce);

      expect(payload.sub).toBe("line-user-1");
      expect(jwtVerifyMock).toHaveBeenCalledWith(
        "FAKE_LINE_JWT",
        "MOCK_JWKS",
        expect.objectContaining({
          issuer: "https://access.line.me",
          audience: "fake-line-aud",
          algorithms: ["ES256"],
        }),
      );
    },
  );

  it(
    "Test 3: Kakao config — nonce mismatch 시 JWTClaimValidationFailed throw",
    async () => {
      jwtVerifyMock.mockResolvedValue({
        payload: {sub: "kakao-user-2", nonce: "server-nonce"},
      });

      const verify = createOidcVerifier(kakaoConfig);
      await expect(verify("FAKE_JWT", "client-nonce")).rejects.toBeInstanceOf(
        jose.errors.JWTClaimValidationFailed,
      );
      await expect(verify("FAKE_JWT", "client-nonce")).rejects.toMatchObject({
        claim: "nonce",
        reason: "check_failed",
      });
    },
  );

  it(
    // eslint-disable-next-line max-len
    "Test 4: LINE config — raw nonce !== claim.nonce 시 JWTClaimValidationFailed throw",
    async () => {
      // claim 의 nonce 가 client 가 전달한 raw 와 다른 의도된 값 — raw 비교
      // path 에서 mismatch trigger (Phase 14.1 D-14.1-02 cross-verified raw
      // 비교 mode).
      jwtVerifyMock.mockResolvedValue({
        payload: {sub: "line-user-2", nonce: "different-nonce-value"},
      });

      const verify = createOidcVerifier(lineConfig);
      await expect(
        verify("FAKE_JWT", "expected-raw-nonce"),
      ).rejects.toBeInstanceOf(jose.errors.JWTClaimValidationFailed);
    },
  );

  it(
    "Test 5: iss mismatch — jwtVerify 가 JOSEError throw 시 caller 가 그대로 받음",
    async () => {
      const ErrCtor = jose.errors.JOSEError as unknown as new (
        m: string
      ) => Error;
      const err = new ErrCtor("unexpected iss");
      (err as unknown as {code: string}).code =
        "ERR_JWT_CLAIM_VALIDATION_FAILED";
      jwtVerifyMock.mockRejectedValue(err);

      const verify = createOidcVerifier(kakaoConfig);
      await expect(verify("FAKE_JWT", "n")).rejects.toBeInstanceOf(
        jose.errors.JOSEError,
      );
    },
  );

  it(
    // eslint-disable-next-line max-len
    "Test 6: aud mismatch — audience() callback 의 반환값과 다른 aud 시 jwtVerify throw",
    async () => {
      const ErrCtor = jose.errors.JOSEError as unknown as new (
        m: string
      ) => Error;
      jwtVerifyMock.mockRejectedValue(new ErrCtor("unexpected aud"));

      const verify = createOidcVerifier(kakaoConfig);
      await expect(verify("FAKE_JWT", "n")).rejects.toBeInstanceOf(
        jose.errors.JOSEError,
      );
      // audience callback 이 lazy invoke 되었음을 검증.
      expect(jwtVerifyMock).toHaveBeenCalledWith(
        expect.anything(),
        expect.anything(),
        expect.objectContaining({audience: "fake-kakao-aud"}),
      );
    },
  );

  it(
    "Test 7: algorithms mismatch — algorithms 배열 외 alg 시 jwtVerify throw",
    async () => {
      const ErrCtor = jose.errors.JOSEError as unknown as new (
        m: string
      ) => Error;
      jwtVerifyMock.mockRejectedValue(new ErrCtor("unexpected alg"));

      const verify = createOidcVerifier(kakaoConfig);
      await expect(verify("FAKE_JWT", "n")).rejects.toBeInstanceOf(
        jose.errors.JOSEError,
      );
      // algorithms 가 config 그대로 jwtVerify 인자에 전달.
      expect(jwtVerifyMock).toHaveBeenCalledWith(
        expect.anything(),
        expect.anything(),
        expect.objectContaining({algorithms: ["RS256"]}),
      );
    },
  );

  it(
    // eslint-disable-next-line max-len
    "Test 8: JWKS singleton — factory 1회 + verifier 2회 호출 후 createRemoteJWKSet mock 은 1회만 evaluate",
    async () => {
      jwtVerifyMock.mockResolvedValue({
        payload: {sub: "kakao-user-singleton", nonce: "n"},
      });

      // factory 1회 호출 — createRemoteJWKSet 도 1회만.
      const verify = createOidcVerifier(kakaoConfig);
      await verify("FAKE_JWT_1", "n");
      await verify("FAKE_JWT_2", "n");

      // factory 호출 시 1회 evaluate — 반환 verifier 2회 호출해도 동일.
      expect(createRemoteJWKSetMock).toHaveBeenCalledTimes(1);
      // jwtVerify 는 verifier 호출 횟수만큼.
      expect(jwtVerifyMock).toHaveBeenCalledTimes(2);
    },
  );
});
