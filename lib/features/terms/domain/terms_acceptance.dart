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

/// 서버 `TermsAcceptanceJson` 계약용 직렬화 (Phase 16 CR-01 / WR-05).
extension TermsAcceptanceServerJson on TermsAcceptance {
  /// Custom Token callable payload 로 보낼 5 키 JSON 을 만든다.
  ///
  /// [toJson] 을 그대로 쓰면 안 된다 — `TermsNotifier.accept` 가 만드는
  /// [acceptedAt] 은 local `DateTime` 이고, Dart 의 `toIso8601String()` 은
  /// UTC 가 아닌 `DateTime` 에 타임존 지시자를 붙이지 않는다. 서버
  /// (Cloud Functions, TZ=UTC) 는 offset 없는 문자열을 UTC 로 해석하므로
  /// local offset 만큼 어긋난 시각이 기록된다 (KST 기준 +9시간, 미래 시각).
  ///
  /// 따라서 직렬화 시점에 [DateTime.toUtc] 로 정규화해 항상 `Z` 접미
  /// (절대 instant) 문자열을 산출한다.
  ///
  /// **본 확장이 유일한 producer 다 (WR-05).** `TermsNotifier` 의 payload
  /// 경로와 계약 sentinel 테스트가 모두 이 메서드를 통과하므로, 모델에
  /// 6번째 필드가 추가되면 sentinel 이 즉시 FAIL 한다 (손으로 쓴 fixture 는
  /// 그 변화를 감지하지 못했다).
  Map<String, dynamic> toServerJson() =>
      copyWith(acceptedAt: acceptedAt.toUtc()).toJson();
}
