// Phase 17.5 — see ROADMAP.md (D-18) — 앱 · 인증 결과 페이지 비밀번호 최소 길이 계약.
//
// 앱 비밀번호 입력(password_field.dart)의 `v.length < N` 과 결과 페이지 재설정
// 폼(hosting/public/state.mjs)의 `MIN_PASSWORD_LENGTH = N` 이 같은 값이어야 한다.
// 두 파일을 소스 텍스트로 읽어(주석 제거) 숫자를 비교한다 — 한쪽만 바꾸면
// 앱에서 되는 비밀번호가 페이지에서 거부되거나 그 반대가 된다. 길이 단위는
// 둘 다 UTF-16 code unit(Dart · JS `String.length`)이다.

import 'package:flutter_test/flutter_test.dart';

import '../../../../helpers/source_text.dart';

const String _appFieldPath =
    'lib/features/auth/presentation/_widgets/password_field.dart';
const String _pageStatePath = 'hosting/public/state.mjs';

/// [source] 에서 [pattern] 의 첫 그룹 숫자를 모두 모은다.
List<int> _collectNumbers(String source, RegExp pattern) => pattern
    .allMatches(source)
    .map((RegExpMatch match) => int.parse(match.group(1)!))
    .toList();

/// [path] 를 읽어 행 주석 · 블록 주석을 걷어낸 코드 텍스트를 돌려준다.
String _readCode(String path) =>
    stripBlockComments(stripSlashComments(readTrackedFile(path)));

void main() {
  test('T-175-PW-01: 앱 비밀번호 최소 길이 == 결과 페이지 MIN_PASSWORD_LENGTH == 8', () {
    final List<int> appValues = _collectNumbers(
      _readCode(_appFieldPath),
      RegExp(r'v\.length\s*<\s*(\d+)'),
    );
    final List<int> pageValues = _collectNumbers(
      _readCode(_pageStatePath),
      RegExp(r'MIN_PASSWORD_LENGTH\s*=\s*(\d+)'),
    );

    expect(appValues, hasLength(1), reason: '$_appFieldPath 의 길이 검사');
    expect(pageValues, hasLength(1), reason: '$_pageStatePath 의 상수 선언');
    expect(pageValues.single, appValues.single);
    expect(appValues.single, 8);
  });
}
