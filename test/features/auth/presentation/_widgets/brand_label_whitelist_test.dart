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
/// **Phase 13.3 verbatim restored (2026-05-15 Wave 4 D-111):** Phase 13.1
/// Gap-1 X2 (2026-05-09 자상화) 의 6 SKIP (Naver ko/en/ja + Kakao ko/en/ja)
/// 모두 풀기 — Universal Layout Pattern (Wave 2) 으로 wide 자상 통째 buttons
/// 패턴 폐기 + ARB 라벨 layer 부활 → ARB ↔ BI 화이트리스트 양방향 검증 부활.
/// 본 file 의 PASS/FAIL 카운트: Apple 3 PASS + Naver 3 PASS + Kakao 3 PASS =
/// 9 test (9 PASS / 0 SKIP / 0 FAIL).

/// Apple HIG 공식 라벨 테이블 (D-78-CLARIFY ko + D-77-CLARIFY ja).
///
/// `[VERIFIED:` developer.apple.com/kr/design/human-interface-guidelines/sign-in-with-apple `]`
const Map<String, Map<String, String>> _kAppleHIG =
    <String, Map<String, String>>{
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
const Map<String, Map<String, String>> _kNaverBI =
    <String, Map<String, String>>{
      'authNaverSignIn': <String, String>{
        'ko': '네이버 아이디로 로그인', // Phase 13.3 Wave 5 (2026-05-17) — NAVER 공식 SDK (Nid-OAuth values-ko/message.xml + 공식 BI 가이드) verbatim. Phase 13.3 Wave 1 의 "네이버 로그인" supersede.
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
const Map<String, Map<String, String>> _kKakaoBI =
    <String, Map<String, String>>{
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
      reason:
          '$localeCode 의 ${entry.key} ARB 값이 BI/HIG 화이트리스트와 drift '
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

  // Phase 13.3 verbatim restored (Wave 4 D-111) — Universal Layout Pattern
  // 으로 wide 자상 통째 buttons 패턴 폐기 (Wave 2 `_renderNaverButton`).
  // ARB authNaverSignIn 값이 위제 트리에 Text 라벨 layer 로 부활 — ARB ↔ Naver
  // BI 화이트리스트 양방향 검증 부활. Phase 13.1 Gap-1 X2 SKIP 정책 종료.
  //
  // **ARB 키 단일 진실원:** authNaverSignIn ko/en/ja 값은 SocialButton._resolveLabel
  // 매핑 + `_renderNaverButton` 의 Text 위제 + a11y Semantics(label) 매개변수에
  // 동시 적용. 본 const Map 이 화이트리스트 단일 진실원.
  group(
    'brand_label_whitelist — Naver BI (R7) [Phase 13.3 verbatim restored]',
    () {
      test('ko: 네이버 아이디로 로그인 (NAVER 공식 SDK + BI 가이드 verbatim, Wave 5 정정)', () async {
        await _verifyLocale('ko', _kNaverBI);
      });
      test('en: Log in with NAVER (공식 AI EN variant verbatim)', () async {
        await _verifyLocale('en', _kNaverBI);
      });
      test(
        'ja: NAVERでログイン (D-110 ja verbatim — D-79 영문 fallback 폐기)',
        () async {
          await _verifyLocale('ja', _kNaverBI);
        },
      );
    },
  );

  // Phase 13.3 verbatim restored (Wave 4 D-111) — Kakao 도 Universal Layout
  // Pattern (Wave 2 `_renderKakaoButton`) 으로 라벨 layer 부활.
  group(
    'brand_label_whitelist — Kakao BI (R7) [Phase 13.3 verbatim restored]',
    () {
      test('ko: 카카오 로그인 (공식 Kakao Design Guide ko verbatim)', () async {
        await _verifyLocale('ko', _kKakaoBI);
      });
      test(
        'en: Login with Kakao (공식 Kakao Design Guide en verbatim)',
        () async {
          await _verifyLocale('en', _kKakaoBI);
        },
      );
      test(
        'ja: Kakaoでログイン (D-110 ja verbatim — D-79 영문 fallback 폐기)',
        () async {
          await _verifyLocale('ja', _kKakaoBI);
        },
      );
    },
  );
}
