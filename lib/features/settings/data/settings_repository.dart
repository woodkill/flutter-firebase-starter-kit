// Phase 16 Plan 16-06 본체 채움 — Wave 0 sentinel placeholder.
//
// `SettingsRepository` 는 `deleteUserAccount` Cloud Function callable 을
// 호출하는 wrapper. Plan 16-06 이 본체 (cloud_functions httpsCallable +
// HttpsError → AppException 매핑) 를 add-only 로 확장한다.
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../domain/delete_user_request.dart';

part 'settings_repository.g.dart';

/// 사용자 설정 (탈퇴 등) 관련 Repository.
///
/// **Wave 0 sentinel placeholder** — Plan 16-06 이 본체 채움.
///
/// 본체 구현 시 mirror source: `lib/features/auth/data/auth_repository.dart`
/// (Phase 6+) — cloud_functions httpsCallable + HttpsError → AppException
/// 매핑 패턴 재사용.
class SettingsRepository {
  /// [SettingsRepository] 를 생성한다.
  const SettingsRepository();

  /// 사용자 계정을 탈퇴 처리한다 (Phase 16 D-06).
  ///
  /// Plan 16-06 이 본체 (deleteUserAccount Cloud Function 호출 + HttpsError
  /// 매핑) 를 채운다.
  Future<void> deleteAccount(DeleteUserRequest request) {
    throw UnimplementedError(
      'Phase 16 Plan 16-06 implementation pending',
    );
  }
}

/// [SettingsRepository] 의 단일 인스턴스를 제공한다 (Wave 0 sentinel).
@Riverpod(keepAlive: true)
SettingsRepository settingsRepository(Ref ref) {
  return const SettingsRepository();
}
