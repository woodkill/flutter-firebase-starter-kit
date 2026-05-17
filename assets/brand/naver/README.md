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

## 디렉토리 구조 (Phase 13.3 Wave 3 이후)
```
assets/brand/naver/
├── btn_signin_icon.svg   (D-107 N symbol SVG, Wave 4 Step 2 분리)
├── LICENSE.txt
└── README.md
```

**Phase 13.3 Wave 3 (commit c73c9a3) supersede:** 이전 wide 자상 (ko/en ×
light/dark × h48/h56_wide.png) 8 file 폐기. 사유: NAVER 공식 N symbol SVG
inline 패턴 채택 (Wave 1 D-107) + Wave 4 Step 2 외부 자산 파일 분리. wide
자상 통째 buttons 패턴 → symbol SVG + ARB 라벨 외부 layer + render-time 색/폰트
hardcode 패턴 전환. locale/theme leaf 디렉토리 (`ko/`, `en/`, `light/`, `dark/`)
모두 폐기.

**Phase 13.3 WR-03 정정 (2026-05-17):** 빈 leaf 디렉토리 (`en/`) 가 git
untracked 형식으로 잔존하던 잔재를 cleanup. **single-level asset directory** —
locale/theme leaf 폐기 후 자상은 디렉토리 root 에 commit. 사용자가 future
locale-specific asset 추가 시점에 새로 디렉토리 생성 + `pubspec.yaml` 의
`assets:` 단락에 신규 leaf 명시 등록 의무 (Flutter directory 등록은 단일 레벨,
재귀 아님).
