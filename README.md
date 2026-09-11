# flutter_starter_kit

Flutter + Firebase 기반 앱을 위한 Starter Kit. 인증 / 다국어 / 디자인 시스템 /
Firebase 설정 보일러플레이트를 제거하고, Feature-First 아키텍처와 코딩 규칙을
프로젝트 시작 시점부터 강제한다.

## Getting Started

**전제:** [FVM](https://fvm.app/) 이 설치되어 있어야 한다. 본 프로젝트는 시스템
Flutter 를 직접 사용하지 않고 항상 `fvm flutter` / `fvm dart` 로 실행한다.

clone 직후 dev flavor 를 띄우기까지 5단계다.

```bash
# 1. clone
git clone <this-repo> && cd flutter_starter_kit

# 2. flavor config 생성 — 실제 키는 gitignored 인 config/dev.json 에만 넣는다.
#    (example 파일에는 절대 실 키를 쓰지 않는다)
cp config/dev.example.json config/dev.json
#    → 에디터로 열어 placeholder 를 본인 값으로 교체.
#      각 키의 출처는 docs/manual.md 의 "Initial Setup" 단락 참조.

# 3. Firebase 설정 파일 생성 — dart options + Android google-services.json +
#    iOS GoogleService-Info.plist 를 한 번에 생성한다.
#    (스크립트 상단의 PROJECT_ID_PREFIX 등 3개 상수를 본인 프로젝트 식별자로
#     먼저 수정할 것)
./scripts/firebase-configure.sh dev

# 4. 의존성 설치 + 코드 생성 (*.g.dart / *.freezed.dart 는 미커밋)
fvm flutter pub get
fvm dart run build_runner build --delete-conflicting-outputs

# 5. 실행
fvm flutter run --flavor dev --dart-define-from-file=config/dev.json
```

### 3단계를 건너뛰면

`lib/core/firebase/firebase_options_{dev,stg,prod}.dart` 는 placeholder 상태로
tracked 되어 있어 **build 와 analyze 는 통과**한다. 다만 런타임에
`initializeFirebase()` 가 `false` 를 반환하여 Firebase 의존 기능(인증, Firestore,
Crashlytics, Remote Config 등)이 전부 비활성화된 채 앱이 실행된다.
`./scripts/firebase-configure.sh dev` 를 실행하면 placeholder 가 실제 옵션으로
교체되고, 스크립트가 해당 파일에 `git update-index --skip-worktree` 를 적용해
실 키가 커밋되지 않도록 막는다.

Android 빌드는 `android/app/src/dev/google-services.json` 도 필요하며, 이 파일
역시 같은 스크립트가 생성한다. dev 는 실 프로젝트 연결용이라 gitignored 이므로
**fresh clone 직후에는 존재하지 않는다** — 3단계를 건너뛰면 `--flavor dev`
Android 빌드는 실패한다.

반면 stg/prod 는 아래 두 placeholder 가 tracked 되어 있어 **`--flavor stg` /
`--flavor prod` Android 빌드는 clone 직후 그대로 통과**한다.

- `android/app/src/stg/google-services.json`
- `android/app/src/prod/google-services.json`

다만 이 값들은 빌드 게이트 통과용 더미이므로, 그 상태로 실행한 앱은 위와
동일하게 `initializeFirebase()` 가 `false` 를 반환하는 미초기화 모드로 뜬다.
**빌드가 된다 ≠ Firebase 가 연결됐다.**

iOS 는 **3 flavor 가 전부 clone 직후 빌드 단계를 통과한다.** Xcode 의
`Copy GoogleService-Info.plist` 빌드 단계는 파일이 없으면
`error: GoogleService-Info.plist not found for flavor` 로 빌드를 중단시키는데,
아래 3종이 모두 placeholder 로 tracked 되어 있어 파일 부재로 실패하지 않는다.

- `ios/config/dev/GoogleService-Info.plist`
- `ios/config/stg/GoogleService-Info.plist`
- `ios/config/prod/GoogleService-Info.plist`

**dev 의 실제 설정 파일 4종 — `lib/core/firebase/firebase_options_dev.dart` ·
`android/app/src/dev/google-services.json` ·
`ios/config/dev/GoogleService-Info.plist` · `ios/Flutter/dev.xcconfig` — 은 전부
로컬 전용이며, repo 에는 placeholder (또는 `*.example.*`) 만 tracked 된다.**
실 연결은 `./scripts/firebase-configure.sh dev` 가 생성하는 로컬 파일로만
이뤄지고, 그 파일들은 skip-worktree 또는 `.gitignore` 로 커밋 대상에서 빠진다.
placeholder 상태로 실행했을 때의 동작은 바로 위 문단과 같다 — 빌드는 되지만
런타임은 미초기화 모드다.

### stg / prod

`./scripts/firebase-configure.sh stg` / `... prod` 로 동일하게 생성한다. 단,
Starter Kit 기본 상태에서는 **dev flavor 만 실제 Firebase 프로젝트에 연결**되어
있으므로, 실행 전 Firebase Console 에서 해당 프로젝트를 먼저 생성해야 한다
(자세한 절차는 아래 "stg/prod flavor 로 fork 하는 경우" 참조).

### 더 읽을 거리

- `docs/manual.md` — 소셜 로그인 provider 별 콘솔 등록 절차, 시크릿 주입, 배포
- [Flutter 공식 문서](https://docs.flutter.dev/)

## Brand Assets

본 Starter Kit 는 5개 공식 소셜 로그인 provider (Apple / Facebook / Google /
Kakao / Naver) 의 공식 brand asset (logo PNG/SVG) 을 `assets/brand/{provider}/`
디렉토리에 동봉한다. 각 자상은 해당 회사의 trademark 이며, 사용 전 반드시
다음 절차를 거쳐야 한다 (Meta brand license verbatim — "Meta's trademarks
are owned by Meta and may only be used as provided in these guidelines or
with Meta's permission").

### 사용 전 의무 검토 (clone 직후 1회)

1. `assets/brand/{apple,facebook,google,kakao,naver}/LICENSE.txt` — 각
   provider 의 라이선스 본문 (verbatim 인용 + 사용자 책임 명시 단락) 을
   숙독한다. 본 파일은 GitHub public repo 의 일부로 자동 복제되지만,
   라이선스 의무 (예: Meta Brand Resource Center 의 사전 동의 절차) 까지
   자동 위임되지 않는다.
2. `assets/brand/{provider}/README.md` — 공식 BI URL / 다운로드 일자 /
   사전 검수 절차 / 미포함 변형 추가 절차 / 자상 freshness 갱신 빈도
   7 단락 모두 확인.
3. `docs/manual.md` 의 `## Brand Asset Management` 단락 — 5 provider
   라이선스 매트릭스 + 사용자 책임 정책 통합 진실원. fork 시점에 반드시
   재검토 의무.

### 비-OAuth 사용 시 추가 검토

OAuth 로그인 버튼 외의 컨텍스트 (예: marketing 자료, prominent 배치,
brand 비교 자료) 로 자상을 재사용할 경우, 각 provider 의 brand center 에
명시된 사용 조건이 OAuth 로그인 버튼 컨텍스트와 다를 수 있다. 별도
허가 / 사전 검수 절차 가능성이 있으므로 사용 직전 공식 가이드라인 재확인
의무.

### 자상 갱신 / 추가

starter-kit 의 자상을 갱신하거나 신규 provider 를 추가할 때는
`docs/manual.md` 의 `## Brand Asset Management` 단락 절차 (1단계 자산
다운로드 → 2단계 사전 검수 → 3단계 commit) 를 따른다. LICENSE.txt +
README.md 가 자상 PNG/SVG 와 동일 디렉토리에 함께 commit 되도록
유지하며, `test/features/auth/presentation/_widgets/docs_compliance_lint_test.dart`
의 회귀 가드 (R12 + Phase 13.2 R4) 가 결락을 RED 로 surface 한다.

## Customization

### Splash 이미지 커스터마이징 (Splash Image Customization)

Splash 이미지는 `assets/images/splash/logo.png` (light) / `logo_dark.png`
(dark) 로 교체한다. 아래 제약을 반드시 지킬 것.

- **최소 해상도 128×128 이상 (PNG, alpha channel 유지).**
  - iOS `actool` 은 `LaunchImage.imageset` 생성 시 `@1x/@2x/@3x` 스케일
    (32/64/96 px) 을 자동 파생한다. 원본이 1×1 인 경우 파생이 0×0 으로 깨져
    Xcode 빌드가 `Distill failed for unknown reasons` 와 함께 실패한다
    (Phase 10 UAT Issue #1).
  - 브랜드 로고 교체 전의 placeholder 도 반드시 128×128 이상 투명 PNG 로 유지할 것.
- **⚠ Starter-Kit placeholder 는 "투명 128×128" 로 커밋되어 있어 앱 실행 시
  눈에 보이지 않는다 (iOS distill 실패만 방지). fork 후 반드시 실제 브랜드
  로고로 교체해야 스플래시 화면에 로고가 표시된다.** (Warning #8)
- **권장 해상도 512×512 (starter 기본값은 128×128 neutral placeholder).**
- Android 12+ 대응: 로고가 128dp 원 프레임 안에 들어가도록 여백을 확보할 것.
- 교체 후 반드시 다음 명령을 실행한다:

  ```bash
  fvm flutter pub get
  fvm dart run flutter_native_splash:create
  ```

- 재생성된 네이티브 파일은 모두 커밋한다 (재현성 확보):
  - `android/app/src/main/res/drawable*/launch_background.xml`
  - `android/app/src/main/res/values*/styles.xml`
  - `ios/Runner/Assets.xcassets/LaunchImage.imageset/`
  - `ios/Runner/Base.lproj/LaunchScreen.storyboard`
- Android 12+ 의 OS SplashScreen API (128dp 원 프레임) 는
  `flutter_native_splash.yaml` 의 `android_12:` 블록에서 관리한다.
  상세 옵션은 `flutter_native_splash` 공식 README 참조.

#### iOS LaunchImage 커스터마이징 (iOS LaunchImage Customization)

- `flutter_native_splash:create` 는 `ios/Runner/Assets.xcassets/LaunchImage.imageset/`
  의 `LaunchImage.png` / `LaunchImage@2x.png` / `LaunchImage@3x.png`
  (light), `LaunchImageDark.png` / `LaunchImageDark@2x.png` /
  `LaunchImageDark@3x.png` (dark) 6개 파일을 자동 생성한다.
- Xcode 에서 수동으로 이 파일들을 덮어쓰지 말 것 — 다음 번
  `flutter_native_splash:create` 실행 시 덮어써진다. 반드시
  `assets/images/splash/` 원본 + `flutter_native_splash.yaml` 설정을 수정한 뒤
  재생성 명령으로 반영한다.
- `ios/Runner/Base.lproj/LaunchScreen.storyboard` 도 `flutter_native_splash`
  가 관리한다. 배경색, 로고 위치 등 고급 커스터마이징이 필요하면 Storyboard
  수동 편집보다는 `flutter_native_splash.yaml` 옵션 (예: `color`, `color_dark`,
  `ios_content_mode`) 을 먼저 검토한다.
- 자세한 배경은 `assets/images/splash/README.md` 를 참조.

### Firebase Console 활성화 — Crashlytics / Analytics

Starter Kit 는 dev/stg/prod 3-Flavor 구조이고 dev flavor 만 실제 Firebase 프로젝트에
연결돼 있다. SDK 호출 코드 (`lib/core/bootstrap.dart`, `lib/core/crashlytics/`,
`lib/core/analytics/`) 는 모든 flavor 에서 동작하지만, **Firebase Console 의
프로젝트 단위 토글이 OFF 면 Console 도달이 차단된다 (수신 0건).**

#### dev flavor — Crashlytics 활성화 절차 (필수, 최초 1회)

1. [Firebase Console](https://console.firebase.google.com/) → 본인 dev 프로젝트
   선택 → 좌측 메뉴 **Crashlytics** 클릭.
2. 첫 진입 시 "Enable Crashlytics" 안내가 표시되면 → **Enable** 버튼 클릭.
3. 프로젝트 설정 → **Integrations** → Crashlytics 토글이 **ON** 인지 확인.
   - dev 프로젝트는 기본적으로 OFF 상태일 수 있다 (`fetched settings:
     "firebase_crashlytics_enabled": false` 로그가 찍히면 확실히 OFF).
4. (Android only) `android/app/src/main/AndroidManifest.xml` 의
   `firebase_crashlytics_collection_enabled` 메타데이터가 명시적으로 `false`
   설정돼 있지 않은지 확인 (Starter Kit 기본값은 미설정 → SDK 기본 활성화 ON).

#### Crashlytics 동작 확인 (Smoke Test)

1. `fvm flutter run --flavor dev --dart-define-from-file=config/dev.json` 으로
   dev 빌드 실행.
2. Home 화면 우상단 **Dev Tools** → "테스트 에러" 버튼 탭 (release 빌드에서는
   tree-shaken 됨).
3. 5분 이내 Firebase Console > Crashlytics > Dashboard 에서 "Dev Tools test
   error" non-fatal 이벤트 수신 확인.
4. **race_guard_triggered custom key 관측 (Plan 10-14 GC-04 fail-safe):** 만약
   미인증 상태에서 silent Home 진입 race 가 재발하면 `auth_guard.dart:283` 의
   `setCustomKey('race_guard_triggered', 'onboarding_race_v1')` 가 발동한다.
   Crashlytics > Issues 의 임의 이벤트 → Custom keys 탭에서 `race_guard_triggered`
   값이 `onboarding_race_v1` 로 기록됐는지 확인하면 fail-safe 동작 증거가 된다.

#### Analytics DebugView 활성화 (개발 중 권장)

Analytics 이벤트는 일반 보고서에는 24시간 후 반영되지만, DebugView 에서는
즉시 확인할 수 있다. Starter Kit 의 dev flavor 에는 디버그 모드 자동 ON 코드가
없으므로 adb 로 수동 활성화한다.

```bash
# Android 에뮬레이터/실기기 (앱 패키지명은 dev flavor 기준)
adb shell setprop debug.firebase.analytics.app com.slimpumpkin.flutter_starter_kit.dev

# iOS 시뮬레이터/실기기
# Xcode > Product > Scheme > Edit Scheme > Run > Arguments
# Arguments Passed On Launch 에 `-FIRDebugEnabled` 추가
```

활성화 후 Firebase Console > Analytics > **DebugView** 에 실시간 이벤트가
표시된다. 비활성화는 동일 명령에서 패키지명을 `.none.` 으로 지정한다.

#### stg/prod flavor 로 fork 하는 경우 (실 프로젝트 적용 시)

Starter Kit 는 stg/prod 의 `lib/core/firebase/firebase_options_stg.dart` /
`firebase_options_prod.dart` 와 `android/app/src/{stg,prod}/google-services.json`
을 placeholder 로 두고 있다 (dev 만 실제 프로젝트 연결, stg/prod 는 build 통과용
더미 값). 실 프로젝트에서는 다음 절차를 거친다.

1. Firebase Console 에서 stg/prod 프로젝트를 별도 생성 (dev/stg/prod 분리 원칙).
2. `./scripts/firebase-configure.sh stg` 실행 (prod 는 `... prod`). 스크립트가
   dart options + Android `google-services.json` + iOS `GoogleService-Info.plist`
   를 flavor 경로에 맞춰 한 번에 생성한다. Android 산출물은
   `android/app/src/<flavor>/google-services.json` (Gradle flavor source set 경로)
   에 **placeholder 를 덮어쓰는 방식**으로 생성되며, 스크립트는 생성된 산출물 중
   tracked 인 것 전부(dart options · iOS plist · Android json)에
   `git update-index --skip-worktree` 를 적용해 실 키 커밋을 막는다. 스크립트
   상단의 `PROJECT_ID_PREFIX` / `IOS_BUNDLE_ID_PREFIX` /
   `ANDROID_PACKAGE_PREFIX` 3개 상수를 본인 프로젝트 식별자로 먼저 수정할 것.

   > **placeholder 를 의도적으로 수정하려면** 먼저
   > `git update-index --no-skip-worktree <path>` 로 해제한 뒤 커밋하고, 끝나면
   > 다시 `--skip-worktree` 를 걸어 둔다. 해제하지 않으면 수정본이 `git status`
   > 에 아예 나타나지 않는다. 또한 실 키가 든 재생성본을 강제로 staged 하면
   > `scripts/git-hooks/pre-commit` 가드가 커밋을 차단한다
   > (docs/manual.md "Git Hooks 활성화" 참조).
   >
   > 이 skip-worktree 규칙은 stg/prod 산출물만이 아니라 **dev 의 iOS plist
   > (`ios/config/dev/GoogleService-Info.plist`) 에도 동일하게 적용**된다 —
   > dev 역시 repo 에는 placeholder 만 tracked 되고, 개발자의 실 파일은
   > skip-worktree 로 가려진 로컬 사본이다.

   > **prod 는 flavor 접미사가 없다.** `android/app/build.gradle.kts` 의
   > `productFlavors` 에서 dev/stg 만 `applicationIdSuffix` 를 가지므로 prod 의
   > Android package 는 `com.slimpumpkin.flutter_starter_kit` (접미사 없음),
   > iOS bundle 도 `com.slimpumpkin.flutterStarterKit` 이다. 여기에 `.prod` 를
   > 붙이면 Gradle 이 "No matching client found for package name" 으로 실패한다.
   > (Firebase **프로젝트 ID** 는 3개 분리 정책이라 prod 에도 접미사가 붙는다.)

   > 참고 (수동 실행이 필요한 경우): `fff configure --project=<stg-project-id>
   > --out=lib/core/firebase/firebase_options_stg.dart
   > --android-package-name=com.slimpumpkin.flutter_starter_kit.stg
   > --ios-bundle-id=<stg.bundle>
   > --android-out=android/app/src/stg/google-services.json` (`fff` =
   > `fvm dart pub global run flutterfire_cli:flutterfire` alias).
   > `--android-out` 을 생략하면 Android source set 이 아닌 app 루트에 파일이
   > 떨어져 flavor 분리가 깨진다. 또 이 경로로 생성하면 skip-worktree 가
   > 적용되지 않으므로 tracked 산출물마다 직접
   > `git update-index --skip-worktree <path>` 를 실행해야 한다.
3. 위와 동일한 Crashlytics 활성화 절차를 stg/prod 각 프로젝트에 적용.
4. **prod 추가 필수:** Crashlytics > Settings > **dSYM upload (iOS)** 자동화 +
   Android 의 NDK symbol upload (네이티브 크래시가 가독성 있게 deobfuscate
   되도록).

#### 알려진 이슈 — dev flavor "race_guard_triggered" 미수신 (Phase 10 Gap B)

Plan 10-14 Task 5 UAT (2026-04-24) 에서 GC-04 fail-safe redirect 가 정상 발동
했음에도 Console 에서 `race_guard_triggered` custom key 가 미수신되는 현상이
관찰됐다. Run 1 fetched settings 로그상 `firebase_crashlytics_enabled: false`
가 확정 — **Firebase Console 의 Crashlytics 토글이 OFF 였던 것이 원인**이고
SDK 호출 코드 자체는 정상이다. 위 "활성화 절차" 1~3 단계를 수행한 뒤 동일
재현 시나리오로 Console 수신을 확인할 수 있다.
