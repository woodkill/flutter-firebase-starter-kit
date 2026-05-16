# Roboto Font Asset

## 출처

- **Source**: https://github.com/google/fonts/tree/main/ofl/roboto
- **License**: SIL Open Font License (OFL) 1.1 — `OFL.txt`
- **Copyright**: 2011 The Roboto Project Authors
- **Asset**: `Roboto-VariableFont_wdth_wght.ttf` (variable font, wdth + wght axes)
- **Fetched**: 2026-05-16

## 채택 사유

**Phase 13.3 Wave 4 Step 3 (2026-05-16)** — Google Identity Services 로그인
버튼 (`_renderGoogleButton`) 의 label fontFamily `'Roboto'` (Google production
CSS verbatim `font-family: 'Roboto', arial, sans-serif`) 부합.

### Test env synthetic bold 회피

`pubspec.yaml` 미bundle 시 Flutter test env (macOS host) 에서 fontFamily
`'Roboto'` 명시는:
1. `'Roboto'` asset 검색 → 없음
2. macOS system fallback → Helvetica/SF Pro
3. fontWeight w500 강제 → fallback font 의 Medium asset 미존재 시
4. Skia **synthetic bold** 적용 → 글자 더 굵음

Roboto variable font asset 을 bundle 함으로써:
- production Android: system Roboto 또는 bundled Roboto 사용 (동일 visual)
- production iOS/macOS: `_renderGoogleButton` 의 platform 분기로 `'SF Pro Text'`
  사용 (정문 강등 정책 부합 — STEP2-google-VERBATIM §2 row `label.fontFamily`)
- test env (macOS host): bundled Roboto 사용 (synthetic bold 회피)

### Variable font 의무

Google Fonts 의 Roboto 는 2023년부터 variable font 로 전환 (static asset
지원 종료). `wdth` (75-100) + `wght` (100-900) 두 axis 보유.

Flutter `fontWeight: FontWeight.w500` 명시 시 variable font 의 `wght` axis
500 (Medium) 자동 매핑 — `FontVariation` API 명시 불필요.

### Weight 매핑

- `FontWeight.w400` (Regular) → variable wght = 400 자동
- `FontWeight.w500` (Medium) → variable wght = 500 자동 ⭐ Google CSS 채택
- 다른 weights 미사용 — `_renderGoogleButton` 는 w500 단독

## 다른 provider 와의 비교

| Provider | Bundled font | License | 출처 |
|---|---|---|---|
| Apple | Inter Regular/Medium static (2 TTF) | SIL OFL 1.1 | rsms/inter |
| **Google** | **Roboto variable (1 TTF)** | **SIL OFL 1.1** | **google/fonts** |
| Kakao/Naver/Facebook | (자체 bundle 없음 — system font 사용) | — | — |

## 관련 코드

- `lib/features/auth/presentation/_widgets/branded_social_button.dart`
  `_renderGoogleButton` — fontFamily `'Roboto'` (Android/Linux/Windows/test)
  또는 `'SF Pro Text'` (iOS/macOS platform 분기)
- `pubspec.yaml` `flutter > fonts` 섹션 Roboto family entry
- `test/features/auth/presentation/_widgets/branded_social_button_golden_test.dart`
  `_loadGoldenFonts` Roboto FontLoader 등록

## License compliance

SIL OFL 1.1 (`OFL.txt`) 의무:
- ✓ Font name 변경 0 (`Roboto` 그대로)
- ✓ License 파일 동봉 (`OFL.txt`)
- ✓ Copyright notice 보존 (`OFL.txt` 의 Copyright 2011 The Roboto Project Authors)
- ✓ Modifications 0 (asset 그대로 채택)
- ✓ Sale 금지 — starter kit 는 sold 안 됨 (OFL 1.1 Reserved Font Name 정책 부합)
