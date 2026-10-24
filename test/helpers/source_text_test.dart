// 하위 항목 덩어리 읽기 헬퍼가 머리 줄과 바로 아래 하위 항목을 함께 읽는지 확인한다.
//
// 문서를 읽는 시험은 줄 머리로 한 줄을 골라 그 안의 토큰을 찾는다. 문서가 「할 일
// 한 줄 + 하위 항목」 꼴로 바뀌면 토큰이 하위 항목으로 내려가므로, 읽는 범위를 머리
// 줄과 그 아래 덩어리로 넓혀야 단언 내용(찾는 토큰 · 개수)을 그대로 둘 수 있다.
// 덩어리가 짧으면 토큰을 놓치고, 길면 다음 단계의 토큰까지 읽어 단언이 공허하게
// 참이 되므로 멈춤 자리를 하나씩 고정한다. 하위 항목이 없는 줄에서는 줄 하나 읽기와
// 같은 결과여야 기존 시험의 뜻이 바뀌지 않는다. 시험 글은 지어낸 짧은 마크다운이다.

import 'package:flutter_test/flutter_test.dart';

import 'source_text.dart';

void main() {
  group('collectItemBlocks — 머리 줄 + 하위 항목 덩어리', () {
    test('T-21-BLOCK-01: 번호 단계 아래 3칸 하위 항목 다섯을 읽고 다음 번호 앞에서 '
        '멈춘다', () {
      const text =
          '1. 첫 단계를 한다.\n'
          '   - 하나다.\n'
          '   - 둘이다.\n'
          '   - 셋이다.\n'
          '   - 넷이다.\n'
          '   - 다섯이다.\n'
          '2. 다음 단계를 한다.\n';

      final List<String> blocks = collectItemBlocks(text, '1. ');

      const expected =
          '1. 첫 단계를 한다.\n'
          '   - 하나다.\n'
          '   - 둘이다.\n'
          '   - 셋이다.\n'
          '   - 넷이다.\n'
          '   - 다섯이다.';
      expect(blocks, <String>[expected]);
    });

    test('T-21-BLOCK-02: 문단 줄 아래 0칸 하위 항목 다섯을 빈 줄 앞까지 읽는다', () {
      const text =
          '설정 파일에 값을 넣는다.\n'
          '- 가.\n'
          '- 나.\n'
          '- 다.\n'
          '- 라.\n'
          '- 마.\n'
          '\n'
          '다른 문단이다.\n';

      final List<String> blocks = collectItemBlocks(text, '설정 파일에 ');

      expect(blocks, <String>['설정 파일에 값을 넣는다.\n- 가.\n- 나.\n- 다.\n- 라.\n- 마.']);
    });

    test('T-21-BLOCK-03: 하위 항목이 없는 머리 줄은 줄 하나 읽기와 같다', () {
      const text =
          '- 사과 항목이다.\n'
          '- 배 항목이다.\n'
          '- 사과 둘째 항목이다.\n'
          '\n'
          '사과 문단이다.\n'
          '\n'
          '끝 문단이다.\n';

      for (final prefix in <String>['- 사과', '사과', '- 배']) {
        expect(
          collectItemBlocks(text, prefix),
          linesStartingWith(text, prefix),
          reason: '머리 $prefix',
        );
      }
    });

    test('T-21-BLOCK-04: 글머리 항목은 같은 들여쓰기의 다음 글머리 앞에서 멈춘다', () {
      const text =
          '- 첫 항목이다.\n'
          '  - 하위 하나.\n'
          '  - 하위 둘.\n'
          '- 둘째 항목이다.\n';

      final List<String> blocks = collectItemBlocks(text, '- 첫');

      expect(blocks, <String>['- 첫 항목이다.\n  - 하위 하나.\n  - 하위 둘.']);
    });

    test('T-21-BLOCK-05: 빈 줄 뒤 들여 쓴 펜스와 0칸 제목 줄은 덩어리 밖이다', () {
      const fenced =
          '1. 명령을 실행한다.\n'
          '   - 터미널에서 친다.\n'
          '\n'
          '   ```bash\n'
          '   echo hi\n'
          '   ```\n';
      const headed =
          '값을 고친다.\n'
          '- 저장한다.\n'
          '## 다음 절\n'
          '본문이다.\n';

      expect(collectItemBlocks(fenced, '1. '), <String>[
        '1. 명령을 실행한다.\n   - 터미널에서 친다.',
      ]);
      expect(collectItemBlocks(headed, '값을'), <String>['값을 고친다.\n- 저장한다.']);
    });

    test('T-21-BLOCK-06: 머리 줄마다 덩어리 하나 · 없으면 빈 목록과 빈 문자열', () {
      const listed =
          '- 키를 넣는다.\n'
          '  - 키 이름이다.\n'
          '- 키를 지운다.\n'
          '- 키를 바꾼다.\n'
          '  - 키 값이다.\n';
      const overlapped =
          '키 값을 넣는다.\n'
          '키 값은 길다.\n';

      expect(collectItemBlocks(listed, '- 키를'), <String>[
        '- 키를 넣는다.\n  - 키 이름이다.',
        '- 키를 지운다.',
        '- 키를 바꾼다.\n  - 키 값이다.',
      ]);
      expect(collectItemBlocks(overlapped, '키 값'), <String>[
        '키 값을 넣는다.\n키 값은 길다.',
        '키 값은 길다.',
      ]);

      final List<String> none = collectItemBlocks('본문이다.\n', '- 없음');
      expect(none, isEmpty);
      expect(none.take(1).join(), isEmpty);
    });

    test('T-21-BLOCK-07: 문단은 이어 쓴 줄을 읽고 번호 항목은 번호 · 표 · 펜스 줄에서 '
        '멈춘다', () {
      const continued =
          '설명을 적는다\n'
          '이어 쓴 줄이다.\n'
          '\n';
      const numbered =
          '1. 첫 단계다.\n'
          '2. 둘째 단계다.\n';
      const tabled =
          '1. 표를 본다.\n'
          '| 칸 | 값 |\n';
      const fenced =
          '1. 명령을 친다.\n'
          '```bash\n'
          'ls\n'
          '```\n';

      expect(collectItemBlocks(continued, '설명을'), <String>[
        '설명을 적는다\n이어 쓴 줄이다.',
      ]);
      expect(collectItemBlocks(numbered, '1. '), <String>['1. 첫 단계다.']);
      expect(collectItemBlocks(tabled, '1. '), <String>['1. 표를 본다.']);
      expect(collectItemBlocks(fenced, '1. '), <String>['1. 명령을 친다.']);
    });
    test('T-21-BLOCK-08: 인용 블록 머리는 표지를 벗긴 본문으로 판정하고 인용 여부가 '
        '바뀌는 줄에서 멈춘다', () {
      // 리뷰 재현 입력 — 인용 안 번호 단계는 다음 번호 앞에서 멈춘다.
      const numbered =
          '> 1. 첫 단계다.\n'
          '> 2. 둘째 단계다.\n'
          '> 3. 셋째 단계다.\n'
          '\n'
          '다음.\n';
      // 인용 안 「문단 + 하위 항목」 은 붙는다(문서의 `> ⚠ …` 꼴).
      const paragraph =
          '> ⚠ 주의할 점이다.\n'
          '> - 하나다.\n'
          '> - 둘이다.\n'
          '>\n'
          '> 다른 문단이다.\n';
      // 인용 머리 뒤 인용 밖 줄에서 멈춘다.
      const leaving =
          '> 인용 문단이다.\n'
          '인용 밖 줄이다.\n';
      // 인용 밖 머리 뒤 0칸 인용 줄에서 멈추고, 깊이 들여 쓴 인용은 항목 안이라 붙는다.
      const entering =
          '- 할 일이다.\n'
          '> 인용이다.\n';
      const nested =
          '1. 단계다.\n'
          '   > 단계 안 인용이다.\n'
          '2. 다음 단계다.\n';

      expect(collectItemBlocks(numbered, '> 1. '), <String>['> 1. 첫 단계다.']);
      expect(collectItemBlocks(numbered, '> 2. '), <String>['> 2. 둘째 단계다.']);
      expect(collectItemBlocks(paragraph, '> ⚠'), <String>[
        '> ⚠ 주의할 점이다.\n> - 하나다.\n> - 둘이다.',
      ]);
      expect(collectItemBlocks(leaving, '> 인용'), <String>['> 인용 문단이다.']);
      expect(collectItemBlocks(entering, '- 할 일'), <String>['- 할 일이다.']);
      expect(collectItemBlocks(nested, '1. '), <String>[
        '1. 단계다.\n   > 단계 안 인용이다.',
      ]);
    });
  });
}
