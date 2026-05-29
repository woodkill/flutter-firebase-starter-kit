// Phase 16 Plan 16-06 본체 채움 — Wave 0 sentinel placeholder.
//
// `DeleteUserRequest` 는 `deleteUserAccount` Cloud Function callable 의
// request payload 모델. Plan 16-06 이 idToken 외 추가 필드 (예: confirmText,
// reauthCredential) 를 add-only 로 확장한다.
import 'package:freezed_annotation/freezed_annotation.dart';

part 'delete_user_request.freezed.dart';
part 'delete_user_request.g.dart';

/// 사용자 탈퇴 요청 모델 (Phase 16 D-06).
///
/// `deleteUserAccount` Cloud Function 의 request payload 로 사용된다.
/// Plan 16-06 이 본체 (재인증 토큰 + 확인 텍스트) 를 add-only 로 확장한다.
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
