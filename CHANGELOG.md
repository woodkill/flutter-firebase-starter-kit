# Changelog

이 킷의 판별 변경 사항을 이 파일에 적습니다.
형식은 [Keep a Changelog](https://keepachangelog.com/ko/1.1.0/)를 따르고, 판 번호는 [Semantic Versioning](https://semver.org/lang/ko/)을 따릅니다.

**판 번호 규칙**

- merge 뒤 사용자가 손봐야 하는 판은 MAJOR 다 — 사용자 소유 표면 표에서 킷이 고칠 가능성이 `낮음` 인 파일의 변경 · 표의 「충돌 시 조치」 칸 밖의 손질이 필요한 변경 · 콘솔 재설정 · 데이터 마이그레이션. 그 판 절 맨 앞 `### 사용자 조치` 에 할 일과 충돌이 날 파일을 적는다. `### 사용자 조치` 가 없는 판은 merge 만으로 끝난다.
- 새 기능 · 새 로그인 수단을 더한 판은 MINOR 다.
- 수정만 담은 판은 PATCH 다.
- 정식 판 전에는 `1.0.0-rc.N` 처럼 rc 번호만 올린다.

사용자 소유 표면 표는 매뉴얼 [킷 업데이트 반영](docs/manual.md#킷-업데이트-반영) 절에 있습니다.

## [Unreleased]

### Added

- 인증 메일 · 비밀번호 재설정 메일을 킷이 보내는 `kit` 모드를 더한다. `config/<flavor>.json` 의 `emailDelivery` 로 고르고, 키가 없거나 비었거나 `firebase` 면 지금처럼 Firebase 가 보낸다. `kit` 은 내 발송 서비스(SMTP)와 Trigger Email 확장으로 보내고, 확장 값은 내가 만드는 `extensions/firestore-send-email.env.<your-project-id>` 에 적는다 — 매뉴얼 「인증 메일 발송 모드 켜고 끄기」 절.
- `kit` 모드의 인증 · 재설정 메일 템플릿을 한국어 · 영어 · 일본어로 제공한다. 메일 머리에 앱 이름(로고를 두면 로고)이 나오고 버튼은 `brandColor` 로 칠한다. 문구는 `functions/src/email/copy.json` 에서 고친다 — 매뉴얼 「인증 메일 발송 모드 켜고 끄기」 절.
- `kit` 모드 메일의 링크는 킷의 결과 페이지(인증 · 비밀번호 재설정)로 열린다 — 앱 이름 · 색 · 로고가 들어간다. `kit` 을 켜는 `bash scripts/deploy_email.sh <flavor> kit --apply` 가 결과 페이지를 Firebase Hosting 에 함께 배포하고, 로고는 `hosting/public/logo.png` 에 두면 페이지와 메일 머리에 함께 쓰인다. `firebase` 모드 메일의 링크는 지금처럼 Firebase 기본 페이지로 열린다. 새 파일을 merge 때 어떻게 다루는지는 「킷 업데이트 반영」 절의 사용자 소유 표면 표에 있다 — 매뉴얼 「인증 결과 페이지 바꾸기」 절.
- config 의 `brandColor` 키(`#RRGGBB`)가 앱 테마 · 결과 페이지 · 메일의 브랜드 색을 정한다. 비우거나 형식이 틀리면 `#673AB7` 로 동작하고, 바꾼 뒤에는 앱을 다시 빌드한다 — 매뉴얼 Initial Setup 절의 키 표.
- 앱이 보내는 인증 · 재설정 메일이 앱 언어(한국어 · 영어 · 일본어)로 온다. `firebase` 모드에서도 같다 — 매뉴얼 「인증 메일 발송 모드 켜고 끄기」 절.
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

[Unreleased]: https://github.com/woodkill/flutter-firebase-starter-kit/compare/v1.0.0-rc.1...HEAD
[1.0.0-rc.1]: https://github.com/woodkill/flutter-firebase-starter-kit/releases/tag/v1.0.0-rc.1
