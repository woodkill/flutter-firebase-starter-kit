// 매뉴얼의 소셜 버튼 안내가 인용한 값을 저장소의 실제 값과 맞춰 보는 계약.
//
// 매뉴얼은 소셜 버튼 골격 상수 이름(`kBrand…`)을 인용하고, 「문제 해결」 에서
// 없는 iOS golden 때문에 실패하는 테스트 건수를 적는다. 이 파일은 그 두 가지만
// 반복 실행 가능한 test 로 단언한다. 상수의 값은 단언하지 않는다.
//
// T-177-DOCS-01: 매뉴얼이 인용한 `kBrand…` 이름이 모두 위젯 파일의 top-level
//   `const` 선언 이름에 있다.
// T-177-DOCS-02: 매뉴얼의 「테스트 실패 N건」 의 N 이 `.gitignore` 에서 주석을
//   뺀 뒤 `_ios.png` 로 끝나는 줄 수와 같다.
//
// 어디서 도는가: 01 은 이름 포인터 확인이라 사용자 저장소에서도 참이므로
// 어디서나 돈다. 02 는 값 대조다 — 킷 사용자가 자기 버튼의 iOS golden 을 더하면
// 자기 저장소의 줄 수가 달라지는데 매뉴얼은 킷의 건수를 적는다. 그래서 비공개
// 작업 일지(`.planning/`)가 있는 유지보수자 트리에서만 돈다(공개 mirror 에서는
// 건너뜀). 건수는 테스트에 리터럴로 두지 않고 `.gitignore` 에서 읽는다.

import 'package:flutter_test/flutter_test.dart';

import '../../helpers/planning_docs.dart';
import '../../helpers/source_text.dart';

/// 매뉴얼 경로.
const String _manualPath = 'docs/manual.md';

/// 소셜 버튼 골격 상수를 선언하는 위젯 파일 경로.
const String _widgetPath =
    'lib/features/auth/presentation/_widgets/branded_social_button.dart';

/// 저장소 `.gitignore` 경로.
const String _gitignorePath = '.gitignore';

/// 유지보수자 트리에만 있는 파일 — 이 파일이 없는 트리에서는 02 를 건너뛴다.
const List<String> _maintainerOnlyDocs = <String>['.planning/ROADMAP.md'];

/// 매뉴얼 본문에서 `kBrand…` 상수 이름 토큰을 찾는 정규식.
final RegExp _manualConstantPattern = RegExp(r'\bkBrand[A-Z][A-Za-z0-9]*\b');

/// 위젯 파일에서 줄 머리 `const <타입> kBrand… =` 선언의 이름을 찾는 정규식.
final RegExp _declarationPattern = RegExp(
  r'^const\s+[\w<>?]+\s+(kBrand[A-Z][A-Za-z0-9]*)\s*=',
  multiLine: true,
);

/// 매뉴얼 「문제 해결」 의 iOS golden 실패 건수 문장을 찾는 정규식.
///
/// 줄 머리 목록 항목의 굵은 글씨를 글자 그대로 본다 — 숫자 자리만 열어 둔다.
/// iOS golden 이 아닌 다른 실패 건수 문장은 이 문장으로 세지 않는다.
final RegExp _failureCountPattern = RegExp(
  r'^- \*\*macOS 에서 `goldens/\*_ios\.png` 가 없다는 테스트 실패 (\d+)건\.\*\*',
  multiLine: true,
);

/// [manual] 이 인용한 `kBrand…` 이름 집합을 모은다.
Set<String> _collectCitedNames(String manual) => _manualConstantPattern
    .allMatches(manual)
    .map((RegExpMatch m) => m.group(0)!)
    .toSet();

/// [source] 에서 줄 머리 `const` 로 선언된 `kBrand…` 이름 집합을 모은다.
///
/// 주석 줄 속 이름과 줄 머리가 아닌 사용처는 선언으로 세지 않는다.
Set<String> _collectDeclaredNames(String source) => _declarationPattern
    .allMatches(source)
    .map((RegExpMatch m) => m.group(1)!)
    .toSet();

/// [gitignore] 에서 `#` 주석 줄을 뺀 뒤 `_ios.png` 로 끝나는 줄 수를 센다.
int _countIosGoldenLines(String gitignore) => stripHashComments(
  gitignore,
).split('\n').where((String line) => line.trim().endsWith('_ios.png')).length;

void main() {
  group('매뉴얼 소셜 버튼 안내 계약', () {
    test('T-177-DOCS-01: 매뉴얼이 인용한 kBrand 상수 이름은 모두 위젯 파일에 '
        '선언돼 있다', () {
      // 세는 방법의 양성 대조 — 선언 줄만 세고 주석 · 사용처는 세지 않는다.
      const String sample = '''
/// `kBrandCommentOnly` 는 문서 주석 속 이름이다.
const double kBrandSampleDeclared = 48;
final double used = kBrandSampleUsedOnly + 1;
''';
      expect(_collectDeclaredNames(sample), <String>{'kBrandSampleDeclared'});

      final Set<String> cited = _collectCitedNames(
        readTrackedFile(_manualPath),
      );
      final Set<String> declared = _collectDeclaredNames(
        readTrackedFile(_widgetPath),
      );
      expect(cited, isNotEmpty, reason: '매뉴얼이 kBrand 이름을 인용하지 않는다');
      expect(declared, isNotEmpty, reason: '위젯 파일에서 선언을 찾지 못했다');

      final Set<String> missing = cited.difference(declared);
      expect(missing, isEmpty, reason: '매뉴얼이 인용한 상수 이름이 위젯 파일에 없다: $missing');
    });

    test('T-177-DOCS-02: 매뉴얼의 iOS golden 테스트 실패 건수는 .gitignore 의 '
        '_ios.png 줄 수와 같다', () {
      final List<RegExpMatch> sentences = _failureCountPattern
          .allMatches(readTrackedFile(_manualPath))
          .toList();
      expect(
        sentences,
        hasLength(1),
        reason: 'iOS golden 실패 건수 문장은 매뉴얼에 정확히 1번 있어야 한다',
      );
      final int documented = int.parse(sentences.single.group(1)!);

      final int actual = _countIosGoldenLines(readTrackedFile(_gitignorePath));
      // 세는 방법의 양성 대조 — 주석 줄은 세지 않고 패턴 줄만 센다.
      expect(_countIosGoldenLines('# a_ios.png\nx/b_ios.png\nc.png'), 1);
      expect(actual, greaterThan(0), reason: '_ios.png 줄을 찾지 못했다');

      expect(
        documented,
        actual,
        reason: '매뉴얼 $documented건 != .gitignore _ios.png $actual줄',
      );
    }, skip: skipUnlessPlanningDocsExist(_maintainerOnlyDocs));
  });
}
