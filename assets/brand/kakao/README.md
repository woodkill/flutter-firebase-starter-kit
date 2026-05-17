# Kakao Brand Asset

Phase 13.1 — Kakao 로그인 버튼 공식 자상 (D-52 retroactive 정정).

## 공식 BI URL
https://developers.kakao.com/docs/ko/kakaologin/design-guide

## 자산 다운로드 URL
https://developers.kakao.com/tool/resource/login (PSD ZIP 패키지)

## 다운로드 일자
2026-05-09 (Plan 13.1-07 checkpoint commit)

## 라이선스
Kakao Resources Terms (https://developers.kakao.com/policy/terms — verbatim 텍스트는 LICENSE.txt 참조). Phase 13.1 Plan 13-08 에서 LICENSE.txt 동봉 의무.

## 사전 검수 절차
N/A (Kakao 공식 디자인 가이드는 사전 검수 신청 미발견 — 자상 가이드 준수만 의무).

## 미포함 변형 추가 절차
Kakao Resources Terms 가 자상 변형 (색상 / 비율 / 회전) 금지 명시. 신규 변형 (예: 추가 라벨 텍스트) 도입 시 1) Kakao Developer Console 사전 문의 + 2) 별 phase 에서 처리.

## 자산 freshness 갱신 빈도
1년 권장 — `다운로드 일자` 1년 경과 시 https://developers.kakao.com/tool/resource/login 재방문 + 자상 갱신 여부 확인.

## 디렉토리 구조 (Phase 13.3 Wave 3 이후)
```
assets/brand/kakao/
├── btn_signin_icon.svg   (D-107 symbol SVG, Wave 4 Step 2 분리)
├── LICENSE.txt
└── README.md  (본 파일)
```

**Phase 13.3 Wave 3 (commit c73c9a3) supersede:** 이전 wide 자상 (ko/en/light/
kakao_login_*_wide.png) 18 file 폐기. 사유: logo-only symbol SVG inline 패턴
채택 (Wave 1 D-107) + Wave 4 Step 2 외부 자산 파일 분리. wide 자상 통째
buttons 패턴 (자상에 배경+라벨+로고 baked-in) → symbol SVG + ARB 라벨 외부
layer + render-time 색/폰트 hardcode 패턴 전환. locale/theme leaf 디렉토리
(`ko/`, `en/`, `light/`, `dark/`) 모두 폐기.

**Phase 13.3 WR-03 정정 (2026-05-17):** 빈 leaf 디렉토리 (`en/`, `ko/`) 가
git untracked 형식으로 잔존하던 잔재를 cleanup. **single-level asset
directory** — locale/theme leaf 폐기 후 자상은 디렉토리 root 에 commit. 사용자
가 future locale-specific asset 추가 시점에 새로 디렉토리 생성 + `pubspec.yaml`
의 `assets:` 단락에 신규 leaf 명시 등록 의무 (Flutter directory 등록은 단일
레벨, 재귀 아님).

## 주의
- hand-crafted SVG 자체 생성 절대 금지 (R3 retroactive — `assets/icons/kakao_logo.svg` 폐기 사유).
- 공식 BI 자상 (Kakao 공식 SDK strings/PSD) verbatim 유지 의무.
