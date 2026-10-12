# 테스트 안내

`test/` 의 자동 테스트는 앱 코드의 동작, 설정 · 빌드 파일의 약속, 매뉴얼과 실제 파일의
일치를 지킨다. 이 문서는 테스트를 어디에 두고 어떻게 이름 짓는지, 기능을 바꾸거나 지울 때
테스트를 어떻게 다루는지, 커밋 전에 무엇을 돌리는지를 설명한다.

## 디렉터리 구조

```
test/
├── core/              # lib/core 와 같은 구조
├── features/          # lib/features 와 같은 구조
├── shared/            # lib/shared 와 같은 구조
├── l10n/              # 다국어 문구(ARB) 검사
├── helpers/           # 여러 테스트가 함께 쓰는 하네스 · mock · 헬퍼
├── examples/          # 복사해 쓰는 예제 테스트
├── infrastructure/    # Android 빌드 · Firebase · 스플래시 설정 계약
├── ios/               # iOS 프로젝트 설정 계약
├── release/           # 공개 문서 · 릴리스 도구 계약
├── bin/               # bin/ 의 명령줄 도구 테스트
└── widget_test.dart   # 앱이 홈 화면까지 뜨는지 보는 스모크 테스트
```

- `core` · `features` · `shared` 아래는 `lib` 와 같은 경로를 쓴다.
  `lib/features/auth/presentation/login_notifier.dart` 의 테스트는
  `test/features/auth/presentation/login_notifier_test.dart` 다.
- golden 테스트는 기준 이미지를 테스트 파일 옆 `goldens/` 디렉터리에 둔다.
- `test/examples/` 와 `test/helpers/` 는 `lib` 에 짝이 없는 디렉터리다 — `lib` 와 같은
  구조를 쓰는 규칙의 예외다.

## 예제

- `test/examples/login_notifier_example_test.dart` — unit 테스트. `LoginNotifier` 가
  읽는 `authRepositoryProvider` 를 mocktail mock 으로 override 하고, 로그인 성공 ·
  실패에 따라 상태가 `AsyncData` · `AsyncError` 가 되는 것을 본다.

예제는 킷의 실제 코드를 시험하므로 다른 테스트와 함께 항상 돌고 늘 통과한다. `package:`
import 만 쓰므로 어느 위치로 복사해도 그대로 돈다.

복사해 쓰는 법:

1. 예제 파일을 시험할 코드와 같은 구조의 위치로 복사한다. 예를 들어
   `lib/features/<기능>/presentation/<원본>.dart` 를 시험한다면
   `test/features/<기능>/presentation/` 아래로 복사한다.
2. 파일 이름을 `<원본>_test.dart` 꼴로 바꾼다.
3. import · mock · override 대상과 테스트 이름을 내 코드에 맞게 바꾼다.
4. 복사한 파일만 돌려 통과하는지 본다.

```
cp test/examples/login_notifier_example_test.dart test/features/<기능>/presentation/<원본>_test.dart
fvm flutter test test/features/<기능>/presentation/<원본>_test.dart
```

## 커밋 전에 돌릴 검사

커밋하기 전에 저장소 루트에서 아래 네 명령을 차례로 돌린다. 넷 다 오류 없이 끝나야 한다.

```
fvm dart format --output=none --set-exit-if-changed lib test bin
fvm flutter analyze
fvm dart analyze
fvm flutter test
```

- 생성 코드(`*.g.dart` · `*.freezed.dart`)가 없으면(clone 직후 등) 먼저
  `fvm dart run build_runner build --delete-conflicting-outputs` 를 돌린다.
- 첫 명령은 포맷이 어긋난 파일이 있으면 0 이 아닌 값으로 끝난다. `fvm dart format <파일>`
  로 고친 뒤 다시 돌린다.
- riverpod_lint 진단은 `fvm dart analyze` 에만 나온다. `fvm flutter analyze` 만 돌리면
  놓친다.
