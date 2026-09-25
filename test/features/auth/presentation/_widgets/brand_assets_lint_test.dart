// Phase 13.1 — see ROADMAP.md (D-76 brand_assets_lint scope — R9/R10/R11)

import 'dart:io';

import 'package:flutter_starter_kit/features/auth/presentation/_widgets/_brand_assets.dart';
import 'package:flutter_test/flutter_test.dart';

/// `assets/brand/{provider}/.placeholder` sentinel + README 7필드 schema 검증
/// — Phase 13.1 D-76 (R9/R10/R11 covers).
///
/// **scope:** 6 active provider 디렉토리 순회 (모든 provider 자상 commit
/// 완료, kPlaceholderProviders empty).
/// 1. kPlaceholderProviders empty 검증 — sentinel 의무 해소 (Phase 14 LINE
///   active 전환과 이후 마지막 placeholder 해제 후 caller 0)
/// 2. 6 active provider `.placeholder` 부재 — 자상 commit 완료 검증
/// 3. 6 provider README 7필드 모두 비어있지 않음 (heading 패턴 매칭)
///
/// **갱신 가이드:** 향후 placeholder 가 필요한 신규 provider 진입 시:
/// - `_brand_assets.dart` 의 `kPlaceholderProviders` 에 슬러그 추가
/// - `assets/brand/{provider}/.placeholder` sentinel 파일 commit
/// - 본 Group 1 이 empty 검증 fail → sentinel 존재 검증 group 으로 보강
void main() {
  group('brand_assets_lint', () {
    test('kPlaceholderProviders empty — 모든 active provider 자상 commit 완료', () {
      // Phase 14 D-LINE-08 (2026-05-19): LINE sentinel 해제 — 이후 마지막
      // placeholder 해제로 목록이 비었다.
      expect(
        kPlaceholderProviders,
        isEmpty,
        reason:
            'kPlaceholderProviders 가 non-empty — 신규 placeholder '
            'provider 진입 시 본 검증을 sentinel 파일 존재 검증으로 보강 의무',
      );
    });

    test(
      'Kakao/Naver/Google/Apple/Facebook/LINE .placeholder 부재 — 자산 commit 후 PASS',
      () {
        // Phase 14 D-LINE-08 (2026-05-19): LINE sentinel → active 전환.
        // 6 active 모두 자상 commit 완료, kPlaceholderProviders = <String>[].
        const activeProviders = <String>[
          'kakao',
          'naver',
          'google',
          'apple',
          'facebook',
          'line',
        ];
        for (final p in activeProviders) {
          final placeholder = File('$kBrandAssetBase/$p/.placeholder');
          expect(
            placeholder.existsSync(),
            isFalse,
            reason: '$p 의 .placeholder 가 자산 commit 후 제거되지 않음',
          );
        }
      },
    );

    test('6 provider README 7필드 모두 채워짐', () {
      // 6 active provider (kakao/naver/google/apple/facebook/line).
      const allProviders = <String>[
        'kakao',
        'naver',
        'google',
        'apple',
        'facebook',
        'line',
      ];
      const requiredHeadings = <String>[
        '## 공식 BI URL',
        '## 자산 다운로드 URL',
        '## 다운로드 일자',
        '## 라이선스',
        '## 사전 검수 절차',
        '## 미포함 변형 추가 절차',
        '## 자산 freshness 갱신 빈도',
      ];
      for (final p in allProviders) {
        final readme = File('$kBrandAssetBase/$p/README.md');
        expect(readme.existsSync(), isTrue, reason: '$p README 부재');
        final content = readme.readAsStringSync();
        for (final heading in requiredHeadings) {
          expect(
            content,
            contains(heading),
            reason: '$p README 7필드 중 $heading 누락',
          );
        }
      }
    });

    // Phase 13.1 REVIEW WR-08 정정 (2026-05-10) — production widget 의
    // `_iconAssetFor` 가 실제 로드하는 자상 path 가 disk 에 존재하는지 검증.
    // 기존 Group 1 (kPlaceholderProviders empty) + Group 2 (6 active
    // .placeholder 부재) + Group 3 (6 README schema) 만으로는 자상 파일 자체 삭제 회귀
    // (예: assets/brand/google/light/btn_signin_full.svg 실수 삭제) 시
    // golden test 만 RED 로 늦게 발견.
    //
    // **Phase 13.3 code review IN-04 정정 (2026-05-17):** Wave 3 (commit
    // c73c9a3) wide 자상 통째 buttons 패턴 폐기 + 5 wave 종결 후 "재검토"
    // 의도 무효 — skip 처리된 3 test (Kakao large_wide / Naver h48_wide /
    // Google btn_signin_full) 모두 폐기 결정 lock. 자상 자체 존재 회귀 가드는
    // `branded_social_button_test.dart` 의 widget tree assertion (예:
    // T-13.3-KAKAO-WIDE-PNG-MISSING-01) + `_iconAssetFor` 의 inline path
    // string 으로 일관 위임. 본 group 은 폐기 cleanup.
  });
}
