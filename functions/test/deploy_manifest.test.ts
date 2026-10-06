/**
 * 배포 함수 목록(scripts/functions_manifest.json) 대조 (Phase 17.3 D-08 — see
 * ROADMAP.md).
 *
 * `scripts/deploy_functions.sh` 는 manifest 한 곳만 읽어 공통 함수 + 켠 provider
 * 함수를 배포한다. 그래서 manifest 가 `src/index.ts` 의 export 와 어긋나면
 * 새 함수가 배포되지 않거나 지운 함수가 명령에 남는다(T-173-12). 또 공통 함수가
 * provider secret 을 묶거나 provider 함수가 다른 provider 의 secret 을 묶으면,
 * 그 provider 를 꺼도 secret 프롬프트가 남아 계약 (4) 「끈 provider 의 함수
 * 배포 · secret 생성이 필요 없다」 가 깨진다(T-173-11).
 *
 * `firebase-functions/params` 는 mock 하지 않는다 — 실제 secret 이름이
 * `__endpoint.secretEnvironmentVariables` 에 남아야 binding 을 검사할 수 있다.
 * 앱 쪽 provider 키 대조는 `test/core/config/functions_manifest_contract_test.dart`.
 */

import {readFileSync} from "node:fs";
import {join} from "node:path";
import functionsTest from "firebase-functions-test";

const testEnv = functionsTest();

// index import 는 testEnv 초기화 이후 (firebase-functions-test 권장 패턴).
// eslint-disable-next-line import/first
import * as myFunctions from "../src/index";

afterAll(() => testEnv.cleanup());

/** manifest JSON 모양 — 최상위 키는 common · providers 두 개뿐이다. */
type Manifest = {common: string[]; providers: Record<string, string[]>};

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
 * `naver_secrets.ts` · `facebook_secrets.ts`. provider secret 을 더했다면 이 맵도
 * 갱신한다.
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
    ];
    // 중복 0 — 한 함수가 공통과 provider 에, 또는 두 provider 에 함께 있으면
    // 배포 명령이 같은 함수를 두 번 담거나 끈 provider 의 함수가 섞인다.
    expect(new Set(all).size).toBe(all.length);

    const exported = Object.keys(myFunctions).sort();
    expect([...all].sort()).toEqual(exported);
  });

  // eslint-disable-next-line max-len
  it("T-173-DEPLOY-02: providers 키 == google · apple · facebook · kakao · naver · line (순서)", () => {
    expect(Object.keys(manifest)).toEqual(["common", "providers"]);
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
    // 사용자가 더한 공통 함수의 자기 secret 이라 허용한다(매뉴얼 「Functions 추가
    // 절차」 경로).
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
});
