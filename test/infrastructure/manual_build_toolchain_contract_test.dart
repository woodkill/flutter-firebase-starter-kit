// 매뉴얼 빌드 설비 안내 계약 (Phase 17.6 — see ROADMAP.md).
//
// 매뉴얼의 두 안내를 실제 설정 파일과 반복 실행 가능한 test 로 맞춰 본다.
// 「Flutter SDK 상향 (FVM)」 ⑤ (Android 빌드 도구 — 지금 값과 정상 출력)와
// 「iOS 의존성 관리 (SPM)」 ② (네이티브 SDK 버전 · LINE 경고 박스)다. 이전에는
// 플랜 verify 의 shell grep 한 번과 리뷰 수정 세션의 일회성 확인뿐이라, 표의 값이
// 파일과 어긋나거나 단언 포인터가 끊겨도 아무 test 도 red 가 되지 않았다. 각 슬라이스는
// 양성 대조(비어 있지 않고 자기 헤딩을 담는다 · 파싱한 행 수)를 함께 세워 빈 슬라이스나
// 파싱 실패가 공허하게 통과하지 못하게 한다. 값은 설정 파일에서 읽어 매뉴얼과
// 견준다 — 도구 버전 숫자는 이 파일에 적지 않는다.
//
// T-176-DOCS-01: ⑤ 슬라이스가 비어 있지 않고 금지 패턴 0.
// T-176-DOCS-02: ⑤ 「지금 값」 표의 각 행이 그 행이 가리키는 파일의 값과 같다.
// T-176-DOCS-03: ⑤ 「지우지 말 것」 표의 각 줄이 그 행의 파일에 정확히 1줄 있다.
// T-176-DOCS-04: ⑤ 가 인용한 계약 test 경로 · test ID 가 실재하고(포인터 무결성 ·
//   T-172-DOCS-06 과 같은 방식), ⑤ 가 그 test 로 가리키는 세 단언의 키가 그 test
//   본문에 있다 — `id("kotlin-android")` 부재는 T-176-ANDROID-02,
//   `android.builtInKotlin=` · `android.newDsl=` 는 T-176-ANDROID-03. 키는 이
//   파일에 적은 상수이고 매뉴얼의 백틱 글자와는 견주지 않는다.
// T-176-DOCS-05: SPM ② LINE 경고 박스가 위 표와 내부적으로 맞다(SDK 개수 · 이름).
// T-176-DOCS-06: LINE 값(`flutter_line_sdk` 버전 · 핀 버전)이 pubspec ·
//   Package.resolved 와 같다.
//
// 어디서 도는가: 매뉴얼은 킷의 문서라 킷의 값을 적는다. 킷 사용자가 매뉴얼 자신의
// 절차(Flutter 상향 뒤 Gradle · AGP · KGP 올리기, ⑤ 의 「새 DSL 켜기」, SPM ② 의
// 「상향 절차」 핀 올리기, `flutter_line_sdk` 올리기)를
// 따르면 자기 저장소에서 그 값이 바뀐다. 그래서 값 동일성을 보는 T-176-DOCS-02 ·
// 03 · 06 은 비공개 작업 일지(`.planning/`)가 있는 유지보수자 트리에서만 돈다
// (공개 mirror 에서는 건너뜀). 04(포인터 무결성 · 키 확인)와 문서 내부 일관성
// (01 · 05)은 사용자 저장소에서도 참이므로 어디서나 돈다.
//
// 킷 사용자 안전 규칙(매뉴얼 절차가 이 파일과 계약 test 를 깨뜨리지 않게):
// - 도구 버전 · LINE 버전 숫자를 리터럴로 두지 않는다. 값은 파일에서 읽는다.
// - 04 는 세 키가 계약 test 본문에 있는지만 본다. `android.builtInKotlin=` ·
//   `android.newDsl=` 뒤의 값과 `id("kotlin-android")` 를 세는 단언의 기대값은
//   보지 않는다 — 사용자가 매뉴얼 안내대로 `android.newDsl` 을 `true` 로 고쳐도
//   red 가 되지 않는다.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../helpers/planning_docs.dart';
import '../helpers/source_text.dart';

/// 매뉴얼 경로.
const String _manualPath = 'docs/manual.md';

/// ⑤ 가 인용하는 Android 빌드 설비 계약 test 경로.
const String _contractTestPath =
    'test/infrastructure/android_build_toolchain_contract_test.dart';

/// iOS 워크스페이스 `Package.resolved` 경로(빌드가 존중하는 쪽).
const String _packageResolvedPath =
    'ios/Runner.xcworkspace/xcshareddata/swiftpm/Package.resolved';

/// pubspec 경로.
const String _pubspecPath = 'pubspec.yaml';

/// Android 빌드 도구 절(⑤) 헤딩.
const String _androidHeading = '### ⑤ Android 빌드 도구 — 지금 값과 정상 출력';

/// SPM 네이티브 SDK 절(②) 헤딩.
const String _spmHeading = '### ② 네이티브 SDK 버전은 어디에 고정돼 있나';

/// ⑤ 「지금 값」 표 바로 위 굵은 줄 — 표 머리글에 Flutter 버전이 있어 이 줄로 찾는다.
const String _currentValuesLabel = '**지금 값**';

/// ⑤ 「지우지 말 것」 표 머리글.
const String _keepTableHeader = '| 줄 | 파일 | 이유 |';

/// SPM ② 핀 표 머리글.
const String _pinTableHeader = '| Swift package identity | 고정 버전 | 비고 |';

/// SPM ② LINE 경고 박스 첫 줄의 시작.
const String _warningBoxStart = '> ⚠ **`Package.resolved` 를 지우지 말고';

/// LINE SDK 핀의 Swift package identity.
const String _lineIdentity = 'line-sdk-ios-swift';

/// 매뉴얼 변경 이력 헤딩 — 이 앞이 본문이다.
const String _changelogHeading = '## 변경 이력';

/// 마크다운 표 행 [row] 의 칸을 앞뒤 공백을 걷어 돌려준다.
List<String> _splitCells(String row) {
  final List<String> parts = row.split('|');
  return parts
      .sublist(1, parts.length - 1)
      .map((String cell) => cell.trim())
      .toList();
}

/// 표 줄 목록 [table] 에서 머리글 · 구분선을 뺀 데이터 행의 칸 목록을 돌려준다.
List<List<String>> _collectDataRows(List<String> table) =>
    table.skip(2).map(_splitCells).toList();

/// [text] 의 백틱 조각 안쪽 문자열을 순서대로 모은다.
List<String> _collectBackticked(String text) => RegExp(
  '`([^`]+)`',
).allMatches(text).map((RegExpMatch m) => m.group(1)!).toList();

/// 앞뒤 공백을 걷어낸 줄이 [line] 과 정확히 같은 줄의 수를 센다.
int _countTrimmedLines(String source, String line) => source
    .split('\n')
    .where((String candidate) => candidate.trim() == line)
    .length;

/// [source] 에서 [id] 를 첫 인자로 선언한 `test(` 의 시작 위치를 돌려준다. 없으면 -1.
int _findTestDeclaration(String source, String id) {
  final RegExpMatch? match = RegExp(
    "\\btest\\(\\s*['\"]${RegExp.escape(id)}[:\\s(]",
  ).firstMatch(source);
  return match?.start ?? -1;
}

/// [id] 선언부터 다음 `test(` 선언 직전(없으면 끝)까지의 본문을 돌려준다.
String _sliceTestBody(String source, String id) {
  final int start = _findTestDeclaration(source, id);
  if (start == -1) {
    return '';
  }
  final RegExpMatch? next = RegExp(
    "\\btest\\(\\s*['\"]",
  ).allMatches(source).where((RegExpMatch m) => m.start > start).firstOrNull;
  return next == null
      ? source.substring(start)
      : source.substring(start, next.start);
}

/// 인용문 [text] 에서 `T-176-ANDROID-NN` 형태의 test ID 집합을 모은다.
Set<String> _collectAndroidTestIds(String text) => RegExp(
  r'T-176-ANDROID-\d{2}',
).allMatches(text).map((RegExpMatch m) => m.group(0)!).toSet();

/// SPM ② 슬라이스 [spmSection] 에서 LINE 경고 박스를 인용 표시(`> `)를 걷어
/// 돌려준다.
///
/// 박스는 [_warningBoxStart] 로 시작하는 줄부터 `>` 로 이어지는 줄까지다. 시작
/// 줄이 없으면 빈 문자열을 돌려준다(호출자가 「비어 있지 않음」 양성 대조를 세운다).
String _sliceWarningBox(String spmSection) {
  final List<String> lines = spmSection.split('\n');
  final int start = lines.indexWhere(
    (String l) => l.startsWith(_warningBoxStart),
  );
  if (start == -1) {
    return '';
  }
  final boxLines = <String>[];
  for (var i = start; i < lines.length && lines[i].startsWith('>'); i++) {
    boxLines.add(lines[i].replaceFirst(RegExp('^> ?'), ''));
  }
  return boxLines.join('\n');
}

/// [text] 에서 사용자 문서 금지 패턴에 걸린 조각을 순서대로 모은다.
List<String> _collectForbiddenHits(String text) => RegExp(
  kUserDocForbiddenPatternSource,
).allMatches(text).map((RegExpMatch m) => m.group(0)!).toList();

void main() {
  final String manual = readTrackedFile(_manualPath);
  final String androidSection = sliceMarkdownSection(
    manual,
    _androidHeading,
    maxLevel: 3,
  );
  final String spmSection = sliceMarkdownSection(
    manual,
    _spmHeading,
    maxLevel: 3,
  );

  group('매뉴얼 빌드 설비 안내 계약 (T-176-DOCS)', () {
    test('T-176-DOCS-01: ⑤ 슬라이스가 비어 있지 않고 금지 패턴이 0 이다', () {
      expect(
        countExactLines(manual, _androidHeading),
        1,
        reason:
            '매뉴얼에 「$_androidHeading」 헤딩이 정확히 1개여야 한다 — 이름을 '
            '바꿨다면 이 파일의 _androidHeading 도 함께 고친다',
      );
      expect(
        androidSection,
        isNotEmpty,
        reason: '⑤ 를 자르지 못했다 — 헤딩 줄 뒤에 줄바꿈이 있어야 한다',
      );
      expect(
        androidSection.startsWith(_androidHeading),
        isTrue,
        reason: '슬라이스가 ⑤ 헤딩으로 시작하지 않는다(양성 대조)',
      );

      final List<String> hits = _collectForbiddenHits(androidSection);
      expect(
        hits,
        isEmpty,
        reason:
            '매뉴얼 ⑤ 에 사용자 문서 금지 패턴이 있다 — 작업 이력 · 내부 식별자를 '
            '현재형 설명으로 바꾼다(.claude/rules/docs-user-manual.md): $hits',
      );
    });

    test(
      'T-176-DOCS-02: ⑤ 지금 값 표의 각 행이 가리키는 파일의 값과 같다',
      () {
        final List<String> lines = androidSection.split('\n');
        final int label = lines.indexOf(_currentValuesLabel);
        expect(label, isNot(-1), reason: '⑤ 에 「$_currentValuesLabel」 줄이 없다');
        final int headerIndex = lines.indexWhere(
          (String l) => l.startsWith('|'),
          label,
        );
        expect(
          headerIndex,
          isNot(-1),
          reason: '「$_currentValuesLabel」 뒤에 표가 없다',
        );
        final table = <String>[];
        for (
          var i = headerIndex;
          i < lines.length && lines[i].startsWith('|');
          i++
        ) {
          table.add(lines[i]);
        }
        final List<List<String>> rows = _collectDataRows(table);

        var wrapperRows = 0;
        var pluginRows = 0;
        for (final cells in rows) {
          final String kitValue = cells[1].replaceAll('`', '');
          final List<String> pointer = _collectBackticked(cells[2]);
          expect(
            pointer.length,
            2,
            reason:
                '⑤ 「어디에 있나」 칸은 `파일 경로` 와 `키` 두 조각을 백틱으로 적어야 '
                '한다: ${cells[2]}',
          );
          final String path = pointer[0];
          final String key = pointer[1];
          final String source = readTrackedFile(path);

          final String actual;
          if (key == 'distributionUrl') {
            wrapperRows++;
            final List<String> urlLines = source
                .split('\n')
                .where((String l) => l.startsWith('$key='))
                .toList();
            expect(
              urlLines,
              hasLength(1),
              reason: '$path 에 `$key=` 줄이 정확히 1개여야 한다',
            );
            actual =
                RegExp(
                  r'gradle-(.+?)-(?:all|bin)\.zip',
                ).firstMatch(urlLines.single)?.group(1) ??
                '';
          } else {
            pluginRows++;
            final String code = stripBlockComments(stripSlashComments(source));
            actual =
                RegExp(
                  '${RegExp.escape(key)}\\s+version\\s+"([^"]+)"',
                ).firstMatch(code)?.group(1) ??
                '';
          }

          expect(
            actual,
            isNotEmpty,
            reason:
                '⑤ 「${cells[0]}」 행이 가리키는 $path 의 `$key` 에서 버전을 '
                '읽지 못했다',
          );
          expect(
            kitValue,
            actual,
            reason:
                '⑤ 지금 값 표의 「${cells[0]}」 킷 값이 $path 의 `$key` 값과 '
                '다르다 — 표를 파일에 맞춘다',
          );
        }

        expect(
          wrapperRows,
          greaterThanOrEqualTo(1),
          reason: 'Gradle(distributionUrl) 행을 파싱하지 못했다',
        );
        expect(
          pluginRows,
          greaterThanOrEqualTo(4),
          reason:
              'settings 플러그인 행(AGP · KGP · google-services · '
              'Crashlytics) 4개를 파싱하지 못했다',
        );
      },
      // 사용자는 Gradle · AGP · KGP 를 올리는 것이 정상 절차라 값이 바뀐다 — 킷의 값을
      // 적은 표이므로 유지보수자 트리에서만 돈다.
      skip: skipUnlessPlanningDocsExist(const <String>['.planning/ROADMAP.md']),
    );

    test(
      'T-176-DOCS-03: ⑤ 지우지 말 것 표의 각 줄이 그 파일에 정확히 1줄 있다',
      () {
        final List<List<String>> rows = _collectDataRows(
          collectTableLines(androidSection, _keepTableHeader),
        );
        expect(rows, isNotEmpty, reason: '⑤ 에서 「$_keepTableHeader」 표를 찾지 못했다');

        final files = <String>{};
        for (final cells in rows) {
          final List<String> quoted = _collectBackticked(cells[0]);
          expect(
            quoted,
            hasLength(1),
            reason: '⑤ 「줄」 칸은 지킬 줄 하나를 백틱으로 감싸 적어야 한다: ${cells[0]}',
          );
          final String line = quoted.single;
          final String path = cells[1].replaceAll('`', '');
          files.add(path);
          final String raw = readTrackedFile(path);
          final String source = path.endsWith('.kts')
              ? stripBlockComments(stripSlashComments(raw))
              : raw;

          expect(
            _countTrimmedLines(source, line),
            1,
            reason:
                '⑤ 「지우지 말 것」 표의 `$line` 이 $path 에 정확히 1줄이어야 한다 '
                '— 파일 줄이 바뀌었다면 표를 고치고, 지워졌다면 되살린다',
          );
        }

        expect(
          files,
          containsAll(const <String>[
            'android/gradle.properties',
            'android/settings.gradle.kts',
            'android/app/build.gradle.kts',
          ]),
          reason: '⑤ 「지우지 말 것」 표가 세 파일을 모두 다뤄야 한다: $files',
        );
      },
      // 사용자는 「내장 Kotlin 켜기」 · 「새 DSL 켜기」 로 이 줄들을 바꾸는 것이 정상
      // 절차다 — 킷의 줄을 적은 표이므로 유지보수자 트리에서만 돈다.
      skip: skipUnlessPlanningDocsExist(const <String>['.planning/ROADMAP.md']),
    );

    test('T-176-DOCS-04: ⑤ 가 인용한 계약 test 경로 · ID 가 실재하고 세 키가 그 본문에 있다', () {
      expect(
        androidSection,
        contains(_contractTestPath),
        reason: '⑤ 「남은 두 단계」 가 계약 test 경로 $_contractTestPath 를 인용해야 한다',
      );
      expect(
        File(_contractTestPath).existsSync(),
        isTrue,
        reason: '⑤ 가 인용한 계약 test 파일이 없다: $_contractTestPath',
      );

      // 주석 처리한 test 는 선언이 아니다 — 행 주석을 걷어낸 뒤 찾는다.
      final String source = stripSlashComments(
        readTrackedFile(_contractTestPath),
      );
      final Set<String> cited = _collectAndroidTestIds(androidSection);
      expect(
        cited,
        containsAll(<String>['T-176-ANDROID-02', 'T-176-ANDROID-03']),
        reason: '⑤ 에서 계약 test ID 추출이 실패했다: $cited',
      );

      for (final id in cited) {
        expect(
          _findTestDeclaration(source, id),
          isNot(-1),
          reason:
              '⑤ 가 인용한 `$id` 가 $_contractTestPath 의 test 이름으로 선언돼 '
              '있지 않다 — ID 를 고치거나 test 를 되살린다',
        );
      }

      final String body02 = _sliceTestBody(source, 'T-176-ANDROID-02');
      expect(
        body02,
        contains('id("kotlin-android")'),
        reason:
            '⑤ 가 T-176-ANDROID-02 로 가리키는 `id("kotlin-android")` 부재 '
            '단언이 그 test 본문에 없다',
      );
      final String body03 = _sliceTestBody(source, 'T-176-ANDROID-03');
      for (final key in <String>['android.builtInKotlin=', 'android.newDsl=']) {
        expect(
          body03,
          contains(key),
          reason:
              '⑤ 가 T-176-ANDROID-03 에서 고치라고 안내하는 `$key` 단언이 그 test '
              '본문에 없다',
        );
      }
    });

    test('T-176-DOCS-05: SPM ② LINE 경고 박스가 핀 표와 내부적으로 맞다', () {
      expect(
        countExactLines(manual, _spmHeading),
        1,
        reason: '매뉴얼에 「$_spmHeading」 헤딩이 정확히 1개여야 한다',
      );
      expect(
        spmSection.startsWith(_spmHeading),
        isTrue,
        reason: 'SPM ② 슬라이스가 비었거나 헤딩으로 시작하지 않는다(양성 대조)',
      );

      final String box = _sliceWarningBox(spmSection);
      expect(box, isNotEmpty, reason: 'SPM ② 에 「$_warningBoxStart…」 경고 박스가 없다');
      final List<String> hits = _collectForbiddenHits(box);
      expect(
        hits,
        isEmpty,
        reason:
            'SPM ② 경고 박스에 사용자 문서 금지 패턴이 있다 — 현재형 설명으로 '
            '바꾼다(.claude/rules/docs-user-manual.md): $hits',
      );

      final List<List<String>> rows = _collectDataRows(
        collectTableLines(spmSection, _pinTableHeader),
      );
      expect(rows, isNotEmpty, reason: 'SPM ② 에서 핀 표를 찾지 못했다');
      final Set<String> tableIdentities = rows
          .map((List<String> cells) => cells[0].replaceAll('`', ''))
          .toSet();
      expect(
        tableIdentities.length,
        rows.length,
        reason: '핀 표의 identity 가 중복이다',
      );

      final RegExpMatch? count = RegExp(r'위 표의 SDK (\d+)개').firstMatch(box);
      expect(count, isNotNull, reason: '경고 박스에 「위 표의 SDK N개」 문구가 없다');
      expect(
        int.parse(count!.group(1)!),
        rows.length,
        reason:
            '경고 박스의 「위 표의 SDK N개」 가 핀 표 행 수(${rows.length})와 다르다 '
            '— 박스를 표에 맞춘다',
      );

      // 박스의 백틱 조각 가운데 Swift package identity 꼴(`-ios` · `-sdk` 포함)만
      // 고른다 — 파일 이름 · 선언 방식(`exact`) · pub 패키지 이름
      // (`flutter_line_sdk` — 밑줄)은 identity 가 아니다.
      final Set<String> boxIdentities = _collectBackticked(
        box,
      ).where((String t) => t.contains('-ios') || t.contains('-sdk')).toSet();
      expect(
        boxIdentities,
        tableIdentities,
        reason:
            '경고 박스가 이름으로 든 SDK 와 핀 표의 identity 가 같아야 한다 '
            '— 박스: $boxIdentities · 표: $tableIdentities',
      );
    });

    test(
      'T-176-DOCS-06: LINE 버전이 pubspec · Package.resolved 와 같다',
      () {
        final int changelogIndex = manual.indexOf('\n$_changelogHeading\n');
        expect(
          changelogIndex,
          isNot(-1),
          reason: '매뉴얼에 「$_changelogHeading」 헤딩이 없어 본문 범위를 정하지 못했다',
        );
        final String body = manual.substring(0, changelogIndex);
        final String pubspec = stripHashComments(readTrackedFile(_pubspecPath));
        final String? pubspecVersion = RegExp(
          r'^  flutter_line_sdk: (\S+)\s*$',
          multiLine: true,
        ).firstMatch(pubspec)?.group(1);
        expect(
          pubspecVersion,
          isNotNull,
          reason: '$_pubspecPath 에서 flutter_line_sdk 버전 줄을 읽지 못했다',
        );
        expect(
          pubspecVersion,
          isNot(contains('^')),
          reason:
              '$_pubspecPath 의 flutter_line_sdk 는 정확 고정(캐럿 없음)이어야 '
              '한다 — 매뉴얼 SPM ② 의 핀 설명이 이 전제를 쓴다',
        );

        final List<RegExpMatch> pluginMentions = RegExp(
          r'`flutter_line_sdk` (\d+\.\d+\.\d+)',
        ).allMatches(body).toList();
        expect(
          pluginMentions.length,
          greaterThanOrEqualTo(3),
          reason:
              '매뉴얼 본문에서 「`flutter_line_sdk` X.Y.Z」 인용을 3곳 이상 찾지 '
              '못했다',
        );
        for (final mention in pluginMentions) {
          expect(
            mention.group(1),
            pubspecVersion,
            reason:
                '매뉴얼의 「${mention.group(0)}」 가 $_pubspecPath 의 '
                'flutter_line_sdk 버전($pubspecVersion)과 다르다',
          );
        }

        // 경고 박스와 표의 LINE 행 양쪽에 인용이 있어야 한다(양성 대조).
        final String box = _sliceWarningBox(spmSection);
        expect(
          box,
          isNotEmpty,
          reason: 'SPM ② 에 「$_warningBoxStart…」 경고 박스가 없다',
        );
        final List<List<String>> lineRows =
            _collectDataRows(collectTableLines(spmSection, _pinTableHeader))
                .where(
                  (List<String> cells) =>
                      cells[0].replaceAll('`', '') == _lineIdentity,
                )
                .toList();
        expect(
          lineRows,
          hasLength(1),
          reason: 'SPM ② 핀 표에 `$_lineIdentity` 행이 정확히 1개여야 한다',
        );
        final List<String> lineRow = lineRows.single;
        final pluginMention = RegExp(r'`flutter_line_sdk` \d');
        expect(
          pluginMention.hasMatch(box),
          isTrue,
          reason: '경고 박스에 `flutter_line_sdk` 버전 인용이 없다',
        );
        expect(
          pluginMention.hasMatch(lineRow.join(' | ')),
          isTrue,
          reason: '핀 표 `$_lineIdentity` 행에 `flutter_line_sdk` 버전 인용이 없다',
        );

        final resolved =
            jsonDecode(readTrackedFile(_packageResolvedPath))
                as Map<String, Object?>;
        final List<Map<String, Object?>> linePins =
            (resolved['pins']! as List<Object?>)
                .cast<Map<String, Object?>>()
                .where(
                  (Map<String, Object?> p) => p['identity'] == _lineIdentity,
                )
                .toList();
        expect(
          linePins,
          hasLength(1),
          reason: '$_packageResolvedPath 에 $_lineIdentity 핀이 정확히 1개여야 한다',
        );
        final pinVersion =
            (linePins.single['state']! as Map<String, Object?>)['version']!
                as String;
        expect(
          pinVersion,
          isNotEmpty,
          reason: '$_packageResolvedPath 에서 $_lineIdentity 의 version 을 읽지 못했다',
        );

        final List<String> boldPins = RegExp(
          r'\*\*(\d+\.\d+\.\d+)\*\*',
        ).allMatches(box).map((RegExpMatch m) => m.group(1)!).toList();
        expect(
          boldPins,
          isNotEmpty,
          reason: '경고 박스에서 굵은 핀 버전 **X.Y.Z** 를 찾지 못했다',
        );
        for (final boldPin in boldPins) {
          expect(
            boldPin,
            pinVersion,
            reason:
                '경고 박스의 핀 **$boldPin** 이 $_packageResolvedPath 의 '
                '$_lineIdentity 핀($pinVersion)과 다르다',
          );
        }
        expect(
          lineRow[1].replaceAll('*', ''),
          pinVersion,
          reason:
              '핀 표 `$_lineIdentity` 행의 고정 버전이 $_packageResolvedPath 의 '
              '핀($pinVersion)과 다르다',
        );
      },
      // 사용자는 flutter_line_sdk 를 올리거나 LINE 핀을 올리는 것이 정상 절차다
      // (SPM ② 「상향 절차」) — 킷의 값을 적은 안내이므로 유지보수자 트리에서만 돈다.
      skip: skipUnlessPlanningDocsExist(const <String>['.planning/ROADMAP.md']),
    );
  });
}
