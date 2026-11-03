# Pretendard JP Font Asset

앱 전체 글자(한글 · 가나 · 한자 · 영문)를 그리는 테마 글꼴이다. 공식 가변 파일을
고치지 않고 그대로 싣는다.

## 출처

- **Source**: https://github.com/orioncactus/pretendard (tag `v1.3.9`)
- **File URL**: https://raw.githubusercontent.com/orioncactus/pretendard/v1.3.9/packages/pretendard-jp/dist/public/variable/PretendardJPVariable.ttf
- **License**: SIL Open Font License (OFL) 1.1 — `OFL.txt` 는 https://raw.githubusercontent.com/orioncactus/pretendard/v1.3.9/LICENSE 원문 그대로다(4,418 bytes)
- **License sha256**: `d31ddd9f2bed32fd7e302a205cf2380ba0de6529152d239ef99cfb6f261bfc04`
- **Copyright**: 2021, Kil Hyung-jin (https://github.com/orioncactus/pretendard) — Reserved Font Name `Pretendard`
- **받은 날**: [브랜드 자산 갱신 — 받은 날 · 만든 날](../../../docs/maintainer/brand-assets.md#받은-날--만든-날) 표에 적는다.

## 이 파일

- **Asset**: `PretendardJPVariable.ttf` — 13,087,888 bytes (gzip 약 6.9MB)
- **sha256**: `bc1d77db0f3cb9c20986b8939aa8a28d5216552d777d082955da22f420535cbb`
- **축**: `wght` 100 ~ 900 가변.
- **글자 범위**: 한글 음절 11,172자 · 가나 184자 · 한자 7,138자 · 라틴.
- **변형**: 없다 — 받은 파일 그대로다.

## 고른 까닭

- 앱이 글꼴을 싣지 않으면 기기 대체 글꼴이 그 글자를 그리는데, 대체 글꼴은 기기와 앱 언어마다 다르다.
- 그래서 앱 언어가 일본어인 일부 Android 기기에서는 한글이 명조로 그려진다.
- 네 문자를 한 파일에 담은 이 글꼴을 테마 글꼴로 두면 앱 언어 · OS 와 상관없이 같은 글꼴로 그려진다.
- 대가는 앱 크기 약 13.1MB(압축 약 6.9MB)다.

## 쓰는 곳

- `pubspec.yaml` `flutter > fonts` 의 family `PretendardJP`. 파일이 굵기 가변이라 `weight` 줄 없이 선언한다.
- `lib/core/theme/app_theme.dart` 의 `AppTheme.fontFamily` 가 이 family 를 `ThemeData(fontFamily:)` 로 건다.
- 소셜 로그인 버튼 라벨은 이 글꼴을 쓰지 않는다.
- 시험: golden 하네스가 `test/helpers/app_font.dart` 의 `loadAppFont()` 로 이 파일을 올리고, `test/core/theme/app_font_test.dart` 가 파일 sha256 · pubspec 선언 · 테마 연결을 고정한다.

## 바꾸거나 빼려면

`docs/guide.md` 의 [디자인 토큰 바꾸기](../../../docs/guide.md#디자인-토큰-바꾸기) 「6. 앱 글꼴 바꾸기 · 빼기」 를 따른다.

## License compliance

SIL OFL 1.1 (`OFL.txt`):

| 항목 | 상태 |
|---|---|
| License 파일 동봉 | ✓ `OFL.txt` (upstream `LICENSE` 파일 그대로) |
| Copyright notice 보존 | ✓ `OFL.txt` 첫 두 줄 — Copyright (c) 2021, Kil Hyung-jin |
| Reserved Font Name | `Pretendard` 선언 있음 — 원본을 고치지 않고 그대로 싣는다. subset · 변형하면 그 결과에 Pretendard 이름을 쓸 수 없다 |
| Modifications | 없음 |
| 단독 판매 금지 | ✓ 글꼴만 따로 팔지 않는다(앱에 번들) |
