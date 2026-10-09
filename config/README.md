# `config/` — Flavor 별 환경 설정

`--dart-define-from-file` 방식으로 빌드 타임에 주입되는 환경 변수 (Flavor:
`dev` / `stg` / `prod`). `*.example.json` 파일은 placeholder 만 tracked,
실제 키가 들어간 `dev.json` / `stg.json` / `prod.json` 은 `.gitignore` 처리.

## `enabledAuthProviders` — 켤 로그인 수단

로그인 화면에 보일 소셜 로그인을 쉼표로 구분해 적는다. 쓸 수 있는 값은
`google` · `apple` · `facebook` · `kakao` · `naver` · `line` 이다.

```json
"enabledAuthProviders": "google,kakao"
```

- **기본값은 빈 문자열이다.** 세 example 파일(`dev` · `stg` · `prod`) 모두 이
  값이 비어 있어서, 복사한 직후 로그인 화면에는 「이메일로 계속」 만 보인다.
- **켠 provider 만 키 · 콘솔 등록이 필요하다.** 끈 provider 의 키는 비워 둬도
  빌드 · 실행된다. provider 를 켜기 전에 그 provider 의 키를 채운다.
- **Cloud Functions secret 은 끈 provider 것도 만들어 둔다.** 함수 배포는 코드에
  선언된 secret 이 Secret Manager 에 모두 있어야 진행된다. 끈 provider 의
  secret 은 자리표시 값이면 된다 — 일괄 생성 명령은 `docs/manual.md`
  「[로그인 수단 켜고 끄기](../docs/manual.md#로그인-수단-켜고-끄기)」 의 「켜기」 ④.
- **값은 빌드 때 들어간다.** 바꾼 뒤에는 앱을 다시 빌드한다.
- **출시 뒤 provider 를 끌 때는 이 값을 고치지 않는다.** Remote Config kill
  switch 로 끈다 — `docs/manual.md` 의 [RC Kill Switch 운영 절차](../docs/manual.md#rc-kill-switch-운영-절차-emergency-disable).
  CSV 에서 빼면 그 provider 로 가입한 사용자는 로그인 · 재인증 · 회원탈퇴를
  할 수 없다.

provider 마다 켤 때 필요한 것과 함수 배포(`bash scripts/deploy_functions.sh <flavor>`)는 `docs/manual.md` 「[로그인 수단 켜고 끄기](../docs/manual.md#로그인-수단-켜고-끄기)」.

## `brandColor` — 브랜드 색

앱 · 인증 결과 페이지 · 킷이 보내는 인증 메일이 같이 쓰는 브랜드 색이다.

```json
"brandColor": "#673AB7"
```

- **형식은 `#RRGGBB` 이다.** `#` 과 16진수 6자리(대소문자 무관)만 쓴다. 앞뒤
  공백 · `#` 없는 값 · 3자리 축약은 틀린 형식이다.
- **비우거나 형식이 틀리면 `#673AB7` 로 동작한다.** 세 example 파일의 값도
  `#673AB7` 이라, 키를 바꾸지 않으면 앱 색은 그대로다.
- **앱은 이 색을 seed 로 Material 3 색을 계산하고, 결과 페이지 · 메일은 이 색을
  그대로 칠한다.** 그래서 앱 버튼 색과 페이지 · 메일 버튼 색이 조금 다를 수 있다.
- **값은 빌드 때 들어간다.** 바꾼 뒤에는 앱을 다시 빌드하고, 결과 페이지 · 메일도
  다시 배포한다.

## `emailDelivery` — 인증 메일 발송 모드

이메일 인증 · 비밀번호 재설정 메일을 누가 보내는지 고른다.

```json
"emailDelivery": ""
```

- **값은 `firebase` · `kit` · 빈 문자열이다.** 빈 문자열은 `firebase` 와 같다 —
  세 example 파일 모두 빈 문자열이다.
- **`firebase`(기본값)** — Firebase 가 기본 템플릿으로 보낸다. 추가 설정이 없다.
- **`kit`** — 킷이 앱 이름 · `brandColor` · 로고로 메일을 만들어 내 발송 서비스로
  보낸다. 발송 서비스 · 확장 설정이 필요하다 — `docs/manual.md` 「인증 메일 발송
  모드 켜고 끄기」.
- **그 밖의 값은 배포 스크립트가 거부한다.** 대소문자 · 공백도 그대로 비교하므로
  `Kit` · ` kit` 도 틀린 값이다. debug 빌드 앱도 이 값을 읽는 순간 오류로 알린다.
- **값은 빌드 때 들어간다.** 바꾼 뒤에는 앱을 다시 빌드한다.

## `firebaseWebApiKey` — 결과 페이지의 Firebase 웹 API 키

`kit` 발송 모드의 결과 페이지가 Firebase Authentication 을 부를 때 쓰는 키다.

```json
"firebaseWebApiKey": "YOUR_FIREBASE_WEB_API_KEY_HERE"
```

- **`emailDelivery` 가 `kit` 일 때만 채운다.** `firebase` 모드(빈 값 포함)는
  결과 페이지를 빌드하지 않으므로 자리표시 값 그대로 둬도 된다.
- **값은 Google Cloud Console → API 및 서비스(APIs & Services) → 사용자 인증 정보(Credentials)
  의 「API 키」 표에 있는 `Browser key (auto created by Firebase)` 다.** 「키 표시」 로 연
  창에서 복사한다. `AIza` 로 시작한다. Android · iOS 앱 전용으로 제한한 키는 브라우저에서
  거부되고, 웹사이트(HTTP 리퍼러) 제한이 걸린 키도 이 페이지에서 거부된다(페이지가
  Referer 를 보내지 않는다). 애플리케이션 제한사항이 「없음」 인 키(Firebase 가 만든
  Browser key 기본값)를 쓴다. 공개 값이라 결과 페이지 산출물에 들어간다.
- **결과 페이지는 이 키로만 Firebase 를 초기화한다.** 메일 링크에 실린 키는 쓰지
  않으므로, 다른 프로젝트에서 만든 링크는 이 페이지에서 「사용할 수 없는 링크」
  로 끝난다.
- **비었거나 자리표시 값이면 결과 페이지 빌드가 `FAIL:` 로 멈춘다.** 값은 출력하지
  않는다.
- **바꾼 뒤에는 결과 페이지를 다시 배포한다** — `docs/manual.md` 「인증 결과 페이지
  바꾸기」 의 「바꾸고 배포하기」 ③.

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
| `naverUrlScheme` | iOS 는 xcconfig `NAVER_URL_SCHEME` 가 실제 출처 (json 은 기록처) | `AppConfig.naverWebCallbackScheme` + Android manifest placeholder `naverWebCallbackScheme`(gradle 이 dart-defines 에서 공급 → 킷 `WebAuthCallbackActivity`(flutter_web_auth_2 콜백 relay) intent-filter) | 웹 경로 콜백 scheme 겸용 — **소문자 영숫자**(RFC 3986)여야 한다 |

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
