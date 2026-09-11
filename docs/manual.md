<!-- Phase 13 — see ROADMAP.md -->
---
last_updated: 2026-05-05
phases: [09 (Facebook), 11 (Cloud Functions + RC), 12 (Kakao Login), 13 (Naver Login)]
audience: starter kit 사용자 (clone 후 새 프로젝트 시작 시점)
---

# Flutter + Firebase Starter Kit 사용자 매뉴얼

이 문서는 starter kit 을 clone 한 사용자가 dev / stg / prod 3 flavor 모두에서
인증·푸시·원격설정·소셜 로그인 등을 동작시키기 위한 외부 콘솔 / 키 / 자산
설정 절차를 phase 별로 정리한 단일 진입점입니다.

각 단락은 **clone 후 즉시 동작 → starter kit 의 핵심 가치** 에 부합하도록
"왜" / "무엇을" / "어디서" / "흔한 실수" 4 축으로 작성되었습니다.

> **flavor 정책 (Phase 12 D-22, memory `project_firebase_dev_only`)**
>
> Starter kit 은 **dev flavor 만 실제 Firebase / 외부 서비스에 연결** 합니다.
> stg / prod 는 placeholder 만 포함하며, 사용자가 production 진입 시점에
> 자체 Firebase 프로젝트 + 외부 콘솔 등록 + 키 주입을 수행해야 합니다.

---

## 목차

0. [Initial Setup — Flavor Config 키 주입 (사전 작업, 모든 Phase 공통)](#initial-setup--flavor-config-키-주입-사전-작업-모든-phase-공통)
1. [Kakao Login (Phase 12)](#kakao-login-phase-12)
2. [Naver Login (Phase 13)](#naver-login-phase-13)
3. [LINE Login (Phase 14)](#line-login-phase-14)
4. [Brand Asset (Phase 13 D-52 — Kakao + Naver 통합)](#brand-asset-phase-13-d-52--kakao--naver-통합)
5. [Kakao 동의 항목 갱신 (Phase 13 D-56 retroactive)](#kakao-동의-항목-갱신-phase-13-d-56-retroactive)
6. [IdP 프로필 동기화 정책 (R10-FOLLOWUP)](#idp-프로필-동기화-정책-r10-followup)
7. [Phase 14~16 — Custom Token Provider 추가 가이드 (stub)](#phase-1416--custom-token-provider-추가-가이드-stub)
8. [Cloud Functions 배포 / Remote Config Kill Switch (Phase 11-04)](#cloud-functions-배포--remote-config-kill-switch-phase-11-04)
9. [Kakao Brand Asset 라이센스 / 출처 (Phase 12-07)](#kakao-brand-asset-라이센스--출처-phase-12-07)
10. [Brand Asset Management (Phase 13.1)](#brand-asset-management-phase-131)
11. [Account Linking & Withdrawal (Phase 16)](#account-linking--withdrawal)
12. [회원탈퇴 cleanup TODO (Phase 17)](#회원탈퇴-cleanup-todo-phase-17)
13. [Multi-Provider Account Linking (Phase 9.2)](#multi-provider-account-linking-phase-92)
14. [App Entry State Machine (Phase 10.2)](#app-entry-state-machine-phase-102)
15. [로그인 화면 구조 — 이메일 격하 (Phase 16.1)](#로그인-화면-구조--이메일-격하-phase-161)

---

## Initial Setup — Flavor Config 키 주입 (사전 작업, 모든 Phase 공통)

> **이 단락은 starter kit 을 fork / clone 한 직후 1회만 수행하는 사전 작업입니다.**
> 이후의 Phase 별 단락 (Kakao Login, Cloud Functions 등) 은 모두 이 단락에서
> 생성한 `config/{flavor}.json` 파일에 키를 주입하는 것을 전제로 합니다.

### 왜 — 시크릿 분리 정책 (D-22 + memory `project_starter_kit_config_secrets`)

Starter kit 의 `config/` 디렉토리는 dev / stg / prod 3 flavor 의 dart-define
설정 파일 (Firebase 프로젝트 ID, Google / Facebook / Kakao 시크릿 등) 을
관리합니다. 보안상 **실제 시크릿이 들어있는 `config/{flavor}.json` 은 git 에
commit 하지 않고**, placeholder 만 담은 `config/{flavor}.example.json` 만 tracked
파일로 유지합니다.

- `.gitignore` 에 `config/*.json` 패턴 + `!config/*.example.json` negation
  으로 자동 분리. 즉 `config/*.json 은 fork 사용자가 본인 키로 채워넣는 로컬
  전용 파일` 이고, `*.example.json` 만 git tracked.
- Fork 사용자는 본인 환경에서 `*.example.json` → `*.json` 으로 복사 후 본인
  키를 직접 입력. 이 파일은 commit 되지 않음.
- 기존 빌드 명령
  (`fvm flutter run --flavor=dev --dart-define-from-file=config/dev.json`) 은
  변경 없이 동작.

### 무엇을 — 3 단계 절차

#### 1단계 — `*.example.json` 을 본인 로컬 `*.json` 으로 복사

```bash
cp config/dev.example.json   config/dev.json
cp config/stg.example.json   config/stg.json
cp config/prod.example.json  config/prod.json
```

> dev flavor 만 우선 사용한다면 `config/dev.json` 만 복사해도 됨. stg/prod 는
> production 진입 시점에 별도 작업 (D-22 정책 — `project_firebase_dev_only`).

#### 2단계 — 각 `config/{flavor}.json` 의 placeholder 를 본인 키로 교체

`config/dev.json` 을 열고 다음 키들을 본인 환경 값으로 채웁니다.

| 키 | 값 출처 | 비고 |
|----|---------|------|
| `firebaseProjectId` | Firebase Console > 프로젝트 설정 > General | 본인 dev 프로젝트 ID |
| `googleServerClientId` | Google Cloud Console > APIs & Services > Credentials > OAuth 2.0 Client IDs > Web application | `flutterfire configure` 로 생성된 Firebase OAuth Web Client ID. iOS/Android 가 아닌 **Web** 용을 사용 (Phase 7 — Google Sign-In 정책) |
| `facebookAppId` | Facebook Developers Console > 내 앱 > 설정 > 기본 | 숫자 문자열 |
| `facebookClientToken` | Facebook Developers Console > 내 앱 > 설정 > 고급 > Client Token | |
| `kakaoNativeAppKey` | Kakao Developers Console > 내 애플리케이션 > 앱 설정 > 앱 키 > **네이티브 앱 키** | REST API 키 아님 (1번 단락 — Kakao Login 1단계 #6 OIDC 활성화 함께 참조) |
| `naverClientId` | Naver Developers Console > 본인 앱 > 개요 > **Client ID** | Phase 13 신규 (`## 2. Naver Login` 단락 참조) |
| `naverClientSecret` | Naver Developers Console > 본인 앱 > 개요 > **Client Secret** | Phase 13 D-60 — 현재 사용처 0건이지만 SDK init 의무 + Phase 17+ 확장 대비 |
| `naverUrlScheme` | Naver Developers Console > API 설정 > iOS 환경 > **URL Scheme** | iOS 빌드는 추가로 `ios/Flutter/dev.xcconfig` 의 `NAVER_URL_SCHEME` 도 동일 값 주입 필요 |
| `appName` | (선택) 앱 표시 이름 — `StarterKit Dev` 기본값 | flavor 별 구분 |
| `appSuffix` | (선택) ApplicationId / BundleId suffix — `.dev` 기본값 | `flutter_native_splash` / Firebase 프로젝트 분리 |
| `splashMinDurationMs` | (선택) 스플래시 최소 노출 시간 — `2000` 기본값 | UX 조정용 |
| `enabledAuthProviders` | (선택) CSV — `google,apple,facebook,kakao,naver` 기본값 | Phase 11 D-26 정책: 정적 false 우위, RC 로 disable 만 가능 (Phase 13 에서 `,naver` 추가) |

> 각 키의 콘솔 등록 절차 (앱 생성, redirect URI, 키 해시 등) 는 본 매뉴얼의
> Phase 별 단락 (Phase 12 = Kakao, Phase 13 = Naver, Phase 14 = LINE,
> Phase 15 = Yahoo!JP) 을 참조.

#### 3단계 — iOS xcconfig 별도 주입 (Kakao 만)

iOS 빌드는 `ios/Flutter/{flavor}.xcconfig` 파일을 통해 빌드 타임 변수
(Bundle Identifier, Display Name, REVERSED_CLIENT_ID, Facebook 키, Kakao
Native App Key 등) 를 주입합니다. 실제 시크릿이 포함되므로 `config/*.json`
과 동일한 `.example` 패턴으로 분리되어 있습니다 (Phase 12.1 R1 — D-36).

Initial Setup 절차 (clone 직후 1회):

```bash
cp ios/Flutter/dev.example.xcconfig   ios/Flutter/dev.xcconfig
cp ios/Flutter/stg.example.xcconfig   ios/Flutter/stg.xcconfig
cp ios/Flutter/prod.example.xcconfig  ios/Flutter/prod.xcconfig
```

각 파일을 열어 placeholder 를 본인 값으로 교체합니다:

- `KAKAO_NATIVE_APP_KEY` — Kakao Developers Console > 내 애플리케이션 > 앱 설정 >
  앱 키 > **네이티브 앱 키** (본 매뉴얼 `## 1. Kakao Login` 단계 참조)
- `NAVER_URL_SCHEME` — Naver Developers Console > API 설정 > iOS 환경의 **URL Scheme**
  (Phase 13 신규, `## 2. Naver Login` 단계 참조). `config/dev.json` 의 `naverUrlScheme`
  과 동일 값.
- `REVERSED_CLIENT_ID` — `ios/Runner/GoogleService-Info.plist` 의 `REVERSED_CLIENT_ID`
  값 (Phase 7 — Google Login. `flutterfire configure` 가 생성)
- `FACEBOOK_APP_ID` — Facebook Developers Console > 내 앱 > 설정 > 기본 (숫자 문자열)
- `FACEBOOK_CLIENT_TOKEN` — Facebook Developers Console > 내 앱 > 설정 > 고급 > Client Token

`ios/Flutter/{dev,stg,prod}.xcconfig` 파일은 `.gitignored` 되어 있어 commit 되지
않습니다 (`*.example.xcconfig` 만 tracked). 신규 키를 추가할 때는 `*.example.xcconfig`
의 placeholder 도 함께 갱신하여 fork 사용자가 동일한 setup 절차로 시작할 수 있도록
유지합니다.

> 참고: `ios/Flutter/Debug-dev.xcconfig` 등 다른 xcconfig 파일은 본 분리 정책의
> 영향을 받지 않습니다 (`.gitignore` 의 explicit 3 라인 패턴 — RESEARCH §R1 Landmine).

### 4단계 — `functions/` 패키지 매니저 활성화 (corepack + pnpm)

Cloud Functions (`functions/` 디렉토리) 는 **pnpm + corepack** 을 사용합니다.
clone 직후 1회만 수행:

```bash
corepack enable                # Node 22+ 에 ship, 한 번만 실행
cd functions
pnpm install                   # pnpm-lock.yaml 기반 reproducible install
```

`functions/package.json` 의 `packageManager` 필드 (`pnpm@x.y.z`) 가 corepack
으로 자동 핀됩니다. 따라서 별도 `npm install -g pnpm` 불필요. 시스템 pnpm 이
이미 설치돼 있어도 corepack 의 핀 버전이 우선합니다.

> Phase 11 (Cloud Functions) / Phase 12 (Kakao) / Phase 13 (Naver) 등의
> 배포 단락에서 사용하는 `pnpm <script>` 명령은 모두 본 단계의 활성화를
> 전제합니다.

### 흔한 실수

- **`config/dev.json` 을 `git add` 하려는 시도** — `.gitignore` 가 차단해도
  `git add -f config/dev.json` 으로 강제 추가 가능. 절대 강제 추가 금지.
  `git status --ignored config/` 로 항상 ignored 상태 확인.
- **`config/dev.example.json` 에 본인 키를 입력** — example 파일은 placeholder
  유지. 본인 키는 반드시 `config/dev.json` (untracked) 에만.
- **빌드 명령 변경 시도** — `--dart-define-from-file=config/dev.json` 그대로
  유지. `*.example.json` 으로 빌드하면 SDK 초기화 단계에서 "Invalid app key"
  에러 (Kakao / Facebook) 또는 Firebase 프로젝트 매칭 실패.
- **placeholder 그대로 빌드 후 "왜 로그인 안 되지" 디버깅** — Kakao Login
  1단계 #6 OIDC 활성화 누락 (Pitfall 1) 보다 흔한 trivial 실수. 빌드 전
  `cat config/dev.json` 으로 placeholder 가 모두 교체됐는지 1차 확인.
- **실제 키가 든 `google-services.json` 재생성본을 강제 `git add`** —
  `android/app/src/{stg,prod}/google-services.json` 2종은 빌드 게이트 통과용
  placeholder 로 **tracked** 되어 있어 (`.gitignore` negation), 실 키 재생성본이
  그대로 커밋 대상이 된다. `scripts/git-hooks/pre-commit` 가드가 Google API 키
  접두사 또는 placeholder `project_number` 소실을 감지해 차단하므로 우회하지 말
  것. 정상 해제 경로는 `./scripts/firebase-configure.sh <flavor>` 가 자동으로
  거는 `git update-index --skip-worktree <path>` 이고, placeholder 자체를
  의도적으로 고칠 때만 `--no-skip-worktree` 로 일시 해제한다.
- **stg/prod 가 빌드된다고 Firebase 가 연결됐다고 오인** — 위 placeholder 덕분에
  fresh clone 직후에도 `--flavor stg` / `--flavor prod` Android 빌드는 통과하지만,
  값은 전부 더미(`placeholder-stg` / `000000000000` 등)라 런타임은
  `initializeFirebase()` 가 `false` 를 반환하는 미초기화 모드다. 실 연결은
  Firebase Console 에서 프로젝트를 만든 뒤
  `./scripts/firebase-configure.sh stg` 를 실행해야 이뤄진다.

### Cloud Functions region 변경 (`functionsRegion`)

`config/{flavor}.json` 의 `functionsRegion` 키가 Flutter 앱이 호출할 Cloud
Functions region 을 결정합니다. 기본값은 `asia-northeast3` (서울) 이며, 키를
생략하면 그 기본값이 쓰입니다.

**서울 외 region 을 쓰려면 반드시 두 곳을 함께 바꿔야 합니다.**

| # | 위치 | 값 |
|---|------|----|
| 1 | `config/{flavor}.json` 의 `functionsRegion` | 클라이언트가 호출할 region |
| 2 | `functions/src/shared/region.ts` 의 `REGION` | 함수가 배포될 region |

두 값이 어긋나면 **빌드도 analyze 도 통과하고, 런타임에 callable 호출이
`not-found` 로 실패**합니다 (Custom Token 로그인 4종 · 회원탈퇴가 모두 막힙니다).
증상만으로는 원인을 찾기 어려우므로 변경 시 반드시 쌍으로 처리하세요.

변경 후에는 함수를 새 region 에 다시 배포해야 하며, 구 region 의 함수는 별도로
삭제해야 합니다 (`firebase functions:delete <name> --region <old-region>`).

> `test/core/config/app_config_test.dart` 의 "Dart 기본값이
> `functions/src/shared/region.ts` 의 REGION 과 일치한다" 테스트가 **기본값**의
> 드리프트를 잡아 줍니다. 다만 `config/{flavor}.json` 은 gitignore 대상이라
> 테스트가 검사하지 않으므로, 실제 주입값과 TS 의 일치는 사용자 책임입니다.

---

## Kakao Login (Phase 12)

Kakao 로그인은 Custom Token 방식으로 구현되어 있습니다. 사용자가 KakaoTalk
설치 단말에서는 1-tap 로그인 (`loginWithKakaoTalk`), 미설치 단말에서는 카카오
계정 웹뷰 fallback (`loginWithKakaoAccount`) 로 자동 분기합니다.

OIDC ID Token 을 Cloud Function (`kakaoCustomToken`, asia-northeast3) 이
자체 검증 (jose + JWKS singleton) 후 Firebase Identity Index 에 등록하고
Firebase Custom Token 을 발급, 클라이언트가 `signInWithCustomToken` 으로
세션을 시작합니다.

### 1단계 — Kakao Developer Console 앱 등록

콘솔: <https://developers.kakao.com/console/app>

1. **앱 생성 (dev flavor)**
   - "내 애플리케이션" → "애플리케이션 추가하기"
   - 앱 이름 / 사업자명 입력 (개인 사업자도 가능, 미입력 시 개인 모드)

2. **플랫폼 등록 — Android**
   - "내 애플리케이션 > 앱 설정 > 플랫폼" → Android 추가
   - 패키지명: `com.example.flutter_starter_kit.dev` (dev flavor — 본 starter
     kit 의 ApplicationId. `android/app/build.gradle.kts` 에서 확인)
   - **키 해시** 등록 (필수 — 미등록 시 `Invalid key hash` 런타임 에러):
     ```bash
     # debug 키 해시
     keytool -exportcert -alias androiddebugkey \
       -keystore ~/.android/debug.keystore \
       -storepass android -keypass android \
       | openssl sha1 -binary | openssl base64

     # release 키 해시 (production 빌드 전 등록)
     keytool -exportcert -alias <your-alias> \
       -keystore <your-keystore.jks> \
       | openssl sha1 -binary | openssl base64
     ```
     자세한 절차는 Kakao 공식 문서 참조:
     <https://developers.kakao.com/docs/latest/ko/getting-started/sdk-android#step3-add-key-hash>

3. **플랫폼 등록 — iOS**
   - 같은 화면에서 iOS 추가
   - 번들 ID: `com.example.flutterStarterKit.dev` (dev flavor — iOS 의
     CFBundleIdentifier. `ios/Flutter/dev.xcconfig` 의 `BUNDLE_ID_SUFFIX`
     기준)

4. **카카오 로그인 활성화**
   - "내 애플리케이션 > 제품 설정 > 카카오 로그인" → "활성화 설정" ON

5. **Redirect URI 등록**
   - 같은 화면 하단의 "Redirect URI" 섹션
   - 형식: `kakao{nativeAppKey}://oauth` (예: `kakao1234567890abcdef://oauth`)
   - **흔한 실수**: nativeAppKey 가 아닌 REST API 키를 넣는 경우 — 반드시
     "앱 키 > 네이티브 앱 키" 값 사용

6. **OpenID Connect (OIDC) 활성화 — ⚠ Pitfall 1**
   - "내 애플리케이션 > 제품 설정 > 카카오 로그인 > 보안" → "OpenID Connect
     활성화" 토글 **ON**
   - **활성화 누락 시:** `OAuthToken.idToken` 이 항상 null → AuthRepository 가
     `ServiceUnavailable` 반환 → LoginScreen 의 FormErrorBanner 가
     `errorServiceUnavailable` 표시. silent failure 처럼 보이는 가장 흔한
     원인.

7. **동의항목 설정 (Phase 12 D-03)**
   - "내 애플리케이션 > 제품 설정 > 카카오 로그인 > 동의항목"
   - **닉네임 (`profile_nickname`)** — "필수 동의" 로 설정
   - **카카오계정 이메일 (`account_email`)** — "필수 동의" 로 설정
   - 그 외 항목 (프로필 사진, 생일, 성별 등) 은 starter kit 기본 범위 외
     (필요 시 사용자가 추가)

### 2단계 — `config/dev.json` 키 주입

콘솔 등록 완료 후 발급받은 두 키를 starter kit 의 dev flavor config 에
주입합니다.

`config/dev.json`:
```json
{
  "enabledAuthProviders": "google,apple,facebook,kakao",
  "kakaoNativeAppKey": "여기에_네이티브_앱_키_붙여넣기"
}
```

- **kakaoNativeAppKey** — "내 애플리케이션 > 앱 설정 > 앱 키 > 네이티브 앱 키"
- **REST API 키** 는 `config/dev.json` 에 넣지 마세요 — 다음 4단계의
  Firebase Secret Manager 로만 주입.

iOS xcconfig (`ios/Flutter/dev.xcconfig`) 도 동일 키를 별도 빌드 설정으로
주입해야 합니다 (Phase 12-01 산출):
```
KAKAO_NATIVE_APP_KEY=여기에_네이티브_앱_키_붙여넣기
```
(따옴표 없이 = 뒤에 값만)

> **stg / prod 는?** dev 와 동일한 절차로 사용자 자체 Kakao 앱을 별도 등록
> + 키 주입. starter kit 의 stg/prod config 는 placeholder 만 포함합니다
> (D-22 — `project_firebase_dev_only` 정책).

### 3단계 — Firestore 보안 규칙 배포 (Phase 12-06)

starter kit 의 `firestore.rules` (Phase 12-06 산출) 를 dev Firebase
프로젝트에 배포합니다. 이 규칙은:

- `identity_index/{document}` 컬렉션 클라이언트 read/write 전면 차단 (D-14)
  → Cloud Function (Admin SDK) 만 우회 가능. 다른 사용자의 Kakao→UID
  매핑을 클라이언트가 직접 read 하지 못하도록 차단.
- `users/{uid}` self-only 임시 규칙 — 사용자가 자기 문서만 read/write 가능.
  Phase 18 정식 ruleset 일반화 대기.

```bash
# Firebase CLI 로그인 (최초 1회)
firebase login

# dev 프로젝트 alias 사용
firebase use dev

# 배포
firebase deploy --only firestore:rules
```

기대 응답:
```
✔ Deploy complete!
```

### 4단계 — KAKAO_NATIVE_APP_KEY Secret 등록 (Phase 11-05 / 12-02 / 12.1 R4)

Cloud Function `kakaoCustomToken` 이 Kakao OIDC ID Token 의 audience 검증에
사용하는 키를 Firebase Secret Manager 에 등록합니다 (코드 / config 파일에 평문
저장 금지).

> ⚠ **Secret 값 = Kakao 네이티브 앱 키** (REST API 키 아님). Native SDK 흐름의
> OAuth `client_id` 가 native app key 라서 ID Token 의 `aud` claim 도 native app
> key. Phase 12.1 R4 cutover 에서 historical 한 misleading naming
> (`KAKAO_REST_API_KEY`) 을 제거하고 secret 이름과 실제 값의 의미를 일치시켰습니다.
> (`project_oauth_custom_token_pitfalls.md` Pitfall #1 참조.)

```bash
firebase use dev
firebase functions:secrets:set KAKAO_NATIVE_APP_KEY
# prompt:
#   ? Enter a value for KAKAO_NATIVE_APP_KEY: <여기에 네이티브 앱 키 붙여넣기 + Enter>
#   (config/dev.json 의 kakaoNativeAppKey 와 동일 값)
```

기대 응답:
```
✔ Created a new secret version projects/.../secrets/KAKAO_NATIVE_APP_KEY/versions/1
```

확인:
```bash
firebase functions:secrets:access KAKAO_NATIVE_APP_KEY
```

> Cloud Function 의 `defineSecret('KAKAO_NATIVE_APP_KEY')` 가 배포 시점에
> 자동으로 secret 을 함수 환경변수로 주입합니다 (Phase 11 D-05 패턴). jose
> `jwtVerify` 의 audience 옵션으로 사용되어 ID Token 의 `aud` claim 과 일치
> 검증.

> **기존 사용자 안내 (Phase 12.1 hotfix 적용 전 secret 을 set 한 경우):** Phase
> 12.1 R4 cutover 절차 (Plan 12.1-04 + 12.1-08) 에서 자동 처리됩니다 —
> `KAKAO_NATIVE_APP_KEY` 신규 set → deploy → dev 검증 → 구
> `KAKAO_REST_API_KEY` destroy. 신규 사용자는 본 단락의
> `KAKAO_NATIVE_APP_KEY` 만 set 하면 됩니다 (구 secret 명명 미존재).

### 5단계 — App Check Debug Provider 등록 — ⚠ Pitfall 6

Cloud Function `kakaoCustomToken` 은 `enforceAppCheck: true` 로 abuse 방어
중입니다 (Phase 12 D-11). dev flavor 실 단말 검증 시 debug 토큰을 Firebase
Console 에 등록해야 통과합니다.

**절차:**

1. dev 빌드 실 단말 첫 실행:
   ```bash
   fvm flutter run --flavor=dev --dart-define-from-file=config/dev.json
   ```

2. 로그에서 debug 토큰 추출:
   - **Android**: `adb logcat | grep "App Check"` 또는 Android Studio Logcat
     에서 `Enter this debug secret into the Firebase Console` 다음 줄의 UUID
   - **iOS**: Xcode Console 에서 동일 메시지 검색

3. Firebase Console 등록:
   - <https://console.firebase.google.com> → dev 프로젝트
   - 좌측 "빌드 > App Check" → 앱 선택 (Android / iOS)
   - "디버그 토큰 관리" → "디버그 토큰 추가" → 추출한 UUID 붙여넣기

4. 등록 후 다음 앱 실행부터 `enforceAppCheck` 통과 — Cloud Function 호출
   401 unauthenticated 에러 사라짐.

**누락 시 증상:** Cloud Function 호출이 401 → AuthRepository 가
`ServiceUnavailable` Failure → LoginScreen 의 FormErrorBanner 에
`errorServiceUnavailable` 표시. Pitfall 1 (OIDC 누락) 과 동일 증상이라
구분 어려움 — Cloud Logging 에서 `app_check_check_failed` warn 확인.

> **Production:** Play Integrity (Android) / DeviceCheck (iOS) 정식 활성화
> 의무. Phase 18 보안 일반화 단계에서 자동화 검토 — 본 starter kit 의
> 현재 코드 (`enforceAppCheck: true`) 그대로 호환.

### 6단계 — Cloud Function 배포

Phase 12-02 산출 `kakaoCustomToken` 함수를 dev Firebase 프로젝트
(asia-northeast3) 에 배포합니다.

```bash
cd functions
pnpm install           # 최초 1회 (corepack 활성화는 0단락의 4단계 참조)
pnpm run lint          # 0 errors 확인
pnpm run build         # tsc OK 확인
pnpm test              # jest 14 PASS 확인 (3 suites)

# 배포
firebase use dev
firebase deploy --only functions:kakaoCustomToken
```

기대 응답:
```
✔ functions[kakaoCustomToken(asia-northeast3)] Successful update operation.
```

확인 — Firebase Console:
- "빌드 > Functions" → `kakaoCustomToken` 함수 row → region = `asia-northeast3`
  + "활성" 상태

### 7단계 — 검증 (실 단말 UAT)

dev 빌드 실 단말 + KakaoTalk 설치 단말 + 미설치 단말 양쪽에서:

1. 빌드:
   ```bash
   fvm flutter run --flavor=dev --dart-define-from-file=config/dev.json
   ```

2. LoginScreen → "카카오 로그인" 버튼 (노란 #FEE500, 검정 라벨, KakaoTalk
   말풍선 아이콘) 표시 확인.

3. 탭 → KakaoTalk 설치 시 KakaoTalk app-to-app 1-tap, 미설치 시 카카오계정
   웹뷰 (Custom Tab / SFSafariViewController) → "동의하고 계속하기".

4. 인증 성공 → Home 진입 + EnvironmentInfoScreen Account 카드 → "로그인
   수단: 카카오" 라벨 확인.

5. Firebase Console > Firestore → `identity_index/kakao:{kakaoUserId}` 문서
   존재 + `firebaseUid` / `linkedAt` / `lastSeenAt` 확인.

6. `users/{uid}` 문서 → `linkedProviders` 배열에
   `{providerId: "kakao", providerUserId: "..."}` 포함 확인.

7. Cloud Logging > Functions > kakaoCustomToken → `event:
   "kakao_custom_token_issued"` + `uid` + `isNewUser` 로그 (idToken 본문 /
   kakao_account 본문 미노출 확인 — Phase 12 D-08 PII 정책).

### 알려진 결함 / 주의사항 (Pitfall 1 / 6 / 11)

#### ⚠ Pitfall 1 — OIDC 활성화 누락

- **증상:** 로그인 시도 시 LoginScreen 에서 즉시 `errorServiceUnavailable`
  배너. 어떤 외부 SDK 호출도 일어나지 않은 것처럼 보임.
- **원인:** `OAuthToken.idToken` 이 null. Kakao Developer Console 의
  "OpenID Connect 활성화" 토글이 OFF.
- **해결:** 1단계 #6 절차 재확인 + 토글 ON 후 앱 재실행.

#### ⚠ Pitfall 6 — App Check Debug 토큰 미등록

- **증상:** Pitfall 1 과 동일하게 `errorServiceUnavailable` 배너.
- **원인:** Cloud Function `kakaoCustomToken` 호출이 401 unauthenticated.
  Cloud Logging 의 `app_check_check_failed` warn 으로 구별.
- **해결:** 5단계 절차 재확인 + Firebase Console 에 debug 토큰 등록 후 앱
  재실행.

#### ⚠ Pitfall 11 — Apple Custom Tab 결함과 무관

- Apple Sign-In 의 Android Custom Tab 결함 (memory
  `project_android_apple_signin_known_issue`) 이 Kakao 에도 적용된다는
  오해가 있을 수 있습니다.
- **무관함:** Kakao SDK 는 자체 Custom Tab 자동 닫힘 처리 + KakaoTalk
  app-to-app 처리 — 별도 결함 없음.
- 다만 Kakao 웹뷰가 인증 후 닫히지 않는 경우는 **Console 의 Redirect URI
  누락** (1단계 #5) 또는 **앱 키 / 패키지명 / 키 해시 mismatch** 가 원인 —
  Kakao 자체 SDK 결함 아님.

#### 회원탈퇴 cleanup TODO (Phase 17 까지 미구현)

- 현재 회원탈퇴 시 `identity_index/kakao:{id}` 문서가 잔존합니다 — Phase 17
  의 Account Linking 일반화 단계에서 transaction 기반 cleanup 도입 예정.
- 잔존 문서가 즉시 보안 결함은 아니지만, 같은 Kakao 계정을 다른 Firebase
  UID 에 재등록하려 할 때 first-write-wins 정책 (D-12) 으로 기존 매핑이
  우선됩니다. starter kit 사용자가 "회원탈퇴 후 즉시 재가입" 시나리오
  검증 시 인지 필요.

---

## Naver Login (Phase 13)

Naver 로그인은 Custom Token 방식 + REST `/v1/nid/me` 검증으로 구현되어 있습니다.
Phase 12 의 Kakao (OIDC ID Token JWT 검증) 와 같은 인프라 위에 검증 라인만 다른
구조 — Cloud Function `naverCustomToken` 이 Naver access_token 을 Bearer 로
`https://openapi.naver.com/v1/nid/me` 호출 → `resultcode='00'` + `response.id`
추출 → Identity Index 등록 → `admin.auth().createCustomToken(uid)` 발급, 클라이언트가
`signInWithCustomToken` 으로 세션을 시작합니다.

`naver_login_sdk` (publisher: lagerstroemia.net, v3.2.1) 가 Naver 앱 설치
단말에서는 1-tap (앱 → 동의 → callback), 미설치 단말에서는 자체 웹뷰 fallback 으로
자동 분기합니다.

### 1단계 — Naver Developers Center 가입 + 앱 등록

콘솔: <https://developers.naver.com>

1. 접속 → 가입 (이미 가입된 경우 로그인) → 우측 상단 "Application > 애플리케이션
   등록 (API 이용신청)"
2. 앱 이름 입력 + 사용 API 에서 **"네이버 로그인"** 선택

### 2단계 — Client ID + Client Secret 확인

1. 등록 완료 후 **"내 애플리케이션 > 본인 앱 > 개요"** 탭에서 다음 두 키 확인:
   - `Client ID`
   - `Client Secret`
2. 양 키 메모 (다음 단계에서 사용 — `config/dev.json` 의 `naverClientId` /
   `naverClientSecret` 에 주입).

### 3단계 — Naver Login Open API Service Environment 추가

"내 애플리케이션 > 본인 앱 > **API 설정**" 탭에서:

1. **iOS 환경 등록**:
   - Bundle ID 입력: `com.slimpumpkin.flutter_starter_kit.dev` (dev flavor —
     본 starter kit 의 iOS Bundle Identifier. Xcode 의 Build Settings >
     Product Bundle Identifier 또는 `ios/Flutter/dev.xcconfig` 기준)
   - **iOS URL Scheme** 입력 (snake/camelCase 권장 — 예:
     `flutterStarterKitDev`). 이 값은 `config/dev.json` 의 `naverUrlScheme`
     + `ios/Flutter/dev.xcconfig` 의 `NAVER_URL_SCHEME` 양쪽에 동일하게
     주입해야 합니다.

2. **Android 환경 등록**:
   - Package Name: `com.slimpumpkin.flutter_starter_kit.dev` (dev flavor —
     `android/app/build.gradle.kts` 의 ApplicationId 와 정확히 일치)
   - 클래스 이름 (Activity): `com.slimpumpkin.flutter_starter_kit.MainActivity`
     (Phase 13 Plan 13-01 에서 `FlutterFragmentActivity` 로 마이그레이션됨 —
     Naver SDK 5.4.0+ Fragment 기반 BottomSheet 호환)
   - **Key Hash** 입력 (Kakao 와 동일 절차):
     ```bash
     # debug 키 해시
     keytool -exportcert -alias androiddebugkey \
       -keystore ~/.android/debug.keystore \
       -storepass android -keypass android \
       | openssl sha1 -binary | openssl base64

     # release 키 해시 (production 빌드 전)
     keytool -exportcert -alias <your-alias> \
       -keystore <your-keystore.jks> \
       | openssl sha1 -binary | openssl base64
     ```

### 4단계 — iOS / Android 키 해시 + Bundle ID 일치 검증

Naver Console 에 등록한 iOS Bundle ID 와 Xcode 의 `Product Bundle Identifier` 가
정확히 일치해야 인증 callback 이 앱으로 복귀합니다. 동일하게 Android Package
Name + Key Hash 도 정확히 일치 필요.

> **흔한 실수:** iOS URL Scheme 을 Naver Console 에 등록한 값과 다르게
> `ios/Flutter/dev.xcconfig` 의 `NAVER_URL_SCHEME` 에 입력. 인증 후 단말이
> Safari 에서 멈추거나 앱으로 복귀하지 않음.

### 5단계 — 동의 항목 활성화 (Phase 13 D-56)

"내 애플리케이션 > 본인 앱 > **API 설정**" 의 동의 항목 단락에서:

- **필수:**
  - `email` (이메일 주소)
  - `nickname` (별명)
- **선택:**
  - `profile_image` (프로필 사진) — Phase 13 D-56. 미래 Phase 17 (Account
    Linking 사용자 확인 다이얼로그) / Phase 18 (Cloud Storage 프로필 아바타)
    진입 시 활용 예정. 현재 Phase 13 단계 사용처 0건.
- **비활성:** 그 외 모든 항목 (CI / 휴대폰 번호 / 생일 / 성별 등) — starter kit
  기본 범위 외.

### 6단계 — `config/dev.json` 키 주입

콘솔에서 발급받은 3 키를 `config/dev.json` 에 주입합니다 (`config/dev.example.json`
이 본 키 placeholder 를 이미 가지고 있으므로 `cp` 후 본인 값으로 교체):

```json
{
  "enabledAuthProviders": "google,apple,facebook,kakao,naver",
  "naverClientId": "<발급받은 Client ID>",
  "naverClientSecret": "<발급받은 Client Secret>",
  "naverUrlScheme": "<발급받은 iOS URL Scheme>"
}
```

> **stg / prod 는?** dev 와 동일한 절차로 사용자 자체 Naver 앱을 별도 등록 +
> 키 주입. starter kit 의 stg/prod config 는 placeholder 만 포함합니다 (D-22).

### 7단계 — iOS xcconfig 갱신

iOS 빌드는 `ios/Flutter/dev.xcconfig` 의 `NAVER_URL_SCHEME` 을 빌드 타임 변수로
주입합니다 (`ios/Flutter/dev.example.xcconfig` 의 placeholder 를 본인 값으로 교체):

```
NAVER_URL_SCHEME = <Naver Console 에서 입력한 iOS URL Scheme>
```

(따옴표 없이 = 뒤에 값만. `config/dev.json` 의 `naverUrlScheme` 와 정확히 동일
값 사용.)

### 8단계 — Firebase Secret Manager 등록 (Phase 13 D-60)

Cloud Function `naverCustomToken` 이 D-60 정책으로 `defineSecret('NAVER_CLIENT_SECRET')`
를 의무 선언합니다. Phase 13 단계에서는 client_secret 사용처 0건 (Cloud Function
이 access_token 만 사용 — refresh / deauth API 미사용) 이지만, **secret 정책
일관성 + Phase 17+ 확장 대비** 로 미리 등록 필요:

```bash
firebase use <dev-project-id>
firebase functions:secrets:set NAVER_CLIENT_SECRET
# prompt:
#   ? Enter a value for NAVER_CLIENT_SECRET: <Client Secret 붙여넣기 + Enter>
#   (config/dev.json 의 naverClientSecret 와 동일 값)
```

기대 응답:
```
✔ Created a new secret version projects/.../secrets/NAVER_CLIENT_SECRET/versions/1
```

확인:
```bash
firebase functions:secrets:access NAVER_CLIENT_SECRET
```

> Cloud Function 의 `defineSecret('NAVER_CLIENT_SECRET')` 가 배포 시점에 자동으로
> 함수 환경변수로 주입합니다 (Phase 11 D-05 패턴). Phase 17+ 에서 Naver
> `/oauth2.0/token` (refresh) 또는 deauth API 진입 시 즉시 활용 가능.

### 9단계 — Cloud Function 배포

Phase 13-02 산출 `naverCustomToken` 함수를 dev Firebase 프로젝트
(asia-northeast3) 에 배포합니다.

```bash
cd functions
pnpm install           # 최초 1회 (corepack 활성화는 0단락의 4단계 참조)
pnpm run lint          # 0 errors 확인
pnpm run build         # tsc OK 확인
pnpm test              # jest 44 PASS 확인 (kakao 14 + naver 15 + 베이스라인 + retroactive)

# 배포
firebase use <dev-project-id>
firebase deploy --only functions:naverCustomToken
```

기대 응답:
```
✔ functions[naverCustomToken(asia-northeast3)] Successful update operation.
```

확인 — Firebase Console:
- "빌드 > Functions" → `naverCustomToken` 함수 row → region = `asia-northeast3`
  + "활성" 상태

### 10단계 — dev flavor 실 단말 검증

```bash
fvm flutter run --flavor dev --dart-define-from-file=config/dev.json -d <android-device-id>
```

- LoginScreen 의 **"네이버로 시작하기"** 버튼 (그린 #03A94D 배경 + 흰 'N' 로고
  — Phase 13.1 R1 정정 후 NAVER ID 로그인 BI; `## Brand Asset Management
  (Phase 13.1)` 단락 D-Note 참조)
  탭 → Naver 앱 설치 시 1-tap, 미설치 시 웹뷰 fallback → 사용자 동의 → 앱 복귀
- Home 진입 + EnvironmentInfoScreen 의 Account 섹션 — `linkedProviders` 에
  "네이버" 표시 확인
- iOS UAT 는 보류 — `.planning/todos/pending/2026-05-XX-ios-naver-uat-deferred.md`
  추적 (Phase 13 Decision #8 — iOS 단말 부재)

자세한 8 시나리오 검증 양식: `.planning/phases/13-naver-login/13-HUMAN-UAT.md`.

### Pitfall 정리 (Phase 13 RESEARCH §Pitfalls)

- **Pitfall 1 (Completer 다중 complete):** `naver_login_sdk` 가 callback 기반 →
  코드 측 `if (!completer.isCompleted)` 가드 필수. Plan 13-03 에서 정착, 사용자
  변경 의무 0건.
- **Pitfall 2 (race-fix logout 위치):** D-57 — `signInWithNaver` finally 블록의
  `_naverSdkClient.logout()` 호출은 `_socialLinkInProgress.end()` 직전 위치.
  Plan 13-03 정착, verifyInOrder 정적 가드 보유.
- **Pitfall 4 (response.id 부재):** Cloud Function 측 nullable 가드 (Plan 13-02).
- **Pitfall 7 (PII 로깅):** Cloud Function logger payload 는 `{event, uid,
  resultcode, status}` 만 — `response.email` / `response.nickname` /
  `response.profile_image` / `accessToken` 절대 로깅 금지 (D-51, jest sentinel
  regression 5종 회귀 가드).
- **Pitfall 10 (Android FlutterFragmentActivity):** Naver SDK 5.4.0+ Fragment
  기반 BottomSheet 호환 — `MainActivity.kt` 가 `FlutterFragmentActivity` 상속
  필수. Plan 13-01 정착.

---

<!-- Phase 14 — see ROADMAP.md -->

## LINE Login (Phase 14)

LINE 로그인은 Custom Token 방식 + OIDC ID Token JWT 검증 (Kakao 와 같은 path)
으로 구현되어 있습니다. Cloud Function `lineCustomToken` (asia-northeast3) 이
`jose + JWKS` 로 LINE ID Token 을 자체 검증 → Identity Index 등록 →
`admin.auth().createCustomToken(uid)` 발급, 클라이언트가 `signInWithCustomToken`
으로 세션을 시작합니다 (Phase 12 D-08 OIDC verifier helper 재사용).

`flutter_line_sdk` (publisher: LINE Corporation, ^2.7.2) 가 LINE 앱 설치 단말
에서는 1-tap (앱 → 동의 → callback), 미설치 단말에서는 Chrome Custom Tabs (Android)
/ ASWebAuthenticationSession (iOS) 웹뷰 fallback 으로 자동 분기합니다.

### 1단계 — LINE Developers Console Channel 생성

콘솔: <https://developers.line.biz/console/>

1. **Business ID 가입** (이미 가입된 경우 로그인) — LINE Business ID 는 본인
   LINE 모바일 계정과 별도. **이메일 + 비밀번호 옵션 권장** (개인 LINE 계정
   분리 — 검수 권한 / 멤버 추가 시 모바일 계정 oauth 가 트러블 발생).
2. **Provider 생성** — "Create" → "Provider" → 이름 입력 (예: `Flutter Starter Kit`).
3. **Login Channel 생성** — Provider 페이지 안의 "Create a new channel" →
   **"LINE Login"** 선택 → 다음 입력:
   - **Region:** `Japan` (LINE 본사 region, 기본 선택)
   - **Channel name:** 사용자 보이는 앱 이름 (예: `Flutter Starter Kit Dev`)
   - **Channel description:** 짧은 설명
   - **App type:** **`Mobile app`** 단독 체크 (Web app 체크 안 함 — 본
     starter-kit 은 Flutter 모바일 단독)
   - **Email:** 본인 이메일
   - 약관 동의 후 "Create"
4. **Channel ID / Channel Secret 확인** — 생성 직후 Channel 상세 페이지의
   "Basic settings" 탭에서 두 키 확인 + 메모:
   - `Channel ID` — 숫자 (예: `0000000000`) — 공개 키, `config/dev.json` 의
     `lineChannelId` 에 주입
   - `Channel Secret` — 영숫자 32자리 — 비공개 키, **Firebase Secret Manager
     로만** 주입 (단계 5)

### 2단계 — iOS Bundle ID + Android Package + SHA-1 등록

Channel 상세 페이지의 **"LINE Login"** 탭 (또는 "App settings") 으로 이동 후:

1. **iOS Bundle ID 등록**:
   - `iOS bundle ID` 입력: `com.slimpumpkin.flutterStarterKit.dev` (dev flavor
     — Xcode 의 Build Settings > Product Bundle Identifier 또는
     `ios/Flutter/dev.xcconfig` 의 `BUNDLE_ID_SUFFIX` 기준)
   - `iOS scheme` 입력: `line3rdp.com.slimpumpkin.flutterStarterKit.dev`
     (`line3rdp.` prefix + Bundle ID 그대로) — 본 값이 `Info.plist` 의
     `CFBundleURLTypes` 와 정확히 일치해야 callback 이 앱으로 복귀.
   - **iOS universal links:** **OFF** (D-LINE-20 — starter-kit dev 는 URL
     scheme 방식만. Universal Links 는 AASA 파일 호스팅 + Associated Domains
     capability 등록 의무이므로 production 진입 시 별도 확장).

2. **Android Package Name 등록**:
   - `Android package name` 입력: `com.slimpumpkin.flutter_starter_kit.dev`
     (`android/app/build.gradle.kts` 의 ApplicationId 와 정확히 일치)
   - `Android package signature` (SHA-1) 입력 (대문자 + 콜론 포함 형식):
     ```bash
     # debug SHA-1 (개발 단계)
     keytool -list -v \
       -keystore ~/.android/debug.keystore \
       -alias androiddebugkey \
       -storepass android -keypass android \
       | grep SHA1
     # → 출력 예: SHA1: 3F:63:50:2E:EC:9B:D9:C6:8E:A0:FA:28:88:11:D3:99:21:AF:8E:EA

     # release SHA-1 (production 빌드 전)
     keytool -list -v \
       -keystore <your-keystore.jks> \
       -alias <your-alias> \
       | grep SHA1
     ```

> **흔한 실수:** SHA-1 을 소문자 / 콜론 없이 입력. LINE Console 은 대문자 +
> 콜론 구분자 형식 (`3F:63:50:...`) 만 정확히 일치 검증 → 미일치 시 Android
> 1-tap 실패 (silent return + LINE 앱 deeplink 후 빈 화면 복귀).

### 3단계 — UAT 권한 절차 (Channel Status 처리)

> **중요 — Plan 14-05 emulator UAT 학습 (2026-05-19):**
>
> Channel 생성 직후 default status 는 **`Developing`** — 본 상태에서는 Provider
> Role 에 등록된 LINE 계정만 1-tap 로그인 가능합니다. 외부 사용자 시도 시
> 400 Bad Request `This channel is now developing status. User need to have
> developer role` 차단.

두 가지 옵션 중 **(A) Tester role 등록 (Recommended)**:

1. **Console > Provider** (Channel 페이지 아닌 **상위 Provider** 페이지) →
   **"Roles"** 탭 → **"Add member"**.
2. 본인 LINE 모바일 계정 ID 또는 이메일 입력 → 권한 **`Tester`** 선택 →
   "Send invite".
3. 본인 LINE 모바일 앱에서 LINE 측 invitation 알림 → "Accept".
4. Channel Status `Developing` 유지 (검수 trigger 회피 + dev 검증 일관).

**(B) Channel publish (Developing → Published)**: Channel 페이지 상단 toggle
또는 "Publish" 버튼 → 외부 사용자도 1-tap 가능. 단 LINE 정책상 production
검수 trigger 가능성 — dev 검증 단계 권장 X.

### 4단계 — OpenID Connect 활성화 (필수)

> **중요 — Plan 14-05 emulator UAT 학습:**
>
> OIDC 활성화 누락 시 LINE 권한 동의 화면 진입은 가능하나 "허용" 버튼이
> frozen (disable) → callback redirect 미도달 → Cloud Function 호출 0. 가장
> 흔한 silent-failure 원인.

1. Channel 페이지의 **"LINE Login settings"** 탭 (또는 별도 **"OpenID
   Connect"** 탭) 진입.
2. **`OpenID Connect`** 활성화 toggle 확인 — default disabled 가능성. 비활성
   상태이면 toggle ON.
3. **Save** 클릭 → 변경 즉시 반영.

> Cloud Function `lineCustomToken` 이 ID Token (`id_token`) 의 JWT
> (`iss / sub / aud / exp / nonce`) 를 jose + JWKS 로 검증하므로 OIDC 활성화는
> 의무 — access_token 단독으로는 검증 path 없음 (D-LINE-01 verifyToken endpoint
> 대안 미채택).

### 5단계 — Firebase Secret Manager 등록 + Cloud Function 배포

Cloud Function `lineCustomToken` 이 D-LINE-16 정책으로 1개 secret 선언
(`defineSecret('LINE_CHANNEL_ID')`). Channel ID 는 OIDC ID Token audience
검증 (`aud` claim) 의 정답값으로 runtime 시점에 의무 주입:

> **WR-04 (Phase 14 review 정정):** 이전 버전 manual 은 `LINE_CHANNEL_SECRET`
> 도 함께 등록하도록 안내했으나, Cloud Function 본문에서 사용처 0 건 +
> declaration 만으로 운영자가 deploy 전 1회성 더미 주입을 강제받는 friction
> 회피 위해 declaration 제거. Phase 17+ refresh / verify-token / revoke API
> 도입 시점에 `LINE_CHANNEL_SECRET` 재등록 + Cloud Function 본문 사용처
> 추가가 한 묶음으로 진행된다.

```bash
firebase use <dev-project-id>

# LINE_CHANNEL_ID 등록 (1단계에서 메모한 Channel ID 숫자)
firebase functions:secrets:set LINE_CHANNEL_ID
# prompt:
#   ? Enter a value for LINE_CHANNEL_ID: <Channel ID 붙여넣기 + Enter>
```

기대 응답:
```
✔ Created a new secret version projects/.../secrets/LINE_CHANNEL_ID/versions/1
```

확인:
```bash
firebase functions:secrets:get LINE_CHANNEL_ID
```

배포 — `lineCustomToken` 함수를 dev Firebase 프로젝트 (asia-northeast3) 에:

```bash
cd functions
pnpm install           # 최초 1회 (corepack 활성화는 Initial Setup 4단계 참조)
pnpm run lint          # 0 errors 확인
pnpm run build         # tsc OK 확인
pnpm test              # jest 22 PASS 확인 (line 14 + oidc_verifier 8)

# 배포
firebase use <dev-project-id>
firebase deploy --only functions:lineCustomToken
```

기대 응답:
```
✔ functions[lineCustomToken(asia-northeast3)] Successful update operation.
```

확인 — Firebase Console > "빌드 > Functions" → `lineCustomToken` row →
region = `asia-northeast3` + "활성" 상태.

### 6단계 — iOS / Android platform manifest 검증

본 starter-kit 의 `ios/Runner/Info.plist` 와 `android/app/src/main/AndroidManifest.xml`
는 Phase 14 Plan 14-05 가 이미 LINE 필수 entry 를 등록한 상태입니다 — fork
사용자 변경 의무 0건. 단 본인 Bundle ID 가 다르면 `Info.plist` 의
`CFBundleURLTypes` 의 `line3rdp.$(PRODUCT_BUNDLE_IDENTIFIER)` 가 build-time
변수 치환되므로 자동 일치 (수동 갱신 0).

**iOS — `ios/Runner/Info.plist` (Phase 14 Plan 14-05 산출, 변경 0):**
```xml
<key>CFBundleURLTypes</key>
<array>
  <dict>
    <key>CFBundleURLSchemes</key>
    <array>
      <string>line3rdp.$(PRODUCT_BUNDLE_IDENTIFIER)</string>
    </array>
  </dict>
</array>
<key>LSApplicationQueriesSchemes</key>
<array>
  <string>lineauth2</string>
</array>
```

> **흔한 실수:** `LSApplicationQueriesSchemes` 에 `line3rdp` 나 `line` 을
> 추가. flutter_line_sdk README 의 verbatim 은 **`lineauth2` 단일 entry** 만
> — 다른 값 추가 시 iOS 의 LINE 앱 detection 실패.

**Android — `android/app/src/main/AndroidManifest.xml` (Phase 14 Plan 14-05
산출, 변경 0):**
```xml
<queries>
  <package android:name="jp.naver.line.android" />
</queries>
```

> **흔한 실수:** Android 11+ package visibility 정책 누락. `<queries>` 부재
> 시 LINE 앱 설치된 단말에서도 1-tap path 미동작 → webview fallback 으로
> degrade (silent — 사용자는 차이를 못 느낌).

> flutter_line_sdk 가 Activity intent-filter 자동 처리 (직접 등록 0건).

### 7단계 — `config/dev.json` 키 주입

콘솔에서 발급받은 Channel ID 를 `config/dev.json` 에 주입합니다
(`config/dev.example.json` 이 placeholder 를 이미 가지고 있으므로 `cp` 후
본인 값으로 교체):

```json
{
  "enabledAuthProviders": "google,apple,facebook,kakao,naver,line",
  "lineChannelId": "<발급받은 Channel ID 숫자>"
}
```

- `Channel Secret` 은 `config/dev.json` 에 **넣지 마세요** — 5단계의
  Firebase Secret Manager 로만 주입 (PII / secret 격리 정책).

> **stg / prod 는?** dev 와 동일한 절차로 사용자 자체 LINE Channel 을 별도
> 등록 + 키 주입. starter-kit 의 stg/prod config 는 placeholder 만 포함합니다
> (D-LINE-19 — `project_firebase_dev_only` 정책 일관).

### 8단계 — dev flavor 실 단말 / emulator 검증

```bash
fvm flutter run --flavor dev --dart-define-from-file=config/dev.json -d <device-id>
```

- LoginScreen 의 **"LINE으로 시작하기"** 버튼 (그린 `#06C755` 배경 + 흰
  LINE 자상 — `BrandedSocialButton.line()`) 탭 → LINE 앱 설치 시 1-tap,
  미설치 시 Chrome Custom Tabs (Android) / ASWebAuthenticationSession (iOS)
  webview fallback → 사용자 동의 → 앱 복귀.
- Home 진입 + EnvironmentInfoScreen 의 Account 섹션 — `linkedProviders` 에
  "LINE" 표시 확인.
- Android UAT 8 시나리오: `.planning/phases/14-line-login/14-HUMAN-UAT.md`.
- iOS UAT 는 보류 — `.planning/todos/pending/2026-05-20-ios-line-uat-deferred.md`
  추적 (Phase 13 D-59 패턴 mirror).
- Android emulator UAT 도 일부 보류 — `.planning/todos/pending/2026-05-20-android-line-uat-deferred.md`
  추적 (Plan 14-05 UAT 학습: Tester role 등록 + OIDC 활성화 + LINE 앱
  설치 단말에서 app-to-app 1-tap A3 queries 검증).

### email permission 신청 절차 (선택 — Phase 17+ 책임 범위)

본 starter-kit 의 Phase 14 단계는 LINE scope = `openid + profile` 만 사용
(D-LINE-21 — email 회피). `user.email = null` 수용. Phase 17 (Account Linking)
이후 사용자 식별 강화 시 email scope 활성화 필요:

1. **신청:** LINE Console > Channel > "LINE Login settings" → "OpenID Connect"
   탭 → "Email address permission" → "Apply" 버튼 클릭 → 사용 목적 + 사용자
   안내 스크린샷 업로드 → LINE 검수 (수일~수 주 [ASSUMED] — 정확한 timeline
   은 LINE 공식 미공개). 참조:
   <https://developers.line.biz/en/docs/line-login/integrate-line-login/#applying-email-permission>
2. **승인 후 code 변경** (Phase 17+ 책임 — starter-kit Phase 14 단계 적용 X):
   - `lib/features/auth/data/line_sdk_client.dart` 의 `LoginOption` scopes
     에 `'email'` 추가
   - `functions/src/auth/line_custom_token.ts` 의 `typedPayload` type 에
     `email?: string` + `email_verified?: boolean` 추가
   - `userInfo.email` 설정 + `createCustomToken(uid, developerClaims: {email,
     email_verified})` 분기

### 비즈니스 인증 절차 (production 전환 시)

dev 단계는 LINE Console 의 본인 Tester 계정만 사용 가능. production 출시
시 LINE Console 의 다음 항목 추가 의무:

1. **사업자 등록증 / 회사 정보** — Provider Settings > "Company information"
   탭 → 회사명 / 사업자 등록번호 / 대표자명 / 주소 입력.
2. **사용자 약관 + Privacy Policy URL 호스팅** — Channel > "Basic settings"
   탭 → "Privacy policy URL" + "Terms of use URL" 등록. starter-kit 사용자가
   자체 도메인에 호스팅 후 URL 등록.
3. **Universal Links 확장** (선택, iOS UX 개선) — Apple Developer Console >
   App ID > Associated Domains capability 등록 + 자체 도메인에 AASA 파일
   호스팅 + LINE Console > iOS universal links ON. starter-kit dev only
   범위 외 (D-LINE-20).
4. **Channel publish** — Channel 페이지 상단 toggle Developing → Published.
   외부 사용자 1-tap 가능 (3단계 (B) 옵션).

### 19 locale 확장 절차

LINE 공식 가이드는 19 언어 (en/ja/ko/zh-Hans 등) verbatim 라벨을 제공.
starter-kit 의 Phase 14 단계는 3 locale (en/ko/ja) 만 채택 (`authLineSignIn`
ARB 키). 19 locale 확장 시 다음 절차:

1. **권위 출처 doc 참조:** `.planning/phases/14-line-login/14-LINE-LOCALE-REFERENCE.md`
   — LINE 공식 19 언어 verbatim 표 (D-LINE-09) + ARB 추가 절차 + 자상 변경
   0 invariant (모든 locale 이 동일 영문 LINE 자상 사용 — 자상은 brand
   단독 권위).
2. **ARB 신규 키 추가:** `lib/l10n/app_<locale>.arb` 에 `authLineSignIn`
   키 verbatim 추가 (예: `app_zh_Hans.arb` → `"authLineSignIn": "使用 LINE 登录"`).
3. **자상 변경 0 invariant:** `assets/brand/line/btn_signin_icon.svg` 단일
   파일 — locale 별 분기 디렉토리 (`assets/brand/line/<locale>/`) 생성 절대
   금지 (LINE BI policy — 자상은 영문 LINE 단일 source).
4. **flutter gen-l10n 자동 호출** + 위젯 회귀 테스트 (BrandedSocialButton.line
   golden) 확인.

### Pitfall 정리 (Phase 14 RESEARCH §Pitfalls)

- **Pitfall 1 (idToken null 가드):** `LineSdkClient.signIn` 본문이
  `LineSDK.instance.login(...)` 결과 `accessToken.idToken` null 가드 필수
  (`if (idToken == null) return null`). null 일 때 `LoginResult.cancelled`
  (사용자 권한 거절) 패턴 — Plan 14-05 정착.
- **Pitfall 2 (race-fix logout 위치):** D-LINE-57 — `signInWithLine` finally
  블록의 `_lineSdkClient.logout()` 호출은 모든 path (성공 / cancel / error /
  timeout) 에서 호출 (Phase 13 WR-01-iter2 보안 우선 정책 mirror). Plan
  14-05 정착, verifyInOrder 정적 가드 보유.
- **Pitfall 3 (nonce SHA256 hashing):** 클라이언트가 raw nonce 생성
  (`Random.secure 16-byte`) → SHA256 해시 후 LINE SDK 에 전달 → Cloud Function
  이 ID Token 의 `nonce` claim 과 raw nonce SHA256 비교 (Phase 12 D-04
  mirror). 단계 미스매치 시 unauthenticated.
- **Pitfall 4 (LINE Console OIDC 활성화 누락):** 4단계 OIDC toggle OFF →
  consent 화면 "허용" 버튼 frozen → silent failure. 가장 흔한 신규 사용자
  trap.
- **Pitfall 5 (Android `<queries>` 누락):** Android 11+ package visibility
  정책 누락 시 LINE 앱 설치 단말에서도 app-to-app 1-tap 미동작 → webview
  fallback degrade (사용자 silent).
- **Pitfall 6 (LINE_CHANNEL_ID config 미주입):** `config/dev.json` 의
  `lineChannelId` placeholder 미교체 시 client SDK init 단계에서 silent
  failure (LineSDK 가 빈 channelId 로 init → login 호출 시 400).
- **Pitfall 7 (Android minSdk < 24):** flutter_line_sdk 가 minSdk 24 요구
  (A8 verified). Flutter 3.41.4 의 flutter.minSdkVersion 가 이미 24 →
  starter-kit 변경 0. 사용자가 minSdk 23 이하로 downgrade 시 LINE 1-tap
  실패.
- **Pitfall 8 (LINE 인증 후 앱 자동 복귀 미보장 — 간헐):**
  - **증상:** LINE 인증을 마쳐도 앱이 자동으로 전면 복귀하지 않고 LINE 앱
    화면에 머무를 **수 있음**. 사용자가 recent apps 등으로 직접 앱에 돌아오면
    그 시점에 로그인 결과가 정상 처리된다. **"항상 발생"이 아니라 "발생할 수
    있음"** — 2026-09-07 Phase 16 UAT 에서 A7(기존 계정 재로그인)은 재현,
    같은 날 A9(LINE 신규 가입)는 자동 복귀 성공. 재현 조건(가입 vs 재로그인 /
    LINE 앱 상태 / 태스크 스택)은 미특정이다.
  - **원인:** `lib/features/auth/data/line_sdk_client.dart:126` 이
    `LoginOption(false /* onlyWebLogin */, 'normal')` 을 쓰므로 LINE 앱이
    설치된 단말에서는 app-to-app 경로를 탄다. activity 로그 실측상 LINE 앱은
    우리 앱의 콜백 액티비티
    (`com.linecorp.linesdk.auth.internal.LineAuthenticationCallbackActivity`)
    를 정상 실행해 **인증 결과 전달 자체는 성공**시킨 뒤, 자신을 백그라운드로
    내리지 않고 자체 MainActivity 를 전면에 복귀시킨다. 전면 복귀 여부는 LINE
    앱 재량이며 앱 측 코드로 강제하기 어렵다.
  - **해결:** 인증이 실패한 것이 아니므로 **재시도하지 말고** 앱으로 수동
    복귀하면 된다(recent apps / 홈에서 앱 아이콘). 앱이 포그라운드로 돌아온
    시점에 결과 처리가 이어진다.
  - **선택적 후속 관측 (본 starter-kit 미적용):** 인증 대기 중 "인증 후 앱으로
    돌아와 주세요" 안내 문구를 노출하거나, `LoginOption` 의 `onlyWebLogin` 을
    `true` 로 두어 Custom Tab 경로를 강제했을 때 복귀 동작이 개선되는지 실
    단말 A/B 로 측정할 수 있다. **본 starter-kit 은 그 측정 전까지 경로를
    바꾸지 않는다** — 간헐 현상이라 측정 없이 경로를 바꾸면 개선 여부를
    확인할 수 없고 webview fallback 으로 1-tap UX 를 잃을 위험만 남는다.
    iOS 는 `ASWebAuthenticationSession` 이라 복귀 동작이 다를 수 있어 iOS
    batch UAT 시 재확인 대상이다.

---

## Yahoo! JAPAN Login (Phase 15)

Yahoo! JAPAN 로그인은 Custom Token 방식 + OIDC ID Token JWT 검증 (Kakao / LINE
과 같은 path) 으로 구현되어 있습니다. Cloud Function `yahoojpCustomToken`
(asia-northeast3) 이 `jose + JWKS` 로 Yahoo!JP ID Token 을 자체 검증 →
Identity Index 등록 → `admin.auth().createCustomToken(uid)` 발급, 클라이언트가
`signInWithCustomToken` 으로 세션을 시작합니다 (Phase 12 D-08 OIDC verifier
helper 의 세 번째 사용처 — Kakao + LINE 다음 자연 carry-forward).

Yahoo! JAPAN 은 Flutter 공식 SDK 부재 (native `github.com/yahoojapan/yjlogin-{ios,android}-sdk`
는 존재) → **`flutter_appauth` (OpenID Foundation 공식 AppAuth-iOS/Android
래핑)** 채택 (D-YJP-01). PKCE + ID Token 추출 + nonce 자동 처리 + native
redirect (iOS `ASWebAuthenticationSession` + Android `Custom Tabs`) 표준
OIDC 라이브러리.

### 1단계 — Yahoo Developers Console 응용프로그램 등록

콘솔: <https://e.developer.yahoo.co.jp/dashboard/>

1. **Yahoo! JAPAN ID 가입** (이미 가입된 경우 로그인) — 개발자 약관 동의.
2. **응용프로그램 신규 등록** — "アプリケーションの管理" → "新しいアプリケーション
   を開発" → 등록 유형 **「クライアントサイド・アプリケーション」** 선택
   (D-YJP-03 verbatim — `client_secret` 0, PKCE 만으로 토큰 endpoint 호출).

   > **출처:** Yahoo!JP docs verbatim "Client IDがクライアントサイド・アプリケー
   > ションとして発行された場合は指定する必要はありません"
   > (<https://developer.yahoo.co.jp/yconnect/v2/authorization_code/>).

3. **iOS Bundle ID / Android Package Name 등록** — 본인 앱의 Bundle ID
   (예: `com.slimpumpkin.flutterStarterKit.dev`) + Package Name
   (예: `com.slimpumpkin.flutter_starter_kit.dev`).
4. **redirect URI scheme 등록** — Yahoo!JP Console 이 자동 발급한 scheme
   (`yj{client_id}://` 형식 [ASSUMED] — researcher Plan researcher Wave 단계
   에서 verbatim cross-verify) 또는 사용자 정의 reverse-domain scheme
   (권장 — Android intent hijack 위험 회피, 예:
   `com.slimpumpkin.flutterStarterKit.dev.yahoojp`).
5. **Client ID 확인 + 메모** — 등록 직후 "アプリケーション詳細" 페이지의
   "Client ID" 표시 (영숫자 64자 [ASSUMED]). 본 값은 (a) `config/dev.json`
   `yahoojpClientId` + (b) Firebase Secret Manager `YAHOOJP_CLIENT_ID`
   이중 등록 의무.

### 2단계 — Yahoo!JP 공식 BI 자상 사용 절차

본 starter-kit 의 Phase 15 Plan 15-04 는 Yahoo!JP 공식 BI 자상 (Symbol SVG +
Case B 패턴 — 자상은 변형 0 + 라벨은 ARB 외부 layer 자체 render) 을 이미
동봉합니다. fork 사용자는 LICENSE 동의 + 1년 freshness 재확인 의무만 수행.

1. **공식 자상 zip 다운로드 (1년 freshness 재확인):**
   <https://s.yimg.jp/dl/developer_network/sample/download/yconnect/yahoo_japan_login_button.zip>
   - 본 starter-kit 의 `assets/brand/yahoojp/btn_signin_icon.svg` 는 zip 안
     `SVG/yahoo_japan_icon_white_64.svg` verbatim 추출 (2026-05-22 다운로드).
     `fill="white"` → `fill="currentColor"` 일괄 치환만 적용 (geometry /
     viewBox / path 수치 변경 0).
2. **LICENSE 검토 + 동의:**
   - `assets/brand/yahoojp/LICENSE.txt` (zip 안 번들된 공식 PDF
     `Yahoo! JAPAN ID ログインボタン.pdf` verbatim 발췌) cross-reference.
   - 변형 금지 verbatim 인용: **"ボタン画像をゆがめたり、ボタン内に配置されて
     いる画像、文字を書き換えたりしないでください。"** — 자상 path / viewBox /
     색상 절대 변경 금지.
3. **자상 README cross-reference:**
   - `assets/brand/yahoojp/README.md` (Phase 13.1 7필드 schema — provider
     name / source URL / variant / license / download date / verbatim text /
     사용자 sign-off).
4. **공식 색상 verbatim** — `yahoo_japan_icon.ai` layer 명
   "**アイコン（赤）#FF0033**" + "**文字色：#FFFFFF（白）**" → starter-kit
   의 `_renderYahoojpButton` hardcode (`0xFFFF0033` bg + `0xFFFFFFFF` label/
   icon) 부합.

> **흔한 실수:** 자상 파일에 `ColorFilter` 적용 또는 SVG path 수정. Yahoo!JP
> BI 가이드의 "サイズ、見た目が変わるような変更を加えないでください"
> verbatim 위반 — Phase 13.1 R3/R4 의 ColorFilter 절대 금지 정책 일관.

### 3단계 — iOS Info.plist + Android manifestPlaceholder + xcconfig 키 갱신

본 starter-kit 의 `ios/Runner/Info.plist` 와 `android/app/build.gradle.kts`
는 Phase 15 Plan 15-01 가 이미 Yahoo!JP 필수 entry 를 등록한 상태입니다 —
fork 사용자는 placeholder 값을 본인 발급값으로 교체만 수행:

**iOS — `ios/Flutter/dev.xcconfig` (또는 `dev.example.xcconfig` 복사 후 갱신):**
```
YAHOOJP_CLIENT_ID=<1단계에서 발급받은 Client ID>
YAHOOJP_REDIRECT_SCHEME=<1단계에서 등록한 redirect URI scheme>
```

**iOS — `ios/Runner/Info.plist` (Phase 15 Plan 15-01 산출, 변경 0 — build-time 치환):**
```xml
<key>CFBundleURLTypes</key>
<array>
  <dict>
    <key>CFBundleURLSchemes</key>
    <array>
      <string>$(YAHOOJP_REDIRECT_SCHEME)</string>
    </array>
  </dict>
</array>
```

**Android — `android/app/build.gradle.kts` (Phase 15 Plan 15-01 산출, 변경 0):**
```kotlin
manifestPlaceholders["appAuthRedirectScheme"] = "<1단계 redirect URI scheme>"
```

> **흔한 실수:** scheme 값 mismatch. `config/dev.json` 의 `yahoojpRedirectScheme`
> + `ios/Flutter/dev.xcconfig` 의 `YAHOOJP_REDIRECT_SCHEME` + Android
> `manifestPlaceholders["appAuthRedirectScheme"]` + Yahoo!JP Console 등록
> 4곳 모두 동일 scheme 의무. 1곳이라도 다르면 callback redirect 미도달 →
> Cloud Function 호출 0.

### 4단계 — UserInfo API 審査申請 + email scope 활성 절차 (D-YJP-09 정정 lock — production 전환 시 의무)

본 starter-kit 의 Phase 15 단계는 Yahoo!JP scope = `openid + profile` 만
사용 (D-YJP-09 정정 lock 2026-05-21). `userInfo.email` 항상 undefined →
`users/{uid}.email` 미설정 → Phase 17 Account Linking email collision detect
부적용 (sub-only identity_index).

**현재 starter-kit 시점 (dev only):**
- scope = `openid + profile` 만 active
- `payload.sub` 만 사용 → `identity_index/yahoojp:${sub}` resolve
- Cloud Function `yahoojp_custom_token.ts` 의 `userInfo.email` undefined 가
  안전 fallback

**production 전환 시 (사용자 의무):**

> **VERBATIM 인용** (`https://developer.yahoo.co.jp/yconnect/v2/userinfo.html`):
> - "**属性取得API（UserInfoAPI）を利用するには審査が必要となります。**"
> - "アプリケーションの詳細画面内の**利用するスコープ**に「**メールアドレス**」
>   の設定がある"
> - "**プライバシーポリシーURL、利用規約URL**の登録が必要です。"

1. **Yahoo Developers Console > application detail** > "**利用するスコープ**"
   항목에 "**メールアドレス**" 설정 추가
2. **プライバシーポリシー URL + 利用規約 URL 등록 의무** — production 도메인
   호스팅 필요
3. **UserInfo API 審査申請** — Yahoo!JP 측 review 진행 + 승인 timeline
   [ASSUMED] (수일~수 주, 정확한 timeline 은 Yahoo!JP 공식 미공개 —
   researcher Wave 2 단계 확인 의무, 또는 사용자가 starter-kit fork 후
   직접 확인)
4. **승인 후 code 변경 point** (Phase 17+ 책임 — starter-kit Phase 15
   단계 적용 X):
   - `lib/features/auth/data/yahoojp_sdk_client.dart` 의 scopes 에 `'email'`
     추가 (`['openid', 'profile']` → `['openid', 'profile', 'email']`)
   - `functions/src/auth/yahoojp_custom_token.ts` 의 `typedPayload` type 에
     `email?: string` + `email_verified?: boolean` 추가
   - `userInfo.email` propagate + `createCustomToken(uid, developerClaims:
     {email, email_verified: true})` 분기

> **흔한 실수:** UserInfo API 審査 미이행 후 scope=email 추가. 審査 미이행
> 상태에서 email scope 요청 시 Yahoo!JP 측에서 silent fail 또는 invalid_scope
> 에러 → D-YJP-09 정정 lock §(4) 절차 의무.

### 5단계 — Firebase Secret Manager 등록 + Cloud Function 배포

Cloud Function `yahoojpCustomToken` 이 1개 secret 선언
(`defineSecret('YAHOOJP_CLIENT_ID')`). Client ID 는 OIDC ID Token audience
검증 (`aud` claim) 의 정답값으로 runtime 시점에 의무 주입:

```bash
firebase use <dev-project-id>

# YAHOOJP_CLIENT_ID 등록 (1단계에서 메모한 Client ID)
firebase functions:secrets:set YAHOOJP_CLIENT_ID
# prompt:
#   ? Enter a value for YAHOOJP_CLIENT_ID: <Client ID 붙여넣기 + Enter>
```

기대 응답:
```
✔ Created a new secret version projects/.../secrets/YAHOOJP_CLIENT_ID/versions/1
```

확인:
```bash
firebase functions:secrets:get YAHOOJP_CLIENT_ID
```

배포 — `yahoojpCustomToken` 함수를 dev Firebase 프로젝트 (asia-northeast3) 에:

```bash
cd functions
pnpm install           # 최초 1회 (corepack 활성화는 Initial Setup 4단계 참조)
pnpm run lint          # 0 errors 확인
pnpm run build         # tsc OK 확인
pnpm test              # jest 22+ PASS 확인 (yahoojp 14 + oidc_verifier 8)

# 배포
firebase use <dev-project-id>
firebase deploy --only functions:yahoojpCustomToken
```

기대 응답:
```
✔ functions[yahoojpCustomToken(asia-northeast3)] Successful update operation.
```

확인 — Firebase Console > "빌드 > Functions" → `yahoojpCustomToken` row →
region = `asia-northeast3` + "활성" 상태.

### 6단계 — `config/dev.json` 키 주입 + dev flavor 실 단말 검증 + 비즈니스 인증 (production 전환 시)

콘솔에서 발급받은 Client ID 를 `config/dev.json` 에 주입합니다
(`config/dev.example.json` 이 placeholder 를 이미 가지고 있으므로 `cp` 후
본인 값으로 교체):

```json
{
  "enabledAuthProviders": "google,apple,facebook,kakao,naver,line,yahoojp",
  "yahoojpClientId": "<1단계에서 발급받은 Client ID>",
  "yahoojpRedirectScheme": "<1단계에서 등록한 redirect URI scheme>"
}
```

- `client_secret` 은 `config/dev.json` 에 **넣지 마세요** — Yahoo!JP 「クライアン
  トサイド・アプリケーション」 등록 유형 = client_secret 0 (D-YJP-03 verbatim).
- `YAHOOJP_CLIENT_ID` 는 (a) `config/dev.json` (공개 — flutter_appauth init
  의무) + (b) Firebase Secret Manager (Cloud Function aud 검증) 이중 등록.

**dev flavor 실 단말 검증:**
```bash
fvm flutter run --flavor dev --dart-define-from-file=config/dev.json -d <device-id>
```

- LoginScreen 의 **"Yahoo! JAPAN IDでログイン"** 버튼 (Red `#FF0033` 배경 +
  흰 Yahoo!JP 자상 — `BrandedSocialButton.yahoojp()`) 탭 → Android Custom
  Tabs (iOS `ASWebAuthenticationSession`) webview → Yahoo!JP 동의 화면 →
  사용자 동의 → 앱 복귀.
- Home 진입 + EnvironmentInfoScreen 의 Account 섹션 — `linkedProviders` 에
  "Yahoo! JAPAN" 표시 확인.
- Android UAT 8 시나리오: `.planning/phases/15-yahoo-japan-login/15-HUMAN-UAT.md`
  (Plan 15-06 산출 — sentinel-active UAT sequencing 의무, Phase 13.1 D-73 mirror).
- iOS UAT 는 보류 — `.planning/todos/pending/2026-05-XX-ios-yahoojp-uat-deferred.md`
  추적 (memory `project_ios_uat_batch_policy` 일관, Phase 17 batch UAT 단일 진입).

**stg / prod 는?** dev 와 동일한 절차로 사용자 자체 Yahoo Developers Console
application 을 별도 등록 + 키 주입 (Phase 12 D-22 mirror — dev/stg/prod 3
application 분리 등록). starter-kit 의 stg/prod config 는 placeholder 만
포함합니다 (D-YJP-22 — `project_firebase_dev_only` 정책 일관).

**비즈니스 인증 절차 (production 전환 시 추가 항목):**

dev 단계는 Yahoo Developers Console 의 본인 계정만 사용 가능. production
출시 시 다음 항목 추가 의무:

1. **stg/prod application 분리 등록** — Phase 12 D-22 패턴 mirror (dev/stg/prod
   3 application 등록).
2. **사업자 등록증 / 회사 정보** — Yahoo!JP Console 요구 시 사용자 의무
   [ASSUMED — researcher Wave 2 단계 확인].
3. **D-YJP-09 §(4) UserInfo API 審査申請** — 위 4단계 절차 의무 (production
   에서 email scope 필요 시).
4. **1년 주기 BI 가이드 재방문** — Yahoo!JP 정책 변경 대비 (`assets/brand/yahoojp/`
   freshness, memory `feedback_label_verbatim_audit` mirror).

### Pitfall 정리 (Phase 15 RESEARCH §Pitfalls + D-YJP-NN)

- **Pitfall 1 (nonce raw transit):** Cloud Function `oidc_verifier.ts` 의
  `nonceHashing: "none"` 단독 union 부합 — sha256 hashing 추가 시 회귀
  (D-YJP-04 5-source cross-verified raw nonce only).
- **Pitfall 2 (YAHOOJP_CLIENT_ID 미주입):** Firebase Secret 등록 + xcconfig +
  config/dev.json 3곳 동기 의무. 1곳이라도 placeholder 잔존 시 silent failure
  (flutter_appauth init 실패 또는 Cloud Function aud 검증 fail).
- **Pitfall 3 (redirect URI scheme 충돌):** 다른 앱이 동일 scheme 등록 시
  Android intent hijack 위험 → 고유 reverse-domain scheme 권장 (예:
  `com.slimpumpkin.flutterStarterKit.dev.yahoojp`).
- **Pitfall 4 (appAuthRedirectScheme placeholder mismatch):** manifestPlaceholders
  + config/dev.json + xcconfig + Yahoo!JP Console 4곳 모두 동일 scheme 의무.
- **Pitfall 5 (UserInfo API 審査 미이행):** D-YJP-09 §(4) 절차 의무 — 審査
  미이행 후 scope=email 추가 시 동작 안 함. dev 단계는 `openid + profile` 만
  fallback 유지.
- **Pitfall 6 (issuer trailing slash 누락):** Cloud Function helper config
  `issuer: "https://auth.login.yahoo.co.jp/yconnect/v2/"` verbatim — trailing
  slash 포함 (`configuration.html` OpenID Provider Metadata truth source,
  RFC 8414 §2 권고). 누락 시 jose `JWTClaimValidationFailed: unexpected "iss"
  claim value`.
- **Pitfall 7 (자상 변형 금지):** `assets/brand/yahoojp/btn_signin_icon.svg`
  path / viewBox / 색상 직접 수정 금지 — Yahoo!JP BI 가이드 "ボタン画像をゆが
  めたり、ボタン内に配置されている画像、文字を書き換えたりしないでください"
  verbatim 위반. ColorFilter 적용 금지 (Phase 13.1 R3/R4 일관).

### Cross-reference

- **자상 + LICENSE:** `assets/brand/yahoojp/` (`btn_signin_icon.svg` + `LICENSE.txt`
  + `README.md` — Plan 15-04 산출)
- **STEP2 권위 매트릭스:** `.planning/phases/15-yahoo-japan-login/15-STEP2-yahoojp-VERBATIM.md`
  (canonical key 매트릭스 + verbatim 출처)
- **Phase 14 LINE 19 locale 가이드 비교:** `14-LINE-LOCALE-REFERENCE.md`
  — Yahoo!JP 는 미적용 (3 locale only, D-YJP-08 — Yahoo!JP BI 가이드 ja-only,
  en/ko 차원 번역 [ASSUMED] tag)
- **UAT 8 시나리오:** `.planning/phases/15-yahoo-japan-login/15-HUMAN-UAT.md`
  (Plan 15-06 산출 — A1~A8 + iOS UAT 보류, sentinel-active UAT sequencing
  Phase 13.1 D-73 두 번째 적용)

---

## Brand Asset (Phase 13 D-52 — Kakao + Naver 통합) — DEPRECATED

> **⚠ 본 단락은 Phase 13.1 마이그레이션 후 stale 입니다.**
>
> Phase 13.1 (2026-05-08~10) 의 cross-cutting 정정으로 brand asset 표준이
> 다음과 같이 변경되었습니다:
>
> - **자상 디렉토리:** `assets/icons/{kakao,naver}_logo.svg` (구) →
>   `assets/brand/{provider}/[{lang}/][{theme}/]` (신, 7 provider 통합 매트릭스).
>   `assets/icons/` 디렉토리는 더 이상 brand asset 보관 위치가 아닙니다.
> - **Naver 공식 색:** `#03C75A` (구, third-party 출처 추정값) → **`#03A94D`**
>   (신, NAVER ID 로그인 BI verbatim — `developers.naver.com/docs/login/bi/bi.md`).
>   `#03C75A` 는 NAVER Corp 회사 브랜드 + NCloud SSO 컨텍스트 색상으로
>   starter-kit 사용 대상 아님.
> - **자상 색 변환:** `ColorFilter.mode(spec.iconColor, BlendMode.srcIn)`
>   가이드 (구) → **ColorFilter 적용 절대 금지** (신, R3/R4). PNG/SVG 자상은
>   `Image.asset(... fit: BoxFit.contain)` / `SvgPicture.asset(... fit:
>   BoxFit.contain)` 직접 렌더, 색 변환 시 BI 위반.
> - **PLACEHOLDER sentinel:** `<!-- PLACEHOLDER -->` SVG 메타데이터 (구) →
>   `assets/brand/{provider}/.placeholder` 빈 파일 (신, sentinel 단일 책임).
>   Phase 14 (LINE) active 전환 + Phase 16 (WeChat) 폐기로 현재
>   `kPlaceholderProviders = <String>[]` empty — sentinel 의무 해소.
>
> **모든 절차는 아래 [Brand Asset Management (Phase 13.1)](#brand-asset-management-phase-131)
> 단락을 참조하십시오.** 본 단락의 본문 (URL/라이선스/변경 금지 항목) 은
> 기록 보존 목적으로 남겨두지만 사용자 절차는 Phase 13.1 단락이 단독 권위.

### Naver 공식 자산 (DEPRECATED — Phase 13.1 단락 참조)

- **다운로드 URL:** <https://developers.naver.com/docs/login/bi/bi.md>
- **라이센스:** Naver 디자인 가이드 — 그린 배경 + 흰 'N' 로고 (메인) 또는 흰
  배경 + 그린 'N' (역색) 변형 사용 가능
- **변경 금지:** 색상 / 회전 / 비율 / 단순화 변형 모두 금지 (위반 시 Naver
  Developers 정책 위반)
- 본 starter kit 은 메인 변형 (그린 #03A94D 배경 + 흰 'N' — Phase 13.1 R1
  정정 후 NAVER ID 로그인 BI verbatim) 사용 —
  `BrandedSocialButton.naver()`

### Kakao 공식 자산 (DEPRECATED — Phase 13.1 단락 참조)

- **다운로드 URL:** <https://developers.kakao.com/tool/resource/login>
- **라이센스:** Kakao Brand Guideline — 노란 #FEE500 배경 + 검정 말풍선 (메인)
  또는 흰 배경 + 노란 말풍선 등 변형
- **변경 금지:** 색상 / 회전 / 비율 변경 모두 금지 (위반 시 Kakao Developer
  Console 앱 정지 위험 — Phase 12-07 단락 참조)
- 본 starter kit 은 노란 배경 + 검정 말풍선 사용 —
  `BrandedSocialButton.kakao()`

### 교체 절차 (DEPRECATED)

> 본 절차는 Phase 13 단계의 stale 절차로, 실제 디렉토리 구조 (`assets/brand/`)
> 와 정합 안 됩니다. **[Brand Asset Management (Phase 13.1)](#brand-asset-management-phase-131)
> 단락의 1~3단계 절차를 사용하십시오.**

### Phase 14 진입 시 (DEPRECATED — Phase 13.1 단락 2단계 참조)

LINE 진입 시 동일 패턴 — Phase 13.1 단락의 "2단계 — Phase 14 진입 시
LINE 자상 commit" 절차 단독 권위.

---

## Kakao 동의 항목 갱신 (Phase 13 D-56 retroactive)

Phase 12 의 Kakao Developer Console 동의 항목에 `profile_image` 추가 의무 —
Naver 와 동시에 운영 시 양 provider 의 프로필 사진 정보 일관 제공.

### 절차

1. **Kakao Developers Console > 본인 앱 > 동의 항목** 탭
2. **"프로필 사진"** 활성화 — "선택 동의" 로 설정 (사용자 동의 시 ID Token
   `picture` claim 자동 포함)
3. (Phase 13 Decision #6 — Kakao 측 코드 변경 0건 채택) — Console 활성화만으로
   ID Token claim 자동 포함

### Decision #6 채택 분기 (Phase 13 Plan 13-06)

- **대안 1 (Console only) — 채택:** 동의 항목 활성화만으로 ID Token `picture`
  claim 자동 포함 (Naver `/v1/nid/me` 응답의 `profile_image` 와 동일 패턴) →
  코드 변경 0건. 근거: Kakao Developers RestAPI ID Token Payload spec —
  `picture` field requires `consent for profile information or profile picture`.
- 대안 2 (SDK arg) — 미채택: `lib/features/auth/data/kakao_sdk_client.dart` 의
  `loginWithKakaoAccount(serviceTerms: ['openid', 'profile_image'])` 인자
  갱신. `serviceTerms` 가 카카오싱크 서비스 약관 태그라 OIDC scope 와 별개
  개념 → 의도 불일치로 미채택.

상세 근거: `.planning/phases/13-naver-login/13-06-SUMMARY.md` 의 Decision #6
단락 (Context7 / pub.dev README 인용 + 회귀 가드 2 case).

### 회귀 가드

Plan 13-06 commit `5038f1e` 가 다음 invariant 검증:

- `serviceTerms = ['openid']` 만 유지 + `'profile_image'` / `'picture'` 추가
  인자 부재 (대안 1 fix point)
- KakaoSignInResult 인터페이스 = idToken + nonce 만 노출 (picture claim 파싱
  책임 부재 — Phase 17/18 forward compat)

<!-- Phase 14 — see ROADMAP.md -->

---

## Kakao 검수 / 비즈앱 / 추가 수집 / stg-prod (Phase 14 D-LINE-22b retroactive)

> **본 단락은 Phase 14 진입 시점에 추가된 retroactive 보강입니다** —
> Phase 12 (Kakao Login) 단계에서는 dev 단독 검증만 다루었으나, 다른 social
> provider (Naver, LINE) 사용자가 starter-kit 을 fork 후 production 출시
> 시 필요한 4 항목 (Kakao 검수 신청 / 비즈앱 인증 / 추가 수집 정보 카탈로그 /
> stg-prod Console 등록) 을 통합 매뉴얼로 분리.
>
> **출처 검증 의무 (memory `feedback_official_bi_verification`):** 본 단락의
> 모든 verbatim claim 은 `[ASSUMED — Phase 14 단계 cross-verify 보류,
> 사용자 책임]` tag 입니다. starter-kit 사용자가 fork 후 production 진입 전
> 다음 4 URL 의 최신 verbatim 직접 cross-verify 의무:
>
> 1. <https://developers.kakao.com/docs/ko/kakaologin/prerequisite> (사전 준비 + 검수)
> 2. <https://kakaobusiness.gitbook.io/main/tool/kakaosync/plan> (비즈앱 전환 가이드 — Kakao 공식 third-party gitbook 이라 Kakao Console UI 와 cross-verify 의무)
> 3. <https://developers.kakao.com/docs/ko/kakaologin/common> (동의 항목 카탈로그 + 비즈앱-only 명시)
> 4. <https://developers.kakao.com/docs/latest/ko/getting-started/app> (stg/prod 등록 절차 — 키 해시 release 변경 + Redirect URI prod domain + Secret Manager prod 등록)

### (1) Kakao 검수 신청 절차 (production 출시 시)

`[ASSUMED — 정책 변경 가능, cross-verify 의무]`

Kakao Developers 정책: **일일 활성 사용자 (DAU) 100명 이상** production 출시
시 검수 신청 의무. 미신청 + DAU 초과 시 앱 일시 정지 위험.

1. **Kakao Developers Console > 본인 앱 > 검수** 탭 진입.
2. 검수 요청 form 작성:
   - 앱 소개 / 사용 시나리오 / 동의 항목 사용 목적
   - Privacy Policy URL / Terms of Service URL
   - 검수용 테스트 계정 정보 (검수자 로그인 가능 계정)
3. "검수 요청" 제출 → Kakao 검수 timeline `[ASSUMED 1~2주]` — 정확한 기간은
   Kakao 공식 미공개.
4. 검수 완료 통보 후 production 배포.

> **흔한 실수:** 검수 시점에 등록 안 한 동의 항목을 production 에서 활성화
> → 재검수 의무. **3 항목** (필요한 모든 동의 항목 + 비즈앱 항목 미리 등록 +
> 사용 목적 명시) 미리 정리 후 검수 신청.

### (2) 비즈앱 인증 절차 (민감 정보 사용 시)

`[ASSUMED — Kakao 비즈앱 정책 변경 가능]`

다음 동의 항목 중 **하나라도** 사용 시 비즈앱 전환 의무:

- 휴대폰 번호 `phone_number`
- CI (Connecting Information) / DI (Duplication Information)
- 배송지 정보
- 카카오톡 메시지 전송 권한
- 생일 / 성별 / 연령대 / 출생연도 (기본 동의 항목 외 민감 정보)

1. **Kakao Developers Console > 본인 앱 > 비즈앱 전환** 메뉴 진입.
2. 분기 선택:
   - **사업자 인증** (법인 / 개인사업자) — 사업자등록증 업로드 + 회사 정보
     입력. 인증 완료 후 모든 비즈앱 전용 동의 항목 가용.
   - **개인 인증** — 본인 명의 핸드폰 인증. 일부 동의 항목 제한.
3. 카카오 검수 timeline `[ASSUMED 1~3 영업일]`.
4. 비즈앱 승인 통보 후 동의 항목 활성화 + (1) 검수 재신청.

자세한 분기는 <https://kakaobusiness.gitbook.io/main/tool/kakaosync/plan>
공식 가이드 cross-verify 의무.

### (3) 인증 후 사용할 수 있는 추가 수집 정보 카탈로그

`[ASSUMED — Kakao 공식 동의 항목 변경 가능, cross-verify 의무]`

**기본 동의 항목 (검수 / 비즈앱 의무 없음):**

| 항목 | scope | 비즈앱 의무 | 검수 의무 (DAU 100+) |
|------|-------|-----------|-------------------|
| 닉네임 | `profile_nickname` | X | X |
| 프로필 사진 | `profile_image` | X | X |
| 카카오계정 이메일 | `account_email` | X | X |

**비즈앱-only 동의 항목 (비즈앱 인증 + 검수 양쪽 의무):**

| 항목 | scope | 비즈앱 의무 | 검수 의무 |
|------|-------|-----------|----------|
| 생일 | `birthday` | O | O |
| 성별 | `gender` | O | O |
| 연령대 | `age_range` | O | O |
| 출생연도 | `birthyear` | O | O |
| 휴대폰 번호 | `phone_number` | O | O |
| CI (연계 정보) | `account_ci` | O | O |
| 배송지 정보 | `shipping_address` | O | O |
| 카카오톡 메시지 전송 | `talk_message` | O | O (카카오톡 정책 별도) |

**채택 시 code 변경 point:**

1. `lib/features/auth/data/kakao_sdk_client.dart` 의 `loginWithKakaoAccount`
   호출 인자 `serviceTerms` 또는 OIDC scope 갱신 (현재 `serviceTerms =
   ['openid']` 만 — Phase 13 D-56 Decision #6 정책 일관). 비즈앱 동의 항목은
   대부분 OIDC scope 외 별도 API 호출 (`UserApi.instance.me()`) 필요 →
   starter-kit 의 Custom Token path 와 별개.
2. `functions/src/auth/kakao_custom_token.ts` 의 `typedPayload` zod schema
   에 비즈앱 claim 추가 (단 ID Token 에 비즈앱 항목 직접 포함되지 않으면
   Cloud Function 변경 0).
3. 신규 `UserApi.instance.me()` 호출 helper 추가 (Cloud Function 또는
   클라이언트 — 보안 정책에 따라 분리).

### (4) stg / prod Console 등록 + 검수 절차

현재 manual.md 의 "Kakao Login (Phase 12)" 단락은 `> **stg / prod 는?** dev
와 동일한 절차로 사용자 자체 Kakao 앱을 별도 등록 + 키 주입` 한 줄로 압축
되어 있습니다. 실제 production 등록 시 다음 보강:

1. **별도 Kakao 앱 생성 (stg / prod 각각 1개)** — Kakao Console > "내
   애플리케이션 > 애플리케이션 추가하기" → stg / prod 각각 신규 앱. dev /
   stg / prod 의 nativeAppKey 가 모두 달라야 함 (보안 격리).
2. **키 해시 release 변경** — production 빌드용 keystore (`<your-keystore.jks>`)
   의 release SHA-1 + base64 키 해시를 stg / prod 각 앱의 Android 플랫폼에
   등록. dev debug 키 해시와 다름 — 누락 시 production 빌드에서 `Invalid
   key hash` 런타임 에러.
   ```bash
   # release 키 해시
   keytool -exportcert -alias <your-alias> \
     -keystore <your-keystore.jks> \
     | openssl sha1 -binary | openssl base64
   ```
3. **Redirect URI prod domain 등록** — stg / prod 의 Kakao 앱 Redirect URI
   섹션에 production domain (예: `kakao{prodNativeAppKey}://oauth` +
   `https://stg.example.com/kakao/callback` 등). dev 의 nativeAppKey 와
   다름.
4. **Secret Manager prod 환경 등록** — `firebase use <prod-project-id>` →
   `firebase functions:secrets:set KAKAO_NATIVE_APP_KEY` 로 prod 키 등록
   (dev / stg / prod 각 Firebase 프로젝트 별 격리). Cloud Function 의
   `defineSecret('KAKAO_NATIVE_APP_KEY')` 가 자동 환경별 분리.
5. **OIDC 활성화 / 동의 항목 / Redirect URI 검수** — (1) 검수 신청 단계에서
   stg / prod 양쪽 앱 별개 검수. dev 검수 통과 = prod 검수 통과 의무 아님
   (Kakao 정책).
6. **App Check Debug Provider Token** — stg / prod 의 Firebase Console >
   App Check > 본인 iOS/Android 앱 > "Manage debug tokens" 에서 dev /
   stg / prod 토큰 분리 관리. dev 디바이스 / CI 환경별 등록.

> **흔한 실수:** dev 의 nativeAppKey 를 prod 의 `config/prod.json` 에 그대로
> 사용. dev Kakao 앱은 검수 미통과 → production 사용자 로그인 시 silent
> failure + Kakao Console 차단.

<!-- Phase 14 — see ROADMAP.md -->

---

## Naver 검수 / 추가 항목 / member detail / stg-prod (Phase 14 D-LINE-22c retroactive)

> **본 단락은 Phase 14 진입 시점에 추가된 retroactive 보강입니다** —
> Phase 13 (Naver Login) 단계에서는 dev 단독 검증만 다루었으나, production
> 출시 시 필요한 4 항목 (네아로 검수 신청 / 추가 항목 활성화 / `/v1/nid/me`
> response 카탈로그 / stg-prod Console 등록) 을 통합 매뉴얼로 분리.
>
> **출처 검증 의무 (memory `feedback_official_bi_verification`):** 본 단락의
> 모든 verbatim claim 은 `[ASSUMED — Phase 14 단계 cross-verify 보류,
> 사용자 책임]` tag 입니다. starter-kit 사용자가 fork 후 production 진입 전
> 다음 4 URL 의 최신 verbatim 직접 cross-verify 의무:
>
> 1. <https://developers.naver.com/docs/login/api/api.md> (네아로 검수 절차 — Console > 애플리케이션 개발 상태 > 네아로 검수요청)
> 2. <https://developers.naver.com/docs/login/devguide/devguide.md> (API 설정 > 추가 항목 — mobile / ci / birthday / gender / age / birthyear / name)
> 3. <https://developers.naver.com/docs/login/profile/profile.md> (`/v1/nid/me` response 필드 카탈로그 — response.email / nickname / profile_image 외)
> 4. <https://developers.naver.com/docs/login/api/api.md#stage-environment> (stg/prod Console 등록 절차 — 별도 Naver 앱 + 검수 + iOS URL Scheme prod 분리 + Secret Manager prod)
>
> WebFetch developers.naver.com 403 차단 가능 — 브라우저 직접 접속 후
> verbatim 인용.

### (1) Naver Login 검수 신청 절차 (production 출시 시)

`[ASSUMED — Naver 검수 정책 변경 가능, cross-verify 의무]`

네아로 (네이버 아이디로 로그인) 정책: production 출시 시 검수 신청 의무.
검수 미통과 시 외부 사용자 로그인 차단 (개발 모드 등록된 본인 계정만 허용).

1. **Naver Developers Center > 내 애플리케이션 > 본인 앱 > 애플리케이션
   개발 상태** 메뉴 진입.
2. **"네아로 검수요청"** 버튼 클릭.
3. 검수 요청 form 작성:
   - 서비스 URL / 안드로이드 앱 / iOS 앱 정보
   - 로그인 동의 항목 사용 목적 (필수 / 선택 / 추가 항목 별)
   - 개발 환경 테스트 계정 정보 (검수자 로그인 가능 계정)
   - 검수 화면 캡처 (로그인 버튼 + 동의 화면 + 사용 화면)
4. "검수 요청 등록" 제출 → Naver 검수 timeline `[ASSUMED 3~7 영업일]` —
   정확한 기간은 Naver 공식 미공개.
5. 검수 완료 통보 후 production 배포.

> **흔한 실수:** 검수 시점에 등록 안 한 동의 항목을 production 에서 활성화
> → 재검수 의무 (검수는 동의 항목 set 별로). 모든 동의 항목 + 추가 항목
> 미리 정리 후 일괄 검수 신청.

### (2) 추가 항목 활성화 절차 (member detail info)

`[ASSUMED — Naver API 설정 정책 변경 가능]`

기본 동의 항목 (이메일 / 닉네임 / 프로필 사진) 외에 다음 **member detail
info** 항목은 별도 활성화 + 검수 의무:

1. **Naver Developers Center > 내 애플리케이션 > 본인 앱 > API 설정** 메뉴
   진입.
2. "추가 항목" 단락에서 다음 중 필요 항목 활성화:
   - 휴대폰 번호 `mobile`
   - CI (Connecting Information) `ci`
   - 생일 `birthday`
   - 성별 `gender`
   - 연령대 `age`
   - 출생연도 `birthyear`
   - 실명 `name`
3. 각 항목별 사용 목적 입력.
4. (1) 검수 재신청 의무 — 추가 항목은 검수 통과 후 production 에서만 사용
   가능.

### (3) 인증 후 사용할 수 있는 추가 수집 정보 카탈로그

`[ASSUMED — Naver `/v1/nid/me` response field 변경 가능, cross-verify 의무]`

Cloud Function `naverCustomToken` 이 Naver access_token 으로 호출하는
`https://openapi.naver.com/v1/nid/me` 응답 필드 카탈로그.

**기본 동의 항목 (검수 / 추가 항목 의무 없음):**

| 항목 | response field | 검수 의무 |
|------|---------------|----------|
| 이메일 | `response.email` | X (기본 필수 동의) |
| 닉네임 | `response.nickname` | X (기본 필수 동의) |
| 프로필 사진 | `response.profile_image` | X (선택 동의, Phase 13 D-56 retroactive) |

**추가 항목 (검수 통과 의무):**

| 항목 | response field | 검수 의무 | 추가 항목 의무 |
|------|---------------|----------|--------------|
| 휴대폰 번호 | `response.mobile` / `response.mobile_e164` | O | O |
| CI (연계 정보) | `response.ci` | O | O |
| 생일 | `response.birthday` | O | O |
| 성별 | `response.gender` (`F` / `M` / `U`) | O | O |
| 연령대 | `response.age` (예: `30-39`) | O | O |
| 출생연도 | `response.birthyear` | O | O |
| 실명 | `response.name` | O | O |

**채택 시 code 변경 point:**

1. `functions/src/auth/naver_custom_token.ts` 의 `/v1/nid/me` response 매핑
   helper (`mapNaverProfile`) 에 신규 필드 추가. 현재 Phase 13 단계는
   email / nickname / profile_image 3 필드만 매핑.
2. **PII 정책 의무 (Phase 13 D-51 / D-54):** Cloud Function logger payload
   에 추가 필드의 raw 값 절대 노출 금지. `{event, uid, resultcode, status}`
   sentinel 5 회귀 가드 (`functions/test/auth/naver_custom_token.test.ts`)
   에 신규 필드 추가 의무.
3. Firebase Auth user record 의 `customClaims` 또는 별도 Firestore
   `users/{uid}/extras/{field}` 분리 저장 (Firebase Auth user record 의
   기본 필드는 displayName / email / photoURL 만 — 그 외는 customClaims
   또는 별도 collection).

### (4) stg / prod Console 등록 + 검수 절차

현재 manual.md 의 "Naver Login (Phase 13)" 단락 6단계 끝 `> **stg / prod
는?** dev 와 동일한 절차로 사용자 자체 Naver 앱을 별도 등록 + 키 주입` 한
줄로 압축되어 있습니다. 실제 production 등록 시 다음 보강:

1. **별도 Naver 앱 생성 (stg / prod 각각 1개)** — Naver Developers Center >
   "Application > 애플리케이션 등록" → stg / prod 각각 신규 앱. dev / stg /
   prod 의 Client ID / Client Secret 모두 다름 (보안 격리 + 검수 분리).
2. **iOS URL Scheme prod 분리** — production 빌드용 iOS URL Scheme 등록
   (예: `flutterStarterKitProd`). `config/prod.json` 의 `naverUrlScheme` +
   `ios/Flutter/prod.xcconfig` 의 `NAVER_URL_SCHEME` 양쪽 prod 값 일치.
3. **Android Key Hash release 변경** — production 빌드용 keystore
   (`<your-keystore.jks>`) 의 release SHA-1 + base64 키 해시를 stg / prod
   각 앱의 Android 플랫폼에 등록. dev debug 키 해시와 다름.
   ```bash
   # release 키 해시
   keytool -exportcert -alias <your-alias> \
     -keystore <your-keystore.jks> \
     | openssl sha1 -binary | openssl base64
   ```
4. **Bundle ID / Package Name 분리** — stg / prod 의 Bundle ID / Package
   Name 이 dev 와 다르면 (예: `com.example.flutter_starter_kit` vs
   `.dev`) 본인 production 값으로 등록.
5. **Secret Manager prod 환경 등록** — `firebase use <prod-project-id>` →
   `firebase functions:secrets:set NAVER_CLIENT_SECRET` 로 prod Client
   Secret 등록 (dev / stg / prod 각 Firebase 프로젝트 별 격리). Cloud
   Function 의 `defineSecret('NAVER_CLIENT_SECRET')` 자동 환경별 분리.
6. **네아로 검수 분리** — (1) 검수 신청을 stg / prod 양쪽 앱 별개 신청.
   dev 검수 통과 = prod 검수 통과 의무 아님.
7. **App Check Debug Provider Token** — stg / prod 의 Firebase Console >
   App Check > 본인 iOS/Android 앱 > "Manage debug tokens" 에서 dev / stg /
   prod 토큰 분리 관리.

> **흔한 실수:** dev 의 Client ID 를 `config/prod.json` 에 그대로 사용.
> dev Naver 앱은 검수 미통과 → production 사용자 로그인 시 외부 사용자
> 차단 + silent failure.

---

## IdP 프로필 동기화 정책 (R10-FOLLOWUP)

OAuth Custom Token provider (Kakao + Naver + Phase 14~15 LINE/Yahoo!JP)
의 **재로그인** 시 IdP 응답의 `displayName` / `photoURL` 을 Firebase Auth
user record 에 어떻게 반영할지 결정하는 정책. 신규 등록 path 는 정책과 무관
(Phase 13 R10 retroactive fix 가 createUser/updateUser 시점에 이미 propagate).

### 정책

`functions/src/auth/identity_index.ts` 상단의 `PROFILE_REFRESH_POLICY` 상수
한 줄로 결정:

```ts
export const PROFILE_REFRESH_POLICY: ProfileRefreshPolicy = "truth-of-source";
```

| 정책 | 동작 | 적합 도메인 |
|------|------|------------|
| `"truth-of-source"` (default) | 응답에 필드가 있으면 update, 없으면 명시 `null` 로 clear. 사용자가 IdP 측에서 프로필 이미지/닉네임 *삭제* → 다음 로그인에 starter-kit 측에서도 즉시 clear | 일반 production app (Slack/Discord 등 패턴) + GDPR Art. 17 (right to erasure) 친화 |
| `"preserve"` | 응답 있으면 update, 없으면 기존 값 보존 | IdP 동의 항목 일시 OFF/ON 빈번한 도메인 (일부 B2B 툴) — 데이터 안정성 우선 |

### email 은 정책 무관 항상 preserve

`email` 은 sign-in 식별자라 clear 시 user lockout 위험 (다음 로그인에 email
매칭 안 되면 새 user record 충돌 가능). 정책은 `displayName` / `photoURL`
에만 적용.

### 적용 절차

1. 본인 앱 도메인 검토 — 사용자가 IdP 측 프로필을 적극 변경/삭제하는가?
   대부분 yes → **default `"truth-of-source"` 유지**.
2. 변경 필요 시 `PROFILE_REFRESH_POLICY` 한 줄 수정:

   ```ts
   export const PROFILE_REFRESH_POLICY: ProfileRefreshPolicy = "preserve";
   ```

3. `cd functions && pnpm test` — `profileFieldsForRefresh` + 통합 케이스
   회귀 0 확인.
4. 배포:

   ```bash
   firebase deploy \
     --only functions:naverCustomToken,functions:kakaoCustomToken \
     --project <dev-project-id>
   ```

   Phase 14~15 추가 시 해당 함수 (`lineCustomToken` 등) 도 동시 배포.

### 적용 범위 (D-08 — helper 1곳 fix → 모든 caller 자동 상속)

- Phase 12 — `kakaoCustomToken`
- Phase 13 — `naverCustomToken`
- Phase 14~15 — LINE / Yahoo!JP (추가 시 동일 helper 재사용 → 자동 상속)

### best-effort 정책 (R9 strict 와 차이)

R9 (anonymous→소셜 신규 등록의 `emailVerified` 갱신) 는 보안 회귀 차단 의무
→ strict throw. 본 R10-FOLLOWUP 의 재로그인 프로필 refresh 는 UI freshness
정도 → best-effort + `logger.warn` (R2 orphan cleanup 패턴과 동일).
`updateUser` 실패가 caller 정상 path 차단 안 함 — 다음 로그인에 자동 재시도.

### 발견 경위

`.planning/phases/13-naver-login/13-HUMAN-UAT.md` 의 T-13-UAT-NAVER-A1 결과
단락 (2026-05-08 Galaxy Z Fold6 1-tap UAT). 사용자가 첫 로그인 후 Naver 계정에
프로필 이미지를 신규 등록 → 재로그인 → starter-kit 측 photoURL stale (이전
빈 상태). Cloud Function logs `isNewUser: false` 로 재로그인 path 확인 →
`identity_index.ts:resolveIdentity` 의 `idxSnap.exists` 분기가 `tx.update(idxRef,
lastSeenAt)` 만 호출, Firebase Auth user record 미갱신 root cause 식별.

상세 helper / test 코드: `functions/src/auth/identity_index.ts` 의
`profileFieldsForRefresh` JSDoc + `functions/test/auth/identity_index.test.ts`
의 R10-FOLLOWUP describe 블록 (pure 6 케이스 + 통합 4 케이스).

### sign-in 직후 linkedProvidersStream permission-denied race (해결됨, R10-FOLLOWUP-2 fix)

**원인:** `PROFILE_REFRESH_POLICY = "truth-of-source"` 가 호출하는 server-side
`updateUser` 가 client side `onIdTokenChanged` emit 가능 → Firestore SDK
token cache propagate timing race → `linkedProvidersStream` 이 sign-in
직후 잠시 `[cloud_firestore/permission-denied]` 를 받음. fix 전에는 stream
의 `handleError` 가 즉시 빈 배열 emit (R6 D-41 정책) → `AsyncData([])`
정착 → UI 의 EnvironmentInfoScreen "로그인 수단" 카드가 첫 frame `"-"`
표시 (cold start 시 회복).

**해결됨 (R10-FOLLOWUP-2 fix):** `lib/features/auth/data/auth_repository.dart::linkedProvidersStream`
이 `async*` generator + `permission-denied` 1s × 5회 retry 로 재작성됨
(총 5s envelope). retry 중에는 stream emit 보류 (yield 안 함) → consumer
(`currentUserProvider`) 의 R13 fix (`linkedAsync.when` 의 AsyncLoading
분기에서 `linkedAsync.value` 직전 cached emit 보존) 가 직전 emit 을 UI
에 유지. 다른 FirebaseException (network/unavailable 등) 은 즉시 빈 배열
fallback (D-41 영구 spinner 회피 정책 보존). 5회 escape 시에도 빈 배열
fallback (escape hatch).

**Retry 정책 (코드 내장 상수):** `permissionDeniedRetries < maxRetries` 이며
`maxRetries = 5`, `retryDelay = Duration(seconds: 1)` — 총 5s envelope.
정책 근거 — 실측 race window 는 sub-second 추정 + Cloud Function cold
start 보정 (~6s 관측) 까지 cover. 단순 1s 고정 backoff 가 D-41 (영구
spinner 회피) 의도와 일치 (exponential backoff 는 envelope 만 늘리고
race 회복 시간은 동일).

**Invariants (auth_repository.dart::linkedProvidersStream doc comment):**
- I1 (D-41 보존): 다른 FirebaseException 즉시 빈 배열 + 5회 escape 빈 배열
- I2 (R13 호환): permission-denied retry 중 yield 안 함 → AsyncLoading 분기 유지
- I3 (카운터 리셋): 정상 emit 도달 시 retry 카운터 0 — 장기 세션 token 재만료 대응
- I4 (Type-safe parsing): `whereType<Map<String, dynamic>>().whereType<String>()` 보존

**Layer 1 회귀 가드:** `test/features/auth/data/auth_repository_current_user_test.dart`
의 `Phase 13 R10-FOLLOWUP-2` group (5 케이스 — 정상 emit / retry 1회 후
정상 / 5회 escape / 다른 FirebaseException 즉시 fallback / 카운터 리셋).

**참고:** Firestore SDK 자체의 token cache 자동 재구독 미동작은 known
bug (firebase-android-sdk #5101, flutterfire #11146). 본 fix 는 client-side
workaround. spec 평가는 옵션 A (retry) / B (handleError 분기) / C
(subscribe 지연) 비교 후 옵션 A 채택 — D-08 helper-1곳-fix 모델 보존
(Phase 14~15 LINE/Yahoo!JP 자동 상속).

**후속 fix 추적:** `.planning/todos/completed/2026-05-08-r10-followup-permission-denied-race.md`
(pending → completed). spec: `docs/superpowers/specs/2026-05-08-r10-followup-2-design.md`.

---

## Phase 14~15 — Custom Token Provider 추가 가이드 (stub)

Phase 12 (Kakao OIDC) + Phase 13 (Naver REST) 의 통합 패턴을 그대로 미러링하여
LINE / Yahoo!JP 등 새 Custom Token provider 를 추가할 수 있습니다.
9 단계 절차:

1. **Provider ID 등록** — `lib/core/auth/provider_id.dart` 의
   `kProviderId{Provider}` 가 이미 등재되어 있음 (Phase 11-02 wave 1). 변경
   없음.

2. **Notifier** — `lib/features/auth/presentation/{provider}_sign_in_notifier.dart`
   신규. Phase 12 `kakao_sign_in_notifier.dart` 1:1 미러 (Facebook → Kakao
   → Naver/... 일괄 치환). autoDispose AsyncNotifier + `ref.mounted` 가드 +
   Result switch.

3. **SDK Client** — `lib/features/auth/data/{provider}_sdk_client.dart` 신규.
   Phase 12 `kakao_sdk_client.dart` 미러. 단 검증 방식이 OIDC vs REST 인지에
   따라 Cloud Function 호출 인자 / SDK 호출 흐름 다름:

   | Phase | Provider | 검증 방식 | 근거 |
   |-------|----------|-----------|------|
   | 12 | Kakao | OIDC ID Token JWT | Kakao 공식 권장 |
   | 13 | Naver | REST `/v1/nid/me` | Naver OIDC 미지원 |
   | 14 | LINE | OIDC ID Token JWT | LINE 공식 OIDC |
   | 15 | Yahoo!JP | OIDC ID Token JWT | Yahoo! ID 連携 v2 표준 |

   각 phase 의 discuss-phase 진입 시 본 매트릭스 + 실 provider 공식 문서
   재확인 의무.

4. **AuthStrategy** — `lib/core/auth/strategies/{provider}_auth_strategy.dart`
   신규. Phase 12 `kakao_auth_strategy.dart` 미러. **race-fix invariant 의무
   (Pitfall 8)** — Strategy.signIn 본문은 Notifier 위임만 수행, `socialLink-
   InProgress.begin/end` 직접 호출 절대 금지.

5. **Registry add-only** — `lib/core/auth/auth_strategies_registry.dart` 의
   `_allStrategies` 끝줄에 1줄 추가. 기존 Google/Apple/Facebook/Kakao 위치
   무변경.

6. **Helper resolver** —
   `lib/features/auth/presentation/_helpers/social_provider_resolver.dart`
   switch 에 1줄 추가 (Pitfall 6 단일 진실원). 본 1줄로
   LoginScreen / LoginPromptSheet 2 화면의 ref.listen for-loop 자동 반영
   (Phase 16.1 — SignupScreen 삭제, 소셜 진입점 2곳으로 단일화).

7. **ARB keys × 3 로케일** — `auth{Provider}SignIn` (소셜 버튼 라벨) +
   `authAccountProvider{Provider}` (Account 카드 라벨) × en/ko/ja 3 파일 +
   `flutter gen-l10n` 자동 호출.

8. **SocialButton 분기** —
   `lib/features/auth/presentation/_widgets/social_button.dart` 의 `build()`
   첫 줄 if 분기 + `_build{Provider}Button` 메서드 + 색 상수 (각 Brand
   Guideline). Kakao 가 sign_in_button 패키지 미지원 provider 의 표본 패턴
   (Material+InkWell+SVG 직접 그리기) — Naver / LINE / Yahoo!JP 모두 동일
   패턴.

9. **Cloud Function** —
   `functions/src/auth/{provider}_custom_token.ts` 신규. Phase 12
   `kakao_custom_token.ts` 미러:
   - `setGlobalOptions` region 자동 상속 (asia-northeast3)
   - `enforceAppCheck: true` + `secrets: [PROVIDER_*_SECRET]`
   - `resolveIdentity(db, {provider, providerUserId, callerUid})` helper 재
     사용 (Phase 12 의 `functions/src/auth/identity_index.ts` 단일 진실원
     — Phase 13~16 모두 같은 helper 호출)
   - 검증 helper 는 OIDC verifier 가 Phase 14 LINE 진입 시 일반화 (D-08)

각 phase 마다 본 manual 의 Kakao 단락 + Phase 12 D-07 검증 매트릭스 + 실
provider 공식 문서 재확인 의무.

---

## Cloud Functions 배포 / Remote Config Kill Switch (Phase 11-04)

> 본 단락은 Phase 11-04 SUMMARY 의 사용자 매뉴얼 카드를 통합한 것입니다.
> Phase 12+ 의 신규 Cloud Function (Naver/LINE/Yahoo!JP) 도 동일
> 패턴 적용.

### Functions 추가 절차 (Phase 12 ~ 15 의 ping 패턴 복제)

1. `functions/src/auth/{provider}_custom_token.ts` 또는 신규
   `functions/src/index.ts` 에 새 `onCall` export 추가:
   ```typescript
   export const myFunction = onCall(
     {enforceAppCheck: true, secrets: [MY_SECRET]},
     async (request) => {
       if (!request.auth) throw new HttpsError('unauthenticated', 'errorUnauthenticated');
       logger.info({event: 'my_function_invoked', uid: request.auth.uid}, 'invoked');
       return { /* result */ };
     },
   );
   ```
2. `functions/test/auth/{provider}_custom_token.test.ts` 작성 —
   `firebase-functions-test` 패턴 (기존 `kakao_custom_token.test.ts` 미러).
3. Secrets: `firebase functions:secrets:set MY_SECRET` +
   `defineSecret('MY_SECRET')`.
4. `cd functions && pnpm run lint && pnpm run build && pnpm test` 풀 게이트
   GREEN 확인.
5. 배포: `firebase deploy --only functions:myFunction`.

### RC Kill Switch 운영 절차 (Emergency Disable)

Phase 11-04 의 `auth_provider_{providerId}_enabled` Remote Config 키로 운영
중 특정 provider 를 즉시 비활성화할 수 있습니다.

1. <https://console.firebase.google.com> → 프로젝트 선택 → 좌측 "Engage >
   Remote Config".
2. **새 매개변수 만들기** 또는 기존 `auth_provider_kakao_enabled` 수정.
3. 데이터 유형: Boolean, 기본값: `false` (disable) / `true` (enable).
4. **변경사항 게시 (Publish)** 클릭.
5. 사용자가 다음 앱 실행 시 (대부분 12시간 안에) 자연 반영.
   - dev flavor 는 즉시 (`minimumFetchInterval=Duration.zero`).

**제약 (Phase 11 D-26 truth table):**
- 정적 config (`config/{flavor}.json`) 의 `enabledAuthProviders` CSV 에서
  특정 provider 가 빠진 경우 RC 로 켤 수 없음 (정적 false 절대 우위).
  정적 enable 후 RC 로 disable 만 가능.

---

## Kakao Brand Asset 라이센스 / 출처 (Phase 12-07) — DEPRECATED

> **⚠ 본 단락은 Phase 13.1 마이그레이션 후 stale 입니다.**
>
> Phase 13.1 (2026-05-08~10) 에서 Kakao brand asset 은 hand-crafted SVG
> (`assets/icons/kakao_logo.svg`, 18×18 단일 검정 심볼) → **Kakao 공식 PNG**
> (`assets/brand/kakao/{ko,en}/light/kakao_login_{medium,large}_wide.png`,
> 600×90 wide 자상) 으로 마이그레이션되었습니다. 18dp icon 슬롯 패턴은
> wide 자상 통째 buttons 패턴으로 폐기되었습니다 (Phase 13.1 Gap-1 X2).
>
> **모든 절차는 [Brand Asset Management (Phase 13.1)](#brand-asset-management-phase-131)
> 단락을 참조하십시오.** Kakao 자상 출처 / 라이선스 / freshness 갱신은
> Phase 13.1 단락의 표 + `assets/brand/kakao/README.md` 가 단독 권위.

### ⚠ 변경 금지 항목 (DEPRECATED — Phase 13.1 자산 변형 정책 참조)

- 색상 / 회전 / 비율 / 단순화 변형 모두 금지 — Phase 13.1 단락 "자산 변형
  정책" 의 Naver/Kakao/Google 항목이 단독 권위.
- **ColorFilter 적용 금지 (R3/R4)** — `ColorFilter.mode(BlendMode.srcIn)`
  가이드 (구) → PNG/SVG 자상은 색 변환 없이 직접 렌더 (신).
- 18×18 logical px 비율은 wide 자상 통째 buttons 패턴 도입 후 무효화 — 자상
  자연 종횡비 (Kakao 600×90 wide) 보존.

### ⚠ Production 빌드 전 의무 (DEPRECATED — Phase 13.1 1단계 참조)

starter-kit clone 직후 `assets/brand/kakao/{ko,en}/light/` 에 Kakao 공식
PNG 자상이 commit 되어 있습니다 (Phase 13.1 commit). 사용자는
**[Brand Asset Management (Phase 13.1)](#brand-asset-management-phase-131)
단락의 1단계** 의 공식 BI URL 재방문 + freshness 갱신 절차를 따르십시오.

---

## Account Linking & Withdrawal

> Phase 16 D-05~D-16 + Phase 9.2 R1 부활 + Phase 14.1 A6 root cause fix. 최종 수정일: 2026-05-29 (Plan 16-06).

본 단락은 Phase 16 에서 추가된 동일 이메일 Account Linking 와 회원탈퇴 (Hard delete + GDPR right-to-be-forgotten) flow 의 사용자 매뉴얼이다. Phase 9.2 P-A-narrow 시점에 deferred 됐던 R1 (provider-aware account-exists 메시지) 가 Phase 16 D-12 wiring 으로 부활됐고, 회원탈퇴 (Plan 9.2 deferred) 가 Plan 16-06 까지 완성됐다.

### 동일 이메일 Account Linking

**진입 시나리오 (D-01~D-04):** 사용자가 이미 Google 로 가입한 이메일 (예: user@gmail.com) 로 Apple 로그인을 시도하면 Firebase Auth 가 `account-exists-with-different-credential` 코드와 함께 충돌 이메일을 반환한다. 본 starter-kit 은 다음과 같이 동작한다:

1. **server-side `lookupSignInMethods` callable** (Plan 16-02) — 충돌 이메일에 대한 기존 provider 식별. identity_index 컬렉션 (Plan 16-03) 의 `conflictKind.existingProvider` 또는 Firebase Auth 의 `fetchSignInMethodsForEmail` 결과를 매핑한다.
2. **client-side `AccountLinkingSheet`** (Plan 16-04) — Material 3 Modal Bottom Sheet 본체. 본문 메시지는 provider-aware (예: "이 이메일은 Google 로 가입되어 있습니다. Google 로 로그인하여 계정을 연결하세요.") + 단일 BrandedSocialButton (D-02 single button 정책 — 정확한 기존 provider 만 노출하여 사용자 confusion 차단) + dismiss TextButton (D-03 cancel — Navigator.pop(false)).
3. **native↔native vs Custom Token 분기 (D-04):**
   - **Native 4 provider (Google/Apple/Facebook/Email):** Firebase Auth 의 `User.linkWithCredential` 로 직접 연결.
   - **Custom Token 4 provider (Kakao/Naver/LINE/Yahoo!JP):** `linkCustomTokenProvider` callable (server-side hybrid) — 외부 IdP 토큰을 server 에서 검증 후 Firebase Custom Token 으로 변환하여 link.
4. **사용자 cancel 시 state 손실 0 (D-03):** sheet 의 dismiss 또는 backdrop tap 시 기존 세션 / onboarding 상태는 모두 보존. `Navigator.pop(false)` 만 호출 → caller 의 catch path 가 fresh 진입점으로 fallback.

**PII invariant (T-16-NEW-07):** `lookupSignInMethods` 호출의 collisionEmail 본문은 client logger / Crashlytics payload 에 절대 전파되지 않는다 (memory `feedback_test_lint_quality` 의 `__` 금지 + Plan 16-04 R7 sentinel test).

#### 충돌 시 안내 시트의 동작 — 2단계 플로우 (Phase 16 gap closure, 2026-09-08 갱신)

**동작 요약:** 이미 가입된 이메일로 **다른 소셜 로그인**을 시도하면, 앱은 (1) 그 이메일이 **어떤 수단으로 가입돼 있었는지 정확한 이름**을 안내 시트에 표시하고, (2) 시트의 버튼은 **그 수단으로 로그인**시킨 뒤, (3) 다른 로그인 수단을 추가하고 싶으면 **설정 > 계정 연결**에서 하도록 안내한다. 즉 시트 버튼 한 번으로 두 계정이 자동 연결되지는 않는다 — **로그인(1단계) → 계정 연결(2단계)** 두 걸음이다.

**왜 자동 연결이 아닌가.** 충돌 시트가 떠 있는 시점의 사용자는 **아직 로그인되지 않은 상태**다. 계정 연결은 "이미 로그인한 계정에 다른 수단을 덧붙이는" 동작이라 로그인되지 않은 상태에서는 성립할 수 없다. 예전 구현은 이 시점에 곧바로 연결을 시도했기 때문에 실질적으로 항상 실패했다. 그래서 지금은 **먼저 로그인시키고**, 연결은 로그인 이후 화면(설정)에서 하도록 나눴다.

**사용자가 보게 되는 흐름:**

1. 이미 가입된 이메일로 다른 소셜 로그인 시도 → 안내 시트가 뜬다.
2. 시트 본문에 **기존 가입 수단의 정확한 이름**이 표시된다 (예: 카카오로 가입한 계정이면 "카카오"). 여기에는 Google / Apple / Facebook 같은 네이티브 수단뿐 아니라 **Kakao / Naver / LINE / Yahoo! JAPAN 같은 Custom Token 수단도 포함**된다 — 이전에는 Custom Token 으로 가입한 계정의 이름을 서버가 알아내지 못해 충돌 자체가 감지되지 않았다.
3. 시트의 브랜드 버튼(예: "카카오로 로그인하기") 탭 → **그 수단으로 로그인**이 진행된다.
4. 로그인 성공 → 시트가 닫히고 홈으로 이동하면서 `{수단} 계정으로 로그인했습니다. 다른 로그인 수단은 설정 > 계정 연결에서 추가할 수 있습니다.` 안내가 잠깐 표시된다 (ko / en / ja 3 locale).
5. 사용자가 원하면 **설정 > 계정 연결**에서 다른 수단을 추가한다 (이 화면이 본 매뉴얼 위쪽의 proactive linking 경로다).
6. 취소하거나 로그인이 실패하면 시트는 그대로 유지되고 계정 상태는 아무것도 바뀌지 않는다.

**Naver 에 대한 주의 (지원 범위가 방향에 따라 다르다):** Naver 는 **로그인 대상으로는 완전히 지원**된다 — 위 3단계에서 "네이버로 로그인하기" 버튼은 정상 동작한다. 그러나 **연결 대상으로는 아직 미지원**이다 — 이미 로그인한 계정에 Naver 를 덧붙이는 경로는 Cloud Function 쪽 OIDC 검증기가 없어 Phase 17 이후로 미뤄져 있다. 설정 > 계정 연결 목록에서 Naver 를 고르면 "지원하지 않는 수단" 안내가 뜬다.

**adopter 가 건드릴 수 있는 지점:** 안내 문구는 ARB 키 `accountLinkingSignInThenLinkHint`(`lib/l10n/app_{ko,en,ja}.arb`) 하나이며 `{provider}` placeholder 에는 **기존 provider 라벨 8 키의 값만** 주입된다(서버 응답 문자열이 그대로 화면에 뜨는 경로는 없다). 시트 자체의 분기는 `lib/features/auth/presentation/_widgets/account_linking_sheet.dart`, 로그인 위임은 `lib/features/auth/data/auth_repository.dart` 의 `signInWithExistingProvider`, 서버측 provider 판별은 `functions/src/auth/identity_index.ts` 다.

**로그 / 문서 PII 정책 (T-16-16-01 상속):** 본 단락과 이 매뉴얼 전체는 실제 계정 이메일, Firebase 사용자 식별자, App Check 디버그 토큰, 단말 시리얼을 기재하지 않는다. Firestore 확인 절차는 `users/{uid}` 같은 **일반형 표기**만 사용한다.

### 회원탈퇴 (Hard delete + GDPR right-to-be-forgotten)

**GDPR 명시:** 본 starter-kit 의 탈퇴 flow 는 **계정과 데이터가 영구 삭제** 되며 **복구 불가** 하다. 사용자에게는 다음 3-line GDPR 경고가 표시된다 (UI-SPEC Surface C verbatim — withdrawalDialogBodyLine1/2/3):

1. "이 계정과 모든 데이터는 영구 삭제됩니다."
2. "삭제 후에는 복구할 수 없습니다."
3. "다시 가입하려면 동일 이메일 또는 동일 로그인 방식으로 신규 등록해야 합니다."

**진입 path (D-05~D-08):**

```
Home AppBar → Icons.settings tap → /settings route
   → Settings screen (계정 section + Danger zone section)
   → Danger zone "회원탈퇴" ListTile tap (Theme.colorScheme.error 강조)
   → WithdrawalConfirmationDialog (AlertDialog)
   → 3-line GDPR 경고 표시
   → TextField "탈퇴" verbatim 입력 (verbatim match 만 confirm 활성화)
   → destructive FilledButton (errorColor 배경) tap
   → SettingsRepository.requestAccountDeletion()
     → FirebaseAuth.currentUser.getIdToken(true) — fresh ID Token 발급
       (D-06 의 5분 auth_time boundary 통과 baseline)
     → deleteUserAccount callable 호출 ({'idToken': idToken})
   → 성공: withdrawalSuccess SnackBar + signOut → /onboarding 자동 reset
   → reauth fail (5분 boundary 초과): withdrawalReauthRequired SnackBar
     + /login redirect (재로그인 후 재시도)
   → server fail: withdrawalFailure SnackBar (dialog 유지 — 재시도)
```

**destructive UX 가드 (D-08):**

- **`barrierDismissible:false`** — dialog 표시 중 backdrop tap 무시.
- **confirmTextField verbatim match** — ko="탈퇴" / en="delete" / ja="削除" 의 정확한 일치 만 confirm 버튼 활성화. partial input (예: "탈") 으로는 활성화 안 됨.
- **destructive FilledButton** — `Theme.colorScheme.error` 배경 + `colorScheme.onError` 전경.
- **Semantics destructive intent** — 스크린리더 사용자에게 "회원탈퇴 — 영구 삭제, 복구 불가" 명시 (UI-SPEC line 332 Warning 7 채택, `withdrawalConfirmActionSemantic` ARB key consume).
- **loading 중 cancel 버튼 비활성화** — callable 진행 중 사용자 실수 차단.

**5분 boundary 의미:** `getIdToken(true)` 의 forceRefresh 호출은 새 ID Token 을 발급하여 `auth_time` claim 을 현재 시각으로 갱신한다. server-side `deleteUserAccount` Cloud Function 은 token 의 `auth_time` 가 5 분 이내인 경우에만 hard delete 를 수락한다 (D-06). 사용자가 dialog 표시 후 다른 작업으로 시간을 보낸 경우 reauth fail SnackBar 가 표시되고 /login redirect 된다.

### 약관 동의 서버 기록 (Custom Token provider — Phase 16 G-16-A9-1)

**동작:** Custom Token provider (Kakao / Naver / LINE / Yahoo!JP) 로 가입할 때 클라이언트가 약관 동의 스냅샷 5 필드 (동의 버전 / 이용약관 동의 / 개인정보 처리방침 동의 / 마케팅 수신 동의 / 동의 시각) 를 callable payload 의 `termsAcceptanceSnapshot` 으로 함께 보내고, Cloud Function 이 `users/{uid}` 문서를 **생성하는 같은 시점에** `termsAccepted` 로 기록한다. native provider (Google / Apple / Facebook) 는 Cloud Function 이 사용자 문서를 만들지 않으므로 클라이언트 mirror 경로 (`TermsNotifier.mirrorToFirestore`) 가 그대로 유효하다.

이 구조를 쓰는 이유는 경합 때문이다. Custom Token 경로에서는 Cloud Function 이 먼저 `users/{uid}` 를 만들고, 그 뒤에 실행되는 클라이언트 mirror 가 "이미 문서가 있다 = 기존 사용자" 로 판단해 skip 한다. 따라서 **문서 생성 시점에 서버가 직접 기록하는 것** 이 유일하게 경합이 없는 지점이다.

**백필 정책 (adopter 결정 사항):** 이 수정 **이전에** Custom Token 으로 가입한 사용자는 서버측 동의 기록이 없다 (클라이언트 로컬 `SharedPreferences` 에만 남아 있어 재설치·기기 변경 시 소실된다). 본 starter-kit 은 **자동 백필을 제공하지 않는다** — 재동의를 받을지, 운영자 스크립트로 채울지, 그대로 둘지는 서비스의 법무·운영 정책에 달렸고 starter-kit 이 임의로 정할 수 없기 때문이다. 백필이 필요하면 `users` 컬렉션에서 `termsAccepted` 필드가 부재한 문서를 골라 처리하는 **1회성 관리자 작업** 으로 수행하고, 위 「사용자 커스터마이징 포인트」 5번의 **법무 자문 의무** 를 함께 적용한다 (어떤 값을 소급 기록해도 "실제 동의 시각" 은 아니므로, 소급 기록 자체가 법적으로 유효한지에 대한 판단이 선행되어야 한다).

**잔여 위험 — 재동의 시각 갱신:** 서버 mirror 는 신규 가입 여부로 게이트되지 않는다. 따라서 기기에 동의 값이 남아 있는 상태에서 **기존 계정으로 재로그인** 하면 `termsAccepted.acceptedAt` 이 현재 세션 시각으로 갱신된다. 최초 동의 시각을 불변 audit 으로 남겨야 하는 서비스는 4개 Custom Token endpoint 의 mirror 블록을 **신규 사용자일 때만** 실행하도록 한 줄 게이트를 추가하면 된다 (파일: `functions/src/auth/{kakao,naver,line,yahoojp}_custom_token.ts` 의 mirror 단계 — 각 endpoint 가 이미 계산해 둔 신규/기존 사용자 판별값을 조건으로 쓴다). 기본값을 게이트 없이 둔 이유는 **최신 동의 상태 반영** 을 우선했기 때문이다 — 약관 버전이 올라간 뒤 재동의를 받은 경우 그 시각이 반영되는 편이 일반적인 서비스에서 더 안전하다.

**확인 방법:** Firestore `users/{uid}` 문서에 `termsAccepted` 5 필드가 존재하는지 확인한다. 없다면 (a) 이 수정 이전에 가입한 사용자이거나, (b) 로그인 시점에 기기 로컬 동의 값이 없어 클라이언트가 스냅샷을 아예 부착하지 않은 경우다. 두 경우는 Cloud Logging 의 `{provider}_terms_acceptance_mirrored` 이벤트 유무로 구분한다.

**mirror 실패는 로그인을 실패시킨다.** 4개 endpoint 모두 mirror 의 `set(merge:true)` 가 던지면 `{provider}_terms_acceptance_mirror_failed` 를 남긴 뒤 `HttpsError('internal')` 로 callable 을 실패시킨다 — 동의 기록 없이 계정만 생성되는 상태를 만들지 않기 위한 의도된 fail-closed 설계다. 따라서 "로그인은 성공했는데 `termsAccepted` 만 없다" 는 상태는 위 (a)/(b) 뿐이며, mirror 실패로는 발생하지 않는다.

### Phase 17 deferred — Storage cascade

본 Phase 16 의 `deleteUserAccount` Cloud Function 은 다음을 삭제한다:

- Firebase Auth user record (Admin SDK `auth().deleteUser(uid)`).
- Firestore `users/{uid}` document + sub-collections (best-effort batch).
- Firestore `identity_index/{provider}:{providerUserId}` 매핑 (Phase 12+ 도입, D-16).

**Cloud Storage cascade 는 Phase 17 deferred:** 본 starter-kit 은 현재 Cloud Storage 사용처가 0 이므로 Storage cleanup trigger 가 정의되어 있지 않다. 사용자가 신규 프로젝트에서 Cloud Storage 를 도입할 때는 다음 중 하나의 cascade 전략을 선택해야 한다:

1. **Firestore trigger 기반 cascade** — `users/{uid}` document 삭제 onDelete 시 Cloud Storage `gs://app/users/{uid}/**` 일괄 삭제 (Cloud Functions 2nd gen).
2. **Storage Security Rules + lifecycle** — 객체 metadata 의 ownerId 가 Firebase Auth user 와 일치하지 않는 객체를 GCS lifecycle 로 자동 삭제 (eventual consistency, 1~24h).

선택 가이드: 즉시 cleanup 의무 (GDPR 30 일 이내) 가 있으면 1, 운영 단순화 우선이면 2.

### App Check debug provider 등록 절차

Phase 11 D-11 에서 도입된 App Check enforcement (`enforceAppCheck:true` onCall) 는 dev 단말에서도 활성화된다. dev 환경 단말 (예: Samsung Galaxy SM F966N, iOS Simulator) 에서 `deleteUserAccount` callable 가 `unauthenticated` 코드로 reject 되는 경우 App Check debug provider 등록이 누락된 것이다 (Phase 16 Plan 16-06 의 reauth fail 분기와 동일 user-facing surface 라 trial-and-error 시간 낭비 발생 — 본 절차 우선 확인).

**등록 절차:**

1. **dev 단말에서 debug token 확보** — `flutter run --flavor dev` 실행 후 logcat (Android) / Xcode Console (iOS) 의 `[FirebaseAppCheck/Debug]` prefix 안 token UUID (예: `12345678-90ab-cdef-1234-567890abcdef`) 확보.
2. **Firebase Console App Check 탭 이동** — Firebase Project Settings → App Check → 해당 app 의 "Manage debug tokens" 클릭.
3. **debug token 등록** — UUID 입력 + 별칭 (예: "Galaxy SM F966N dev") + Save. debug token 은 동일 단말에서 영구 유효 (앱 재설치 시 새 token 발급 → 재등록 필요).
4. **enforceAppCheck 검증** — 재실행 시 `deleteUserAccount` callable 가 정상 응답 (또는 비즈니스 로직 분기) 확인.

본 절차는 Phase 11 의 App Check 도입 시점에 manual.md 의 다른 단락에 정의돼 있을 수 있으나, Plan 16-06 시점의 cross-reference 안전 차원에서 본 단락에도 명시.

### 사용자 커스터마이징 포인트

본 starter-kit 사용자가 자신의 프로젝트에서 변경할 수 있는 surface:

1. **ARB 라벨 변경 (provider 라벨, dialog 본문):**
   - `lib/l10n/app_{en,ko,ja}.arb` 의 `withdrawalDialogBodyLine1/2/3` — GDPR 경고 문구 변경 (단, 법적 의무 보존 검증 의무).
   - `withdrawalConfirmFieldHint` — 사용자 입력 verbatim phrase 변경 (ko="탈퇴" → 예: "확인", en="delete" → 예: "permanently delete"). 변경 시 widget test WC3/WC4 의 expected 값 동기화 의무.
   - `errorAccountExistsWithProvider` — provider-aware 메시지 본문.
2. **AccountLinkingSheet 의 mirror 패턴 (LoginPromptSheet 위 1-provider 강조 vs n-provider 전체):**
   - 본 starter-kit 은 D-02 의 single button 정책 (정확한 1 provider 만 표시). n-provider 전체 (예: AccountLinkingSheet 안에서 모든 8 provider 를 노출하여 사용자가 "어떤 provider 로 가입했는지 모를 때 모두 시도" UX) 를 채택하려면 `lib/features/auth/presentation/_widgets/account_linking_sheet.dart` 의 `_BrandedLinkButton` exhaustive switch 를 `AccountProvider.values` iterate 로 교체.
3. **WithdrawalConfirmationDialog 의 confirmTextField verbatim 변경:**
   - 사용자 confusion 차단 의도가 약한 환경 (예: B2B 어드민 도구) 에서는 verbatim match 가드 자체를 폐기 가능. `_verbatimMatch` flag 를 `true` 상수로 교체.
4. **deleteUserAccount Cloud Function 본문 (Plan 16-02 산출):**
   - Firestore `users/{uid}` 외 cascade 대상 (예: notifications 컬렉션, push token 등록) 가 있는 경우 callable 본문에 batch 추가.
   - Cloud Storage cascade (위 Phase 17 deferred 참조).
5. **법무 자문 의무:** 본 starter-kit 의 GDPR 명시는 일반적 사용 사례를 가정한 baseline. 실제 production 에서는 변호사 / DPO (Data Protection Officer) 자문 의무 — 본 starter-kit 의 manual.md 단락 verbatim 채택은 사용자 책임 범위 (memory `project_starter_kit_review_ready_scope` mirror — starter-kit 검수 scope = review-ready, 신청 / deploy 제외).

---

## 회원탈퇴 cleanup TODO (Phase 16)

현재 starter kit 의 회원탈퇴 흐름은 다음 cleanup 작업이 누락된 상태입니다
(Phase 16 의 Account Linking 일반화 단계에서 일괄 도입 예정):

- **`identity_index/{provider}:{providerUserId}` 문서 cleanup** — 회원탈퇴
  시 사용자가 등록한 Kakao / Naver / LINE / Yahoo!JP 의 매핑 문서가
  잔존. 같은 외부 계정으로 재가입 시 first-write-wins 정책 (D-12) 으로
  기존 매핑이 우선되어 새 UID 가 아닌 기존 (탈퇴된) UID 로 매핑되는
  결함 가능성.
- **Native 4 provider (Email/Google/Apple/Facebook) 의 `linkedProviders`
  회고 등록** — Phase 12 의 Identity Index 컬렉션 등록은 Custom Token
  provider 만 자동. Native 4 provider 도 Phase 16 에서 회고 등록 후 통합
  관리 예정.
- **충돌 UI** — 동일 외부 계정이 다른 Firebase UID 에 등록된 상태에서 새
  사용자가 같은 계정으로 로그인 시 "이 카카오 계정은 다른 앱 계정에
  등록됐습니다. 통합할까요?" 다이얼로그 (Plan 10-06 의 `account-exists-with-
  different-credential` 패턴 확장).

starter kit 사용자가 production 진입 시점에 회원탈퇴 / Account Linking
플로우를 자체 구현하거나 Phase 17 도입 후 본 starter kit 의 후속 버전을
merge 하는 두 가지 옵션 중 선택.

---

## Git Hooks 활성화 (선택)

starter-kit 의 `scripts/check_phase_refs.sh` 는 코드 주석의 `Phase NN`
참조와 `TODO` 주석을 진실원 (`ROADMAP.md` 의 active phase 또는
`.planning/todos/pending/<file>.md` ad-hoc todo) 과 양방향 검증한다.

production 진입 시 deferred 항목 추적에 유용. starter-kit 단순성을 위해
CI 별도 도입 없이 git pre-commit hook 으로만 강제 (필수 아님 — D-39).

활성화 (clone 직후 1회):

```bash
# scripts/git-hooks/pre-commit 을 .git/hooks/pre-commit 으로 symlink.
# .git/hooks/ 디렉토리 자체는 git tracked 불가 — scripts/git-hooks/pre-commit
# 만 tracked 상태로 두고 symlink 로 활성화한다.
ln -s ../../scripts/git-hooks/pre-commit .git/hooks/pre-commit
chmod +x .git/hooks/pre-commit
```

이후 commit 시점에 자동 lint. mismatch 시 commit 차단 + 차이 요약 출력.

수동 실행 (활성화 없이 1회 검증):

```bash
bash scripts/check_phase_refs.sh
```

비활성화: `rm .git/hooks/pre-commit`.

검증 규칙 요약:

| TODO / Phase 참조 | Pass / Fail |
|-------------------|-------------|
| `// TODO: Phase 8 후속 — Crashlytics.recordError (.planning/todos/pending/...md)` | PASS (todo 파일 인용) |
| `// Phase 17 — see ROADMAP.md` | PASS (ROADMAP 인용) |
| `// TODO(phase-08): ...` | FAIL (raw — 진실원 미명시) |
| `// TODO: dedicated NotFoundScreen` | FAIL (raw — 진실원 미명시) |
| `// Phase 99 — see ROADMAP.md` | FAIL (Phase 99 가 ROADMAP 미존재) |

> ⚠ 이 hook 은 `scripts/check_phase_refs.sh` 만 실행하며 **dart format 은 검사하지 않는다** — 커밋 전 `fvm dart format --output=none --set-exit-if-changed lib test` 를 별도로 실행할 것 (미실행 시 drift 누적: quick `260909-mwh` 에서 91개 파일 일괄 정리).

---

## Brand Asset Management (Phase 13.1 + 13.2)

<!-- Updated by Phase 13.2 retroactive: R13 — Facebook entry 갱신 (Meta 공식 자상 + 라이선스 verbatim + Phase 18 단어 폐기) -->

본 단락은 starter-kit 의 social provider brand asset 출처·라이선스·다운로드·
freshness 갱신 정책을 정리한다. 7 provider (Kakao / Naver / Google / Apple /
Facebook / LINE / Yahoo!JP) 자산 모두 단일 표준 디렉토리 (`assets/brand/{provider}/`)
+ 7필드 README schema 를 따른다. Phase 13.2 진입으로 Facebook 도 Meta 공식
Brand Resource Center 자상 마이그 완료 (D-95 PNG / D-94 theme 부재 / D-96
Google 패턴 locale 독립).

> **⚠ 미래 갱신자 함정 경고 #2 (Phase 13.1 Gap-1 X2 — 자상 layout 패턴):**
> Phase 13.1 Plan 13.1-05 초기 코드는 wide 자상 (Kakao 600×90 / Naver
> 1472×192 / Google viewBox 189×40) 을 sign_in_button 패키지 모방 패턴
> (`Container + Row(18dp icon + ARB 라벨)`) 의 18dp icon 슬롯에 fit 시도 →
> 자상이 squash 되어 회색 작은 막대로만 보이는 시각 결함 (사용자 보고 4
> issue, VERIFICATION.md Gap-1). Plan 13.1-14 재설계로 wide 자상 통째 buttons
> 패턴 도입 + Plan 13.1-15 4-round 시각 검증 deviation 흡수 (`Image.asset
> (fit: BoxFit.contain)` / `SvgPicture.asset(fit: BoxFit.contain)` +
> ClipRRect wrapper 폐기 + Material `clipBehavior: Clip.none` + InkWell
> `borderRadius: 12dp` ripple 영역만 제어) 채택 — 자상이 buttons 외관 전체를
> baked-in 으로 형성, 자상의 baked-in 모서리 (Naver 사각 / Kakao 7.2px
> scaled / Google rx=19.5 pill) 가 시각 단독 권위. letterbox 영역 (Kakao
> 좌우 ~20dp / Google 좌우 ~67dp / Naver 1dp 미세) Scaffold 배경 자연 채움.
> 미래 갱신자가 자상 layout 변경 시 **반드시 사전 검토:**
>
> 1. Wide 자상 (가로 비율 ≥ 4:1) 은 자상 통째 buttons 패턴 사용 의무 —
>    18dp icon 슬롯 패턴 회귀 금지.
> 2. ARB 라벨 시각 layer 추가 금지 (Kakao/Naver/Google 분기) — 자상에
>    label baked-in. Apple/Facebook 만 ARB 라벨 명시 의무 (위제 위임).
> 3. PNG / SVG 양쪽 `fit: BoxFit.contain` + `width: double.infinity`
>    + `height: spec.height` 강제 sizing 의무 — `BoxFit.fitWidth` 회귀 시
>    wide 자상 자연 종횡비 무시 + 상하 잘림 + 텍스트 1.9× 확대 결함 (Plan
>    13.1-15 round 2 사용자 보고).
> 4. ClipRRect wrapper 폐기 + Material `clipBehavior: Clip.none` + InkWell
>    `borderRadius: 12dp` (ripple 영역만 제어) — ClipRRect 12dp 강제 또는
>    Material `Clip.antiAlias` 회귀 시 자상 baked-in 모서리 추가 클립 결함
>    (Plan 13.1-15 round 3/4 사용자 보고).
> 5. en fallback 정책: ko 외 모든 locale (ja, fr, de, zh 등) 은 en 자상
>    path 로딩 — `_iconAssetFor` 의 `languageCode == 'ko' ? 'ko' : 'en'`
>    분기 보존. 신규 locale 추가 시 자상 ko/en 양쪽 commit 의무 또는 en
>    fallback 채택.

> **⚠ 미래 갱신자 함정 경고 (Plan 13.1-07 retro):** Phase 13.1 초기 plan 은
> "1x / 2x / 3x density bucket × ko/en" 으로 자상 차원을 가정했으나, 다운로드
> 후 Kakao / Naver / Google 모두 공식 제공 형식이 plan 가정과 다름을 발견 —
> Kakao 는 사이즈+가로비율 변형, Naver 는 5차원 매트릭스 (theme × locale ×
> color × variant × height) 64 PNG, Google 은 5차원 매트릭스 (platform ×
> format × theme × shape × label) 360+ 파일. 1년 후 자산 갱신 시 동일
> 함정에 빠지지 않도록, 본 단락의 "Provider 별 채택 차원 매트릭스" 와 각
> `assets/brand/{provider}/README.md` 의 "자산 형식 결정" 단락을 **반드시**
> 먼저 읽고 공식 페이지의 현재 제공 형식과 대조하라.

### 자산 디렉토리 구조

```
assets/brand/
├── kakao/{ko,en}/light/kakao_login_{medium,large}_wide.png + LICENSE.txt + README.md
│   # Plan 13.1-07 retro: 사이즈+가로비율 변형 (NOT 1x/2x/3x density), light only, 4 PNG
├── naver/{ko,en}/{light,dark}/naver_login_h{48,56}_wide.png + LICENSE.txt + README.md
│   # Plan 13.1-07 retro: Kakao 의 2배 차원 (light/dark 추가), 8 PNG.
│   # light → 흰 배경 위 그린 BI, dark → 검정 배경 위 흰 BI (Naver BI 사용 패턴)
├── google/{light,dark,neutral}/btn_signin_{full,icon}.svg + LICENSE.txt + README.md
│   # Plan 13.1-07 retro: Android × rd × ctn 채택, 6 SVG. cross-platform 사용 라이선스 무관
├── apple/README.md          # SDK 위제 (sign_in_with_apple ^8.0.0), 자상 commit 없음
├── facebook/facebook_login.png + LICENSE.txt + README.md
│   # Phase 13.2 — Meta 공식 자상 (Primary Logo, 2084×2084 PNG, D-95 lock)
│   # D-94 theme 부재 (단일 #1877F2 변형) / D-96 Google 패턴 locale 독립 ('f' 마크 단독)
├── line/{en,ko,...}/btn_signin_icon.svg + LICENSE.txt + README.md
│   # Phase 14 D-LINE-08 (2026-05-19): sentinel → active 전환 (Symbol SVG)
└── yahoojp/SVG/yahoo_japan_icon_white_64.svg + LICENSE.txt + README.md
    # Phase 15 D-YJP-07 (2026-05-22): sentinel 미경유 신규 active 진입
```

### Provider 별 출처 + 라이선스

| Provider | 공식 BI URL | 자산 형식 | 라이선스 | 사용자 사전 검수 |
|----------|------------|-----------|---------|-----------------|
| Kakao    | https://developers.kakao.com/docs/ko/kakaologin/design-guide | PNG + PSD | Kakao Resources Terms | N/A (가이드 준수만) |
| Naver    | https://developers.naver.com/docs/login/bi/bi.md | PNG + Figma + AI | NAVER Brand License | **사용자 책임** (가이드 준수 — starter-kit 은 검수 자동화 미제공) |
| Google   | https://developers.google.com/identity/branding-guidelines | SVG | Google Terms of Service | N/A |
| Apple    | https://developer.apple.com/design/human-interface-guidelines/sign-in-with-apple | (SDK 위제) | Apple HIG (`sign_in_with_apple` 패키지 BSD-3-Clause) | N/A |
| Facebook | https://www.meta.com/brand/resources/facebook/logo/ + https://developers.facebook.com/docs/facebook-login/userexperience/ | PNG (Primary Logo, 2084×2084) | Meta Brand License (`Meta's trademarks are owned by Meta and may only be used as provided in these guidelines or with Meta's permission.` verbatim) | **사용자 책임** (Wave 0 응답 verbatim — Meta Brand Resource Center 다운, Phase 13.2 완료) |
| LINE     | https://developers.line.biz/en/docs/line-login/login-button/ | PNG + PSD (19 언어) | LINE Branding License | **사용자 책임** (Phase 14 진입 시) |
| Yahoo!JP | https://developer.yahoo.co.jp/yconnect/v2/ | SVG (64×36 viewBox) | Yahoo! JAPAN Brand Guideline | **사용자 책임** (Phase 15 진입 시) |

**D-Note (Phase 13.1 R1 — Naver 색상 컨텍스트 분리):** Naver 의 회사 브랜드
(`#03C75A`, NAVER Corp + NCloud SSO) ↔ 로그인 버튼 (`#03A94D`, NAVER ID
로그인 BI) 는 컨텍스트가 다르다. starter-kit 의 production 코드는 `#03A94D`
채택 (NAVER ID 로그인 BI 페이지 verbatim). 회사 브랜드 색은 starter-kit 사용
대상이 아님 — 자상 갱신 시 `#03C75A` 가 third-party 출처 (wikipedia / blog
등) 에서 발견되더라도 **무시**.

### Provider 별 채택 차원 매트릭스 (Plan 13.1-07 결정)

> 본 매트릭스는 미래 갱신자가 "Plan 가정 1x/2x/3x" 함정을 회피하기 위해
> 핵심. 각 cell 의 "공식 제공" vs "starter-kit 채택" 차이를 인지한 뒤 갱신.

| Provider | 공식 제공 차원 | starter-kit 채택 차원 | 채택 자상 수 | runtime default |
|---------|---------------|----------------------|-------------|----------------|
| Kakao   | 사이즈(medium/large) × 가로비율(wide/narrow) × 라벨(완성형/축약) × locale(ko/en) — light only | locale × size × **wide 만** (light only) | 4 PNG | `kakao_login_large_wide.png` (600×90) |
| Naver   | theme × locale × color × variant(wide/narrow/center/icon) × height(H48/H56) — 5차원 64 PNG | locale × theme × height × **wide 만** (light=green / dark=white) | 8 PNG | `naver_login_h48_wide.png` (Material 표준 button height) |
| Google  | platform(iOS/Android/Web) × format(SVG/PNG) × theme(light/dark/neutral) × shape(rd/sq) × label(ctn/SI/SU) — 5차원 360+ 파일 | **Android × SVG × theme × rd × {ctn, na}** | 6 SVG | `btn_signin_full.svg` (Android × rd × ctn) |

**Cross-platform 사용 정책 (Google):** Google Identity Branding Guidelines 가
platform 일치를 강제하지 않음 — `"You can scale the button as needed for
different devices"` verbatim 명시 (LICENSE.txt 인용). 따라서 iOS 앱에서
Android 자상 (`android_*_rd_*.svg`) 사용도 라이선스/정책 위반 아님 — Flutter
mobile single codebase 단순성 + Material framework default 일관성으로 Android
채택. 단 향후 갱신 시 cross-platform 정책 verbatim 재확인 의무 (정책 변경
가능성 — 1년 freshness 갱신 시).

### 1단계 — 자산 다운로드 (Kakao / Naver / Google)

starter-kit clone 직후 `assets/brand/{kakao,naver,google}/` 에 공식 자상 +
LICENSE.txt + README.md 가 commit 되어 있다 (Phase 13.1 commit). starter-kit
사용자가 새 프로젝트 시작 시 다음을 검토:

1. 위 표의 공식 BI 페이지 방문 → 최신 자상 갱신 여부 확인
2. 갱신 있으면 `assets/brand/{provider}/[{lang}/][{theme}/]` 에 파일 갱신
   (rename 금지 — starter-kit 명명 패턴 보존, 공식 ↔ starter-kit 매핑은
   `assets/brand/{provider}/LICENSE.txt` 에 verbatim 기록)
3. `LICENSE.txt` 의 verbatim 텍스트 갱신 (라이선스 조항 변경 시)
4. `README.md` 의 7필드 (특히 "다운로드 일자") 갱신
5. **공식 BI 정보 검증 의무:** wikipedia / seeklogo / 블로그 등 third-party
   출처 채택 금지 — 위 표의 공식 BI URL 직접 방문 + verbatim 인용 (사용자
   메모리 `feedback_official_bi_verification.md` 패턴)

### 2단계 — sentinel-active 전환 패턴 (historical, Phase 14 LINE 완료)

Phase 13.1 시점에 LINE/WeChat 자상 미commit `kPlaceholderProviders` sentinel
패턴 도입 → Phase 14 D-LINE-08 (2026-05-19) 으로 LINE 자상 commit 완료 +
Phase 16 (WeChat) 폐기 (2026-05-22) 으로 sentinel 의무 해소
(`kPlaceholderProviders = <String>[]`). 향후 placeholder 가 필요한 신규
provider 진입 시 본 패턴 재도입:

1. 공식 BI 페이지 자상 다운 (위 표의 "공식 BI URL" + "자산 형식" 참조).
2. `assets/brand/{provider}/[{lang}/][{theme}/]` 에 파일 + `LICENSE.txt` commit.
3. `_brand_assets.dart` 의 `kPlaceholderProviders` 에 슬러그 추가 +
   `assets/brand/{provider}/.placeholder` sentinel 파일 commit (sentinel
   진입). 자상 commit 완료 후 슬러그 + sentinel 파일 모두 제거 (sentinel 해제).
4. `assets/brand/{provider}/README.md` 7필드 (특히 "다운로드 일자") 갱신.
5. `fvm flutter test test/features/auth/presentation/_widgets/brand_assets_lint_test.dart`
   실행 — sentinel 진입/해제 검증의 **source-of-truth 는 본 lint test**.
   `kPlaceholderProviders.isEmpty` (모든 active 자상 commit 완료) 또는
   sentinel 파일 존재 (placeholder provider 진입) 를 자동 검증.
   production widget 의 placeholder fallback 분기는 sealed switch 가 컴파일
   시점에 처리 — sub-class 추가 시 build() 컴파일 fail 강제.

### 3단계 — 자산 freshness 갱신 (1년 권장)

각 `assets/brand/{provider}/README.md` 의 "다운로드 일자" 필드를 기준으로 1년
경과 시:

1. 공식 BI 페이지 재방문 (위 표 참조).
2. 자상 갱신 여부 확인 — 갱신 있으면 자상 + LICENSE + README 갱신, 변경
   없으면 README 의 "다운로드 일자" 만 갱신.
3. **공식 제공 차원 변동 확인** — 1단계 retro 함정 회피. 위 매트릭스의
   "공식 제공 차원" cell 이 현재 페이지와 일치하는지 검토 (예: Kakao 가
   density bucket 으로 전환했는지, Naver 가 5차원 → 6차원 확장했는지).
4. `fvm flutter test --update-goldens test/features/auth/presentation/_widgets/branded_social_button_golden_test.dart`
   재 generate (자상 갱신 시 golden 도 갱신 의무).
5. golden PNG diff review — production 코드 색/사양 drift 부재 확인.
6. `LICENSE.txt` verbatim 텍스트 변경 시 → 라이선스 조항 변경 의미 → 법무
   검토 후 적용.

### 자산 변형 정책

- **Naver / Kakao / Google:** 공식 자상만 — 자체 SVG 생성 / 색 변환 / resize
  금지. 특히 PNG 자산은 `Image.asset(... fit: BoxFit.contain)` 직접 렌더 —
  `ColorFilter.mode(BlendMode.srcIn)` 적용 시 BI 색이 단색으로 변환되어
  guideline 위반 (Phase 13.1 RESEARCH §Pitfall 7).
- **Apple:** `sign_in_with_apple` 패키지의 `SignInWithAppleButton` 위제 위임
  — Apple HIG 의 3 변형 (Sign in / Sign up / Continue) 중 starter-kit 은
  **Sign in 만** 사용. Sign up / Continue 추가는 별 phase. `borderRadius`
  인수는 `BorderRadius.circular(12)` 형태 의무 (int 12 직접 주입 시 컴파일
  에러). height 는 SDK 기본값 44 존종 (외부 SizedBox 래핑 안 함) — Naver/
  Kakao height 48 과 4dp 차이는 HIG/BI 양쪽 공식 권장값 충돌의 정상 산물.
- **Facebook:** Phase 13.2 완료 — Meta Brand Resource Center (`meta.com/brand/
  resources/facebook/logo/`) 공식 Primary Logo PNG (2084×2084, #1877F2 파란
  원형 + 흰 'f' 마크) 마이그. `_renderFacebookButton` 함수가 Apple
  `SignInWithAppleButton` 패턴 mirror 로 wide button 외관 layer (white bg +
  black text + 1dp grey outline, dark = dark bg + white text + 1dp lighter
  outline) 형성. 자상 변형 금지 (`DON'T modify the 'f' logo in any way` —
  `developers.facebook.com/docs/facebook-login/userexperience/` verbatim).
- **사용자 책임:** Naver / LINE 은 일부 사용 시 사전 검수 신청 별도
  의무 가능 (정확한 절차는 공식 BI 페이지 — starter-kit 은 검수 자동화
  미제공).
- **자상 layout 패턴 (Phase 13.1 Gap-1 X2):** Wide 자상 통째 buttons 패턴
  의무 — `Image.asset(fit: BoxFit.contain, width: double.infinity, height:
  spec.height)` 또는 `SvgPicture.asset(fit: BoxFit.contain, width:
  double.infinity, height: spec.height)`. 자상이 18dp icon 슬롯에 squash
  되지 않도록 full-width sizing 강제 + 자상 자연 종횡비 보존 (`BoxFit.contain`
  강제). ClipRRect wrapper 폐기 + Material `clipBehavior: Clip.none` —
  자상 baked-in 모서리 (Naver 사각 / Kakao 7.2px scaled / Google rx=19.5
  pill) 가 시각 단독 권위. InkWell `borderRadius: 12dp` 는 ripple 영역만
  제어 (시각 변경 0). letterbox 영역 (Kakao 좌우 ~20dp / Google 좌우
  ~67dp / Naver 1dp 미세) Scaffold 배경 자연 채움. ARB 라벨 시각 layer
  추가 금지 (자상 baked-in). en fallback 정책: ko 외 모든 locale 은 en
  자상 path 로딩 (`_iconAssetFor` 의 `languageCode == 'ko' ? 'ko' : 'en'`
  분기). 자세한 production widget tree 는 `lib/features/auth/
  presentation/_widgets/branded_social_button.dart` 의 `_renderActiveButton`
  함수 참조.

### 회귀 가드 (3-layer)

Phase 13.1 의 회귀 가드 3종이 starter-kit 에 포함:

1. `test/features/auth/presentation/_widgets/brand_assets_lint_test.dart`
   — `.placeholder` sentinel + README 7필드 schema 검증 (3 group 3 PASS).
2. `test/features/auth/presentation/_widgets/brand_label_whitelist_test.dart`
   — ARB↔HIG/BI verbatim 매칭 (Apple ko/en/ja + Naver/Kakao ja 영문 fallback).
3. `test/features/auth/presentation/_widgets/branded_social_button_golden_test.dart`
   — Naver/Kakao/Google 6 fixture brand drift detection (zero pixel
   tolerance).

자상 / 라벨 / 시각 사양 변경 시 위 3 test 중 ≥ 1 RED — 회귀 차단.

> **갱신 의무:** 자상 변경 후 `fvm flutter test test/features/auth/presentation/_widgets/`
> 실행 의무. 3 test 모두 GREEN 일 때만 commit. golden test RED 는
> `--update-goldens` 후 PNG diff review 의무.

---

## Multi-Provider Account Linking (Phase 9.2)

본 단락은 5 social provider (Apple / Google / Facebook / Naver / Kakao) 사용 시
`account-exists-with-different-credential` (FirebaseAuth) /
`'already-exists'` (Cloud Function — Phase 12.1 R3) 충돌 시점의 기본 동작 +
자동 `sendEmailVerification` (이메일 인증, Email Verification) +
Facebook `photoURL` Graph API 보완 + 5 provider `signOut` (로그아웃)
일관성 을 설명한다.

> **🔴 Path A-narrow 채택 (2026-05-10):** RESEARCH §2.1 의 critical 결함
> (firebase_auth 6.0.0 의 `FirebaseAuth.fetchSignInMethodsForEmail()`
> client-side API 제거) 으로 SPEC R1 (provider-aware 정확 라벨 메시지) 은
> **Phase 17 (Account Linking) — see ROADMAP.md** 로 이월. Phase 9.2 는
> unknown fallback 메시지 (provider-미상 명시) 를 default path 로 채택한다.
> R1 부활 절차는 본 단락 §2 (AccountProvider enum 확장 절차) 참조.

### 1. account-exists 메시지 동작 (Phase 9.2 R2 — Path A-narrow)

5 social provider 의 충돌 시 신규 ARB (Application Resource Bundle) 키
`errorAccountExistsWithUnknownProvider` 가 default 메시지 — 3 locale 별
다음 텍스트 (verbatim):

| Locale | 메시지 |
|--------|--------|
| ko | 이 이메일은 다른 방식으로 가입되어 있습니다. 처음 가입한 방식으로 다시 로그인해 주세요 |
| en | This email is already registered with another sign-in method. Please sign in with the method you originally used. |
| ja | このメールアドレスは別の方法で登録されています。最初に登録した方法でログインしてください。 |

매핑 경로 (`lib/core/l10n/exception_l10n.dart` 의 `resolveExceptionMessage`):

1. `_mapAuthException` (`lib/features/auth/data/auth_repository.dart` —
   `_mapAuthException` 본체 안 `'account-exists-with-different-credential'`
   분기) → `AccountExistsWithDifferentCredential(email: e.email)` 매핑.
2. `_mapFunctionsException` (동일 파일의 `_mapFunctionsException` 본체 안
   `'already-exists'` 분기 — Phase 12.1 R3 / D-34 계승) →
   `AccountExistsWithDifferentCredential()` (email null) 매핑.
3. `resolveExceptionMessage` 의 D-13 조기 return (early return) —
   `AccountExistsWithDifferentCredential` 인스턴스 →
   `errorAccountExistsWithUnknownProvider` 단일 경로.

EEP (Email Enumeration Protection, 이메일 열거 방지) 활성 환경 / Custom Token
(Kakao / Naver — Phase 12·13 D-09) / `FirebaseAuthException.email == null`
모두 동일 default path. 사용자에게 노출되는 정보는 "이메일이 다른 방식으로
가입되어 있다" 단일 사실 만 — specific provider 미식별 (Path A-narrow 의
의도된 fallback). PII (Personally Identifiable Information, 개인 식별 정보)
노출 vector 회피.

LoginScreen 의 자동 채움 (auto-fill) + focus 호출 (R3 / D-31) 도 제거 —
충돌 시 사용자에게 잘못된 비밀번호 입력 cognitive trigger 가 작동하지 않는다.
구체 코드 위치: `lib/features/auth/presentation/login_screen.dart` 의
`ref.listen` listener body — D-10 자동 채움 + focus 호출 4줄을 정확히 삭제하고
소셜 실패만 배너 state 에 담는 `setState` 블록만 보존
(P3 / 09.2-03-PLAN.md commit 616603c).
**Phase 16.1 정정:** 위 화면은 chooser 가 되어 이메일 입력 필드가 없다 —
`login_screen.dart` 에는 소셜 실패용 state 하나만 남아 있고, 이메일 제출 실패
배너는 `lib/features/auth/presentation/email_login_screen.dart` 로 이관됐다.
따라서 자동 채움·focus 호출을 되살릴 수 있는 위젯 자체가 A 에 존재하지 않으며,
R1 부활 시 검토 대상 코드 anchor 는 두 파일로 나뉜다. `AccountExistsWithDifferentCredential.email`
필드 자체는 보존 — Phase 17 (Account Linking) — see ROADMAP.md 부활 시
server-side provider 매핑 input 으로 활용.

### 2. AccountProvider enum 확장 절차 (Phase 17 add-only 가이드)

**Phase 17 (Account Linking) — see ROADMAP.md** 진입 시점에 server-side
provider 매핑 인프라 (Cloud Function `lookupSignInMethods` with App Check +
rate limit + enumeration log alarm, 또는 Custom Token claim 기반 매핑) 위에서
R1 (provider-aware 라벨 메시지) 부활 절차:

1. **AccountProvider enum 신설** (`lib/core/auth/provider_id.dart`):

   ```dart
   enum AccountProvider {
     google, apple, facebook, email,
     // Phase 16 부활 시 add-only — kakao, naver, line, yahooJp 도
     // 마지막 unknown 직전에 add-only 위치.
     unknown,
   }
   ```

2. **`_mapAccountExistsException` async helper 신설**
   (`lib/features/auth/data/auth_repository.dart`): server-side
   `lookupSignInMethods` 호출 + provider 라벨 매핑.

3. **ARB `{provider}` placeholder 활용** — 기존
   `errorAccountExistsWithDifferentCredential` 키 (3 locale, Phase 9.2 에서
   unchanged 보존) 를 `{provider}` placeholder 메시지로 갱신. en metadata
   description 의 placeholder spec 추가 (Phase 13.1 D-84 패턴 정합).

4. **`exception_l10n.resolveExceptionMessage` 의 D-13 분기 보강** —
   `if (exception.provider == null || arbKey == null)` → unknown fallback
   (Phase 9.2 의 default), else → provider-aware 메시지.

5. **5 case parameterized test** + 추가 UAT (User Acceptance Test, 사용자
   인수 시험) — Apple → Facebook / Kakao → Google / password → Google /
   EEP 활성 mock.

09.2-CONTEXT.md 의 D-05 ~ D-12 / D-15 / D-29 결정 (deferred) 이 Phase 17
SPEC 의 starting point 로 재활용 가능 — 단 server-side 인프라 디자인 추가
의무 (PII 노출 vector 분석 + rate limit + enumeration log alarm 설계).

### 3. Facebook 자동 sendEmailVerification + photoURL Graph API (R4 + R5)

5 social sign-in 메서드 모두 success path 에서 `_autoSendEmailVerification`
helper 호출 — `lib/features/auth/data/auth_repository.dart` 안 private async
helper. callsite 는 `signInWithGoogle` / `signInWithApple` /
`signInWithFacebook` / `signInWithKakao` / `signInWithNaver` 5 메서드 각
success path 의 마지막 `await _autoSendEmailVerification(userCredential);`
한 줄 (정의는 `_autoSendEmailVerification` 본체). 5 가드 (D-19 + D-20):

- `user == null` / `user.isAnonymous` / `(user.email ?? '').isEmpty` /
  `user.emailVerified == true` / `isNewUser == false` 중 하나라도 true →
  no-op (조기 return).

이로 인해 Apple / Google (idToken `email_verified=true` claim) + Kakao /
Naver (Cloud Function `functions/src/auth/identity_index.ts` 의
`emailVerified: true` 자동 set) 4 provider 는 자연 no-op. **Facebook 만
실효적 호출** — Facebook OAuth 가 verification claim 미전달 →
`emailVerified=false` 기본.

isNewUser 가드 (`UserCredential.additionalUserInfo?.isNewUser ?? false`) 가
재로그인 spam 방지 (D-20). 검증 안 한 기존 Facebook 사용자가 매 로그인마다
verification 메일 받는 spam 차단. 사용자가 의도적으로 검증을 재요청할 때는
verifyEmailScreen 의 "재전송" (Resend) 버튼이 manual-resend 경로.

`signInWithFacebook` 만 추가로 `_setFacebookPhotoUrl` 호출 (정의는
`_setFacebookPhotoUrl` 본체, callsite 는 `signInWithFacebook` success path
의 `_autoSendEmailVerification` 호출 직후) — Graph API
`picture.type(large)` 응답의 `picture.data.url`
path 추출 후 `user.updatePhotoURL(url)` 갱신. Apple / Google 의 idToken
picture claim 자동 채움 차이 보완. D-25 — `_autoSendEmailVerification` →
`_setFacebookPhotoUrl` 순차 호출 (verify 먼저, photoURL 후순).

**race-fix invariant 의무** (Phase 9.1 D-03 직접 계승): 두 helper 호출 모두
`try { _socialLinkInProgress.begin(); ... } finally { _socialLinkInProgress.end(); }`
블록 **안** 위치. 호출이 finally 밖 또는 begin 이전 위치 = race regression
vector — splash 자동 익명 sign-in race 재발 (Phase 9 UAT.md Gap test 6 의
root cause). 09.2-04 Plan 의 `auth_repository_auto_verify_test.dart` 의
`verifyInOrder([begin, sendEmailVerification, end])` 가 회귀 가드.

**PII regression invariant** (D-27): `_setFacebookPhotoUrl` 의 광역 catch
블록의 `debugPrint` 는 **`e.runtimeType` 만** 출력 — `e.toString()` /
`result` Map / `url` 값 직접 출력 금지. Phase 12.1 D-40 catch-block sentinel
패턴 직접 계승. 09.2-04 Plan 의 `auth_repository_facebook_picture_test.dart`
가 sentinel facebook id + sentinel CDN URL + sentinel email 을 Exception
message 안에 verbatim 주입 후 `verifyNever(updatePhotoURL)` 로 graceful skip
보장.

silhouette (실루엣) 정책: 본 phase 는 **허용 default** —
`picture.data.is_silhouette == 1` 시에도 valid CDN (Content Delivery Network,
콘텐츠 전송망) URL 로 채택. Phase 17 / 18 의 truth-of-source (출처 진실원)
정책 결정 후 변경 가능 영역.

### 4. signOut 5 SDK 일괄 해제 (R6 — D-26)

`AuthRepository.signOut()` (`lib/features/auth/data/auth_repository.dart`
의 `signOut()` 본체) 가 Google → Facebook → Kakao → Naver → Firebase
Auth 순서로 5 SDK 순차 호출:

1. `_googleSignIn.signOut()` (Google)
2. `_facebookAuth.logOut()` (Facebook)
3. `_kakaoSdkClient.logout()` (Kakao — Phase 9.2 추가, Phase 12 D-57 정합)
4. `_naverSdkClient.logout()` (Naver — Phase 9.2 추가, Phase 13 D-57 정합)
5. `_auth.signOut()` (Firebase Auth — 마지막 호출 보장)

각 SDK logout 은 `try / on Object catch` 무시 패턴 — 한 SDK 실패가 후속
SDK + Firebase Auth signOut 호출을 차단하지 않는다. 본 invariant 가
09.2-04 Plan 의 `auth_repository_test.dart` signOut group 의 `verifyInOrder`
+ Kakao / Naver 실패 시뮬레이션 test (S2 / S3) 로 회귀 가드.

Phase 9.2 이전 결함: Kakao / Naver SDK logout 이 sign-in finally 에서만 호출
(1회성 토큰 정책 D-57) — `signOut()` 본체에서 누락 → 한 계정으로 로그아웃
후 native prompt 가 같은 계정 자동 진입하는 케이스가 5 provider 일관 결함.
Phase 9.2 의 add-only 패치가 5 SDK 세션 cache 일괄 해제 보장.

실 기기 검증 (Android dev flavor): Facebook 계정 A signOut → 계정 B 재로그인
시 native prompt 가 계정 B 선택지 표시 (계정 A cache 미잔존) —
09.2-VALIDATION.md 의 UAT (d) 시나리오.

### 커스터마이징 포인트 (사용자 관점)

starter-kit fork 사용자가 본 단락의 동작을 프로젝트 정책에 맞춰 조정할 때:

1. **자동 sendEmailVerification 비활성화**: `signInWithGoogle` /
   `signInWithApple` / `signInWithFacebook` / `signInWithKakao` /
   `signInWithNaver` 5 메서드 각 success path 의
   `await _autoSendEmailVerification(userCredential);` 호출 한 줄 (5
   callsite) 을 단순 제거. 또는 `_autoSendEmailVerification` 함수 본체
   첫 줄에 `return;` 추가하여 모든 path no-op 강제. (WR-01 iter1 fix 로
   시그니처가 `UserCredential` 단일 인자 채택 — `isNewUser` 추출은 helper
   내부 `userCredential.additionalUserInfo?.isNewUser ?? false` 로
   흡수됨.)
2. **Facebook photoURL 자동 갱신 비활성화**: `signInWithFacebook` 의
   `await _setFacebookPhotoUrl(fbUser);` 호출 한 줄만 제거 →
   `user.photoURL` 빈 값 유지. 같은 메서드의
   `_autoSendEmailVerification` 호출은 그대로.
3. **자동 채움 + focus 동작 복구 (D-31 inversion)**: `login_screen.dart` 의
   listener body 안 anchor 주석 영역에 자동 채움 4줄 재도입 — 단 cognitive
   hijack vector 재도입 위험 인지. Phase 17 (Account Linking) 부활 시
   server-side provider 매핑 input path 와 충돌 가능성.
4. **5 SDK signOut 순서 커스터마이즈**: `signOut()` 본체의 try/catch 블록
   순서 재배치 가능. 단 `_auth.signOut()` 가 마지막 호출 invariant 만 보존
   의무 — Firebase Auth 세션 해제 보장.
5. **silhouette URL 정책 변경**: `_setFacebookPhotoUrl` 의 type guard 단계에
   `data['is_silhouette'] != 1` 조건 추가 → silhouette URL skip. Phase 9.2
   는 허용 default 채택 (placeholder URL 역할 가능).

### 회귀 가드 매트릭스

09.2-04 Plan 이 도입한 4 신규 + 2 add-only test 가 5 invariant 회귀 가드:

| Invariant | 회귀 시 RED test | 책임 |
|-----------|------------------|------|
| R2 unknown fallback 단일 경로 | `auth_repository_unknown_fallback_test.dart` (U1+U2) + `exception_l10n_test.dart` add-only group (EL1+EL2) | `_mapAuthException` / `_mapFunctionsException` / `resolveExceptionMessage` D-13 분기 |
| R4 5 provider no-op + isNewUser + graceful + race-fix | `auth_repository_auto_verify_test.dart` (V1~V8) | `_autoSendEmailVerification` 5 가드 + `verifyInOrder` race-fix |
| R5 + D-27 PII | `auth_repository_facebook_picture_test.dart` (F1~F8) | `_setFacebookPhotoUrl` safe nav + sentinel 매트릭스 (facebook id / CDN URL / email — verbatim 값은 test 파일 내부에 격리) verifyNever |
| R6 5 SDK signOut 순차 | `auth_repository_test.dart` signOut group add-only (S1~S3) | `verifyInOrder([Google, Facebook, Kakao, Naver, Auth])` + 실패 시뮬레이션 |
| R3 widget — 자동 채움 0 + focus 0 | `login_screen_account_exists_test.dart` (W1) + `login_screen_test.dart` AUTH-03-17 inversion | EmailField focusNode `hasFocus=false` + unknown 메시지 banner verbatim |

회귀 가드 실행:
`fvm flutter test test/features/auth/`. 회귀 시 ≥ 1 RED 즉시 발생.

---

## App Entry State Machine (Phase 10.2)

> Phase 10.2 도입 (2026-05-12). authRedirect 분기 정합 + logout invariant
> 단일 진리원. Phase 10 D-20 (`signOutAndContinueAsGuest` 자동 익명 재진입)
> 폐기 history — `signOutAndResetOnboarding` + 4 invariants (I1~I4) 로 교체.
> 9.2 HUMAN-UAT cycle 1+2 OOS-01 closure.

### Invariants 표

| ID | Invariant | 진리원 (코드 anchor) |
|----|-----------|---------------------|
| I1 | 익명 user `/home` 도달 == `onboardingSeen=true AND termsAccepted=true` | `lib/core/router/auth_guard.dart` 분기 (3) — `(!onboardingSeen \|\| !termsAccepted) → /onboarding` (Phase 10.2 D-C1) + `lastReloadedUid` stale guard (D-C2) |
| I2 | 로그아웃 → `onboardingSeen=false` reset + signOut → /onboarding 자연 redirect | `lib/features/auth/data/auth_repository.dart` `signOutAndResetOnboarding()` (Phase 10.2 D-A1/A3) — reset 먼저 → signOut |
| I3 | OAuth 정식 user 발급 → 바로 /home (emailVerified=false 만 /verify-email gate) | `lib/core/router/auth_guard.dart` authUserObserver BLOCKER #4 mirror + 분기 (5) Plan 10-11 stale guard 신뢰 (Phase 10.2 D-D1 — 추가 코드 0건) |
| I4 | 새 device / `onboardingSeen=false` → 무조건 /onboarding (AsyncLoading 동안 라우팅 보류) | `lib/core/router/auth_guard.dart` `onboardingAsync.isLoading → null` 가드 + D-C1/C2 자연 결합 (Phase 10.2 D-C4 — 추가 코드 0건) |

### `signOutAndResetOnboarding` API

`AuthRepository.signOutAndResetOnboarding()` 는 I2 invariant 의 단일 진리원이다.

- **호출자 (3곳):**
  - `lib/features/home/presentation/environment_info_screen.dart` `_confirmSignOut` (production 로그아웃 다이얼로그 confirm path)
  - `lib/features/home/presentation/environment_info_screen.dart` `_handleForceSignOut` (Dev Tools 강제 로그아웃 — Phase 10.2 D-A4 production 와 완전 동일 동작 강제)
  - `lib/features/auth/presentation/verify_email_notifier.dart` `logout()` ("다른 계정으로 로그인" verify-email 화면 TextButton — Phase 10.2 review iter3 CR-01 정정. iter3 이전에는 `signOut()` 단독 호출로 D-A7 호출자 책임 invariant 위배 — D-20 cycle 회귀 vector 였음)
- **본체 (Phase 10.2 D-A3 순서):**
  1. `await _onResetOnboarding();` — `OnboardingNotifier.reset()` 콜백 호출. state `AsyncData<bool>(false)` 동기 set + SharedPreferences `prefs.remove(_key)` lossy 정책 (실패 graceful).
  2. `await signOut();` — Firebase Auth signOut + Google / Facebook / Kakao / Naver SDK 5개 순차 logout (Phase 9.2 R6 invariant 보존).
- **navigation 명시 호출 0건 (Phase 10.2 D-B1):** `authStateChanges → AuthChangeNotifier → authRedirect 분기 (2)` 가 `/onboarding` 으로 자연 redirect. `context.go(AppRoutes.onboarding)` 등 explicit navigation **금지** — race condition (호출 직후 vs userChanges emit 직후) 차단.
- **Crashlytics signal / SnackBar / Loading indicator 추가 안 함 (Phase 10.2 D-A6/B2/B4):** logout 은 정상 흐름 — over-instrumentation 회피.

### D-20 폐기 history (Phase 10 → Phase 10.2)

**Phase 10 D-20 (2026-04-24, `auth_repository.dart:701-715` 원본):** `signOutAndContinueAsGuest()` — 로그아웃 직후 `signInAnonymously()` 자동 cascading 으로 게스트 사용성 보존. 의도는 "Home 에서 Login 으로 튕기는 UX 단절 방지" 였다.

**Defect:** `termsAccepted` 는 user-bound (Firestore `users/{uid}/termsAccepted` mirror) 이므로 새 익명 user 마다 false 로 reset. 결과적으로 "익명홈 = onboarding+termsAccepted 모두 완료" mental model 위배.

**9.2 HUMAN-UAT cycle 1+2 OOS-01 driver log 인용 (2026-05-11):**

```
authRedirect: matchedLocation=/, isAuthenticated=true, emailVerified=true,
onboardingSeen=true, termsAccepted=false — 라우터 평가는 home 인데 UI 는
onboarding 첫 페이지 표시 (Facebook 이메일 인증 후 / Kakao 신규 가입 후 /
Naver 신규 가입 후 3건 모두 동일)
```

Source: `.planning/phases/09.2-multi-provider-account-linking-enhancement/09.2-HUMAN-UAT-v2.md` OOS-01 (Phase 10 carry-forward, severity major).

**Phase 10.2 결정 (2026-05-12):**

- D-A5: 원본 `signOutAndContinueAsGuest` 완전 삭제 (소프트 transition 없음).
- D-A1/A3: `signOutAndResetOnboarding()` 도입 — reset → signOut 순서 강제.
- D-B1: 자연 redirect 채택 — `/onboarding` 자동 진입 (UX 단절 trade-off 수용, multi-user device 안전 우선).
- D-C1/C2: `auth_guard.dart` 분기 (3) 단일 gate 정정 + stale guard 익명 확장 (Plan 10-11 분기 (5) 패턴 mirror).

### Phase 17 (Account Linking & Withdrawal) note

회원탈퇴 reauthentication + `deleteUser` 경로의 onboardingSeen reset 정책은 본 단락 scope 외 — Phase 17 논의에서 결정. `AuthRepository.signOut()` 단독 호출은 `_safeDelete` fallback 등 내부 경로 전용 (Phase 10.2 D-A7 호출자 책임).

### Pitfall

- **다이어그램 도구 미도입 (Phase 10.2 D-D4):** 코드 ↔ 다이어그램 동기 유지 부담 vs 시각적 가치 — 향후 manual.md 종합 개편 시 재검토. 본 단락은 markdown table + prose 만으로 명문화.
- **별도 `docs/auth-state-machine.md` 분리 안 함 (Phase 10.2 D-D4):** Starter Kit docs 내포 원칙 — manual.md 단일 진리원 정책.
- **invariant 표 drift 위험:** 미래 phase review 시 본 단락의 4 invariants 가 코드와 drift 가능. Phase 17 / Phase 10.3 등 신규 phase 에서 auth 영역 변경 시 본 단락 확인 의무 (LEARNINGS.md 기록 anchor — feedback_review_recurring_issues memory).
- **Dev Tools "Reset Onboarding" full vs anonymous user 동작 비대칭 (Phase 10.2 review iter3 WR-02):** `_DevToolsSection._handleResetOnboarding` 는 `OnboardingNotifier.reset()` 만 호출하고 `signOut()` 은 호출하지 **않는다**. 정식 user (`isAuthenticated && !isAnonymous && termsAccepted=true`) 가 `/home` 에서 본 버튼을 tap 하면 즉시 상태가 `(authenticated && !anonymous && termsAccepted=true && onboardingSeen=false)` 로 전환되나 authRedirect 분기 (1)~(7) 어디에도 매치되지 않아 `/home` 에 그대로 잔류한다 (cold restart 후에도 동일 — disk `seen_version` 가 reset 되었으므로 `onboardingSeen=false` 유지 + 정식 user → 분기 (3) 익명 가드 미진입). 기능적으로 invariant 위배는 아니나 4개 invariant (I1~I4) 표가 명시적으로 다루지 않는 state 조합이다. **익명 user** 가 동일 tap 시에는 분기 (3) D-C1 stale guard 가 즉시 trip 하여 `/onboarding` 으로 redirect — 동일 버튼이 user 종류에 따라 비대칭 UX 를 produce. Dev Tools 의 의도 — "로그인 상태는 유지하면서 onboarding 만 리셋하여 onboarding flow 를 재검토" — 와 정합하므로 본 비대칭은 의도된 design 이며, 정식 user 로 onboarding 재진입을 원하면 별도의 "로그아웃" Dev Tools 액션 (D-A4 `_handleForceSignOut`) 사용을 권장. 통일된 동작이 필요해지면 `_handleResetOnboarding` 을 `signOutAndResetOnboarding()` 호출로 교체하는 옵션을 후속 phase 에서 재검토 (단, Dev Tools 버튼 라벨/시그니처 의미가 바뀌므로 별도 결정 필요).
- **Lossy persistence drift — `OnboardingNotifier.reset()` cold restart 회복 (Phase 10.2 review WR-02):** `signOutAndResetOnboarding` 의 1단계 `_onResetOnboarding()` 은 `OnboardingNotifier.reset()` 콜백을 호출한다. `reset()` 은 in-memory state 를 즉시 `AsyncData<bool>(false)` 로 set 하고 `prefs.remove(_key)` 를 시도하나, IO 예외 (disk full / permission) 발생 시 Crashlytics `onboarding_reset` reason 으로 기록 후 silent 흡수한다 (lossy 정책 — Starter Kit D-13 철학 승계). 따라서 disk 상의 `seen_version=1` 은 잔존 가능. 이때 동작:
  1. 직후 라우터 평가 — in-memory 기준 `onboardingSeen=false` → 분기 (2) 가 `/onboarding` 으로 redirect (정상).
  2. **앱 cold restart** — disk 의 `seen_version=1` 로드 → `onboardingSeen=true` 로 부활.
  3. splash initializer 가 익명 sign-in 후 `/home` 진입 시도.
  4. 새 익명 user 의 `termsAccepted=null` 이므로 분기 (3) D-C1 stale guard (I1 invariant) 가 `/onboarding` 으로 다시 보냄 → **self-correcting**.
  최종 invariant 는 충족하나 cold restart 까지의 시점 동작은 disk-vs-memory drift 가 존재한다. Crashlytics `onboarding_reset` reason 으로 추적 가능. `signOutAndResetOnboarding` 자체 시그니처를 Result 로 변경하여 호출자에게 disk 실패 신호를 surface 하는 강한 변경은 Starter Kit 수준에서 over-engineering 으로 미채택 (D-A6 over-instrumentation 회피 정책 일관).

---

## 로그인 화면 구조 — 이메일 격하 (Phase 16.1)

> Phase 16.1 도입 (2026-09-10). 소셜 provider 7개가 모두 통합된 뒤 이메일/
> 비밀번호 UI 를 **격하(relegation)** 한 결과의 화면 구조 단일 진리원.
> 이메일 로그인·가입 **기능은 하나도 제거되지 않았고** 진입 위치만 바뀌었다.
> 진실원: `.planning/todos/completed/2026-05-18-email-password-ui-relegation.md`
> 「재토론 결과」 + `.planning/sketches/MANIFEST.md` Sketch 003/004 sign-off.

### 3화면 + 1시트 구조

| 경로 / 표면 | 화면 클래스 | 담는 것 |
|---|---|---|
| `/login` | `LoginScreen` (Surface A) | 7 social provider chooser + `OrDivider` + "이메일로 계속" CTA + 하단 가입 링크. **이메일 입력 필드 0** |
| `/login/email` | `EmailLoginScreen` (Surface B) | Phase 6/6.1 이메일 로그인 form 전용. `/login` 의 sub-route 가 아닌 **최상위 형제 route** 이므로 진입은 항상 chooser 위 `push` 여야 한다 — CTA 2곳은 `push` 직접 호출, `AccountLinkingSheet` 경로 C 와 `ForgotPasswordScreen` 딥링크 fallback 은 `go('/login')` + `push('/login/email')` 2단. 그 결과 AppBar back 버튼으로 chooser 복귀 가능. 비밀번호 찾기 링크 · 하단 가입 링크 보유 |
| `/signup` | `EmailSignupScreen` (Surface C) | 이메일 가입 form 만. 경로·route name 은 종전 그대로이며 **소셜 섹션이 없다** |
| `LoginPromptSheet` (Surface D) | `_widgets/login_prompt_sheet.dart` | 익명 사용자가 보호된 동작을 탭했을 때 뜨는 시트. A 와 **동일한 `EmailAuthCta` 위젯**을 공유하고 본문 전체가 스크롤된다 |

`EmailAuthCta` (`_widgets/email_auth_cta.dart`) 는 A 와 D 가 공유하는 얇은
`TextButton` wrapper 다. 라벨(`authContinueWithEmail`)을 위젯 내부에 고정해
두 화면의 문구·외관 drift 를 구조적으로 차단한다.

### Option C 의 의미 — 코드는 전부 보존된다

- Phase 6/6.1 의 이메일 form · validator · 비밀번호 찾기 · 이메일 인증 화면,
  Phase 9.2 의 이메일 계정 linking 은 **변경 0** 이다.
- 바뀐 것은 **UI 노출 위계**뿐이다 — 이메일이 첫 화면의 form 에서 CTA 뒤
  한 단계로 내려갔다.
- 삭제된 것은 소셜 버튼까지 함께 담던 구 `SignupScreen` 1개이며, 그 자리는
  form 전용 `EmailSignupScreen` 이 이어받았다. 소셜 진입점이 3곳 → 2곳(A·D)
  으로 줄어 도달 불가능한 인증 wiring 이 사라졌다.
- `?focus=email` 쿼리 파라미터로 화면 안 이메일 섹션에 포커스를 주던 Phase 10
  의 진입 계약은 **폐기**됐다. 대신 전용 경로 `/login/email` 로 이동한다.

### 커스터마이징 포인트

1. **이메일 경로를 완전히 숨기려면** — `EmailAuthCta` 호출 2곳
   (`login_screen.dart` · `_widgets/login_prompt_sheet.dart`) + A 하단 가입
   링크(`TextButton(l10n.authLoginNoAccount)`) + `app_router.dart` 의
   `/login/email` `GoRoute` + `auth_guard.dart` `_unauthRoutes` 1줄을 함께
   지운다. **딥링크까지 막으려면 `/signup` `GoRoute` 와 그 화이트리스트
   항목도 제거**해야 한다 — 링크만 지우면 URL 직접 진입이 열려 있다.

   ⚠ **UI 진입점 외에 `AppRoutes.emailLogin` 을 참조하는 곳이 2군데 더
   있다** — `_widgets/account_linking_sheet.dart` 의 경로 C (동일 이메일
   충돌 시트) 와 `forgot_password_screen.dart` 의 딥링크 fallback 이다.
   둘 다 `go('/login')` + `push('/login/email')` 2단으로 이동하므로,
   `GoRoute` 만 지우면 이 두 경로가 `errorBuilder`
   (`buildNotFoundScreen`) 로 떨어진다. 두 지점의 도착지를 `/login` 단독
   이동으로 되돌린 뒤 route 를 제거할 것. 지우기 전 전수 확인:

   ```bash
   grep -rn "AppRoutes.emailLogin" lib   # UI 진입점 2 + go/push 2단 2
   ```
2. **CTA 라벨을 바꾸려면** — `EmailAuthCta` 는 label 파라미터를 노출하지
   않는다. `lib/l10n/app_{ko,en,ja}.arb` 의 `authContinueWithEmail` 값을
   **3 파일 모두** 고치고 `fvm flutter gen-l10n` 을 실행한다. 다른 ARB key 로
   교체하려면 `email_auth_cta.dart` 의 getter 참조 1줄만 바꾸면 A/D 양쪽에
   반영된다.
3. **CTA 를 divider 위로 올리거나 외관을 바꾸려면** —
   `_widgets/email_auth_cta.dart` **1 파일**이 외관의 진실원이다(A/D 공유).
   위치를 바꾸려면 각 화면 `build()` 의 `Column` children 순서를 조정한다.
   단 소셜보다 **위로** 올리면 격하 의도가 뒤집히고 A 의 좌표 비교 테스트
   2건이 RED 가 된다 — 의도적 변경이라면 그 단언도 함께 갱신할 것.
4. **provider 를 추가할 때 시트 높이** — `LoginPromptSheet` 는 3블록
   구조다(quick 260911-0t3): **고정 헤더** / `Flexible` + `SingleChildScrollView`
   안의 **provider 목록** / **고정 footer 의 "이메일로 계속" CTA**. provider 를
   몇 개 추가하든 (a) 늘어난 높이는 스크롤 영역이 흡수하므로 overflow 예외가
   나지 않고, (b) CTA 는 스크롤 영역 **밖**이라 폰 높이와 무관하게 항상 첫
   화면에 보인다. `maxHeight` 는 화면의 90% 로 cap 되어 있지만 이는 상한일
   뿐이며, 콘텐츠가 작으면 시트가 콘텐츠 높이로 줄어든다(800 dp 폰 · 7
   provider 실측 680 dp = 85%). 회귀 가드는
   `test/features/auth/widgets/login_prompt_sheet_overflow_test.dart` 의
   7/8 provider × 계약 2종(overflow 0 · CTA 첫 화면 노출)이다(default
   800×600 viewport 를 넓히지 말 것 — 좁음 자체가 회귀 조건이다).
5. **`/login/email` 경로 문자열을 바꾸려면** — `app_routes.dart` 의
   `AppRoutes.emailLogin` 상수 1곳만 고친다. `GoRoute` 와
   `_unauthRoutes` 가 모두 이 상수를 참조하므로 하드코딩 지점이 없다. 단
   `AppRoutes.emailLoginName` 은 GA4 screen name 으로 전송되므로 이름을
   바꾸면 대시보드 필터도 함께 갱신해야 한다.

### ⚠ adopter breaking 안내 — Analytics(GA4) screen name

`analytics.logScreenView` 로직은 변경 0 이지만 **관측 데이터의 의미가 바뀐다.**

1. `emailLogin` 이 **신규 screen name** 으로 등장한다. 이메일 로그인을 시도한
   사용자는 이제 `login` → `emailLogin` 두 개의 `screen_view` 를 발생시킨다.
2. 기존 `login` 의 의미가 "이메일 form 을 본 사용자" → "**chooser 를 본
   사용자**" 로 바뀐다.
3. `signup` 은 이름·경로 모두 그대로지만 화면에 소셜 버튼이 없으므로 그
   화면에서 발생하던 소셜 가입 이벤트는 0 이 된다.

**필요한 조치:** Firebase Console 등록 작업은 **불필요**하다. 다만 `login` 을
기준으로 funnel/대시보드를 만든 경우 (a) `emailLogin` 을 step 으로 추가하거나
(b) `login` 을 "인증 진입" 으로 재정의해야 한다. 배포 시점을 annotation 으로
남겨 before/after 를 구분할 것을 권장한다.

### 회귀 가드 위치

| 대상 | 테스트 파일 |
|---|---|
| A chooser 구성 · CTA push · 이메일 필드 부재 | `test/features/auth/presentation/login_screen_layout_test.dart` · `login_screen_test.dart` |
| B 이메일 로그인 form · 성공 navigation | `test/features/auth/presentation/email_login_screen_test.dart` · `email_login_screen_nav_test.dart` |
| C 가입 form · 소셜 섹션 부재 | `test/features/auth/presentation/email_signup_screen_test.dart` |
| S 공유 CTA (라벨 · 48 dp 탭 타겟) | `test/features/auth/presentation/_widgets/email_auth_cta_test.dart` |
| D 시트 스크롤 · 7/8 provider overflow 0 · CTA 첫 화면 노출 · 소셜 실패 피드백 | `test/features/auth/widgets/login_prompt_sheet_overflow_test.dart` · `login_prompt_sheet_test.dart` · `login_prompt_sheet_error_test.dart` |
| route 등록 · 미인증 접근 화이트리스트 | `test/core/router/app_router_observers_test.dart` · `app_routes_test.dart` · `auth_guard_test.dart` |
| 화면 문자열 3 locale verbatim | `test/l10n/email_relegation_arb_verbatim_test.dart` |
| B 진입 시 back 스택 확보 (chooser 복귀 가능) | `test/features/auth/presentation/account_linking_sheet_two_step_test.dart` TS7 · `forgot_password_screen_test.dart` |
| C 하단 "로그인" 링크의 진입 경로별 착지 | `test/features/auth/presentation/email_signup_screen_test.dart` |
| 이메일 제출 ↔ 소셜 교차 잠금 | `test/features/auth/presentation/login_screen_test.dart` |

### Pitfall

- **긴 라벨의 2줄 wrap 은 버그가 아니다** — `authLoginNoAccount` /
  `authSignupHasAccount` 의 ja 값은 280 dp 폭에서 2줄로 감싼다. `TextButton`
  의 softWrap 동작이며 `maxLines` 나 ellipsis 를 넣으면 3 locale sign-off 를
  깬다.
- **비밀번호 재설정 진입이 한 단계 깊어졌다** — chooser 에는 비밀번호 찾기
  링크가 없다. `/login/email` 을 거쳐야 하며, 이는 격하 결정의 의도된 귀결이다.
- **시트 안 소셜 로그인 실패도 chooser 와 똑같이 안내된다** — 실패하면 시트가
  닫히지 않고 소셜 버튼 바로 아래에 에러 배너가 뜬다. 같은 이메일이 다른
  방식으로 이미 가입돼 있으면 계정 연결 시트가 그 **위에** 뜨고, 취소하면
  원래 시트로 되돌아온다 (연결에 성공하면 두 시트 모두 닫히고 홈으로
  이동한다). 배너 문구는 ARB + `resolveExceptionMessage` 가 소유하므로
  provider 를 추가해도 별도 배선 없이 자동 반영된다.

---

## 변경 이력

| 일자 | Phase | 변경 |
|------|-------|------|
| 2026-05-03 | 12-07 | 신규 작성 — Kakao Login + Phase 13~16 stub + RC kill switch 통합 + Brand Asset 라이센스 + 회원탈퇴 TODO |
| 2026-05-04 | 12.1 | Initial Setup 단락 신규 추가 — config 시크릿 분리 (BL-01 hotfix). config/{flavor}.json 을 .gitignore 처리하고 *.example.json placeholder 만 tracked. |
| 2026-05-05 | 12.1-03 | Git Hooks 활성화 (선택) 단락 신규 추가 — `scripts/check_phase_refs.sh` 양방향 lint + git pre-commit hook (R8.2 / WR-08). |
| 2026-05-05 | 13-07 | Naver Login 단락 (10 단계) + Brand Asset 단락 (Kakao + Naver 통합, D-52) + Kakao 동의 항목 갱신 (D-56 retroactive) + Initial Setup 표에 naver 3 키 + iOS xcconfig 의 NAVER_URL_SCHEME + Firebase Secret Manager `NAVER_CLIENT_SECRET` 등록 (D-60). 목차 8 항목으로 확장. |
| 2026-05-08 | 13.1-13 | `## Brand Asset Management (Phase 13.1)` 단락 신규 — 7 provider 매트릭스 (출처 + 라이선스 + 채택 차원) + 3단계 절차 (다운/Phase 14·16 sentinel 해제/freshness 1년) + 자산 변형 정책 + Plan 13.1-07 retro 경고 (1x/2x/3x density 가정 vs 실제 형식) + 3-layer 회귀 가드. R15 acceptance. 목차 9 항목으로 확장. |
| 2026-05-09 | 13.1-16 | Brand Asset Management 단락 보강 — Phase 13.1 Gap-1 X2 (wide 자상 통째 buttons 패턴) 함정 경고 박스 #2 신규 + 자산 변형 정책 단락에 layout 패턴 bullet 추가 (`Image.asset(fit: BoxFit.contain)` / `SvgPicture.asset(fit: BoxFit.contain)` + ClipRRect 폐기 + Material `clipBehavior: Clip.none` + InkWell `borderRadius: 12dp` ripple 제어 + letterbox 영역). en fallback 정책 (ko 외 모든 locale 은 en 자상 path 로딩) 명시. Plan 13.1-14 production code + Plan 13.1-15 4-round 시각 검증 deviation 1+2 인용. |
| 2026-05-10 | 13.1-REVIEW | iter1 code review CR-02 정정 — `## Brand Asset (Phase 13 D-52)` + `## Kakao Brand Asset 라이센스 (Phase 12-07)` 두 단락 DEPRECATED 표시 + Phase 13.1 신규 단락 (`## Brand Asset Management (Phase 13.1)`) 으로 사용자 redirect. Phase 13.1 R1 정정 (#03A94D) + ColorFilter 절대 금지 + `assets/brand/{provider}/` 신규 디렉토리 구조 정합성 회복. |
| 2026-05-10 | 09.2-05 | `## Multi-Provider Account Linking (Phase 9.2)` 단락 신규 (D-32, 4 sub-section + 커스터마이징 포인트 + 회귀 가드 매트릭스) — Path A-narrow R2~R6 동작 (account-exists unknown fallback 메시지 ko/en/ja verbatim, AccountProvider enum 부활 절차 — Phase 17 (Account Linking) — see ROADMAP.md, Facebook 자동 sendEmailVerification + photoURL Graph API + race-fix invariant + D-27 PII regression sentinel 매트릭스, signOut 5 SDK 순차 — Google → Facebook → Kakao → Naver → FirebaseAuth). R1 deferred to Phase 17 명시 (D-33). 코드 anchor (auth_repository.dart line 230/340/441/442/525/612/728/778/829/837/845/853/859) + 회귀 test 파일 5종 인용 (Phase 13.1 D-84 패턴 정합). 목차 11 항목으로 확장. |
| 2026-05-20 | 14-07 | `## LINE Login (Phase 14)` 단락 신규 (D-LINE-22a, 8 단계 종합 절차 + Pitfall 7종) — Channel 생성 (Business ID 가입 + Provider + Login Channel + Region Japan + Mobile app 단독), iOS Bundle/Android Package/SHA-1 등록 (Universal Links OFF), UAT 권한 절차 (Tester role recommended / Channel publish 분기, Plan 14-05 UAT 학습 verbatim), OpenID Connect 활성화 (silent-failure 가장 흔한 trap), Firebase Secret Manager 등록 + Cloud Function deploy, platform manifest 검증 (CFBundleURLTypes line3rdp / LSApplicationQueriesSchemes lineauth2 단일 / `<queries>` jp.naver.line.android), config/dev.json 키 주입, dev flavor 검증 + UAT 보류 todo 2건 (ios/android). email permission 신청 절차 + 비즈니스 인증 (production) + 19 locale 확장 절차 (자상 변경 0 invariant) + Pitfall 7종 (idToken null / race-fix logout / nonce SHA256 / OIDC 누락 / queries 누락 / lineChannelId 미주입 / Android minSdk < 24). 목차 13 항목으로 확장. |
| 2026-05-20 | 14-07 | `## Kakao 검수 / 비즈앱 / 추가 수집 / stg-prod (Phase 14 D-LINE-22b retroactive)` 단락 신규 — Phase 12 Kakao Login 단계에서 dev 단독 검증만 다룬 매뉴얼에 production 출시 4 항목 retroactive 보강: (1) Kakao 검수 신청 절차 (DAU 100+ 의무 + 검수 form + 신규 동의 항목 재검수 회피) / (2) 비즈앱 인증 절차 (사업자 / 개인 인증 분기 + phone_number / CI / DI / 배송지 / 카톡 메시지 / 생일 / 성별 / 연령대 / 출생연도 트리거) / (3) 추가 수집 정보 카탈로그 (기본 3 + 비즈앱-only 8 + scope 매트릭스 + 채택 시 code 변경 point — kakao_sdk_client.dart serviceTerms / kakao_custom_token.ts zod / UserApi 호출 helper) / (4) stg / prod Console 등록 + 검수 (별도 앱 / 키 해시 release / Redirect URI prod / Secret Manager prod / OIDC 활성화 + 검수 분리 / App Check Debug Token 분리). 모든 verbatim claim 에 `[ASSUMED — Phase 14 단계 cross-verify 보류, 사용자 책임]` tag + 4 URL cross-verify 의무 명시. |
| 2026-05-20 | 14-07 | `## Naver 검수 / 추가 항목 / member detail / stg-prod (Phase 14 D-LINE-22c retroactive)` 단락 신규 — Phase 13 Naver Login 단계에서 dev 단독 검증만 다룬 매뉴얼에 production 출시 4 항목 retroactive 보강: (1) 네아로 검수 신청 절차 (외부 사용자 차단 회피 + 검수 form + 동의 항목 일괄 등록) / (2) 추가 항목 활성화 절차 (mobile / ci / birthday / gender / age / birthyear / name member detail info, 항목별 검수 의무) / (3) `/v1/nid/me` response 카탈로그 (기본 3 + 추가 7 + response field 매트릭스 + 채택 시 code 변경 point — naver_custom_token.ts mapNaverProfile / PII 정책 의무 / Firebase Auth customClaims 분리) / (4) stg / prod Console 등록 + 검수 (별도 Naver 앱 / iOS URL Scheme prod / Android Key Hash release / Bundle ID 분리 / Secret Manager prod / 네아로 검수 분리 / App Check Debug Token 분리). 모든 verbatim claim 에 `[ASSUMED — Phase 14 단계 cross-verify 보류, 사용자 책임]` tag + 4 URL cross-verify 의무 명시. |
| 2026-05-29 | 16-06 | `## Account Linking & Withdrawal` 단락 신규 (Phase 16 D-05~D-16 + R1 부활) — 5 sub-section: (1) 동일 이메일 Account Linking (D-01~D-04 흐름 + native↔native vs Custom Token 분기 + 사용자 cancel 시 state 손실 0 + PII invariant), (2) 회원탈퇴 Hard delete + GDPR right-to-be-forgotten (3-line 경고 verbatim + 진입 path /settings → Danger zone → confirmTextField verbatim → fresh ID Token + 5분 boundary → /onboarding 자동 reset + destructive UX 가드 5종), (3) Phase 17 deferred — Cloud Storage cascade (Firestore trigger vs Storage Security Rules + lifecycle), (4) App Check debug provider 등록 절차 (Firebase Console debug token 등록 4 단계 — Plan 16-06 reauth fail 분기와 동일 surface trial-and-error 회피), (5) 사용자 커스터마이징 포인트 5종 (ARB / AccountLinkingSheet n-provider / confirmTextField verbatim / deleteUserAccount cascade / 법무 자문 의무). |
| 2026-09-10 | 16.1-04 | `## 로그인 화면 구조 — 이메일 격하 (Phase 16.1)` 단락 신규 (D-11) — 3화면 + 1시트 구조표 (`/login` chooser · `/login/email` EmailLoginScreen · `/signup` EmailSignupScreen · LoginPromptSheet) + Option C 의미 (이메일 코드 보존, UI 노출만 격하) + 커스터마이징 포인트 5종 (경로 은닉 / CTA 라벨 ARB / EmailAuthCta 단일 외관 진실원 / 시트 provider 증가 안전성 / `/login/email` path 상수) + GA4 breaking 안내 (`emailLogin` 신규 screen name · `login` 의미 변화) + 회귀 가드 7행 매트릭스 + Pitfall 3종. 목차 15 항목으로 확장. stale 서술 2곳 정정 — Custom Token Provider 추가 가이드의 소셜 wiring 화면 수(3 → 2, SignupScreen 삭제 반영) + Multi-Provider Account Linking 절의 `login_screen.dart` 이메일 배너 코드 anchor (이메일 배너는 `email_login_screen.dart` 로 이관). |
| 2026-09-10 | 16.1-REVIEW | code review 정정 (CR-01 · WR-06) — 3화면 구조표의 `/login/email` 진입 방식 서술을 실제 위상 (최상위 형제 route · 항상 chooser 위 push) 에 맞춰 정정. 커스터마이징 포인트 1번에 `AppRoutes.emailLogin` 을 참조하는 비-UI 지점 2곳 (`account_linking_sheet.dart` 경로 C · `forgot_password_screen.dart` 딥링크 fallback) 경고 + `grep -rn "AppRoutes.emailLogin" lib` 자가 점검 명령 추가 — GoRoute 만 지우면 두 경로가 `buildNotFoundScreen` 으로 떨어진다. 회귀 가드 매트릭스 3행 추가 (back 스택 확보 / C 하단 링크 경로별 착지 / 이메일 제출 ↔ 소셜 교차 잠금). |
| 2026-09-10 | quick 260910-uff | Surface D Pitfall 정정 — 시트 안 소셜 실패가 이제 배너 + 계정 연결 시트로 안내된다는 현행 동작 서술로 교체 (사라진 pending todo 경로 제거) + 「회귀 가드 위치」 표 D 행에 실패 피드백 회귀 가드 테스트 1건 추가. 근거: AR-16.1-01 회수 (16.1-SECURITY.md Accepted Risks Log). |
| 2026-09-11 | quick 260911-0t3 | Surface D 구조를 A1 (고정 헤더 + provider 스크롤 + CTA footer 고정) 로 전환 + `maxHeight` cap 0.75 → 0.9 — 7 provider 에서 "이메일로 계속" CTA 가 모든 폰 높이에서 fold 아래이던 갭 해소 (800 dp 실측: 현행 B 는 CTA 하단이 fold 아래 64 dp). CTA 첫 화면 노출 회귀 가드 2건 add-only (7/8 provider · `getRect(cta).bottom <= 600` · `ensureVisible` 없는 tap → `/login/email` push, 기존 `ensureVisible` 4건은 방어 계층으로 유지) + Surface D golden 2장 재생성 (light 는 사용자 sign-off mockup 과 byte 동일) + 커스터마이징 항목 4 · 「회귀 가드 위치」 표 D 행 정정. 사용자 시각 sign-off 2026-09-11. |
| 2026-09-11 | quick 260911-spw | Initial Setup 「흔한 실수」 목록에 Android placeholder 항목 2건 add-only — (1) 실 키가 든 `google-services.json` 재생성본 강제 `git add` 금지 (pre-commit 가드 2 차단 + 해제 경로는 skip-worktree) (2) stg/prod 빌드 통과 ≠ Firebase 연결 (placeholder 는 빌드 게이트용, 런타임은 미초기화 모드). 근거: `android/app/src/{stg,prod}/google-services.json` placeholder 2종을 tracked 로 전환하고 `.gitignore` negation + 회귀 가드 test + skip-worktree 일반화 + pre-commit 값 가드 로 3중 방어. |

---

*Last updated: 2026-09-11 — quick 260911-spw Android stg/prod google-services placeholder tracked 화*
