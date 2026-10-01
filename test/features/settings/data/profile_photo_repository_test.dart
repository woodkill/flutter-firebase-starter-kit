// Phase 17 Plan 17-17 — ProfilePhotoRepository 단위 테스트 (T-17-PHOTO).
//
// - T-17-PHOTO-01: 갤러리 선택 → putFile(image/jpeg) → downloadURL(+v) →
//   customPhotoUrl set-merge · 취소 = 호출 0 · 리사이즈 인자.
// - T-17-PHOTO-02: Firebase 실패 = ProfilePhotoUploadException(기록 0) ·
//   예상치 못한 오류 = UnknownException(기록 1 · reason 상수).
import 'dart:async';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mocktail/mocktail.dart';

import 'package:flutter_starter_kit/core/crashlytics/crashlytics_service.dart';
import 'package:flutter_starter_kit/core/error/app_exception.dart';
import 'package:flutter_starter_kit/core/error/result.dart';
import 'package:flutter_starter_kit/features/settings/data/profile_photo_repository.dart';

class _MockCrashlyticsService extends Mock implements CrashlyticsService {}

class _MockStorage extends Mock implements FirebaseStorage {}

class _MockReference extends Mock implements Reference {}

class _MockPicker extends Mock implements ImagePicker {}

class _MockFirestore extends Mock implements FirebaseFirestore {}

// cloud_firestore 의 CollectionReference / DocumentReference 는 sealed 클래스다.
// fake_cloud_firestore 의존성을 추가하지 않기 위해 mocktail Mock 으로 우회하며,
// sealed 경고는 테스트 한정 의도된 우회다 (fcm_token_repository_test 와 동일).
// ignore: subtype_of_sealed_class
class _MockCollection extends Mock
    implements CollectionReference<Map<String, dynamic>> {}

// ignore: subtype_of_sealed_class
class _MockDoc extends Mock
    implements DocumentReference<Map<String, dynamic>> {}

class _FakeSetOptions extends Fake implements SetOptions {}

class _FakeStackTrace extends Fake implements StackTrace {}

class _FakeTaskSnapshot extends Fake implements TaskSnapshot {}

/// [UploadTask] 대체 — `await` 가 부르는 [then] 만 실제 Future 로 위임한다.
class _FakeUploadTask extends Fake implements UploadTask {
  _FakeUploadTask(this._future);

  final Future<TaskSnapshot> _future;

  @override
  Future<R> then<R>(
    FutureOr<R> Function(TaskSnapshot value) onValue, {
    Function? onError,
  }) => _future.then(onValue, onError: onError);
}

/// downloadURL fixture — 실제 형식(`?alt=media&token=`)을 흉내 낸 합성 값.
const String _kDownloadUrl =
    'https://firebasestorage.googleapis.com/v0/b/demo/o/avatar?alt=media&token=t';

/// 업로드 시각 fixture — 버전 쿼리 값.
final DateTime _kNow = DateTime.utc(2026, 10, 1, 9);

void main() {
  setUpAll(() {
    registerFallbackValue(_FakeSetOptions());
    registerFallbackValue(_FakeStackTrace());
    registerFallbackValue(File('fallback.jpg'));
    registerFallbackValue(SettableMetadata());
    registerFallbackValue(ImageSource.gallery);
  });

  late _MockCrashlyticsService crashlytics;
  late _MockStorage storage;
  late _MockReference reference;
  late _MockPicker picker;
  late _MockFirestore firestore;
  late _MockCollection users;
  late _MockDoc userDoc;
  late ProfilePhotoRepository repository;

  /// pickImage stub — [file] 을 돌려준다 (null = 선택 취소).
  void stubPick(XFile? file) {
    when(
      () => picker.pickImage(
        source: any(named: 'source'),
        maxWidth: any(named: 'maxWidth'),
        imageQuality: any(named: 'imageQuality'),
      ),
    ).thenAnswer((_) async => file);
  }

  setUp(() {
    crashlytics = _MockCrashlyticsService();
    storage = _MockStorage();
    reference = _MockReference();
    picker = _MockPicker();
    firestore = _MockFirestore();
    users = _MockCollection();
    userDoc = _MockDoc();

    when(
      () => crashlytics.recordError(
        any<Object>(),
        any<StackTrace?>(),
        reason: any(named: 'reason'),
        fatal: any(named: 'fatal'),
      ),
    ).thenAnswer((_) async {});
    when(() => storage.ref(any())).thenReturn(reference);
    when(
      () => reference.putFile(any(), any()),
    ).thenAnswer((_) => _FakeUploadTask(Future.value(_FakeTaskSnapshot())));
    when(
      () => reference.getDownloadURL(),
    ).thenAnswer((_) async => _kDownloadUrl);
    when(() => firestore.collection('users')).thenReturn(users);
    when(() => users.doc(any())).thenReturn(userDoc);
    when(() => userDoc.set(any(), any())).thenAnswer((_) async {});

    repository = ProfilePhotoRepository(
      storage: storage,
      firestore: firestore,
      picker: picker,
      crashlytics: crashlytics,
      now: () => _kNow,
    );
  });

  group('Phase 17 프로필 사진 (T-17-PHOTO)', () {
    test('T-17-PHOTO-01: 선택 → putFile(image/jpeg) → downloadURL(+v) → '
        'customPhotoUrl set-merge · Success(url)', () async {
      stubPick(XFile('/tmp/picked.jpg'));

      final result = await repository.pickAndUpload('u1');

      final expectedUrl = '$_kDownloadUrl&v=${_kNow.millisecondsSinceEpoch}';
      expect(result, isA<Success<String?>>());
      expect((result as Success<String?>).data, expectedUrl);

      // 리사이즈 인자 = 갤러리 · 가로 1024 · 품질 85 (D-41).
      verify(
        () => picker.pickImage(
          source: ImageSource.gallery,
          maxWidth: 1024,
          imageQuality: 85,
        ),
      ).called(1);
      // 경로 = 사용자당 단일 객체.
      verify(() => storage.ref('users/u1/profile/avatar.jpg')).called(1);
      final captured = verify(
        () => reference.putFile(captureAny(), captureAny()),
      ).captured;
      expect((captured[0] as File).path, '/tmp/picked.jpg');
      expect((captured[1] as SettableMetadata).contentType, 'image/jpeg');
      verify(() => reference.getDownloadURL()).called(1);
      // users/u1 에 customPhotoUrl 만 merge set 1회.
      verify(() => users.doc('u1')).called(1);
      final setArgs = verify(
        () => userDoc.set(captureAny(), captureAny()),
      ).captured;
      expect(setArgs[0], <String, Object?>{'customPhotoUrl': expectedUrl});
      expect((setArgs[1] as SetOptions).merge, isTrue);
      verifyNever(
        () => crashlytics.recordError(
          any<Object>(),
          any<StackTrace?>(),
          reason: any(named: 'reason'),
          fatal: any(named: 'fatal'),
        ),
      );
    });

    test('T-17-PHOTO-01: 선택 취소 — putFile · set 0 · Success(null)', () async {
      stubPick(null);

      final result = await repository.pickAndUpload('u1');

      expect(result, isA<Success<String?>>());
      expect((result as Success<String?>).data, isNull);
      verifyNever(() => storage.ref(any()));
      verifyNever(() => reference.putFile(any(), any()));
      verifyNever(() => userDoc.set(any(), any()));
    });

    test('T-17-PHOTO-02: putFile FirebaseException → '
        'Failure(ProfilePhotoUploadException) · 기록 0 · set 0', () async {
      stubPick(XFile('/tmp/picked.jpg'));
      when(() => reference.putFile(any(), any())).thenAnswer(
        (_) => _FakeUploadTask(
          Future<TaskSnapshot>.error(
            FirebaseException(plugin: 'firebase_storage', code: 'unauthorized'),
          ),
        ),
      );

      final result = await repository.pickAndUpload('u1');

      expect(result, isA<Failure<String?>>());
      final exception = (result as Failure<String?>).exception;
      expect(exception, isA<ProfilePhotoUploadException>());
      expect(exception.cause, isA<FirebaseException>());
      verifyNever(() => userDoc.set(any(), any()));
      verifyNever(
        () => crashlytics.recordError(
          any<Object>(),
          any<StackTrace?>(),
          reason: any(named: 'reason'),
          fatal: any(named: 'fatal'),
        ),
      );
    });

    test('T-17-PHOTO-02: 예상치 못한 StateError → Failure(UnknownException) · '
        '기록 1회(reason profile_photo_repository_upload)', () async {
      stubPick(XFile('/tmp/picked.jpg'));
      when(() => reference.getDownloadURL()).thenThrow(StateError('boom'));

      final result = await repository.pickAndUpload('u1');

      expect(result, isA<Failure<String?>>());
      expect((result as Failure<String?>).exception, isA<UnknownException>());
      verify(
        () => crashlytics.recordError(
          any<Object>(that: isA<StateError>()),
          any<StackTrace?>(),
          reason: 'profile_photo_repository_upload',
          fatal: false,
        ),
      ).called(1);
      verifyNever(() => userDoc.set(any(), any()));
    });
  });
}
