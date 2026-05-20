# `config/` — Flavor 별 환경 설정

`--dart-define-from-file` 방식으로 빌드 타임에 주입되는 환경 변수 (Flavor:
`dev` / `stg` / `prod`). `*.example.json` 파일은 placeholder 만 tracked,
실제 키가 들어간 `dev.json` / `stg.json` / `prod.json` 은 `.gitignore` 처리
(MEMORY `project_starter_kit_config_secrets`).

## `enabledAuthProviders` 정책

CSV 문자열로 활성 소셜 로그인 provider 를 list. **Flavor 별 의도된 차이:**

| Flavor | 기본 CSV | 이유 |
|--------|----------|------|
| `dev`  | `google,apple,facebook,kakao,naver,line` | 전체 provider 검증용 |
| `stg`  | `google,apple,facebook,kakao` | `naver` / `line` 는 의도된 부재 |
| `prod` | `google,apple,facebook,kakao` | `naver` / `line` 는 의도된 부재 |

**Why naver/line 가 stg/prod 에서 빠져 있나? (IN-04 — Phase 14 review):**

starter-kit 은 dev flavor 만 실제 Firebase 프로젝트에 연결되어 있고
(MEMORY `project_firebase_dev_only`), `naverClientId` / `lineChannelId`
는 stg/prod 에서 placeholder 상태 (`YOUR_..._HERE`). placeholder 로 LINE
/ NAVER 버튼을 활성화하면 첫 `login()` 호출에서 silent UX 실패 → 운영자
실수 회피 위해 **비활성화가 안전 default**.

starter-kit 을 clone 한 운영자가 stg / prod 출시 시:
1. `config/stg.json` (또는 `prod.json`) 의 `naverClientId` / `naverClientSecret`
   / `naverUrlScheme` / `lineChannelId` 를 실제 발급 키로 교체.
2. `enabledAuthProviders` 의 CSV 에 `naver` / `line` 토큰 명시적 추가
   (예: `"google,apple,facebook,kakao,naver,line"`).
3. Firebase Secret Manager 에 `LINE_CHANNEL_ID` (Phase 17+ 진입 시
   `LINE_CHANNEL_SECRET` 도 함께) + `NAVER_CLIENT_SECRET` 등록.

## `kakao` / `google` / `apple` / `facebook` 의 차이

위 4 provider 는 stg / prod CSV 에 포함되어 있지만, 같이 placeholder
키로 동작 → 운영자는 동일 절차로 실제 키 교체 의무. 본 README 의 정책
설명은 CSV 토큰 부재 여부와 무관하게 모든 provider 에 적용.

## See Also

- `docs/manual.md` 의 "5단계 — Firebase Secret Manager 등록" / "소셜 로그인
  설정" 단락 — provider 별 신청 절차 + 키 메모 + 콘솔 설정.
- `lib/core/config/app_config.dart` — CSV 파싱 + provider gate 로직.
