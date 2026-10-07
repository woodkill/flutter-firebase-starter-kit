// 비공개 작업 일지가 없는 트리(공개 mirror)에서의 skip 경로를 고정한다 (Phase 17.4 D-08 —
// see ROADMAP.md).
//
// 두 트리 모두에서 돈다. `.planning/ROADMAP.md` 가 없는 작업 디렉터리에서 phase 참조 lint 가
// [SKIP] 으로 통과하는지, skip 사유 헬퍼가 존재 · 부재 · 빈 목록을 구분하는지 확인한다.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../helpers/planning_docs.dart';

void main() {
  group('작업 일지 부재 skip (D-08)', () {
    test(
      'T-174-SKIP-01: ROADMAP.md 없는 작업 디렉터리에서 check_phase_refs.sh 는 [SKIP] 후 exit 0',
      () {
        final String root = Directory.current.path;
        final Directory build = Directory('$root/build')
          ..createSync(recursive: true);
        final Directory work = build.createTempSync('test-publish-kit-skip-');
        addTearDown(() => work.deleteSync(recursive: true));
        expect(
          File('${work.path}/.planning/ROADMAP.md').existsSync(),
          isFalse,
          reason: '작업 디렉터리에 .planning 이 없어야 시나리오가 성립한다',
        );

        final ProcessResult result = Process.runSync('bash', <String>[
          '$root/scripts/check_phase_refs.sh',
        ], workingDirectory: work.path);

        expect(result.exitCode, 0, reason: '${result.stdout}${result.stderr}');
        expect(
          (result.stdout as String).startsWith('[SKIP] check_phase_refs.sh'),
          isTrue,
          reason: 'stdout=${result.stdout}',
        );
      },
    );

    test(
      'T-174-SKIP-02: skipUnlessPlanningDocsExist — 있으면 false · 없으면 경로가 든 사유 · 빈 목록은 오류',
      () {
        expect(skipUnlessPlanningDocsExist(<String>['pubspec.yaml']), isFalse);

        const String missing = 'no/such/planning-doc.md';
        final Object reason = skipUnlessPlanningDocsExist(<String>[
          'pubspec.yaml',
          missing,
        ]);
        expect(reason, isA<String>());
        expect(reason as String, contains(missing));

        expect(
          () => skipUnlessPlanningDocsExist(<String>[]),
          throwsArgumentError,
        );
      },
    );
  });
}
