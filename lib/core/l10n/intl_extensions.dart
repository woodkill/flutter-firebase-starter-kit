import 'package:intl/intl.dart';

/// [DateTime]에 로케일별 포맷 메서드를 제공하는 확장.
///
/// 각 메서드는 선택적 [locale] 파라미터를 받으며, 생략 시
/// [Intl.defaultLocale] 이 적용된다. **이 스타터 킷은 [Intl.defaultLocale] 을
/// 설정하지 않으므로, 생략하면 앱 로케일이 아니라 intl 기본값(`en_US`)으로
/// 포맷된다.** 앱 로케일을 따르려면 `ref.watch(localeProvider).languageCode`
/// 같은 값을 반드시 명시 전달할 것.
///
/// 앱 전역으로 동기화하려면 로케일 변경 지점에서 `Intl.defaultLocale` 을 직접
/// 설정하면 된다. **단 이 킷은 그 경로를 채택하지 않았다** — Riverpod `build()`
/// 안에서 전역 가변 상태를 쓰면 provider 순수성이 깨지고, 로케일을 명시하지
/// 않는 테스트의 기대값이 실행 순서에 따라 흔들린다(전역 상태 누수). 그래도
/// 도입한다면 동기화 지점을 `build()` 밖(로케일 변경 액션)으로 빼고, 테스트는
/// `setUp`/`tearDown` 에서 이전 값으로 되돌릴 것.
///
/// **[locale] 계약.** intl 이 아는 로케일 코드여야 한다 ('ko', 'en_GB' 등).
/// 알 수 없는 코드는 intl 이 [ArgumentError] 를 던지며(실측: `Invalid locale
/// "xx"`), 이 확장들은 `build()` 안에서 호출되므로 그대로 화면 파손이 된다.
/// 따라서 사용자 입력이나 서버 응답을 그대로 넘기지 말고
/// `AppLocalizations.supportedLocales` 파생값만 전달할 것. 지역 코드(`en_GB`)도
/// 유효하므로, 지역까지 반영하려면 호출부에서 `languageCode` 대신
/// `Intl.canonicalizedLocale(locale.toString())` 을 쓴다.
///
/// **선행조건 — date symbol 로드.** 실패는 입력값만의 함수가 아니다. date
/// symbol 이 로드돼 있지 않으면 `'ko'` 처럼 완전히 유효한 코드도
/// `LocaleDataException`(=[ArgumentError] 가 아니다) 으로 죽는다. 앱 실행
/// 경로에서는 `AppLocalizations.localizationsDelegates` 의
/// `GlobalMaterialLocalizations.delegate` 가 자동으로 로드하지만, 위젯 트리
/// 밖(순수 유닛 테스트·isolate·백그라운드 작업)에는 그 구제가 없다. 호출자가
/// `initializeDateFormatting()` 을 먼저 await 할 것 — `bootstrap()` 의 초기화는
/// 실패를 의도적으로 삼키므로 보장이 아니다.
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
  /// en: `5:08\u202FPM`, ko: `오후 5:08`
  ///
  /// **en 의 구분자는 일반 공백이 아니다** — 시:분과 AM/PM 사이는 NBSP
  /// (U+202F NARROW NO-BREAK SPACE) 다(실측 rune: `35 3a 30 38 202f 50 4d`).
  /// 육안으로 U+0020 과 구별되지 않으므로, 문자열을 그대로 단언하거나 골든
  /// 텍스트로 비교할 때는 `replaceAll('\u202F', ' ')` 로 먼저 정규화할 것.
  /// ko 는 일반 공백이라 해당 없다.
  String formatJm([String? locale]) => DateFormat.jm(locale).format(toLocal());
}

/// [num]에 로케일별 포맷 메서드를 제공하는 확장.
///
/// 각 메서드는 선택적 [locale] 파라미터를 받으며, 생략 시
/// [Intl.defaultLocale] 이 적용된다. [DateTimeFormatX] 와 동일하게 이 스타터
/// 킷은 [Intl.defaultLocale] 을 설정하지 않으므로, **생략하면 intl
/// 기본값(`en_US`)으로 포맷된다** — 앱 로케일을 따르려면 명시 전달할 것.
///
/// **[locale] 계약.** 알 수 없는 코드는 [DateTimeFormatX] 와 동일하게
/// [ArgumentError] 로 죽으므로 `AppLocalizations.supportedLocales` 파생값만
/// 전달할 것. 단 **date symbol 선행조건은 없다** — `NumberFormat` 계열은
/// `initializeDateFormatting()` 없이도 동작한다(실측: 미초기화 상태에서
/// `1234.formatCompact('ko')` → `1.23천`). 두 확장의 선행조건은 다르다.
extension NumberFormatX on num {
  /// 간결한 숫자 포맷.
  ///
  /// 예: 1234 -> '1.23K' (en), '1.23천' (ko), '1234' (ja)
  ///     1234567 -> '1.23M' (en), '123만' (ko), '123万' (ja)
  ///
  /// CJK 로케일은 '천'/'만'/'万' 단위로 축약되므로, 레이아웃은 라틴 축약
  /// 표기('K'/'M')보다 넓은 폭을 감안해야 한다.
  String formatCompact([String? locale]) =>
      NumberFormat.compact(locale: locale).format(this);

  /// 소수점 포함 일반 숫자 포맷.
  ///
  /// 예: 1234 -> '1,234' (en), '1,234' (ko)
  String formatDecimal([String? locale]) =>
      NumberFormat.decimalPattern(locale).format(this);
}
