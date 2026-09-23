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
// 탈출구가 없다. guard 는 state 를 AsyncError 로 되돌린 뒤 **예외를 밖으로
// 전파하지 않고 종료한다**.
//
// **계약이 뒤집힌 이력 (16.4 code review WR-03):** 이 파일의 최초 판
// (`f8908659`) 은 「state 복구 + rethrow」 를 계약으로 잠갔다. 그런데 호출부
// `social_button.dart` 가 반환 Future 를 버리므로(fire-and-forget) rethrow 된
// 예외는 아무도 받지 않는 unhandled error 가 되어 zone 으로 올라갔고,
// `bootstrap.dart` 가 그것을 Crashlytics 에 `fatal: true` 로 기록했다 — 같은
// 한 번의 실패가 「배너로 복구 안내」 와 「치명적으로 죽었다」 두 형태로
// 동시에 보고되는 모순이다. 그래서 계약을 「예외를 밖으로 던지지 않고 정상
// 완료하며, state 만 AsyncError 가 된다」 로 재정의했다. 로그는 잃지 않는다 —
// 각 notifier 가 `kDebugMode` 아래에서 예외 **타입만** 찍는다 (PII 표면 0).

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:flutter_starter_kit/core/auth/provider_id.dart';
import 'package:flutter_starter_kit/features/auth/data/auth_repository.dart';
import 'package:flutter_starter_kit/features/auth/presentation/apple_sign_in_notifier.dart';
import 'package:flutter_starter_kit/features/auth/presentation/facebook_sign_in_notifier.dart';
import 'package:flutter_starter_kit/features/auth/presentation/google_sign_in_notifier.dart';
import 'package:flutter_starter_kit/features/auth/presentation/kakao_sign_in_notifier.dart';
import 'package:flutter_starter_kit/features/auth/presentation/line_sign_in_notifier.dart';
import 'package:flutter_starter_kit/features/auth/presentation/naver_sign_in_notifier.dart';
import 'package:flutter_starter_kit/features/auth/presentation/yahoojp_sign_in_notifier.dart';

/// provider **생성** 실패 축의 sentinel 문구 (첫 번째 축).
///
/// 단언이 이 상수를 그대로 참조하므로 문구를 바꿔도 테스트가 조용히 공허해지지
/// 않는다 (16.4 code review IN-04).
const String _kProviderCreateSentinel =
    'IN-06 sentinel: authRepositoryProvider 생성 실패';

/// `AuthRepository` mock — 두 번째 축(repository 호출이 예외를 흘린다) 전용.
class _MockAuthRepository extends Mock implements AuthRepository {}

/// repository 호출이 **비동기로** 던지는 예외의 sentinel (16.4 IN-02).
///
/// `Exception` 계열을 고른 이유: 첫 번째 축(provider 생성 실패) 은 오랫동안
/// riverpod 재시도 Timer 회피 때문에 `Error` 로 고정돼 있었고, 그래서
/// `Exception` 계열이 통째로 미검증으로 남아 있었다(IN-04 가 `retry` 를
/// 명시적으로 넘겨 그 제약을 없앴다). 이 축은 provider **생성**이 아니라 이미
/// 만들어진 repository 의 메서드 호출이라 애초에 재시도 정책과 무관하다.
final class _RepoThrowSentinel implements Exception {
  const _RepoThrowSentinel();

  @override
  String toString() => 'IN-02 sentinel: repository 호출이 비동기로 throw';
}

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
    required this.stubAsyncThrow,
  });

  /// 도메인 provider 슬러그 ([kAllProviderIds] 의 원소).
  final String providerId;

  /// 해당 notifier 의 `signInWithXxx()` 를 호출한다.
  final Future<void> Function(ProviderContainer container) signIn;

  /// 해당 notifier 의 현재 state 를 읽는다.
  final AsyncValue<void> Function(ProviderContainer container) readState;

  /// 이 notifier 가 호출하는 repository 메서드를 「비동기 throw」 로 stub 한다
  /// (16.4 IN-02 — 두 번째 축).
  final void Function(AuthRepository repo) stubAsyncThrow;
}

/// 7 소셜 notifier 표 — 순서는 진실원 [kAllProviderIds] 와 같다.
final List<_NotifierCase> _cases = <_NotifierCase>[
  _NotifierCase(
    providerId: kProviderIdGoogle,
    signIn: (container) =>
        container.read(googleSignInProvider.notifier).signInWithGoogle(),
    readState: (container) => container.read(googleSignInProvider),
    stubAsyncThrow: (repo) => when(
      () => repo.signInWithGoogle(),
    ).thenAnswer((_) async => throw const _RepoThrowSentinel()),
  ),
  _NotifierCase(
    providerId: kProviderIdApple,
    signIn: (container) =>
        container.read(appleSignInProvider.notifier).signInWithApple(),
    readState: (container) => container.read(appleSignInProvider),
    stubAsyncThrow: (repo) => when(
      () => repo.signInWithApple(),
    ).thenAnswer((_) async => throw const _RepoThrowSentinel()),
  ),
  _NotifierCase(
    providerId: kProviderIdFacebook,
    signIn: (container) =>
        container.read(facebookSignInProvider.notifier).signInWithFacebook(),
    readState: (container) => container.read(facebookSignInProvider),
    stubAsyncThrow: (repo) => when(
      () => repo.signInWithFacebook(),
    ).thenAnswer((_) async => throw const _RepoThrowSentinel()),
  ),
  _NotifierCase(
    providerId: kProviderIdKakao,
    signIn: (container) =>
        container.read(kakaoSignInProvider.notifier).signInWithKakao(),
    readState: (container) => container.read(kakaoSignInProvider),
    stubAsyncThrow: (repo) => when(
      () => repo.signInWithKakao(),
    ).thenAnswer((_) async => throw const _RepoThrowSentinel()),
  ),
  _NotifierCase(
    providerId: kProviderIdNaver,
    signIn: (container) =>
        container.read(naverSignInProvider.notifier).signInWithNaver(),
    readState: (container) => container.read(naverSignInProvider),
    stubAsyncThrow: (repo) => when(
      () => repo.signInWithNaver(),
    ).thenAnswer((_) async => throw const _RepoThrowSentinel()),
  ),
  _NotifierCase(
    providerId: kProviderIdLine,
    signIn: (container) =>
        container.read(lineSignInProvider.notifier).signInWithLine(),
    readState: (container) => container.read(lineSignInProvider),
    stubAsyncThrow: (repo) => when(
      () => repo.signInWithLine(),
    ).thenAnswer((_) async => throw const _RepoThrowSentinel()),
  ),
  _NotifierCase(
    providerId: kProviderIdYahooJp,
    signIn: (container) =>
        container.read(yahoojpSignInProvider.notifier).signInWithYahoojp(),
    readState: (container) => container.read(yahoojpSignInProvider),
    stubAsyncThrow: (repo) => when(
      () => repo.signInWithYahoojp(),
    ).thenAnswer((_) async => throw const _RepoThrowSentinel()),
  ),
];

void main() {
  // `ProviderContainer` 단위 테스트지만 flutter_test 바인딩을 초기화해 둔다.
  //
  // **근거가 소멸한 주석을 대체한다 (16.4 code review IN-01).** 이 파일이
  // 만들어진 `f8908659` 시점에는 naver 행이 `kDebugMode` 에서
  // `AppLifecycleListener` 를 만들었고 그 생성자가 `WidgetsBinding.instance`
  // 를 요구해 이 줄이 **필수**였다. 그런데 `54f7b9d2`(레버 5 제거)가 그
  // `AppLifecycleListener` 를 삭제해 현재 `naver_sign_in_notifier.dart` 에
  // 해당 식별자는 0건이고, 옛 주석이 인용하던
  // `naver_sign_in_notifier_test.dart:41-44` 도 실제로는 `User` fixture 필드라
  // 두 전제가 모두 거짓이 됐다. 지금 이 줄은 riverpod 스케줄러가 바인딩 위에서
  // 결정론적으로 도는 것을 보장하는 위생 목적으로만 남긴다.
  TestWidgetsFlutterBinding.ensureInitialized();

  /// `authRepositoryProvider` 생성 자체가 실패하는 container 를 만든다.
  ///
  /// **riverpod 내부 구현에 결합하지 않는다 (16.4 code review IN-04).** 종전에는
  /// sentinel 을 [StateError] 로 고른 것만으로 재시도 Timer 를 피했는데, 그
  /// 회피는 `ProviderContainer.defaultRetry` 의 「`error is Error` 면 재시도하지
  /// 않는다」 구현(riverpod 3.2.1 `provider_container.dart`)에 의존한 것이라
  /// 그 조건이 바뀌면 production 결함 없이 pending Timer 로 RED 가 됐다. 이제
  /// `retry` 를 명시적으로 넘겨 그 의존을 끊는다 — sentinel 의 타입 선택은 더
  /// 이상 load-bearing 이 아니다.
  ProviderContainer makeContainer() {
    final container = ProviderContainer(
      retry: (_, _) => null,
      overrides: [
        authRepositoryProvider.overrideWith(
          (_) => throw StateError(_kProviderCreateSentinel),
        ),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  /// repository 는 정상 생성되지만 **메서드 호출이 비동기로 throw** 하는
  /// container 를 만든다 (16.4 code review IN-02 — 두 번째 축).
  ProviderContainer makeThrowingRepoContainer(_NotifierCase testCase) {
    final repo = _MockAuthRepository();
    testCase.stubAsyncThrow(repo);
    final container = ProviderContainer(
      overrides: [authRepositoryProvider.overrideWithValue(repo)],
    );
    addTearDown(container.dispose);
    return container;
  }

  group('소셜 notifier AsyncLoading 누수 가드 (16.4 IN-06 · quick 260923-cs5)', () {
    test('표가 kAllProviderIds 와 1:1 이다 (vacuous pass 차단)', () {
      expect(_cases.map((c) => c.providerId).toList(), kAllProviderIds);
    });

    for (final testCase in _cases) {
      test('[${testCase.providerId}] ref.read 동기 throw → 예외를 밖으로 던지지 '
          '않고 AsyncError 로 전환된다 (IN-06 · WR-03)', () async {
        final container = makeContainer();

        // 1) **전파 금지 계약 (16.4 code review WR-03 — 계약 반전).**
        //    종전에는 이 자리에 `throwsA(isA<ProviderException>()…)` 가 있어
        //    「예외는 밖으로 나간다」 를 의도된 계약으로 잠갔다. 호출부가
        //    Future 를 버리는 이 킷에서 그 전파는 곧 Crashlytics fatal 오보이므로
        //    (파일 머리말 참조), 계약을 「정상 완료」 로 뒤집었다.
        await expectLater(
          testCase.signIn(container),
          completes,
          reason:
              '예외가 밖으로 나가면 fire-and-forget Future 의 unhandled error 가 되어 '
              'bootstrap 이 Crashlytics 에 fatal: true 로 오보한다 (WR-03)',
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
        // **원인 체인 단언 (16.4 code review IN-04).** 종전에는
        // `isA<ProviderException>().having((e) => e.exception, …)` 로 단언해
        // 메인 배럴이 export 하지 않는 보조 entrypoint(`misc.dart`) 의 심볼에
        // 결합돼 있었다. 우리가 잠그려는 것은 래퍼 타입이 아니라 「guard 가
        // 삼킨 것이 바로 그 sentinel 이다」 이므로, 원인 체인에 sentinel 이
        // 남아 있는지만 본다 — import 1개가 사라지고 상향 내성이 올라간다.
        // sentinel 문구 하나가 곧 정체성이다 — `StateError.toString()` 은
        // 타입 이름이 아니라 `Bad state: …` 로 렌더링되므로 타입 이름을
        // 찾는 단언은 두지 않는다 (실측으로 확인).
        expect(
          state.error.toString(),
          contains(_kProviderCreateSentinel),
          reason: '원인 체인에서 sentinel 이 사라지면 guard 가 다른 예외를 실은 것이다',
        );
      });
    }

    // 16.4 code review IN-02 — docstring 이 주장하는 범위는 두 축
    // (「ref.read 가 동기 throw」 **또는** 「repository 호출이 예외를 흘린다」)
    // 인데 위 축 하나만 덮여 있었다. 게다가 그 축은 재시도 Timer 회피 때문에
    // `Error` 서브타입에 한정돼 `Exception` 계열도 함께 비어 있었다. 이 축이
    // 두 공백을 동시에 메운다 — 비동기 throw + `Exception` 계열.
    for (final testCase in _cases) {
      test('[${testCase.providerId}] repository 호출이 비동기 throw → 예외를 '
          '밖으로 던지지 않고 AsyncError 로 전환된다 (IN-02 · WR-03)', () async {
        final container = makeThrowingRepoContainer(testCase);

        await expectLater(
          testCase.signIn(container),
          completes,
          reason: 'await 이후 경로에서도 전파 금지 계약은 같다 (WR-03)',
        );

        final state = testCase.readState(container);
        expect(
          state.isLoading,
          isFalse,
          reason:
              'AsyncLoading 누수 = AuthInProgressOverlay AbsorbPointer 영구 차단 (IN-06)',
        );
        expect(state, isA<AsyncError<void>>());
        // payload 는 래퍼 없이 우리가 던진 그 객체다 — `Result.failure` 경로와
        // 달리 `AppException` 이 아니다 (IN-05 가 docstring 에 기록한 확장).
        expect(state.error, isA<_RepoThrowSentinel>());
      });
    }
  });
}
