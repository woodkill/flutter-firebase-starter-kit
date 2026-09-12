import 'package:intl/intl.dart';

/// [DateTime]에 로케일별 포맷 메서드를 제공하는 확장.
///
/// 각 메서드는 선택적 [locale] 파라미터를 받으며,
/// 생략 시 [Intl.defaultLocale]이 적용된다.
extension DateTimeFormatX on DateTime {
  /// 연-월-일 포맷.
  ///
  /// UTC [DateTime] 은 [DateTime.toLocal] 로 정규화한 뒤 포맷한다 —
  /// `DateFormat.format` 은 타임존 변환 없이 필드값을 그대로 렌더하므로,
  /// Firebase `UserMetadata.creationTime` 처럼 `isUtc: true` 인 값은 정규화
  /// 없이는 **하루 어긋난 날짜**로 표시된다 (KST 기준 9시간 편차).
  /// UTC 를 그대로 표시해야 한다면 호출자가 별도 포맷터를 쓸 것.
  ///
  /// en: 4/6/2026, ko: 2026. 4. 6.
  String formatYMD([String? locale]) =>
      DateFormat.yMd(locale).format(toLocal());

  /// 연 월(풀네임) 일 포맷.
  ///
  /// UTC [DateTime] 은 [DateTime.toLocal] 로 정규화한 뒤 포맷한다 ([formatYMD]
  /// 와 동일 계약).
  ///
  /// en: April 6, 2026, ko: 2026년 4월 6일
  String formatYMMMMd([String? locale]) =>
      DateFormat.yMMMMd(locale).format(toLocal());

  /// 시:분 포맷.
  ///
  /// UTC [DateTime] 은 [DateTime.toLocal] 로 정규화한 뒤 포맷한다 ([formatYMD]
  /// 와 동일 계약).
  ///
  /// en: 5:08 PM, ko: 오후 5:08
  String formatJm([String? locale]) => DateFormat.jm(locale).format(toLocal());
}

/// [num]에 로케일별 포맷 메서드를 제공하는 확장.
///
/// 각 메서드는 선택적 [locale] 파라미터를 받으며,
/// 생략 시 [Intl.defaultLocale]이 적용된다.
extension NumberFormatX on num {
  /// 간결한 숫자 포맷.
  ///
  /// 예: 1234 -> '1.2K' (en), '1234' (ko)
  String formatCompact([String? locale]) =>
      NumberFormat.compact(locale: locale).format(this);

  /// 소수점 포함 일반 숫자 포맷.
  ///
  /// 예: 1234 -> '1,234' (en), '1,234' (ko)
  String formatDecimal([String? locale]) =>
      NumberFormat.decimalPattern(locale).format(this);
}
