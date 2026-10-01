import 'package:freezed_annotation/freezed_annotation.dart';

part 'user.freezed.dart';
part 'user.g.dart';

/// 인증된 사용자 정보 모델.
///
/// Firebase Auth 사용자 정보를 앱 도메인 모델로 변환한 불변 객체.
/// Phase 6(Email Auth)부터 실제 사용된다.
///
/// **providerIds 의미 변경 (Phase 12 D-15 / D-16):**
/// - Phase 6~9: Firebase `providerData[].providerId` 만 (`'google.com'` /
///   `'apple.com'` / `'facebook.com'` / `'password'` — OAuth URI 형식).
/// - Phase 12+: Firebase `providerData[].providerId` ∪ Firestore
///   `users/{uid}.linkedProviders[].providerId` (Custom Token slug —
///   `'kakao'` 등) 합집합 (Set 기반 중복 제거).
/// - 매핑 책임: `lib/shared/auth/provider_label_formatter.dart`
///   의 `formatProviderIds` 헬퍼가 slug + URI 양 형식을 모두 인식한다.
///
/// 합집합 로직은 `currentUserProvider` (auth_repository.dart) 가 수행하며,
/// User 모델 자체는 단순 데이터 보유자로 유지된다 (Freezed 정의 변경 없음).
///
/// **Phase 16.7 — 가입 수단 [signUpProviderId] (D-11 · D-13 · D-28):**
/// 계정을 처음 확정한 수단(가입 수단)은 Firebase `providerData` 와 무관하다
/// — `providerData` 순서나 연결 시각으로 추론하지 않는다. 진실원은 Firestore
/// `users/{uid}.signUpProviderId` 하나이며, `currentUserProvider` 가
/// `linkedProvidersStream` 의 같은 snapshot 에서 함께 읽어 채운다.
/// `_mapFirebaseUser` (auth_repository.dart) 는 이 필드를 채우지 않는다.
///
/// [copyWith], [==], [toJson], [fromJson]은 Freezed + json_serializable이
/// 자동 생성한다.
@freezed
abstract class User with _$User {
  /// 사용자 정보를 생성한다.
  const factory User({
    /// Firebase Auth UID.
    required String uid,

    /// 사용자 이메일 주소. null = 이메일 없음(익명 · 이메일을 주지 않는
    /// Custom Token 사용자) — firebase_auth `User.email` 과 같은 계약
    /// (quick 260928-fp6 D-02). 표시 층은 `?? '-'` 로 받는다(D-01).
    String? email,

    /// 이메일 인증 완료 여부.
    required bool emailVerified,

    /// 표시 이름 (nullable -- 소셜 로그인 시 제공될 수 있음).
    String? displayName,

    /// 표시용 프로필 사진 URL (nullable).
    ///
    /// Phase 17 D-17 — 표시 사진 = [customPhotoUrl] > Auth `photoURL` >
    /// `providerData` 사진. `currentUserProvider` 가 합성한 결과이며,
    /// `_mapFirebaseUser` 단독 결과(Auth top-level 값)와 다를 수 있다.
    String? photoUrl,

    /// 계정 생성 시각.
    required DateTime createdAt,

    /// 연결된 인증 프로바이더 ID 목록 (예: 'google.com', 'password').
    @Default(<String>[]) List<String> providerIds,

    /// 가입 수단 providerId (Phase 16.7 D-13 · D-28).
    ///
    /// 값 형식은 [providerIds] 와 같다 (`'password'` · `'google.com'` ·
    /// `'kakao'` 등). null = 기록 없음 (D-11 — 옛 계정 · Firestore 읽기 실패 ·
    /// 첫 emit 전 과도 상태). 원천은 Firestore `users/{uid}.signUpProviderId`
    /// 뿐이며 추론 · backfill 하지 않는다.
    String? signUpProviderId,

    /// 사용자가 직접 올린 사진 URL (Phase 17 D-17).
    ///
    /// 원천은 Firestore `users/{uid}.customPhotoUrl` 이다. null = 업로드
    /// 사진 없음. [photoUrl] 은 이 값이 있으면 이 값이다(표시 우선순위
    /// 합성 결과 — `currentUserProvider`).
    String? customPhotoUrl,
  }) = _User;

  /// JSON에서 [User] 객체를 생성한다.
  factory User.fromJson(Map<String, dynamic> json) => _$UserFromJson(json);
}
