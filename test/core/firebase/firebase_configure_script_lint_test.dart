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
}
