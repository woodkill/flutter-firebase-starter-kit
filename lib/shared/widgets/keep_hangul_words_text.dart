import 'package:flutter/widgets.dart';

/// 이음 문자(U+2060 WORD JOINER) — 앞뒤 글자 사이에서 줄을 바꾸지 않게 한다.
final String _wordJoiner = String.fromCharCode(0x2060);

/// 한글 음절(가 ~ 힣) 하나.
final RegExp _hangulSyllable = RegExp('[가-힣]');

/// [grapheme] 이 덩어리를 나누는 공백(띄어쓰기 · 줄바꿈 · 탭)인지 본다.
///
/// 줄바꿈은 LF · CR, 그리고 한 글자로 묶이는 CRLF 다.
bool _isSpace(String grapheme) =>
    grapheme == ' ' ||
    grapheme == '\n' ||
    grapheme == '\r\n' ||
    grapheme == '\r' ||
    grapheme == '\t';

/// [codePoint] 가 아래 코드 포인트 범위 가운데 하나에 드는지 본다.
///
/// 감싸개가 묶지 않는 예외 경계의 범위는 이 목록 한 곳에서 정한다 — CJK
/// 문장부호 · 가나 · 한자 · 전각 기호의 범위를 담지만, 같은 범주라도 이 목록 밖
/// 코드 포인트는 예외가 아니다.
bool _isCjkNonHangul(int codePoint) =>
    (codePoint >= 0x3000 && codePoint <= 0x303F) ||
    (codePoint >= 0x3040 && codePoint <= 0x30FF) ||
    (codePoint >= 0x3400 && codePoint <= 0x4DBF) ||
    (codePoint >= 0x4E00 && codePoint <= 0x9FFF) ||
    (codePoint >= 0xF900 && codePoint <= 0xFAFF) ||
    (codePoint >= 0xFF01 && codePoint <= 0xFF9F) ||
    (codePoint >= 0x20000 && codePoint <= 0x3FFFF);

/// 맞닿은 두 글자 [before] · [after] 사이를 원래 줄바꿈 규칙에 맡길지 본다.
///
/// 둘 가운데 하나라도 [_isCjkNonHangul] 의 범위 안 코드 포인트를 담으면 참이다.
bool _isExceptionBoundary(String before, String after) {
  return before.runes.any(_isCjkNonHangul) || after.runes.any(_isCjkNonHangul);
}

/// [text] 를 글자(grapheme) 조각 목록으로 나누고 이음 문자 조각을 끼운다.
///
/// 공백으로 나뉜 덩어리에 한글 음절이 하나라도 있으면 그 덩어리 안 글자
/// 사이마다 이음 문자 조각을 둔다. 예외 경계와 한글이 없는 덩어리는 그대로다.
List<String> _splitWithJoiners(String text) {
  final pieces = <String>[];
  final chunk = <String>[];

  void flushChunk() {
    final hasHangul = chunk.any(_hangulSyllable.hasMatch);
    for (var i = 0; i < chunk.length; i++) {
      if (hasHangul && i > 0 && !_isExceptionBoundary(chunk[i - 1], chunk[i])) {
        pieces.add(_wordJoiner);
      }
      pieces.add(chunk[i]);
    }
    chunk.clear();
  }

  for (final grapheme in text.characters) {
    if (_isSpace(grapheme)) {
      flushChunk();
      pieces.add(grapheme);
    } else {
      chunk.add(grapheme);
    }
  }
  flushChunk();
  return pieces;
}

/// [text] 를 이음 문자만 글자 간격 0 인 자식 span 으로 끼운 [TextSpan] 으로 만든다.
///
/// 나머지 글자는 스타일 없는 자식 span 이라 부모 스타일을 그대로 받는다.
TextSpan _buildJoinedSpan(String text) {
  final children = <InlineSpan>[];
  final buffer = StringBuffer();
  for (final piece in _splitWithJoiners(text)) {
    if (piece == _wordJoiner) {
      if (buffer.isNotEmpty) {
        children.add(TextSpan(text: buffer.toString()));
        buffer.clear();
      }
      children.add(
        TextSpan(
          text: _wordJoiner,
          // design-literal: 이음 문자에 부모 글자 간격이 더해지지 않게 0 으로 끊는다
          style: const TextStyle(letterSpacing: 0),
        ),
      );
    } else {
      buffer.write(piece);
    }
  }
  if (buffer.isNotEmpty) {
    children.add(TextSpan(text: buffer.toString()));
  }
  return TextSpan(children: children);
}

/// 한국어 문구가 낱말(어절) 가운데서 줄바뀌지 않게 그리는 [Text].
///
/// 여러 줄로 감길 수 있는 한국어 문구에 [Text] 대신 쓴다. 공백으로 나뉜
/// 덩어리에 한글 음절이 있으면 그 덩어리를 한 단위로 묶어, 줄이 모자랄 때
/// 덩어리째 다음 줄로 넘긴다. 덩어리가 한 줄보다 넓으면 그 안에서 줄을 바꾼다.
/// 이때 줄을 바꾸는 자리는 부호를 가리지 않아 닫는 부호(「?」 · 「)」 등)가
/// 줄 맨 앞에, 여는 괄호가 줄 끝에 올 수 있고, [Text] 로 그리면 이 꼴이
/// 없다. 덩어리가 한 줄보다 넓을 때만 생기며, 아주 큰 글자나 대화상자 제목
/// 같은 좁은 자리에서 그렇게 된다.
///
/// 이 파일의 `_isCjkNonHangul` 범위 목록에 든 글자(CJK 문장부호 · 가나 · 한자 ·
/// 전각 기호 가운데 일부)와 맞닿은 경계는 묶지 않고 원래 줄바꿈 규칙을 그대로
/// 따른다 — 일본어 문장 안의 한글 이름도 일본어 쪽 경계는 그대로다. 같은 범주라도
/// 목록 밖 글자는 다른 글자처럼 덩어리 안에서 묶인다.
///
/// 원문 [data] 는 바꾸지 않는다. 묶는 표시는 그릴 때만 더하므로 저장 · 비교 ·
/// 낭독에는 원문을 쓴다. 낭독 문구는 [semanticsLabel] 을 주지 않으면 원문이다.
///
/// `SelectionArea` 로 감싸 복사하면 묶는 표시(이음 문자)가 함께 복사된다 —
/// 복사할 문구는 감싸개 대신 [Text] 로 그린다.
///
/// [data] 에 한글 음절이 없으면 같은 인자로 만든 [Text] 를 그대로 돌려준다.
class KeepHangulWordsText extends StatelessWidget {
  /// [data] 를 낱말 단위로 줄바꿈하는 [KeepHangulWordsText] 를 만든다.
  const KeepHangulWordsText(
    this.data, {
    super.key,
    this.style,
    this.textAlign,
    this.softWrap,
    this.overflow,
    this.maxLines,
    this.semanticsLabel,
    this.textScaler,
  });

  /// 표시할 원문.
  final String data;

  /// 글자 스타일. [Text.style] 과 같다.
  final TextStyle? style;

  /// 가로 정렬. [Text.textAlign] 과 같다.
  final TextAlign? textAlign;

  /// 줄 끝에서 감을지. [Text.softWrap] 과 같다.
  final bool? softWrap;

  /// 넘친 글자를 어떻게 보일지. [Text.overflow] 와 같다.
  final TextOverflow? overflow;

  /// 최대 줄 수. [Text.maxLines] 와 같다.
  final int? maxLines;

  /// 낭독 문구. 주지 않으면 원문 [data] 를 읽는다.
  final String? semanticsLabel;

  /// 글자 배율. [Text.textScaler] 와 같다.
  final TextScaler? textScaler;

  @override
  Widget build(BuildContext context) {
    if (!_hangulSyllable.hasMatch(data)) {
      return Text(
        data,
        style: style,
        textAlign: textAlign,
        softWrap: softWrap,
        overflow: overflow,
        maxLines: maxLines,
        semanticsLabel: semanticsLabel,
        textScaler: textScaler,
      );
    }
    return Text.rich(
      _buildJoinedSpan(data),
      style: style,
      textAlign: textAlign,
      softWrap: softWrap,
      overflow: overflow,
      maxLines: maxLines,
      semanticsLabel: semanticsLabel ?? data,
      textScaler: textScaler,
    );
  }
}
