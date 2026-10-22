# Test-only Fonts

본 디렉토리는 **테스트 환경 전용** 폰트 자산을 보관한다. **production
`pubspec.yaml` 의 `fonts:` 단락에 미bundle** — 앱 binary 동봉 0.

## 자산 목록

| 파일 | 용도 | 라이센스 |
|------|------|---------|
| `Roboto-Medium.ttf` | golden test 의 Roboto Medium fixture (버튼 라벨 글꼴 `Roboto`) | Apache License 2.0 — `Roboto_LICENSE.txt` |
| `NotoSansCJKKR-Regular-Subset.otf` | ko golden 의 한글 글리프 (Android 시스템 CJK fallback 재현) | SIL OFL 1.1 — `NotoSansCJK_LICENSE.txt` |
| `NotoSansCJKJP-Regular-Subset.otf` | ja golden 의 가나 · 한자 글리프 (같은 목적) | SIL OFL 1.1 — `NotoSansCJK_LICENSE.txt` |

## 사유

로그인 버튼 라벨(Google 을 뺀 5개 · Android)이 글꼴 `Roboto` 를 쓴다. Android
에서는 번들한 Roboto 로 그려지지만, test env
(macOS host) 에서는 system fallback 의 weight 분기가 macOS 시스템 폰트 (SF
Pro / Helvetica) 로 우회 → Skia synthetic bold 발생 위험.

`assets/fonts/roboto/Roboto-VariableFont_wdth_wght.ttf` 가 production bundle
의 Roboto 단일 진실원이지만, 일부 legacy test fixture 가 명시적 weight binary
(Roboto-Medium.ttf) 를 FontLoader 에 직접 등록하는 패턴 사용.

## 미bundle 확인

`pubspec.yaml` 의 `fonts:` 단락에 본 디렉토리 entry 부재 → Flutter asset
bundler 가 무시. `flutter build apk --analyze-size` 검증 시 본 디렉토리 자산
0 bytes contribution.

## 갱신

본 디렉토리 자산은 test fixture — production behavior 영향 0. Roboto Medium
공식 binary 갱신 시 `Roboto_LICENSE.txt` 의 source URL 재방문 + Apache 2.0
attribution 보존 의무.

## Noto Sans CJK subset

### 왜 필요한가

앱은 한글 · 가나 · 한자 폰트를 bundle 하지 않는다. production Android 는 `Roboto`
(`pubspec.yaml` fonts:) 에 없는 글리프를 **시스템 fallback** 으로 그린다. AOSP 의
fallback 은 `NotoSansCJK-Regular.ttc` 이며 `font_fallback.xml` 이 ko → face 1
(Noto Sans CJK KR) · ja → face 0 (JP) 으로 매핑한다. Samsung One UI 단말의 실제
fallback 폰트는 확인하지 않았다.

flutter_tester 는 `FontLoader` 로 올린 폰트로 **자동 fallback 하지 않는다** — Roboto
만 올린 golden 은 한글 자리에 tofu 가 찍힌다. 그래서 ko/ja
golden 은 이 파일을 별도 family 로 올리고, **테스트 전용** ThemeData 에
`textTheme.apply(fontFamilyFallback: [<family>])` 를 건다 (`lib/` 변경 0).

### 출처

| 항목 | 값 |
|------|----|
| 원본 파일 | `NotoSansCJK-Regular.ttc` (variable, `wght` axis) — Android Studio 2025.3 `plugins/design-tools/resources/layoutlib/data/fonts/` 동봉 AOSP 시스템 폰트 |
| 원본 sha256 | `3e7e5afaac2c6d872592d76abedac03a51c6f0fc42d11e311ff2816a6c368afe` |
| 버전 | `Version 2.004-H1;hotconv 1.0.118;makeotfexe 2.5.65603` (name ID 5) |
| 저작권 (name ID 0, subset 에 보존) | `(c) 2014-2021 Adobe (http://www.adobe.com/), with Reserved Font Name 'Source'.` |
| 라이선스 | SIL OFL 1.1 — `NotoSansCJK_LICENSE.txt` 는 공식 저장소 `https://raw.githubusercontent.com/notofonts/noto-cjk/main/Sans/LICENSE` 의 verbatim 사본 (sha256 `6a73f9541c2de74158c0e7cf6b0a58ef774f5a780bf191f2d7ec9cc53efe2bf2`) |
| Reserved Font Name | `Source` — subset 은 OFL 상 수정본이므로 이름에 `Source` 를 쓰지 않는다. family 이름(`Noto Sans CJK KR/JP`) 은 RFN 이 아니다 |

사본이 어느 원문에서 왔는지(upstream 마지막 변경 커밋)와 subset 을 만든 날은
[브랜드 자산 갱신 — 받은 날 · 만든 날](../../docs/maintainer/brand-assets.md#받은-날--만든-날) 표에 있다.

### 다시 만들기

subset 은 `fonttools` 스크립트로 만들고, 같은 입력이면 결과가 byte 단위로 같다.
만드는 명령 · 옵션 · 확인 방법은 유지보수자 문서
[시험 글꼴 subset 다시 만들기](../../docs/maintainer/brand-assets.md#시험-글꼴-subset-다시-만들기) 에 있다.

### 글리프 범위 · 해시

| 파일 | face | 포함 code point | cmap 수 | 크기 | sha256 |
|------|------|-----------------|---------|------|--------|
| `NotoSansCJKKR-Regular-Subset.otf` | 1 (KR) | ASCII · 완성형 한글 11,172자 전부(U+AC00–D7A3) · 호환 자모(U+3130–318F) · `app_ko.arb` 값 문자 · fixture 문자 | 11,383 | 3,420,572 B | `68f3dd74e4c432c89d86314761e9b0c2ecab9447a48df9ee9cf6911249dbc324` |
| `NotoSansCJKJP-Regular-Subset.otf` | 0 (JP) | ASCII · U+3000–30FF(CJK 기호 · 히라가나 · 가타카나) · U+FF00–FFEF(전각) · `app_ja.arb` 값 문자 · fixture 문자(`登録方法 連携済みアカウント なし 山田太郎` 등) | 793 (한자 203) | 553,676 B | `f069561a2b145c5e06a89e7a2b622c7a8353c67198da49549e061af3856b742c` |

**갱신 조건:** `app_ja.arb` 에 subset 에 없는 한자가 더해지면 ja golden 에서 tofu 로 드러난다
→ [시험 글꼴 subset 다시 만들기](../../docs/maintainer/brand-assets.md#시험-글꼴-subset-다시-만들기) 의 절차로
JP 파일을 다시 만들고 이 표의 해시를 고친다. 한글은 전 음절을 담아 갱신하지 않는다.
