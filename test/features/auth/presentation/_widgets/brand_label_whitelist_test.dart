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

/// Naver BI 화이트리스트 (D-79 ja 영문 fallback).
const Map<String, Map<String, String>> _kNaverBI = <String, Map<String, String>>{
  'authNaverSignIn': <String, String>{
    'ko': '네이버로 시작하기', // Naver BI ko 4 변형 중 채택 (D-23)
    'en': 'Continue with Naver',
    'ja': 'Continue with Naver', // R7 영문 fallback (D-79)
  },
};

/// Kakao BI 화이트리스트 (D-79 ja 영문 fallback).
const Map<String, Map<String, String>> _kKakaoBI = <String, Map<String, String>>{
  'authKakaoSignIn': <String, String>{
    'ko': '카카오 로그인',
    'en': 'Continue with Kakao',
    'ja': 'Continue with Kakao', // R7 영문 fallback (D-79)
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

  group('brand_label_whitelist — Naver BI (R7)', () {
    test('ko: 네이버로 시작하기', () async {
      await _verifyLocale('ko', _kNaverBI);
    });
    test('en: Continue with Naver', () async {
      await _verifyLocale('en', _kNaverBI);
    });
    test('ja: Continue with Naver (D-79 영문 fallback)', () async {
      await _verifyLocale('ja', _kNaverBI);
    });
  });

  group('brand_label_whitelist — Kakao BI (R7)', () {
    test('ko: 카카오 로그인', () async {
      await _verifyLocale('ko', _kKakaoBI);
    });
    test('en: Continue with Kakao', () async {
      await _verifyLocale('en', _kKakaoBI);
    });
    test('ja: Continue with Kakao (D-79 영문 fallback)', () async {
      await _verifyLocale('ja', _kKakaoBI);
    });
  });
}
