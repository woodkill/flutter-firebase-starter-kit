// Phase 13.3 X4 (2026-05-17, 260517-uv4) — Apple Font License rasterized
// risk lint guard.
//
// **목적:** memory `feedback_apple_font_license_rasterized_risk.md` 권고
// 패턴 자기검증. `test/features/auth/presentation/_widgets/goldens/` 디렉토리
// 의 모든 `*_ios.png` golden fixture 가 `.gitignore` 에 명시되었는지 filesystem
// scan + 매칭 검증. 누락 시 fail-loud — Apple SF Pro / AppleSDGothicNeo +
// Sandoll 등 macOS native 시스템 폰트로 렌더된 PNG 를 repo distribute 시
// 라이센스 위반 위험.
//
// **검증 패턴:** 외부 의존 0 (Dart core File API + RegExp 만 사용).
// `.gitignore` 의 entry 가 line-by-line 매칭 — comment line 또는 negation
// pattern (`!`) 무시. macOS / Linux / Windows 모두 같은 절대 경로 패턴 사용.
//
// **T-13.3-IOS-GOLDEN-GITIGNORE-LINT-01** — Phase 13.3 X4 단일 가드.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const String _goldensDir = 'test/features/auth/presentation/_widgets/goldens';
const String _gitignorePath = '.gitignore';

void main() {
  group('T-13.3-IOS-GOLDEN-GITIGNORE-LINT-01: Apple Font License lint guard', () {
    test('_ios.png golden fixtures 모두 .gitignore 에 명시 (memory '
        'feedback_apple_font_license_rasterized_risk.md 권고 패턴)', () {
      final Directory dir = Directory(_goldensDir);
      if (!dir.existsSync()) {
        // golden 디렉토리 자체 부재 시 검증 대상 0 — fail 아님 (CI 환경 등).
        return;
      }

      // _ios.png 글로브 매칭 — 디렉토리 내 모든 entry 중 `_ios.png` 로 끝
      // 나는 파일만 (working tree 에 존재하는 실제 파일, gitignored 여부
      // 무관).
      final List<File> iosGoldens = dir
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('_ios.png'))
          .toList();

      if (iosGoldens.isEmpty) {
        // macOS dev 환경 외 (CI / Linux) 에서는 _ios.png 생성 자체 미발생
        // (Platform.isMacOS skip 게이트). 검증 대상 0 → PASS (trivial).
        return;
      }

      // .gitignore 본문 읽기 — line-by-line 매칭 위함.
      final File gitignoreFile = File(_gitignorePath);
      expect(
        gitignoreFile.existsSync(),
        isTrue,
        reason: '.gitignore 파일 부재 — Apple Font License 회피 패턴 검증 불가.',
      );
      final List<String> gitignoreLines = gitignoreFile
          .readAsLinesSync()
          .map((line) => line.trim())
          .where((line) => line.isNotEmpty && !line.startsWith('#'))
          .toList();

      // 각 _ios.png 파일이 .gitignore 의 entry 와 매칭되는지 검증.
      final List<String> missingEntries = <String>[];
      for (final File golden in iosGoldens) {
        // Dart File.path 가 working dir relative path 인 경우, fully-
        // qualified path (`test/features/.../goldens/xxx_ios.png`) 로
        // 표준화. golden.path 가 이미 그 형식이지만 명시적으로 변환.
        final String expectedEntry = golden.path
            .replaceAll(r'\', '/')
            .replaceFirst(RegExp('^\\./'), '');
        final bool matched = gitignoreLines.any(
          (line) => line == expectedEntry,
        );
        if (!matched) {
          missingEntries.add(expectedEntry);
        }
      }

      expect(
        missingEntries,
        isEmpty,
        reason:
            'Apple Font License rasterized risk — 다음 _ios.png 파일이 '
            '.gitignore 미명시 (commit distribute 시 macOS native 시스템 '
            '폰트 라이센스 위반 위험): \n'
            '${missingEntries.map((e) => '  - $e').join('\n')}\n'
            '\n.gitignore 에 다음을 추가하세요: \n'
            '${missingEntries.map((e) => 'test/features/auth/presentation/_widgets/goldens/${e.split('/').last}').join('\n')}\n'
            '\nmemory feedback_apple_font_license_rasterized_risk.md '
            '권고 패턴: iOS golden 은 macOS dev 환경에서만 로컬 생성 + '
            '시각 sign-off + commit 차단. Platform.isMacOS skip 게이트 '
            '+ .gitignore 2-layer 가드 의무.',
      );
    });
  });
}
