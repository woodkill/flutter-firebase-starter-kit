# Apple Brand Asset

Apple 로그인 버튼에 그리는 Apple 로고다. Apple 의 공식 웹 로그인 스크립트가 버튼을
그릴 때 쓰는 **medium** 로고의 path 를 좌표 그대로 담은 SVG 2장이고, 버튼 바탕 · 글자는
앱이 그린다.

## 디렉터리 구조

```
assets/brand/apple/
├── black_logo/btn_signin_icon.svg   # 검정 로고 (#000000) — 어두운 테마의 흰 버튼
├── white_logo/btn_signin_icon.svg   # 흰 로고 (#FFFFFF) — 밝은 테마의 검정 버튼
└── README.md
```

두 파일은 채움색만 다르다(각 1,447 bytes). 디렉터리 이름은 로고의 색이다.

## 공식 BI URL

- https://developer.apple.com/design/human-interface-guidelines/sign-in-with-apple
  (Human Interface Guidelines — Sign in with Apple)

## 자산 다운로드 URL

- https://appleid.cdn-apple.com/appleauth/static/jsapi/appleid/1/en_US/appleid.auth.js
  - sha256 `d443b6ff67b95e7d5811d53447365c980c9c4f3dd13317024853672298d75790` · 42,880 bytes
- 이 스크립트는 로고를 `small` · `medium` · `large` 세 객체로 갖고 있다. 싣는 것은
  `medium` 이다.

  ```
  medium:{height:44,width:31,logoWidth:17,path:"M15.7099491,14.8846154 …"}
  ```

- SVG 는 그 객체를 그대로 옮긴 것이다.
  - viewBox `7 0 17 44` — 캔버스 31 × 44 가운데 로고 폭 17 만 남긴다(x = (31 − 17) / 2 = 7).
    스크립트가 버튼을 그릴 때 만드는 viewBox 와 같다.
  - path 의 `d` = `medium` 객체의 `path` 문자열 1,259자 그대로(첫 좌표
    `M15.7099491,14.8846154`). sha256 `870e7f7ff994651ec0d878cd0dd6007c2b99089332e65efb656a4862d3cabf74`
  - 채움색 `#000000`(`black_logo/`) · `#FFFFFF`(`white_logo/`)

## 다운로드 일자

받은 날은 [브랜드 자산 갱신 — 받은 날 · 만든 날](../../../docs/maintainer/brand-assets.md#받은-날--만든-날) 표에 적는다.

## 지금 그리는 값

| 항목 | 값 |
|---|---|
| 로고 크기 | 폭 `17 × 48 / 44`(약 18.5) · 높이 48 — 파일 높이 44 를 버튼 높이 48 에 맞춘다 |
| 보이는 로고 | 약 16.9 × 20.7 (파일 위아래의 여백을 뺀 그림) |
| 로고 ↔ 라벨 | 간격 9 |
| 라벨 | 16 / w500 · 줄 높이 22 · 자간 0.1 |
| 라벨 글꼴 | Android = 킷이 싣는 Roboto(영문) + 기기 글꼴(한글 · 가나) · iOS = 시스템 글꼴 |
| 버튼 | 높이 48 · 모서리 12 · 밝은 테마 = 검정 바탕 + 흰 로고 · 글자 / 어두운 테마 = 흰 바탕 + 검정 로고 · 글자 |

값은 `lib/features/auth/presentation/_widgets/branded_social_button.dart` 의 Apple 스킨과
`kBrand…` 상수에 있다.

## Apple HIG mandate 부합

| HIG 문장 | 이 킷 |
|---|---|
| 「Logos are available in small, medium, and large sizes」 | `medium` 을 쓴다 |
| 「Match the height of the logo file to the height of the button」 | 파일 높이 44 를 버튼 높이 48 로 그린다 — 로고 위아래에 여백을 더하지 않는다 |
| 로고는 검정 또는 흰색만 쓴다 | 검정 · 흰색 2장뿐이다 |
| 로고를 자르거나 직접 그리지 않는다 | path 좌표와 viewBox 를 손대지 않는다 |

## 라이선스

이 디렉터리에는 `LICENSE.txt` 가 없다. Apple 은 로고에 배포 라이선스 본문을 따로 주지
않고, Human Interface Guidelines 가 정한 범위 안에서 쓰도록 한다.

- 로고는 Apple 로그인 버튼 안에서만 쓴다. 다른 화면 요소에 쓰지 않는다.
- path 는 Apple 이 버튼 외관을 맞추도록 공개 스크립트로 배포하는 값 그대로다.
- **Apple 글꼴은 싣지 않는다.** iOS 에서는 기기의 시스템 글꼴로 라벨을 그리고, Android
  에서는 Roboto 로 그린다. Apple 글꼴로 그린 그림(스크린샷 · 테스트 기준 그림)도
  저장소에 두지 않는다.

## 사전 검수 절차

Apple 은 버튼에 대해 따로 검수 신청을 받지 않는다. App Store 심사가 Human Interface
Guidelines 준수를 본다. 출시 전에 직접 대조한다.

1. 두 SVG 의 path 가 스크립트 `medium` 객체의 문자열과 같은지 — 자산 계약 테스트
   `T-177-ASSET-07` 이 path 의 sha256 · viewBox · 채움색을 고정한다.
2. 버튼이 검정 또는 흰색 바탕이고 로고 색이 그 반대인지.
3. 버튼 글자가 「locale 라벨」 절의 문구인지.

```bash
fvm flutter test --no-pub test/features/auth/presentation/_widgets/brand_button_assets_test.dart
```

## 미포함 변형 추가 절차

`small` · `large` 로고는 싣지 않는다. 다른 크기를 쓰려면:

1. 스크립트를 받아 sha256 을 위 값과 대조한다(다르면 「자산 freshness 갱신 빈도」 절).
2. 쓰려는 객체의 `path` 문자열을 그대로 옮기고 viewBox 를
   `<(width − logoWidth) / 2> 0 <logoWidth> <height>` 로 잡는다.
3. 흑 · 백 2장을 같은 디렉터리에 다른 이름으로 두거나 지금 파일을 바꾼다. 지금 파일을
   바꾸면 `branded_social_button.dart` Apple 스킨의 로고 폭(`logoWidth × 48 / 44`)과 로고
   ↔ 라벨 간격, 자산 계약 테스트의 고정값을 함께 고친다.
4. 버튼 기준 그림(golden)을 다시 만들고 눈으로 확인한다.

## 자산 freshness 갱신 빈도

1년마다 공식 페이지(https://developer.apple.com/design/human-interface-guidelines/sign-in-with-apple)를
다시 확인한다 — 절차는 [브랜드 자산 갱신 — freshness 갱신](../../../docs/maintainer/brand-assets.md#freshness-갱신)
에 있다.

스크립트의 sha256 이 위 값과 달라졌을 때도 본다. 달라졌으면 `medium`
객체의 `height` · `width` · `logoWidth` · `path` 를 지금 값과 견주고, 바뀐 것이 있으면
SVG 2장과 이 README · 자산 계약 테스트의 값을 함께 고친다.

## locale 라벨

버튼 글자는 ARB 키 `authAppleSignIn` 이다(`lib/l10n/app_{en,ko,ja}.arb`).

| locale | 문구 |
|---|---|
| en | Sign in with Apple |
| ko | Apple로 로그인 |
| ja | Appleでサインイン |

Apple 이 언어별로 정한 버튼 문구와 같다. 언어를 더하면 그 언어의 Apple 공식 문구를 쓴다.

## 주의

- 버튼 높이를 48 에서 바꾸면 로고 폭(`17 × 높이 / 44`)이 함께 바뀐다 — 스킨이 버튼 높이
  상수로 계산한다. 로고 ↔ 라벨 간격은 따로 다시 정한다.
- 라벨 크기 16 은 여섯 로그인 버튼에 공통인 값이다. Human Interface Guidelines 가
  권하는 크기(버튼 높이의 43%)보다 작다 — 한 화면에 놓인 버튼들의 글자 크기를 맞추기
  위해서다.
- 로고 SVG 를 다른 내용으로 바꾼 뒤 테스트의 그림이 그대로이면, 파일의 수정 시각이
  갱신됐는지 본다(테스트 자산 묶음은 수정 시각으로 갱신 여부를 정한다).
