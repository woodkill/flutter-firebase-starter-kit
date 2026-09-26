// Phase 16.8 D-01 · D-04 — UnlinkProviderRequest Freezed model.
//
// `unlinkCustomTokenProvider` Cloud Function callable 의 request payload.
// 필드는 해제할 Custom Token provider slug 하나뿐이다 — uid 는 서버가
// `request.auth` 에서 읽으므로 클라이언트가 보내지 않는다.
//
// 10-REVIEW WR-17 관례: 본 모델은 `AuthRepository.unlinkCustomTokenProvider`
// 의 **유일한 payload 생성 경로**다.
import 'package:freezed_annotation/freezed_annotation.dart';

part 'unlink_provider_request.freezed.dart';
part 'unlink_provider_request.g.dart';

/// Custom Token provider 연결 해제 요청 모델 (Phase 16.8 D-01 · D-04).
///
/// `unlinkCustomTokenProvider` Cloud Function 의 request payload 로 사용된다.
///
/// **WR-17:** `AuthRepository.unlinkCustomTokenProvider` 가 본 모델의
/// [toJson] 으로만 payload 를 만든다. 서버 `request.data.provider` 키와
/// 1:1 이며, 필드를 추가/변경하면 실제 전송 payload 가 함께 바뀐다.
@freezed
abstract class UnlinkProviderRequest with _$UnlinkProviderRequest {
  /// 해제 요청을 생성한다.
  const factory UnlinkProviderRequest({
    /// 해제할 Custom Token provider slug (예: `kakao` · `line`).
    required String provider,
  }) = _UnlinkProviderRequest;

  /// JSON 으로부터 [UnlinkProviderRequest] 를 생성한다.
  factory UnlinkProviderRequest.fromJson(Map<String, dynamic> json) =>
      _$UnlinkProviderRequestFromJson(json);
}
