# Kakao Brand Asset

Phase 13.1 — Kakao 로그인 버튼 공식 자상 (D-52 retroactive 정정).

## 공식 BI URL
https://developers.kakao.com/docs/ko/kakaologin/design-guide

## 자산 다운로드 URL
https://developers.kakao.com/tool/resource/login (PSD ZIP 패키지)

## 다운로드 일자
YYYY-MM-DD (Plan 13.1-08 실행 시 갱신 의무)

## 라이선스
Kakao Resources Terms (https://developers.kakao.com/policy/terms — verbatim 텍스트는 LICENSE.txt 참조). Phase 13.1 Plan 13-08 에서 LICENSE.txt 동봉 의무.

## 사전 검수 절차
N/A (Kakao 공식 디자인 가이드는 사전 검수 신청 미발견 — 자상 가이드 준수만 의무).

## 미포함 변형 추가 절차
Kakao Resources Terms 가 자상 변형 (색상 / 비율 / 회전) 금지 명시. 신규 변형 (예: 추가 라벨 텍스트) 도입 시 1) Kakao Developer Console 사전 문의 + 2) 별 phase 에서 처리.

## 자산 freshness 갱신 빈도
1년 권장 — `다운로드 일자` 1년 경과 시 https://developers.kakao.com/tool/resource/login 재방문 + 자상 갱신 여부 확인.

## 디렉토리 구조 (Plan 13.1-08 commit 후)
```
assets/brand/kakao/
├── ko/light/kakao_login_{1x,2x,3x}.png
├── en/light/kakao_login_{1x,2x,3x}.png
├── LICENSE.txt
└── README.md  (본 파일)
```

## 주의
- hand-crafted SVG 자체 생성 절대 금지 (R3 retroactive — `assets/icons/kakao_logo.svg` 폐기 사유).
- PNG `Image.asset` 직접 렌더 — `ColorFilter.mode(BlendMode.srcIn)` 적용 금지 (RESEARCH §Pitfall 7).
