import 'package:test/test.dart';

import '../../../tool/setup/confirm.dart';
import 'fakes.dart';

/// 확인 표 테스트에 쓰는 값 행.
const List<SummaryRow> sampleRows = <SummaryRow>[
  SummaryRow('프로젝트 ID', 'demo-dev'),
  SummaryRow('위치', 'asia-northeast3'),
  SummaryRow('결제 계정', '데모 결제 계정'),
];

/// 확인 표 테스트에 쓰는 경고 줄.
const List<String> sampleWarnings = <String>[
  'Firestore 위치는 만든 뒤 바꿀 수 없습니다',
  '결제 계정을 연결하면 사용량에 따라 비용이 생길 수 있습니다',
];

/// [haystack] 에서 [needle] 이 나타나는 횟수를 센다.
int countText(String haystack, String needle) =>
    haystack.split(needle).length - 1;

void main() {
  test('T-19-CONFIRM-01: 제목 · 정렬된 값 행 · 경고 줄 · 질문 한 번을 보인다', () {
    final ScriptedTerminal terminal = ScriptedTerminal(const <String?>['y']);

    final bool isConfirmed = confirmSummary(
      terminal,
      title: '비용 · 되돌릴 수 없는 선택',
      rows: sampleRows,
      warnings: sampleWarnings,
    );

    expect(isConfirmed, isTrue);
    final List<String> lines = terminal.output.toString().split('\n');
    // 라벨은 화면 폭(한글 2칸) 기준으로 가장 긴 라벨에 맞춰 정렬한다.
    expect(lines, <String>[
      '── 비용 · 되돌릴 수 없는 선택 ──',
      '  프로젝트 ID  demo-dev',
      '  위치         asia-northeast3',
      '  결제 계정    데모 결제 계정',
      '  ! Firestore 위치는 만든 뒤 바꿀 수 없습니다',
      '  ! 결제 계정을 연결하면 사용량에 따라 비용이 생길 수 있습니다',
      '이 값으로 진행할까요? [y/N] ',
      '',
    ]);
    expect(countText(terminal.output.toString(), '이 값으로 진행할까요? [y/N]'), 1);
    expect(summaryConfirmQuestion, '이 값으로 진행할까요?');
  });

  group('T-19-CONFIRM-02: y · yes 만 진행하고 기본은 진행하지 않는다', () {
    for (final String answer in <String>['y', 'yes', 'Y', ' yes ']) {
      test('「$answer」 → 진행', () {
        final ScriptedTerminal terminal = ScriptedTerminal(<String?>[answer]);
        expect(confirmSummary(terminal, title: '확인', rows: sampleRows), isTrue);
      });
    }

    for (final String? answer in <String?>['', 'n', 'N', '네', 'ok', null]) {
      test('「${answer ?? '입력 끝'}」 → 진행 안 함', () {
        final ScriptedTerminal terminal = ScriptedTerminal(<String?>[answer]);
        expect(
          confirmSummary(terminal, title: '확인', rows: sampleRows),
          isFalse,
        );
      });
    }
  });

  test('T-19-CONFIRM-03: 진행하지 않아도 값을 다시 묻지 않는다', () {
    final ScriptedTerminal terminal = ScriptedTerminal(const <String?>[
      '',
      'demo-other',
      'y',
    ]);

    final bool isConfirmed = confirmSummary(
      terminal,
      title: '확인',
      rows: sampleRows,
      warnings: sampleWarnings,
    );

    expect(isConfirmed, isFalse);
    expect(terminal.asks, <String>[summaryConfirmQuestion]);
  });

  test('경고가 없으면 경고 줄 없이 표와 질문만 보인다', () {
    final ScriptedTerminal terminal = ScriptedTerminal(const <String?>['n']);

    confirmSummary(
      terminal,
      title: '확인',
      rows: const <SummaryRow>[SummaryRow('값', 'a')],
    );

    expect(
      terminal.output.toString(),
      '── 확인 ──\n  값  a\n이 값으로 진행할까요? [y/N] \n',
    );
  });
}
