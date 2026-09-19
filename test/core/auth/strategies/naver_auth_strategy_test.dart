// Phase 13 — see ROADMAP.md (T-13-NAVER-STRATEGY)

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_starter_kit/core/auth/provider_id.dart';
import 'package:flutter_starter_kit/core/auth/strategies/naver_auth_strategy.dart';
import 'package:flutter_starter_kit/features/auth/application/social_link_in_progress.dart';
import 'package:flutter_starter_kit/features/auth/presentation/naver_sign_in_notifier.dart';

/// stub notifier 들의 호출 횟수를 notifier 밖에서 기록하는 recorder.
///
/// riverpod_lint `avoid_public_notifier_properties` — fake notifier 가 public
/// 카운터를 노출하지 않도록 기록 상태를 이 객체로 분리하고, 각 stub 은
/// 생성자로 받은 recorder 에만 기록한다.
class _SignInCallRecorder {
  /// [SocialLinkInProgress.begin] 호출 횟수.
  int beginCount = 0;

  /// [SocialLinkInProgress.end] 호출 횟수.
  int endCount = 0;

  /// [NaverSignInNotifier.signInWithNaver] 호출 횟수.
  int signInCount = 0;
}

/// SocialLinkInProgress race-guard stub — `begin` / `end` 호출 횟수를
/// [_SignInCallRecorder] 에 기록하여 [NaverAuthStrategy.signIn] 이
/// race-guard 를 직접 건드렸는지 회귀 가드 (Pitfall 8) 한다. mocktail Mock 은
/// Riverpod generator 의 `_element` 등 internal getter 가 누락되어
/// ProviderException 을 일으키므로 사용 불가
/// (Phase 12 Plan 12-04 Rule 1 fix during execution) — 대신 [SocialLinkInProgress]
/// 를 직접 확장.
class _StubSocialLinkInProgress extends SocialLinkInProgress {
  /// 호출 횟수를 주입된 recorder 에 기록하는 stub 을 만든다.
  _StubSocialLinkInProgress(this._recorder);

  final _SignInCallRecorder _recorder;

  @override
  bool build() => false;

  @override
  void begin() {
    _recorder.beginCount += 1;
    super.begin();
  }

  @override
  void end() {
    _recorder.endCount += 1;
    super.end();
  }
}

/// NaverSignInNotifier 위임 검증용 stub — `signInWithNaver` 호출 횟수를
/// [_SignInCallRecorder] 에 기록한다.
class _StubNaverSignInNotifier extends NaverSignInNotifier {
  /// 호출 횟수를 주입된 recorder 에 기록하는 stub 을 만든다.
  _StubNaverSignInNotifier(this._recorder);

  final _SignInCallRecorder _recorder;

  @override
  void build() {}

  @override
  Future<void> signInWithNaver() async {
    _recorder.signInCount += 1;
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
  });

  group('NaverAuthStrategy — race-fix Pitfall 8 회귀 가드 '
      '(T-13-NAVER-STRATEGY-RACE-01)', () {
    testWidgets('T-13-NAVER-STRATEGY-02: signIn → naverSignInProvider.notifier'
        '.signInWithNaver delegate (1회) + '
        'T-13-NAVER-STRATEGY-RACE-01: socialLinkInProgress.begin/end 미호출 '
        '(T-11-RACE-01 등가)', (tester) async {
      final recorder = _SignInCallRecorder();
      final stubSocialLink = _StubSocialLinkInProgress(recorder);
      final stubNaverNotifier = _StubNaverSignInNotifier(recorder);

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
        recorder.beginCount,
        0,
        reason:
            'Strategy 가 race-guard begin 을 호출하면 이중 begin race '
            '(T-11-RACE-01) 회귀',
      );
      expect(
        recorder.endCount,
        0,
        reason: 'Strategy 가 race-guard end 를 호출하면 단일 진실원 위배',
      );
      // 위임 검증 — Notifier 만 호출.
      expect(
        recorder.signInCount,
        1,
        reason:
            'NaverAuthStrategy.signIn 은 NaverSignInNotifier.signInWithNaver '
            '를 정확히 1회 위임 호출해야 한다',
      );
    });
  });
}
