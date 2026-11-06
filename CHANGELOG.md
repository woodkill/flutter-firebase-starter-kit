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

- 알림 색을 손으로 바꾼 저장소(`android/app/src/main/res/values/colors.xml` 의 `notification_color` · `lib/features/notifications/data/local_notifications_service.dart` 의 `_kNotificationColor`)는 이 판을 받을 때 두 파일에서 충돌이 난다. `colors.xml` 은 킷이 지운 파일이라 `CONFLICT (modify/delete)` 가 난다 — 그 파일에서 `notification_color` 줄과 그 위 알림 색 설명 주석을 지우고, 남은 `<color>` 가 없으면 `git rm android/app/src/main/res/values/colors.xml`, 있으면 `git add android/app/src/main/res/values/colors.xml` 한다(그 줄을 남겨도 빌드는 되지만 빌드가 `brandColor` 로 만든 값이 이겨 쓰이지 않는다). `local_notifications_service.dart` 는 `CONFLICT (content)` 가 난다 — 충돌 블록마다 킷 쪽(`=======` 와 `>>>>>>>` 사이)만 남기고 `git add` 한다. 그 뒤 손으로 넣었던 색을 `config/dev.json` · `config/stg.json` · `config/prod.json` 의 `brandColor` 에 `#RRGGBB` 로 쓰고 다시 빌드한다 — 이 판부터 알림 색은 `brandColor` 하나를 따르므로 알림 색을 브랜드 색과 다르게 두었다면 두 색이 하나가 된다. 알림 색을 손으로 바꾸지 않았다면 할 일이 없다.
- 「홈 화면 바꾸기」 ③ 의 지우는 법으로 데모 화면을 지운 저장소는 이 판을 받을 때 `lib/features/demo/presentation/demo_screen.dart` 에서 `CONFLICT (modify/delete)` 가 난다 — `git rm lib/features/demo/presentation/demo_screen.dart` 로 푼다. 데모 화면을 지우지 않았다면 할 일이 없다.
- 간격 토큰 `AppSpacing` 의 `xs` · `sm` 을 바꿔 둔 저장소는 이 판부터 킷 화면의 배지 · 배너 · 안내 상자 모서리가 그 값을 따르지 않는다 — 모서리도 그 값으로 두려면 「디자인 토큰 바꾸기」 2번의 `extensions:` 리스트에 `const AppRadius().copyWith(xs: …, sm: …)` 를 넣는다. 간격 토큰을 바꾸지 않았다면 할 일이 없다.

### Added

- 브랜드 원색 토큰 `context.appColors.brand` 가 생긴다. config `brandColor` 의 색 그대로(비우거나 형식이 틀리면 `#673AB7`)이고 라이트 · 다크가 같은 값이라, 시드에서 다시 계산한 `colorScheme.primary` 와 달리 로고 · 지도 강조처럼 브랜드 hex 그대로가 필요한 곳에 쓴다(위에 올릴 글자 색 · 대비는 쓰는 쪽이 정한다). `AppColors.fromBrightness(...)` 를 `brand` 없이 부르면 같은 config 색이 들어가므로 「디자인 토큰 바꾸기」 대로 `copyWith(extensions:)` 에 토큰을 다시 등록한 코드는 그대로 둔다. 바뀐 파일은 `lib/core/theme/app_colors.dart` · `lib/core/theme/app_theme.dart` · `lib/app.dart` · `docs/guide.md` · `config/README.md` · `docs/setup.md` · 시험이고, `lib/core/theme/` 를 고치지 않았다면 merge 로 끝난다(고쳤다면 사용자 소유 표면 표 21행).
- 디자인 토큰에 모서리 둥글기 `context.appRadius`(`xs` 4 · `sm` 8 · `md` 12 · `lg` 16 · `xl` 28 — Material 3 모양 단계)와 투명도 `context.appOpacity`(Material 3 상태 레이어 `hover` 0.08 · `focus` 0.1 · `pressed` 0.1 · `dragged` 0.16, 비활성 `disabled` 0.38 · `disabledContainer` 0.12, 킷 가림막 `scrim` 0.32 · 비활성 표시 `inactive` 0.3)가 생기고, 아이콘 크기 `context.appIconSizes` 가 `xs` 16 · `sm` 20 · `md` 24 · `lg` 32 · `xl` 48 · `xxl` 64 여섯 단계가 된다(`sm` 은 그대로). 킷 화면의 모서리 · 아이콘 크기 · 투명도 숫자와 간격 토큰으로 정하던 모서리를 이 토큰으로 바꾸며 화면 결과는 같다. 「디자인 토큰 바꾸기」 대로 `copyWith(extensions:)` 에 네 extension 을 다시 등록한 코드는 그대로 두어도 새 토큰을 기본값으로 읽고, 새 토큰을 조정하려면 그 리스트에 `const AppRadius()` · `const AppOpacity()` 를 더한다. 바뀐 파일은 `lib/core/theme/app_radius.dart` · `lib/core/theme/app_opacity.dart` · `lib/core/theme/app_icon_sizes.dart` · `lib/core/theme/app_theme.dart` · `lib/core/theme/theme_extensions.dart` · `lib/shared/widgets/error_banner.dart` · `lib/features/auth/presentation/_widgets/account_linking_sheet.dart` · `lib/features/auth/presentation/_widgets/auth_in_progress_overlay.dart` · `lib/features/auth/presentation/_widgets/login_prompt_sheet.dart` · `lib/features/auth/presentation/forgot_password_screen.dart` · `lib/features/auth/presentation/verify_email_screen.dart` · `lib/features/demo/presentation/demo_screen.dart` · `lib/features/not_found/presentation/not_found_screen.dart` · `lib/features/onboarding/presentation/_widgets/onboarding_indicator.dart` · `lib/features/onboarding/presentation/_widgets/terms_checkbox_group.dart` · `docs/guide.md` · 시험이고, `lib/core/theme/` 를 고치지 않았다면 merge 로 끝난다(고쳤다면 사용자 소유 표면 표 21행).

### Fixed

- 알림 색이 config `brandColor` 를 따른다. 앱 안 알림과, 앱이 뒤에 있거나 꺼져 있을 때 Android 가 그리는 FCM 알림의 색이 브랜드 색과 따로 킷 보라 `#673AB7` 로 남던 문제를 고친다 — 빌드가 `brandColor` 로 리소스 `notification_color` 를 만들고(비우거나 형식이 틀리면 `#673AB7`), 앱 안 알림도 같은 값을 쓴다. 사용자 소유 표면 표 22행은 알림 아이콘만 남는다. 바뀐 파일은 `android/app/build.gradle.kts` · `android/app/src/main/res/values/colors.xml`(삭제) · `lib/features/notifications/data/local_notifications_service.dart` · `docs/guide.md` · 시험이고, 알림 색을 손으로 바꿨다면 위 「사용자 조치」 를 본다.

## [1.0.0-rc.10] - 2026-11-06

### 사용자 조치

- merge 뒤 `functions/` 의 `pnpm run lint` 가 필드 객체를 먼저 넘긴 logger 호출(`logger.info({event: "…"}, "…")` 꼴)을 거부한다. 내가 더한 함수 파일에 그런 호출이 있으면 인자 순서만 `logger.info("…", {event: "…"})` 로 바꾼다(메시지 · 필드 내용은 그대로).
- 「홈 화면 바꾸기」 ③ 의 지우는 법으로 데모 화면을 지운 저장소는 이 판을 받을 때 `lib/features/settings/presentation/settings_screen.dart` 의 생성자 · 「개발자」 묶음 자리에서 `CONFLICT (content)` 가 난다. 충돌 블록마다 킷 쪽(`=======` 와 `>>>>>>>` 사이)을 받은 뒤 「개발자」 묶음의 `const _DemoRow(),` 한 줄만 다시 지우고, `import 'package:flutter/foundation.dart';` 줄이 없으면 다시 넣은 다음 `git add` 한다. `test/features/settings/presentation/settings_screen_test.dart` 가 충돌하면 `git checkout --theirs -- <그 파일>` 로 킷 판을 받은 뒤 `docs/guide.md` 「홈 화면 바꾸기」 ③ 「지우는 법」 4단계의 그 파일 항목(상수까지 지웠다면 1단계의 하네스 항목도)을 다시 따르고 `git add` 한다. 새 파일 `lib/features/settings/presentation/developer_rows.dart` 는 충돌 없이 들어온다. 데모 화면을 지우지 않았다면 할 일이 없다.

### Added

- 설정 화면 「개발자」 묶음에 내 개발용 행을 더하는 자리가 생긴다. `lib/features/settings/presentation/developer_rows.dart` 의 `buildAppDeveloperRows()`(킷 판은 빈 목록)에 행을 더하면 「개발자 · 데모 화면」 행 뒤에 뜨고 release 빌드에서는 묶음째 빠진다. 이 파일은 사용자 소유 표면 38행(킷이 고칠 가능성 `없음`)이다. 데모를 지우는 법은 「개발자」 묶음 전체 대신 `const _DemoRow(),` 한 줄과 `_DemoRow` 클래스를 지우는 꼴이 되고, 데모 행도 내 행도 없으면 「개발자」 제목도 뜨지 않는다(`docs/guide.md` 「홈 화면 바꾸기」 ③ 「지우는 법」). 킷 설정 시험과 golden 은 개발용 행 없이 그려 내 행이 섞이지 않는다. 바뀐 파일은 `lib/features/settings/presentation/settings_screen.dart` · `developer_rows.dart`(새) · `docs/guide.md` · 시험이고, 데모를 지우지 않았다면 merge 로 끝난다(지웠다면 위 「사용자 조치」).

### Fixed

- 킷 Cloud Functions 운영 로그의 `event` · `uid` · `code` 같은 필드가 Cloud Logging `jsonPayload` 필드로 남아 `jsonPayload.event="ping_invoked"` 같은 필터와 로그 기반 지표에 쓸 수 있다. 킷 함수의 logger 호출이 필드 객체를 먼저 넘겨 이 필드들이 `textPayload` 문자열 안에 섞이던 문제를 고친다. 바뀐 파일은 `functions/src/` 의 함수 파일 · `functions/test/` 의 시험 · `functions/.eslintrc.js` · `docs/guide.md` 이고, 그 파일들을 고치지 않았다면 merge 로 끝난다(내가 더한 함수 파일은 위 「사용자 조치」).

## [1.0.0-rc.9] - 2026-11-06

### 사용자 조치

- merge 뒤 `lib/l10n/app_en.arb` 의 `appTitle` 을 내 앱의 기본 이름(`config/<flavor>.json` 의 `appName` 에서 ` Dev` · ` Stg` 를 뗀 값)으로 맞춘다. 두 값이 다르면 iOS · Android 첫 빌드가 두 값과 고칠 파일을 알리며 멈춘다. `./setup.sh` 를 다시 실행하면 「앱 정체성」 단계가 이 값을 맞춘다. 맞춘 뒤 `fvm flutter pub get` 으로 다시 만든 `lib/l10n/generated/` 를 함께 커밋한다.
- `ios/Runner.xcodeproj/project.pbxproj` 에 Runner 빌드 단계 「Localize Launcher Name」 하나가 더해지고, `android/app/build.gradle.kts` 에 홈 화면 이름 생성 task · `app_name` 리소스 줄이 더해지며 `manifestPlaceholders["appName"]` 값이 `@string/app_name` 으로 바뀐다. 두 파일을 고치지 않았다면 merge 로 끝나고, 충돌하면 그 줄들은 킷 값을 받는다(사용자 소유 표면 표 7행 · 9행).
- 킷 `lib/l10n/app_ko.arb` · `app_ja.arb` 의 `appTitle` 이 빠진다. 그 언어 이름을 내 값으로 두었다면 merge 충돌에서 내 줄을 남긴다.
- Android 빌드는 `--dart-define-from-file=config/<flavor>.json` 없이 하면 config 이름이 빌드에 들어오지 않았다는 오류로 멈춘다. 빌드 명령마다 이 옵션을 붙인다.

### Added

- 홈 화면 앱 이름이 기기 언어를 따른다. 그 언어 ARB 의 `appTitle` 이 이름이고, 빌드가 iOS · Android 이름 파일을 빌드 산출물 안에만 만든다. dev · stg 의 다른 언어 이름에는 config `appName` 이 ` Dev` · ` Stg` 로 끝나면 같은 접미사가 붙는다. 언어를 더할 때 `ios/` · `android/` 파일은 고치지 않는다 — 빌드가 그 언어의 이름 파일을 만든다(절차는 [언어별 앱 이름 넣기 · 앱 언어 추가하기](docs/guide.md#언어별-앱-이름-넣기--앱-언어-추가하기)). 빌드된 iOS 앱은 ARB 언어 목록을 앱이 다루는 언어로 알린다. 바뀐 파일은 `tool/launcher_names.dart`(새) · `ios/Runner.xcodeproj/project.pbxproj` · `android/app/build.gradle.kts` · `docs/guide.md` · `docs/setup.md` · 시험이고, 두 네이티브 파일은 위 「사용자 조치」 를 본다.
- 설정 위저드에 「언어별 앱 이름」 단계가 「앱 정체성」 다음에 들어간다. 영어 아닌 ARB(`lib/l10n/app_ko.arb` · `app_ja.arb` · 더한 언어)마다 홈 화면 · 앱 안 제목에 쓸 이름을 묻고 그 ARB 의 `appTitle` 에 쓰며, Enter 면 기본 이름을 그대로 기록해 그 언어는 다시 묻지 않는다. 기존 사용자가 merge 뒤 `./setup.sh` 를 다시 실행하면 이 단계가 할 일로 보이고, 영어 `appTitle` 이 내 앱의 기본 이름과 다르면 「앱 정체성」 단계도 할 일로 보인다(위 「사용자 조치」 첫 항목). 입력은 앞뒤 공백을 떼고, 빈 이름 · 이어진 공백 · ` Dev` · ` Stg` 로 끝나는 이름은 받지 않고 다시 묻는다 — 공백 규칙은 빌드의 이름 생성기와 같고, 접미사는 flavor 접미사와 겹치므로 위저드가 받지 않는다 — 다시 물을 때 「빌드가 붙인다」 고 알리는 것은 지금 flavor 의 표시 이름이 그 접미사로 끝날 때뿐이다(ARB 에 손으로 쓴 접미사 값은 빌드가 거부하지 않는다). 한국어 화면의 앱 이름(ko `appTitle`, 없으면 영어 `appTitle`)이 마지막 커밋과 달라지면 홈 화면 golden 2장을 다시 만드는 명령을 끝 요약에 안내한다(이 단계가 이름을 물은 실행이면 단계 직후에도 · 실행은 하지 않는다) — 「앱 정체성」 에서 기본 이름만 바꾼 경우도 안내한다. 이 판정이 커밋된 ARB 원문을 읽는 git 명령은 실행 기록(`.setup/logs/`)에 본문 대신 글자 수만 남긴다. 바뀐 파일은 `tool/setup/steps/app_names_step.dart`(새) · `tool/setup/arb_titles.dart`(새) · `tool/setup/locale_endonyms.dart`(새) · `tool/setup/config_files.dart` · `tool/setup/steps/flavor_steps.dart` · `tool/setup/completion.dart` · `tool/setup/git_tree.dart` · `tool/setup/command_runner.dart` · `tool/launcher_names.dart` · `docs/setup.md` · `docs/guide.md` · 시험이고, 모두 킷 전용(사용자 소유 표면 32행)이라 merge 로 끝난다.

### Changed

- 앱 안 제목(홈 AppBar · Android 최근 앱)이 config `appName` 대신 앱 언어의 ARB `appTitle` 이고, config `appName` 이 ` Dev` · ` Stg` 로 끝나면 같은 접미사를 붙인다. 설정 위저드 「앱 정체성」 단계가 `lib/l10n/app_en.arb` 의 `appTitle` 에 표시 이름에서 접미사를 뗀 값도 쓰고, 다시 실행하면 영어 `appTitle` 과 표시 이름의 어긋남을 맞춘다. 킷의 영어 `appTitle` 은 example 표시 이름의 기본 이름 `StarterKit` 이다. 바뀐 파일은 `lib/app.dart` · `lib/core/l10n/app_title.dart` · `lib/core/config/app_config.dart`(주석) · `lib/l10n/app_en.arb` · `app_ko.arb` · `app_ja.arb` · `lib/l10n/generated/` · `tool/setup/steps/identity_step.dart` · 홈 공지 golden 2장(`test/features/home/goldens/`) · `test/tool/setup/` 의 위저드 시험 파일 등 시험이고, ARB 는 위 「사용자 조치」 를 본다.
- 설정 위저드 「앱 정체성」 이 기본 이름을 바꿀 때(처음 실행 · 표시 이름 다시 쓰기 · 다시 실행의 영어 `appTitle` 맞추기) 옛 기본 이름과 같은 다른 언어 `appTitle` 도 새 기본 이름으로 함께 바꾼다. `lib/l10n/app_en.arb` 의 `@appTitle` 설명은 위저드가 영어 아닌 언어마다 이 키를 쓰고 기본 이름 그대로인 언어는 같은 값을 둔다는 뜻으로 바뀌고, `lib/l10n/generated/app_localizations.dart` 가 함께 바뀐다. 바뀐 파일은 `tool/setup/steps/identity_step.dart` · `lib/l10n/app_en.arb` · `lib/l10n/generated/` · 시험이고, ARB 는 위 「사용자 조치」 의 영어 `appTitle` 맞추기를 그대로 본다(설명 줄은 자동 병합된다).

### Fixed

- 재인증 성공 뒤 계정 화면으로 돌아오는 golden 시험과 계정 정보 화면 golden 시험이 시험을 돌리는 컴퓨터의 시간대와 상관없이 통과한다. 두 시험이 가입일을 UTC 시각으로 줘 계정 화면이 그 컴퓨터의 시간대로 날짜를 그리는 바람에, 시간대가 UTC 보다 서쪽(예: 미국 서부 `America/Los_Angeles`)이거나 UTC+12 이상(예: 뉴질랜드 `Pacific/Auckland`)이면 「가입일」 날짜가 하루 어긋나 이 시험들이 실패하던 문제를 고친다. 바뀐 파일은 `test/features/auth/presentation/auth_surfaces_golden_test.dart` · `test/features/settings/presentation/account_screen_golden_test.dart` 이고, 그 파일들을 고치지 않았다면 merge 로 끝난다.

## [1.0.0-rc.8] - 2026-11-03

### 사용자 조치

- 킷 테마(`AppTheme`)로 화면을 그리는 golden 시험을 직접 만든 저장소는 merge 뒤 `fvm flutter test --update-goldens <그 시험 파일>` 로 golden 을 다시 만든다. 테마 글꼴이 Pretendard JP 로 바뀌어 글자 모양이 달라진다. 킷 하네스의 `loadGoldenFonts()`(`test/features/settings/presentation/settings_golden_harness.dart`)를 쓰는 시험은 앱 글꼴도 함께 올라가므로 다시 만들기만 하면 된다. 글꼴을 직접 올리는 시험은 `setUpAll` 에서 `await loadAppFont();`(`test/helpers/app_font.dart`)도 부른다 — flutter_tester 는 `pubspec.yaml` 의 글꼴을 스스로 올리지 않아, 부르지 않으면 글자가 네모 상자로 그려진다. 직접 만든 golden 시험이 없으면 할 일이 없다.

### Changed

- 앱 전체 글자(한글 · 가나 · 한자 · 영문)를 킷이 싣는 Pretendard JP 글꼴로 그린다. 기기 대체 글꼴은 기기와 앱 언어마다 달라, 앱 언어를 일본어로 두면 일부 Android 기기에서 한글이 명조로 그려지는 등 글꼴이 섞이던 문제를 고친다. 앱 크기가 약 13.1MB(압축 약 6.9MB) 늘어나고, 소셜 로그인 버튼 라벨은 그대로 기기 기본 글꼴이다. 바뀐 파일은 `assets/fonts/pretendard-jp/` · `pubspec.yaml` · `lib/core/theme/app_theme.dart` · `LICENSE` · `test/helpers/app_font.dart` · 화면 golden 하네스 두 파일(`test/features/settings/presentation/settings_golden_harness.dart` · `test/features/auth/presentation/auth_surfaces_golden_test.dart`) · 화면 golden 이다. 직접 만든 golden 시험이 있으면 위 「사용자 조치」 를 본다. 글꼴을 바꾸거나 빼려면 `docs/guide.md` 「디자인 토큰 바꾸기」 의 「6. 앱 글꼴 바꾸기 · 빼기」 를 따른다.

## [1.0.0-rc.7] - 2026-11-03

### Fixed

- 설정 위저드 「Naver 로그인」 단계가 밑줄(`_`)이 든 Client ID · Client Secret 을 받는다. 콘솔에서 복사한 값인데 `형식이 맞지 않습니다` 가 세 번 나오고 위저드가 멈추던 문제를 고친다. 바뀐 파일은 `tool/setup/providers/key_formats.dart` · `test/tool/setup/` 의 위저드 시험 파일이고, 그 파일들을 고치지 않았다면 merge 로 끝난다.
- 설정 위저드 「Kakao 로그인」 · 「Naver 로그인」 단계의 할 일 줄과 `docs/setup.md` · `docs/guide.md` 의 안내가 이메일과 함께 이름 · 프로필 사진을 받는 설정을 적는다 — Kakao 는 「닉네임」 · 「프로필 사진」 동의항목을 [선택 동의] 로, Naver 는 「별명」 · 「프로필 사진」 을 추가 제공 항목으로 켠다. 킷은 이 값을 계정 이름과 계정 사진으로 보이는데 안내에 빠져 있어, 안내대로 설정한 앱은 계정 정보 화면의 「이름」 행이 「-」 로 보이고 Naver 는 프로필 사진도 오지 않던 문제를 고친다. 이미 콘솔을 설정한 앱은 그대로 동작하고, 이 항목을 켜야 이름과 사진이 온다. 바뀐 파일은 `tool/setup/steps/kakao_step.dart` · `tool/setup/steps/naver_step.dart` · `test/tool/setup/` 의 위저드 시험 파일 · `docs/setup.md` · `docs/guide.md` 이고, 그 파일들을 고치지 않았다면 merge 로 끝난다.
- `docs/guide.md` 「사용자 소유 표면」 표가 `pubspec.yaml` 의 `flutter:` 아래 `assets` · `fonts` · `config` 도 사용자가 바꾸는 자리로 적는다. 표에 없어 앱 자산이나 글꼴을 더한 일이 표 밖 수정으로 읽히던 문제를 고친다. 같은 자리에 킷과 사용자가 서로 다른 항목을 더해 충돌하면 양쪽 줄을 모두 남기라고도 적는다 — 「같은 줄은 내 값」 대로 풀면 킷 쪽 줄이 사라져 그 자산이 빌드에서 빠진다. 바뀐 파일은 `docs/guide.md` 이고 merge 로 끝난다.
- Cloud Functions 배포 스크립트 시험(`functions/test/deploy_functions_script.test.ts`)이 배포 묶음 수를 함수 개수로 계산해 확인한다. 스크립트는 함수를 10개씩 나눠 배포하는데 시험이 1묶음으로 고정돼 있어, `scripts/functions_manifest.json` 의 `common` 에 함수를 더해 배포할 함수가 10개를 넘으면 이 시험이 실패하던 문제를 고친다. 바뀐 파일은 그 시험 파일 · `docs/guide.md` 이고, 그 파일들을 고치지 않았다면 merge 로 끝난다.
- Android 에서 LINE 로그인 「허용」 뒤 앱 화면으로 바로 돌아온다. LINE 앱이 최근 앱에 떠 있으면 LINE 메인 화면이 앞에 남아 사용자가 직접 앱으로 돌아가야 했고, LINE 앱이 없어 웹으로 로그인하면 브라우저 탭이 앱 위에 남아 탭을 직접 닫아야 로그인이 끝나던 문제를 고친다 — LINE SDK 의 콜백 화면이 앱과 다른 작업(task)에 열려, 기다리던 앱의 로그인 화면이 앞으로 오지 못했다. 이제 앱의 `LineAuthCallbackActivity` 가 콜백을 받아 앱 작업의 로그인 화면으로 결과를 바로 넘기고, 그 위의 브라우저 탭도 함께 닫힌다. 바뀐 파일은 `android/app/src/main/kotlin/` 아래 앱 패키지 디렉터리의 `MainActivity.kt` · `android/app/src/main/AndroidManifest.xml` · `android/app/build.gradle.kts` · 새 시험 파일 `test/infrastructure/line_auth_task_return_contract_test.dart` 이고, 그 파일들을 고치지 않았다면 merge 로 끝난다. 앱 패키지 경로를 바꾼 저장소에서도 git 이 옮긴 `MainActivity.kt` 로 자동 병합한다.

## [1.0.0-rc.6] - 2026-10-28

### Fixed

- 설정 위저드 시험 `test/tool/setup/identity_step_test.dart` 가 저장소의 stg 자리표시 `android/app/src/stg/google-services.json` 을 복사하지 않고 시험 안에서 만든다. 위저드로 앱 ID 를 바꾼 저장소에서도 이 시험이 통과한다. 바뀐 파일은 그 시험 파일 하나이고 merge 로 끝난다.
- 온보딩 화면 시험(`test/features/onboarding/onboarding_screen_test.dart`)이 마지막 슬라이드의 약관 체크박스를 누르기 전에 그 체크박스를 화면 안으로 스크롤한다. 3장 제목 · 본문(`lib/l10n/app_*.arb` 의 `onboardingSlide3Title` · `onboardingSlide3Body`)을 킷 문구보다 길게 바꾼 저장소에서도 이 시험이 통과한다 — 1.0.0-rc.5 의 온보딩 화면 시험 항목에 적은 「이 시험은 고치지 않아도 된다」 는 3장 문구를 길게 바꾼 경우에는 맞지 않았다. 바뀐 파일은 그 시험 파일 하나이고, 그 파일을 고치지 않았다면 merge 로 끝난다.
- 설정 화면 시험(`test/features/settings/presentation/settings_screen_test.dart`)이 설정 목록 전체를 세로로 긴 시험 화면에 그리거나 알림 섹션까지 스크롤한 뒤 확인하고, 약관 상세 화면 시험(`test/features/terms/terms_detail_screen_test.dart`)이 본문 문구를 다국어 문구(`AppLocalizations`)에서 읽는다. 설정 화면(`lib/features/settings/presentation/settings_screen.dart`)에 섹션을 하나 더 넣거나 `lib/l10n/app_*.arb` 의 약관 본문(`termsDetailPlaceholder`)을 바꾼 저장소에서도 이 시험들이 통과한다. 바뀐 파일은 그 시험 파일 둘이고, 두 파일을 고치지 않았다면 merge 로 끝난다.
- 설정 위저드 「Cloud Functions 배포」 단계가 공개 호출(`allUsers` 의 `roles/run.invoker`)을 앱이 부르는 함수(`onCall` · `onRequest`)에만 확인하고 붙이고, Auth · Firestore · 스케줄 같은 백그라운드 함수는 배포됐는지만 본다. `scripts/functions_manifest.json` 의 `common` 에 백그라운드 함수를 더한 저장소에서 1세대 함수면 이 단계가 늘 실패하고 2세대 함수면 앱이 부르지 않는 함수에 공개 호출이 붙던 문제와, 빌드가 실패해 상태가 `ACTIVE` 가 아닌 함수를 「다시 시도」 가 다시 배포하지 않아 같은 자리에서 멈추던 문제를 고친다. 바뀐 파일은 `tool/setup/steps/functions_step.dart` · `test/tool/setup/` 의 위저드 시험 파일 · `docs/setup.md` · `docs/guide.md` 이고, 그 파일들을 고치지 않았다면 merge 로 끝난다.
- 조직(Google Workspace) 계정으로 만든 프로젝트에서 「Cloud Functions 배포」 단계가 함수 빌드 계정(기본 Compute 서비스 계정)에 역할이 없어 빌드가 실패한 것을 알아보고 원인과 역할을 붙이는 명령을 보인다. 공개 호출이 조직 정책에 막혔을 때의 안내에는 조직 정책 관리자가 이 프로젝트에만 예외를 두는 명령이 더해진다. 위저드는 프로젝트 역할과 조직 정책을 바꾸지 않고, 절차는 `docs/setup.md` 의 「조직 계정 프로젝트에서 함수 배포가 막히면」 에 있다. 바뀐 파일은 `tool/setup/steps/functions_step.dart` · `test/tool/setup/` 의 시험 파일과 시험 자료 · `docs/setup.md` 이고, 그 파일들을 고치지 않았다면 merge 로 끝난다.
- 설정 위저드 「앱 정체성」 단계에서 정한 표시 이름이 홈 화면 런처 이름이 된다 — Android 는 `config/<flavor>.json` 의 `appName` 을, iOS 는 `ios/Flutter/<flavor>.xcconfig` 의 `DISPLAY_NAME` 을 쓴다. 위저드에 넣은 이름과 상관없이 Android 는 `flutter_starter_kit`, iOS 는 `Flutter Starter Kit` 로 보이던 문제를 고친다. `--dart-define-from-file` 없이 빌드한 Android 앱의 런처 이름은 `flutter_starter_kit` 이다. 바뀐 파일은 `ios/Runner/Info.plist` · `android/app/src/main/AndroidManifest.xml` · `android/app/build.gradle.kts` · `test/infrastructure/launcher_label_contract_test.dart` · `docs/setup.md` 이고, 그 파일들을 고치지 않았다면 merge 로 끝난다.
- `ios/Flutter/<flavor>.example.xcconfig` 의 `DISPLAY_NAME` 이 `config/<flavor>.example.json` 의 `appName` 과 같다 — dev `StarterKit Dev` · stg `StarterKit Stg` · prod `StarterKit` 이다. 설정 위저드 「앱 정체성」 단계를 거치기 전에 빌드한 앱이 Android 홈 화면에는 `StarterKit Dev`, iOS 홈 화면에는 `FSK Dev`(stg 는 `FSK Stg`, prod 는 `Flutter Starter Kit`)로 보이던 문제를 고친다. 이미 만든 `ios/Flutter/<flavor>.xcconfig` 는 merge 로 바뀌지 않고, 위저드 「앱 정체성」 단계가 표시 이름을 정하면 두 파일에 같은 값이 들어간다. 바뀐 파일은 `ios/Flutter/dev.example.xcconfig` · `ios/Flutter/stg.example.xcconfig` · `ios/Flutter/prod.example.xcconfig` · `test/infrastructure/launcher_label_contract_test.dart` · `test/tool/setup/config_files_test.dart` · `test/tool/setup/identity_step_test.dart` · `test/bin/rename_test.dart` 이고, 그 파일들을 고치지 않았다면 merge 로 끝난다.

## [1.0.0-rc.5] - 2026-10-27

### Fixed

- 킷 유지보수 문서와 같은 경로에 자기 작업 문서를 둔 저장소에서 킷 유지보수용 시험(문서 금지 패턴 · 문서 꼴 · 문서와 코드 대조 등)이 켜져 내 문서 때문에 실패하던 문제를 고친다. 이 시험들은 킷 저장소에만 있는 발행 규칙 파일이 있을 때만 돌고, 킷을 받은 저장소에서는 늘 건너뛴다(테스트 결과의 `~N`). 바뀐 파일은 `test/helpers/planning_docs.dart` 와 그 헬퍼를 쓰는 시험 파일이다.
- 로그인 · 가입 화면과 로그인 안내 시트의 다국어 문구를 원문 그대로 고정하는 시험(`test/l10n/email_relegation_arb_verbatim_test.dart`)이 킷 저장소에서만 돈다. `lib/l10n/app_*.arb` 의 그 문구를 바꾼 저장소에서는 이 시험이 실패하지 않고 건너뛴다.
- 온보딩 화면 시험(`test/features/onboarding/onboarding_screen_test.dart`)이 슬라이드 1 · 2 의 제목 · 본문을 다국어 문구(`AppLocalizations`)에서 읽고 슬라이드 아이콘을 화면에서 읽는다. `lib/l10n/app_*.arb` 의 온보딩 문구나 `lib/features/onboarding/presentation/onboarding_screen.dart` 의 슬라이드 아이콘을 바꿔도 이 시험은 고치지 않아도 된다.

## [1.0.0-rc.4] - 2026-10-25

### 사용자 조치

- merge 뒤 `fvm flutter pub get` 을 실행한다. woody_lints 2.0.0 이 새 규칙을 켜므로, 킷이 고치지 않은 내 코드에 info 진단이 생겨 `fvm flutter analyze` 가 실패할 수 있다. `fvm dart fix --apply` 로 고칠 수 있는 것을 고치고 나머지는 손으로 고친다. 규칙을 끄려면 `analysis_options.yaml` 의 `linter: rules:` 에 `<규칙>: false` 를 적는다. 내 무시 주석에는 바로 윗줄에 이유 주석이 있어야 한다(`document_ignores`) — [정적 분석 — woody_lints · riverpod_lint](docs/guide.md#정적-분석--woody_lints--riverpod_lint).
- `pubspec.yaml` 의 `dependencies` · `dev_dependencies` 가 이름 순으로 바뀐다. 의존성을 더하거나 고친 저장소는 이 두 블록에서 충돌한다 — 킷의 순서를 받고 내 항목을 이름 순 자리에 다시 넣은 뒤 `fvm flutter pub get` 을 한다. `name` · `description` · `version` 줄은 내 값 그대로 둔다.
- 직접 하는 일 문서(`docs/guide.md`) 「킷 업데이트 반영」 사용자 소유 표면 표에서 이 판이 고치는 파일과 조치: 9행 `ios/Runner.xcodeproj/project.pbxproj`(Crashlytics 업로드 빌드 스크립트 안 주석의 문서 참조 한 곳 — 번들 ID 줄은 그대로라 대개 자동 병합된다) · 10행 `config/*.example.json` · `ios/Flutter/*.example.xcconfig`(고치지 않았다면 충돌 없음 — 새 키 `appCheckDebugToken` 은 아래 Added 항목대로 내 config 에 채우고, xcconfig 예시는 주석만 바뀐다) · 12 · 13행 `pubspec.yaml` · `pubspec.lock`(위 항목대로 · lock 이 충돌하면 표의 조치대로 킷 판을 받고 `fvm flutter pub get`) · 19행 `lib/core/router/app_router.dart`(import 순서만 — 충돌은 직접 합친다) · 20행 `lib/features/demo/` · `test/features/demo/`(데모를 지웠다면 규칙 1 의 `git rm` · 「데모를 지웠다면」 규칙 3) · 데모를 지우며 고친 테스트 `test/features/home/home_listener_source_guard_test.dart` · `test/helpers/route_tree.dart`(지운 T-171-HOME-15 · `buildRoutesWithoutNamed` 자리의 줄을 킷이 고쳐 `CONFLICT (content)` 가 난다 — 충돌 블록마다 `<<<<<<<` 와 `=======` 사이의 내 쪽(지운 상태)만 남기고 표시 줄 셋과 킷 쪽 줄을 지운 뒤 `git add`) · 22행 `lib/features/notifications/data/local_notifications_service.dart`(알림 id 를 고르는 함수의 한 줄 — `_kNotificationColor` 줄은 그대로라 대개 자동 병합되고, 겹치면 내 값) · 23행 `ios/Runner/Info.plist` · 24행 `android/app/src/main/AndroidManifest.xml` · 28행 `ios/Runner/Runner.entitlements`(세 파일 모두 XML 주석 한 줄만 바뀐다 — 충돌하면 그 주석 줄은 내 파일 그대로 둔다) · 26행 `lib/core/config/app_config.dart`(새 config 키 상수와 주석 — `defaultFunctionsRegion` 줄은 그대로라 대개 자동 병합된다) · 29행 `README.md`(내 앱 소개로 바꿨다면 충돌한다 — 표의 조치대로 내 값) · 30행 `.gitignore`(`/.setup/` 줄과 주석 — 대개 자동 병합된다) · 32행 `setup.sh` · `bin/setup.dart` · `tool/setup/` · `CONTRIBUTING.md` · `.github/`(킷 전용 · 고치지 않았다면 충돌 없음).

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

[Unreleased]: https://github.com/woodkill/flutter-firebase-starter-kit/compare/v1.0.0-rc.10...HEAD
[1.0.0-rc.10]: https://github.com/woodkill/flutter-firebase-starter-kit/releases/tag/v1.0.0-rc.10
[1.0.0-rc.9]: https://github.com/woodkill/flutter-firebase-starter-kit/releases/tag/v1.0.0-rc.9
[1.0.0-rc.8]: https://github.com/woodkill/flutter-firebase-starter-kit/releases/tag/v1.0.0-rc.8
[1.0.0-rc.7]: https://github.com/woodkill/flutter-firebase-starter-kit/releases/tag/v1.0.0-rc.7
[1.0.0-rc.6]: https://github.com/woodkill/flutter-firebase-starter-kit/releases/tag/v1.0.0-rc.6
[1.0.0-rc.5]: https://github.com/woodkill/flutter-firebase-starter-kit/releases/tag/v1.0.0-rc.5
[1.0.0-rc.4]: https://github.com/woodkill/flutter-firebase-starter-kit/releases/tag/v1.0.0-rc.4
[1.0.0-rc.3]: https://github.com/woodkill/flutter-firebase-starter-kit/releases/tag/v1.0.0-rc.3
[1.0.0-rc.2]: https://github.com/woodkill/flutter-firebase-starter-kit/releases/tag/v1.0.0-rc.2
[1.0.0-rc.1]: https://github.com/woodkill/flutter-firebase-starter-kit/releases/tag/v1.0.0-rc.1
