import 'package:freezed_annotation/freezed_annotation.dart';

part 'terms_acceptance.freezed.dart';
part 'terms_acceptance.g.dart';

/// 약관 동의 정보를 담는 불변 모델 (Phase 10 D-15, D-17).
///
/// SharedPreferences 영속화 및 Firestore `users/{uid}/termsAccepted`
/// 미러링의 source of truth 이다 (D-16, WARNING #16).
///
/// [toJson] / [fromJson] 왕복으로 cold-start 후에도 정확한 값을 복원하여
/// `TermsNotifier.mirrorToFirestore` 가 올바른 데이터를 기록한다.
@freezed
abstract class TermsAcceptance with _$TermsAcceptance {
  /// 약관 동의 정보를 생성한다.
  const factory TermsAcceptance({
    /// 약관 버전. [TermsNotifier.currentVersion] 과 매칭하여 구 버전 데이터를
    /// 무효 처리할 수 있도록 보관한다.
    required int version,

    /// 이용약관 동의 여부 (필수).
    required bool service,

    /// 개인정보처리방침 동의 여부 (필수).
    required bool privacy,

    /// 마케팅 정보 수신 동의 여부 (선택).
    required bool marketing,

    /// 사용자 동의 시각. Firestore 미러 시 `Timestamp.fromDate` 로 저장.
    required DateTime acceptedAt,
  }) = _TermsAcceptance;

  /// JSON 에서 [TermsAcceptance] 객체를 생성한다 (WARNING #16 왕복용).
  factory TermsAcceptance.fromJson(Map<String, dynamic> json) =>
      _$TermsAcceptanceFromJson(json);
}
