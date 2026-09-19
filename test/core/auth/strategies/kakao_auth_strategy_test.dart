import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_starter_kit/core/auth/provider_id.dart';
import 'package:flutter_starter_kit/core/auth/strategies/kakao_auth_strategy.dart';
import 'package:flutter_starter_kit/features/auth/application/social_link_in_progress.dart';
import 'package:flutter_starter_kit/features/auth/presentation/kakao_sign_in_notifier.dart';

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

  /// [KakaoSignInNotifier.signInWithKakao] 호출 횟수.
  int signInCount = 0;
}

/// SocialLinkInProgress race-guard stub — `begin` / `end` 호출 횟수를
/// [_SignInCallRecorder] 에 기록하여 [KakaoAuthStrategy.signIn] 이 race-guard
/// 를 직접 건드렸는지 회귀 가드 (Pitfall 8) 한다. mocktail Mock 은 Riverpod
/// generator 의 `_element` 등 internal getter 가 누락되어 ProviderException 을
/// 일으키므로 사용 불가 (Rule 1 fix during execution) — 대신
/// [SocialLinkInProgress] 를 직접 확장.
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

/// KakaoSignInNotifier 위임 검증용 stub — `signInWithKakao` 호출 횟수를
/// [_SignInCallRecorder] 에 기록한다.
class _StubKakaoSignInNotifier extends KakaoSignInNotifier {
  /// 호출 횟수를 주입된 recorder 에 기록하는 stub 을 만든다.
  _StubKakaoSignInNotifier(this._recorder);

  final _SignInCallRecorder _recorder;

  @override
  void build() {}

  @override
  Future<void> signInWithKakao() async {
    _recorder.signInCount += 1;
  }
}

/// 실제 [Consumer] 가 노출하는 [WidgetRef] 를 차용해 [KakaoAuthStrategy.signIn]
/// 을 호출하는 helper. Riverpod 3.x 의 [WidgetRef] 는 sealed class 라서 직접
/// 구현이 불가능하므로, [ProviderScope] + [Consumer] 트리 안에서 ref 를 빌려
/// 사용한다 (`SocialButton` widget test 와 동일 진입 패턴).
Future<void> _runStrategySignIn(
  WidgetTester tester,
  KakaoAuthStrategy strategy, {
  required SocialLinkInProgress stubSocialLink,
  required KakaoSignInNotifier stubKakaoNotifier,
}) async {
  Future<void>? signInFuture;
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        socialLinkInProgressProvider.overrideWith(() => stubSocialLink),
        kakaoSignInProvider.overrideWith(() => stubKakaoNotifier),
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
  group('KakaoAuthStrategy 메타', () {
    const strategy = KakaoAuthStrategy();

    test('providerId 는 kProviderIdKakao 이다', () {
      expect(strategy.providerId, kProviderIdKakao);
    });

    test('labelKey 는 authKakaoSignIn 이다', () {
      expect(strategy.labelKey, 'authKakaoSignIn');
    });
  });

  group('KakaoAuthStrategy — race-fix Pitfall 8 회귀 가드', () {
    testWidgets('Strategy 단계에서 socialLinkInProgress 직접 호출 절대 금지 '
        '(T-11-RACE-01 등가)', (tester) async {
      final recorder = _SignInCallRecorder();
      final stubSocialLink = _StubSocialLinkInProgress(recorder);
      final stubKakaoNotifier = _StubKakaoSignInNotifier(recorder);

      const strategy = KakaoAuthStrategy();
      await _runStrategySignIn(
        tester,
        strategy,
        stubSocialLink: stubSocialLink,
        stubKakaoNotifier: stubKakaoNotifier,
      );

      // T-11-RACE-01 등가 — Strategy 가 begin/end 호출하면 즉시 실패.
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
            'KakaoAuthStrategy.signIn 은 KakaoSignInNotifier.signInWithKakao '
            '를 정확히 1회 위임 호출해야 한다',
      );
    });
  });
}
