// 디자인 리터럴 소스 스캔 가드 — 킷 소스 스캔 1단계.
//
// `lib/` 의 화면 · 공용 코드에 색 · 간격 · 둥글기 · 글자 · 아이콘 · 투명도 · 시간
// 리터럴이 디자인 토큰을 거치지 않고 다시 생기는지 정규식으로 찾는다. 사용 가이드
// 「디자인 토큰 바꾸기」 의 표 「쓰지 않는 것」 열이 [kDesignLiteralPatterns] 의
// 패턴 이름과 1:1 이다.
//
// analyzer 를 쓰지 않는다 — 줄 머리 `//` 주석 줄 · 블록 주석을 같은 줄 수의 빈
// 줄로 바꾸고(줄 끝 `//` 주석은 남긴다) 공백을 한 칸으로 접은 텍스트에서 이름
// 붙인 정규식을 찾는 순수 함수다. 예외는 폴더 · 파일 제외 목록과 줄 표시
// 주석(리터럴 줄 바로 윗줄의 `// design-literal: <이유>` 행 주석)뿐이다.
//
// 이 파일의 블록 주석은 Dart 문법이 아니라 글자로 정한다 — 줄 머리 `//` 주석
// 줄을 비운 뒤 `/*` 부터 그 뒤 가장 가까운 `*/` 까지이고, 문자열 · 줄 끝 `//`
// 주석 안의 `/*` · `*/` 도 시작 · 끝으로 보며, 뒤에 `*/` 가 없는 `/*` 는
// 블록 주석이 아니다.

import 'dart:io';

/// 줄 예외 표시 주석의 머리 글자다.
///
/// 리터럴이 있는 줄(여러 줄 호출은 숫자가 있는 인자 줄) 바로 윗줄에 이 머리 +
/// 공백 하나 + 이유 글자로 시작하는 행 주석을 두면 그 줄의 리터럴을 건너뛴다.
/// 이유가 없으면 표시로 치지 않는다.
const String kDesignLiteralMarker = '// design-literal:';

/// 이름을 붙인 디자인 리터럴 정규식 하나다.
///
/// `presentationOnly` 가 참인 패턴은 화면 · 공용 폴더([isDurationScopePath])
/// 파일에서만 본다.
typedef DesignLiteralPattern = ({
  String name,
  RegExp pattern,
  bool presentationOnly,
});

/// 디자인 리터럴 패턴 20개다 — 범주 순서대로 적는다.
///
/// - 색: Material 색 상수 · 8자리 16진 색 · 성분으로 만든 색.
/// - 글자: 숫자 글자 크기 · 굵기 상수 · 글자 스타일 생성자.
/// - 간격 · 둥글기 · 아이콘 · 투명도 · 높이: 인자 이름 바로 뒤 숫자.
/// - 시간 · 곡선: Duration 생성자(화면 · 공용 폴더만 — 표시된 이름 붙인 선언만
///   통과) · 곡선 상수.
/// - 선 · 폭 · 크기: 테두리 굵기 · 폭 비교 숫자 · 숫자 크기 상자 · 간격 토큰을
///   크기로 쓴 상자 · 진행 표시 굵기.
/// - 비율: 1 미만 소수(`0.x` · `.x`) 곱 — 소수가 곱의 앞이든 뒤든.
///
/// 숫자는 「인자 이름: 숫자」 꼴로만 잡는다 — `const double _kX = 40;` 같은 이름
/// 붙인 상수 선언 자체는 걸리지 않는다. `EdgeInsets` · `SizedBox` 는 숫자
/// 인자마다 따로 잡고, 0 도 숫자 리터럴이다.
///
/// `EdgeInsets` · `SizedBox` 패턴과 여는 괄호 바로 뒤 숫자를 보는 패턴(`Gap(` ·
/// `Radius.circular(` · `Color.fromARGB(` 등)은 접은 텍스트에서 숫자 인자
/// (`이름:` 포함) 바로 앞이 공백만 두고 ① 호출의 여는 괄호이거나 ② 쉼표이고
/// 여는 괄호 바로 뒤부터 그 쉼표 직전까지가 닫는 괄호 없이 400자 이하일 때만
/// 잡는다 — ② 는 `EdgeInsets` · `SizedBox` 패턴만 본다. 괄호 · 쉼표는 코드 ·
/// 줄 끝 `//` 주석 · 문자열 어디에 있든 센다. 400자는
/// [findDesignLiteralHits] 순서 2 · 3 을 거친 텍스트에서 센 글자 수다 —
/// 쉼표 뒤 공백은 세지 않는다.
///
/// 모든 패턴은 길이 1 이상 일치만 낸다 — 적중 줄을 일치 마지막 글자의 줄로
/// 계산하는 [findDesignLiteralHits] 의 전제다.
final List<DesignLiteralPattern> kDesignLiteralPatterns =
    <DesignLiteralPattern>[
      (
        name: 'material-colors',
        pattern: RegExp(r'\bColors\.\w'),
        presentationOnly: false,
      ),
      (
        name: 'color-hex',
        pattern: RegExp(r'\bColor\(\s*0x[0-9A-Fa-f]{8}\s*\)'),
        presentationOnly: false,
      ),
      (
        name: 'color-from-components',
        pattern: RegExp(r'\bColor\.from(?:ARGB|RGBO)\(\s*\d'),
        presentationOnly: false,
      ),
      (
        name: 'font-size-number',
        pattern: RegExp(r'\bfontSize:\s*\d'),
        presentationOnly: false,
      ),
      (
        name: 'font-weight-literal',
        pattern: RegExp(r'\bfontWeight:\s*FontWeight\.\w'),
        presentationOnly: false,
      ),
      (
        name: 'text-style-constructor',
        pattern: RegExp(r'\bTextStyle\('),
        presentationOnly: false,
      ),
      (
        name: 'edge-insets-number',
        pattern: RegExp(
          r'(?<=\bEdgeInsets(?:Directional)?\.\w+\((?:[^)]{0,400},)?\s*)'
          r'(?:\w+:\s*)?\d',
        ),
        presentationOnly: false,
      ),
      (
        name: 'gap-number',
        pattern: RegExp(r'\bGap\(\s*\d'),
        presentationOnly: false,
      ),
      (
        name: 'radius-number',
        pattern: RegExp(r'Radius\.circular\(\s*\d'),
        presentationOnly: false,
      ),
      (
        name: 'icon-size-number',
        pattern: RegExp(r'(?:\bsize|iconSize):\s*\d'),
        presentationOnly: false,
      ),
      (
        name: 'alpha-number',
        pattern: RegExp(
          r'\b(?:alpha|opacity):\s*\d|\bwith(?:Opacity|Alpha)\(\s*\d',
        ),
        presentationOnly: false,
      ),
      (
        name: 'elevation-number',
        pattern: RegExp(r'\belevation:\s*\d'),
        presentationOnly: false,
      ),
      (
        name: 'duration-literal',
        pattern: RegExp(r'\bDuration\('),
        presentationOnly: true,
      ),
      (
        name: 'curves-literal',
        pattern: RegExp(r'\bCurves\.\w'),
        presentationOnly: false,
      ),
      (
        name: 'border-width-number',
        pattern: RegExp(r'\b(?:BorderSide|Border\.all)\([^)]*\bwidth:\s*\d'),
        presentationOnly: false,
      ),
      (
        name: 'width-compare-number',
        pattern: RegExp(r'(?:\bwidth|Width)\s*[<>]=?\s*\d'),
        presentationOnly: false,
      ),
      (
        name: 'sized-box-number',
        pattern: RegExp(
          r'(?<=\bSizedBox(?:\.square)?\((?:[^)]{0,400},)?\s*)'
          r'(?:width|height|dimension):\s*\d',
        ),
        presentationOnly: false,
      ),
      (
        name: 'spacing-as-size',
        pattern: RegExp(r'\bSizedBox\.square\(\s*dimension:\s*spacing\.'),
        presentationOnly: false,
      ),
      (
        name: 'stroke-width-number',
        pattern: RegExp(r'\bstrokeWidth:\s*\d'),
        presentationOnly: false,
      ),
      (
        name: 'ratio-literal',
        pattern: RegExp(r'\*\s*0?\.\d|(?<![\w.])0?\.\d+\s*\*'),
        presentationOnly: false,
      ),
    ];

/// 통째로 스캔하지 않는 폴더 접두다.
///
/// 테마 폴더는 토큰 값을 정의하는 곳이고, 생성된 다국어 코드는 손으로 고치지 않는다.
const List<String> kDesignLiteralExcludedPrefixes = <String>[
  'lib/core/theme/',
  'lib/l10n/generated/',
];

/// 통째로 스캔하지 않는 파일이다.
///
/// `lib/app.dart` 는 테마를 조립하는 파일이라 킷 사용자가 테마의 `copyWith`
/// override 를 두는 자리다. 브랜드 버튼 파일은 provider 브랜드 가이드의 고정
/// 색 · 치수를 그대로 그린다.
const List<String> kDesignLiteralExcludedFiles = <String>[
  'lib/app.dart',
  'lib/features/auth/presentation/_widgets/branded_social_button.dart',
];

/// 코드 생성 파일 꼬리다 — 이 꼬리로 끝나는 파일은 스캔하지 않는다.
const List<String> kGeneratedDartSuffixes = <String>[
  '.g.dart',
  '.freezed.dart',
  '.gr.dart',
  '.gen.dart',
];

/// 이름 붙인 Duration 선언 규칙을 쓰는 패턴의 이름이다.
const String _durationPatternName = 'duration-literal';

/// 유효한 표시 주석 줄 — 줄 앞 공백 뒤 표시 머리 + 공백 하나 + 공백 아닌 글자.
final RegExp _markerLine = RegExp(
  '^\\s*${RegExp.escape(kDesignLiteralMarker)} \\S',
);

/// 블록 주석(정의는 파일 머리 주석)을 찾는 정규식이다.
final RegExp _blockComment = RegExp(r'/\*.*?\*/', dotAll: true);

/// Duration 일치 바로 앞이 이름 붙인 선언 머리로 끝나는지 보는 정규식이다.
final RegExp _durationDeclarationHead = RegExp(
  r'(?:static\s+)?const\s+Duration\s+\w+\s*=\s*$',
);

/// 저장소 루트 기준 경로 [path] 가 스캔 대상이면 참을 돌려준다.
///
/// 대상 = `lib/` 아래 `.dart` 가운데 생성 파일([kGeneratedDartSuffixes]) ·
/// 제외 폴더([kDesignLiteralExcludedPrefixes]) · 제외 파일
/// ([kDesignLiteralExcludedFiles])이 아닌 것.
bool isDesignLiteralScanTarget(String path) {
  if (!path.startsWith('lib/') || !path.endsWith('.dart')) {
    return false;
  }
  if (kGeneratedDartSuffixes.any(path.endsWith)) {
    return false;
  }
  if (kDesignLiteralExcludedPrefixes.any(path.startsWith)) {
    return false;
  }
  return !kDesignLiteralExcludedFiles.contains(path);
}

/// 경로 [path] 가 Duration 패턴을 보는 화면 · 공용 폴더면 참을 돌려준다.
///
/// `lib/shared/` 로 시작하거나 경로에 `/presentation/` 이 든 파일이다. data ·
/// application 폴더의 타임아웃 · 재시도 간격은 대상 밖이다.
bool isDurationScopePath(String path) =>
    path.startsWith('lib/shared/') || path.contains('/presentation/');

/// `lib/` 를 순회해 스캔 대상 경로를 `/` 구분자로 정렬해 돌려준다.
///
/// tracked 목록이 아니라 디렉터리를 순회한다 — 아직 커밋하지 않은 파일도 잡는다.
/// `flutter test` 의 작업 디렉터리 = 프로젝트 루트다. `lib/` 가 없으면 빈 목록이다.
List<String> collectDesignLiteralScanPaths() {
  final root = Directory('lib');
  if (!root.existsSync()) {
    return <String>[];
  }
  final paths = <String>[];
  for (final FileSystemEntity entity in root.listSync(recursive: true)) {
    if (entity is! File) {
      continue;
    }
    final String path = entity.path.replaceAll(Platform.pathSeparator, '/');
    if (isDesignLiteralScanTarget(path)) {
      paths.add(path);
    }
  }
  return paths..sort();
}

/// 소스 [source] 의 유효한 표시 주석 줄 수를 돌려준다.
///
/// 줄 앞 공백 뒤 [kDesignLiteralMarker] + 공백 하나 + 공백 아닌 글자로 시작하는
/// 줄만 센다 — 이유 없는 표시 · 문서 주석 · 줄 끝 주석은 세지 않는다.
int countDesignLiteralMarkers(String source) =>
    source.split('\n').where(_markerLine.hasMatch).length;

/// 소스 [source] 에서 디자인 리터럴을 찾아 `'<path>:<줄> — <이름>'` 목록으로
/// 돌려준다.
///
/// [path] 는 저장소 루트 기준 경로이고 Duration 범위([isDurationScopePath])를
/// 고르는 데 쓴다. 순서:
///
/// 1. 줄로 나눠, 바로 윗줄이 유효한 표시 주석인 줄 번호를 모은다 — 주석 제거 ·
///    공백 접기 **전**이다.
/// 2. 줄 머리가 `//` 인 줄(문서 주석 포함)을 빈 줄로 바꾸고, 블록 주석을 그 안
///    줄바꿈 수만큼의 줄바꿈으로 바꾼다 — 줄 수가 그대로다. 줄 머리 `//` 줄을
///    먼저 비우므로 그 줄 안의 `/*` · `*/` 는 블록 주석의 시작 · 끝이 되지
///    않는다.
/// 3. 공백 문자 연속(스페이스 · 탭 · 줄바꿈)을 한 칸으로 접고, 접은 글자마다 원문
///    줄 번호를 기록한다 — 여러 줄 호출도 한 줄처럼 찾는다. 이 순서의 글자와
///    접은 텍스트에서 센 글자 수는 UTF-16 code unit(`String.length` 의 단위)이다.
/// 4. 패턴마다(화면 · 공용 폴더 한정 패턴은 그 폴더 파일에서만) 모든 일치의 줄 =
///    일치 마지막 글자의 원문 줄이다. 그 줄이 1 의 표시 줄이면 건너뛴다. Duration
///    패턴만 다르다 — 일치 앞이 `(static) const Duration <이름> =` 선언 머리로
///    끝나고 그 선언 첫 글자의 줄이 표시 줄일 때만 건너뛴다(인라인은 표시가
///    있어도 위반).
/// 5. 위반을 줄 순 · 같은 줄은 패턴 순으로, 줄 · 패턴마다 한 번씩 돌려준다.
List<String> findDesignLiteralHits(String path, String source) {
  final List<String> lines = source.split('\n');
  final markedLines = <int>{
    for (var i = 0; i + 1 < lines.length; i++)
      if (_markerLine.hasMatch(lines[i])) i + 2,
  };

  final String uncommented = _blankLineComments(lines).replaceAllMapped(
    _blockComment,
    (Match match) => '\n' * '\n'.allMatches(match[0]!).length,
  );

  final collapsed = StringBuffer();
  final lineOfChar = <int>[];
  var line = 1;
  var inWhitespace = false;
  for (final int unit in uncommented.codeUnits) {
    final isNewline = unit == 0x0A;
    final bool isWhitespace =
        isNewline || unit == 0x20 || unit == 0x09 || unit == 0x0D;
    if (isWhitespace) {
      if (!inWhitespace) {
        collapsed.writeCharCode(0x20);
        lineOfChar.add(line);
      }
      inWhitespace = true;
    } else {
      collapsed.writeCharCode(unit);
      lineOfChar.add(line);
      inWhitespace = false;
    }
    if (isNewline) {
      line++;
    }
  }
  final text = collapsed.toString();

  final hitsByLine = <int, Set<int>>{};
  for (var p = 0; p < kDesignLiteralPatterns.length; p++) {
    final DesignLiteralPattern named = kDesignLiteralPatterns[p];
    if (named.presentationOnly && !isDurationScopePath(path)) {
      continue;
    }
    final isDuration = named.name == _durationPatternName;
    for (final RegExpMatch match in named.pattern.allMatches(text)) {
      final int hitLine = lineOfChar[match.end - 1];
      if (isDuration) {
        final RegExpMatch? head = _durationDeclarationHead.firstMatch(
          text.substring(0, match.start),
        );
        if (head != null && markedLines.contains(lineOfChar[head.start])) {
          continue;
        }
      } else if (markedLines.contains(hitLine)) {
        continue;
      }
      (hitsByLine[hitLine] ??= <int>{}).add(p);
    }
  }

  final List<int> hitLines = hitsByLine.keys.toList()..sort();
  return <String>[
    for (final int hitLine in hitLines)
      for (final int p in hitsByLine[hitLine]!.toList()..sort())
        '$path:$hitLine — ${kDesignLiteralPatterns[p].name}',
  ];
}

/// 줄 머리가 `//` 인 줄을 빈 줄로 바꿔 다시 잇는다 — 줄 수가 그대로다.
String _blankLineComments(List<String> lines) => lines
    .map((String line) => line.trimLeft().startsWith('//') ? '' : line)
    .join('\n');
