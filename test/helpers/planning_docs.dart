// 비공개 작업 일지를 읽는 유지보수자 검사의 skip 사유 헬퍼 (Phase 17.4 D-08 — see
// ROADMAP.md).
//
// 공개 mirror 에는 비공개 작업 일지 디렉터리(`.planning/`)가 없다. 그것을 읽는
// 유지보수자 검사는 공개 트리에서 건너뛰고, 파일이 있는 private 트리에서는 지금처럼
// 검사한다. `test(..., skip: ...)` 의 `skip:` 인자는 `bool` 또는 사유 `String` 을
// 받는다 — 사유 문자열이면 flutter_test 가 그 사유를 출력하며 건너뛴다(`~N` 집계).

import 'dart:io';

/// [paths] 가 전부 있으면 `false`, 하나라도 없으면 건너뛸 사유 문자열을 돌려준다.
///
/// `test(..., skip: skipUnlessPlanningDocsExist([...]))` 처럼 선언 시점에 평가해
/// `skip:` 인자로 쓴다. 경로는 저장소 루트 기준이다(`flutter test` 의 CWD = 프로젝트
/// 루트). 사유에는 처음 없는 경로를 넣는다.
///
/// [paths] 가 비어 있으면 무엇을 확인할지 정하지 않은 호출이므로 [ArgumentError] 를
/// 던진다 — 빈 목록이 조용히 `false`(검사 실행)가 되지 않게 한다.
Object skipUnlessPlanningDocsExist(List<String> paths) {
  if (paths.isEmpty) {
    throw ArgumentError.value(paths, 'paths', '확인할 경로가 최소 1개 필요하다');
  }
  for (final String path in paths) {
    if (!File(path).existsSync()) {
      return '비공개 작업 일지($path)가 없는 트리(공개 mirror) — 유지보수자 검사 건너뜀';
    }
  }
  return false;
}
