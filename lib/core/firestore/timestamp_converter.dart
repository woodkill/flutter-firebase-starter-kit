import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:json_annotation/json_annotation.dart';

/// Firestore [Timestamp] ↔ [DateTime] JSON 변환기.
///
/// Phase 17 — see ROADMAP.md (D-14). Freezed 모델 필드에
/// `@TimestampConverter()` 를 붙이면 `toJson` 이 [Timestamp] 를, `fromJson`
/// 이 UTC [DateTime] 을 만든다. `withConverter` 와 함께 쓰는 typed 경로의
/// 예제다 — raw map 에 `Timestamp.fromDate` 를 직접 넣는 `terms_notifier` 와
/// 대비된다.
///
/// `fromJson` 은 항상 UTC 로 돌려준다 — 기기 타임존과 무관하게 같은 instant 를
/// 비교 · 직렬화하기 위해서다.
class TimestampConverter implements JsonConverter<DateTime, Timestamp> {
  /// [TimestampConverter] 를 생성한다.
  const TimestampConverter();

  /// Firestore [Timestamp] 를 UTC [DateTime] 으로 바꾼다.
  @override
  DateTime fromJson(Timestamp json) => json.toDate().toUtc();

  /// [DateTime] 을 Firestore [Timestamp] 로 바꾼다.
  @override
  Timestamp toJson(DateTime object) => Timestamp.fromDate(object);
}
