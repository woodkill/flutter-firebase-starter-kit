import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_starter_kit/core/auth/provider_id.dart';

/// Phase 16 Task 4.1 — AccountProvider enum 7값 + arbKey getter 매핑 검증.
///
/// Phase 9.2 deferred R1 부활 — 7 provider (google/apple/facebook/email +
/// kakao/naver/line) 모두 `authAccountProvider{X}` ARB key 와
/// 정확히 매핑되는지 unit test 로 lock.
void main() {
  group('AccountProvider enum — 7 값 + arbKey 매핑', () {
    test('enum 값 7 개 (google/apple/facebook/email + kakao/naver/line)', () {
      expect(AccountProvider.values.length, 7);
      expect(AccountProvider.values.toSet(), {
        AccountProvider.google,
        AccountProvider.apple,
        AccountProvider.facebook,
        AccountProvider.email,
        AccountProvider.kakao,
        AccountProvider.naver,
        AccountProvider.line,
      });
    });

    test('google → authAccountProviderGoogle', () {
      expect(AccountProvider.google.arbKey, 'authAccountProviderGoogle');
    });

    test('apple → authAccountProviderApple', () {
      expect(AccountProvider.apple.arbKey, 'authAccountProviderApple');
    });

    test('facebook → authAccountProviderFacebook', () {
      expect(AccountProvider.facebook.arbKey, 'authAccountProviderFacebook');
    });

    test('email → authAccountProviderEmailPassword', () {
      expect(AccountProvider.email.arbKey, 'authAccountProviderEmailPassword');
    });

    test('kakao → authAccountProviderKakao', () {
      expect(AccountProvider.kakao.arbKey, 'authAccountProviderKakao');
    });

    test('naver → authAccountProviderNaver', () {
      expect(AccountProvider.naver.arbKey, 'authAccountProviderNaver');
    });

    test('line → authAccountProviderLine', () {
      expect(AccountProvider.line.arbKey, 'authAccountProviderLine');
    });
  });

  group('AccountProvider.tryParse — slug → enum 매핑', () {
    test('알려진 slug 7 종은 enum 으로 매핑된다', () {
      expect(AccountProvider.tryParse('google'), AccountProvider.google);
      expect(AccountProvider.tryParse('apple'), AccountProvider.apple);
      expect(AccountProvider.tryParse('facebook'), AccountProvider.facebook);
      expect(AccountProvider.tryParse('email'), AccountProvider.email);
      expect(AccountProvider.tryParse('kakao'), AccountProvider.kakao);
      expect(AccountProvider.tryParse('naver'), AccountProvider.naver);
      expect(AccountProvider.tryParse('line'), AccountProvider.line);
    });

    test('알 수 없는 slug 는 null 반환 (unknown fallback)', () {
      expect(AccountProvider.tryParse('unknown'), isNull);
      expect(AccountProvider.tryParse(''), isNull);
      expect(AccountProvider.tryParse(null), isNull);
    });
  });
}
