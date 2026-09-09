// Phase 15 — see ROADMAP.md (YahoojpAuthStrategy unit tests)
//
// Pattern: line_auth_strategy_test.dart 의 stub Notifier 위임 검증 패턴 mirror.
// Strategy 단계 race-fix begin/end 0건 invariant (T-11-RACE-01 등가) 회귀 가드.
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_starter_kit/core/auth/provider_id.dart';
import 'package:flutter_starter_kit/core/auth/strategies/yahoojp_auth_strategy.dart';
import 'package:flutter_starter_kit/features/auth/application/social_link_in_progress.dart';
import 'package:flutter_starter_kit/features/auth/presentation/yahoojp_sign_in_notifier.dart';

/// SocialLinkInProgress race-guard stub — `begin` / `end` 호출 카운터를 보유
/// 하여 [YahoojpAuthStrategy.signIn] 이 race-guard 를 직접 건드렸는지 회귀
/// 가드 (Pitfall 8) 한다. mocktail Mock 은 Riverpod generator 의 `_element` 등
/// internal getter 가 누락되어 ProviderException 을 일으키므로 사용 불가
/// (Phase 14 line_auth_strategy_test.dart 와 동일 패턴).
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

/// YahoojpSignInNotifier 위임 검증용 stub — `signInWithYahoojp` 호출 카운터.
class _StubYahoojpSignInNotifier extends YahoojpSignInNotifier {
  int signInCount = 0;

  @override
  void build() {}

  @override
  Future<void> signInWithYahoojp() async {
    signInCount += 1;
  }
}

/// [YahoojpAuthStrategy.signIn] 을 호출하는 helper — Riverpod 3.x WidgetRef
/// 는 sealed 라 직접 구현 불가 → [ProviderScope] + [Consumer] 트리에서 ref
/// 차용.
Future<void> _runStrategySignIn(
  WidgetTester tester,
  YahoojpAuthStrategy strategy, {
  required SocialLinkInProgress stubSocialLink,
  required YahoojpSignInNotifier stubYahoojpNotifier,
}) async {
  Future<void>? signInFuture;
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        socialLinkInProgressProvider.overrideWith(() => stubSocialLink),
        yahoojpSignInProvider.overrideWith(() => stubYahoojpNotifier),
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
  await signInFuture;
}

void main() {
  group('YahoojpAuthStrategy 메타', () {
    const strategy = YahoojpAuthStrategy();

    test('providerId 는 kProviderIdYahooJp 이다', () {
      expect(strategy.providerId, kProviderIdYahooJp);
      expect(strategy.providerId, 'yahoojp');
    });

    test('labelKey 는 authYahoojpSignIn 이다', () {
      expect(strategy.labelKey, 'authYahoojpSignIn');
    });

    test('iconAsset 는 yahoojp 이다', () {
      expect(strategy.iconAsset, 'yahoojp');
    });
  });

  group('YahoojpAuthStrategy — race-fix Pitfall 8 회귀 가드', () {
    testWidgets('Strategy 단계에서 socialLinkInProgress 직접 호출 절대 금지 '
        '(T-11-RACE-01 등가)', (tester) async {
      final stubSocialLink = _StubSocialLinkInProgress();
      final stubYahoojpNotifier = _StubYahoojpSignInNotifier();

      const strategy = YahoojpAuthStrategy();
      await _runStrategySignIn(
        tester,
        strategy,
        stubSocialLink: stubSocialLink,
        stubYahoojpNotifier: stubYahoojpNotifier,
      );

      // T-11-RACE-01 등가 — Strategy 가 begin/end 호출하면 즉시 실패.
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
        stubYahoojpNotifier.signInCount,
        1,
        reason:
            'YahoojpAuthStrategy.signIn 은 YahoojpSignInNotifier.signInWith'
            'Yahoojp 을 정확히 1회 위임 호출해야 한다',
      );
    });
  });
}
