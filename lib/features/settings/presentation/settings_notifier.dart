// Phase 16 Plan 16-06 본체 채움 — Wave 0 sentinel placeholder.
//
// `SettingsNotifier` 는 탈퇴 진행 상태 (AsyncValue<void>) 를 관리하는
// Riverpod controller. Plan 16-06 이 본체 (requestAccountDeletion 의
// 재인증 + Cloud Function 호출 + 라우팅) 를 add-only 로 확장한다.
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'settings_notifier.g.dart';

/// 사용자 설정 화면의 상태 관리자 (Phase 16 D-06).
///
/// **Wave 0 sentinel placeholder** — Plan 16-06 이 본체 채움.
@riverpod
class SettingsNotifier extends _$SettingsNotifier {
  @override
  AsyncValue<void> build() {
    return const AsyncValue<void>.data(null);
  }

  /// 사용자 탈퇴를 요청한다 (Phase 16 D-06 / D-07).
  ///
  /// Plan 16-06 이 본체 (재인증 → deleteAccount → 라우팅) 를 채운다.
  Future<void> requestAccountDeletion() {
    throw UnimplementedError(
      'Phase 16 Plan 16-06 implementation pending',
    );
  }
}
