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
import 'package:flutter/foundation.dart';
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

/// 프로필 사진 업로드 최대 크기(바이트) — `storage.rules` 의
/// `request.resource.size <= 5 * 1024 * 1024` 와 짝이다 (리뷰 IN-18).
///
/// 업로드 전에 이 값으로 먼저 걸러 전송 뒤 거부되는 왕복을 없앤다. 규칙을
/// 바꾸면 이 값도 같이 고친다(T-17-PHOTO-07 이 두 값을 대조한다).
const int kProfilePhotoMaxBytes = 5 * 1024 * 1024;

/// 이미지 파일 앞 [header] 바이트(매직 넘버)로 MIME 타입을 판정한다
/// (리뷰 IN-18). JPEG · PNG · GIF 만 알아보고 그 밖은 `null` 이다.
///
/// image_picker 1.2.3 이 돌려주는 [XFile] 은 Android · iOS 모두 `XFile(path)`
/// 로 만들어져 [XFile.mimeType] 이 항상 `null` 이고(cross_file `io.dart` —
/// 경로에서 추론하지 않는다), Android 리사이즈는 알파가 있으면 PNG 로 다시
/// 쓰면서 파일 이름 확장자는 원본 그대로 둔다(image_picker_android
/// `ImageResizer.java`). 그래서 확장자 · `mimeType` 대신 바이트로 본다. 리사이즈
/// 결과는 Android = JPEG · PNG, iOS = JPEG · PNG · GIF 다.
@visibleForTesting
String? sniffImageContentType(List<int> header) {
  bool startsWith(List<int> magic) {
    if (header.length < magic.length) return false;
    for (var i = 0; i < magic.length; i++) {
      if (header[i] != magic[i]) return false;
    }
    return true;
  }

  if (startsWith(const [0xFF, 0xD8, 0xFF])) return 'image/jpeg';
  if (startsWith(const [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])) {
    return 'image/png';
  }
  if (startsWith(const [0x47, 0x49, 0x46, 0x38])) return 'image/gif';
  return null;
}

/// [sniffImageContentType] 에 넘길 머리 바이트 수 (PNG 서명 8바이트).
const int _kImageHeaderLength = 8;

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
  /// - `contentType` 명시 — 미지정이면 rules 의 `image/.*` 검사를 통과하지
  ///   못할 수 있다(Pitfall 7). 값은 파일 앞 바이트로 판정한다(JPEG · PNG ·
  ///   GIF → [XFile.mimeType] → `image/jpeg` 순 · [sniffImageContentType] ·
  ///   리뷰 IN-18).
  /// - 크기 상한([kProfilePhotoMaxBytes] = 5MB)을 업로드 **전에** 검사한다 —
  ///   넘으면 Storage · Firestore 호출 없이 [ProfilePhotoUploadException]
  ///   (기록 0). rules 도 같은 상한을 검사한다.
  ///
  /// **부분 실패 (리뷰 IN-19):** `putFile` 은 성공했는데 `getDownloadURL` 또는
  /// 필드 `set` 이 실패하면 Storage 에는 새 사진, Firestore 에는 옛 URL(또는
  /// null)이 남는다. 보상 처리는 하지 않는다 — 객체가 사용자당 1개 덮어쓰기
  /// (D-15)라 다음 업로드가 두 쪽을 다시 맞추고(재업로드로 수렴), 탈퇴
  /// cascade(D-40)가 prefix 를 통째로 지운다. 화면은 실패 SnackBar 를 띄운다.
  ///
  /// **Android 선택 결과 유실 (리뷰 IN-20 · 구현하지 않음):** 갤러리가 떠 있는
  /// 동안 메모리 압박으로 MainActivity 가 파괴되면 `pickImage` 결과는 사라지고
  /// 앱이 다시 시작될 때 `ImagePicker.retrieveLostData()`(Android 전용)로만
  /// 회수된다(image_picker 1.2.3 `pickImage` 문서). 킷은 이를 회수하지 않아
  /// 사용자는 피드백 없이 「없음」 으로 돌아온다. 필요하면 설정 화면 진입 때
  /// `retrieveLostData()` 를 1회 확인해 `file != null` 이면 업로드를 이어간다
  /// (매뉴얼 커스터마이징 포인트).
  Future<Result<String?>> pickAndUpload(String uid) {
    return guardResult<String?>('profile_photo_repository_upload', () async {
      // D-41 — 자르기 없이 업로드 전 리사이즈만(가로 1024 px · JPEG 품질 85).
      final picked = await _picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1024,
        imageQuality: 85,
      );
      if (picked == null) return null;
      final size = await picked.length();
      if (size > kProfilePhotoMaxBytes) {
        throw const ProfilePhotoUploadException();
      }
      final contentType = await _resolveContentType(picked, size);
      try {
        final ref = _storage.ref(profilePhotoPath(uid));
        await ref.putFile(
          File(picked.path),
          SettableMetadata(contentType: contentType),
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

  /// [picked] 의 업로드 contentType 을 정한다 — 앞 바이트 판정 →
  /// [XFile.mimeType] → `image/jpeg` 순 (리뷰 IN-18).
  Future<String> _resolveContentType(XFile picked, int size) async {
    final headerLength = size < _kImageHeaderLength
        ? size
        : _kImageHeaderLength;
    final header = <int>[];
    if (headerLength > 0) {
      await picked.openRead(0, headerLength).forEach(header.addAll);
    }
    return sniffImageContentType(header) ?? picked.mimeType ?? 'image/jpeg';
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
