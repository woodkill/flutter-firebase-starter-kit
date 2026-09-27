// Phase 16.8 D-03 · D-05 · D-11 · D-19 — `canUnlinkProvider` 3조건 fixture.
//
// 해제 가능 규칙은 provider 중립 순수 함수 한 곳이다. fixture 는 id 문자열,
// 기대값은 리터럴이다 — 연결 가능 집합 목록 · provider 별 switch 로 기대값을
// 만들지 않는다 (D-19).
import 'package:flutter_starter_kit/features/auth/domain/user.dart';
import 'package:flutter_starter_kit/features/settings/application/unlink_eligibility.dart';
import 'package:flutter_test/flutter_test.dart';

/// 테스트용 User factory — 합성 값만 쓴다 (`uid-1` · `me@example.com`).
User _testUser({
  List<String> providerIds = const <String>['password'],
  String? signUpProviderId,
}) {
  return User(
    uid: 'uid-1',
    email: 'me@example.com',
    emailVerified: true,
    createdAt: DateTime.utc(2026, 1, 1),
    providerIds: providerIds,
    signUpProviderId: signUpProviderId,
  );
}

void main() {
  group('Phase 16.8 D-03 · D-05 · D-11 — canUnlinkProvider', () {
    test('EL1: 가입 kakao · 보유 kakao + google.com → google.com 해제 가능', () {
      final user = _testUser(
        providerIds: const <String>['kakao', 'google.com'],
        signUpProviderId: 'kakao',
      );

      expect(canUnlinkProvider(user, 'google.com'), isTrue);
    });

    test('EL2: 덮어쓰기 — 가입 password · 보유 google.com 1개 → 해제 불가 (D-03)', () {
      // 익명 → Google 로그인이 password 기록을 덮어쓴 사례 (D-16 · D-22).
      // 자격증명이 1개뿐이라 해제하면 로그인 수단 0 계정이 된다.
      final user = _testUser(
        providerIds: const <String>['google.com'],
        signUpProviderId: 'password',
      );

      expect(canUnlinkProvider(user, 'google.com'), isFalse);
    });

    test('EL3: 가입 수단 기록 null · 보유 7 → 7 id 전부 해제 불가 (D-05)', () {
      final user = _testUser(
        providerIds: const <String>[
          'password',
          'google.com',
          'apple.com',
          'facebook.com',
          'kakao',
          'naver',
          'line',
        ],
      );

      expect(canUnlinkProvider(user, 'password'), isFalse);
      expect(canUnlinkProvider(user, 'google.com'), isFalse);
      expect(canUnlinkProvider(user, 'apple.com'), isFalse);
      expect(canUnlinkProvider(user, 'facebook.com'), isFalse);
      expect(canUnlinkProvider(user, 'kakao'), isFalse);
      expect(canUnlinkProvider(user, 'naver'), isFalse);
      expect(canUnlinkProvider(user, 'line'), isFalse);
    });

    test('EL4: 미지 id 혼재 — yahoo 해제 불가 · 같은 행 google.com 해제 가능 (D-11)', () {
      final user = _testUser(
        providerIds: const <String>['kakao', 'google.com', 'yahoo'],
        signUpProviderId: 'kakao',
      );

      expect(canUnlinkProvider(user, 'yahoo'), isFalse);
      expect(canUnlinkProvider(user, 'google.com'), isTrue);
    });

    test(
      'EL4b: 식별 불가 id 도 ≥2 계수에 포함 — google.com + yahoo → google.com 해제 가능',
      () {
        // 식별 불가 id(AccountProvider 미등록 provider 등)도 실제 로그인 가능한
        // 자격증명이라 계수에 넣는다 (review IN-05 — 현행 동작 고정).
        final user = _testUser(
          providerIds: const <String>['google.com', 'yahoo'],
          signUpProviderId: 'yahoo',
        );

        expect(canUnlinkProvider(user, 'google.com'), isTrue);
        expect(canUnlinkProvider(user, 'yahoo'), isFalse);
      },
    );

    test('EL5: user null → 해제 불가', () {
      expect(canUnlinkProvider(null, 'google.com'), isFalse);
    });

    test('EL6: 이메일이 연결된 계정 — password 해제 가능 (D-04 provider 중립)', () {
      final user = _testUser(
        providerIds: const <String>['kakao', 'password'],
        signUpProviderId: 'kakao',
      );

      expect(canUnlinkProvider(user, 'password'), isTrue);
    });

    test('EL7: Naver 가 연결된 계정 — naver 해제 가능 (D-04 provider 중립)', () {
      // 연결 가능 집합에 Naver 가 없어도 연결된 계정에 나타나면 같은 규칙이다.
      final user = _testUser(
        providerIds: const <String>['kakao', 'naver'],
        signUpProviderId: 'kakao',
      );

      expect(canUnlinkProvider(user, 'naver'), isTrue);
    });
  });
}
