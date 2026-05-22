// Phase 13.1 — see ROADMAP.md (D-77/D-78-CLARIFY/D-77-CLARIFY ARB↔HIG/BI 양방향 검증)
// Phase 15 — see ROADMAP.md (D-YJP-08 Yahoo!JP BI 라벨 12 testcase verbatim 매트릭스)

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

/// Yahoo! JAPAN BI 화이트리스트 (Phase 15 D-YJP-08).
///
/// Source-of-truth:
/// - ja: Yahoo!JP 공식 BI 가이드 verbatim
///   (`developer.yahoo.co.jp/yconnect/loginbuttons.html` 권장값
///   "「ログイン」または「Yahoo! JAPAN IDでログイン」" + yahoo_japan_login_button.zip
///   안 'Yahoo! JAPAN ID ログインボタン.pdf' altText
///   '適切な代替テキスト(例：alt="Yahoo! JAPAN IDでログイン")'). LINE ja 패턴 mirror —
///   Yahoo! JAPAN 은 일본 본사 (LY Corporation) 제공 + 일본어 원철 서비스 → ja 는
///   [ASSUMED] tag 아닌 공식 1차 출처.
/// - en: [ASSUMED] 차원 번역 — Yahoo!JP BI 가이드는 ja-only, en 권장 라벨 가이드
///   부재. starter-kit 차원 번역. Naver 'Sign in with Naver' 패턴 mirror.
/// - ko: [ASSUMED] 차원 번역 — Yahoo!JP BI 가이드 ko 권장값 부재. 외래어+조사 붙임
///   ('Yahoo! JAPAN' + '으로') Naver/LINE 패턴 mirror.
///
/// 금지어 sentinel (ja 기준 — BI 가이드 verbatim 금지어 매트릭스):
/// - 'Yahoo!でログイン' (브랜드 명사 'Yahoo! JAPAN' 누락)
/// - 'Yahoo! IDでログイン' ('JAPAN' 누락)
/// - 'Yahoo! JAPANでログイン' ('ID' 누락)
/// - 'Yahoo! JAPAN ID でログイン' (ID 뒤 띄어쓰기 회귀)
const Map<String, Map<String, String>> _kYahoojpBI =
    <String, Map<String, String>>{
      'authYahoojpSignIn': <String, String>{
        'ko': 'Yahoo! JAPAN으로 로그인', // [ASSUMED] 외래어+조사 (Naver/LINE mirror)
        'en': 'Sign in with Yahoo! JAPAN', // [ASSUMED] 차원 번역
        'ja': 'Yahoo! JAPAN IDでログイン', // 공식 BI 가이드 verbatim (D-YJP-08)
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
      'authYahoojpSignIn' => l10n.authYahoojpSignIn,
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

  // Phase 13.3 Wave 5 (2026-05-17) — Facebook BI 화이트리스트 회귀 가드 신규.
  // Login mirror 통일 (en "Login with Facebook" preferred 화이트리스트 #2 +
  // ko "Facebook으로 로그인" Apple/Google mirror + ja "Facebookでログイン"
  // [ASSUMED] Login mirror) — 향후 silent ARB drift 회귀 방지.
  group(
    'brand_label_whitelist — Facebook BI (Wave 5) [Login mirror 통일]',
    () {
      test('ko: Facebook으로 로그인 (Wave 5 — Apple/Google mirror)', () async {
        await _verifyLocale('ko', _kFacebookBI);
      });
      test(
        'en: Login with Facebook (preferred 화이트리스트 #2, Wave 5)',
        () async {
          await _verifyLocale('en', _kFacebookBI);
        },
      );
      test(
        'ja: Facebookでログイン ([ASSUMED] Login mirror — 자유 영역)',
        () async {
          await _verifyLocale('ja', _kFacebookBI);
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

  // Phase 15 Plan 15-05 (D-YJP-08) — Yahoo!JP BI 화이트리스트 12 testcase.
  // 공식 가이드 (`developer.yahoo.co.jp/yconnect/loginbuttons.html`) ja 권장값
  // 'Yahoo! JAPAN IDでログイン' verbatim + en/ko [ASSUMED] 차원 번역. ja 금지어
  // sentinel ('Yahoo!でログイン' / 'Yahoo! IDでログイン' / 'Yahoo! JAPANでログイン')
  // + ID 뒤 띄어쓰기 회귀 + Sign in/으로 로그인 prefix/suffix 일관 + 변형 위반
  // (Sign up / 가입) + 3 locale brand integrity ('Yahoo! JAPAN' 포함).
  group('brand_label_whitelist — Yahoo!JP BI (Phase 15 D-YJP-08)', () {
    // 정상 verbatim — 3 locale 권장값 (Test 1~3)
    test('ja: Yahoo! JAPAN IDでログイン (BI 가이드 verbatim)', () async {
      await _verifyLocale('ja', _kYahoojpBI);
    });
    test('en: Sign in with Yahoo! JAPAN ([ASSUMED] tag)', () async {
      await _verifyLocale('en', _kYahoojpBI);
    });
    test('ko: Yahoo! JAPAN으로 로그인 ([ASSUMED] tag)', () async {
      await _verifyLocale('ko', _kYahoojpBI);
    });
    // ja 금지어 sentinel (Test 4~6) — BI 가이드 verbatim 금지어 매트릭스
    test('ja 금지어 1: Yahoo!でログイン 채택 불가', () async {
      final l10n = await AppLocalizations.delegate.load(const Locale('ja'));
      expect(
        l10n.authYahoojpSignIn,
        isNot(equals('Yahoo!でログイン')),
        reason: '브랜드 명사 "Yahoo! JAPAN" 누락 — BI 가이드 금지어',
      );
    });
    test('ja 금지어 2: Yahoo! IDでログイン 채택 불가', () async {
      final l10n = await AppLocalizations.delegate.load(const Locale('ja'));
      expect(
        l10n.authYahoojpSignIn,
        isNot(equals('Yahoo! IDでログイン')),
        reason: '"JAPAN" 누락 — BI 가이드 금지어',
      );
    });
    test('ja 금지어 3: Yahoo! JAPANでログイン 채택 불가', () async {
      final l10n = await AppLocalizations.delegate.load(const Locale('ja'));
      expect(
        l10n.authYahoojpSignIn,
        isNot(equals('Yahoo! JAPANでログイン')),
        reason: '"ID" 누락 — BI 가이드 금지어',
      );
    });
    // ja 띄어쓰기 회귀 가드 (Test 7) — ID 뒤 띄어쓰기 위반
    test('ja 띄어쓰기 회귀: Yahoo! JAPAN ID でログイン 채택 불가', () async {
      final l10n = await AppLocalizations.delegate.load(const Locale('ja'));
      expect(
        l10n.authYahoojpSignIn,
        isNot(equals('Yahoo! JAPAN ID でログイン')),
        reason: 'ID 뒤 띄어쓰기 위반 — BI 가이드 verbatim 불부합',
      );
    });
    // 일관 mirror — prefix/suffix (Test 8~9)
    test('en: "Sign in with" prefix 일관 (Apple/Google/Naver mirror)', () async {
      final l10n = await AppLocalizations.delegate.load(const Locale('en'));
      expect(
        l10n.authYahoojpSignIn,
        startsWith('Sign in with'),
        reason: '"Sign in with" prefix — 5 provider en 일관 패턴',
      );
    });
    test('ko: "으로 로그인" suffix 일관 (Naver/LINE mirror)', () async {
      final l10n = await AppLocalizations.delegate.load(const Locale('ko'));
      expect(
        l10n.authYahoojpSignIn,
        endsWith('으로 로그인'),
        reason: '외래어+조사 붙임 — Naver/LINE ko 패턴 mirror',
      );
    });
    // 변형 위반 negative test (Test 10~11)
    test('en 변형 위반: "Sign up" 채택 불가 (로그인 → 가입 substitution)', () async {
      final l10n = await AppLocalizations.delegate.load(const Locale('en'));
      expect(
        l10n.authYahoojpSignIn,
        isNot(contains('Sign up')),
        reason: 'sign-in 의도 — sign-up 변형 회귀 가드',
      );
    });
    test('ko 변형 위반: "가입" 채택 불가 (로그인 → 가입 substitution)', () async {
      final l10n = await AppLocalizations.delegate.load(const Locale('ko'));
      expect(
        l10n.authYahoojpSignIn,
        isNot(contains('가입')),
        reason: '로그인 의도 — 가입 변형 회귀 가드',
      );
    });
    // Yahoo! JAPAN brand integrity (Test 12) — 3 locale 모두 브랜드 명사 포함
    test('3 locale 모두 "Yahoo! JAPAN" brand 포함', () async {
      final l10nJa = await AppLocalizations.delegate.load(const Locale('ja'));
      final l10nEn = await AppLocalizations.delegate.load(const Locale('en'));
      final l10nKo = await AppLocalizations.delegate.load(const Locale('ko'));
      expect(
        l10nJa.authYahoojpSignIn,
        contains('Yahoo! JAPAN'),
        reason: 'ja 브랜드 명사 누락',
      );
      expect(
        l10nEn.authYahoojpSignIn,
        contains('Yahoo! JAPAN'),
        reason: 'en 브랜드 명사 누락',
      );
      expect(
        l10nKo.authYahoojpSignIn,
        contains('Yahoo! JAPAN'),
        reason: 'ko 브랜드 명사 누락',
      );
    });
  });
}
