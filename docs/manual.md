<!-- Phase 13 — see ROADMAP.md -->
---
last_updated: 2026-09-26
phases: [03 (Design System), 09 (Facebook), 11 (Cloud Functions + RC), 12 (Kakao Login), 13 (Naver Login), 16.3 (iOS SPM), 16.5 (Naver web OAuth), 16.6 (provider 제거 가이드), 16.7 (가입 수단 기록)]
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
7. [Custom Token Provider 추가 가이드 (stub)](#custom-token-provider-추가-가이드-stub)
8. [Custom Token Provider 제거 가이드 (Phase 16.6)](#custom-token-provider-제거-가이드-phase-166)
9. [Cloud Functions 배포 / Remote Config Kill Switch (Phase 11-04)](#cloud-functions-배포--remote-config-kill-switch-phase-11-04)
10. [Kakao Brand Asset 라이센스 / 출처 (Phase 12-07)](#kakao-brand-asset-라이센스--출처-phase-12-07)
11. [Brand Asset Management (Phase 13.1)](#brand-asset-management-phase-131)
12. [Account Linking & Withdrawal (Phase 16)](#account-linking--withdrawal)
13. [회원탈퇴 cleanup TODO (Phase 17)](#회원탈퇴-cleanup-todo-phase-17)
14. [Multi-Provider Account Linking (Phase 9.2)](#multi-provider-account-linking-phase-92)
15. [App Entry State Machine (Phase 10.2)](#app-entry-state-machine-phase-102)
16. [로그인 화면 구조 — 이메일 격하 (Phase 16.1)](#로그인-화면-구조--이메일-격하-phase-161)
17. [Design System — 디자인 토큰 커스터마이징 (Phase 3)](#design-system--디자인-토큰-커스터마이징-phase-3)
18. [ATT (App Tracking Transparency) 와 iOS Facebook 로그인 — 앱 책임 영역](#att-app-tracking-transparency-와-ios-facebook-로그인--앱-책임-영역)
19. [정적 분석 — woody_lints · riverpod_lint](#정적-분석--woody_lints--riverpod_lint)
20. [Flutter SDK 상향 (FVM)](#flutter-sdk-상향-fvm)
21. [iOS 의존성 관리 (SPM)](#ios-의존성-관리-spm)

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
| `naverClientId` | Naver Developers Console > 본인 앱 > 개요 > **Client ID** | Android 는 gradle 이 dart-defines 에서 읽어 string resource 로 주입 (Phase 16.2). iOS 는 `ios/Flutter/{flavor}.xcconfig` 의 `NAVER_CLIENT_ID` 에 같은 값을 따로 넣는다. **Phase 16.5 부터 Dart 도 읽는다** — `AppConfig.naverClientId`(NAVER 앱 미설치 단말의 킷 웹 경로 authorize URL 의 `client_id`, 공개 식별자). xcconfig 값과 다르면 1-tap 과 웹 경로가 서로 다른 앱으로 로그인한다 |
| `naverClientSecret` | Naver Developers Console > 본인 앱 > 개요 > **Client Secret** | Android 는 gradle 이 dart-defines 에서 읽어 string resource 로 주입 (Phase 16.2). iOS 는 `ios/Flutter/{flavor}.xcconfig` 의 `NAVER_CLIENT_SECRET` 에 같은 값을 따로 넣는다. Dart 코드는 이 키를 읽지 않는다. Firebase Secret Manager `NAVER_CLIENT_SECRET` 과 **같은 값 2본**이다 (Naver 8단계) |
| `naverUrlScheme` | Naver Developers Console > API 설정 > iOS 환경 > **URL Scheme** | iOS SDK 의 실제 출처는 `ios/Flutter/{flavor}.xcconfig` 의 `NAVER_URL_SCHEME`. **Phase 16.5 부터 킷 웹 경로의 콜백 scheme 으로도 쓰인다** — Dart `AppConfig.naverWebCallbackScheme` + Android gradle manifest placeholder `naverWebCallbackScheme`. 소문자 영숫자(RFC 3986)여야 한다 (Naver 9단계) |
| `appName` | (선택) 앱 표시 이름 — `StarterKit Dev` 기본값 | flavor 별 구분. Android 에서 Naver 동의 화면 앱 이름으로도 쓰인다 (Phase 16.2). 따옴표 등 특수문자가 든 값의 Android 빌드 영향은 `[ASSUMED]` 미검증이라 영숫자 · 공백만 쓰기를 권장한다 |
| `appSuffix` | (선택) ApplicationId / BundleId suffix — `.dev` 기본값 | `flutter_native_splash` / Firebase 프로젝트 분리 |
| `splashMinDurationMs` | (선택) 스플래시 최소 노출 시간 — `2000` 기본값 | UX 조정용 |
| `enabledAuthProviders` | (선택) CSV — `google,apple,facebook,kakao,naver,line` 기본값 (dev 예시 기준) | Phase 11 D-26 정책: 정적 false 우위, RC 로 disable 만 가능 (Phase 13 에서 `,naver` · Phase 14 에서 `,line` 추가) |

> 각 키의 콘솔 등록 절차 (앱 생성, redirect URI, 키 해시 등) 는 본 매뉴얼의
> Phase 별 단락 (Phase 12 = Kakao, Phase 13 = Naver, Phase 14 = LINE) 을
> 참조.

#### 3단계 — iOS xcconfig 별도 주입 (Kakao · Naver · Facebook 등)

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
- `NAVER_CLIENT_ID` — Naver Developers Console > 내 애플리케이션 > 본인 앱 > 개요 의
  **Client ID** (Phase 16.2 신규). `config/dev.json` 의 `naverClientId` 와 동일 값.
- `NAVER_CLIENT_SECRET` — Naver Developers Console > 내 애플리케이션 > 본인 앱 > 개요 의
  **Client Secret** (Phase 16.2 신규). `config/dev.json` 의 `naverClientSecret` 와
  동일 값.
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
- **iOS `GoogleService-Info.plist` 도 같은 규칙 — dev 라고 예외가 아니다** —
  `ios/config/dev/GoogleService-Info.plist` / `ios/config/stg/GoogleService-Info.plist` / `ios/config/prod/GoogleService-Info.plist`
  3종은 **전부 placeholder 로 tracked** 되어 있다 (Xcode 의
  `Copy GoogleService-Info.plist` 빌드 단계가 파일 부재 시 빌드를 중단시키므로
  3 flavor 모두 파일 자체는 있어야 한다). 개발자의 실제 dev plist 는
  `./scripts/firebase-configure.sh dev` 가 생성하고 skip-worktree 로 가린
  **로컬 전용 사본**이며 커밋되지 않는다. 실 키가 든 재생성본을 강제로 staged
  하면 pre-commit 가드 3 이 차단하므로 우회하지 말 것 — placeholder 자체를
  고칠 때만 `--no-skip-worktree` 로 일시 해제한다.
- **`./scripts/firebase-configure.sh` 가 멈추거나 ruby 에러로 죽는다** —
  FlutterFire CLI 는 `--ios-out` 만 주고 `--ios-build-config` 을 빼면 "build
  configuration vs target" 선택 프롬프트를 띄우며, `--yes` 로도 막히지 않아
  비대화형 셸이 그대로 대기한다. 스크립트는 `--ios-build-config=Debug-<flavor>`
  를 항상 전달하므로 이 증상은 **수동 `fff configure`** 에서만 재현된다.
  또 CLI 는 그 값을 검증할 때 ruby 의 `xcodeproj` gem 으로
  `ios/Runner.xcodeproj` 를 파싱하므로 gem 이 없으면 실패한다 —
  `gem install xcodeproj` (또는 gem 이 있는 ruby 를 PATH 앞에) 로 해결한다.
  이 함정의 주체는 **flutterfire CLI 의 ruby gem 의존**이지 프로젝트의 의존성
  관리자가 아니다 — 이 킷의 iOS 는 SPM 이라 CocoaPods 를 설치할 필요가 없지만
  (「iOS 의존성 관리 (SPM)」 참고), CocoaPods 를 따로 설치해 둔 머신이라면
  CocoaPods 에 벤더링된 xcodeproj 는 gem 경로 밖이라 인식되지 않는다.
  2026-09-11 실측: 수동 `fff configure` 는 `ios/Runner.xcodeproj/project.pbxproj`
  (중복 `bundle-service-file` 단계 추가 + crashlytics 단계 인자가
  `--build-configuration=${CONFIGURATION}` 으로 교체 → `firebase.json` 에
  등록되지 않은 8개 configuration 의 iOS 빌드 실패) 와 `firebase.json` 을
  함께 변형한다. 스크립트 경로는 두 파일을 실행 전 스냅샷했다가 실행
  후(실패 포함) 자동 복원하고, 생성된 dart options 에 `fvm dart format` 을
  적용해 포맷 게이트와 어긋나지 않게 한다.

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
`not-found` 로 실패**합니다 (Custom Token 로그인(Kakao · Naver · LINE) · 회원탈퇴가 모두 막힙니다).
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

4. 인증 성공 → Home 진입 + EnvironmentInfoScreen Account 카드 →
   「가입 수단: 카카오」 · 「연결된 계정: 없음」 확인.

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

클라이언트 SDK 는 `naver_login_flutter` **4.0.0** 입니다 (Phase 16.2 교체).
unverified publisher 패키지이므로 `pubspec.yaml` 에 **정확 버전으로 고정**되어 있고
(caret 금지), 상향할 때는
`.planning/phases/16.2-naver-login-plugin-migration/16.2-PLUGIN-AUDIT.md` 의 기준선과
diff 검토를 먼저 돌립니다. 이 패키지가 감싸는 네이티브 SDK 는 iOS
`NidThirdPartyLogin` 5.2.x · Android `com.navercorp.nid:oauth` 5.11.2 두 종입니다.

이 플러그인은 **runtime `initialize()` 가 없습니다.** Client ID · Client Secret ·
동의 화면 앱 이름을 앱 기동 시점의 Dart 코드가 아니라 **빌드 타임 native 설정**
(Android `AndroidManifest.xml` 의 `com.naver.sdk.*` meta-data / iOS `Info.plist` 의
`Nid*` 키) 에서 읽습니다. 그래서 키를 채우는 곳이 아래 6단계(Android) 와
7단계(iOS) **두 곳**으로 나뉩니다.

NAVER 앱 설치 단말은 1-tap(wrapper `logIn()` — 앱 → 동의 → callback), 미설치
단말은 **킷이** `flutter_web_auth_2` 로 authorize URL 을 직접 열어 `code` + `state`
를 받고 Cloud Function `naverWebCustomToken` 이 `client_secret` 으로 교환합니다
(Phase 16.5 D-01 · D-04). 판정은 호스트 네이티브(Android
`NidApplicationUtil.isExistNaverApp` · iOS `canOpenURL`)이고 판정 실패는 웹
경로입니다. 미설치 단말에서 SDK 의 커스텀탭 fallback 은 **타지 않습니다**
(Pitfall 19). 웹 경로의 설정 · 확인 절차는 아래 9단계입니다.

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
   `naverClientSecret` + `ios/Flutter/dev.xcconfig` 의 `NAVER_CLIENT_ID` /
   `NAVER_CLIENT_SECRET` 에 주입).

> **fork 사용자 주의 (Phase 16.2 이관):** 클라이언트 시크릿은 앱 바이너리에서
> 추출 가능합니다 (Naver SDK 가 client 측 설정 값으로 요구하는 설계상 불가피).
> Android 는 네이티브 SDK 가 이 값을 기기 저장소에도 암호화 사본으로 보관합니다.
> 이 값은 **서버 시크릿이 아니며**, 반드시 **자신의 키를 발급받아** 사용할 것 —
> 스타터킷의 dev 키를 그대로 배포하지 말 것.

### 3단계 — Naver Login Open API Service Environment 추가

"내 애플리케이션 > 본인 앱 > **API 설정**" 탭에서:

1. **iOS 환경 등록**:
   - Bundle ID 입력: `com.slimpumpkin.flutter_starter_kit.dev` (dev flavor —
     본 starter kit 의 iOS Bundle Identifier. Xcode 의 Build Settings >
     Product Bundle Identifier 또는 `ios/Flutter/dev.xcconfig` 기준)
   - **iOS URL Scheme** 입력 — **소문자 영문 · 숫자만** (예: `myappnaverdev`).
     이 값은 `config/dev.json` 의 `naverUrlScheme`
     + `ios/Flutter/dev.xcconfig` 의 `NAVER_URL_SCHEME` 양쪽에 동일하게
     주입해야 합니다. Phase 16.5 부터 이 값이 킷 웹 경로의 콜백 scheme 도
     겸하므로(9단계) 대문자 · underscore 를 쓰면 웹 경로가 세션을 열기 전에
     `code=config` 로 실패합니다 (RFC 3986 scheme 규칙 + Android intent-filter 는
     대소문자를 구분).

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

이 키들의 소비처는 둘입니다.

- **SDK 1-tap 경로 (Android 빌드 입력):** `android/app/build.gradle.kts` 가
  dart-defines 에서 `naverClientId` · `naverClientSecret` · `appName` 을 읽어
  `resValue("string", …)` 로 주입하고, `AndroidManifest.xml` 의 `com.naver.sdk.*`
  meta-data 가 그 string resource 를 참조합니다. iOS SDK 는 이 경로를 타지 않으며
  **7단계의 xcconfig 가 실제 출처**입니다.
- **킷 웹 경로 (Phase 16.5 — Dart + Android manifest):** Dart 가
  `naverClientId`(→ `AppConfig.naverClientId`) 와 `naverUrlScheme`(→
  `AppConfig.naverWebCallbackScheme`) **두 키만** 읽고, gradle 이 `naverUrlScheme`
  을 manifest placeholder `naverWebCallbackScheme` 으로도 넘깁니다(9단계).
  `naverClientSecret` 은 Dart 가 **읽지 않습니다** — 웹 경로의 secret 은 서버
  Secret Manager 에만 있습니다(8단계).

> **stg / prod 는?** dev 와 동일한 절차로 사용자 자체 Naver 앱을 별도 등록 +
> 키 주입. starter kit 의 stg/prod config 는 placeholder 만 포함합니다 (D-22).

### 7단계 — iOS xcconfig 갱신 (Naver 3변수)

iOS 는 플러그인이 `register(with:)` 시점 (= Dart 가 뜨기 전) 에 `Info.plist` 를
직접 읽기 때문에 값이 **빌드 설정(xcconfig)** 에서 와야 합니다.
`ios/Flutter/dev.xcconfig` 에 다음 **3변수**를 넣습니다
(`ios/Flutter/dev.example.xcconfig` 의 placeholder 를 본인 값으로 교체):

```
NAVER_CLIENT_ID = <Naver Console 개요 탭의 Client ID>
NAVER_CLIENT_SECRET = <Naver Console 개요 탭의 Client Secret>
NAVER_URL_SCHEME = <Naver Console 에서 입력한 iOS URL Scheme>
```

(따옴표 없이 `=` 뒤에 값만. `ios/Runner/Info.plist` 의 `NidClientID` ·
`NidClientSecret` · `NidUrlScheme` 이 이 변수들을 `$(…)` 로 치환합니다.)

- **config json 과 값이 중복되는 것은 의도된 것입니다** — Kakao · Facebook 과 같은
  방식입니다. 6단계의 `config/{flavor}.json` 은 Android 입력, 7단계의 xcconfig 는
  iOS 출처이며, 두 값이 어긋나면 Android 와 iOS 가 서로 다른 앱으로 로그인합니다.
- **동의 화면에 뜨는 앱 이름은 `DISPLAY_NAME` 을 따릅니다** — `Info.plist` 의
  `NidAppName` 이 `$(DISPLAY_NAME)` 이므로 같은 xcconfig 의 `DISPLAY_NAME` 한 곳만
  바꾸면 앱 표시명과 동의 화면 이름이 함께 바뀝니다. Naver 전용 앱 이름 변수는
  만들지 않았습니다 (Android 은 `config/{flavor}.json` 의 `appName` 이 그 역할).
- **플러그인의 `dart run naver_login_flutter:configure` CLI 는 쓰지 않습니다** —
  flavor 개념이 없어 `Debug` / `Release` 2개 xcconfig 만 인식하고, 무엇보다 tracked
  `ios/Runner/Info.plist` 에 Client ID 를 평문으로 기록하고 `android/local.properties`
  에 secret 을 씁니다. 실행하면 시크릿이 git 에 들어가고 계약 테스트가 즉시 실패합니다.
- **iOS 웹 경로(NAVER 앱 미설치)는 추가 plist 설정이 없습니다 (Phase 16.5)** —
  iOS 도 Android 와 같은 `flutter_web_auth_2` 5.1.0 이 `ASWebAuthenticationSession`
  을 열고(콜백 scheme 은 인자로 넘겨 `CFBundleURLTypes` 등록 불요), 호스트 쪽
  Swift 는 설치 판정 1파일(`ios/Runner/NaverHostChannel.swift`)뿐입니다. 이 파일은
  `Info.plist` `LSApplicationQueriesSchemes` 의 `naversearchthirdlogin` 선언(Phase 13
  에서 이미 존재)에 기대므로, 그 줄을 지우면 NAVER 앱이 있어도 항상 웹 경로로 갑니다.

### 8단계 — Firebase Secret Manager 등록 (Phase 13 D-60 · Phase 16.5)

Naver 서버 함수 2개가 Secret Manager 의 secret 2종을 씁니다.

| secret | 값 | 사용처 |
|--------|----|--------|
| `NAVER_CLIENT_SECRET` | 개요 탭의 Client Secret (`config/{flavor}.json` 의 `naverClientSecret` 와 같은 값) | Phase 16.5 부터 사용처 1 — `naverWebCustomToken` 의 `code` 교환. `naverCustomToken`(1-tap) 은 D-60 정책으로 선언만 하고 쓰지 않습니다 |
| `NAVER_CLIENT_ID` | 개요 탭의 Client ID (`config/{flavor}.json` 의 `naverClientId` 와 같은 값) | Phase 16.5 신규 — `naverWebCustomToken` 의 교환 요청 파라미터. 앱 쪽 값과 다르면 NAVER 가 교환을 거부합니다 |

```bash
firebase use <dev-project-id>
firebase functions:secrets:set NAVER_CLIENT_SECRET
# prompt:
#   ? Enter a value for NAVER_CLIENT_SECRET: <Client Secret 붙여넣기 + Enter>
#   (config/dev.json 의 naverClientSecret 와 동일 값)
firebase functions:secrets:set NAVER_CLIENT_ID
# prompt:
#   ? Enter a value for NAVER_CLIENT_ID: <Client ID 붙여넣기 + Enter>
#   (config/dev.json 의 naverClientId 와 동일 값)
```

기대 응답 (secret 마다 1줄):
```
✔ Created a new secret version projects/.../secrets/NAVER_CLIENT_SECRET/versions/1
✔ Created a new secret version projects/.../secrets/NAVER_CLIENT_ID/versions/1
```

확인 (값이 터미널에 출력되므로 화면 공유 · 로그 수집 중에는 하지 말 것):
```bash
firebase functions:secrets:access NAVER_CLIENT_SECRET
firebase functions:secrets:access NAVER_CLIENT_ID
```

> **`config/{flavor}.json` 의 `naverClientSecret` 과 Secret Manager 의
> `NAVER_CLIENT_SECRET` 은 같은 값 2본입니다.** 서버 교환을 도입했다고 앱 번들에서
> secret 이 사라지지 않습니다 — NAVER SDK 1-tap 경로가 native 설정(Android
> meta-data · iOS `Info.plist`)의 `clientSecret` 을 필수로 요구하기 때문입니다
> (Phase 16.5 D-19, 2단계의 「fork 사용자 주의」 그대로). 서버 교환의 가치는
> **secret 은닉이 아니라** 웹 경로가 RFC 8252 공개 클라이언트 모양이 되고
> (`client_secret` · access token · refresh token 이 킷 Dart 코드 · 로그 · callable
> 응답 어디에도 없음) NAVER 앱 미설치 단말에서 로그인이 착지한다는 데 있습니다.
> secret 을 교체할 때는 두 곳(+ iOS xcconfig)을 함께 바꿉니다.

> Cloud Function 의 `defineSecret(...)` 이 배포 시점에 자동으로 함수 환경변수로
> 주입합니다 (Phase 11 D-05 패턴). 배포가 compute 서비스 계정에 `secretAccessor`
> 를 자동 부여합니다. refresh token 은 저장하지 않습니다 (refresh / deauth flow 는
> Phase 17+).

### 9단계 — 웹 경로(앱 미설치) Callback URL · redirect_uri 확인 (Phase 16.5)

NAVER 앱이 없는 단말에서 킷은 authorize URL 을 직접 엽니다. 이때 NAVER 가 로그인
뒤 돌려보낼 주소(`redirect_uri`)를 받아들여야 합니다. 이 단계는 **콘솔 작업 없이**
끝나는 것이 정상이지만, 왜 그런지와 막혔을 때의 확인 방법을 적어 둡니다.

**(1) 왜 확인이 필요한가.** 네이버 개발자센터의 Android / iOS 서비스 환경에는
Callback URL 입력 칸이 있는지 확인되지 않았습니다 — 킷 검증 때는 콘솔을 열지 않고도
(아래 후보 A) 통과해 칸 유무를 보지 않았습니다(`CONSOLE_CALLBACK_FIELD: UNKNOWN`).
임의로 정한 scheme 을 넣으면 authorize 가 로그인 폼 대신 오류 페이지를 낼 수
있으므로, 이미 콘솔에 등록된 값을 재사용합니다.

**(2) 브라우저 probe 절차 (1분).** PC 브라우저 주소창에 아래 URL 을 **본인 값으로
조립해** 엽니다. 파라미터는 4개뿐이고, `client_secret` 은 **절대 넣지 않습니다**.

```
https://nid.naver.com/oauth2.0/authorize?response_type=code&client_id=<clientId>&redirect_uri=<naverUrlScheme>%3A%2F%2Fauthorize&state=probe1
```

- 합격: NAVER **로그인 폼**이 뜨고, 로그인 뒤 브라우저가
  `<naverUrlScheme>://authorize?code=…&state=probe1` 로 이동하려 합니다(PC 에는 그
  scheme 을 받을 앱이 없어 이동 실패 · 주소창 표시만 되는 것이 정상). `code=` 와
  `state=probe1` 이 있으면 통과입니다. `code` 값은 1회용이므로 기록 · 공유하지 말고
  교환하지도 않습니다.
- 불합격: 로그인 폼 대신 NAVER 오류 페이지 → 아래 (6) 대안으로 갑니다.
- 후보(킷이 검토한 3안): **A** `<naverUrlScheme>://authorize`(기존 iOS URL Scheme
  재사용) · **B** 새 역도메인 scheme(`<소문자 bundleId 형태>://naver/callback`) ·
  **C** https Hosting bounce(`https://<project>.web.app/naver/callback`).

**(3) 이 킷의 채택 결과 — 후보 A.** dev 앱에서 A 가 콘솔 작업 0 으로 로그인 폼 표시 ·
콜백 도착 · `state` echo 까지 통과했고(2026-09-23), B · C 는 열지 않았습니다.
authorize 부가 파라미터(`locale` · `oauth_os` · `version` · `network`)는 없어도
통과했습니다. A 의 scheme 은 3단계에서 콘솔 「iOS URL Scheme」 에 이미 등록한 값이라
NAVER 가 그 앱의 주소로 인식하는 것으로 봅니다(완전히 임의의 문자열 B 의 수락 여부는
미실측). 근거: `.planning/phases/16.5-naver-web-oauth-kit-owned-flow/16.5-PROBE-RESULT.md`
`## 3.`

**(4) scheme 파생 규칙 — 채택자 커스터마이징 포인트.** URI scheme 은 RFC 3986 상
`소문자 알파벳 *(영숫자 / + / - / .)` 이어야 하고 underscore 를 쓸 수 없습니다.
그래서 applicationId / bundleId(`com.slimpumpkin.flutter_starter_kit.dev` — underscore
포함)를 그대로 scheme 으로 쓸 수 없고, 킷은 **새 config 키 없이** 기존
`naverUrlScheme` 을 재사용합니다.

| 위치 | 공급식 | 바꿀 때 |
|------|--------|---------|
| Dart | `AppConfig.naverWebCallbackScheme = String.fromEnvironment('naverUrlScheme')` · `naverWebRedirectUri = '<scheme>://authorize'` (`lib/core/config/app_config.dart`) | 키 이름을 바꾸지 않는 한 수정 불요 |
| Android | `android/app/build.gradle.kts` `manifestPlaceholders["naverWebCallbackScheme"] = dartDefines["naverUrlScheme"] ?: ""` | 같음 |
| iOS | 추가 설정 없음 (세션이 scheme 을 인자로 받음) | — |
| 값 | `config/{flavor}.json` `naverUrlScheme` = `ios/Flutter/{flavor}.xcconfig` `NAVER_URL_SCHEME` = 콘솔 「iOS URL Scheme」 | 세 곳을 함께 · 소문자 영숫자 |

형태 위반(대문자 · underscore · 빈 값)은 세션을 열기 전에 debug 로그
`Naver web 도착: outcome=error elapsedMs=0 code=config` + 오류 배너로 드러납니다.

**(5) Android 콜백 수신 — 킷 relay `WebAuthCallbackActivity` (G-16.5-2).**
`android/app/src/main/AndroidManifest.xml` 에 킷 소유 `.WebAuthCallbackActivity`
(`exported="true"` · `taskAffinity=""` · intent-filter
`<data android:scheme="${naverWebCallbackScheme}" />`)가 선언돼 있고, scheme 은 위
placeholder 가 채웁니다. 구현은
`android/app/src/main/kotlin/com/slimpumpkin/flutter_starter_kit/WebAuthCallbackActivity.kt`
입니다. **`flutter_web_auth_2` README 가 안내하는 라이브러리 콜백 Activity
(`CallbackActivity`) 는 선언하지 않습니다.**

- **왜 라이브러리 것을 쓰지 않나:** Chrome Auth Tab 을 지원하지 않는 브라우저(킷
  실측: Samsung Internet 30)는 Custom Tab 으로 fallback 합니다. 그 경로에서 라이브러리
  콜백 Activity 는 결과를 전달하지만 **탭을 닫지 못해 검은 화면이 남습니다.**
  라이브러리의 닫기 동작은 같은 task 안에서만 통합니다. 그런데 MainActivity(Flutter
  템플릿)와 콜백 Activity 가 둘 다 빈 `taskAffinity` 라서 콜백이 새 task 에
  떨어집니다. 상류 `ThexXTURBOXx/flutter_web_auth_2` **#158** 이 이 문제이고 OPEN
  입니다. 5.1.0 · 6.0.0-alpha.8 · master 의 해당 파일이 같으므로 버전을 올려도 풀리지
  않습니다.
- **relay 가 하는 일:** 콜백 URL 을 대기 중인 호출에 넘깁니다(라이브러리와 같은
  경로 — `FlutterWebAuth2Plugin.callbacks`). 그다음 MainActivity 를 띄워 기존 task 를
  앞으로 되돌립니다. flag 는 대기 호출을 실제로 넘겼는지에 따라 다릅니다.
  - **전달함(정상 로그인):** `NEW_TASK | CLEAR_TOP | SINGLE_TOP`(logcat
    `flg=0x34000000`). 원래 인증 관리 Activity 와 Custom Tab 이 걷히고, Flutter
    엔진은 그대로 유지됩니다(MainActivity `launchMode="singleTop"` 전제).
  - **대기 호출 없음(외부 앱 · 브라우저 링크가 띄운 경우 · 중복 콜백 · 앱 재기동
    뒤 콜백):** `NEW_TASK | SINGLE_TOP` 만(`flg=0x30000000`). 앱을 앞으로 가져오기만
    하고 MainActivity 위의 화면(Kakao · Apple 인증 화면, NAVER 1-tap 대기
    화면, 이미지 picker 등)은 걷지 않습니다. relay 는 누구나 띄울 수 있는
    Activity 라서, 외부 intent 하나로 진행 중인 다른 흐름이 끊기지 않게 하려는
    것입니다.
  - **대가:** 앱 프로세스가 죽은 뒤 도착한 콜백은 대기 호출이 없어 Custom Tab 을
    닫지 못합니다. 그 로그인은 어차피 이어지지 않으므로(취소와 같은 결과) 사용자가
    tab 을 직접 닫고 다시 로그인하면 됩니다.
- **기각한 대안 두 개:**
  - 빈 `taskAffinity` 제거(#158 커뮤니티 우회): minSdk 24(< 30)에서 StrandHogg 에
    노출됩니다. MainActivity 를 바꾸므로 다른 provider 흐름에도 영향이 갑니다.
  - 인증 관리 Activity 를 manifest 에서 `singleTask` 로 override: Chrome Auth Tab
    경로의 task 배치 · 최근 앱 목록까지 바뀝니다.
- **Chrome Auth Tab(141+) 은 relay 를 거치지 않습니다.** 결과가 Activity result 로
  돌아오므로 relay 가 기동되지 않는 것이 정상입니다(plan 06 · 09 실측).
- **채택자 주의:**
  - `flutter_web_auth_2` 를 올릴 때는 상류 콜백 Activity 의 전달 방식과 플러그인
    `callbacks` companion 이 그대로인지 확인합니다. `callbacks` 가 없어지면 Android
    빌드가 실패합니다(조용한 실패가 아닙니다).
  - 상류가 #158 을 고치면 relay 를 걷고 README 의 선언 방식으로 돌아갈 수 있습니다.
  - README 의 콜백 Activity 선언을 relay 와 **함께** 넣으면 같은 scheme 을 받는
    Activity 가 2개가 됩니다. 계약 테스트 `T-16.5-NATIVE-04` 가 이를 잡습니다.
- **실측 상태:** 2026-09-24 SM-S942N Samsung Internet 30 에서 탭이 닫혔고,
  Chrome Auth Tab · NAVER 앱 1-tap 회귀도 통과했습니다(G-16.5-2 재UAT
  `G2_RESULT: PASS`). 합성 콜백 · 실제 로그인 모두 relay 뒤 세션 시작과 같은
  MainActivity 인스턴스로 돌아왔습니다. 근거:
  `.planning/phases/16.5-naver-web-oauth-kit-owned-flow/16.5-UAT-RESULT.md` `## 8.`
- **Auth Tab 미지원 브라우저를 직접 재현하려면:** `adb shell cmd role
  add-role-holder --user 0 android.app.role.BROWSER com.sec.android.app.sbrowser` 로
  기본 브라우저를 바꿉니다. 이어서 NAVER 앱을 비활성화하고,
  `https://nid.naver.com/nidlogin.logout` 을 열어 로그인 폼이 뜨게 만듭니다. 판정은
  화면이 아니라 `dumpsys activity activities` 의 `topResumedActivity` 가 로그인
  전과 같은 MainActivity record 인지로 합니다. 끝나면 기본 브라우저와 NAVER 앱을
  원래대로 돌려 놓습니다.

병합본 확인: `build/app/intermediates/merged_manifests/devDebug/processDevDebugManifest/AndroidManifest.xml`
의 relay 블록에 `${` 가 남아 있지 않아야 합니다. 이전 빌드가 깔린 단말은 새 scheme 을
받으려면 APK 를 재설치해야 합니다.

**(6) https 만 받는 경우의 대안 — Hosting bounce (킷 미구현 · 미실측).** (2) 가
불합격이고 콘솔이 https Callback URL 만 받는다면, Firebase Hosting 정적 페이지
`https://<project>.web.app/naver/callback` 이 `code` · `state` 를 보존한 채
`<naverUrlScheme>://authorize?…` 로 재이동하게 만들고(세션이 그 이동을 가로챔),
콘솔에 그 https 주소를 Callback URL 로 등록한 뒤 `AppConfig.naverWebRedirectUri`
만 https 주소로 바꿉니다(콜백 scheme 은 그대로). 배포는 `firebase.json` 에 hosting
항목을 추가하고 `firebase deploy --only hosting` 이며, flavor 마다 페이지의 scheme
문자열을 그 flavor 의 값으로 바꿔야 합니다. 킷은 A 가 통과해 이 경로를 만들지
않았습니다.

**(7) `naverClientId` 는 두 경로가 같은 값을 써야 합니다.** 웹 경로는 Dart
dart-define(`config/{flavor}.json`), iOS 1-tap 은 xcconfig(`NAVER_CLIENT_ID`) 에서
읽으므로 두 값이 어긋나면 1-tap 과 웹이 **다른 앱으로** 로그인합니다(조용한 실패).
계약 테스트 `T-16.5-NATIVE-01`(`test/core/config/naver_native_config_contract_test.dart`)
이 dev flavor 의 로컬 실 키 파일(`config/dev.json` · `ios/Flutter/dev.xcconfig`)로
`naverClientId` · `naverUrlScheme` 일치와 scheme 형태를 단언합니다(파일이 없으면
skip · stg/prod 는 직접 대조).

**웹 경로에서 사용자가 보는 것:**

- iOS 는 「"앱"이(가) 로그인하기 위해 "naver.com"을(를) 사용하려고 합니다」 시스템
  확인창이 1회 뜹니다 — `preferEphemeral: false`(SSO 쿠키 공유)의 표준 동작이며
  제거 대상이 아닙니다.
- **NAVER 동의 화면은 이 앱과 NAVER 계정의 연결이 없을 때만 뜹니다** — 첫 로그인,
  사용자가 NAVER 쪽에서 연결을 끊은 뒤, 그리고 서버가 토큰을 폐기하던 이전
  배포본으로 로그인했던 계정의 새 배포 후 첫 로그인. 서버가 교환한 NAVER 토큰을
  폐기하지 않는 이유: NAVER 토큰 삭제 요청(`grant_type=delete`)은 NAVER SDK 에서
  연동 해제(`disconnect`) 전용이라, 부르면 웹 로그인마다 동의 화면이 다시 뜹니다.
  1-tap 경로의 로그아웃도 기기에 저장된 토큰만 지웁니다. 잔존 노출: 교환한
  access_token 은 서버 메모리 밖으로 나가지 않고(저장 · 로깅 · 응답 0), NAVER 가
  교환 응답 `expires_in` 으로 정한 시간이 지나면 만료됩니다 — 값은 서버 로그
  `naver_web_custom_token_issued` 의 `expiresInSec` 로 확인하며, NAVER Android SDK
  5.11.2 는 이 값이 응답에 없을 때 3600초를 기본값으로 씁니다(dev 실측
  2026-09-24: 3600초, 웹 로그인 3회 모두 동일). 근거:
  `.planning/phases/16.5-naver-web-oauth-kit-owned-flow/16.5-CONTEXT.md` 「D-15 번복」.
- 같은 이메일이 다른 provider(예: Apple)로 이미 가입돼 있으면 웹 로그인이 성공해도
  계정 연결 시트(「이미 가입된 이메일입니다」)가 뜨고, 시트 안에서 기존 provider 로
  로그인해야 홈에 착지합니다.

**Naver 를 빼는 채택자:** Android `NaverHostChannel.kt` · `WebAuthCallbackActivity.kt` +
`MainActivity.kt` 의 등록/해제 3줄 + manifest relay 블록(`.WebAuthCallbackActivity`) +
gradle placeholder 1줄 ·
`compileOnly("com.navercorp.nid:oauth:…")` 1줄, iOS `NaverHostChannel.swift` +
`AppDelegate.swift` 등록 1줄 + `project.pbxproj` 4항목(PBXBuildFile ·
PBXFileReference · Runner group · Sources), Dart `naver_host_channel.dart` ·
`naver_web_auth_client.dart` 와 계약 테스트 `T-16.5-NATIVE-*` 를 함께 지웁니다.
`naver_login_flutter` 를 상향할 때는 gradle `compileOnly` 의 SDK 버전도 같이
올립니다(`T-16.5-NATIVE-07` 이 불일치를 잡습니다).

### 10단계 — Cloud Function 배포

Naver 서버 함수 2개 — `naverCustomToken`(Phase 13-02, 1-tap 의 access token 검증)과
`naverWebCustomToken`(Phase 16.5, 웹 경로의 `code` 교환) — 를 dev Firebase
프로젝트 (asia-northeast3) 에 배포합니다. 두 함수는 `/v1/nid/me` 검증 → identity →
Custom Token 체인을 공용 helper 로 공유합니다.

```bash
cd functions
pnpm install           # 최초 1회 (corepack 활성화는 0단락의 4단계 참조)
pnpm run lint          # 0 errors 확인
pnpm run build         # tsc OK 확인
pnpm test              # 전체 jest PASS 확인 (naver 는 naver_custom_token + naver_web_custom_token 두 파일)

# 배포 (8단계의 secret 2종이 먼저 등록돼 있어야 한다)
firebase use <dev-project-id>
firebase deploy --only functions:naverCustomToken,functions:naverWebCustomToken
```

기대 응답 (최초 배포 시 `naverWebCustomToken` 은 create):
```
✔ functions[naverCustomToken(asia-northeast3)] Successful update operation.
✔ functions[naverWebCustomToken(asia-northeast3)] Successful create operation.
```

확인 — Firebase Console:
- "빌드 > Functions" → `naverCustomToken` · `naverWebCustomToken` 함수 row →
  region = `asia-northeast3` + "활성" 상태
- 웹 경로에만 있는 구간(code 교환 · 최종 발급)은 `naver_web_*` 이벤트
  3종(`naver_web_custom_token_issued` · `naver_web_token_exchange_failed` ·
  `naver_web_token_error_response`)을 남깁니다. `naver_web_custom_token_issued` 의
  `expiresInSec` 는 NAVER 가 알려준 access_token 유효 시간(초)이며, 응답 값이 숫자
  형식이 아니면 `null` 입니다 — 토큰 값은 싣지 않습니다.
  `/v1/nid/me` 검증 · identity · Custom Token 발급 구간은 두 경로가 공용 helper 를
  쓰므로 이벤트 이름(`naver_custom_token_issued` · `naver_verify_*` ·
  `naver_email_collision` 등)도 공용이고, payload 의 `path` 필드(`"app"` = 1-tap ·
  `"web"` = 킷 웹)로 경로를 가립니다. 그래서 웹 로그인 1건은
  `naver_custom_token_issued`(`path: "web"`)와 `naver_web_custom_token_issued` 를 둘 다
  남깁니다 — 1-tap 로그인 수는 `naver_custom_token_issued` 를 `path = "app"` 으로
  걸러 세십시오. terms mirror 이벤트(`naver_terms_acceptance_*`)와 `resolveIdentity`
  내부(`identity_index.ts`) 이벤트에는 `path` 가 없습니다.
- NAVER 호출 두 개(code 교환 5s · `/v1/nid/me` 5s)의 시간 예산은 모두
  **응답 본문 읽기까지 포함한 상한**입니다. 그래서 두 예산의 합(10s)이 클라이언트 웹
  경로 callable timeout(20s) 안에 들어온다는 계산이 성립합니다. 교환 ·
  `/v1/nid/me` 가 시간을 넘기면 `naver_web_token_exchange_failed` ·
  `naver_fetch_failed` 경고의 `code` 가 `TimeoutError` 이고, 클라이언트에는
  `unavailable`(일시 장애 배너)로 갑니다. 헤더를 받은 뒤 본문에서 멈춘 경우도 같습니다.
  2026-09-24 리뷰 2회차 fix 이전 배포본은 같은 timeout 을 `AbortError` 로 남겼습니다.

### 11단계 — dev flavor 실 단말 검증

```bash
fvm flutter run --flavor dev --dart-define-from-file=config/dev.json -d <android-device-id>
```

- LoginScreen 의 **"네이버로 시작하기"** 버튼 (그린 #03A94D 배경 + 흰 'N' 로고
  — Phase 13.1 R1 정정 후 NAVER ID 로그인 BI; `## Brand Asset Management
  (Phase 13.1)` 단락 D-Note 참조)
  탭 → Naver 앱 설치 시 1-tap, 미설치 시 킷 웹 경로(9단계 — Android Auth Tab /
  Custom Tab, iOS 웹 인증 세션) → 사용자 동의 → 앱 복귀
- Home 진입 + EnvironmentInfoScreen 의 Account 섹션 — `linkedProviders` 에
  "네이버" 표시 확인
- 두 경로를 모두 보려면 같은 단말에서 NAVER 앱을 비활성화(`adb shell pm
  disable-user --user 0 com.nhn.android.search`)한 채 한 번, 되돌린 뒤(`adb shell pm
  enable com.nhn.android.search`) 한 번 로그인합니다. debug 로그의
  `Naver 경로 선택: mode=web installed=false` / `mode=app installed=true` 가 경로를
  알려 줍니다 (Pitfall 19 의 여섯 접두어).
- iOS 는 Phase 16.5 에서 NAVER 앱 미설치 웹 경로(로그인 · 취소)만 실기기로 확인했고,
  1-tap 은 테스트 SIM 부재로 미검증입니다 —
  `.planning/todos/pending/2026-05-05-ios-naver-uat-deferred.md` 추적.

자세한 8 시나리오 검증 양식 (Phase 13 이력): `.planning/phases/13-naver-login/13-HUMAN-UAT.md`.
플러그인 교체 후의 시나리오와 기대값은
`.planning/phases/16.2-naver-login-plugin-migration/16.2-HUMAN-UAT.md`, 웹 경로의
실기기 결과(3조건 · 재인증 · 취소 · 회귀)는
`.planning/phases/16.5-naver-web-oauth-kit-owned-flow/16.5-UAT-RESULT.md` 입니다.

### 키를 채우기 전에도 빌드 · 기동은 된다

fresh clone 직후처럼 실제 키가 하나도 없고 tracked placeholder 만 있는 상태에서도
**dev / stg / prod 3 flavor 의 Android · iOS 빌드와 앱 기동은 성공**합니다. 새
플러그인은 native 설정을 읽지만 값이 비어 있다고 기동 시점에 죽지 않습니다 —
실패는 **Naver 버튼을 탭했을 때 오류 배너 1회**로만 나타나고, 다른 provider 버튼과
화면은 정상입니다.

이 계약을 직접 확인하려면:

```bash
bash scripts/verify_placeholder_builds.sh <android|ios> <dev|stg|prod>
```

성공 시 마지막 줄이 `PLACEHOLDER-BUILD-OK <platform> <flavor>` 입니다. 이 스크립트는
**본인의 실 키 파일(`config/{flavor}.json` · `ios/Flutter/{flavor}.xcconfig`) 을 읽지도
바꾸지도 않습니다** — tracked placeholder 만 입력으로 씁니다.

### 클라이언트에서의 프로필 조회와 개인정보 (Phase 16.2)

플러그인은 로그인이 성공하면 **클라이언트에서 곧바로**
`https://openapi.naver.com/v1/nid/me` 를 호출해 그 결과를 `account` 로 실어 보냅니다
(iOS · Android 양쪽 동일). `logIn()` 에는 인자가 없어 **이 호출을 끌 수 있는 옵션이
없습니다.**

- 킷은 결과에서 `accessToken` 만 꺼내고 **나머지(`account`) 는 곧바로 버립니다** —
  필드를 참조하는 코드가 0건이고, 결과 · 토큰 객체를 문자열 보간에 넣지 않습니다
  (토큰 클래스의 `toString` 이 access · refresh token 전문을 출력합니다).
- 실제로 내려오는 필드는 5단계의 **동의 항목 설정**에 갇힙니다. 킷이 안내하는 기본
  설정 (필수 `email` · `nickname`, 선택 `profile_image`, 그 외 비활성) 에서는
  **mobile · birthday · gender 가 애초에 내려오지 않습니다.**
- 사용자 프로필의 진실원은 여전히 서버입니다 — Cloud Function `naverCustomToken` 이
  access_token 으로 직접 검증한 값만 씁니다.

### 구 SDK 가 남긴 토큰 (Phase 16.2)

- **Android:** 새 SDK 가 구 SDK 와 같은 저장소를 그대로 쓰고, 레거시
  SharedPreferences 는 SDK 가 자동 이관한 뒤 삭제합니다 — 잔존분이 승계 · 정리됩니다.
- **iOS:** 새 Swift SDK 는 Keychain service name 이 달라서 구 ObjC SDK 가 남긴 항목을
  읽지도 지우지도 않습니다. 따라서 구 항목이 남아 있을 수 있습니다 (구 SDK 의 정확한
  저장 위치는 `[ASSUMED]` — 확인은 본 phase 범위 밖). 앱을 삭제하면 함께 사라지는
  종류의 항목입니다.
- **킷은 일회성 정리 코드를 넣지 않았습니다.** 킷은 이미 배포된 사용자 기기가 없는
  템플릿이고, 정상 경로에서는 매 로그인 finally 에서 기기 토큰을 지우기 때문입니다.

### Pitfall 정리 (Phase 13 · Phase 16.2)

- **Pitfall 1 (구조 소멸):** 구 플러그인이 callback 기반이라 필요했던
  `Completer` 다중 complete 가드는 **Phase 16.2 에서 구조 자체가 사라졌습니다** —
  이제 플러그인이 돌려주는 Future 를 그대로 await 합니다. 앱 쪽 타이머가 없으므로
  「늦게 끝난 성공을 버리는」 주체도 없습니다.
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
- **Pitfall 11 (iOS 취소는 `error` 로 온다):** Android 취소는 status `loggedOut`
  으로 오지만 **iOS 취소는 status `error` + 플러그인이 붙인 고정 영문 리터럴**로
  옵니다. `error` 를 곧장 오류 배너로 보내면 사용자의 취소가 배너로 보입니다.
  킷은 취소 판정을 오류 분기보다 **먼저** 보고, 리터럴을 `contains` 가 아니라
  **완전 일치**로 비교합니다 (넓히면 `-999 cancelled` 같은 네트워크 오류까지
  silent 로 흡수됩니다).
  - **이 완전 일치 규칙은 iOS 표면에만 적용됩니다.** Android 가 취소와 실패를
    구분하지 못하는 원인은 플러그인의 `contains` 가 아니라 **한 단계 상류인
    NAVER Android SDK** 입니다 — SDK 는 커스텀탭 결과가 `data == null` 인 실패를
    사용자 취소와 **같은 상수**(`CLIENT_USER_CANCEL`, code 와 description 이 둘
    다 문자열 `user_cancel`)로 접어 돌려줍니다. 그래서 플러그인이 `contains` 를
    쓰든 완전 일치를 쓰든 킷 경계에 도착한 두 경우는 문자 단위로 같아집니다.
    Phase 16.5 가 미설치 단말의 웹 경로를 킷 소유 흐름으로 바꿔, 이 둘을 가르던
    16.4 의 Android 호스트 쪽 계수(레버 2)는 제거됐습니다 (Pitfall 19). 이 SDK
    표면은 이제 NAVER 앱 설치 단말의 1-tap 경로에만 남습니다.
  - 그래서 Android 에서 「눌렀는데 아무 반응이 없다」 는 제보를 받으면, 먼저
    debug 로그에 취소 로그(`Naver logIn cancel: status=loggedOut …`)가 찍혔는지
    확인하십시오. 사용자가 취소한 적이 없는데 이 줄이 있다면 취소가 아니라
    흡수된 오류입니다 (Pitfall 12 의 무반응과 원인이 다릅니다).
- **Pitfall 12 (iOS 1-tap 미복귀 wedge) — 미해결 · 미검증:** iOS 에서 NAVER 앱으로
  넘어간 뒤 사용자가 돌아오지 않으면, 플러그인의 대기 슬롯이 점유된 채 남아 이후
  호출이 플러그인 내부에서 `Another request is in progress` 로 거부되는 상태가
  됩니다. 다만 **킷을 쓰는 한 이 문구를 보게 되지는 않습니다** — 킷의 in-flight
  가드가 그보다 먼저 plugin 호출 자체를 막기 때문입니다.
  - 증상: **오류 배너도 로딩도 없이, 버튼을 눌러도 아무 반응이 없습니다.**
    가드에 걸린 재진입은 `null` 로 돌아오고 킷은 그것을 사용자 취소와 같게
    (= silent) 처리하므로 화면에는 아무 일도 일어나지 않습니다.
  - 진단: debug 빌드 로그의 `Naver logIn 재진입 무시 (in-flight)` 한 줄이
    유일한 단서입니다. 이 줄이 탭할 때마다 찍힌다면 단말 · 계정 · 콘솔 설정이
    아니라 이 wedge 입니다 (UAT 에서 가장 오진하기 쉬운 증상).
  - 복구: **앱 재시작.** 플러그인에 이 상태를 되돌릴 API 가 없고, 킷에도
    점유된 가드를 되돌리는 경로가 없습니다.
  - 킷의 in-flight 가드는 **요청 폭주만 막는 부분 완화**입니다 — 이미 잠긴 상태를
    풀지 못합니다.
  - 테스트 SIM 이 없는 단말이라 **미검증**으로 남습니다 (재현 자체가 불가).
- **Pitfall 13 (토큰 객체 문자열 보간):** 플러그인의 토큰 클래스는 `toString` 이
  access token 과 refresh token **전문**을 출력합니다. 토큰 객체를 로그 ·
  Crashlytics 에 넣지 말고 필요한 필드 하나만 꺼내 쓰십시오.
- **Pitfall 14 (프로필 API 실패 = 로그인 실패):** 토큰을 이미 받았어도 클라이언트
  프로필 조회가 실패하면 로그인 전체가 실패합니다 — 구 플러그인보다 실패 지점이
  하나 늘었습니다. 보안 위험은 없습니다 (finally 의 logout 이 토큰을 지웁니다).
- **Pitfall 15 (iOS `Info.plist` 키 부재):** `Nid*` 4키 중 하나라도 **키 자체가
  없으면** 플러그인 채널이 등록되지 않아 `MissingPluginException` 이 납니다. 킷은
  변수 치환 방식이라 값이 비어도 키는 항상 존재합니다.
- **Pitfall 16 (Android meta-data 는 `@string` 참조):** meta-data 값을 리터럴로
  직접 쓰면 숫자로만 이뤄진 값이 정수로 컴파일돼 SDK 가 조용히 초기화를 건너뛸
  위험이 있습니다 (`[ASSUMED]`). 킷은 `resValue` + `@string/…` 참조로 이 위험을
  구조적으로 제거했습니다 — 이 구조를 바꾸지 마십시오.
- **Pitfall 17 (NAVER 앱 미설치 · 업데이트 필요):** 플러그인 표면에서는 이 두
  경우가 **종단 오류**로 올라옵니다 (구 wrapper 처럼 후속 콜백을 기다리는 대기
  분기가 없습니다). 구 무시 분기를 그대로 옮기면 Future 가 영원히 완료되지
  않습니다. Phase 16.5 부터 **미설치** 단말은 호스트 판정이 먼저 킷 웹 경로로
  보내므로 SDK 를 부르지 않고, SDK 까지 가는 것은 「앱은 있으나 업데이트 필요」
  뿐입니다 (Pitfall 19 잔여 케이스).
- **Pitfall 18 (네이티브 디버그 로깅):** 플러그인의 네이티브 로깅은 manifest 설정
  으로 **전 flavor off** 입니다. 켜면 logcat 에 client ID 평문과 마스킹된 secret 이
  찍힙니다 — 디버깅 목적으로 잠시 켰다면 반드시 되돌리고, 그 로그를 공유하지
  마십시오.
- **Pitfall 19 (Android 웹 fallback 커스텀탭 재개방) — 상류 미해결 ·
  킷 소유 웹 흐름으로 우회 (Phase 16.5):** NAVER Android SDK 의 웹(커스텀탭) fallback 은
  NAVER 가 돌려준 콜백을 이미 떠 있는 `NidOAuthCustomTabActivity` 로 전달하지 않고
  새 인스턴스를 만들어 커스텀탭을 한 번 더 열고, 원래 호출은 결과 없이 끝납니다
  (Phase 16.4 귀속, 상류 `naver/naveridlogin-sdk-android` **#152**, 결함 자체는
  그대로). 킷은 **NAVER 앱 미설치 단말에서 이 경로를 타지 않습니다** — 호스트가
  설치 여부를 판정해 미설치(또는 판정 실패)면 킷이 `flutter_web_auth_2` 로
  authorize 를 직접 열고, `code` 교환은 `naverWebCustomToken` 이 합니다(9단계).
  Android · iOS 가 같은 웹 흐름을 씁니다. 플러그인 fork · vendoring 은 하지 않습니다.
  - 실증: `naver-off` SM-S942N 에서 쿠키 활성 · 만료 · 재활성 3조건이 각 1회 홈에
    착지했고 SDK 커스텀탭 기동은 0 이었습니다. 재인증 1회 · 취소 1회(배너 없음) ·
    iPhone Air 웹 로그인 1회 · 취소 1회도 같은 결과입니다(`16.5-UAT-RESULT.md`).
  - 잔여 케이스: NAVER 앱은 **설치돼 있으나 업데이트가 필요한** 단말은 1-tap 경로로
    가고, SDK 가 이를 `need_app_update` **종단 오류**로 올려 오류 배너가 뜹니다
    (Pitfall 17 · SDK 내부 순서는 `[ASSUMED]`). 재개방 결함 경로에는 들어가지
    않습니다.
  - 진단 — debug 빌드 로그의 **여섯 접두어** (앱 경로 2 + 웹 경로 4, 전부
    `kDebugMode` 전용):
    - 공통 분기: `Naver 경로 선택: mode=app|web installed=<bool>` — 어느 경로로
      갔는지. 판정 예외가 나면 그 앞에 `Naver 설치 판정 예외(web 으로 접음):` 가
      찍히고 `mode=web` 으로 갑니다.
    - 앱 경로: `Naver logIn 시작` → `Naver logIn 도착: status=… elapsedMs=…` 한 쌍.
      취소면 뒤에 `Naver logIn cancel:`, 오류면 `Naver logIn error:` 가 붙습니다.
    - 웹 경로: `Naver web 시작` →
      `Naver web 도착: outcome=code|cancel|error elapsedMs=<n>[ code=<…>]` 한 쌍.
      콜백 `state` 가 다르면 도착 줄 앞에 `Naver web state 불일치` 가 찍힙니다.
  - grep 앵커 규칙: `outcome=` 값은 `code` · `cancel` · `error` 셋뿐입니다.
    ` code=` 접미는 `outcome=error` 일 때만 붙고 값은 닫힌 집합 `config`(설정 ·
    scheme 형태) · `callback`(콜백 파싱 · NAVER `error` 파라미터) · `state` ·
    `missing`(`code` 부재) 또는 플러그인 `PlatformException.code`(`FAILED` 등)
    입니다. 콜백 URL · `code` · `state` 원문은 **어느 줄에도 없습니다**(길이조차
    싣지 않음). 경과 ms 는 사람의 로그인 · 동의 시간을 포함하므로 임계로 쓰지
    마십시오 — 접두어까지만 앵커로 씁니다.
  - `outcome=cancel` 인데 사용자가 취소한 기억이 없다면: Android 는 웹 세션 중 앱을
    **전면으로 되돌리기만 해도** 플러그인이 대기 중인 세션을 `CANCELED` 로 접습니다
    (앱 전환 · 홈 → 아이콘 재진입). 킷은 이를 silent 취소로 처리하므로 배너는 뜨지
    않습니다 — 세션 중에는 앱을 전환하지 않습니다.
  - Android 에서 웹 로그인 뒤 브라우저가 **검은 화면으로 남으면**: 먼저 병합본
    manifest 에 킷 relay `WebAuthCallbackActivity` 가 있고 라이브러리 콜백 Activity
    가 없는지 확인합니다(9단계 (5)). 다음으로 logcat 의 `I ActivityTaskManager: START`
    줄에서 relay 직후 MainActivity 재기동(`flg=0x34000000`)이 찍히는지 봅니다. 판정은
    세 갈래입니다.
    1. **재기동 줄이 없음:** 콜백이 relay 가 아닌 곳에 도착한 것입니다(G-16.5-2 ·
       상류 #158).
    2. **재기동 줄이 `flg=0x30000000`(CLEAR_TOP 없음):** relay 는 동작했지만 넘길 대기
       호출이 없었던 것입니다 — 로그인 도중 앱 프로세스가 죽었거나, 콜백이 두 번
       도착했거나, 로그인과 무관한 외부 기동입니다. 이때 tab 이 남는 것은 의도된
       동작입니다(9단계 (5) 「대가」).
    3. **START 줄은 있는데 바로 뒤에 `W ActivityTaskManager: ` 경고가 있음:** OS 가
       전면 복귀를 막은 것입니다(Android 14+ 백그라운드 Activity 기동 제한 · 15+
       ASM). START 줄은 이 판정보다 **먼저** 찍히므로, START 줄만 보고 relay 가
       정상이라고 결론내면 안 됩니다. 경고 문구는 OS 버전마다 다릅니다
       (`Background activity launch blocked` · `Abort background activity starts` ·
       `[ASM]`). 그러니 태그 앵커로 먼저 좁힌 뒤 문구를 확인합니다. relay 가
       코드로 막을 수 없는 잔존 위험입니다(relay KDoc). 발생하면 OS 버전 ·
       브라우저 · 단말을 기록해 G-16.5-2 재평가 자료로 남깁니다.
  - 근거: `.planning/phases/16.5-naver-web-oauth-kit-owned-flow/` 의
    `16.5-PROBE-RESULT.md` · `16.5-UAT-RESULT.md` (결함 귀속은
    `.planning/phases/16.4-naver-web-fallback-and-auth-feedback/16.4-AB-RESULT.md`).

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
>   Phase 14 (LINE) active 전환으로 마지막 placeholder 가 해제되어 현재
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
   (소문자 영숫자 — 예: `myappnaverprod`). `config/prod.json` 의 `naverUrlScheme` +
   `ios/Flutter/prod.xcconfig` 의 `NAVER_URL_SCHEME` 양쪽 prod 값 일치. 이 값이
   Phase 16.5 부터 웹 경로 콜백 scheme 도 겸하므로 prod 에서도 Naver 9단계 (2)
   브라우저 probe 로 authorize 통과를 한 번 확인합니다.
   Phase 16.2 부터는 같은 `ios/Flutter/prod.xcconfig` 의 `NAVER_CLIENT_ID` ·
   `NAVER_CLIENT_SECRET` 도 prod 앱의 값으로 함께 맞춰야 합니다 (iOS 는 이
   xcconfig 가 실제 출처이므로 `config/prod.json` 만 고치면 iOS 빌드는 여전히
   옛 값으로 로그인합니다).
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
   Secret 등록 (dev / stg / prod 각 Firebase 프로젝트 별 격리). Phase 16.5 부터
   `firebase functions:secrets:set NAVER_CLIENT_ID` 도 prod Client ID 로 함께
   등록합니다(`naverWebCustomToken` 이 사용 — Naver 8단계). Cloud Function 의
   `defineSecret(...)` 이 환경별로 자동 분리됩니다.
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

OAuth Custom Token provider (Kakao + Naver + Phase 14 LINE)
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
     --only functions:naverCustomToken,functions:naverWebCustomToken,functions:kakaoCustomToken \
     --project <dev-project-id>
   ```

   Phase 14 LINE 이후 추가된 함수 (`lineCustomToken` 등) 도 동시 배포.

### 적용 범위 (D-08 — helper 1곳 fix → 모든 caller 자동 상속)

- Phase 12 — `kakaoCustomToken`
- Phase 13 — `naverCustomToken`
- Phase 16.5 — `naverWebCustomToken` (`naverCustomToken` 과 같은 Naver 검증 helper 공유)
- Phase 14 — `lineCustomToken` (동일 helper 재사용 → 자동 상속)

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
정착 → UI 의 EnvironmentInfoScreen 「가입 수단」 · 「연결된 계정」 카드가
첫 frame 에 「-」 · 보유 provider 전부(D-11 fallback)로 표시 (cold start 시
회복).

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
(Phase 14 LINE 자동 상속).

**후속 fix 추적:** `.planning/todos/completed/2026-05-08-r10-followup-permission-denied-race.md`
(pending → completed). spec: `docs/superpowers/specs/2026-05-08-r10-followup-2-design.md`.

---

## Custom Token Provider 추가 가이드 (stub)

Phase 12 (Kakao OIDC) + Phase 13 (Naver REST) 의 통합 패턴을 그대로 미러링하여
새 Custom Token provider 를 추가할 수 있습니다 (Phase 14 LINE 이 이 절차로 추가됐다).
제거는 역순이다 — 바로 아래 「Custom Token Provider 제거 가이드 (Phase 16.6)」 절을 따른다.
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
   (Material+InkWell+SVG 직접 그리기) — Naver / LINE 모두 동일
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

## Custom Token Provider 제거 가이드 (Phase 16.6)

위 추가 가이드의 역순이다. 킷에서 provider 하나를 완전히 빼야 할 때 따른다.
Phase 16.6 이 Custom Token provider 1종을 이 순서로 제거하며 실측한 절차와
함정을 provider 이름 없이 옮겼다. `<provider>` · `<slug>` · `<PROVIDER>_CLIENT_ID`
는 제거 대상에 맞게 바꿔 읽는다. 4 단계 절차:

1. **먼저 — 비활성으로 충분한가.** 코드를 지우지 않고 provider 를 끄는 레버가
   두 개 있고, 둘 다 코드 변경 0 이다.

   | 레버 | 시점 | 방법 |
   |------|------|------|
   | 정적 CSV | 빌드 | `config/{flavor}.json` 의 `enabledAuthProviders` 에서 `<slug>` 토큰을 뺀다 |
   | Remote Config | 운영 | `auth_provider_<slug>_enabled = false` 게시 — [RC Kill Switch 운영 절차](#rc-kill-switch-운영-절차-emergency-disable) |

   두 레버의 관계는 Kill Switch 절의 제약 그대로다 — 정적 CSV 에서 빠진
   provider 는 RC 로 켤 수 없다 (정적 false 절대 우위). 그래서 「이 앱은 이
   provider 를 쓰지 않는다」 는 CSV 토큰 제거만으로 확정되고, 운영 중 임시
   차단은 RC 로 충분하다. 코드까지 지우는 경우는 다음 중 하나다: 검증 · 유지가
   불가능하다 (개발자 · 테스트 계정을 만들 수 없어 로그인 경로를 검증하지 못함),
   의존성 부담이 크다 (전용 플러그인 · native SDK · secret · 배포 함수의 유지비),
   킷 가치가 비대칭이다 (대상 사용자층 대비 설정 비용).

2. **제거 체크리스트 — 의존 역순, 매 커밋 green.** 추가 9 단계의 역순이다.
   항목 하나가 커밋 하나이고, 게이트를 통과해야 다음 항목으로 간다.
   - ① **등록 해제 (UI 소멸)** — `lib/core/auth/auth_strategies_registry.dart`
     의 `_allStrategies` 1줄 + `social_provider_resolver.dart` 1줄 삭제, strategy
     · notifier 파일 삭제 (고아 `.g.dart` 는 `rm`). 이 1줄로 `/login` chooser ·
     LoginPromptSheet · 설정 화면 「Link an account」 에서 버튼이 모두 사라진다.
     버튼 수를 단언하는 테스트 (`findsNWidgets`) 와 골든 harness 의 override
     목록을 함께 고치고 골든을 재생성한다 — before/after 를 사용자에게 보여
     승인받은 뒤 커밋하고 촬영 locale 을 기록한다 (함정 (d)).
   - ② **enum · 상수 · switch 일괄 (한 커밋)** — `AccountProvider` enum 값 ·
     `kProviderId<Provider>` · `kAllProviderIds` · exhaustive switch 사이트 전부 ·
     `AuthRepository` 생성자 인자와 signIn / signOut / link 분기 · `AppConfig`
     getter. enum 값 하나가 여러 파일의 switch 를 끌고 다니므로 (이번 실측 8 파일
     21 사이트) 컴파일 결합 단위로 한 커밋에 묶고, 테스트의 생성자 mock ·
     provider 행도 같은 커밋에 넣는다. 그 provider 가 우연히 유일하게 증명하던
     성질 (매트릭스 행 · 두 번째 slug 증명) 은 지우지 말고 남은 provider 로
     이관한다. 이 커밋 **전에** 로컬 `config/*.json` 의 CSV 토큰을 먼저 뺀다
     (함정 (b)).
   - ③ **brand 버튼 · 자산** — sealed `BrandSpec` 서브클래스 ·
     `BrandedSocialButton.<provider>` factory · `build()` switch case · render
     메서드 4 블록 + `assets/brand/<slug>/` + `pubspec.yaml` assets 행 + brand
     테스트의 provider 목록 (`brand_assets_lint_test` · `brand_label_whitelist_test`).
   - ④ **ARB** — 키 × 3 locale 삭제, 수가 박힌 description 정정,
     `fvm flutter gen-l10n` 산출 4 파일을 같은 커밋에 넣는다 (description 만
     바꿔도 generated dart 의 `///` 가 바뀐다). 한 번 더 돌려 diff 0 을 확인한다.
   - ⑤ **남은 주석 · docstring** — 이름 0. 「N provider」 처럼 수가 박힌 문장은
     수도 함께 고치고, 교훈은 이름만 빼고 남긴다.
   - ⑥ **플러그인 + native 등록 (같은 커밋)** — `fvm flutter pub remove <plugin>`
     + 그 플러그인이 요구하던 Android manifest placeholder · iOS `Info.plist` URL
     type · xcconfig 변수 · `config/*.example.json` 키 (함정 (e)). gitignored
     로컬 파일 (`ios/Flutter/<flavor>.xcconfig` · `config/<flavor>.json`) 은 도구가
     알려주지 않으므로 값 출력 없이 줄 단위로 지우고 계수로 확인한다. iOS 는
     3 flavor debug 빌드 후 `Package.resolved` 를 판독한다 (함정 (c)).
   - ⑦ **Cloud Functions** — closed union (`ProviderId` · `OidcProviderId`) 과
     짝 맵 (`OIDC_VERIFIERS` · priority 배열) · `defineSecret` 선언 ·
     `linkCustomTokenProvider` 의 `secrets:` 와 narrowing · `index.ts` export ·
     전용 endpoint 파일 · Jest (유일 증명 이관 포함). OIDC secret 선언은 provider
     파일이 아니라 공유 `functions/src/shared/oidc_providers.ts` 에 있고 link
     callable 이 전부 bind 하므로, 전용 파일만 지우면 binding 이 남는다.
     `functions/lib` 는 지우고 다시 빌드한다 (tsc 는 고아 `.js` 를 지우지 않는다).
   - ⑧ **문서 · 스킬 · 계획 문서** — 이 매뉴얼의 provider 절 · 목차 · 표, 스킬
     `references/`, `.planning` 활성 문서.

   각 항목의 게이트 (C-04):

   ```bash
   fvm dart run build_runner build --delete-conflicting-outputs
   fvm flutter analyze && fvm dart analyze     # riverpod_lint 진단은 dart analyze 만
   fvm flutter test --no-pub <범위>             # ② 이후는 full suite
   fvm dart format --output=none --set-exit-if-changed lib test
   cd functions && pnpm run lint && pnpm build && pnpm test   # ⑦
   ```

   테스트 수는 산식 「착수 − 삭제 + 이관 = 종료」 로 기록한다.
   `AccountProvider.values` · `kAllProviderIds` 를 순회해 생성되는 테스트는 코드
   편집 없이 줄어들므로 그 몫을 따로 센다.

3. **dev 배포 리소스 정리 순서.** 체크리스트 ⑦ 을 커밋한 뒤 배포본을 소스에
   맞춘다. 단계마다 삭제 전 read-only 스냅샷을 남기고 개별 승인 후 실행한다.
   - ① **남는 함수만 명시 필터로 재배포** —
     `firebase deploy --project <project> --non-interactive --only functions:<fn1>,functions:<fn2>,…`.
     필터 없는 `--only functions` 는 로컬 소스에 없는 함수 (제거 대상) 때문에
     non-interactive 에서 배포 전체를 abort 한다. 이 재배포가 link callable
     revision 의 secret binding 을 해제한다 — `gcloud functions describe
     linkCustomTokenProvider --gen2 --region <region> --format='value(serviceConfig.secretEnvironmentVariables)'`
     에 대상 secret 이 없고 revision 번호가 올랐는지 확인한다.
   - ② **warm-up probe** — `curl -X POST <함수 URL> -H 'Content-Type: application/json' -d '{"data":{}}'`.
     401 = 함수 살아 있음 (App Check / auth 게이트 거부). 403 = Cloud Run IAM
     거부, 429 = 할당량 · 인스턴스 부족, 5xx = 기동 실패 의심 — 401 외에는 정지한다.
   - ③ **함수 삭제** — `firebase functions:delete <fn> --region <region> --project <project> --force`.
     대상은 인자 1개, `--region` 명시. 여기서 `--force` 는 non-interactive 의 확인
     prompt 를 넘기기 위한 것이다. 성공 로그는 `Successful delete operation`.
   - ④ **secret 파괴** — in-use 판정은 **read-only 로만** 한다. 남는 함수 전부에
     `gcloud functions describe <fn> --gen2 --region <region> --format='value(serviceConfig.secretEnvironmentVariables)'`
     를 돌려 `<PROVIDER>_CLIENT_ID` 가 0 인지 (대조군 secret 은 ≥1) 세고,
     `firebase functions:secrets:get <PROVIDER>_CLIENT_ID` 로 버전 상태를 기록한다.
     승인 뒤 `firebase functions:secrets:destroy <PROVIDER>_CLIENT_ID --project <project> --force`
     를 1회 실행한다 — `--force` 1회 외의 실행은 없다 (함정 (a)). functions-managed
     secret 은 마지막 활성 버전이 파괴되면 secret 자체가 삭제된다
     (`No active secret versions left. Destroying secret …`).
     `functions:secrets:prune` (다른 미참조 secret 까지 후보) · `functions:secrets:access`
     (값 출력) 는 쓰지 않는다.
   - ⑤ **probe 재실행** — 401 + `gcloud run services describe <svc> --region <region> --format='value(status.latestReadyRevisionName)'`
     가 ① 의 새 revision 과 같은지.
   - ⑥ **잔존 데이터 계수** — Firestore `identity_index` (`provider == <slug>`) ·
     `users.linkedProviders` (요소가 map `{providerId, providerUserId}` 라 문자열
     `ARRAY_CONTAINS` 는 항상 0 — map 필드를 집계한다) · `users.providerLinkedAt.<slug>`
     · `users.signUpProviderId == <slug>` (가입 수단 기록 — 제거 뒤 남은 값의
     표시는 `errorUnknownProvider` 로 떨어지므로 삭제 대상 여부는 별도 승인)
     · RC `auth_provider_<slug>_enabled`. 남은 provider 로 대조군 (≥1) 을 먼저 세고
     계수만 출력한다 (값 출력 0). 0 이 아니면 삭제는 별도 승인.
   - ⑦ **외부 콘솔 앱 등록 삭제** — provider 개발자 콘솔의 앱 (Client ID) 은 수동
     삭제하고 스크린샷을 남긴다. 되돌릴 수 없는 콘솔이 많으므로 ④ 뒤 (참조 0
     확인 뒤) 에 한다.

   파괴적 명령 (③ · ④) 은 에이전트 대신 사용자가 직접 실행하고
   (`; echo "EXIT=$?"` 로 종료 코드를 남긴다) 에이전트는 read-only 로 사후 확인한다.

4. **함정 — Phase 16.6 실측.**
   - **(a) secret binding 순서.** Cloud Run 은 secret 환경변수를 인스턴스 기동
     **전에** 해석한다. binding 이 남은 revision 에서 secret 을 파괴하면 떠 있는
     인스턴스는 멀쩡하지만 새 인스턴스 (cold start · scale-out) 가 조용히 기동에
     실패한다 — 그래서 순서가 재배포 → 삭제 → 파괴다. Firebase CLI 의 in-use 거부
     (`Refusing to destroy secret in use`) 는 소스가 아니라 **배포본** 기준이고
     binding 이 **남아 있을 때만** 작동한다. binding 이 0 이면 곧바로 confirm 으로
     가는데 `--non-interactive` 에서 confirm 기본값이 승인이다 — binding 0 상태의
     `--force` 를 뺀 `--non-interactive` 관측 실행 = 파괴다 (firebase-tools 15.29.0 소스). 판정은
     `gcloud functions describe` 로, 파괴는 `--force` 1회로 한다.
   - **(b) `enabledAuthProviders` debug assert.** `parseEnabledProviders` 는 CSV 의
     미지 슬러그를 debug assert (`StateError`) 로 거부한다. `app_config_test` 가
     gitignored 로컬 `config/*.json` 을 실제로 읽으므로, 로컬 CSV 정리가
     `kAllProviderIds` 축소 커밋의 게이트보다 먼저여야 한다.
   - **(c) SPM transitive pin.** 제거한 플러그인이 끌어오던 iOS native 패키지를
     다른 플러그인이 전이 의존으로 요구하면 `Package.resolved` 의 핀은 남고 diff 0
     이 정상이다 — 핀 소실을 기대하지 않는다. 핀을 지우려고 `Package.resolved` 를
     삭제하거나 「Update to Latest Package Versions」 · `flutter clean` 을 돌리면 킷의
     모든 핀이 풀린다. 판독은 `cmp -s` 두 파일 → `git diff --stat -- '**/Package.resolved'`
     → `jq -r '.pins[].identity'` 전후 비교 → `test/ios/spm_policy_test.dart` 순서로
     하고, 핀이 남은 이유를 「iOS 의존성 관리 (SPM)」 절 고정값 표 비고에 적는다.
   - **(d) 골든 재생성.** `fvm flutter test --no-pub --update-goldens <파일>` 은 그
     파일의 골든 전부를 다시 찍는다. 대상 외 fixture 가 제거 직전 tag 와 바이트
     동일한지 `cmp` 로 확인한다 — 다르면 폰트 · SDK 환경 drift 이므로 원인부터
     추적한다. 대상 수는 harness override 목록에 달려 있다 (설정 화면 연결 섹션
     골든 포함). 사용자 승인 전 커밋 금지.
   - **(e) manifest placeholder.** 플러그인 AAR 이 intent-filter 에 `${placeholder}`
     를 요구하므로 placeholder 를 플러그인보다 먼저 지우면 manifest merger 가 치환
     실패로 빌드를 깬다. 반대 순서는 무해하지만 같은 커밋이 원칙이다. 병합 결과는
     `build/app/intermediates/merged_manifests/<flavor>Debug/` 아래
     `AndroidManifest.xml` 을 grep 해 확인한다.

제거는 `git grep -i <provider>` (`.planning/` · sketch `sources/` sign-off 증거 제외)
0 건으로 종결한다 — 0 을 판정하기 전에 남은 provider 이름으로 대조군 (≥1) 을
먼저 센다.

---

## Cloud Functions 배포 / Remote Config Kill Switch (Phase 11-04)

> 본 단락은 Phase 11-04 SUMMARY 의 사용자 매뉴얼 카드를 통합한 것입니다.
> Phase 12+ 의 신규 Cloud Function (Naver/LINE) 도 동일
> 패턴 적용.

### Functions 추가 절차 (ping 패턴 복제)

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
   - **Custom Token 3 provider (Kakao/Naver/LINE):** `linkCustomTokenProvider` callable (server-side hybrid) — 외부 IdP 토큰을 server 에서 검증 후 Firebase Custom Token 으로 변환하여 link.
4. **사용자 cancel 시 state 손실 0 (D-03):** sheet 의 dismiss 또는 backdrop tap 시 기존 세션 / onboarding 상태는 모두 보존. `Navigator.pop(false)` 만 호출 → caller 의 catch path 가 fresh 진입점으로 fallback.

**PII invariant (T-16-NEW-07):** `lookupSignInMethods` 호출의 collisionEmail 본문은 client logger / Crashlytics payload 에 절대 전파되지 않는다 (memory `feedback_test_lint_quality` 의 `__` 금지 + Plan 16-04 R7 sentinel test).

#### 충돌 시 안내 시트의 동작 — 2단계 플로우 (Phase 16 gap closure, 2026-09-08 갱신)

**동작 요약:** 이미 가입된 이메일로 **다른 소셜 로그인**을 시도하면, 앱은 (1) 그 이메일이 **어떤 수단으로 가입돼 있었는지 정확한 이름**을 안내 시트에 표시하고, (2) 시트의 버튼은 **그 수단으로 로그인**시킨 뒤, (3) 다른 로그인 수단을 추가하고 싶으면 **설정 > 계정 연결**에서 하도록 안내한다. 즉 시트 버튼 한 번으로 두 계정이 자동 연결되지는 않는다 — **로그인(1단계) → 계정 연결(2단계)** 두 걸음이다.

**왜 자동 연결이 아닌가.** 충돌 시트가 떠 있는 시점의 사용자는 **아직 로그인되지 않은 상태**다. 계정 연결은 "이미 로그인한 계정에 다른 수단을 덧붙이는" 동작이라 로그인되지 않은 상태에서는 성립할 수 없다. 예전 구현은 이 시점에 곧바로 연결을 시도했기 때문에 실질적으로 항상 실패했다. 그래서 지금은 **먼저 로그인시키고**, 연결은 로그인 이후 화면(설정)에서 하도록 나눴다.

**사용자가 보게 되는 흐름:**

1. 이미 가입된 이메일로 다른 소셜 로그인 시도 → 안내 시트가 뜬다.
2. 시트 본문에 **기존 가입 수단의 정확한 이름**이 표시된다 (예: 카카오로 가입한 계정이면 "카카오"). 여기에는 Google / Apple / Facebook 같은 네이티브 수단뿐 아니라 **Kakao / Naver / LINE 같은 Custom Token 수단도 포함**된다 — 이전에는 Custom Token 으로 가입한 계정의 이름을 서버가 알아내지 못해 충돌 자체가 감지되지 않았다.
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

**동작:** Custom Token provider (Kakao / Naver / LINE) 로 가입할 때 클라이언트가 약관 동의 스냅샷 5 필드 (동의 버전 / 이용약관 동의 / 개인정보 처리방침 동의 / 마케팅 수신 동의 / 동의 시각) 를 callable payload 의 `termsAcceptanceSnapshot` 으로 함께 보내고, Cloud Function 이 `users/{uid}` 문서를 **생성하는 같은 시점에** `termsAccepted` 로 기록한다. native provider (Google / Apple / Facebook) 는 Cloud Function 이 사용자 문서를 만들지 않으므로 클라이언트 mirror 경로 (`TermsNotifier.mirrorToFirestore`) 가 그대로 유효하다.

이 구조를 쓰는 이유는 경합 때문이다. Custom Token 경로에서는 Cloud Function 이 먼저 `users/{uid}` 를 만들고, 그 뒤에 실행되는 클라이언트 mirror 가 "이미 문서가 있다 = 기존 사용자" 로 판단해 skip 한다. 따라서 **문서 생성 시점에 서버가 직접 기록하는 것** 이 유일하게 경합이 없는 지점이다.

**백필 정책 (adopter 결정 사항):** 이 수정 **이전에** 가입한 사용자도 아래 「잔여 위험」 의 재동의 게이트를 거친다 — 기기 로컬 값은 정식 사용자의 게이트를 통과시키지 못하므로, 돌아온 사용자는 재동의 시각으로 기록이 채워지고 돌아오지 않은 사용자만 기록이 없다. 본 starter-kit 은 **자동 백필을 제공하지 않는다** — 돌아오지 않은 사용자의 처리와 재동의 시각의 인정 여부는 서비스의 법무·운영 정책에 달렸다. 백필이 필요하면 `users` 컬렉션에서 `termsAccepted` 부재 문서를 골라 처리하는 **1회성 관리자 작업** 으로 수행하고, 아래 「사용자 커스터마이징 포인트」 5번의 **법무 자문 의무** 를 함께 적용한다 (소급 기록한 값은 "실제 동의 시각" 이 아니므로, 그 법적 유효성 판단이 선행되어야 한다).

**기본 동작 — 서버 mirror 는 신규 등록 시점 1회만 (WR-01 게이트):** Custom Token 경로 3곳 — `functions/src/auth/kakao_custom_token.ts` · `functions/src/auth/line_custom_token.ts` · Naver 공용 helper `functions/src/auth/naver_profile_to_custom_token.ts`(`naverCustomToken` · `naverWebCustomToken` 공유) — 의 mirror 단계는 모두 `if (termsSnapshot && isNewUser)` 조건 아래에 있다. `isNewUser` 는 `identity_index` 에 `(provider, providerUserId)` 매핑이 처음 등록되는 transaction 에서만 `true` 이고, 그때의 uid 는 익명 caller 의 uid(제자리 승격) 또는 서버가 미리 만든 새 uid 다 — 이미 로그인된 정식 사용자는 신규 등록 대상이 아니다. 따라서 **이미 등록된 신원으로 재로그인** 하면 payload 에 스냅샷이 실려 있어도 서버는 `termsAccepted` 를 건드리지 않는다. 이 조건은 한 기기를 여러 계정이 쓰는 경우를 위한 것이다. 기기 로컬 동의가 남은 기기에서 기존 계정으로 재로그인할 때 조건이 없다면 서버의 권위 있는 `termsAccepted` 가 기기 값으로 덮어써진다 — `acceptedAt` 뿐 아니라 `marketing` · `version` 까지. 클라이언트 `TermsNotifier.mirrorToFirestore` 의 pre-read + skip(Plan 10-12 multi-user invariant)과 대칭인 서버측 가드다. Jest `C3 (WR-01)` 케이스 3건(`functions/test/auth/` 의 kakao · line · naver 테스트)이 「기존 사용자 재로그인(`isNewUser=false`) + 스냅샷 있음 → `users/{uid}` 쓰기 0」 을 고정한다. 재동의 시각은 이 경로가 아니라 클라이언트가 기록한다 — 약관 버전이 올라간 뒤 사용자가 다시 동의하면 `OnboardingScreen._handleCta` 가 `mirrorToFirestore(uid: …, force: true)` 로 pre-read 를 건너뛰고 새 `acceptedAt` 을 쓴다. 자동 경로(`authUserObserver` 의 익명 → 정식 전이 mirror)는 `force` 기본값 false 라 문서가 이미 있으면 건너뛴다.

**잔여 위험 — 첫 등록 요청에 스냅샷이 없거나 mirror 가 실패하면 서버 기록은 재동의 전까지 비어 있다:** 신규 등록 callable 에 `termsAcceptanceSnapshot` 이 실리지 않았거나(그 시점 기기 로컬 동의 부재 · payload 소실), 실렸어도 서버의 5 필드 런타임 검증(`parseTermsAcceptanceJson`)에 실패해 null 로 무시되면, 서버는 신원만 등록하고 mirror 를 건너뛴다(로그인은 계속된다). 첫 등록에서 mirror 의 `set(merge:true)` 자체가 실패한 경우도 결과가 같다. 그 요청은 실패하지만 신원 등록은 앞선 `identity_index` transaction 으로 이미 확정돼 있어(`identity_index` 매핑 + `users/{uid}` 의 `linkedProviders` · `providerLinkedAt`), 재시도는 기존 신원 재로그인(`isNewUser=false`)으로 처리되어 mirror 가 돌지 않는다. 어느 경우든 이후 서버 재로그인은 기록을 채우지 않고, 클라이언트 자동 mirror 도 문서가 이미 있어 skip 한다. 기록을 채우는 것은 클라이언트 재동의 게이트다. 클라이언트가 Firestore 를 다시 읽을 때(`TermsNotifier.reloadForUser` — 앱 콜드 스타트 또는 uid 가 바뀌는 로그인) `termsAccepted` 부재를 미동의로 판정하고, `resolveAuthRedirect` 분기 (5) 가 사용자를 `/onboarding` 으로 보낸다. 사용자가 CTA 를 누르면 위 `force: true` 기록이 문서를 채운다. 대가는 세 가지다 — 사용자가 동의 화면을 한 번 더 보고, 기록되는 `acceptedAt` 은 최초 동의가 아니라 재동의 시각이며, 사용자가 재동의하지 않고 떠나거나 그 `force: true` 쓰기마저 실패하면(SnackBar 안내 후 홈 진행) 다음 재읽기 전까지 문서가 비어 있다. 비어 있는 문서를 찾고 채울지 판단하는 방법은 위 「백필 정책」 과 같다(자동 백필 없음 · 1회성 관리자 작업 · 법무 자문 의무).

**커스터마이징 — 매 로그인마다 기기의 최신 동의를 서버에 반영하려면:** 위 3 파일의 조건에서 `&& isNewUser` 를 지우면 모든 Custom Token 로그인이 스냅샷을 `set(merge:true)` 한다. 대가는 다중 사용자 기기의 덮어쓰기다 — 다른 사용자의 기기 로컬 동의가 기존 계정의 `acceptedAt` · `marketing` · `version` 을 바꾸고, 최초 동의 시각 audit 이 사라진다. Jest `C3 (WR-01)` 3건이 red 가 되므로 기대값을 함께 바꿔야 하고, 클라이언트 pre-read + skip 과의 대칭도 깨진다. 본 starter-kit 은 기본값을 게이트 쪽에 둔다. 반대로 최초 동의 시각을 불변 audit 으로 남겨야 해서 위 「잔여 위험」(첫 등록 mirror 실패 → 재동의 시각으로 기록)을 받아들일 수 없는 서비스는, 검증된 스냅샷을 `resolveIdentity` 의 인자로 넘겨 `identity_index` 신규 등록 transaction 의 `users/{uid}` merge write(`linkedProviders` · `providerLinkedAt` 를 쓰는 곳)에 `termsAccepted` 를 함께 쓰는 방법이 있다 — 신원 등록과 동의 기록이 원자적으로 함께 성공·실패하며, kakao · line 은 `parseTermsAcceptanceJson` 을 `resolveIdentity` 호출 앞으로 옮기고(Naver helper 는 이미 입력으로 받는다) 3 파일의 사후 mirror 블록을 지우면 `{provider}_terms_acceptance_mirror_failed` 이벤트가 사라져 「확인 방법」 (c) 는 신원 등록 실패로 흡수된다(본 starter-kit 미구현 · 기본값은 위 게이트 그대로).

**확인 방법:** Firestore `users/{uid}` 문서에 `termsAccepted` 5 필드가 존재하는지 확인한다. 없다면 (a) 이 수정 이전에 가입한 사용자이거나, (b) **첫 등록 시점에** 기기 로컬 동의 값이 없어 클라이언트가 스냅샷을 부착하지 않았거나 서버 5 필드 검증에 걸려 무시된 경우이거나, (c) 첫 등록의 mirror 가 실패한 뒤 재시도로 로그인한 경우이고, 어느 쪽이든 아직 재동의 화면을 통과하지 않은 사용자다. `{provider}_terms_acceptance_mirrored` 이벤트는 신규 등록 요청에서 mirror 가 실제로 수행될 때만 남으므로 (a) · (b) · (c) 어디에도 없다 — 이벤트 유무로는 나눌 수 없다. (c) 는 같은 uid 의 `{provider}_terms_acceptance_mirror_failed` 이벤트로 식별하고, (a) 와 (b) 는 `users/{uid}.providerLinkedAt.{provider}`(신원 등록 시각 — `identity_index` 가 신규 등록 write 에 함께 기록)를 이 기능의 배포 시각과 비교해 나눈다.

**mirror 실패는 로그인을 실패시킨다.** mirror 가 실제로 수행되는 **신규 등록 요청** 에서 공용 helper `mirrorTermsAccepted`(`functions/src/auth/mirror_terms.ts`)의 `set(merge:true)` 가 던지면 `{provider}_terms_acceptance_mirror_failed` 를 남긴 뒤 `HttpsError('internal')` 로 callable 을 실패시킨다 — 4개 endpoint(Kakao · LINE · `naverCustomToken` · `naverWebCustomToken`) 공통. 의도는 동의 기록 없이 로그인이 성공하는 요청을 만들지 않는 것(fail-closed)이다. 다만 신원 등록은 그 앞의 `identity_index` transaction 에서 이미 확정되고 이를 되돌리는 코드가 없으므로, 실패하는 것은 첫 등록 요청 하나뿐이다 — **재시도는 성공하고 `termsAccepted` 는 비어 있다**(위 (c) · 재동의 전까지). 재로그인(`isNewUser=false`)에서는 mirror 가 실행되지 않으므로 이 실패 경로도 없다.

### 가입 수단 기록 (Phase 16.7)

**동작:** 계정을 처음 만든 수단을 Firestore `users/{uid}.signUpProviderId` 필드 1개에 한 번 기록하고, 홈 계정정보 카드와 설정 「내 계정」 이 이 값으로 「가입 수단」 과 「연결된 계정」 을 나눠 보여 준다. 연결된 계정 = 보유 provider(`User.providerIds`) 에서 가입 수단을 뺀 나머지이고, 0개면 「없음」 이다. 값 형식은 `User.providerIds` 와 같다 — `'google.com'` · `'apple.com'` · `'facebook.com'` · `'password'` · `'kakao'` · `'naver'` · `'line'`. 그래서 표시 쪽은 변환 없이 차집합을 만들고 기존 라벨 매핑(`formatProviderLabels`)을 그대로 쓴다. 클라이언트는 `linkedProvidersStream` 이 같은 `users/{uid}` snapshot 에서 `linkedProviders` 와 함께 읽고 `currentUserProvider` 가 `User.signUpProviderId` 에 싣는다. 두 표면은 `splitAccountProviders`(`lib/shared/auth/provider_label_formatter.dart`) 한 곳의 규칙으로 나눈다.

**기록 지점:** 경로별로 한 곳씩, 두 곳뿐이다.

- **native (Google · Apple · Facebook · 이메일)** — 클라이언트 `SignUpMethodRecorder`(`lib/features/auth/data/sign_up_method_recorder.dart`) 가 `users/{uid}` 에 `{signUpProviderId: <값>}` 을 set-merge 한다. `AuthRepository` 는 recorder 타입을 모르고 named optional 콜백 `recordSignUpMethod`(`RecordSignUpMethod` signature) 만 받는다 — factory provider 가 주입한다. call site 는 `AuthRepository` 의 가입 확정 분기 4곳(이메일 가입 · Google · Apple · Facebook)이며 모두 `unawaited(_recordSignUpMethod(fbUser.uid, <SDK>.PROVIDER_ID))` 다. 로그인 흐름은 서버 ack 를 기다리지 않는다 — 네트워크 실패는 Firestore SDK 오프라인 큐가 재전송하고, 즉시 던지는 예외(`permission-denied` 등)만 잡아 Crashlytics 에 reason `sign_up_method_record` 로 남긴 뒤 로그인은 계속된다. 앱 레벨 재시도는 없다.
- **Custom Token (Kakao · Naver · LINE)** — 서버 `resolveIdentity`(`functions/src/auth/identity_index.ts`) 의 신규 등록 transaction 이 `users/{uid}` set-merge 에 `linkedProviders` · `providerLinkedAt` 와 함께 `signUpProviderId: provider` 를 쓴다(원자적). Naver 는 앱 1-tap(`naverCustomToken`) 과 웹(`naverWebCustomToken`) 이 공용 helper 를 거쳐 같은 함수를 부르므로 둘 다 기록된다. 재로그인(`isNewUser: false`) 은 이 분기에 들어가지 않으므로 기록이 0 이다. 서버 쪽은 클라이언트 call site 가 필요 없다.

「가입」 의 정의 (D-14) — 이 표 밖의 경로는 기록하지 않으므로 한 번 쓴 값은 연결 · 재로그인으로 바뀌지 않는다:

| 기록함 | 기록 안 함 |
|--------|-----------|
| native 익명 → `link*` 성공 (익명 계정 제자리 승격) | 기존 계정 재로그인 |
| native 비익명 신규 sign-in (`additionalUserInfo.isNewUser == true`) | `credential-already-in-use` 뒤 익명 폐기 + 기존 계정 sign-in |
| 이메일 가입 (`createUserWithEmailAndPassword` · 익명 이메일 link) | 설정 화면 · 충돌 시트의 계정 연결 (native `link*` · `linkCustomTokenProvider`) |
| Custom Token `resolveIdentity` 신규 등록 분기 | Custom Token 재로그인 (`isNewUser: false`) |

**순서 — 약관 mirror 가 먼저:** `SignUpMethodRecorder` 는 경로 구분 없이 항상 `TermsNotifier.mirrorToFirestore` 를 먼저 await 한 뒤 `signUpProviderId` 를 쓴다 (D-19 · D-29). 약관 mirror 는 pre-read 에서 `users/{uid}` 문서가 이미 있으면 skip 하는데(다중 사용자 기기 보호), 가입 수단을 먼저 쓰면 Firestore 가 자기 pending write 를 로컬 읽기에 반영해 문서가 「있다」 고 보고 약관 mirror 가 건너뛰어진다 → 서버에 `termsAccepted` 가 없어 다음 재읽기에서 재동의 화면이 뜬다. 위 「약관 동의 서버 기록」 절의 Custom Token 경합과 같은 함정이다. 이 순서 때문에 익명을 거치지 않은 native 신규 sign-in 에서도 약관이 서버에 기록된다(행동 변화 — 의도). mirror 가 실패해도(reason `sign_up_method_terms_mirror`) 가입 수단 기록은 이어간다. **흔한 실수:** recorder 를 거치지 않고 다른 곳에서 `users/{uid}` 에 먼저 set-merge 하면 이 함정이 그대로 재현된다.

**기록 없는 계정 (fallback):** `signUpProviderId` 가 없으면 가입 수단은 「-」, 연결된 계정은 보유 provider 전부다 (D-11). provider 가 1개뿐이어도 추론하지 않는다 — 읽기 실패 때 추론값이 진짜처럼 보이기 때문이다. 같은 규칙이 Firestore 읽기 실패(`linkedProvidersStream` 의 빈 fallback) · 로그인 직후 첫 emit 전 과도 상태 · 이 기능 이전에 만든 계정에 똑같이 적용된다. 킷은 backfill 을 제공하지 않는다(추론 · lazy 기록 0). 기록값이 현재 `providerIds` 에 없으면(Admin 조작으로만 생긴다) 기록값을 그대로 가입 수단으로 보이고 연결된 계정은 보유 전부가 된다 (D-12). 등록되지 않은 값은 raw 문자열 대신 `errorUnknownProvider` 라벨로 표시된다.

**위조 한계:** 이 필드는 **표시 전용** 이다. `firestore.rules` 의 `users/{userId}` 규칙은 본인 문서 전체 write 를 허용하므로(WR-12 — 알려진 갭) 로그인한 사용자는 앱을 거치지 않고 자기 `signUpProviderId` 를 바꿀 수 있고, 서버 `resolveIdentity` 가 쓴 값도 이후 클라이언트가 덮어쓸 수 있다. 그래서 서버는 이 값을 읽지 않고, 인가 · 권한 판단에도 쓰지 않는다 — 지금 위조의 영향은 자기 화면 표시뿐이다. 필드 단위 write 금지는 client write 경로(약관 mirror · 이 recorder)를 서버 callable 로 옮기는 작업과 함께 **Phase 18** 에서 한다(WR-12). 그 전에 이 값으로 서버 쪽 결정(예: 해제 불가 수단 판정)을 하려면 서버가 따로 검증하는 경로가 먼저 필요하다.

**provider 를 추가 · 제거할 때:**

- **native provider 추가** — 그 provider 의 sign-in 메서드에 3줄 패턴을 넣는다: `userCredential` 선언 앞 `var didLinkAnonymous = false;` → 익명 `link*` 호출 **바로 다음 줄** `didLinkAnonymous = true;`(catch 안 `credential-already-in-use` fallback 에는 넣지 않는다) → `fbUser == null` 검사 뒤 `final isSignUp = didLinkAnonymous || (userCredential.additionalUserInfo?.isNewUser ?? false);` 이면 `unawaited(_recordSignUpMethod(fbUser.uid, <SDK>.PROVIDER_ID));`. 표시 쪽은 `AccountProvider.tryParse`(`lib/core/auth/provider_id.dart`) 에 Firebase URI or-pattern 1개 + `formatProviderLabels` switch 1행 + ARB `authAccountProvider{X}` 3 locale + `kSupportedAuthProviderIds`(`lib/shared/auth/provider_label_formatter.dart`) 에 URI 추가(컨트랙트 테스트 · 설정 가입 수단 1줄 가드 · 홈 E1 sweep 이 이 set 을 순회하므로 새 provider 가 자동 포함된다) + `kAllProviderIds`(`lib/core/auth/provider_id.dart`) 에 slug 등재(D-05 표시 순서의 원천 — 누락하면 enum 에 있어도 `orderForDisplay` 가 미지 값 자리로 조용히 정렬한다). **흔한 실수:** 기존 `isLinkedFromAnonymous`(인증 메일용)를 기록 조건으로 쓰면 fallback 뒤에도 true 라 기존 계정 로그인이 「가입」 으로 기록된다 — `test/features/auth/data/auth_repository_sign_up_method_test.dart` 의 `credential-already-in-use` 케이스가 red 로 잡는다(새 provider 도 이 파일에 1회 · 0회 케이스를 복제한다).
- **Custom Token provider 추가** — 가입 수단 기록 쪽 편집은 0 이다. 새 endpoint 가 `resolveIdentity(db, {provider: "<slug>", …})` 를 부르면 신규 등록에서 자동 기록된다(slug 는 `ProviderId` closed union 에 먼저 넣어야 컴파일된다). 그 함수는 `resolveIdentity` 를 바꿀 때마다 재배포 대상에 들어간다.
- **provider 제거** — 이미 그 값으로 기록된 문서는 남는다. 표시는 `errorUnknownProvider` 라벨로 떨어지고(raw slug 노출 0), 잔존 계수 · 정리는 「Custom Token Provider 제거 가이드」 3-⑥ 의 `users.signUpProviderId == <slug>` 항목을 따른다.
- 기록 자체를 끄려면 `authRepository` factory 의 `recordSignUpMethod:` 인자 1줄을 지운다 — no-op 기본값으로 돌아가고 모든 계정이 위 fallback 으로 보인다.

**확인 방법:** 두 끝을 모두 본다 — 한쪽만 보면 사이 wiring 누락을 놓친다. (1) Firebase Console > Firestore `users/{uid}` 문서에 `signUpProviderId` 가 가입한 수단 값으로 있는지, (2) 같은 계정으로 앱의 홈 계정정보 카드와 설정 「내 계정」 에 가입 수단 · 연결된 계정이 그 값대로 보이는지. 이어서 설정에서 다른 provider 를 연결하고 그 수단으로 재로그인해도 (1) 의 값이 바뀌지 않아야 한다. Admin 으로 원장을 바꾼 직후에는 기기 캐시가 옛 값을 보일 수 있으니 재로그인 뒤 대조한다. 예: 합성 사용자 `uid = test-uid-0001` 이 Kakao 로 가입했다면 문서는 `signUpProviderId: "kakao"` 이고 홈 카드는 가입 수단 = 카카오 · 연결된 계정 = 없음이다.

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

#### ⚠ 재발급 함정 — `adb shell pm clear` 는 디버그 시크릿을 새로 발급시킨다

`adb shell pm clear <applicationId>` 는 앱 데이터를 지우면서
`shared_prefs/com.google.firebase.appcheck.debug.store.*.xml` 도 함께 지운다. 그 결과 디버그 시크릿이
**새로 발급**되고, 새 시크릿은 허용 목록에 없으므로 App Check 를 요구하는 호출이 **전부** 실패한다.
시크릿은 앱을 재기동해도 불변이며 `pm clear`(및 재설치) 시에만 바뀐다 — 실측으로 확인된 동작이다.

위 4단계가 적은 「앱 재설치 시 새 token 발급 → 재등록 필요」의 **되풀이 변종**이며, 이 저장소에서만
같은 단말에 최소 2회 발생했다. 증상이 `unauthenticated` 이므로 **reauth 실패로 오진하기 쉽다** —
회원탈퇴가 실패할 때 reauth 코드를 뒤지기 전에 logcat 에서
`Error getting App Check token; using placeholder token instead` 가 있는지 먼저 볼 것.

#### Firebase Console 없이 디버그 토큰 등록하기 (API 절차)

Console UI 를 열지 않고 REST API 로도 등록할 수 있다 (CI·원격 단말·터미널 전용 환경에서 유용).

```bash
curl -X POST \
  "https://firebaseappcheck.googleapis.com/v1/projects/<project>/apps/<appId>/debugTokens" \
  -H "Authorization: Bearer $(gcloud auth print-access-token)" \
  -H "x-goog-user-project: <project>" \
  -H "Content-Type: application/json" \
  -d '{"displayName":"<단말 별칭> (<날짜> regen)","token":"<debug secret>"}'
```

- `<debug secret>` — 현재 값은 logcat 의 `D/DebugAppCheckProvider ... Enter this debug secret` 행에서 읽는다.
  **이 값은 App Check attestation 을 우회시키는 자격증명이므로 저장소·이슈·문서에 기록하지 않는다.**
- `<appId>` — Firebase 앱 ID. debug store **파일명의 base64 부분을 디코드**하면 얻을 수 있다
  (`shared_prefs/com.google.firebase.appcheck.debug.store.<base64>.xml`).
- `<project>` — Firebase 프로젝트 ID. `x-goog-user-project` 헤더를 빠뜨리면 권한 오류가 난다.

**부작용:** 등록된 디버그 토큰이 계속 누적된다. 대부분 과거 단말·에뮬레이터 것이라 시간이 지나면
목록이 지저분해진다. 정리(삭제)는 별건이며 같은 API 의 `debugTokens` 리소스로 처리한다.

본 절차는 Phase 11 의 App Check 도입 시점에 manual.md 의 다른 단락에 정의돼 있을 수 있으나, Plan 16-06 시점의 cross-reference 안전 차원에서 본 단락에도 명시.

### 사용자 커스터마이징 포인트

본 starter-kit 사용자가 자신의 프로젝트에서 변경할 수 있는 surface:

1. **ARB 라벨 변경 (provider 라벨, dialog 본문):**
   - `lib/l10n/app_{en,ko,ja}.arb` 의 `withdrawalDialogBodyLine1/2/3` — GDPR 경고 문구 변경 (단, 법적 의무 보존 검증 의무).
   - `withdrawalConfirmFieldHint` — 사용자 입력 verbatim phrase 변경 (ko="탈퇴" → 예: "확인", en="delete" → 예: "permanently delete"). 변경 시 widget test WC3/WC4 의 expected 값 동기화 의무.
   - `errorAccountExistsWithProvider` — provider-aware 메시지 본문.
2. **AccountLinkingSheet 의 mirror 패턴 (LoginPromptSheet 위 1-provider 강조 vs n-provider 전체):**
   - 본 starter-kit 은 D-02 의 single button 정책 (정확한 1 provider 만 표시). n-provider 전체 (예: AccountLinkingSheet 안에서 모든 provider (`AccountProvider.values`) 를 노출하여 사용자가 "어떤 provider 로 가입했는지 모를 때 모두 시도" UX) 를 채택하려면 `lib/features/auth/presentation/_widgets/account_linking_sheet.dart` 의 `_BrandedLinkButton` exhaustive switch 를 `AccountProvider.values` iterate 로 교체.
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
  시 사용자가 등록한 Kakao / Naver / LINE 의 매핑 문서가
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

hook 이 실행하는 가드는 4 건이다. 1~3 은 **실제 Firebase 키가 repo 에 커밋되는
것을 차단**하는 것이 목적이고 (placeholder 파일군이 tracked 이라 재생성본이
그대로 커밋 대상이 된다), 4 는 문서 참조 lint 다.

| 가드 | 대상 | 차단 조건 |
|------|------|-----------|
| 1 | `lib/core/firebase/firebase_options_{dev,stg,prod}.dart` | index 내용에 FlutterFire CLI 생성 마커가 있음 |
| 2 | `android/app/src/{stg,prod}/google-services.json` | Google API 키 접두사가 있거나 placeholder `project_number` 가 사라짐 |
| 3 | `ios/config/dev/GoogleService-Info.plist` · `ios/config/stg/GoogleService-Info.plist` · `ios/config/prod/GoogleService-Info.plist` | Google API 키 접두사가 있거나 placeholder `GCM_SENDER_ID` 가 사라짐 |
| 4 | 코드 주석의 `Phase NN` 참조 + `TODO` 주석 | 진실원 (`ROADMAP.md` active phase 또는 `.planning/todos/pending/<file>.md`) 미인용 |

가드 1~3 에 걸리면 해제 절차 (`git restore --staged` → `git update-index
--skip-worktree`) 가 차단 메시지에 함께 출력된다. placeholder 자체를 의도적으로
고치려면 placeholder 어휘를 유지한 채 실 키만 제거하고 커밋한다.

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
| `// Phase 09 — see ROADMAP.md` | PASS (0 채움 표기 — 번호 성분별 선행 0 을 떼고 비교하므로 Phase 9 와 같다) |
| `// TODO(phase-08): ...` | FAIL (raw — 진실원 미명시) |
| `// TODO: dedicated NotFoundScreen` | FAIL (raw — 진실원 미명시) |
| `// Phase 99 — see ROADMAP.md` | FAIL (Phase 99 가 ROADMAP 미존재) |

> ⚠ 이 hook 은 `scripts/check_phase_refs.sh` 만 실행하며 **dart format 은 검사하지 않는다** — 커밋 전 `fvm dart format --output=none --set-exit-if-changed lib test` 를 별도로 실행할 것 (미실행 시 drift 누적: quick `260909-mwh` 에서 91개 파일 일괄 정리).

---

## 정적 분석 — woody_lints · riverpod_lint

### 무엇이 바뀌었나

woody_lints 1.3.0 부터 riverpod_lint 가 최상위 `plugins:` 선언으로 **실제로
실행**된다. 이전 버전의 `analyzer: plugins: - riverpod_lint` 선언은
riverpod_lint 3.x 를 아무것도 로드하지 않았다 — 킷이 강제한다고 믿던 Riverpod
규칙이 한 번도 돌지 않았던 셈이다. 킷의 `analysis_options.yaml` 이
`package:woody_lints/analysis_options.yaml` 을 include 하므로 추가 설정은
필요 없다.

### 확인 방법

- IDE (Dart Analysis Server) 의 Problems 패널 또는 `fvm dart analyze`.
- Flutter 3.41.9 에서는 `fvm flutter analyze` 도 plugin 진단을 표시하지만,
  Flutter 3.47.5 에서는 `flutter analyze` 가 plugin 진단을 표시하지 않았다
  (2026-09-20 실측). **기준 명령은 `fvm dart analyze`** 로 잡는다.

### plugin 해석 · Analysis Server 재시작

- plugin 은 프로젝트 `pubspec.lock` 이 아니라 Analysis Server 의 plugin 캐시
  (`~/.dartServer/.plugin_manager`) 에서 woody_lints 의 제약
  (`riverpod_lint: ^3.1.3`) 대로 해석된다.
- plugin 설정이나 woody_lints 버전을 바꾼 뒤에는 IDE 에서 **Analysis Server 를
  재시작**해야 새 규칙이 반영된다 (VS Code: `Dart: Restart Analysis Server`).

### 억제 문법

- plugin 진단은 네임스페이스 형식만 동작한다:
  `// ignore: riverpod_lint/<rule>` · `// ignore_for_file: riverpod_lint/<rule>`.
  plain `// ignore: <rule>` 은 **무효**다.
- ignore 는 진단 **시작 줄 바로 윗줄**에 둔다. doc 주석이 있는 멤버는 진단이
  `///` 첫 줄에서 시작하므로 `///` 블록 **위**에 둔다.
- 억제할 때는 바로 위에 이유 주석을 남기고, 구조 개편이 필요하면 후속 todo
  파일명을 함께 적는다.

### 테스트 작성 규칙

- generator provider 를 override 하는 `ProviderScope` 는
  `await tester.pumpWidget(ProviderScope(...))` 처럼 **pumpWidget 의 직접
  인자**로 넘긴다. helper 가 `ProviderScope` 위젯을 반환하거나 다른 위젯으로
  감싸면 규칙이 root scope 로 보지 않아 `scoped_providers_should_specify_dependencies`
  가 난다 → helper 는 `WidgetTester` 를 받아 직접 pump 한다
  (예: `Future<void> _pumpApp(WidgetTester tester, {...})`).
- fake Notifier 에 public 카운터 · 기록 필드 · getter 를 두지 않는다
  (`avoid_public_notifier_properties`). 호출 기록은 생성자로 받은 **외부
  recorder** 객체에 남기고, 테스트는 recorder 를 단언한다.

### 현재 lib 억제 0건

quick `260920-b28` 이 남아 있던 lib 억제 3건을 **구조로** 해소했다. `lib` ·
`test` 어디에도 `riverpod_lint/` 지시문이 없다.

| 해소한 진단 | 옛 구조 | 새 구조 |
|-------------|---------|---------|
| `unsupported_provider_value` (`authChangeNotifier` provider) | provider 가 GoRouter `refreshListenable` 용 `ChangeNotifier` 를 값으로 반환 | `AuthRefresh` notifier 가 불변 state(인증 스냅샷 + 최초 emit 여부 + revision)만 노출하고, GoRouter 가 요구하는 `Listenable` 은 `appRouter` 가 만들어 소유 · dispose 한다 (`ref.listen` 으로 중계) |
| `avoid_public_notifier_properties` (`acceptanceSnapshotJson` getter) | notifier getter 가 Custom Token payload JSON 을 직접 계산 | `TermsState` 의 순수 파생(`buildAcceptanceSnapshotJson()`) |
| `avoid_public_notifier_properties` (`lastReloadedUid` getter) | notifier getter 가 stale 가드 기준값을 노출 | `TermsState.lastReloadedUid` (소비처는 `ref.read(termsProvider).lastReloadedUid`) |

**새 코드를 쓸 때의 규칙 2줄:**

1. **Notifier 는 불변 state 만 노출한다.** public 필드 · getter 를 두지 말고
   값을 `state` 에 담는다. 값이 여러 개면 record 나 freezed 값 객체로 묶고,
   파생값은 notifier 밖 순수 함수 · extension 으로 뺀다.
2. **provider 는 `Listenable` 같은 가변 객체를 값으로 반환하지 않는다.**
   필요하면 **소비하는 쪽**이 만들어 소유하고 `ref.listen` 으로 값을 받아
   올린다 — 그 객체는 소비자의 구현 세부이고, 정리(`ref.onDispose`)도
   소비자 책임이다. `appRouter` 의 `RouterRefreshListenable` 이 그 예다.

---

## Brand Asset Management (Phase 13.1 + 13.2)

<!-- Updated by Phase 13.2 retroactive: R13 — Facebook entry 갱신 (Meta 공식 자상 + 라이선스 verbatim + Phase 18 단어 폐기) -->

본 단락은 starter-kit 의 social provider brand asset 출처·라이선스·다운로드·
freshness 갱신 정책을 정리한다. 6 provider (Kakao / Naver / Google / Apple /
Facebook / LINE) 자산 모두 단일 표준 디렉토리 (`assets/brand/{provider}/`)
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
├── apple/{black_logo,white_logo}/btn_signin_icon.svg + README.md
│   # Phase 13.3 Wave 4 Step 3 (2026-05-16): Apple Sign-in JS API 의 inline SVG
│   # verbatim 추출 (R['small'].path + viewBox "6 0 12 44"), 2 SVG.
│   # 디렉토리 명명은 logo 색 기준 — `isDark ? black_logo : white_logo`
│   # (dark theme → 검정 logo on 흰 bg). LICENSE.txt 없음 — Apple HIG
│   # compliance 범위 내 사용이라 배포 라이선스 본문이 존재하지 않는다
├── facebook/facebook_login.png + LICENSE.txt + README.md
│   # Phase 13.2 — Meta 공식 자상 (Primary Logo, 2084×2084 PNG, D-95 lock)
│   # D-94 theme 부재 (단일 #1877F2 변형) / D-96 Google 패턴 locale 독립 ('f' 마크 단독)
└── line/{en,ko,...}/btn_signin_icon.svg + LICENSE.txt + README.md
    # Phase 14 D-LINE-08 (2026-05-19): sentinel → active 전환 (Symbol SVG)
```

### Provider 별 출처 + 라이선스

| Provider | 공식 BI URL | 자산 형식 | 라이선스 | 사용자 사전 검수 |
|----------|------------|-----------|---------|-----------------|
| Kakao    | https://developers.kakao.com/docs/ko/kakaologin/design-guide | PNG + PSD | Kakao Resources Terms | N/A (가이드 준수만) |
| Naver    | https://developers.naver.com/docs/login/bi/bi.md | PNG + Figma + AI | NAVER Brand License | **사용자 책임** (가이드 준수 — starter-kit 은 검수 자동화 미제공) |
| Google   | https://developers.google.com/identity/branding-guidelines | SVG | Google Terms of Service | N/A |
| Apple    | https://developer.apple.com/design/human-interface-guidelines/sign-in-with-apple | SVG (Sign-in JS API inline path verbatim) | Apple HIG compliance 범위 내 사용 (`assets/brand/apple/README.md` 「라이선스」 절 — 동봉 LICENSE.txt 없음) | N/A |
| Facebook | https://www.meta.com/brand/resources/facebook/logo/ + https://developers.facebook.com/docs/facebook-login/userexperience/ | PNG (Primary Logo, 2084×2084) | Meta Brand License (`Meta's trademarks are owned by Meta and may only be used as provided in these guidelines or with Meta's permission.` verbatim) | **사용자 책임** (Wave 0 응답 verbatim — Meta Brand Resource Center 다운, Phase 13.2 완료) |
| LINE     | https://developers.line.biz/en/docs/line-login/login-button/ | PNG + PSD (19 언어) | LINE Branding License | **사용자 책임** (Phase 14 진입 시) |

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

Phase 13.1 시점에 자상 미commit provider 용 `kPlaceholderProviders` sentinel
패턴 도입 → Phase 14 D-LINE-08 (2026-05-19) 으로 마지막 placeholder 였던 LINE
자상 commit 완료 → sentinel 의무 해소
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
- **Apple:** `_renderAppleButton` 자체 render (Phase 13.3 Wave 4 Step 2/3) —
  공식 Logo-only SVG + 외부 텍스트 라벨 layer. Apple HIG 의 3 변형 (Sign in /
  Sign up / Continue) 중 starter-kit 은 **Sign in 만** 사용. Sign up /
  Continue 추가는 별도 phase. 기하는 `AppleSpec` 이 `BrandSpec` 기본값을
  그대로 쓴다 — **height 48 / borderRadius 12** 로 Naver / Kakao / Facebook
  과 동일하며 provider 간 높이 차이는 없다 (`AppleSpec` 은 `assetType` 만
  override). SVG 자상 변형 금지 — path 좌표 + viewBox `"6 0 12 44"` verbatim
  유지 의무 (`assets/brand/apple/README.md` 의 HIG mandate 표 참조).
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
     // Phase 16 부활 시 add-only — kakao, naver, line 도
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

⚠ 위 `_setFacebookPhotoUrl` 서술은 **Classic 경로(Android · iOS ATT 허용)
전제**다. ATT 를 요청하지 않는 킷 기본 설정의 iOS 는 Limited Login 이라 이
호출을 건너뛴다 — `## ATT (App Tracking Transparency) 와 iOS Facebook 로그인 — 앱 책임 영역`
절 참조.

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
   6/7 provider × 계약 2종(overflow 0 · CTA 첫 화면 노출)이다(default
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
| D 시트 스크롤 · 6/7 provider overflow 0 · CTA 첫 화면 노출 · 소셜 실패 피드백 | `test/features/auth/widgets/login_prompt_sheet_overflow_test.dart` · `login_prompt_sheet_test.dart` · `login_prompt_sheet_error_test.dart` |
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

## Design System — 디자인 토큰 커스터마이징 (Phase 3)

> **이 절의 계약은 2026-09-12 Phase 3 code review fix 12건**
> (`.planning/phases/03-design-system/03-REVIEW-FIX.md`) **으로 확정된 것입니다.**
> 그 이전 코드를 기준으로 쓰인 커스터마이징 방법은 더 이상 유효하지 않습니다 —
> 특히 타이포그래피는 등록되는 extension 자체가 바뀌었습니다 (아래 2번).

Starter kit 의 디자인 시스템은 **`ThemeExtension` 3종** 으로 구성됩니다.

| Extension | 파일 | 담는 것 |
|---|---|---|
| `AppColors` | `lib/core/theme/app_colors.dart` | `ColorScheme` 에 없는 앱 고유 시맨틱 컬러 6종 |
| `AppTypography` | `lib/core/theme/app_typography.dart` | M3 `TextTheme` 15 스타일의 **override 레이어** |
| `AppSpacing` | `lib/core/theme/app_spacing.dart` | 4 의 배수 간격 스케일 7단계 |

세 extension 을 `ThemeData` 로 조립하는 곳은 `AppTheme.light()` / `AppTheme.dark()`
(`lib/core/theme/app_theme.dart`) 이고, 호출부는 `lib/app.dart:53-54` 의
`theme: AppTheme.light(),` / `darkTheme: AppTheme.dark(),` 단 두 줄입니다.
`ColorScheme` 은 `seedColor` 하나에서 `ColorScheme.fromSeed` 로 파생되고,
extension 3종은 `base.copyWith(extensions: [...])` 로 등록됩니다 —
`AppColors.fromBrightness(...)` · `AppTypography.empty` · `const AppSpacing()`
순서입니다.

이 밖에 반응형은 `AppBreakpoint` + `ResponsiveX`
(`lib/core/theme/app_breakpoint.dart`) 가, 키보드 focus outline 은
`BrandFocusWrapper` (`lib/core/theme/brand_focus_wrapper.dart`) 가 담당합니다.

앱 코드가 토큰에 접근하는 경로는 `ThemeX` extension
(`lib/core/theme/theme_extensions.dart`) 의 **다섯 getter** 입니다.

| getter | 반환 | extension 미등록 테마에서의 동작 |
|---|---|---|
| `context.appColors` | `AppColors` | `AppColors.fromBrightness(theme.brightness)` 로 폴백 |
| `context.appTypography` | `AppTypography` (합성 결과) | 테마 `textTheme` 기하를 그대로 반영 |
| `context.appSpacing` | `AppSpacing` | `const AppSpacing()` 으로 폴백 |
| `context.colorScheme` | `ColorScheme` | `Theme.of` 직통 |
| `context.textTheme` | `TextTheme` | `Theme.of` 직통 — **extension override 미반영** |

세 토큰 getter 는 extension 이 등록되지 않은 테마에서도 크래시하지 않고 기본
토큰으로 폴백하므로, 사용자가 자체 `ThemeData` 를 쓰거나 위젯 테스트에서 맨몸
`MaterialApp()` 을 써도 안전합니다.

### 1. 시드 컬러 교체 — M3 팔레트 전체 전환

기본 시드는 `app_theme.dart` 에 상수로 선언돼 있습니다.

```dart
static const MaterialColor seedColor = Colors.deepPurple;
```

**소스를 고치지 않는 교체 경로는 `light()` / `dark()` 의 `seedColor` 인자입니다**
— 두 메서드는 `light({Color seedColor = AppTheme.seedColor})` /
`dark({Color seedColor = AppTheme.seedColor})` 로 동일한 시그니처를 갖습니다.
`lib/app.dart` 의 두 줄만 바꾸면 됩니다.

```dart
// lib/app.dart — MaterialApp.router
theme: AppTheme.light(seedColor: Colors.teal),
darkTheme: AppTheme.dark(seedColor: Colors.teal),
```

- **라이트와 다크에 같은 시드를 넘기세요.** `app_theme.dart:53-54` docstring 이
  못박은 계약입니다 — 서로 다른 시드를 넘기면 두 모드의 팔레트가 어긋납니다.
- 시드 하나에서 `ColorScheme.fromSeed` 가 M3 팔레트 **전체**(primary /
  secondary / tertiary / surface / error 및 각 `on-` 쌍)를 파생하므로,
  개별 색을 일일이 지정할 필요가 없습니다. 브랜드 색을 하나 정해 넣는 것이
  가장 빠른 커스터마이징입니다.
- 상수 자체를 바꾸고 싶다면 `AppTheme.seedColor` 를 수정해도 되지만, starter kit
  업스트림 갱신을 병합할 때 충돌하므로 **인자 주입을 권장**합니다.

### 2. 타이포그래피 계약 — `context.appTypography` 가 유일한 경로

**이번 fix 에서 가장 크게 바뀐 부분입니다.** 순서대로 읽어 주세요.

1. **`AppTheme` 이 등록하는 extension 은 `AppTypography.empty` 입니다.** 전 15
   필드가 빈 `TextStyle()` 인 **순수 override 레이어**이며, 기하(fontSize /
   fontWeight / baseline / fontFamily)를 하나도 담고 있지 않습니다.
2. **완성된 스타일은 반드시 `context.appTypography` 로 얻습니다.**
   `ThemeX.appTypography` 는 호출 시점에
   `AppTypography.fromTextTheme(Theme.of(context).textTheme).merge(등록된 override)`
   를 계산합니다. 즉 로케일 기하가 적용된 테마 `textTheme` 을 밑바탕으로
   사용자 override 를 얹은 **합성 결과**입니다.
3. **⚠ `Theme.of(context).extension<AppTypography>()` 직접 읽기는 금지입니다.**
   등록된 값이 `AppTypography.empty` 이므로 **빈 스타일**이 돌아옵니다.
   크래시도 경고도 없이 글자가 기본값으로 렌더되는 조용한 어긋남이라
   발견이 늦습니다.
4. **override 를 등록하지 않은 기본 상태에서는 `context.appTypography.X` 와
   `context.textTheme.X` 가 같은 값입니다.** 이 설계의 목적은 ko/ja 로케일의
   dense 기하(`textBaseline: ideographic`)가 Flutter 의 `ThemeData.localize`
   를 거쳐 자동 반영되게 하는 것입니다. 기하를 extension 에 미리 구워 두면
   로케일 전환 시 desync 가 납니다. 이 계약은
   `T-03-WR-03: appTypography 가 로케일별 기하를 따른다` group 이 잠급니다.
5. **폰트 교체는 `ThemeData(fontFamily:)` 또는 `textTheme` 으로 합니다** —
   extension 을 건드릴 필요가 없습니다. 등록 레이어를 `empty` 로 둔 이유가
   정확히 이것입니다: `03-REVIEW-FIX.md` WR-03 의 실측에 따르면 등록 레이어에
   `fontFamily: 'Roboto'` 가 살아 있으면 `merge` 단계에서 사용자가 바꾼 폰트를
   **다시 Roboto 로 덮어씁니다**.

일부 스타일만 바꾸고 싶다면 `AppTypography.empty.copyWith(...)` 로 override 를
채워 등록합니다.

```dart
// 타이포그래피 부분 override — extensions 리스트에 3종을 모두 넣는다.
final lightTheme = AppTheme.light().copyWith(
  extensions: <ThemeExtension<dynamic>>[
    AppColors.fromBrightness(Brightness.light),
    const AppSpacing(),
    AppTypography.empty.copyWith(
      bodyMedium: const TextStyle(fontSize: 15, height: 1.5),
      titleLarge: const TextStyle(fontWeight: FontWeight.w700),
    ),
  ],
);
```

> ⚠ **`ThemeData.copyWith(extensions:)` 는 기존 extension map 을 통째로
> 교체합니다** (교체이지 병합이 아닙니다). 위 리스트에서 `AppTypography` 만
> 넘기면 `AppColors` 와 `AppSpacing` 이 **등록에서 사라집니다**.
> `ThemeX` 의 폴백 덕에 크래시는 나지 않지만, 사용자가 `copyWith` 로 조정해 둔
> 색·간격 값은 조용히 유실되고 기본 토큰으로 되돌아갑니다. **항상 세 원소를
> 모두 나열하세요.**

`copyWith` 에 넘길 수 있는 인자는 M3 15 스타일과 같은 이름입니다 —
`displayLarge` / `displayMedium` / `displaySmall` / `headlineLarge` /
`headlineMedium` / `headlineSmall` / `titleLarge` / `titleMedium` /
`titleSmall` / `bodyLarge` / `bodyMedium` / `bodySmall` / `labelLarge` /
`labelMedium` / `labelSmall`. 지정하지 않은 속성은 `TextStyle.merge` 로
테마 값이 유지되므로, `fontSize` 만 바꾸고 `fontWeight` 는 테마를 따르는 식의
부분 override 가 가능합니다.

### 3. 시맨틱 컬러 · 간격 커스터마이징

**`AppColors`** 는 `ColorScheme` 에 없는 앱 고유 시맨틱 컬러 6종
(`success` / `warning` / `info` + 각각의 `onSuccess` / `onWarning` / `onInfo`)
을 담습니다. `AppColors.fromBrightness(Brightness)` 로 라이트/다크 기본 토큰을
만들고 `copyWith` 로 개별 색만 교체합니다.

```dart
AppColors.fromBrightness(Brightness.light)
    .copyWith(success: const Color(0xFF00897B));
```

**`AppSpacing`** 은 **4 의 배수 7단계**입니다 (등차 4dp 가 아닙니다 — `xl` 은
`lg` 의 +8 입니다).

| 토큰 | 값 (dp) | 토큰 | 값 (dp) |
|---|---|---|---|
| `xs` | 4 | `xl` | 24 |
| `sm` | 8 | `xxl` | 32 |
| `md` | 12 | `xxxl` | 48 |
| `lg` | 16 | | |

`const AppSpacing()` 이 기본값이고, `const AppSpacing().copyWith(md: 16)` 처럼
개별 단계만 조정합니다. 두 extension 모두 위 2번의 `extensions:` 리스트에
함께 넣어 등록합니다.

이 절의 커스터마이징과 직결된 계약이 둘 더 있습니다.

- **세 extension 모두 전 필드 기반 `==` / `hashCode` 가 구현돼 있습니다.**
  덕분에 `lib/app.dart` 처럼 `build` 안에서 `AppTheme.light()` 를 매번 새로
  만들어도 `ThemeData` 가 동일로 판정됩니다. 테스트가 잠그는 것은
  `AppTheme.light() == AppTheme.light()` 이며 (`T-03-WR-02: ThemeData 동등성`),
  그 귀결로 App 리빌드마다 `AnimatedTheme` 의 200ms 보간
  (`kThemeAnimationDuration`)이 재시작되고 `Theme.of` 의존 서브트리가 통째로
  리빌드되던 동작이 사라집니다. 이 fix 이전에도 `const` 정규화 덕에 기본값끼리는
  `==` 였고, **사용자가 `copyWith` 로 커스터마이즈하는 순간** 깨졌습니다 —
  즉 starter kit 의 주 사용 시나리오가 정확히 피해자였습니다.
- **extension 이 등록되지 않은 테마에서도 세 getter 는 크래시하지 않습니다.**
  사용자가 `AppTheme` 을 쓰지 않고 자체 `ThemeData` 를 만들거나, 위젯 테스트가
  맨몸 `MaterialApp()` 을 써도 기본 토큰으로 폴백합니다
  (`T-03-WR-04: extension 미등록 테마에서도 기본 토큰을 돌려준다`).

### 4. 반응형 breakpoint 계약

모바일 전용 3단계입니다 (`lib/core/theme/app_breakpoint.dart`).

| breakpoint | 범위 (dp) | 대상 |
|---|---|---|
| `compact` | 280 이상 ~ 360 미만 | 소형 디바이스 |
| `medium` | 360 이상 ~ 600 미만 | 일반 모바일 |
| `expanded` | 600 이상 ~ 674 미만 | 대형 모바일 / 폴더블 |

- **하한 포함, 상한 배타**입니다. 판정의 단일 진실원은
  `contains(width) => width >= minWidth && width < maxWidth` 이고
  `fromWidth` 가 거기서 파생되므로, **인접한 두 breakpoint 가 동시에 참인
  경계값은 없습니다** (360dp 는 `medium` 단독, 600dp 는 `expanded` 단독).
- 지원 범위(280~674dp) 밖은 **양끝으로 포화**합니다 — 279dp 는 `compact`,
  가로 모드의 800dp 는 `expanded` 로 떨어집니다.

> ⚠ **`maxWidth` 를 실제 가용 폭으로 쓰지 마세요.** `maxWidth` 는 "선언된 지원
> 상한"입니다. 포화 정책 때문에 800dp 화면에서도 `expanded.maxWidth` 는 674 를
> 돌려주므로, 이 값을 `clamp` 등 레이아웃 계산에 그대로 넣으면 화면이 674dp 로
> 잘립니다.

컨테이너의 **지역 제약**을 기준으로 분기하려면 `LayoutBuilder` 안에서
`fromWidth` 를 직접 호출합니다.

```dart
LayoutBuilder(
  builder: (context, constraints) {
    final bp = AppBreakpoint.fromWidth(constraints.maxWidth);
    return bp == AppBreakpoint.compact ? const _Narrow() : const _Wide();
  },
);
```

`context.breakpoint` 는 `MediaQuery.sizeOf(context).width`, 즉 **화면 전체 폭**
기준입니다. 그래서 bottom sheet, 분할 레이아웃, 패딩된 칼럼 안에서는 실제
가용 폭과 어긋납니다 — 640dp 화면 안의 300dp 컨테이너에서 `context.breakpoint`
는 `expanded` 지만 지역 breakpoint 는 `compact` 입니다. 이 사용 예는
`T-03-IN-05: isPortrait 은 isLandscape 에서 파생된다` group 이 실행 가능한
근거로 잠급니다. 화면 방향은 `context.isLandscape` / `context.isPortrait`
(후자는 전자의 부정으로 파생) 로 읽습니다.

### 5. 키보드 focus outline (접근성)

`BrandFocusWrapper` (`lib/core/theme/brand_focus_wrapper.dart`) 는 브랜드 규격이
고정된 버튼을 감싸 **키보드 focus 도착 시에만** outline 을 그립니다
(WCAG 2.1 SC 2.4.7 Focus Visible, Level AA).

- **파일 경로가 바뀌었습니다.** 2026-09-12 에 `lib/core/theme/focus_wrapper.dart`
  → `lib/core/theme/brand_focus_wrapper.dart` 로 `git mv` 했습니다.
  **클래스명 `BrandFocusWrapper` 는 그대로**이므로, 옛 경로로 import 하던
  사용자 코드는 import 경로만 갱신하면 됩니다.
- 생성자는 다음과 같고, `borderRadius` 는 음수를 `assert` 로 거부합니다.

  ```dart
  BrandFocusWrapper({
    required Widget child,
    required double borderRadius,
    bool isEnabled = true,
  })
  ```

- **Tab 1회당 버튼 1개입니다.** wrapper 는 traversal 정지점을 만들지 않습니다 —
  내부 `Focus` 가 `canRequestFocus: false` + `skipTraversal: true` 이므로
  버튼 앞에 "Enter 가 먹지 않는 죽은 Tab stop" 이 생기지 않습니다.
  `isEnabled: false` 면 `descendantsAreFocusable` 로 자손 focus 진입 자체를
  차단합니다 (disabled button).
- **outline 은 키보드 조작에서만 표시됩니다.** 조건은 자손 focus 보유
  **그리고** `FocusManager.highlightMode == FocusHighlightMode.traditional`
  의 AND 입니다. 손가락 터치로 들어온 focus, 다이얼로그 닫힘 후 focus 복원,
  코드에서 호출한 `requestFocus()` 에서는 표시하지 않습니다. 입력 수단이
  런타임에 바뀌면 구독한 리스너가 outline 을 다시 계산하므로 stale 로 남지도
  않습니다.
- **외관은 hardcode 입니다** — 2dp solid border, 2dp offset(padding),
  라이트 테마는 검정 `Color(0xFF000000)` / 다크 테마는 흰
  `Color(0xFFFFFFFF)`, outline 모서리는 `borderRadius + 4` (버튼보다 4dp 큽니다 —
  2dp offset + 2dp border 만큼 바깥에 그려지기 때문입니다).
  M3 `colorScheme` / `textTheme` 토큰 의존이 **0** 이므로 사용자가 `ThemeData`
  를 어떻게 바꾸든 focus indicator 가 drift 하지 않습니다. 이것이 의도된
  설계이며, `ThemeData.focusColor` 나 `colorScheme.primary` 를 쓰는 대안은
  **금지**합니다 (테마 tint 로 물들면 outline 과 버튼 배경의 대비가 깨집니다).

> ⚠ **wrapper 는 child 제약을 가로·세로 각 8dp 잠식합니다.** border 2dp +
> padding 2dp 로 사방 4dp 씩 줄어듭니다. 부모가 크기를 bound 하면
> **300x48 → child 292x40** 이 되어 브랜드 규정 높이(48dp)와 최소 터치 타겟이
> 함께 깨집니다. **브랜드 규격 높이는 wrapper 바깥에서 지정하세요** (현재
> 호출부는 `SizedBox(height: spec.height)` 를 child 내부에 두어 이를 피합니다).
> 수치 계약은 `T-03-IN-04: wrapper 의 제약 잠식과 borderRadius 방어` group 이
> 잠급니다.

**a11y 위임:** 감싸는 버튼이 `Semantics(excludeSemantics: true)` 로 자손의
focus 의미론을 차단하는 경우가 있습니다. 그래서 wrapper 는
`includeSemantics: false` 로 자기 의미론을 숨기는 대신
`Semantics(focusable:, onFocus:)` 를 직접 노출하고, focus 요청을 첫 traversal
자손(실제 버튼의 `InkWell`)에게 위임합니다. 덕분에 스크린리더의 focus 요청이
실제 버튼에 도달합니다.

**실 단말 UAT 체크 3항목** — 위젯 테스트로는 실 입력기(외부 키보드,
스크린리더) 동작을 완전히 대체할 수 없으므로, 소셜 로그인 버튼을 손대거나
새 provider 를 추가한 뒤에는 실 단말에서 다음을 확인하세요.

1. 외부 키보드 Tab 1회당 버튼 1개씩 이동하고, Tab 직후 Enter 로 즉시 동작한다
   (중간에 아무 반응 없는 정지점이 끼지 않는다).
2. TalkBack / VoiceOver 스와이프로 각 버튼에 도달하고 더블탭으로 활성화된다.
3. 손가락으로 터치한 뒤에는 outline 이 표시되지 않는다.

### 회귀 가드 위치

| 대상 | 테스트 파일 |
|---|---|
| 시드 컬러 주입 (`light`/`dark` 의 `seedColor` 인자) | `test/core/theme/app_theme_test.dart` — `T-03-IN-02: seedColor 를 인자로 주입할 수 있다` |
| `ThemeData` 동등성 (`AppTheme.light() == AppTheme.light()`) | `test/core/theme/app_theme_test.dart` — `T-03-WR-02: ThemeData 동등성` |
| extension 값 동등성 3종 (`==` / `hashCode`) | `test/core/theme/app_colors_test.dart` — `T-03-WR-02: AppColors 값 동등성` · `app_spacing_test.dart` — `T-03-WR-02: AppSpacing 값 동등성` · `app_typography_test.dart` — `T-03-WR-02: AppTypography 값 동등성` |
| 시맨틱 컬러 대비 (라이트/다크 pair) | `test/core/theme/app_colors_test.dart` — `WCAG AA contrast` |
| 타이포그래피 로케일 기하 + override 우선순위 | `test/core/theme/theme_extensions_test.dart` — `T-03-WR-03: appTypography 가 로케일별 기하를 따른다` |
| extension 미등록 테마 폴백 | `test/core/theme/theme_extensions_test.dart` — `T-03-WR-04: extension 미등록 테마에서도 기본 토큰을 돌려준다` |
| breakpoint 범위 파생 (상한 배타 + 양끝 포화) | `test/core/theme/app_breakpoint_test.dart` — `T-03-WR-05: contains 와 fromWidth 가 범위에서 파생된다` |
| 지역 제약 기준 breakpoint + orientation 파생 | `test/core/theme/app_breakpoint_test.dart` — `T-03-IN-05: isPortrait 은 isLandscape 에서 파생된다` |
| Tab 1회당 버튼 1개 (죽은 Tab stop 0) | `test/features/auth/presentation/_widgets/focus_visible_test.dart` — `T-03-CR-01: BrandFocusWrapper 는 traversal 정지점을 추가하지 않는다` |
| outline 표시 조건 (키보드 조작 한정) | `test/features/auth/presentation/_widgets/focus_visible_test.dart` — `T-03-WR-01: outline 은 highlightMode=traditional 에서만 표시된다` |
| wrapper 의 8dp 잠식 수치 + `borderRadius` 방어 | `test/features/auth/presentation/_widgets/focus_visible_test.dart` — `T-03-IN-04: wrapper 의 제약 잠식과 borderRadius 방어` |

### Pitfall

- **`Theme.of(context).extension<AppTypography>()` 직접 읽기 → 빈 스타일** —
  등록된 값은 `AppTypography.empty` 다. 완성된 스타일은 `context.appTypography`
  로만 얻는다.
- **`copyWith(extensions:)` 로 일부만 넘기면 나머지 extension 등록이 사라진다** —
  map 통째 교체이므로 `AppColors` · `AppTypography` · `AppSpacing` 셋을 항상
  함께 나열한다. 폴백 덕에 크래시는 없지만 커스터마이즈 값이 조용히 유실된다.
- **`AppBreakpoint.maxWidth` 를 가용 폭으로 오용** — 포화 정책상 800dp 화면도
  674 를 돌려준다. 레이아웃 계산에는 `LayoutBuilder` 의 `constraints.maxWidth`
  를 쓴다.
- **브랜드 규격 높이를 `BrandFocusWrapper` 안쪽에서 지정 → 8dp 잠식** —
  border 2dp + padding 2dp 가 사방 4dp 를 먹으므로 규격 크기는 wrapper 바깥에서
  지정한다.
- **라이트와 다크에 다른 시드 주입** — `AppTheme.light()` 와 `AppTheme.dark()`
  에 서로 다른 `seedColor` 를 넘기면 두 모드의 팔레트가 어긋난다.

---

## ATT (App Tracking Transparency) 와 iOS Facebook 로그인 — 앱 책임 영역

> **2026-09-16 도입.** 근거 = `/gsd-debug ios-facebook-limited-login` 세션의
> FU-f 결정(사용자 승인 2026-09-16). 진실원 2건 —
> `.planning/debug/resolved/ios-facebook-limited-login.md` ·
> `.planning/todos/completed/2026-09-16-att-manual-customization-point.md`.
>
> **ATT 프롬프트 · `NSUserTrackingUsageDescription` 목적 문구 ·
> `app_tracking_transparency` 같은 패키지는 스타터 킷 범위 밖이며, 킷 위에
> 만드는 각 앱의 책임입니다.** 다만 ATT 허용 여부가 iOS Facebook 로그인의
> 동작(Limited Login vs Classic)을 바꾸므로, 그 경계와 귀결을 이 절에
> 정리합니다.

### 킷이 보장하는 것 / 보장하지 않는 것

| 구분 | 내용 |
|---|---|
| **보장** | ATT 가 전혀 없는 **기본 설정 그대로** iOS Facebook 로그인이 동작한다 — Limited Login 경로가 이미 처리되어 있다 |
| **보장** | `ClassicToken` 분기를 코드에 유지한다. 따라서 ATT 를 추가한 앱도 **인증 코드를 고칠 필요가 없다** — ⚠ 이 문장은 **구조상 추론**이며 **ATT 허용 상태 실기기 검증은 0건**이다 |
| **비보장** | ATT 프롬프트 노출 · 목적 문구 · 추적 동의 UX |
| **비보장** | App Store 개인정보 라벨(privacy label) · privacy manifest · 심사 대응 |
| **비보장** | IDFA 를 실제로 쓰는 광고 / 어트리뷰션 기능 — 킷의 의존성에 광고 패키지는 0건이다(실측) |

### ATT 유무가 Facebook 로그인을 어떻게 바꾸는가

| 상태 | 토큰 종류 | Firebase 로 보내는 credential | 프로필 사진(photoURL) | 앱 전환 | 근거 |
|---|---|---|---|---|---|
| iOS · ATT 미요청 (**킷 기본값**) | `LimitedToken` (OIDC JWT) | `OAuthProvider('facebook.com').credential(idToken:, rawNonce:)` | **미갱신** | **전환되지 않음** — 웹 인증 세션 | (B) 실측 |
| iOS · ATT 거부 | `LimitedToken` (OIDC JWT) | 미요청 상태와 동일 | **미갱신** | **전환되지 않음** — 웹 인증 세션 | (B) 실측 |
| iOS · ATT 허용 | `ClassicToken` | `fb.FacebookAuthProvider.credential` | Graph API 프로필 사진 사용 가능 | **[미검증 — 실기기 0건]** | **[미검증 — 실기기 0건]** |
| Android (ATT 무관) | `ClassicToken` | `fb.FacebookAuthProvider.credential` | Graph API 프로필 사진 사용 가능 | 플러그인 기본 동작 | (B) 실측 — 플러그인 Android 소스에 Limited 분기 없음 |

**Android 는 7.2.0 부터 nonce 를 실제로 보낸다.** flutter_facebook_auth 7.1.6
까지 Android 는 앱이 넘긴 nonce 를 버렸다. 7.2.0 부터는
`LoginConfiguration(permissions, nonce)` 로 로그인하므로 Facebook Android SDK
가 요청 권한에 **`openid` 를 자동으로 더하고**(앱이 요청한 `email` ·
`public_profile` + `openid`) PKCE 를 쓰며, 결과 `ClassicToken` 의
`authenticationToken` 에 OIDC JWT 가 함께 실린다 ((B) 실측 — 플러그인 Android
소스 + SDK 18.1.3 `LoginConfiguration`). 킷은 그래도 Android 에서 access token
credential 을 유지한다 — access token 이 있어야 Graph API 프로필 사진을 쓸 수
있기 때문이다. `authenticationToken` 을 쓰도록 코드를 고칠 필요는 없다.

**앱이 `LoginTracking.enabled` 를 요청해도 결과는 같다.** 킷은 로그인 호출에
이미 추적 허용을 요청하고 있지만, iOS 는 ATT 가 허용 상태가 아니면 그 요청을
무시하고 Limited Login 으로 강제한다. 호출부는 아래 한 곳이다
(`lib/features/auth/data/auth_repository.dart:2486-2491`).

```dart
_facebookAuth.login(
  permissions: ['email', 'public_profile'],
  loginTracking: LoginTracking.enabled,
  nonce: hashNonceSha256Hex(rawNonce),
)
```

### 근거 — 출처 구분

이 절의 주장은 **(A) 공식 문서 인용 / (B) 우리 코드 · SDK 소스 실측 /
(C) 미검증** 셋으로 구분한다. 실측을 공식 문서 주장으로 승격하지 않는다.

#### (A) 공식 문서 인용 — 영문 verbatim

- Meta, Limited Login overview — https://developers.facebook.com/docs/facebook-login/limited-login/
  - "Limited Login returns an `AuthenticationToken` that wraps an OpenID Connect token"
  - "The ID token cannot be used to request additional data using the Graph API, such as friends, photos, or pages"
  - classic Facebook Login "does not support Limited Login safeguards."
- Meta, Advertising Tracking Enabled — https://developers.facebook.com/docs/app-events/guides/advertising-tracking-enabled/
  - "If permission is provided, call the `setAdvertiserTrackingEnabled` method of the `FBSDKSettings` class and set it to `YES`"
  - iOS 17.0+ : "We now rely on Apple's App Tracking Transparency (ATT) system API to determine ATT permission status."
- Firebase, Supporting iOS 14 — https://firebase.google.com/docs/ios/supporting-ios-14
  - "With iOS 14.5, Apple requires developers to receive the user's permission through the App Tracking Transparency framework to track them or access their device's advertising identifier (IDFA)."
  - "Analytics event logging, event reporting, and conversion measurement are unaffected, but attribution is impacted if IDFA is not accessible."
- Firebase, Configure data collection — https://firebase.google.com/docs/analytics/configure-data-collection
  - "If you installed the `FirebaseAnalytics` module to your app through SPM or CocoaPods and want to disable collection of the IDFA (a device's advertising identifier) in your Apple app, ensure that the AdSupport framework is not included in your app."

#### (B) 우리 코드 · SDK 소스 실측

⚠ **「ATT 미허용 → Limited Login 강제」 인과의 유일한 근거는 이쪽이다.**
이 인과를 직접 진술하는 **Meta 공식 문서 문장은 확보하지 못했다** — 해당
문서 페이지 2건이 각각 HTTP 500 · 404 로 접근 불가였다. 아래 실측을 공식
문서 인용인 것처럼 옮기지 말 것.

| 위치 | 실측 내용 |
|---|---|
| `lib/features/auth/data/auth_repository.dart:2459-2468` (docstring) | flutter_facebook_auth 7.2.0 iOS 는 ATT 미허용이면 Limited Login 으로 강제하고(`FacebookAuth.swift:106-110`) `LimitedToken` 을 돌려준다 |
| `auth_repository.dart:2486-2491` | 로그인 호출부 — `LoginTracking.enabled` 와 해시된 nonce 를 넘긴다 |
| `auth_repository.dart:651-655` | `if (!facebook.isLimited)` 일 때만 Graph API 프로필 사진(`_setFacebookPhotoUrl`)을 채운다 |
| `auth_repository.dart:617` (주석) | Classic(Android · iOS ATT 허용)의 access token credential 에는 nonce 가 묶이지 않는다 (로그인 요청에는 Android 도 7.2.0 부터 nonce 가 실린다) |
| `auth_repository.dart:608-611` | Limited 충돌은 `_signInAfterLimitedLinkConflict` 로 분기한다 — nonce 는 1회용이라 재제출할 수 없다 |
| `.planning/debug/resolved/ios-facebook-limited-login.md` | 실 단말 관측 이력 |

#### (C) 미검증 — 실측 0건

- **ATT 허용 상태의 실기기 Facebook 로그인(= Classic 경로) 검증 0건.**
- ATT 를 추가해도 인증 코드 변경이 불필요하다는 것은 **구조상 추론**이다.

### 추적하는 앱이 해야 할 일

1. **ATT 요청을 붙인다** — `app_tracking_transparency` 같은 패키지는 **킷에
   없다**(실측). 앱이 직접 추가한다.
2. **목적 문구를 넣는다** — `ios/Runner/Info.plist` 에
   `NSUserTrackingUsageDescription` 키를 추가한다. **현재 킷에는 없다**(실측).
3. **Meta SDK 설정** — (A) 의 "If permission is provided, call the
   `setAdvertiserTrackingEnabled` method of the `FBSDKSettings` class and set
   it to `YES`" 인용이 근거다. 다만 같은 문서가 iOS 17.0+ 에 대해 "We now rely
   on Apple's App Tracking Transparency (ATT) system API to determine ATT
   permission status." 라고 밝히므로, 최신 iOS 에서는 SDK 가 ATT 상태를 직접
   본다.
4. **순서 주의** — ATT 를 로그인 **뒤에** 요청하면 그 로그인은 이미 Limited 로
   끝난 상태다. **[추론 — 실측 0건]**
5. **App Store 개인정보 라벨 · privacy manifest 갱신은 앱 책임이다.**

목적 문구 키(`NSUserTrackingUsageDescription`)가 없을 때 iOS 가 ATT 프롬프트를
어떻게 처리하는지는 **[미확인 — Apple 공식 문서 확인 필요]** 다. 이 매뉴얼은
그 동작에 대한 Apple 문서를 인용하지 않았다.

### IDFA — 현재 킷 설정에서 실제로 수집되는가

- **의존성 구성은 수집 가능 상태다** — iOS 는 SPM 을 쓰므로 근거도 SPM 쪽이다.
  `firebase_analytics` **12.6.0**(현재 해석값 — `pubspec.yaml` 은 `^12.6.0` 이므로
  실제 값은 `pubspec.lock` 에서 확인한다)의 `ios/firebase_analytics/Package.swift` 는
  환경변수가 없을 때 기본 product 로 **`FirebaseAnalytics`** 를 고르며(`:15-16`
  실측), 이는 CocoaPods 기본 구성(`FirebaseAnalytics/Default`)과 **동등**하다 —
  전환으로 IDFA 구성이 달라진 것은 없다(delta 0).
  - caret 범위이므로 `pub upgrade` 로 12.7+ 가 들어오면 기본 product 선택 로직이
    바뀌어도 이 서술은 12.6.0 을 계속 가리킨다. 올린 뒤에는 아래 한 줄로 **해석된
    버전의** 근거를 다시 확인할 것(`fvm flutter pub get` 이 돌아 있어야 한다).
    ```bash
    P="$(jq -r '.plugins.ios[] | select(.name=="firebase_analytics") | .path' .flutter-plugins-dependencies)ios/firebase_analytics/Package.swift"
    grep -n -e '^// .*FIREBASE_ANALYTICS_WITHOUT_ADID' -e '^let useWithoutAdId' -e '^let analyticsProduct' "$P"
    ```
    - **라인 번호가 아니라 내용으로 찾는다.** 이 명령의 목적이 「상향 **뒤**」 근거
      재확인인데, 상향으로 `Package.swift` 에 줄이 추가되면 `sed -n '13,16p'` 같은
      고정 구간은 엉뚱한 곳을 가리킨다 — 목적과 수단이 서로를 무효화한다.
    - 패턴은 **선언 줄에만** 걸리도록 `^` 로 고정했다. 앵커가 없으면 같은 파일
      `:35` 의 사용 줄(`.product(name: analyticsProduct, …)`)까지 섞여 아래 서술의
      「4줄」 과 어긋난다. 교대(`|`) 대신 `-e` 를 여러 번 쓰는 이유는 이 환경의
      `grep` 이 ugrep 이라 괄호를 쓴 `-E` 패턴에 위음성 위험이 있기 때문이다.
    - 출력의 **맨 앞 줄 번호가 곧 최신 근거**다 — 본문이 인용한 `:13-14` · `:15-16` 은
      `firebase_analytics` 12.6.0 기준이므로, 상향 뒤에는 이 출력의 번호로 읽는다.
    실행하면 **아래** 「수집 구성 자체를 끄고 싶다면」 bullet 의 swift 인용
    블록(`// Set FIREBASE_ANALYTICS_WITHOUT_ADID=true …`) 2줄에 이어
    `let useWithoutAdId = …!= nil` ·
    `let analyticsProduct = useWithoutAdId ? "FirebaseAnalyticsCore" :
    "FirebaseAnalytics"` 가 나온다 — 주석 2줄 + 선언 2줄로 **합계 4줄**이다.
    뒤 2줄이 달라졌다면 서술을 갱신해야 한다.
- **그럼에도 실제 수집되는 IDFA 는 없다** — 킷은 ATT 를 **한 번도 요청하지
  않으므로** iOS 14.5+ 가 IDFA 를 내주지 않는다. 근거는 (A) Firebase
  Supporting iOS 14 의 "With iOS 14.5, Apple requires developers to receive
  the user's permission through the App Tracking Transparency framework to
  track them or access their device's advertising identifier (IDFA)." 이다.
  같은 문서가 "Analytics event logging, event reporting, and conversion
  measurement are unaffected, but attribution is impacted if IDFA is not
  accessible." 라고 밝히듯 Analytics 이벤트 수집 자체는 영향받지 않는다.
- **ATT 를 추가하고 사용자가 허용하면** 그 경로가 열린다. 그 시점부터 App Store
  개인정보 라벨과 정책 귀결은 **앱 책임**이다.
- **수집 구성 자체를 끄고 싶다면** (A) 의 Firebase Configure data collection
  인용("… ensure that the AdSupport framework is not included in your app.")이
  출발점이고, SPM 경로의 스위치는 위 `Package.swift` 의 주석이 그대로 알려준다
  (`:13-14` verbatim).
  ```swift
  // Set FIREBASE_ANALYTICS_WITHOUT_ADID=true to use FirebaseAnalyticsCore.
  // e.g. FIREBASE_ANALYTICS_WITHOUT_ADID=true flutter build ios
  ```
  - ⚠ 위 블록은 **upstream `Package.swift` 의 verbatim 인용**이라 bare
    `flutter build ios` 가 그대로 들어 있다. 그대로 복붙하지 말 것 — 이 킷은
    **FVM 필수**이고 flavor · dart-define 도 함께 넘겨야 한다. 킷에서의 모양은
    아래와 같다(「Flutter SDK 상향 (FVM)」 ② 10번의 빌드 명령에 환경변수만 앞에
    붙인 것이다).
    ```bash
    FIREBASE_ANALYTICS_WITHOUT_ADID=true fvm flutter build ios --no-codesign --flavor dev --dart-define-from-file=config/dev.json
    ```
  - 판정은 `!= nil` 이라 **값이 무엇이든 환경변수가 정의돼 있기만 하면**
    `FirebaseAnalyticsCore` 로 바뀐다(`:15` 실측) — `=false` 도 끈 것이 된다.
  - 이 경로로 실제 수집을 끄는 것은 **[미검증 — 킷에서 시도 0건]** 이다.
- ⚠ **ATT 허용 상태에서 실제로 무엇이 수집되는지에 대한 실측은 0건**이다.

### 흔한 실수

- **photoURL 이 안 채워지는 것은 버그가 아니다** — ATT 가 없는 기본 설정의
  정상 동작이다(`auth_repository.dart:651-655`).
- **Limited 토큰으로 Graph API 추가 데이터를 기대하지 말 것** — (A) 의 "The ID
  token cannot be used to request additional data using the Graph API, such as
  friends, photos, or pages" 그대로다.
- **Facebook 앱으로 전환되지 않는 것도 정상이다** — Limited 경로는 웹 인증
  세션을 쓴다.
- **`LoginTracking.enabled` 를 켰으니 Classic 이겠거니 하는 가정** — iOS 는 ATT
  미허용이면 그 요청을 무시하고 Limited 로 간다.
- **ATT 를 붙였다고 인증 코드를 갈아엎지 말 것** — Classic 분기는 이미 있다.
  단 실기기 검증 0건이므로 적용하는 앱이 직접 검증해야 한다.

### 코드 anchor · 회귀 가드

| anchor | 무엇을 정하는가 |
|---|---|
| `auth_repository.dart:2459-2468` | Limited 강제 조건과 토큰 타입 분기의 근거 docstring |
| `auth_repository.dart:2486-2491` | 로그인 요청 옵션(`LoginTracking.enabled` · 해시 nonce) |
| `auth_repository.dart:651-655` | Graph API 프로필 사진 호출의 Classic 전용 가드 |
| `auth_repository.dart:617` | Classic credential 의 재제출 허용 근거 주석 |
| `auth_repository.dart:608-611` | Limited 충돌 분기(nonce 1회용) |

**자동 회귀 가드는 없다.** ATT 상태나 Limited / Classic 분기를 단언하는 테스트는
0건이며, 이 절의 근거는 위 docstring 과 `/gsd-debug` 세션 기록뿐이다. 이 동작을
바꾸는 앱은 스스로 실기기에서 확인해야 한다.

### 관련 절

- `## IdP 프로필 동기화 정책 (R10-FOLLOWUP)` — 재로그인 시 `photoURL` 동기화
  정책.
- `## Multi-Provider Account Linking (Phase 9.2)` 의
  `### 3. Facebook 자동 sendEmailVerification + photoURL Graph API (R4 + R5)`
  — `_setFacebookPhotoUrl` 본체 설명. 그 절의 서술은 **Classic 경로 전제**이며,
  Limited 에서는 이 호출을 건너뛴다.

---

## Flutter SDK 상향 (FVM)

> **2026-09-20 도입.** 근거 = quick `260920-23d`
> (`.planning/quick/260920-23d-upgrade-flutter-to-3-47-5-with-spm-off/`) 의 실측 —
> Flutter 3.41.9(Dart 3.11.5) → **3.47.5(Dart 3.13.4)** 상향. 원 todo =
> `.planning/todos/pending/2026-09-20-flutter-3-47-5-upgrade.md`.
>
> 이 절은 **킷 사용자가 자기 프로젝트의 Flutter 를 올릴 때**의 절차 · 도구가
> 자동으로 고치는 파일 · 함정을 정리합니다.

### ① 버전 pin 의 진실원

| 대상 | 값 | 비고 |
|---|---|---|
| `.fvmrc` | `{"flutter": "3.47.5"}` | **유일한 추적 pin.** 여기만 바꾸면 된다 |
| `.fvm/flutter_sdk` | `~/fvm/versions/<버전>` 심볼릭 링크 | 추적하지 않는다 |
| `.vscode/settings.json` | `"dart.flutterSdkPath": ".fvm/flutter_sdk"` | **심볼릭 링크 경로로 고정** |
| `.mcp.json` dart 서버 | `.fvm/flutter_sdk/bin/dart` | 링크를 따라가므로 수정 불필요 |

- `fvm use <버전>` 은 `.vscode/settings.json` 을 `.fvm/versions/<버전>` 같은
  **버전 박힌 경로**로 바꿔 버린다. 그대로 커밋하면 다음 상향마다 이 파일이
  또 바뀐다 → **`git checkout -- .vscode/settings.json` 으로 되돌린다.**
- `fvm use` 뒤 dart MCP 서버 · IDE 의 Analysis Server 는 옛 SDK 프로세스를 물고
  있을 수 있다 → 세션/IDE 재시작을 권한다.

### ② 상향 절차

1. **같은 HEAD 에서 현재 SDK 기준선을 먼저 잰다** — `pub get` → `build_runner` →
   `flutter analyze` → `dart analyze` → `dart format --output=none
   --set-exit-if-changed lib test bin` → **전체 test**. 이 수치가 유일한 비교 기준이다.
   여기서 이미 실패가 있으면 상향하지 말고 그것부터 해결한다.
2. **iOS 네이티브 SDK 의 고정 상태를 먼저 확인한다** — 두 `Package.resolved` 가
   같은 내용인지(`cmp -s`) 보고, 상향 뒤 그대로인지 대조할 기준으로 삼는다
   (「iOS 의존성 관리 (SPM)」 ②).
3. `fvm install <버전> --skip-pub-get` → `fvm use <버전> --skip-pub-get`
4. `.vscode/settings.json` 복원 · `fvm flutter --version --machine` 으로
   framework/dart 버전 확인
5. `fvm flutter pub get` — **`pub upgrade` 는 쓰지 않는다.** 원인 분리가 깨진다
   (SDK 변화와 패키지 변화가 섞여 실패 원인을 좁힐 수 없게 된다)
6. `fvm dart run build_runner build --delete-conflicting-outputs`
7. `fvm flutter analyze` **그리고** `fvm dart analyze` — 둘 다 필요하다.
   Flutter 3.47.5 의 `flutter analyze` 는 analyzer plugin(riverpod_lint) 진단을
   **표시하지 않는다**(「정적 분석」 절 참고)
8. `fvm dart format --output=none --set-exit-if-changed lib test bin`
9. 전체 `fvm flutter test` — 기준선과 pass/skip/fail 수를 비교
10. iOS `fvm flutter build ios --no-codesign --flavor dev
    --dart-define-from-file=config/dev.json` · Android `fvm flutter build apk
    --debug --flavor dev --dart-define-from-file=config/dev.json`
11. 실기기 smoke — 기동 · 대표 provider 로그인 · 콜드 재기동 세션 복원

### ③ 도구가 자동으로 고치는 tracked 파일 (되돌리지 말고 함께 커밋)

3.41.9 → 3.47.5 에서 실제로 바뀐 것은 다음 3개다. **손으로 되돌려도 다음
`pub get` · 빌드에서 다시 생긴다.**

| 파일 | 원인 | 실제 diff |
|---|---|---|
| `analysis_options.yaml` | 3.47 `AnalysisOptionsMigration`(`flutter pub get` 이 호출) | `analyzer.exclude` 에 `build/**` · `android/**` · `ios/**` · `web/**` · `windows/**` · `macos/**` · `linux/**` **7줄 append**(+7/-0, 기존 주석 보존). stdout 에 `Upgrading analysis_options.yaml …` |
| `android/gradle.properties` | 3.47 `DisableBuiltInKotlin` · `DisableNewDsl` migrator(**모든 Android 빌드 직전** 실행) | `android.builtInKotlin=false` · `android.newDsl=false` + 각 설명 주석 **4줄 append** |
| `pubspec.lock` | SDK 가 고정하는 pub 핀 변화 | 직접 의존성은 `test` · `intl` 둘뿐, transitive 5건(`matcher` · `meta` · `test_api` · `test_core` · `vector_math`). codegen 스택은 불변 |

- `lib/l10n/generated/*.dart`(tracked) · `macos/Flutter/GeneratedPluginRegistrant.swift`
  도 SDK 템플릿이 바뀌면 재생성된다 — 이번에는 **변화 0** 이었다.
- SPM 통합은 **이미 적용돼 있다.** `ios/Runner.xcodeproj/project.pbxproj` ·
  `ios/Runner.xcodeproj/xcshareddata/xcschemes/*.xcscheme` · `Package.resolved` 가
  바뀌면 **diff 를 읽고 원인을 확인한다** — 도구의 새 migration, 아직 빌드한 적 없는
  scheme 의 첫 빌드, 또는 **SPM 미지원 플러그인의 유입**(「iOS 의존성 관리 (SPM)」 ④)
  셋 중 하나다.

### ④ iOS Swift Package Manager — 기본값(on)을 그대로 쓴다

- `pubspec.yaml` 에 SPM 스위치 키를 **두지 않는다.** Flutter 3.44+ 는 SPM 이 기본 on
  이고 `flutter create` 산출물에도 그 키가 없다 — 킷은 표준 모양을 따른다.
- **실효 증거 3종**(설정값이 아니라 결과로 판정한다): `project.pbxproj` 의
  `FlutterGeneratedPluginSwiftPackage` 참조 ≥ 1 · `ios/Flutter/ephemeral/Packages`
  존재 · `ios/Podfile` 부재.
- 해석 우선순위는 **pubspec `flutter: config:` → 전역 `flutter config` → 환경변수**
  다. `flutter config --list` 는 전역 설정이라 이 프로젝트의 판정 근거가 못 된다.
- 옛 키 `disable-swift-package-manager: true` 는 3.47 에서 **manifest 오류**다.
- iOS 네이티브 의존성의 운영(버전 고정 · 새 플러그인 확인 · 배포 타겟 · 미지원
  플러그인 증상)은 **「iOS 의존성 관리 (SPM)」**(`#ios-의존성-관리-spm`) 절에 있다.

### ⑤ Android 빌드 도구 하한 — 지금 경계선에 걸쳐 있다

| 항목 | 킷 현재 값 | 3.47.5 오류 하한 | 3.47.5 경고 하한 |
|---|---|---|---|
| Gradle | 8.14 | **8.14.0** | 9.1.0 |
| AGP | 8.11.1 | **8.11.1** | 9.0.1 |
| KGP | 2.2.20 | **2.2.20** | 2.3.20 |

- 세 값 모두 **오류 하한과 정확히 같다** → 빌드는 통과하되 `Warning: Flutter
  support for your project's … will soon be dropped` 3건이 찍힌다. **정상이다.**
- 다음 Flutter 상향에서는 AGP/KGP/Gradle 상향이 강제될 가능성이 높다. SDK 상향과
  **별도 작업**으로 잡아라(원인 분리).

### ⑥ iOS 환경 요구치

- 최소 deployment target: 3.47 은 **iOS 15.0**(3.41 은 13.0). 킷은 15.6 이라 여유가 있다.
- Xcode: 필수 ≥ 15, 권장 ≥ 16. 3.47.4 · 3.47.5 에 **Xcode 27 대응 핫픽스**가
  들어 있다(흰 화면 hang · iOS 27 실기기 디버깅 간헐 크래시) — 3.47.x 를 쓸 거면
  **3.47.5 이상**을 권한다.
- 번들 `iproxy` 는 3.47.5 에서도 여전히 **x86_64** 다 → Apple Silicon 에서 실기기
  실행에 **Rosetta 2 가 필요**하다. macOS major 업그레이드가 Rosetta 를 지울 수
  있으니 `arch -x86_64 /usr/bin/true` 로 확인한다.
- 실기기 debug 실행은 **USB 연결이 필수**다(무선은 디버거 미부착 → JIT 불가).
- **CocoaPods 는 iOS 빌드에 더 이상 필요하지 않다**(Phase 16.3 에서 SPM 으로
  전환했다). 단 `macos/` 는 아직 CocoaPods 를 쓰고(이 킷은 macOS 를 빌드하지
  않는다), `flutter doctor` 의 CocoaPods 항목은 **설치 여부와 무관하게 계속
  표시된다** — Xcode 워크플로에 조건 없이 등록된 검사라 그렇다.

### ⑦ golden test — SDK 상향은 렌더를 바꾼다

- 이번 상향에서 **golden 20장(추적 16 + gitignore `_ios` 4)이 실패**했다. 차이는
  버튼 둥근 모서리 안티에일리어싱뿐(최대 0.03% · 401px)이었고, 같은 HEAD 3.41.9
  기준선이 green 이었으므로 원인은 엔진 래스터 변화로 특정됐다.
- 절차: **같은 HEAD 기준선이 green 인지 먼저 확인** → 실패 golden 의
  `failures/*_isolatedDiff.png` · `*_maskedDiff.png` 를 **눈으로 확인** → 그 뒤에만
  실패한 test 파일만 대상으로 `--update-goldens` → 전체 test 재실행 → 별도 `test:` 커밋.
- 일괄 `--update-goldens` 는 하지 않는다(진짜 회귀를 덮어쓴다).
- iOS 변형 `*_ios.png` 는 Apple Font License 때문에 **gitignore** 라 로컬에서만
  재생성된다 — git 으로 복원할 수 없으니 재생성 전 디렉터리 백업을 권한다.

### ⑧ `environment: sdk` 하한은 별개 작업이다

`pubspec.yaml` 의 `environment: sdk: ^3.11.1` 은 이번에 **올리지 않았다.**
Dart 3.13 포매터의 스타일 변경 중 상당수(import 섹션 분리 · 호출 체인 split ·
파라미터 block formatting)는 **language version 3.13 이상에서만** 켜지기 때문에,
하한을 올리면 대량 재포맷과 언어 규칙 변화가 한꺼번에 들어온다. SDK 상향과
**분리해서** 별도 작업으로 다뤄라.

> 단, **language version 과 무관한** 포매터 수정은 하한을 안 올려도 적용된다.
> 이번에도 3.13 의 eager-split 수정 때문에 test 6파일 144줄이 재포맷됐다
> (`style:` 별도 커밋으로 분리). `dart format --set-exit-if-changed` 를
> analyze · test 와 동급 게이트로 두면(`.claude/rules/dart-format.md`) 이런 drift 가
> 누적되지 않는다.

### ⑨ 이번 3.47.5 상향의 실제 결과 (한 줄 요약)

`pub get` · `build_runner` · `flutter analyze` · `dart analyze` · iOS(`--no-codesign`,
210s) · Android(dev debug APK, 88s) 전부 통과했고, 전체 test 는 golden 20장을
사용자 승인 후 재생성한 뒤 기준선과 동일한 **`+1632 ~2` fail 0** 이었다.
추가 조치가 필요했던 것은 **golden 20장 재생성**과 **test 6파일 포맷 drift** 둘뿐이며,
AGP/KGP/Gradle 경고 3건과 `naver_login_sdk` SPM 미지원 경고 1건은 예상된 정상 출력이다
(이 경고는 Phase 16.2 이후 사라졌다).

---

## iOS 의존성 관리 (SPM)

> **2026-09-22 도입.** 근거 = Phase 16.3 산출물
> (`.planning/phases/16.3-ios-cocoapods-to-spm-migration/` 의 `16.3-CONTEXT.md` ·
> `16.3-RESEARCH.md` · `artifacts/`) 의 실측 — iOS 네이티브 의존성 관리자를
> CocoaPods → **Swift Package Manager(SPM)** 로 전환. 원 todo =
> `.planning/todos/pending/2026-09-19-cocoapods-to-spm-migration.md`.
>
> 이 절은 **킷 사용자가 iOS 네이티브 의존성을 다룰 때**의 개념 · 버전 고정 ·
> 새 플러그인 사전 확인 · 배포 타겟 변경 절차를 정리합니다.

### ① SPM 이 무엇이고 이 킷이 왜 SPM 인가

**Swift Package Manager(SPM)** 는 Apple 이 Swift 도구체인과 Xcode 에 내장한 의존성
관리자다. CocoaPods 가 하던 일(네이티브 SDK 선언 · 버전 해석 · 내려받기 · Xcode
프로젝트 연결)을 **별도 도구 설치 없이** Xcode 와 Flutter 도구가 직접 수행한다.
Flutter 3.44+ 는 SPM 이 **기본 on** 이고 `flutter create` 는 더 이상 `ios/Podfile` 을
만들지 않는다 — 이 킷도 그 표준 모양(별도 스위치 없이 기본값)을 따른다.

| 항목 | CocoaPods (이전) | SPM (현재) |
|---|---|---|
| 의존성 선언 | `ios/Podfile` + 각 플러그인의 `<name>.podspec` | 각 플러그인의 `Package.swift` + Flutter 가 매 빌드마다 생성하는 `FlutterGeneratedPluginSwiftPackage` |
| 잠금 파일 | `ios/Podfile.lock` (1개) | `Package.resolved` (**2곳** — ② 참고) |
| 내려받은 산출물 | `ios/Pods/` · `ios/.symlinks/` (프로젝트 안, gitignored) | `build/ios/SourcePackages/checkouts/` (빌드 디렉터리 안, gitignored) |
| 설치 요구 | ruby gem `cocoapods` 를 개발자가 따로 설치 | **없다** — Xcode · Flutter 도구에 내장 |

**왜 지금 옮겼나 (날짜가 걸린 확정 사실 2건):**

- Firebase 는 **2026-10** 이후 CocoaPods 로 **신규 버전을 배포하지 않는다** —
  "Firebase will stop publishing new versions to CocoaPods in October 2026."
  (https://firebase.google.com/docs/ios/cocoapods-deprecation)
- CocoaPods 레지스트리는 **2026-12-02** 에 영구 **read-only** 가 된다 —
  "Flutter continues to support CocoaPods in maintenance mode, however, the CocoaPods
  registry permanently becomes read-only on December 2, 2026."
  (https://docs.flutter.dev/packages-and-plugins/swift-package-manager/for-app-developers)

**Flutter 가 「SPM 비활성화」 와 CocoaPods fallback 을 막는 시점은 미공개다.** 도구는
예고만 한다 — 아래 두 문장이 Flutter 3.47.5 소스의 원문이다.

- `Disabling Swift Package Manager will not be allowed in a future version of Flutter.`
- `This will become an error in a future version of Flutter. Please contact the plugin maintainers to request Swift Package Manager adoption.`

- 특정 Flutter 버전 · 날짜를 추정해 계획을 세우지 않는다. 위 두 예고에는 버전도
  날짜도 없다. 확정된 날짜는 **2026-10** 과 **2026-12-02** 둘뿐이다.
- **범위:** 이 전환은 `ios/` 에만 해당한다. `macos/` 는 지금도 CocoaPods 를 쓴다
  (이 킷은 macOS 를 지원하지 않으므로 빌드하지 않는다).

### ② 네이티브 SDK 버전은 어디에 고정돼 있나

**진실원 표**

| 대상 | 값 | 비고 |
|---|---|---|
| `ios/Runner.xcworkspace/xcshareddata/swiftpm/Package.resolved` | 20개 핀의 `version` · `revision` | **빌드가 존중하는 쪽.** 실제 빌드가 `-workspace Runner.xcworkspace` 로 돌기 때문 |
| `ios/Runner.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved` | 위와 **바이트 동일**해야 한다 | Flutter 의 사전 해석(prefetch)이 이 컨테이너를 쓴다. 지우면 **핀을 무시한 최신값으로 자동 재생성**된다 |

- 두 파일 모두 tracked 다. 한쪽만 추적하면 fresh clone 의 첫 빌드에서 다른 쪽이
  최신값으로 생기고 `git status` 가 더러워진다.
- 같은지 확인: `cmp -s ios/Runner.xcworkspace/xcshareddata/swiftpm/Package.resolved ios/Runner.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved && echo SAME`
- **이 불변식에는 자동 가드가 있다** — `test/ios/spm_policy_test.dart` 의
  `T-16.3-SPM-03`. Xcode 는 **해석한 컨테이너 한쪽만** 갱신하므로(`.xcodeproj` 를
  직접 열면 project 쪽, `Runner.xcworkspace` 를 열면 workspace 쪽) 한쪽만 바뀌는
  것이 **정상 동작**이다. 이 test 가 red 면 위 ⚠ 박스가 말하는 핀 drift 가 이미
  시작된 것이다 — 의도한 쪽을 다른 쪽으로 복사해 같은 커밋에 담는다.

**직접 선언한 SDK 의 현재 고정값** (전이 의존성은 해석 결과를 그대로 수용한다)

| Swift package identity | 고정 버전 | 비고 |
|---|---|---|
| `firebase-ios-sdk` | 12.19.0 | 플러그인이 `exact` 로 고정 — 값을 손댈 필요가 없다 |
| `appauth-ios` | 2.0.0 | `GoogleSignIn-iOS` · `GTMAppAuth` 의 전이 의존 — 두 패키지가 `2.0.0 ..< 3.0.0` 을 요구해 핀이 유지된다 |
| `googlesignin-ios` | 9.1.0 | **명시 고정.** 그래프가 우연히 준 값이다 — 상향 시 `GoogleSignIn-iOS` 가 요구하는 AppAuth 범위와 함께 확인한다 |
| `facebook-ios-sdk` | 18.0.2 | 선언이 `"18.0.2" ..< "19.0.0"` 이라 고정하지 않으면 18.1.1 로 올라간다 |
| `line-sdk-ios-swift` | **5.17.0** | 아래 경고 박스 참고 |
| `naveridlogin-sdk-ios-swift` | 5.2.1 | 선언이 `.upToNextMinor(from: "5.2.0")` |

**상향 절차** — 값 문자열만 고치는 편집이다.

1. 두 `Package.resolved` 에서 대상 핀의 `version` · `revision` **문자열만** 고친다.
2. 두 파일을 **같은 내용**으로 맞춘다(`cmp -s`).
3. `revision` 은 추측하지 말고 태그에서 얻는다 — annotated 태그는 **peeled sha** 를 쓴다.
   ```bash
   git ls-remote --tags <repo-url> | grep -E 'refs/tags/<tag>(\^\{\})?$'
   ```
   - `--refs` 를 붙이면 `^{}` 줄이 **버려져** annotated 태그에서 태그 객체 sha(틀린 값)를 집는다.
4. 재빌드한 뒤 실제 checkout 으로 확인한다.
   ```bash
   ls build/ios/SourcePackages/checkouts          # 디렉터리 이름을 먼저 확인
   git -C build/ios/SourcePackages/checkouts/<디렉터리> describe --tags
   ```
   - **디렉터리 이름은 identity 가 아니라 repo 이름이다.** 위 표의 열 제목이
     「Swift package identity」(소문자)라 헷갈리기 쉬운데, SPM 은 checkout 디렉터리를
     저장소 URL 의 **마지막 경로 요소에서 `.git` 접미사를 뗀 이름**으로 만든다
     (`https://github.com/google/GoogleUtilities.git` → `GoogleUtilities`).
     현재 핀 20개 중 **16개의 `location` 이 `.git` 으로 끝나므로 URL 의 마지막 경로
     요소를 그대로 쓰면 안 된다** — `.git` 이 붙은 이름으로 `git -C` 를 걸면
     `No such file or directory` 가 난다. 재현:
     ```bash
     R=ios/Runner.xcworkspace/xcshareddata/swiftpm/Package.resolved
     jq '.pins | length' "$R"                             # 20
     jq -r '.pins[].location' "$R" | grep -c '\.git$'      # 16
     ```
     identity(소문자)와도 20개 중 6개가 어긋난다 —
     `appauth-ios` → `AppAuth-iOS`, `googlesignin-ios` → `GoogleSignIn-iOS`,
     `googleappmeasurement` → `GoogleAppMeasurement`, `googledatatransport` →
     `GoogleDataTransport`, `googleutilities` → `GoogleUtilities`, `gtmappauth` →
     `GTMAppAuth`.
   - macOS 기본 APFS 는 대소문자를 무시하므로 소문자 identity 로도 **지금은
     통한다**(실측). 대소문자 구분 볼륨이나 Linux CI 에서는
     `No such file or directory` 가 난다 — 그래서 `ls` 를 먼저 둔다.
5. 두 파일을 **같은 커밋**에 함께 담는다.

- FlutterFire 계열(`firebase_*` · `cloud_*`)은 플러그인이 `exact` 로 고정하므로 **pub
  패키지를 올리면 네이티브 SDK 가 따라 올라간다** — `Package.resolved` 를 손으로
  고치는 대상이 아니다.

> ⚠ **`Package.resolved` 를 지우지 말고, Xcode 의 *Update to Latest Package Versions* 를
> 누르지 말 것.**
>
> 핀이 풀리면 LINE 이 **5.17.0** 을 벗어나 5.18+ 로 drift 하고, `flutter_line_sdk` 2.7.2 의
> manifest 하한(iOS 13.0)과 LineSDK 의 하한 불일치는 **도구가 그 검사를 되살리는 순간
> 빌드 에러**가 된다(upstream issue https://github.com/line/flutter_line_sdk/issues/151).
> 다른 5개 핀도 같은 조작 한 번에 전부 풀린다.
>
> **복귀 조건:** `flutter_line_sdk` **3.0.0 의 pub.dev 릴리스** AND 킷 Android 의
> **AGP 9 세대 전환** 이 둘 다 성립할 때 다시 검토한다
> (`.planning/todos/pending/2026-09-21-flutter-line-sdk-3-0-0-return.md`).

- **SPM 경로에서는 `firebase_app_check` 가 `RecaptchaEnterprise`(바이너리 XCFramework,
  `recaptcha-enterprise-mobile-sdk` 18.9.1)를 함께 링크한다** — CocoaPods 경로에는 없던
  SDK 다. 앱 크기 · privacy manifest · 심사 신고 대상 판단에 넣을 것.
- **`flutter clean` 은 SPM checkout(`build/ios/SourcePackages`)까지 지운다** — 다음 빌드가
  수백 MB 를 다시 받아 수 분이 걸린다. 캐시 문제를 풀려는 목적이라면 ⑥ 을 먼저 볼 것.

### ③ 새 플러그인을 넣기 전에 확인할 것

**(가) `Package.swift` 가 있는가** — native 코드를 가진 iOS 플러그인 전수 검사.

```bash
jq -r '.plugins.ios[] | select(.native_build) | "\(.name)\t\(.path)"' .flutter-plugins-dependencies \
  | while IFS=$'\t' read -r n p; do
      if [ -f "${p}ios/$n/Package.swift" ] || [ -f "${p}darwin/$n/Package.swift" ]; then
        echo "SPM-OK $n"; else echo "SPM-MISSING $n"; fi
    done | sort
```

- `select(.native_build)` 필터를 빼면 `path_provider_foundation` 같은 **Dart 전용
  플러그인**(`dartPluginClass` 만 있고 네이티브 패키지가 아예 없다)이 `SPM-MISSING` 으로
  오탐된다.
- `SPM-MISSING` 이 0줄인 것만으로 끝내지 말고 **대상 개수가 0 이 아닌지** 함께 본다 —
  0개를 검사하고 통과한 것과 구분되지 않는다.

**(나) 플러그인과 그 의존 SDK 의 `platforms` 하한을 대조한다.**

- 플러그인 `Package.swift` 의 `platforms: [.iOS(...)]` 와, 그 플러그인이
  `.package(url:)` 로 끌어오는 SDK 의 같은 값을 비교한다. **의존 SDK 의 하한이 더 높으면
  SPM 이 타깃 그래프 구성 단계에서 빌드를 막는다.**
- LINE 의 교훈: `flutter_line_sdk` 2.7.2 는 13.0 인데 LineSDK 5.17.0 은 15.0 이다. 이
  불일치는 **앱의 배포 타겟을 올려도 해소되지 않는다** — Flutter 는 자기가 생성하는
  패키지의 하한만 끌어올리고 플러그인 자신의 `Package.swift` 는 건드리지 않기 때문이다.

**(다) FlutterFire 계열은 `firebaseSdkVersion` 이 기존 플러그인들과 같은지 본다.**

`fvm flutter pub get` 을 먼저 돌린 뒤 실행한다 — `.flutter-plugins-dependencies` 는
gitignored 생성물이라 fresh clone 에는 없다.

```bash
EXPECTED=$(jq -r '[.plugins.ios[] | select(.native_build)
                   | select(.name | startswith("firebase_") or startswith("cloud_"))]
                  | length' .flutter-plugins-dependencies)
jq -r '.plugins.ios[] | select(.native_build) | "\(.name)\t\(.path)"' .flutter-plugins-dependencies \
  | while IFS=$'\t' read -r n p; do
      f="${p}ios/$n/Package.swift"; [ -f "$f" ] || f="${p}darwin/$n/Package.swift"
      [ -f "$f" ] && grep -h '^let firebaseSdkVersion' "$f"
    done | sort | uniq -c
echo "기대 FlutterFire 플러그인 수: $EXPECTED"
```

- **합격 기준: 선언 줄이 정확히 1줄이고, 그 줄의 맨 앞 개수가 `$EXPECTED` 와 같다.**
  현재 킷의 실제 출력은 아래 2줄이다.
  ```
     8 let firebaseSdkVersion: Version = "12.19.0"
  기대 FlutterFire 플러그인 수: 8
  ```
- **개수가 `$EXPECTED` 보다 작으면 합격이 아니다.** 이 명령은 플러그인마다
  `<path>ios/<name>/Package.swift` 와 `<path>darwin/<name>/Package.swift` **두 경로만**
  본다. 어느 쪽에도 없는 플러그인은 **조용히 건너뛴다** — 8개 중 3개만 읽혀도 출력은
  여전히 1줄이라, 「1줄」 조건만으로는 **읽히지 않은 플러그인이 다른 값을 선언하고
  있어도 통과한다.** 이 명령의 존재 이유가 바로 그 값 불일치 검출이므로, 표본이
  빠지면 검출력이 그만큼 조용히 줄어든다. 그래서 「1줄」 과 「개수 = `$EXPECTED`」 를
  **함께** 본다.
- **0줄이면 합격이 아니라 공허한 통과다** — 플러그인을 하나도 읽지 못한 것이다
  (`pub get` 미실행, 또는 `.flutter-plugins-dependencies` 의 구조가 바뀌었다).
  그래서 `sort -u` 가 아니라 `sort | uniq -c` 로 **개수까지 함께** 본다. 0줄은 위
  개수 대조에도 걸리지만 원인이 다르므로 따로 적는다.
- `$EXPECTED` 는 `firebase_` · `cloud_` **접두사**로 센다. 이 접두사를 쓰지 않는
  FlutterFire 플러그인을 넣거나, `firebaseSdkVersion` 을 선언하지 않는 `firebase_*`
  플러그인이 생기면 개수가 어긋난다 — 둘 다 **시끄럽게 실패하는 방향**이므로
  그때 필터를 함께 고친다.
- **2줄 이상이면 충돌이다.** 킷이 쓰는 `firebase_core` 4.15.0 은 firebase-ios-sdk 를
  `exact: firebaseSdkVersion` 으로 고정하므로, 값이 갈리면 `exact` ↔ `exact` 충돌로
  **해석 단계에서 즉시 실패**한다.
  - **버전 조건:** 이 `exact` 서술은 현재 세대 기준이다. 옛 FlutterFire
    (`firebase_core` **4.7.0 이하** 실측)는 식별자부터 다르고(`firebase_sdk_version`)
    `from:` 으로 건다 — 위 명령의 `^let firebaseSdkVersion` 패턴이 잡지 못한다.
    - **「충돌하지도 않는다」 는 조건부로만 참이다.** `from: X` 와 `exact: Y` 는
      **`Y >= X` 일 때만** 함께 해석된다. 옛 세대가 새 세대보다 **높은 하한**을
      걸고 있으면(예: `from: 13.0.0` vs `exact: 12.19.0`) 해석이 실패한다 —
      즉 **이 명령이 잡지 못하는 충돌이 존재한다.** 두 세대를 섞게 되면 옛 쪽
      선언을 직접 읽어 값을 비교할 것.
      ```bash
      grep -n -e '^let firebase_sdk_version' -e '^let firebaseSdkVersion' \
        "$(jq -r '.plugins.ios[] | select(.name=="firebase_core") | .path' .flutter-plugins-dependencies)ios/firebase_core/Package.swift"
      ```
      실측(`.pub-cache` 원문) — `firebase_core` **4.7.0** 은
      `let firebase_sdk_version: Version = "12.12.0"` + `from:`,
      **4.15.0** 은 `let firebaseSdkVersion: Version = "12.19.0"` + `exact:` 다.
- ⚠ `grep -h 'firebaseSdkVersion' ~/.pub-cache/…/Package.swift | sort -u` 형태로
  pub-cache 를 직접 훑지 말 것. 패턴이 **선언 줄과 사용 줄 양쪽**에 매칭돼 정상
  트리에서도 2줄이 나오고(정상 상태를 충돌로 오판한다), 해석되지 않은 옛 버전까지
  함께 읽는다.

**최종 판정은 iOS 빌드다.** 위 세 검사는 사전 선별일 뿐이고, 전이 의존성의 하한 문제는
실제 빌드에서만 드러난다.

### ④ SPM 을 지원하지 않는 플러그인을 넣으면 생기는 일

Flutter 는 **에러가 아니라 경고**를 내고 CocoaPods 로 되돌아간다. 빌드 로그의 문구는
다음과 같다.

```
The following plugins do not support Swift Package Manager for ios: <플러그인 이름>
```

이어서 일어나는 일:

1. **`ios/Podfile` 이 조용히 재생성된다** — 그리고 **빌드는 성공할 수도 있다.** 이것이
   이 절이 존재하는 이유다(조용한 실패).
2. 도구가 되돌리는 xcconfig 는 **`ios/Flutter/Debug.xcconfig` · `ios/Flutter/Release.xcconfig`
   두 개뿐**이다. 나머지 flavor xcconfig 9개는 복구되지 않아 **flavor 빌드만 링크 에러**가
   날 수 있다.
3. `test/ios/ios_deployment_target_consistency_test.dart` 의 **`ios/Podfile` 부재 단언이
   red 가 된다** — 이 테스트가 red 면 위 1·2 가 이미 벌어진 것이다.

**대응:** 그 플러그인의 SPM 지원 버전을 찾거나, 넣지 않는다. 재생성된 `ios/Podfile` 을
지우는 것만으로는 원인이 사라지지 않는다 — 다음 해석에서 다시 생긴다.

### ⑤ iOS 최소 배포 타겟을 바꾸려면

| 대상 | 값 | 비고 |
|---|---|---|
| `ios/Runner.xcodeproj/project.pbxproj` 의 `IPHONEOS_DEPLOYMENT_TARGET` | **12개** (현재 전부 15.6) | **유일한 진실원.** 12 build configuration 각각에 하나씩 있다 |

- Xcode 의 **PROJECT > Runner > Build Settings > iOS Deployment Target** 을 한 번 바꾸면
  12개가 함께 바뀐다. 손으로 고칠 때는 12개를 **전부 같은 값**으로 맞춘다 —
  `test/ios/ios_deployment_target_consistency_test.dart` 가 「12개가 전부 같은 값」 을
  강제한다.
- ⚠ **하한은 15.0 이다 — 그 아래로는 내릴 수 없다.** 같은 test 가 「12개 일치」와
  함께 **15.0 미만을 금지**한다(`_minSupportedIosTarget`). 14.0 으로 내리려 하면
  빌드가 아니라 `fvm flutter test` 가 먼저 red 가 된다.
  - 근거는 진실원의 복제가 아니라 **외부 의존이 부과하는 독립 제약**이다 —
    Flutter 3.47 이 지원하는 iOS 최소 버전이자 킷이 고정한 LineSDK 5.17.0 의
    `platforms` 하한이 둘 다 15.0 이다. 그래서 15.6 → 15.7 같은 정상 상향은
    그대로 통과한다.
  - 하한 자체를 올리거나 내리려면 test 의 `_minSupportedIosTarget` 과 이 bullet 을
    **함께** 고친다.
- Flutter 는 **빌드 때마다 이 값을 읽어** 자기가 생성하는 패키지의 `platforms` 를
  끌어올린다. CocoaPods 시절의 `post_install` 하한 보정 루프 같은 장치는 필요 없다.
- 의존 SDK 의 하한보다 **낮게** 내리면 SPM 이 빌드를 막는다(③ (나)).

### ⑥ 흔한 실수

전환(Phase 16.3) 실행 중 **실제로 겪은** 증상과, 그 과정에서 **손으로 넣은 패치**의
취급을 적는다.

- **`project.pbxproj` 의 Crashlytics 업로드 단계는 upstream 템플릿에 없는 손패치다.**
  `flutterfire_cli` 1.3.2 가 생성하는 원본은 DerivedData 경로 한 줄을 무조건
  대입하는데, Flutter 는 모든 iOS `xcodebuild` 호출에
  `-clonedSourcePackagesDirPath <project>/build/ios/SourcePackages` 를 붙이므로
  SPM checkout 은 **DerivedData 밑에 없다.** 그래서 킷은 이 단계에 Flutter 경로를
  먼저 보는 **probe 루프**와, 두 후보가 모두 없을 때 probe 한 경로를 찍으며
  `exit 1` 하는 분기를 손으로 넣어 두었다.
  - ⚠ **알려진 제약 — Xcode 를 직접 열어 빌드하면 stale `build/ios/SourcePackages`
    가 우선한다.** probe 순서(Flutter 경로 먼저)는 `fvm flutter build` ·
    `fvm flutter run` 경로에서만 옳다. **Xcode IDE 빌드에는
    `-clonedSourcePackagesDirPath` 가 붙지 않아** 권위 있는 checkout 은 DerivedData
    쪽인데, 직전 `flutter build` 가 남긴 **오래된** `build/ios/SourcePackages` 가
    있으면 후보 1이 먼저 히트해 **실제로 링크된 SDK 와 다른 버전의 업로드
    스크립트**가 쓰인다. 두 경로 모두 gitignored 빌드 산출물이라 버전이 갈라지는 것은
    흔한 상태다. `exit 1` 분기는 「둘 다 없음」만 막고 이 경우는 막지 못한다.
    - **순서를 자동으로 뒤집지 않는 이유:** 두 호출을 구분하는 build setting 이
      없다. `BUILD_DIR` 은 archive 가 아닐 때만 Flutter 가 덮어쓰고
      (`flutter_tools/lib/src/ios/mac.dart:426-427`), `-clonedSourcePackagesDirPath`
      는 archive 를 포함한 **모든** 호출에 붙는다(`:333-338` →
      `xcodeproj.dart:214-228`). 「DerivedData 쪽 checkout 이 존재하면 그쪽 우선」
      같은 조건은 Xcode 를 한 번이라도 연 머신에서 **`flutter build` 를 거꾸로
      망가뜨린다** — 같은 결함을 방향만 바꿔 옮기는 셈이다.
    - **대신 어느 후보를 골랐는지 빌드 로그에 남긴다.** 이 단계는
      `note: Crashlytics upload script = <경로>` 를 출력한다. Xcode 에서 직접 빌드한
      뒤 심볼이 엉뚱해 보이면 이 줄의 경로를 확인하고, `build/ios/SourcePackages` 를
      가리키고 있다면 그 디렉터리를 지운 뒤 다시 빌드한다(다음 `flutter build` 가
      다시 받는다).
  - **수동으로 `fff configure` 를 돌리면 이 build phase 가 upstream 모양으로
    재생성되어 패치가 조용히 사라진다.** 돌린 뒤에는 이 build phase 의 diff 를
    반드시 확인하고 복원할 것. `scripts/firebase-configure.sh` 경로는 이 파일을
    스냅샷·복원하므로 안전하다.
  - 회귀 가드: `test/ios/spm_policy_test.dart` 의 `T-16.3-SPM-01` · `T-16.3-SPM-02`
    가 red 면 패치가 사라진 것이다.
  - 빌드 로그에 `error: firebase-ios-sdk Crashlytics/run not found. Probed: …` 이
    찍히면 두 후보 경로가 모두 없다는 뜻이다. Xcode 의 build location 을
    custom/relative 로 바꿔 `BUILD_ROOT` 에 `DerivedData` 문자열이 없는 머신에서
    일어난다 — 한 번 `fvm flutter build ios` 를 돌려 `build/ios/SourcePackages` 를
    채우거나, build location 을 기본값으로 되돌린다.
- **SDK 버전을 고친 뒤 첫 빌드가 헤더 불일치로 실패한다** — 에러는
  `A precompiled file has been changed since last built. Please run "flutter clean"` 이고
  직전 줄이 `File '…/FBSDKCoreKit.framework/Headers/….h' has been modified since the module
  file '…/SwiftExplicitPrecompiledModules/….pcm' was built` 다. Xcode 의 explicit module
  캐시(`.pcm`)가 **옛 버전 헤더로** 만들어져 있어서 그렇다.
  - 도구가 권하는 `flutter clean` 을 그대로 따르지 말고 **에러가 지목한 그 프로젝트의
    DerivedData 디렉터리 하나만** 지운다. `flutter clean` 은 `build/ios/SourcePackages`
    (수백 MB)까지 함께 날린다. checkout 은 DerivedData 밑에 없다 — Flutter 가
    `-clonedSourcePackagesDirPath build/ios/SourcePackages` 를 붙이기 때문이다.
  - 근거: `.planning/phases/16.3-ios-cocoapods-to-spm-migration/16.3-02-SUMMARY.md`
    (Deviations 1) · `artifacts/BUILD-GATE-EVIDENCE.md` `## Stage A`.
- **`Xcode build done` 은 성공 마커가 아니다** — `** BUILD FAILED **` 로 끝난 로그에도
  `Xcode build done. 84.1s` 가 찍힌다(Flutter 가 경과 시간 status 를 성패와 무관하게
  닫는다). 빌드 성패는 **`✓ Built` 와 종료 코드**로 판정한다.
  - 근거: `.planning/phases/16.3-ios-cocoapods-to-spm-migration/16.3-01-SUMMARY.md`
    (후속 plan 이월 2).

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

| 2026-09-11 | quick 260911-twn | `ios/config/dev/GoogleService-Info.plist` 를 stg/prod 와 동일한 placeholder 로 전환 — 이로써 iOS plist 3 flavor 가 전부 placeholder tracked 가 되고, 개발자의 실제 dev plist 는 `./scripts/firebase-configure.sh dev` 가 만드는 로컬 전용 skip-worktree 사본으로만 남는다. 「Git Hooks 활성화」 절에 hook 가드 4 건 목록 표 신규 + 「흔한 실수」 에 iOS plist 항목 1 건 add-only. pre-commit 가드 3 (iOS plist placeholder 값 검사) 추가로 quick 260911-spw D-08 의 iOS 보류가 해소됐고, placeholder 회귀 가드 test 는 읽기 출처를 워킹트리 → 커밋된 내용 (`git show HEAD:<path>`) 으로 옮겨 로컬 파일이 실 값인 개발자 머신에서도 오탐 없이 통과한다. dev iOS API 키는 2026-09-11 에 회전되어 history 에 남은 구 키는 이미 폐기 상태다. |

| 2026-09-11 | quick 260911-w9w | `scripts/firebase-configure.sh` 가 `--ios-build-config=Debug-<flavor>` 를 항상 전달하도록 해 비대화형(비-TTY) 셸에서 CLI 의 "build configuration vs target" 선택 프롬프트로 멈추던 hang 을 해소 — `--yes` 는 덮어쓰기 확인만 처리하므로 이 프롬프트를 막지 못한다. 값 3종(`Debug-dev` / `Debug-stg` / `Debug-prod`)은 `ios/Runner.xcodeproj` 에 실재한다. 이어서 CLI 가 그 값을 ruby `xcodeproj` gem 으로 검증하므로, gem 이 없으면 flutterfire 호출 **전에** 스크립트가 exit 1 하고 한국어 해결 안내를 출력하는 fail-fast 전제조건 검사를 추가 (산출물 3종 변경 0 · skip-worktree 플래그 변화 0, `DRY_RUN=1` 경로는 검사를 건너뛴다). README 에 「전제 2」 문단 + Quick Start 3단계 주석 + 수동 `fff configure` 스니펫 비대화형화(`--ios-out` · `--ios-build-config` 동반), 「흔한 실수」 에 항목 1 건 add-only. 회귀 가드 test 3 건은 header 주석이 아니라 **실행 라인**만 보고 두 계약(플래그 전달 · 전제조건 검사 위치)을 단언한다. |

| 2026-09-11 | quick 260911-x9x | `./scripts/firebase-configure.sh <flavor>` 의 FlutterFire CLI 부수효과를 스크립트가 자동 복원하도록 변경 — live run 실측 결과 `--ios-build-config` 을 주면 CLI 가 `ios/Runner.xcodeproj/project.pbxproj` 에 중복 `bundle-service-file` 실행 스크립트 단계를 추가하고, 기존 `upload-crashlytics-symbols` 단계의 인자를 `--default-config=default` 에서 `--build-configuration=${CONFIGURATION}` 으로 바꾼다. `firebase.json` 에는 `Debug-<flavor>` 한 개만 등록되므로 후자는 나머지 **8/9 configuration 의 iOS 빌드**를 `FirebaseJsonException` 으로 깨뜨린다 (진짜 손상). `firebase.json` 자체도 1줄로 재작성된다. 스크립트는 두 파일을 flutterfire 호출 직전 `mktemp` 디렉터리에 스냅샷해 두고 호출 후(실패 경로는 EXIT trap) 스냅샷 **파일 복사**로 되돌린다 — `git checkout` 을 쓰지 않는 이유는 개발자의 미커밋 pbxproj 편집까지 날리기 때문이다. 복원 함수는 `local rc=$?` / `return "$rc"` 로 원래 종료 코드를 보존하고 임시 디렉터리를 성공·실패 양쪽에서 정리한다. 또 flutterfire 가 생성한 dart options 는 포맷이 적용돼 있지 않아 `fvm dart format --set-exit-if-changed lib test` 를 rc=1 로 만들므로 스크립트가 산출물에 `fvm dart format` 을 적용한다. `DRY_RUN=1` 경로는 스냅샷·복원·포맷을 전부 건너뛴다 (flutterfire 미호출 = 변형 원인 없음). header ⚠ 경고 문구를 추측에서 실측으로 교체하고 회귀 가드 test 를 4건 추가(3 → 7건), 직전 260911-w9w 가 남긴 미검증 deferred 2건(pbxproj 부수효과 실측 · 비대화형 hang 해소 end-to-end 실증)을 함께 종결. |

| 2026-09-12 | quick 260912-gam | `## Design System — 디자인 토큰 커스터마이징 (Phase 3)` 단락 신규 — 2026-09-12 Phase 3 code review fix 12건 (`03-REVIEW-FIX.md`) 으로 확정된 공개 계약을 사용자 관점으로 문서화. 6개 내용: (1) 개요 (ThemeExtension 3종 · `AppTheme.light()`/`dark()` 조립 · `lib/app.dart:53-54` 호출부 · `ThemeX` 다섯 getter 와 폴백 표) / (2) 시드 컬러 교체 (`AppTheme.seedColor` = `Colors.deepPurple`, 소스 수정 없는 주입 경로 `light({Color seedColor})`/`dark({Color seedColor})`, 라이트·다크 동일 시드 의무) / (3) 타이포그래피 계약 — 등록 extension 이 `AppTypography.empty` (전 15 필드 빈 `TextStyle`) 로 바뀌어 `Theme.of(context).extension<AppTypography>()` 직접 읽기가 빈 스타일을 돌려주므로 `context.appTypography` 가 유일한 경로 + ko/ja dense 기하 자동 반영 목적 + 폰트 교체는 `ThemeData(fontFamily:)` 경로 + 부분 override 코드 블록과 `copyWith(extensions:)` map 통째 교체 경고 / (4) 시맨틱 컬러 6종 · 간격 4 의 배수 7단계 (4/8/12/16/24/32/48) + 전 필드 `==`/`hashCode` 구현으로 `AppTheme.light() == AppTheme.light()` 성립 (리빌드마다 `AnimatedTheme` 200ms 보간 재시작이 사라짐) + 미등록 테마 폴백 / (5) breakpoint 3단계 (compact 280~360 · medium 360~600 · expanded 600~674, 하한 포함 상한 배타 + 양끝 포화) 와 `maxWidth` 오용 경고 · `LayoutBuilder` + `AppBreakpoint.fromWidth(constraints.maxWidth)` 지역 제약 경로 / (6) `BrandFocusWrapper` (2026-09-12 `focus_wrapper.dart` 에서 개명) — Tab 1회당 버튼 1개 · outline 표시 조건 AND (`FocusHighlightMode.traditional`) · 외관 hardcode (2dp border / 2dp offset / `borderRadius + 4`) · 사방 4dp 총 8dp 잠식 경고 · a11y focus 위임 · 실 단말 UAT 체크 3항목. 회귀 가드 11행 매트릭스 (인용 group 은 전부 실재 확인) + Pitfall 5종. 목차 16 항목으로 확장. |
| 2026-09-14 | quick-260914-0ag | `### App Check debug provider 등록 절차` 절에 2덩어리 보강 — (1) **재발급 함정**: `adb shell pm clear <applicationId>` 가 `shared_prefs/com.google.firebase.appcheck.debug.store.*.xml` 을 함께 지워 디버그 시크릿이 새로 발급되고 허용 목록 미등재로 App Check 호출이 전부 실패한다 (시크릿은 앱 재기동에는 불변, `pm clear`/재설치 시에만 변경 — 실측). 기존 4단계의 「재설치 시 재등록 필요」 되풀이 변종이며 증상이 `unauthenticated` 라 reauth 실패로 오진하기 쉬움을 경고. (2) **Console 없는 API 등록 절차**: `gcloud auth print-access-token` Bearer + `POST https://firebaseappcheck.googleapis.com/v1/projects/<project>/apps/<appId>/debugTokens` + `x-goog-user-project` 헤더 + `{"displayName":..,"token":"<debug secret>"}` 본문, `<appId>` 는 debug store 파일명 base64 디코드로 획득, 토큰 누적 부작용과 정리가 별건임 명시. 전부 일반형 placeholder 만 사용 (T-16-16-01 PII 정책 준수). |
| 2026-09-16 | quick 260916-hd6 | `## ATT (App Tracking Transparency) 와 iOS Facebook 로그인 — 앱 책임 영역` 단락 신규 — ATT 는 스타터 킷 범위 밖 = 앱 책임(FU-f, 사용자 승인 2026-09-16)이지만 ATT 유무가 iOS Facebook 로그인 동작을 바꾸므로 경계와 귀결을 문서화. 내용: 킷 보장/비보장 경계 + ATT 미요청(기본값)/허용/거부 × iOS/Android 동작 표(Limited = OIDC credential · photoURL 미갱신 · 앱 전환 없음 / Classic = Graph API 프로필 사진) + 출처 3분할(Meta·Firebase 공식 verbatim 인용 / `auth_repository.dart` 실측 anchor / 미검증 항목) + 추적하는 앱의 의무 5항(ATT 요청 · `NSUserTrackingUsageDescription` · SDK 설정 · 요청 순서 · App Store 개인정보 라벨) + IDFA 실태(`GoogleAppMeasurement/Default` 12.12.0 은 `IdentitySupport` 포함이나 ATT 미요청이라 실제 수집 0) + Pitfall 5종. 「ATT 미허용 → Limited 강제」 인과는 공식 문장 미확보 상태이며 SDK 소스 실측이 유일 근거임을 절 안에 명시. ATT 허용 상태 실기기 검증 0건. 목차 17 항목으로 확장. |
| 2026-09-20 | quick 260920-4h7 | 「정적 분석 — woody_lints · riverpod_lint」 단락 신규 — woody_lints 1.3.0 채택으로 riverpod_lint 가 최상위 `plugins:` 로 처음 실제 실행됨(옛 `analyzer: plugins:` 선언은 riverpod_lint 3.x 를 로드하지 않았다). 확인 명령(`fvm dart analyze` 기준 — Flutter 3.47.5 의 `flutter analyze` 는 plugin 진단 미표시) · plugin 해석 위치(`~/.dartServer/.plugin_manager`)와 Analysis Server 재시작 · 네임스페이스 ignore 문법(`// ignore: riverpod_lint/<rule>`, plain 형식 무효, `///` 블록 위 배치) · 테스트 작성 규칙 2종(ProviderScope 는 `pumpWidget` 직접 인자 · fake Notifier 카운터는 외부 recorder) · 현재 lib 억제 3건 표(후속 todo `2026-09-20-riverpod-lint-lib-refactor`). 목차 18 항목으로 확장. |

---
| 2026-09-20 | quick 260920-b28 | 「정적 분석 — woody_lints · riverpod_lint」의 '현재 억제 3건' 표를 '현재 lib 억제 0건' 으로 교체 — 3건 모두 구조로 해소(약관 두 값은 `TermsState` 불변 state + 파생 순수 함수, 인증 변화는 `AuthRefresh` 불변 state + `appRouter` 가 소유하는 `RouterRefreshListenable`). adopter 가 새 Notifier · provider 를 만들 때 따라야 할 규칙 2줄 추가. 후속 todo 참조 제거. |

| 2026-09-20 | quick 260920-23d | 「Flutter SDK 상향 (FVM)」 단락 신규 — Flutter 3.41.9(Dart 3.11.5) → 3.47.5(Dart 3.13.4) 상향 실측을 킷 사용자 관점 절차로 문서화. 10항목: ① 버전 pin 진실원 표(`.fvmrc` 하나 · `fvm use` 가 바꾼 `.vscode/settings.json` 복원 · MCP/Analysis Server 재시작) ② 상향 절차 11단계(같은 HEAD 기준선 선측정 · `pub upgrade` 금지 · **analyze 2종** — 3.47.5 의 `flutter analyze` 는 plugin 진단 미표시) ③ 도구가 자동으로 고치는 tracked 파일 4종 표(`analysis_options.yaml` exclude 7줄 · `android/gradle.properties` migrator flag 4줄 · `ios/Podfile.lock` `Flutter:` checksum 1줄 · `pubspec.lock`) ④ SPM 명시적 off(`flutter: config: enable-swift-package-manager: false`, 3.44+ 기본 on · pubspec 이 전역보다 우선 · 옛 키는 manifest 오류 · **SDK 전환 전 선편집** · 실효 증거 3종 · 향후 금지 예고) ⑤ Android AGP 8.11.1 · KGP 2.2.20 · Gradle 8.14 가 오류 하한과 동일(경고 3건 정상) ⑥ iOS 요구치(deployment 15.0 · Xcode 27 핫픽스가 3.47.4/3.47.5 · `iproxy` x86_64 → Rosetta · 실기기 USB 필수) ⑦ `PODFILE CHECKSUM` = Podfile 내용 SHA1 이라 주석만 고쳐도 lock 동반 커밋 필요(`pod` 직접 호출 금지) ⑧ golden 은 기준선 green 확인 → 시각 확인 → 실패 파일만 `--update-goldens`(`_ios` 는 gitignore) ⑨ `environment: sdk` 하한 상향은 별개 작업(language-versioned 포맷 변경 대량 유입) ⑩ 이번 상향 결과 한 줄. 목차 19 항목으로 확장. |

| 2026-09-20 | 16.2-05 | Naver Login 절을 플러그인 교체(naver_login_flutter 4.0.0 · 정확 버전 고정) 기준으로 갱신 — 키를 채우는 곳이 runtime 초기화에서 native 두 곳(Android 는 config json → gradle string resource, iOS 는 xcconfig 3변수 → Info.plist 변수 치환)으로 바뀐 절차, Client Secret 추출 가능 경고를 2단계로 이관, placeholder 상태에서도 3 flavor 빌드 · 기동이 된다는 계약과 확인 스크립트, 클라이언트 프로필 조회와 개인정보 범위, 구 SDK 잔존 토큰 사실 기록, Pitfall 을 Phase 13 · 16.2 통합 18항으로 개정(iOS 취소 표면 · 1-tap 미복귀 wedge 미검증 · 토큰 보간 · 프로필 실패 · plist 키 부재 · meta-data 참조 · 미설치 종단 오류 · 네이티브 로깅). Initial Setup 키 표의 naver 3행 + appName 행 비고 갱신, iOS xcconfig 변수 목록에 NAVER_CLIENT_ID · NAVER_CLIENT_SECRET 추가, stg/prod 등록 절차에 prod xcconfig 2변수 추가, SPM 미지원 경고 서술을 교체 후 실측(경고 0건)으로 정정. |

| 2026-09-22 | 16.3 | `## iOS 의존성 관리 (SPM)` 절 신규(①~⑥ — SPM 입문 + CocoaPods ↔ SPM 대응표 · 두 tracked `Package.resolved` 고정과 peeled sha 상향 절차 + LINE 5.17.0 경고 · 새 플러그인 사전 확인 3단계 · SPM 미지원 플러그인의 조용한 CocoaPods fallback 증상 · 배포 타겟 진실원 = pbxproj `IPHONEOS_DEPLOYMENT_TARGET` 12개 · ⑥ = 손패치 취급 1건 + 전환 중 실제로 겪은 증상 2건) + CocoaPods 전제 서술 6곳을 현재형으로 재작성 — firebase-configure 함정 bullet 에 「주체는 flutterfire CLI 의 ruby gem」 조건절, IDFA 근거를 `Podfile.lock` 에서 `firebase_analytics` 의 `Package.swift`(기본 product `FirebaseAnalytics` · 끄는 법 `FIREBASE_ANALYTICS_WITHOUT_ADID`, 킷에서 시도 0건 유지)로 교체, 「Flutter SDK 상향 (FVM)」 의 ② 2번 · ③ 표(`ios/Podfile.lock` 행 삭제 + 경고 문장 교체) · ④(「명시적으로 끈다」 → 「기본값(on)을 그대로 쓴다」) · ⑥(CocoaPods 불요 + `flutter doctor` 표시 유지) 수정, ⑦ `PODFILE CHECKSUM` 절 삭제와 ⑧⑨⑩ → ⑦⑧⑨ 재번호. 목차 20 항목으로 확장. 근거: `.planning/phases/16.3-ios-cocoapods-to-spm-migration/`. |

| 2026-09-22 | 16.3-REVIEW-FIX | 증분 코드 리뷰 2회차 지적 11건(Warning 4 · Info 7) 반영 — 「iOS 의존성 관리 (SPM)」 절의 **검증력** 보강이 주제다. ② 상향 절차 4번: checkout 디렉터리 규칙을 「URL 마지막 경로 요소」 → 「마지막 경로 요소에서 **`.git` 접미사를 뗀 이름**」 으로 정정(핀 20개 중 16개의 `location` 이 `.git` 으로 끝나 규칙대로 하면 `No such file or directory` — 재현 명령 병기, 규칙 성립을 실제 checkout 20개와 `diff` 로 전수 확인) + identity 불일치 6건을 별개 사실로 분리. ③(다): 합격 기준을 「출력 1줄」 단독에서 「1줄 **AND** 맨 앞 개수 = `$EXPECTED`」 로 교체 — 두 경로만 탐색해 조용히 건너뛰는 구조 때문에 **표본 부분 누락에 공허하게 참**이었다(8개 중 3개만 읽혀도 1줄). 기대 개수는 `grep -cE` 가 아니라 **jq 필터**로 센다(ugrep 괄호 `-E` 위음성 + 주석 오염 배제). 성립 불가능 조항 「맨 앞 개수가 0 이 아니다」(`uniq -c` 는 개수 0 을 출력할 수 없다) 제거. 「옛 세대는 충돌하지도 않는다」 단정을 조건부로 한정(`from: X` 와 `exact: Y` 는 `Y >= X` 일 때만 해석 — 반례 존재, 확인 명령 추가). ⑤: **하한 15.0 금지선**을 명시(test 가 12개 일치와 함께 강제하므로 14.0 으로 내리면 빌드 전에 `flutter test` 가 red) — `_minSupportedIosTarget` doc comment 와의 양방향 링크 복구. ⑥: **Xcode IDE 빌드에서 stale `build/ios/SourcePackages` 가 우선한다**는 알려진 제약 신규(probe 순서를 자동으로 뒤집지 않는 근거를 flutter_tools 라인 인용으로 명시 — `BUILD_DIR` 은 archive 가 아닐 때만 덮어써지고 `-clonedSourcePackagesDirPath` 는 모든 호출에 붙는다) + build phase 가 고른 후보를 `note:` 로 로깅. IDFA 절: 근거 재확인 명령을 하드코딩 `sed -n '13,16p'` 에서 **내용 앵커 `grep`** 으로 교체(상향으로 줄이 밀리면 목적과 수단이 서로를 무효화했다) + 「위 인용 블록」 방향 오기를 「아래 … 블록」 + 식별 문자열로 정정. 회귀 가드 쪽은 `test/helpers/source_text.dart` 신규 추출(헬퍼 3종의 3중 복제 해소 · public 최상위 심볼 0), SPM 손패치 단언을 **`shellScript` 본문으로 범위 한정**(전체 텍스트 검사라 shellScript 가 비어도 통과하던 구멍 폐쇄), 배포 타겟 비교를 `double.parse` 에서 **성분 단위 비교**로 교체(`15.6.1` 예외사 · `15.10` → `15.1` 오독 제거). 모든 문서 명령은 블록에서 그대로 추출해 실행한 출력과 대조했고, 가드 변경은 fixture 로 red 재현을 확인했다. 근거: `.planning/phases/16.3-ios-cocoapods-to-spm-migration/16.3-REVIEW.md`(round 2) · `16.3-REVIEW-FIX.md`. |
| 2026-09-24 | 16.5-07 | Naver Login 절을 킷 소유 웹 흐름(Phase 16.5) 기준으로 갱신 — 도입 문단(설치 단말 1-tap / 미설치 단말 킷 웹 + `naverWebCustomToken` 서버 교환 · 호스트 네이티브 판정 · 판정 실패 = 웹), 3단계 iOS URL Scheme 예시를 소문자 영숫자로 정정(웹 콜백 scheme 겸용), 6단계 「Dart 가 읽지 않는다」 를 두 소비처(SDK 1-tap · 킷 웹) 서술로 교체, 7단계에 iOS 웹 경로 추가 설정 0 · 설치 판정 Swift 1파일 메모, 8단계를 secret 2종(`NAVER_CLIENT_SECRET` 사용처 1 · `NAVER_CLIENT_ID` 신규) + 「같은 값 2본」(D-19 — secret 은닉이 아니라 RFC 8252 정합 + 착지) 으로 재작성, **9단계 신설**(웹 경로 Callback URL · redirect_uri 확인 — 브라우저 probe 절차 · 채택 결과 후보 A · scheme 파생 규칙과 커스터마이징 표 · Android `CallbackActivity` · Hosting bounce 대안(미구현) · `naverClientId` 2경로 일치 · 사용자가 보는 것 · Naver 제거 절차) 와 기존 9·10단계 → 10·11단계 재번호(배포 대상에 `naverWebCustomToken` 추가 · 웹 경로 확인법). Pitfall 11 의 16.4 계수 문장 · Pitfall 17 을 정정하고 **Pitfall 19 를 「킷 소유 웹 흐름으로 우회」 로 교체** — 레버 2(재개방 계수) 서술 삭제, 여섯 로그 접두어(앱 2 + 웹 4) + grep 앵커 규칙 + Android 앱 전면 복귀 취소 주의. Initial Setup 키 표 naver 3행 · stg/prod 등록 절차(scheme 예시 · `NAVER_CLIENT_ID` secret) · IdP 프로필 동기화 배포 목록 동반 갱신. 근거: `.planning/phases/16.5-naver-web-oauth-kit-owned-flow/`. |
| 2026-09-24 | 16.5-09 | G-16.5-2: 9단계 (5) Android 콜백 수신을 킷 relay `WebAuthCallbackActivity` 로 교체 — 라이브러리 콜백 Activity 미선언 이유(Auth Tab 미지원 브라우저 Custom Tab fallback 에서 탭 미닫힘 · 빈 affinity 로 새 task · 상류 #158 OPEN · 버전 상향 무효) · relay 동작 · 기각안 2개(빈 affinity 제거 = StrandHogg · 인증 관리 Activity singleTask override) · Chrome Auth Tab 은 relay 미경유 · `flutter_web_auth_2` 상향 시 확인 · 실측 상태(SM-S942N Samsung Internet 30 탭 닫힘 · Chrome Auth Tab · 1-tap 회귀 통과) · Auth Tab 미지원 브라우저 재현 레시피. 옛 「Custom Tab 경로 실기기 기동 미관측」 괄호 서술 삭제, Naver 제거 절차에 relay Kotlin 파일 · manifest relay 블록 반영, Pitfall 19 에 검은 화면 진단 bullet(relay · `flg=0x34000000`) 추가. 근거: `.planning/phases/16.5-naver-web-oauth-kit-owned-flow/16.5-UAT-RESULT.md` `## 8.` |
| 2026-09-24 | 16.5-REVIEW-FIX (2회차) | 증분 리뷰 2회차 Info 반영 — IN-01: 9단계 (5) 「relay 가 하는 일」 을 대기 호출 **전달함**(`NEW_TASK | CLEAR_TOP | SINGLE_TOP` · `flg=0x34000000`) / **대기 호출 없음**(`NEW_TASK | SINGLE_TOP` · `flg=0x30000000` — 외부 기동이 MainActivity 위 Kakao · Firebase IdP · NAVER 1-tap bridge 등을 걷지 않게) 두 갈래로 나누고 대가(프로세스 종료 뒤 콜백은 tab 을 닫지 못함)를 명시, Pitfall 19 검은 화면 진단에 `flg=0x30000000` 판정 추가. IN-04: 10단계 배포 확인에 NAVER 호출 3개의 시간 예산이 본문 읽기까지 포함한 상한이라는 점과 timeout fingerprint `TimeoutError`(이전 배포본 `AbortError`) 해석 bullet 추가. IN-05: Pitfall 19 검은 화면 진단을 세 갈래로 정리하고 BAL/ASM 차단 갈래(START 줄 뒤 `W ActivityTaskManager: ` 경고 — START 가 차단 판정보다 먼저 찍힘)를 추가, grep 앵커를 `I ActivityTaskManager: START` 형태로 정정. 근거: `.planning/phases/16.5-naver-web-oauth-kit-owned-flow/16.5-REVIEW.md`(2회차) · `16.5-REVIEW-FIX.md`. |
| 2026-09-24 | quick 260924-k61 | 검증 규칙 요약 표에 0 채움 phase 참조 PASS 행 추가 — check_phase_refs.sh 가 ROADMAP 헤딩 · 코드 참조 양쪽 번호의 성분별 선행 0 을 떼고 고정 문자열 정확 일치로 비교 |
| 2026-09-24 | quick 260924-lw2 | 웹 경로 서버 토큰 폐기 제거(16.5 D-15 번복) — 8단계 secret 표의 사용처에서 폐기 삭제, 9단계 「사용자가 보는 것」 을 동의 화면은 연결이 없을 때만 뜬다 · 폐기하지 않는 이유(NAVER 토큰 삭제 요청 = SDK 연동 해제) · 잔존 노출(access_token 은 서버 메모리 한정 · `expires_in` 까지 유효) · `expiresInSec` 확인법으로 교체, 10단계 배포 대상 설명에서 폐기 삭제 · `naver_web_*` 이벤트 3종 + `expiresInSec` 설명 · 폐기 판정 bullet 과 폐기 실패 이벤트 삭제 · NAVER 호출 예산 2개(합 10s). 근거: `.planning/phases/16.5-naver-web-oauth-kit-owned-flow/16.5-CONTEXT.md` 「D-15 번복」. |
| 2026-09-25 | 16.6-10 | Custom Token provider 1종 제거(Phase 16.6)에 따른 정리 — 해당 provider 절 삭제 · 절 밖 서술을 남은 provider(Kakao / Naver / LINE) 기준으로 재작성(Initial Setup 참조 · relay 서술 · IdP 동기화 적용 범위 · Kill Switch 인용 · 계정 연결 분기 「Custom Token 3 provider」 · 약관 서버 기록 mirror 위치를 provider 3종 + Naver 공용 helper `naver_profile_to_custom_token.ts` 로 · 회원탈퇴 TODO · Brand Asset 6 provider · 디렉터리 트리 · 출처 표 · sentinel 이력 · enum 예시 주석) · 「Custom Token Provider 추가 가이드 (stub)」 제목 · 본문 중립화(검증 방식 표 행 삭제) · **「Custom Token Provider 제거 가이드 (Phase 16.6)」 절 신설**(비활성 레버 2 · 의존 역순 체크리스트 ①~⑧ + 게이트 · dev 배포 정리 순서 ①~⑦ — secret 은 read-only 판정 뒤 `--force` 1회 · 실측 함정 5) · 목차 항목 7 stale 앵커 정정 + 제거 절 항목 8 삽입(21 항목) · SPM 고정값 표 `appauth-ios` 비고를 전이 의존 사유로, `googlesignin-ios` 비고의 상향 서술 정정 |
| 2026-09-25 | quick 260925-r1f | 「약관 동의 서버 기록 (Custom Token provider — Phase 16 G-16-A9-1)」 절의 stale 문단 재작성 — 옛 문단(2026-09-07 `518902f9`)이 37분 뒤 `6e24873a`(WR-01) 의 `isNewUser` 게이트를 반영하지 않아 서버 mirror 동작 · 재동의 시각 갱신 주체 · 권장 커스터마이징 방향이 코드와 반대였다. 「기본 동작(3 경로 `if (termsSnapshot && isNewUser)` · 재동의는 클라이언트 `force: true`)」 · 「잔여 위험(첫 등록 스냅샷 부재 · 검증 실패 · mirror 실패 후 재시도 → 클라이언트 재동의 게이트가 채울 때까지 `termsAccepted` 부재, 기록 시각은 재동의 시각)」 · 「커스터마이징(매 로그인 반영은 `&& isNewUser` 제거 + 다중 사용자 기기 덮어쓰기 대가 + Jest C3 갱신)」 3 문단으로 교체, 「확인 방법」 (b) 첫 등록 기준 + (c) 추가 + 이벤트 식별 규칙 정정(`_mirrored` 이벤트는 세 경우 모두 없음 · (c) 는 `_mirror_failed` · (a)/(b) 는 `providerLinkedAt`), 「mirror 실패」 문단을 신규 등록 요청 한정 + 재시도 결과로 정밀화. 근거: Phase 16.6 plan 10 SUMMARY 「Issues Encountered」 첫 bullet. |
| 2026-09-25 | quick 260925-u0f | 「약관 동의 서버 기록 (Custom Token provider — Phase 16 G-16-A9-1)」 절 후속 정정 2건 — (1) 「백필 정책」 문단의 과장 정정: 이 수정 이전 가입자의 서버 기록이 영구 부재라는 서술을, 기기 로컬 값은 정식 사용자의 약관 게이트를 통과시키지 못해 다음 콜드 스타트 · 로그인에서 「잔여 위험」 의 클라이언트 재동의 게이트가 재동의 시각으로 채운다는 사실로 교체(adopter 결정은 돌아오지 않은 사용자의 처리와 재동의 시각 인정 여부 · 「사용자 커스터마이징 포인트」 참조 방향 위→아래 정정 · 자동 백필 없음 · 1회성 관리자 작업 · 법무 자문 의무는 유지) · (2) 「커스터마이징」 문단에 반대 방향 한 줄 추가: 최초 동의 시각을 불변 audit 으로 남겨야 하면 검증된 스냅샷을 `resolveIdentity` 신규 등록 transaction 의 `users/{uid}` merge write 에 함께 쓰는 방법(신원 등록과 원자적 · 사후 mirror 블록 제거 · `_mirror_failed` 이벤트 소멸로 「확인 방법」 (c) 흡수 · 킷 기본값 아님). 근거: `.planning/quick/260925-r1f-fix-stale-terms-mirror-manual-paragraph/260925-r1f-SUMMARY.md` 「Deferred / 관찰」. |
| 2026-09-26 | 16.7-09 | Phase 16.7 가입 수단 · 연결된 계정 분리 반영 — 「가입 수단 기록 (Phase 16.7)」 절 신설(「약관 동의 서버 기록」 절 뒤: 필드 `users/{uid}.signUpProviderId` · 값 형식 7종 · 기록 지점 2곳(native = 클라이언트 `SignUpMethodRecorder` 콜백 · call site 4곳 · `unawaited` · CT = `resolveIdentity` 신규 등록 tx) · 「가입」 정의 표(D-14) · 약관 mirror 선행 순서(D-19 · D-29) · fallback(D-11 「-」 + 연결 = 전부 · D-12) · 위조 한계(WR-12 · 표시 전용 · 서버 판단 미사용 · Phase 18) · provider 추가/제거 때 할 일 · 확인 방법) · stale 2곳 정정(`linkedProvidersStream` race 절의 옛 카드 이름 → 「가입 수단」 · 「연결된 계정」 카드 + D-11 fallback 표시 · Kakao UAT 4단계 확인 문구 → 「가입 수단: 카카오」 · 「연결된 계정: 없음」) · 「Custom Token Provider 제거 가이드」 3-⑥ 잔존 데이터 계수에 `users.signUpProviderId == <slug>` 추가 |

---

*Last updated: 2026-09-26 — 16.7-09 가입 수단 기록 절 신설 · stale 2곳 정정 · 제거 가이드 3-⑥ 항목 추가*
