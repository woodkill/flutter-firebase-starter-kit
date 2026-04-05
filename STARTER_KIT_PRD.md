# Flutter + Firebase Starter Kit PRD

## 목표

Flutter + Firebase를 기반으로 하는 앱 프로젝트를 위한 Starter Kit 제작

## 기술스택

- Flutter 3.4+, Dart 3.1+
- 상태관리: Riverpod (stable 최신)
- 라우팅: go_router
- 코딩 규칙: rules/flutter.md 참조

## Firebase 설정

- FlutterFire CLI + Flavor: dev / prod 기본, stg 추가가 용이한 구조
- 환경별 설정 주입: `--dart-define-from-file` 방식
- 사용 서비스:
    - 필수: Authentication, Cloud Firestore, Crashlytics, Analytics, FCM
    - 기본 포함: Remote Config, Cloud Storage, Cloud Functions

## 프로젝트 설정

- Package Name(Android), Bundle ID(iOS)를 쉽게 변경할 수 있도록 구성

## 앱 진입 플로우

- 앱 실행 → 스플래시 화면 → 인증 상태 확인 → 로그인 화면 또는 메인 화면
- 스플래시 화면: 앱 로고/브랜드 표시, 로고와 배경을 쉽게 커스터마이징 가능한 구조
    - 인증 상태 확인 등 백그라운드 초기화 진행 상태를 사용자에게 표시
    - 초기화가 빠르게 완료되더라도 설정된 최소 표시 시간 동안 스플래시 유지

## 인증

- Firebase Auth 네이티브: 이메일/비밀번호, Google, Apple, Facebook
- Custom Token 방식: Kakao, Naver, LINE, Yahoo! JAPAN, WeChat
    - Custom Token 발급을 위한 Cloud Functions 백엔드 포함
- 프로바이더 추가/제거가 용이한 구조
- 프로바이더 활성화/비활성화를 설정으로 제어
- 동일 이메일 기반 Account Linking 지원
- 회원탈퇴/로그아웃 기능
- 약관 동의 플로우 (개인정보 처리방침, 이용약관)
- 로케일에 따라 소셜 로그인 버튼 우선순위 설정 가능 (메인 2~3개 큰 버튼, 나머지 작은 버튼)
- 자동로그인: Firebase Auth 기본 세션 관리 사용
- 인증 완료 후 메인 화면(웰컴 메시지)으로 랜딩

## 디자인 시스템

- ThemeExtension 기반 디자인 토큰 (컬러, 타이포그래피, 간격 등)
- 라이트/다크 테마 기본 포함, 커스텀 테마 추가 용이한 구조
- 타이포그래피: Material 3 TextTheme 기본, ThemeExtension으로 커스텀 오버라이드 가능
- 반응형: 모바일 전용 (280dp~674dp, 폴더블 펼친 상태 포함)

## 다국어 (i18n/l10n)

- Flutter 공식 로컬라이제이션 (flutter_localizations + intl + ARB)
- 기본 언어: 영어(en)
- ARB 파일 추가만으로 새 언어 지원 가능한 구조
- 앱 내 언어 수동 전환 기능 (최초에는 기기 로케일 자동 선택)
- 날짜, 숫자, 통화는 intl 로케일별 포맷 사용

## 에러 핸들링

- 공통 Exception 클래스 계층 정의
- 예상치 못한 에러는 Crashlytics 자동 전송
- 사용자에게는 안내 메시지 표시

## 산출물

- Starter Kit 소스코드
- Starter Kit 사용 매뉴얼: 이 Starter Kit을 기반으로 실제 배포용 앱을 만들기 위한 단계별 가이드 (환경 설정, 커스터마이징, 빌드 및 배포 절차 포함)
