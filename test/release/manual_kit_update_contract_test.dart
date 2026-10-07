// 매뉴얼 「킷 업데이트 반영」 · README 머리 계약 (Phase 17.4 D-36 · D-37 · D-38 — see ROADMAP.md).
// 헤딩 · 목차 · 사용자 문서 금지 패턴 · 명령 · 사용자 소유 표면 표 · 진입점 ·
// 예시 일치 대조.
//
// T-174-DOCS-01: 절 헤딩 1개 · 목차 항목 1개 · 목차 번호 0부터 연속 · 새 항목이
//   「로그인 수단 켜고 끄기」 항목 바로 다음 줄이다.
// T-174-DOCS-02: 절에 사용자 문서 금지 패턴이 0 건이고, template 시작 소절의 bash
//   블록이 기준점 명령 4줄 하나다.
// T-174-DOCS-03: 절의 `###` 소절 9개가 이 순서 그대로다.
// T-174-DOCS-04: 새 판 받기 · 충돌 풀기 · 바꾸지 않는 것 · 확인 · 문제 해결 ·
//   되돌리기의 명령 줄과 토큰(git 메시지 원문 · rename 사용 순서 포함)이 있고,
//   `git apply -3` 은 「쓰지 않는다」 문장 1회 · 되돌리기의 bash 블록은 2개다.
// T-174-DOCS-05: 사용자 소유 표면 표가 헤더 · 32행 · 등급 단어로 시작하는 넷째 칸을
//   갖고, 표 앞 문단의 MAJOR 기준 문장이 CHANGELOG 판 번호 규칙과 같은 문자열이다.
// T-174-DOCS-06: README 머리(첫 `## ` 앞)에 Use this template · 매뉴얼 절 링크 ·
//   Issues 안내가 있고 금지 패턴이 0 건이며, Getting Started 가 template → clone
//   순이고 매뉴얼 Initial Setup 머리가 template 기준이다.
// T-174-DOCS-07: 절 끝 배경 링크 1줄이 유지보수자 발행 문서를 가리키고, 그 문서에
//   발행 단계 · 릴리스 컷 · 첫 공개 절차 절이 있다.
// T-174-DOCS-08: 절의 rename 예시 옵션 · xcconfig 파일 이름이 `bin/rename.dart` 에,
//   표의 `DEVELOPMENT_TEAM` 이 dev example xcconfig 에, 상수 3개 이름이
//   `scripts/firebase-configure.sh` 에 있다.

import 'package:flutter_test/flutter_test.dart';

import '../helpers/source_text.dart';

/// 매뉴얼 경로.
const String _manualPath = 'docs/manual.md';

/// README 경로.
const String _readmePath = 'README.md';

/// CHANGELOG 경로 (판 번호 규칙의 진실원).
const String _changelogPath = 'CHANGELOG.md';

/// 유지보수자 발행 문서 경로.
const String _maintainerDocPath = 'docs/maintainer/kit-release-publishing.md';

/// 앱 ID 변경 도구 소스 경로.
const String _renamePath = 'bin/rename.dart';

/// dev example xcconfig 경로(진실원).
const String _exampleXcconfigPath = 'ios/Flutter/dev.example.xcconfig';

/// Firebase 설정 스크립트 경로(진실원).
const String _firebaseConfigurePath = 'scripts/firebase-configure.sh';

/// 절 헤딩 (정확히 한 줄).
const String _sectionHeading = '## 킷 업데이트 반영';

/// 목차 항목 줄 (번호는 목차 위치에 따라 바뀌므로 정규식으로 본다).
final RegExp _tocEntryPattern = RegExp(
  r'^\d+\. \[킷 업데이트 반영\]\(#킷-업데이트-반영\)$',
  multiLine: true,
);

/// 새 항목 바로 앞에 있어야 하는 목차 항목.
final RegExp _previousTocEntryPattern = RegExp(
  r'^\d+\. \[로그인 수단 켜고 끄기\]\(#로그인-수단-켜고-끄기\)$',
);

/// 「시작하기 — template」 의 기준점 명령 4줄 (정확한 줄).
const List<String> _templateCommandLines = <String>[
  'git remote add upstream https://github.com/woodkill/flutter-firebase-starter-kit.git',
  'git fetch upstream --tags',
  'git merge -s ours --allow-unrelated-histories "v\$(cat KIT_VERSION)" -m "킷 기준점 v\$(cat KIT_VERSION)"',
  'git push',
];

/// 절의 `###` 소절 (순서 그대로).
const List<String> _subsectionHeadings = <String>[
  '### 시작하기 — template 로 앱 저장소 만들기',
  '### 시작하기 — clone 으로 시작한 경우',
  '### 새 판 받기',
  '### 충돌 풀기',
  '### 바꾸지 않는 것',
  '### 사용자 소유 표면',
  '### 확인 방법',
  '### 문제 해결',
  '### 되돌리기',
];

/// 절에 정확한 줄로 있어야 하는 명령 줄.
const List<String> _requiredCommandLines = <String>[
  'TAG=v1.0.0-rc.2',
  'git merge "\$TAG" -m "킷 \$TAG 반영"',
  'git rm <파일>',
  'git checkout --ours -- <파일>',
  'git add <파일>',
  'git commit --no-edit',
  'mkdir -p ../kit-merge-backup',
  'cp lib/core/firebase/firebase_options_dev.dart ios/config/dev/GoogleService-Info.plist ../kit-merge-backup/',
  'git update-index --no-skip-worktree lib/core/firebase/firebase_options_dev.dart ios/config/dev/GoogleService-Info.plist',
  'git checkout -- lib/core/firebase/firebase_options_dev.dart ios/config/dev/GoogleService-Info.plist',
  'cp ../kit-merge-backup/firebase_options_dev.dart lib/core/firebase/firebase_options_dev.dart',
  'cp ../kit-merge-backup/GoogleService-Info.plist ios/config/dev/GoogleService-Info.plist',
  'git update-index --skip-worktree lib/core/firebase/firebase_options_dev.dart ios/config/dev/GoogleService-Info.plist',
  'git remote rename origin upstream',
  'git remote add origin <your-private-repo-url>',
  'git push -u origin main',
  'git merge --abort',
  'git revert -m 1 <merge 커밋>',
  'fvm flutter pub get',
  'fvm dart run build_runner build --delete-conflicting-outputs',
  'fvm dart analyze',
  'fvm flutter test',
  'fvm dart run bin/rename.dart --org com.mycompany --name my_app --project-prefix my-company-app',
  'fvm dart run bin/rename.dart --org com.mycompany --name my_app --project-prefix my-company-app --apply',
  "fvm flutter test --update-goldens --plain-name '(iOS)' test/features/auth/presentation/_widgets/branded_social_button_golden_test.dart",
];

/// 절에 있어야 하는 토큰 (git 메시지는 영어 · 한국어 원문).
const List<String> _requiredTokens = <String>[
  'Watch',
  'Releases',
  'cat KIT_VERSION',
  '### 사용자 조치',
  'flutter_starter_kit',
  'pub upgrade',
  'fork',
  'MAJOR',
  'CONFLICT (modify/delete)',
  'CONFLICT (content)',
  'error: Your local changes to the following files would be overwritten by merge:',
  'Please commit your changes or stash them before you merge',
  '병합하기 전에 변경 사항을 커밋하거나 스태시하십시오',
  'git ls-files -v | grep',
  'config example 을 복사한 뒤 실행한다',
  '`config/*.example.json` 은 바꾸지 않는다',
];

/// 패치 적용 방식 — 「쓰지 않는다」 문장으로 정확히 1회만 나온다.
const String _patchApplyToken = 'git apply -3';

/// 사용자 소유 표면 표 헤더 (정확한 줄).
const String _surfaceTableHeader =
    '| # | 파일 | 사용자가 바꾸는 것 | 킷이 고칠 가능성 | 충돌 시 조치 |';

/// 사용자 소유 표면 표 데이터 행 수.
const int _surfaceTableRowCount = 32;

/// 넷째 칸(킷이 고칠 가능성)이 시작할 수 있는 등급 단어.
const Set<String> _likelihoodGrades = <String>{'높음', '중간', '낮음', '없음'};

/// MAJOR 기준 문장 — CHANGELOG 판 번호 규칙 ①과 같은 문자열이다.
const String _majorCriterion =
    'merge 뒤 사용자가 손봐야 하는 판은 MAJOR 다 — 사용자 소유 표면 표에서 킷이 '
    '고칠 가능성이 `낮음` 인 파일의 변경 · 표의 「충돌 시 조치」 칸 밖의 손질이 '
    '필요한 변경 · 콘솔 재설정 · 데이터 마이그레이션.';

/// README 머리의 매뉴얼 절 링크.
const String _readmeManualLink = '](docs/manual.md#킷-업데이트-반영)';

/// README Getting Started 의 단계 수 문장.
const String _readmeStepSentence = '앱 저장소를 만든 뒤 dev flavor 를 띄우기까지 5단계다.';

/// 매뉴얼 Initial Setup 머리의 새 문장(조각).
const String _initialSetupHead =
    'template 로 만든 앱 저장소(또는 킷 clone)를 받은 직후 1회만 수행하는 사전 작업입니다.';

/// 매뉴얼 Initial Setup 머리의 옛 문장(조각) — 남아 있으면 안 된다.
const String _initialSetupLegacyHead = 'starter kit 을 fork / clone 한 직후';

/// 절 끝 배경 링크 줄 (정확한 줄).
const String _backgroundLinkLine =
    '자세한 배경: 킷이 판을 내는 방법과 판 번호 규칙은 '
    '[유지보수자 문서](maintainer/kit-release-publishing.md)에 있다.';

/// 유지보수자 발행 문서에 있어야 하는 절 헤딩.
const List<String> _maintainerDocHeadings = <String>[
  '## 발행 단계',
  '## 릴리스 컷',
  '## 첫 공개 절차',
];

/// rename 예시 옵션 — 절 명령 줄의 `--<옵션>` 과 CLI 소스의 옵션 이름 문자열.
const List<String> _renameOptions = <String>[
  'org',
  'name',
  'project-prefix',
  'apply',
];

/// rename 이 iOS 번들 ID 를 바꾸는 사용자 xcconfig 파일 이름.
const List<String> _userXcconfigFileNames = <String>[
  'dev.xcconfig',
  'stg.xcconfig',
  'prod.xcconfig',
];

/// rename 이 킷 추적 xcconfig 를 바꾸지 않는다는 문장 조각.
const String _exampleXcconfigUntouched = '`*.example.xcconfig` 는 바꾸지 않는다';

/// `scripts/firebase-configure.sh` 의 앱 ID 상수 이름.
const List<String> _firebaseConfigureConstants = <String>[
  'PROJECT_ID_PREFIX',
  'IOS_BUNDLE_ID_PREFIX',
  'ANDROID_PACKAGE_PREFIX',
];

/// [text] 에서 사용자 문서 금지 패턴에 걸린 문자열을 모은다.
List<String> _collectForbiddenHits(String text) => RegExp(
  kUserDocForbiddenPatternSource,
).allMatches(text).map((RegExpMatch m) => m.group(0)!).toList();

/// README 에서 첫 `## ` 줄 앞까지(머리)를 돌려준다.
String _sliceReadmeHead(String readme) {
  final int index = readme.indexOf(RegExp(r'^## ', multiLine: true));
  return index == -1 ? readme : readme.substring(0, index);
}

/// [text] 의 ```` ```bash ```` 블록마다 본문 줄 목록을 모은다.
List<List<String>> _collectBashBlocks(String text) {
  final List<List<String>> blocks = <List<String>>[];
  List<String>? current;
  for (final String line in text.split('\n')) {
    if (current == null) {
      if (line == '```bash') {
        current = <String>[];
      }
    } else if (line == '```') {
      blocks.add(current);
      current = null;
    } else {
      current.add(line);
    }
  }
  return blocks;
}

/// 표 데이터 행 [row] 의 넷째 칸(킷이 고칠 가능성) 첫 단어를 돌려준다.
String _readLikelihoodGrade(String row) {
  final List<String> cells = row.split('|');
  if (cells.length < 5) {
    return '';
  }
  final String cell = cells[4].trim();
  return cell.split(' ').first;
}

void main() {
  final String manual = readTrackedFile(_manualPath);
  final String readme = readTrackedFile(_readmePath);
  final String section = sliceMarkdownSection(
    manual,
    _sectionHeading,
    maxLevel: 2,
  );

  group('매뉴얼 「킷 업데이트 반영」 계약 (T-174-DOCS)', () {
    test('T-174-DOCS-01: 절 헤딩 1개 · 목차 항목 1개 · 번호 0부터 연속 · 로그인 수단 항목 다음이다', () {
      expect(
        countExactLines(manual, _sectionHeading),
        1,
        reason: '절 헤딩이 없거나 중복이다',
      );

      final String toc = sliceTocBlock(manual);
      expect(toc.trim(), isNotEmpty, reason: '목차 블록을 찾지 못했다');
      expect(
        _tocEntryPattern.allMatches(toc).length,
        1,
        reason: '목차 블록 안 「킷 업데이트 반영」 항목이 없거나 중복이다',
      );

      final List<int> numbers = RegExp(
        r'^(\d+)\. ',
        multiLine: true,
      ).allMatches(toc).map((RegExpMatch m) => int.parse(m.group(1)!)).toList();
      expect(numbers, isNotEmpty, reason: '목차 번호 줄이 없다');
      expect(
        numbers,
        List<int>.generate(numbers.length, (int i) => i),
        reason: '목차 번호가 0부터 빠짐없이 이어지지 않는다',
      );

      final List<String> tocLines = toc.split('\n');
      final int entryIndex = tocLines.indexWhere(_tocEntryPattern.hasMatch);
      expect(entryIndex, greaterThan(0), reason: '목차 항목 위치를 찾지 못했다');
      expect(
        _previousTocEntryPattern.hasMatch(tocLines[entryIndex - 1]),
        isTrue,
        reason: '「킷 업데이트 반영」 항목이 「로그인 수단 켜고 끄기」 바로 다음이 아니다',
      );
    });

    test('T-174-DOCS-02: 절에 금지 패턴이 0 건이고 template 시작 명령 4줄이 있다', () {
      expect(section.trim(), isNotEmpty, reason: '절 슬라이스가 비었다');
      // 양성 대조: 금지 패턴 정규식이 실제로 phase 번호를 잡는다.
      expect(_collectForbiddenHits('Phase 9'), isNotEmpty);
      final List<String> hits = _collectForbiddenHits(section);
      expect(hits, isEmpty, reason: '금지 패턴이 절에 있다: $hits');

      // `git fetch upstream --tags` 는 「새 판 받기」 에도 나오므로 소절 안의
      // bash 블록 단위로 본다.
      final String templateStart = sliceMarkdownSection(
        section,
        _subsectionHeadings.first,
        maxLevel: 3,
      );
      expect(_collectBashBlocks(templateStart), <List<String>>[
        _templateCommandLines,
      ], reason: 'template 시작 소절의 bash 블록이 기준점 명령 4줄 하나가 아니다');
      expect(
        countExactLines(section, _templateCommandLines[2]),
        1,
        reason: '기준점 merge 명령은 절에 한 번만 나온다',
      );
    });

    test('T-174-DOCS-03: 절의 ### 소절 9개가 순서 그대로다', () {
      expect(linesStartingWith(section, '### '), _subsectionHeadings);
    });

    test('T-174-DOCS-04: 명령 줄 · 토큰 · git 메시지 원문 · 되돌리기 블록 2개가 있다', () {
      for (final String line in _requiredCommandLines) {
        expect(
          countExactLines(section, line),
          greaterThanOrEqualTo(1),
          reason: '명령 줄이 정확한 줄로 없다: $line',
        );
      }
      for (final String token in _requiredTokens) {
        expect(
          countOccurrences(section, token),
          greaterThanOrEqualTo(1),
          reason: '토큰이 절에 없다: $token',
        );
      }
      expect(
        countOccurrences(section, _patchApplyToken),
        1,
        reason: '`git apply -3` 은 「쓰지 않는다」 문장으로 정확히 1회만 나온다',
      );

      final String rollback = sliceMarkdownSection(
        section,
        '### 되돌리기',
        maxLevel: 3,
      );
      expect(rollback.trim(), isNotEmpty, reason: '되돌리기 소절을 찾지 못했다');
      expect(_collectBashBlocks(rollback), <List<String>>[
        <String>['git merge --abort'],
        <String>['git revert -m 1 <merge 커밋>'],
      ], reason: '되돌리기는 merge 도중 · merge 뒤 bash 블록 2개로 나뉜다');
    });

    test('T-174-DOCS-05: 사용자 소유 표면 표 32행 · 등급 · MAJOR 기준이 CHANGELOG 와 같다', () {
      final List<String> table = collectTableLines(
        section,
        _surfaceTableHeader,
      );
      expect(
        countExactLines(section, _surfaceTableHeader),
        1,
        reason: '표 헤더가 없거나 중복이다',
      );
      expect(table.length, greaterThan(2), reason: '표를 찾지 못했다');
      final List<String> rows = table.skip(2).toList();
      expect(rows, hasLength(_surfaceTableRowCount));

      final List<String> grades = rows.map(_readLikelihoodGrade).toList();
      for (int i = 0; i < rows.length; i++) {
        expect(
          _likelihoodGrades,
          contains(grades[i]),
          reason: '넷째 칸이 등급 단어로 시작하지 않는다: ${rows[i]}',
        );
      }
      expect(grades, contains('낮음'));
      final String firebaseOptionsRow = rows.firstWhere(
        (String row) => row.contains('firebase_options'),
        orElse: () => '',
      );
      expect(
        _readLikelihoodGrade(firebaseOptionsRow),
        '낮음',
        reason: 'skip-worktree 파일 행은 킷이 고치지 않겠다는 약속(낮음)이다',
      );

      final String surface = sliceMarkdownSection(
        section,
        '### 사용자 소유 표면',
        maxLevel: 3,
      );
      final int headerIndex = surface.indexOf(_surfaceTableHeader);
      expect(headerIndex, greaterThan(0), reason: '표 앞 문단을 찾지 못했다');
      final String lead = surface.substring(0, headerIndex);
      expect(countOccurrences(lead, '### 사용자 조치'), greaterThanOrEqualTo(1));
      expect(
        countOccurrences(lead, _majorCriterion),
        1,
        reason: 'CHANGELOG 판 번호 규칙과 매뉴얼 표 앞 문장은 같은 문자열이어야 한다',
      );
      expect(
        countOccurrences(section, _majorCriterion),
        1,
        reason: 'CHANGELOG 판 번호 규칙과 매뉴얼 표 앞 문장은 같은 문자열이어야 한다',
      );
      expect(
        countOccurrences(readTrackedFile(_changelogPath), _majorCriterion),
        1,
        reason: 'CHANGELOG 판 번호 규칙과 매뉴얼 표 앞 문장은 같은 문자열이어야 한다',
      );
    });

    test('T-174-DOCS-07: 절 끝 배경 링크가 유지보수자 발행 문서를 가리킨다', () {
      expect(countExactLines(section, _backgroundLinkLine), 1);
      final List<String> tail = section
          .split('\n')
          .where((String line) => line.trim().isNotEmpty)
          .toList();
      expect(tail.length, greaterThan(2));
      expect(tail.last, '---', reason: '절이 `---` 로 끝나지 않는다');
      expect(
        tail[tail.length - 2],
        _backgroundLinkLine,
        reason: '배경 링크가 절 끝(되돌리기 뒤)에 있지 않다',
      );

      final String maintainerDoc = readTrackedFile(_maintainerDocPath);
      for (final String heading in _maintainerDocHeadings) {
        expect(
          countExactLines(maintainerDoc, heading),
          1,
          reason: '유지보수자 발행 문서에 「$heading」 이 없거나 중복이다',
        );
      }
    });

    test('T-174-DOCS-08: rename 예시 · 표 변수 · 상수 이름이 소스 · example 과 일치한다', () {
      final String renameSource = readTrackedFile(_renamePath);
      for (final String option in _renameOptions) {
        expect(
          countOccurrences(renameSource, "'$option'"),
          greaterThanOrEqualTo(1),
          reason: 'bin/rename.dart 에 옵션 $option 이 없다',
        );
        expect(
          countOccurrences(section, '--$option'),
          greaterThanOrEqualTo(1),
          reason: '절의 rename 예시에 --$option 이 없다',
        );
      }
      for (final String fileName in _userXcconfigFileNames) {
        expect(
          countOccurrences(renameSource, "'$fileName'"),
          greaterThanOrEqualTo(1),
          reason: 'bin/rename.dart 가 $fileName 을 수집하지 않는다',
        );
        expect(
          countOccurrences(section, '`ios/Flutter/$fileName`'),
          greaterThanOrEqualTo(1),
          reason: '절이 rename 대상 xcconfig $fileName 을 적지 않는다',
        );
      }
      expect(
        countOccurrences(section, _exampleXcconfigUntouched),
        greaterThanOrEqualTo(1),
      );

      expect(
        countOccurrences(
          readTrackedFile(_exampleXcconfigPath),
          'DEVELOPMENT_TEAM =',
        ),
        1,
      );
      expect(
        countOccurrences(section, 'DEVELOPMENT_TEAM'),
        greaterThanOrEqualTo(1),
      );

      final String firebaseConfigure = readTrackedFile(_firebaseConfigurePath);
      for (final String constant in _firebaseConfigureConstants) {
        expect(
          countOccurrences(firebaseConfigure, '$constant='),
          greaterThanOrEqualTo(1),
          reason: '$_firebaseConfigurePath 에 $constant 가 없다',
        );
        expect(
          countOccurrences(section, constant),
          greaterThanOrEqualTo(1),
          reason: '절에 $constant 가 없다',
        );
      }
    });
  });

  group('README · Initial Setup 진입점 계약 (T-174-DOCS)', () {
    test(
      'T-174-DOCS-06: README 머리 · Getting Started · Initial Setup 머리가 template 기준이다',
      () {
        final String head = _sliceReadmeHead(readme);
        expect(head.trim(), isNotEmpty, reason: 'README 머리를 찾지 못했다');
        expect(
          countOccurrences(head, 'Use this template'),
          1,
          reason: 'README 머리에 Use this template 안내가 없거나 중복이다',
        );
        expect(
          countOccurrences(head, _readmeManualLink),
          1,
          reason: 'README 머리에 매뉴얼 「킷 업데이트 반영」 링크가 없거나 중복이다',
        );
        expect(
          countOccurrences(head, 'Issues'),
          greaterThanOrEqualTo(1),
          reason: 'README 머리에 Issues 안내가 없다',
        );
        final List<String> hits = _collectForbiddenHits(head);
        expect(hits, isEmpty, reason: '금지 패턴이 README 머리에 있다: $hits');

        final String gettingStarted = sliceMarkdownSection(
          readme,
          '## Getting Started',
          maxLevel: 2,
        );
        expect(gettingStarted.trim(), isNotEmpty);
        final List<String> gsLines = gettingStarted.split('\n');
        final int templateIndex = gsLines.indexWhere(
          (String line) => line.contains('Use this template'),
        );
        final int cloneIndex = gsLines.indexWhere(
          (String line) => line.contains('git clone <your-repo-url>'),
        );
        expect(templateIndex, greaterThanOrEqualTo(0));
        expect(cloneIndex, greaterThan(templateIndex));
        expect(countOccurrences(readme, 'git clone <this-repo>'), 0);
        expect(countOccurrences(gettingStarted, 'cd flutter_starter_kit'), 0);
        expect(countOccurrences(readme, _readmeStepSentence), 1);

        expect(countOccurrences(manual, _initialSetupHead), 1);
        expect(countOccurrences(manual, _initialSetupLegacyHead), 0);
      },
    );
  });
}
