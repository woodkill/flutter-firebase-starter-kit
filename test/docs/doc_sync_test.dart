// 사용자 문서 ↔ 저장소 대조 계약 — 문서가 말하는 경로 · 위저드 단계가 실제로 있다.
//
// 어디서 도는가: 경로 수집 · 판정 함수 표본(SYNC-04)은 어디서나 돈다. 문서별 경로
// 실재(SYNC-01) · 위저드 단계 제목(SYNC-02) · 이름 붙인 예외 목록 점검(SYNC-03)은 킷
// 사용자가 데모를 지우거나 자기 문서를 고치면 깨지는 내용 검사라, 비공개 작업 일지가
// 있는 유지보수자 트리에서만 돈다.
//
// T-21-SYNC-01: 두 가이드 · README 의 백틱 저장소 경로가 tracked 파일이거나 tracked
//   파일을 담은 디렉터리다. 자리표시 · 튜토리얼이 만드는 경로 · 이름 붙인 예외 ·
//   git 이 무시하는 경로는 뺀다. 두 가이드는 확인한 경로가 5개 이상이다.
// T-21-SYNC-02: 위저드 단계의 `stepTitle` 값(28개 이상)이 setup.md 「위저드 실행」 절에
//   모두 있다.
// T-21-SYNC-03: 이름 붙인 예외 경로는 저장소에 없고, 세 문서 가운데 어딘가에 나온다.
// T-21-SYNC-04: 경로 수집 · 판정 함수 표본.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/planning_docs.dart';
import '../helpers/source_text.dart';
import '../helpers/user_docs.dart';

/// 유지보수자 트리에서만 도는 내용 검사의 skip 값이다.
final Object _skipMaintainer = skipUnlessPlanningDocsExist(<String>[
  '.planning/ROADMAP.md',
]);

/// 위저드로 하는 일 가이드다.
const String _setupPath = 'docs/setup.md';

/// 직접 하는 일 가이드다.
const String _guidePath = 'docs/guide.md';

/// 저장소 첫 화면 문서다.
const String _readmePath = 'README.md';

/// 경로를 대조하는 문서다.
const List<String> _syncDocs = <String>[_setupPath, _guidePath, _readmePath];

/// 확인한 경로 하한을 두는 문서다 — README 는 문서로 가는 링크만 두고 백틱 저장소
/// 경로를 두지 않으므로 하한 밖이다(링크는 링크 시험이 본다).
const Set<String> _flooredDocs = <String>{_setupPath, _guidePath};

/// 하한을 두는 문서에서 확인한 경로의 최소 개수다 — 수집이 공허하지 않음을 본다.
const int _minCheckedPaths = 5;

/// 저장소 경로로 치는 백틱 span 의 머리다.
const List<String> _repoPathHeads = <String>[
  'lib/',
  'test/',
  'tool/',
  'scripts/',
  'functions/',
  'ios/',
  'android/',
  'config/',
  'assets/',
  'docs/',
  'bin/',
  'hosting/',
  'extensions/',
];

/// 자리표시로 치는 글자다 — 이 글자가 든 경로는 독자가 바꿔 쓰는 꼴이다.
const List<String> _placeholderMarks = <String>['<', '*', '{', r'$'];

/// 튜토리얼이 독자 저장소에 만드는 경로의 머리다.
const List<String> _tutorialPathPrefixes = <String>[
  'lib/features/memos/',
  'test/features/memos/',
  'functions/test/rules/memos',
];

/// 문서가 말하지만 킷 저장소에 없는 것이 맞는 경로다.
const Set<String> _namedAbsentPaths = <String>{
  // 사용자가 직접 두는 웹 표면 로고 — 킷 기본은 파일 없음이다.
  'hosting/public/logo.png',
  // 함수를 더하는 예시가 새 파일을 저장할 경로다.
  'functions/src/my_function.ts',
  // 알림 탭으로 열 화면을 만드는 예시의 경로다.
  'lib/features/notices/presentation/notices_screen.dart',
  // SPM 을 쓰는 킷에 없어야 하는 CocoaPods 파일이다.
  'ios/Podfile',
  // SPM 을 쓰는 킷에 없어야 하는 CocoaPods 잠금 파일이다.
  'ios/Podfile.lock',
};

/// 인라인 백틱 span 이다.
final RegExp _backtickSpan = RegExp(r'`([^`\n]+)`');

/// 경로 끝의 구두점이다.
final RegExp _trailingPunctuation = RegExp(r'[.,;:!?)\]]+$');

/// 경로 끝의 `:줄` · `:줄-줄` 꼬리다.
final RegExp _lineSuffix = RegExp(r':\d+(-\d+)?$');

/// 위저드 단계 소스 디렉터리다.
const String _stepsDir = 'tool/setup/steps';

/// 단계 제목 상수 선언(한 줄)이다.
final RegExp _stepTitleLine = RegExp(
  r"^\s*static const String stepTitle = '([^']*)';",
  multiLine: true,
);

/// 단계 제목 상수 선언의 머리다 — 한 줄 선언으로 읽지 못한 파일을 찾는 데 쓴다.
const String _stepTitleDeclaration = 'static const String stepTitle';

/// 위저드 단계 제목의 최소 개수다.
const int _minStepTitles = 28;

/// 문서에서 모은 저장소 경로 한 건 — 줄 번호(1부터)와 정규화한 경로다.
class _PathMention {
  _PathMention(this.line, this.path);

  /// 경로가 나온 줄 번호다.
  final int line;

  /// `:줄` 꼬리와 끝 구두점을 뗀 경로다.
  final String path;
}

/// 문서 경로의 판정 갈래다.
enum _PathKind {
  /// 자리표시가 든 경로다.
  placeholder,

  /// 튜토리얼이 만드는 경로다.
  tutorial,

  /// 이름 붙인 예외 경로다.
  namedAbsent,

  /// tracked 파일이거나 tracked 파일을 담은 디렉터리다.
  tracked,

  /// git 이 무시하는 경로다(사용자 파일 · 생성물).
  ignored,

  /// 어디에도 없는 경로다.
  missing,
}

/// [markdown] 의 인라인 백틱 span 가운데 저장소 경로 머리로 시작하는 것을 모은다.
///
/// 코드 펜스 안의 줄은 보지 않는다. 경로는 [_normalizePathSpan] 으로 정규화한다.
List<_PathMention> _collectRepoPathMentions(String markdown) {
  final mentions = <_PathMention>[];
  final List<String> lines = markdown.split('\n');
  var inFence = false;
  for (var i = 0; i < lines.length; i++) {
    final String line = lines[i];
    if (line.trimLeft().startsWith('```')) {
      inFence = !inFence;
      continue;
    }
    if (inFence) {
      continue;
    }
    for (final RegExpMatch match in _backtickSpan.allMatches(line)) {
      final String span = match.group(1)!.trim();
      if (_repoPathHeads.any(span.startsWith)) {
        mentions.add(_PathMention(i + 1, _normalizePathSpan(span)));
      }
    }
  }
  return mentions;
}

/// 백틱 span [span] 에서 끝 구두점과 `:줄` 꼬리를 뗀다.
String _normalizePathSpan(String span) => span
    .replaceFirst(_trailingPunctuation, '')
    .replaceFirst(_lineSuffix, '')
    .replaceFirst(_trailingPunctuation, '');

/// tracked 파일 [tracked] 를 담은 디렉터리 경로(끝 `/` 없음)를 모두 모은다.
Set<String> _collectTrackedDirs(Set<String> tracked) {
  final dirs = <String>{};
  for (final file in tracked) {
    var end = file.lastIndexOf('/');
    while (end > 0) {
      if (!dirs.add(file.substring(0, end))) {
        break;
      }
      end = file.lastIndexOf('/', end - 1);
    }
  }
  return dirs;
}

/// git 없이 정할 수 있는 갈래를 돌려준다 — 정하지 못하면 `null` 이다.
_PathKind? _classifyKnownPath(
  String path,
  Set<String> tracked,
  Set<String> trackedDirs,
) {
  if (_placeholderMarks.any(path.contains)) {
    return _PathKind.placeholder;
  }
  if (_tutorialPathPrefixes.any(
    (String prefix) => path.startsWith(prefix) || '$path/' == prefix,
  )) {
    return _PathKind.tutorial;
  }
  if (_namedAbsentPaths.contains(path)) {
    return _PathKind.namedAbsent;
  }
  final String bare = path.endsWith('/')
      ? path.substring(0, path.length - 1)
      : path;
  if (tracked.contains(bare) || trackedDirs.contains(bare)) {
    return _PathKind.tracked;
  }
  return null;
}

/// 경로 [paths] 를 판정 갈래로 나눈다(경로마다 하나).
///
/// 자리표시 → 튜토리얼 경로 → 이름 붙인 예외 → tracked 파일 · tracked 파일을 담은
/// 디렉터리 순으로 보고, 남은 경로는 [findIgnored] 가 돌려준 무시 경로면 무시,
/// 아니면 없음이다. 무시 판정은 문서에 쓴 그대로의 경로로 한다 — 끝 `/` 가 있어야
/// 디렉터리 규칙에 걸리는 경로가 있다.
Map<String, _PathKind> _classifyPaths(
  Iterable<String> paths, {
  required Set<String> tracked,
  required Set<String> Function(List<String> paths) findIgnored,
}) {
  final Set<String> trackedDirs = _collectTrackedDirs(tracked);
  final kinds = <String, _PathKind>{};
  final unresolved = <String>[];
  for (final String path in paths.toSet()) {
    final _PathKind? kind = _classifyKnownPath(path, tracked, trackedDirs);
    if (kind == null) {
      unresolved.add(path);
    } else {
      kinds[path] = kind;
    }
  }
  final Set<String> ignored = unresolved.isEmpty
      ? <String>{}
      : findIgnored(unresolved);
  for (final path in unresolved) {
    kinds[path] = ignored.contains(path)
        ? _PathKind.ignored
        : _PathKind.missing;
  }
  return kinds;
}

/// [paths] 가운데 git 이 무시하는 경로를 `git check-ignore` 한 번으로 돌려준다.
///
/// 출력은 한 줄에 경로 하나다. 한글 경로를 따옴표로 감싸지 않게 `core.quotePath` 를
/// 끈다 — 그래도 감싸는 경로(따옴표 · 줄바꿈 포함)는 일치하지 않아 없음으로 남는다.
Set<String> _findIgnoredByGit(List<String> paths) {
  final ProcessResult result = Process.runSync('git', <String>[
    '-c',
    'core.quotePath=false',
    'check-ignore',
    '--',
    ...paths,
  ], stdoutEncoding: utf8);
  // 종료 코드 0 = 무시 경로 있음 · 1 = 없음 · 그 밖은 오류다.
  if (result.exitCode > 1) {
    fail('git check-ignore 실패(${result.exitCode}): ${result.stderr}');
  }
  return (result.stdout as String)
      .split('\n')
      .where((String path) => path.isNotEmpty)
      .toSet();
}

/// tracked 파일 집합을 돌려준다 — git 을 쓸 수 없으면 시험을 실패시킨다.
Set<String> _requireTrackedFiles() {
  final Set<String>? tracked = listTrackedFiles();
  if (tracked == null) {
    fail('git ls-files 를 실행하지 못했다');
  }
  return tracked;
}

/// [kinds] 에서 갈래 [kind] 에 든 언급 수를 센다.
int _countMentions(
  List<_PathMention> mentions,
  Map<String, _PathKind> kinds,
  _PathKind kind,
) => mentions.where((_PathMention m) => kinds[m.path] == kind).length;

void main() {
  test('T-21-SYNC-04: 경로 수집 · 판정 함수 표본', () {
    final List<_PathMention> mentions = _collectRepoPathMentions(
      <String>[
        '`lib/a.dart:12` 와 `test/b/` 를 본다.',
        '`scripts/x.sh:3-9` · `docs/guide.md` · `fvm flutter test` · `ios/`.',
        '`lib/features/<기능>/` 는 바꿔 쓴다.',
        '```bash',
        'cat `lib/fence.dart`',
        '```',
        '`config/dev.json,`',
      ].join('\n'),
    );
    expect(
      mentions.map((_PathMention m) => '${m.line}:${m.path}').toList(),
      <String>[
        '1:lib/a.dart',
        '1:test/b/',
        '2:scripts/x.sh',
        '2:docs/guide.md',
        '2:ios/',
        '3:lib/features/<기능>/',
        '7:config/dev.json',
      ],
    );

    const tracked = <String>{
      'lib/a.dart',
      'test/b/c_test.dart',
      'docs/guide.md',
    };
    final Map<String, _PathKind> kinds = _classifyPaths(
      <String>[
        'lib/a.dart',
        'test/b/',
        'test/b',
        'lib/features/<기능>/',
        'lib/features/memos/data/memo.dart',
        'ios/Podfile',
        'config/dev.json',
        'lib/gone.dart',
        'lib/a',
      ],
      tracked: tracked,
      findIgnored: (List<String> paths) =>
          paths.where((String path) => path == 'config/dev.json').toSet(),
    );
    expect(kinds, <String, _PathKind>{
      'lib/a.dart': _PathKind.tracked,
      'test/b/': _PathKind.tracked,
      'test/b': _PathKind.tracked,
      'lib/features/<기능>/': _PathKind.placeholder,
      'lib/features/memos/data/memo.dart': _PathKind.tutorial,
      'ios/Podfile': _PathKind.namedAbsent,
      'config/dev.json': _PathKind.ignored,
      // 없는 경로를 잡는다 — 파일 이름의 앞부분은 디렉터리가 아니다.
      'lib/gone.dart': _PathKind.missing,
      'lib/a': _PathKind.missing,
    });
  });

  group('문서별 경로 실재', () {
    for (final path in _syncDocs) {
      test('T-21-SYNC-01: 문서의 저장소 경로가 실재한다 — $path', () {
        final Set<String> tracked = _requireTrackedFiles();
        final List<_PathMention> mentions = _collectRepoPathMentions(
          readTrackedFile(path),
        );
        final Map<String, _PathKind> kinds = _classifyPaths(
          mentions.map((_PathMention m) => m.path),
          tracked: tracked,
          findIgnored: _findIgnoredByGit,
        );
        final List<String> missing = mentions
            .where((_PathMention m) => kinds[m.path] == _PathKind.missing)
            .map((_PathMention m) => '$path:${m.line} → ${m.path}')
            .toList();
        final int checked = _countMentions(mentions, kinds, _PathKind.tracked);
        // 결과 한 줄 — 여러 파일을 함께 돌려도 시험 로그에 이 시험 이름이 남는다.
        debugPrintSynchronously(
          '문서 경로 $path: 수집 ${mentions.length} · 확인 $checked · '
          '자리표시 ${_countMentions(mentions, kinds, _PathKind.placeholder)} · '
          '튜토리얼 ${_countMentions(mentions, kinds, _PathKind.tutorial)} · '
          '예외 ${_countMentions(mentions, kinds, _PathKind.namedAbsent)} · '
          '무시 ${_countMentions(mentions, kinds, _PathKind.ignored)} · '
          '없음 ${missing.length}',
        );
        expect(missing, isEmpty, reason: '문서가 가리키는 저장소 경로가 없다(파일:줄 → 경로)');
        if (_flooredDocs.contains(path)) {
          expect(
            checked,
            greaterThanOrEqualTo(_minCheckedPaths),
            reason: '확인한 경로가 $_minCheckedPaths개보다 적다 — 수집이 공허하다',
          );
        }
      }, skip: _skipMaintainer);
    }
  });

  test('T-21-SYNC-02: 위저드 단계 제목이 setup.md 위저드 실행에 있다', () {
    final List<File> stepFiles =
        Directory(_stepsDir)
            .listSync()
            .whereType<File>()
            .where((File file) => file.path.endsWith('.dart'))
            .toList()
          ..sort((File a, File b) => a.path.compareTo(b.path));
    final titles = <String>[];
    final unreadable = <String>[];
    for (final file in stepFiles) {
      final String source = file.readAsStringSync();
      final List<String> found = _stepTitleLine
          .allMatches(source)
          .map((RegExpMatch match) => match.group(1)!)
          .toList();
      if (countOccurrences(source, _stepTitleDeclaration) != found.length) {
        unreadable.add(file.path);
      }
      titles.addAll(found);
    }
    expect(unreadable, isEmpty, reason: '한 줄 선언으로 읽지 못한 단계 제목이 있다');
    expect(titles.length, greaterThanOrEqualTo(_minStepTitles));

    final String section = sliceMarkdownSection(
      readTrackedFile(_setupPath),
      '## 위저드 실행',
      maxLevel: 2,
    );
    expect(section, isNotEmpty, reason: 'setup.md 에 「위저드 실행」 절이 없다');
    final List<String> absent = titles
        .where((String title) => !section.contains(title))
        .toList();
    // 결과 한 줄 — 여러 파일을 함께 돌려도 시험 로그에 이 시험 이름이 남는다.
    debugPrintSynchronously(
      '위저드 단계 제목: ${titles.length}개 · 위저드 실행 절에 없는 것 ${absent.length}개',
    );
    expect(absent, isEmpty, reason: 'setup.md 「위저드 실행」 에 없는 단계 제목이다');
  }, skip: _skipMaintainer);

  test('T-21-SYNC-03: 이름 붙인 예외 경로는 저장소에 없고 문서에 나온다', () {
    final Set<String> tracked = _requireTrackedFiles();
    final Set<String> trackedDirs = _collectTrackedDirs(tracked);
    final mentioned = <String>{
      for (final String path in _syncDocs)
        ..._collectRepoPathMentions(
          readTrackedFile(path),
        ).map((_PathMention m) => m.path),
    };
    final List<String> present = _namedAbsentPaths
        .where(
          (String path) => tracked.contains(path) || trackedDirs.contains(path),
        )
        .toList();
    final List<String> unmentioned = _namedAbsentPaths
        .where((String path) => !mentioned.contains(path))
        .toList();
    // 결과 한 줄 — 여러 파일을 함께 돌려도 시험 로그에 이 시험 이름이 남는다.
    debugPrintSynchronously(
      '이름 붙인 예외: ${_namedAbsentPaths.length}개 · 저장소에 있음 '
      '${present.length} · 문서에 없음 ${unmentioned.length}',
    );
    expect(present, isEmpty, reason: '저장소에 생긴 경로다 — 예외 목록에서 뺀다');
    expect(unmentioned, isEmpty, reason: '문서에서 사라진 경로다 — 예외 목록에서 뺀다');
  }, skip: _skipMaintainer);
}
