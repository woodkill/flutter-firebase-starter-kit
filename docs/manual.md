---
last_updated: 2026-05-03
phases: [09 (Facebook), 11 (Cloud Functions + RC), 12 (Kakao Login)]
audience: starter kit 사용자 (clone 후 새 프로젝트 시작 시점)
---

# Flutter + Firebase Starter Kit 사용자 매뉴얼

이 문서는 starter kit 을 clone 한 사용자가 dev / stg / prod 3 flavor 모두에서
인증·푸시·원격설정·소셜 로그인 등을 동작시키기 위한 외부 콘솔 / 키 / 자산
설정 절차를 phase 별로 정리한 단일 진입점입니다.

각 단락은 **clone 후 즉시 동작 → starter kit 의 핵심 가치** 에 부합하도록
"왜" / "무엇을" / "어디서" / "흔한 실수" 4 축으로 작성되었습니다.

> **flavor 정책 (Phase 12 D-22, memory `project_firebase_dev_only`)**
>
> Starter kit 은 **dev flavor 만 실제 Firebase / 외부 서비스에 연결** 합니다.
> stg / prod 는 placeholder 만 포함하며, 사용자가 production 진입 시점에
> 자체 Firebase 프로젝트 + 외부 콘솔 등록 + 키 주입을 수행해야 합니다.

---

## 목차

1. [Kakao Login (Phase 12)](#kakao-login-phase-12)
2. [Phase 13~16 — Custom Token Provider 추가 가이드 (stub)](#phase-1316--custom-token-provider-추가-가이드-stub)
3. [Cloud Functions 배포 / Remote Config Kill Switch (Phase 11-04)](#cloud-functions-배포--remote-config-kill-switch-phase-11-04)
4. [Kakao Brand Asset 라이센스 / 출처 (Phase 12-07)](#kakao-brand-asset-라이센스--출처-phase-12-07)
5. [회원탈퇴 cleanup TODO (Phase 17)](#회원탈퇴-cleanup-todo-phase-17)

---

## Kakao Login (Phase 12)

Kakao 로그인은 Custom Token 방식으로 구현되어 있습니다. 사용자가 KakaoTalk
설치 단말에서는 1-tap 로그인 (`loginWithKakaoTalk`), 미설치 단말에서는 카카오
계정 웹뷰 fallback (`loginWithKakaoAccount`) 로 자동 분기합니다.

OIDC ID Token 을 Cloud Function (`kakaoCustomToken`, asia-northeast3) 이
자체 검증 (jose + JWKS singleton) 후 Firebase Identity Index 에 등록하고
Firebase Custom Token 을 발급, 클라이언트가 `signInWithCustomToken` 으로
세션을 시작합니다.

### 1단계 — Kakao Developer Console 앱 등록

콘솔: <https://developers.kakao.com/console/app>

1. **앱 생성 (dev flavor)**
   - "내 애플리케이션" → "애플리케이션 추가하기"
   - 앱 이름 / 사업자명 입력 (개인 사업자도 가능, 미입력 시 개인 모드)

2. **플랫폼 등록 — Android**
   - "내 애플리케이션 > 앱 설정 > 플랫폼" → Android 추가
   - 패키지명: `com.example.flutter_starter_kit.dev` (dev flavor — 본 starter
     kit 의 ApplicationId. `android/app/build.gradle.kts` 에서 확인)
   - **키 해시** 등록 (필수 — 미등록 시 `Invalid key hash` 런타임 에러):
     ```bash
     # debug 키 해시
     keytool -exportcert -alias androiddebugkey \
       -keystore ~/.android/debug.keystore \
       -storepass android -keypass android \
       | openssl sha1 -binary | openssl base64

     # release 키 해시 (production 빌드 전 등록)
     keytool -exportcert -alias <your-alias> \
       -keystore <your-keystore.jks> \
       | openssl sha1 -binary | openssl base64
     ```
     자세한 절차는 Kakao 공식 문서 참조:
     <https://developers.kakao.com/docs/latest/ko/getting-started/sdk-android#step3-add-key-hash>

3. **플랫폼 등록 — iOS**
   - 같은 화면에서 iOS 추가
   - 번들 ID: `com.example.flutterStarterKit.dev` (dev flavor — iOS 의
     CFBundleIdentifier. `ios/Flutter/dev.xcconfig` 의 `BUNDLE_ID_SUFFIX`
     기준)

4. **카카오 로그인 활성화**
   - "내 애플리케이션 > 제품 설정 > 카카오 로그인" → "활성화 설정" ON

5. **Redirect URI 등록**
   - 같은 화면 하단의 "Redirect URI" 섹션
   - 형식: `kakao{nativeAppKey}://oauth` (예: `kakao1234567890abcdef://oauth`)
   - **흔한 실수**: nativeAppKey 가 아닌 REST API 키를 넣는 경우 — 반드시
     "앱 키 > 네이티브 앱 키" 값 사용

6. **OpenID Connect (OIDC) 활성화 — ⚠ Pitfall 1**
   - "내 애플리케이션 > 제품 설정 > 카카오 로그인 > 보안" → "OpenID Connect
     활성화" 토글 **ON**
   - **활성화 누락 시:** `OAuthToken.idToken` 이 항상 null → AuthRepository 가
     `ServiceUnavailable` 반환 → LoginScreen 의 FormErrorBanner 가
     `errorServiceUnavailable` 표시. silent failure 처럼 보이는 가장 흔한
     원인.

7. **동의항목 설정 (Phase 12 D-03)**
   - "내 애플리케이션 > 제품 설정 > 카카오 로그인 > 동의항목"
   - **닉네임 (`profile_nickname`)** — "필수 동의" 로 설정
   - **카카오계정 이메일 (`account_email`)** — "필수 동의" 로 설정
   - 그 외 항목 (프로필 사진, 생일, 성별 등) 은 starter kit 기본 범위 외
     (필요 시 사용자가 추가)

### 2단계 — `config/dev.json` 키 주입

콘솔 등록 완료 후 발급받은 두 키를 starter kit 의 dev flavor config 에
주입합니다.

`config/dev.json`:
```json
{
  "enabledAuthProviders": "google,apple,facebook,kakao",
  "kakaoNativeAppKey": "여기에_네이티브_앱_키_붙여넣기"
}
```

- **kakaoNativeAppKey** — "내 애플리케이션 > 앱 설정 > 앱 키 > 네이티브 앱 키"
- **REST API 키** 는 `config/dev.json` 에 넣지 마세요 — 다음 4단계의
  Firebase Secret Manager 로만 주입.

iOS xcconfig (`ios/Flutter/dev.xcconfig`) 도 동일 키를 별도 빌드 설정으로
주입해야 합니다 (Phase 12-01 산출):
```
KAKAO_NATIVE_APP_KEY=여기에_네이티브_앱_키_붙여넣기
```
(따옴표 없이 = 뒤에 값만)

> **stg / prod 는?** dev 와 동일한 절차로 사용자 자체 Kakao 앱을 별도 등록
> + 키 주입. starter kit 의 stg/prod config 는 placeholder 만 포함합니다
> (D-22 — `project_firebase_dev_only` 정책).

### 3단계 — Firestore 보안 규칙 배포 (Phase 12-06)

starter kit 의 `firestore.rules` (Phase 12-06 산출) 를 dev Firebase
프로젝트에 배포합니다. 이 규칙은:

- `identity_index/{document}` 컬렉션 클라이언트 read/write 전면 차단 (D-14)
  → Cloud Function (Admin SDK) 만 우회 가능. 다른 사용자의 Kakao→UID
  매핑을 클라이언트가 직접 read 하지 못하도록 차단.
- `users/{uid}` self-only 임시 규칙 — 사용자가 자기 문서만 read/write 가능.
  Phase 18 정식 ruleset 일반화 대기.

```bash
# Firebase CLI 로그인 (최초 1회)
firebase login

# dev 프로젝트 alias 사용
firebase use dev

# 배포
firebase deploy --only firestore:rules
```

기대 응답:
```
✔ Deploy complete!
```

### 4단계 — KAKAO_REST_API_KEY Secret 등록 (Phase 11-05 / 12-02)

Cloud Function `kakaoCustomToken` 이 Kakao OIDC ID Token 의 audience 검증에
사용하는 REST API 키를 Firebase Secret Manager 에 등록합니다 (코드 / config
파일에 평문 저장 금지).

```bash
firebase use dev
firebase functions:secrets:set KAKAO_REST_API_KEY
# prompt:
#   ? Enter a value for KAKAO_REST_API_KEY: <여기에 REST API 키 붙여넣기 + Enter>
```

기대 응답:
```
✔ Created a new secret version projects/.../secrets/KAKAO_REST_API_KEY/versions/1
```

확인:
```bash
firebase functions:secrets:access KAKAO_REST_API_KEY
```

> Cloud Function 의 `defineSecret('KAKAO_REST_API_KEY')` 가 배포 시점에
> 자동으로 secret 을 함수 환경변수로 주입합니다 (Phase 11 D-05 패턴).

### 5단계 — App Check Debug Provider 등록 — ⚠ Pitfall 6

Cloud Function `kakaoCustomToken` 은 `enforceAppCheck: true` 로 abuse 방어
중입니다 (Phase 12 D-11). dev flavor 실 단말 검증 시 debug 토큰을 Firebase
Console 에 등록해야 통과합니다.

**절차:**

1. dev 빌드 실 단말 첫 실행:
   ```bash
   fvm flutter run --flavor=dev --dart-define-from-file=config/dev.json
   ```

2. 로그에서 debug 토큰 추출:
   - **Android**: `adb logcat | grep "App Check"` 또는 Android Studio Logcat
     에서 `Enter this debug secret into the Firebase Console` 다음 줄의 UUID
   - **iOS**: Xcode Console 에서 동일 메시지 검색

3. Firebase Console 등록:
   - <https://console.firebase.google.com> → dev 프로젝트
   - 좌측 "빌드 > App Check" → 앱 선택 (Android / iOS)
   - "디버그 토큰 관리" → "디버그 토큰 추가" → 추출한 UUID 붙여넣기

4. 등록 후 다음 앱 실행부터 `enforceAppCheck` 통과 — Cloud Function 호출
   401 unauthenticated 에러 사라짐.

**누락 시 증상:** Cloud Function 호출이 401 → AuthRepository 가
`ServiceUnavailable` Failure → LoginScreen 의 FormErrorBanner 에
`errorServiceUnavailable` 표시. Pitfall 1 (OIDC 누락) 과 동일 증상이라
구분 어려움 — Cloud Logging 에서 `app_check_check_failed` warn 확인.

> **Production:** Play Integrity (Android) / DeviceCheck (iOS) 정식 활성화
> 의무. Phase 18 보안 일반화 단계에서 자동화 검토 — 본 starter kit 의
> 현재 코드 (`enforceAppCheck: true`) 그대로 호환.

### 6단계 — Cloud Function 배포

Phase 12-02 산출 `kakaoCustomToken` 함수를 dev Firebase 프로젝트
(asia-northeast3) 에 배포합니다.

```bash
cd functions
npm install            # 최초 1회
npm run lint           # 0 errors 확인
npm run build          # tsc OK 확인
npm test               # jest 14 PASS 확인 (3 suites)

# 배포
firebase use dev
firebase deploy --only functions:kakaoCustomToken
```

기대 응답:
```
✔ functions[kakaoCustomToken(asia-northeast3)] Successful update operation.
```

확인 — Firebase Console:
- "빌드 > Functions" → `kakaoCustomToken` 함수 row → region = `asia-northeast3`
  + "활성" 상태

### 7단계 — 검증 (실 단말 UAT)

dev 빌드 실 단말 + KakaoTalk 설치 단말 + 미설치 단말 양쪽에서:

1. 빌드:
   ```bash
   fvm flutter run --flavor=dev --dart-define-from-file=config/dev.json
   ```

2. LoginScreen → "카카오 로그인" 버튼 (노란 #FEE500, 검정 라벨, KakaoTalk
   말풍선 아이콘) 표시 확인.

3. 탭 → KakaoTalk 설치 시 KakaoTalk app-to-app 1-tap, 미설치 시 카카오계정
   웹뷰 (Custom Tab / SFSafariViewController) → "동의하고 계속하기".

4. 인증 성공 → Home 진입 + EnvironmentInfoScreen Account 카드 → "로그인
   수단: 카카오" 라벨 확인.

5. Firebase Console > Firestore → `identity_index/kakao:{kakaoUserId}` 문서
   존재 + `firebaseUid` / `linkedAt` / `lastSeenAt` 확인.

6. `users/{uid}` 문서 → `linkedProviders` 배열에
   `{providerId: "kakao", providerUserId: "..."}` 포함 확인.

7. Cloud Logging > Functions > kakaoCustomToken → `event:
   "kakao_custom_token_issued"` + `uid` + `isNewUser` 로그 (idToken 본문 /
   kakao_account 본문 미노출 확인 — Phase 12 D-08 PII 정책).

### 알려진 결함 / 주의사항 (Pitfall 1 / 6 / 11)

#### ⚠ Pitfall 1 — OIDC 활성화 누락

- **증상:** 로그인 시도 시 LoginScreen 에서 즉시 `errorServiceUnavailable`
  배너. 어떤 외부 SDK 호출도 일어나지 않은 것처럼 보임.
- **원인:** `OAuthToken.idToken` 이 null. Kakao Developer Console 의
  "OpenID Connect 활성화" 토글이 OFF.
- **해결:** 1단계 #6 절차 재확인 + 토글 ON 후 앱 재실행.

#### ⚠ Pitfall 6 — App Check Debug 토큰 미등록

- **증상:** Pitfall 1 과 동일하게 `errorServiceUnavailable` 배너.
- **원인:** Cloud Function `kakaoCustomToken` 호출이 401 unauthenticated.
  Cloud Logging 의 `app_check_check_failed` warn 으로 구별.
- **해결:** 5단계 절차 재확인 + Firebase Console 에 debug 토큰 등록 후 앱
  재실행.

#### ⚠ Pitfall 11 — Apple Custom Tab 결함과 무관

- Apple Sign-In 의 Android Custom Tab 결함 (memory
  `project_android_apple_signin_known_issue`) 이 Kakao 에도 적용된다는
  오해가 있을 수 있습니다.
- **무관함:** Kakao SDK 는 자체 Custom Tab 자동 닫힘 처리 + KakaoTalk
  app-to-app 처리 — 별도 결함 없음.
- 다만 Kakao 웹뷰가 인증 후 닫히지 않는 경우는 **Console 의 Redirect URI
  누락** (1단계 #5) 또는 **앱 키 / 패키지명 / 키 해시 mismatch** 가 원인 —
  Kakao 자체 SDK 결함 아님.

#### 회원탈퇴 cleanup TODO (Phase 17 까지 미구현)

- 현재 회원탈퇴 시 `identity_index/kakao:{id}` 문서가 잔존합니다 — Phase 17
  의 Account Linking 일반화 단계에서 transaction 기반 cleanup 도입 예정.
- 잔존 문서가 즉시 보안 결함은 아니지만, 같은 Kakao 계정을 다른 Firebase
  UID 에 재등록하려 할 때 first-write-wins 정책 (D-12) 으로 기존 매핑이
  우선됩니다. starter kit 사용자가 "회원탈퇴 후 즉시 재가입" 시나리오
  검증 시 인지 필요.

---

## Phase 13~16 — Custom Token Provider 추가 가이드 (stub)

Phase 12 의 Kakao 통합 패턴을 그대로 미러링하여 Naver / LINE / Yahoo!JP /
WeChat 등 새 Custom Token provider 를 추가할 수 있습니다. 9 단계 절차:

1. **Provider ID 등록** — `lib/core/auth/provider_id.dart` 의
   `kProviderId{Provider}` 가 이미 등재되어 있음 (Phase 11-02 wave 1). 변경
   없음.

2. **Notifier** — `lib/features/auth/presentation/{provider}_sign_in_notifier.dart`
   신규. Phase 12 `kakao_sign_in_notifier.dart` 1:1 미러 (Facebook → Kakao
   → Naver/... 일괄 치환). autoDispose AsyncNotifier + `ref.mounted` 가드 +
   Result switch.

3. **SDK Client** — `lib/features/auth/data/{provider}_sdk_client.dart` 신규.
   Phase 12 `kakao_sdk_client.dart` 미러. 단 검증 방식이 OIDC vs REST 인지에
   따라 Cloud Function 호출 인자 / SDK 호출 흐름 다름:

   | Phase | Provider | 검증 방식 | 근거 |
   |-------|----------|-----------|------|
   | 12 | Kakao | OIDC ID Token JWT | Kakao 공식 권장 |
   | 13 | Naver | REST `/v1/nid/me` | Naver OIDC 미지원 |
   | 14 | LINE | OIDC ID Token JWT | LINE 공식 OIDC |
   | 15 | Yahoo!JP | OIDC ID Token JWT | Yahoo! ID 連携 v2 표준 |
   | 16 | WeChat | REST `/sns/userinfo` | WeChat OIDC 미지원 |

   각 phase 의 discuss-phase 진입 시 본 매트릭스 + 실 provider 공식 문서
   재확인 의무.

4. **AuthStrategy** — `lib/core/auth/strategies/{provider}_auth_strategy.dart`
   신규. Phase 12 `kakao_auth_strategy.dart` 미러. **race-fix invariant 의무
   (Pitfall 8)** — Strategy.signIn 본문은 Notifier 위임만 수행, `socialLink-
   InProgress.begin/end` 직접 호출 절대 금지.

5. **Registry add-only** — `lib/core/auth/auth_strategies_registry.dart` 의
   `_allStrategies` 끝줄에 1줄 추가. 기존 Google/Apple/Facebook/Kakao 위치
   무변경.

6. **Helper resolver** —
   `lib/features/auth/presentation/_helpers/social_provider_resolver.dart`
   switch 에 1줄 추가 (Pitfall 6 단일 진실원). 본 1줄로 LoginScreen /
   SignupScreen / LoginPromptSheet 3 화면의 ref.listen for-loop 자동 반영.

7. **ARB keys × 3 로케일** — `auth{Provider}SignIn` (소셜 버튼 라벨) +
   `authAccountProvider{Provider}` (Account 카드 라벨) × en/ko/ja 3 파일 +
   `flutter gen-l10n` 자동 호출.

8. **SocialButton 분기** —
   `lib/features/auth/presentation/_widgets/social_button.dart` 의 `build()`
   첫 줄 if 분기 + `_build{Provider}Button` 메서드 + 색 상수 (각 Brand
   Guideline). Kakao 가 sign_in_button 패키지 미지원 provider 의 표본 패턴
   (Material+InkWell+SVG 직접 그리기) — Naver / LINE / Yahoo!JP / WeChat
   모두 동일 패턴.

9. **Cloud Function** —
   `functions/src/auth/{provider}_custom_token.ts` 신규. Phase 12
   `kakao_custom_token.ts` 미러:
   - `setGlobalOptions` region 자동 상속 (asia-northeast3)
   - `enforceAppCheck: true` + `secrets: [PROVIDER_*_SECRET]`
   - `resolveIdentity(db, {provider, providerUserId, callerUid})` helper 재
     사용 (Phase 12 의 `functions/src/auth/identity_index.ts` 단일 진실원
     — Phase 13~17 모두 같은 helper 호출)
   - 검증 helper 는 OIDC verifier 가 Phase 14 LINE 진입 시 일반화 (D-08)

각 phase 마다 본 manual 의 Kakao 단락 + Phase 12 D-07 검증 매트릭스 + 실
provider 공식 문서 재확인 의무.

---

## Cloud Functions 배포 / Remote Config Kill Switch (Phase 11-04)

> 본 단락은 Phase 11-04 SUMMARY 의 사용자 매뉴얼 카드를 통합한 것입니다.
> Phase 12+ 의 신규 Cloud Function (Naver/LINE/Yahoo!JP/WeChat) 도 동일
> 패턴 적용.

### Functions 추가 절차 (Phase 12 ~ 16 의 ping 패턴 복제)

1. `functions/src/auth/{provider}_custom_token.ts` 또는 신규
   `functions/src/index.ts` 에 새 `onCall` export 추가:
   ```typescript
   export const myFunction = onCall(
     {enforceAppCheck: true, secrets: [MY_SECRET]},
     async (request) => {
       if (!request.auth) throw new HttpsError('unauthenticated', 'errorUnauthenticated');
       logger.info({event: 'my_function_invoked', uid: request.auth.uid}, 'invoked');
       return { /* result */ };
     },
   );
   ```
2. `functions/test/auth/{provider}_custom_token.test.ts` 작성 —
   `firebase-functions-test` 패턴 (기존 `kakao_custom_token.test.ts` 미러).
3. Secrets: `firebase functions:secrets:set MY_SECRET` +
   `defineSecret('MY_SECRET')`.
4. `cd functions && npm run lint && npm run build && npm test` 풀 게이트
   GREEN 확인.
5. 배포: `firebase deploy --only functions:myFunction`.

### RC Kill Switch 운영 절차 (Emergency Disable)

Phase 11-04 의 `auth_provider_{providerId}_enabled` Remote Config 키로 운영
중 특정 provider 를 즉시 비활성화할 수 있습니다.

1. <https://console.firebase.google.com> → 프로젝트 선택 → 좌측 "Engage >
   Remote Config".
2. **새 매개변수 만들기** 또는 기존 `auth_provider_kakao_enabled` 수정.
3. 데이터 유형: Boolean, 기본값: `false` (disable) / `true` (enable).
4. **변경사항 게시 (Publish)** 클릭.
5. 사용자가 다음 앱 실행 시 (대부분 12시간 안에) 자연 반영.
   - dev flavor 는 즉시 (`minimumFetchInterval=Duration.zero`).

**제약 (Phase 11 D-26 truth table):**
- 정적 config (`config/{flavor}.json`) 의 `enabledAuthProviders` CSV 에서
  특정 provider 가 빠진 경우 RC 로 켤 수 없음 (정적 false 절대 우위).
  정적 enable 후 RC 로 disable 만 가능.

---

## Kakao Brand Asset 라이센스 / 출처 (Phase 12-07)

- **자산 파일:** `assets/icons/kakao_logo.svg`
- **출처:** Kakao Developers Design Resources —
  <https://developers.kakao.com/tool/resource/login>
- **라이센스:** Kakao Brand Guideline 준수 의무 — 형태 / 색상 / 회전 / 크기
  비율 변형 금지. 위반 시 Kakao Developer Console 앱 정지 위험.

### ⚠ 변경 금지 항목

- **단일 검정 로고 (다른 색 변형 금지)** — UI-SPEC `_kKakaoIcon =
  0xFF000000` 만 허용. 흰색 / 회색 / 다른 색상 변형 금지.
- **18×18 logical px 비율 보존** — sign_in_button 패키지의 다른 소셜
  아이콘과 동일 면적. SocialButton 의 Kakao 분기는 `SvgPicture.asset(...,
  width: 18, height: 18)` 고정.
- **다른 형태 (예: 둥근 사각형 / 반전 / 회전) 사용 금지** — Kakao 공식
  KakaoTalk 말풍선 형태 (가로 타원 + 우하단 꼬리) 그대로.

### ⚠ Production 빌드 전 의무 — 공식 자산으로 교체

본 starter kit 의 `assets/icons/kakao_logo.svg` 는 **Kakao 공식 다운로드
자산이 아닌 hand-crafted SVG** 입니다.

**이유:** Kakao Developers Design Resources 페이지
(<https://developers.kakao.com/tool/resource/login>) 가 Single Page App 이라
정적 fetch 로 SVG 를 자동 다운로드 받을 수 없습니다 (모든 경로가 동일
HTML 반환). 또한 18×18 단일 색 말풍선 단독 자산이 공개 정적 URL 에 노출되어
있지 않습니다.

**Production 빌드 전 의무:**

1. 위 URL 의 페이지에서 "Kakao 로그인 디자인 자산" 단락의 공식 SVG / PNG
   자산을 직접 다운로드.
2. 18×18 logical px 단일 검정 KakaoTalk 말풍선 형태에 가장 가까운 자산
   선택 (예: `kakaotalk_symbol.svg` 또는 동등 단일 심볼).
3. `assets/icons/kakao_logo.svg` 를 다운로드한 자산으로 덮어쓰기.
4. PNG 인 경우 확장자 `.png` 로 변경하고 `pubspec.yaml` 의 `assets:` 리스트
   + `social_button.dart` 의 `SvgPicture.asset` → `Image.asset` 으로 교체.

starter kit 사용자가 production 배포 전 본 단락을 반드시 재검토할 것 —
Kakao Brand Guideline 위반은 Console 정지 위험.

---

## 회원탈퇴 cleanup TODO (Phase 17)

현재 starter kit 의 회원탈퇴 흐름은 다음 cleanup 작업이 누락된 상태입니다
(Phase 17 의 Account Linking 일반화 단계에서 일괄 도입 예정):

- **`identity_index/{provider}:{providerUserId}` 문서 cleanup** — 회원탈퇴
  시 사용자가 등록한 Kakao / Naver / LINE / Yahoo!JP / WeChat 의 매핑
  문서가 잔존. 같은 외부 계정으로 재가입 시 first-write-wins 정책 (D-12)
  으로 기존 매핑이 우선되어 새 UID 가 아닌 기존 (탈퇴된) UID 로 매핑되는
  결함 가능성.
- **Native 4 provider (Email/Google/Apple/Facebook) 의 `linkedProviders`
  회고 등록** — Phase 12 의 Identity Index 컬렉션 등록은 Custom Token
  provider 만 자동. Native 4 provider 도 Phase 17 에서 회고 등록 후 통합
  관리 예정.
- **충돌 UI** — 동일 외부 계정이 다른 Firebase UID 에 등록된 상태에서 새
  사용자가 같은 계정으로 로그인 시 "이 카카오 계정은 다른 앱 계정에
  등록됐습니다. 통합할까요?" 다이얼로그 (Plan 10-06 의 `account-exists-with-
  different-credential` 패턴 확장).

starter kit 사용자가 production 진입 시점에 회원탈퇴 / Account Linking
플로우를 자체 구현하거나 Phase 17 도입 후 본 starter kit 의 후속 버전을
merge 하는 두 가지 옵션 중 선택.

---

## 변경 이력

| 일자 | Phase | 변경 |
|------|-------|------|
| 2026-05-03 | 12-07 | 신규 작성 — Kakao Login + Phase 13~16 stub + RC kill switch 통합 + Brand Asset 라이센스 + 회원탈퇴 TODO |

---

*Last updated: 2026-05-03 — Phase 12 Plan 07 완료 (Kakao Login)*
