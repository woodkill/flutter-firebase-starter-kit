// ignore_for_file: subtype_of_sealed_class
//
// 본 테스트는 cloud_firestore 의 일부 sealed class (Query / DocumentReference /
// DocumentSnapshot) 를 mock 으로 implements 한다. fake_cloud_firestore 패키지
// 가 dev_dependencies 에 부재하므로 mocktail 직접 mock 채택. 본 ignore 는
// 테스트 파일 한정 — 프로덕션 코드는 sealed class 우회 금지 정책 유지.
import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:flutter_starter_kit/core/providers/firebase_providers.dart';
import 'package:flutter_starter_kit/features/auth/data/auth_repository.dart';

/// Phase 12 Plan 06 — currentUserProvider 합집합 회귀 테스트.
///
/// 검증 대상 (D-15 / D-16):
/// 1. Firebase user==null → currentUserProvider==null (기존 동작 보존)
/// 2. Firebase providerData(['google.com']) + Firestore linkedProviders
///    ([{kakao}, {google.com}]) → User.providerIds 가 합집합 + 중복 제거
/// 3. Firestore 문서 미존재 → Firebase providerData 만 사용 (Plan 10-09 패턴)
/// 4. Firestore stream 에러 → Firebase providerData 만 사용 (fallback)
/// 5. linkedProviders 필드 부재 → Firebase providerData 만 사용
/// 6. linkedProviders 가 잘못된 schema → type-safe filter 가 차단
///
/// Phase 16.7 — [UserProviderRecord] 의 두 필드가 같은 snapshot 에서 함께
/// 파싱되고 loading 에서 함께 보존된다 (D-11 · assumption-delta 불변식):
/// 7. linkedProviders=[{kakao}] + signUpProviderId='kakao' → User 에 실림 ·
///    providerIds 합집합 불변
/// 8. signUpProviderId 가 String 아닌 타입(42) → null (추론 0)
/// 9. linkedProviders 부재 + signUpProviderId='password' → providerIds =
///    providerData 만 · signUpProviderId 보존 (부재 fallback 이 버리지 않음)
/// 10. 첫 emit 뒤 재구독 중 AsyncLoading → 직전 cached record 의
///     signUpProviderId 유지

class _MockFbUser extends Mock implements fb.User {}

class _MockUserMetadata extends Mock implements fb.UserMetadata {}

class _MockUserInfo extends Mock implements fb.UserInfo {}

class _MockFirebaseFirestore extends Mock implements FirebaseFirestore {}

class _MockCollectionReference extends Mock
    implements CollectionReference<Map<String, dynamic>> {}

class _MockDocumentReference extends Mock
    implements DocumentReference<Map<String, dynamic>> {}

class _MockDocumentSnapshot extends Mock
    implements DocumentSnapshot<Map<String, dynamic>> {}

/// 단일 케이스 헬퍼 — Stream provider 들의 emit 까지 microtask 를 풀어준다.
///
/// authStateProvider 는 `Stream<fb.User?>` 를 watch 하고
/// linkedProvidersStreamProvider 는 Firestore snapshots stream 을 watch
/// 한다. 모두 첫 emit 까지 microtask 를 소비하므로 충분히 기다린다.
Future<void> _settle() async {
  for (var i = 0; i < 5; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

/// [currentUserProvider] 를 활성화한 [ProviderContainer] 를 만든다.
///
/// `keepAlive: true` 라도 listener 가 없으면 lazy 평가만 일어나 Stream 이
/// 구독되지 않을 수 있다. listener 를 명시적으로 등록하여 stream subscription
/// 을 기동한다.
ProviderContainer _makeContainer({required List<Object> overrides}) {
  // ignore: argument_type_not_assignable — flutter_riverpod 의 Override 타입은
  // 외부 노출 미지원이라 List<Object> 로 받고 ProviderContainer 가 sub-type
  // 동적 캐스팅한다. 호출부는 모두 *.overrideWith / *.overrideWithValue 의
  // 결과만 전달하므로 안전.
  final container = ProviderContainer(overrides: overrides.cast());
  // currentUserProvider listener — Stream subscription 활성화 + 안정화.
  container.listen(currentUserProvider, (_, _) {}, fireImmediately: true);
  return container;
}

/// `userChanges` 가 emit 할 [fb.User] mock 을 생성한다.
///
/// mocktail 의 `when().thenReturn()` 은 nested when 을 허용하지 않으므로
/// providerData 의 [_MockUserInfo] 인스턴스는 미리 생성하여 thenReturn 에
/// 전달한다.
_MockFbUser _buildFbUser({
  required String uid,
  required List<String> providerIds,
  String? displayName = 'Test User',
  String? photoUrl,
}) {
  final fbUser = _MockFbUser();
  final metadata = _MockUserMetadata();
  // providerData 인스턴스 사전 생성 — nested when 회피.
  final infos = <_MockUserInfo>[];
  for (final id in providerIds) {
    final info = _MockUserInfo();
    when(() => info.providerId).thenReturn(id);
    infos.add(info);
  }
  when(() => fbUser.uid).thenReturn(uid);
  when(() => fbUser.email).thenReturn('user@example.com');
  when(() => fbUser.emailVerified).thenReturn(true);
  when(() => fbUser.displayName).thenReturn(displayName);
  when(() => fbUser.photoURL).thenReturn(photoUrl);
  when(() => fbUser.metadata).thenReturn(metadata);
  when(() => metadata.creationTime).thenReturn(DateTime.utc(2026, 1, 1));
  when(() => fbUser.providerData).thenReturn(infos);
  return fbUser;
}

/// Firestore stub: `users/{uid}` snapshots stream 을 [snapshots] 로 emit 한다.
///
/// [shouldError] true 면 stream 이 즉시 [errorCode] 의 [FirebaseException] 을
/// emit 한다 (D-41 fallback 검증용). default 는 `'unavailable'` —
/// R10-FOLLOWUP-2 fix 후 `'permission-denied'` 는 retry 진입 (yield 안 함)
/// 이므로 D-41 즉시 fallback contract 검증용으로 적합하지 않다. 다른
/// FirebaseException 코드 (`unavailable`/`internal` 등) 는 즉시 빈 배열
/// fallback (I1) — 본 default 가 그 contract 를 검증한다.
_MockFirebaseFirestore _buildFirestore({
  required String uid,
  Stream<_MockDocumentSnapshot>? snapshots,
  bool shouldError = false,
  String errorCode = 'unavailable',
}) {
  final firestore = _MockFirebaseFirestore();
  final collection = _MockCollectionReference();
  final doc = _MockDocumentReference();

  when(() => firestore.collection('users')).thenReturn(collection);
  when(() => collection.doc(uid)).thenReturn(doc);
  if (shouldError) {
    when(() => doc.snapshots()).thenAnswer(
      (_) => Stream<_MockDocumentSnapshot>.error(
        FirebaseException(plugin: 'cloud_firestore', code: errorCode),
      ),
    );
  } else {
    when(() => doc.snapshots()).thenAnswer(
      (_) => snapshots ?? const Stream<_MockDocumentSnapshot>.empty(),
    );
  }
  return firestore;
}

/// Firestore stub for retry 시나리오 — 호출마다 다른 [Stream] 을 emit 한다.
///
/// `linkedProvidersStream` 의 R10-FOLLOWUP-2 fix 가 `permission-denied`
/// 발생 시 `await Future.delayed(1s) + continue` 로 source stream 을
/// 재구독하므로 `doc.snapshots()` 가 여러 번 호출된다. 호출 카운트별로
/// [streamFactories] 의 다른 factory 를 사용하여 (1차 throw → 2차 정상
/// 같은) 시나리오를 표현한다.
///
/// 각 factory 는 호출마다 새 [Stream] 을 반환해야 한다 — Stream subscription
/// 1회 제약 (single-subscription) 회피.
_MockFirebaseFirestore _buildRetryFirestore({
  required String uid,
  required List<Stream<_MockDocumentSnapshot> Function()> streamFactories,
}) {
  final firestore = _MockFirebaseFirestore();
  final collection = _MockCollectionReference();
  final doc = _MockDocumentReference();
  when(() => firestore.collection('users')).thenReturn(collection);
  when(() => collection.doc(uid)).thenReturn(doc);
  var callIndex = 0;
  when(() => doc.snapshots()).thenAnswer((_) {
    final clamped = callIndex.clamp(0, streamFactories.length - 1);
    final factory = streamFactories[clamped];
    callIndex += 1;
    return factory();
  });
  return firestore;
}

/// `permission-denied` 에러를 emit 하는 stream factory.
Stream<_MockDocumentSnapshot> Function() _permissionDeniedFactory() =>
    () => Stream<_MockDocumentSnapshot>.error(
      FirebaseException(plugin: 'cloud_firestore', code: 'permission-denied'),
    );

/// 정상 emit 을 내는 stream factory — 단일 [_MockDocumentSnapshot] value.
Stream<_MockDocumentSnapshot> Function() _valueFactory(
  _MockDocumentSnapshot snap,
) =>
    () => Stream<_MockDocumentSnapshot>.value(snap);

/// 한 개의 [DocumentSnapshot] mock — `linkedProviders` 데이터를 담는다.
_MockDocumentSnapshot _buildSnapshot({
  required bool exists,
  Map<String, dynamic>? data,
}) {
  final snap = _MockDocumentSnapshot();
  when(() => snap.exists).thenReturn(exists);
  when(() => snap.data()).thenReturn(data);
  return snap;
}

void main() {
  setUpAll(() {
    registerFallbackValue(<String, dynamic>{});
  });

  group('Phase 12: currentUserProvider 합집합 (D-16)', () {
    test('1. Firebase user==null → currentUserProvider 가 null 반환', () async {
      final container = _makeContainer(
        overrides: [
          authStateProvider.overrideWith((ref) => Stream<fb.User?>.value(null)),
          firebaseFirestoreProvider.overrideWithValue(_MockFirebaseFirestore()),
        ],
      );
      addTearDown(container.dispose);

      await _settle();
      expect(container.read(currentUserProvider), isNull);
    });

    test('2. Firebase providerData=[google.com] + Firestore linkedProviders='
        '[{kakao}, {google.com}] → providerIds 합집합 + 중복 제거', () async {
      const uid = 'uid-merge';
      final fbUser = _buildFbUser(uid: uid, providerIds: ['google.com']);
      final snap = _buildSnapshot(
        exists: true,
        data: <String, dynamic>{
          'linkedProviders': <Map<String, dynamic>>[
            {'providerId': 'kakao', 'providerUserId': '12345'},
            {'providerId': 'google.com', 'providerUserId': 'gid'},
          ],
        },
      );
      final firestore = _buildFirestore(
        uid: uid,
        snapshots: Stream<_MockDocumentSnapshot>.value(snap),
      );

      final container = _makeContainer(
        overrides: [
          authStateProvider.overrideWith(
            (ref) => Stream<fb.User?>.value(fbUser),
          ),
          firebaseFirestoreProvider.overrideWithValue(firestore),
        ],
      );
      addTearDown(container.dispose);

      await _settle();
      final user = container.read(currentUserProvider);
      expect(user, isNotNull);
      // 합집합: google.com (Firebase) ∪ {kakao, google.com} (Firestore)
      // → {google.com, kakao} (Set 기반 중복 제거).
      expect(user!.providerIds.toSet(), {'google.com', 'kakao'});
      expect(user.providerIds.length, 2, reason: '중복 제거 검증');
    });

    test(
      '3. Firestore 문서 미존재 (exists=false) → Firebase providerData 만 사용',
      () async {
        const uid = 'uid-no-doc';
        final fbUser = _buildFbUser(uid: uid, providerIds: ['google.com']);
        final snap = _buildSnapshot(exists: false);
        final firestore = _buildFirestore(
          uid: uid,
          snapshots: Stream<_MockDocumentSnapshot>.value(snap),
        );

        final container = _makeContainer(
          overrides: [
            authStateProvider.overrideWith(
              (ref) => Stream<fb.User?>.value(fbUser),
            ),
            firebaseFirestoreProvider.overrideWithValue(firestore),
          ],
        );
        addTearDown(container.dispose);

        await _settle();
        final user = container.read(currentUserProvider);
        expect(user, isNotNull);
        expect(user!.providerIds, ['google.com']);
      },
    );

    test('4. Firestore stream 에러 (unavailable) → AsyncData(<String>[]) emit '
        '(D-41 fallback empty, R6 + R10-FOLLOWUP-2 I1)', () async {
      const uid = 'uid-error';
      final fbUser = _buildFbUser(uid: uid, providerIds: ['google.com']);
      // R10-FOLLOWUP-2 후, `permission-denied` 는 1s × 5회 retry 진입.
      // D-41 (영구 spinner 회피) 정책은 다른 FirebaseException (network /
      // unavailable 등) 에서 검증한다 — `unavailable` 코드 사용.
      final firestore = _buildFirestore(uid: uid, shouldError: true);

      final container = _makeContainer(
        overrides: [
          authStateProvider.overrideWith(
            (ref) => Stream<fb.User?>.value(fbUser),
          ),
          firebaseFirestoreProvider.overrideWithValue(firestore),
        ],
      );
      addTearDown(container.dispose);

      await _settle();

      // 신규 contract (R6 D-41 + R10-FOLLOWUP-2 I1): 직접 stream 소비 시
      // AsyncData([]) 정착. 직접 stream consumer (Account 섹션, debug
      // widget) 가 spinner 무한 회피.
      final asyncValue = container.read(linkedProvidersStreamProvider(uid));
      expect(asyncValue.hasValue, isTrue);
      expect(asyncValue.value?.linkedProviderIds, isEmpty);

      // 합집합 결과는 동일 — Firebase providerData 만 사용
      // (currentUserProvider 의 linkedAsync.when data 분기로 자연 흐름).
      final user = container.read(currentUserProvider);
      expect(user, isNotNull);
      expect(user!.providerIds, ['google.com']);
    });

    test(
      '5. linkedProviders 필드 없음 (다른 필드만) → Firebase providerData 만 사용',
      () async {
        const uid = 'uid-no-linked';
        final fbUser = _buildFbUser(uid: uid, providerIds: ['apple.com']);
        final snap = _buildSnapshot(
          exists: true,
          data: <String, dynamic>{'termsAccepted': true},
        );
        final firestore = _buildFirestore(
          uid: uid,
          snapshots: Stream<_MockDocumentSnapshot>.value(snap),
        );

        final container = _makeContainer(
          overrides: [
            authStateProvider.overrideWith(
              (ref) => Stream<fb.User?>.value(fbUser),
            ),
            firebaseFirestoreProvider.overrideWithValue(firestore),
          ],
        );
        addTearDown(container.dispose);

        await _settle();
        final user = container.read(currentUserProvider);
        expect(user, isNotNull);
        expect(user!.providerIds, ['apple.com']);
      },
    );

    test('6. 잘못된 schema (linkedProviders 가 List<String>) → whereType 가 필터 — '
        '빈 배열 처리 (T-12-06-05 type-safe parsing)', () async {
      const uid = 'uid-bad-schema';
      final fbUser = _buildFbUser(uid: uid, providerIds: ['google.com']);
      // manual 변조: List<String> 형식 (객체 schema 아님). whereType<Map> 가
      // invalid entry 를 자동 제거 → 빈 배열 → Firebase providerData 만 사용.
      final snap = _buildSnapshot(
        exists: true,
        data: <String, dynamic>{
          'linkedProviders': <dynamic>['kakao', 'google.com'],
        },
      );
      final firestore = _buildFirestore(
        uid: uid,
        snapshots: Stream<_MockDocumentSnapshot>.value(snap),
      );

      final container = _makeContainer(
        overrides: [
          authStateProvider.overrideWith(
            (ref) => Stream<fb.User?>.value(fbUser),
          ),
          firebaseFirestoreProvider.overrideWithValue(firestore),
        ],
      );
      addTearDown(container.dispose);

      await _settle();
      final user = container.read(currentUserProvider);
      expect(user, isNotNull);
      // invalid schema 는 type-safe filter 가 차단 → fallback.
      expect(user!.providerIds, ['google.com']);
    });
  });

  // Phase 13 R13 (WR-06) fix 적용 후 invariant — 옵션 A (AsyncLoading 분기
  // 보존, explicit pattern matching) 회귀 가드.
  //
  // 신규 contract (auth_repository.dart::currentUser):
  //
  //   final rec = recAsync.when(
  //     data: (r) => r,
  //     loading: () => recAsync.value ?? _emptyUserProviderRecord,
  //     error: (_, _) => _emptyUserProviderRecord,
  //   );
  //
  // (Phase 16.7: List → UserProviderRecord 로 확장 — 분기 규칙은 동일.)
  //
  // 폐기된 invariant: "AsyncLoading 첫 frame 시 base.providerIds 유지"
  // (기존 maybeWhen orElse: empty 의 의도적 deferred 동작) — Phase 13
  // 시나리오 3/4 의 ephemeral '-' UX 회귀 trigger.
  //
  // 신규 invariant:
  // 1. AsyncLoading + cached value 없음 → 빈 배열 fallback (첫 진입은 동일)
  // 2. AsyncLoading + 직전 cached emit 보존 → cached list 합산 (R13 핵심 fix)
  // 3. AsyncError → 빈 배열 fallback (영구 spinner 회피, 옵션 A 단점 대응)
  group('Phase 13 R13 (WR-06) fix: linkedAsync.when 3-way explicit branch', () {
    test(
      '1. AsyncLoading 첫 진입 (cached value 없음) → base.providerIds 만 사용',
      () async {
        const uid = 'uid-async-loading-first';
        final fbUser = _buildFbUser(uid: uid, providerIds: <String>[]);
        // 절대 emit 안 하는 stream — AsyncLoading 영구 유지.
        final firestore = _buildFirestore(
          uid: uid,
          snapshots: const Stream<_MockDocumentSnapshot>.empty(),
        );

        final container = _makeContainer(
          overrides: [
            authStateProvider.overrideWith(
              (ref) => Stream<fb.User?>.value(fbUser),
            ),
            firebaseFirestoreProvider.overrideWithValue(firestore),
          ],
        );
        addTearDown(container.dispose);

        await _settle();

        // 첫 진입은 cached value 없음 → linked=[] → base 만 사용 → 빈 배열.
        final user = container.read(currentUserProvider);
        expect(user, isNotNull);
        expect(user!.uid, uid);
        expect(user.providerIds, isEmpty);
      },
    );

    test(
      '2. AsyncLoading + 직전 cached emit 보존 → cached list 합산 (R13 핵심)',
      () async {
        const uid = 'uid-async-loading-cached';
        final fbUser = _buildFbUser(uid: uid, providerIds: <String>[]);
        // 1차 emit 으로 [{naver}] 정착. AsyncValue 의 hasValue=true 보존.
        final snap = _buildSnapshot(
          exists: true,
          data: <String, dynamic>{
            'linkedProviders': <Map<String, dynamic>>[
              {'providerId': 'naver', 'providerUserId': '67890'},
            ],
          },
        );
        final firestore = _buildFirestore(
          uid: uid,
          snapshots: Stream<_MockDocumentSnapshot>.value(snap),
        );

        final container = _makeContainer(
          overrides: [
            authStateProvider.overrideWith(
              (ref) => Stream<fb.User?>.value(fbUser),
            ),
            firebaseFirestoreProvider.overrideWithValue(firestore),
          ],
        );
        addTearDown(container.dispose);

        await _settle();

        // R13 핵심 invariant: 1차 emit 도착 후 linkedAsync.value=['naver']
        // 가 보존되어 user.providerIds 에 'naver' 포함.
        final user = container.read(currentUserProvider);
        expect(user, isNotNull);
        expect(user!.providerIds.toSet(), {'naver'});
      },
    );

    test('3. AsyncError 직접 도달 → base.providerIds 만 (영구 spinner 회피)', () async {
      // 본 케이스는 handleError 가 우회된 가상 시나리오 — production
      // path 는 transform handleError 가 AsyncData([]) 정착시킴.
      // 옵션 A 단점 (AsyncError fallback 시 영구 spinner 위험) 회피
      // path 안전망 검증.
      const uid = 'uid-async-error';
      final fbUser = _buildFbUser(uid: uid, providerIds: ['google.com']);

      final container = ProviderContainer(
        overrides: [
          authStateProvider.overrideWith(
            (ref) => Stream<fb.User?>.value(fbUser),
          ),
          firebaseFirestoreProvider.overrideWithValue(_MockFirebaseFirestore()),
          // linkedProvidersStreamProvider 직접 override — AsyncError 강제.
          linkedProvidersStreamProvider(uid).overrideWith(
            (ref) => Stream<UserProviderRecord>.error(
              StateError('forced error for R13 fallback test'),
            ),
          ),
        ],
      );
      container.listen(currentUserProvider, (_, _) {}, fireImmediately: true);
      addTearDown(container.dispose);

      await _settle();

      // 영구 spinner 회피 invariant: currentUserProvider 가 즉시 valid
      // User 반환 (null / throw 아님), providerIds 는 base 만.
      final user = container.read(currentUserProvider);
      expect(user, isNotNull);
      expect(user!.uid, uid);
      expect(user.providerIds, ['google.com']);
    });
  });

  group('Phase 12: linkedProvidersStreamProvider (직접 호출)', () {
    test(
      'Firestore linkedProviders=[{kakao}, {naver}] → providerId 만 추출',
      () async {
        const uid = 'uid-direct';
        final snap = _buildSnapshot(
          exists: true,
          data: <String, dynamic>{
            'linkedProviders': <Map<String, dynamic>>[
              {'providerId': 'kakao', 'providerUserId': '12345'},
              {'providerId': 'naver', 'providerUserId': '67890'},
            ],
          },
        );
        final firestore = _buildFirestore(
          uid: uid,
          snapshots: Stream<_MockDocumentSnapshot>.value(snap),
        );

        final container = ProviderContainer(
          overrides: [firebaseFirestoreProvider.overrideWithValue(firestore)],
        );
        addTearDown(container.dispose);
        // Stream subscription 활성화.
        container.listen(
          linkedProvidersStreamProvider(uid),
          (_, _) {},
          fireImmediately: true,
        );

        // Stream provider 의 첫 emit 까지 대기 — AsyncValue<List<String>>.
        await _settle();
        final asyncValue = container.read(linkedProvidersStreamProvider(uid));
        expect(asyncValue.value?.linkedProviderIds, ['kakao', 'naver']);
      },
    );
  });

  // Phase 13 R10-FOLLOWUP-2 fix 회귀 가드.
  //
  // sign-in 직후 Firebase Auth ID Token 갱신과 Firestore SDK 의 token cache
  // propagate 사이 timing window 에서 발생하는 `[cloud_firestore/permission-
  // denied]` race 를 stream 내부 selective retry 로 흡수하는 contract 검증.
  //
  // 검증 invariants (auth_repository.dart::linkedProvidersStream, spec §4.6):
  // - I1 (D-41): 다른 FirebaseException → 즉시 빈 배열 / 5회 escape → 빈 배열
  // - I2 (R13 호환): retry 중 yield 안 함 (현 케이스 group 은 stream 직접
  //   AsyncValue 검증 — yield 안 함은 AsyncLoading 잔류로 표현)
  // - I3 (카운터 리셋): 정상 emit 도달 시 retry 카운터 0
  //
  // fakeAsync 호환성 — ProviderContainer microtask 와 mocktail thenAnswer
  // 카운팅이 fake zone 안에서 함께 실행되어야 한다. wallclock 채택 (spec §5
  // 의 fakeAsync 는 권장이지 의무 아님).
  group(
    'Phase 13 R10-FOLLOWUP-2: linkedProvidersStream permission-denied retry',
    () {
      test('1. 정상 emit (회귀) — Firestore mock [{providerId: naver}] → '
          'AsyncData([naver])', () async {
        const uid = 'uid-r10f2-normal';
        final snap = _buildSnapshot(
          exists: true,
          data: <String, dynamic>{
            'linkedProviders': <Map<String, dynamic>>[
              {'providerId': 'naver', 'providerUserId': 'nv1'},
            ],
          },
        );
        final firestore = _buildFirestore(
          uid: uid,
          snapshots: Stream<_MockDocumentSnapshot>.value(snap),
        );

        final container = ProviderContainer(
          overrides: [firebaseFirestoreProvider.overrideWithValue(firestore)],
        );
        addTearDown(container.dispose);
        container.listen(
          linkedProvidersStreamProvider(uid),
          (_, _) {},
          fireImmediately: true,
        );

        await _settle();
        final asyncValue = container.read(linkedProvidersStreamProvider(uid));
        expect(asyncValue.hasValue, isTrue);
        expect(asyncValue.value?.linkedProviderIds, ['naver']);
      });

      test('2. permission-denied 1회 후 정상 (R10-FOLLOWUP-2 핵심) — 1s delay 후 '
          'AsyncData([naver])', () async {
        const uid = 'uid-r10f2-retry-once';
        final snap = _buildSnapshot(
          exists: true,
          data: <String, dynamic>{
            'linkedProviders': <Map<String, dynamic>>[
              {'providerId': 'naver', 'providerUserId': 'nv1'},
            ],
          },
        );
        // 1차 throw permission-denied → retry 진입 (yield 안 함) → 2차 정상.
        final firestore = _buildRetryFirestore(
          uid: uid,
          streamFactories: [_permissionDeniedFactory(), _valueFactory(snap)],
        );

        final container = ProviderContainer(
          overrides: [firebaseFirestoreProvider.overrideWithValue(firestore)],
        );
        addTearDown(container.dispose);
        container.listen(
          linkedProvidersStreamProvider(uid),
          (_, _) {},
          fireImmediately: true,
        );

        // 1차 throw 시점에 yield 안 함 → AsyncLoading 잔류 (I2).
        await _settle();
        final pendingValue = container.read(linkedProvidersStreamProvider(uid));
        expect(
          pendingValue.isLoading,
          isTrue,
          reason: 'retry 중 yield 안 함 → AsyncLoading 잔류 (I2 invariant)',
        );

        // 1s wallclock + microtask flush — retryDelay 후 2차 정상 emit.
        await Future<void>.delayed(const Duration(milliseconds: 1100));
        await _settle();
        final asyncValue = container.read(linkedProvidersStreamProvider(uid));
        expect(asyncValue.hasValue, isTrue);
        expect(asyncValue.value?.linkedProviderIds, [
          'naver',
        ], reason: 'retry 후 정상 emit 도달 (R10-FOLLOWUP-2 핵심)');
      }, timeout: const Timeout(Duration(seconds: 10)));

      test('3. permission-denied 5회 escape — 5s 후 AsyncData([]) (D-41 escape '
          'hatch, I1)', () async {
        const uid = 'uid-r10f2-escape';
        // 6 호출 모두 permission-denied — 5회 retry 후 escape hatch.
        final firestore = _buildRetryFirestore(
          uid: uid,
          streamFactories: List.generate(6, (_) => _permissionDeniedFactory()),
        );

        final container = ProviderContainer(
          overrides: [firebaseFirestoreProvider.overrideWithValue(firestore)],
        );
        addTearDown(container.dispose);
        container.listen(
          linkedProvidersStreamProvider(uid),
          (_, _) {},
          fireImmediately: true,
        );

        // 5s + buffer wallclock — 5회 retry 모두 소진 후 빈 배열 emit.
        await Future<void>.delayed(const Duration(milliseconds: 5500));
        await _settle();
        final asyncValue = container.read(linkedProvidersStreamProvider(uid));
        expect(asyncValue.hasValue, isTrue);
        expect(
          asyncValue.value?.linkedProviderIds,
          isEmpty,
          reason: '5회 escape → 빈 배열 fallback (영구 spinner 회피)',
        );
      }, timeout: const Timeout(Duration(seconds: 15)));

      test('4. 다른 FirebaseException (unavailable) → 즉시 AsyncData([]) (D-41 '
          '보존, I1)', () async {
        const uid = 'uid-r10f2-other-error';
        final firestore = _buildFirestore(
          uid: uid,
          shouldError: true,
          errorCode: 'unavailable',
        );

        final container = ProviderContainer(
          overrides: [firebaseFirestoreProvider.overrideWithValue(firestore)],
        );
        addTearDown(container.dispose);
        container.listen(
          linkedProvidersStreamProvider(uid),
          (_, _) {},
          fireImmediately: true,
        );

        // 즉시 (no delay) 빈 배열 fallback — retry 진입 안 함.
        await _settle();
        final asyncValue = container.read(linkedProvidersStreamProvider(uid));
        expect(asyncValue.hasValue, isTrue);
        expect(
          asyncValue.value?.linkedProviderIds,
          isEmpty,
          reason: 'permission-denied 가 아닌 코드는 즉시 fallback (I1)',
        );
      });

      test('5. 카운터 리셋 — 1차 throw → 2차 정상 → 3차 throw → 4차 정상 (5회 누적 '
          '아님, I3)', () async {
        const uid = 'uid-r10f2-counter-reset';
        final snap = _buildSnapshot(
          exists: true,
          data: <String, dynamic>{
            'linkedProviders': <Map<String, dynamic>>[
              {'providerId': 'naver', 'providerUserId': 'nv1'},
            ],
          },
        );
        // 1차 throw → 2차 정상 (카운터 리셋) → 3차 throw → 4차 정상.
        // 카운터가 리셋되지 않으면 5회 escape 임계 근접; 리셋 시 재 retry 가능.
        final firestore = _buildRetryFirestore(
          uid: uid,
          streamFactories: [
            _permissionDeniedFactory(),
            _valueFactory(snap),
            _permissionDeniedFactory(),
            _valueFactory(snap),
          ],
        );

        final container = ProviderContainer(
          overrides: [firebaseFirestoreProvider.overrideWithValue(firestore)],
        );
        addTearDown(container.dispose);
        container.listen(
          linkedProvidersStreamProvider(uid),
          (_, _) {},
          fireImmediately: true,
        );

        // 1차 retryDelay 후 2차 정상 emit → 카운터 0 리셋 → source stream
        // 끝나며 다시 try 진입 → 3차 throw → retryDelay → 4차 정상.
        // 총 wallclock ≈ 2 × 1s = 2s + microtask buffer.
        await Future<void>.delayed(const Duration(milliseconds: 2200));
        await _settle();

        final asyncValue = container.read(linkedProvidersStreamProvider(uid));
        expect(asyncValue.hasValue, isTrue);
        expect(asyncValue.value?.linkedProviderIds, [
          'naver',
        ], reason: '카운터 리셋 후 재 retry 통해 정상 emit 도달 (I3)');
      }, timeout: const Timeout(Duration(seconds: 10)));
    },
  );

  // ==========================================================================
  // WR-04 (Phase 7 review): 비-permission-denied FirebaseException 후에도
  // generator 를 닫지 않고 backoff 재구독으로 자력 복구한다. 이전 구현은
  // `break` 로 async* generator 를 종료시켜, keepAlive provider 가 앱 재시작
  // 전까지 재구독되지 않아 linkedProviders 가 세션 내내 빈 배열에 고정됐다.
  // ==========================================================================
  group('WR-04: linkedProvidersStream 에러 후 backoff 재구독 (I5)', () {
    test('unavailable 1회 → 빈 배열 fallback 후 backoff 재구독으로 복구', () async {
      const uid = 'uid-wr04-recover';
      final snap = _buildSnapshot(
        exists: true,
        data: <String, dynamic>{
          'linkedProviders': <Map<String, dynamic>>[
            {'providerId': 'kakao', 'providerUserId': 'kk1'},
          ],
        },
      );
      final firestore = _buildRetryFirestore(
        uid: uid,
        streamFactories: [
          () => Stream<_MockDocumentSnapshot>.error(
            FirebaseException(plugin: 'cloud_firestore', code: 'unavailable'),
          ),
          _valueFactory(snap),
        ],
      );

      final container = ProviderContainer(
        overrides: [firebaseFirestoreProvider.overrideWithValue(firestore)],
      );
      addTearDown(container.dispose);
      container.listen(
        linkedProvidersStreamProvider(uid),
        (_, _) {},
        fireImmediately: true,
      );

      // 1차 — 즉시 빈 배열 fallback (D-41 / I1 보존).
      await _settle();
      expect(
        container
            .read(linkedProvidersStreamProvider(uid))
            .value
            ?.linkedProviderIds,
        isEmpty,
        reason: '비-permission-denied 는 즉시 빈 배열 fallback (I1)',
      );

      // 2차 — 5s backoff 후 재구독하여 정상 emit 도달 (I5).
      await Future<void>.delayed(const Duration(milliseconds: 5500));
      await _settle();
      expect(
        container
            .read(linkedProvidersStreamProvider(uid))
            .value
            ?.linkedProviderIds,
        ['kakao'],
        reason: 'generator 가 살아 있어 세션 내 자력 복구 (WR-04)',
      );
    }, timeout: const Timeout(Duration(seconds: 20)));
  });

  // ==========================================================================
  // Phase 16.7 D-11: UserProviderRecord — linkedProviderIds 와
  // signUpProviderId 가 같은 snapshot 에서 함께 파싱되고 함께 보존된다.
  // ==========================================================================
  group('Phase 16.7: signUpProviderId record (D-11)', () {
    test('7. linkedProviders=[{kakao}] + signUpProviderId=kakao → '
        'User.signUpProviderId=kakao · providerIds 합집합 불변', () async {
      const uid = 'uid-signup-kakao';
      final fbUser = _buildFbUser(uid: uid, providerIds: <String>[]);
      final snap = _buildSnapshot(
        exists: true,
        data: <String, dynamic>{
          'linkedProviders': <Map<String, dynamic>>[
            {'providerId': 'kakao', 'providerUserId': 'kk1'},
          ],
          'signUpProviderId': 'kakao',
        },
      );
      final firestore = _buildFirestore(
        uid: uid,
        snapshots: Stream<_MockDocumentSnapshot>.value(snap),
      );

      final container = _makeContainer(
        overrides: [
          authStateProvider.overrideWith(
            (ref) => Stream<fb.User?>.value(fbUser),
          ),
          firebaseFirestoreProvider.overrideWithValue(firestore),
        ],
      );
      addTearDown(container.dispose);

      await _settle();
      final user = container.read(currentUserProvider);
      expect(user, isNotNull);
      expect(user!.signUpProviderId, 'kakao');
      expect(user.providerIds, ['kakao']);
    });

    test('8. signUpProviderId 가 String 아닌 타입 (42) → null', () async {
      const uid = 'uid-signup-bad-type';
      final fbUser = _buildFbUser(uid: uid, providerIds: ['google.com']);
      final snap = _buildSnapshot(
        exists: true,
        data: <String, dynamic>{
          'linkedProviders': <Map<String, dynamic>>[],
          'signUpProviderId': 42,
        },
      );
      final firestore = _buildFirestore(
        uid: uid,
        snapshots: Stream<_MockDocumentSnapshot>.value(snap),
      );

      final container = _makeContainer(
        overrides: [
          authStateProvider.overrideWith(
            (ref) => Stream<fb.User?>.value(fbUser),
          ),
          firebaseFirestoreProvider.overrideWithValue(firestore),
        ],
      );
      addTearDown(container.dispose);

      await _settle();
      final user = container.read(currentUserProvider);
      expect(user, isNotNull);
      expect(user!.signUpProviderId, isNull);
      expect(user.providerIds, ['google.com']);
    });

    test('9. linkedProviders 부재 + signUpProviderId=password → '
        'providerIds = providerData 만 · signUpProviderId 보존', () async {
      const uid = 'uid-signup-no-linked';
      final fbUser = _buildFbUser(uid: uid, providerIds: ['password']);
      final snap = _buildSnapshot(
        exists: true,
        data: <String, dynamic>{'signUpProviderId': 'password'},
      );
      final firestore = _buildFirestore(
        uid: uid,
        snapshots: Stream<_MockDocumentSnapshot>.value(snap),
      );

      final container = _makeContainer(
        overrides: [
          authStateProvider.overrideWith(
            (ref) => Stream<fb.User?>.value(fbUser),
          ),
          firebaseFirestoreProvider.overrideWithValue(firestore),
        ],
      );
      addTearDown(container.dispose);

      await _settle();
      final user = container.read(currentUserProvider);
      expect(user, isNotNull);
      expect(user!.providerIds, ['password']);
      expect(user.signUpProviderId, 'password');
    });

    test('10. 첫 emit 뒤 재구독 중 AsyncLoading → 직전 cached record 의 '
        'signUpProviderId 유지', () async {
      const uid = 'uid-signup-loading-cached';
      final fbUser = _buildFbUser(uid: uid, providerIds: <String>[]);
      final snap = _buildSnapshot(
        exists: true,
        data: <String, dynamic>{
          'linkedProviders': <Map<String, dynamic>>[
            {'providerId': 'naver', 'providerUserId': 'nv1'},
          ],
          'signUpProviderId': 'naver',
        },
      );
      // 2차 구독은 영원히 emit 하지 않는다 — invalidate 뒤 AsyncLoading 유지.
      final pending = StreamController<_MockDocumentSnapshot>();
      addTearDown(pending.close);
      final firestore = _buildRetryFirestore(
        uid: uid,
        streamFactories: [_valueFactory(snap), () => pending.stream],
      );

      final container = _makeContainer(
        overrides: [
          authStateProvider.overrideWith(
            (ref) => Stream<fb.User?>.value(fbUser),
          ),
          firebaseFirestoreProvider.overrideWithValue(firestore),
        ],
      );
      addTearDown(container.dispose);

      await _settle();
      expect(container.read(currentUserProvider)?.signUpProviderId, 'naver');

      // 재구독 — 새 generator 가 아직 emit 전이라 AsyncLoading(cached).
      container.invalidate(linkedProvidersStreamProvider(uid));
      await _settle();
      final recAsync = container.read(linkedProvidersStreamProvider(uid));
      expect(recAsync.isLoading, isTrue);

      final user = container.read(currentUserProvider);
      expect(user, isNotNull);
      expect(user!.signUpProviderId, 'naver');
      expect(user.providerIds, ['naver']);
    });
  });

  // ==========================================================================
  // Phase 17 D-17 · D-18 · D-27: 표시 이름 · 사진 합성.
  // 표시 사진 = users/{uid}.customPhotoUrl > Auth photoURL > providerData.
  // ==========================================================================
  group('Phase 17 프로필 표시 (T-17-PROFILE)', () {
    /// [data] 한 번을 emit 하는 Firestore 와 Auth 사용자로 컨테이너를 만든다.
    ProviderContainer buildContainer({
      required _MockFbUser fbUser,
      required String uid,
      required Map<String, dynamic> data,
    }) {
      final snap = _buildSnapshot(exists: true, data: data);
      final firestore = _buildFirestore(
        uid: uid,
        snapshots: Stream<_MockDocumentSnapshot>.value(snap),
      );
      return _makeContainer(
        overrides: [
          authStateProvider.overrideWith(
            (ref) => Stream<fb.User?>.value(fbUser),
          ),
          firebaseFirestoreProvider.overrideWithValue(firestore),
        ],
      );
    }

    test('T-17-PROFILE-01 customPhotoUrl 있음 → photoUrl · customPhotoUrl '
        '모두 업로드 사진', () async {
      const uid = 'uid-profile-custom';
      const custom = 'https://x/avatar.jpg?v=1';
      final fbUser = _buildFbUser(
        uid: uid,
        providerIds: ['google.com'],
        photoUrl: 'https://auth/photo.jpg',
      );
      final container = buildContainer(
        fbUser: fbUser,
        uid: uid,
        data: <String, dynamic>{'customPhotoUrl': custom},
      );
      addTearDown(container.dispose);

      await _settle();
      final user = container.read(currentUserProvider);
      expect(user, isNotNull);
      expect(user!.photoUrl, custom);
      expect(user.customPhotoUrl, custom);
    });

    test('T-17-PROFILE-01 customPhotoUrl 부재 → photoUrl = Auth photoURL · '
        'customPhotoUrl null', () async {
      const uid = 'uid-profile-no-custom';
      final fbUser = _buildFbUser(
        uid: uid,
        providerIds: ['google.com'],
        photoUrl: 'https://auth/photo.jpg',
      );
      final container = buildContainer(
        fbUser: fbUser,
        uid: uid,
        data: <String, dynamic>{'signUpProviderId': 'google.com'},
      );
      addTearDown(container.dispose);

      await _settle();
      final user = container.read(currentUserProvider);
      expect(user, isNotNull);
      expect(user!.photoUrl, 'https://auth/photo.jpg');
      expect(user.customPhotoUrl, isNull);
    });

    test('T-17-PROFILE-01 customPhotoUrl 이 문자열 아님(숫자) → 부재와 같다', () async {
      const uid = 'uid-profile-bad-type';
      final fbUser = _buildFbUser(
        uid: uid,
        providerIds: ['google.com'],
        photoUrl: 'https://auth/photo.jpg',
      );
      final container = buildContainer(
        fbUser: fbUser,
        uid: uid,
        data: <String, dynamic>{'customPhotoUrl': 42},
      );
      addTearDown(container.dispose);

      await _settle();
      final user = container.read(currentUserProvider);
      expect(user, isNotNull);
      expect(user!.photoUrl, 'https://auth/photo.jpg');
      expect(user.customPhotoUrl, isNull);
    });

    test('T-17-PROFILE-02 customPhotoUrl 있음 → 삭제(재방출) → Auth 사진 '
        '복귀 (D-17)', () async {
      const uid = 'uid-profile-revert';
      const custom = 'https://x/avatar.jpg?v=2';
      final fbUser = _buildFbUser(
        uid: uid,
        providerIds: ['google.com'],
        photoUrl: 'https://auth/photo.jpg',
      );
      final snapshots = StreamController<_MockDocumentSnapshot>();
      addTearDown(snapshots.close);
      final firestore = _buildFirestore(uid: uid, snapshots: snapshots.stream);
      final container = _makeContainer(
        overrides: [
          authStateProvider.overrideWith(
            (ref) => Stream<fb.User?>.value(fbUser),
          ),
          firebaseFirestoreProvider.overrideWithValue(firestore),
        ],
      );
      addTearDown(container.dispose);

      snapshots.add(
        _buildSnapshot(
          exists: true,
          data: <String, dynamic>{'customPhotoUrl': custom},
        ),
      );
      await _settle();
      expect(container.read(currentUserProvider)?.photoUrl, custom);

      // 업로드 사진 삭제 = 필드 null → 같은 문서 재방출.
      snapshots.add(
        _buildSnapshot(
          exists: true,
          data: <String, dynamic>{'customPhotoUrl': null},
        ),
      );
      await _settle();
      final user = container.read(currentUserProvider);
      expect(user, isNotNull);
      expect(user!.photoUrl, 'https://auth/photo.jpg');
      expect(user.customPhotoUrl, isNull);
    });
  });
}
