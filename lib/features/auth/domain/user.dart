import 'package:freezed_annotation/freezed_annotation.dart';

part 'user.freezed.dart';
part 'user.g.dart';

/// 인증된 사용자 정보 모델.
///
/// Firebase Auth 사용자 정보를 앱 도메인 모델로 변환한 불변 객체.
/// Phase 6(Email Auth)부터 실제 사용된다.
///
/// [copyWith], [==], [toJson], [fromJson]은 Freezed + json_serializable이
/// 자동 생성한다.
@freezed
abstract class User with _$User {
  /// 사용자 정보를 생성한다.
  const factory User({
    /// Firebase Auth UID.
    required String uid,

    /// 사용자 이메일 주소.
    required String email,

    /// 이메일 인증 완료 여부.
    required bool emailVerified,

    /// 표시 이름 (nullable -- 소셜 로그인 시 제공될 수 있음).
    String? displayName,

    /// 프로필 사진 URL (nullable).
    String? photoUrl,

    /// 계정 생성 시각.
    required DateTime createdAt,

    /// 연결된 인증 프로바이더 ID 목록 (예: 'google.com', 'password').
    @Default(<String>[]) List<String> providerIds,
  }) = _User;

  /// JSON에서 [User] 객체를 생성한다.
  factory User.fromJson(Map<String, dynamic> json) => _$UserFromJson(json);
}
