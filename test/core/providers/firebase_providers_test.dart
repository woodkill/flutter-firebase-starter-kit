import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:flutter_starter_kit/core/providers/firebase_providers.dart';

class _MockFirebaseAuth extends Mock implements FirebaseAuth {}

void main() {
  group('firebaseAuthProvider', () {
    test('FirebaseAuth 타입을 반환한다', () {
      final mockAuth = _MockFirebaseAuth();
      final container = ProviderContainer(
        overrides: [
          firebaseAuthProvider.overrideWithValue(mockAuth),
        ],
      );
      addTearDown(container.dispose);

      final auth = container.read(firebaseAuthProvider);

      expect(auth, isA<FirebaseAuth>());
      expect(auth, same(mockAuth));
    });

    test('keepAlive Provider이다 (autoDispose가 아니다)', () {
      final mockAuth = _MockFirebaseAuth();
      final container = ProviderContainer(
        overrides: [
          firebaseAuthProvider.overrideWithValue(mockAuth),
        ],
      );
      addTearDown(container.dispose);

      // keepAlive Provider는 ProviderSubscription을 닫아도 값이 유지된다.
      final sub = container.listen(firebaseAuthProvider, (_, _) {});
      sub.close();

      // autoDispose라면 subscription 해제 후 값이 사라지지만,
      // keepAlive이므로 여전히 읽을 수 있다.
      final auth = container.read(firebaseAuthProvider);
      expect(auth, isA<FirebaseAuth>());
    });
  });
}
