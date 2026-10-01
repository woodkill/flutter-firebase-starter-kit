import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:flutter_starter_kit/core/crashlytics/crashlytics_service.dart';
import 'package:flutter_starter_kit/core/error/app_exception.dart';
import 'package:flutter_starter_kit/core/error/result.dart';
import 'package:flutter_starter_kit/features/notifications/data/fcm_token_repository.dart';
import 'package:flutter_starter_kit/features/notifications/domain/fcm_token.dart';

class _MockCrashlyticsService extends Mock implements CrashlyticsService {}

class _MockFirestore extends Mock implements FirebaseFirestore {}

// cloud_firestore 의 CollectionReference / DocumentReference 는 sealed 클래스다.
// fake_cloud_firestore 의존성을 추가하지 않기 위해 mocktail Mock 으로 우회하며,
// sealed 경고는 테스트 한정 의도된 우회다 (terms_notifier_firestore_test 와 동일).
// ignore: subtype_of_sealed_class
class _MockRawCollection extends Mock
    implements CollectionReference<Map<String, dynamic>> {}

// ignore: subtype_of_sealed_class
class _MockRawDoc extends Mock
    implements DocumentReference<Map<String, dynamic>> {}

// ignore: subtype_of_sealed_class
class _MockTokenCollection extends Mock
    implements CollectionReference<FcmToken> {}

// ignore: subtype_of_sealed_class
class _MockTokenDoc extends Mock implements DocumentReference<FcmToken> {}

class _FakeSetOptions extends Fake implements SetOptions {}

class _FakeStackTrace extends Fake implements StackTrace {}

/// plan 02 `firestore.rules` 의 fcmTokens `hasOnly` 5키 (T-17-RULES-08).
const _rulesKeys = <String>{
  'token',
  'platform',
  'locale',
  'updatedAt',
  'expireAt',
};

void main() {
  final sampleToken = FcmToken.forDevice(
    token: 't1',
    platform: 'android',
    locale: 'ko',
    now: DateTime.utc(2026, 10),
  );

  setUpAll(() {
    registerFallbackValue(_FakeSetOptions());
    registerFallbackValue(_FakeStackTrace());
    registerFallbackValue(sampleToken);
    // mocktail 은 `element is T` 로 fallback 을 찾는다 — 파라미터 타입을
    // 명시한 함수 선언이라야 런타임 타입이 typedef 와 같아진다.
    FcmToken fromFallback(
      DocumentSnapshot<Map<String, dynamic>> _,
      SnapshotOptions? _,
    ) => throw UnimplementedError();
    Map<String, Object?> toFallback(FcmToken _, SetOptions? _) =>
        <String, Object?>{};
    registerFallbackValue(fromFallback);
    registerFallbackValue(toFallback);
  });

  late _MockCrashlyticsService mockCrashlytics;
  late _MockFirestore mockFirestore;
  late _MockRawCollection usersCollection;
  late _MockRawDoc userDoc;
  late _MockRawCollection rawTokens;
  late _MockTokenCollection typedTokens;
  late _MockTokenDoc tokenDoc;
  late FcmTokenRepository repository;
  ToFirestore<FcmToken>? capturedToFirestore;

  setUp(() {
    mockCrashlytics = _MockCrashlyticsService();
    mockFirestore = _MockFirestore();
    usersCollection = _MockRawCollection();
    userDoc = _MockRawDoc();
    rawTokens = _MockRawCollection();
    typedTokens = _MockTokenCollection();
    tokenDoc = _MockTokenDoc();
    capturedToFirestore = null;

    when(
      () => mockCrashlytics.recordError(
        any<Object>(),
        any<StackTrace?>(),
        reason: any(named: 'reason'),
        fatal: any(named: 'fatal'),
      ),
    ).thenAnswer((_) async {});

    when(() => mockFirestore.collection('users')).thenReturn(usersCollection);
    when(() => usersCollection.doc(any())).thenReturn(userDoc);
    when(() => userDoc.collection('fcmTokens')).thenReturn(rawTokens);
    when(
      () => rawTokens.withConverter<FcmToken>(
        fromFirestore: any(named: 'fromFirestore'),
        toFirestore: any(named: 'toFirestore'),
      ),
    ).thenAnswer((invocation) {
      final to = invocation.namedArguments[#toFirestore];
      if (to is ToFirestore<FcmToken>) capturedToFirestore = to;
      return typedTokens;
    });
    when(() => typedTokens.doc(any())).thenReturn(tokenDoc);
    when(
      () => tokenDoc.set(any<FcmToken>(), any<SetOptions>()),
    ).thenAnswer((_) async {});

    repository = FcmTokenRepository(
      firestore: mockFirestore,
      crashlytics: mockCrashlytics,
    );
  });

  group('Phase 17 FCM 토큰 저장소 (T-17-FCM)', () {
    test('T-17-FCM-02: forDevice 는 expireAt = now + 30일 · 직렬화 키 = rules '
        '5키 · 시각 값은 Timestamp', () {
      final token = FcmToken.forDevice(
        token: 't1',
        platform: 'android',
        locale: 'ko',
        now: DateTime.utc(2026, 10),
      );

      expect(kFcmTokenTtl, const Duration(days: 30));
      expect(token.updatedAt, DateTime.utc(2026, 10));
      expect(token.expireAt, DateTime.utc(2026, 10, 31));

      final json = token.toJson();
      expect(json.keys.toSet(), _rulesKeys);
      expect(json['token'], 't1');
      expect(json['platform'], 'android');
      expect(json['locale'], 'ko');
      expect(json['updatedAt'], isA<Timestamp>());
      expect(json['expireAt'], isA<Timestamp>());
    });

    test('T-17-FCM-02: normalizeFcmLocale 은 ko/en/ja 만 통과 · 그 밖은 en', () {
      expect(normalizeFcmLocale('ko'), 'ko');
      expect(normalizeFcmLocale('en'), 'en');
      expect(normalizeFcmLocale('ja'), 'ja');
      expect(normalizeFcmLocale('fr'), 'en');
      expect(normalizeFcmLocale(''), 'en');
    });

    test('T-17-FCM-02: forDevice 는 미지원 locale 을 en 으로 정규화한다', () {
      final token = FcmToken.forDevice(
        token: 't1',
        platform: 'ios',
        locale: 'fr',
        now: DateTime.utc(2026, 10),
      );

      expect(token.locale, 'en');
    });

    test('T-17-FCM-02: fromJson 왕복이 같은 값을 복원한다', () {
      expect(FcmToken.fromJson(sampleToken.toJson()), sampleToken);
    });

    test('T-17-FCM-03: upsert 는 users/{uid}/fcmTokens typed ref 의 '
        'doc(token) 에 set-merge 를 1회 부르고 Success', () async {
      final result = await repository.upsert(uid: 'u1', token: sampleToken);

      expect(result, isA<Success<void>>());
      verify(() => usersCollection.doc('u1')).called(1);
      verify(() => typedTokens.doc('t1')).called(1);
      final captured = verify(
        () => tokenDoc.set(sampleToken, captureAny<SetOptions>()),
      ).captured;
      expect(captured, hasLength(1));
      final options = captured.single;
      expect(options, isA<SetOptions>());
      expect((options as SetOptions).merge, isTrue);
      verifyNever(
        () => mockCrashlytics.recordError(
          any<Object>(),
          any<StackTrace?>(),
          reason: any(named: 'reason'),
          fatal: any(named: 'fatal'),
        ),
      );
    });

    test('T-17-FCM-03: withConverter toFirestore 가 rules 5키 map 을 만든다 '
        '(rules hasOnly 와 정확히 같음)', () async {
      await repository.upsert(uid: 'u1', token: sampleToken);

      final toFirestore = capturedToFirestore;
      expect(toFirestore, isNotNull);
      final written = toFirestore!(sampleToken, null);
      expect(written.keys.toSet(), _rulesKeys);
      expect(written['token'], 't1');
      expect(written['updatedAt'], isA<Timestamp>());
      expect(written['expireAt'], isA<Timestamp>());
    });

    test('T-17-FCM-03: set 실패 → Failure(UnknownException) · recordError '
        "1회(reason 'fcm_token_repository_upsert')", () async {
      when(
        () => tokenDoc.set(any<FcmToken>(), any<SetOptions>()),
      ).thenThrow(StateError('boom'));

      final result = await repository.upsert(uid: 'u1', token: sampleToken);

      expect(result, isA<Failure<void>>());
      expect((result as Failure<void>).exception, isA<UnknownException>());
      verify(
        () => mockCrashlytics.recordError(
          any<Object>(that: isA<StateError>()),
          any<StackTrace?>(),
          reason: 'fcm_token_repository_upsert',
          fatal: false,
        ),
      ).called(1);
    });
  });
}
