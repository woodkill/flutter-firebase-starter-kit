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

import 'package:flutter_test/flutter_test.dart';

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
int _countExactLines(String source, String line) => source
    .split('\n')
    .where((String candidate) => candidate.trim() == line)
    .length;

void main() {
  group('DEVELOPMENT_TEAM 위치 (D-11)', () {
    test('T-174-TEAM-01: tracked project.pbxproj 에 DEVELOPMENT_TEAM 0', () {
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
    });

    test('T-174-TEAM-02: example xcconfig 3 flavor 에 빈 자리표시 1줄 · 값 0', () {
      for (final String flavor in _flavors) {
        final String path = 'ios/Flutter/$flavor.example.xcconfig';
        final String source = stripSlashComments(readTrackedFile(path));

        expect(
          _countExactLines(source, _emptyPlaceholder),
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
