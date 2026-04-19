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
        'marketing=false, version=1', () async {
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
    });

    test(
        'Test 3: accept(false, true, false) 또는 accept(true, false, false) → '
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

    test(
        'Test 4: accept 성공 시 SharedPreferences `terms.accepted_value` 키에 '
        '전체 JSON 문자열 저장됨 (WARNING #16 계약)', () async {
      SharedPreferences.setMockInitialValues({});
      final container = createContainer();
      final notifier = container.read(termsProvider.notifier);

      await notifier.accept(
        service: true,
        privacy: true,
        marketing: true,
      );

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

    test(
        'Test 5: cold-start + reloadForUser(isAnonymous=true) 시 '
        '`terms.accepted_value` JSON 복원 → state 가 원본 accept() 호출 값과 동일 '
        '(marketing=true, acceptedAt 정확)',
        () async {
      // 1단계: accept 호출하여 SharedPreferences 에 JSON 저장
      SharedPreferences.setMockInitialValues({});
      final firstContainer = createContainer();
      await firstContainer.read(termsProvider.notifier).accept(
            service: true,
            privacy: true,
            marketing: true,
          );
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
      await firstContainer.read(termsProvider.notifier).accept(
            service: true,
            privacy: true,
            marketing: true,
          );
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
    });

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
    });

    test('Test 8: Firestore FirebaseException throw → failure 반환, state 유지',
        () async {
      SharedPreferences.setMockInitialValues({});
      final container = createContainer();
      await container.read(termsProvider.notifier).accept(
            service: true,
            privacy: true,
            marketing: false,
          );
      final stateBefore = container.read(termsProvider);
      expect(stateBefore, isNotNull);

      when(
        () => mockDoc.set(any<Map<String, dynamic>>(), any<SetOptions>()),
      ).thenThrow(FirebaseException(plugin: 'firestore', code: 'unavailable'));

      final result = await container
          .read(termsProvider.notifier)
          .mirrorToFirestore(uid: 'abc-123');

      expect(result, isA<Failure<dynamic>>());
      // state 는 유지되어 사용자가 다시 시도할 수 있다.
      expect(container.read(termsProvider), stateBefore);
    });

    test('Test 9: reset() → state null + SharedPreferences 키 제거 (public 메서드)',
        () async {
      SharedPreferences.setMockInitialValues({});
      final container = createContainer();
      await container.read(termsProvider.notifier).accept(
            service: true,
            privacy: true,
            marketing: true,
          );
      expect(container.read(termsProvider), isNotNull);

      // public reset() 호출 (WARNING #8: production 표면)
      await container.read(termsProvider.notifier).reset();

      expect(container.read(termsProvider), isNull);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('terms.accepted_value'), isNull);
      expect(prefs.getInt('terms.accepted_version'), isNull);
    });

    test(
        'Test 9c (Issue #7 D-1 Plan 10-11): mirrorToFirestore(state=null) → '
        'Result.success(null) no-op + Firestore.collection 미호출 '
        '(mirror→reload 직렬화 체인 noise 제거)',
        () async {
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
        reason: 'state=null 은 accept() 미호출 또는 logout 직후 — mirror 대상 부재 → '
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
      await notifier.reloadForUser(
        uid: 'ANON-A',
        isAnonymous: true,
      );
      expect(
        notifier.lastReloadedUid,
        'ANON-A',
        reason: 'isAnonymous=true 분기는 uid 를 저장한다',
      );

      // 3분기 (full uid): lastReloadedUid = 'FULL-B'.
      // Firestore mock 을 '문서 없음' 으로 두어 state 는 null 로 유지.
      await notifier.reloadForUser(
        uid: 'FULL-B',
        isAnonymous: false,
      );
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
    });

    test(
        'Test 9e (Issue #8 Plan 10-12 — multi-user invariant): '
        'mirrorToFirestore skip 경로 — `users/{uid}` 문서 존재 시 set 미호출 + '
        'Result.success(null) + Crashlytics setCustomKey 기록', () async {
      SharedPreferences.setMockInitialValues({});
      final container = createContainer();
      final notifier = container.read(termsProvider.notifier);

      // Given: 익명 B 의 device-local 동의값으로 _acceptance 채움 (Test 21 재현).
      await notifier.accept(
        service: true,
        privacy: true,
        marketing: true,
      );

      // And: Firestore 에 정식 사용자 A 의 문서가 이미 존재 (termsAccepted 필드
      // 유무와 무관 — 문서 존재 자체가 "기존 사용자" invariant 신호).
      final existingSnapshot = _MockSnapshot();
      when(() => existingSnapshot.exists).thenReturn(true);
      when(() => existingSnapshot.data())
          .thenReturn(<String, dynamic>{'displayName': 'Foo'});
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
      await notifier.accept(
        service: true,
        privacy: true,
        marketing: false,
      );

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
    });

    test(
        'Test 9b (CR-02 review fix): 정식 사용자 logout(reloadForUser(uid: null)) → '
        '익명 재로그인 시 직전 사용자의 device-local 동의가 승계되지 않는다 '
        '(multi-user device 교차 누출 차단)',
        () async {
      SharedPreferences.setMockInitialValues({});
      final container = createContainer();

      // 1) 정식 사용자 A 가 약관 동의 → SharedPreferences 에 A 의 JSON 저장.
      await container.read(termsProvider.notifier).accept(
            service: true,
            privacy: true,
            marketing: true,
          );
      expect(container.read(termsProvider), isNotNull);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('terms.accepted_value'), isNotNull);

      // 2) 사용자 A 로그아웃 — userChanges null emit 시뮬레이션.
      await container.read(termsProvider.notifier).reloadForUser(uid: null);

      expect(container.read(termsProvider), isNull,
          reason: 'state 가 즉시 비워져야 한다');
      // CR-02 핵심 검증: prefs 도 함께 clear 되어야 한다.
      expect(prefs.getString('terms.accepted_value'), isNull,
          reason: 'logout 시 device-local 동의 키도 제거되어야 한다 (CR-02)');
      expect(prefs.getInt('terms.accepted_version'), isNull,
          reason: 'legacy version 키도 함께 제거되어야 한다');

      // 3) 익명 사용자 X 신규 로그인 — userChanges anonymous emit 시뮬레이션.
      await container
          .read(termsProvider.notifier)
          .reloadForUser(uid: 'anon-X', isAnonymous: true);

      expect(container.read(termsProvider), isNull,
          reason:
              '익명 X 진입 시 사용자 A 의 동의가 prefs 에서 복원되지 않아야 한다 '
              '(authRedirect 분기 (5)/(2) → /onboarding 으로 보내야 한다)');
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
