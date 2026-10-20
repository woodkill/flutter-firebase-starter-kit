import '../wizard.dart';

/// 터미널에 끌어다 놓거나 붙여 넣은 경로 답 [answer] 에서 셸 따옴표 · 백슬래시를 벗긴다.
///
/// 앞뒤 공백을 떼고, `file://` 주소면 파일 경로로 바꾼다. 그 밖은 왼쪽부터 —
/// 따옴표 밖 `\X` 는 `X`, 작은따옴표 안은 글자 그대로, 큰따옴표 안은 `\"` · `\\`
/// 만 풀고, 따옴표 조각은 이어 붙인다. 끝까지 닫히지 않은 따옴표가 있으면 손대지
/// 않은 값을 돌려준다(이름에 따옴표 하나만 있는 경로를 손으로 친 경우). 유니코드
/// 정규화는 바꾸지 않는다.
String parseDroppedPath(String answer) {
  final String text = answer.trim();
  if (text.startsWith('file://')) {
    final Uri? uri = Uri.tryParse(text);
    if (uri != null &&
        uri.scheme == 'file' &&
        uri.host.isEmpty &&
        !uri.hasQuery &&
        !uri.hasFragment) {
      return uri.toFilePath();
    }
    return text;
  }
  final buffer = StringBuffer();
  var quote = '';
  for (var i = 0; i < text.length; i++) {
    final String char = text[i];
    if (quote.isEmpty) {
      if (char == r'\' && i + 1 < text.length) {
        i++;
        buffer.write(text[i]);
      } else if (char == "'" || char == '"') {
        quote = char;
      } else {
        buffer.write(char);
      }
    } else if (char == quote) {
      quote = '';
    } else if (quote == '"' &&
        char == r'\' &&
        i + 1 < text.length &&
        (text[i + 1] == '"' || text[i + 1] == r'\')) {
      i++;
      buffer.write(text[i]);
    } else {
      buffer.write(char);
    }
  }
  if (quote.isNotEmpty) return text;
  return buffer.toString().trim();
}

/// 입력한 [path] 의 `~` 를 홈 디렉터리로, 상대 경로를 저장소 루트 기준으로 바꾼다.
String expandInputPath(WizardContext context, String path) {
  if (path.isEmpty) return path;
  if (path == '~') return context.homeDirectory;
  if (path.startsWith('~/')) {
    return '${context.homeDirectory}/${path.substring(2)}';
  }
  return context.resolve(path);
}

/// 화면에 보일 [path] — 홈 디렉터리(사용자 이름이 든 경로)는 `~` 로 줄인다.
String describePath(WizardContext context, String path) {
  final String home = context.homeDirectory;
  if (home.isEmpty) return path;
  if (path == home) return '~';
  if (path.startsWith('$home/')) return '~/${path.substring(home.length + 1)}';
  return path;
}
