# Pretendard

## Asset

- `PretendardVariable.ttf` — Pretendard v1.3.9 Variable Font (`wght` axis 100-900), 6,739,336 bytes
- `OFL.txt` — SIL Open Font License 1.1

## Source

- Repo: https://github.com/orioncactus/pretendard (orioncactus / Kil Hyung-jin)
- Release: `v1.3.9` (2023-11-05)
- Download URL: https://github.com/orioncactus/pretendard/releases/download/v1.3.9/Pretendard-1.3.9.zip
- Path in archive: `public/variable/PretendardVariable.ttf`

## License

SIL Open Font License 1.1 — see `OFL.txt`. Permits embedding in software programs and redistribution.

## Adoption Rationale (Phase 13.3 Wave 4 Step 3)

NAVER ID 로그인 BI 공식 자상 (`NAVER_login_EN.zip` 의 `NAVER_login_Light_EN_green_center_H48.png`) 의 라벨 글리프 시각 비교 결과 **Pretendard ExtraBold/Bold** 가 가장 부합 (직선적 sans-serif + Bold weight + 한국 design 표준). 후보 비교 — Roboto Black (stroke 굵기 차이) / Apple SD Gothic Neo (Bold weight 부족) / Inter (project bundle ExtraBold 미보유) → Pretendard 채택.

NAVER 정문 (`developers.naver.com/docs/login/bi/bi.md`) 의 `button.label.fontFamily` 는 미명시 (자유). 사용자 결정 2026-05-16 — 공식 PNG 글리프 시각 부합 우선.

## Flutter Usage

`pubspec.yaml` 의 `flutter > fonts` entry 로 등록. `fontWeight` 명시 시 wght axis 자동 매핑:
- `FontWeight.w400` → Regular
- `FontWeight.w500` → Medium
- `FontWeight.w700` → Bold
- `FontWeight.w800` → ExtraBold
- `FontWeight.w900` → Black

```dart
const TextStyle(
  fontFamily: 'Pretendard',
  fontSize: 18,
  fontWeight: FontWeight.w800,
)
```

## Variable Font Axis

Single TTF, `wght` axis 100-900. Flutter 가 `fontWeight` 명시 시 axis 값 자동 매핑.
