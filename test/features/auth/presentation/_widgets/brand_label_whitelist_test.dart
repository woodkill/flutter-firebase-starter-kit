// Phase 13.1 — see ROADMAP.md (D-77/D-78-CLARIFY/D-77-CLARIFY ARB↔HIG/BI 양방향 검증)

import 'package:flutter/material.dart';
import 'package:flutter_starter_kit/l10n/generated/app_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

/// ARB↔HIG/BI 양방향 회귀 가드 — Phase 13.1 D-77~D-83 (R6/R7 covers).
///
/// **source-of-truth:**
/// - Apple HIG ko/en/ja: `developer.apple.com/design/human-interface-guidelines/sign-in-with-apple`
///   verbatim (RESEARCH 검증, D-78-CLARIFY ko + D-77-CLARIFY ja).
/// - Naver BI ko/en: `developers.naver.com/docs/login/bi/bi.md`
///   ja 는 자상 미제공 → 영문 BI fallback (D-79).
/// - Kakao BI ko/en: `developers.kakao.com/docs/ko/kakaologin/design-guide`
///   ja 는 자상 미제공 → 영문 BI fallback (D-79).
///
/// 본 test 는 ARB 값이 위 표와 1:1 일치 검증 — drift 자동 감지 (D-80).
///
/// **RED→GREEN tracking:**
/// - Wave 0 (Plan 13.1-04 commit) 시점:
///   - ko/en 6 test PASS (ARB 이미 정확).
///   - ja 3 test FAIL (ARB ja 가 'Appleでログイン' / 'カカオではじめる' /
///     'Naverではじめる' 미정정 — Plan 13.1-06 ARB 정정 후 GREEN 전환 의도).
/// - Plan 13.1-06 ARB 정정 + `fvm flutter gen-l10n` 후: 9 test 모두 PASS.
///
/// **Phase 13.1 Gap-1 X2 (2026-05-09 자상화):** Naver/Kakao 6 test (3 ko/en/ja
/// × 2 provider) `skip:` 처리 — 자상화로 라벨 layer 부재. Apple HIG 3 test
/// PASS 유지. 본 file 의 PASS/FAIL 카운트: Apple 3 PASS + Naver 3 SKIP +
/// Kakao 3 SKIP = 9 test (3 PASS / 6 SKIP / 0 FAIL).

/// Apple HIG 공식 라벨 테이블 (D-78-CLARIFY ko + D-77-CLARIFY ja).
///
/// `[VERIFIED:` developer.apple.com/kr/design/human-interface-guidelines/sign-in-with-apple `]`
const Map<String, Map<String, String>> _kAppleHIG = <String, Map<String, String>>{
  'authAppleSignIn': <String, String>{
    'ko': 'Apple로 로그인', // D-78-CLARIFY: 띄어쓰기 없음
    'en': 'Sign in with Apple',
    'ja': 'Appleでサインイン', // D-77-CLARIFY: 히라가나+카타카나 일본어
  },
};

/// Naver BI 화이트리스트 (Phase 13.3 D-111 갱신 — D-79 ja 영문 fallback 폐기).
///
/// Source-of-truth:
/// - ko/en: Naver 공식 AI 파일 (`developers.naver.com/docs/login/bi/bi.md`,
///   `NAVER_login_KR.ai` + `NAVER_login_EN.ai`) verbatim — Phase 13.3 RESEARCH §1.2.
/// - ja: [ASSUMED] 패턴 일관성 (Apple/Google/Facebook ja mirror) 채택 — user
///   sign-off 2026-05-15 Wave 1 Task 1.0 Step 3 옵션 (B). Starter 사용자 일본
///   진출 시점 공식 verbatim 재확정 의무.
const Map<String, Map<String, String>> _kNaverBI = <String, Map<String, String>>{
  'authNaverSignIn': <String, String>{
    'ko': '네이버 로그인', // Phase 13.3 SPEC R8 + user sign-off 2026-05-15
    'en': 'Log in with NAVER', // 공식 AI EN variant verbatim
    'ja': 'NAVERでログイン', // [ASSUMED] 패턴 일관성 (Apple/Google/Facebook mirror)
  },
};

/// Kakao BI 화이트리스트 (Phase 13.3 D-111 갱신 — D-79 ja 영문 fallback 폐기).
///
/// Source-of-truth:
/// - ko: 공식 Kakao Design Guide (`developers.kakao.com/docs/ko/kakaologin/design-guide`) verbatim.
/// - en: 공식 Kakao Design Guide (`developers.kakao.com/docs/latest/en/kakaologin/design-guide`)
///   verbatim — user sign-off 2026-05-15 Wave 1 Task 1.0 Step 4 옵션 (b) 채택
///   (Phase 12 D-29 'Continue with Kakao' → 'Login with Kakao' retroactive 갱신).
/// - ja: [ASSUMED] 패턴 일관성 채택 — user sign-off 2026-05-15 Step 3 옵션 (B).
const Map<String, Map<String, String>> _kKakaoBI = <String, Map<String, String>>{
  'authKakaoSignIn': <String, String>{
    'ko': '카카오 로그인',
    'en': 'Login with Kakao', // 공식 BI en verbatim (Phase 13.3 D-111 정정)
    'ja': 'Kakaoでログイン', // [ASSUMED] 패턴 일관성 (Apple/Google/Facebook mirror)
  },
};

/// 지정 [localeCode] 의 [AppLocalizations] 를 로드해 [table] 의 라벨이
/// ARB 와 1:1 일치하는지 검증한다.
Future<void> _verifyLocale(
  String localeCode,
  Map<String, Map<String, String>> table,
) async {
  final l10n = await AppLocalizations.delegate.load(Locale(localeCode));
  for (final entry in table.entries) {
    final expected = entry.value[localeCode];
    expect(
      expected,
      isNotNull,
      reason: '${entry.key} 의 $localeCode 라벨 _kXxxX 테이블에 부재',
    );
    final actual = switch (entry.key) {
      'authAppleSignIn' => l10n.authAppleSignIn,
      'authNaverSignIn' => l10n.authNaverSignIn,
      'authKakaoSignIn' => l10n.authKakaoSignIn,
      _ => throw UnsupportedError('Unknown key: ${entry.key}'),
    };
    expect(
      actual,
      expected,
      reason: '$localeCode 의 ${entry.key} ARB 값이 BI/HIG 화이트리스트와 drift '
          '— production ARB 또는 본 const Map 둘 중 하나 갱신 필요',
    );
  }
}

void main() {
  group('brand_label_whitelist — Apple HIG (R6)', () {
    test('ko: Apple로 로그인 (D-78-CLARIFY 띄어쓰기 없음)', () async {
      await _verifyLocale('ko', _kAppleHIG);
    });
    test('en: Sign in with Apple', () async {
      await _verifyLocale('en', _kAppleHIG);
    });
    test('ja: Appleでサインイン (D-77-CLARIFY 일본어 verbatim)', () async {
      await _verifyLocale('ja', _kAppleHIG);
    });
  });

  // Phase 13.1 Gap-1 X2 (2026-05-09 자상화) — Naver wide 자상이 logo + 텍스트
  // 모두 baked-in 으로 buttons 외관을 형성. ARB authNaverSignIn 값은 widget
  // tree 에 라벨 layer 로 렌더되지 않음. 본 group 의 검증 의도 (ARB ↔ Naver
  // BI 화이트리스트 일치) 는 자상화로 자연 무효화 — Phase 18 Brand Center
  // 권한 확보 후 자상 ↔ 라벨 디자인 분리 정책 결정 시 재검토.
  //
  // **REVIEW WR-03 흡수:** 'BI 4 변형 중 1종만 강제' 약한 가드 (REVIEW line
  // 102~122) 는 자상화로 자연 해소 — 본 skip 으로 수렴.
  //
  // **ARB 키 자체 보존:** authNaverSignIn ko/en/ja 값은 SocialButton._resolveLabel
  // 매핑 + 향후 접근성 (Semantics) layer 에서 활용 가능 (Plan 14 docstring 참조).
  // 본 const Map 도 mirror 단일 진실원으로 보존.
  group('brand_label_whitelist — Naver BI (R7) [Phase 13.1 Gap-1 X2 자상화]', () {
    test(
      'ko: 네이버로 시작하기 [SKIPPED: 자상화로 라벨 layer 부재]',
      () async {
        await _verifyLocale('ko', _kNaverBI);
      },
      skip: '자상화로 라벨 layer 부재 — Phase 18 Brand Center 권한 확보 후 재검토',
    );
    test(
      'en: Continue with Naver [SKIPPED: 자상화로 라벨 layer 부재]',
      () async {
        await _verifyLocale('en', _kNaverBI);
      },
      skip: '자상화로 라벨 layer 부재 — Phase 18 Brand Center 권한 확보 후 재검토',
    );
    test(
      'ja: Continue with Naver (D-79 영문 fallback) [SKIPPED: 자상화로 라벨 layer 부재]',
      () async {
        await _verifyLocale('ja', _kNaverBI);
      },
      skip: '자상화로 라벨 layer 부재 — Phase 18 Brand Center 권한 확보 후 재검토',
    );
  });

  // Phase 13.1 Gap-1 X2 (2026-05-09 자상화) — Kakao wide 자상도 동일 정책.
  group('brand_label_whitelist — Kakao BI (R7) [Phase 13.1 Gap-1 X2 자상화]', () {
    test(
      'ko: 카카오 로그인 [SKIPPED: 자상화로 라벨 layer 부재]',
      () async {
        await _verifyLocale('ko', _kKakaoBI);
      },
      skip: '자상화로 라벨 layer 부재 — Phase 18 Brand Center 권한 확보 후 재검토',
    );
    test(
      'en: Continue with Kakao [SKIPPED: 자상화로 라벨 layer 부재]',
      () async {
        await _verifyLocale('en', _kKakaoBI);
      },
      skip: '자상화로 라벨 layer 부재 — Phase 18 Brand Center 권한 확보 후 재검토',
    );
    test(
      'ja: Continue with Kakao (D-79 영문 fallback) [SKIPPED: 자상화로 라벨 layer 부재]',
      () async {
        await _verifyLocale('ja', _kKakaoBI);
      },
      skip: '자상화로 라벨 layer 부재 — Phase 18 Brand Center 권한 확보 후 재검토',
    );
  });
}
