// Phase 13 — see ROADMAP.md (T-13-NAVER-STRATEGY)

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_starter_kit/core/auth/provider_id.dart';
import 'package:flutter_starter_kit/core/auth/strategies/naver_auth_strategy.dart';
import 'package:flutter_starter_kit/features/auth/application/social_link_in_progress.dart';
import 'package:flutter_starter_kit/features/auth/presentation/naver_sign_in_notifier.dart';

/// SocialLinkInProgress race-guard stub — `begin` / `end` 호출 카운터를 보유
/// 하여 [NaverAuthStrategy.signIn] 이 race-guard 를 직접 건드렸는지 회귀 가드
/// (Pitfall 8) 한다. mocktail Mock 은 Riverpod generator 의 `_element` 등
/// internal getter 가 누락되어 ProviderException 을 일으키므로 사용 불가
/// (Phase 12 Plan 12-04 Rule 1 fix during execution) — 대신 [SocialLinkInProgress]
/// 를 직접 확장.
class _StubSocialLinkInProgress extends SocialLinkInProgress {
  int beginCount = 0;
  int endCount = 0;

  @override
  bool build() => false;

  @override
  void begin() {
    beginCount += 1;
    super.begin();
  }

  @override
  void end() {
    endCount += 1;
    super.end();
  }
}

/// NaverSignInNotifier 위임 검증용 stub — `signInWithNaver` 호출 카운터.
class _StubNaverSignInNotifier extends NaverSignInNotifier {
  int signInCount = 0;

  @override
  void build() {}

  @override
  Future<void> signInWithNaver() async {
    signInCount += 1;
  }
}

/// 실제 [Consumer] 가 노출하는 [WidgetRef] 를 차용해 [NaverAuthStrategy.signIn]
/// 을 호출하는 helper. Riverpod 3.x 의 [WidgetRef] 는 sealed class 라서 직접
/// 구현이 불가능하므로, [ProviderScope] + [Consumer] 트리 안에서 ref 를 빌려
/// 사용한다 (Phase 12 [KakaoAuthStrategy] test 와 동일 진입 패턴).
Future<void> _runStrategySignIn(
  WidgetTester tester,
  NaverAuthStrategy strategy, {
  required SocialLinkInProgress stubSocialLink,
  required NaverSignInNotifier stubNaverNotifier,
}) async {
  Future<void>? signInFuture;
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        socialLinkInProgressProvider.overrideWith(() => stubSocialLink),
        naverSignInProvider.overrideWith(() => stubNaverNotifier),
      ],
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: Consumer(
          builder: (context, ref, _) {
            signInFuture = strategy.signIn(ref);
            return const SizedBox.shrink();
          },
        ),
      ),
    ),
  );
  // Consumer.build 가 즉시 signIn 을 호출했으므로 future 는 non-null.
  await signInFuture;
}

void main() {
  group('NaverAuthStrategy 메타 (T-13-NAVER-STRATEGY)', () {
    const strategy = NaverAuthStrategy();

    test('T-13-NAVER-STRATEGY-01: providerId = kProviderIdNaver', () {
      expect(strategy.providerId, kProviderIdNaver);
    });

    test('T-13-NAVER-STRATEGY-LABEL: labelKey = authNaverSignIn', () {
      expect(strategy.labelKey, 'authNaverSignIn');
    });

    test('T-13-NAVER-STRATEGY-ICON: iconAsset = naver', () {
      expect(strategy.iconAsset, 'naver');
    });

    test(
        'T-13-NAVER-STRATEGY-PRIORITY: defaultPriorityFor 는 Phase 11 '
        'placeholder 0 을 반환한다', () {
      expect(strategy.defaultPriorityFor(const Locale('en')), 0);
      expect(strategy.defaultPriorityFor(const Locale('ko')), 0);
    });
  });

  group(
      'NaverAuthStrategy — race-fix Pitfall 8 회귀 가드 '
      '(T-13-NAVER-STRATEGY-RACE-01)', () {
    testWidgets(
      'T-13-NAVER-STRATEGY-02: signIn → naverSignInProvider.notifier'
      '.signInWithNaver delegate (1회) + '
      'T-13-NAVER-STRATEGY-RACE-01: socialLinkInProgress.begin/end 미호출 '
      '(T-11-RACE-01 등가)',
      (tester) async {
        final stubSocialLink = _StubSocialLinkInProgress();
        final stubNaverNotifier = _StubNaverSignInNotifier();

        const strategy = NaverAuthStrategy();
        await _runStrategySignIn(
          tester,
          strategy,
          stubSocialLink: stubSocialLink,
          stubNaverNotifier: stubNaverNotifier,
        );

        // T-13-NAVER-STRATEGY-RACE-01 — Strategy 가 begin/end 호출하면 즉시 실패.
        // verifyNever 등가 — 단일 진실원 = AuthRepository.signInWithNaver
        // try-finally (Plan 13-03).
        expect(
          stubSocialLink.beginCount,
          0,
          reason:
              'Strategy 가 race-guard begin 을 호출하면 이중 begin race '
              '(T-11-RACE-01) 회귀',
        );
        expect(
          stubSocialLink.endCount,
          0,
          reason: 'Strategy 가 race-guard end 를 호출하면 단일 진실원 위배',
        );
        // 위임 검증 — Notifier 만 호출.
        expect(
          stubNaverNotifier.signInCount,
          1,
          reason:
              'NaverAuthStrategy.signIn 은 NaverSignInNotifier.signInWithNaver '
              '를 정확히 1회 위임 호출해야 한다',
        );
      },
    );
  });
}
