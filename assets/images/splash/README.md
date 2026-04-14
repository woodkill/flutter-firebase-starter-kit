# Splash 로고 에셋 (Starter Kit Placeholder)

이 디렉토리는 `flutter_native_splash`가 네이티브 스플래시(Android/iOS OS 레벨)를 생성할 때 사용하는 로고 에셋을 담는다. 현재 커밋된 `logo.png`와 `logo_dark.png`는 **1×1 투명 PNG placeholder**이므로 프로젝트에서 반드시 교체해야 한다.

## 프로젝트 교체 체크리스트

1. 브랜드 로고를 `logo.png` (라이트 모드)와 `logo_dark.png` (다크 모드)로 교체한다.
   - 권장 크기: 512×512 PNG (정사각)
   - 배경 투명 (알파 채널) 유지
   - Android 12+ 대응: 로고가 128dp 원 프레임 안에 들어가도록 여백 확보
2. 필요 시 `flutter_native_splash.yaml`의 `color` / `color_dark` 배경색을 브랜드 컬러로 수정한다.
3. 아래 명령으로 네이티브 파일을 재생성한다.
   ```bash
   fvm flutter pub get
   fvm dart run flutter_native_splash:create
   ```
4. 생성된 `android/app/src/main/res/drawable*/launch_background.xml`, `android/app/src/main/res/values*/styles.xml`, `ios/Runner/Assets.xcassets/LaunchImage.imageset/`, `ios/Runner/Base.lproj/LaunchScreen.storyboard`를 모두 커밋한다 (재현성 확보).
5. Android 에뮬레이터(v21~v30, v31+)와 iOS 시뮬레이터(light/dark)에서 시각 검증한다.

## 알려진 제약

- **Android 12+ 원 프레임:** `android_12:` 블록은 SplashScreen API가 128dp 원형 영역만 렌더한다. 로고가 원 밖으로 나가면 잘린다.
- **Flavor별 스플래시 미지원(본 Starter Kit 범위):** `flutter_native_splash-dev.yaml` / `-stg.yaml` / `-prod.yaml`로 분리 후 `--flavors-file` 옵션을 쓰면 가능하지만 기본 Starter Kit에서는 단일 설정만 제공한다.
- **1×1 placeholder의 가시성:** 현재 placeholder는 1×1 투명 PNG이므로 Android 12+에서는 OS가 앱 기본 아이콘으로 대체 표시한다. 정상 동작이다.

## 참고

- AUTH-08, AUTH-09, AUTH-10 (`.planning/REQUIREMENTS.md`)
- Phase 10 CONTEXT D-22, D-26 (`.planning/phases/10-app-entry-flow/10-CONTEXT.md`)
- Phase 10 RESEARCH Pitfall 5 (flavor 구분)
