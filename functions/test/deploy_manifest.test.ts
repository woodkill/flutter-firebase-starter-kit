/**
 * 배포 함수 목록(scripts/functions_manifest.json) 대조.
 *
 * `scripts/deploy_functions.sh` 는 manifest 한 곳만 읽어 공통 함수 + 켠 provider
 * 함수를 배포한다. 그래서 manifest 가 `src/index.ts` 의 export 와 어긋나면
 * 새 함수가 배포되지 않거나 지운 함수가 명령에 남는다(T-173-12). 또 공통 함수가
 * provider secret 을 묶거나 provider 함수가 다른 provider 의 secret 을 묶으면,
 * 그 provider 를 꺼도 그 secret 의 유효 버전 검사 · 접근 권한 부여가 배포에
 * 걸리고 값이 런타임에 읽힌다 — binding 최소화가 계약 (4) 「끈 provider 의 함수
 * 배포가 필요 없고 secret 값은 자리표시여도 된다」 를 지킨다(T-173-11).
 * secret **존재** 확인은 binding 과 무관하다 — Firebase CLI 는 `--only` 필터와
 * 상관없이 선언된 `defineSecret` 전부를 확인하므로 끈 provider 의 secret 도
 * Secret Manager 에 있어야 한다. secret 은 위저드(`./setup.sh --providers`)가
 * 만든다 — 위저드 provider 단계(`tool/setup/steps/*_step.dart`)의 `secretNames`
 * 가 그 이름이다. 그 이름 · 단계 token · 아래 소유 맵 · `src/` 의
 * `defineSecret` 선언은 T-173-DEPLOY-15 가 서로 대조한다.
 *
 * `firebase-functions/params` 는 mock 하지 않는다 — 실제 secret 이름이
 * `__endpoint.secretEnvironmentVariables` 에 남아야 binding 을 검사할 수 있다.
 * 앱 쪽 provider 키 대조는 `test/core/config/functions_manifest_contract_test.dart`.
 */

import {readdirSync, readFileSync} from "node:fs";
import {join} from "node:path";
import functionsTest from "firebase-functions-test";

const testEnv = functionsTest();

// index import 는 testEnv 초기화 이후 (firebase-functions-test 권장 패턴).
// eslint-disable-next-line import/first
import * as myFunctions from "../src/index";

afterAll(() => testEnv.cleanup());

/**
 * manifest JSON 모양 — 최상위 키는 common · providers · email 세 개뿐이다.
 *
 * `email` 은 발송 모드별 묶음이다(Phase 17.5 — `email.kit` 은
 * `emailDelivery=kit` 일 때만 배포한다 · 원칙 P).
 */
type Manifest = {
  common: string[];
  providers: Record<string, string[]>;
  email: Record<string, string[]>;
};

/** 배포 함수의 secret binding 을 읽기 위한 최소 endpoint 모양. */
type EndpointCarrier = {
  __endpoint?: {secretEnvironmentVariables?: Array<{key: string}>};
};

const MANIFEST_PATH = join(
  __dirname,
  "..",
  "..",
  "scripts",
  "functions_manifest.json",
);
const manifest = JSON.parse(readFileSync(MANIFEST_PATH, "utf8")) as Manifest;

/**
 * provider secret 이름 → 소유 provider.
 *
 * 선언 위치: `src/shared/oidc_providers.ts` · `kakao_admin_secret.ts` ·
 * `naver_secrets.ts` · `facebook_secrets.ts`. 키 집합은 위저드 provider 단계의
 * `secretNames` 합집합과 같고, 값은 그 secret 을 등록하는 단계의 `token` 이다
 * (T-173-DEPLOY-15).
 */
const PROVIDER_SECRET_OWNER: Readonly<Record<string, string>> = {
  KAKAO_NATIVE_APP_KEY: "kakao",
  KAKAO_ADMIN_KEY: "kakao",
  NAVER_CLIENT_ID: "naver",
  NAVER_CLIENT_SECRET: "naver",
  LINE_CHANNEL_ID: "line",
  LINE_CHANNEL_SECRET: "line",
  FACEBOOK_APP_ID: "facebook",
  FACEBOOK_APP_SECRET: "facebook",
};

const SRC_DIR = join(__dirname, "..", "src");
const STEPS_DIR = join(__dirname, "..", "..", "tool", "setup", "steps");

/** 단계 소스의 secretNames 목록 — 1번 그룹 = 대괄호 안 글자. */
const STEP_SECRET_NAMES_PATTERN = /secretNames: <String>\[([^\]]*)\]/g;

/** 대괄호 안의 작은따옴표 secret 이름 — 1번 그룹 = 이름. */
const QUOTED_SECRET_NAME_PATTERN = /'([A-Z0-9_]+)'/g;

/** 단계 클래스의 provider token 상수 — 1번 그룹 = token. */
const STEP_TOKEN_PATTERN = /static const String token = '([a-z]+)';/;

/** `defineSecret("<이름>")` 호출 — 따옴표 인자만 잡는다(주석의 `defineSecret()` 제외). */
const DEFINE_SECRET_PATTERN = /defineSecret\("([A-Z0-9_]+)"\)/g;

/**
 * 디렉터리 아래 `.ts` 파일 경로를 재귀로 모은다.
 *
 * @param {string} dir 시작 디렉터리.
 * @return {Array<string>} `.ts` 파일 경로 목록.
 */
function listTsFiles(dir: string): string[] {
  const files: string[] = [];
  for (const entry of readdirSync(dir, {withFileTypes: true})) {
    const path = join(dir, entry.name);
    if (entry.isDirectory()) {
      files.push(...listTsFiles(path));
    } else if (entry.name.endsWith(".ts")) {
      files.push(path);
    }
  }
  return files;
}

/**
 * `src/` 전체에서 `defineSecret("<이름>")` 으로 선언한 secret 이름을 모은다.
 *
 * @return {Array<string>} 정렬한 secret 이름 목록 (중복 제거).
 */
function readDeclaredSecrets(): string[] {
  const names = new Set<string>();
  for (const file of listTsFiles(SRC_DIR)) {
    const text = readFileSync(file, "utf8");
    DEFINE_SECRET_PATTERN.lastIndex = 0;
    let match = DEFINE_SECRET_PATTERN.exec(text);
    while (match !== null) {
      names.add(match[1]);
      match = DEFINE_SECRET_PATTERN.exec(text);
    }
  }
  return [...names].sort();
}

/**
 * 위저드 provider 단계 소스에서 [secret 이름, 그 단계 token] 쌍을 모은다.
 *
 * `secretNames` 가 있는 단계 파일마다 그 파일의 `token` 상수를 소유 provider 로
 * 붙인다. token 상수가 없으면 빈 문자열이다(대조에서 위반으로 잡힌다).
 *
 * @return {Array<Array<string>>} [secret 이름, token] 쌍 목록.
 */
function readStepSecretOwners(): Array<[string, string]> {
  const pairs: Array<[string, string]> = [];
  const files = readdirSync(STEPS_DIR).filter((n) => n.endsWith("_step.dart"));
  for (const file of files.sort()) {
    const text = readFileSync(join(STEPS_DIR, file), "utf8");
    const token = STEP_TOKEN_PATTERN.exec(text)?.[1] ?? "";
    for (const list of text.matchAll(STEP_SECRET_NAMES_PATTERN)) {
      for (const name of list[1].matchAll(QUOTED_SECRET_NAME_PATTERN)) {
        pairs.push([name[1], token]);
      }
    }
  }
  return pairs;
}

/**
 * export 이름으로 배포 함수의 secret binding key 목록을 돌려준다.
 *
 * @param {string} name `src/index.ts` 의 export 이름.
 * @return {Array<string>} secret 이름 목록 (binding 이 없으면 빈 목록).
 */
function readSecretKeys(name: string): string[] {
  const exported = (myFunctions as Record<string, unknown>)[name] as
    | EndpointCarrier
    | undefined;
  const secrets = exported?.__endpoint?.secretEnvironmentVariables ?? [];
  return secrets.map((s) => s.key);
}

describe("배포 함수 manifest 대조 (Phase 17.3 D-08)", () => {
  it("T-173-DEPLOY-01: manifest 함수 집합 == index.ts export 집합 · 중복 0", () => {
    const all: string[] = [
      ...manifest.common,
      ...Object.values(manifest.providers).flat(),
      ...Object.values(manifest.email).flat(),
    ];
    // 중복 0 — 한 함수가 공통과 provider 에, 또는 두 provider 에 함께 있으면
    // 배포 명령이 같은 함수를 두 번 담거나 끈 provider 의 함수가 섞인다.
    expect(new Set(all).size).toBe(all.length);

    const exported = Object.keys(myFunctions).sort();
    expect([...all].sort()).toEqual(exported);
  });

  // eslint-disable-next-line max-len
  it("T-173-DEPLOY-02: providers 키 == google · apple · facebook · kakao · naver · line (순서)", () => {
    expect(Object.keys(manifest)).toEqual(["common", "providers", "email"]);
    expect(Object.keys(manifest.providers)).toEqual([
      "google",
      "apple",
      "facebook",
      "kakao",
      "naver",
      "line",
    ]);
  });

  // eslint-disable-next-line max-len
  it("T-173-DEPLOY-03: 공통 함수는 provider secret 0 · provider 함수의 secret 은 그 provider 소유뿐", () => {
    // 양성 대조 — binding 을 하나도 못 읽으면 아래 검사가 공허하게 통과한다.
    expect(readSecretKeys("linkKakaoProvider")).toEqual([
      "KAKAO_NATIVE_APP_KEY",
    ]);

    const violations: string[] = [];

    // 공통 함수: 맵에 있는 provider secret 이 하나도 없어야 한다. 맵 밖 secret 은
    // 사용자가 더한 공통 함수의 자기 secret 이라 허용한다(docs/guide.md
    // 「Cloud Functions 함수 더하기」 경로).
    for (const name of manifest.common) {
      for (const key of readSecretKeys(name)) {
        const owner = PROVIDER_SECRET_OWNER[key];
        if (owner !== undefined) {
          violations.push(
            `공통 함수 ${name} 가 ${owner} secret ${key} 를 묶었다`,
          );
        }
      }
    }

    // provider 함수: secret 은 전부 맵에 있고 그 provider 소유여야 한다.
    for (const [provider, names] of Object.entries(manifest.providers)) {
      for (const name of names) {
        for (const key of readSecretKeys(name)) {
          const owner = PROVIDER_SECRET_OWNER[key];
          if (owner === undefined) {
            violations.push(
              `${provider} 함수 ${name} 의 secret ${key} 가 소유 맵에 없다 — ` +
                "provider secret 을 더했다면 이 맵도 갱신한다",
            );
          } else if (owner !== provider) {
            violations.push(
              `${provider} 함수 ${name} 가 ${owner} secret ${key} 를 묶었다`,
            );
          }
        }
      }
    }

    expect(violations).toEqual([]);
  });

  // eslint-disable-next-line max-len
  it("T-175-DEPLOY-01: email 묶음 키 == kit · 이름은 common · providers 와 겹치지 않는다", () => {
    expect(Object.keys(manifest.email)).toEqual(["kit"]);
    const others = new Set([
      ...manifest.common,
      ...Object.values(manifest.providers).flat(),
    ]);
    const emailNames = Object.values(manifest.email).flat();
    // 양성 대조 — 묶음이 비면 아래 검사가 공허하게 통과한다.
    expect(emailNames).toEqual(
      expect.arrayContaining(["sendVerificationMail", "sendPasswordResetMail"]),
    );
    // kit 함수가 common 에 있으면 firebase 모드 프로젝트에도 배포된다(원칙 P).
    expect(emailNames.filter((name) => others.has(name))).toEqual([]);
  });

  it("T-175-DEPLOY-02: email 묶음 함수는 provider secret binding 0", () => {
    const violations: string[] = [];
    for (const [mode, names] of Object.entries(manifest.email)) {
      for (const name of names) {
        for (const key of readSecretKeys(name)) {
          const owner = PROVIDER_SECRET_OWNER[key];
          if (owner !== undefined) {
            violations.push(
              `email.${mode} 함수 ${name} 가 ${owner} secret ${key} 를 묶었다`,
            );
          }
        }
      }
    }
    expect(violations).toEqual([]);
  });

  // eslint-disable-next-line max-len
  it("T-173-DEPLOY-15 src 의 defineSecret 선언 · 소유 맵 · 위저드 단계 secretNames · token 이 서로 맞다", () => {
    const declared = readDeclaredSecrets();
    const mapped = Object.keys(PROVIDER_SECRET_OWNER).sort();
    const stepOwners = readStepSecretOwners();
    const stepNames = [...new Set(stepOwners.map(([name]) => name))].sort();
    // 양성 대조 — 선언 · 단계 secret 을 하나도 못 읽으면 아래 검사가 공허하게
    // 통과한다.
    expect(declared).toEqual(expect.arrayContaining(["KAKAO_ADMIN_KEY"]));
    expect(stepNames.length).toBeGreaterThanOrEqual(8);
    expect(stepOwners).toContainEqual(["KAKAO_ADMIN_KEY", "kakao"]);

    const violations: string[] = [];

    // 맵의 이름은 모두 코드에 선언돼 있어야 한다(지운 secret 이 맵에 남지 않게).
    for (const key of mapped) {
      if (!declared.includes(key)) {
        violations.push(`소유 맵의 ${key} 가 src/ 의 defineSecret 에 없다`);
      }
    }

    // 맵 밖 선언은 공통 함수만 묶는 사용자 secret 이어야 한다(docs/guide.md
    // 「Cloud Functions 함수 더하기」). provider 함수가 묶으면 T-173-DEPLOY-03 이,
    // 아무 함수도 묶지 않으면 여기서 잡는다 — 새 provider secret 의 맵 · 단계 누락.
    const providerFunctions = Object.values(manifest.providers).flat();
    for (const key of declared) {
      if (PROVIDER_SECRET_OWNER[key] !== undefined) {
        continue;
      }
      const isBoundByCommon = manifest.common.some((name) =>
        readSecretKeys(name).includes(key),
      );
      const isBoundByProvider = providerFunctions.some((name) =>
        readSecretKeys(name).includes(key),
      );
      if (!isBoundByCommon || isBoundByProvider) {
        violations.push(
          `src/ 의 ${key} 가 소유 맵에 없다 — provider secret 이면 ` +
            "provider 단계의 secretNames 와 PROVIDER_SECRET_OWNER 에 더한다",
        );
      }
    }

    // 소유 맵 키 = 위저드 단계 secretNames 합집합 · secret 마다 소유 provider =
    // 그 secret 을 등록하는 단계의 token.
    expect(mapped).toEqual(stepNames);
    for (const [name, token] of stepOwners) {
      const owner = PROVIDER_SECRET_OWNER[name];
      if (owner !== token) {
        violations.push(
          `${name} 의 소유 provider ${owner} 가 위저드 단계 token ${token} 와 다르다`,
        );
      }
    }

    expect(violations).toEqual([]);
  });
});
