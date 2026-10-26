// 사용자 문서 링크 계약 — 상대 링크 · 이미지 경로 · 앵커 · 공개 제외 경로.
//
// 어디서 도는가: 앵커 규칙 표본(LINK-01) · 파일별 링크 무결성(LINK-02) · 경로 정규화
// 표본(LINK-04)은 어디서나 돈다 — 문서가 가리키는 파일 · 제목이 실제로 있는지는 킷
// 사용자 저장소에서도 지켜야 하는 성질이다. 공개 제외 경로 검사(LINK-03)는 그 목록
// 파일이 비공개 작업 일지 아래에 있어 유지보수자 트리에서만 돈다.
//
// T-21-LINK-01: GitHub 가 제목에 붙이는 앵커와 같은 앵커를 만들고, 같은 제목에는
//   `-1` · `-2` 를 붙이고, 코드 펜스 안의 `#` 줄은 제목으로 치지 않는다.
// T-21-LINK-02: 대상 md 마다 상대 링크 · 이미지 경로가 tracked 파일
//   (또는 tracked 파일이 든 디렉터리)을 가리키고, 앵커가 그 파일의 제목 앵커에 있다.
// T-21-LINK-03: 대상 md 의 링크가 공개 제외 경로(또는 그 아래)를 가리키지 않는다.
// T-21-LINK-04: 저장소 밖으로 나가는 상대 경로는 거르고, `.` · `..` · 퍼센트 인코딩을
//   푼다 · 링크 수집 표본.

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/markdown_anchor.dart';
import '../helpers/planning_docs.dart';
import '../helpers/source_text.dart';
import '../helpers/user_docs.dart';

/// 공개 mirror 에서 빼는 경로 목록 파일이다.
const String _excludePath = '.planning/release/mirror-exclude-paths.txt';

/// 유지보수자 트리에서만 도는 검사의 skip 값이다.
final Object _skipMaintainer = skipUnlessPlanningDocsExist(<String>[
  _excludePath,
]);

/// 제목 → GitHub 앵커 표본이다.
const Map<String, String> _anchorSamples = <String, String>{
  '정적 분석 — woody_lints · riverpod_lint': '정적-분석--woody_lints--riverpod_lint',
  '⑤ Android 빌드 도구 — 지금 값과 정상 출력': '-android-빌드-도구--지금-값과-정상-출력',
  '알림(APNs) · App Check': '알림apns--app-check',
  'stg · prod 설정': 'stg--prod-설정',
  'Git Hooks 활성화 (선택)': 'git-hooks-활성화-선택',
  '① 기본 방법 — `home_body.dart` 만 바꾼다': '-기본-방법--home_bodydart-만-바꾼다',
  '확인 방법': '확인-방법',
};

/// 공개 제외 목록 파일에서 주석 · 빈 줄을 뺀 경로 목록을 읽는다.
List<String> _readExcludedPaths() => readTrackedFile(_excludePath)
    .split('\n')
    .map((String line) => line.trim())
    .where((String line) => line.isNotEmpty && !line.startsWith('#'))
    .toList();

/// [path] 가 제외 경로 [excluded] 가운데 하나와 같거나 그 아래인지 돌려준다.
bool _isExcludedPath(String path, List<String> excluded) =>
    excluded.any((String entry) => path == entry || path.startsWith('$entry/'));

/// 저장소 루트 기준 [path] 가 파일이나 파일이 든 디렉터리로 있는지 돌려준다.
///
/// [tracked] 가 있으면 tracked 파일 집합으로 판단하고, 없으면(git 을 쓸 수 없음)
/// 파일 시스템 존재로 대신한다. 빈 경로는 저장소 루트다.
bool _existsInRepo(String path, Set<String>? tracked) {
  if (path.isEmpty) {
    return true;
  }
  if (tracked == null) {
    return File(path).existsSync() || Directory(path).existsSync();
  }
  return tracked.contains(path) ||
      tracked.any((String file) => file.startsWith('$path/'));
}

/// 링크 [target] 의 `#` 뒤 앵커를 퍼센트 디코드해 돌려준다 — 없으면 `null`.
String? _extractAnchor(String target) {
  final int hash = target.indexOf('#');
  if (hash == -1 || hash == target.length - 1) {
    return null;
  }
  final String raw = target.substring(hash + 1);
  return decodePercentEncoding(raw) ?? raw;
}

void main() {
  final List<String> docs = collectUserDocTargets()
      .where((String path) => path.endsWith('.md'))
      .toList();
  final Set<String>? tracked = listTrackedFiles();

  test('T-21-LINK-01: 앵커 = GitHub 규칙(표본 · 중복 접미)', () {
    for (final MapEntry<String, String> sample in _anchorSamples.entries) {
      expect(buildGithubAnchor(sample.key), sample.value, reason: sample.key);
    }
    expect(
      collectHeadingAnchors(
        <String>[
          '## 확인 방법',
          '본문',
          '### 확인 방법',
          '```bash',
          '# 펜스 안의 셸 주석',
          '```',
          '#### 확인 방법',
        ].join('\n'),
      ),
      <String>{'확인-방법', '확인-방법-1', '확인-방법-2'},
    );
  });

  group('파일별 링크', () {
    for (final path in docs) {
      test('T-21-LINK-02: 링크 · 앵커 — $path', () {
        final broken = <String>[];
        for (final MarkdownLink link in collectRelativeLinks(
          readTrackedFile(path),
        )) {
          final String? resolved = resolveRepoPath(path, link.target);
          if (resolved == null || !_existsInRepo(resolved, tracked)) {
            broken.add('$path:${link.line} → ${link.target}');
            continue;
          }
          final String? anchor = _extractAnchor(link.target);
          if (anchor == null || !resolved.endsWith('.md')) {
            continue;
          }
          if (!collectHeadingAnchors(
            readTrackedFile(resolved),
          ).contains(anchor)) {
            broken.add('$path:${link.line} → ${link.target}');
          }
        }
        // 결과 한 줄 — 여러 파일을 함께 돌려도 시험 로그에 이 시험 이름이 남는다.
        debugPrintSynchronously('링크 · 앵커 $path: 풀리지 않음 ${broken.length}건');
        expect(broken, isEmpty, reason: '풀리지 않는 링크 · 앵커가 있다');
      });
    }
  });

  test('T-21-LINK-03: 공개 제외 경로를 가리키는 링크 0', () {
    final List<String> excluded = _readExcludedPaths();
    // 양성 대조: 목록이 비공개 작업 일지를 담고, 판정 함수가 그 아래 경로를 잡는다.
    expect(excluded, contains('.planning'));
    expect(excluded.length, greaterThanOrEqualTo(5));
    final String? planningLink = resolveRepoPath(
      'docs/x.md',
      '../.planning/ROADMAP.md',
    );
    expect(planningLink, isNotNull);
    expect(_isExcludedPath(planningLink!, excluded), isTrue);

    final hits = <String>[];
    for (final path in docs) {
      for (final MarkdownLink link in collectRelativeLinks(
        readTrackedFile(path),
      )) {
        final String? resolved = resolveRepoPath(path, link.target);
        if (resolved != null && _isExcludedPath(resolved, excluded)) {
          hits.add('$path:${link.line} → ${link.target}');
        }
      }
    }
    expect(hits, isEmpty, reason: '공개본에서 사라지는 경로를 가리키는 링크가 있다');
  }, skip: _skipMaintainer);

  test('T-21-LINK-04: 저장소 밖으로 나가는 상대 경로는 거른다', () {
    expect(resolveRepoPath('README.md', '../../x.md'), isNull);
    expect(resolveRepoPath('docs/a.md', '../../x.md'), isNull);
    expect(resolveRepoPath('docs/a.md', './b/../c.md#x'), 'docs/c.md');
    expect(resolveRepoPath('docs/a.md', '#x'), 'docs/a.md');
    expect(resolveRepoPath('docs/a.md', 'my%20file.md'), 'docs/my file.md');
    expect(resolveRepoPath('docs/a.md', '../README.md'), 'README.md');
    // 인코딩하지 않은 한글과 퍼센트 인코딩이 섞인 경로 · 앵커도 푼다.
    expect(resolveRepoPath('docs/a.md', '설정%20안내.md'), 'docs/설정 안내.md');
    expect(resolveRepoPath('docs/a.md', '%ED%95%9C.md#x'), 'docs/한.md');
    expect(resolveRepoPath('docs/a.md', '%FF.md'), isNull);
    expect(decodePercentEncoding('처음-%EC%84%A4%EC%A0%95'), '처음-설정');
    expect(decodePercentEncoding('100%-완료'), '100%-완료');

    // 링크 수집: 스킴 링크 · 펜스 안 · 인라인 코드 안은 빼고, 제목 따옴표를 떼고,
    // 앵커만인 링크와 이미지 경로는 남긴다.
    final List<MarkdownLink> links = collectRelativeLinks(
      <String>[
        '[가이드](docs/guide.md#처음-설정 "제목") · [바깥](https://example.com/x)',
        '[위](#목차) · <img src="assets/a.png" width="20">',
        '```',
        '[펜스 안](docs/x.md)',
        '```',
        '`[코드 안](docs/y.md)` · [메일](mailto:x@example.com)',
      ].join('\n'),
    );
    expect(links, <MarkdownLink>[
      (line: 1, target: 'docs/guide.md#처음-설정'),
      (line: 2, target: '#목차'),
      (line: 2, target: 'assets/a.png'),
    ]);
  });
}
