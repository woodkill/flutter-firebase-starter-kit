# Naver Brand Asset

Phase 13.1 — NAVER ID 로그인 버튼 공식 자상 (R1 retroactive 정정).

## 공식 BI URL
https://developers.naver.com/docs/login/bi/bi.md (NAVER ID 로그인 BI — `#03A94D`)

**D-Note (R1 / 13.1-CONTEXT specifics):** 회사 브랜드 (`#03C75A`, NAVER Corp + NCloud SSO) ↔ 로그인 버튼 (`#03A94D`, NAVER ID 로그인 BI) 컨텍스트 분리. Phase 13 단계는 third-party 출처 채택 오류, Phase 13.1 정정.

## 자산 다운로드 URL
https://developers.naver.com/docs/login/bi/bi.md → "디자인 가이드" 단락 (PNG + Figma + AI export)

## 다운로드 일자
2026-05-09 (Plan 13.1-07 checkpoint commit)

## 라이선스
NAVER Brand License (LICENSE.txt 의 verbatim 라이선스 텍스트). Plan 13.1-08 에서 LICENSE.txt 동봉 의무.

## 사전 검수 절차
사용자 책임 — Naver BI 페이지에 일부 사용 시 사전 검수 신청 절차 명시 가능 (사전 조사 결과 미발견, 사용자 직접 확인 의무 — `docs/manual.md` 의 "Brand Asset Management" 단락 참조).

## 미포함 변형 추가 절차
Naver BI 가 자상 변형 (색상 / 회전 / 비율) 금지 명시. 신규 변형 도입 시 1) Naver Developer Console 사전 검수 + 2) 별 phase 에서 처리.

## 자산 freshness 갱신 빈도
1년 권장.

## 디렉토리 구조 (Plan 13.1-07 commit 후)
```
assets/brand/naver/
├── ko/light/naver_login_h{48,56}_wide.png
├── ko/dark/naver_login_h{48,56}_wide.png
├── en/light/naver_login_h{48,56}_wide.png
├── en/dark/naver_login_h{48,56}_wide.png
├── LICENSE.txt
└── README.md
```

**자산 형식 결정 (Plan 13.1-07 retro):** Naver 공식 자상은 5차원 매트릭스 (theme × locale × color × variant × height) 로 **64 PNG** 제공. 본 starter-kit 은 Kakao 의 2배 차원 (Kakao = light only × locale × size × wide; Naver 는 + dark theme 추가) 로 채택 — `locale(ko/en) × theme(light/dark) × height(H48/H56) × variant(wide) = 8 PNG`.

**자상 색 ↔ theme 매핑** (Naver BI 사용 패턴):
- `NaverTheme.light` → `Light_${LANG}_green_wide_H{48,56}` (흰 배경 위 그린 BI)
- `NaverTheme.dark` → `Dark_${LANG}_white_wide_H{48,56}` (검정 배경 위 흰 BI)

**Default load (코드):** `naver_login_h48_wide.png` (Material Design 표준 button height, BrandedSocialButton 와 일치). H56 은 future-proof commit — CTA emphasis 시 향후 size 파라미터 노출 가능.

**미포함 변형 (NaverBI 64 PNG 중 commit 안 된 것):**
- `narrow` / `center` / `icon` variant — wide 만 채택 (BrandedSocialButton 가로 텍스트 버튼 디자인과 일치)
- `Light_*_white_*` (흰 배경 위 흰 자상 — 가시성 부족) / `Dark_*_green_*` (검정 위 그린 — Naver BI 권고 외)

**공식 명명 보존 vs starter-kit 명명:** 공식 파일명 (`NAVER_login_Light_KR_green_wide_H48.png`) 대신 starter-kit 의 일관 명명 패턴 (`naver_login_h48_wide.png`) 채택 — 디렉토리 구조가 이미 `theme/locale` 분기를 표현하므로 파일명에서 중복 차원 제거. 공식 파일명 ↔ starter-kit 명명 매핑은 LICENSE.txt 에 verbatim 기록.
