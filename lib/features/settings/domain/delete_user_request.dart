// Phase 16 Plan 16-06 / D-06 — DeleteUserRequest Freezed model.
//
// `deleteUserAccount` Cloud Function callable 의 request payload.
// 현재 idToken 단일 필드 (D-06 fresh ID Token freshness invariant).
// 향후 reauth credential 또는 confirm phrase 가 server-side 검증 의무로
// 도입되면 add-only 확장.
//
// 10-REVIEW WR-17: 본 모델은 `SettingsRepository.requestAccountDeletion` 의
// **유일한 payload 생성 경로**다 (이전에는 정의만 있고 호출자가 0이었다).
import 'package:freezed_annotation/freezed_annotation.dart';

part 'delete_user_request.freezed.dart';
part 'delete_user_request.g.dart';

/// 사용자 탈퇴 요청 모델 (Phase 16 D-06).
///
/// `deleteUserAccount` Cloud Function 의 request payload 로 사용된다.
///
/// **WR-17:** `SettingsRepository.requestAccountDeletion` 이 본 모델의
/// [toJson] 으로만 payload 를 만든다. 이전에는 repository 가
/// `{'idToken': idToken}` 를 손으로 만들고 본 모델은 어디서도 참조되지
/// 않아, 서버가 필드를 추가해도 모델이 조용히 낡고 컴파일러 경고도 나오지
/// 않았다 — 계약 타입이 실제 전송 경로를 전혀 보증하지 못하는 상태였다.
/// 필드를 추가/변경하면 실제 전송 payload 가 함께 바뀐다.
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
