import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_starter_kit/features/auth/application/social_link_in_progress.dart';

void main() {
  group(
    'Phase 9.1 Plan 01: SocialLinkInProgress Notifier (Provider 직접 검증)',
    () {
      /// Test SLP-P1: ProviderContainer 생성 직후 초기 상태 검증.
      ///
      /// `bool build() => false` 계약에 따라 첫 read 는 반드시 false 여야 한다.
      /// Mock/Stub 미사용 — production class 직접 검증.
      test('SLP-P1: 초기 상태가 false 이다', () {
        final container = ProviderContainer();
        addTearDown(container.dispose);

        final state = container.read(socialLinkInProgressProvider);

        expect(
          state,
          isFalse,
          reason: 'build() 는 false 를 반환해야 한다 (진행 중인 linking 없음)',
        );
      });

      /// Test SLP-P2: begin() 호출 후 state=true 전환 검증.
      ///
      /// AuthRepository.signInWith* 의 try 블록 첫 줄에서 begin() 을 호출하면
      /// race-window 진입을 알리는 신호가 true 가 되어야 한다 (D-03).
      test('SLP-P2: begin() 호출 후 state 가 true 로 전환된다', () {
        final container = ProviderContainer();
        addTearDown(container.dispose);

        container.read(socialLinkInProgressProvider.notifier).begin();

        expect(
          container.read(socialLinkInProgressProvider),
          isTrue,
          reason: 'begin() 호출 후 state 는 true 여야 한다 (race-window 진입 신호)',
        );
      });

      /// Test SLP-P3: begin() → end() 순서 후 state=false 복귀 검증.
      ///
      /// AuthRepository.signInWith* 의 finally 블록에서 end() 를 호출하면
      /// race-window 종료를 알리는 신호가 false 로 복귀해야 한다 (D-03).
      /// success/failure/cancel 모든 경로에서 invariant 가 보장되어야 한다.
      test('SLP-P3: begin() → end() 호출 후 state 가 false 로 복귀한다', () {
        final container = ProviderContainer();
        addTearDown(container.dispose);

        final notifier = container.read(socialLinkInProgressProvider.notifier);
        notifier.begin();
        expect(
          container.read(socialLinkInProgressProvider),
          isTrue,
          reason: '사전 조건: begin() 이후 state=true',
        );

        notifier.end();

        expect(
          container.read(socialLinkInProgressProvider),
          isFalse,
          reason: 'end() 호출 후 state 는 false 로 복귀해야 한다 (race-window 종료)',
        );
      });

      /// Test SLP-P4: keepAlive lifecycle — listener 해제 후에도 state 유지.
      ///
      /// `@Riverpod(keepAlive: true)` 의 핵심 invariant.
      /// ProviderSubscription 을 close 해도 Provider 가 dispose 되지 않으므로
      /// state 는 reset 되지 않아야 한다. hot reload / Provider rebuild 시
      /// state churn 방지 보장 (SUMMARY key-decisions 4번째).
      test('SLP-P4: keepAlive — listener 해제 후에도 state 가 reset 되지 않는다', () {
        final container = ProviderContainer();
        addTearDown(container.dispose);

        // begin() 으로 state=true 설정.
        container.read(socialLinkInProgressProvider.notifier).begin();

        // ProviderSubscription 획득 후 즉시 close — keepAlive 가 없으면
        // AutoDispose Provider 는 이 시점에 dispose 되어 state 가 false 로
        // 초기화된다.
        final subscription = container.listen(
          socialLinkInProgressProvider,
          (prev, next) {},
        );
        subscription.close();

        // keepAlive: true 이므로 dispose 되지 않아 state=true 가 유지되어야 한다.
        final stateAfterClose = container.read(socialLinkInProgressProvider);

        expect(
          stateAfterClose,
          isTrue,
          reason: 'keepAlive: true 이므로 listener 해제 후에도 state 가 reset 되어서는 안 된다',
        );
      });
    },
  );
}
