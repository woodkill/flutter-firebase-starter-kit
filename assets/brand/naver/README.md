# Naver Brand Asset

Phase 13.1 — NAVER ID 로그인 버튼 공식 자상 (R1 retroactive 정정).

## 공식 BI URL
https://developers.naver.com/docs/login/bi/bi.md (NAVER ID 로그인 BI — `#03A94D`)

**D-Note (R1 / 13.1-CONTEXT specifics):** 회사 브랜드 (`#03C75A`, NAVER Corp + NCloud SSO) ↔ 로그인 버튼 (`#03A94D`, NAVER ID 로그인 BI) 컨텍스트 분리. Phase 13 단계는 third-party 출처 채택 오류, Phase 13.1 정정.

## 자산 다운로드 URL
https://developers.naver.com/docs/login/bi/bi.md → "디자인 가이드" 단락 (PNG + Figma + AI export)

## 다운로드 일자
YYYY-MM-DD (Plan 13.1-08 실행 시 갱신 의무)

## 라이선스
NAVER Brand License (LICENSE.txt 의 verbatim 라이선스 텍스트). Plan 13.1-08 에서 LICENSE.txt 동봉 의무.

## 사전 검수 절차
사용자 책임 — Naver BI 페이지에 일부 사용 시 사전 검수 신청 절차 명시 가능 (사전 조사 결과 미발견, 사용자 직접 확인 의무 — `docs/manual.md` 의 "Brand Asset Management" 단락 참조).

## 미포함 변형 추가 절차
Naver BI 가 자상 변형 (색상 / 회전 / 비율) 금지 명시. 신규 변형 도입 시 1) Naver Developer Console 사전 검수 + 2) 별 phase 에서 처리.

## 자산 freshness 갱신 빈도
1년 권장.

## 디렉토리 구조 (Plan 13.1-08 commit 후)
```
assets/brand/naver/
├── ko/light/naver_login_{1x,2x,3x}.png
├── ko/dark/naver_login_{1x,2x,3x}.png
├── en/light/naver_login_{1x,2x,3x}.png
├── en/dark/naver_login_{1x,2x,3x}.png
├── LICENSE.txt
└── README.md
```
