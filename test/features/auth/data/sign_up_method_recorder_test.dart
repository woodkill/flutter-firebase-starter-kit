// ignore_for_file: subtype_of_sealed_class
//
// cloud_firestore 의 CollectionReference / DocumentReference / DocumentSnapshot
// 은 sealed 클래스다. fake_cloud_firestore 를 dev_dependencies 에 추가하지
// 않기 위해 mocktail Mock 으로 우회한다 — terms_notifier_firestore_test 와
// 같은 테스트 한정 우회이며 프로덕션 코드는 sealed 우회 금지를 유지한다.
//
// Phase 16.7 Plan 01 — SignUpMethodRecorder 의 D-17 · D-19 경계.
//
// R1 순서: 약관 mirror → signUpProviderId set (D-19 — 반대 순서면 mirror
//    pre-read 가 자기 pending write 를 보고 skip)
// R2 payload: {'signUpProviderId': providerId} + SetOptions(merge: true)
// R3 mirror throw: set 은 계속 1회 · reason 'sign_up_method_terms_mirror'
// R4 set 예외: reason 'sign_up_method_record' 로 흡수 · record() 는 throw 0
// R5 D-19 통합(실제 TermsNotifier): get → set(termsAccepted) →
//    set(signUpProviderId) 순서로 약관이 가입 수단보다 먼저 착지
// R6 오프라인 pre-read(실제 TermsNotifier): get 이 unavailable 로 실패해
//    mirror 가 Failure 여도 signUpProviderId set 은 1회 · throw 0 (D-17)
//
// 단언의 uid 는 합성값('U1')만 쓴다 — 실 uid · email 은 로그 · 테스트에
// 넣지 않는다 (PII 0 정책).

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter_starter_kit/core/crashlytics/crashlytics_service.dart';
import 'package:flutter_starter_kit/core/providers/firebase_providers.dart';
import 'package:flutter_starter_kit/features/auth/data/sign_up_method_recorder.dart';
import 'package:flutter_starter_kit/features/terms/presentation/terms_notifier.dart';

class _MockCrashlyticsService extends Mock implements CrashlyticsService {}

class _MockFirestore extends Mock implements FirebaseFirestore {}

class _MockCollection extends Mock
    implements CollectionReference<Map<String, dynamic>> {}

class _MockDoc extends Mock
    implements DocumentReference<Map<String, dynamic>> {}

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
  });

  /// [mirrorTerms] 를 주입한 recorder 를 생성자로 직접 만든다 (R1~R4).
  SignUpMethodRecorder buildRecorder(
    Future<void> Function(String uid) mirrorTerms,
  ) {
    return SignUpMethodRecorder(
      firestore: mockFirestore,
      crashlytics: mockCrashlytics,
      mirrorTerms: mirrorTerms,
    );
  }

  /// 실제 [TermsNotifier] 를 쓰는 container 를 만든다 (R5 · R6).
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

  group('SignUpMethodRecorder — 생성자 주입 (R1~R4)', () {
    test('R1 약관 mirror 가 signUpProviderId set 보다 먼저 실행된다 (D-19)', () async {
      final calls = <String>[];
      when(
        () => mockDoc.set(any<Map<String, dynamic>>(), any<SetOptions>()),
      ).thenAnswer((_) async => calls.add('set'));
      final recorder = buildRecorder((uid) async => calls.add('mirror'));

      await recorder.record(uid: 'U1', providerId: 'password');

      expect(calls, <String>['mirror', 'set']);
    });

    test('R2 payload = {signUpProviderId} 한 필드 + merge: true', () async {
      final recorder = buildRecorder((uid) async {});

      await recorder.record(uid: 'U1', providerId: 'google.com');

      verify(() => mockFirestore.collection('users')).called(1);
      verify(() => mockCollection.doc('U1')).called(1);
      final captured = verify(
        () => mockDoc.set(captureAny(), captureAny()),
      ).captured;
      expect(captured[0], <String, dynamic>{'signUpProviderId': 'google.com'});
      expect((captured[1] as SetOptions).merge, isTrue);
      verifyNever(
        () => mockCrashlytics.recordError(
          any<Object>(),
          any<StackTrace?>(),
          reason: any(named: 'reason'),
          fatal: any(named: 'fatal'),
        ),
      );
    });

    test('R3 mirror 가 throw 해도 set 은 1회 · Crashlytics reason '
        'sign_up_method_terms_mirror 1회', () async {
      final recorder = buildRecorder(
        (uid) async => throw StateError('mirror failed'),
      );

      await expectLater(
        recorder.record(uid: 'U1', providerId: 'password'),
        completes,
      );

      verify(
        () => mockDoc.set(any<Map<String, dynamic>>(), any<SetOptions>()),
      ).called(1);
      verify(
        () => mockCrashlytics.recordError(
          any<Object>(),
          any<StackTrace?>(),
          reason: 'sign_up_method_terms_mirror',
          fatal: any(named: 'fatal'),
        ),
      ).called(1);
    });

    test('R4 set 이 permission-denied 로 throw 해도 흡수 — Crashlytics reason '
        'sign_up_method_record 1회 · record() 는 throw 0 (D-17)', () async {
      when(
        () => mockDoc.set(any<Map<String, dynamic>>(), any<SetOptions>()),
      ).thenThrow(
        FirebaseException(plugin: 'cloud_firestore', code: 'permission-denied'),
      );
      final recorder = buildRecorder((uid) async {});

      await expectLater(
        recorder.record(uid: 'U1', providerId: 'password'),
        completes,
      );

      verify(
        () => mockCrashlytics.recordError(
          any<Object>(),
          any<StackTrace?>(),
          reason: 'sign_up_method_record',
          fatal: any(named: 'fatal'),
        ),
      ).called(1);
    });
  });

  group('SignUpMethodRecorder × 실제 TermsNotifier (R5 · R6)', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
      // mirror skip 분기의 setCustomKey — Test 8 과 같은 inline stub.
      when(
        () => mockCrashlytics.setCustomKey(any(), any<Object>()),
      ).thenAnswer((_) async {});
    });

    test('R5 약관 set 이 가입 수단 set 보다 먼저 착지한다 — '
        'get → set(termsAccepted) → set(signUpProviderId) (D-19)', () async {
      when(() => mockDoc.get()).thenAnswer((_) async => mockSnapshot);
      when(() => mockSnapshot.exists).thenReturn(false);
      final container = createContainer();
      final notifier = container.read(termsProvider.notifier);
      await notifier.accept(service: true, privacy: true, marketing: false);

      final recorder = buildRecorder((uid) async {
        await container
            .read(termsProvider.notifier)
            .mirrorToFirestore(uid: uid);
      });

      await recorder.record(uid: 'U1', providerId: 'password');

      verifyInOrder([
        () => mockDoc.get(),
        () => mockDoc.set(
          any<Map<String, dynamic>>(
            that: containsPair('termsAccepted', anything),
          ),
          any<SetOptions>(),
        ),
        () => mockDoc.set(
          any<Map<String, dynamic>>(
            that: containsPair('signUpProviderId', 'password'),
          ),
          any<SetOptions>(),
        ),
      ]);
      verifyNever(
        () => mockCrashlytics.recordError(
          any<Object>(),
          any<StackTrace?>(),
          reason: any(named: 'reason'),
          fatal: any(named: 'fatal'),
        ),
      );
    });

    test('R6 오프라인 pre-read 실패(unavailable) — mirror Failure 여도 '
        'signUpProviderId set 1회 · throw 0', () async {
      when(() => mockDoc.get()).thenThrow(
        FirebaseException(plugin: 'cloud_firestore', code: 'unavailable'),
      );
      final container = createContainer();
      final notifier = container.read(termsProvider.notifier);
      await notifier.accept(service: true, privacy: true, marketing: false);

      final recorder = buildRecorder((uid) async {
        await container
            .read(termsProvider.notifier)
            .mirrorToFirestore(uid: uid);
      });

      await expectLater(
        recorder.record(uid: 'U1', providerId: 'password'),
        completes,
      );

      verify(
        () => mockCrashlytics.recordError(
          any<Object>(),
          any<StackTrace?>(),
          reason: 'terms_mirror_firestore',
          fatal: any(named: 'fatal'),
        ),
      ).called(1);
      verifyNever(
        () => mockDoc.set(
          any<Map<String, dynamic>>(
            that: containsPair('termsAccepted', anything),
          ),
          any<SetOptions>(),
        ),
      );
      verify(
        () => mockDoc.set(
          any<Map<String, dynamic>>(
            that: containsPair('signUpProviderId', 'password'),
          ),
          any<SetOptions>(),
        ),
      ).called(1);
    });
  });
}
