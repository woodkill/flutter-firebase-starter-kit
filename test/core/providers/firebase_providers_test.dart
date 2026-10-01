import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:flutter_starter_kit/core/providers/firebase_providers.dart';

class _MockFirebaseAuth extends Mock implements FirebaseAuth {}

class _MockFirebaseCrashlytics extends Mock implements FirebaseCrashlytics {}

class _MockFirebaseAnalytics extends Mock implements FirebaseAnalytics {}

class _MockFirebaseFirestore extends Mock implements FirebaseFirestore {}

void main() {
  group('isFirebaseInitializedProvider', () {
    test('기본값은 false이다', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final result = container.read(isFirebaseInitializedProvider);
      expect(result, isFalse);
    });

    test('overrideWithValue로 true를 주입할 수 있다', () {
      final container = ProviderContainer(
        overrides: [isFirebaseInitializedProvider.overrideWithValue(true)],
      );
      addTearDown(container.dispose);

      final result = container.read(isFirebaseInitializedProvider);
      expect(result, isTrue);
    });
  });

  group('authStateProvider', () {
    test('Firebase 미초기화 시 AsyncValue 타입을 반환한다', () {
      final container = ProviderContainer(
        overrides: [isFirebaseInitializedProvider.overrideWithValue(false)],
      );
      addTearDown(container.dispose);

      // Stream.empty()이므로 초기 상태는 AsyncLoading이다
      final result = container.read(authStateProvider);
      expect(result, isA<AsyncValue<User?>>());
    });
  });

  group('firebaseAuthProvider', () {
    test('FirebaseAuth 타입을 반환한다', () {
      final mockAuth = _MockFirebaseAuth();
      final container = ProviderContainer(
        overrides: [firebaseAuthProvider.overrideWithValue(mockAuth)],
      );
      addTearDown(container.dispose);

      final auth = container.read(firebaseAuthProvider);

      expect(auth, isA<FirebaseAuth>());
      expect(auth, same(mockAuth));
    });

    test('keepAlive Provider이다 (autoDispose가 아니다)', () {
      final mockAuth = _MockFirebaseAuth();
      final container = ProviderContainer(
        overrides: [firebaseAuthProvider.overrideWithValue(mockAuth)],
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

  group('firebaseCrashlyticsProvider (Phase 10 D-28)', () {
    test('override로 fake 주입이 가능하다', () {
      final fake = _MockFirebaseCrashlytics();
      final container = ProviderContainer(
        overrides: [firebaseCrashlyticsProvider.overrideWithValue(fake)],
      );
      addTearDown(container.dispose);

      final crashlytics = container.read(firebaseCrashlyticsProvider);

      expect(crashlytics, isA<FirebaseCrashlytics>());
      expect(crashlytics, same(fake));
    });

    test('keepAlive Provider이다 (subscription 해제 후에도 값 유지)', () {
      final fake = _MockFirebaseCrashlytics();
      final container = ProviderContainer(
        overrides: [firebaseCrashlyticsProvider.overrideWithValue(fake)],
      );
      addTearDown(container.dispose);

      final sub = container.listen(firebaseCrashlyticsProvider, (_, _) {});
      sub.close();

      final crashlytics = container.read(firebaseCrashlyticsProvider);
      expect(crashlytics, isA<FirebaseCrashlytics>());
    });
  });

  group('firebaseAnalyticsProvider (Phase 10 D-29)', () {
    test('override로 fake 주입이 가능하다', () {
      final fake = _MockFirebaseAnalytics();
      final container = ProviderContainer(
        overrides: [firebaseAnalyticsProvider.overrideWithValue(fake)],
      );
      addTearDown(container.dispose);

      final analytics = container.read(firebaseAnalyticsProvider);

      expect(analytics, isA<FirebaseAnalytics>());
      expect(analytics, same(fake));
    });
  });

  group('firebaseFirestoreProvider (Phase 10 D-16)', () {
    test('override로 fake 주입이 가능하다', () {
      final fake = _MockFirebaseFirestore();
      final container = ProviderContainer(
        overrides: [firebaseFirestoreProvider.overrideWithValue(fake)],
      );
      addTearDown(container.dispose);

      final firestore = container.read(firebaseFirestoreProvider);

      expect(firestore, isA<FirebaseFirestore>());
      expect(firestore, same(fake));
    });
  });

  group('Phase 1 D-13 가드 (코드 리뷰 CR-02)', () {
    // 네이티브 인스턴스 provider 6종은 모두 `Xxx.instance` 를 반환하며 그
    // 접근은 Firebase 미초기화 시 `[core/no-app]` 으로 throw 한다.
    // _assertFirebaseReady 가 debug 빌드에서 그 계약 위반을 "원인이 적힌
    // 실패" 로 앞당긴다 — 조용한 [core/no-app] 대신 어느 provider 를 어떻게
    // 가드해야 하는지가 메시지에 담긴다.
    //
    // 본 테스트는 override 없이 provider 를 읽는다. 수정 전에는 여기서
    // FirebaseException([core/no-app]) 이 났고, 수정 후에는 AssertionError 다.
    // 어느 쪽이든 throw 이므로 "release 계약이 바뀌지 않는다" 는 성질도 함께
    // 확인되며, 검증 대상은 **메시지에 가드 방법이 담겨 있는지** 다.
    // 생성된 provider 는 각각 고유 타입이라 공통 상위 타입으로 묶을 수 없다.
    // 이름 + 읽기 클로저 쌍으로 테이블을 만든다.
    final guardedProviders = <String, Object Function(ProviderContainer)>{
      'firebaseAuthProvider': (c) => c.read(firebaseAuthProvider),
      'firebaseCrashlyticsProvider': (c) => c.read(firebaseCrashlyticsProvider),
      'firebaseAnalyticsProvider': (c) => c.read(firebaseAnalyticsProvider),
      'firebaseFirestoreProvider': (c) => c.read(firebaseFirestoreProvider),
      'firebaseRemoteConfigProvider': (c) =>
          c.read(firebaseRemoteConfigProvider),
      'firebaseFunctionsProvider': (c) => c.read(firebaseFunctionsProvider),
    };

    guardedProviders.forEach((name, readProvider) {
      test('$name 은 Firebase 미초기화 상태에서 읽으면 D-13 위반으로 실패한다', () {
        final container = ProviderContainer(
          overrides: [isFirebaseInitializedProvider.overrideWithValue(false)],
        );
        addTearDown(container.dispose);

        // Riverpod 3.x 는 provider build 예외를 ProviderException 으로 감싸고
        // 원본 메시지를 toString() 에 그대로 실어 보낸다 (ProviderException
        // 은 public export 가 아니므로 타입 대신 메시지로 검증한다).
        // 'Failed assertion' 은 실패 주체가 _assertFirebaseReady 임을 못박는다
        // — 가드가 사라지면 [core/no-app] FirebaseException 이 되어 깨진다.
        expect(
          () => readProvider(container),
          throwsA(
            isA<Object>().having(
              (e) => e.toString(),
              'toString()',
              allOf(
                contains('Failed assertion'),
                contains(name),
                contains('D-13'),
                contains('isFirebaseInitializedProvider'),
              ),
            ),
          ),
          reason: 'CR-02: $name 무가드 접근이 원인 없는 실패로 새어 나가면 안 된다',
        );
      });
    });

    test('override 주입 시에는 가드가 평가되지 않는다 (테스트/대체 구현 경로 보존)', () {
      // provider body 가 실행되지 않으므로 미초기화 상태에서도 mock 을
      // 그대로 읽을 수 있어야 한다 — 기존 테스트 harness 전부가 이 성질에
      // 의존한다.
      final mockAuth = _MockFirebaseAuth();
      final container = ProviderContainer(
        overrides: [
          isFirebaseInitializedProvider.overrideWithValue(false),
          firebaseAuthProvider.overrideWithValue(mockAuth),
        ],
      );
      addTearDown(container.dispose);

      expect(container.read(firebaseAuthProvider), same(mockAuth));
    });
  });

  group('Phase 17 인스턴스 provider (T-17-PROVIDER)', () {
    // Phase 17 — see ROADMAP.md (D-01 · D-15). 새 인스턴스 provider 2종도
    // 기존 6종과 같은 Phase 1 D-13 가드(_assertFirebaseReady)를 거친다.
    // 검증 방식은 위 CR-02 그룹과 같다 — 미초기화 컨테이너에서 override 없이
    // 읽으면 원인(provider 이름 · D-13 · 가드 방법)이 적힌 assertion 실패다.
    Matcher guardFailureFor(String name) => throwsA(
      isA<Object>().having(
        (e) => e.toString(),
        'toString()',
        allOf(
          contains('Failed assertion'),
          contains(name),
          contains('D-13'),
          contains('isFirebaseInitializedProvider'),
        ),
      ),
    );

    test(
      'T-17-PROVIDER-01 firebaseMessagingProvider 는 미초기화 상태에서 D-13 가드로 실패한다',
      () {
        final container = ProviderContainer(
          overrides: [isFirebaseInitializedProvider.overrideWithValue(false)],
        );
        addTearDown(container.dispose);

        expect(
          () => container.read(firebaseMessagingProvider),
          guardFailureFor('firebaseMessagingProvider'),
        );
      },
    );

    test(
      'T-17-PROVIDER-02 firebaseStorageProvider 는 미초기화 상태에서 D-13 가드로 실패한다',
      () {
        final container = ProviderContainer(
          overrides: [isFirebaseInitializedProvider.overrideWithValue(false)],
        );
        addTearDown(container.dispose);

        expect(
          () => container.read(firebaseStorageProvider),
          guardFailureFor('firebaseStorageProvider'),
        );
      },
    );
  });
}
