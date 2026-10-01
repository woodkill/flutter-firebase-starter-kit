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
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} from "@firebase/rules-unit-testing";
import type {
  RulesTestContext,
  RulesTestEnvironment,
} from "@firebase/rules-unit-testing";
import {setLogLevel} from "firebase/app";
import {
  deleteObject,
  getBytes,
  getMetadata,
  ref,
  uploadBytes,
} from "firebase/storage";
import type {FirebaseStorage} from "firebase/storage";

const PROJECT_ID = "demo-starter-kit";
const REPO_ROOT = path.resolve(__dirname, "../../..");
const RULES_PATH = path.join(REPO_ROOT, "storage.rules");
const AVATAR_PATH = "users/alice/profile/avatar.jpg";
const ONE_KB = 1024;
const FIVE_MB = 5 * 1024 * 1024;
const JPEG = {contentType: "image/jpeg"};

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
 * 익명 세션 context 를 만든다 (`sign_in_provider: anonymous`).
 * @param {string} uid 익명 uid.
 * @return {RulesTestContext} context.
 */
function anonymousUser(uid: string): RulesTestContext {
  return testEnv.authenticatedContext(uid, {
    firebase: {sign_in_provider: "anonymous"},
  });
}

/**
 * context 의 Storage 를 modular API 에 넘길 타입으로 돌려준다.
 *
 * rules-unit-testing 은 compat 인스턴스를 주지만 modular 함수는 내부에서
 * `getModularInstance` 로 위임 객체를 꺼내 쓴다(Firestore 스위트와 같은 방식).
 * compat 타입이 `FirebaseStorage` 와 구조적으로 호환돼 단언 없이 넘어간다.
 * @param {RulesTestContext} ctx 테스트 context.
 * @return {FirebaseStorage} modular Storage.
 */
function storageOf(ctx: RulesTestContext): FirebaseStorage {
  return ctx.storage();
}

/**
 * [size] 바이트짜리 업로드 payload 를 만든다.
 * @param {number} size 바이트 수.
 * @return {Uint8Array} payload.
 */
function bytes(size: number): Uint8Array {
  return new Uint8Array(size);
}

/**
 * rules 를 우회해 객체를 seed 한다 (서버 Admin SDK write 대역).
 * @param {string} objectPath 객체 경로.
 * @return {Promise<void>} 완료.
 */
async function seed(objectPath: string): Promise<void> {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await uploadBytes(ref(storageOf(ctx), objectPath), bytes(ONE_KB), JPEG);
  });
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
      uploadBytes(ref(alice, AVATAR_PATH), bytes(ONE_KB), JPEG),
    );
  });

  it("T-17-SRULES-02: 타인 경로 업로드 · 읽기 거부", async () => {
    await seed(AVATAR_PATH);
    const bob = storageOf(regularUser("bob"));

    await assertFails(uploadBytes(ref(bob, AVATAR_PATH), bytes(ONE_KB), JPEG));
    await assertFails(getBytes(ref(bob, AVATAR_PATH)));
  });

  it("T-17-SRULES-03: 정확히 5MB 허용 · 5MB+1 바이트 거부", async () => {
    const alice = storageOf(regularUser("alice"));

    await assertSucceeds(
      uploadBytes(ref(alice, AVATAR_PATH), bytes(FIVE_MB), JPEG),
    );
    await assertFails(
      uploadBytes(ref(alice, AVATAR_PATH), bytes(FIVE_MB + 1), JPEG),
    );
  });

  it("T-17-SRULES-04: text/plain · contentType 미지정 거부", async () => {
    const alice = storageOf(regularUser("alice"));

    await assertFails(
      uploadBytes(ref(alice, AVATAR_PATH), bytes(ONE_KB), {
        contentType: "text/plain",
      }),
    );
    // Pitfall 7 — metadata 없이 올리면 image/* 매치에 실패해야 한다.
    await assertFails(uploadBytes(ref(alice, AVATAR_PATH), bytes(ONE_KB)));

    // 실측: metadata 없는 업로드가 실제로 받는 contentType (rules 우회 seed).
    let inferred: string | undefined;
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      const target = ref(storageOf(ctx), "users/alice/probe.bin");
      await uploadBytes(target, bytes(ONE_KB));
      inferred = (await getMetadata(target)).contentType;
    });
    expect(inferred).toBe("application/octet-stream");
  });

  it("T-17-SRULES-05: 익명 세션 본인 경로 업로드 거부", async () => {
    const anon = storageOf(anonymousUser("alice"));

    await assertFails(
      uploadBytes(ref(anon, AVATAR_PATH), bytes(ONE_KB), JPEG),
    );
  });

  it("T-17-SRULES-06: 본인 삭제 허용 · 타인 삭제 거부", async () => {
    const alice = storageOf(regularUser("alice"));
    const bob = storageOf(regularUser("bob"));

    await assertSucceeds(
      uploadBytes(ref(alice, AVATAR_PATH), bytes(ONE_KB), JPEG),
    );
    await assertFails(deleteObject(ref(bob, AVATAR_PATH)));
    // A11 — delete 는 request.resource == null 관용구로 허용된다.
    await assertSucceeds(deleteObject(ref(alice, AVATAR_PATH)));
  });

  it("T-17-SRULES-07: 본인 읽기 허용", async () => {
    await seed(AVATAR_PATH);
    const alice = storageOf(regularUser("alice"));

    const data = await assertSucceeds(getBytes(ref(alice, AVATAR_PATH)));
    expect(data.byteLength).toBe(ONE_KB);
  });

  it("T-17-SRULES-08: users 밖 경로 읽기 · 쓰기 거부", async () => {
    const outside = ["public/x.jpg", "users.jpg"];
    for (const objectPath of outside) {
      await seed(objectPath);
    }
    const alice = storageOf(regularUser("alice"));

    for (const objectPath of outside) {
      await assertFails(
        uploadBytes(ref(alice, objectPath), bytes(ONE_KB), JPEG),
      );
      await assertFails(getBytes(ref(alice, objectPath)));
    }
  });
});
