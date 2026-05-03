/** @type {import('jest').Config} */
module.exports = {
  preset: "ts-jest",
  testEnvironment: "node",
  testMatch: ["**/test/**/*.test.ts"],
  transform: {
    "^.+\\.ts$": ["ts-jest", {tsconfig: "tsconfig.dev.json"}],
  },
  // Phase 12 — jose 6.x 는 ESM-only 배포라 jest CommonJS 환경에서 직접
  // require 시 SyntaxError. ping.test.ts 가 src/index.ts 전체를 import 하므로
  // jest 가 모든 테스트에서 jose 모듈을 평가한다. moduleNameMapper 로 jose
  // import 를 jest 호환 stub 으로 치환 — 실제 검증은 kakao_custom_token.test.ts
  // 가 jest.mock('jose', ...) 로 자체 mock 한다.
  moduleNameMapper: {
    "^jose$": "<rootDir>/test/mocks/jose.ts",
  },
};
