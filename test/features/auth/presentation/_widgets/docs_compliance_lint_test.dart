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
    test('R7: app_ja.arb 의 authNaverSignIn/authKakaoSignIn BI verbatim 보존', () {
      // Arrange — ARB 파일 직접 읽기 (gen-l10n 산출물 의존 금지).
      final arb = File('lib/l10n/app_ja.arb');
      expect(arb.existsSync(), isTrue, reason: 'app_ja.arb 부재');
      final content = arb.readAsStringSync();

      // Assert — Phase 13.3 D-111 retroactive 갱신: D-79 영문 fallback 폐기,
      // [ASSUMED] 패턴 일관성 ja verbatim (user sign-off 2026-05-15).
      expect(
        content,
        contains('"authNaverSignIn": "NAVERでログイン"'),
        reason:
            'authNaverSignIn ja BI verbatim 값이 drift — '
            'Phase 13.3 D-111 acceptance 위반',
      );
      expect(
        content,
        contains('"authKakaoSignIn": "Kakaoでログイン"'),
        reason:
            'authKakaoSignIn ja BI verbatim 값이 drift — '
            'Phase 13.3 D-111 acceptance 위반',
      );
    });

    // ─── Phase 13.2 REVIEW WR-03 정정 (2026-05-13): brand redistribution
    // 회귀 가드. starter-kit clone 시 사용자가 Meta/Google/Kakao/Naver
    // 라이선스를 별도 동의 없이 받는 vector 를 차단하기 위해 자상 디렉토리에
    // LICENSE.txt + README.md 둘 모두 존재 의무. 결락 시 RED.
    //
    // **Apple 제외 이유:** AppleSpec 는 SDK 위제 (SignInWithAppleButton)
    // 위임으로 PNG/SVG 자상 미동봉. assets/brand/apple/ 디렉토리는 README.md
    // 만 보유 (Phase 13.1 D-62 lock).
    test('Phase 13.2 WR-03: 4 provider 자상 디렉토리 LICENSE.txt + README.md '
        '동시 존재 검증', () {
      const providers = <String>['facebook', 'google', 'kakao', 'naver'];
      for (final provider in providers) {
        final licenseFile = File('assets/brand/$provider/LICENSE.txt');
        final readmeFile = File('assets/brand/$provider/README.md');
        expect(
          licenseFile.existsSync(),
          isTrue,
          reason:
              'WR-03 회귀 — assets/brand/$provider/LICENSE.txt 부재. '
              '$provider trademark 사용 전 라이선스 본문 사전 검토 의무.',
        );
        expect(
          readmeFile.existsSync(),
          isTrue,
          reason:
              'WR-03 회귀 — assets/brand/$provider/README.md 부재. '
              'BI URL / 다운로드 일자 / 사전 검수 절차 결락 시 사용자가 '
              '라이선스 의무 우회 가능.',
        );
      }
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
        reason:
            'facebook README 가 sign_in_button community package retain '
            '명시 누락 — Phase 13.1 R12 acceptance 위반 (현재 hit=$hits)',
      );
    });

    test(
      'R14: 13-UI-SPEC.md / 13-PATTERNS.md 의 Phase 13.1 retro 마커 ≥ 1 each',
      () {
        // Arrange — 두 phase 13 docs.
        final uiSpec = File('.planning/phases/13-naver-login/13-UI-SPEC.md');
        final patterns = File('.planning/phases/13-naver-login/13-PATTERNS.md');
        expect(uiSpec.existsSync(), isTrue, reason: '13-UI-SPEC.md 부재');
        expect(patterns.existsSync(), isTrue, reason: '13-PATTERNS.md 부재');

        // Act — retro marker substring 매칭 (markdown comment / 본문 모두 허용).
        const marker = 'Phase 13.1 retroactive';
        final uiSpecHits = marker.allMatches(uiSpec.readAsStringSync()).length;
        final patternsHits = marker
            .allMatches(patterns.readAsStringSync())
            .length;

        // Assert — 각 파일 ≥ 1 hit.
        expect(
          uiSpecHits,
          greaterThanOrEqualTo(1),
          reason:
              '13-UI-SPEC.md 의 Phase 13.1 retroactive 마커 누락 — '
              'R14 acceptance 위반 (현재 hit=$uiSpecHits)',
        );
        expect(
          patternsHits,
          greaterThanOrEqualTo(1),
          reason:
              '13-PATTERNS.md 의 Phase 13.1 retroactive 마커 누락 — '
              'R14 acceptance 위반 (현재 hit=$patternsHits)',
        );
      },
    );

    test('R15: docs/manual.md 의 Brand Asset Management heading + 4 키워드', () {
      // Arrange.
      final manual = File('docs/manual.md');
      expect(manual.existsSync(), isTrue, reason: 'docs/manual.md 부재');
      final content = manual.readAsStringSync();

      // Assert — heading 존재.
      expect(
        content,
        contains('## Brand Asset Management'),
        reason:
            'docs/manual.md 의 ## Brand Asset Management heading 누락 — '
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
          reason:
              'docs/manual.md Brand Asset Management 단락의 핵심 키워드 '
              '"$keyword" 누락 — R15 단락 적정성 회귀',
        );
      }
    });

    // ─── Phase 13.2 — Wave 1+ 진입 acceptance signal 단일 진실원 (RED) ─────
    //
    // Phase 13.2 R4/R8/R9/R10/R11/R12/R13 grep + smoke acceptance 를 자동
    // test 로 검증. Wave 1+ 진입 게이트 — 모든 신규 test 가 Wave 1+ 코드/문서
    // 마이그 완료 후 GREEN 으로 자동 전환. Test 12 (R17) 만 시작부터 GREEN
    // (helper 호출 path 보존 회귀 가드 sentinel — RED gate 와 분리, Plan
    // 13.2-02 acceptance 명시).
    //
    // **grep gate hygiene:** comment line (`//`, `#`) 은 filter 후 카운트 —
    // 자가 invalidating 회피 (Phase 13.1 패턴 일관).

    test('Phase 13.2 R4: assets/brand/facebook/README.md 의 "Phase 18" 단어 '
        '폐기 + 7 헤딩 모두 존재', () {
      // Arrange — README.md 직접 읽기.
      final readme = File('assets/brand/facebook/README.md');
      expect(readme.existsSync(), isTrue, reason: 'facebook README 부재');
      final content = readme.readAsStringSync();
      final lines = content.split('\n');

      // Act — "Phase 18" 단어 hit 카운트 (comment line filter).
      final phase18Hits = lines
          .where(
            (l) =>
                !l.trimLeft().startsWith('//') && !l.trimLeft().startsWith('#'),
          )
          .where((l) => l.contains('Phase 18'))
          .length;

      // Assert — Wave 1 README 갱신 후 0 (현재 ≥ 1 → RED).
      expect(
        phase18Hits,
        0,
        reason:
            'Phase 13.2 R4 acceptance 위반 — README.md 의 "Phase 18" 단어 '
            'hit = $phase18Hits (target = 0, Wave 1 retro 후 GREEN). '
            'README 7 필드 모두 "Phase 18" 폐기 + 실제 값 갱신 의무.',
      );

      // Assert — 7 헤딩 모두 존재 (Phase 13.1 active provider README schema
      // 일관).
      const requiredHeadings = <String>[
        '공식 BI URL',
        '자산 다운로드 URL',
        '다운로드 일자',
        '라이선스',
        '사전 검수 절차',
        '미포함 변형 추가 절차',
        '자산 freshness 갱신 빈도',
      ];
      for (final heading in requiredHeadings) {
        expect(
          content,
          contains('## $heading'),
          reason:
              'Phase 13.2 R4 acceptance 위반 — README 의 "## $heading" '
              'heading 누락 (Phase 13.1 active provider README schema 일관)',
        );
      }
    });

    test('Phase 13.2 R8: pubspec.yaml 에 sign_in_button + font_awesome_flutter '
        'hit 0', () {
      // Arrange — pubspec.yaml 직접 읽기.
      final pubspec = File('pubspec.yaml');
      expect(pubspec.existsSync(), isTrue, reason: 'pubspec.yaml 부재');
      final lines = pubspec.readAsLinesSync();

      // Act — comment 제외 substring 카운트.
      int countSubstring(String needle) {
        return lines
            .where((l) => !l.trimLeft().startsWith('#'))
            .where((l) => l.contains(needle))
            .length;
      }

      final signInHits = countSubstring('sign_in_button');
      final fontAwesomeHits = countSubstring('font_awesome_flutter');

      // Assert — Wave 2 pubspec 정정 후 0 (현재 각 ≥ 1 → RED).
      expect(
        signInHits,
        0,
        reason:
            'Phase 13.2 R8 acceptance 위반 — pubspec.yaml 의 '
            'sign_in_button hit = $signInHits (target = 0, Wave 2 후 GREEN). '
            '의존성 단락 제거 의무.',
      );
      expect(
        fontAwesomeHits,
        0,
        reason:
            'Phase 13.2 R8 acceptance 위반 — pubspec.yaml 의 '
            'font_awesome_flutter hit = $fontAwesomeHits (target = 0, '
            'Wave 2 후 GREEN). 제약 단락 제거 의무.',
      );
    });

    // Phase 13.2 Plan 13.2-06 — self-invalidating 회피 분리:
    // R9/R10 needle 문자열을 concat 으로 분리하여 본 test 파일 자체가
    // grep 결과에 자가 hit 되지 않도록 한다. lint 본문 (test 제목 + needle
    // 검색 코드 + reason 메시지) 의 substring literal 을 컴파일 시점에만
    // join 되는 변수 / 문자열 결합으로 회피. self-invalidating 회피 분리는
    // Phase 13.2 Plan 13.2-05 SUMMARY 의 의도된 정정 항목 (Wave 2 → Wave 6
    // 전환에서 R9/R10 GREEN 의무).
    //
    // grep 검증 source 단어 구성 ('Buttons' + '.' + 'facebookNew' 결합):
    //   final r9Needle = '${'Buttons'}.${'facebookNew'}';
    // (string interpolation 으로 source 에 'Buttons.facebookNew' literal
    // substring 부재 — comment 라인 외 hit 0).
    //
    // 동일 패턴으로 R10 needle ('package:' + 'sign_in_' + 'button') 도 분리.

    test('Phase 13.2 R9: lib/ + test/ 트리에서 Buttons 식별자 hit 0', () {
      // Arrange — lib/ + test/ 의 .dart 파일 전부 재귀 walk.
      final files = <File>[
        ...Directory('lib').listSync(recursive: true).whereType<File>(),
        ...Directory('test').listSync(recursive: true).whereType<File>(),
      ].where((f) => f.path.endsWith('.dart')).toList();
      expect(files, isNotEmpty, reason: 'lib/ + test/ Dart 파일 0건');

      // self-invalidating 회피 분리 — interpolation 으로 source literal 부재.
      final needle = '${'Buttons'}.${'facebookNew'}';

      // Act — comment 제외 substring 카운트 (자가 invalidating 회피).
      final hits = <String>[];
      for (final file in files) {
        final lines = file.readAsLinesSync();
        for (var i = 0; i < lines.length; i += 1) {
          final line = lines[i];
          final trimmed = line.trimLeft();
          if (trimmed.startsWith('//')) {
            continue;
          }
          if (line.contains(needle)) {
            hits.add('${file.path}:${i + 1}');
          }
        }
      }

      // Assert — Wave 2 코드/test 정정 후 0 (현재 ≥ 5 → RED).
      expect(
        hits,
        isEmpty,
        reason:
            'Phase 13.2 R9 acceptance 위반 — $needle '
            'hit ${hits.length} (target = 0, Wave 6 후 GREEN). '
            '잔존 위치: ${hits.join(", ")}',
      );
    });

    test('Phase 13.2 R10: lib/ + test/ 트리에서 sign_in_button import hit 0', () {
      // Arrange.
      final files = <File>[
        ...Directory('lib').listSync(recursive: true).whereType<File>(),
        ...Directory('test').listSync(recursive: true).whereType<File>(),
      ].where((f) => f.path.endsWith('.dart')).toList();
      expect(files, isNotEmpty, reason: 'lib/ + test/ Dart 파일 0건');

      // self-invalidating 회피 분리 — interpolation 으로 source literal 부재.
      final needle = '${'package:'}${'sign_in_'}button';

      // Act — comment 제외 substring 카운트.
      final hits = <String>[];
      for (final file in files) {
        final lines = file.readAsLinesSync();
        for (var i = 0; i < lines.length; i += 1) {
          final line = lines[i];
          final trimmed = line.trimLeft();
          if (trimmed.startsWith('//')) {
            continue;
          }
          if (line.contains(needle)) {
            hits.add('${file.path}:${i + 1}');
          }
        }
      }

      // Assert — Wave 2 정정 후 0 (현재 5 hit → RED, D-100 단일 진실원).
      expect(
        hits,
        isEmpty,
        reason:
            'Phase 13.2 R10 acceptance 위반 — $needle '
            'import hit ${hits.length} (target = 0, Wave 6 후 GREEN). '
            '잔존 위치: ${hits.join(", ")}',
      );
    });

    test('Phase 13.2 R11: 13.1-PATTERNS.md 의 retro 마커 ≥ 1 + 7 잔존 어휘 '
        'hit 0', () {
      // Arrange.
      final patterns = File(
        '.planning/phases/13.1-social-brand-asset-compliance/13.1-PATTERNS.md',
      );
      expect(patterns.existsSync(), isTrue, reason: '13.1-PATTERNS.md 부재');
      final content = patterns.readAsStringSync();

      // Act — retro 마커 (Wave 3 retro 후 ≥ 1).
      final retroHits = 'Updated by Phase 13.2 retroactive'
          .allMatches(content)
          .length;

      // Assert — Wave 3 retro 후 ≥ 1 (현재 0 → RED).
      expect(
        retroHits,
        greaterThanOrEqualTo(1),
        reason:
            'Phase 13.2 R11 acceptance 위반 — 13.1-PATTERNS.md retro 마커 '
            'hit = $retroHits (target ≥ 1, Wave 3 후 GREEN). '
            'Phase 13.1 R12 단락 retroactive 재기술 + 마커 주석 의무.',
      );

      // Act — 7 잔존 어휘 (BL-06 ground-truth verbatim substring) hit 0.
      // self-invalidating 회피 분리 — 'Buttons.facebookNew' 어휘는
      // interpolation 으로 source literal 부재 (R9 grep test 자가 hit 회피).
      final staleSubstrings = <String>[
        '잔존 — Facebook 만 sign_in_button',
        "throw UnsupportedError('Facebook uses sign_in_button",
        'sign_in_button: ^4.1.0',
        'Phase 18 마이그',
        'Phase 18 자산 교체 예정',
        'sign_in_button community package',
        '${'Buttons'}.${'facebookNew'}',
      ];
      final staleHits = <String, int>{};
      for (final needle in staleSubstrings) {
        final hits = needle.allMatches(content).length;
        if (hits > 0) {
          staleHits[needle] = hits;
        }
      }

      // Assert — Wave 3 retro 후 모든 잔존 어휘 0 hit (현재 ≥ 7 → RED).
      expect(
        staleHits,
        isEmpty,
        reason:
            'Phase 13.2 R11 acceptance 위반 — 13.1-PATTERNS.md 의 잔존 '
            '어휘 (target = 0, Wave 3 후 GREEN): $staleHits',
      );
    });

    test('Phase 13.2 R12: 13-UI-SPEC.md 의 retro 마커 ≥ 1 + Phase 13.1 흔적 '
        '12건 보존', () {
      // Arrange — BL-05 ground-truth: Phase 13.1 retro 마커는 12건 (NOT 9).
      final uiSpec = File('.planning/phases/13-naver-login/13-UI-SPEC.md');
      expect(uiSpec.existsSync(), isTrue, reason: '13-UI-SPEC.md 부재');
      final content = uiSpec.readAsStringSync();

      // Act — Phase 13.2 retro 마커 (Wave 3 retro 후 ≥ 1).
      final retroHits = 'Updated by Phase 13.2 retroactive'
          .allMatches(content)
          .length;

      // Assert — Wave 3 retro 후 ≥ 1 (현재 0 → RED).
      expect(
        retroHits,
        greaterThanOrEqualTo(1),
        reason:
            'Phase 13.2 R12 acceptance 위반 — 13-UI-SPEC.md Phase 13.2 '
            'retro 마커 hit = $retroHits (target ≥ 1, Wave 3 후 GREEN).',
      );

      // Act — Phase 13.1 retro 마커 12건 보존 검증 (BL-05 ground-truth).
      final phase131Hits = 'Updated by Phase 13.1 retroactive'
          .allMatches(content)
          .length;

      // Assert — Phase 13.1 흔적 12건 변경 0 (Wave 3 가 Facebook 단락만 정정,
      // Phase 13.1 흔적 변경 0 의무).
      expect(
        phase131Hits,
        12,
        reason:
            'Phase 13.2 R12 회귀 가드 — 13-UI-SPEC.md Phase 13.1 retro 마커 '
            'hit = $phase131Hits (target = 12, history 보존 의무). '
            'Wave 3 는 Facebook 단락만 정정, Phase 13.1 흔적 변경 0.',
      );
    });

    test('Phase 13.2 R13: docs/manual.md 의 retro 마커 ≥ 1 + Meta 공식 URL + '
        '라이선스 verbatim + Facebook entry "Phase 18" 폐기', () {
      // Arrange.
      final manual = File('docs/manual.md');
      expect(manual.existsSync(), isTrue, reason: 'docs/manual.md 부재');
      final content = manual.readAsStringSync();

      // Act — Phase 13.2 retro 마커 (Wave 3 retro 후 ≥ 1).
      final retroHits = 'Updated by Phase 13.2 retroactive'
          .allMatches(content)
          .length;

      // Assert — Wave 3 retro 후 ≥ 1 (현재 0 → RED).
      expect(
        retroHits,
        greaterThanOrEqualTo(1),
        reason:
            'Phase 13.2 R13 acceptance 위반 — docs/manual.md Phase 13.2 '
            'retro 마커 hit = $retroHits (target ≥ 1, Wave 3 후 GREEN).',
      );

      // Act — Meta 공식 URL substring (둘 중 하나 hit ≥ 1).
      final metaUrlHits =
          'meta.com/brand/resources/facebook'.allMatches(content).length +
          'developers.facebook.com/docs/facebook-login'
              .allMatches(content)
              .length;

      // Assert — Wave 3 retro 후 Meta 공식 URL ≥ 1 hit.
      expect(
        metaUrlHits,
        greaterThanOrEqualTo(1),
        reason:
            'Phase 13.2 R13 acceptance 위반 — docs/manual.md Meta 공식 URL '
            'hit = $metaUrlHits (target ≥ 1, Wave 3 후 GREEN). '
            'Provider 표 Facebook entry 의 공식 BI URL 갱신 의무.',
      );

      // Act — Meta 라이선스 verbatim substring (Wave 0 lock 결과 의존).
      // Wave 0 LOCK 인용: `Meta's trademarks are owned by Meta and may only
      // be used as provided in these guidelines or with Meta's permission.`
      final licenseHits = "Meta's trademarks".allMatches(content).length;

      // Assert — Wave 3 retro 후 라이선스 verbatim ≥ 1 hit.
      expect(
        licenseHits,
        greaterThanOrEqualTo(1),
        reason:
            'Phase 13.2 R13 acceptance 위반 — docs/manual.md Meta 라이선스 '
            "verbatim (\"Meta's trademarks\") hit = $licenseHits "
            '(target ≥ 1, Wave 3 후 GREEN).',
      );

      // Act — Facebook entry 의 "Phase 18" 단어 0 hit 검증 (substring
      // anchoring — line 번호 shift 회피).
      // Wave 3 retro 가 line 1168 / 1181 의 Facebook entry 의 "Phase 18"
      // 문자열을 폐기 의무 (manual baseline grep: 4 hit 잔존, 1168/1181 은
      // Facebook entry, 278/369/547 은 unrelated phase reference 잔존 가능).
      // 본 test 는 Facebook entry 의 핵심 표 column (`Facebook |`) 행을
      // line filter 후 "Phase 18" hit 0 검증으로 anchor.
      final lines = content.split('\n');
      final facebookEntryHits = lines
          .where(
            (l) => l.contains('| Facebook') || l.contains('facebook/README'),
          )
          .where((l) => l.contains('Phase 18'))
          .length;

      // Assert — Facebook entry 본문 "Phase 18" 단어 0 (현재 ≥ 2 → RED).
      expect(
        facebookEntryHits,
        0,
        reason:
            'Phase 13.2 R13 acceptance 위반 — docs/manual.md Facebook '
            'entry 의 "Phase 18" 단어 hit = $facebookEntryHits (target = 0, '
            'Wave 3 후 GREEN). Facebook entry 만 정정, 다른 unrelated phase '
            'reference 는 변경 0 보존.',
      );
    });

    // SENTINEL: 시작부터 GREEN — R17 회귀 가드, RED gate 와 분리 (WR-04 fix).
    //
    // Test 12 (R17): `signInWithFacebook` 함수 body 안에 helper 호출 path
    // 보존 회귀 가드. Wave 1+ 코드 마이그가 `_autoSendEmailVerification` /
    // `_setFacebookPhotoUrl` 호출 path 를 건드리면 RED — Phase 9.2 R4/R5
    // helper 작동 회귀 차단. 본 test 는 commit 시점 GREEN (회귀 가드 sentinel),
    // 다른 7 test (Test 5~11) 의 Wave 1+ RED gate 와 의도 분리.
    test('Phase 13.2 R17 SENTINEL: auth_repository signInWithFacebook 의 '
        '_autoSendEmailVerification + _setFacebookPhotoUrl 호출 path 보존', () {
      // Arrange.
      final repo = File('lib/features/auth/data/auth_repository.dart');
      expect(repo.existsSync(), isTrue, reason: 'auth_repository.dart 부재');
      final content = repo.readAsStringSync();

      // Phase 13.2 REVIEW WR-04 정정 (2026-05-13): 함수 body 추출 fragile
      // (literal indexOf + indent 의존 substring) → 정규식 기반 + brace
      // counting robust 패턴 전환. (1) 함수 반환 타입 변경 (예: Stream,
      // void) 회귀 시 root cause 가림 해소, (2) class indent 변경 시 false
      // positive PASS 차단, (3) nested `Future<List<X>>` 등 generic 안의
      // substring 매칭 우회.
      final pattern = RegExp(
        r'^\s*[A-Za-z<>?,\s]+\s+signInWithFacebook\s*\([^)]*\)\s*(?:async\s*)?\{',
        multiLine: true,
      );
      final match = pattern.firstMatch(content);
      expect(
        match,
        isNotNull,
        reason:
            'WR-04 회귀 가드 — signInWithFacebook 함수 시그니처 부재. '
            'auth_repository 의 함수 명 변경 / 시그니처 refactor 회귀 '
            '가능성. R17 sentinel 대상 미존재.',
      );
      // `{` 부터 매칭하는 `}` 까지 brace depth counting 으로 body 추출.
      var depth = 1;
      var idx = match!.end;
      while (depth > 0 && idx < content.length) {
        final ch = content[idx];
        if (ch == '{') {
          depth += 1;
        } else if (ch == '}') {
          depth -= 1;
        }
        idx += 1;
      }
      expect(
        depth,
        0,
        reason: 'WR-04 회귀 가드 — signInWithFacebook brace 미균형 (구문 손상).',
      );
      final body = content.substring(match.end, idx);

      // Assert — body 안에 두 helper 호출 substring ≥ 1 each.
      expect(
        '_autoSendEmailVerification'.allMatches(body).length,
        greaterThanOrEqualTo(1),
        reason:
            'Phase 13.2 R17 SENTINEL 회귀 — signInWithFacebook body 안 '
            '_autoSendEmailVerification 호출 부재. Phase 9.2 helper 호출 '
            'path 변경 0 의무.',
      );
      expect(
        '_setFacebookPhotoUrl'.allMatches(body).length,
        greaterThanOrEqualTo(1),
        reason:
            'Phase 13.2 R17 SENTINEL 회귀 — signInWithFacebook body 안 '
            '_setFacebookPhotoUrl 호출 부재. Phase 9.2 helper 호출 path '
            '변경 0 의무.',
      );
    });

    // SENTINEL: Phase 13.3 code review CR-01 정정 (2026-05-17).
    //
    // Wave 4 Step 2 에서 Facebook 자상을 PNG → SVG (`btn_signin_icon.svg`)
    // 로 전환했으나 stale `facebook_login.png` 가 git tracked 잔존 +
    // `pubspec.yaml` 의 `- assets/brand/facebook/` directory-level 등록이
    // production bundle 에 PNG 도 동봉 → Meta brand license 혼동 위험.
    //
    // CR-01 fix commit 에서 `git rm` 으로 PNG 폐기 + 본 sentinel 신규로
    // 회귀 가드. 미래 갱신자가 `facebook_login.png` 를 재commit 하면 RED.
    test('Phase 13.3 CR-01 SENTINEL: facebook_login.png 자상 부재 의무 '
        '(Wave 4 Step 2 PNG → SVG 전환 후 stale asset 폐기)', () {
      final stalePng = File('assets/brand/facebook/facebook_login.png');
      expect(
        stalePng.existsSync(),
        isFalse,
        reason:
            'Phase 13.3 CR-01 회귀 — facebook_login.png 가 재commit 됨. '
            'Wave 4 Step 2 (2026-05-15) PNG → SVG 전환 후 Meta brand '
            'license 혼동 위험 회피 위해 폐기 의무. Facebook 자상은 '
            'assets/brand/facebook/btn_signin_icon.svg 단독.',
      );
    });
  });
}
