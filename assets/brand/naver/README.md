# Naver Brand Asset

NAVER ID 로그인 버튼의 로고 자산이다. NAVER 공식 N 심볼 하나를 SVG 로 싣고, 버튼
바탕 · 라벨은 `BrandedSocialButton` 의 공통 골격이 그린다(배경 `#03A94D`).

## 공식 BI URL
https://developers.naver.com/docs/login/bi/bi.md (NAVER ID 로그인 BI — `#03A94D`)

NAVER 의 회사 브랜드 색(`#03C75A`, NAVER Corp + NCloud SSO)과 로그인 버튼 색(`#03A94D`, NAVER ID 로그인 BI)은 쓰는 곳이 다르다. 로그인 버튼은 NAVER ID 로그인 BI 페이지의 `#03A94D` 를 쓴다 — 다른 출처에서 `#03C75A` 를 보더라도 버튼 색으로 쓰지 않는다.

## 자산 다운로드 URL
https://developers.naver.com/docs/login/bi/bi.md → "디자인 가이드" 단락 (PNG + Figma + AI export)

## 다운로드 일자
받은 날은 [브랜드 자산 갱신 — 받은 날 · 만든 날](../../../docs/maintainer/brand-assets.md#받은-날--만든-날) 표에 적는다.

## 라이선스
NAVER Brand License (`LICENSE.txt` 의 원문 라이선스 텍스트).

## 사전 검수 절차
NAVER BI 페이지에는 로고 사용의 사전 검수 신청 절차가 보이지 않는다 — 출시 전에 BI 페이지를 직접 열어 신청 절차가 있는지 확인한다. 앱 출시 전에 하는 Naver 쪽 검수(검수 요청 · 추가 항목)는 [직접 하는 일 — 로그인 수단 검수 · 인증](../../../docs/guide.md#로그인-수단-검수--인증) 에 있다.

## 미포함 변형 추가 절차
NAVER BI 는 로고 변형(색상 / 회전 / 비율)을 금지한다. 다른 변형(예: 라벨이 그림에 들어 있는 버튼 이미지)을 쓰려면 NAVER Developers 의 가이드를 먼저 확인하고, BI 페이지의 파일을 내용 그대로 이 디렉토리에 둔다. 하위 디렉토리를 새로 만들면 `pubspec.yaml` 의 `assets:` 에 그 디렉토리를 따로 등록한다(디렉토리 등록은 재귀가 아니다).

## 자산 freshness 갱신 빈도
1년마다 공식 페이지(https://developers.naver.com/docs/login/bi/bi.md)를 다시 확인한다 — 절차는 [브랜드 자산 갱신 — freshness 갱신](../../../docs/maintainer/brand-assets.md#freshness-갱신) 에 있다.

## 디렉토리 구조
```
assets/brand/naver/
├── btn_signin_icon.svg   (N 심볼 SVG, viewBox 0 0 20 20, fill=currentColor)
├── LICENSE.txt
└── README.md
```

로고는 디렉토리 바로 아래 한 장이고, 언어 · 밝기별 하위 디렉토리는 없다. 라벨은 그림에 들어 있지 않다 — ARB 문구를 `BrandedSocialButton` 이 그리고, 심볼 색도 그릴 때 정한다.
