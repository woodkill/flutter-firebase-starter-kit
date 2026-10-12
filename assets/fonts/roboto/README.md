# Roboto Font Asset

## 출처

- **Source**: https://github.com/google/fonts/tree/main/ofl/roboto
- **License**: SIL Open Font License (OFL) 1.1 — `OFL.txt`
- **Copyright**: 2011 The Roboto Project Authors
- **Asset**: `Roboto-VariableFont_wdth_wght.ttf` (variable font, wdth + wght axes)
- **Fetched**: 2026-05-16

## 채택 사유

번들 Roboto 는 Android 에서 두 곳에 쓰인다. 앱의 영문 글자가 이 파일로
그려지고(`pubspec.yaml` 이 family `Roboto` 로 선언한다 — Flutter Material 이
Android 에서 쓰는 기본 글꼴 이름이다), Google 을 뺀 5개 로그인 버튼의 라벨도
이 글꼴을 쓴다(상수 `kBrandLabelFontFamily`). Google 버튼 라벨의 영문은
Google Sans 다 — `assets/fonts/googlesans/README.md`. iOS · macOS 에서는 버튼
라벨이 시스템 글꼴로 그려진다(상수 `kBrandLabelFontFamilyApple`).

### Test env synthetic bold 회피

`pubspec.yaml` 미bundle 시 Flutter test env (macOS host) 에서 fontFamily
`'Roboto'` 명시는:
1. `'Roboto'` asset 검색 → 없음
2. macOS system fallback → Helvetica/SF Pro
3. fontWeight w500 강제 → fallback font 의 Medium asset 미존재 시
4. Skia **synthetic bold** 적용 → 글자 더 굵음

Roboto variable font asset 을 bundle 함으로써:
- production Android: 앱의 영문 글자와 Google 을 뺀 5개 버튼 라벨이 bundled Roboto 로 그려진다
- production iOS/macOS: 버튼 라벨이 시스템 글꼴로 그려진다 (`kBrandLabelFontFamilyApple`)
- test env (macOS host): 화면 golden 하네스가 이 파일을 family `Roboto` 로 올린다
  (synthetic bold 회피). 버튼 단독 golden 은 `assets/test_fonts/Roboto-Medium.ttf` 를 올린다

### Variable font 의무

Google Fonts 의 Roboto 는 2023년부터 variable font 로 전환 (static asset
지원 종료). `wdth` (75-100) + `wght` (100-900) 두 axis 보유.

Flutter `fontWeight: FontWeight.w500` 명시 시 variable font 의 `wght` axis
500 (Medium) 자동 매핑 — `FontVariation` API 명시 불필요.

### Weight 매핑

- `FontWeight.w400` (Regular) → variable wght = 400 자동
- `FontWeight.w500` (Medium) → variable wght = 500 자동 ⭐ 버튼 라벨의 굵기
- 버튼 라벨은 w500 하나만 쓴다 (`kBrandLabelFontWeight`)

## 다른 provider 와의 비교

| Provider | Bundled font | License | 출처 |
|---|---|---|---|
| Google | Google Sans 라틴 subset (1 TTF — `assets/fonts/googlesans/`) | SIL OFL 1.1 | google/fonts |
| **Apple/Facebook/Kakao/Naver/LINE** | **Roboto variable (1 TTF) — Android. iOS · macOS 는 시스템 글꼴** | **SIL OFL 1.1** | **google/fonts** |

## 관련 코드

- `lib/features/auth/presentation/_widgets/branded_social_button.dart`
  `kBrandLabelFontFamily` — `'Roboto'` (iOS · macOS 가 아닌 플랫폼의 버튼 라벨) ·
  `kBrandLabelFontFamilyApple` (iOS · macOS 의 버튼 라벨) · `kGoogleLabelFontFamily` (Google 버튼 라벨)
- `pubspec.yaml` `flutter > fonts` 섹션 Roboto family entry
- `test/features/auth/presentation/_widgets/branded_social_button_golden_test.dart`
  `_loadGoldenFonts` 가 `assets/test_fonts/Roboto-Medium.ttf` 를 family `Roboto` 로 올린다
- `test/features/auth/presentation/auth_surfaces_golden_test.dart` ·
  `test/features/settings/presentation/settings_golden_harness.dart` 가 이 파일을 family `Roboto` 로 올린다

## License compliance

SIL OFL 1.1 (`OFL.txt`) 의무:
- ✓ Font name 변경 0 (`Roboto` 그대로)
- ✓ License 파일 동봉 (`OFL.txt`)
- ✓ Copyright notice 보존 (`OFL.txt` 의 Copyright 2011 The Roboto Project Authors)
- ✓ Modifications 0 (asset 그대로 채택)
- ✓ Sale 금지 — starter kit 는 sold 안 됨 (OFL 1.1 Reserved Font Name 정책 부합)
