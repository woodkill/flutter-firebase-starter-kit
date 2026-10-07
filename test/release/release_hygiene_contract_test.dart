// 킷 릴리스 형상 계약을 고정한다 — 공개 문서 위생, Ruleset · gitleaks 설정 (Phase 17.4
// D-03 ~ D-06 · 17.4-04 — see ROADMAP.md).
//
// 데스크톱 · 웹 폴더 부재(D-02)는 여기서 잠그지 않는다 — `flutter create .` 재실행으로
// 되살아나는 경우는 가드 없이 유지보수자 문서 안내로 받아들인 위험이다.
//
// 전부 유지보수자 트리 전용이다. 공개 mirror 에는 `.planning/` 이 없으므로 건너뛴다
// (D-08 skip 형).

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../helpers/planning_docs.dart';
import '../helpers/source_text.dart';

const String _excludePath = '.planning/release/mirror-exclude-paths.txt';
final Object _skipPublic = skipUnlessPlanningDocsExist(<String>[_excludePath]);

/// `git ls-files` 결과를 줄 목록으로 돌려준다.
List<String> _lsFiles(List<String> args) {
  final ProcessResult result = Process.runSync('git', <String>[
    'ls-files',
    ...args,
  ]);
  expect(result.exitCode, 0, reason: '${result.stderr}');
  return (result.stdout as String)
      .split('\n')
      .where((String line) => line.isNotEmpty)
      .toList();
}

/// 제외 경로 파일에서 주석 · 빈 줄을 뺀 경로 목록을 읽는다.
List<String> _readExcludedPaths() => readTrackedFile(_excludePath)
    .split('\n')
    .map((String line) => line.trim())
    .where((String line) => line.isNotEmpty && !line.startsWith('#'))
    .toList();

/// [path] 가 제외 경로 [excluded] 중 하나이거나 그 아래인지(literal prefix) 돌려준다.
bool _isExcluded(String path, List<String> excluded) => excluded.any(
  (String prefix) => path == prefix || path.startsWith('$prefix/'),
);

/// 마크다운 링크 대상에 `.planning/` 이 든 패턴 — 인라인 링크 `](…)` 와 참조식 링크
/// 정의 줄 `[label]: <대상>`(앞 공백 0~3칸) 둘 다 본다. 정의 줄은 대상 토큰(공백 전까지)만
/// 보므로 뒤따르는 제목 문자열의 `.planning/` 은 잡지 않는다(IN-10).
final RegExp _planningLink = RegExp(
  r'\]\([^)\n]*\.planning/[^)\n]*\)|^ {0,3}\[[^\]\n]+\]:[ \t]*\S*\.planning/',
  multiLine: true,
);

Map<String, dynamic> _readJson(String path) =>
    jsonDecode(readTrackedFile(path)) as Map<String, dynamic>;

List<String> _ruleTypes(Map<String, dynamic> ruleset) =>
    (ruleset['rules'] as List<dynamic>)
        .map((dynamic rule) => (rule as Map<String, dynamic>)['type'] as String)
        .toList()
      ..sort();

List<String> _includes(Map<String, dynamic> ruleset) =>
    (((ruleset['conditions'] as Map<String, dynamic>)['ref_name']
                as Map<String, dynamic>)['include']
            as List<dynamic>)
        .cast<String>();

void main() {
  group('공개 문서 위생 (D-03 ~ D-06)', () {
    test('T-174-HYG-02: 공개 대상 *.md 에 .planning/ 링크 대상이 0건 (양성 대조 포함)', () {
      expect(_planningLink.hasMatch('[x](../.planning/a.md)'), isTrue);
      expect(_planningLink.hasMatch('[x](docs/a.md) `.planning/` 설명'), isFalse);
      expect(_planningLink.hasMatch('본문\n[spec]: .planning/a.md\n'), isTrue);
      expect(_planningLink.hasMatch('  [spec]: <../.planning/a.md>'), isTrue);
      expect(
        _planningLink.hasMatch('[spec]: docs/a.md ".planning/ 설명"'),
        isFalse,
      );
      expect(_planningLink.hasMatch('본문 [spec]: .planning/a.md'), isFalse);

      final List<String> excluded = _readExcludedPaths();
      expect(excluded, isNotEmpty);
      final List<String> all = _lsFiles(<String>['*.md']);
      final List<String> published = all
          .where((String p) => !_isExcluded(p, excluded))
          .toList();
      expect(published, isNotEmpty);
      expect(
        published.length,
        lessThan(all.length),
        reason: '제외 경로가 실제로 걸러낸 파일이 있어야 한다(양성 대조)',
      );

      final List<String> offenders = <String>[];
      for (final String path in published) {
        final File file = File(path);
        if (!file.existsSync()) {
          continue;
        }
        final String text = utf8.decode(
          file.readAsBytesSync(),
          allowMalformed: true,
        );
        if (_planningLink.hasMatch(text)) {
          offenders.add(path);
        }
      }
      expect(offenders, isEmpty, reason: '.planning/ 링크가 공개 문서에 있다');
    }, skip: _skipPublic);

    test(
      'T-174-HYG-03: project.md 가 ## Project 를 갖고 CLAUDE.md 는 갖지 않으며 PRD 는 없다',
      () {
        final List<String> rules = readTrackedFile(
          '.claude/rules/project.md',
        ).split('\n');
        expect(rules, contains('## Project'));
        final List<String> claude = readTrackedFile('CLAUDE.md').split('\n');
        expect(claude.where((String l) => l == '## Project'), isEmpty);
        expect(File('STARTER_KIT_PRD.md').existsSync(), isFalse);
      },
      skip: _skipPublic,
    );
  });

  group('릴리스 설정 계약 (17.4-04 · 17.4-07)', () {
    test(
      'T-174-HYG-04: main Ruleset — active · bypass 0 · refs/heads/main · deletion + non_fast_forward',
      () {
        final Map<String, dynamic> ruleset = _readJson(
          'scripts/github/ruleset-main.json',
        );
        expect(ruleset['target'], 'branch');
        expect(ruleset['enforcement'], 'active');
        expect(ruleset['bypass_actors'], isEmpty);
        expect(_includes(ruleset), <String>['refs/heads/main']);
        expect(_ruleTypes(ruleset), <String>['deletion', 'non_fast_forward']);
      },
      skip: _skipPublic,
    );

    test(
      'T-174-HYG-05: tag Ruleset — active · bypass 0 · refs/tags/v* · update 는 fetch-merge 불허',
      () {
        final Map<String, dynamic> ruleset = _readJson(
          'scripts/github/ruleset-tags.json',
        );
        expect(ruleset['target'], 'tag');
        expect(ruleset['enforcement'], 'active');
        expect(ruleset['bypass_actors'], isEmpty);
        expect(_includes(ruleset), <String>['refs/tags/v*']);
        expect(_ruleTypes(ruleset), <String>[
          'deletion',
          'non_fast_forward',
          'update',
        ]);
        final Map<String, dynamic> update =
            (ruleset['rules'] as List<dynamic>)
                    .cast<Map<String, dynamic>>()
                    .firstWhere(
                      (Map<String, dynamic> r) => r['type'] == 'update',
                    )['parameters']
                as Map<String, dynamic>;
        expect(update['update_allows_fetch_and_merge'], isFalse);
      },
      skip: _skipPublic,
    );

    test(
      'T-174-HYG-06: gitleaks — 기본 규칙 확장 · 허용 목록 1개 · Podfile.lock 의 generic-api-key 만',
      () {
        final List<String> lines = readTrackedFile('.gitleaks.toml')
            .split('\n')
            .where((String l) => !l.trimLeft().startsWith('#'))
            .toList();
        final int extend = lines.indexOf('[extend]');
        expect(extend, greaterThanOrEqualTo(0));
        expect(
          lines.sublist(extend + 1).first.trim(),
          'useDefault = true',
          reason: '[extend] 바로 아래에서 기본 규칙을 확장해야 한다',
        );
        expect(
          lines.where((String l) => l.trim() == '[[allowlists]]'),
          hasLength(1),
        );
        expect(lines.where((String l) => l.trim() == '[allowlist]'), isEmpty);

        final String text = lines.join('\n');
        final RegExpMatch paths = RegExp(
          r'^paths = \[(.*)\]$',
          multiLine: true,
        ).firstMatch(text)!;
        expect(
          RegExp(
            r"'''(.*?)'''",
          ).allMatches(paths.group(1)!).map((m) => m.group(1)),
          <String>[r'^ios/Podfile\.lock$'],
        );
        final RegExpMatch targets = RegExp(
          r'^targetRules = \[(.*)\]$',
          multiLine: true,
        ).firstMatch(text)!;
        expect(targets.group(1)!.trim(), '"generic-api-key"');
      },
      skip: _skipPublic,
    );
  });
}
