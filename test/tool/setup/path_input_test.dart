import 'dart:io';

import 'package:test/test.dart';

import '../../../tool/setup/providers/path_input.dart';
import '../../../tool/setup/wizard.dart';
import 'fakes.dart';

/// 기대 경로 안의 홈 디렉터리 자리표시.
const String homeMark = '{home}';

/// 기대 경로 안의 저장소 root 자리표시.
const String rootMark = '{root}';

/// macOS 스크린샷 꼴 파일 이름(조합형 글자로 적은 원문).
const String screenshotName = '스크린샷 오후 3.14.15.png';

/// [text] 의 한글 음절을 첫소리 · 가운데소리 · 끝소리 자모로 푼다(NFD 꼴).
///
/// 음절이 아닌 글자는 그대로 둔다.
String decomposeHangul(String text) {
  const syllableBase = 0xAC00;
  const syllableLast = 0xD7A3;
  const leadBase = 0x1100;
  const vowelBase = 0x1161;
  const tailBase = 0x11A7;
  const vowelCount = 21;
  const tailCount = 28;
  final codes = <int>[];
  for (final int rune in text.runes) {
    if (rune < syllableBase || rune > syllableLast) {
      codes.add(rune);
      continue;
    }
    final int index = rune - syllableBase;
    codes
      ..add(leadBase + index ~/ (vowelCount * tailCount))
      ..add(vowelBase + (index % (vowelCount * tailCount)) ~/ tailCount);
    final int tail = index % tailCount;
    if (tail != 0) codes.add(tailBase + tail);
  }
  return String.fromCharCodes(codes);
}

/// 끌어다 놓기 · 붙여 넣기 답과 기대 경로 한 행.
typedef PathCase = ({String answer, String expected});

/// 답 [answer] 를 풀고 확장한 경로 — 화면 질문 답과 같은 두 단계다.
String resolveAnswer(WizardContext context, String answer) =>
    expandInputPath(context, parseDroppedPath(answer));

void main() {
  late Directory base;
  late String root;
  late String home;
  late WizardContext context;

  setUp(() {
    base = Directory.systemTemp.createTempSync('path_input_');
    root = '${base.path}/repo';
    home = '${base.path}/home';
    Directory(root).createSync();
    Directory(home).createSync();
    context = buildTestContext(projectRoot: root, homeDirectory: home);
  });

  tearDown(() => base.deleteSync(recursive: true));

  /// [expected] 의 자리표시를 이 시험의 홈 · root 로 바꾼다.
  String fillMarks(String expected) =>
      expected.replaceAll(homeMark, home).replaceAll(rootMark, root);

  test('T-20.1-PATH-01: 끌어다 놓기 · 따옴표 · escape · ~ · 상대 경로 · '
      'file 주소 답이 기대 경로로 풀린다', () {
    final String nfd = decomposeHangul(screenshotName);
    final cases = <PathCase>[
      (
        answer: '/Users/me/Desktop/logo.png',
        expected: '/Users/me/Desktop/logo.png',
      ),
      (
        answer: r'/Users/me/My\ Logos/app\ icon.png ',
        expected: '/Users/me/My Logos/app icon.png',
      ),
      (
        answer: "'/Users/me/My Logos/app icon.png'",
        expected: '/Users/me/My Logos/app icon.png',
      ),
      (answer: '"/Users/me/x (1).png"', expected: '/Users/me/x (1).png'),
      (answer: r'/Users/me/x\ \(1\).png', expected: '/Users/me/x (1).png'),
      (answer: r"'/Users/me/It'\''s.png'", expected: "/Users/me/It's.png"),
      (answer: r"/Users/me/It\'s.png", expected: "/Users/me/It's.png"),
      (answer: '~/Desktop/logo.png', expected: '$homeMark/Desktop/logo.png'),
      (
        answer: r'~/My\ Logos/logo.png',
        expected: '$homeMark/My Logos/logo.png',
      ),
      (answer: 'assets/logo.png', expected: '$rootMark/assets/logo.png'),
      (
        answer: '/Users/me/Desktop/${nfd.replaceAll(' ', r'\ ')}',
        expected: '/Users/me/Desktop/$nfd',
      ),
      // 닫히지 않은 작은따옴표 — 이름에 따옴표 하나만 든 경로는 그대로다.
      (answer: "/Users/me/It's.png", expected: "/Users/me/It's.png"),
      (
        answer: 'file:///Users/me/My%20Logos/a.png',
        expected: '/Users/me/My Logos/a.png',
      ),
    ];

    for (final item in cases) {
      expect(
        resolveAnswer(context, item.answer),
        fillMarks(item.expected),
        reason: item.answer,
      );
    }
    // 조각 안의 %2F · 깨진 UTF-8 — 파일 경로로 바꿀 수 없어 예외 대신 손대지
    // 않은 값이다.
    for (final unconvertible in <String>[
      'file:///a%2Fb.png',
      'file:///Users/me/a%2F..%2Fb.png',
      'file:///a%FF.png',
    ]) {
      expect(parseDroppedPath(unconvertible), unconvertible);
    }
  });

  group('T-20.1-PATH-02: 경로 확장 · 화면 표시', () {
    test('~ · ~/x · 상대 · 절대 · 빈 값을 확장한다', () {
      expect(expandInputPath(context, '~'), home);
      expect(expandInputPath(context, '~/x.png'), '$home/x.png');
      expect(expandInputPath(context, 'a/b.png'), '$root/a/b.png');
      expect(expandInputPath(context, '/abs/x.png'), '/abs/x.png');
      expect(expandInputPath(context, ''), '');
    });

    test('홈과 그 아래는 ~ 로 줄이고 바깥은 그대로 둔다', () {
      expect(describePath(context, home), '~');
      expect(describePath(context, '$home/x/y.png'), '~/x/y.png');
      expect(describePath(context, '/other/z.png'), '/other/z.png');
      expect(describePath(context, '${home}x/y.png'), '${home}x/y.png');
    });

    test('홈 디렉터리를 모르면 그대로 둔다', () {
      final WizardContext noHome = buildTestContext(
        projectRoot: root,
        homeDirectory: '',
      );

      expect(describePath(noHome, '/Users/me/x.png'), '/Users/me/x.png');
    });
  });

  test('T-20.1-PATH-03: NFD 한글 파일 이름은 풀기 · 확장 뒤에도 코드 단위가 '
      '그대로다', () {
    final String nfd = decomposeHangul(screenshotName);
    expect(nfd, isNot(screenshotName));
    expect(
      nfd.runes.where((int rune) => rune >= 0xAC00 && rune <= 0xD7A3),
      isEmpty,
    );
    final expected = '$home/Desktop/$nfd';
    final dropped = '~/Desktop/${nfd.replaceAll(' ', r'\ ')} ';

    final String resolved = resolveAnswer(context, dropped);

    expect(resolved.codeUnits, expected.codeUnits);
    expect(
      describePath(context, resolved).codeUnits,
      '~/Desktop/$nfd'.codeUnits,
    );
  });
}
