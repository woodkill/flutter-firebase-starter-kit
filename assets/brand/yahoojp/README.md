# Yahoo! JAPAN Brand Asset

Phase 15 — Yahoo! JAPAN Login 버튼 공식 자상 (D-YJP-07). Yahoo!JP 는 sentinel
단계 미경유 신규 active 진입 (Phase 13.1 sentinel 패턴 미적용, Phase 14 LINE
의 sentinel → active 전환 패턴과 다른 — Plan 15-01 의 `.placeholder` 만
임시 sentinel 로 사용 후 Plan 15-04 에서 git rm). Symbol SVG + LICENSE.txt
동봉. Phase 13.3 Wave 4 패턴 (symbol SVG + ARB 자체 render — Case B) mirror.

## 공식 BI URL

https://developer.yahoo.co.jp/yconnect/loginbuttons.html (Yahoo! ID連携 >
ログインボタンのデザインガイドライン)

**Usage Guidelines (verbatim source):**
https://developer.yahoo.co.jp/yconnect/loginbuttonsterms.html (Yahoo! ID連携 >
ログインボタン利用規約 — Plan 15-04 시점 WebFetch 403 / 사이트 직접 접근 불가)

**Operator:** LY Corporation (Yahoo! JAPAN 서비스 운영 주체)

## 자산 다운로드 URL

https://s.yimg.jp/dl/developer_network/sample/download/yconnect/yahoo_japan_login_button.zip
(yahoo_japan_login_button.zip — PSD/AI/PNG/SVG 일괄 패키지. 599KB.

zip 안 구조:
  - SVG/ (10 파일: yahoo_japan_icon_{red,white}_{64,128,256}.svg +
    login_button_{small,medium,large}.svg)
  - PNG/ (10 파일: yahoo_japan_icon_{red,white}_{64,128,256}.png +
    login_button_{small,medium,large}.png)
  - yahoo_japan_icon.ai (Adobe Illustrator 원본 — layer 명 "アイコン（赤）#FF0033",
    "アイコン（白）（背景透過）")
  - Yahoo! JAPAN ID ログインボタン.pdf (공식 가이드 PDF, 약관 verbatim 발췌 출처)

본 starter-kit 은 zip 내 SVG/yahoo_japan_icon_white_64.svg (Symbol SVG, white
variant) 만 추출하여 `btn_signin_icon.svg` 로 동봉. 변환: `fill="white"` →
`fill="currentColor"` 일괄 치환 (Wave 4 ColorFilter.srcIn 패턴 호환 — 기하/
viewBox/path 수치 변경 0). 외 9 SVG (red variant + 256/128 해상도 + wide
baked-in login_button_*.svg) 미동봉. ARB 라벨 자체 render 채택 (Case B 결정,
Plan 15-04 사용자 sign-off). 19 언어 baked-in 라벨 wide PNG (Case A) 는 변형
금지 폭이 넓어 채택 보류.

## 다운로드 일자

2026-05-22 (Plan 15-04 checkpoint A1 사용자 sign-off 일자)

## 라이선스

Yahoo! JAPAN ID ログインボタン利用規約 — `LICENSE.txt` 의 verbatim 발췌 참조.
공식 PDF `Yahoo! JAPAN ID ログインボタン.pdf` (zip 안 번들) 단일 출처.

핵심 조항:
  - 「ボタン画像の改変禁止」: "ボタン画像をゆがめたり、ボタン内に配置されている画像、
    文字を書き換えたりしないでください。" / "サイズ、見た目が変わるような変更を
    加えないでください。"
  - 「クリアスペース」: "上下左右それぞれ10px以上のクリアスペース（余白）を確保
    してください。" / "Yahoo! JAPANアイコンの高さHの3分の1のサイズ以上の領域を
    確保してください。"
  - 「色の指定」: "アイコン（赤）#FF0033" / "文字色：#FFFFFF（白）"
  - 「禁止事項」: ロゴ・ボタンの商標 사용 금지 / 변형, 회전, 傾斜, 장식 금지 /
    다른 서비스 와 誤認 시키는 用途 사용 금지
  - LY Corporation (Yahoo! JAPAN 운영 주체) 의 서비스 약관 준수 의무

## 사전 검수 절차

Yahoo Developers Console (https://developer.yahoo.co.jp/yconnect/v2/) 의
Client 등록 단계에서 BI 자상 사용 자체 검수 절차 미명시 — 「ボタン画像の改変禁止」
조항 만 self-enforce. 단, UserInfo API 호출 (email scope 활성) 시 별도 심사
의무 — 사용자가 starter-kit fork 후 production 전환 시 「プライバシーポリシー
URL」 + 「利用規約URL」 등록 + 심사 신청 절차 수행 의무 (D-YJP-09 정정 lock,
manual.md D-YJP-22 (4) 단락 참조, Plan 15-07 산출물).

자세한 절차는 `docs/manual.md` 의 「Yahoo! JAPAN Login (Phase 15)」 단락
참조 (Phase 15 Plan 15-07 commit 예정).

## 미포함 변형 추가 절차

본 starter-kit 의 active locale = en/ko/ja 3 종 (D-YJP-08 lock — Yahoo! JAPAN
자체가 일본어 원철 서비스, 다국어 button label 가이드라인 강제 부재). 신규
언어 추가 시:
  1. `lib/l10n/app_{locale}.arb` 의 `authYahoojpSignIn` 키에 verbatim string
     추가 (자상 변경 0).
  2. `_renderYahoojpButton` widget spec 변경 0 — ARB 신규 키만 추가하면 자체
     render 자동 확장 (Phase 13.3 Wave 4 패턴 invariant).

red variant (#FF0033 bg) 채택 — 사용자 fork 후 white variant (#FFFFFF bg)
또는 별 자상 사용 시:
  1. zip 안 SVG/yahoo_japan_icon_red_64.svg (red variant) 추출 + fill 치환 후
     `btn_signin_icon.svg` 교체. 단 변형 금지 — geometry/viewBox/path 수치
     변경 0 의무.
  2. `_renderYahoojpButton` 의 `bgColor` (`0xFFFF0033`) 와 `symbolColor`
     (`0xFFFFFFFF`) 를 verbatim 사양에 맞춰 swap.
  3. LICENSE.txt 의 verbatim 발췌 변경 0 (공식 가이드 단일 truth source).

## 자산 freshness 갱신 빈도

1년 권장. `다운로드 일자` 1년 경과 시:
  1. https://developer.yahoo.co.jp/yconnect/loginbuttons.html 재방문 +
     yahoo_japan_login_button.zip 갱신 여부 확인.
  2. zip 의 SVG/yahoo_japan_icon_white_64.svg re-extract → `git diff` 로
     vector path 변경 확인. 차이 있을 시 `btn_signin_icon.svg` 재추출.
  3. https://developer.yahoo.co.jp/yconnect/loginbuttonsterms.html (사이트
     접근 회복 시) verbatim 변경 확인 → 차이 있을 시 `LICENSE.txt` 갱신.
  4. PDF (`Yahoo! JAPAN ID ログインボタン.pdf`) verbatim 변경 시 즉시
     갱신 의무 — freshness 주기 1년과 별도로 ad-hoc 갱신 가능.

## 디렉토리 구조 (Phase 15 Plan 15-04 이후)

```
assets/brand/yahoojp/
├── btn_signin_icon.svg   (D-YJP-07 vector symbol, viewBox 0 0 64 36, fill=currentColor)
├── LICENSE.txt           (Yahoo! JAPAN ID ログインボタン利用規約 verbatim 발췌)
└── README.md             (본 파일)
```

**Phase 15 sentinel 해제 (Plan 15-04 commit):**
- `assets/brand/yahoojp/.placeholder` git rm — D-YJP-07 invariant 충족.
- `lib/features/auth/presentation/_widgets/_brand_assets.dart` 의
  `kPlaceholderProviders` const list 변경 0 — Yahoo!JP 는 sentinel 단계
  미경유 신규 active 진입 (Phase 14 LINE sentinel 해제 패턴 직접 mirror
  미적용). Phase 16 (WeChat) 폐기 (2026-05-22) 으로 `kPlaceholderProviders
  = <String>[]` (empty, sentinel 의무 해소). 향후 placeholder 가 필요한
  신규 provider 진입 시 본 패턴 재적용.

## 사용자 검수 sign-off

- **2026-05-22 — Plan 15-04 checkpoint A1 사용자 sign-off:**
  - Case B 채택 (Symbol SVG + ARB 자체 render — Phase 14 LINE D-LINE-08 mirror,
    Case A wide baked-in PNG 변형 위험 회피)
  - bg color `#FF0033` (yahoo_japan_icon.ai layer 명 "アイコン（赤）#FF0033"
    verbatim — 사용자 정정 lock)
  - asset filename `assets/brand/yahoojp/btn_signin_icon.svg` (LINE/Kakao/Naver
    일관 명명)
  - LICENSE.txt PDF-only sign-off (zip 안 번들된 `Yahoo! JAPAN ID ログインボタン.pdf`
    단일 출처 — loginbuttonsterms.html WebFetch 불가 사실을 Notes 2/5 명시 유지)

## 주의

- third-party 출처 (wikipedia / seeklogo / 블로그 등) 채택 절대 금지
  (memory `feedback_official_bi_verification`).
- hand-crafted SVG 자체 생성 절대 금지 — Yahoo! JAPAN 공식 zip
  (`yahoo_japan_login_button.zip`) 의 SVG/yahoo_japan_icon_white_64.svg
  추출 결과만 채택 (memory `feedback_psd_ai_vector_extraction`).
- `btn_signin_icon.svg` 의 viewBox `0 0 64 36` + `fill="currentColor"` 는
  Wave 4 ColorFilter.srcIn 동작 의무 (BrandedSocialButton color enforcement).
  사용자가 svg 수동 편집 금지 — 재추출 워크플로우 (zip 안 SVG 직접 추출 +
  fill 치환만) 만 허용.
