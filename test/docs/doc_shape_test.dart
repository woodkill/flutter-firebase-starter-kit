// 사용자 문서 꼴 계약 — 할 일 한 줄 꼴.
//
// README.md · docs/setup.md · docs/guide.md 의 펜스 · 표 · 제목 밖 덩어리(문단 · 목록
// 항목 — 빈 줄이나 다음 항목 전까지 이어 쓴 줄을 합친 것)를 센다. 200자가 넘는 덩어리는
// 문장이 하나뿐이고, 맨 위 목록 항목(들여쓰기 0 번호 단계 · 글머리)은 한 문장, 하위 항목은
// 두 문장까지다 — 할 일 한 줄 꼴이 무너지지 않게 한다(`.claude/rules/docs-user-manual.md`
// §9).
//
// 어디서 도는가: 덩어리 · 문장 수 · 항목 판정 표본(FORM-01)은 어디서나 돈다. 세 문서
// 검사(FORM-02 · 03 · 04)는 킷 사용자가 자기 문서를 고치면 깨지는 내용 검사라 비공개 작업
// 일지가 있는 유지보수자 트리에서만 돈다.
//
// T-21-FORM-01: 덩어리 · 문장 수 · 맨 위 항목 · 하위 항목 판정의 양성 · 음성 표본.
// T-21-FORM-02: 세 문서마다 — 200자가 넘고 문장이 둘 이상인 덩어리 0.
// T-21-FORM-03: 세 문서의 덩어리 수 하한 — 덩어리 판정이 공허하지 않다(유지보수자 트리
//   전용).
// T-21-FORM-04: 세 문서마다 — 문장이 둘 이상인 맨 위 항목 · 문장이 셋 이상인 하위 항목 0.

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/planning_docs.dart';
import '../helpers/source_text.dart';

/// 유지보수자 트리에서만 도는 내용 검사의 skip 값이다.
final Object _skipMaintainer = skipUnlessPlanningDocsExist(<String>[
  '.planning/ROADMAP.md',
]);

/// 꼴을 세는 문서 — 이 셋뿐이다.
const List<String> _shapeDocPaths = <String>[
  'README.md',
  'docs/setup.md',
  'docs/guide.md',
];

/// 문서마다 덩어리 수의 하한 — 덩어리 판정이 공허하지 않음을 본다.
const Map<String, int> _minBlockCounts = <String, int>{
  'README.md': 10,
  'docs/setup.md': 300,
  'docs/guide.md': 600,
};

/// 한 줄로 세는 덩어리 글자 수의 상한이다(넘으면 문장이 하나여야 한다).
const int _maxMultiSentenceChars = 200;

/// 목록 표지(`숫자. ` · `- ` · `* ` · `+ `)로 시작하는 글.
final RegExp _listMarker = RegExp(r'^(\d+\. |[-*+] )');

/// 번호 표지(`숫자. `)로 시작하는 글.
final RegExp _numberMarker = RegExp(r'^\d+\. ');

/// 제목 줄(`#` 1 ~ 6개 + 공백).
final RegExp _headingLine = RegExp('^#{1,6} ');

/// 한글 한 글자.
final RegExp _koreanChar = RegExp('[가-힣]');

/// 백틱 구간.
final RegExp _backtickSpan = RegExp('`[^`]*`');

/// 링크 주소 `](…)`.
final RegExp _linkTarget = RegExp(r'\]\([^)]*\)');

/// `<http…>` 자동 링크.
final RegExp _autoLink = RegExp('<http[^>]*>');

/// 「…」 인용 — 인용한 메시지 · 라벨의 글자라 그 안의 부호는 문장 끝이 아니다.
final RegExp _cornerQuote = RegExp('「[^」]*」');

/// `숫자.숫자`(판 번호 · 소수).
final RegExp _dottedNumber = RegExp(r'\d+\.\d+');

/// 문장 끝 — `[.?!]` + 닫는 글자 0개 이상 + 공백이나 글 끝.
final RegExp _sentenceEnd = RegExp(r'''[.?!][)」』"'*]*(?=\s|$)''');

/// 꼴 덩어리 하나 — 문서 줄 번호 · 이은 글 · 인용 여부 · 들여쓰기 · 목록 항목 여부 ·
/// 하위 항목 여부다.
///
/// `line` 은 덩어리 첫 줄의 1 기준 줄 번호, `text` 는 인용 표지를 떼고 줄마다 앞뒤
/// 공백을 뗀 뒤 공백 하나로 이은 글(목록 표지 포함), `indent` 는 첫 줄의 인용 표지 뒤
/// 앞 공백 수다. `isSubItem` 은 들여 쓴 목록 항목이거나 문단 밑 0칸 글머리일 때 참이다.
typedef ProseBlock = ({
  int line,
  String text,
  bool isQuote,
  int indent,
  bool isListItem,
  bool isSubItem,
});

/// 덩어리를 모으는 동안 쓰는 가변 기록이다.
class _BlockDraft {
  _BlockDraft({
    required this.line,
    required this.text,
    required this.isQuote,
    required this.indent,
    required this.isAfterBreak,
  });

  /// 첫 줄의 1 기준 줄 번호다.
  final int line;

  /// 지금까지 이은 글이다.
  String text;

  /// 인용 덩어리인지다.
  final bool isQuote;

  /// 첫 줄의 앞 공백 수다.
  final int indent;

  /// 첫 줄 바로 앞 줄이 없거나 덩어리 줄이 아닌지(끊김 뒤)다.
  final bool isAfterBreak;
}

/// 줄 하나의 종류 — 덩어리 줄인지만 끊김 판정에 쓴다.
enum _LineKind { block, other }

/// 덩어리 판정에 필요한 값을 모은 기록이다.
typedef _ClassifiedBlock = ({
  _BlockDraft draft,
  int sentences,
  bool isList,
  bool isBullet,
  bool isPara,
  bool isExternal,
});

/// [text] 의 문장 수를 센다.
///
/// 백틱 구간 · 링크 주소 · `<http…>` 자동 링크 · 「…」 인용을 한 덩어리로 바꾸고, 머리
/// 목록 표지와 `숫자.숫자` 를 뗀 뒤 `[.?!]` + 닫는 글자(`)` · `」` · `』` · `"` · `'` ·
/// `*`) 0개 이상 + 공백이나 글 끝인 자리를 센다.
int countSentences(String text) {
  final String neutral = text
      .replaceAll(_backtickSpan, 'X')
      .replaceAll(_linkTarget, ']')
      .replaceAll(_autoLink, 'X')
      .replaceAll(_cornerQuote, 'X')
      .replaceFirst(_listMarker, '')
      .replaceAll(_dottedNumber, 'N');
  return _sentenceEnd.allMatches(neutral).length;
}

/// [markdown] 을 펜스 · 표 · 제목 밖 꼴 덩어리로 나눈 초안 목록을 돌려준다.
List<_BlockDraft> _scanDrafts(String markdown) {
  final List<String> lines = markdown.split('\n');
  final kinds = <_LineKind>[];
  final drafts = <_BlockDraft>[];
  var inFence = false;
  _BlockDraft? open;
  for (var i = 0; i < lines.length; i++) {
    final String raw = lines[i];
    if (raw.trimLeft().startsWith('```')) {
      inFence = !inFence;
      kinds.add(_LineKind.other);
      open = null;
      continue;
    }
    if (inFence || _headingLine.hasMatch(raw)) {
      kinds.add(_LineKind.other);
      open = null;
      continue;
    }
    final Match? quote = quoteMarkerHead.firstMatch(raw);
    final isQuote = quote != null;
    final String body = isQuote ? raw.substring(quote.end) : raw;
    final String trimmed = body.trim();
    if (trimmed.isEmpty ||
        body.trimLeft().startsWith('|') ||
        trimmed == '---') {
      kinds.add(_LineKind.other);
      open = null;
      continue;
    }
    if (open != null && open.isQuote != isQuote) {
      open = null;
    }
    if (open == null || _listMarker.hasMatch(body.trimLeft())) {
      final bool isAfterBreak = i == 0 || kinds[i - 1] != _LineKind.block;
      open = _BlockDraft(
        line: i + 1,
        text: trimmed,
        isQuote: isQuote,
        indent: body.length - body.trimLeft().length,
        isAfterBreak: isAfterBreak,
      );
      drafts.add(open);
    } else {
      open.text = '${open.text} $trimmed';
    }
    kinds.add(_LineKind.block);
  }
  return drafts;
}

/// [markdown] 의 꼴 덩어리를 모아 맨 위 항목 · 하위 항목을 가른 목록을 돌려준다.
///
/// 펜스 줄과 펜스 안 줄 · 제목 줄 · 표 줄 · 구분선 · 빈 줄은 덩어리 밖이고 열린 덩어리를
/// 끝낸다. 목록 표지로 시작하는 줄이나 열린 덩어리가 없을 때의 줄이 새 덩어리를 열고,
/// 그 밖의 줄은 열린 덩어리 글 뒤에 공백 하나로 잇는다. 인용 여부가 바뀌는 줄은 새
/// 덩어리를 연다. 한글이 없는 인용 덩어리(외부 원문 인용)는 항목 판정에는 쓰지만
/// 돌려주는 목록에서는 뺀다.
///
/// 들여쓰기 0 글머리가 끊김 뒤가 아니고, 앞으로 거슬러 올라가며 들여 쓴 목록 항목과
/// 끊김 뒤가 아닌 0칸 글머리를 건너뛰어 처음 닿는 덩어리가 0칸 문단 · 문장 하나 이상 ·
/// 같은 인용 여부이면 그 글머리는 문단 밑 하위 항목이다. 건너뛰는 도중 끊김 뒤인 0칸
/// 글머리를 만나면 하위 항목이 아니다.
List<ProseBlock> collectProseBlocks(String markdown) {
  final blocks = <_ClassifiedBlock>[
    for (final _BlockDraft d in _scanDrafts(markdown))
      (
        draft: d,
        sentences: countSentences(d.text),
        isList: _listMarker.hasMatch(d.text),
        isBullet:
            _listMarker.hasMatch(d.text) && !_numberMarker.hasMatch(d.text),
        isPara: !_listMarker.hasMatch(d.text),
        isExternal: d.isQuote && !_koreanChar.hasMatch(d.text),
      ),
  ];
  final out = <ProseBlock>[];
  for (var b = 0; b < blocks.length; b++) {
    final _ClassifiedBlock block = blocks[b];
    final bool isParaSub = _isParagraphSubItem(blocks, b);
    if (block.isExternal) {
      continue;
    }
    out.add((
      line: block.draft.line,
      text: block.draft.text,
      isQuote: block.draft.isQuote,
      indent: block.draft.indent,
      isListItem: block.isList,
      isSubItem: (block.isList && block.draft.indent > 0) || isParaSub,
    ));
  }
  return out;
}

/// [blocks] 의 [index] 번 덩어리가 문단 밑 0칸 하위 항목인지 판정한다.
bool _isParagraphSubItem(List<_ClassifiedBlock> blocks, int index) {
  final _ClassifiedBlock item = blocks[index];
  if (item.draft.indent != 0 || !item.isBullet || item.draft.isAfterBreak) {
    return false;
  }
  for (var j = index - 1; j >= 0; j--) {
    final _ClassifiedBlock prev = blocks[j];
    if (prev.isList && prev.draft.indent > 0) {
      continue;
    }
    if (prev.isBullet && prev.draft.indent == 0) {
      if (prev.draft.isAfterBreak) {
        return false;
      }
      continue;
    }
    return prev.isPara &&
        prev.draft.indent == 0 &&
        prev.sentences >= 1 &&
        prev.draft.isQuote == item.draft.isQuote;
  }
  return false;
}

/// [markdown] 에서 200자가 넘고 문장이 둘 이상인 덩어리를 찾아 위반 목록으로 돌려준다.
///
/// 항목은 `'{path}:{줄} — {글자}자 · {문장}문장'` 꼴이다.
List<String> findLongMultiSentenceBlocks(String path, String markdown) {
  final out = <String>[];
  for (final ProseBlock block in collectProseBlocks(markdown)) {
    final int chars = block.text.runes.length;
    final int sentences = countSentences(block.text);
    if (chars > _maxMultiSentenceChars && sentences >= 2) {
      out.add('$path:${block.line} — $chars자 · $sentences문장');
    }
  }
  return out;
}

/// [markdown] 에서 문장이 둘 이상인 맨 위 항목과 문장이 셋 이상인 하위 항목을 찾아
/// 위반 목록으로 돌려준다.
///
/// 항목은 `'{path}:{줄} — 맨 위 항목 {문장}문장'` 또는
/// `'{path}:{줄} — 하위 항목 {문장}문장'` 꼴이다.
List<String> findListItemShapeViolations(String path, String markdown) {
  final out = <String>[];
  for (final ProseBlock block in collectProseBlocks(markdown)) {
    final int sentences = countSentences(block.text);
    if (block.isSubItem) {
      if (sentences >= 3) {
        out.add('$path:${block.line} — 하위 항목 $sentences문장');
      }
    } else if (block.isListItem && sentences >= 2) {
      out.add('$path:${block.line} — 맨 위 항목 $sentences문장');
    }
  }
  return out;
}

/// 표본 문서의 경로 이름 — 위반 메시지 머리에 붙는다.
const String _samplePath = 'sample.md';

/// [count] 번 되풀이한 지어낸 구절이다 — 200자를 넘기는 표본을 만든다.
String _filler(int count) =>
    List<String>.filled(count, '표본 설명이 길게 이어지고').join(' ');

void main() {
  test('T-21-FORM-01: 덩어리 · 문장 수 · 항목 판정 표본', () {
    // (a) 200자 넘는 두 문장 문단 → 위반 1.
    final longTwo = '${_filler(16)} 첫 문장이 끝난다. 둘째 문장이 이어진다.';
    expect(findLongMultiSentenceBlocks(_samplePath, longTwo), <String>[
      '$_samplePath:1 — ${longTwo.runes.length}자 · 2문장',
    ]);

    // (b) 200자 넘는 한 문장 → 위반 0.
    final longOne = '${_filler(16)} 한 문장으로 끝난다.';
    expect(longOne.runes.length, greaterThan(200));
    expect(findLongMultiSentenceBlocks(_samplePath, longOne), isEmpty);

    // (c) 백틱 안 마침표 · 판 번호 · 링크 주소 안 마침표 · 머리 번호는 문장이 아니다.
    expect(
      countSentences('`a. b` 와 `c.d` 를 [안내](https://example.com/a.) 로 본다.'),
      1,
    );
    expect(countSentences('판 1.0.0 과 2.5 를 쓴다. 끝이다.'), 2);
    expect(countSentences('<https://example.com/a. b> 를 연다.'), 1);
    expect(countSentences('12. 번호 단계 한 문장이다.'), 1);

    // (d) 펜스 · 표 · 제목 안의 긴 글은 덩어리 밖 — 펜스는 열린 덩어리를 끝낸다.
    final String fenced = <String>[
      '## ${_filler(16)} 제목이다. 제목 둘째다.',
      '| ${_filler(16)} 칸이다. 칸 둘째다. |',
      '```text',
      '${_filler(16)} 펜스 안이다. 펜스 둘째다.',
      '```',
      '짧은 문단이다.',
    ].join('\n');
    expect(findLongMultiSentenceBlocks(_samplePath, fenced), isEmpty);
    final List<ProseBlock> fencedBlocks = collectProseBlocks(fenced);
    expect(fencedBlocks.map((ProseBlock b) => b.line), <int>[6]);
    expect(fencedBlocks.single.text, '짧은 문단이다.');

    // (e) 이어 쓴 세 줄을 합쳐 200자 넘는 두 문장 → 위반 1(줄마다는 200자 이하).
    final String wrapped = <String>[
      _filler(9),
      '${_filler(9)} 첫 문장이 끝난다.',
      '둘째 문장이 이어진다.',
    ].join('\n');
    expect(
      wrapped.split('\n').every((String l) => l.runes.length <= 200),
      isTrue,
    );
    final List<ProseBlock> wrappedBlocks = collectProseBlocks(wrapped);
    expect(wrappedBlocks, hasLength(1));
    expect(wrappedBlocks.single.text, wrapped.split('\n').join(' '));
    expect(findLongMultiSentenceBlocks(_samplePath, wrapped), hasLength(1));

    // (f) 한글 없는 인용 덩어리는 빠지고, 한글 인용은 센다.
    final String english = List<String>.filled(
      30,
      'plain sample words',
    ).join(' ');
    final String quotes = <String>[
      '> $english. Second sentence here.',
      '',
      '> ${_filler(16)} 인용 첫 문장이다. 인용 둘째 문장이다.',
    ].join('\n');
    final List<ProseBlock> quoteBlocks = collectProseBlocks(quotes);
    expect(quoteBlocks.map((ProseBlock b) => b.line), <int>[3]);
    expect(quoteBlocks.single.isQuote, isTrue);
    expect(findLongMultiSentenceBlocks(_samplePath, quotes), hasLength(1));

    // (g) 굵게 닫힘 바로 앞 마침표는 문장 끝이다.
    expect(countSentences('**굵게 끝난다.** 다음 문장이다.'), 2);

    // (h) 「」 안 번호 · 마침표 · 물음표는 문장 끝이 아니다.
    expect(countSentences('둘째 칸 「2. 이름」 을 고른다.'), 1);
    expect(countSentences('창에 「저장했습니다. 잠시 기다려 주세요.」 가 뜬다.'), 1);
    expect(countSentences('「다시 할까요?」 를 누른다. 끝이다.'), 2);

    // (i) 문장 문단 바로 아래 0칸 글머리는 하위 항목 — 두 문장까지 통과.
    final String paraSub = <String>[
      '문단 첫 문장이다.',
      '- 하위 첫 문장이다. 하위 둘째 문장이다.',
      '- 하위 셋째 문장이다. 하위 넷째 문장이다.',
    ].join('\n');
    expect(findListItemShapeViolations(_samplePath, paraSub), isEmpty);
    expect(
      collectProseBlocks(paraSub).map((ProseBlock b) => b.isSubItem),
      <bool>[false, true, true],
    );
    //     같은 글머리가 빈 줄 뒤면 맨 위 항목 → 위반.
    final String blankTop = <String>[
      '문단 첫 문장이다.',
      '',
      '- 첫 문장이다. 둘째 문장이다.',
    ].join('\n');
    expect(findListItemShapeViolations(_samplePath, blankTop), <String>[
      '$_samplePath:3 — 맨 위 항목 2문장',
    ]);

    // (j) 들여 쓴 하위 항목 — 두 문장은 통과, 세 문장은 위반.
    final String subTwo = <String>[
      '1. 단계를 한다.',
      '   - 하위 첫 문장이다. 하위 둘째 문장이다.',
    ].join('\n');
    expect(findListItemShapeViolations(_samplePath, subTwo), isEmpty);
    final String subThree = <String>[
      '1. 단계를 한다.',
      '   - 첫째다. 둘째다. 셋째다.',
    ].join('\n');
    expect(findListItemShapeViolations(_samplePath, subThree), <String>[
      '$_samplePath:2 — 하위 항목 3문장',
    ]);

    // (k) 맨 위 번호 단계의 짧은 두 문장 → 위반.
    expect(
      findListItemShapeViolations(_samplePath, '1. 첫 문장이다. 둘째 문장이다.'),
      <String>['$_samplePath:1 — 맨 위 항목 2문장'],
    );
  });

  group('세 문서 200자 덩어리', () {
    for (final String path in _shapeDocPaths) {
      test('T-21-FORM-02: 200자 넘는 다문장 덩어리 0 — $path', () {
        final List<String> violations = findLongMultiSentenceBlocks(
          path,
          readTrackedFile(path),
        );
        // 결과 한 줄 — 여러 파일을 함께 돌려도 시험 로그에 이 시험 ID 가 남는다.
        debugPrintSynchronously('T-21-FORM-02 $path: 위반 ${violations.length}건');
        expect(
          violations,
          isEmpty,
          reason: '200자가 넘는 덩어리는 문장이 하나뿐이다 — 문장마다 하위 항목으로 나눈다',
        );
      }, skip: _skipMaintainer);
    }
  });

  test('T-21-FORM-03: 세 문서 덩어리 수 하한', () {
    final counts = <String, int>{
      for (final String path in _shapeDocPaths)
        path: collectProseBlocks(readTrackedFile(path)).length,
    };
    // 결과 한 줄 — 여러 파일을 함께 돌려도 시험 로그에 이 시험 ID 가 남는다.
    debugPrintSynchronously('T-21-FORM-03 덩어리 수: $counts');
    for (final MapEntry<String, int> min in _minBlockCounts.entries) {
      expect(
        counts[min.key],
        greaterThanOrEqualTo(min.value),
        reason: '${min.key} 덩어리가 적다 — 덩어리 판정이 공허하다',
      );
    }
  }, skip: _skipMaintainer);

  group('세 문서 목록 항목 문장 수', () {
    for (final String path in _shapeDocPaths) {
      test('T-21-FORM-04: 맨 위 항목 한 문장 · 하위 항목 두 문장까지 — $path', () {
        final List<String> violations = findListItemShapeViolations(
          path,
          readTrackedFile(path),
        );
        // 결과 한 줄 — 여러 파일을 함께 돌려도 시험 로그에 이 시험 ID 가 남는다.
        debugPrintSynchronously('T-21-FORM-04 $path: 위반 ${violations.length}건');
        expect(violations, isEmpty, reason: '맨 위 목록 항목은 한 문장, 하위 항목은 두 문장까지다');
      }, skip: _skipMaintainer);
    }
  });
}
