# LINE Brand Asset

LINE Login 버튼의 로고 자산이다. LINE 공식 버튼 이미지 묶음의 심볼을 SVG 1장으로
싣고, 버튼 바탕 · 라벨은 `BrandedSocialButton` 의 공통 골격이 그린다(배경 `#06C755`).

## 공식 BI URL
https://developers.line.biz/en/docs/line-login/login-button/ (LINE Developers 의 LINE Login 버튼 디자인 가이드)

사용 지침 원문은 https://terms2.line.me/LINE_Developers_Guidelines_for_Login_Button 에 있다. 원문 제목은 `Usage Guidelines for the LINE Login Button` 이고 운영사는 LY Corporation 이다.

## 자산 다운로드 URL
https://vos.line-scdn.net/line-developers/docs/media/line-login/login-button/LINE_Login_Button_Image.zip

로그인 버튼 이미지 묶음(ZIP)이다 — Android · iOS · 데스크톱용 크기별 PSD · PNG 가 들어 있다.

킷은 PSD 안의 벡터 원본(PSD 의 개체 이름 `벡터 고급 개체.ai`)만 옮겨 `btn_signin_icon.svg` 한 장으로 싣는다. 언어별 라벨이 그림에 들어 있는 PNG 는 싣지 않는다 — 라벨은 ARB 키 `authLineSignIn` 으로 앱이 그린다.

## 다운로드 일자
받은 날은 [브랜드 자산 갱신 — 받은 날 · 만든 날](../../../docs/maintainer/brand-assets.md#받은-날--만든-날) 표에 적는다.

## 라이선스
LINE 로그인 버튼 사용 지침을 따른다 — 원문 발췌는 `LICENSE.txt` 에 있다. 킷 사용자에게 걸리는 핵심 조항은 아래와 같다.

- 버튼 이미지의 색을 바꾸지 않는다 — 버튼 바탕은 `#06C755` 다(Section 4.3.2).
- LINE 아이콘의 가로세로 비율을 바꾸거나 알아보기 · 화질을 해치게 바꾸지 않는다 — 킷의 심볼은 47:44 비율이다(Section 4.3.1).
- 버튼 글자의 좌우 여백은 LINE 아이콘 말풍선 폭 이상, 위아래 여백은 그 폭의 절반 이상이다(Section 4.4).
- 버튼 둘레에 다른 요소를 두지 않는 빈 영역(원문 `Isolation Zone`)을 말풍선 왼쪽 여백 폭 이상으로 둔다(Section 4.5).
- 로그인 버튼 이미지를 앱 아이콘이나 로고의 일부 같은 용도로 쓰지 않는다(Section 4.7).
- LINE 이 버튼 이미지 · 아이콘을 바꾸고 갱신을 요청하면 바로 갱신하거나, 못 하면 까닭을 알린다(Section 4.16).
- 지침은 일본법을 따르고 분쟁은 도쿄지방법원 전속 관할이다(Section 9).

## 사전 검수 절차
LINE Developers Console(https://developers.line.biz/console/)에는 로고 사용의 사전 검수 신청 절차가 없다 — 위 조항을 직접 지킨다. LINE 이 그 앱을 공식으로 지지하거나 후원하는 것처럼 보이게 하는 디자인 · 문구는 쓰지 않는다(Section 4.6.3 · 4.14). 지침과 다르게 쓰면 LINE 이 LINE Developers 서비스나 버튼 이미지 사용을 멈추게 하고 필요한 조치를 할 수 있다(Section 6.1). 앱 출시 전에 하는 LINE 쪽 확인(email permission · 비즈니스 인증)은 [직접 하는 일 — 로그인 수단 검수 · 인증](../../../docs/guide.md#로그인-수단-검수--인증) 에 있다.

## 미포함 변형 추가 절차
LINE 공식 디자인 가이드는 로그인 버튼 문구를 18개 언어(en · ja · ko · de · es · fr · id · it · ms · pt-BR · pt-PT · ru · th · tr · ar · vi · zh-CN · zh-TW)로 준다. 킷의 ARB 는 ko · en · ja 의 `authLineSignIn` 을 담는다. 언어를 더하려면:

1. LINE 공식 디자인 가이드의 「Login button text」 표(long · short)에서 그 언어의 문구를 그대로 가져온다.
2. `lib/l10n/app_{locale}.arb` 의 `authLineSignIn` 키에 그 문구를 넣는다(자산은 바뀌지 않는다).
3. `BrandedSocialButton` 의 공통 골격(LINE 스킨)은 바꾸지 않는다 — ARB 키만 더하면 그 언어의 버튼이 그려진다.

누름 · 마우스 올림 · 비활성 상태의 색 원문은 `LICENSE.txt` 의 디자인 가이드 색 표에 있다. `BrandedSocialButton` 의 공통 골격(LINE 스킨)은 그 표의 상태별 색을 따로 그리지 않는다 — 비활성은 여섯 버튼 공통으로 버튼 전체를 투명도 0.38(`kBrandButtonDisabledOpacity`)로 그리고, 누름 · 마우스 올림은 `InkWell` 의 기본 표시다.

## 자산 freshness 갱신 빈도
1년마다 두 공식 페이지(https://developers.line.biz/en/docs/line-login/login-button/ · https://terms2.line.me/LINE_Developers_Guidelines_for_Login_Button)를 다시 확인한다 — 절차는 [브랜드 자산 갱신 — freshness 갱신](../../../docs/maintainer/brand-assets.md#freshness-갱신) 에 있다. LINE 이 버튼 이미지 · 아이콘 갱신을 요청하면(Section 4.16) 1년을 기다리지 않고 바로 갱신한다.

## 디렉토리 구조
```
assets/brand/line/
├── btn_signin_icon.svg   (심볼 SVG · viewBox 0 0 47 44 · fill=currentColor)
├── LICENSE.txt           (사용 지침 · 디자인 가이드 원문 발췌)
└── README.md             (이 파일)
```

로고는 디렉토리 바로 아래 한 장이고, 언어 · 밝기별 하위 디렉토리는 없다.

## 주의
- 위키백과 · seeklogo · 블로그 같은 제3자 출처의 그림 · 색은 쓰지 않는다 — 공식 페이지 원문만 쓴다.
- 로고를 직접 그려 만들지 않는다 — LINE 공식 PSD 의 벡터 원본에서 옮긴 그림만 쓴다.
- `btn_signin_icon.svg` 의 viewBox `0 0 47 44` 와 `fill="currentColor"` 를 그대로 둔다 — 색은 `BrandedSocialButton` 이 그릴 때 정한다. SVG 를 손으로 고치지 않고, 바꿀 때는 PSD 에서 다시 옮긴다.
