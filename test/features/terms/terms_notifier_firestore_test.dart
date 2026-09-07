import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter_starter_kit/core/crashlytics/crashlytics_service.dart';
import 'package:flutter_starter_kit/core/error/result.dart';
import 'package:flutter_starter_kit/core/providers/firebase_providers.dart';
import 'package:flutter_starter_kit/features/terms/domain/terms_acceptance.dart';
import 'package:flutter_starter_kit/features/terms/presentation/terms_notifier.dart';

class _MockCrashlyticsService extends Mock implements CrashlyticsService {}

class _MockFirestore extends Mock implements FirebaseFirestore {}

// cloud_firestore 의 CollectionReference / DocumentReference 는 sealed 클래스이다.
// fake_cloud_firestore 의존성을 추가하지 않기 위해 mocktail Mock 으로 우회하며,
// sealed 경고는 테스트 한정 의도된 우회임 (terms_notifier_test 와 동일 패턴).
// ignore: subtype_of_sealed_class
class _MockCollection extends Mock
    implements CollectionReference<Map<String, dynamic>> {}

// ignore: subtype_of_sealed_class
class _MockDoc extends Mock
    implements DocumentReference<Map<String, dynamic>> {}

// ignore: subtype_of_sealed_class
class _MockSnapshot extends Mock
    implements DocumentSnapshot<Map<String, dynamic>> {}

class _FakeSetOptions extends Fake implements SetOptions {}

class _FakeStackTrace extends Fake implements StackTrace {}

void main() {
  setUpAll(() {
    registerFallbackValue(<String, dynamic>{});
    registerFallbackValue(_FakeSetOptions());
    registerFallbackValue(_FakeStackTrace());
  });

  late _MockCrashlyticsService mockCrashlytics;
  late _MockFirestore mockFirestore;
  late _MockCollection mockCollection;
  late _MockDoc mockDoc;
  late _MockSnapshot mockSnapshot;

  setUp(() {
    mockCrashlytics = _MockCrashlyticsService();
    mockFirestore = _MockFirestore();
    mockCollection = _MockCollection();
    mockDoc = _MockDoc();
    mockSnapshot = _MockSnapshot();

    when(
      () => mockCrashlytics.recordError(
        any<Object>(),
        any<StackTrace?>(),
        reason: any(named: 'reason'),
        fatal: any(named: 'fatal'),
      ),
    ).thenAnswer((_) async {});

    when(() => mockFirestore.collection(any())).thenReturn(mockCollection);
    when(() => mockCollection.doc(any())).thenReturn(mockDoc);
    when(
      () => mockDoc.set(any<Map<String, dynamic>>(), any<SetOptions>()),
    ).thenAnswer((_) async {});
    when(() => mockDoc.get()).thenAnswer((_) async => mockSnapshot);
  });

  ProviderContainer createContainer() {
    final container = ProviderContainer(
      overrides: [
        crashlyticsServiceProvider.overrideWithValue(mockCrashlytics),
        firebaseFirestoreProvider.overrideWithValue(mockFirestore),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  group('TermsNotifier Firestore source-of-truth (Issue #6 — Plan 10-09)', () {
    test('Test 1: Firestore termsAccepted 존재 → reloadForUser → state '
        '갱신 (Timestamp → DateTime 정확)', () async {
      SharedPreferences.setMockInitialValues({});
      final acceptedAt = DateTime.utc(2026, 4, 1, 10, 30, 45);
      when(() => mockSnapshot.exists).thenReturn(true);
      when(() => mockSnapshot.data()).thenReturn(<String, dynamic>{
        'termsAccepted': <String, dynamic>{
          'version': 1,
          'service': true,
          'privacy': true,
          'marketing': true,
          'acceptedAt': Timestamp.fromDate(acceptedAt),
        },
      });

      final container = createContainer();
      await container
          .read(termsProvider.notifier)
          .reloadForUser(uid: 'test-uid', isAnonymous: false);

      final state = container.read(termsProvider);
      expect(state, isNotNull);
      expect(state!.version, 1);
      expect(state.service, isTrue);
      expect(state.privacy, isTrue);
      expect(state.marketing, isTrue);
      // Timestamp.toDate() 는 local DateTime 으로 반환하므로
      // millisecondsSinceEpoch 단위로 비교 (UTC ↔ local 차이 무관).
      expect(
        state.acceptedAt.millisecondsSinceEpoch,
        acceptedAt.millisecondsSinceEpoch,
      );
      verify(() => mockFirestore.collection('users')).called(1);
      verify(() => mockCollection.doc('test-uid')).called(1);
    });

    test('Test 2: Firestore 문서 없음 → state null (D-15 invariant 평가용)', () async {
      SharedPreferences.setMockInitialValues({});
      when(() => mockSnapshot.exists).thenReturn(false);
      when(() => mockSnapshot.data()).thenReturn(null);

      final container = createContainer();
      await container
          .read(termsProvider.notifier)
          .reloadForUser(uid: 'no-data-uid', isAnonymous: false);

      expect(container.read(termsProvider), isNull);
    });

    test(
      'Test 2b: Firestore 문서 존재하나 termsAccepted 필드 없음 → state null',
      () async {
        SharedPreferences.setMockInitialValues({});
        when(() => mockSnapshot.exists).thenReturn(true);
        when(
          () => mockSnapshot.data(),
        ).thenReturn(<String, dynamic>{'displayName': 'Foo'});

        final container = createContainer();
        await container
            .read(termsProvider.notifier)
            .reloadForUser(uid: 'no-terms-uid', isAnonymous: false);

        expect(container.read(termsProvider), isNull);
      },
    );

    test('Test 3: Firestore FirebaseException → SharedPreferences fallback + '
        'Crashlytics recordError(reason=terms_load_firestore)', () async {
      // SharedPreferences 에 사전 유효 acceptance JSON.
      final fallbackAcceptedAt = DateTime.utc(2026, 4, 5, 12);
      final fallback = TermsAcceptance(
        version: TermsNotifier.currentVersion,
        service: true,
        privacy: true,
        marketing: false,
        acceptedAt: fallbackAcceptedAt,
      );
      SharedPreferences.setMockInitialValues(<String, Object>{
        'terms.accepted_value': jsonEncode(fallback.toJson()),
      });

      when(
        () => mockDoc.get(),
      ).thenThrow(FirebaseException(plugin: 'firestore', code: 'unavailable'));

      final container = createContainer();
      await container
          .read(termsProvider.notifier)
          .reloadForUser(uid: 'offline-uid', isAnonymous: false);

      // Fallback 으로 복원된 state 검증.
      final state = container.read(termsProvider);
      expect(state, isNotNull);
      expect(state!.service, isTrue);
      expect(state.privacy, isTrue);
      expect(state.marketing, isFalse);
      expect(state.acceptedAt, fallbackAcceptedAt);

      // Crashlytics 호출 검증.
      verify(
        () => mockCrashlytics.recordError(
          any<Object>(),
          any<StackTrace?>(),
          reason: 'terms_load_firestore',
        ),
      ).called(1);
    });

    test('Test 4: Timestamp 왕복 정확성 (mirror → reload millisecond 일치)', () async {
      SharedPreferences.setMockInitialValues({});
      final container = createContainer();
      final notifier = container.read(termsProvider.notifier);

      // 1) accept 호출 → state 캡처.
      await notifier.accept(service: true, privacy: true, marketing: false);
      final original = container.read(termsProvider);
      expect(original, isNotNull);

      // Plan 10-12 Issue #8: mirrorToFirestore 가 pre-read 를 수행. mirror
      // 단계에서는 문서 미존재 (exists=false) 로 stub 하여 pre-read 통과 +
      // write 경로 유지.
      when(() => mockSnapshot.exists).thenReturn(false);

      // 2) mirrorToFirestore 호출 → mockDoc.set 캡처.
      await notifier.mirrorToFirestore(uid: 'rt-uid');

      final captured = verify(
        () =>
            mockDoc.set(captureAny<Map<String, dynamic>>(), any<SetOptions>()),
      ).captured;
      final payload = captured.single as Map<String, dynamic>;
      final terms = payload['termsAccepted'] as Map<String, dynamic>;
      // mirrorToFirestore 의 payload 를 mockSnapshot 으로 재주입하여 reload.
      when(() => mockSnapshot.exists).thenReturn(true);
      when(
        () => mockSnapshot.data(),
      ).thenReturn(<String, dynamic>{'termsAccepted': terms});

      // 3) reloadForUser → 복원된 state.acceptedAt 비교.
      await notifier.reloadForUser(uid: 'rt-uid', isAnonymous: false);
      final restored = container.read(termsProvider);
      expect(restored, isNotNull);
      // Firestore Timestamp 정밀도 한계 (microsecond) 내에서 일치.
      expect(
        restored!.acceptedAt.millisecondsSinceEpoch,
        original!.acceptedAt.millisecondsSinceEpoch,
        reason: 'mirror→reload Timestamp 왕복 millisecond 정확성',
      );
      expect(restored.service, original.service);
      expect(restored.privacy, original.privacy);
      expect(restored.marketing, original.marketing);
      expect(restored.version, original.version);
    });

    test(
      'Test 5: Firestore version < currentVersion → state null (재동의 강제)',
      () async {
        SharedPreferences.setMockInitialValues({});
        when(() => mockSnapshot.exists).thenReturn(true);
        when(() => mockSnapshot.data()).thenReturn(<String, dynamic>{
          'termsAccepted': <String, dynamic>{
            // currentVersion=1 보다 낮은 버전.
            'version': 0,
            'service': true,
            'privacy': true,
            'marketing': true,
            'acceptedAt': Timestamp.fromDate(DateTime.utc(2026)),
          },
        });

        final container = createContainer();
        await container
            .read(termsProvider.notifier)
            .reloadForUser(uid: 'old-version-uid', isAnonymous: false);

        expect(
          container.read(termsProvider),
          isNull,
          reason: 'currentVersion 미달 → 재동의 강제',
        );
      },
    );

    test(
      'Test 6: reloadForUser(uid: null) → state null (로그아웃 reset)',
      () async {
        SharedPreferences.setMockInitialValues({});
        final container = createContainer();
        // 사전 accept 로 state 채워두기.
        await container
            .read(termsProvider.notifier)
            .accept(service: true, privacy: true, marketing: true);
        expect(container.read(termsProvider), isNotNull);

        // null uid → state=null.
        await container
            .read(termsProvider.notifier)
            .reloadForUser(uid: null, isAnonymous: false);

        expect(container.read(termsProvider), isNull);
        // Firestore read 호출 안 됨.
        verifyNever(() => mockDoc.get());
      },
    );

    test('Test 7: reloadForUser(uid: anon, isAnonymous: true) → '
        'SharedPreferences fallback (Firestore read 안 함)', () async {
      // SharedPreferences 에 사전 유효 acceptance.
      final fallbackAcceptedAt = DateTime.utc(2026, 4, 10);
      final fallback = TermsAcceptance(
        version: TermsNotifier.currentVersion,
        service: true,
        privacy: true,
        marketing: true,
        acceptedAt: fallbackAcceptedAt,
      );
      SharedPreferences.setMockInitialValues(<String, Object>{
        'terms.accepted_value': jsonEncode(fallback.toJson()),
      });

      final container = createContainer();
      await container
          .read(termsProvider.notifier)
          .reloadForUser(uid: 'anon-uid', isAnonymous: true);

      final state = container.read(termsProvider);
      expect(state, isNotNull);
      expect(state!.service, isTrue);
      expect(state.privacy, isTrue);
      expect(state.marketing, isTrue);
      // 익명 경로 — Firestore read 호출되지 않아야 함.
      verifyNever(() => mockFirestore.collection(any()));
    });

    test('Test 8 (Issue #8 Plan 10-12): multi-user invariant — Firestore A 문서 '
        '존재 + termsAccepted 필드 부재 시 mirror skip 후 reloadForUser 가 '
        'state=null 반환 (분기 (5) /onboarding 발동 조건)', () async {
      // Given: 정식 사용자 A 의 Firestore 문서 존재, termsAccepted 필드
      // 삭제 상태 (UAT Test 21 재현 — 관리자가 필드 수동 삭제).
      SharedPreferences.setMockInitialValues({});
      when(() => mockSnapshot.exists).thenReturn(true);
      when(
        () => mockSnapshot.data(),
      ).thenReturn(<String, dynamic>{'displayName': 'User A'});

      final container = createContainer();
      final notifier = container.read(termsProvider.notifier);

      // Crashlytics setCustomKey mock (본 파일 setUp 에 setCustomKey 가
      // 없으므로 inline stub).
      when(
        () => mockCrashlytics.setCustomKey(any(), any<Object>()),
      ).thenAnswer((_) async {});

      // Given: device-local 에서 익명 B 가 약관 동의 → _acceptance=B 동의값.
      await notifier.accept(service: true, privacy: true, marketing: true);

      // When (step 1): 익명 B → 정식 A 전이 — authUserObserver 가 mirror 호출.
      final mirrorResult = await notifier.mirrorToFirestore(uid: 'A-UID');

      // Then (step 1): mirror skip — A 의 기존 문서는 보존된다.
      expect(mirrorResult, isA<Success<dynamic>>());
      verifyNever(
        () => mockDoc.set(any<Map<String, dynamic>>(), any<SetOptions>()),
      );

      // When (step 2): mirror 후 authUserObserver 가 reloadForUser 호출.
      await notifier.reloadForUser(uid: 'A-UID', isAnonymous: false);

      // Then (step 2): Firestore A 에 termsAccepted 필드가 없으므로 state=null.
      // authRedirect 분기 (5) 가 /onboarding 으로 강제 리다이렉트하는 조건
      // 성립.
      expect(
        container.read(termsProvider),
        isNull,
        reason:
            'multi-user invariant — 기존 사용자 A 의 termsAccepted 필드 부재 시 '
            'device-local 동의값이 승계되지 않아야 한다 (Test 21 기대)',
      );
      expect(
        notifier.lastReloadedUid,
        'A-UID',
        reason: 'Issue #7 C-1 — reloadForUser 완료 후 lastReloadedUid 갱신',
      );
    });

    test('Test 9 (G-16-A9-1 재검토 결론 lock): 문서 존재 + termsAccepted 필드 '
        '존재 시에도 mirror skip — first-write-wins 반대편 sentinel', () async {
      // G-16-A9-1 은 skip 조건을 `!snapshot.exists ||
      // snapshot.data()?['termsAccepted'] == null` 로 완화할지 검토를
      // 요구했고, 결론은 반려(완화 불가)다. Test 8 이 "문서 존재 +
      // termsAccepted 부재" 를 잠그고, 본 Test 9 가 "문서 존재 +
      // termsAccepted 존재" 를 잠근다. 이 단언이 깨지면 Plan 10-12
      // multi-user invariant 도 함께 깨진 것이다.
      SharedPreferences.setMockInitialValues({});
      when(() => mockSnapshot.exists).thenReturn(true);
      when(() => mockSnapshot.data()).thenReturn(<String, dynamic>{
        'termsAccepted': <String, dynamic>{
          'version': 1,
          'service': true,
          'privacy': true,
          'marketing': false,
          'acceptedAt': Timestamp.fromDate(DateTime.utc(2026, 3, 1)),
        },
      });
      when(
        () => mockCrashlytics.setCustomKey(any(), any<Object>()),
      ).thenAnswer((_) async {});

      final container = createContainer();
      final notifier = container.read(termsProvider.notifier);

      // Given: 익명 사용자가 device-local 동의를 만든 상태.
      await notifier.accept(service: true, privacy: true, marketing: true);

      // When: 기존 사용자 문서를 대상으로 자동 mirror (force=false).
      final mirrorResult = await notifier.mirrorToFirestore(uid: 'A-UID');

      // Then: no-op 성공 + write 0 (first-write-wins 보존).
      expect(mirrorResult, isA<Success<dynamic>>());
      verifyNever(
        () => mockDoc.set(any<Map<String, dynamic>>(), any<SetOptions>()),
      );
      verify(
        () => mockCrashlytics.setCustomKey(
          'mirror_skip_reason',
          'existing_user_doc',
        ),
      ).called(1);
    });
  });
}
