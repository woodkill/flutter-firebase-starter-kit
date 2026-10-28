// 킷 발행 규칙 파일이 없는 트리(킷 사용자 저장소 · 공개 mirror)에서의 skip 경로를 고정한다
// (Phase 17.4 D-08 — see ROADMAP.md).
//
// 두 트리 모두에서 돈다. 킷 발행 규칙 파일(`kMaintainerTreeMarker`)이나
// `.planning/ROADMAP.md` 가 없는 작업 디렉터리에서 phase 참조 lint 가 [SKIP] 으로
// 통과하는지(자기 ROADMAP.md 만 있는 킷 사용자 저장소 포함) · 둘 다 있으면 검사가 실제로
// 도는지, skip 사유 헬퍼가 존재 · 부재 · 빈 목록을 구분하는지, 유지보수자 트리 판정이 킷
// 발행 규칙 파일에 묶여 있는지 확인한다.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../helpers/planning_docs.dart';

/// phase 참조 lint 스크립트의 저장소 루트 기준 경로.
const String _scriptPath = 'scripts/check_phase_refs.sh';

/// `build/` 아래에 빈 작업 디렉터리를 만들고, 시험이 끝나면 지운다.
Directory _createWorkDir() {
  final build = Directory('${Directory.current.path}/build')
    ..createSync(recursive: true);
  final Directory work = build.createTempSync('test-publish-kit-skip-');
  addTearDown(() => work.deleteSync(recursive: true));
  return work;
}

/// [work] 아래 [relativePath] 에 [content] 를 쓴다(상위 디렉터리를 만든다).
void _writeFixture(Directory work, String relativePath, String content) {
  File('${work.path}/$relativePath')
    ..createSync(recursive: true)
    ..writeAsStringSync(content);
}

/// [work] 를 작업 디렉터리로 삼아 phase 참조 lint 스크립트를 돌린다.
ProcessResult _runCheckPhaseRefs(Directory work) => Process.runSync(
  'bash',
  <String>['${Directory.current.path}/$_scriptPath'],
  workingDirectory: work.path,
);

void main() {
  group('작업 일지 부재 skip (D-08)', () {
    test(
      'T-174-SKIP-01: ROADMAP.md 없는 작업 디렉터리에서 check_phase_refs.sh 는 [SKIP] 후 exit 0',
      () {
        final Directory work = _createWorkDir();
        expect(
          File('${work.path}/.planning/ROADMAP.md').existsSync(),
          isFalse,
          reason: '작업 디렉터리에 .planning 이 없어야 시나리오가 성립한다',
        );

        final ProcessResult result = _runCheckPhaseRefs(work);

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

        const missing = 'no/such/planning-doc.md';
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

    test(
      'T-174-SKIP-03: skipUnlessMaintainerTree — 킷 발행 규칙 파일(kMaintainerTreeMarker)로 판정한다',
      () {
        expect(
          kMaintainerTreeMarker,
          '.planning/release/mirror-exclude-paths.txt',
        );

        final Object skip = skipUnlessMaintainerTree();
        if (File(kMaintainerTreeMarker).existsSync()) {
          expect(skip, isFalse, reason: '발행 규칙 파일이 있으면 유지보수자 검사를 돌린다');
        } else {
          expect(skip, isA<String>());
          expect(
            skip as String,
            contains(kMaintainerTreeMarker),
            reason: '사유에 판정 표지 경로가 들어가야 한다',
          );
        }
      },
    );

    test(
      'T-174-SKIP-04: ROADMAP.md 가 있어도 킷 발행 규칙 파일이 없으면 [SKIP] · 둘 다 있으면 검사가 돈다',
      () {
        final Directory work = _createWorkDir();
        // 킷 사용자 저장소 재현 — 킷 코드 주석의 phase 가 자기 ROADMAP 에 없다.
        _writeFixture(work, '.planning/ROADMAP.md', '### Phase 1: x\n');
        _writeFixture(work, 'lib/a.dart', '// Phase 17 — see ROADMAP.md\n');

        final ProcessResult adopter = _runCheckPhaseRefs(work);
        final adopterOut = adopter.stdout as String;
        expect(adopter.exitCode, 0, reason: '$adopterOut${adopter.stderr}');
        expect(
          adopterOut.startsWith('[SKIP] check_phase_refs.sh'),
          isTrue,
          reason: 'stdout=$adopterOut',
        );
        expect(
          adopterOut,
          contains(kMaintainerTreeMarker),
          reason: '사유에 처음 없는 경로(킷 발행 규칙 파일)가 들어가야 한다',
        );

        // 대조군 — 같은 픽스처에 발행 규칙 파일을 더하면 검사가 실제로 돈다.
        _writeFixture(work, kMaintainerTreeMarker, '');
        final ProcessResult maintainer = _runCheckPhaseRefs(work);
        final maintainerOut = maintainer.stdout as String;
        expect(
          maintainer.exitCode,
          1,
          reason: '$maintainerOut${maintainer.stderr}',
        );
        expect(maintainerOut, contains('[FAIL] lib/a.dart:1'));

        // 발행 규칙 파일만 있고 ROADMAP.md 가 없으면 ROADMAP 경로를 사유로 건너뛴다.
        File('${work.path}/.planning/ROADMAP.md').deleteSync();
        final ProcessResult noRoadmap = _runCheckPhaseRefs(work);
        final noRoadmapOut = noRoadmap.stdout as String;
        expect(
          noRoadmap.exitCode,
          0,
          reason: '$noRoadmapOut${noRoadmap.stderr}',
        );
        expect(
          noRoadmapOut.startsWith('[SKIP] check_phase_refs.sh'),
          isTrue,
          reason: 'stdout=$noRoadmapOut',
        );
        expect(noRoadmapOut, contains('.planning/ROADMAP.md'));

        // 스크립트의 판정 표지가 시험 헬퍼 상수와 같은 경로다(한 줄 대조).
        expect(
          File(_scriptPath).readAsStringSync(),
          contains('MAINTAINER_MARKER="$kMaintainerTreeMarker"'),
        );
      },
    );
  });
}
