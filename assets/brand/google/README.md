# Google Brand Asset

Google 로그인 버튼에 그리는 「G」 로고다. Google 이 배포하는 공식 버튼 SVG 에서 G 부분만
투명 배경 PNG 로 그린 것이고, 버튼 바탕(색 · 외곽선 · 모서리)은 앱이 가이드 값으로
그린다.

## 디렉터리 구조

```
assets/brand/google/
├── g.png          # 20 × 20 px (1배)
├── 2.0x/g.png     # 40 × 40 px
├── 3.0x/g.png     # 60 × 60 px
├── 4.0x/g.png     # 80 × 80 px
├── LICENSE.txt
└── README.md
```

- 앱은 `assets/brand/google/g.png` 하나만 이름으로 부른다. Flutter 가 기기 화소 밀도에
  가장 가까운 변형(`2.0x` · `3.0x` · `4.0x`)을 고른다.
- `pubspec.yaml` 의 `assets/brand/google/` 한 줄이 변형 디렉터리까지 함께 싣는다.
- 밝은 테마 · 어두운 테마가 같은 파일을 쓴다. 공식 묶음의 Light · Dark · Neutral 버튼은
  바탕만 다르고 G 그림은 같다.

## 왜 PNG 인가

공식 묶음에는 G 만 따로 든 파일이 없고 완성된 버튼 그림만 있다. 그 SVG 는
`foreignObject` 와 `filter`(흐림 효과)로 색 번짐을 그리는데, 앱이 SVG 를 그리는
`flutter_svg` 는 이 두 요소를 그리지 못한다. 그래서 같은 SVG 를 Chrome 으로 그려 PNG 로
싣는다.

## 공식 BI URL

- https://developers.google.com/identity/branding-guidelines (Sign in with Google
  Branding Guidelines — 본문 끝의 갱신 표기(`Last updated …`)를 확인한다)
- 이 가이드는 「the standard color gradient super G logo」 를 요구한다. 단색 G · 직접 만든
  아이콘 · 색이나 크기를 바꾼 G 는 쓰면 안 되는 예로 든다.

## 자산 다운로드 URL

- 공식 묶음: https://developers.google.com/static/identity/images/signin-assets.zip
  - sha256 `ba884069e12093b06bcfd776915081254a7c95094b80d50be2c5dc6bac1c1da1` · 855,303 bytes · 132 파일
- 원천 SVG(묶음 안 경로):
  `Android + Web/SVG/Light/Theme=Light, Show text=No, Shape=Square, Platform=Android+Web.svg`
- 대조에 쓰는 공식 PNG(묶음 안 경로 · N = 1 ~ 4):
  `Android + Web/PNG @Nx/{Light,Dark}/Theme={Light,Dark}, Show text=No, Shape=Square, Platform=Android+Web[@Nx].png`

## 다운로드 일자

받은 날은 [브랜드 자산 갱신 — 받은 날 · 만든 날](../../../docs/maintainer/brand-assets.md#받은-날--만든-날) 표에 적는다.

## 만드는 절차

1. 묶음을 받아 sha256 을 위 값과 대조하고 푼다.
2. 원천 SVG 를 복사해 두 곳만 고친다. G 를 그리는 나머지 줄(mask · group · defs)은
   손대지 않는다.
   - 루트 `<svg>` 의 크기와 영역을 `width="20" height="20" viewBox="10 10 20 20"` 으로
     바꾼다(40 × 40 버튼 가운데의 G 칸 20 × 20 만 남는다).
   - 버튼 바탕 path 2개(`M4 0.5H36…` 로 시작하는 채움과 외곽선)를 지운다.
   - 고친 SVG 의 sha256: `a6b7524174e5143f771c3ad2923e24a19aa86e7a5823dd1be0e1494fea05b6a4`
3. 고친 SVG 를 아래 본문에 그대로 넣어 `google_g.html` 로 저장한다.

   ```html
   <!doctype html><html><head><style>html,body{margin:0;padding:0;background:transparent;overflow:hidden}svg{display:block}</style></head><body>
   <!-- 여기에 고친 SVG -->
   </body></html>
   ```

4. headless Chrome 으로 배율마다 한 장씩 찍는다(N = 1 · 2 · 3 · 4 → 20 · 40 · 60 · 80 px).

   ```bash
   "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" --headless=new --disable-gpu --hide-scrollbars \
     --no-first-run --no-default-browser-check --user-data-dir=<새 임시 디렉터리> \
     --force-device-scale-factor=N --default-background-color=00000000 --window-size=20,20 \
     --screenshot=<출력 PNG> file://<google_g.html 의 절대 경로>
   ```

   - `--default-background-color=00000000` 이 투명 배경을 만든다. 빼면 흰 배경이 그림에
     구워진다.
   - `--user-data-dir` 는 실행마다 저장소 밖의 새 디렉터리를 준다. 이미 떠 있는 Chrome 과
     섞이지 않는다.
   - **4배 그림을 줄여서 1 ~ 3배를 만들지 않고 배율마다 직접 그린다.** 윤곽선이 배율마다
     다르게 깔려서, 직접 그린 쪽이 공식 PNG 에 더 가깝다.
5. 출력 4장을 `g.png` · `2.0x/g.png` · `3.0x/g.png` · `4.0x/g.png` 로 둔다.

지금 파일은 Chrome `155.0.8059.40`(macOS)으로 만들었다.

| 배율 | 파일 | 크기 | sha256 |
|---|---|---|---|
| 1 | `g.png` | 20 × 20 | `7dd27866e69aa77ab7b9d4aae6649e3207d29d60100d3a36b0aa69edcda2270c` |
| 2 | `2.0x/g.png` | 40 × 40 | `c56f8e471761761735fb0dc0f06500d01ac1b60f4c7ff8312eece7ab3bae4600` |
| 3 | `3.0x/g.png` | 60 × 60 | `17bfc27f2bbbc7d60de882b8aad89af030aba833aa8ed0c915e5401fb705a595` |
| 4 | `4.0x/g.png` | 80 × 80 | `830af225265111738899788c16db2783120e7da58c035b4c157a6f3e809f1e29` |

네 장 모두 8-bit RGBA 이고 네 모서리의 알파가 0 이다.

## 공식 PNG 와의 대조

G 를 공식 버튼의 바탕색 위에 합성한 그림과, 같은 배율 공식 PNG 의 G 칸(가로 · 세로
`10N` 픽셀 떨어진 `20N × 20N` 영역)을 견준 값이다. 흰 배경은 Light 버튼(`#FFFFFF`),
어두운 배경은 Dark 버튼(`#131314`)이다.

| 배율 | 칸(px) | 흰 배경 평균 | 흰 배경 최대 | 흰 배경 16 초과 | 어두운 배경 평균 | 어두운 배경 최대 | 어두운 배경 16 초과 |
|---|---|---|---|---|---|---|---|
| 1 | 20 | 2.44 | 37 | 34 | 2.27 | 45 | 31 |
| 2 | 40 | 1.47 | 49 | 73 | 1.37 | 47 | 68 |
| 3 | 60 | 1.10 | 45 | 74 | 1.05 | 57 | 78 |
| 4 | 80 | 1.17 | 62 | 177 | 1.08 | 76 | 175 |

- 합성 = `색 × 알파 + 배경 × (1 − 알파)` — 반올림하지 않는다.
- 평균 = 채널별 차(픽셀 × RGB)의 전체 평균 · 최대 = 채널별 차의 최대 · 16 초과 = 채널
  최대차가 16 을 넘는 픽셀 수.
- 차이는 G 의 윤곽선 픽셀에 몰려 있다(가장자리 처리 차이).

## 다시 만들 때의 확인

다른 Chrome 버전으로 다시 만들면 윤곽선 픽셀이 달라져 sha256 이 바뀔 수 있다. 같은
대조를 돌려 기준 안인지 본다 — 배율마다 **평균 ≤ 3.0 · 최대 ≤ 96 · 16 초과 ≤ 칸의 10%**.

```bash
fvm flutter test --no-pub \
  --dart-define=BRAND_ASSET_GOOGLE_SIGNIN_DIR=<묶음을 푼 디렉터리의 절대 경로> \
  test/features/auth/presentation/_widgets/brand_button_assets_test.dart
```

- 경로를 주면 `T-177-ASSET-06` 이 위 표와 같은 대조를 하고 배율별 값을 출력한다.
- 경로를 주지 않으면 그 대조는 건너뛰고, 4장의 sha256 · 크기 고정(`T-177-ASSET-04`)과
  번들 변형(`T-177-ASSET-05`)만 확인한다.
- 기준 안이면 이 README 의 sha256 표 · 대조 표 · Chrome 버전과 테스트 파일의 고정값을
  함께 고친다.

## 라이선스

Google 의 브랜드 가이드가 사용 조건이다. 조항 원문은 같은 디렉터리의 `LICENSE.txt` 에
옮겨 두었다. G 의 색 · 비율을 바꾸지 않고, Google 로그인 버튼 안에서만 쓴다.

## 사전 검수 절차

Google 은 로그인 버튼에 대해 사전 검수 신청을 받지 않는다. 출시 전에 가이드의 색 표 ·
여백 · 문구와 버튼을 직접 대조한다.

- 버튼 바탕 · 외곽선 · 글자색 = 가이드의 Light · Dark 값
- 로고와 글자 사이 간격 = Android 10 · iOS 12
- 버튼 글자 = `Sign in with Google` 등 가이드가 든 문구와 그 번역

## 미포함 변형 추가 절차

싣는 것은 G 한 벌뿐이다. 완성된 버튼 그림(글자가 든 것 · Neutral · Pill · iOS 판)은
싣지 않는다 — 버튼은 앱이 그린다.

- 더 큰 배율이 필요하면 「만드는 절차」 4번을 그 배율로 돌려 `N.0x/g.png` 로 더한다.
  `pubspec.yaml` 은 고치지 않아도 된다.
- 다른 그림을 더하면 같은 디렉터리에 다른 이름으로 두고 이 README 에 출처와 sha256 을
  적는다. G 를 직접 그리거나 색을 바꾼 파일은 두지 않는다(가이드가 금지한다).

## 자산 freshness 갱신 빈도

1년마다 공식 페이지(https://developers.google.com/identity/branding-guidelines)를 다시
확인한다 — 절차는 [브랜드 자산 갱신 — freshness 갱신](../../../docs/maintainer/brand-assets.md#freshness-갱신)
에 있다.

가이드 본문 끝의 `Last updated` 날짜가 바뀌었을 때도 본다. 묶음을 다시 받아
sha256 이 위 값과 다르면 「만드는 절차」 로 다시 만들고 「다시 만들 때의 확인」 을 거친다.
