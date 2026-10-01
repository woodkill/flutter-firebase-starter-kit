// Phase 17 D-15 · D-17 · D-20 · D-41 — 프로필 사진 업로드 · 삭제 repository.
//
// 업로드 = 갤러리 1장 선택(리사이즈만 · 자르기 화면 없음) → Storage 단일 객체
// `users/{uid}/profile/avatar.jpg` 덮어쓰기 → downloadURL(+버전 쿼리) →
// Firestore `users/{uid}.customPhotoUrl` set-merge. 삭제 = Storage 객체 삭제
// (없으면 무시) → 필드 null. 표시 우선순위 합성은 `currentUserProvider`
// (plan 14)가 같은 문서 stream 으로 맡는다.
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image_picker_android/image_picker_android.dart';
import 'package:image_picker_platform_interface/image_picker_platform_interface.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/crashlytics/crashlytics_service.dart';
import '../../../core/error/app_exception.dart';
import '../../../core/error/guard_result.dart';
import '../../../core/error/result.dart';
import '../../../core/providers/firebase_providers.dart';

part 'profile_photo_repository.g.dart';

/// 프로필 사진 Storage 객체 경로를 돌려준다 (Phase 17 D-15).
///
/// 사용자당 단일 객체를 덮어쓴다(Pitfall 7 · 옛 사진 정리 불필요). 경로는
/// Storage rules(plan 06)와 탈퇴 cascade(plan 05)가 같은 값을 쓴다.
String profilePhotoPath(String uid) => 'users/$uid/profile/avatar.jpg';

/// 프로필 사진 업로드 · 삭제 repository (Phase 17 D-15 · D-17 · D-20 ①).
///
/// - 예상한 Firebase 실패([FirebaseException])는 [ProfilePhotoUploadException]
///   · [ProfilePhotoRemoveException] 으로 바꿔 돌려준다 — 기록 0 (분류된 실패).
/// - 그 밖의 예상치 못한 오류는 [guardResult] 가 Crashlytics 에 1회 기록하고
///   [UnknownException] 으로 돌려준다.
///
/// **PII 금지:** downloadURL · Storage 경로 · uid 를 로그 · reason 에 싣지
/// 않는다(T-17-56). reason 은 코드 경로 상수뿐이다.
class ProfilePhotoRepository {
  /// [ProfilePhotoRepository] 를 생성한다.
  ///
  /// [now] 는 캐시 버전 쿼리(`&v=`) 시각 — 테스트 주입용이며 기본값은
  /// [DateTime.now] 다.
  ProfilePhotoRepository({
    required FirebaseStorage storage,
    required FirebaseFirestore firestore,
    required ImagePicker picker,
    required CrashlyticsService crashlytics,
    DateTime Function()? now,
  }) : _storage = storage,
       _firestore = firestore,
       _picker = picker,
       _crashlytics = crashlytics,
       _now = now ?? DateTime.now;

  final FirebaseStorage _storage;
  final FirebaseFirestore _firestore;
  final ImagePicker _picker;
  final CrashlyticsService _crashlytics;
  final DateTime Function() _now;

  /// 갤러리에서 사진 1장을 골라 올리고 표시 URL 을 기록한다 (D-15 · D-17).
  ///
  /// - 선택 취소: Storage · Firestore 호출 0 · `Success(null)`.
  /// - 성공: `Success(<기록한 URL>)` — downloadURL 뒤에 `&v=<업로드 millis>`
  ///   를 붙여 저장한다. 같은 객체를 덮어써도 URL(캐시 키)이 바뀌어 설정 ·
  ///   홈이 재시작 없이 새 사진을 보인다(Pitfall 8).
  /// - `contentType: image/jpeg` 명시 — 미지정이면 rules 의 `image/.*` 검사를
  ///   통과하지 못할 수 있다(Pitfall 7). 크기 상한(5MB)은 rules 가 검사한다.
  Future<Result<String?>> pickAndUpload(String uid) {
    return guardResult<String?>('profile_photo_repository_upload', () async {
      // D-41 — 자르기 없이 업로드 전 리사이즈만(가로 1024 px · JPEG 품질 85).
      final picked = await _picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1024,
        imageQuality: 85,
      );
      if (picked == null) return null;
      try {
        final ref = _storage.ref(profilePhotoPath(uid));
        await ref.putFile(
          File(picked.path),
          SettableMetadata(contentType: 'image/jpeg'),
        );
        final downloadUrl = await ref.getDownloadURL();
        final url = '$downloadUrl&v=${_now().millisecondsSinceEpoch}';
        await _userDoc(uid).set(<String, Object?>{
          'customPhotoUrl': url,
        }, SetOptions(merge: true));
        return url;
      } on FirebaseException catch (e) {
        throw ProfilePhotoUploadException(cause: e);
      }
    }, crashlytics: _crashlytics);
  }

  /// 직접 올린 사진을 지운다 (D-17 · 확인 다이얼로그 없음 — UI-SPEC (P)).
  ///
  /// 순서 = Storage 객체 삭제 → `customPhotoUrl: null` set-merge. Storage 먼저 ·
  /// 필드 나중 = 재시도 안전 — 중간에 실패해도 필드가 남아 있으면 「올린 사진
  /// 삭제」 가 다시 보여 재시도할 수 있고, 객체가 이미 없으면(`object-not-found`)
  /// 무시하고 필드만 지운다(T-17-59). 필드가 지워지면 같은 문서 stream 재방출로
  /// 표시가 소셜 사진(또는 없음)으로 돌아간다.
  ///
  /// - Storage 의 그 밖 [FirebaseException] → [ProfilePhotoRemoveException]
  ///   (필드 write 0).
  /// - 필드 write [FirebaseException] → [ProfilePhotoRemoveException].
  Future<Result<void>> remove(String uid) {
    return guardResult<void>('profile_photo_repository_remove', () async {
      try {
        await _storage.ref(profilePhotoPath(uid)).delete();
      } on FirebaseException catch (e) {
        if (e.code != 'object-not-found') {
          throw ProfilePhotoRemoveException(cause: e);
        }
      }
      try {
        await _userDoc(uid).set(<String, Object?>{
          'customPhotoUrl': null,
        }, SetOptions(merge: true));
      } on FirebaseException catch (e) {
        throw ProfilePhotoRemoveException(cause: e);
      }
    }, crashlytics: _crashlytics);
  }

  /// `users/{uid}` 문서 참조.
  DocumentReference<Map<String, dynamic>> _userDoc(String uid) =>
      _firestore.collection('users').doc(uid);
}

/// 갤러리 선택기 [ImagePicker] Provider (Phase 17 D-15).
///
/// 생성 시 Android Photo Picker 를 1회 켠다 — 저장소 권한 요청 없이 사용자가
/// 고른 1장만 받는다(UI-SPEC (P) 「앱 권한 요청 없음」 · T-17-57).
@Riverpod(keepAlive: true)
ImagePicker imagePicker(Ref ref) {
  // Android 15 이하도 Photo Picker — 앱 권한 요청 0 · 16+ 는 항상.
  final platform = ImagePickerPlatform.instance;
  if (platform is ImagePickerAndroid) platform.useAndroidPhotoPicker = true;
  return ImagePicker();
}

/// [ProfilePhotoRepository] Provider (Phase 17 D-15).
@riverpod
ProfilePhotoRepository profilePhotoRepository(Ref ref) {
  return ProfilePhotoRepository(
    storage: ref.watch(firebaseStorageProvider),
    firestore: ref.watch(firebaseFirestoreProvider),
    picker: ref.watch(imagePickerProvider),
    crashlytics: ref.watch(crashlyticsServiceProvider),
  );
}
