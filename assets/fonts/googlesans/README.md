# Google Sans Font Asset

Google 로그인 버튼의 영문 라벨에 쓰는 Google Sans 의 라틴 subset 이다. 공식 가변
파일에서 글자 범위와 축을 줄여 만든다.

## 출처

- **Source**: https://github.com/google/fonts/tree/main/ofl/googlesans
- **Original file**: `GoogleSans[GRAD,opsz,wght].ttf` — variable font (`GRAD` · `opsz` · `wght` axes), 4,974,940 bytes
- **Original sha256**: `d0a87d835a944b8b40d0e82a5651bb59ab97b936a2aeed5946eb57e7b2a3a90a`
- **License**: SIL Open Font License (OFL) 1.1 — `OFL.txt`
- **Copyright**: 2025 The Google Sans Project Authors (https://github.com/googlefonts/googlesans)
- **Fetched**: 2026-10-12

원본 파일은 저장소에 싣지 않는다. 필요하면 아래 「만드는 명령」 의 `curl` 로 받아
sha256 을 위 값과 대조한다.

## 이 파일

- **Asset**: `GoogleSans-Latin-wght.ttf` — 168,580 bytes (gzip 약 60KB)
- **sha256**: `349dce84fdb280f980a3cfd7e52103d2a4e2bfb7321be674fe038bbec87fda2c`
- **축**: `wght` 400 ~ 700 가변. `opsz` 는 18, `GRAD` 는 0 으로 고정한다.
- **글자 범위**: 라틴만 — U+0020–007E · U+00A0–017F 와 문장부호 9자(U+2010 · U+2011 ·
  U+2013 · U+2014 · U+2018 · U+2019 · U+201C · U+201D · U+2026). 이 범위에서
  원본에 없는 2자(U+0149 · U+017F)를 뺀 326자다.
- **한글 · 가나 글리프는 없다**(원본에도 없다). 그 글자는 기기 글꼴로 그려진다.

`opsz` 를 18 로 고정하는 이유: 원본 가변 파일을 축 지정 없이 그리면 실행 환경이
광학 크기 축을 스스로 골라 같은 글자의 폭이 환경마다 달라진다. 고정하면 어디서나
같은 폭으로 그려진다.

## 만드는 명령

저장소 밖 임시 가상 환경에서 만든다. 도구 버전: uv 0.12.23 · Python 3.12.7 ·
fonttools 4.66.1 · brotli 1.2.0.

```bash
# 1. 도구 (저장소 밖)
uv venv /tmp/gsans-venv -p 3.12
uv pip install --python /tmp/gsans-venv/bin/python 'fonttools==4.66.1' brotli

# 2. 원본 — URL 의 대괄호는 %5B %5D 로 쓰고 curl 에 -g 를 준다
curl -g -sSL -o GoogleSans-orig.ttf \
  'https://raw.githubusercontent.com/google/fonts/main/ofl/googlesans/GoogleSans%5BGRAD%2Copsz%2Cwght%5D.ttf'
shasum -a 256 GoogleSans-orig.ttf   # d0a87d83…a90a 와 같아야 한다

# 3. opsz · GRAD 고정 (wght 축은 남긴다)
/tmp/gsans-venv/bin/fonttools varLib.instancer GoogleSans-orig.ttf opsz=18 GRAD=0 \
  --no-recalc-timestamp -o GoogleSans-wght.ttf

# 4. 라틴 subset
/tmp/gsans-venv/bin/pyftsubset GoogleSans-wght.ttf \
  --unicodes='U+0020-007E,U+00A0-017F,U+2010,U+2011,U+2013,U+2014,U+2018,U+2019,U+201C,U+201D,U+2026' \
  --layout-features='*' --notdef-outline --name-IDs='*' --drop-tables+=DSIG \
  --no-recalc-timestamp \
  --output-file=assets/fonts/googlesans/GoogleSans-Latin-wght.ttf
```

`--no-recalc-timestamp` 는 글꼴의 수정 시각 필드를 원본 값 그대로 둔다. 이 옵션으로
같은 명령을 두 번 돌리면 결과 파일의 sha256 이 같다(위 값). 옵션을 빼면 만들 때마다
시각 필드가 달라져 해시가 달라진다 — 그림은 같다.

굵기 500 으로 고정한 정적 파일은 만들지 않는다. 고정하면 윤곽 좌표가 정수로
반올림되어 원본 가변 파일의 렌더와 픽셀이 달라진다.

## 쓰는 곳

- Google 로그인 버튼의 라벨 — 영문만 이 글꼴로 그려지고 한글 · 가나는 기기 글꼴로 넘어간다.
- `pubspec.yaml` `flutter > fonts` 의 family `GoogleSans`. 파일이 굵기 가변이라 `weight`
  줄 없이 선언한다.
- `fontWeight: FontWeight.w500` 이 `wght` 500(Medium)으로 그려진다. 축을 따로 지정하지
  않는다.

## 원본과의 대조

이 파일로 그린 글자는 원본 가변 파일을 `wght` 500 · `opsz` 18 · `GRAD` 0 으로 그린
것과 픽셀까지 같다. 원본 경로를 주면 계약 테스트가 다시 대조한다.

```bash
fvm flutter test --no-pub \
  --dart-define=BRAND_ASSET_GSANS_ORIGINAL=<원본 파일 절대 경로> \
  test/features/auth/presentation/_widgets/brand_button_assets_test.dart
```

- 조건: 16sp · `FontWeight.w500` · 줄 높이 22 · 자간 0.1 · 배율 3 · macOS 테스트 환경.
- 결과: 「Sign in with Google」(484 × 114) · 라틴 문장부호 문자열(633 × 114) 둘 다 다른
  픽셀 0. 같은 측정에서 원본을 `wght` 400 으로 그리면 20,462픽셀이 다르다(대조군).
- 경로를 주지 않으면 이 대조는 건너뛰고, 파일의 sha256 고정(`T-177-ASSET-01`)과
  pubspec 선언(`T-177-ASSET-02`)만 확인한다.

## License compliance

SIL OFL 1.1 (`OFL.txt`):

| 항목 | 상태 |
|---|---|
| License 파일 동봉 | ✓ `OFL.txt` (upstream 파일 그대로) |
| Copyright notice 보존 | ✓ `OFL.txt` 첫 줄 — Copyright 2025 The Google Sans Project Authors |
| Reserved Font Name | 선언 없음 — `OFL.txt` 의 저작권 고지에 Reserved Font Name 이 없어 수정본(subset)을 같은 이름으로 재배포할 수 있다 |
| Modifications | 축 고정(`opsz` 18 · `GRAD` 0) + 라틴 subset. 윤곽 · 메트릭은 손대지 않는다 |
| 단독 판매 금지 | ✓ 글꼴만 따로 팔지 않는다(앱에 번들) |
| 상표 | upstream `TRADEMARKS.md` — 「Google」 · 「Google Sans」 는 Google LLC 의 상표다. 글꼴(원본 · 수정본)과 관련해 그 이름을 쓸 수 있지만 Google 과의 제휴 · 후원을 암시해서는 안 되고, 회사 · 제품 · 도메인 이름에 넣을 수 없다 |

## 글자 범위를 넓히려면

다른 문자(예: 키릴 · 그리스)가 Google 버튼 라벨에 필요하면 위 4번 명령의 `--unicodes`
값만 바꿔 다시 만든다. 그런 다음 이 README 의 크기 · sha256 과
`test/features/auth/presentation/_widgets/brand_button_assets_test.dart` 의 고정값을
함께 고친다. 범위 밖 글자는 지금도 기기 글꼴로 그려지므로, 넓히지 않아도 글자가
빠지지는 않는다.
