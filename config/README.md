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
   **+ `ios/Flutter/{flavor}.xcconfig` 의 NAVER 3변수** (`NAVER_CLIENT_ID` /
   `NAVER_CLIENT_SECRET` / `NAVER_URL_SCHEME`) 도 같은 값으로 교체 — iOS 는
   이 xcconfig 가 실제 출처라 json 만 고치면 반영되지 않는다 (아래 절 참조).
2. `enabledAuthProviders` 의 CSV 에 `naver` / `line` 토큰 명시적 추가
   (예: `"google,apple,facebook,kakao,naver,line"`).
3. Firebase Secret Manager 에 `LINE_CHANNEL_ID` (Phase 17+ 진입 시
   `LINE_CHANNEL_SECRET` 도 함께) + `NAVER_CLIENT_SECRET` · `NAVER_CLIENT_ID`
   (Phase 16.5 — Naver 웹 경로 서버 교환) 등록.

## `kakao` / `google` / `apple` / `facebook` 의 차이

위 4 provider 는 stg / prod CSV 에 포함되어 있지만, 같이 placeholder
키로 동작 → 운영자는 동일 절차로 실제 키 교체 의무. 본 README 의 정책
설명은 CSV 토큰 부재 여부와 무관하게 모든 provider 에 적용.

## Naver 키의 소비처 (Phase 16.2 · Phase 16.5)

`config/*.json` 의 naver 키는 두 경로가 나눠 쓴다 — NAVER 앱 설치 단말의 **SDK
1-tap 경로**(`naver_login_flutter` 4.0.0, 빌드 타임 native 설정)와 미설치 단말의
**킷 웹 경로**(Phase 16.5 — `flutter_web_auth_2` + Cloud Function
`naverWebCustomToken`).

| 키 | SDK 1-tap 소비처 (native) | 킷 웹 경로 소비처 (Dart / Android manifest) | 비고 |
|----|---------------------------|---------------------------------------------|------|
| `naverClientId` | `android/app/build.gradle.kts` 가 dart-defines 에서 읽어 string resource 로 주입 → manifest meta-data 가 참조 | `AppConfig.naverClientId`(웹 경로 authorize URL 의 `client_id`, Phase 16.5) | iOS SDK 는 xcconfig `NAVER_CLIENT_ID` 를 쓴다 — 값이 같아야 한다 |
| `naverClientSecret` | 위와 동일 (Android string resource) | **없음** — Dart 는 읽지 않는다. 웹 경로의 교환은 서버 Secret Manager `NAVER_CLIENT_SECRET` 이 한다 | Secret Manager 와 **같은 값 2본** (SDK 1-tap 이 native 설정을 요구하므로 앱 번들에서 없앨 수 없다) |
| `appName` | 위와 동일 — Android 동의 화면의 앱 이름으로도 쓰인다 | 없음 | iOS 는 `DISPLAY_NAME` 을 따른다 |
| `naverUrlScheme` | iOS 는 xcconfig `NAVER_URL_SCHEME` 가 실제 출처 (json 은 기록처) | `AppConfig.naverWebCallbackScheme` + Android manifest placeholder `naverWebCallbackScheme`(gradle 이 dart-defines 에서 공급 → `flutter_web_auth_2` `CallbackActivity` intent-filter) | 웹 경로 콜백 scheme 겸용 — **소문자 영숫자**(RFC 3986)여야 한다 |

**Firebase Secret Manager (서버 쪽, 2종):** `NAVER_CLIENT_SECRET`(교환 · revoke —
Phase 16.5 부터 사용처 1) · `NAVER_CLIENT_ID`(Phase 16.5 신규 — json 의
`naverClientId` 와 같은 값). 등록 절차는 `docs/manual.md` Naver 8단계.

- **iOS SDK 는 `ios/Flutter/{flavor}.xcconfig` 가 실제 출처다.** 플러그인이 Dart 가
  뜨기 전(`register(with:)` 시점)에 `Info.plist` 를 직접 읽기 때문에 값이 빌드
  설정에서 와야 한다. 그래서 `NAVER_CLIENT_ID` · `NAVER_CLIENT_SECRET` ·
  `NAVER_URL_SCHEME` 3변수를 xcconfig 에 따로 넣는다 — json 과의 값 중복은
  **의도된 것**이며 (Kakao · Facebook 과 같은 방식), 두 값이 어긋나면 Android 와
  iOS 가 (그리고 iOS 안에서도 1-tap 과 웹 경로가) 서로 다른 앱으로 로그인한다.
  dev 는 계약 테스트 `T-16.5-NATIVE-01` 이 로컬 실 키 파일로 일치를 단언한다.
- **Dart 가 읽는 naver 키는 `naverClientId` · `naverUrlScheme` 두 개뿐이다
  (Phase 16.5).** 둘 다 공개 값이다 — `client_id` 는 RFC 6749 상 공개 식별자이고
  authorize URL 에 어차피 평문으로 실린다. 16.2 D-04 의 본질인 「secret 을 Dart
  번들에 두지 않는다」 는 그대로다: `naverClientSecret` 은 Dart 상수가 없다.
  json 을 바꾼 뒤에는 Android 빌드와 Dart dart-define 이 모두 새 값을 읽도록
  **다시 빌드**해야 한다.

## See Also

- `docs/manual.md` 의 "5단계 — Firebase Secret Manager 등록" / "소셜 로그인
  설정" 단락 — provider 별 신청 절차 + 키 메모 + 콘솔 설정.
- `lib/core/config/app_config.dart` — CSV 파싱 + provider gate 로직.
