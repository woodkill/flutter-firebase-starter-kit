// Phase 13.1 — see ROADMAP.md (D-76 brand_assets_lint scope — R9/R10/R11)

import 'dart:io';

import 'package:flutter_starter_kit/features/auth/presentation/_widgets/_brand_assets.dart';
import 'package:flutter_test/flutter_test.dart';

/// `assets/brand/{provider}/.placeholder` sentinel + README 7필드 schema 검증
/// — Phase 13.1 D-76 (R9/R10/R11 covers).
///
/// **scope:** 7 provider 디렉토리 순회.
/// 1. LINE/WeChat `.placeholder` 존재 — sentinel 의도 (Phase 14/16 진입 전)
/// 2. Kakao/Naver/Google/Apple/Facebook `.placeholder` 부재 — 자상 commit 의도
///   - Wave 0 시점에는 active 5 provider 도 자상 미commit 이라 일부 RED.
///     본 plan 의 acceptance 는 Plan 13.1-03 sentinel 정비 commit 후 PASS.
/// 3. 7 provider README 7필드 모두 비어있지 않음 (heading 패턴 매칭)
///
/// **RED→GREEN tracking:**
/// - Plan 13.1-04 commit 시점: 본 test 파일 단독 — 모든 group PASS
///   (Plan 13.1-03 의 7 README + LINE/WeChat .placeholder 사전 commit 의존).
/// - Plan 13.1-07 commit 후: Group 2 보존 (active 5 .placeholder 부재 유지) +
///   Group 1 그대로 (LINE/WeChat sentinel 보존 — Phase 14/16 진입 전).
void main() {
  group('brand_assets_lint', () {
    test('LINE/WeChat .placeholder 존재 — 자상 commit 후 제거 의무', () {
      for (final p in kPlaceholderProviders) {
        final placeholder = File('$kBrandAssetBase/$p/.placeholder');
        expect(
          placeholder.existsSync(),
          isTrue,
          reason: '$p 디렉토리의 .placeholder 가 사라졌으나 자산이 commit '
              '안 되었거나 _brand_assets.dart 의 list 갱신 누락',
        );
      }
    });

    test('Kakao/Naver/Google/Apple/Facebook .placeholder 부재 — 자산 commit 후 PASS', () {
      const activeProviders = <String>[
        'kakao',
        'naver',
        'google',
        'apple',
        'facebook',
      ];
      for (final p in activeProviders) {
        final placeholder = File('$kBrandAssetBase/$p/.placeholder');
        expect(
          placeholder.existsSync(),
          isFalse,
          reason: '$p 의 .placeholder 가 자산 commit 후 제거되지 않음',
        );
      }
    });

    test('7 provider README 7필드 모두 채워짐', () {
      const allProviders = <String>[
        'kakao',
        'naver',
        'google',
        'apple',
        'facebook',
        'line',
        'wechat',
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
    // 기존 Group 1 (LINE/WeChat .placeholder) + Group 2 (active 5 .placeholder
    // 부재) + Group 3 (7 README schema) 만으로는 자상 파일 자체 삭제 회귀
    // (예: assets/brand/google/light/btn_signin_full.svg 실수 삭제) 시
    // golden test 만 RED 로 늦게 발견. 본 group 이 생산 production widget
    // 이 의존하는 모든 (provider × locale × theme × variant) tuple 의 자상
    // path 존재를 컴파일 시점에 검출.
    test('Kakao 자상 (locale × {large}_wide PNG) 모두 존재', () {
      const sizes = <String>['large']; // production default; medium 은 future-proof
      for (final lang in <String>['ko', 'en']) {
        for (final size in sizes) {
          final path =
              '$kBrandAssetBase/kakao/$lang/light/kakao_login_${size}_wide.png';
          expect(
            File(path).existsSync(),
            isTrue,
            reason: 'production widget 의존 자상 부재: $path',
          );
        }
      }
    });

    test('Naver 자상 (locale × theme × h48 PNG) 모두 존재', () {
      for (final lang in <String>['ko', 'en']) {
        for (final theme in <String>['light', 'dark']) {
          final path =
              '$kBrandAssetBase/naver/$lang/$theme/naver_login_h48_wide.png';
          expect(
            File(path).existsSync(),
            isTrue,
            reason: 'production widget 의존 자상 부재: $path',
          );
        }
      }
    });

    test('Google 자상 (theme × full SVG) 모두 존재', () {
      for (final theme in <String>['light', 'dark', 'neutral']) {
        final path = '$kBrandAssetBase/google/$theme/btn_signin_full.svg';
        expect(
          File(path).existsSync(),
          isTrue,
          reason: 'production widget 의존 자상 부재: $path',
        );
      }
    });
  });
}
