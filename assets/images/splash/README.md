# Splash 로고 에셋 (Starter Kit Placeholder)

이 디렉토리의 `logo.png`(라이트 모드) · `logo_dark.png`(다크 모드)는 네이티브 스플래시(Android/iOS OS 레벨)와 Flutter 스플래시가 함께 쓰는 로고다. 지금 들어 있는 그림은 **128×128 투명 PNG 자리 그림**이므로 프로젝트에서 내 로고로 바꾼다.

## 바꾸는 법

- 로고 원본 규격 · 배경색 · 네이티브 파일 다시 만들기 · 확인까지 스플래시를 바꾸는 전체 절차는 [스플래시 바꾸기](../../../docs/guide.md#스플래시-바꾸기) 한 곳에 있다.
- 로고 경로와 배경색은 `flutter_native_splash.yaml` 의 `image` · `image_dark` · `color` · `color_dark`(`android_12:` 블록 포함)와 내 파일 `lib/features/splash/presentation/splash_body.dart` 의 상수(`kSplashImage` · `kSplashImageDark` · `kSplashColor` · `kSplashColorDark`)에 같은 값으로 적는다.

## 알려진 제약

- **Flavor별 스플래시 미지원(본 Starter Kit 범위):** `flutter_native_splash-dev.yaml` / `-stg.yaml` / `-prod.yaml`로 분리 후 `--flavors-file` 옵션을 쓰면 가능하지만 기본 Starter Kit에서는 단일 설정만 제공한다.
