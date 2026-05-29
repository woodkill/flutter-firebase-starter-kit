// Phase 16 Plan 16-06 / D-06 — DeleteUserRequest Freezed model.
//
// `deleteUserAccount` Cloud Function callable 의 request payload.
// 현재 idToken 단일 필드 (D-06 fresh ID Token freshness invariant).
// 향후 reauth credential 또는 confirm phrase 가 server-side 검증 의무로
// 도입되면 add-only 확장.
import 'package:freezed_annotation/freezed_annotation.dart';

part 'delete_user_request.freezed.dart';
part 'delete_user_request.g.dart';

/// 사용자 탈퇴 요청 모델 (Phase 16 D-06).
///
/// `deleteUserAccount` Cloud Function 의 request payload 로 사용된다.
/// 본 모델은 `SettingsRepository.requestAccountDeletion` 내부에서 inline
/// `{'idToken': idToken}` payload 와 직교한다 — JSON 직렬화 surface 가
/// 보존되어 server tier 가 향후 Freezed 기반 client SDK 도입 시 mirror
/// 가능.
@freezed
abstract class DeleteUserRequest with _$DeleteUserRequest {
  /// 탈퇴 요청을 생성한다.
  const factory DeleteUserRequest({
    /// 최근 재인증으로 발급된 Firebase ID Token (D-07 재인증 의무).
    required String idToken,
  }) = _DeleteUserRequest;

  /// JSON 으로부터 [DeleteUserRequest] 를 생성한다.
  factory DeleteUserRequest.fromJson(Map<String, dynamic> json) =>
      _$DeleteUserRequestFromJson(json);
}
