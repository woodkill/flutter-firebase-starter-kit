/// 화면 · 로그로 나가기 직전의 문자열에서 비밀 값을 가린다.
///
/// 위저드가 아는 값(액세스 토큰 · App Check 디버그 토큰 등)은 [register] 로
/// 등록하고, 등록하지 않은 값도 모양이 알려진 것(액세스 토큰 · API 키 · UUID)은
/// 패턴으로 가린다. 화면 감싸개(`RedactingTerminal`)와 실행 기록이 모두 같은
/// [apply] 를 거친다.
final class Redactor {
  /// 가린 자리에 들어가는 문자열.
  static const String mask = '***';

  /// 등록할 수 있는 값의 최소 길이 — 짧은 값이 일반 단어를 가리지 않게 한다.
  static const int minSecretLength = 8;

  /// 등록 값 없이도 가리는 모양 — 액세스 토큰 · API 키 · UUID(8-4-4-4-12 16진).
  static final List<RegExp> patterns = <RegExp>[
    RegExp(r'ya29\.[0-9A-Za-z._-]+'),
    RegExp(r'AIza[0-9A-Za-z_-]{35}'),
    RegExp(
      r'[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-'
      r'[0-9A-Fa-f]{12}',
    ),
  ];

  // 긴 값부터 치환해야 다른 등록 값을 품은 값이 남지 않는다.
  final List<String> _secrets = <String>[];

  /// [secret] 을 가릴 값으로 등록한다.
  ///
  /// [minSecretLength] 보다 짧거나 이미 등록된 값은 무시한다.
  void register(String secret) {
    if (secret.length < minSecretLength) return;
    if (_secrets.contains(secret)) return;
    _secrets
      ..add(secret)
      ..sort((String a, String b) => b.length.compareTo(a.length));
  }

  /// [text] 의 등록 값을 먼저, 그다음 패턴에 걸리는 값을 [mask] 로 바꾼다.
  String apply(String text) {
    String result = text;
    for (final String secret in _secrets) {
      result = result.replaceAll(secret, mask);
    }
    for (final RegExp pattern in patterns) {
      result = result.replaceAll(pattern, mask);
    }
    return result;
  }
}
