/**
 * Phase 17 — see ROADMAP.md (D-19) · Security Rules 에뮬레이터 테스트 전용 jest 설정.
 *
 * `pnpm test:rules` 가 `firebase emulators:exec` 로 에뮬레이터를 띄운 뒤 이 설정으로
 * `test/rules/` 스위트만 실행한다. unit jest(`jest.config.js`)는 `test/rules/` 를 제외한다.
 *
 * @type {import('jest').Config}
 */
module.exports = {
  preset: "ts-jest",
  testEnvironment: "node",
  testMatch: ["**/test/rules/**/*.test.ts"],
  transform: {
    "^.+\\.ts$": ["ts-jest", {tsconfig: "tsconfig.dev.json"}],
  },
  // 에뮬레이터 호출 왕복이 unit 테스트보다 길다.
  testTimeout: 30000,
  // 에뮬레이터 DB 는 스위트 간 공유 상태 — 병렬 실행 시 clearFirestore 경합을 막는다.
  maxWorkers: 1,
  // jest.config.js 와 같은 jose stub (ESM-only 패키지 CJS 로드 회피).
  moduleNameMapper: {
    "^jose$": "<rootDir>/test/mocks/jose.ts",
  },
};
