import '../config_files.dart';
import '../terminal.dart';
import 'provider_catalog.dart';

/// 체크 목록 머리 줄.
const String providerChecklistHeading = '로그인 수단 — 이메일 로그인은 늘 켜져 있습니다';

/// 체크 목록의 번호 질문.
const String providerChoiceQuestion =
    '켤 로그인 수단 번호를 띄어 써서 입력하세요 — Enter = 지금 그대로 · 0 = 이메일만';

/// 체크 목록 번호를 다시 묻는 최대 횟수.
const int maxProviderChoiceAttempts = 3;

/// 이메일만 쓰는 답.
const String emailOnlyAnswer = '0';

/// 체크 목록 답 해석 결과 — 고른 토큰 또는 잘못된 이유 하나만 있다.
typedef ProviderChoice = ({Set<String>? tokens, String? error});

/// 체크 목록을 보이고 켤 로그인 수단을 고르게 한다.
///
/// 번호 목록(`  1) [x] Google`)과 이메일 로그인이 늘 켜져 있다는 줄을 보인 뒤
/// [providerChoiceQuestion] 을 한 번 묻는다. Enter 는 [current] 그대로, `0` 은
/// 이메일만이다. 잘못된 답은 이유 한 줄 뒤 다시 묻고, [maxProviderChoiceAttempts]
/// 회를 넘기거나 입력이 끝나면 null 이다.
Set<String>? chooseProviders(
  Terminal terminal, {
  required Set<String> current,
}) {
  terminal.writeLine(providerChecklistHeading);
  for (var i = 0; i < providerCatalog.length; i++) {
    final ProviderEntry entry = providerCatalog[i];
    final mark = current.contains(entry.token) ? 'x' : ' ';
    terminal.writeLine('  ${i + 1}) [$mark] ${entry.displayName}');
  }
  final String defaultAnswer = _formatNumbers(current);
  for (var attempt = 0; attempt < maxProviderChoiceAttempts; attempt++) {
    final String? answer = terminal.ask(
      providerChoiceQuestion,
      defaultValue: defaultAnswer,
    );
    if (answer == null) return null;
    final ProviderChoice choice = parseProviderChoice(answer);
    final Set<String>? tokens = choice.tokens;
    if (tokens != null) return tokens;
    terminal.writeLine('  ${choice.error}');
  }
  return null;
}

/// 체크 목록 답(띄어 쓴 번호)을 토큰 집합으로 해석한다.
///
/// `0` 하나는 빈 집합(이메일만)이다. 숫자가 아닌 글자 · 표 밖의 번호 · `0` 과
/// 다른 번호를 섞은 답 · 빈 답은 이유와 함께 돌려준다.
ProviderChoice parseProviderChoice(String answer) {
  final List<String> parts = answer
      .trim()
      .split(RegExp(r'[\s,]+'))
      .where((String part) => part.isNotEmpty)
      .toList();
  if (parts.isEmpty) {
    return (tokens: null, error: '번호를 입력하세요 — 이메일만 쓰려면 0 입니다.');
  }
  final numbers = <int>[];
  for (final part in parts) {
    final int? number = int.tryParse(part);
    if (number == null) {
      return (tokens: null, error: '숫자만 띄어 써서 입력하세요 — 「$part」 는 번호가 아닙니다.');
    }
    numbers.add(number);
  }
  if (numbers.contains(0)) {
    if (numbers.every((int number) => number == 0)) {
      return (tokens: <String>{}, error: null);
    }
    return (tokens: null, error: '0(이메일만)은 다른 번호와 함께 쓸 수 없습니다.');
  }
  final tokens = <String>{};
  for (final number in numbers) {
    if (number < 1 || number > providerCatalog.length) {
      return (
        tokens: null,
        error: '1 부터 ${providerCatalog.length} 사이의 번호를 입력하세요 — $number 는 없습니다.',
      );
    }
    tokens.add(providerCatalog[number - 1].token);
  }
  return (tokens: tokens, error: null);
}

/// [jsonPath] config 의 켠 로그인 수단 목록을 [tokens] 로 바꾼다.
///
/// 표 순서의 CSV 로 그 값만 바꾸고 다른 바이트는 그대로 둔다. 키가 없으면
/// [StateError] 를 던진다.
void writeEnabledProviders(String jsonPath, Set<String> tokens) =>
    replaceJsonString(jsonPath, enabledProvidersKey, formatProviderCsv(tokens));

/// [tokens] 의 체크 목록 번호를 띄어 쓴 문자열로 만든다 — 비었으면 `0`.
String _formatNumbers(Set<String> tokens) {
  final numbers = <String>[
    for (int i = 0; i < providerCatalog.length; i++)
      if (tokens.contains(providerCatalog[i].token)) '${i + 1}',
  ];
  return numbers.isEmpty ? emailOnlyAnswer : numbers.join(' ');
}
