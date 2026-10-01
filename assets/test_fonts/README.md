# Test-only Fonts

본 디렉토리는 **테스트 환경 전용** 폰트 자산을 보관한다. **production
`pubspec.yaml` 의 `fonts:` 단락에 미bundle** — 앱 binary 동봉 0.

## 자상 목록

| 파일 | 용도 | 라이센스 |
|------|------|---------|
| `Roboto-Medium.ttf` | golden test 의 Roboto Medium fixture (Google Sign-in label fontFamily) | Apache License 2.0 — `Roboto_LICENSE.txt` |
| `NotoSansCJKKR-Regular-Subset.otf` | ko golden 의 한글 글리프 (Android 시스템 CJK fallback 재현) — Phase 16.7 | SIL OFL 1.1 — `NotoSansCJK_LICENSE.txt` |
| `NotoSansCJKJP-Regular-Subset.otf` | ja golden 의 가나 · 한자 글리프 (같은 목적) — Phase 16.7 | SIL OFL 1.1 — `NotoSansCJK_LICENSE.txt` |

## 사유

production code 의 `_renderGoogleButton` 은 fontFamily 'Roboto' (Google CSS
verbatim) 사용. Android system 의 Roboto 가 default 매핑되지만, test env
(macOS host) 에서는 system fallback 의 weight 분기가 macOS 시스템 폰트 (SF
Pro / Helvetica) 로 우회 → Skia synthetic bold 발생 위험.

`assets/fonts/roboto/Roboto-VariableFont_wdth_wght.ttf` 가 production bundle
의 Roboto 단일 진실원이지만, 일부 legacy test fixture 가 명시적 weight binary
(Roboto-Medium.ttf) 를 FontLoader 에 직접 등록하는 패턴 사용.

## 미bundle 확인

`pubspec.yaml` 의 `fonts:` 단락에 본 디렉토리 entry 부재 → Flutter asset
bundler 가 무시. `flutter build apk --analyze-size` 검증 시 본 디렉토리 자상
0 bytes contribution.

## 갱신

본 디렉토리 자상은 test fixture — production behavior 영향 0. Roboto Medium
공식 binary 갱신 시 `Roboto_LICENSE.txt` 의 source URL 재방문 + Apache 2.0
attribution 보존 의무.

## Noto Sans CJK subset (Phase 16.7)

### 왜 필요한가

앱은 한글 · 가나 · 한자 폰트를 bundle 하지 않는다. production Android 는 `Roboto`
(`pubspec.yaml` fonts:) 에 없는 글리프를 **시스템 fallback** 으로 그린다. AOSP 의
fallback 은 `NotoSansCJK-Regular.ttc` 이며 `font_fallback.xml` 이 ko → face 1
(Noto Sans CJK KR) · ja → face 0 (JP) 으로 매핑한다. Samsung One UI 단말의 실제
fallback 폰트는 확인하지 않았다.

flutter_tester 는 `FontLoader` 로 올린 폰트로 **자동 fallback 하지 않는다** — Roboto
만 올리면 한글이 tofu 로 찍힌다 (Phase 16.7 UI-SPEC mockup probe 실측). 그래서 ko/ja
golden 은 이 파일을 별도 family 로 올리고, **테스트 전용** ThemeData 에
`textTheme.apply(fontFamilyFallback: [<family>])` 를 건다 (`lib/` 변경 0).

### 출처

| 항목 | 값 |
|------|----|
| 원본 파일 | `NotoSansCJK-Regular.ttc` (variable, `wght` axis) — Android Studio 2025.3 `plugins/design-tools/resources/layoutlib/data/fonts/` 동봉 AOSP 시스템 폰트 |
| 원본 sha256 | `3e7e5afaac2c6d872592d76abedac03a51c6f0fc42d11e311ff2816a6c368afe` |
| 버전 | `Version 2.004-H1;hotconv 1.0.118;makeotfexe 2.5.65603` (name ID 5) |
| 저작권 (name ID 0, subset 에 보존) | `(c) 2014-2021 Adobe (http://www.adobe.com/), with Reserved Font Name 'Source'.` |
| 라이선스 | SIL OFL 1.1 — `NotoSansCJK_LICENSE.txt` 는 공식 저장소 `https://raw.githubusercontent.com/notofonts/noto-cjk/main/Sans/LICENSE` (마지막 변경 커밋 `a99a4354c68964f6bfac488d01010b1fb6d9178a`, 2022-03-20) 의 verbatim 사본 (sha256 `6a73f9541c2de74158c0e7cf6b0a58ef774f5a780bf191f2d7ec9cc53efe2bf2`) |
| Reserved Font Name | `Source` — subset 은 OFL 상 수정본이므로 이름에 `Source` 를 쓰지 않는다. family 이름(`Noto Sans CJK KR/JP`) 은 RFN 이 아니다 |

### 생성 방법

스크립트: `.planning/phases/16.7-sign-in-method-and-linked-accounts-split/mockups/subset_cjk.py.txt`
(fonttools 4.66.0 · `recalcTimestamp=False` 라 같은 입력이면 byte 동일 — 2회 생성 `cmp` 동일 확인).

```bash
uv venv /tmp/ftenv && uv pip install --python /tmp/ftenv/bin/python fonttools==4.66.0
cp .planning/phases/16.7-sign-in-method-and-linked-accounts-split/mockups/subset_cjk.py.txt /tmp/subset_cjk.py
/tmp/ftenv/bin/python -X utf8 /tmp/subset_cjk.py "<NotoSansCJK-Regular.ttc 경로>"   # repo root 에서
```

subset 옵션: `layout_features=['*']` · `name_IDs=['*']` · `name_languages=['*']` ·
`notdef_outline=True` · variable 축(`wght`) 유지.

### 글리프 범위 · 해시

| 파일 | face | 포함 code point | cmap 수 | 크기 | sha256 |
|------|------|-----------------|---------|------|--------|
| `NotoSansCJKKR-Regular-Subset.otf` | 1 (KR) | ASCII · 완성형 한글 11,172자 전부(U+AC00–D7A3) · 호환 자모(U+3130–318F) · `app_ko.arb` 값 문자 · fixture 문자 | 11,383 | 3,420,572 B | `68f3dd74e4c432c89d86314761e9b0c2ecab9447a48df9ee9cf6911249dbc324` |
| `NotoSansCJKJP-Regular-Subset.otf` | 0 (JP) | ASCII · U+3000–30FF(CJK 기호 · 히라가나 · 가타카나) · U+FF00–FFEF(전각) · `app_ja.arb` 값 문자 · fixture 문자(`登録方法 連携済みアカウント なし 山田太郎` 등) | 790 (한자 200) | 551,312 B | `8d88fafaa1b1709c9cc57687964d6782d53314a135d2e5b75e8c7885bcc3e9e9` |

**갱신 조건:** `app_ja.arb` 에 subset 에 없는 한자가 추가되면 ja golden 에서 tofu 로 드러난다
→ 스크립트를 다시 돌려 JP 파일과 이 표의 해시를 갱신한다. 한글은 전 음절을 담아 갱신 불요.

**검증 (2026-09-26):** 이 두 파일로 렌더한 Phase 16.7 mockup 46장이 원본 face 추출본
(subset 전) 으로 렌더한 46장과 byte 동일 (`cmp` 46/46), stage 1 mockup 30장도 30/30 동일.

### 갱신 이력

| 날짜 | 파일 | 내용 |
|------|------|------|
| 2026-09-26 | KR · JP | Phase 16.7 — 최초 생성 (JP cmap 780 · 한자 190) |
| 2026-10-01 | JP | Phase 17 — see ROADMAP.md: 새 ja 문구 한자 10자(分 台 択 決 知 般 許 起 通 選) 추가 — cmap 780 → 790 · 한자 190 → 200 · 제거 0. KR 은 byte 동일(sha256 불변) |
