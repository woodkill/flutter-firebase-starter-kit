import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';

import 'package:flutter_starter_kit/core/providers/firebase_providers.dart';
import 'package:flutter_starter_kit/core/router/app_routes.dart';
import 'package:flutter_starter_kit/core/router/auth_guard.dart';

class _MockGoRouterState extends Mock implements GoRouterState {}

class _MockUser extends Mock implements fb.User {}

class _MockFirebaseAuth extends Mock implements fb.FirebaseAuth {}

void main() {
  late _MockGoRouterState mockState;

  setUp(() {
    mockState = _MockGoRouterState();
  });

  /// 인증 상태를 미인증/인증으로 시뮬레이션하기 위해
  /// `firebaseAuthProvider`를 mock으로 override한 컨테이너를 만든다.
  ///
  /// [user]가 null이면 미인증, non-null이면 인증 상태를 흉내낸다.
  ProviderContainer makeContainer({
    required bool isInitialized,
    fb.User? user,
  }) {
    final mockAuth = _MockFirebaseAuth();
    when(() => mockAuth.currentUser).thenReturn(user);
    return ProviderContainer(
      overrides: [
        isFirebaseInitializedProvider.overrideWithValue(isInitialized),
        firebaseAuthProvider.overrideWithValue(mockAuth),
      ],
    );
  }

  group('authRedirect', () {
    /// authRedirect는 Ref를 첫 번째 파라미터로 받는다.
    /// ProviderContainer에서 Ref를 얻기 위해 임시 Provider 안에서 호출한다.
    FutureOr<String?> callAuthRedirect(
      ProviderContainer container,
      GoRouterState state,
    ) {
      late FutureOr<String?> result;
      final testProvider = Provider<Object?>((ref) {
        result = authRedirect(ref, state);
        return null;
      });
      container.read(testProvider);
      return result;
    }

    test('Firebase 미초기화 시 null을 반환한다', () async {
      final container = makeContainer(isInitialized: false);
      addTearDown(container.dispose);

      when(() => mockState.matchedLocation).thenReturn(AppRoutes.home);

      final result = await callAuthRedirect(container, mockState);
      expect(result, isNull);
    });

    test('미인증 + home 위치 시 /login을 반환한다', () async {
      final container = makeContainer(isInitialized: true);
      addTearDown(container.dispose);

      when(() => mockState.matchedLocation).thenReturn(AppRoutes.home);

      final result = await callAuthRedirect(container, mockState);
      expect(result, AppRoutes.login);
    });

    test('미인증 + login 위치 시 null을 반환한다', () async {
      final container = makeContainer(isInitialized: true);
      addTearDown(container.dispose);

      when(() => mockState.matchedLocation).thenReturn(AppRoutes.login);

      final result = await callAuthRedirect(container, mockState);
      expect(result, isNull);
    });

    test('인증 완료 + login 위치 시 /를 반환한다', () async {
      final mockUser = _MockUser();
      when(() => mockUser.uid).thenReturn('test-uid');
      when(() => mockUser.emailVerified).thenReturn(true);
      final container = makeContainer(isInitialized: true, user: mockUser);
      addTearDown(container.dispose);

      when(() => mockState.matchedLocation).thenReturn(AppRoutes.login);

      final result = await callAuthRedirect(container, mockState);
      expect(result, AppRoutes.home);
    });

    test('인증 완료 + home 위치 시 null을 반환한다', () async {
      final mockUser = _MockUser();
      when(() => mockUser.uid).thenReturn('test-uid');
      when(() => mockUser.emailVerified).thenReturn(true);
      final container = makeContainer(isInitialized: true, user: mockUser);
      addTearDown(container.dispose);

      when(() => mockState.matchedLocation).thenReturn(AppRoutes.home);

      final result = await callAuthRedirect(container, mockState);
      expect(result, isNull);
    });

    test('미인증 + /signup 위치 시 null을 반환한다', () async {
      final container = makeContainer(isInitialized: true);
      addTearDown(container.dispose);

      when(() => mockState.matchedLocation).thenReturn(AppRoutes.signup);

      final result = await callAuthRedirect(container, mockState);
      expect(result, isNull);
    });

    test('미인증 + /forgot-password 위치 시 null을 반환한다', () async {
      final container = makeContainer(isInitialized: true);
      addTearDown(container.dispose);

      when(() => mockState.matchedLocation)
          .thenReturn(AppRoutes.forgotPassword);

      final result = await callAuthRedirect(container, mockState);
      expect(result, isNull);
    });

    test('인증 완료 + /signup 위치 시 / 를 반환한다', () async {
      final mockUser = _MockUser();
      when(() => mockUser.uid).thenReturn('test-uid');
      when(() => mockUser.emailVerified).thenReturn(true);
      final container = makeContainer(isInitialized: true, user: mockUser);
      addTearDown(container.dispose);

      when(() => mockState.matchedLocation).thenReturn(AppRoutes.signup);

      final result = await callAuthRedirect(container, mockState);
      expect(result, AppRoutes.home);
    });

    test(
      '인증 완료 + /forgot-password 위치 시 / 를 반환한다 (T-06.07-01 회귀)',
      () async {
        // T-06.07-01 회귀 방지: authRedirect가 firebaseAuth.currentUser를
        // 직접 읽어 stream 구독 순서에 따른 stale value 문제를 회피한다.
        // 이 테스트는 authStateProvider override 없이도 인증 상태가
        // 정확히 인지되는지를 검증한다.
        final mockUser = _MockUser();
        when(() => mockUser.uid).thenReturn('test-uid');
        when(() => mockUser.emailVerified).thenReturn(true);
        final container = makeContainer(isInitialized: true, user: mockUser);
        addTearDown(container.dispose);

        when(() => mockState.matchedLocation)
            .thenReturn(AppRoutes.forgotPassword);

        final result = await callAuthRedirect(container, mockState);
        expect(result, AppRoutes.home);
      },
    );

    test(
      '인증 + emailVerified==false + /home 접근 시 /verify-email로 redirect',
      () async {
        final mockUser = _MockUser();
        when(() => mockUser.uid).thenReturn('test-uid');
        when(() => mockUser.emailVerified).thenReturn(false);
        final container = makeContainer(
          isInitialized: true,
          user: mockUser,
        );
        addTearDown(container.dispose);

        when(() => mockState.matchedLocation).thenReturn(AppRoutes.home);

        final result = await callAuthRedirect(container, mockState);
        expect(result, AppRoutes.verifyEmail);
      },
    );

    test(
      '인증 + emailVerified==false + /verify-email 접근 시 null (redirect 없음)',
      () async {
        final mockUser = _MockUser();
        when(() => mockUser.uid).thenReturn('test-uid');
        when(() => mockUser.emailVerified).thenReturn(false);
        final container = makeContainer(
          isInitialized: true,
          user: mockUser,
        );
        addTearDown(container.dispose);

        when(() => mockState.matchedLocation)
            .thenReturn(AppRoutes.verifyEmail);

        final result = await callAuthRedirect(container, mockState);
        expect(result, isNull);
      },
    );

    test(
      '인증 + emailVerified==true + /verify-email 접근 시 /home으로 redirect',
      () async {
        final mockUser = _MockUser();
        when(() => mockUser.uid).thenReturn('test-uid');
        when(() => mockUser.emailVerified).thenReturn(true);
        final container = makeContainer(
          isInitialized: true,
          user: mockUser,
        );
        addTearDown(container.dispose);

        when(() => mockState.matchedLocation)
            .thenReturn(AppRoutes.verifyEmail);

        final result = await callAuthRedirect(container, mockState);
        expect(result, AppRoutes.home);
      },
    );

    test(
      '인증 + emailVerified==false + /login 접근 시 /verify-email로 redirect',
      () async {
        // D-06 우선순위: (3)번 조건이 (4)번보다 먼저 평가된다.
        // 이미 로그인된 상태에서 /login에 올 이유가 없으므로
        // /verify-email로 보내는 것이 올바른 동작이다.
        final mockUser = _MockUser();
        when(() => mockUser.uid).thenReturn('test-uid');
        when(() => mockUser.emailVerified).thenReturn(false);
        final container = makeContainer(
          isInitialized: true,
          user: mockUser,
        );
        addTearDown(container.dispose);

        when(() => mockState.matchedLocation).thenReturn(AppRoutes.login);

        final result = await callAuthRedirect(container, mockState);
        expect(result, AppRoutes.verifyEmail);
      },
    );
  });
}
