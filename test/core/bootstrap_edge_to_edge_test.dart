// 앱 시작이 Android 에서만, 실패를 다시 던지지 않는 자기 try 안에서, 스플래시
// 로고 미리 디코딩을 시작한 뒤 · 그 기다림보다 앞에서 edge-to-edge 를 켜는지
// 소스 순서로 고정한다. 실제 bootstrap 은 Firebase 없이 돌릴 수 없어 다른
// bootstrap 시험과 같은 소스 문자열 계약으로 본다 — 주석을 걷어 낸 뒤 공백과
// 줄바꿈에 무관한 정규식으로 맞춘다.

import 'package:flutter_test/flutter_test.dart';

import '../helpers/source_text.dart';

/// 미리 디코딩을 시작해 그 Future 를 변수에 담는 꼴 — 그룹 1 이 변수 이름이다.
final RegExp _startPattern = RegExp(
  r'WidgetsFlutterBinding\.ensureInitialized\(\);\s*'
  r'final\s+Future<void>\s+(\w+)\s*=\s*precacheSplashLogo\(\s*'
  r'timeout:\s*_kSplashLogoPrecacheTimeout\s*,?\s*\);',
);

/// Android 가드 · 자기 try · 켜는 호출 · `on Object catch` 를 한 덩어리로 잡는다.
final RegExp _guardedCall = RegExp(
  r'if\s*\(\s*defaultTargetPlatform\s*==\s*TargetPlatform\.android\s*\)\s*\{\s*'
  r'try\s*\{\s*'
  r'await\s+SystemChrome\.setEnabledSystemUIMode\(\s*'
  r'SystemUiMode\.edgeToEdge\s*,?\s*\)\s*;\s*'
  r'\}\s*on\s+Object\s+catch\s*\(',
);

/// 잡은 실패를 다시 던지는 꼴 — 가드 블록 안에 있으면 안 된다.
final RegExp _throwsAgain = RegExp(r'\b(?:rethrow|throw)\b');

/// [source] 의 [open] 자리 `{` 에서 짝이 맞는 `}` 까지(둘 다 포함)를 돌려준다.
///
/// 짝이 맞지 않으면 빈 문자열을 돌려준다 — 호출자가 「비어 있지 않음」 을 단언한다.
String _readBraceBlock(String source, int open) {
  var depth = 0;
  for (var i = open; i < source.length; i++) {
    final String ch = source[i];
    if (ch == '{') {
      depth++;
    } else if (ch == '}') {
      depth--;
      if (depth == 0) {
        return source.substring(open, i + 1);
      }
    }
  }
  return '';
}

void main() {
  group('bootstrap Android edge-to-edge 켜기', () {
    late String code;

    setUpAll(() {
      code = stripBlockComments(
        stripSlashComments(readTrackedFile('lib/core/bootstrap.dart')),
      );
    });

    test('T-30-E2E-03: Android 에서만 자기 try 안에서 한 번, 로고 미리 디코딩 '
        '시작 뒤 · 그 기다림 앞에서 켠다', () {
      expect(
        countOccurrences(code, 'setEnabledSystemUIMode('),
        1,
        reason: '켜는 호출은 한 곳',
      );
      final guarded = _guardedCall.allMatches(code).toList();
      expect(guarded, hasLength(1), reason: 'Android 가드 + 자기 try 안');
      final String guardBlock = _readBraceBlock(
        code,
        code.indexOf('{', guarded.single.start),
      );
      expect(guardBlock, isNotEmpty, reason: '가드 블록 중괄호 짝');
      expect(
        _throwsAgain.hasMatch(guardBlock),
        isFalse,
        reason: '실패를 다시 던지지 않는다 — runApp 까지 간다',
      );

      final starts = _startPattern.allMatches(code).toList();
      expect(starts, hasLength(1), reason: '미리 디코딩 시작');
      final String name = starts.single.group(1)!;
      final waits = RegExp('await\\s+$name\\s*;').allMatches(code).toList();
      expect(waits, hasLength(1), reason: '미리 디코딩 기다림');

      expect(
        guarded.single.start,
        greaterThan(starts.single.end),
        reason: '미리 디코딩 시작 뒤',
      );
      expect(
        guarded.single.end,
        lessThan(waits.single.start),
        reason: '미리 디코딩 기다림 앞',
      );
    });
  });
}
