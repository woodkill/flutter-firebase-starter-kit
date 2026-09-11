// quick 260911-w9w — `scripts/firebase-configure.sh` 비대화형 계약 가드.
//
// **목적:** FlutterFire CLI 는 `--ios-out` 이 주어졌는데 `--ios-build-config`
// (또는 `--ios-target`) 이 없으면 "build configuration 과 target 중 무엇을
// 쓸 것인가" 를 묻는 선택 프롬프트를 띄운다. `--yes` 는 덮어쓰기 확인만
// 처리하므로 이 프롬프트를 막지 못하고, 비-TTY 실행은 그대로 멈춘다.
// 두 번째로, 그 검증 단계는 ruby 의 `xcodeproj` gem 으로 Runner.xcodeproj 를
// 파싱하므로 gem 이 없으면 CLI 가 LoadError 로 죽는다.
//
// 따라서 본 가드는 스크립트의 두 계약을 단언한다.
//   (1) flavor 별 build configuration 이 실제 CLI 인자로 전달된다
//   (2) flutterfire 호출 전에 ruby xcodeproj 전제조건을 검사한다
//
// **왜 주석을 제외하는가:** 같은 옵션 문자열이 header 주석에도 설명으로 등장한다.
// 주석을 세면 "실제로 CLI 에 전달되는가" 라는 질문에 답하지 못하고, 주석만 남고
// 실행 라인이 사라진 회귀를 놓친다.
//
// quick 260911-x9x 추가 근거: 2026-09-11 live run 실측 결과, 위 옵션을 주면
// flutterfire 가 요청하지 않은 파일 2종을 함께 변형한다 —
// `ios/Runner.xcodeproj/project.pbxproj` 에 중복 `bundle-service-file` 단계를
// 추가하고, 기존 crashlytics 단계의 인자를 `--default-config=default` 에서
// `--build-configuration=CONFIGURATION` 으로 바꿔 `firebase.json` 에 등록되지 않은
// 8개 configuration 의 iOS 빌드를 깨뜨린다. `firebase.json` 자체도 한 줄로
// 재작성된다. 또 생성된 dart options 는 포맷이 적용돼 있지 않아 프로젝트 포맷
// 게이트를 rc=1 로 만든다.
//
// 그래서 스크립트는 flutterfire 호출 직전에 두 파일을 스냅샷하고 호출 후(실패
// 포함) 되돌리며, 산출물에 `fvm dart format` 을 적용한다. 아래 두 번째 group 은
// 그 세 계약(스냅샷 · 복원 · 포맷)과 **실행 순서**를 실행 라인 기준으로 고정한다.
// 복원을 VCS 되돌림으로 바꾸는 회귀도 함께 막는다 — `git checkout` 방식은 개발자의
// 미커밋 편집까지 날리기 때문이다.
//
// **T-QUICK-260911-W9W-FIREBASE-CONFIGURE-LINT-01**

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const String _scriptPath = 'scripts/firebase-configure.sh';

/// 주석(`#` 으로 시작)과 빈 줄을 제외한 실행 라인만 돌려준다.
///
/// [path] 는 저장소 루트 기준 상대 경로다 (`flutter test` 의 CWD = 프로젝트 루트).
List<String> readExecutableLines(String path) {
  final File file = File(path);
  expect(file.existsSync(), isTrue, reason: '$path 가 존재해야 한다');
  return file
      .readAsLinesSync()
      .where((String line) => !line.trimLeft().startsWith('#'))
      .where((String line) => line.trim().isNotEmpty)
      .toList();
}

void main() {
  late List<String> lines;

  setUp(() {
    lines = readExecutableLines(_scriptPath);
  });

  group('firebase-configure.sh 비대화형 계약', () {
    test('flutterfire 호출에 flavor 별 --ios-build-config 이 전달된다', () {
      const String flag = r'--ios-build-config="Debug-${FLAVOR}"';
      expect(
        lines.where((String line) => line.contains(flag)).length,
        1,
        reason: '이 인자가 빠지면 CLI 가 선택 프롬프트에서 멈춘다 (--yes 무효)',
      );
    });

    test('flutterfire 호출 전에 ruby xcodeproj 전제조건을 검사한다', () {
      const String guard = r'''ruby -e "require 'xcodeproj'" >/dev/null''';
      expect(
        lines.where((String line) => line.contains(guard)).length,
        1,
        reason: 'gem 부재를 LoadError 가 아니라 안내 메시지로 바꾸는 검사',
      );
    });

    test('전제조건 검사가 DRY_RUN 분기 뒤 · flutterfire 호출 앞에 놓인다', () {
      final int dryRunIndex = lines.indexWhere(
        (String line) => line.contains(r'${DRY_RUN:-0}'),
      );
      final int guardIndex = lines.indexWhere(
        (String line) => line.contains("require 'xcodeproj'"),
      );
      final int invokeIndex = lines.indexWhere(
        (String line) => line.contains('flutterfire_cli:flutterfire configure'),
      );

      expect(dryRunIndex, greaterThanOrEqualTo(0));
      expect(
        guardIndex,
        greaterThan(dryRunIndex),
        reason: 'DRY_RUN 분기보다 앞서면 flutterfire 를 안 부르는 모드까지 막힌다',
      );
      expect(
        invokeIndex,
        greaterThan(guardIndex),
        reason: '검사가 호출보다 뒤면 LoadError 가 그대로 노출된다',
      );
    });
  });

  group('firebase-configure.sh 부수효과 복원 계약', () {
    test('변형 대상 2종을 스냅샷할 상수로 들고 있고 mktemp/cp 로 떠 둔다', () {
      const String pbxproj =
          r'CLI_TOUCHED_PBXPROJ="ios/Runner.xcodeproj/project.pbxproj"';
      const String firebaseJson = r'CLI_TOUCHED_FIREBASE_JSON="firebase.json"';
      const String mktemp =
          r'mktemp -d "${TMPDIR:-/tmp}/firebase-configure-XXXXXX"';
      const String snapshotCopy =
          r'cp "$SNAP_SRC" "${SNAP_DIR}/$(basename "$SNAP_SRC")"';

      for (final String literal in <String>[
        pbxproj,
        firebaseJson,
        mktemp,
        snapshotCopy,
      ]) {
        expect(
          lines.where((String line) => line.contains(literal)).length,
          1,
          reason: '스냅샷 계약: $literal 가 실행 라인에 정확히 1건 있어야 한다',
        );
      }
    });

    test('복원은 EXIT trap + cmp 비교로 이뤄지고 git 되돌림을 쓰지 않는다', () {
      expect(
        lines
            .where(
              (String line) =>
                  line.contains('trap restore_cli_side_effects EXIT'),
            )
            .length,
        1,
        reason: 'flutterfire 가 실패하면 set -e 가 명시 호출에 도달하지 못한다',
      );
      expect(
        lines.where((String line) => line.contains('cmp -s')).length,
        1,
        reason: '내용이 같으면 되돌리지 않는다 (조용한 성공)',
      );
      expect(
        lines.where((String line) => line.contains('git checkout')),
        isEmpty,
        reason: '체크아웃 되돌림은 개발자의 미커밋 pbxproj 편집까지 날린다',
      );
    });

    test('생성된 dart options 에 포맷을 적용한다', () {
      const String format = r'fvm dart format "$OUT_DART"';
      expect(
        lines.where((String line) => line.contains(format)).length,
        1,
        reason: 'flutterfire 출력은 포맷되지 않아 프로젝트 포맷 게이트를 깨뜨린다',
      );
    });

    test('스냅샷 → flutterfire → 포맷 → skip-worktree 순서가 유지된다', () {
      final int snapshotIndex = lines.indexWhere(
        (String line) => line.contains('firebase-configure-XXXXXX'),
      );
      final int invokeIndex = lines.indexWhere(
        (String line) => line.contains('flutterfire_cli:flutterfire configure'),
      );
      final int formatIndex = lines.indexWhere(
        (String line) => line.contains(r'fvm dart format "$OUT_DART"'),
      );
      final int skipWorktreeIndex = lines.indexWhere(
        (String line) => line.contains(r'for OUT_PATH in'),
      );

      expect(snapshotIndex, greaterThanOrEqualTo(0));
      expect(
        invokeIndex,
        greaterThan(snapshotIndex),
        reason: '스냅샷이 호출보다 뒤면 이미 변형된 내용을 뜬다',
      );
      expect(
        formatIndex,
        greaterThan(invokeIndex),
        reason: '포맷이 호출보다 앞서면 갱신 전 파일을 포맷한다',
      );
      expect(
        skipWorktreeIndex,
        greaterThan(formatIndex),
        reason: 'skip-worktree 는 최종 내용에 걸려야 한다',
      );
    });
  });
}
