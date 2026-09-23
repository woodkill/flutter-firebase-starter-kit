// quick 260923-cs5 — 16.4 code review IN-06 회귀 가드.
//
// **왜 provider 별 테스트 파일이 아니라 cross-provider 1파일인가:** IN-06 이
// 16.4 fix pass 에서 skip 된 사유가 「naver 단독 수정은 7 provider 대칭
// invariant 를 깨뜨린다」 였다. 각 notifier docstring 에 「이 동작은 7 provider
// 가 문자 단위로 동일하며」 가 명문화되어 있으므로, 그 대칭을 지키는 guard 도
// provider 별로 흩어진 7개 테스트가 아니라 한 표에서 잠근다 — 표가
// [kAllProviderIds] 와 1:1 임을 먼저 단언하므로 8번째 provider 가 추가되고
// 행이 누락되면 이 파일이 FAIL 한다.
//
// 잠그는 invariant: `state = AsyncLoading` 직후의 `ref.read(authRepositoryProvider)`
// 가 동기 throw 하면(provider 생성 실패) state 가 영구 AsyncLoading 에 남아
// AuthInProgressOverlay 의 AbsorbPointer 가 화면을 덮은 채 앱 재시작 외
// 탈출구가 없다. guard 는 state 를 AsyncError 로 되돌리고 예외는 rethrow 한다.

import 'package:flutter_riverpod/flutter_riverpod.dart';
// ProviderException 은 메인 라이브러리의 show 목록에 없고 misc.dart 가 export
// 한다 (flutter_riverpod 3.3.1 misc.dart:17).
import 'package:flutter_riverpod/misc.dart' show ProviderException;
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_starter_kit/core/auth/provider_id.dart';
import 'package:flutter_starter_kit/features/auth/data/auth_repository.dart';
import 'package:flutter_starter_kit/features/auth/presentation/apple_sign_in_notifier.dart';
import 'package:flutter_starter_kit/features/auth/presentation/facebook_sign_in_notifier.dart';
import 'package:flutter_starter_kit/features/auth/presentation/google_sign_in_notifier.dart';
import 'package:flutter_starter_kit/features/auth/presentation/kakao_sign_in_notifier.dart';
import 'package:flutter_starter_kit/features/auth/presentation/line_sign_in_notifier.dart';
import 'package:flutter_starter_kit/features/auth/presentation/naver_sign_in_notifier.dart';
import 'package:flutter_starter_kit/features/auth/presentation/yahoojp_sign_in_notifier.dart';

/// 소셜 notifier 1개를 provider-agnostic 하게 호출하기 위한 표 1행.
///
/// 7 provider 의 notifier 는 클래스·메서드 이름만 다르고 본문 구조가 동일하다.
/// 이 표가 그 구조적 동일성을 테스트 코드에서 복사-붙여넣기 7번 대신 순회 1번
/// 으로 검증하게 한다.
final class _NotifierCase {
  /// 표 1행을 만든다.
  const _NotifierCase({
    required this.providerId,
    required this.signIn,
    required this.readState,
  });

  /// 도메인 provider 슬러그 ([kAllProviderIds] 의 원소).
  final String providerId;

  /// 해당 notifier 의 `signInWithXxx()` 를 호출한다.
  final Future<void> Function(ProviderContainer container) signIn;

  /// 해당 notifier 의 현재 state 를 읽는다.
  final AsyncValue<void> Function(ProviderContainer container) readState;
}

/// 7 소셜 notifier 표 — 순서는 진실원 [kAllProviderIds] 와 같다.
final List<_NotifierCase> _cases = <_NotifierCase>[
  _NotifierCase(
    providerId: kProviderIdGoogle,
    signIn: (container) =>
        container.read(googleSignInProvider.notifier).signInWithGoogle(),
    readState: (container) => container.read(googleSignInProvider),
  ),
  _NotifierCase(
    providerId: kProviderIdApple,
    signIn: (container) =>
        container.read(appleSignInProvider.notifier).signInWithApple(),
    readState: (container) => container.read(appleSignInProvider),
  ),
  _NotifierCase(
    providerId: kProviderIdFacebook,
    signIn: (container) =>
        container.read(facebookSignInProvider.notifier).signInWithFacebook(),
    readState: (container) => container.read(facebookSignInProvider),
  ),
  _NotifierCase(
    providerId: kProviderIdKakao,
    signIn: (container) =>
        container.read(kakaoSignInProvider.notifier).signInWithKakao(),
    readState: (container) => container.read(kakaoSignInProvider),
  ),
  _NotifierCase(
    providerId: kProviderIdNaver,
    signIn: (container) =>
        container.read(naverSignInProvider.notifier).signInWithNaver(),
    readState: (container) => container.read(naverSignInProvider),
  ),
  _NotifierCase(
    providerId: kProviderIdLine,
    signIn: (container) =>
        container.read(lineSignInProvider.notifier).signInWithLine(),
    readState: (container) => container.read(lineSignInProvider),
  ),
  _NotifierCase(
    providerId: kProviderIdYahooJp,
    signIn: (container) =>
        container.read(yahoojpSignInProvider.notifier).signInWithYahoojp(),
    readState: (container) => container.read(yahoojpSignInProvider),
  ),
];

void main() {
  // naver 행은 kDebugMode(테스트 기본값) 에서 `AppLifecycleListener` 를 만들고
  // 그 생성자가 `WidgetsBinding.instance` 를 요구한다 — 이 줄이 없으면 naver
  // 행이 guard 도달 전에 생성자에서 깨진다
  // (naver_sign_in_notifier_test.dart:41-44 와 같은 이유).
  TestWidgetsFlutterBinding.ensureInitialized();

  /// `authRepositoryProvider` 생성 자체가 실패하는 container 를 만든다.
  ///
  /// sentinel 을 [StateError] 로 던지는 이유: riverpod 3.2.1 의
  /// `ProviderContainer.defaultRetry` 가 `error is ProviderException ||
  /// error is Error` 면 `null` 을 반환하므로 재시도 Timer 가 생기지 않는다
  /// (provider_container.dart:831-845). `Exception` 을 던지면 200ms 재시도
  /// Timer 가 걸려 flutter_test 가 pending Timer 로 실패한다.
  ProviderContainer makeContainer() {
    final container = ProviderContainer(
      overrides: [
        authRepositoryProvider.overrideWith(
          (_) =>
              throw StateError('IN-06 sentinel: authRepositoryProvider 생성 실패'),
        ),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  group('소셜 notifier AsyncLoading 누수 가드 (16.4 IN-06 · quick 260923-cs5)', () {
    test('표가 kAllProviderIds 와 1:1 이다 (vacuous pass 차단)', () {
      expect(_cases.map((c) => c.providerId).toList(), kAllProviderIds);
    });

    for (final testCase in _cases) {
      test('[${testCase.providerId}] ref.read 동기 throw → AsyncError 로 '
          '전환되고 예외는 rethrow 된다 (IN-06)', () async {
        final container = makeContainer();

        // 1) rethrow 계약 — notifier 가 받는 것은 `Ref.read` 가 감싼
        //    ProviderException 이고 `.exception` 이 위 StateError 다
        //    (ref.dart:537 → provider_container.dart:916-920 →
        //    stack_trace.dart:9). 이 단언을 먼저 두어, guard 가 없는 상태에서도
        //    「rethrow 는 원래 되고 있었고 새는 것은 state 뿐」 이 로그에
        //    드러나게 한다.
        await expectLater(
          testCase.signIn(container),
          throwsA(
            isA<ProviderException>().having(
              (e) => e.exception,
              'exception',
              isA<StateError>(),
            ),
          ),
        );

        // 2) state 가 AsyncLoading 에 남지 않는다 — guard 가 잠그는 본체.
        final state = testCase.readState(container);
        expect(
          state.isLoading,
          isFalse,
          reason:
              'AsyncLoading 누수 = AuthInProgressOverlay AbsorbPointer 영구 차단 (IN-06)',
        );
        expect(state, isA<AsyncError<void>>());
        expect(state.hasError, isTrue);
        expect(
          state.error,
          isA<ProviderException>().having(
            (e) => e.exception,
            'exception',
            isA<StateError>(),
          ),
        );
      });
    }
  });
}
