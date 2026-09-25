// Phase 13.1 — see ROADMAP.md (D-77/D-78-CLARIFY/D-77-CLARIFY ARB↔HIG/BI 양방향 검증)
// Phase 16 D-11 — authAccountProvider{X} 7 ARB key 의 brand verbatim audit
//   trail 신규 4 testcase add (Google/Facebook/Email/LINE).
//   Apple/Naver/Kakao 3 은 sign-in 버튼 라벨 검증으로 이미 보유 — 본 plan 은
//   계정 표시용 provider label (settings linkedProviders + account linking
//   sheet provider 텍스트) 의 audit trail 확장.

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
const Map<String, Map<String, String>>
_kNaverBI = <String, Map<String, String>>{
  'authNaverSignIn': <String, String>{
    'ko':
        '네이버 아이디로 로그인', // Phase 13.3 Wave 5 (2026-05-17) — NAVER 공식 SDK (Nid-OAuth values-ko/message.xml + 공식 BI 가이드) verbatim. Phase 13.3 Wave 1 의 "네이버 로그인" supersede.
    'en': 'Log in with NAVER', // 공식 AI EN variant verbatim
    'ja': 'NAVERでログイン', // [ASSUMED] 패턴 일관성 (Apple/Google/Facebook mirror)
  },
};

/// Facebook BI 화이트리스트 (Phase 13.3 Wave 5 신규 — Login mirror 통일).
///
/// Source-of-truth:
/// - en: 공식 Facebook Login UX 가이드 (`developers.facebook.com/docs/
///   facebook-login/userexperience/`) 의 preferred 화이트리스트 "Continue
///   with Facebook" / "Login with Facebook" 중 #2 (Login) 채택 — user 결정
///   2026-05-17 (3 locale Login mirror 통일).
/// - ko: 정문 미명시 자유 영역 — "Facebook으로 로그인" ("Apple/Google로 로그인"
///   외래어+조사 붙임 패턴 mirror). user 결정 2026-05-17.
/// - ja: 정문 미명시 자유 영역 — [ASSUMED] "Facebookでログイン" (Login mirror
///   직역, Apple/Google/Kakao/Naver ja mirror).
const Map<String, Map<String, String>> _kFacebookBI =
    <String, Map<String, String>>{
      'authFacebookSignIn': <String, String>{
        'ko': 'Facebook으로 로그인', // Wave 5 정정 — Login mirror (Apple/Google 패턴)
        'en': 'Login with Facebook', // preferred 화이트리스트 #2 (Wave 5 정정)
        'ja': 'Facebookでログイン', // [ASSUMED] Login mirror (자유 영역)
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
      'authFacebookSignIn' => l10n.authFacebookSignIn,
      // Phase 16 D-11 — authAccountProvider{X} 7 키 매핑
      'authAccountProviderGoogle' => l10n.authAccountProviderGoogle,
      'authAccountProviderFacebook' => l10n.authAccountProviderFacebook,
      'authAccountProviderEmailPassword' =>
        l10n.authAccountProviderEmailPassword,
      'authAccountProviderLine' => l10n.authAccountProviderLine,
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

/// Phase 16 D-11 — Google 계정 표시 라벨 audit trail.
///
/// Source-of-truth:
/// - Google Identity 공식 brand 가이드는 'Google' wordmark 만 사용 권장 —
///   3 locale 모두 'Google' verbatim (Phase 13.3 검증).
const Map<String, Map<String, String>> _kGoogleAccountLabel =
    <String, Map<String, String>>{
      'authAccountProviderGoogle': <String, String>{
        'ko': 'Google',
        'en': 'Google',
        'ja': 'Google',
      },
    };

/// Phase 16 D-11 — Facebook 계정 표시 라벨 audit trail.
///
/// Source-of-truth:
/// - Meta brand 가이드 — 'Facebook' wordmark 만 사용 권장. 3 locale verbatim.
const Map<String, Map<String, String>> _kFacebookAccountLabel =
    <String, Map<String, String>>{
      'authAccountProviderFacebook': <String, String>{
        'ko': 'Facebook',
        'en': 'Facebook',
        'ja': 'Facebook',
      },
    };

/// Phase 16 D-11 — Email/Password 계정 표시 라벨 audit trail.
///
/// Source-of-truth:
/// - starter-kit 일관 — Phase 9.2 P-A-narrow 산출 (auth_email_* ARB 라인 mirror).
///   ko='이메일 / 비밀번호' / en='Email / Password' / ja='メール / パスワード'.
///   (Plan 16-05 본문은 ko='이메일' 단순화 제안하나 P-A-narrow 락 본문 보존 —
///   세팅 surface 의 라벨 정합성 우선.)
const Map<String, Map<String, String>> _kEmailAccountLabel =
    <String, Map<String, String>>{
      'authAccountProviderEmailPassword': <String, String>{
        'ko': '이메일 / 비밀번호',
        'en': 'Email / Password',
        'ja': 'メール / パスワード',
      },
    };

/// Phase 16 D-11 — LINE 계정 표시 라벨 audit trail.
///
/// Source-of-truth:
/// - LINE 공식 brand 자산 (Phase 14 verbatim 검증). en/ja 는 'LINE' 영문
///   wordmark 권장. ko 는 starter-kit 의 Phase 9.2 P-A-narrow 산출 '라인' 한글
///   표기 보존 (외래어 표기법 준수). [ASSUMED 2026-05-29] ko 한글 표기 —
///   향후 공식 KR locale 자상 출시 시 재검증 의무.
const Map<String, Map<String, String>> _kLineAccountLabel =
    <String, Map<String, String>>{
      'authAccountProviderLine': <String, String>{
        'ko': '라인', // [ASSUMED 2026-05-29] starter-kit Phase 9.2 한글 표기 보존
        'en': 'LINE',
        'ja': 'LINE',
      },
    };

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
      test(
        'ko: 네이버 아이디로 로그인 (NAVER 공식 SDK + BI 가이드 verbatim, Wave 5 정정)',
        () async {
          await _verifyLocale('ko', _kNaverBI);
        },
      );
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

  // Phase 13.3 Wave 5 (2026-05-17) — Facebook BI 화이트리스트 회귀 가드 신규.
  // Login mirror 통일 (en "Login with Facebook" preferred 화이트리스트 #2 +
  // ko "Facebook으로 로그인" Apple/Google mirror + ja "Facebookでログイン"
  // [ASSUMED] Login mirror) — 향후 silent ARB drift 회귀 방지.
  group('brand_label_whitelist — Facebook BI (Wave 5) [Login mirror 통일]', () {
    test('ko: Facebook으로 로그인 (Wave 5 — Apple/Google mirror)', () async {
      await _verifyLocale('ko', _kFacebookBI);
    });
    test('en: Login with Facebook (preferred 화이트리스트 #2, Wave 5)', () async {
      await _verifyLocale('en', _kFacebookBI);
    });
    test('ja: Facebookでログイン ([ASSUMED] Login mirror — 자유 영역)', () async {
      await _verifyLocale('ja', _kFacebookBI);
    });
  });

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

  // Phase 16 D-11 — authAccountProvider{X} 7 ARB key 의 brand verbatim
  // audit trail 4 신규 testcase (Google/Facebook/Email/LINE).
  // Apple/Naver/Kakao 3 provider 의 sign-in 버튼 라벨 검증은 위 group 들이
  // 보유 — 본 group 들은 계정 표시용 provider label
  // (settings linkedProviders + account_linking_sheet provider 텍스트) 의
  // ARB drift 회귀 가드. Phase 13.1 D-84 + Phase 15 mirror.
  group('brand_label_whitelist — Google AccountLabel (Phase 16 D-11) B1', () {
    test('ko: Google (Google Identity verbatim — 3 locale 동일)', () async {
      await _verifyLocale('ko', _kGoogleAccountLabel);
    });
    test('en: Google (Google Identity verbatim)', () async {
      await _verifyLocale('en', _kGoogleAccountLabel);
    });
    test('ja: Google (Google Identity verbatim)', () async {
      await _verifyLocale('ja', _kGoogleAccountLabel);
    });
  });

  group('brand_label_whitelist — Facebook AccountLabel (Phase 16 D-11) B2', () {
    test('ko: Facebook (Meta brand verbatim — 3 locale 동일)', () async {
      await _verifyLocale('ko', _kFacebookAccountLabel);
    });
    test('en: Facebook (Meta brand verbatim)', () async {
      await _verifyLocale('en', _kFacebookAccountLabel);
    });
    test('ja: Facebook (Meta brand verbatim)', () async {
      await _verifyLocale('ja', _kFacebookAccountLabel);
    });
  });

  group('brand_label_whitelist — Email AccountLabel (Phase 16 D-11) B3', () {
    test('ko: 이메일 / 비밀번호 (starter-kit Phase 9.2 P-A-narrow lock)', () async {
      await _verifyLocale('ko', _kEmailAccountLabel);
    });
    test('en: Email / Password (Phase 9.2 P-A-narrow lock)', () async {
      await _verifyLocale('en', _kEmailAccountLabel);
    });
    test('ja: メール / パスワード (Phase 9.2 P-A-narrow lock)', () async {
      await _verifyLocale('ja', _kEmailAccountLabel);
    });
  });

  group('brand_label_whitelist — LINE AccountLabel (Phase 16 D-11) B4', () {
    test(
      'ko: 라인 ([ASSUMED 2026-05-29] starter-kit Phase 9.2 한글 표기 보존)',
      () async {
        await _verifyLocale('ko', _kLineAccountLabel);
      },
    );
    test('en: LINE (LINE 공식 brand 자산 verbatim)', () async {
      await _verifyLocale('en', _kLineAccountLabel);
    });
    test('ja: LINE (LINE 공식 brand 자산 verbatim)', () async {
      await _verifyLocale('ja', _kLineAccountLabel);
    });
  });
}
