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
3. [Brand Asset (Phase 13 D-52 — Kakao + Naver 통합)](#brand-asset-phase-13-d-52--kakao--naver-통합)
4. [Kakao 동의 항목 갱신 (Phase 13 D-56 retroactive)](#kakao-동의-항목-갱신-phase-13-d-56-retroactive)
5. [IdP 프로필 동기화 정책 (R10-FOLLOWUP)](#idp-프로필-동기화-정책-r10-followup)
6. [Phase 14~16 — Custom Token Provider 추가 가이드 (stub)](#phase-1416--custom-token-provider-추가-가이드-stub)
7. [Cloud Functions 배포 / Remote Config Kill Switch (Phase 11-04)](#cloud-functions-배포--remote-config-kill-switch-phase-11-04)
8. [Kakao Brand Asset 라이센스 / 출처 (Phase 12-07)](#kakao-brand-asset-라이센스--출처-phase-12-07)
9. [Brand Asset Management (Phase 13.1)](#brand-asset-management-phase-131)
10. [회원탈퇴 cleanup TODO (Phase 17)](#회원탈퇴-cleanup-todo-phase-17)
11. [Multi-Provider Account Linking (Phase 9.2)](#multi-provider-account-linking-phase-92)
12. [App Entry State Machine (Phase 10.2)](#app-entry-state-machine-phase-102)

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
> Phase 별 단락 (Phase 12 = Kakao, Phase 13 = Naver, 추후 Phase 14~16 = LINE /
> Yahoo!JP / WeChat) 을 참조.

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
>   `assets/brand/{line,wechat}/.placeholder` 빈 파일 (신, sentinel 단일 책임).
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

### Phase 14~16 진입 시 (DEPRECATED — Phase 13.1 단락 2단계 참조)

LINE / WeChat 진입 시 동일 패턴 — Phase 13.1 단락의 "2단계 — Phase 14/16
진입 시 LINE/WeChat 자상 commit" 절차 단독 권위.

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

---

## IdP 프로필 동기화 정책 (R10-FOLLOWUP)

OAuth Custom Token provider (Kakao + Naver + Phase 14~16 LINE/Yahoo!JP/WeChat)
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

   Phase 14~16 추가 시 해당 함수 (`lineCustomToken` 등) 도 동시 배포.

### 적용 범위 (D-08 — helper 1곳 fix → 모든 caller 자동 상속)

- Phase 12 — `kakaoCustomToken`
- Phase 13 — `naverCustomToken`
- Phase 14~16 — LINE / Yahoo!JP / WeChat (추가 시 동일 helper 재사용 → 자동 상속)

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
(Phase 14~16 LINE/Yahoo!JP/WeChat 자동 상속).

**후속 fix 추적:** `.planning/todos/completed/2026-05-08-r10-followup-permission-denied-race.md`
(pending → completed). spec: `docs/superpowers/specs/2026-05-08-r10-followup-2-design.md`.

---

## Phase 14~16 — Custom Token Provider 추가 가이드 (stub)

Phase 12 (Kakao OIDC) + Phase 13 (Naver REST) 의 통합 패턴을 그대로 미러링하여
LINE / Yahoo!JP / WeChat 등 새 Custom Token provider 를 추가할 수 있습니다.
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
   | 16 | WeChat | REST `/sns/userinfo` | WeChat OIDC 미지원 |

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
   switch 에 1줄 추가 (Pitfall 6 단일 진실원). 본 1줄로 LoginScreen /
   SignupScreen / LoginPromptSheet 3 화면의 ref.listen for-loop 자동 반영.

7. **ARB keys × 3 로케일** — `auth{Provider}SignIn` (소셜 버튼 라벨) +
   `authAccountProvider{Provider}` (Account 카드 라벨) × en/ko/ja 3 파일 +
   `flutter gen-l10n` 자동 호출.

8. **SocialButton 분기** —
   `lib/features/auth/presentation/_widgets/social_button.dart` 의 `build()`
   첫 줄 if 분기 + `_build{Provider}Button` 메서드 + 색 상수 (각 Brand
   Guideline). Kakao 가 sign_in_button 패키지 미지원 provider 의 표본 패턴
   (Material+InkWell+SVG 직접 그리기) — Naver / LINE / Yahoo!JP / WeChat
   모두 동일 패턴.

9. **Cloud Function** —
   `functions/src/auth/{provider}_custom_token.ts` 신규. Phase 12
   `kakao_custom_token.ts` 미러:
   - `setGlobalOptions` region 자동 상속 (asia-northeast3)
   - `enforceAppCheck: true` + `secrets: [PROVIDER_*_SECRET]`
   - `resolveIdentity(db, {provider, providerUserId, callerUid})` helper 재
     사용 (Phase 12 의 `functions/src/auth/identity_index.ts` 단일 진실원
     — Phase 13~17 모두 같은 helper 호출)
   - 검증 helper 는 OIDC verifier 가 Phase 14 LINE 진입 시 일반화 (D-08)

각 phase 마다 본 manual 의 Kakao 단락 + Phase 12 D-07 검증 매트릭스 + 실
provider 공식 문서 재확인 의무.

---

## Cloud Functions 배포 / Remote Config Kill Switch (Phase 11-04)

> 본 단락은 Phase 11-04 SUMMARY 의 사용자 매뉴얼 카드를 통합한 것입니다.
> Phase 12+ 의 신규 Cloud Function (Naver/LINE/Yahoo!JP/WeChat) 도 동일
> 패턴 적용.

### Functions 추가 절차 (Phase 12 ~ 16 의 ping 패턴 복제)

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

## 회원탈퇴 cleanup TODO (Phase 17)

현재 starter kit 의 회원탈퇴 흐름은 다음 cleanup 작업이 누락된 상태입니다
(Phase 17 의 Account Linking 일반화 단계에서 일괄 도입 예정):

- **`identity_index/{provider}:{providerUserId}` 문서 cleanup** — 회원탈퇴
  시 사용자가 등록한 Kakao / Naver / LINE / Yahoo!JP / WeChat 의 매핑
  문서가 잔존. 같은 외부 계정으로 재가입 시 first-write-wins 정책 (D-12)
  으로 기존 매핑이 우선되어 새 UID 가 아닌 기존 (탈퇴된) UID 로 매핑되는
  결함 가능성.
- **Native 4 provider (Email/Google/Apple/Facebook) 의 `linkedProviders`
  회고 등록** — Phase 12 의 Identity Index 컬렉션 등록은 Custom Token
  provider 만 자동. Native 4 provider 도 Phase 17 에서 회고 등록 후 통합
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

---

## Brand Asset Management (Phase 13.1)

본 단락은 starter-kit 의 social provider brand asset 출처·라이선스·다운로드·
freshness 갱신 정책을 정리한다. 7 provider (Kakao / Naver / Google / Apple /
Facebook / LINE / WeChat) 자산 모두 단일 표준 디렉토리 (`assets/brand/{provider}/`)
+ 7필드 README schema 를 따른다.

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
├── facebook/README.md       # sign_in_button community package (Phase 18 마이그 예정)
├── line/.placeholder + README.md   # Phase 14 (LINE) 진입 시 자상 commit
└── wechat/.placeholder + README.md # Phase 16 (WeChat) 진입 시 자상 commit
```

### Provider 별 출처 + 라이선스

| Provider | 공식 BI URL | 자산 형식 | 라이선스 | 사용자 사전 검수 |
|----------|------------|-----------|---------|-----------------|
| Kakao    | https://developers.kakao.com/docs/ko/kakaologin/design-guide | PNG + PSD | Kakao Resources Terms | N/A (가이드 준수만) |
| Naver    | https://developers.naver.com/docs/login/bi/bi.md | PNG + Figma + AI | NAVER Brand License | **사용자 책임** (가이드 준수 — starter-kit 은 검수 자동화 미제공) |
| Google   | https://developers.google.com/identity/branding-guidelines | SVG | Google Terms of Service | N/A |
| Apple    | https://developer.apple.com/design/human-interface-guidelines/sign-in-with-apple | (SDK 위제) | Apple HIG (`sign_in_with_apple` 패키지 BSD-3-Clause) | N/A |
| Facebook | (현재 sign_in_button 4.1.0 community-rendered) | (community-rendered) | sign_in_button MIT | Phase 18 — Meta Brand Center 자상 교체 예정 |
| LINE     | https://developers.line.biz/en/docs/line-login/login-button/ | PNG + PSD (19 언어) | LINE Branding License | **사용자 책임** (Phase 14 진입 시) |
| WeChat   | https://developers.weixin.qq.com/doc/oplatform/en/Downloads/Design_Resource.html | PNG only (24/32/48/64) | WeChat Brand Guideline | **사용자 책임** (변형 절대 금지, Phase 16 진입 시) |

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

### 2단계 — Phase 14/16 진입 시 LINE/WeChat 자상 commit

starter-kit 은 LINE/WeChat 자상 미commit (Phase 13.1 sentinel). Phase 14
(LINE) / Phase 16 (WeChat) 시작 시:

1. **LINE:** https://developers.line.biz/console/ 자상 다운 (PNG 다중 해상도
   + PSD, 19 언어 중 채택 변형 결정).
   **WeChat:** https://open.weixin.qq.com/ 자상 다운 (4 해상도 PNG only —
   24/32/48/64px, **변형 절대 금지** — WeChat Brand Guideline 명시).
2. `assets/brand/{line,wechat}/[{lang}/][{theme}/]` 에 파일 + `LICENSE.txt`
   commit.
3. `git rm assets/brand/{line,wechat}/.placeholder` (sentinel 해제).
4. `assets/brand/{line,wechat}/README.md` 의 7필드 (특히 "다운로드 일자") 갱신.
5. `fvm flutter test test/features/auth/presentation/_widgets/brand_assets_lint_test.dart`
   실행 — sentinel 제거 검증의 **source-of-truth 는 본 lint test**.
   `.placeholder` 가 부재 + README 7필드 모두 채워짐을 자동 검증, PASS 로
   전환되면 sentinel 제거 절차 완료. **별도 const list 직접 수정 불필요**
   — production widget 의 placeholder fallback 분기는 sealed switch
   (`LineSpec` / `WechatSpec` case) 가 컴파일 시점에 처리.
   (참고: lint test 가 의존하는 const 정의 파일의 정확한 경로는 본 manual
   이 인용하지 않는다 — 향후 phase 에서 파일이 재배치되어도 본 절차가
   유효하도록 lint test PASS 자체를 sentinel 제거의 source-of-truth 로
   채택.)

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

- **WeChat:** 변형 절대 금지 — 24/32/48/64 px 4 해상도만 사용, 다른 사이즈
  / 색상 / 비율 변형 금지 (WeChat Brand Guideline 명시).
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
- **Facebook:** 현재 `sign_in_button` community package — Phase 18 Brand
  Center 권한 확보 후 공식 자상 마이그.
- **사용자 책임:** Naver / LINE / WeChat 은 일부 사용 시 사전 검수 신청 별도
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
`setState({_socialError = err, _emailError = null})` 블록만 보존
(P3 / 09.2-03-PLAN.md commit 616603c). `AccountExistsWithDifferentCredential.email`
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
     // Phase 17 부활 시 add-only — kakao, naver, line, yahooJp, wechat 도
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

- **호출자 (2곳):**
  - `lib/features/home/presentation/environment_info_screen.dart` `_confirmSignOut` (production 로그아웃 다이얼로그 confirm path)
  - `lib/features/home/presentation/environment_info_screen.dart` `_handleForceSignOut` (Dev Tools 강제 로그아웃 — Phase 10.2 D-A4 production 와 완전 동일 동작 강제)
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

---

*Last updated: 2026-05-10 — Phase 9.2 P5 docs (Multi-Provider Account Linking 단락 신규)*
