// Phase 13.1 — see ROADMAP.md (Nyquist gap-fill: R7/R12/R14/R15 manual→automate)

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Phase 13.1 manual-review 4건의 docs/asset/ARB 회귀 가드를 자동화한다 —
/// Nyquist auditor 가 R7/R12/R14/R15 를 manual review 에서 자동 검증으로
/// 승격하여 미래 회귀 시 즉시 RED 노출.
///
/// **scope:**
/// - Test 1 (R7): `lib/l10n/app_ja.arb` 의 `authNaverSignIn` /
///   `authKakaoSignIn` 키-값이 D-79 영문 fallback verbatim 인지 검증.
///   자상화 (Phase 13.1 Gap-1 X2) 로 widget render path 에서는 라벨이
///   사용되지 않지만, ARB source 자체는 미래 라벨 layer 복귀 시 회귀 차단
///   목적으로 보존 — 본 test 가 source-of-truth 가드.
/// - Test 2 (R12): `assets/brand/facebook/README.md` 의 `sign_in_button`
///   community package retain 명시 ≥ 1 hit.
/// - Test 3 (R14): `.planning/phases/13-naver-login/13-UI-SPEC.md` +
///   `13-PATTERNS.md` 의 Phase 13.1 retroactive 마커 ≥ 1 each.
/// - Test 4 (R15): `docs/manual.md` `## Brand Asset Management` heading
///   존재 + 4 키워드 (provider 출처 / 라이선스 / 다운 절차 / 사전 검수)
///   substring 모두 존재.
///
/// **RED→GREEN tracking:** 본 test 는 commit 시점 GREEN — 미래 회귀 (예:
/// app_ja.arb 의 fallback 값 변경, README 의 sign_in_button 키워드 삭제,
/// retro 마커 제거, manual.md heading rename) 시 RED 즉시 노출.
void main() {
  group('docs_compliance_lint', () {
    test('R7: app_ja.arb 의 authNaverSignIn/authKakaoSignIn 영문 fallback 보존', () {
      // Arrange — ARB 파일 직접 읽기 (gen-l10n 산출물 의존 금지).
      final arb = File('lib/l10n/app_ja.arb');
      expect(arb.existsSync(), isTrue, reason: 'app_ja.arb 부재');
      final content = arb.readAsStringSync();

      // Assert — D-79 영문 fallback verbatim.
      expect(
        content,
        contains('"authNaverSignIn": "Continue with Naver"'),
        reason: 'authNaverSignIn 의 D-79 영문 fallback 값이 drift — '
            'Phase 13.1 R7 acceptance 위반',
      );
      expect(
        content,
        contains('"authKakaoSignIn": "Continue with Kakao"'),
        reason: 'authKakaoSignIn 의 D-79 영문 fallback 값이 drift — '
            'Phase 13.1 R7 acceptance 위반',
      );
    });

    test('R12: assets/brand/facebook/README.md 의 sign_in_button retain 명시', () {
      // Arrange.
      final readme = File('assets/brand/facebook/README.md');
      expect(readme.existsSync(), isTrue, reason: 'facebook README 부재');
      final content = readme.readAsStringSync();

      // Act — community package 키워드 출현 횟수 카운트.
      const needle = 'sign_in_button';
      var hits = 0;
      var idx = 0;
      while (true) {
        final found = content.indexOf(needle, idx);
        if (found < 0) {
          break;
        }
        hits += 1;
        idx = found + needle.length;
      }

      // Assert — Phase 18 마이그 전까지 community package retain 명시 의무.
      expect(
        hits,
        greaterThanOrEqualTo(1),
        reason: 'facebook README 가 sign_in_button community package retain '
            '명시 누락 — Phase 13.1 R12 acceptance 위반 (현재 hit=$hits)',
      );
    });

    test('R14: 13-UI-SPEC.md / 13-PATTERNS.md 의 Phase 13.1 retro 마커 ≥ 1 each', () {
      // Arrange — 두 phase 13 docs.
      final uiSpec = File('.planning/phases/13-naver-login/13-UI-SPEC.md');
      final patterns = File('.planning/phases/13-naver-login/13-PATTERNS.md');
      expect(uiSpec.existsSync(), isTrue, reason: '13-UI-SPEC.md 부재');
      expect(patterns.existsSync(), isTrue, reason: '13-PATTERNS.md 부재');

      // Act — retro marker substring 매칭 (markdown comment / 본문 모두 허용).
      const marker = 'Phase 13.1 retroactive';
      final uiSpecHits = marker.allMatches(uiSpec.readAsStringSync()).length;
      final patternsHits = marker.allMatches(patterns.readAsStringSync()).length;

      // Assert — 각 파일 ≥ 1 hit.
      expect(
        uiSpecHits,
        greaterThanOrEqualTo(1),
        reason: '13-UI-SPEC.md 의 Phase 13.1 retroactive 마커 누락 — '
            'R14 acceptance 위반 (현재 hit=$uiSpecHits)',
      );
      expect(
        patternsHits,
        greaterThanOrEqualTo(1),
        reason: '13-PATTERNS.md 의 Phase 13.1 retroactive 마커 누락 — '
            'R14 acceptance 위반 (현재 hit=$patternsHits)',
      );
    });

    test('R15: docs/manual.md 의 Brand Asset Management heading + 4 키워드', () {
      // Arrange.
      final manual = File('docs/manual.md');
      expect(manual.existsSync(), isTrue, reason: 'docs/manual.md 부재');
      final content = manual.readAsStringSync();

      // Assert — heading 존재.
      expect(
        content,
        contains('## Brand Asset Management'),
        reason: 'docs/manual.md 의 ## Brand Asset Management heading 누락 — '
            'R15 acceptance 위반',
      );

      // Assert — 4 핵심 키워드 substring (manual 단락 내용 정합성).
      // - 출처: 공식 BI URL 표 (`공식 BI URL`)
      // - 라이선스: 표 컬럼 + LICENSE.txt 절차 (`라이선스`)
      // - 다운 절차: `자산 다운로드` 단어 (1단계 — 자산 다운로드)
      // - 사전 검수: `사전 검수` 단어 (사용자 책임 사전 검수 정책)
      const requiredKeywords = <String>[
        '공식 BI URL',
        '라이선스',
        '자산 다운로드',
        '사전 검수',
      ];
      for (final keyword in requiredKeywords) {
        expect(
          content,
          contains(keyword),
          reason: 'docs/manual.md Brand Asset Management 단락의 핵심 키워드 '
              '"$keyword" 누락 — R15 단락 적정성 회귀',
        );
      }
    });
  });
}
