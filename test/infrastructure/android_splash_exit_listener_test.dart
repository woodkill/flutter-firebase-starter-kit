// Android 12 이상 OS 스플래시 퇴장 리스너 계약.
//
// Android 12 이상의 OS 스플래시는 Flutter 첫 프레임이 그려질 때 짧은 페이드로 사라지고,
// 그동안 로고가 옅어졌다 돌아와 깜빡여 보인다. 킷의 MainActivity 는 `super.onCreate` 전에
// 퇴장 리스너를 걸어 스플래시 화면을 애니메이션 없이 바로 걷는다(Flutter 공식 문서의 예제
// 꼴). Activity 는 기기에서만 돌므로 소스 텍스트로 잠근다 — 주석을 걷은 뒤 `MainActivity`
// 클래스 안의 `onCreate` 본문만 본다(같은 파일의 LINE 콜백 relay 에도 `onCreate` 가 있다).
// Kotlin 디렉터리는 `MainActivity.kt` 위치에서 파생하므로 앱 패키지 경로를 바꾼 저장소에서도
// 돈다.
//
// 창 맞춤(WindowCompat) 금지는 킷 유지보수 규칙이라 유지보수자 트리에서만 돈다 — 킷을 받은
// 저장소는 창 맞춤을 넣을 수 있고, 거기서 이 시험이 실패하면 안 된다.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../helpers/planning_docs.dart';
import '../helpers/source_text.dart';

/// `MainActivity` 클래스 머리 — 본문은 바로 뒤 여는 중괄호에서 시작한다.
const String _classHead = 'class MainActivity : FlutterFragmentActivity() {';

/// `onCreate` 재정의 머리 — 본문은 끝의 여는 중괄호에서 시작한다.
final RegExp _onCreateHead = RegExp(
  r'override\s+fun\s+onCreate\(\s*savedInstanceState:\s*Bundle\?\s*\)\s*\{',
);

/// Android 12(API 31) 가드 안에서 퇴장 리스너를 걸고, 리스너가 받은 스플래시 화면을
/// 바로 걷는 꼴이다.
final RegExp _guardedExitListener = RegExp(
  r'if\s*\(\s*Build\.VERSION\.SDK_INT\s*>=\s*Build\.VERSION_CODES\.S\s*\)\s*\{\s*'
  r'splashScreen\.setOnExitAnimationListener\s*\{\s*(\w+)\s*->\s*\1\.remove\(\)\s*\}'
  r'\s*\}',
);

/// 퇴장 리스너를 거는 호출이다.
const String _listenerCall = 'splashScreen.setOnExitAnimationListener';

/// 부모 `onCreate` 호출이다.
final RegExp _superOnCreate = RegExp(
  r'super\.onCreate\(\s*savedInstanceState\s*\)',
);

void main() {
  group('Android 12 이상 OS 스플래시 퇴장 리스너', () {
    late final String mainActivity = _readMainActivityClassBody();

    /// `MainActivity` 의 `onCreate` 본문들을 돌려준다(재정의가 없으면 빈 목록).
    List<String> onCreateBodies() => <String>[
      for (final RegExpMatch head in _onCreateHead.allMatches(mainActivity))
        _readBraceBlock(mainActivity, head.end - 1),
    ];

    test('MainActivity.onCreate 가 Android 12 이상에서만 퇴장 리스너를 걸어 '
        '스플래시 화면을 바로 걷는다', () {
      final List<String> bodies = onCreateBodies();
      expect(bodies, hasLength(1), reason: 'MainActivity 의 onCreate 재정의 하나');
      expect(
        _guardedExitListener.allMatches(bodies.single),
        hasLength(1),
        reason: 'API 31 가드 안에서 리스너를 걸고 리스너가 remove() 로 바로 걷는다',
      );
      expect(
        countOccurrences(mainActivity, _listenerCall),
        1,
        reason: '리스너를 거는 곳은 한 곳',
      );
    });

    test('퇴장 리스너는 super.onCreate 보다 먼저 건다', () {
      final List<String> bodies = onCreateBodies();
      expect(bodies, hasLength(1), reason: 'MainActivity 의 onCreate 재정의 하나');
      final String body = bodies.single;
      final int listener = body.indexOf(_listenerCall);
      final List<RegExpMatch> supers = _superOnCreate.allMatches(body).toList();
      expect(listener, isNonNegative, reason: 'onCreate 안의 리스너');
      expect(supers, hasLength(1), reason: 'onCreate 안의 부모 호출 하나');
      expect(
        listener,
        lessThan(supers.single.start),
        reason: '리스너는 부모 onCreate 전에 건다(문서 예제와 같은 자리)',
      );
    });

    test('창 맞춤(WindowCompat)은 바꾸지 않는다', () {
      for (final token in <String>[
        'WindowCompat',
        'setDecorFitsSystemWindows',
      ]) {
        expect(
          countOccurrences(mainActivity, token),
          0,
          reason: '`$token` 금지 — 스플래시 퇴장 리스너만 더하고 창 맞춤은 그대로 둔다',
        );
      }
    }, skip: skipUnlessMaintainerTree());
  });
}

/// 주석을 걷은 `MainActivity.kt` 에서 `MainActivity` 클래스 본문을 돌려준다.
String _readMainActivityClassBody() {
  final String code = stripBlockComments(
    stripSlashComments(
      readTrackedFile('${_findKotlinPackageDir()}/MainActivity.kt'),
    ),
  );
  final int start = code.indexOf(_classHead);
  if (start < 0) {
    fail('MainActivity.kt 에서 `$_classHead` 를 찾지 못했다.');
  }
  return _readBraceBlock(code, start + _classHead.length - 1);
}

/// [source] 의 [open] 위치 여는 중괄호부터 짝이 맞는 닫는 중괄호 직전까지를 돌려준다.
String _readBraceBlock(String source, int open) {
  var depth = 0;
  for (var i = open; i < source.length; i++) {
    final String char = source[i];
    if (char == '{') {
      depth++;
    } else if (char == '}') {
      depth--;
      if (depth == 0) {
        return source.substring(open + 1, i);
      }
    }
  }
  fail('중괄호 짝을 찾지 못했다(위치 $open).');
}

/// `android/app/src/main/kotlin` 아래 `MainActivity.kt` 가 있는 패키지
/// 디렉터리를 돌려준다.
///
/// `test/infrastructure/line_auth_task_return_contract_test.dart` 의 같은 이름 함수와
/// 같은 동작의 작은 사본이다 — 그 시험 파일을 고치지 않으려고 여기 둔다.
/// `MainActivity.kt` 가 0개 또는 2개 이상이면 어느 패키지를 볼지 모호하므로 시험을
/// 실패시킨다.
String _findKotlinPackageDir() {
  const kotlinBase = 'android/app/src/main/kotlin';
  final base = Directory(kotlinBase);
  if (!base.existsSync()) {
    fail('Kotlin 소스 루트 부재: $kotlinBase');
  }
  final List<File> mainActivities = base
      .listSync(recursive: true)
      .whereType<File>()
      .where((File file) => file.uri.pathSegments.last == 'MainActivity.kt')
      .toList();
  if (mainActivities.length != 1) {
    fail(
      '$kotlinBase 아래 MainActivity.kt 가 정확히 1개여야 한다 '
      '(발견 ${mainActivities.length}개).',
    );
  }
  return mainActivities.single.parent.path;
}
