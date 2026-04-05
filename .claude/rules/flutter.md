---
paths:
  - "**/*.dart"
---

# Dart/Flutter Coding Style

## Formatting
- `dart format` 기본 설정 준수 (줄 길이 80자)
- trailing comma 사용 (위젯 트리 가독성)
- import 순서: dart: → package: → relative, 각 그룹 사이 빈 줄
- relative import 사용 (같은 패키지 내)

## Naming
- 변수/함수/매개변수: camelCase
- 클래스/enum/typedef: PascalCase
- 상수: camelCase (`lowerCamelCase`, UPPER_SNAKE_CASE 아님)
- 파일명: snake_case (`my_widget.dart`)
- private: _single_leading_underscore
- bool 변수/getter: `is`, `has`, `should` 접두사 권장

## Dart Idioms
- `final` 기본 사용 — 재할당 필요 시에만 `var`
- `const` 생성자 적극 활용 (위젯, 값 객체)
- null safety 활용: `?.`, `??`, `?..`, `!`(최소한으로)
- `late` 사용 최소화 — 가능하면 nullable + null check
- collection literal 사용: `[]`, `{}`, `<String, int>{}`
- cascade notation (`..`) 활용
- `switch` expression 사용 (Dart 3.0+)
- pattern matching 활용 (Dart 3.0+)
- `sealed class` > abstract class (exhaustive switch용)
- extension method로 유틸리티 정리
- `typedef` > inline function type (복잡한 콜백)

## Type & Null Safety
- 타입 추론 가능해도 public API에는 명시적 타입 선언
- `dynamic` 사용 금지 — 필요 시 `Object?`
- `as` 캐스팅 최소화 — pattern matching 또는 `is` 체크
- non-nullable 기본 — `?` 는 진짜 null이 가능한 경우만

## Documentation
- 모든 public API에 doc comment (`///`) 작성
- 첫 줄: 한 문장 요약 (마침표로 끝)
- 길면 요약 + 빈 줄 + 상세
- `[]`로 다른 식별자 참조: `/// [MyWidget]을 참조`

## Structure
- 파일 당 하나의 public 클래스/위젯 권장
- part/part of 사용 금지 — 별도 파일로 분리
- barrel file (`export`) 남용 금지 — 필요한 곳에서 직접 import

## Error Handling
- `catch (e)` 보다 구체적 예외 타입 사용
- `rethrow` > `throw e` (스택 트레이스 보존)
- Result 패턴 또는 sealed class로 에러 모델링 권장

# Flutter Widget Guidelines

## Widget 구조
- StatelessWidget 우선 — 상태 필요 시 ConsumerWidget(Riverpod)
- 위젯 트리 깊이 줄이기 — 메서드 추출보다 별도 위젯 클래스로 분리
- `build()` 메서드는 가볍게 — 로직은 provider 또는 별도 클래스로
- `const` 생성자 적극 사용 (불필요한 리빌드 방지)

## Key 사용
- ListView/GridView 아이템에 `ValueKey` 필수
- 동적 위젯 교체 시 `Key` 명시

## Performance
- `const` 위젯으로 리빌드 범위 최소화
- 큰 리스트: `ListView.builder` / `GridView.builder` 사용
- 무거운 연산: `compute()` 또는 Isolate 사용
- 이미지: `cached_network_image` 사용

## Common UI Patterns
- 로딩: Shimmer 또는 CircularProgressIndicator (프로젝트 표준 따름)
- 에러: 재시도 버튼이 포함된 에러 위젯 사용
- 빈 상태: 빈 상태 전용 위젯 제공
- AsyncValue: `.when()` 사용, `.value!` 직접 접근 금지

# Project Structure

## Feature-First Architecture
```
lib/
├── core/              # 공통 유틸, 상수, 테마, 라우터, DI
├── features/
│   ├── auth/
│   │   ├── data/          # repository 구현, data source, DTO
│   │   ├── domain/        # entity, repository interface, use case
│   │   └── presentation/  # widget, provider
│   └── home/
└── shared/            # feature 간 공유 위젯, 모델
```
- 한 feature 안에서만 사용되는 provider/widget은 해당 feature 내에 배치
- feature 간 공유 필요 시 shared/ 또는 core/로 이동
- feature 간 직접 import 최소화 — core/ 또는 shared/를 통해 연결

## Routing
- go_router 사용 (Navigator 2.0 직접 사용 금지)
- 라우트 정의: `lib/core/router/`에 집중
- deep link 지원 고려

## Data Modeling
- 불변 모델: freezed 사용 (`@freezed` class)
- JSON 직렬화: json_serializable (`@JsonSerializable`)
- 모델 파일 위치: 해당 feature의 data/ 또는 domain/
- toJson/fromJson은 generated 코드 사용 — 수동 작성 금지

# Riverpod

## Provider 정의
- riverpod_generator (`@riverpod`) 사용 — 수동 Provider 선언 금지
- Provider 파일 위치: feature별 디렉토리에 배치

## Provider 종류 (generated)
- `@riverpod` 함수 → 자동으로 AutoDispose 적용
- `@Riverpod(keepAlive: true)` → 앱 생명주기 동안 유지할 때만
- class 기반 `@riverpod` → 상태 변경 메서드가 필요할 때

## 상태 관리 패턴
- UI 로직: Provider에 위임 — Widget에 비즈니스 로직 금지
- AsyncValue 패턴: `.when(data:, loading:, error:)` 사용
- ref.watch (build 내) / ref.listen (사이드 이펙트) / ref.read (이벤트 핸들러)
- ref.read는 build 내에서 사용 금지

## 네이밍
- Provider 함수명: 역할 기반 (`fetchUser`, `userList`, `authState`)
- generated provider 변수: 함수명 + `Provider` (자동 생성)

## 테스트
- `ProviderContainer`로 provider 단위 테스트
- `overrides`로 의존성 주입/목킹

# Flutter Runtime & Tooling (FVM)

## Runtime
- Flutter 버전 관리: FVM (시스템 Flutter 직접 사용 금지)
- 프로젝트 Flutter 버전: `.fvmrc` 파일로 고정
- Flutter 명령 실행: `fvm flutter <command>`
- Dart 명령 실행: `fvm dart <command>`

## 의존성 관리
- `pubspec.yaml`로 의존성 선언
- `pubspec.lock` 커밋 필수
- 의존성 추가: `fvm flutter pub add <package>`
- dev 의존성: `fvm flutter pub add --dev <package>`
- 동기화: `fvm flutter pub get`

## 코드 생성 (build_runner)
- Riverpod, Freezed, json_serializable 등 코드 생성 시:
  `fvm dart run build_runner build --delete-conflicting-outputs`
- 개발 중: `fvm dart run build_runner watch --delete-conflicting-outputs`
- 생성 파일(`*.g.dart`, `*.freezed.dart`, `*.gr.dart`, `*.gen.dart`)은 절대 직접 읽거나 수정 금지
- 생성 파일에 문제가 있으면 원본 소스를 수정 후 build_runner 재실행
- 생성 파일은 코드 리뷰/분석 대상에서 제외
- 생성 파일 커밋 여부: 프로젝트 정책 따름

## Linting
- 커스텀 lint 패키지: `woody_lints` (GitHub 비공개 패키지)
- dev 의존성 추가 (pubspec.yaml):
```yaml
  dev_dependencies:
    woody_lints:
      git:
        url: https://github.com/woodkill/woody_lints.git
        ref: main
```
- 프로젝트 `analysis_options.yaml`에서 `include: package:woody_lints/analysis_options.yaml`
- 프로젝트별 추가/제외 규칙은 `analysis_options.yaml`에서 오버라이드
- lint 규칙 자체를 수정하려면 `woody_lints` 패키지를 업데이트
- 검사: `fvm dart analyze`

## Testing
- 테스트 실행: `fvm flutter test`
- 커버리지: `fvm flutter test --coverage`
- 테스트 파일: `test/` 디렉토리, 원본과 동일 구조

## FlutterFire CLI
- `flutterfire` 명령을 직접 실행하지 않는다 — PATH에 `~/.pub-cache/bin`을 추가하지 않음
- FVM이 관리하는 Dart를 통해 실행: `fvm dart pub global run flutterfire_cli:flutterfire`
- 프로젝트에 alias가 등록되어 있음: `fff` = `fvm dart pub global run flutterfire_cli:flutterfire`
- FlutterFire configure 실행 시: `fff configure --project=<id> --out=<path> ...`
- FlutterFire CLI 설치/업데이트: `fvm dart pub global activate flutterfire_cli`

## 금지 사항
- 시스템 Flutter 직접 사용 금지 — 항상 `fvm flutter`
- `dart pub` 직접 사용 금지 — 항상 `fvm dart`
- `flutterfire` 직접 실행 금지 — 항상 `fff` alias 사용 (FVM Dart 경유)
- `.fvm/` 디렉토리 커밋 금지 (`.gitignore`에 추가)
