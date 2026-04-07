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

void main() {
  late _MockGoRouterState mockState;

  setUp(() {
    mockState = _MockGoRouterState();
  });

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
      final container = ProviderContainer(
        overrides: [
          isFirebaseInitializedProvider.overrideWithValue(false),
        ],
      );
      addTearDown(container.dispose);

      when(() => mockState.matchedLocation).thenReturn(AppRoutes.home);

      final result = await callAuthRedirect(container, mockState);
      expect(result, isNull);
    });

    test('미인증 + home 위치 시 /login을 반환한다', () async {
      // isFirebaseInitialized=true + authState는 AsyncLoading 상태
      // AsyncLoading.value == null -> 미인증으로 판단
      final container = ProviderContainer(
        overrides: [
          isFirebaseInitializedProvider.overrideWithValue(true),
          authStateProvider.overrideWith(
            (ref) => const Stream<fb.User?>.empty(),
          ),
        ],
      );
      addTearDown(container.dispose);

      when(() => mockState.matchedLocation).thenReturn(AppRoutes.home);

      final result = await callAuthRedirect(container, mockState);
      expect(result, AppRoutes.login);
    });

    test('미인증 + login 위치 시 null을 반환한다', () async {
      final container = ProviderContainer(
        overrides: [
          isFirebaseInitializedProvider.overrideWithValue(true),
          authStateProvider.overrideWith(
            (ref) => const Stream<fb.User?>.empty(),
          ),
        ],
      );
      addTearDown(container.dispose);

      when(() => mockState.matchedLocation).thenReturn(AppRoutes.login);

      final result = await callAuthRedirect(container, mockState);
      expect(result, isNull);
    });

    test('인증 완료 + login 위치 시 /를 반환한다', () async {
      final mockUser = _MockUser();

      final container = ProviderContainer(
        overrides: [
          isFirebaseInitializedProvider.overrideWithValue(true),
          authStateProvider.overrideWith(
            (ref) => Stream<fb.User?>.value(mockUser),
          ),
        ],
      );
      addTearDown(container.dispose);

      // StreamProvider listen 시작 후 AsyncData 전환까지 microtask 소비
      container.listen(authStateProvider, (_, _) {});
      // Stream.value는 listen -> microtask(emit) -> microtask(done) 순서
      // Riverpod이 state를 AsyncData로 전환하기까지 여러 microtask 필요
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      when(() => mockState.matchedLocation).thenReturn(AppRoutes.login);

      final result = await callAuthRedirect(container, mockState);
      expect(result, AppRoutes.home);
    });

    test('인증 완료 + home 위치 시 null을 반환한다', () async {
      final mockUser = _MockUser();

      final container = ProviderContainer(
        overrides: [
          isFirebaseInitializedProvider.overrideWithValue(true),
          authStateProvider.overrideWith(
            (ref) => Stream<fb.User?>.value(mockUser),
          ),
        ],
      );
      addTearDown(container.dispose);

      container.listen(authStateProvider, (_, _) {});
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      when(() => mockState.matchedLocation).thenReturn(AppRoutes.home);

      final result = await callAuthRedirect(container, mockState);
      expect(result, isNull);
    });

    test('미인증 + /signup 위치 시 null을 반환한다', () async {
      final container = ProviderContainer(
        overrides: [
          isFirebaseInitializedProvider.overrideWithValue(true),
          authStateProvider.overrideWith(
            (ref) => const Stream<fb.User?>.empty(),
          ),
        ],
      );
      addTearDown(container.dispose);

      when(() => mockState.matchedLocation).thenReturn(AppRoutes.signup);

      final result = await callAuthRedirect(container, mockState);
      expect(result, isNull);
    });

    test('미인증 + /forgot-password 위치 시 null을 반환한다', () async {
      final container = ProviderContainer(
        overrides: [
          isFirebaseInitializedProvider.overrideWithValue(true),
          authStateProvider.overrideWith(
            (ref) => const Stream<fb.User?>.empty(),
          ),
        ],
      );
      addTearDown(container.dispose);

      when(() => mockState.matchedLocation)
          .thenReturn(AppRoutes.forgotPassword);

      final result = await callAuthRedirect(container, mockState);
      expect(result, isNull);
    });

    test('인증 완료 + /signup 위치 시 / 를 반환한다', () async {
      final mockUser = _MockUser();

      final container = ProviderContainer(
        overrides: [
          isFirebaseInitializedProvider.overrideWithValue(true),
          authStateProvider.overrideWith(
            (ref) => Stream<fb.User?>.value(mockUser),
          ),
        ],
      );
      addTearDown(container.dispose);

      container.listen(authStateProvider, (_, _) {});
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      when(() => mockState.matchedLocation).thenReturn(AppRoutes.signup);

      final result = await callAuthRedirect(container, mockState);
      expect(result, AppRoutes.home);
    });
  });
}
