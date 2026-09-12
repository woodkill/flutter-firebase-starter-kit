import 'dart:io';

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

    // CR-01 (Phase 04 리뷰) — UTC DateTime 이 변환 없이 렌더되면 계정 생성일이
    // 하루 어긋난다 (Firebase UserMetadata.creationTime 은 isUtc: true).
    //
    // 봉인 설계 (2차 리뷰 WR-01). 직전 봉인은 기대값을
    // `DateFormat.yMd('ko').format(utc.toLocal())` 로 적어 **구현을 그대로
    // 되풀이**했고, 실행 오프셋이 0 이면 버그 구현 `format(this)` 도 같은
    // 문자열을 내므로 회귀를 놓쳤다. intl 0.20.2 실측 (기준값 아래 utc 와 동일):
    //   TZ=Asia/Seoul(+9)      yMd/yMMMMd/jm 3건 유효
    //   TZ=America/LA(-7)      yMd·yMMMMd 무력, jm 만 유효
    //   TZ=UTC(0)              3건 전부 무력  ← GitHub Actions 러너 기본값
    //
    // 오프셋이 0 이면 UTC 와 local 의 wall-clock 필드가 동일하므로 **포맷 결과
    // 문자열만으로는 두 구현을 원리적으로 구별할 수 없다.** 따라서 두 축으로
    // 잠근다.
    //   행동 축 — 기대값을 구현 되풀이 대신 오프셋 산술로 독립 산출한 정확
    //             문자열로 단언한다. 모든 타임존에서 참이며(= UTC CI 에서도
    //             ko 패턴을 잠근다), 오프셋이 0 이 아니면 버그 구현을 잡는다.
    //   소스 축 — 세 메서드가 수신자를 toLocal() 로 정규화한다는 사실을 소스
    //             수준에서 잠근다. 타임존과 무관하게 toLocal() 제거를 RED 로
    //             만드는 유일한 가드다 (sentinel 선례:
    //             test/core/l10n/reauth_key_consumer_sentinel_test.dart).
    group('UTC 정규화 (CR-01) — 행동 축', () {
      final utc = DateTime.utc(2026, 4, 6, 20);

      // 이 instant 의 실행 환경 오프셋. 구현이 쓰는 DateTime.toLocal 이 아니라
      // epoch 로부터 local DateTime 을 재구성하는 독립 경로로 얻는다.
      final offset = DateTime.fromMillisecondsSinceEpoch(
        utc.millisecondsSinceEpoch,
      ).timeZoneOffset;

      // UTC 필드에 오프셋을 직접 더해 얻은 local wall-clock. DateTime.add 는
      // isUtc 를 보존하므로 이 값의 필드가 곧 화면에 보여야 할 값이다.
      final wall = utc.add(offset);

      test('formatYMD 는 local wall-clock 날짜를 ko 패턴으로 렌더한다', () {
        expect(
          utc.formatYMD('ko'),
          '${wall.year}. ${wall.month}. ${wall.day}.',
        );
      });

      test('formatYMMMMd 는 local wall-clock 날짜를 ko 패턴으로 렌더한다', () {
        expect(
          utc.formatYMMMMd('ko'),
          '${wall.year}년 ${wall.month}월 ${wall.day}일',
        );
      });

      test('formatJm 은 local wall-clock 시각을 ko 패턴으로 렌더한다', () {
        final meridiem = wall.hour < 12 ? '오전' : '오후';
        final hour12 = wall.hour % 12 == 0 ? 12 : wall.hour % 12;
        final minute = wall.minute.toString().padLeft(2, '0');

        expect(utc.formatJm('ko'), '$meridiem $hour12:$minute');
      });

      test('local 입력을 UTC 로 되밀지 않는다', () {
        // 과잉 정규화(toLocal 대신 toUtc) 회귀 가드 — local 입력에 대해
        // 정규화는 항등이어야 한다.
        expect(DateTime(2026, 4, 6, 20).formatYMD('ko'), '2026. 4. 6.');
      });
    });

    group('UTC 정규화 (CR-01) — 소스 축', () {
      test('DateFormat 포맷 호출 3건이 모두 toLocal() 수신자를 넘긴다', () {
        const path = 'lib/core/l10n/intl_extensions.dart';
        final file = File(path);
        expect(file.existsSync(), isTrue, reason: '$path 부재');

        // 근거 주석이 `DateFormat.format` / `toLocal` 을 언급하므로, 주석을
        // 걷어내지 않으면 문서 문장이 호출로 오탐된다.
        final code = file
            .readAsLinesSync()
            .where((line) => !line.trimLeft().startsWith('//'))
            .join('\n');

        // 포맷 인자를 전수 추출한다. 공백·줄바꿈은 흡수해 포매터 재줄바꿈에
        // 견디게 한다 (.claude/rules/dart-format.md 3번).
        final receivers =
            RegExp(
                  r'DateFormat\.\w+\([^)]*\)\s*\.format\((.*?)\)\s*;',
                  dotAll: true,
                )
                .allMatches(code)
                .map(
                  (m) => m
                      .group(1)!
                      .replaceAll(RegExp(r'\s'), '')
                      .replaceAll(RegExp(r',$'), ''),
                )
                .toList();

        expect(
          receivers.length,
          3,
          reason:
              'DateTimeFormatX 의 DateFormat 포맷 호출은 3건이다. 메서드를 '
              '추가·삭제했다면 이 봉인도 함께 갱신할 것 — 추출 정규식이 깨진 채 '
              '조용히 통과하는 것을 막는다.',
        );
        expect(
          receivers.toSet(),
          {'toLocal()'},
          reason:
              'CR-01 회귀: DateFormat.format 은 타임존 변환 없이 필드값을 그대로 '
              '렌더하므로, UTC 수신자를 정규화 없이 넘기면 KST 기준 하루 어긋난 '
              '날짜가 표시된다. 오프셋 0 환경(UTC CI)에서는 행동 축 테스트가 이 '
              '회귀를 원리적으로 볼 수 없으므로 이 소스 단언이 유일한 가드다.',
        );
      });
    });
  });

  group('NumberFormatX', () {
    // WR-02 (Phase 04 리뷰) — 느슨한 matcher 는 docstring 예시와 실제 출력의
    // 불일치를 잡지 못했다. lock 버전(intl 0.20.2) 의 로케일별 실측값을 잠근다.
    test('formatCompact 는 로케일별 축약 표기를 반환한다', () {
      expect(1234.formatCompact('en'), '1.23K');
      expect(1234.formatCompact('ko'), '1.23천');
      expect(1234.formatCompact('ja'), '1234');
      expect(1234567.formatCompact('en'), '1.23M');
      expect(1234567.formatCompact('ko'), '123만');
    });

    test('formatDecimal("ko")은 천 단위 구분을 반환한다', () {
      expect(1234.formatDecimal('ko'), '1,234');
    });
  });
}
