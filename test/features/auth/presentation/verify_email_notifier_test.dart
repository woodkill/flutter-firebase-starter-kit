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
  });
}
