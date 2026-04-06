import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';

import 'package:flutter_starter_kit/core/providers/firebase_providers.dart';
import 'package:flutter_starter_kit/core/router/app_router.dart';

class _MockFirebaseAuth extends Mock implements FirebaseAuth {}

void main() {
  group('appRouterProvider', () {
    late ProviderContainer container;

    setUp(() {
      final mockAuth = _MockFirebaseAuth();
      when(() => mockAuth.authStateChanges())
          .thenAnswer((_) => const Stream<User?>.empty());

      container = ProviderContainer(
        overrides: [
          isFirebaseInitializedProvider.overrideWithValue(false),
          firebaseAuthProvider.overrideWithValue(mockAuth),
        ],
      );
    });

    tearDown(() => container.dispose());

    test('GoRouter 인스턴스를 반환한다', () {
      final router = container.read(appRouterProvider);
      expect(router, isA<GoRouter>());
    });

    test('keepAlive Provider이다', () {
      final sub = container.listen(appRouterProvider, (_, _) {});
      sub.close();

      // keepAlive이므로 subscription 해제 후에도 읽을 수 있다
      final router = container.read(appRouterProvider);
      expect(router, isA<GoRouter>());
    });
  });
}
