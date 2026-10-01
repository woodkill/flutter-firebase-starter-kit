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
import {
  deleteDoc,
  deleteField,
  doc,
  getDoc,
  setDoc,
  setLogLevel,
  Timestamp,
  updateDoc,
} from "firebase/firestore";

const PROJECT_ID = "demo-starter-kit";
const REPO_ROOT = path.resolve(__dirname, "../../..");
const RULES_PATH = path.join(REPO_ROOT, "firestore.rules");
const TEN_MINUTES_MS = 10 * 60 * 1000;

type DocData = Record<string, unknown>;
// rules-unit-testing context 가 돌려주는 클라이언트 Firestore (compat 타입).
type ClientDb = ReturnType<RulesTestContext["firestore"]>;

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
 * 「지금」 시각 — 서버 request.time 보다 확실히 과거가 되도록 1초 뺀다.
 * @return {Timestamp} 현재 시각 − 1초.
 */
function nowTs(): Timestamp {
  return Timestamp.fromMillis(Date.now() - 1000);
}

/**
 * `TermsNotifier.mirrorToFirestore` 와 같은 5필드 약관 payload 를 만든다.
 * @param {DocData} overrides 덮어쓸 필드.
 * @return {DocData} termsAccepted map.
 */
function terms(overrides: DocData = {}): DocData {
  return {
    version: 1,
    service: true,
    privacy: true,
    marketing: false,
    acceptedAt: nowTs(),
    ...overrides,
  };
}

/**
 * 클라이언트 writer 와 같은 `set(..., {merge: true})` 를 수행한다.
 * @param {ClientDb} db 클라이언트 Firestore.
 * @param {string} docPath 문서 경로.
 * @param {DocData} data payload.
 * @return {Promise<void>} write 결과.
 */
function setMerge(
  db: ClientDb,
  docPath: string,
  data: DocData,
): Promise<void> {
  return setDoc(doc(db, docPath), data, {merge: true});
}

/**
 * fcmTokens 문서의 정확한 5키 payload 를 만든다 (D-02).
 * @param {string} token FCM 토큰(= 문서 id).
 * @param {DocData} overrides 덮어쓸 필드.
 * @return {DocData} 토큰 문서.
 */
function fcmToken(token: string, overrides: DocData = {}): DocData {
  return {
    token,
    platform: "android",
    locale: "ko",
    updatedAt: nowTs(),
    expireAt: Timestamp.fromMillis(Date.now() + 60 * 24 * 3600 * 1000),
    ...overrides,
  };
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

  it(
    "T-17-RULES-02: 약관 mirror 재생 — 문서 없음 생성 · force 재동의 · 역행 거부",
    async () => {
      const alice = regularUser("alice").firestore();
      const path = "users/alice";
      // (1a) 익명→정식 전이 mirror — 문서 없음 → create.
      await assertSucceeds(setMerge(alice, path, {termsAccepted: terms()}));
      // (1b) force 재동의 — 같은 version · 큰 version 허용.
      await assertSucceeds(setMerge(alice, path, {termsAccepted: terms()}));
      await assertFails(
        setMerge(alice, path, {termsAccepted: terms({version: 0})}),
      );
      await assertSucceeds(
        setMerge(alice, path, {termsAccepted: terms({version: 2})}),
      );
      await assertFails(
        setMerge(alice, path, {termsAccepted: terms({version: 1})}),
      );
    });

  it(
    "T-17-RULES-03: 약관 삭제 · 미래 시각 · 필수 false · 키/타입 위반 거부",
    async () => {
      const alice = regularUser("alice").firestore();
      const path = "users/alice";
      await seed(path, {termsAccepted: terms()});

      // ① 삭제 거부 — 필드 삭제 · 문서 overwrite 로 누락.
      await assertFails(
        updateDoc(doc(alice, path), {termsAccepted: deleteField()}),
      );
      await assertFails(
        setDoc(doc(alice, path), {signUpProviderId: "google.com"}),
      );
      // ④ acceptedAt = now 허용 · now + 10분 거부 (허용 오차 0).
      await assertSucceeds(
        setMerge(alice, path, {termsAccepted: terms({acceptedAt: nowTs()})}),
      );
      const future = Timestamp.fromMillis(Date.now() + TEN_MINUTES_MS);
      await assertFails(
        setMerge(alice, path, {termsAccepted: terms({acceptedAt: future})}),
      );
      // ③ 필수 동의 false 거부.
      await assertFails(
        setMerge(alice, path, {termsAccepted: terms({service: false})}),
      );
      await assertFails(
        setMerge(alice, path, {termsAccepted: terms({privacy: false})}),
      );
      // ⑤ 6번째 키 · 키 누락 · 타입 위반 거부.
      await assertFails(
        setMerge(alice, path, {termsAccepted: terms({extra: true})}),
      );
      const missing = terms();
      delete missing.marketing;
      await assertFails(updateDoc(doc(alice, path), {termsAccepted: missing}));
      const bob = regularUser("bob").firestore();
      await assertFails(setMerge(bob, "users/bob", {termsAccepted: missing}));
      await assertFails(setMerge(bob, "users/bob", {termsAccepted: {}}));
      await assertFails(
        setMerge(alice, path, {termsAccepted: terms({version: "1"})}),
      );
      await assertFails(
        setMerge(alice, path, {
          termsAccepted: terms({acceptedAt: "2026-10-01T00:00:00Z"}),
        }),
      );
      // marketing(선택) true ↔ false 변경 허용.
      await assertSucceeds(
        setMerge(alice, path, {termsAccepted: terms({marketing: true})}),
      );
      await assertSucceeds(
        setMerge(alice, path, {termsAccepted: terms({marketing: false})}),
      );
    });

  it(
    "T-17-RULES-04: 가입 수단 recorder 재생 — write-once (변경 · 삭제 · 빈 값 거부)",
    async () => {
      const alice = regularUser("alice").firestore();
      // 문서 없음 → create (mirror 실패 뒤 recorder 가 먼저 쓰는 경로).
      await assertSucceeds(
        setMerge(alice, "users/alice", {signUpProviderId: "google.com"}),
      );
      // 약관만 있는 문서에 추가 (mirror → recorder 정상 순서).
      const bob = regularUser("bob").firestore();
      await assertSucceeds(
        setMerge(bob, "users/bob", {termsAccepted: terms()}),
      );
      await assertSucceeds(
        setMerge(bob, "users/bob", {signUpProviderId: "google.com"}),
      );
      // 재시도 — 같은 값 재기록 허용.
      await assertSucceeds(
        setMerge(bob, "users/bob", {signUpProviderId: "google.com"}),
      );
      // 다른 값 · 삭제 거부.
      await assertFails(
        setMerge(bob, "users/bob", {signUpProviderId: "apple.com"}),
      );
      await assertFails(
        updateDoc(doc(bob, "users/bob"), {signUpProviderId: deleteField()}),
      );
      // 빈 문자열 거부.
      const carol = regularUser("carol").firestore();
      await assertFails(
        setMerge(carol, "users/carol", {signUpProviderId: ""}),
      );
    });

  it(
    "T-17-RULES-05: 서버 전용 키 클라이언트 write 거부 · 화이트리스트 merge 허용",
    async () => {
      const alice = regularUser("alice").firestore();
      const path = "users/alice";
      // 서버(Admin SDK)가 쓴 문서 대역.
      await seed(path, {
        linkedProviders: [{providerId: "kakao", providerUserId: "1"}],
        providerLinkedAt: {kakao: nowTs()},
        email: "alice@example.com",
        emailVerified: true,
        signUpProviderId: "kakao",
      });
      const serverOnly: DocData = {
        linkedProviders: [{providerId: "naver", providerUserId: "2"}],
        providerLinkedAt: {naver: nowTs()},
        email: "mallory@example.com",
        emailVerified: false,
        displayName: "Mallory",
      };
      for (const [key, value] of Object.entries(serverOnly)) {
        await assertFails(setMerge(alice, path, {[key]: value}));
      }
      // create 에 서버 전용 키를 섞으면 거부.
      const bob = regularUser("bob").firestore();
      await assertFails(
        setMerge(bob, "users/bob", {
          termsAccepted: terms(),
          linkedProviders: [{providerId: "kakao", providerUserId: "3"}],
        }),
      );
      // 서버 키가 있는 문서에 화이트리스트 키만 merge → 허용.
      await assertSucceeds(setMerge(alice, path, {termsAccepted: terms()}));
    });

  it(
    "T-17-RULES-06: customPhotoUrl 문자열 · null 허용 · 숫자 거부",
    async () => {
      const alice = regularUser("alice").firestore();
      const path = "users/alice";
      await assertSucceeds(
        setMerge(alice, path, {customPhotoUrl: "https://example.com/a.jpg"}),
      );
      await assertSucceeds(setMerge(alice, path, {customPhotoUrl: null}));
      await assertFails(setMerge(alice, path, {customPhotoUrl: 42}));
    });

  it(
    "T-17-RULES-07: users 문서 delete · 타인 write · 미인증 write 거부",
    async () => {
      await seed("users/alice", {termsAccepted: terms()});
      const alice = regularUser("alice").firestore();
      const bob = regularUser("bob").firestore();
      const anon = testEnv.unauthenticatedContext().firestore();

      await assertFails(deleteDoc(doc(alice, "users/alice")));
      await assertFails(
        setMerge(bob, "users/alice", {customPhotoUrl: "https://x/y.jpg"}),
      );
      await assertFails(
        setMerge(anon, "users/alice", {customPhotoUrl: "https://x/y.jpg"}),
      );
    });

  it(
    "T-17-RULES-08: fcmTokens 정식 본인만 정확 스키마 write · 익명 · 타인 거부",
    async () => {
      const alice = regularUser("alice").firestore();
      const tokenPath = "users/alice/fcmTokens/tok-1";
      // 정식 본인 create · update · read · delete 허용.
      await assertSucceeds(setDoc(doc(alice, tokenPath), fcmToken("tok-1")));
      await assertSucceeds(
        setDoc(doc(alice, tokenPath), fcmToken("tok-1", {locale: "en"})),
      );
      await assertSucceeds(getDoc(doc(alice, tokenPath)));
      await assertSucceeds(deleteDoc(doc(alice, tokenPath)));

      // 스키마 위반 거부.
      const other = "users/alice/fcmTokens/tok-2";
      await assertFails(setDoc(doc(alice, other), fcmToken("tok-1")));
      await assertFails(
        setDoc(doc(alice, other), fcmToken("tok-2", {extra: "x"})),
      );
      await assertFails(
        setDoc(doc(alice, other), fcmToken("tok-2", {platform: "web"})),
      );
      await assertFails(
        setDoc(doc(alice, other), fcmToken("tok-2", {locale: "fr"})),
      );
      await assertFails(
        setDoc(
          doc(alice, other),
          fcmToken("tok-2", {updatedAt: "2026-10-01T00:00:00Z"}),
        ),
      );

      // 익명 세션 거부 (D-28 — 30일 뒤 고아 데이터 방지).
      const ghost = anonymousUser("ghost").firestore();
      await assertFails(
        setDoc(doc(ghost, "users/ghost/fcmTokens/tok-3"), fcmToken("tok-3")),
      );

      // 타인 uid 경로 read · write 거부.
      await seed(tokenPath, fcmToken("tok-1"));
      const bob = regularUser("bob").firestore();
      await assertFails(getDoc(doc(bob, tokenPath)));
      await assertFails(setDoc(doc(bob, tokenPath), fcmToken("tok-1")));
      await assertFails(deleteDoc(doc(bob, tokenPath)));
    });

  it(
    "T-17-RULES-09: firestore.rules stale 표기 정정 (Phase 18 · TODO 0)",
    () => {
      const rules = readFileSync(RULES_PATH, "utf8");
      expect(rules).not.toContain("Phase 18");
      expect(rules).not.toContain("TODO");
      expect(rules).toContain("Phase 17");
    });

  it(
    "T-17-RULES-10: 재생 payload 키 = 실제 writer 소스 리터럴",
    () => {
      const termsWriter = readFileSync(
        path.join(
          REPO_ROOT,
          "lib/features/terms/presentation/terms_notifier.dart",
        ),
        "utf8",
      );
      const termsKeys = [
        "'termsAccepted'",
        "'version'",
        "'service'",
        "'privacy'",
        "'marketing'",
        "'acceptedAt'",
        "SetOptions(merge: true)",
      ];
      for (const literal of termsKeys) {
        expect(termsWriter).toContain(literal);
      }
      const recorder = readFileSync(
        path.join(
          REPO_ROOT,
          "lib/features/auth/data/sign_up_method_recorder.dart",
        ),
        "utf8",
      );
      expect(recorder).toContain("'signUpProviderId'");
      expect(recorder).toContain("SetOptions(merge: true)");
    });
});
