---
paths:
  - "**/*.dart"
---

# Dart Format 규율

`.fvmrc` 가 고정한 Dart 3.11.5 tall style 포매터가 진실원이다. 아래 3개 규칙은
포맷 drift 가 대량 누적되는 것을 막기 위한 것이며, 각 규칙 뒤의 *왜* 는 그 규칙이
없어서 실제로 벌어진 일을 가리킨다.

## 1. 커밋 전 format 의무

수정한 dart 파일은 스테이징 **전에** 반드시 포매터를 통과시킨다.

```bash
fvm dart format <수정한 파일…>
```

- 시스템 `dart` 직접 호출 금지 — 항상 `fvm dart` (SDK 버전이 달라지면 포맷 결과도 달라진다).
- 생성 파일(`*.g.dart`, `*.freezed.dart`)은 gitignore 대상이므로 대상 밖이다.

**왜:** quick `260424-uzl`(2026-04-25) sweep 이후 executor 들이 커밋 전 format 을
돌리지 않아, quick `260909-mwh` 시점에 **91개 파일**(4512+/4970-) 의 drift 가
누적됐다. 이 규칙 하나면 91건 전부가 발생하지 않았다.

## 2. 게이트 명령에 format 검사 포함

phase / post-merge / hotfix 게이트에 아래를 `analyze`·`test` 와 **동급**으로 포함한다.

```bash
fvm dart format --output=none --set-exit-if-changed lib test
```

- exit 0 = drift 없음. non-zero 면 게이트 FAIL 로 취급하고 그 자리에서 해소한다.
- `scripts/git-hooks/pre-commit` 은 `check_phase_refs.sh` 만 실행하고 format 은
  검사하지 않는다 — hook 활성화가 이 규칙을 대체하지 못한다.

**왜:** drift 가 게이트에서 걸리지 않으면 검출 시점이 다음 sweep 까지 밀리고,
그 사이 변경량에 비례해 sweep commit 이 비대해져 리뷰 불가능한 diff 가 된다.

## 3. 소스를 문자열로 읽는 테스트는 whitespace-insensitive 매칭

`readAsStringSync` + `contains` 로 소스 텍스트를 검사하는 테스트는 하드코딩 indent
대신 `RegExp` + `\s*` 로 공백·줄바꿈을 흡수한다.

```dart
// 나쁨 — format 이 중첩 깊이를 바꾸면 indent 가 변해 깨진다
expect(source.contains('A =\n          B'), isTrue);

// 좋음 — 공백·줄바꿈 무관
expect(RegExp(r'A\s*=\s*B').hasMatch(source), isTrue);
```

- 가능하면 애초에 indent 가 포함되지 않는 **단일 라인** 단위로 매칭을 자른다.

**왜:** `260424-uzl` 의 format 이 `lib/core/bootstrap.dart` 의 indent 를 10-space →
14-space 로 바꾸자 `bootstrap_crashlytics_test.dart` Test 2 가 깨졌고, 다음 날
quick `260425-mti` 가 사후 수습해야 했다. 포매터 출력이 진실원이고 취약한 쪽은
테스트이므로, 수리는 **항상 테스트 matcher 쪽**이다 — 통과시키려고 포맷된 소스를
손으로 되돌리지 않는다.
