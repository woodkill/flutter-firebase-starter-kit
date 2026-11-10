// Phase 25 — 계정 연결 안내 줄 ARB verbatim 고정 (SC4).
//
// **책임 범위:** ARB key `settingsAccountLinkingGuide` 의 ko/en/ja 문구를
// ROADMAP SC4 원문과 문자 단위로 고정한다. 기준값은 SC4 에서 옮겼고 ARB 에서
// 복사하지 않는다(복사하면 현재 값이 무엇이든 통과한다). 킷 트리에서만 돈다 —
// ARB 는 킷 사용자 소유 표면이다.
//
// **시험 ID:** T-25-ARB-01 (ko) · T-25-ARB-02 (en) · T-25-ARB-03 (ja).

import 'package:flutter/material.dart';
import 'package:flutter_starter_kit/l10n/generated/app_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/planning_docs.dart';

/// SC4 원문 기준값 — locale 코드 → 문구.
const Map<String, String> _kGuideCopy = <String, String>{
  'ko': '다른 로그인 수단을 추가할 수 있습니다.',
  'en': 'Add another way to sign in.',
  'ja': 'ほかのログイン方法を追加できます。',
};

Future<void> _verifyLocale(String code) async {
  final l10n = await AppLocalizations.delegate.load(Locale(code));
  expect(
    l10n.settingsAccountLinkingGuide,
    _kGuideCopy[code],
    reason: '$code 의 settingsAccountLinkingGuide 가 SC4 원문과 다르다',
  );
}

void main() {
  group('account_linking_guide_arb_verbatim — Phase 25 SC4', () {
    test('T-25-ARB-01 ko 안내 줄이 SC4 원문과 일치', () => _verifyLocale('ko'));
    test('T-25-ARB-02 en 안내 줄이 SC4 원문과 일치', () => _verifyLocale('en'));
    test('T-25-ARB-03 ja 안내 줄이 SC4 원문과 일치', () => _verifyLocale('ja'));
  }, skip: skipUnlessMaintainerTree());
}
