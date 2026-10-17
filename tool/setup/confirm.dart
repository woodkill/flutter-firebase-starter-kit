import 'terminal.dart';

/// 비용 · 되돌릴 수 없는 선택 확인 표의 질문(`[y/N]` 은 터미널이 붙인다).
const String summaryConfirmQuestion = '이 값으로 진행할까요?';

/// 확인 표의 값 행 하나.
final class SummaryRow {
  /// [label] 과 [value] 로 행을 만든다.
  const SummaryRow(this.label, this.value);

  /// 왼쪽 라벨(예: 프로젝트 ID).
  final String label;

  /// 오른쪽 값.
  final String value;
}

/// 값 요약 표를 질문 없이 보인다.
///
/// `── <title> ──` 머리 줄, 라벨을 화면 폭 기준으로 맞춘 값 행, [notes] 마다
/// `  · <note>` 줄을 쓴다.
void writeSummary(
  Terminal terminal, {
  required String title,
  required List<SummaryRow> rows,
  List<String> notes = const <String>[],
}) {
  terminal.writeLine('── $title ──');
  final int labelWidth = rows.fold<int>(0, (int widest, SummaryRow row) {
    final int width = measureDisplayWidth(row.label);
    return width > widest ? width : widest;
  });
  for (final row in rows) {
    final int padding = labelWidth - measureDisplayWidth(row.label);
    terminal.writeLine('  ${row.label}${' ' * padding}  ${row.value}');
  }
  for (final note in notes) {
    terminal.writeLine('  · $note');
  }
}

/// 비용이 들거나 되돌릴 수 없는 선택 직전에 값 요약 표를 보이고 한 번 묻는다.
///
/// [writeSummary] 의 표 뒤에 경고마다 `  ! <경고>` 줄을 보인 뒤
/// [summaryConfirmQuestion] 을 묻는다. `y` · `yes` 만 true 이고 Enter · 그 밖의
/// 답 · 입력 끝은 false 다. 진행하지 않아도 값을 다시 입력받지 않는다 — 호출한
/// 단계가 멈춘다. 단계 진행 확인과는 별개의 질문이다.
bool confirmSummary(
  Terminal terminal, {
  required String title,
  required List<SummaryRow> rows,
  List<String> warnings = const <String>[],
}) {
  writeSummary(terminal, title: title, rows: rows);
  for (final warning in warnings) {
    terminal.writeLine('  ! $warning');
  }
  return terminal.confirm(summaryConfirmQuestion);
}

/// [text] 가 고정폭 터미널에서 차지하는 칸 수를 센다 — 한글 · 한자 · 전각 문자는 2칸.
int measureDisplayWidth(String text) {
  var width = 0;
  for (final int rune in text.runes) {
    width += _isWideRune(rune) ? 2 : 1;
  }
  return width;
}

/// 동아시아 넓은 문자(한글 자모 · 음절, CJK, 전각 기호)면 true.
bool _isWideRune(int rune) =>
    (rune >= 0x1100 && rune <= 0x115F) ||
    (rune >= 0x2E80 && rune <= 0x303E) ||
    (rune >= 0x3041 && rune <= 0x33FF) ||
    (rune >= 0x3400 && rune <= 0x4DBF) ||
    (rune >= 0x4E00 && rune <= 0x9FFF) ||
    (rune >= 0xA000 && rune <= 0xA4CF) ||
    (rune >= 0xAC00 && rune <= 0xD7A3) ||
    (rune >= 0xF900 && rune <= 0xFAFF) ||
    (rune >= 0xFE30 && rune <= 0xFE4F) ||
    (rune >= 0xFF00 && rune <= 0xFF60) ||
    (rune >= 0xFFE0 && rune <= 0xFFE6);
