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
