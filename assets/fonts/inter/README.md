# Inter Font — Apple Sign-in 버튼 라벨 fallback

Phase 13.3 Wave 4 Step 3 (2026-05-16) — Apple SF Pro Text 의 license-safe
open-source alternative. iOS/macOS 환경에서 system 'SF Pro Text' 자동 사용
불가능한 환경 (Android / Linux / Windows / Flutter test env) 에서 fallback.

## 자산 출처

- **upstream**: https://github.com/rsms/inter (Inter Project)
- **version**: v4.1 (2024-11-16)
- **release ZIP**: https://github.com/rsms/inter/releases/download/v4.1/Inter-4.1.zip
- **추출 경로**: ZIP 의 `extras/ttf/Inter-Regular.ttf` + `extras/ttf/Inter-Medium.ttf`

## License — SIL Open Font License 1.1

> Copyright (c) 2016 The Inter Project Authors (https://github.com/rsms/inter)
> This Font Software is licensed under the SIL Open Font License, Version 1.1.

전체 license 본문 — `OFL.txt` 참조.

**SIL OFL 1.1 허용 사항** (verbatim 본문 참조):
- ✓ Embed in software (starter kit asset 포함 OK)
- ✓ Bundle in any product (Android, iOS, web 무관)
- ✓ Commercial use
- ✓ Modify + redistribute (단 modified 버전은 OFL 1.1 유지 의무)
- ✓ No royalty

**SIL OFL 1.1 의무 사항**:
- License 사본 포함 (`OFL.txt`) — 본 디렉토리 안 commit 완료
- Copyright notice 보존

## 채택 사유

Apple Sign-in 버튼 라벨의 SF Pro Text Medium 외관 매칭 위해 검토된 후보:

| Font | SIL OFL? | SF Pro 유사도 | 채택 |
|---|---|---|---|
| **Inter** | ✓ | ⭐⭐⭐⭐⭐ (가장 유사) | **✓** |
| Geist (Vercel) | ✓ | ⭐⭐⭐⭐ | — |
| Public Sans | ✓ | ⭐⭐⭐ | — |
| Manrope | ✓ | ⭐⭐⭐ | — |
| IBM Plex Sans | ✓ | ⭐⭐ | — |
| Roboto (Apache 2.0) | △ | ⭐ (현재 fallback) | — |

Inter 는 SF Pro 영향 받은 humanist sans-serif. Figma/Vercel/Linear/Notion
등 다수 채택 — web typography 의 사실상 standard.

## weight 채택

| weight | TTF 파일 | 사용 |
|---|---|---|
| 400 (Regular) | `Inter-Regular.ttf` | **primary** — Apple Button API CSS `fontWeight: "400"` verbatim 매칭. Inter Medium (w500) 보다 SF Pro Text Medium 의 visual stroke weight 와 더 가까운 매칭 (사용자 시각 sign-off 2026-05-16) |
| 500 (Medium) | `Inter-Medium.ttf` | future use 대비 |

## 사용 경로

본 font 는 **Apple Sign-in 버튼 라벨 단독** 사용 — 다른 UI 요소에 미사용:
- `lib/features/auth/presentation/_widgets/branded_social_button.dart` 의
  `_renderAppleButton` 함수 안 `TextStyle(fontFamily: 'Inter', ...)`
- platform 분기: iOS/macOS = system 'SF Pro Text' / 다른 = 'Inter' asset

## 자산 freshness 갱신 빈도

Inter Project 의 major release 시 — github.com/rsms/inter/releases 의 v4.x
업데이트 추적 의무. 시각 변화 검증 후 갱신.

## 주의

- pubspec.yaml 의 `flutter > fonts` 섹션에 family 'Inter' 등록 의무 (현재
  완료)
- Flutter golden test 의 `_loadGoldenFonts` 함수에서 explicit `FontLoader`
  load 의무 (test env 의 default font 가 Ahem 으로 fallback 됨 회피)
- Inter Variable (variable font, ~800KB) 미채택 — 우리는 weight 400/500 만
  사용, 개별 TTF 가 효율적
