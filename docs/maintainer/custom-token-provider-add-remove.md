# Custom Token provider 추가 · 제거 (유지보수자 문서)

> 킷 사용자 문서가 아니다 — 킷 사용자는 provider 를 끄고 켜기만 한다(`docs/manual.md`
> 「로그인 수단 켜고 끄기」). 추가 · 제거는 킷 유지보수자 작업이다.

배경과 이력은 아래 원본에 있고, 이 문서는 내용을 복사하지 않는다.

- 원칙 P(사용자는 on/off 만) · 마찰 판정표 · on/off 계약 5항 · 누출 L1~L3:
  [provider 추가/제거 마찰 해소 todo](../../.planning/todos/pending/2026-09-25-provider-add-remove-friction-refactor.md)
- provider 1종 제거의 마찰 계수 · 실측 원장:
  [16.6-LEDGER.md](../../.planning/phases/16.6-yahoo-jp-login-removal/16.6-LEDGER.md) §7
- 연결 callable 분리 · 초기화 표 · 배포 함수 목록 · scheme 자리표시 결정:
  [Phase 17.3](../../.planning/phases/17.3-provider-on-off-contract/)

`<provider>` · `<Provider>` · `<slug>` · `<PROVIDER>_CLIENT_ID` 는 대상 provider 에 맞게
바꿔 읽는다(예: `line` · `Line` · `LINE_CHANNEL_ID`).

---

## 추가 가이드

Kakao(OIDC ID token) · Naver(access token / REST) · LINE(OIDC ID token)의 통합 패턴을
그대로 따라 새 Custom Token provider 를 붙인다. 제거는 이 순서의 역순이다(아래
「제거 가이드」). 단계마다 provider 하나를 기준으로 쓴다.

1. **Provider ID 등록** — `lib/core/auth/provider_id.dart` 에 `kProviderId<Provider>`
   상수와 `AccountProvider` enum 값을 더하고, `kAllProviderIds` 에 slug 를 넣는다.
   `kAllProviderIds` 의 순서는 `scripts/functions_manifest.json` 의 `providers` 키
   순서와 같아야 한다 — `test/core/config/functions_manifest_contract_test.dart`
   (T-173-DEPLOY-04)가 순서까지 대조한다. enum 값 하나가 여러 파일의 exhaustive
   switch 를 끌고 다니므로 컴파일이 깨지는 사이트를 같은 커밋에서 채운다.

2. **Notifier** — `lib/features/auth/presentation/<provider>_sign_in_notifier.dart`
   신규. `kakao_sign_in_notifier.dart` 1:1 미러 — autoDispose AsyncNotifier +
   `ref.mounted` 가드 + Result switch.

3. **SDK Client** — `lib/features/auth/data/<provider>_sdk_client.dart` 신규.
   `kakao_sdk_client.dart` 미러. 검증 방식이 OIDC 인지 REST 인지에 따라 Cloud
   Function 호출 인자 · SDK 호출 흐름이 다르다:

   | Provider | 검증 방식 | 근거 |
   |----------|-----------|------|
   | Kakao | OIDC ID Token JWT | Kakao 공식 권장 |
   | Naver | REST `/v1/nid/me` | Naver OIDC 미지원 |
   | LINE | OIDC ID Token JWT | LINE 공식 OIDC |

   새 provider 의 discuss 단계에서 이 표와 그 provider 의 공식 문서를 다시 확인한다.

4. **AuthStrategy** — `lib/core/auth/strategies/<provider>_auth_strategy.dart` 신규.
   `kakao_auth_strategy.dart` 미러. **race-fix invariant (Pitfall 8)** — `signIn` 본문은
   Notifier 위임만 하고 `socialLinkInProgress.begin/end` 를 직접 부르지 않는다.

5. **Registry add-only** — `lib/core/auth/auth_strategies_registry.dart` 의
   `_allStrategies` 끝에 1줄. 기존 provider 위치는 바꾸지 않는다.

6. **Helper resolver** —
   `lib/features/auth/presentation/_helpers/social_provider_resolver.dart` switch 에
   1줄(Pitfall 6 단일 진실원). 이 1줄로 `/login` chooser · LoginPromptSheet 두 화면의
   `ref.listen` for-loop 에 자동 반영된다.

7. **ARB keys × 3 locale** — `auth<Provider>SignIn`(소셜 버튼 라벨) +
   `authAccountProvider<Provider>`(계정 정보 화면 · 데모 계정 디버그 정보 카드 라벨) ×
   en/ko/ja + `fvm flutter gen-l10n` 산출물.

8. **브랜드 버튼** — `lib/features/auth/presentation/_widgets/branded_social_button.dart`
   의 sealed `BrandSpec` 서브클래스 · `BrandedSocialButton.<provider>` factory ·
   `build()` switch case · render 메서드, `social_button.dart` 의 provider switch ·
   라벨 switch, `assets/brand/<slug>/` + `pubspec.yaml` assets 행. 색 · 자산 · 라벨은
   그 provider 의 공식 브랜드 가이드에서 가져온다.

9. **Cloud Functions — 로그인 endpoint 와 연결 callable.**
   - 로그인: `functions/src/auth/<provider>_custom_token.ts` 신규(`kakao_custom_token.ts`
     미러). `setGlobalOptions` region 자동 상속(asia-northeast3) · `enforceAppCheck: true`
     · `secrets: [<자기 secret>]` · `resolveIdentity(db, {provider, providerUserId, callerUid})`
     재사용(`functions/src/auth/identity_index.ts` 단일 진실원). slug 는 `ProviderId`
     closed union 에 먼저 넣는다.
   - 연결 — OIDC ID token provider: `functions/src/shared/oidc_providers.ts` 의
     `OidcProviderId` · `OIDC_VERIFIERS` 에 1줄, 그리고
     `functions/src/auth/link_<provider>_provider.ts` 에 공용 팩토리 선언 1개 —
     `export const link<Provider>Provider = buildLinkOidcProviderCallable("<slug>", [<자기 secret>]);`
     (`link_kakao_provider.ts` · `link_line_provider.ts` 가 표본). 팩토리
     (`functions/src/auth/link_oidc_provider.ts`)는 caller 검사 · verifier 호출 ·
     연결 transaction(`linkCustomTokenIdentity`)을 모두 가지므로 provider 파일에는
     secret 목록 외의 코드가 없다.
   - 연결 — access token provider: `functions/src/auth/link_naver_provider.ts` 를 본뜬
     전용 callable. 검증 helper 만 provider 것으로 바꾸고 연결 transaction 은
     `linkCustomTokenIdentity` 를 그대로 부른다.
   - 어느 경우든 공용 callable 에 provider 분기를 넣지 않는다 — 각 callable 은 자기
     secret 만 binding 해야 그 provider 를 끈 프로젝트가 나머지 함수를 배포할 때 끈
     provider 의 secret 에 접근 권한 부여 · 유효 버전 검사가 걸리지 않고, 값이 런타임에
     읽히지도 않는다(on/off 계약 (4)). secret **존재**는 binding 과 무관하다 —
     Firebase CLI 는 `--only` 필터와 상관없이 코드베이스가 선언한 `defineSecret` 전부의
     존재를 확인하고 없으면 값을 묻는다(firebase-tools 15.29.0 `deploy/functions/params.js`
     `resolveParams` → `ensureSecret`). 그래서 끈 provider 의 secret 도 자리표시 값으로
     만들어 둔다 — 매뉴얼 「로그인 수단 켜고 끄기」 「켜기」 ④. 그 반복문은
     `functions:secrets:get` 의 출력에 `HTTP Error: 404` 가 있을 때만 `unset` 으로
     만들고, 다른 실패(로그인 · 권한 · 네트워크)에서는 메시지를 보이고 멈춘다 — 기존
     secret 에 `secrets:set` 을 부르면 새 버전 `unset` 이 더해지기 때문이다
     (`functions-secrets-set.js` → `ensureSecret` → `addVersion`). 이 문구는
     firebase-tools 의 `lib/responseToError.js`(`"HTTP Error: " + statusCode + ", " …`)가
     만들고 종료 코드로는 404 와 403 을 가를 수 없으므로(둘 다 1), CLI 를 올릴 때 이
     형식이 그대로인지 확인한다. 새 provider 의
     `defineSecret` 을 더하면 그 반복문의 secret 이름 목록에도 더한다.
   - `functions/src/index.ts` 에 export 1줄씩. 클라이언트는
     `AuthRepository.linkCustomTokenProviderArm` 의 callable 이름 switch 에 1행
     (`lib/features/auth/data/auth_repository.dart`), access token provider 는
     `linkNaverProviderArm` 처럼 전용 arm 을 둔다.
   - 해제 callable(`unlinkCustomTokenProvider`)은 편집 0 — 해제 대상은
     `CUSTOM_TOKEN_PROVIDER_PRIORITY`(`functions/src/auth/identity_index.ts`)에 slug 가
     있는지로 정해진다. 목록을 바꾸면 해제 callable 도 재배포한다.

10. **배포 함수 목록** — `scripts/functions_manifest.json` 의 `providers.<slug>` 에 그
    provider 의 함수 이름(로그인 · 연결 · 끊기)을 넣는다. 배포 스크립트
    (`scripts/deploy_functions.sh`)는 이 목록만 읽는다. Jest
    `functions/test/deploy_manifest.test.ts` 가 manifest == `index.ts` export 를
    대조하고(T-173-DEPLOY-01), 새 provider secret 은 같은 파일의
    `PROVIDER_SECRET_OWNER` 맵에 `<SECRET>: "<slug>"` 로 더한다 — 맵에 없으면 다른
    provider 함수나 공통 함수가 그 secret 을 묶어도 잡히지 않는다.

11. **SDK 초기화 표** — Dart SDK 초기화가 필요하면 `lib/core/bootstrap.dart` 의
    `buildProviderSdkInits()` 표에 `(providerId: kProviderId<Provider>, label: …, init: …)`
    1줄. 실행할 줄은 `selectEnabledSdkInits` 가 정적 CSV 로 고르므로 off provider 의
    초기화는 호출되지 않는다. 초기화 호출을 표 밖에 두지 않는다. 네이티브가 빌드
    설정을 읽는 SDK(Facebook · Naver 방식)는 표에 넣지 않는다.

12. **URL scheme — 키가 비면 자리표시가 되게.** 앱이 직접 적는 scheme 은 키가 비었을
    때 일반 scheme(빈 문자열 · `fb` · `kakao` 처럼 다른 앱과 겹치는 값)이 되면 안 된다.
    - iOS `ios/Runner/Info.plist`: `$(<VAR>:default=unset.<slug>.$(PRODUCT_BUNDLE_IDENTIFIER))`
      꼴(Google · Naver 표본). 접두가 붙는 scheme 은 접두 뒤에 둔다 —
      `kakao$(KAKAO_NATIVE_APP_KEY:default=unset.$(PRODUCT_BUNDLE_IDENTIFIER))`.
    - Android `android/app/build.gradle.kts`: `manifestPlaceholders` 에 빈 값 fallback
      (`kakaoOAuthScheme` = 키가 비면 `unset.kakao.oauth` · `naverWebCallbackScheme` =
      비면 `unset.naver.web`). bundle id 를 섞지 않는다 — applicationId 의 밑줄은
      scheme 문자가 아니다.
    - 빌드 설정은 `enabledAuthProviders` 를 읽지 않는다 — 이미 읽는 키 값의 비어
      있음만 본다. 계약 테스트 `test/core/config/provider_url_scheme_contract_test.dart`
      (T-173-SCHEME-01~03)에 새 scheme 을 더한다.

13. **example 설정** — `config/{dev,stg,prod}.example.json` · `ios/Flutter/*.example.xcconfig`
    에 키 자리표시를 더한다. 기본 `enabledAuthProviders` 는 빈 문자열 그대로 둔다(소셜
    0개 기본). `scripts/verify_placeholder_builds.sh` 의 `all` case 가 새 키를 넣는지
    확인한다.

14. **사용자 매뉴얼** — `docs/manual.md` 「로그인 수단 켜고 끄기」 절의 provider 표에
    1행(토큰 · config 키 · xcconfig 변수 · 함수 · secret · 콘솔 등록)과 그 provider 의
    설정 절. 계약 테스트 `test/features/auth/manual_provider_on_off_contract_test.dart`
    (T-173-DOCS-03 · 04)가 표의 함수 · 키를 manifest · example 파일과 대조한다.

각 단계 뒤 게이트는 「제거 가이드」 2 의 게이트 블록과 같다.

---

## 제거 가이드

위 추가 가이드의 역순이다. 킷에서 provider 하나를 완전히 빼야 할 때 따른다. 4 단계:

1. **먼저 — 비활성으로 충분한가.** 코드를 지우지 않고 provider 를 끄는 레버가
   두 개 있고, 둘 다 코드 변경 0 이다.

   | 레버 | 시점 | 방법 |
   |------|------|------|
   | 정적 CSV | 빌드 | `config/{flavor}.json` 의 `enabledAuthProviders` 에서 `<slug>` 토큰을 뺀다 |
   | Remote Config | 운영 | `auth_provider_<slug>_enabled = false` 게시 — 매뉴얼 「RC Kill Switch 운영 절차」 |

   정적 CSV 에서 빠진 provider 는 RC 로 켤 수 없다(정적 false 절대 우위). 그래서
   「이 앱은 이 provider 를 쓰지 않는다」 는 CSV 토큰 제거만으로 확정되고, 운영 중 임시
   차단은 RC 로 충분하다. CSV 에서 뺀 provider 는 SDK 초기화 · 배포 함수 · URL scheme
   도 따라 빠진다(초기화 표 · 배포 스크립트 · 자리표시 scheme).
   secret 은 빠지지 않는다 — 코드에 `defineSecret` 이 남아 있는 한 Firebase CLI 가
   존재를 확인하므로 자리표시 값으로 남겨 둔다(값은 읽히지 않는다). 코드까지
   지우는 경우는 다음 중 하나다: 검증 · 유지가 불가능하다(개발자 · 테스트 계정을 만들
   수 없어 로그인 경로를 검증하지 못함), 의존성 부담이 크다(전용 플러그인 · native SDK
   의 유지비), 킷 가치가 비대칭이다(대상 사용자층 대비 설정 비용).

2. **제거 체크리스트 — 의존 역순, 매 커밋 green.** 항목 하나가 커밋 하나이고, 게이트를
   통과해야 다음 항목으로 간다.
   - ① **등록 해제 (UI 소멸)** — `lib/core/auth/auth_strategies_registry.dart` 의
     `_allStrategies` 1줄 + `social_provider_resolver.dart` 1줄 삭제, strategy · notifier
     파일 삭제(고아 `.g.dart` 는 `rm`). 이 1줄로 `/login` chooser · LoginPromptSheet ·
     계정 정보 화면(설정 → 내 계정) 「계정 연결」 에서 버튼이 모두 사라진다. 버튼 수를
     단언하는 테스트(`findsNWidgets`)와 골든 harness 의 override 목록을 함께 고치고
     골든을 재생성한다 — before/after 를 사용자에게 보여 승인받은 뒤 커밋하고 촬영
     locale 을 기록한다(함정 (d)).
   - ② **enum · 상수 · switch 일괄 (한 커밋)** — `AccountProvider` enum 값 ·
     `kProviderId<Provider>` · `kAllProviderIds` · exhaustive switch 사이트 전부 ·
     `AuthRepository` 생성자 인자와 signIn / signOut / link 분기(OIDC provider 면
     `linkCustomTokenProviderArm` 의 callable 이름 switch 행) · `AppConfig` getter ·
     `lib/core/bootstrap.dart` `buildProviderSdkInits()` 의 그 provider 줄. 컴파일 결합
     단위로 한 커밋에 묶고, 테스트의 생성자 mock · provider 행도 같은 커밋에 넣는다. 그
     provider 가 우연히 유일하게 증명하던 성질(매트릭스 행 · 두 번째 slug 증명)은 지우지
     말고 남은 provider 로 이관한다. `kAllProviderIds` 에서 빼는 커밋은 manifest 의
     `providers.<slug>` 키도 함께 뺀다(T-173-DEPLOY-04 가 순서 · 집합을 대조). 이 커밋
     **전에** 로컬 `config/*.json` 의 CSV 토큰을 먼저 뺀다(함정 (b)).
   - ③ **brand 버튼 · 자산** — sealed `BrandSpec` 서브클래스 ·
     `BrandedSocialButton.<provider>` factory · `build()` switch case · render 메서드 +
     `assets/brand/<slug>/` + `pubspec.yaml` assets 행 + brand 테스트의 provider 목록
     (`brand_assets_lint_test` · `brand_label_whitelist_test`).
   - ④ **ARB** — 키 × 3 locale 삭제, 수가 박힌 description 정정, `fvm flutter gen-l10n`
     산출 4 파일을 같은 커밋에 넣는다(description 만 바꿔도 generated dart 의 `///` 가
     바뀐다). 한 번 더 돌려 diff 0 을 확인한다.
   - ⑤ **남은 주석 · docstring** — 이름 0. 「N provider」 처럼 수가 박힌 문장은 수도
     함께 고치고, 교훈은 이름만 빼고 남긴다.
   - ⑥ **플러그인 + native 등록 (같은 커밋)** — `fvm flutter pub remove <plugin>` + 그
     플러그인이 요구하던 Android manifest placeholder(`android/app/build.gradle.kts` 의
     `manifestPlaceholders` — Kakao 면 `kakaoNativeAppKey` · `kakaoOAuthScheme`, Naver 면
     `naverWebCallbackScheme` — 와 `AndroidManifest.xml` 의 `${…}` 참조) · iOS
     `Info.plist` URL type(`$(<VAR>:default=…)` 줄 포함) · xcconfig 변수 ·
     `config/*.example.json` 키 · `test/core/config/provider_url_scheme_contract_test.dart`
     의 그 scheme 단언(함정 (e)). gitignored 로컬 파일(`ios/Flutter/<flavor>.xcconfig` ·
     `config/<flavor>.json`)은 도구가 알려주지 않으므로 값 출력 없이 줄 단위로 지우고
     계수로 확인한다. iOS 는 3 flavor debug 빌드 후 `Package.resolved` 를 판독한다
     (함정 (c)).
   - ⑦ **Cloud Functions** — closed union(`ProviderId` · `OidcProviderId`)과 짝 맵
     (`OIDC_VERIFIERS` · priority 배열) · `defineSecret` 선언 · 전용 endpoint 파일 ·
     Jest(유일 증명 이관 포함). 그리고:
     - **연결 callable** — 그 provider 의 전용 연결 callable 파일
       (`functions/src/auth/link_<provider>_provider.ts`)과 그 Jest
       (`functions/test/auth/link_<provider>_provider.test.ts`) 삭제 + `index.ts` 의
       `export {link<Provider>Provider}` 1줄 + `scripts/functions_manifest.json` 의
       `providers.<slug>` 1줄 삭제 + 배포 정리 ③ 의 `firebase functions:delete link<Provider>Provider`.
       Kakao · LINE 연결 callable 은 공용 팩토리 `buildLinkOidcProviderCallable`
       (`functions/src/auth/link_oidc_provider.ts`)을 1번 부르는 선언뿐이라 다른
       provider 의 연결 callable 은 편집 · 재배포 0 이다 — 각 callable 이 자기 secret 만
       binding 하므로 secret narrowing 할 곳도 없다. 팩토리와
       `link_identity_transaction.ts`(연결 transaction)는 남은 provider 가 쓰는 동안
       유지한다(OIDC provider 가 0 이 되면 팩토리도 지운다).
     - **OIDC secret 선언** — 공유 `functions/src/shared/oidc_providers.ts` 에 있다.
       선언을 지우면 그 secret 을 import 하던 파일(연결 callable · 로그인 endpoint)이
       컴파일되지 않으므로 같은 커밋에서 정리된다. `functions/test/deploy_manifest.test.ts`
       의 `PROVIDER_SECRET_OWNER` 맵에서도 그 secret 행을 지운다.
     - `functions/lib` 는 지우고 다시 빌드한다(tsc 는 고아 `.js` 를 지우지 않는다).
     - **Naver 를 제거할 때** — 연결 callable `functions/src/auth/link_naver_provider.ts`
       와 `index.ts` 의 `export {linkNaverProvider}` 줄(+ 위 주석)을 지우고, 배포 정리
       ③ 에서 `firebase functions:delete linkNaverProvider` 를 함께 실행한다.
       `naver_token_exchange.ts`(code 교환) · `fetchNaverProfile`
       (`naver_profile_to_custom_token.ts`)은 Naver 파일만 쓰므로 함께 삭제하고,
       `link_identity_transaction.ts` 는 Kakao / LINE 연결이 쓰므로 유지한다. 잔존 데이터
       계수(배포 정리 ⑥)는 `identity_index where provider == "naver"` 와
       `users.providerLinkedAt.naver` 로 연결 사본까지 센다. 클라이언트는
       `kSocialProviderOrder`(`lib/core/auth/provider_order.dart`) 원소 1개와
       `SettingsNotifier` 의 naver arm · `AuthRepository.linkNaverProviderArm` 을
       ②(switch 일괄)와 같은 커밋에서 지운다. Naver 로그인은 두고 **연결만** 빼려면 이
       callable 파일 · export 1줄 · manifest 1줄 · `firebase functions:delete linkNaverProvider`
       와 위 클라이언트 3곳만 지운다 — 다른 연결 callable 은 재배포할 필요가 없다.
     - **provider 측 끊기 경로** — 탈퇴 · 해제의 provider 측 끊기는 provider 마다 서버
       callable 파일 1개 + export 1줄 + manifest 1줄 + 클라이언트 레지스트리 1줄로 붙어
       있다. 제거할 provider 에 해당하는 것만 지운다:
       - 서버 — `functions/src/auth/disconnect_<provider>_provider.ts`
         (`disconnect_kakao_provider.ts` · `disconnect_facebook_provider.ts` ·
         `disconnect_naver_provider.ts` · `disconnect_line_provider.ts`)와 그 Jest 파일
         삭제 + `functions/src/index.ts` 의 `export {disconnect<Provider>Provider}` 줄(+ 위
         주석) 삭제 + `scripts/functions_manifest.json` 의 그 이름 삭제.
       - secret 선언 — 그 callable 만 쓰는 선언을 함께 지운다: Kakao
         `functions/src/shared/kakao_admin_secret.ts`(`KAKAO_ADMIN_KEY`) · Facebook
         `functions/src/shared/facebook_secrets.ts`(`FACEBOOK_APP_ID` · `FACEBOOK_APP_SECRET`)
         · LINE `functions/src/shared/oidc_providers.ts` 의 `LINE_CHANNEL_SECRET` 선언.
         Naver 는 끊기 전용 secret 이 없다(`NAVER_CLIENT_ID` · `NAVER_CLIENT_SECRET` 은 위
         Naver 항목대로). 파괴는 배포 정리 ④ 순서를 따른다.
       - 공용 helper — `functions/src/shared/relogin_token.ts`(`mintReloginToken`) ·
         `functions/src/auth/identity_ownership.ts` 는 LINE · Naver 끊기가 함께 쓰므로 둘
         다 제거할 때만 지운다.
       - 배포 정리 ③ 에서 `firebase functions:delete disconnect<Provider>Provider` 를
         함께 실행한다.
       - 클라이언트 — `kDisconnectSteps`(`lib/features/settings/data/disconnect/disconnect_steps.dart`)
         의 그 provider 줄 1개 삭제 + 재로그인 행이면 그 step import 1줄 · step 파일
         (`lib/features/settings/data/disconnect/<provider>_disconnect_step.dart`)과 그
         테스트 삭제. 레지스트리 항목 수를 단언하는 테스트(`server_disconnect_step_test.dart`
         S10)도 같은 커밋에서 고친다. 공용 계약 `DisconnectDeps`(`disconnect_step.dart`)와
         `disconnectDepsProvider` 는 편집 0 이다 — LINE · Naver step 은 자기 SDK client 를
         `deps.read(lineSdkClientProvider)` · `deps.read(naverSdkClientProvider)` 로 직접
         읽고, `DisconnectDeps` 에는 provider 별 필드가 없다. 다른 테스트의
         `DisconnectDeps(...)` 생성부도 그대로다.
       - 레지스트리 줄만 지우고 서버 callable 을 남기면 그 provider 는 킷 쪽만 해제되고,
         탈퇴 진행 화면 행과 해제 다이얼로그의 고지 · 안내가 사라진다.
       - 탈퇴 · 해제 callable(`deleteUserAccount` · `unlinkCustomTokenProvider`)과 진행
         화면 · 해제 다이얼로그는 편집 0 이다 — provider 분기가 없다.
     native provider(Google · Apple · Facebook)를 제거할 때도 레지스트리의 그 줄과
     (Google · Apple 이면) step 파일을 ② 와 같은 커밋에서 지운다 — `AccountProvider`
     enum 값이 사라지면 그 줄이 컴파일되지 않는다.
   - ⑧ **문서 · 스킬 · 계획 문서** — 사용자 매뉴얼의 provider 절 · 목차 ·
     「로그인 수단 켜고 끄기」 provider 표 행, 이 문서의 예 · 표, 스킬 `references/`,
     `.planning` 활성 문서.

   각 항목의 게이트(C-04):

   ```bash
   fvm dart run build_runner build --delete-conflicting-outputs
   fvm flutter analyze && fvm dart analyze     # riverpod_lint 진단은 dart analyze 만
   fvm flutter test --no-pub <범위>             # ② 이후는 full suite
   fvm dart format --output=none --set-exit-if-changed lib test
   cd functions && pnpm run lint && pnpm build && pnpm test   # ⑦ — deploy_manifest 대조 포함
   ```

   테스트 수는 산식 「착수 − 삭제 + 이관 = 종료」 로 기록한다. `AccountProvider.values` ·
   `kAllProviderIds` 를 순회해 생성되는 테스트는 코드 편집 없이 줄어들므로 그 몫을 따로
   센다.

3. **dev 배포 리소스 정리 순서.** 체크리스트 ⑦ 을 커밋한 뒤 배포본을 소스에 맞춘다.
   단계마다 삭제 전 read-only 스냅샷을 남기고 개별 승인 후 실행한다.
   - ① **남는 함수 재배포** — `bash scripts/deploy_functions.sh <flavor>` 로 목록을
     확인한 뒤 `--apply`. 스크립트는 manifest 의 공통 함수 + 켠 provider 함수만
     `functions:<이름>` 필터로 배포한다. 필터 없는 `--only functions` 는 로컬 소스에 없는
     함수(제거 대상) 때문에 non-interactive 에서 배포 전체를 abort 한다. 각 연결 ·
     끊기 callable 은 자기 secret 만 binding 하므로, 남는 함수 가운데 제거 대상 secret
     을 묶은 함수는 0 이어야 한다 — 남는 함수마다 `gcloud functions describe <fn> --gen2 --region <region> --format='value(serviceConfig.secretEnvironmentVariables)'`
     로 확인한다.
   - ② **warm-up probe** — `curl -X POST <함수 URL> -H 'Content-Type: application/json' -d '{"data":{}}'`.
     401 = 함수 살아 있음(App Check / auth 게이트 거부). 403 = Cloud Run IAM 거부,
     429 = 할당량 · 인스턴스 부족, 5xx = 기동 실패 의심 — 401 외에는 정지한다.
   - ③ **함수 삭제** — `firebase functions:delete <fn> --region <region> --project <project> --force`.
     대상은 인자 1개, `--region` 명시. 제거 provider 의 함수 이름은 manifest 에서 지운
     `providers.<slug>` 목록 그대로다(로그인 · `link<Provider>Provider` · 끊기). 여기서
     `--force` 는 non-interactive 의 확인 prompt 를 넘기기 위한 것이다. 성공 로그는
     `Successful delete operation`.
   - ④ **secret 파괴** — in-use 판정은 **read-only 로만** 한다. 남는 함수 전부에
     `gcloud functions describe <fn> --gen2 --region <region> --format='value(serviceConfig.secretEnvironmentVariables)'`
     를 돌려 `<PROVIDER>_CLIENT_ID` 가 0 인지(대조군 secret 은 ≥1) 세고,
     `firebase functions:secrets:get <PROVIDER>_CLIENT_ID` 로 버전 상태를 기록한다. 승인
     뒤 `firebase functions:secrets:destroy <PROVIDER>_CLIENT_ID --project <project> --force`
     를 1회 실행한다 — `--force` 1회 외의 실행은 없다(함정 (a)). functions-managed
     secret 은 마지막 활성 버전이 파괴되면 secret 자체가 삭제된다
     (`No active secret versions left. Destroying secret …`).
     `functions:secrets:prune`(다른 미참조 secret 까지 후보) · `functions:secrets:access`
     (값 출력)는 쓰지 않는다.
   - ⑤ **probe 재실행** — 401 + `gcloud run services describe <svc> --region <region> --format='value(status.latestReadyRevisionName)'`
     가 ① 의 새 revision 과 같은지.
   - ⑥ **잔존 데이터 계수** — Firestore `identity_index`(`provider == <slug>`) ·
     `users.linkedProviders`(요소가 map `{providerId, providerUserId}` 라 문자열
     `ARRAY_CONTAINS` 는 항상 0 — map 필드를 집계한다) · `users.providerLinkedAt.<slug>` ·
     `users.signUpProviderId == <slug>`(가입 수단 기록 — 제거 뒤 남은 값의 표시는
     `errorUnknownProvider` 로 떨어지므로 삭제 대상 여부는 별도 승인) · RC
     `auth_provider_<slug>_enabled`. 남은 provider 로 대조군(≥1)을 먼저 세고 계수만
     출력한다(값 출력 0). 0 이 아니면 삭제는 별도 승인.
   - ⑦ **외부 콘솔 앱 등록 삭제** — provider 개발자 콘솔의 앱(Client ID)은 수동 삭제하고
     스크린샷을 남긴다. 되돌릴 수 없는 콘솔이 많으므로 ④ 뒤(참조 0 확인 뒤)에 한다.

   파괴적 명령(③ · ④)은 에이전트 대신 사용자가 직접 실행하고(`; echo "EXIT=$?"` 로 종료
   코드를 남긴다) 에이전트는 read-only 로 사후 확인한다.

4. **함정.** (실측 원장: 16.6-LEDGER §7)
   - **(a) secret binding 순서.** Cloud Run 은 secret 환경변수를 인스턴스 기동 **전에**
     해석한다. binding 이 남은 revision 에서 secret 을 파괴하면 떠 있는 인스턴스는
     멀쩡하지만 새 인스턴스(cold start · scale-out)가 조용히 기동에 실패한다 — 그래서
     순서가 재배포 → 삭제 → 파괴다. Firebase CLI 의 in-use 거부
     (`Refusing to destroy secret in use`)는 소스가 아니라 **배포본** 기준이고 binding 이
     **남아 있을 때만** 작동한다. binding 이 0 이면 곧바로 confirm 으로 가는데
     `--non-interactive` 에서 confirm 기본값이 승인이다 — binding 0 상태의 `--force` 를
     뺀 `--non-interactive` 관측 실행 = 파괴다(firebase-tools 15.29.0 소스). 판정은
     `gcloud functions describe` 로, 파괴는 `--force` 1회로 한다.
   - **(b) `enabledAuthProviders` debug assert.** `parseEnabledProviders` 는 CSV 의 미지
     슬러그를 debug assert(`StateError`)로 거부한다. `app_config_test` 가 gitignored 로컬
     `config/*.json` 을 실제로 읽으므로, 로컬 CSV 정리가 `kAllProviderIds` 축소 커밋의
     게이트보다 먼저여야 한다. 배포 스크립트도 manifest 에 없는 토큰을
     `알 수 없는 provider` 로 거부한다.
   - **(c) SPM transitive pin.** 제거한 플러그인이 끌어오던 iOS native 패키지를 다른
     플러그인이 전이 의존으로 요구하면 `Package.resolved` 의 핀은 남고 diff 0 이
     정상이다 — 핀 소실을 기대하지 않는다. 핀을 지우려고 `Package.resolved` 를
     삭제하거나 「Update to Latest Package Versions」 · `flutter clean` 을 돌리면 킷의 모든
     핀이 풀린다. 판독은 `cmp -s` 두 파일 → `git diff --stat -- '**/Package.resolved'` →
     `jq -r '.pins[].identity'` 전후 비교 → `test/ios/spm_policy_test.dart` 순서로 하고,
     핀이 남은 이유를 매뉴얼 「iOS 의존성 관리 (SPM)」 절 고정값 표 비고에 적는다.
   - **(d) 골든 재생성.** `fvm flutter test --no-pub --update-goldens <파일>` 은 그 파일의
     골든 전부를 다시 찍는다. 대상 외 fixture 가 제거 직전 tag 와 바이트 동일한지 `cmp` 로
     확인한다 — 다르면 폰트 · SDK 환경 drift 이므로 원인부터 추적한다. 대상 수는 harness
     override 목록에 달려 있다(계정 정보 화면 연결 섹션을 찍는
     `auth_surfaces_golden_test.dart` 의 `reauth_account_success_*` 골든 포함). 사용자 승인
     전 커밋 금지.
   - **(e) manifest placeholder 순서.** 플러그인 AAR 이 intent-filter 에 `${placeholder}`
     를 요구하고, 앱 `AndroidManifest.xml` 도 `${kakaoNativeAppKey}` ·
     `${kakaoOAuthScheme}` · `${naverWebCallbackScheme}` 를 참조한다. gradle 의
     `manifestPlaceholders` 를 manifest 참조 · 플러그인보다 먼저 지우면 manifest merger 가
     치환 실패로 빌드를 깬다. 반대 순서는 무해하지만 같은 커밋이 원칙이다. 병합 결과는
     `build/app/intermediates/merged_manifests/<flavor>Debug/` 아래 `AndroidManifest.xml`
     을 grep 해 확인하고, `bash scripts/verify_placeholder_builds.sh android dev off` ·
     `… all` 로 산출물 scheme 검사까지 돌린다.

제거는 `git grep -i <provider>`(`.planning/` · sketch `sources/` sign-off 증거 제외) 0 건으로
종결한다 — 0 을 판정하기 전에 남은 provider 이름으로 대조군(≥1)을 먼저 센다.

---

## URL scheme — 킷이 적는 것과 플러그인이 병합하는 것

**킷이 적는 scheme.** `ios/Runner/Info.plist` 와 `android/app/src/main/AndroidManifest.xml`
에 킷이 직접 적은 provider scheme 은 키가 비면 앱 고유 자리표시가 된다 — 끈 provider 가
`fb` · `kakao` · 빈 문자열 같은 일반 scheme 을 등록해 다른 앱의 링크를 가로채지 않게.

| 플랫폼 | provider | 키가 있을 때 | 키가 빌 때 | 자리 |
|--------|----------|--------------|------------|------|
| iOS | Google | `$(REVERSED_CLIENT_ID)` | `unset.google.<bundle id>` | `$(REVERSED_CLIENT_ID:default=unset.google.$(PRODUCT_BUNDLE_IDENTIFIER))` |
| iOS | Facebook | `fb<app id>` | `fbunset.<bundle id>` | `fb$(FACEBOOK_APP_ID:default=unset.$(PRODUCT_BUNDLE_IDENTIFIER))` |
| iOS | Kakao | `kakao<native app key>` | `kakaounset.<bundle id>` | `kakao$(KAKAO_NATIVE_APP_KEY:default=unset.$(PRODUCT_BUNDLE_IDENTIFIER))` |
| iOS | Naver | `$(NAVER_URL_SCHEME)` | `unset.naver.<bundle id>` | `$(NAVER_URL_SCHEME:default=unset.naver.$(PRODUCT_BUNDLE_IDENTIFIER))` — `CFBundleURLSchemes` · `NidUrlScheme` 두 곳 |
| iOS | LINE | `line3rdp.<bundle id>` | (같음 — 키와 무관) | `line3rdp.$(PRODUCT_BUNDLE_IDENTIFIER)` |
| Android | Kakao | `kakao<native app key>` | `unset.kakao.oauth` | gradle `kakaoOAuthScheme` → manifest `${kakaoOAuthScheme}` |
| Android | Naver 웹 콜백 | `naverUrlScheme` 값 | `unset.naver.web` | gradle `naverWebCallbackScheme` → manifest `${naverWebCallbackScheme}` |

빌드 설정은 `enabledAuthProviders` 를 읽지 않고 이미 읽는 키 값의 비어 있음만 본다.
고정 계약은 `test/core/config/provider_url_scheme_contract_test.dart`(T-173-SCHEME-01~03),
빌드 산출물 검사는 `scripts/verify_placeholder_builds.sh <android|ios> <flavor> <off|google|all>`.

**플러그인이 병합하는 scheme — 범위 밖 (Android).** 아래 scheme 은 플러그인
라이브러리(AAR)의 manifest 에 들어 있어 manifest merger 가 앱 manifest 에 병합한다. 키 ·
CSV 와 무관하게 플러그인을 설치한 것만으로 등록된다(빈 키 · 소셜 0개 빌드의 merged
manifest 에도 있다).

| scheme | 출처 |
|--------|------|
| `naver3rdpartylogin` | Naver 로그인 SDK |
| `lineauth` | LINE SDK |
| `fbconnect://cct.<applicationId>` | Facebook SDK (Custom Tab 콜백 · host 에 applicationId) |
| `genericidp` · `recaptcha` | Firebase Auth |

이것을 빼려면 provider on/off 에 따라 플러그인 의존이나 병합 결과를 바꿔야 하고, 그러려면
gradle 이 CSV 를 읽어야 한다 — 빌드 설정이 CSV 를 읽지 않는다는 구조의 범위 밖이다
(2026-10-06 결정 · Phase 17.3 D-04 · D-05). 킷의 빈 scheme 불변식은 킷이 직접 적은 scheme
(위 표)만 다룬다. 플러그인 자체를 빼는 것은 위 「제거 가이드」 ⑥ 이다.
