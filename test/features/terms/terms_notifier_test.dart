import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

import 'package:flutter_starter_kit/core/crashlytics/crashlytics_service.dart';
import 'package:flutter_starter_kit/core/error/app_exception.dart';
import 'package:flutter_starter_kit/core/error/result.dart';
import 'package:flutter_starter_kit/core/providers/firebase_providers.dart';
import 'package:flutter_starter_kit/features/terms/domain/terms_acceptance.dart';
import 'package:flutter_starter_kit/features/terms/presentation/terms_notifier.dart';

/// 쓰기만 실패하는 SharedPreferences 스토어 (10-REVIEW WR-21 회귀 재현용).
///
/// `setMockInitialValues` 가 설치하는 in-memory 스토어는 쓰기가 항상 성공해서
/// 영속화 실패 경로를 재현할 수 없다. 읽기/삭제는 정상 동작시키고 `setValue`
/// 만 던지게 하여 `accept()` 의 롤백 분기를 정확히 겨냥한다.
class _WriteFailingPrefsStore extends SharedPreferencesStorePlatform {
  final Map<String, Object> _values = <String, Object>{};

  @override
  Future<bool> clear() async {
    _values.clear();
    return true;
  }

  @override
  Future<Map<String, Object>> getAll() async => Map<String, Object>.of(_values);

  @override
  Future<bool> remove(String key) async {
    _values.remove(key);
    return true;
  }

  @override
  Future<bool> setValue(String valueType, String key, Object value) async {
    throw StateError('prefs write failed (WR-21 회귀 재현)');
  }
}

class _MockCrashlyticsService extends Mock implements CrashlyticsService {}

class _MockFirestore extends Mock implements FirebaseFirestore {}

// cloud_firestore 의 CollectionReference / DocumentReference 는 sealed
// 클래스이다. fake_cloud_firestore 의존성을 추가하지 않기 위해 mocktail
// `Mock` 으로 우회하며, sealed 경고는 테스트 한정 의도된 우회임.
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

  setUp(() {
    mockCrashlytics = _MockCrashlyticsService();
    mockFirestore = _MockFirestore();
    mockCollection = _MockCollection();
    mockDoc = _MockDoc();

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

    // Plan 10-12 Issue #8: mirrorToFirestore 가 pre-read 를 수행하므로,
    // 기본 stub 은 `snapshot.exists=false` 로 설정하여 기존 테스트(Test 6
    // write 경로, Test 8 FirebaseException 경로)가 회귀하지 않도록 한다.
    // Test 7 (Issue #7 D-1, _acceptance=null) 은 pre-read 미진입 → stub
    // 영향 없음. Issue #8 skip 테스트(Test 9e) 는 per-test override 로
    // exists=true 로 전환.
    final defaultSnapshot = _MockSnapshot();
    when(() => defaultSnapshot.exists).thenReturn(false);
    when(() => defaultSnapshot.data()).thenReturn(null);
    when(() => mockDoc.get()).thenAnswer((_) async => defaultSnapshot);
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

  group('TermsNotifier', () {
    test('Test 1: 빈 상태 → build() null', () async {
      SharedPreferences.setMockInitialValues({});
      final container = createContainer();

      expect(container.read(termsProvider), isNull);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(container.read(termsProvider), isNull);
    });

    test(
      'Test 2: accept(true, true, false) → success + state.service/privacy=true, '
      'marketing=false, version=1',
      () async {
        SharedPreferences.setMockInitialValues({});
        final container = createContainer();
        final notifier = container.read(termsProvider.notifier);

        final result = await notifier.accept(
          service: true,
          privacy: true,
          marketing: false,
        );

        expect(result, isA<Success<dynamic>>());
        final state = container.read(termsProvider);
        expect(state, isNotNull);
        expect(state!.service, isTrue);
        expect(state.privacy, isTrue);
        expect(state.marketing, isFalse);
        expect(state.version, TermsNotifier.currentVersion);
      },
    );

    test('Test 3: accept(false, true, false) 또는 accept(true, false, false) → '
        'failure, state 변경 없음', () async {
      SharedPreferences.setMockInitialValues({});
      final container = createContainer();
      final notifier = container.read(termsProvider.notifier);

      final result1 = await notifier.accept(
        service: false,
        privacy: true,
        marketing: false,
      );
      expect(result1, isA<Failure<dynamic>>());
      expect(container.read(termsProvider), isNull);

      final result2 = await notifier.accept(
        service: true,
        privacy: false,
        marketing: false,
      );
      expect(result2, isA<Failure<dynamic>>());
      expect(container.read(termsProvider), isNull);
    });

    test('Test 3b (WR-13): 필수 동의 누락은 InvalidInput — 서비스 장애가 아니다', () async {
      // ServiceUnavailable 로 반환하면 호출자가 "잠시 후 다시 시도" 문구를
      // 붙이게 되는데, 계약 위반은 재시도로 절대 해소되지 않는다. 영속화
      // 실패(ServiceUnavailable)와 타입으로 구분되어야 한다.
      SharedPreferences.setMockInitialValues({});
      final container = createContainer();
      final notifier = container.read(termsProvider.notifier);

      final result = await notifier.accept(
        service: false,
        privacy: false,
        marketing: false,
      );

      expect(result, isA<Failure<void>>());
      final exception = (result as Failure<void>).exception;
      expect(exception, isA<InvalidInput>());
      expect(exception, isNot(isA<ServiceUnavailable>()));
    });

    test('Test 3c (WR-21): 영속화 실패 시 in-memory 동의 상태를 롤백한다', () async {
      // 실패를 반환하면서 상태를 "동의 완료" 로 남기면 mirrorToFirestore 가
      // 디스크에도 서버에도 없는 값을 권위 있는 것처럼 쓰고, _loadFromPrefs
      // 는 저장값 부재 시 state 를 clear 하지 않아 유령 상태가 영속된다.
      SharedPreferences.setMockInitialValues({});
      final originalStore = SharedPreferencesStorePlatform.instance;
      SharedPreferencesStorePlatform.instance = _WriteFailingPrefsStore();
      SharedPreferences.resetStatic();
      addTearDown(() {
        SharedPreferencesStorePlatform.instance = originalStore;
        SharedPreferences.resetStatic();
      });

      final container = createContainer();
      final notifier = container.read(termsProvider.notifier);

      final result = await notifier.accept(
        service: true,
        privacy: true,
        marketing: false,
      );

      expect(result, isA<Failure<void>>());
      expect((result as Failure<void>).exception, isA<ServiceUnavailable>());
      // 롤백 — state / 내부 캐시 / mirror payload 모두 직전 값(null)으로 복귀.
      expect(container.read(termsProvider), isNull);
      expect(notifier.acceptanceSnapshot, isNull);
      expect(notifier.acceptanceSnapshotJson, isNull);
      // 실패는 telemetry 로 남는다.
      verify(
        () => mockCrashlytics.recordError(
          any<Object>(),
          any<StackTrace?>(),
          reason: 'terms_save',
        ),
      ).called(1);
    });

    test('Test 4: accept 성공 시 SharedPreferences `terms.accepted_value` 키에 '
        '전체 JSON 문자열 저장됨 (WARNING #16 계약)', () async {
      SharedPreferences.setMockInitialValues({});
      final container = createContainer();
      final notifier = container.read(termsProvider.notifier);

      await notifier.accept(service: true, privacy: true, marketing: true);

      final prefs = await SharedPreferences.getInstance();
      final savedJson = prefs.getString('terms.accepted_value');
      expect(savedJson, isNotNull);
      final map = jsonDecode(savedJson!) as Map<String, dynamic>;
      expect(map['service'], isTrue);
      expect(map['privacy'], isTrue);
      expect(map['marketing'], isTrue);
      expect(map['version'], TermsNotifier.currentVersion);
      expect(map['acceptedAt'], isNotNull);
    });

    test('Test 5: cold-start + reloadForUser(isAnonymous=true) 시 '
        '`terms.accepted_value` JSON 복원 → state 가 원본 accept() 호출 값과 동일 '
        '(marketing=true, acceptedAt 정확)', () async {
      // 1단계: accept 호출하여 SharedPreferences 에 JSON 저장
      SharedPreferences.setMockInitialValues({});
      final firstContainer = createContainer();
      await firstContainer
          .read(termsProvider.notifier)
          .accept(service: true, privacy: true, marketing: true);
      final original = firstContainer.read(termsProvider);
      expect(original, isNotNull);
      firstContainer.dispose();

      // 2단계: cold-start 시뮬레이션 — 새 container.
      // CR-01 review fix 이후 build() 는 prefs 를 자동 로드하지 않으므로
      // authUserObserver 가 호출하는 reloadForUser 경로를 명시 호출하여
      // 익명 사용자 진입 시 device-local 복원이 정확히 동작함을 검증한다.
      final secondContainer = createContainer();
      await secondContainer
          .read(termsProvider.notifier)
          .reloadForUser(uid: 'anon-cold-start', isAnonymous: true);

      final restored = secondContainer.read(termsProvider);
      expect(restored, isNotNull);
      expect(restored!.service, isTrue);
      expect(restored.privacy, isTrue);
      // WARNING #16 핵심 검증: marketing=true 가 정확히 복원되어야 한다.
      expect(restored.marketing, isTrue);
      expect(restored.version, original!.version);
      // acceptedAt 도 epoch fallback 이 아니라 원본 시각으로 복원됨.
      expect(
        restored.acceptedAt.toIso8601String(),
        original.acceptedAt.toIso8601String(),
      );
    });

    test(
      'Test 6: mirrorToFirestore(uid: abc-123) → users/abc-123 문서 '
      'termsAccepted 필드 쓰기 + cold-start 후에도 marketing=true 기록 (WARNING #16)',
      () async {
        // 1단계: accept + cold-start 시뮬
        SharedPreferences.setMockInitialValues({});
        final firstContainer = createContainer();
        await firstContainer
            .read(termsProvider.notifier)
            .accept(service: true, privacy: true, marketing: true);
        firstContainer.dispose();

        // 2단계: 새 container 로 cold-start.
        // CR-01 review fix 이후 build() 는 prefs 자동 로드 없음 → mirror 가 참조하는
        // _acceptance 를 채우려면 reloadForUser(isAnonymous=true) 로 prefs 를
        // 명시 복원해야 한다. 이는 익명→정식 전이 직전 authUserObserver 가
        // 익명 reload 를 거친 후 mirror 를 호출하는 실제 흐름과 일치한다.
        final secondContainer = createContainer();
        await secondContainer
            .read(termsProvider.notifier)
            .reloadForUser(uid: 'anon-pre-mirror', isAnonymous: true);

        final result = await secondContainer
            .read(termsProvider.notifier)
            .mirrorToFirestore(uid: 'abc-123');

        expect(result, isA<Success<dynamic>>());
        verify(() => mockFirestore.collection('users')).called(1);
        verify(() => mockCollection.doc('abc-123')).called(1);

        final captured = verify(
          () => mockDoc.set(
            captureAny<Map<String, dynamic>>(),
            any<SetOptions>(),
          ),
        ).captured;
        final payload = captured.single as Map<String, dynamic>;
        final terms = payload['termsAccepted'] as Map<String, dynamic>;
        expect(terms['service'], isTrue);
        expect(terms['privacy'], isTrue);
        // WARNING #16 핵심 — cold-start 후에도 marketing=true 가 기록됨.
        expect(terms['marketing'], isTrue);
        expect(terms['version'], TermsNotifier.currentVersion);
        expect(terms['acceptedAt'], isA<Timestamp>());
      },
    );

    test(
      'Test 7 (updated by Issue #7 D-1 Plan 10-11): state null 상태에서 '
      'mirrorToFirestore 호출 → Result.success(null) no-op (ServiceUnavailable 제거)',
      () async {
        SharedPreferences.setMockInitialValues({});
        final container = createContainer();

        final result = await container
            .read(termsProvider.notifier)
            .mirrorToFirestore(uid: 'abc-123');

        // D-1 전환: state=null 은 mirror 대상 부재 → 에러가 아닌 no-op 성공.
        expect(result, isA<Success<dynamic>>());
        verifyNever(
          () => mockDoc.set(any<Map<String, dynamic>>(), any<SetOptions>()),
        );
      },
    );

    test(
      'Test 8: Firestore FirebaseException throw → failure 반환, state 유지',
      () async {
        SharedPreferences.setMockInitialValues({});
        final container = createContainer();
        await container
            .read(termsProvider.notifier)
            .accept(service: true, privacy: true, marketing: false);
        final stateBefore = container.read(termsProvider);
        expect(stateBefore, isNotNull);

        when(
          () => mockDoc.set(any<Map<String, dynamic>>(), any<SetOptions>()),
        ).thenThrow(
          FirebaseException(plugin: 'firestore', code: 'unavailable'),
        );

        final result = await container
            .read(termsProvider.notifier)
            .mirrorToFirestore(uid: 'abc-123');

        expect(result, isA<Failure<dynamic>>());
        // state 는 유지되어 사용자가 다시 시도할 수 있다.
        expect(container.read(termsProvider), stateBefore);
      },
    );

    test(
      'Test 9: reset() → state null + SharedPreferences 키 제거 (public 메서드)',
      () async {
        SharedPreferences.setMockInitialValues({});
        final container = createContainer();
        await container
            .read(termsProvider.notifier)
            .accept(service: true, privacy: true, marketing: true);
        expect(container.read(termsProvider), isNotNull);

        // public reset() 호출 (WARNING #8: production 표면)
        await container.read(termsProvider.notifier).reset();

        expect(container.read(termsProvider), isNull);
        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getString('terms.accepted_value'), isNull);
        expect(prefs.getInt('terms.accepted_version'), isNull);
      },
    );

    test('Test 9c (Issue #7 D-1 Plan 10-11): mirrorToFirestore(state=null) → '
        'Result.success(null) no-op + Firestore.collection 미호출 '
        '(mirror→reload 직렬화 체인 noise 제거)', () async {
      // Given: accept() 미호출 → _acceptance=null 초기 상태.
      SharedPreferences.setMockInitialValues({});
      final container = createContainer();
      final notifier = container.read(termsProvider.notifier);

      // When: mirrorToFirestore 호출.
      final result = await notifier.mirrorToFirestore(uid: 'test-uid');

      // Then: 성공 반환 + Firestore write 경로 미호출.
      expect(
        result,
        isA<Success<dynamic>>(),
        reason:
            'state=null 은 accept() 미호출 또는 logout 직후 — mirror 대상 부재 → '
            '에러가 아닌 no-op 성공 (Issue #7 D-1)',
      );
      verifyNever(() => mockFirestore.collection(any()));
      verifyNever(
        () => mockDoc.set(any<Map<String, dynamic>>(), any<SetOptions>()),
      );
    });

    test(
      'Test 9d (Issue #7 C-1 Plan 10-11): reloadForUser 3분기 끝에 '
      'lastReloadedUid 가 갱신된다 (uid=null / isAnonymous=true / full uid)',
      () async {
        SharedPreferences.setMockInitialValues({});
        final container = createContainer();
        final notifier = container.read(termsProvider.notifier);

        // 초기 상태 — lastReloadedUid 가 null.
        expect(
          notifier.lastReloadedUid,
          isNull,
          reason: 'cold-start 직후 reload 이력 없음',
        );

        // 1분기 (uid=null, logout): lastReloadedUid = null.
        await notifier.reloadForUser();
        expect(
          notifier.lastReloadedUid,
          isNull,
          reason: 'uid=null 분기는 null 을 저장한다',
        );

        // 2분기 (isAnonymous=true): lastReloadedUid = 'ANON-A'.
        await notifier.reloadForUser(uid: 'ANON-A', isAnonymous: true);
        expect(
          notifier.lastReloadedUid,
          'ANON-A',
          reason: 'isAnonymous=true 분기는 uid 를 저장한다',
        );

        // 3분기 (full uid): lastReloadedUid = 'FULL-B'.
        // Firestore mock 을 '문서 없음' 으로 두어 state 는 null 로 유지.
        await notifier.reloadForUser(uid: 'FULL-B', isAnonymous: false);
        expect(
          notifier.lastReloadedUid,
          'FULL-B',
          reason: 'full uid 분기는 uid 를 저장한다 (Firestore read 성공/실패 무관)',
        );

        // 과거 값에 대한 덮어쓰기 검증: 다시 null → null 로 덮어씀.
        await notifier.reloadForUser();
        expect(
          notifier.lastReloadedUid,
          isNull,
          reason: '직전 값이 FULL-B 여도 null 로 재할당된다',
        );
      },
    );

    test('Test 9e (Issue #8 Plan 10-12 — multi-user invariant): '
        'mirrorToFirestore skip 경로 — `users/{uid}` 문서 존재 시 set 미호출 + '
        'Result.success(null) + Crashlytics setCustomKey 기록', () async {
      SharedPreferences.setMockInitialValues({});
      final container = createContainer();
      final notifier = container.read(termsProvider.notifier);

      // Given: 익명 B 의 device-local 동의값으로 _acceptance 채움 (Test 21 재현).
      await notifier.accept(service: true, privacy: true, marketing: true);

      // And: Firestore 에 정식 사용자 A 의 문서가 이미 존재 (termsAccepted 필드
      // 유무와 무관 — 문서 존재 자체가 "기존 사용자" invariant 신호).
      final existingSnapshot = _MockSnapshot();
      when(() => existingSnapshot.exists).thenReturn(true);
      when(
        () => existingSnapshot.data(),
      ).thenReturn(<String, dynamic>{'displayName': 'Foo'});
      when(() => mockDoc.get()).thenAnswer((_) async => existingSnapshot);

      when(
        () => mockCrashlytics.setCustomKey(any(), any<Object>()),
      ).thenAnswer((_) async {});

      // When: 익명 B → 정식 A 전이 시점에 authUserObserver 가 mirror 호출.
      final result = await notifier.mirrorToFirestore(uid: 'A-UID');

      // Then: write 미발생 + 성공 반환.
      expect(
        result,
        isA<Success<dynamic>>(),
        reason: 'Option B — 기존 문서 존재 시 mirror 는 no-op 성공 반환',
      );
      verifyNever(
        () => mockDoc.set(any<Map<String, dynamic>>(), any<SetOptions>()),
      );
      verify(() => mockDoc.get()).called(1);
      // Crashlytics skip 사유 추적.
      verify(
        () => mockCrashlytics.setCustomKey(
          'mirror_skip_reason',
          'existing_user_doc',
        ),
      ).called(1);
    });

    test(
      'Test 9f (Issue #8 Plan 10-12 — BLOCKER #4 회귀): '
      'mirrorToFirestore write 경로 — `users/{uid}` 문서 미존재 시 set 정상 호출',
      () async {
        SharedPreferences.setMockInitialValues({});
        final container = createContainer();
        final notifier = container.read(termsProvider.notifier);

        // Given: 익명 사용자가 약관 동의 → _acceptance 채움.
        await notifier.accept(service: true, privacy: true, marketing: false);

        // And: Firestore 에 신규 UID 문서 없음 (BLOCKER #4 최초 가입 시나리오).
        //      setUp 기본 stub 그대로 사용 — defaultSnapshot.exists=false.

        // When: 익명 → 정식 승격 시점에 mirror 호출.
        final result = await notifier.mirrorToFirestore(uid: 'NEW-UID');

        // Then: write 발생 + 성공 반환 (기존 BLOCKER #4 동작 유지).
        expect(result, isA<Success<dynamic>>());
        verify(() => mockDoc.get()).called(1);
        verify(
          () => mockDoc.set(any<Map<String, dynamic>>(), any<SetOptions>()),
        ).called(1);
      },
    );

    test('Test 9g (Issue #9 Plan 10-13 — force 재동의 경로): '
        'mirrorToFirestore(force: true) → 문서 존재해도 pre-read skip + set 호출 + '
        'Crashlytics setCustomKey 미호출', () async {
      SharedPreferences.setMockInitialValues({});
      final container = createContainer();
      final notifier = container.read(termsProvider.notifier);

      // Given: 정식 사용자 A 가 재동의를 마쳐 _acceptance 가 채워진 상태.
      await notifier.accept(service: true, privacy: true, marketing: true);

      // And: Firestore 에 A 문서가 이미 존재 (Plan 10-12 Option B 의 skip 조건).
      final existingSnapshot = _MockSnapshot();
      when(() => existingSnapshot.exists).thenReturn(true);
      when(
        () => existingSnapshot.data(),
      ).thenReturn(<String, dynamic>{'displayName': 'A'});
      when(() => mockDoc.get()).thenAnswer((_) async => existingSnapshot);
      when(
        () => mockCrashlytics.setCustomKey(any(), any<Object>()),
      ).thenAnswer((_) async {});

      // When: 사용자 명시적 재동의 의도로 force=true 경로 호출.
      final result = await notifier.mirrorToFirestore(
        uid: 'A-UID',
        force: true,
      );

      // Then: pre-read 건너뛰기 — get 미호출 + set 호출 (재동의 재기록).
      expect(result, isA<Success<dynamic>>());
      verifyNever(() => mockDoc.get());
      verify(
        () => mockDoc.set(any<Map<String, dynamic>>(), any<SetOptions>()),
      ).called(1);
      // Skip 경로를 타지 않았으므로 Crashlytics key 미호출.
      verifyNever(
        () => mockCrashlytics.setCustomKey('mirror_skip_reason', any<Object>()),
      );
    });

    test('Test 9h (Issue #9 Plan 10-13 — force 기본값 false 회귀): '
        'mirrorToFirestore() 기본값 호출은 Plan 10-12 Option B skip 정책을 '
        '그대로 유지 (force 파라미터 미전달)', () async {
      SharedPreferences.setMockInitialValues({});
      final container = createContainer();
      final notifier = container.read(termsProvider.notifier);

      await notifier.accept(service: true, privacy: true, marketing: false);

      final existingSnapshot = _MockSnapshot();
      when(() => existingSnapshot.exists).thenReturn(true);
      when(() => existingSnapshot.data()).thenReturn(<String, dynamic>{});
      when(() => mockDoc.get()).thenAnswer((_) async => existingSnapshot);
      when(
        () => mockCrashlytics.setCustomKey(any(), any<Object>()),
      ).thenAnswer((_) async {});

      // When: force 파라미터 생략 → 기본값 false 적용.
      final result = await notifier.mirrorToFirestore(uid: 'A-UID');

      // Then: Plan 10-12 skip 경로 그대로 — get 호출 + set 미호출.
      expect(result, isA<Success<dynamic>>());
      verify(() => mockDoc.get()).called(1);
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

    test(
      'Test 9b (CR-02 review fix): 정식 사용자 logout(reloadForUser(uid: null)) → '
      '익명 재로그인 시 직전 사용자의 device-local 동의가 승계되지 않는다 '
      '(multi-user device 교차 누출 차단)',
      () async {
        SharedPreferences.setMockInitialValues({});
        final container = createContainer();

        // 1) 정식 사용자 A 가 약관 동의 → SharedPreferences 에 A 의 JSON 저장.
        await container
            .read(termsProvider.notifier)
            .accept(service: true, privacy: true, marketing: true);
        expect(container.read(termsProvider), isNotNull);
        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getString('terms.accepted_value'), isNotNull);

        // 2) 사용자 A 로그아웃 — userChanges null emit 시뮬레이션.
        await container.read(termsProvider.notifier).reloadForUser(uid: null);

        expect(
          container.read(termsProvider),
          isNull,
          reason: 'state 가 즉시 비워져야 한다',
        );
        // CR-02 핵심 검증: prefs 도 함께 clear 되어야 한다.
        expect(
          prefs.getString('terms.accepted_value'),
          isNull,
          reason: 'logout 시 device-local 동의 키도 제거되어야 한다 (CR-02)',
        );
        expect(
          prefs.getInt('terms.accepted_version'),
          isNull,
          reason: 'legacy version 키도 함께 제거되어야 한다',
        );

        // 3) 익명 사용자 X 신규 로그인 — userChanges anonymous emit 시뮬레이션.
        await container
            .read(termsProvider.notifier)
            .reloadForUser(uid: 'anon-X', isAnonymous: true);

        expect(
          container.read(termsProvider),
          isNull,
          reason:
              '익명 X 진입 시 사용자 A 의 동의가 prefs 에서 복원되지 않아야 한다 '
              '(resolveAuthRedirect 분기 (5)/(2) → /onboarding 으로 보내야 한다)',
        );
      },
    );
  });

  group('TermsNotifier.acceptanceSnapshotJson (CR-01)', () {
    test('Test 11 (CR-01): accept() 직후 acceptanceSnapshotJson.acceptedAt 이 '
        'UTC(Z 접미) ISO 8601 이며 동일 instant 를 가리킨다', () async {
      SharedPreferences.setMockInitialValues({});
      final container = createContainer();
      final notifier = container.read(termsProvider.notifier);

      // accept() 는 DateTime.now() (local) 로 acceptedAt 을 만든다 —
      // fixture 문자열이 아니라 실제 producer 출력을 검증한다.
      await notifier.accept(service: true, privacy: true, marketing: false);

      final localAcceptedAt = notifier.acceptanceSnapshot!.acceptedAt;
      expect(
        localAcceptedAt.isUtc,
        isFalse,
        reason: 'accept() 는 local DateTime 을 만든다 — 전제 고정',
      );

      final json = notifier.acceptanceSnapshotJson;
      expect(json, isNotNull);
      final acceptedAt = json!['acceptedAt'] as String;
      expect(
        acceptedAt,
        endsWith('Z'),
        reason:
            '서버(TZ=UTC)는 offset 없는 문자열을 UTC 로 해석하므로 '
            'Z 접미 UTC 문자열이어야 한다 (CR-01)',
      );
      // 값이 바뀌지 않고 표현만 UTC 로 정규화되어야 한다.
      expect(
        DateTime.parse(acceptedAt).isAtSameMomentAs(localAcceptedAt),
        isTrue,
        reason: 'UTC 정규화는 instant 를 보존해야 한다',
      );
    });

    test(
      'Test 12 (CR-01): 동의 기록이 없으면 acceptanceSnapshotJson 은 null 이다',
      () async {
        SharedPreferences.setMockInitialValues({});
        final container = createContainer();
        final notifier = container.read(termsProvider.notifier);

        expect(notifier.acceptanceSnapshotJson, isNull);
      },
    );

    test('Test 13 (CR-01): acceptanceSnapshotJson 키 집합이 서버 계약 5 키다', () async {
      SharedPreferences.setMockInitialValues({});
      final container = createContainer();
      final notifier = container.read(termsProvider.notifier);

      await notifier.accept(service: true, privacy: true, marketing: true);

      expect(notifier.acceptanceSnapshotJson!.keys.toSet(), <String>{
        'version',
        'service',
        'privacy',
        'marketing',
        'acceptedAt',
      });
    });
  });

  group('TermsAcceptance', () {
    test('Test 10a: toJson/fromJson 왕복 동일성', () {
      final original = TermsAcceptance(
        version: 1,
        service: true,
        privacy: true,
        marketing: false,
        acceptedAt: DateTime.utc(2026, 4, 14, 10, 30, 45),
      );

      final json = original.toJson();
      final restored = TermsAcceptance.fromJson(json);

      expect(restored, original);
      expect(restored.acceptedAt, original.acceptedAt);
    });

    test('T1 (10-REVIEW CR-03): 손상된 terms.accepted_value JSON 은 '
        'TypeError 를 누출하지 않고 흡수 + 손상값 제거', () async {
      // jsonDecode 는 List 를 반환하고 Map<String, dynamic> 캐스트에서
      // 진짜 TypeError 가 난다 (인위적 mock throw 아님).
      SharedPreferences.setMockInitialValues({
        'terms.accepted_value': '[1,2,3]',
      });
      final container = createContainer();
      final notifier = container.read(termsProvider.notifier);

      await notifier.reloadForUser(uid: 'anon-1', isAnonymous: true);

      expect(container.read(termsProvider), isNull);
      verify(
        () => mockCrashlytics.recordError(
          any<Object>(),
          any<StackTrace?>(),
          reason: 'terms_load',
          fatal: any(named: 'fatal'),
        ),
      ).called(1);
      // 다음 cold start 가 같은 실패를 반복하지 않도록 손상값이 제거된다.
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('terms.accepted_value'), isNull);
    });

    test('T2 (10-REVIEW CR-03): 손상된 legacy terms.accepted_version 도 '
        'TypeError 를 누출하지 않고 흡수 + 두 키 모두 제거', () async {
      // 신규 키 부재 → legacy int 키 경로의 prefs.getInt 에서 cast TypeError.
      SharedPreferences.setMockInitialValues({
        'terms.accepted_version': 'corrupt',
      });
      final container = createContainer();
      final notifier = container.read(termsProvider.notifier);

      await notifier.reloadForUser(uid: 'anon-1', isAnonymous: true);

      expect(container.read(termsProvider), isNull);
      verify(
        () => mockCrashlytics.recordError(
          any<Object>(),
          any<StackTrace?>(),
          reason: 'terms_load',
          fatal: any(named: 'fatal'),
        ),
      ).called(1);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('terms.accepted_value'), isNull);
      // getInt 는 값이 남아 있으면 다시 TypeError 이므로 키 존재 여부로 단언.
      expect(prefs.containsKey('terms.accepted_version'), isFalse);
    });

    test('Test 10b: copyWith 동작', () {
      final original = TermsAcceptance(
        version: 1,
        service: true,
        privacy: true,
        marketing: false,
        acceptedAt: DateTime.utc(2026, 4, 14),
      );

      final updated = original.copyWith(marketing: true);

      expect(updated.marketing, isTrue);
      expect(updated.service, original.service);
      expect(updated.privacy, original.privacy);
      expect(updated.version, original.version);
      expect(updated.acceptedAt, original.acceptedAt);
    });
  });
}
