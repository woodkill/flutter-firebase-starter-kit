// Phase 17 — see ROADMAP.md (D-19) · `pnpm test:rules` 전용 — 에뮬레이터 없이 실행 금지.
//
// `firebase emulators:exec --only firestore` 가 FIRESTORE_EMULATOR_HOST 를 넣어 준
// 상태에서, 저장소 루트의 실제 `firestore.rules` 를 로드해 클라이언트 SDK 관점의
// 허용 · 거부를 판정한다. unit jest(`pnpm test`)는 `test/rules/` 를 제외한다.
import {readFileSync} from "fs";
import * as path from "path";
import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} from "@firebase/rules-unit-testing";
import type {
  RulesTestContext,
  RulesTestEnvironment,
} from "@firebase/rules-unit-testing";
import {doc, getDoc, setDoc, setLogLevel} from "firebase/firestore";

const PROJECT_ID = "demo-starter-kit";
const RULES_PATH = path.resolve(__dirname, "../../../firestore.rules");

let testEnv: RulesTestEnvironment;

/**
 * 정식(비익명) 사용자 context 의 Firestore 인스턴스를 만든다.
 * @param {string} uid 인증 uid.
 * @return {RulesTestContext} context.
 */
function regularUser(uid: string): RulesTestContext {
  return testEnv.authenticatedContext(uid, {
    firebase: {sign_in_provider: "google.com"},
  });
}

/**
 * rules 를 우회해 문서를 seed 한다 (서버 Admin SDK write 대역).
 * @param {string} docPath 문서 경로.
 * @param {Record<string, unknown>} data 문서 데이터.
 * @return {Promise<void>} 완료.
 */
async function seed(
  docPath: string,
  data: Record<string, unknown>,
): Promise<void> {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await setDoc(doc(ctx.firestore(), docPath), data);
  });
}

beforeAll(async () => {
  // assertFails 가 기대하는 PERMISSION_DENIED 가 SDK warn 로그로 쏟아지는 것을 막는다.
  setLogLevel("error");
  testEnv = await initializeTestEnvironment({
    projectId: PROJECT_ID,
    firestore: {rules: readFileSync(RULES_PATH, "utf8")},
  });
});

afterEach(async () => {
  await testEnv.clearFirestore();
});

afterAll(async () => {
  await testEnv.cleanup();
});

describe("Phase 17 Firestore rules (T-17-RULES)", () => {
  it(
    "T-17-RULES-01: users 본인 읽기 허용 · 타인 · 미인증 거부 · identity_index 거부",
    async () => {
      await seed("users/alice", {signUpProviderId: "google.com"});
      await seed("identity_index/kakao:1", {uid: "alice"});

      const alice = regularUser("alice").firestore();
      const bob = regularUser("bob").firestore();
      const anon = testEnv.unauthenticatedContext().firestore();

      await assertSucceeds(getDoc(doc(alice, "users/alice")));
      await assertFails(getDoc(doc(bob, "users/alice")));
      await assertFails(getDoc(doc(anon, "users/alice")));

      await assertFails(getDoc(doc(alice, "identity_index/kakao:1")));
      await assertFails(
        setDoc(doc(alice, "identity_index/kakao:2"), {uid: "alice"}),
      );
    });
});
