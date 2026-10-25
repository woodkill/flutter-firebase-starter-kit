# Changelog

이 킷의 판별 변경 사항을 이 파일에 적는다.
형식은 [Keep a Changelog](https://keepachangelog.com/ko/1.1.0/)를 따르고, 판 번호는 [Semantic Versioning](https://semver.org/lang/ko/)을 따른다.

**판 번호 규칙**

- merge 뒤 사용자가 손봐야 하는 판은 MAJOR 다 — 사용자 소유 표면 표에서 킷이 고칠 가능성이 `낮음` 인 파일의 변경 · 표의 「충돌 시 조치」 칸 밖의 손질이 필요한 변경 · 콘솔 재설정 · 데이터 마이그레이션. 그 판 절 맨 앞 `### 사용자 조치` 에 할 일과 충돌이 날 파일을 적는다. `### 사용자 조치` 가 없는 판은 merge 만으로 끝난다.
- 새 기능 · 새 로그인 수단을 더한 판은 MINOR 다.
- 수정만 담은 판은 PATCH 다.
- 정식 판 전에는 `1.0.0-rc.N` 처럼 rc 번호만 올린다.

사용자 소유 표면 표는 [킷 업데이트 반영](docs/guide.md#킷-업데이트-반영) 절에 있다.

## [Unreleased]

### 사용자 조치

- merge 뒤 `fvm flutter pub get` 을 실행한다. woody_lints 2.0.0 이 새 규칙을 켜므로, 킷이 고치지 않은 내 코드에 info 진단이 생겨 `fvm flutter analyze` 가 실패할 수 있다. `fvm dart fix --apply` 로 고칠 수 있는 것을 고치고 나머지는 손으로 고친다. 규칙을 끄려면 `analysis_options.yaml` 의 `linter: rules:` 에 `<규칙>: false` 를 적는다. 내 무시 주석에는 바로 윗줄에 이유 주석이 있어야 한다(`document_ignores`) — [정적 분석 — woody_lints · riverpod_lint](docs/guide.md#정적-분석--woody_lints--riverpod_lint).
- `pubspec.yaml` 의 `dependencies` · `dev_dependencies` 가 이름 순으로 바뀐다. 의존성을 더하거나 고친 저장소는 이 두 블록에서 충돌한다 — 킷의 순서를 받고 내 항목을 이름 순 자리에 다시 넣은 뒤 `fvm flutter pub get` 을 한다. `name` · `description` · `version` 줄은 내 값 그대로 둔다.
- 직접 하는 일 문서(`docs/guide.md`) 「킷 업데이트 반영」 사용자 소유 표면 표에서 이 판이 고치는 파일과 조치: 12 · 13행 `pubspec.yaml` · `pubspec.lock`(위 항목대로 · lock 이 충돌하면 표의 조치대로 킷 판을 받고 `fvm flutter pub get`) · 19행 `lib/core/router/app_router.dart`(import 순서만 — 충돌은 직접 합친다) · 20행 `lib/features/demo/` · `test/features/demo/`(데모를 지웠다면 규칙 1 의 `git rm` · 「데모를 지웠다면」 규칙 3) · 22행 `lib/features/notifications/data/local_notifications_service.dart`(알림 id 를 고르는 함수의 한 줄 — `_kNotificationColor` 줄은 그대로라 대개 자동 병합되고, 겹치면 내 값) · 23행 `ios/Runner/Info.plist` · 28행 `ios/Runner/Runner.entitlements`(두 파일 모두 XML 주석 한 줄만 바뀐다 — 충돌하면 그 주석 줄은 내 파일 그대로 둔다) · 32행 `bin/setup.dart` · `tool/setup/`(킷 전용 · 고치지 않았다면 충돌 없음).

### Added

- 설정 위저드 `./setup.sh` 를 더한다. macOS 에서 개발 도구를 확인하고(없으면 확인을 받은 뒤 Homebrew 로 설치한다) 앱 정체성 · Firebase 프로젝트 만들기와 결제 연결 · Firestore · Storage · 이메일 로그인 · 앱 등록 · App Check 디버그 토큰 · Cloud Functions 배포를 거쳐 dev flavor 앱 실행과 로그인 확인까지 진행한다. 다시 실행하면 끝난 단계를 건너뛴다. 실행 기록은 `.setup/logs/` 에 남는다. 새 파일은 `setup.sh` · `bin/setup.dart` · `tool/setup/` 이고, `.gitignore` 에 `/.setup/` 한 줄이 더해진다 — README 「빠른 시작」.
- config 에 `appCheckDebugToken` 키를 더한다. debug 빌드가 쓰는 App Check 디버그 토큰이고, 위저드가 값을 만들어 Firebase 의 iOS · Android 앱에 등록한다. 비워 두면 지금처럼 앱이 만든 토큰을 로그에 출력한다. 바뀐 파일은 `config/*.example.json` · `lib/core/config/app_config.dart` · `lib/core/bootstrap.dart` 이고, merge 뒤 `./setup.sh` 를 다시 실행하면 내 `config/<flavor>.json` 에 빈 키를 채운다 — `docs/setup.md` 「위저드가 채우는 설정 키」.
- 설정 위저드에 로그인 수단 고르기 · 출시용 단계 · flavor 선택을 더한다. `./setup.sh --providers` 가 로그인 수단 체크 목록을 열고, 켠 수단마다 provider 콘솔에 넣을 값을 보여 준 뒤 키를 한 번 입력받아 config · xcconfig · Secret Manager · Firebase 로그인 설정에 기록하고, 함수를 배포하고, 앱에서 그 수단으로 로그인했는지 확인한다. Kakao · Naver · LINE 을 켜면 함수를 배포한 뒤 함수 런타임 서비스 계정에 서명 권한(Token Creator)이 있는지 확인하고, 없으면 부여한다. 뺀 수단은 가입자 수를 세어, 한 수단이라도 가입자가 있으면 목록을 바꾸지 않고 Remote Config 로 버튼만 숨기는 방법을 안내한다. 그 수단의 배포된 함수는 따로 묻고 예라고 답할 때만 지운다. 위저드 끝에 출시용 단계(App Check 의 Play Integrity · DeviceCheck 등록과 APNs 키 업로드 안내)가 이어진다 — 「지금 안 함」 으로 미룰 수 있고, 남은 일은 끝에 목록으로 보인다. `./setup.sh --flavor stg`(또는 `--flavor prod`)는 그 flavor 의 Firebase 프로젝트에 같은 흐름을 적용한다. 바뀐 파일은 `bin/setup.dart` · `tool/setup/` 이고 merge 로 끝난다 — README 「빠른 시작」 · `docs/setup.md` 「로그인 수단 켜기」.
- 설정 위저드에 앱 아이콘 단계를 더한다. 로그인 수단 가운데 Naver · Kakao · LINE · Facebook · Google 을 켜면 정사각 원본 이미지 하나(1024 픽셀 이상)를 받아 provider 마다 콘솔 규격의 PNG 를 `.setup/icons/`(git 에 올라가지 않는다)에 만들고 Finder 로 연 뒤, 그 provider 의 값 표에 경로를 보인다. 「지금 안 함」 으로 미룰 수 있고, 다시 실행하면 보관한 원본으로 새로 켠 수단의 파일만 만든다. 바뀐 파일은 `tool/setup/` 이고 merge 로 끝난다 — README 「빠른 시작」.

### Changed

- `scripts/firebase-configure.sh` 가 `config/<flavor>.json` 의 `firebaseProjectId` 를 먼저 쓰고, 그 값이 비었거나 자리표시 값(`your-project-<flavor>`)일 때만 `PROJECT_ID_PREFIX` 로 프로젝트 ID 를 정한다. 어느 값을 썼는지는 출력의 `project source:` 줄에 보인다. config 파일이 있으면 `jq` 가 필요하다. 상수 3줄은 그대로라 merge 로 끝난다 — `docs/guide.md` 「킷 업데이트 반영」 사용자 소유 표면 표 4행.
- woody_lints 를 tag `v2.0.0` 으로 고정하고 묶음 프리셋 `package:woody_lints/recommended.yaml` 로 받는다. 새 규칙 75개가 켜지고, 킷 코드(lib · test · tool · bin)에는 그 진단이 남지 않는다. riverpod_lint plugin 은 프리셋이 `^3.1.9` 범위로 선언하고 분석할 때 pub.dev 에서 받는다. 바뀐 파일은 `pubspec.yaml` · `pubspec.lock` · `analysis_options.yaml` 과 킷 코드 다수이고, 앱 동작은 그대로다. 설정 위저드는 설정 파일에서 키 · 변수 · 리전 자리를 찾지 못한 실패를 전용 예외로 알리고(화면 문구는 같다), 그 밖의 예상하지 못한 오류는 단계 실패로 감추지 않고 위저드를 멈춘다 — [정적 분석 — woody_lints · riverpod_lint](docs/guide.md#정적-분석--woody_lints--riverpod_lint).
- 사용자 매뉴얼을 `docs/setup.md`(위저드로 하는 일) · `docs/guide.md`(직접 하는 일) 두 파일로 나누고 `docs/manual.md` 를 없앤다. 킷의 문서 · 코드 주석 · 위저드 안내는 두 가이드의 절을 가리킨다. 원본 매뉴얼을 고친 저장소는 이 판을 받을 때 그 파일에서 `CONFLICT (modify/delete)` 가 난다 — 고친 내용을 두 가이드의 해당 절로 옮긴 뒤 `git rm docs/manual.md` 로 푼다. 고치지 않았다면 merge 로 끝난다.
- `pubspec.yaml` 의 `flutter:` 절 맨 앞에 `config:` 를 두어 web · macOS · Linux · Windows 대상을 끈다. 킷은 Android · iOS 앱만 만들고, `fvm flutter devices` 에 Android · iOS 기기만 보이며 기기를 지정하지 않은 `fvm flutter run` 이 web · 데스크톱용 Flutter 파일을 내려받지 않는다. 새 시험 `test/infrastructure/pubspec_flutter_config_test.dart` 가 그 네 줄을 지킨다. `pubspec.yaml` 의 `flutter:` 줄 바로 아래를 고치지 않았다면 merge 로 끝난다. web 이나 데스크톱 대상을 쓰려면 그 대상의 줄을 `pubspec.yaml` 과 그 시험의 기대값에서 함께 지운다 — `docs/guide.md` 「Flutter SDK 상향 (FVM)」 ⑨.

### Removed

- `pubspec.yaml` `dev_dependencies` 의 `riverpod_lint` 줄을 뺀다. plugin 은 옵션 파일의 `plugins:` 로 받는다(프리셋이 선언한다).
- 공통 함수 `mirrorTermsAcceptanceSnapshot` 을 뺀다. 킷 앱은 이 함수를 부르지 않는다 — 약관 동의는 앱이 Firestore 에 직접 기록하고, Kakao · Naver · LINE 로그인은 그 로그인 함수가 새 계정에 기록한다. 이미 배포한 프로젝트에서는 `firebase functions:delete mirrorTermsAcceptanceSnapshot --region <functionsRegion> --project <your-project-id>` 로 지운다(`--region` 은 `config/<flavor>.json` 의 `functionsRegion` 값) — `scripts/deploy_functions.sh` 는 배포 목록(`scripts/functions_manifest.json`)의 함수만 배포하므로 이 함수를 저절로 지우지 않고, 남겨 둬도 앱 동작은 같다. 바뀐 파일은 `functions/src/` · `functions/test/` · `scripts/functions_manifest.json` 이고 merge 로 끝난다. `firestore.rules` 는 `users` 규칙 위 주석 두 줄만 바뀌므로 그 주석을 고치지 않았다면 merge 로 끝난다 — `docs/guide.md` 「킷 업데이트 반영」 사용자 소유 표면 표 25행.

## [1.0.0-rc.3] - 2026-10-14

### 사용자 조치

- 데모 화면을 지운 저장소는 이 판을 받을 때 `lib/features/demo/presentation/demo_screen.dart` 에서 `CONFLICT (modify/delete)` 가 난다 — `git rm lib/features/demo/presentation/demo_screen.dart` 로 푼다. `test/features/home/home_listener_source_guard_test.dart` 가 충돌하면 `git checkout --theirs -- test/features/home/home_listener_source_guard_test.dart` 로 킷 판을 받은 뒤 T-171-HOME-15 를 지우고, T-171-HOME-16 기대 집합에서 `demo_screen.dart`(상수 `_demoScreenPath`)를 다시 빼고, 쓰는 곳이 없어진 `_demoScreenPath` 선언을 지운 다음 `git add` 한다. 데모 화면을 지우지 않았다면 할 일이 없다 — `docs/guide.md` 「킷 업데이트 반영」 「충돌 풀기」 규칙 3 · 「홈 화면 바꾸기」 ③ 「지우는 법」 4단계.

### Added

- 로그아웃과 회원탈퇴 마무리 동안 화면 전체를 덮는 진행 오버레이를 더한다. 로그아웃은 확인한 직후, 회원탈퇴는 서버 삭제가 끝난 직후부터 온보딩 화면이 뜰 때까지 스피너와 「로그아웃 처리 중…」 · 「탈퇴 처리 중…」 문구가 보이고 입력이 막힌다. 로그아웃이 예외로 끝나면 바로 걷히고, 30초가 지나면 로그아웃은 계속 진행한 채 오버레이만 걷힌다. 새 문구 키는 `authSigningOut` · `withdrawalFinalizing` 이다(영어 · 한국어 · 일본어). 로그아웃 뒤 목적지를 온보딩이 아닌 화면으로 바꿨다면 그 화면의 route `builder` 를 `SessionEndingArrival` 로 감싼다 — `docs/guide.md` 「알아 둘 동작」 절.
- Google 로그인 버튼에 쓰는 자산 두 가지를 싣는다. Google Sans 라틴 subset 글꼴(`assets/fonts/googlesans/` · SIL OFL 1.1)은 버튼 라벨의 영문만 그리고, 한글 · 가나는 기기 글꼴로 그려진다. gradient G 투명 PNG 4장(`assets/brand/google/` · 1 ~ 4배)은 Google 이 배포하는 공식 버튼 SVG 의 G 를 Chrome 으로 그린 것이다. Google 로그인 브랜드 가이드가 버튼 글꼴로 Google Sans Medium 을, 로고로 gradient G 를 요구한다. 바뀐 파일은 `assets/fonts/googlesans/` · `assets/brand/google/` · `pubspec.yaml` · `LICENSE` 다. 만드는 절차는 각 디렉터리의 `README.md` 에 있다 — `docs/guide.md` 「소셜 로고 · 브랜드 자산」.
- 테스트 안내 `test/README.md` 를 더한다 — 디렉터리 구조 · 분류별로 기능을 바꾸거나 지울 때 할 일 · 이름 짓기 · 린트 기준 · golden 갱신 · 커밋 전에 돌릴 검사. 복사해 쓸 수 있는 예제 테스트 2개(`test/examples/` — `LoginNotifier` unit · `NotFoundScreen` widget)와 `AuthRepository` 를 만드는 테스트 헬퍼 `buildAuthRepository` · 공용 mock(`test/helpers/auth_mocks.dart`)이 함께 들어간다. 바뀐 파일은 `test/` 아래뿐이라 merge 로 끝난다.

### Changed

- Android 빌드 도구를 Gradle 9.3.1 · Android Gradle Plugin 9.1.0 · Kotlin Gradle Plugin 2.4.0 · google-services Gradle 플러그인 4.5.0 · Crashlytics Gradle 플러그인 3.0.8 로 올린다. Flutter 가 내던 지원 종료 경고 3건이 사라지고, Kotlin Gradle Plugin 적용 경고는 FlutterFire 플러그인 8개를 나열하는 1줄이 남는다(빌드를 막지 않는다 — FlutterFire 가 플러그인 빌드 파일을 바꾸면 사라진다). `android/app/build.gradle.kts` 는 `buildFeatures { resValues = true }` 와 `kotlin { compilerOptions { … } }` 를 쓴다 — 앱 ID · 서명 줄은 그대로라 merge 로 끝난다. 바뀐 파일은 `android/settings.gradle.kts` · `android/gradle/wrapper/gradle-wrapper.properties` · `android/app/build.gradle.kts` 다. Android Studio 로 `android/` 를 열려면 2025.3.2 이상이 필요하다 — `docs/guide.md` 「Flutter SDK 상향 (FVM)」 ⑤.
- 앱 모듈이 Android Gradle Plugin 의 내장 Kotlin 을 쓴다 — `android/gradle.properties` 가 `android.builtInKotlin=true` 이고 `android/app/build.gradle.kts` 에 `kotlin-android` 플러그인 줄이 없다. Naver 웹 로그인에 쓰는 `flutter_web_auth_2` 는 `6.0.0-alpha.8` 로 고정한다 — 내장 Kotlin 을 지원하는 판이 아직 정식판 전 alpha 뿐이라서이고, 정식판이 나오면 올린다. `google_sign_in_android` · `shared_preferences_android` · `kakao_flutter_sdk_auth` · `kakao_flutter_sdk_common` · `kakao_flutter_sdk_user` 는 patch 판으로 오른다. `flutter_web_auth_2` 를 따라 `flutter_web_auth_2_platform_interface` 가 6.0.0-alpha.2 로, `window_to_front` 가 1.0.0 으로 오르고, `material_ui` 1.6.0 · `cupertino_ui` 1.1.2 가 새 transitive 의존성으로 들어온다(Flutter SDK 의 `material.dart` · `cupertino.dart` 와 별개 패키지다). 이 둘 때문에 `pubspec.lock` 의 SDK 하한이 Dart 3.13.0 · Flutter 3.47.0 이 된다 — `.fvmrc` 의 Flutter 로 `fvm flutter pub get` 하면 lock 그대로 끝나고, 다른 Flutter 를 쓰면 3.47.0 이상이어야 lock 이 그대로 받아진다. `pubspec.yaml` 의 `environment: sdk` 하한은 그대로다. 앱 동작은 그대로다. 바뀐 파일은 `android/gradle.properties` · `android/app/build.gradle.kts` · `pubspec.yaml` · `pubspec.lock` 이고, merge 뒤 `fvm flutter pub get` 으로 끝난다(`docs/guide.md` 「킷 업데이트 반영」) — `docs/guide.md` 「Flutter SDK 상향 (FVM)」 ⑤.
- `flutter_line_sdk` 를 3.0.0 으로 올린다. 새 Android Gradle Plugin 에서 Android 빌드가 되는 판이다. iOS 는 15.0 이상 · LineSDK 5.17 이상을 요구하고, 킷의 iOS 핀(5.17.0)은 그대로다. 바뀐 파일은 `pubspec.yaml` · `pubspec.lock` 이다 — `docs/guide.md` 「iOS 의존성 관리 (SPM)」 ②.
- 소셜 로그인 버튼 6개(Google · Apple · Facebook · Kakao · Naver · LINE)를 한 벌의 골격으로 그린다 — 높이 48 · radius 12 · 라벨 16 · 굵기 500 · 로고와 라벨 가운데 묶음 · 로고 상자 20dp(Naver 18 · LINE 은 높이 20 에 종횡비 유지 · Apple 은 공식 medium 로고를 버튼 높이에 맞춤) · 비활성 투명도 0.38. 라벨 글꼴은 기기 기본이다 — Android 는 영문이 킷이 싣는 Roboto 이고 한글 · 가나는 기기 글꼴, iOS 는 시스템 글꼴이며 Google 버튼의 영문만 Google Sans 다. 배경색 · 글자색 · 외곽선 · 로고 · 문구는 브랜드 가이드 값 그대로다. 버튼마다 크기 · 모서리 · 글꼴이 달라 한 화면에 놓으면 들쭉날쭉했다. 바뀐 파일은 `lib/features/auth/presentation/_widgets/branded_social_button.dart` · `assets/brand/apple/` · `assets/brand/google/` · `pubspec.yaml` 이다. 버튼 값이나 로고를 바꾸면 버튼 기준 그림(golden)을 다시 만든다 — `docs/guide.md` 「소셜 로고 · 브랜드 자산」.
- 휴대폰 글자 크기를 키워도 소셜 로그인 버튼의 글자는 1.34배까지만 커지고 버튼 높이와 로고는 그대로다. 버튼 밖 글자는 설정대로 커진다. 큰 글자 설정에서 버튼 글자가 잘리는 일을 줄인다. 상한은 `lib/features/auth/presentation/_widgets/branded_social_button.dart` 의 `kBrandLabelScaleCap` 이다.
- 「이미 가입된 이메일입니다」 시트의 소셜 버튼 글자가 수단 이름(예: 「카카오」)에서 로그인 문구(예: 「카카오 로그인」)로 바뀐다. 로그인 화면의 같은 버튼과 문구가 같아진다. 새 문구 키는 없다. 바뀐 파일은 `lib/features/auth/presentation/_widgets/account_linking_sheet.dart` 다.

### Removed

- Pretendard · Inter 번들 글꼴을 뺀다(`assets/fonts/pretendard/` · `assets/fonts/inter/` · `pubspec.yaml` 의 `Pretendard` · `Inter` family 선언 · `LICENSE` 제3자 자산 목록의 두 줄). 소셜 로그인 버튼이 더는 쓰지 않는다. 앱 코드에서 이 두 family 이름을 `fontFamily` 로 직접 쓰고 있었다면 그 글자는 기기 기본 글꼴로 그려진다 — 계속 쓰려면 글꼴 파일과 `pubspec.yaml` 선언을 자기 프로젝트에 다시 싣는다.
- 옛 4색 Google G(`assets/brand/google/btn_signin_icon.svg`)를 뺀다. Google 로그인 버튼은 gradient G PNG 를 쓴다.

### Fixed

- 회원탈퇴에서 서버 삭제가 끝난 뒤 온보딩 화면으로 넘어가기 전에 「탈퇴」 버튼과 뒤로 가기가 다시 살아나던 문제를 고친다. 이미 삭제된 계정으로 「탈퇴」 를 다시 누를 수 없다.

## [1.0.0-rc.2] - 2026-10-10

### Added

- 인증 메일 · 비밀번호 재설정 메일을 킷이 보내는 `kit` 모드를 더한다. `config/<flavor>.json` 의 `emailDelivery` 로 고르고, 키가 없거나 비었거나 `firebase` 면 지금처럼 Firebase 가 보낸다. `kit` 은 내 발송 서비스(SMTP)와 Trigger Email 확장으로 보내고, 확장 값은 내가 만드는 `extensions/firestore-send-email.env.<your-project-id>` 에 적는다 — `docs/guide.md` 「인증 메일 발송 모드 켜고 끄기」 절.
- `kit` 모드의 인증 · 재설정 메일 템플릿을 한국어 · 영어 · 일본어로 제공한다. 메일 머리에 앱 이름(로고를 두면 로고)이 나오고 버튼은 `brandColor` 로 칠한다. 문구는 `functions/src/email/copy.json` 에서 고친다 — `docs/guide.md` 「인증 메일 발송 모드 켜고 끄기」 절.
- `kit` 모드 메일의 링크는 킷의 결과 페이지(인증 · 비밀번호 재설정)로 열린다 — 앱 이름 · 색 · 로고가 들어간다. `kit` 을 켜는 `bash scripts/deploy_email.sh <flavor> kit --apply` 가 결과 페이지를 Firebase Hosting 에 함께 배포하고, 로고는 `hosting/public/logo.png` 에 두면 페이지와 메일 머리에 함께 쓰인다. `firebase` 모드 메일의 링크는 지금처럼 Firebase 기본 페이지로 열린다. 새 파일을 merge 때 어떻게 다루는지는 「킷 업데이트 반영」 절의 사용자 소유 표면 표에 있다 — `docs/guide.md` 「인증 결과 페이지 바꾸기」 절.
- config 의 `firebaseWebApiKey` 키를 더한다. `kit` 모드의 결과 페이지는 이 키로만 Firebase 를 초기화하고 메일 링크에 실린 키는 쓰지 않는다 — 다른 프로젝트에서 만든 링크는 「사용할 수 없는 링크」 로 끝난다. `kit` 을 켤 때 이 키(웹 API 키)를 채운다. 값은 Google Cloud Console → API 및 서비스(APIs & Services) → 사용자 인증 정보(Credentials) 의 `Browser key (auto created by Firebase)` 다. 비었거나 자리표시 값이면 결과 페이지 빌드가 `FAIL:` 로 멈춘다. `firebase` 모드는 채우지 않아도 된다. merge 뒤 `diff config/dev.example.json config/dev.json` 으로 새 키를 내 파일에 옮겨 적는다 — `docs/setup.md` 「위저드가 채우는 설정 키」 · `docs/guide.md` 「인증 메일 발송 모드 켜고 끄기」 「켜기」 ②.
- config 의 `brandColor` 키(`#RRGGBB`)가 앱 테마 · 결과 페이지 · 메일의 브랜드 색을 정한다. 비우거나 형식이 틀리면 `#673AB7` 로 동작하고, 바꾼 뒤에는 앱을 다시 빌드한다 — `docs/setup.md` 「위저드가 채우는 설정 키」.
- 앱이 보내는 인증 · 재설정 메일이 앱 언어(한국어 · 영어 · 일본어)로 온다. `firebase` 모드에서도 같다 — `docs/guide.md` 「인증 메일 발송 모드 켜고 끄기」 절.
- README 머리에 지금 판이 `v1.0.0` 전의 pre-release 판이라 판마다 구조와 설정이 바뀔 수 있다는 안내를 둔다 — README 머리.

### Fixed

- 앱 ID 변경 도구(`bin/rename.dart`)가 키 없는 빌드용 Firebase placeholder(Android `google-services.json` 2종의 `package_name` · iOS `GoogleService-Info.plist` 3종의 `BUNDLE_ID`)도 새 앱 ID 로 바꾼다. 앱 ID 를 바꾼 뒤 `--flavor stg` · `--flavor prod` Android 빌드가 `No matching client found for package name` 으로 멈추던 문제를 고친다. 실 값으로 바꾼 파일은 건드리지 않는다.
- placeholder 검사 테스트가 기대 앱 ID 를 `android/app/build.gradle.kts` 의 `applicationId` 와 `ios/Runner.xcodeproj/project.pbxproj` 의 번들 ID 에서 읽는다. 앱 ID 를 바꾼 저장소에서도 `fvm flutter test` 가 통과한다.
- 앱 ID 변경 도구가 `--apply` 뒤 안내하는 빌드 확인 명령에 flavor 를 준다(`--flavor dev --dart-define-from-file=config/dev.json`, 키 없이 확인할 때는 `--flavor stg`). flavor 없는 명령은 이 프로젝트에서 빌드되지 않는다.
- 앱 ID 변경 도구가 미리 보기에서 센 자리만 바꾼다. `project.pbxproj` · 내 xcconfig · `scripts/firebase-configure.sh` 의 주석 줄이 같은 값을 품고 있어도 그 줄은 그대로 둔다.
- 앱 ID 변경 도구가 내 config 파일의 `appName` 을 바꿀 때 키와 값 사이의 공백을 그대로 둔다.
- 앱 ID 변경 도구가 내 xcconfig(`ios/Flutter/<flavor>.xcconfig`)의 번들 ID 줄을 바꿀 때 줄 끝 공백을 그대로 둔다.
- README 머리를 검사하는 테스트가 킷 저장소에서만 돈다. README 를 내 앱 소개로 바꾼 저장소에서도 `fvm flutter test` 가 통과한다.
- `ios/Runner.xcodeproj/project.pbxproj` 에 `DEVELOPMENT_TEAM` 이 없는지 검사하는 테스트가 킷 저장소에서만 돈다. Xcode 에서 Team 을 골라 그 줄이 생긴 저장소에서도 `fvm flutter test` 가 통과한다. Team ID 는 그대로 `ios/Flutter/<flavor>.xcconfig` 에 적는다.

## [1.0.0-rc.1] - 2026-10-07

### Added

- 초기 공개 — 킷의 첫 공개 판이다. 아래 기능을 담는다.
- 로그인: 이메일 · 게스트와 소셜 로그인 6종(Google · Apple · Facebook · Kakao · Naver · LINE)을 제공하고, config 의 `enabledAuthProviders` 로 수단마다 켜고 끈다.
- 계정: 로그인 수단 연결 · 해제와 회원 탈퇴를 제공한다.
- 앱 진입: 스플래시 · 온보딩 · 약관 동의를 거쳐 홈으로 들어간다.
- 다국어: 영어 · 한국어 · 일본어(en · ko · ja) 문구를 ARB 로 관리한다.
- 환경 분리: dev · stg · prod flavor 를 `--dart-define-from-file` 로 나눈다.
- 디자인 시스템: ThemeExtension 기반 디자인 토큰과 라이트 · 다크 테마를 제공한다.
- Firebase: Crashlytics · Analytics · Remote Config(Kill Switch) · Cloud Storage · Cloud Functions · FCM(알림을 눌러 해당 화면 열기)을 연결한다.
- 홈: 앱의 홈 화면을 바꿔 끼우는 교체 지점과 개발자 데모 화면(release 빌드 제외)을 제공한다.
- 함수 배포 스크립트(`scripts/deploy_functions.sh`)가 켠 로그인 수단에 맞는 Cloud Functions 만 배포한다.
- 키 없는 빌드 게이트(`scripts/verify_placeholder_builds.sh`)가 실제 키 없이도 flavor 별 Android · iOS 빌드가 되는지 확인한다.
- 앱 ID 변경 도구(`bin/rename.dart`)가 Android 앱 ID · iOS 번들 ID · 앱 이름 · Firebase 프로젝트 ID 접두어를 새 값으로 바꾼다(미리 보기가 기본).
- 정적 분석: woody_lints · riverpod_lint 규칙으로 코드를 검사한다.

[Unreleased]: https://github.com/woodkill/flutter-firebase-starter-kit/compare/v1.0.0-rc.3...HEAD
[1.0.0-rc.3]: https://github.com/woodkill/flutter-firebase-starter-kit/releases/tag/v1.0.0-rc.3
[1.0.0-rc.2]: https://github.com/woodkill/flutter-firebase-starter-kit/releases/tag/v1.0.0-rc.2
[1.0.0-rc.1]: https://github.com/woodkill/flutter-firebase-starter-kit/releases/tag/v1.0.0-rc.1
