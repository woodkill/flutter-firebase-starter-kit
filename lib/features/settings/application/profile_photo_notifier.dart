// Phase 17 D-15 · D-20 ② — 프로필 사진 업로드 · 삭제 진행 상태 Notifier.
//
// state = 진행 중(busy) 여부. 진행 중에는 설정 사진 행이 비활성 · 진행 링을
// 그린다. 본문은 guardAsyncValue 로 감싸 repository 밖에서 throw 된
// 예상치 못한 오류도 1회 기록하고 `failed` 로 끝낸다(busy 해제는 finally).
import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/crashlytics/crashlytics_service.dart';
import '../../../core/error/guard_result.dart';
import '../../../core/error/result.dart';
import '../../../core/providers/firebase_providers.dart';
import '../data/profile_photo_repository.dart';

part 'profile_photo_notifier.g.dart';

/// 프로필 사진 동작 결과 (Phase 17 D-15 · UI-SPEC (P) 흐름).
enum ProfilePhotoActionResult {
  /// 업로드 · 삭제 성공 — 성공 SnackBar.
  success,

  /// 사용자가 갤러리 선택을 취소했거나 이미 진행 중 — 아무 표시 없음.
  cancelled,

  /// 실패 — 실패 SnackBar · 행은 이전 상태.
  failed,
}

/// 프로필 사진 업로드 · 삭제 Notifier (Phase 17 D-15 · D-20 ②).
///
/// state 는 진행 중(busy) 여부다. 정식(비익명) 사용자만 동작한다 — 그 밖은
/// repository 호출 없이 [ProfilePhotoActionResult.failed].
@riverpod
class ProfilePhotoNotifier extends _$ProfilePhotoNotifier {
  @override
  bool build() => false;

  /// 갤러리에서 사진을 골라 올린다 (D-15).
  ///
  /// 본문은 [guardAsyncValue] 로 감싼다 — repository 의 `Result` 실패는
  /// throw 가 아니라 기록 0, 그 밖에서 throw 된 non-AppException 은 1회 기록
  /// (D-20 ②). 진행 중 재호출은 [ProfilePhotoActionResult.cancelled].
  Future<ProfilePhotoActionResult> pickAndUpload() async {
    if (state) return ProfilePhotoActionResult.cancelled;
    final crashlytics = ref.read(crashlyticsServiceProvider);
    state = true;
    try {
      final result = await guardAsyncValue<ProfilePhotoActionResult>(
        () async {
          final uid = _currentRegularUid();
          if (uid == null) return ProfilePhotoActionResult.failed;
          final outcome = await ref
              .read(profilePhotoRepositoryProvider)
              .pickAndUpload(uid);
          return switch (outcome) {
            Success(data: null) => ProfilePhotoActionResult.cancelled,
            Success() => ProfilePhotoActionResult.success,
            Failure() => ProfilePhotoActionResult.failed,
          };
        },
        reason: 'profile_photo_notifier_upload',
        crashlytics: crashlytics,
      );
      return _resultOf(result);
    } finally {
      if (ref.mounted) state = false;
    }
  }

  /// 현재 정식(비익명) 사용자 uid — 로그인 전 · 게스트 · 미초기화면 null.
  String? _currentRegularUid() {
    final fb.User? user = ref.read(authStateProvider).value;
    if (user == null || user.isAnonymous) return null;
    return user.uid;
  }
}

/// guard 결과를 동작 결과로 바꾼다 — error 는 [ProfilePhotoActionResult.failed].
ProfilePhotoActionResult _resultOf(AsyncValue<ProfilePhotoActionResult> v) =>
    switch (v) {
      AsyncData(:final value) => value,
      _ => ProfilePhotoActionResult.failed,
    };
