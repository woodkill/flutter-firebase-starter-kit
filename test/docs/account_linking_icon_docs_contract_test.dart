// Phase 25 — 계정 연결 아이콘 버튼 문서 불변식 계약 (SC6).
//
// **책임 범위:** `docs/guide.md` 「알고 둔 가이드와의 차이」 표의 데이터 행 수가
// 그 수를 적은 두 문장(한글 수사)과 같은지, 브랜드 README 6개의
// `## 아이콘 단독 사용` 절이 정확히 1개씩인지, Facebook · Kakao README 와 가이드의
// 「Facebook 검수 전」 가리킴이 살아 있는지 고정한다. 앵커 해석 자체는
// `links_test.dart` 가 맡는다.
//
// **어디서 도는가:** 한글 수사 해석기 · 표 행 수 판정 함수의 샘플 시험은 어디서나
// 돈다. 실제 문서를 읽는 시험은 킷 유지보수자 트리에서만 돈다 — 킷 사용자는
// 문서를 고쳐 쓴다.
//
// **시험 ID:** T-25-DOC-01 (수사 해석기) · T-25-DOC-02 (표 행 수 판정 함수) ·
// T-25-DOC-03 (표 행 수 = 두 문장 수사) · T-25-DOC-04 (README 절 1개) ·
// T-25-DOC-05 (Facebook 검수 전 가리킴 · 단락 제목 1개).

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../helpers/planning_docs.dart';

const String _kGuidePath = 'docs/guide.md';
const String _kDiffHeading = '**알고 둔 가이드와의 차이.**';
const String _kFacebookHeading = '**Facebook 검수 전.**';
const String _kIconSectionHeading = '## 아이콘 단독 사용';
const List<String> _kProviders = <String>[
  'apple',
  'facebook',
  'google',
  'kakao',
  'line',
  'naver',
];

const Map<String, int> _kNumerals = <String, int>{
  '하나': 1,
  '둘': 2,
  '셋': 3,
  '넷': 4,
  '다섯': 5,
  '여섯': 6,
  '일곱': 7,
  '여덟': 8,
  '아홉': 9,
  '열': 10,
  '열하나': 11,
  '열둘': 12,
  '열셋': 13,
  '열넷': 14,
  '열다섯': 15,
  '열여섯': 16,
  '열일곱': 17,
  '열여덟': 18,
  '열아홉': 19,
  '스물': 20,
};

/// 한글 고유어 수사([word])를 정수로 돌려준다. 모르는 낱말이면 `null`.
int? parseKoreanCount(String word) => _kNumerals[word];

/// 「차이」 절의 표 데이터 행 수를 센다 — 절 제목 뒤 첫 표의 머리 · 구분선을 뺀 행.
///
/// 절 제목이나 표가 없으면 -1 을 돌려준다.
int countDiffTableRows(String guide) {
  final lines = guide.split('\n');
  final start = lines.indexWhere((l) => l.trim() == _kDiffHeading);
  if (start < 0) {
    return -1;
  }
  var index = start + 1;
  while (index < lines.length && !lines[index].startsWith('|')) {
    index++;
  }
  var pipeLines = 0;
  while (index < lines.length && lines[index].startsWith('|')) {
    pipeLines++;
    index++;
  }
  return pipeLines < 2 ? -1 : pipeLines - 2;
}

/// 가이드에서 두 문장이 적은 수사 낱말을 순서대로 돌려준다(못 찾은 문장은 생략).
List<String> extractCountWords(String guide) {
  final first = RegExp(r'다르게 둔 곳이 (\S+) 있다').firstMatch(guide);
  // 조사는 수사 끝소리에 따라 「을」(아홉을) · 「를」(열하나를) 둘 다 받는다.
  final second = RegExp(
    r'「알고 둔 가이드와의 차이」 (\S+?)(?:을|를) 내 앱에',
  ).firstMatch(guide);
  return <String>[?first?.group(1), ?second?.group(1)];
}

/// [text] 에서 [heading] 과 정확히 같은 줄의 수.
int countHeadingLines(String text, String heading) =>
    text.split('\n').where((l) => l.trimRight() == heading).length;

/// README 에 가이드 앵커 링크와 「Facebook 검수 전」 을 함께 적은 줄이 있는가.
bool hasReviewPointer(String readme) {
  final link = RegExp(r'\]\([^)]*docs/guide\.md#[^)]*\)');
  return readme
      .split('\n')
      .any((l) => link.hasMatch(l) && l.contains('「Facebook 검수 전」'));
}

String _read(String path) => File(path).readAsStringSync();

void main() {
  test('T-25-DOC-01 수사 해석기는 하나~스물을 풀고 모르는 낱말은 null', () {
    expect(parseKoreanCount('하나'), 1);
    expect(parseKoreanCount('넷'), 4);
    expect(parseKoreanCount('여덟'), 8);
    expect(parseKoreanCount('아홉'), 9);
    expect(parseKoreanCount('열'), 10);
    expect(parseKoreanCount('스물'), 20);
    expect(parseKoreanCount('아흔'), isNull);
    expect(parseKoreanCount(''), isNull);
  });

  test('T-25-DOC-02 표 행 수 판정 함수는 머리 · 구분선을 빼고 센다', () {
    const sample =
        '$_kDiffHeading\n- 문장\n\n| a | b |\n|---|---|\n| 1 | 2 |\n| 3 | 4 |\n\n끝\n';
    expect(countDiffTableRows(sample), 2);
    expect(countDiffTableRows('표 없음'), -1);
    expect(countDiffTableRows('$_kDiffHeading\n| a |\n|---|\n'), 0);
    expect(
      extractCountWords('다르게 둔 곳이 아홉 있다.\n「알고 둔 가이드와의 차이」 아홉을 내 앱에'),
      <String>['아홉', '아홉'],
    );
    expect(
      extractCountWords('다르게 둔 곳이 열하나 있다.\n「알고 둔 가이드와의 차이」 열하나를 내 앱에'),
      <String>['열하나', '열하나'],
    );
    expect(countHeadingLines('a\n## x\n## x\n', '## x'), 2);
    expect(hasReviewPointer('[g](../docs/guide.md#a) 「Facebook 검수 전」'), isTrue);
    expect(hasReviewPointer('[g](../docs/guide.md#a) 없음'), isFalse);
  });

  group('실제 문서 (유지보수자 트리 전용)', () {
    test('T-25-DOC-03 표 데이터 행 수는 두 문장의 수사와 같다', () {
      final guide = _read(_kGuidePath);
      final rows = countDiffTableRows(guide);
      // 양성 대조 — 빈 표가 우연히 통과하지 않게 한다.
      expect(rows, greaterThan(0), reason: '차이 표를 찾지 못했다');
      final words = extractCountWords(guide);
      expect(words, hasLength(2), reason: '수를 적은 두 문장 중 하나가 없다');
      for (final word in words) {
        expect(parseKoreanCount(word), rows, reason: '「$word」 문장이 표 행 수와 다르다');
      }
      // 현재 값 고정 — 행을 더하거나 빼면 표와 두 문장을 함께 고치라는 신호다.
      expect(rows, 9);
    }, skip: skipUnlessMaintainerTree());

    test('T-25-DOC-04 브랜드 README 6개에 아이콘 단독 사용 절이 정확히 1개', () {
      for (final provider in _kProviders) {
        final readme = _read('assets/brand/$provider/README.md');
        expect(
          countHeadingLines(readme, _kIconSectionHeading),
          1,
          reason: '$provider README 의 「$_kIconSectionHeading」 절 수',
        );
      }
    }, skip: skipUnlessMaintainerTree());

    test('T-25-DOC-05 Facebook 검수 전 가리킴과 단락 제목이 살아 있다', () {
      for (final provider in <String>['facebook', 'kakao']) {
        expect(
          hasReviewPointer(_read('assets/brand/$provider/README.md')),
          isTrue,
          reason: '$provider README 에 가이드 링크 + 「Facebook 검수 전」 줄이 없다',
        );
      }
      expect(countHeadingLines(_read(_kGuidePath), _kFacebookHeading), 1);
    }, skip: skipUnlessMaintainerTree());
  });
}
