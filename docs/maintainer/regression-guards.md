# 회귀 가드 지도 (유지보수자 문서)

> 킷 사용자 문서가 아니다 — 사용자 문서는 동작만 쓰고, 무엇이 그 동작을 지키는지는 여기 있다([직접 하는 일](../guide.md)).

킷의 동작 하나를 고치기 전에 이 지도에서 그 동작을 지키는 시험을 찾는다. 시험 ID 는
시험 이름의 접두(`test(` · `testWidgets(` · `group(` 의 첫 인자)이고, ID 가 없는 시험은
파일과 시험 · group 이름으로 적는다. 이 문서가 인용한 시험 ID 는 모두 실제 시험 이름으로
선언돼 있어야 한다 — `test/features/home/manual_nested_routes_contract_test.dart` 가 그것을
확인한다.

데모 화면을 지울 때 함께 지우는 시험은 이 지도에 없다 — 그 목록은
[직접 하는 일](../guide.md#-데모-화면--위치--노출-조건--지우는-법) 의 「지우는 법」 에 있다.

---

## 홈 화면

| 동작 | 가드 시험 파일 | 시험 ID |
|---|---|---|
| `lib` 에서 알림 탭 이동 리스너(`PendingNotificationRouteListener`)를 만드는 파일은 홈 배선 파일(`_homeScreenPath`) 하나다 | `test/features/home/home_listener_source_guard_test.dart` | T-171-HOME-14 |
| 로그아웃은 세션 종료 관리자(`SessionEnding`)를 거친다 — 관리자를 쓰는 파일 집합과 `signOutAndResetOnboarding()` 을 직접 부르는 파일(관리자 1개)이 고정돼 있다 | `test/features/home/home_listener_source_guard_test.dart` | T-171-HOME-16 |
| 알림 허용 목록 가운데 홈이 아닌 경로는 모두 홈 GoRoute 의 `routes:` 아래에 있다 | `test/core/router/app_router_nesting_test.dart` | T-172-ROUTER-01 |

- T-172-ROUTER-01 의 실패 메시지는 `test/helpers/route_tree.dart` 의
  `describeRouteNotUnderHome` 이 만들고, 가이드 「홈 화면 바꾸기」 ④ 의 코드 블록이 그
  문장을 그대로 싣는다. 문구를 바꾸면 둘을 함께 고친다.

## 알림

| 동작 | 가드 시험 파일 | 시험 ID |
|---|---|---|
| 알림으로 계정 정보 화면을 열면 홈 · 설정 · 계정 정보 3장이 쌓이고 뒤로 2번이면 홈이다 | `test/core/router/app_router_nesting_test.dart` | T-172-STACK-01 |
| 알림으로 연 계정 정보 화면 위에서 새 알림을 받아도 이동한다(홈 리스너가 스택 맨 아래에 남는다) | `test/core/router/app_router_nesting_test.dart` | T-172-LISTENER-01 |
| 알림으로 계정 정보 화면을 열면 `screen_view` 가 `settings` · `account` 순서로 2건이다 | `test/core/router/app_router_nesting_test.dart` | T-172-ANALYTICS-01 |
| 알림 탭으로 열 수 있는 화면은 허용 목록 `kNotificationRoutableRoutes` 5개이고, 문자열이 정확히 같을 때만 그 화면으로 간다 | `test/features/notifications/application/notification_route_test.dart` | T-17-PUSH-01 |

- 허용 목록에 화면을 더하면 T-17-PUSH-01 의 기대 Set 에 1줄을 더하고,
  `test/core/router/app_router_observers_test.dart` Test 2 · 3 의 재귀 개수에 1 을 더한다.

## Android 빌드 도구

| 동작 | 가드 시험 파일 | 시험 ID |
|---|---|---|
| 앱 모듈(`android/app/build.gradle.kts`)에 Kotlin Gradle Plugin 적용 줄(`id("kotlin-android")`)이 없고 jvmTarget 은 `compilerOptions` DSL 로 둔다 | `test/infrastructure/android_build_toolchain_contract_test.dart` | T-176-ANDROID-02 |
| `android/gradle.properties` 의 `android.builtInKotlin=true` · `android.newDsl=false` 와 `android/settings.gradle.kts` 의 KGP 선언이 있다 | `test/infrastructure/android_build_toolchain_contract_test.dart` | T-176-ANDROID-03 |

- 새 DSL 을 켤 때(`android.newDsl=true`)는 T-176-ANDROID-03 의 `android.newDsl=false` 단언을
  `android.newDsl=true` 로 고친다.

## iOS SPM

| 동작 | 가드 시험 파일 | 시험 ID |
|---|---|---|
| Crashlytics 기호 업로드 build phase 가 SPM checkout 경로를 찾는다 | `test/ios/spm_policy_test.dart` | T-16.3-SPM-01 |
| 그 경로 찾기가 실패하면 빈 경로를 넘기지 않고 멈춘다 | `test/ios/spm_policy_test.dart` | T-16.3-SPM-02 |
| `ios/Runner.xcworkspace` 와 `ios/Runner.xcodeproj/project.xcworkspace` 의 `Package.resolved` 가 바이트 단위로 같다 | `test/ios/spm_policy_test.dart` | T-16.3-SPM-03 |

- `flutterfire configure` 를 직접 돌리면 Crashlytics build phase 가 다시 만들어진다 —
  T-16.3-SPM-01 · T-16.3-SPM-02 가 실패하면 그 패치가 사라진 것이다.

## iOS 배포 타겟

| 동작 | 가드 시험 파일 | 시험 ID |
|---|---|---|
| `ios/Runner.xcodeproj/project.pbxproj` 의 `IPHONEOS_DEPLOYMENT_TARGET` 12개가 모두 같은 값이고 하한 15.0 이상이다 | `test/ios/ios_deployment_target_consistency_test.dart` | 없음 — 시험 「Runner pbxproj 의 IPHONEOS_DEPLOYMENT_TARGET 이 전부 같은 값이다」 |
| `ios/Podfile` 이 없다(SPM 만 쓴다 — SPM 을 지원하지 않는 플러그인이 들어오면 Flutter 가 CocoaPods 로 넘어가며 이 파일을 만든다) | `test/ios/ios_deployment_target_consistency_test.dart` | 없음 — 시험 「ios/Podfile 이 존재하지 않는다 (SPM 전용)」 |

## Multi-Provider 인증

| 동작 | 가드 시험 파일 | 시험 ID |
|---|---|---|
| 계정 충돌 오류(Firebase Auth `account-exists-with-different-credential` · Functions `already-exists`)가 이메일 없이 `AccountExistsWithDifferentCredential` 한 꼴로 바뀐다(`_mapAuthException` · `_mapFunctionsException`) | `test/features/auth/data/auth_repository_unknown_fallback_test.dart` | 없음 — 시험 `Test U1:` · `Test U2:` |
| 가입 직후 인증 메일 자동 발송 — provider 별 건너뜀 · `isNewUser` 조건 · 실패해도 로그인 유지 · 호출 순서 | `test/features/auth/data/auth_repository_auto_verify_test.dart` | 없음 — 시험 `V1:` ~ `V15:` |
| Facebook 프로필 사진(`_setFacebookPhotoUrl`) — 응답 모양이 달라도 멈추지 않고, 실패해도 로그인 유지 · 오류에 든 id · URL · 이메일이 사진으로 새지 않는다 · 사진 덮어쓰기는 가입 경로 한정 | `test/features/auth/data/auth_repository_facebook_picture_test.dart` | 없음 — 시험 `F1:` ~ `F8:` · `F9` · `F10` · 가입 경로 group |
| 로그아웃이 각 SDK 와 Firebase Auth 를 차례로 끝낸다 | `test/features/auth/data/auth_repository_test.dart` | 없음 — group `signOut` · `signOut (GoogleSignIn + FacebookAuth 병행 호출)` |
| 이미 가입된 이메일 안내에서 이메일 칸을 자동으로 채우지 않고 포커스도 주지 않는다 | `test/features/auth/presentation/login_screen_account_exists_test.dart` · `test/features/auth/presentation/login_screen_test.dart` | 없음 — 앞 파일 전체 · 뒤 파일의 `AUTH-03-17` |

- 이 표의 시험은 `fvm flutter test test/features/auth/` 로 한 번에 돈다.

## 로그인 화면

| 동작 | 가드 시험 파일 | 시험 ID |
|---|---|---|
| 로그인 화면 구성(소셜 버튼 · 「이메일로 계속」 · 이메일 칸 없음) | `test/features/auth/presentation/login_screen_layout_test.dart` · `test/features/auth/presentation/login_screen_test.dart` | 없음 |
| 이메일 로그인 화면 form · 성공 뒤 이동 | `test/features/auth/presentation/email_login_screen_test.dart` · `test/features/auth/presentation/email_login_screen_nav_test.dart` | 없음 |
| 가입 화면 form · 소셜 섹션 없음 · 하단 「로그인」 링크의 진입 경로별 착지 | `test/features/auth/presentation/email_signup_screen_test.dart` | 없음 |
| 「이메일로 계속」 버튼(라벨 · 48 dp 탭 영역) | `test/features/auth/presentation/_widgets/email_auth_cta_test.dart` | 없음 |
| 로그인 안내 시트 — 스크롤 · provider 가 많아도 넘침 0 · 첫 화면의 이메일 버튼 · 소셜 실패 안내 | `test/features/auth/widgets/login_prompt_sheet_overflow_test.dart` · `test/features/auth/widgets/login_prompt_sheet_test.dart` · `test/features/auth/widgets/login_prompt_sheet_error_test.dart` | 없음 |
| 로그인 · 가입 route 등록 · 미인증 접근 허용 목록 | `test/core/router/app_router_observers_test.dart` · `test/core/router/app_routes_test.dart` · `test/core/router/auth_guard_test.dart` | 없음 |
| 로그인 · 가입 화면 문자열 세 언어 원문 | `test/l10n/email_relegation_arb_verbatim_test.dart` | 없음 |
| 이메일 로그인 화면에서 뒤로 가면 로그인 화면으로 돌아온다 | `test/features/auth/presentation/account_linking_sheet_two_step_test.dart` · `test/features/auth/presentation/forgot_password_screen_test.dart` | 없음 — 앞 파일의 group `TS7` |
| 이메일 제출 중에는 소셜 버튼이, 소셜 로그인 중에는 이메일 제출이 잠긴다 | `test/features/auth/presentation/login_screen_test.dart` | 없음 |

## 디자인 토큰

| 동작 | 가드 시험 파일 | 시험 ID |
|---|---|---|
| 시드 색을 `AppTheme.light` · `AppTheme.dark` 인자로 넣을 수 있다 | `test/core/theme/app_theme_test.dart` | T-03-IN-02 |
| `AppTheme.light() == AppTheme.light()` | `test/core/theme/app_theme_test.dart` | T-03-WR-02 |
| 테마 extension 4종의 값 동등성(`==` · `hashCode`) | `test/core/theme/app_colors_test.dart` · `test/core/theme/app_spacing_test.dart` · `test/core/theme/app_typography_test.dart` · `test/core/theme/app_icon_sizes_test.dart` | T-03-WR-02 (앞 세 파일) · `app_icon_sizes_test.dart` 는 group `값 동등성` |
| 시맨틱 색의 라이트 · 다크 대비 | `test/core/theme/app_colors_test.dart` | 없음 — group `WCAG AA contrast` |
| `context.appTypography` 가 로케일별 기하와 override 우선순위를 따른다 | `test/core/theme/theme_extensions_test.dart` | T-03-WR-03 |
| extension 이 등록되지 않은 테마에서도 기본 토큰을 돌려준다 | `test/core/theme/theme_extensions_test.dart` | T-03-WR-04 |
| breakpoint 범위 파생(상한 배타 · 양끝 포화) | `test/core/theme/app_breakpoint_test.dart` | T-03-WR-05 |
| `isPortrait` 은 `isLandscape` 에서 파생된다 | `test/core/theme/app_breakpoint_test.dart` | T-03-IN-05 |
| 키보드 Tab 1번에 버튼 1개(포커스 wrapper 가 정지점을 더하지 않는다) | `test/features/auth/presentation/_widgets/focus_visible_test.dart` | T-03-CR-01 |
| 포커스 outline 은 키보드 조작(`highlightMode` traditional)일 때만 그린다 | `test/features/auth/presentation/_widgets/focus_visible_test.dart` | T-03-WR-01 |
| 포커스 wrapper 의 제약 잠식 수치 · `borderRadius` 방어 | `test/features/auth/presentation/_widgets/focus_visible_test.dart` | T-03-IN-04 |

## ATT 와 iOS Facebook 로그인

| 동작 | 가드 시험 파일 | 시험 ID |
|---|---|---|
| iOS Limited Login 의 익명 승격 충돌 — 새 nonce 로 다시 로그인하고 같은 nonce credential 을 다시 내지 않는다 | `test/features/auth/data/auth_repository_facebook_limited_conflict_test.dart` | 없음 — group `signInWithFacebook — iOS Limited 익명 승격 충돌 (stage 2)` |
| Limited 토큰이면 Graph API 프로필 사진 호출을 건너뛴다 | `test/features/auth/data/auth_repository_facebook_picture_test.dart` | 없음 — 시험 `F10` |
| ATT 권한 상태와 로그인 요청 옵션(`LoginTracking.enabled` · 해시 nonce)으로 Limited · Classic 이 갈리는 동작 | 없음 — `lib/features/auth/data/auth_repository.dart` 의 `_facebookCredentialOf` docstring 이 근거다 | 자동 회귀 가드 없음 — 실기기에서 확인 |

## 브랜드 자산

소셜 로그인 버튼의 로고 자산 · 라벨 · 색을 지키는 시험은 [브랜드 자산 갱신](brand-assets.md) 에 있다.
