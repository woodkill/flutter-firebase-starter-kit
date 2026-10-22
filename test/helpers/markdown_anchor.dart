// 마크다운 링크 · 앵커 헬퍼 — 사용자 문서 시험이 링크 대상과 앵커를 GitHub 렌더
// 규칙으로 검사한다.
//
// 앵커는 GitHub 가 제목에 붙이는 앵커(github-slugger 규칙)를 근사한다 — 소문자로 바꾸고
// 글자 · 결합 기호 · 십진 숫자 · 글자 숫자 · 연결 문장부호 · `-` · 공백이 아닌 문자를
// 지운 뒤 공백을 `-` 로 바꾸고, 같은 앵커가 다시 나오면 `-1` · `-2` 를 붙인다. 링크
// 수집과 제목 수집은 코드 펜스(```) 안을 보지 않는다.

import 'dart:convert';

/// 앵커를 만들 때 지우는 문자다.
///
/// github-slugger 는 원문자(`①` 같은 Other_Number) · 문장부호(연결 문장부호와 `-`
/// 제외) · 기호 · 제어 · 서식 · 공백(` ` 제외) 범주에서 Alphabetic 문자를 빼고
/// 지운다. 여기서는 그 범주를 Unicode 일반 범주로 적는다 — 기호이면서 Alphabetic 인
/// 문자(`ⓐ` 같은 원 글자)만 다르게 지운다.
final RegExp _anchorDroppedCharacters = RegExp(
  r'[^\p{L}\p{M}\p{Nd}\p{Nl}\p{Pc}\- ]',
  unicode: true,
);

/// 마크다운 제목 줄(`#` 1 ~ 6개 뒤 공백)과 그 텍스트다.
final RegExp _headingLine = RegExp(r'^#{1,6} (.*)$');

/// 인라인 링크(`](대상)` · `](대상 "제목")`)의 대상을 잡는다.
final RegExp _inlineLinkTarget = RegExp(
  r'''\]\(\s*<?([^)\s>]+)>?(?:\s+["'][^"']*["'])?\s*\)''',
);

/// `<img … src="…">` 의 경로를 잡는다.
final RegExp _imageSource = RegExp(r'''<img\b[^>]*\bsrc=["']([^"']+)["']''');

/// 인라인 코드 조각(`` `…` ``)이다 — 그 안의 링크 문법은 링크가 아니다.
final RegExp _inlineCode = RegExp('`[^`]*`');

/// URL 스킴(`https:` · `mailto:` 등)으로 시작하는 대상이다.
final RegExp _schemePrefix = RegExp('^[A-Za-z][A-Za-z0-9+.-]*:');

/// 이어진 퍼센트 인코딩 바이트(`%XX` 반복)다.
final RegExp _percentEncodedRun = RegExp('(?:%[0-9A-Fa-f]{2})+');

/// 링크 경로 · 앵커 [text] 의 퍼센트 인코딩(UTF-8 바이트)을 푼다.
///
/// 한글처럼 인코딩하지 않은 글자는 그대로 두고 `%XX` 묶음만 UTF-8 로 푼다 — 링크에는
/// 두 꼴이 섞여 쓰이고, 비ASCII 글자가 든 입력을 거부하는 `Uri.decodeComponent` 로는
/// 풀 수 없다. 뒤에 16진수 두 자리가 없는 `%` 는 그대로 둔다. 바이트가 UTF-8 이
/// 아니면 `null` 이다.
String? decodePercentEncoding(String text) {
  try {
    return text.replaceAllMapped(_percentEncodedRun, (Match match) {
      final String run = match.group(0)!;
      return utf8.decode(<int>[
        for (var i = 0; i < run.length; i += 3)
          int.parse(run.substring(i + 1, i + 3), radix: 16),
      ]);
    });
  } on FormatException {
    return null;
  }
}

/// GitHub 가 제목 텍스트 [headingText] 에 붙이는 앵커를 만든다(중복 접미 없이).
///
/// 같은 제목이 여러 번 나올 때의 `-1` · `-2` 는 [collectHeadingAnchors] 가 붙인다.
String buildGithubAnchor(String headingText) => headingText
    .toLowerCase()
    .replaceAll(_anchorDroppedCharacters, '')
    .replaceAll(' ', '-');

/// 마크다운 [markdown] 의 제목 줄마다 GitHub 앵커를 만들어 집합으로 돌려준다.
///
/// 코드 펜스 안의 `#` 줄(셸 주석 등)은 제목이 아니다. 제목 텍스트는 `#` 들과 공백 뒤
/// 줄 끝까지이고 앞뒤 공백만 지운다. 같은 앵커가 다시 나오면 github-slugger 처럼
/// 처음 앵커 뒤에 `-<횟수>` 를 붙이고, 그 이름도 이미 있으면 횟수를 늘린다.
Set<String> collectHeadingAnchors(String markdown) {
  final occurrences = <String, int>{};
  final anchors = <String>{};
  var inFence = false;
  for (final String line in markdown.split('\n')) {
    if (line.trimLeft().startsWith('```')) {
      inFence = !inFence;
      continue;
    }
    if (inFence) {
      continue;
    }
    final RegExpMatch? match = _headingLine.firstMatch(line);
    if (match == null) {
      continue;
    }
    final String slug = buildGithubAnchor(match.group(1)!.trim());
    var result = slug;
    while (occurrences.containsKey(result)) {
      final int count = (occurrences[slug] ?? 0) + 1;
      occurrences[slug] = count;
      result = '$slug-$count';
    }
    occurrences[result] = 0;
    anchors.add(result);
  }
  return anchors;
}

/// 마크다운 링크 하나 — 1부터 센 줄 번호와 링크 대상 원문(앵커 포함)이다.
typedef MarkdownLink = ({int line, String target});

/// 마크다운 [markdown] 에서 상대 링크 · 이미지 경로를 줄 순서대로 모은다.
///
/// 인라인 링크(`](…)` — 제목 따옴표는 뗀다)와 `<img … src="…">` 를 모은다. 코드
/// 펜스 안 · 인라인 코드 안은 보지 않고, URL 스킴으로 시작하는 대상은 뺀다. 앵커만인
/// 링크(`#…`)는 남긴다 — 같은 파일의 제목을 가리킨다.
List<MarkdownLink> collectRelativeLinks(String markdown) {
  final links = <MarkdownLink>[];
  final List<String> lines = markdown.split('\n');
  var inFence = false;
  for (var i = 0; i < lines.length; i++) {
    final String line = lines[i];
    if (line.trimLeft().startsWith('```')) {
      inFence = !inFence;
      continue;
    }
    if (inFence) {
      continue;
    }
    final String visible = line.replaceAll(_inlineCode, '');
    for (final pattern in <RegExp>[_inlineLinkTarget, _imageSource]) {
      for (final RegExpMatch match in pattern.allMatches(visible)) {
        final String target = match.group(1)!;
        if (!_schemePrefix.hasMatch(target)) {
          links.add((line: i + 1, target: target));
        }
      }
    }
  }
  return links;
}

/// 저장소 루트 기준 파일 [fromFile] 에서 링크 [target] 이 가리키는 경로를 돌려준다.
///
/// `#` 앞 경로만 보고 퍼센트 인코딩을 푼다. `/` 로 시작하면 저장소 루트 기준, 아니면
/// [fromFile] 의 디렉터리 기준이며 `.` · `..` 를 정규화한다. 앵커만인 링크는
/// [fromFile] 자신이고, 저장소 루트를 가리키면 빈 문자열이다. 저장소 밖으로 나가거나
/// 퍼센트 인코딩이 깨졌으면 `null` 이다.
String? resolveRepoPath(String fromFile, String target) {
  final int hash = target.indexOf('#');
  final String rawPath = hash == -1 ? target : target.substring(0, hash);
  if (rawPath.isEmpty) {
    return fromFile;
  }
  final String? decoded = decodePercentEncoding(rawPath);
  if (decoded == null) {
    return null;
  }
  final List<String> segments = decoded.startsWith('/')
      ? <String>[]
      : (fromFile.split('/')..removeLast());
  for (final String segment in decoded.split('/')) {
    if (segment.isEmpty || segment == '.') {
      continue;
    }
    if (segment == '..') {
      if (segments.isEmpty) {
        return null;
      }
      segments.removeLast();
      continue;
    }
    segments.add(segment);
  }
  return segments.join('/');
}
