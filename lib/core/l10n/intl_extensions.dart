import 'package:intl/intl.dart';

/// [DateTime]에 로케일별 포맷 메서드를 제공하는 확장.
///
/// 각 메서드는 선택적 [locale] 파라미터를 받으며,
/// 생략 시 [Intl.defaultLocale]이 적용된다.
extension DateTimeFormatX on DateTime {
  /// 연-월-일 포맷.
  ///
  /// en: 4/6/2026, ko: 2026. 4. 6.
  String formatYMD([String? locale]) => DateFormat.yMd(locale).format(this);

  /// 연 월(풀네임) 일 포맷.
  ///
  /// en: April 6, 2026, ko: 2026년 4월 6일
  String formatYMMMMd([String? locale]) =>
      DateFormat.yMMMMd(locale).format(this);

  /// 시:분 포맷.
  ///
  /// en: 5:08 PM, ko: 오후 5:08
  String formatJm([String? locale]) => DateFormat.jm(locale).format(this);
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
