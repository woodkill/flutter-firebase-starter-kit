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

## 테스트 분류와 바꾸거나 지울 때

| 분류 | 디렉터리 | 무엇을 지키는가 | 기능을 바꾸거나 지울 때 |
|---|---|---|---|
| ① 앱 코드 테스트 | `core` · `features` · `shared` · `l10n` | `lib` 코드의 동작 · 화면 · 다국어 문구 | `lib` 파일을 바꾸면 같은 경로의 테스트를 함께 고치고, 지우면 함께 지운다. 화면이 바뀌어 golden 이 실패하면 「golden 갱신」 절차를 따른다. |
| ② 설정 · 빌드 계약 테스트 | `infrastructure` · `ios` · `release` · `bin` | 설정 파일 · 빌드 스크립트 · 공개 문서에 꼭 있어야 할 값 | 설정을 일부러 바꿨다면 실패 메시지가 가리키는 기대값을 새 값으로 고친다. 그 설정을 더는 쓰지 않으면 해당 테스트도 지운다. |
| ③ 매뉴얼 대조 테스트 | 여러 디렉터리 — `docs/manual.md` 를 읽는 테스트 | 매뉴얼의 명령 · 표가 실제 파일과 같은지 | 매뉴얼 절을 고치거나 지우면 함께 고친다. 실패하면 매뉴얼 문장과 실제 파일 중 틀린 쪽을 고친다. |
| ④ 유지보수자 전용 | 여러 디렉터리 — `skipUnlessPlanningDocsExist` 를 쓰는 테스트 | 킷 유지보수 문서와 코드의 일치 | 킷을 받은 저장소에는 그 문서가 없어 늘 건너뛴다. 테스트 결과의 `~N`(건너뛴 수)은 정상이다. 그대로 둔다. |

## 이름 짓기

- 테스트 파일은 시험하는 `lib` 파일과 같은 경로에 두고 이름을 `<원본>_test.dart` 로 한다.
- 한 원본의 테스트를 주제별로 나누면 `<원본>_<주제>_test.dart` 로 한다
  (예: `test/features/auth/data/auth_repository_reauth_test.dart`).
- golden 테스트는 `<원본>_golden_test.dart` 로 하고, 기준 이미지는 같은 디렉터리의
  `goldens/` 에 둔다.
- 예제 디렉터리의 파일은 `<원본>_example_test.dart` 로 한다 — `lib` 와 같은 경로 규칙의
  예외다.
- 테스트 이름은 「상황 → 결과」 를 한 문장으로 쓴다
  (예: 「잘못된 비밀번호면 상태가 AsyncError 이고 오류는 InvalidCredentials 다」).
- 기존 테스트 이름 앞의 `T-…` 표지는 킷 유지보수용이다. 새 테스트에는 붙이지 않아도 된다.

## 린트 기준

- 테스트 코드도 앱 코드와 같은 린트 규칙으로 검사한다. `fvm dart analyze` 결과 0 건이
  기준이다.
- 쓰지 않는 인자는 밑줄 하나 `_` 로 쓴다(`(_, _)`). `__` 처럼 밑줄을 겹쳐 쓰지 않는다.
- riverpod_lint 규칙 두 가지를 지킨다.
  - generator provider 를 override 하는 `ProviderScope` 는
    `await tester.pumpWidget(ProviderScope(...))` 처럼 pumpWidget 의 직접 인자로
    넘긴다. helper 가 `ProviderScope` 위젯을 반환하거나 다른 위젯으로 감싸면
    `scoped_providers_should_specify_dependencies` 진단이 난다 — helper 는
    `WidgetTester` 를 받아 직접 pump 한다.
  - fake Notifier 에 public 카운터 · 기록 필드 · getter 를 두지 않는다
    (`avoid_public_notifier_properties`). 호출 기록은 생성자로 받은 외부 recorder
    객체에 남기고, 테스트는 recorder 를 단언한다.

## 예제

- `test/examples/login_notifier_example_test.dart` — unit 테스트. `LoginNotifier` 가
  읽는 `authRepositoryProvider` 를 mocktail mock 으로 override 하고, 로그인 성공 ·
  실패에 따라 상태가 `AsyncData` · `AsyncError` 가 되는 것을 본다.
- `test/examples/not_found_screen_example_test.dart` — widget 테스트. 홈 경로와 404
  화면만 둔 `GoRouter` 로 `NotFoundScreen` 을 앱과 같은 테마 · 다국어 설정으로 그리고,
  다국어 문구로 「홈으로」 버튼을 찾아 누른 뒤 홈 경로로 이동했는지 본다.

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

## mock 과 헬퍼

새로 쓰는 테스트와 `AuthRepository` 를 만드는 테스트는 아래 규칙을 따른다. 그 밖의 기존
테스트에는 같은 외부 경계의 mock 을 파일마다 따로 선언한 것이 남아 있고, 그대로 둔다 —
새 테스트의 본보기로는 위 예제와 `test/helpers/auth_mocks.dart` 를 본다.

- mock 은 테스트 파일 안에 private 클래스로 둔다
  (예: `class _MockAuthRepository extends Mock implements AuthRepository {}`).
- 여러 파일이 같은 외부 경계(Firebase · 로그인 SDK 등)를 흉내 내면 `test/helpers/` 의 공용
  mock 을 쓴다.
- `AuthRepository` 를 만드는 테스트는 `test/helpers/auth_mocks.dart` 의
  `buildAuthRepository` 를 쓴다. 모든 인자가 이름 인자 · 선택이라 시험에 필요한 의존성만
  넘긴다. 넘긴 의존성만 바뀌고, 넘기지 않은 Firebase · 로그인 SDK 의존성은 호출마다 새
  공용 mock(`MockFirebaseAuth` · `MockGoogleSignIn` 등)이 채운다.

```dart
final mockAuth = MockFirebaseAuth();
final repository = buildAuthRepository(auth: mockAuth);
```

- 생성자의 선택 인자(`now` · `recordSignUpMethod` · `emailDeliveryMode` 등)도 같은 이름으로
  넘긴다.

`test/helpers/` 의 헬퍼:

- `test/helpers/auth_mocks.dart` — Firebase · 로그인 SDK 공용 mock 과 `buildAuthRepository`.
- `test/helpers/router_harness.dart` — 실제 앱 라우터로 앱 전체를 그리는 하네스
  (`pumpProductionApp`)와 라우트 표만 보는 컨테이너(`buildRouteTableContainer`).
- `test/helpers/route_tree.dart` — 하위 라우트까지 전체 경로로 `GoRoute` 를 찾는 헬퍼.
- `test/helpers/source_text.dart` — 소스 · 문서를 문자열로 읽어 세는 헬퍼와 사용자 문서
  금지 패턴(`kUserDocForbiddenPatternSource`).
- `test/helpers/planning_docs.dart` — 킷 유지보수 문서가 없는 저장소에서 테스트를 건너뛰게
  하는 `skipUnlessPlanningDocsExist`.
- `test/helpers/brand_button_text_scale.dart` — 큰 글자 · 좁은 화면에서 소셜 로그인 버튼
  라벨을 재는 헬퍼.

## golden 갱신

golden 테스트는 화면을 이미지로 그려 `goldens/` 의 기준 이미지와 비교한다. 실패하면:

1. 테스트 파일 옆 `failures/` 에 생기는 비교 이미지(`*_isolatedDiff.png` ·
   `*_maskedDiff.png`)를 눈으로 본다.
2. 바뀐 것이 의도한 변화일 때만, 실패한 테스트 파일 하나를 대상으로 기준 이미지를 다시
   만든다.

   ```
   fvm flutter test --update-goldens <실패한 golden 테스트 파일>
   ```

3. 전체 테스트를 다시 돌려 통과하는지 본다.
4. 다시 만든 기준 이미지는 코드 변경과 따로 커밋한다.

모든 테스트에 한꺼번에 `--update-goldens` 를 쓰지 않는다 — 진짜 회귀까지 기준 이미지로
덮어쓴다.

소셜 로그인 버튼의 iOS 변형 기준 이미지(`*_ios.png`)는 macOS 시스템 글꼴로 그린 것이라
글꼴 사용권 때문에 저장소에 없다. 이 테스트는 macOS 에서만 대조하고 다른 OS 에서는
건너뛴다. macOS 에서 처음 테스트를 돌리기 전에 내 Mac 에서 한 번 만든다.

```
fvm flutter test --update-goldens --plain-name '(iOS)' test/features/auth/presentation/_widgets/branded_social_button_golden_test.dart
```

iOS 변형 이미지는 git 으로 되돌릴 수 없으니, 다시 만들기 전에 기존 파일을 백업해 둔다.

## 커밋 전에 돌릴 검사

커밋하기 전에 저장소 루트에서 아래 네 명령을 차례로 돌린다. 넷 다 오류 없이 끝나야 한다.

```
fvm dart format --output=none --set-exit-if-changed lib test bin tool
fvm flutter analyze
fvm dart analyze
fvm flutter test
```

- 생성 코드(`*.g.dart` · `*.freezed.dart`)가 없으면(clone 직후 등) 먼저
  `fvm dart run build_runner build --delete-conflicting-outputs` 를 돌린다.
- macOS 에서는 iOS 변형 golden 이미지가 있어야 `fvm flutter test` 가 통과한다 — 없으면
  「golden 갱신」 의 iOS 명령으로 먼저 만든다.
- 첫 명령은 포맷이 어긋난 파일이 있으면 0 이 아닌 값으로 끝난다. `fvm dart format <파일>`
  로 고친 뒤 다시 돌린다.
- riverpod_lint 진단은 `fvm dart analyze` 에만 나온다. `fvm flutter analyze` 만 돌리면
  놓친다.

선택으로 git pre-commit hook(`scripts/git-hooks/pre-commit`)을 켤 수 있다. hook 은 가드 넷만
돌린다 — 실제 Firebase 키가 커밋되는 것을 막는 셋(FlutterFire 가 만든 Firebase 옵션 파일,
Android stg · prod `google-services.json` 의 실제 키, iOS `GoogleService-Info.plist` 의
실제 키)과 코드 주석의 문서 참조 검사다. format · analyze · test 는 돌리지 않으므로 위 네
명령은 hook 을 켜도 따로 돌린다. 켜는 법은 `docs/manual.md` 「Git Hooks 활성화 (선택)」 절에
있다.
