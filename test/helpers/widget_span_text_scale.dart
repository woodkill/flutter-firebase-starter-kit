// 연결된 계정 값의 provider 이름이 큰 글자 배율에서 한 번만 커지는지 재는
// 테스트 헬퍼.
//
// 무엇을 재나: baseline `WidgetSpan` 안에 든 이름 상자를, 같은 문자열 · 같은
// style · 같은 배율로 그린 일반 `Text` 상자와 견준다. `WidgetSpan` 은 자식을
// 배율만큼 변환 확대하므로, 자식이 배율을 또 읽으면 이름만 배율의 제곱으로
// 커진다.
//
// 왜 `tester.getRect` 인가: 전역 좌표라 `WidgetSpan` 의 변환 확대가 들어간다.
// `getSize` · `RenderBox.size` 는 변환 전 크기라서 이중 배율 꼴이 일반 `Text`
// 와 같게 읽히고 고친 꼴이 배율만큼 작게 읽힌다 — 쓰지 않는다.
//
// 문턱과 근거: 글꼴은 적재하지 않는다(시험 기본 글꼴 — 양쪽이 같은 글꼴이라
// 상대 비교가 성립한다). 이 조건(배율 1.3 · 2.0 · 비선형 · 이름 5개)에서
// 고친 꼴과 이중 배율 꼴을 재서, 문턱을 고친 꼴 최대 차이의 두 배 이상 ·
// 이중 배율 꼴 최소 차이의 1/3 이하로 정했다.
// - 높이 0.5dp(두 style 공통) — 1.0 줄 높이에 배율을 곱한 상자와 일반 문단의
//   줄 높이가 반올림만큼 다르다. 고친 꼴 최대 0.2 · 이중 배율 꼴 최소 9.3.
// - 폭 0.01dp(`letterSpacing: 0`) — 고친 꼴 0 · 이중 배율 꼴 최소 12.48.
// - 폭 비율 0.05(`letterSpacing` 있음) — `letterSpacing` 은 배율이 붙지 않는
//   절대값인데 변환이 함께 키워 고친 꼴도 조금 넓다(받아들인 차이). 일반
//   `Text` 폭에 대한 비율로 고친 꼴 최대 0.0047 · 이중 배율 꼴 최소 0.30.
//
// 측정 줄 보기: `--dart-define=WIDGET_SPAN_SCALE_REPORT=true` 를 붙여 돌리면
// 이름마다 `MEASURE` 줄을 출력한다.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Android 14+ 비선형 글자 배율을 흉내 낸 [TextScaler] — 작은 글자를 더 키운다.
///
/// 20 미만 글자는 1.8배, 그 이상은 1.3배로 키운다.
class NonlinearTextScaler implements TextScaler {
  /// 비선형 배율을 만든다.
  const NonlinearTextScaler();

  @override
  double scale(double fontSize) =>
      fontSize < 20 ? fontSize * 1.8 : fontSize * 1.3;

  @override
  double get textScaleFactor => 1.8;

  @override
  TextScaler clamp({
    double minScaleFactor = 0,
    double maxScaleFactor = double.infinity,
  }) => this;
}

/// 회귀 시험이 도는 배율 조건 — 1.3 · 2.0 · 비선형.
const List<({String label, TextScaler scaler})> kWidgetSpanScaleCases =
    <({String label, TextScaler scaler})>[
      (label: '1.3', scaler: TextScaler.linear(1.3)),
      (label: '2.0', scaler: TextScaler.linear(2)),
      (label: 'nonlinear', scaler: NonlinearTextScaler()),
    ];

/// `letterSpacing` 이 0 인 시험 style — 고친 꼴의 폭이 일반 `Text` 와 같다.
///
/// `letterSpacing` 을 null 이 아닌 0 으로 둔다 — null 이면 Material 의
/// `DefaultTextStyle` 이 물려주는 값이 들어온다.
const TextStyle kWidgetSpanFlatStyle = TextStyle(
  fontSize: 16,
  height: 1.5,
  letterSpacing: 0,
);

/// `letterSpacing` 이 있는 시험 style — 계정 화면 값 style
/// (`context.appTypography.titleMedium`)의 크기 · 줄 높이 · 자간과 같다.
const TextStyle kWidgetSpanSpacedStyle = TextStyle(
  fontSize: 16,
  height: 1.5,
  letterSpacing: 0.15,
);

/// 값 `Text.rich` 의 key — 이름을 그 아래에서만 찾는다.
const Key kWidgetSpanValueKey = ValueKey<String>('widget-span-value');

/// 측정 줄을 출력할지 정한다 — `--dart-define=WIDGET_SPAN_SCALE_REPORT=true`.
const bool _isReportEnabled = bool.fromEnvironment('WIDGET_SPAN_SCALE_REPORT');

/// 높이 차 문턱(dp) — 두 style 공통.
const double _maxHeightDelta = 0.5;

/// `letterSpacing: 0` style 의 폭 차 문턱(dp).
const double _maxFlatWidthDelta = 0.01;

/// `letterSpacing` 이 있는 style 의 폭 차 문턱 — 일반 `Text` 폭에 대한 비율.
const double _maxSpacedWidthRatio = 0.05;

/// 측정 view 의 논리 크기(dp).
const Size _viewSize = Size(360, 1600);

/// 측정 view 의 기기 픽셀 비율.
const double _viewPixelRatio = 3;

/// 값 span 의 이름 상자를 일반 `Text` 상자와 견줘 문턱을 넘은 이름을 모은다.
///
/// [buildValue] 는 style 을 받아 값 span 을 만든다. [tagsByName] 은 잴 이름
/// (화면에 그려지는 문자열 · 쉼표 포함)과 위반 줄 앞에 붙일 꼬리표다.
/// [caseLabel] · [textScaler] 는 배율 조건이다. 두 시험 style
/// ([kWidgetSpanFlatStyle] · [kWidgetSpanSpacedStyle])마다 한 번씩 그린다.
///
/// 위반 줄은 꼬리표 뒤에 배율 · style · 이름과 두 상자 크기
/// (`value=폭x높이` · `reference=폭x높이`) · 폭 차 `dW` · 높이 차 `dH` 를
/// 붙인 한 줄이다. 이름이 정확히 하나 찾아지지 않으면 `[count]` 줄을 남기고
/// 그 이름은 건너뛴다.
Future<List<String>> collectWidgetSpanScaleViolations(
  WidgetTester tester, {
  required InlineSpan Function(TextStyle style) buildValue,
  required Map<String, String> tagsByName,
  required String caseLabel,
  required TextScaler textScaler,
}) async {
  tester.view.devicePixelRatio = _viewPixelRatio;
  tester.view.physicalSize = _viewSize * _viewPixelRatio;
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);

  final names = tagsByName.keys.toList();
  final violations = <String>[];
  for (final (styleLabel, style) in <(String, TextStyle)>[
    ('flat', kWidgetSpanFlatStyle),
    ('spaced', kWidgetSpanSpacedStyle),
  ]) {
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: textScaler),
          child: child!,
        ),
        // InkWell 이 Material 조상을 요구한다.
        home: Material(
          child: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: _viewSize.width,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text.rich(
                    buildValue(style),
                    key: kWidgetSpanValueKey,
                    softWrap: true,
                    style: style,
                  ),
                  for (final (i, name) in names.indexed)
                    Text(
                      name,
                      key: ValueKey<String>('reference-$i'),
                      style: style,
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    for (final (i, name) in names.indexed) {
      final where = 'case=$caseLabel style=$styleLabel name=$name';
      final nameFinder = find.descendant(
        of: find.byKey(kWidgetSpanValueKey),
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is Text &&
              (widget.data ?? widget.textSpan?.toPlainText()) == name,
        ),
      );
      final found = nameFinder.evaluate().length;
      if (found != 1) {
        violations.add('[count] $where found=$found');
        continue;
      }
      final value = tester.getRect(nameFinder);
      final reference = tester.getRect(
        find.byKey(ValueKey<String>('reference-$i')),
      );
      final dW = value.width - reference.width;
      final dH = value.height - reference.height;
      final tag = tagsByName[name]!;
      final measured =
          '$where value=${_formatSize(value)} '
          'reference=${_formatSize(reference)} '
          'dW=${dW.toStringAsFixed(3)} dH=${dH.toStringAsFixed(3)}';
      if (_isReportEnabled) {
        final ratioW = dW / reference.width;
        debugPrint(
          'MEASURE $tag $measured ratioW=${ratioW.toStringAsFixed(3)}',
        );
      }
      final maxWidthDelta = styleLabel == 'flat'
          ? _maxFlatWidthDelta
          : reference.width * _maxSpacedWidthRatio;
      if (dW.abs() > maxWidthDelta || dH.abs() > _maxHeightDelta) {
        violations.add('$tag $measured');
      }
    }
  }
  return violations;
}

/// 상자 크기를 `<폭>x<높이>`(소수 셋째 자리) 꼴로 적는다.
String _formatSize(Rect rect) =>
    '${rect.width.toStringAsFixed(3)}x${rect.height.toStringAsFixed(3)}';
