import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'package:flutter_starter_kit/core/l10n/intl_extensions.dart';

void main() {
  setUpAll(() async {
    await initializeDateFormatting();
  });

  group('DateTimeFormatX', () {
    // 고정 날짜: 2026년 4월 6일
    final date = DateTime(2026, 4, 6);

    test('formatYMD("en")은 M/d/yyyy 패턴을 반환한다', () {
      expect(date.formatYMD('en'), '4/6/2026');
    });

    test('formatYMD("ko")은 yyyy. M. d. 패턴을 반환한다', () {
      expect(date.formatYMD('ko'), '2026. 4. 6.');
    });

    test('formatYMMMMd("en")은 MMMM d, yyyy 패턴을 반환한다', () {
      expect(date.formatYMMMMd('en'), 'April 6, 2026');
    });

    test('formatJm("en")은 h:mm a 패턴을 반환한다', () {
      final dateWithTime = DateTime(2026, 4, 6, 17, 8);
      final result = dateWithTime.formatJm('en');
      // intl 패키지는 시:분과 AM/PM 사이에 NBSP(\u202F)를 사용할 수 있다.
      final normalized = result.replaceAll('\u202F', ' ');
      expect(normalized, '5:08 PM');
    });
  });

  group('NumberFormatX', () {
    test('formatCompact("en")은 간결한 숫자를 반환한다', () {
      // intl 버전에 따라 '1.2K' 또는 '1.23K'를 반환할 수 있다.
      expect(1234.formatCompact('en'), contains('K'));
      expect(1234.formatCompact('en'), startsWith('1.'));
    });

    test('formatDecimal("ko")은 천 단위 구분을 반환한다', () {
      expect(1234.formatDecimal('ko'), '1,234');
    });
  });
}
