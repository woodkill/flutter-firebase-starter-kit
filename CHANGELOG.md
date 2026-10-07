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
