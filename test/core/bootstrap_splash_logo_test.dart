// 앱 시작이 스플래시 로고 미리 디코딩을 바인딩 초기화 바로 다음에 기다리지 않고
// 시작해 다른 초기화와 겹쳐 돌리고, runApp 바로 앞에서 기다리는지 소스 순서로
// 고정한다. 실제 bootstrap 은 Firebase 없이 돌릴 수 없어 다른 bootstrap 시험과
// 같은 소스 문자열 계약으로 본다 — 주석을 걷어 낸 뒤 공백과 줄바꿈에 무관한
// 정규식으로 맞춘다.

import 'package:flutter_test/flutter_test.dart';

import '../helpers/source_text.dart';

/// 미리 디코딩을 시작해 그 Future 를 변수에 담는 꼴 — 그룹 1 이 변수 이름이다.
final RegExp _startPattern = RegExp(
  r'WidgetsFlutterBinding\.ensureInitialized\(\);\s*'
  r'final\s+Future<void>\s+(\w+)\s*=\s*precacheSplashLogo\(\s*'
  r'timeout:\s*_kSplashLogoPrecacheTimeout\s*,?\s*\);',
);

/// 상한 시간 선언 — 초기화와 겹치므로 짧게 둔다.
final RegExp _timeoutDeclaration = RegExp(
  r'const\s+Duration\s+_kSplashLogoPrecacheTimeout\s*=\s*'
  r'Duration\(\s*milliseconds:\s*500\s*\);',
);

void main() {
  group('bootstrap 스플래시 로고 미리 디코딩 순서', () {
    late String code;

    setUpAll(() {
      code = stripBlockComments(
        stripSlashComments(readTrackedFile('lib/core/bootstrap.dart')),
      );
    });

    test('바인딩 초기화 바로 다음에 기다리지 않고 시작해 다른 초기화와 '
        '겹쳐 돈다', () {
      final starts = _startPattern.allMatches(code).toList();
      expect(starts, hasLength(1), reason: '바인딩 초기화 바로 다음 시작');
      expect(
        _timeoutDeclaration.allMatches(code),
        hasLength(1),
        reason: '상한 시간 500ms 선언',
      );
      expect(
        countOccurrences(code, 'precacheSplashLogo('),
        1,
        reason: '부르는 곳은 한 곳',
      );
      final int dateFormatting = code.indexOf('initializeDateFormatting(');
      final int firebase = code.indexOf('initializeFirebase(');
      expect(dateFormatting, isNonNegative);
      expect(firebase, isNonNegative);
      expect(
        starts.single.end,
        lessThan(dateFormatting),
        reason: '날짜 형식 초기화보다 먼저 시작',
      );
      expect(
        starts.single.end,
        lessThan(firebase),
        reason: 'Firebase 초기화보다 먼저 시작',
      );
    });

    test('runApp 바로 앞에서 기다린다', () {
      final String? name = _startPattern.firstMatch(code)?.group(1);
      expect(name, isNotNull, reason: '시작한 Future 의 변수');
      final waits = RegExp(
        'await\\s+$name\\s*;\\s*runApp\\(',
      ).allMatches(code).toList();
      expect(waits, hasLength(1), reason: 'runApp 바로 앞 기다림');
      expect(
        RegExp('await\\s+$name\\b').allMatches(code),
        hasLength(1),
        reason: '기다리는 곳은 한 곳',
      );
      expect(countOccurrences(code, 'runApp('), 1, reason: 'runApp 은 한 곳');
      final int lastInit = code.indexOf('fetchAndActivate()');
      expect(lastInit, isNonNegative);
      expect(
        waits.single.start,
        greaterThan(lastInit),
        reason: '마지막 초기화 뒤에 기다림',
      );
    });
  });
}
