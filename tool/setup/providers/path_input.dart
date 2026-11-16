import '../wizard.dart';

/// 터미널에 끌어다 놓거나 붙여 넣은 경로 답 [answer] 에서 셸 따옴표 · 백슬래시를 벗긴다.
///
/// 앞뒤 공백을 떼고, `file://` 주소면 파일 경로로 바꾼다(`%2F` · 깨진 UTF-8
/// 처럼 바꿀 수 없는 주소는 손대지 않은 값). 그 밖은 왼쪽부터 — 따옴표 밖 `\X` 는 `X`,
/// 작은따옴표 안은 글자 그대로, 큰따옴표 안은 `\"` · `\\` 만 풀고, 따옴표 조각은
/// 이어 붙인다. 끝까지 닫히지 않은 따옴표가 있으면 손대지 않은 값을 돌려준다
/// (이름에 따옴표 하나만 있는 경로를 손으로 친 경우). 유니코드 정규화는 바꾸지
/// 않는다.
String parseDroppedPath(String answer) {
  final String text = answer.trim();
  if (text.startsWith('file://')) {
    final Uri? uri = Uri.tryParse(text);
    if (uri != null &&
        uri.scheme == 'file' &&
        uri.host.isEmpty &&
        !uri.hasQuery &&
        !uri.hasFragment) {
      // 파일 경로로 바꿀 수 없는 주소는 손대지 않은 값을 돌려준다 —
      // 부르는 쪽이 `file://` 로 남은 값을 보고 까닭을 가른다.
      // 조각 안의 `%2F` 는 toFilePath 가 UnsupportedError(Error)를 던지고,
      // 깨진 UTF-8 은 조각을 풀 때 FormatException 이 난다.
      final List<String> segments;
      try {
        segments = uri.pathSegments;
      } on FormatException {
        return text;
      }
      if (segments.any((String segment) => segment.contains('/'))) return text;
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

/// 답을 풀어낸 경로가 빌 때(`""` · `''`)의 까닭 — 경로는 보이지 않는다.
///
/// 답을 되풀이하지 않는다 — 넣은 값 안에 홈 경로(사용자 이름)가 있을 수 있다.
const String emptyPathAnswerReason = '경로가 비었습니다';

/// `file://` 주소를 파일 경로로 바꾸지 못할 때의 까닭 — 주소는 보이지 않는다.
///
/// 답을 되풀이하지 않는다 — 주소 안에 홈 경로(사용자 이름)가 있을 수 있다.
const String unconvertibleAddressAnswerReason = '파일 경로로 바꿀 수 없는 주소입니다';

/// 경로 답 하나를 푼 결과 — [resolvePathAnswer] 가 네 갈래 중 하나로 돌려준다.
///
/// 다음 일(미루기 · 까닭 줄 · 파일 검사)은 부르는 자리가 정한다.
sealed class PathAnswer {
  /// 갈래 공통 생성자.
  const PathAnswer();
}

/// 앞뒤 공백을 떼면 빈 답(Enter).
final class BlankPathAnswer extends PathAnswer {
  /// 빈 답 갈래를 만든다.
  const BlankPathAnswer();
}

/// 따옴표만 있어 풀어낸 경로가 빈 답.
final class EmptyPathAnswer extends PathAnswer {
  /// 빈 경로 갈래를 만든다.
  const EmptyPathAnswer();
}

/// 따옴표를 벗기고 한 번 더 바꿔도 `file://` 주소로 남는 답.
final class UnconvertibleAddressAnswer extends PathAnswer {
  /// 바꿀 수 없는 주소 갈래를 만든다.
  const UnconvertibleAddressAnswer();
}

/// 파일 시스템 경로로 풀어낸 답.
final class ResolvedPathAnswer extends PathAnswer {
  /// `~` · 상대 경로를 확장한 [path] 로 만든다.
  const ResolvedPathAnswer(this.path);

  /// `~` 는 홈 디렉터리로, 상대 경로는 저장소 루트 기준으로 확장한 경로.
  final String path;
}

/// 터미널에 넣은 경로 답 [answer] 를 풀어 [PathAnswer] 네 갈래 중 하나로 가른다.
///
/// 앞뒤 공백을 떼면 비는 답은 [BlankPathAnswer] 다. 그 밖은 [parseDroppedPath] 로
/// 따옴표 · 백슬래시 · `file://` 주소를 풀고, 따옴표로 감싼 `file://` 답은 따옴표만
/// 벗겨진 주소로 돌아오므로 그 값으로 한 번 더 바꾼다. 풀어낸 값이 비면
/// [EmptyPathAnswer], 한 번 더 바꾸고도 `file://` 주소로 남으면
/// [UnconvertibleAddressAnswer] 다 — 둘 다 확장 전에 가른다(확장하면 저장소 루트가
/// 붙어 넣은 주소와 다른 경로가 된다). 나머지는 [expandInputPath] 로 확장한
/// [ResolvedPathAnswer] 다. 폴더 · 존재 · 읽기 검사는 하지 않는다.
PathAnswer resolvePathAnswer(WizardContext context, String answer) {
  final String trimmed = answer.trim();
  if (trimmed.isEmpty) return const BlankPathAnswer();
  final String unquoted = parseDroppedPath(trimmed);
  // 바꿀 수 없는 주소는 손대지 않은 값이 돌아와 그대로다.
  final String parsed = unquoted.startsWith('file://')
      ? parseDroppedPath(unquoted)
      : unquoted;
  if (parsed.isEmpty) return const EmptyPathAnswer();
  if (parsed.startsWith('file://')) return const UnconvertibleAddressAnswer();
  return ResolvedPathAnswer(expandInputPath(context, parsed));
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
