// Phase 16.1 — see ROADMAP.md (D-10 ARB 3 locale verbatim audit 자동화)
//
// **책임 범위:** Phase 16.1 이 렌더하는 앱 chrome 문자열 14 key 의 ko/en/ja
// verbatim 고정. SC 5 「신규 ARB key 0」 계약의 회귀 가드이며, locale 하나만
// 갱신하는 부분 번역과 문구 drift 를 CI 에서 잡는다.
//
// **책임 밖:** provider brand 라벨(소셜 로그인 버튼 라벨 · 계정 표시용 provider
// 라벨) 은 이 파일이 다루지 않는다. 그 매트릭스의 유일 진실원은
// `test/features/auth/presentation/_widgets/brand_label_whitelist_test.dart`
// 이며 Phase 13.1/13.3/14/15 가 공식 BI/HIG 로 lock 했다 — 두 곳에서 같은 값을
// 단언하면 다음 brand 갱신 때 진실원이 갈라진다.

import 'package:flutter/material.dart';
import 'package:flutter_starter_kit/l10n/generated/app_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

/// Phase 16.1 의 4 surface (A `/login` chooser · B `/login/email` ·
/// C `/signup` · D `LoginPromptSheet`) 가 렌더하는 문자열 화이트리스트.
///
/// **기준값 출처:** `16.1-RESEARCH.md` §Code Examples 「ARB verbatim 표
/// (11 key × 3 locale — 2026-09-10 실측)」 + 같은 절의 B/C 필드 라벨 3 key.
/// `16.1-UI-SPEC.md` §Copywriting Contract 의 표와 교차 확인했다.
///
/// **ARB 파일에서 복사하지 않는다.** 복사하면 "현재 값이 무엇이든 통과" 하는
/// 자기참조 test 가 되어 회귀 가드 기능이 0 이 된다 (T-16.1-10).
const Map<String, Map<String, String>>
_kEmailRelegationCopy = <String, Map<String, String>>{
  // --- A + D 공유 CTA (Surface S `EmailAuthCta`) ---
  'authContinueWithEmail': <String, String>{
    'ko': '이메일로 계속',
    'en': 'Continue with email',
    'ja': 'メールアドレスで続行',
  },
  // --- A chooser ---
  'authOrDivider': <String, String>{'ko': '또는', 'en': 'or', 'ja': 'または'},
  'authLoginNoAccount': <String, String>{
    'ko': '계정이 없으신가요? 가입하기',
    'en': 'No account? Create one',
    // 280dp 에서 2줄 wrap 되는 것은 설계다 (RESEARCH Pitfall 8) —
    // ellipsis/maxLines 로 잘라내면 3 locale sign-off 를 깬다.
    'ja': 'アカウントをお持ちでない方はこちら',
  },
  // --- AppBar title (A · B 재사용 / C 재사용) ---
  'authLoginTitle': <String, String>{
    'ko': '로그인',
    'en': 'Sign in',
    'ja': 'ログイン',
  },
  'authSignupTitle': <String, String>{
    'ko': '계정 만들기',
    'en': 'Create account',
    'ja': 'アカウント作成',
  },
  // --- B / C form CTA ---
  'authLoginCta': <String, String>{'ko': '로그인', 'en': 'Sign in', 'ja': 'ログイン'},
  'authSignupCta': <String, String>{
    'ko': '가입하기',
    'en': 'Create account',
    'ja': 'アカウントを作成',
  },
  // --- B / C 하단 링크 ---
  'authLoginForgotPassword': <String, String>{
    'ko': '비밀번호를 잊으셨나요?',
    'en': 'Forgot your password?',
    'ja': 'パスワードをお忘れですか？',
  },
  'authSignupHasAccount': <String, String>{
    'ko': '이미 계정이 있으신가요? 로그인',
    'en': 'Already have an account? Sign in',
    'ja': 'すでにアカウントをお持ちの方はログイン',
  },
  // --- D LoginPromptSheet ---
  'authPromptSheetTitle': <String, String>{
    'ko': '로그인이 필요해요',
    'en': 'Sign-in required',
    'ja': 'ログインが必要です',
  },
  'authPromptSheetBody': <String, String>{
    'ko': '이 기능을 계속 사용하려면 계정이 필요해요.',
    'en': "You'll need an account to keep using this feature.",
    'ja': 'この機能を使い続けるには、アカウントが必要です。',
  },
  // --- B / C 필드 라벨 (Phase 6 현행 · 본 phase 변경 0) ---
  'authLoginEmailLabel': <String, String>{
    'ko': '이메일',
    'en': 'Email',
    'ja': 'メールアドレス',
  },
  'authLoginPasswordLabel': <String, String>{
    'ko': '비밀번호',
    'en': 'Password',
    'ja': 'パスワード',
  },
  'authSignupDisplayNameLabel': <String, String>{
    'ko': '이름',
    'en': 'Display name',
    'ja': 'お名前',
  },
};

/// 화이트리스트가 담는 key 총수 — 11(앱 chrome) + 3(B/C 필드 라벨).
const int _kExpectedKeyCount = 14;

/// 검증 대상 locale — `l10n.yaml` 의 ARB 3 파일과 1:1 대응한다.
const List<String> _kLocales = <String>['ko', 'en', 'ja'];

/// 지정 [localeCode] 의 [AppLocalizations] 를 로드해 [table] 의 문자열이 ARB
/// 와 문자 단위로 일치하는지 검증한다.
///
/// getter 매핑을 잊은 채 [table] 에만 key 를 추가하면 `_` 분기가 즉시 throw
/// 하므로, 화이트리스트만 늘어나고 실제로는 아무것도 검증하지 않는 vacuous
/// 상태가 생기지 않는다.
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
      reason: '${entry.key} 의 $localeCode 기준값이 화이트리스트에 부재',
    );
    final actual = switch (entry.key) {
      'authContinueWithEmail' => l10n.authContinueWithEmail,
      'authOrDivider' => l10n.authOrDivider,
      'authLoginNoAccount' => l10n.authLoginNoAccount,
      'authLoginTitle' => l10n.authLoginTitle,
      'authSignupTitle' => l10n.authSignupTitle,
      'authLoginCta' => l10n.authLoginCta,
      'authSignupCta' => l10n.authSignupCta,
      'authLoginForgotPassword' => l10n.authLoginForgotPassword,
      'authSignupHasAccount' => l10n.authSignupHasAccount,
      'authPromptSheetTitle' => l10n.authPromptSheetTitle,
      'authPromptSheetBody' => l10n.authPromptSheetBody,
      'authLoginEmailLabel' => l10n.authLoginEmailLabel,
      'authLoginPasswordLabel' => l10n.authLoginPasswordLabel,
      'authSignupDisplayNameLabel' => l10n.authSignupDisplayNameLabel,
      _ => throw UnsupportedError('Unknown key: ${entry.key}'),
    };
    expect(
      actual,
      expected,
      reason:
          '$localeCode 의 ${entry.key} ARB 값이 Phase 16.1 verbatim 표와 drift '
          '— production ARB 또는 본 const Map 둘 중 하나 갱신 필요',
    );
  }
}

void main() {
  group('email_relegation_arb_verbatim — Phase 16.1 SC 5 (D-10)', () {
    test('ko: 14 key 가 ARB verbatim 표와 문자 단위 일치', () async {
      await _verifyLocale('ko', _kEmailRelegationCopy);
    });

    test('en: 14 key 가 ARB verbatim 표와 문자 단위 일치', () async {
      await _verifyLocale('en', _kEmailRelegationCopy);
    });

    test('ja: 14 key 가 ARB verbatim 표와 문자 단위 일치', () async {
      await _verifyLocale('ja', _kEmailRelegationCopy);
    });

    test('key 집합 완전성: 14 key × 3 locale 이 전부 채워져 있다', () {
      expect(
        _kEmailRelegationCopy.length,
        _kExpectedKeyCount,
        reason: 'key 를 추가·삭제했다면 _kExpectedKeyCount 도 함께 갱신할 것',
      );
      for (final entry in _kEmailRelegationCopy.entries) {
        for (final localeCode in _kLocales) {
          expect(
            entry.value[localeCode],
            isNotNull,
            reason: '${entry.key} 에 $localeCode 값이 없다 — 부분 번역 회귀',
          );
        }
        expect(
          entry.value.length,
          _kLocales.length,
          reason: '${entry.key} 에 검증 대상 밖 locale 이 섞였다',
        );
      }
    });
  });
}
