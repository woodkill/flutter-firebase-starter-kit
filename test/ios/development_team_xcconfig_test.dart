// Apple Team ID 위치 계약 테스트 (Phase 17.4 D-11 — see ROADMAP.md).
//
// **목적:** Apple Developer Team ID(`DEVELOPMENT_TEAM`)는 사용자마다 다른 값이라
// 사용자 소유 표면인 gitignored `ios/Flutter/{flavor}.xcconfig` 에만 둔다.
// `project.pbxproj` 에 값이 다시 들어오면 (1) 공개본에 값이 실리고 (2) 킷이
// pbxproj 를 고치는 판마다 사용자의 Team ID 줄과 충돌한다. target 수준의
// pbxproj 값은 xcconfig 값을 덮으므로, 줄이 하나라도 남으면 xcconfig 의 값이
// 조용히 무시된다.
//
// **tracked 파일만 읽는다** — gitignored 실 값 파일(`ios/Flutter/{flavor}.xcconfig`)
// 은 열지 않으므로 fresh clone · CI 에서도 결과가 같다. 부재 단언 앞에는 양성
// 대조(같은 파일에서 다른 빌드 설정이 실재)를 세워 경로가 깨졌을 때 「0건」 이
// 공허하게 참이 되지 않게 한다.
//
// **어디서 도는가:** T-174-TEAM-01(pbxproj 0건)은 유지보수자 트리에서만 돈다 —
// 사용자가 Xcode 에서 Team 을 고르면 Xcode 가 pbxproj 에 값을 다시 써 넣고,
// 매뉴얼 사용자 소유 표면 표가 pbxproj 의 「Xcode 가 저장하는 설정」 을 사용자에게
// 넘긴다. 공개본에 값이 실리지 않는 것은 발행 스크립트 `scan` 의 전체 이력 검사가
// 보장한다. T-174-TEAM-02(example xcconfig)는 사용자 저장소에서도 참이어야 하므로
// 어디서나 돈다.

import 'package:flutter_test/flutter_test.dart';

import '../helpers/planning_docs.dart';
import '../helpers/source_text.dart';

const String _pbxprojPath = 'ios/Runner.xcodeproj/project.pbxproj';
const String _teamKey = 'DEVELOPMENT_TEAM';
const String _emptyPlaceholder = 'DEVELOPMENT_TEAM =';
const List<String> _flavors = <String>['dev', 'stg', 'prod'];

/// 10자 Team ID 값이 채워진 줄 — example 에는 0 이어야 한다.
final RegExp _filledTeamLine = RegExp(
  r'^DEVELOPMENT_TEAM = [A-Z0-9]{10}$',
  multiLine: true,
);

/// 앞뒤 공백을 걷어낸 줄이 [line] 과 정확히 같은 줄의 수를 센다.
///
/// 공용 `countExactLines`(`test/helpers/source_text.dart`)는 공백을 걷지 않고
/// 비교한다 — 의미가 달라 이름을 나눈다.
int _countTrimmedLines(String source, String line) => source
    .split('\n')
    .where((String candidate) => candidate.trim() == line)
    .length;

void main() {
  group('DEVELOPMENT_TEAM 위치 (D-11)', () {
    test(
      'T-174-TEAM-01: tracked project.pbxproj 에 DEVELOPMENT_TEAM 0',
      () {
        final String source = readTrackedFile(_pbxprojPath);

        // 양성 대조 — 같은 파일에서 다른 빌드 설정은 읽힌다.
        expect(
          countOccurrences(source, 'PRODUCT_BUNDLE_IDENTIFIER'),
          greaterThanOrEqualTo(1),
          reason:
              '$_pbxprojPath 를 제대로 읽었다면 PRODUCT_BUNDLE_IDENTIFIER 가 '
              '1개 이상 있어야 한다.',
        );
        expect(
          countOccurrences(source, _teamKey),
          0,
          reason:
              '$_pbxprojPath 에 $_teamKey 가 있으면 target 값이 xcconfig 를 '
              '덮고, 공개본에 값이 실리며, 킷 업데이트 때 충돌한다. 값은 '
              'gitignored ios/Flutter/<flavor>.xcconfig 에만 둔다.',
        );
      },
      // 사용자 저장소에서는 Xcode 의 Team 선택이 pbxproj 에 값을 써 넣는다 —
      // 킷 발행 위생 검사라 비공개 작업 일지가 있는 유지보수자 트리에서만 돈다.
      skip: skipUnlessPlanningDocsExist(const <String>['.planning/ROADMAP.md']),
    );

    test('T-174-TEAM-02: example xcconfig 3 flavor 에 빈 자리표시 1줄 · 값 0', () {
      for (final String flavor in _flavors) {
        final String path = 'ios/Flutter/$flavor.example.xcconfig';
        final String source = stripSlashComments(readTrackedFile(path));

        expect(
          _countTrimmedLines(source, _emptyPlaceholder),
          1,
          reason:
              '$path 에 빈 자리표시 "$_emptyPlaceholder" 가 정확히 1줄 '
              '있어야 한다. 비어 있지 않은 자리표시 문자열은 xcodebuild 가 '
              '팀으로 넘기므로 값 없이 둔다.',
        );
        expect(
          _filledTeamLine.allMatches(source).length,
          0,
          reason:
              '$path 에 10자 Team ID 값이 있으면 안 된다 — 값은 '
              'gitignored ios/Flutter/$flavor.xcconfig 에만 둔다.',
        );
      }
    });
  });
}
