# Kakao Brand Asset

Kakao 로그인 버튼의 로고 자산이다. Kakao 공식 리소스의 말풍선 심볼 하나를 SVG 로
싣고, 버튼 바탕 · 라벨은 `BrandedSocialButton` 의 공통 골격이 그린다(배경 `#FEE500`).

## 공식 BI URL
https://developers.kakao.com/docs/ko/kakaologin/design-guide

## 자산 다운로드 URL
https://developers.kakao.com/tool/resource/login (「전체 다운로드」 ZIP — SVG · PNG)

## 다운로드 일자
받은 날은 [브랜드 자산 갱신 — 받은 날 · 만든 날](../../../docs/maintainer/brand-assets.md#받은-날--만든-날) 표에 적는다.

## 라이선스
Kakao Resources Terms (https://developers.kakao.com/policy/terms — 원문 텍스트는 `LICENSE.txt` 참조).

## 사전 검수 절차
Kakao 공식 디자인 가이드에는 로고 사용의 사전 검수 신청 절차가 없다 — 가이드를 지키면 된다. 앱 출시 전에 하는 Kakao 쪽 검수(비즈 앱 · 동의 항목)는 [직접 하는 일 — 로그인 수단 검수 · 인증](../../../docs/guide.md#로그인-수단-검수--인증) 에 있다.

계정 연결 절의 Kakao 아이콘 버튼은 검수 전에 [직접 하는 일 — 소셜 로고 · 브랜드 자산](../../../docs/guide.md#소셜-로고--브랜드-자산) 의 「Facebook 검수 전」 과 같은 방법으로 글자 버튼 모양으로 바꿀 수 있다.

## 아이콘 단독 사용

- 계정 정보 화면(설정 → 내 계정)의 「계정 연결」 절에 Kakao 가 아직 연결되지 않았을 때만, Kakao 로 로그인해 계정을 연결하는 원형 아이콘 버튼이 나온다 — 스크린 리더 라벨은 「카카오 연결」 이다.
- 크기는 지름 `48dp`(`kBrandIconButtonSize`) · 로고 상자 높이 = 지름 × 0.5 = 24dp 다 — 바탕 `#FEE500` · 심볼 · 심볼 색은 로그인 버튼과 같다.
- Kakao 디자인 가이드 본문에는 아이콘 단독형 정의가 없고, 공식 리소스 「전체 다운로드」 ZIP 에 원형 아이콘 자산(`kakao_login_light.svg` · rx 24 · 심볼 `#191919`)이 있다 — 킷 심볼 색은 가이드 색 표의 `#000000` 이고, 그 자산은 이 디렉토리에 싣지 않는다.
- 로고 상자(지름의 절반) 안에 그리는 심볼은 지름 대비 약 0.45 × 0.42 로, 그 공식 원형 자산의 심볼(지름 대비 0.458 × 0.4375)과 크기가 거의 같다.
- 글자 버튼 모양으로 바꾸려면 `lib/features/settings/presentation/account_screen.dart` 의 `AccountLinkingSection(leadingGap: true)` 에 `shape: AccountLinkingShape.button` 을 더한다.
- 한 화면에서 맞추느라 다르게 둔 곳은 [직접 하는 일 — 소셜 로고 · 브랜드 자산](../../../docs/guide.md#소셜-로고--브랜드-자산) 의 「알고 둔 가이드와의 차이」 에 있다.

## 미포함 변형 추가 절차
Kakao Resources Terms 는 로고 변형(색상 / 비율 / 회전)을 금지한다. 다른 변형(예: 라벨이 그림에 들어 있는 버튼 이미지)을 쓰려면 Kakao Developers 에 먼저 문의하고, 공식 리소스의 파일을 내용 그대로 이 디렉토리에 둔다. 하위 디렉토리를 새로 만들면 `pubspec.yaml` 의 `assets:` 에 그 디렉토리를 따로 등록한다(디렉토리 등록은 재귀가 아니다).

## 자산 freshness 갱신 빈도
1년마다 공식 페이지(https://developers.kakao.com/tool/resource/login)를 다시 확인한다 — 절차는 [브랜드 자산 갱신 — freshness 갱신](../../../docs/maintainer/brand-assets.md#freshness-갱신) 에 있다.

## 디렉토리 구조
```
assets/brand/kakao/
├── btn_signin_icon.svg   (말풍선 심볼 SVG, viewBox 0 0 20 20, fill=currentColor)
├── LICENSE.txt
└── README.md  (이 파일)
```

로고는 디렉토리 바로 아래 한 장이고, 언어 · 밝기별 하위 디렉토리는 없다. 라벨은 그림에 들어 있지 않다 — ARB 문구를 `BrandedSocialButton` 이 그리고, 심볼 색도 그릴 때 정한다.

## 주의
- 로고를 직접 그려 만들지 않는다 — Kakao 공식 리소스의 그림만 쓴다.
- 공식 BI 자산(Kakao 공식 SDK · 공식 리소스 ZIP 의 SVG · PNG)의 그림을 바꾸지 않는다.
