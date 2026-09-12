import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';

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

    // CR-01 (Phase 04 리뷰) — UTC DateTime 이 변환 없이 렌더되면 계정 생성일이
    // 하루 어긋난다 (Firebase UserMetadata.creationTime 은 isUtc: true).
    // 실행 환경 타임존에 의존하지 않도록 "local 로 변환한 값" 을 기준으로 잠근다.
    group('UTC 정규화 (CR-01)', () {
      final utc = DateTime.utc(2026, 4, 6, 20);

      test('formatYMD 는 UTC 를 local 로 정규화해 포맷한다', () {
        expect(utc.formatYMD('ko'), DateFormat.yMd('ko').format(utc.toLocal()));
      });

      test('formatYMMMMd 는 UTC 를 local 로 정규화해 포맷한다', () {
        expect(
          utc.formatYMMMMd('ko'),
          DateFormat.yMMMMd('ko').format(utc.toLocal()),
        );
      });

      test('formatJm 은 UTC 를 local 로 정규화해 포맷한다', () {
        expect(utc.formatJm('ko'), DateFormat.jm('ko').format(utc.toLocal()));
      });

      test('local DateTime 은 정규화의 영향을 받지 않는다', () {
        expect(DateTime(2026, 4, 6, 20).formatYMD('ko'), '2026. 4. 6.');
      });
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
