// Phase 17 — see ROADMAP.md (D-15 · D-19 · D-28)
// `pnpm test:rules` 전용 — 에뮬레이터 없이 실행 금지.
//
// `firebase emulators:exec --only firestore,storage` 가
// FIREBASE_STORAGE_EMULATOR_HOST 를 넣어 준 상태에서, 저장소 루트의 실제
// `storage.rules` 를 로드해 클라이언트 SDK 관점의 업로드 · 읽기 · 삭제
// 허용 · 거부를 판정한다. unit jest(`pnpm test`)는 `test/rules/` 를 제외한다.
import {readFileSync} from "fs";
import * as path from "path";
import {
  assertSucceeds,
  initializeTestEnvironment,
} from "@firebase/rules-unit-testing";
import type {
  RulesTestContext,
  RulesTestEnvironment,
} from "@firebase/rules-unit-testing";
import {setLogLevel} from "firebase/app";
import {ref, uploadBytes} from "firebase/storage";
import type {FirebaseStorage} from "firebase/storage";

const PROJECT_ID = "demo-starter-kit";
const REPO_ROOT = path.resolve(__dirname, "../../..");
const RULES_PATH = path.join(REPO_ROOT, "storage.rules");
const AVATAR_PATH = "users/alice/profile/avatar.jpg";
const ONE_KB = 1024;

let testEnv: RulesTestEnvironment;

/**
 * 정식(비익명) 사용자 context 를 만든다.
 * @param {string} uid 인증 uid.
 * @return {RulesTestContext} context.
 */
function regularUser(uid: string): RulesTestContext {
  return testEnv.authenticatedContext(uid, {
    firebase: {sign_in_provider: "google.com"},
  });
}

/**
 * context 의 compat Storage 를 modular API 가 받는 타입으로 돌려준다.
 *
 * rules-unit-testing 은 compat 인스턴스를 주지만 modular 함수는 내부에서
 * `getModularInstance` 로 위임 객체를 꺼내 쓴다(Firestore 스위트와 같은 방식).
 * @param {RulesTestContext} ctx 테스트 context.
 * @return {FirebaseStorage} modular Storage.
 */
function storageOf(ctx: RulesTestContext): FirebaseStorage {
  return ctx.storage() as unknown as FirebaseStorage;
}

/**
 * [size] 바이트짜리 업로드 payload 를 만든다.
 * @param {number} size 바이트 수.
 * @return {Uint8Array} payload.
 */
function bytes(size: number): Uint8Array {
  return new Uint8Array(size);
}

beforeAll(async () => {
  // assertFails 가 기대하는 권한 거부가 SDK warn 로그로 쏟아지는 것을 막는다.
  setLogLevel("error");
  testEnv = await initializeTestEnvironment({
    projectId: PROJECT_ID,
    storage: {rules: readFileSync(RULES_PATH, "utf8")},
  });
});

afterEach(async () => {
  await testEnv.clearStorage();
});

afterAll(async () => {
  await testEnv.cleanup();
});

describe("Phase 17 Storage rules (T-17-SRULES)", () => {
  it("T-17-SRULES-01: 정식 본인 image/jpeg 업로드 허용", async () => {
    const alice = storageOf(regularUser("alice"));

    await assertSucceeds(
      uploadBytes(ref(alice, AVATAR_PATH), bytes(ONE_KB), {
        contentType: "image/jpeg",
      }),
    );
  });
});
