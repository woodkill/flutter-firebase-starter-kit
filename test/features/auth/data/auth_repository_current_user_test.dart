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
ProviderContainer _makeContainer({
  required List<Object> overrides,
}) {
  // ignore: argument_type_not_assignable — flutter_riverpod 의 Override 타입은
  // 외부 노출 미지원이라 List<Object> 로 받고 ProviderContainer 가 sub-type
  // 동적 캐스팅한다. 호출부는 모두 *.overrideWith / *.overrideWithValue 의
  // 결과만 전달하므로 안전.
  final container = ProviderContainer(
    overrides: overrides.cast(),
  );
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
  when(() => fbUser.displayName).thenReturn('Test User');
  when(() => fbUser.photoURL).thenReturn(null);
  when(() => fbUser.metadata).thenReturn(metadata);
  when(() => metadata.creationTime).thenReturn(DateTime.utc(2026, 1, 1));
  when(() => fbUser.providerData).thenReturn(infos);
  return fbUser;
}

/// Firestore stub: `users/{uid}` snapshots stream 을 [snapshots] 로 emit 한다.
///
/// [shouldError] true 면 stream 이 즉시 에러를 emit (handleError fallback
/// 검증용).
_MockFirebaseFirestore _buildFirestore({
  required String uid,
  Stream<_MockDocumentSnapshot>? snapshots,
  bool shouldError = false,
}) {
  final firestore = _MockFirebaseFirestore();
  final collection = _MockCollectionReference();
  final doc = _MockDocumentReference();

  when(() => firestore.collection('users')).thenReturn(collection);
  when(() => collection.doc(uid)).thenReturn(doc);
  if (shouldError) {
    when(() => doc.snapshots()).thenAnswer(
      (_) => Stream<_MockDocumentSnapshot>.error(
        FirebaseException(plugin: 'cloud_firestore', code: 'permission-denied'),
      ),
    );
  } else {
    when(() => doc.snapshots()).thenAnswer(
      (_) => snapshots ?? const Stream<_MockDocumentSnapshot>.empty(),
    );
  }
  return firestore;
}

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
          authStateProvider.overrideWith(
            (ref) => Stream<fb.User?>.value(null),
          ),
          firebaseFirestoreProvider.overrideWithValue(
            _MockFirebaseFirestore(),
          ),
        ],
      );
      addTearDown(container.dispose);

      await _settle();
      expect(container.read(currentUserProvider), isNull);
    });

    test(
      '2. Firebase providerData=[google.com] + Firestore linkedProviders='
      '[{kakao}, {google.com}] → providerIds 합집합 + 중복 제거',
      () async {
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
      },
    );

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

    test(
      '4. Firestore stream 에러 → Firebase providerData 만 사용 (fallback)',
      () async {
        const uid = 'uid-error';
        final fbUser = _buildFbUser(uid: uid, providerIds: ['google.com']);
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
        final user = container.read(currentUserProvider);
        // handleError 가 emit 자체를 차단 → AsyncLoading 잔류 → maybeWhen
        // orElse 분기로 빈 배열 → Firebase providerData 만 사용.
        expect(user, isNotNull);
        expect(user!.providerIds, ['google.com']);
      },
    );

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

    test(
      '6. 잘못된 schema (linkedProviders 가 List<String>) → whereType 가 필터 — '
      '빈 배열 처리 (T-12-06-05 type-safe parsing)',
      () async {
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
      },
    );
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
          overrides: [
            firebaseFirestoreProvider.overrideWithValue(firestore),
          ],
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
        expect(asyncValue.value, ['kakao', 'naver']);
      },
    );
  });
}
