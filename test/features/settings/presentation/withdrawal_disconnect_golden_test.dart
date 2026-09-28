// Phase 16.10 Plan 16.10-08 Task 2 — 탈퇴 진행 화면 golden (D-06 · UI-SPEC
// §Golden 캡처 계약).
//
// production `WithdrawalDisconnectScreen` 을 상태 fixture 로 렌더해 사용자
// sign-off 채택안 `mockups/adopted_withdrawal_progress_ko_280_{mid,done}_
// {light,dark}.png` 와 byte 동일해야 한다 (구분선 · 아래 영역 선 포함 · Q9 ·
// Q10). 캡처 조건은 설정 화면 golden 과 같은 공용 golden harness 다.
//
// **fixture (UI-SPEC · harness `_states` s2 · s3):** 16.8 W5 사용자 · 행 =
// 서버(Facebook · 카카오) → 재로그인(Google · Apple · 네이버 · 라인).
// - mid = Facebook 해제됨 · 카카오 실패 · Google 해제됨 · Apple 건너뜀 · 네이버
//   로그인 대기(현재) · 라인 대기.
// - done = 전부 해제됨 · Apple 만 건너뜀.
// 스피너 없는 상태만 golden 이다 (UI-SPEC F1 — 스피너 상태는 widget test).
//
// **E1 overflow backstop:** `takeException() == null` 을 golden 비교보다 먼저
// 단언한다 — 목록이 넘쳐도 소개 · 행이 함께 스크롤되고 아래 고정 영역은
// 잘리지 않는다.
//
// **fixture 갱신:** `fvm flutter test --no-pub --update-goldens <this file>` 뒤
// 산출 PNG 를 `cmp` 로 채택안과 대조한다. 불일치면 채택안을 덮어쓰지 말고
// 원인(구현 트리 · harness 조건 차이)을 먼저 찾는다.

import 'package:flutter/material.dart';
import 'package:flutter_starter_kit/core/auth/auth_strategies_registry.dart';
import 'package:flutter_starter_kit/core/auth/provider_id.dart';
import 'package:flutter_starter_kit/features/auth/data/auth_repository.dart';
import 'package:flutter_starter_kit/features/auth/domain/user.dart';
import 'package:flutter_starter_kit/features/settings/data/disconnect/disconnect_step.dart';
import 'package:flutter_starter_kit/features/settings/presentation/withdrawal_disconnect_notifier.dart';
import 'package:flutter_starter_kit/features/settings/presentation/withdrawal_disconnect_screen.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'settings_golden_harness.dart';

/// [AuthRepository] 대체 Mock — 진행 화면 렌더는 repository 를 호출하지
/// 않으므로 stub 을 두지 않는다.
class _MockAuthRepository extends Mock implements AuthRepository {}

/// 고정 상태를 내보내는 진행 notifier — `start()` 는 아무것도 하지 않는다.
class _FixtureNotifier extends WithdrawalDisconnect {
  _FixtureNotifier(this.fixture);

  /// 화면에 그릴 상태 fixture.
  final WithdrawalDisconnectState fixture;

  @override
  WithdrawalDisconnectState build() => fixture;

  @override
  Future<void> start() async {}
}

/// 16.8 W5 사용자 — 가입 naver · 보유 6종 (UI-SPEC §Golden 캡처 계약 fixture).
final User _w5User = User(
  uid: 'Xy7Qa2Lm9Rt4Wz8Kp1Nc5Vb3Hd6',
  email: 'me@example.com',
  emailVerified: true,
  displayName: '홍길동',
  createdAt: DateTime.utc(2026, 9, 26, 12),
  providerIds: const <String>[
    'google.com',
    'apple.com',
    'facebook.com',
    'kakao',
    'line',
    'naver',
  ],
  signUpProviderId: 'naver',
);

/// 행 1개 fixture — 끊긴 적이 있는 행([status] 해제됨)은 wasDisconnected.
DisconnectRow _row(
  String providerId,
  AccountProvider provider,
  DisconnectKind kind,
  DisconnectRowStatus status,
) => DisconnectRow(
  providerId: providerId,
  provider: provider,
  kind: kind,
  status: status,
  wasDisconnected: status == DisconnectRowStatus.done,
);

/// 행 순서 = 서버 행 → 재로그인 행 (각 묶음 킷 표준 순서 · Q2-A).
WithdrawalDisconnectState _state(List<DisconnectRowStatus> statuses) {
  const specs = <(String, AccountProvider, DisconnectKind)>[
    ('facebook.com', AccountProvider.facebook, DisconnectKind.server),
    ('kakao', AccountProvider.kakao, DisconnectKind.server),
    ('google.com', AccountProvider.google, DisconnectKind.relogin),
    ('apple.com', AccountProvider.apple, DisconnectKind.relogin),
    ('naver', AccountProvider.naver, DisconnectKind.relogin),
    ('line', AccountProvider.line, DisconnectKind.relogin),
  ];
  return WithdrawalDisconnectState(
    rows: <DisconnectRow>[
      for (var i = 0; i < specs.length; i++)
        _row(specs[i].$1, specs[i].$2, specs[i].$3, statuses[i]),
    ],
  );
}

/// ② 중간 — 모든 상태가 한 화면에 (harness `_St.s2`).
final WithdrawalDisconnectState _mid = _state(const <DisconnectRowStatus>[
  DisconnectRowStatus.done,
  DisconnectRowStatus.failed,
  DisconnectRowStatus.done,
  DisconnectRowStatus.skipped,
  DisconnectRowStatus.needsSignIn,
  DisconnectRowStatus.waiting,
]);

/// ⑤ 모두 끝남 — 「탈퇴」 활성 · Apple 만 건너뜀 (harness `_St.s3`).
final WithdrawalDisconnectState _done = _state(const <DisconnectRowStatus>[
  DisconnectRowStatus.done,
  DisconnectRowStatus.done,
  DisconnectRowStatus.done,
  DisconnectRowStatus.skipped,
  DisconnectRowStatus.done,
  DisconnectRowStatus.done,
]);

void main() {
  setUpAll(loadGoldenFonts);

  group('Phase 16.10 탈퇴 진행 화면 golden — ko 280×800 W5 · push (D-06)', () {
    for (final (name, fixture) in <(String, WithdrawalDisconnectState)>[
      ('mid', _mid),
      ('done', _done),
    ]) {
      for (final brightness in Brightness.values) {
        final mode = brightness.name;

        testWidgets('golden ko 280 $name — $mode', (tester) async {
          await pumpGoldenRoute(
            tester,
            route: (_) => const WithdrawalDisconnectScreen(),
            overrides: [
              authRepositoryProvider.overrideWithValue(_MockAuthRepository()),
              activeStrategiesProvider.overrideWithValue(kGoldenSixStrategies),
              currentUserProvider.overrideWith((ref) => _w5User),
              withdrawalDisconnectProvider.overrideWith(
                () => _FixtureNotifier(fixture),
              ),
            ],
            locale: const Locale('ko'),
            brightness: brightness,
            width: 280,
          );
          expect(
            tester.takeException(),
            isNull,
            reason: 'layout 예외 0 이어야 golden 이 시각 계약을 대표한다 (E1 overflow)',
          );
          await expectLater(
            find.byType(MaterialApp),
            matchesGoldenFile(
              'goldens/withdrawal_progress_ko_280_${name}_$mode.png',
            ),
          );
        });
      }
    }
  });
}
