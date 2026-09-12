import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:flutter_starter_kit/core/error/app_exception.dart';
import 'package:flutter_starter_kit/core/error/result.dart';
import 'package:flutter_starter_kit/core/providers/firebase_providers.dart';
import 'package:flutter_starter_kit/core/router/auth_guard.dart';
import 'package:flutter_starter_kit/features/auth/data/auth_repository.dart';
import 'package:flutter_starter_kit/features/auth/presentation/verify_email_notifier.dart';
import 'package:flutter_starter_kit/features/auth/presentation/verify_email_state.dart';

// --- Mocks ---

class _MockAuthRepository extends Mock implements AuthRepository {}

class _MockFirebaseAuth extends Mock implements fb.FirebaseAuth {}

class _MockUser extends Mock implements fb.User {}

class _MockAuthChangeNotifier extends Mock implements AuthChangeNotifier {}

void main() {
  late _MockAuthRepository mockRepo;
  late _MockFirebaseAuth mockAuth;
  late _MockUser mockUser;
  late _MockAuthChangeNotifier mockChangeNotifier;

  setUp(() {
    mockRepo = _MockAuthRepository();
    mockAuth = _MockFirebaseAuth();
    mockUser = _MockUser();
    mockChangeNotifier = _MockAuthChangeNotifier();

    // 기본 stub: reloadUser 성공, emailVerified false
    when(
      () => mockRepo.reloadUser(),
    ).thenAnswer((_) async => const Result.success(null));
    when(() => mockAuth.currentUser).thenReturn(mockUser);
    when(() => mockUser.emailVerified).thenReturn(false);
  });

  /// ProviderContainer를 생성한다.
  ProviderContainer makeContainer() {
    final container = ProviderContainer(
      overrides: [
        authRepositoryProvider.overrideWithValue(mockRepo),
        firebaseAuthProvider.overrideWithValue(mockAuth),
        authChangeProvider.overrideWithValue(mockChangeNotifier),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  group('VerifyEmailNotifier', () {
    test('Test 1: build() 시 초기 상태가 올바르다', () {
      final container = makeContainer();

      final state = container.read(verifyEmailProvider);

      expect(state, isA<AsyncData<VerifyEmailState>>());
      final value = state.requireValue;
      expect(value.isPolling, isTrue);
      expect(value.cooldownRemaining, 0);
      expect(value.isChecking, isFalse);
      expect(value.error, isNull);
    });

    test('Test 2: pollOnce 호출 시 reloadUser가 호출된다', () async {
      final container = makeContainer();
      container.read(verifyEmailProvider);

      await container.read(verifyEmailProvider.notifier).pollOnce();

      verify(() => mockRepo.reloadUser()).called(1);
    });

    test('Test 3: pollOnce에서 emailVerified==true 감지 시 redirect 트리거', () async {
      final container = makeContainer();
      container.read(verifyEmailProvider);

      // emailVerified=true로 설정
      when(() => mockUser.emailVerified).thenReturn(true);

      await container.read(verifyEmailProvider.notifier).pollOnce();

      // authChangeNotifier.notifyListeners() 호출로 redirect 재평가
      verify(() => mockChangeNotifier.triggerRedirect()).called(greaterThan(0));
    });

    test('Test 3b: pollOnce에서 emailVerified==false면 '
        'redirect 트리거하지 않는다', () async {
      final container = makeContainer();
      container.read(verifyEmailProvider);

      // emailVerified는 기본 false
      await container.read(verifyEmailProvider.notifier).pollOnce();

      verifyNever(() => mockChangeNotifier.triggerRedirect());
    });

    test('Test 4: stopPolling 호출 시 isPolling이 false로 전환된다', () {
      final container = makeContainer();
      container.read(verifyEmailProvider);

      // 초기 상태: isPolling == true
      expect(
        container.read(verifyEmailProvider).requireValue.isPolling,
        isTrue,
      );

      container.read(verifyEmailProvider.notifier).stopPolling();

      expect(
        container.read(verifyEmailProvider).requireValue.isPolling,
        isFalse,
      );
    });

    test('Test 4b: 폴링 타임아웃 상수가 300초(5분)이다', () {
      expect(pollingTimeoutSeconds, 300);
      expect(pollingIntervalSeconds, 3);
    });

    test('Test 5: resendVerification 성공 시 cooldownRemaining이 '
        '60으로 설정된다', () async {
      when(
        () => mockRepo.sendEmailVerification(),
      ).thenAnswer((_) async => const Result.success(null));

      final container = makeContainer();
      container.read(verifyEmailProvider);

      await container.read(verifyEmailProvider.notifier).resendVerification();

      final state = container.read(verifyEmailProvider);
      expect(state.requireValue.cooldownRemaining, cooldownSeconds);
      expect(state.requireValue.error, isNull);
    });

    test('Test 5b: tickCooldown 호출 시 cooldownRemaining이 1씩 감소한다', () async {
      when(
        () => mockRepo.sendEmailVerification(),
      ).thenAnswer((_) async => const Result.success(null));

      final container = makeContainer();
      container.read(verifyEmailProvider);

      await container.read(verifyEmailProvider.notifier).resendVerification();

      final notifier = container.read(verifyEmailProvider.notifier);

      // 60에서 시작, 1 감소
      notifier.tickCooldown();
      expect(
        container.read(verifyEmailProvider).requireValue.cooldownRemaining,
        cooldownSeconds - 1,
      );

      // 한 번 더 감소
      notifier.tickCooldown();
      expect(
        container.read(verifyEmailProvider).requireValue.cooldownRemaining,
        cooldownSeconds - 2,
      );
    });

    test('Test 5c: cooldownRemaining이 1일 때 tickCooldown 호출 시 0이 된다', () async {
      when(
        () => mockRepo.sendEmailVerification(),
      ).thenAnswer((_) async => const Result.success(null));

      final container = makeContainer();
      container.read(verifyEmailProvider);

      await container.read(verifyEmailProvider.notifier).resendVerification();

      final notifier = container.read(verifyEmailProvider.notifier);

      // cooldownRemaining을 1까지 감소시킨다
      for (var i = 0; i < cooldownSeconds - 1; i++) {
        notifier.tickCooldown();
      }
      expect(
        container.read(verifyEmailProvider).requireValue.cooldownRemaining,
        1,
      );

      // 마지막 tick: 0이 되어야 한다
      notifier.tickCooldown();
      expect(
        container.read(verifyEmailProvider).requireValue.cooldownRemaining,
        0,
      );
    });

    test('Test 6: resendVerification 실패 시 error에 AppException 설정', () async {
      when(
        () => mockRepo.sendEmailVerification(),
      ).thenAnswer((_) async => const Result.failure(TooManyRequests()));

      final container = makeContainer();
      container.read(verifyEmailProvider);

      await container.read(verifyEmailProvider.notifier).resendVerification();

      final state = container.read(verifyEmailProvider);
      expect(state.requireValue.error, isA<TooManyRequests>());
      // 실패 시 쿨다운 시작하지 않는다
      expect(state.requireValue.cooldownRemaining, 0);
    });

    test('Test 7: checkManually 호출 시 emailVerified==true면 '
        'redirect 트리거', () async {
      final container = makeContainer();
      container.read(verifyEmailProvider);

      // emailVerified=true로 설정
      when(() => mockUser.emailVerified).thenReturn(true);

      await container.read(verifyEmailProvider.notifier).checkManually();

      // redirect 트리거 확인
      verify(() => mockChangeNotifier.triggerRedirect()).called(greaterThan(0));
    });

    test('Test 7b: checkManually 호출 시 emailVerified==false면 '
        'isChecking=false 복귀', () async {
      final container = makeContainer();
      container.read(verifyEmailProvider);

      // emailVerified는 기본 false
      await container.read(verifyEmailProvider.notifier).checkManually();

      final state = container.read(verifyEmailProvider);
      expect(state.requireValue.isChecking, isFalse);
    });

    test('Test 6b: resendVerification에서 ServiceUnavailable 에러 시 '
        'error에 ServiceUnavailable 설정 '
        '(Firebase 이메일 인증 미설정)', () async {
      // Firebase Console에서 이메일 인증이 활성화되지 않은 경우
      // operation-not-allowed → ServiceUnavailable로 매핑된다.
      when(
        () => mockRepo.sendEmailVerification(),
      ).thenAnswer((_) async => const Result.failure(ServiceUnavailable()));

      final container = makeContainer();
      container.read(verifyEmailProvider);

      await container.read(verifyEmailProvider.notifier).resendVerification();

      final state = container.read(verifyEmailProvider);
      expect(state.requireValue.error, isA<ServiceUnavailable>());
      // 실패 시 쿨다운 시작하지 않는다
      expect(state.requireValue.cooldownRemaining, 0);
    });

    test('Test 6c: resendVerification 실패 후 재시도 성공 시 '
        'error가 null로 초기화된다 (에러 복구 가능)', () async {
      // 1차: ServiceUnavailable 실패
      when(
        () => mockRepo.sendEmailVerification(),
      ).thenAnswer((_) async => const Result.failure(ServiceUnavailable()));

      final container = makeContainer();
      container.read(verifyEmailProvider);

      await container.read(verifyEmailProvider.notifier).resendVerification();

      expect(
        container.read(verifyEmailProvider).requireValue.error,
        isA<ServiceUnavailable>(),
      );

      // 2차: 재시도 성공
      when(
        () => mockRepo.sendEmailVerification(),
      ).thenAnswer((_) async => const Result.success(null));

      await container.read(verifyEmailProvider.notifier).resendVerification();

      final state = container.read(verifyEmailProvider);
      // error가 null로 초기화되었는지 확인
      expect(state.requireValue.error, isNull);
      // 성공했으므로 쿨다운 시작
      expect(state.requireValue.cooldownRemaining, cooldownSeconds);
    });

    test('Test 8: logout 호출 시 signOutAndResetOnboarding (I2 진리원) + '
        'redirect 트리거 (Phase 10.2 CR-01 iter3)', () async {
      // Phase 10.2 D-A7 호출자 책임: UI 로그아웃 path 는 반드시
      // signOutAndResetOnboarding 경유 (signOut 단독 호출 금지).
      when(() => mockRepo.signOutAndResetOnboarding()).thenAnswer((_) async {});

      final container = makeContainer();
      container.read(verifyEmailProvider);

      await container.read(verifyEmailProvider.notifier).logout();

      verify(() => mockRepo.signOutAndResetOnboarding()).called(1);
      // signOut 단독 호출 금지 회귀 가드 (CR-01 sentinel).
      verifyNever(() => mockRepo.signOut());
      // signOut 후 redirect 트리거 확인
      verify(() => mockChangeNotifier.triggerRedirect()).called(greaterThan(0));
    });

    // --- WR-02 (Phase 09 review) — reloadUser Failure 를 상태로 매핑 ---

    test('WR-02 Test 9: checkManually 가 reloadUser Failure 를 error 로 매핑하고 '
        'isChecking 을 false 로 되돌린다 (이전에는 Result 를 통째로 버려 '
        '오프라인에서 에러 표시가 0이었다)', () async {
      final container = makeContainer();
      container.read(verifyEmailProvider);

      const failure = NoInternetConnection();
      when(
        () => mockRepo.reloadUser(),
      ).thenAnswer((_) async => const Result.failure(failure));

      await container.read(verifyEmailProvider.notifier).checkManually();

      final value = container.read(verifyEmailProvider).requireValue;
      expect(value.error, same(failure));
      expect(value.isChecking, isFalse);
      // 실패했으므로 redirect 는 트리거되지 않는다.
      verifyNever(() => mockChangeNotifier.triggerRedirect());
    });

    test('WR-02 Test 9b: checkManually 재시도 성공 시 직전 error 가 잔류하지 않는다', () async {
      final container = makeContainer();
      container.read(verifyEmailProvider);

      when(
        () => mockRepo.reloadUser(),
      ).thenAnswer((_) async => const Result.failure(NoInternetConnection()));
      await container.read(verifyEmailProvider.notifier).checkManually();
      expect(container.read(verifyEmailProvider).requireValue.error, isNotNull);

      // 재시도 — 성공하면 배너가 사라져야 한다.
      when(
        () => mockRepo.reloadUser(),
      ).thenAnswer((_) async => const Result.success(null));
      await container.read(verifyEmailProvider.notifier).checkManually();

      final value = container.read(verifyEmailProvider).requireValue;
      expect(value.error, isNull);
      expect(value.isChecking, isFalse);
    });

    test('WR-02 Test 10: pollOnce 는 1~2회 실패를 조용히 흡수하고 '
        '연속 pollFailureThreshold 회에 도달해야 폴링을 멈추고 error 를 세팅한다', () async {
      final container = makeContainer();
      container.read(verifyEmailProvider);

      const failure = NoInternetConnection();
      when(
        () => mockRepo.reloadUser(),
      ).thenAnswer((_) async => const Result.failure(failure));

      final notifier = container.read(verifyEmailProvider.notifier);

      // 임계값 직전까지는 소음 없이 폴링을 계속한다.
      for (var i = 0; i < pollFailureThreshold - 1; i++) {
        await notifier.pollOnce();
        final value = container.read(verifyEmailProvider).requireValue;
        expect(value.error, isNull, reason: '${i + 1}회차는 아직 흡수 구간');
        expect(value.isPolling, isTrue);
      }

      // 임계값 도달 — 중지 + 에러 노출.
      await notifier.pollOnce();
      final value = container.read(verifyEmailProvider).requireValue;
      expect(value.error, same(failure));
      expect(value.isPolling, isFalse);
    });

    test('WR-02 Test 10b: pollOnce 성공 1회로 연속 실패 카운터가 초기화되어 '
        '간헐적 실패만으로는 폴링이 멈추지 않는다', () async {
      final container = makeContainer();
      container.read(verifyEmailProvider);
      final notifier = container.read(verifyEmailProvider.notifier);

      // 실패 → 성공 → 실패 … 를 임계값의 2배만큼 반복해도 "연속" 이 아니므로
      // 폴링은 계속되어야 한다.
      for (var i = 0; i < pollFailureThreshold * 2; i++) {
        when(
          () => mockRepo.reloadUser(),
        ).thenAnswer((_) async => const Result.failure(NoInternetConnection()));
        await notifier.pollOnce();

        when(
          () => mockRepo.reloadUser(),
        ).thenAnswer((_) async => const Result.success(null));
        await notifier.pollOnce();
      }

      final value = container.read(verifyEmailProvider).requireValue;
      expect(value.error, isNull);
      expect(value.isPolling, isTrue);
    });

    // --- WR-03 (Phase 09 review) — resendVerification 재진입 가드 ---

    test('WR-03 Test 11: resendVerification 이 네트워크 왕복 **전에** '
        'isResending 을 세운다 (그 전까지 상태 변화가 0이라 버튼이 계속 활성이었다)', () async {
      final container = makeContainer();
      // verifyEmailProvider 는 autoDispose 다. 아래에서 event loop 에 양보하는
      // 사이 구독이 0이면 provider 가 폐기되고 다음 read 가 **새 상태**를
      // 만들어 in-flight 관찰이 불가능해진다 — 구독을 살려 둔다.
      container.listen(verifyEmailProvider, (_, _) {}, fireImmediately: true);

      // 왕복이 끝나기 전 상태를 관찰하기 위해 완료를 보류시킨다.
      final gate = Completer<Result<void>>();
      when(
        () => mockRepo.sendEmailVerification(),
      ).thenAnswer((_) => gate.future);

      final pending = container
          .read(verifyEmailProvider.notifier)
          .resendVerification();
      await Future<void>.delayed(Duration.zero);

      // in-flight 구간: 쿨다운은 아직 0인데 isResending 이 버튼을 잠근다.
      final inFlight = container.read(verifyEmailProvider).requireValue;
      expect(inFlight.isResending, isTrue);
      expect(inFlight.cooldownRemaining, 0);

      gate.complete(const Result.success(null));
      await pending;

      final settled = container.read(verifyEmailProvider).requireValue;
      expect(settled.isResending, isFalse);
      expect(settled.cooldownRemaining, cooldownSeconds);
    });

    test('WR-03 Test 12: in-flight 중 연타해도 sendEmailVerification 은 1회만 '
        '호출된다 (중복 인증 메일 + too-many-requests 유발 차단)', () async {
      final container = makeContainer();
      // autoDispose 폐기 방지 (Test 11 주석 참조).
      container.listen(verifyEmailProvider, (_, _) {}, fireImmediately: true);

      final gate = Completer<Result<void>>();
      when(
        () => mockRepo.sendEmailVerification(),
      ).thenAnswer((_) => gate.future);

      final notifier = container.read(verifyEmailProvider.notifier);
      final first = notifier.resendVerification();
      await Future<void>.delayed(Duration.zero);

      // 응답이 느린 네트워크에서 사용자가 2~3회 연타하는 상황.
      await notifier.resendVerification();
      await notifier.resendVerification();

      gate.complete(const Result.success(null));
      await first;

      verify(() => mockRepo.sendEmailVerification()).called(1);
    });

    test('WR-03 Test 12b: 쿨다운 중 호출은 notifier 가 자체 차단한다 '
        '(방어선이 UI 단독 → notifier + UI 이중)', () async {
      when(
        () => mockRepo.sendEmailVerification(),
      ).thenAnswer((_) async => const Result.success(null));

      final container = makeContainer();
      container.read(verifyEmailProvider);
      final notifier = container.read(verifyEmailProvider.notifier);

      await notifier.resendVerification();
      expect(
        container.read(verifyEmailProvider).requireValue.cooldownRemaining,
        cooldownSeconds,
      );

      // 쿨다운이 남은 동안의 재호출 — UI 비활성화를 우회해 직접 불러도 무시.
      await notifier.resendVerification();

      verify(() => mockRepo.sendEmailVerification()).called(1);
    });

    test('WR-03 Test 13: 실패 시에도 isResending 이 false 로 풀려 '
        '버튼이 영구 잠기지 않는다', () async {
      when(
        () => mockRepo.sendEmailVerification(),
      ).thenAnswer((_) async => const Result.failure(TooManyRequests()));

      final container = makeContainer();
      container.read(verifyEmailProvider);

      await container.read(verifyEmailProvider.notifier).resendVerification();

      final value = container.read(verifyEmailProvider).requireValue;
      expect(value.isResending, isFalse);
      expect(value.error, isA<TooManyRequests>());
      // 실패 시 쿨다운을 시작하지 않으므로 즉시 재시도 가능하다.
      expect(value.cooldownRemaining, 0);
    });
  });
}
