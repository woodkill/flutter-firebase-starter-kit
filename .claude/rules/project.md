# Flutter + Firebase Starter Kit — 프로젝트 규칙

이 파일은 경로 조건(`paths:`)이 없어 Claude Code 가 항상 읽는다 — 공개본에도 실린다.

## Project

**Flutter + Firebase Starter Kit**

Flutter + Firebase 기반 앱 프로젝트를 위한 개인용 Starter Kit. 새 프로젝트를 시작할 때 반복되는 인증, 다국어, Firebase 설정, 디자인 시스템 등의 보일러플레이트를 제거하고, 동시에 Feature-First Architecture와 코딩 규칙을 프로젝트 시작부터 강제하는 템플릿.

**Core Value:** 빠른 프로젝트 시작과 모범 사례 강제를 동등하게 달성 — clone 후 최소 설정만으로 비즈니스 로직에 즉시 집중할 수 있으면서, 아키텍처와 코드 품질 기준이 내장된 구조.

### Constraints

- **Tech Stack**: Flutter (FVM) + Riverpod + go_router + Freezed — PRD 및 기존 설정에 의해 고정
- **Mobile Only**: 280dp~674dp 반응형, 웹/데스크톱 미지원
- **Firebase**: Authentication, Firestore, Crashlytics, Analytics, FCM, Remote Config, Cloud Storage, Cloud Functions 사용
- **Flavor**: dev / stg / prod 3개 환경, `--dart-define-from-file` 방식
- **FVM 필수**: 시스템 Flutter 직접 사용 금지, 항상 `fvm flutter` / `fvm dart`
- **코드 생성 파일 미커밋**: `*.g.dart`, `*.freezed.dart` 등은 `.gitignore`
- **flutter_hooks**: 사용하지 않음

## Alternatives Considered
| Category | Recommended | Alternative | Why Not |
|----------|-------------|-------------|---------|
| Routing | go_router | auto_route | 코드 생성 추가 부하, PROJECT.md에 go_router 명시 |
| Routing | go_router | Navigator 2.0 직접 | 보일러플레이트 과다, flutter.md에 금지 명시 |
| State Mgmt | Riverpod (generator) | Bloc/Cubit | 이미 locked, Riverpod이 코드 생성 + 컴파일 타임 안전성 우수 |
| State Mgmt | Riverpod (generator) | GetX | 아키텍처 강제력 부족, 테스트 어려움, 안티패턴 유발 |
| HTTP | dio | http | 인터셉터/로깅 직접 구현 필요 |
| HTTP | cloud_functions (callable) | REST API + dio | Firebase callable이 인증 자동 처리, 보안 우수 |
| l10n | flutter_localizations + intl | easy_localization | 공식 파이프라인 충분, 서드파티 호환성 위험 |
| Test Mock | mocktail | mockito | 코드 생성 불필요, Starter Kit 수준에서 충분 |
| Splash | flutter_native_splash | 직접 구현 | YAML 설정만으로 Android/iOS 네이티브 스플래시 생성, 시간 절약 |
| Theme | ThemeExtension 직접 | flex_color_scheme | Starter Kit는 완전한 제어 + 학습 목적, 추상화 레이어 불필요 |
| Auth UI | 직접 구현 | firebase_ui_auth | 커스터마이징 제한, 디자인 시스템 충돌 |
| Storage | shared_preferences | hive | 간단한 키-값 저장에 hive는 과도, shared_preferences로 충분 |
| Image | cached_network_image | 직접 구현 | 캐시 전략, 에러 핸들링 등 검증된 구현 재사용 |
