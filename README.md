# flutter_starter_kit

A new Flutter project.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Learn Flutter](https://docs.flutter.dev/get-started/learn-flutter)
- [Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Flutter learning resources](https://docs.flutter.dev/reference/learning-resources)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.

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
`firebase_options_prod.dart` 를 placeholder 로 두고 있다 (dev 만 실제 프로젝트
연결, stg/prod 는 build 통과용 더미 값). 실 프로젝트에서는 다음 절차를 거친다.

1. Firebase Console 에서 stg/prod 프로젝트를 별도 생성 (dev/stg/prod 분리 원칙).
2. `fff configure --project=<stg-project-id>
   --out=lib/core/firebase/firebase_options_stg.dart
   --android-package-name=com.slimpumpkin.flutter_starter_kit.stg
   --ios-bundle-id=<stg.bundle>` 실행 (`fff` = `fvm dart pub global run
   flutterfire_cli:flutterfire` alias). prod 는 동일 패턴으로 `.prod` suffix.
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
