// 소셜 버튼이 그려지는 화면을 큰 글자 · 좁은 화면에서 재는 테스트 헬퍼.
//
// 버튼 라벨이 글자 배율 상한에서 멈추는지, 그 조건에서 난 넘침(RenderFlex
// overflow)이 버튼에서 비롯됐는지 버튼 밖 위젯의 것인지를 화면 테스트가 같은
// 방법으로 확인한다. 넘침이 아닌 오류는 이 헬퍼가 가로채지 않는다 — 테스트가
// 평소처럼 실패한다.
//
// 재는 기준에는 한계가 둘 있다.
// - 글자 배율은 글자 크기에 그대로 곱한 값(선형)이다. 기기가 큰 글자를 덜
//   키우는 방식(비선형)은 재지 않는다.
// - 폭과 줄 높이는 위젯 테스트 기본 글꼴 기준이다. 이 글꼴은 글자마다 1em
//   정사각형이라 영문 폭은 실제 글꼴보다 넓고 줄 높이는 낮게 잡힌다.

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_starter_kit/features/auth/presentation/_widgets/branded_social_button.dart';
import 'package:flutter_test/flutter_test.dart';

/// 화면 테스트가 도는 언어 — ko 먼저, en, ja.
const List<Locale> kBrandScaleLocales = <Locale>[
  Locale('ko'),
  Locale('en'),
  Locale('ja'),
];

/// 큰 글자 · 좁은 화면 단언의 범위 — 버튼에서 비롯된 넘침 0 을 단언한다.
///
/// 버튼 밖 위젯의 넘침은 이 단언의 범위가 아니다 — 세어서 측정 줄에만 싣는다.
/// true 로 바꾸면 버튼이 그려지는 화면 전체에서 넘침 0 을 단언한다.
const bool kBrandScaleAssertsWholeScreen = false;

/// 측정 줄을 출력할지 정한다 — `--dart-define=BRAND_SCALE_REPORT=true`.
const bool _isReportEnabled = bool.fromEnvironment('BRAND_SCALE_REPORT');

/// 좁은 화면의 논리 크기 (dp).
const Size _narrowViewSize = Size(280, 800);

/// 좁은 화면의 기기 픽셀 비율.
const double _narrowViewPixelRatio = 3;

/// 큰 글자에서 버튼 라벨이 가져야 하는 유효 글자 크기 — 글자 크기 × 배율 상한.
const double _cappedLabelSize = kBrandLabelFontSize * kBrandLabelScaleCap;

/// [collectBrandScaleErrors] 가 모은 넘침(RenderFlex overflow)을 난 자리로
/// 나눈 결과.
///
/// 넘침이 아닌 오류는 여기에 들지 않는다. 항목 하나는 「예외 첫 줄 @ 넘친
/// 위젯 < 조상 < 조상」 꼴의 한 줄이다.
@immutable
class BrandScaleErrors {
  /// 버튼에서 비롯된 넘침과 버튼 밖 넘침의 목록으로 만든다.
  const BrandScaleErrors({required this.fromButtons, required this.outside});

  /// [BrandedSocialButton] 아래의 render object 가 낸 넘침.
  final List<String> fromButtons;

  /// 버튼 밖 위젯이 낸 넘침 — 넘친 위젯을 알 수 없는 것도 여기에 든다.
  final List<String> outside;
}

/// 테스트 화면을 폭 280 · 글자 배율 [textScaleFactor] 로 맞춘다.
///
/// pump 전에 부른다. 화면 크기와 글자 배율을 걸고, 테스트가 끝나면 모두
/// 되돌린다.
void applyLargeTextNarrowView(
  WidgetTester tester, {
  double textScaleFactor = 2.0,
}) {
  tester.view.physicalSize = _narrowViewSize * _narrowViewPixelRatio;
  tester.view.devicePixelRatio = _narrowViewPixelRatio;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  tester.platformDispatcher.textScaleFactorTestValue = textScaleFactor;
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
}

/// 화면의 [BrandedSocialButton] 마다 라벨의 유효 글자 크기를 돌려준다.
///
/// 유효 글자 크기는 라벨에 걸린 글자 배율을 [kBrandLabelFontSize] 에 적용한
/// 값이다. 라벨을 찾지 못한 버튼이 있으면 실패한다.
List<double> readBrandButtonLabelSizes(WidgetTester tester) {
  return <double>[
    for (final Element button in _findButtonElements()) _readLabelSize(button),
  ];
}

/// [body] 가 도는 동안 난 넘침(RenderFlex overflow)을 모아 난 자리로 나눠
/// 돌려준다.
///
/// 화면을 그리는 pump 를 [body] 안에 둔다. 넘친 render object 를 만든 위젯의
/// 조상에 [BrandedSocialButton] 이 있으면 버튼의 넘침으로, 없거나 만든 위젯을
/// 알 수 없으면 버튼 밖 넘침으로 센다.
///
/// 넘침이 아닌 오류(빌드 예외 · 단언 실패 등)는 모으지 않고 원래 handler 로
/// 넘긴다 — 테스트 바인딩이 받아 테스트가 평소처럼 실패한다. 오류 handler 는
/// [body] 가 예외를 던져도 원래 것으로 되돌린다.
Future<BrandScaleErrors> collectBrandScaleErrors(
  Future<void> Function() body,
) async {
  final fromButtons = <String>[];
  final outside = <String>[];
  final previousHandler = FlutterError.onError;
  FlutterError.onError = (FlutterErrorDetails details) {
    // 넘침만 이 헬퍼가 분류한다. 그 밖의 오류는 원래 handler 로 넘겨 테스트가
    // 평소처럼 실패하게 둔다.
    if (!_isOverflowError(details)) {
      previousHandler?.call(details);
      return;
    }
    final origin = _findErrorOrigin(details);
    final line = '${_readFirstLine(details)} @ ${origin.description}';
    (origin.isInButton ? fromButtons : outside).add(line);
  };
  try {
    await body();
  } finally {
    FlutterError.onError = previousHandler;
  }
  return BrandScaleErrors(fromButtons: fromButtons, outside: outside);
}

/// 화면의 버튼 라벨이 상한에서 멈췄고 버튼이 넘치지 않았는지 본다.
///
/// [errors] 는 이 화면을 그리는 동안 [collectBrandScaleErrors] 가 모은 것이다.
/// 단언하는 것은 넷이다: 버튼이 [minButtons] 개 이상 · 모든 라벨의 유효 글자
/// 크기가 상한 값 · 모든 버튼 높이가 [kBrandButtonHeight] · 버튼에서 비롯된
/// 넘침 0. [kBrandScaleAssertsWholeScreen] 이 true 면 버튼 밖 넘침도 0 이어야
/// 한다.
///
/// `--dart-define=BRAND_SCALE_REPORT=true` 로 돌리면 단언에 앞서 측정 줄
/// 하나를 출력한다 — [surface] 와 [locale] 이 그 줄의 이름표다.
void expectBrandButtonLabelsCapped(
  WidgetTester tester,
  BrandScaleErrors errors, {
  required String surface,
  required Locale locale,
  required int minButtons,
}) {
  final lang = locale.languageCode;
  final labelSizes = readBrandButtonLabelSizes(tester);
  final heights = <double>[
    for (final Element button in _findButtonElements())
      _readButtonHeight(button),
  ];

  if (_isReportEnabled) {
    final firstOutside = errors.outside.isEmpty
        ? 'none'
        : '"${errors.outside.first}"';
    debugPrint(
      'SURFACE_SCALE surface=$surface lang=$lang '
      'buttons=${labelSizes.length} '
      'label_px=${_findMax(labelSizes).toStringAsFixed(1)} '
      'button_h=${_findMax(heights).toStringAsFixed(1)} '
      'button_errors=${errors.fromButtons.length} '
      'outside_errors=${errors.outside.length} '
      'first_outside=$firstOutside',
    );
  }

  final where = '$surface · $lang';
  expect(
    labelSizes.length,
    greaterThanOrEqualTo(minButtons),
    reason: '$where: 화면에 그려진 소셜 버튼이 $minButtons개보다 적다',
  );
  for (final double size in labelSizes) {
    expect(
      size,
      closeTo(_cappedLabelSize, 0.001),
      reason: '$where: 버튼 라벨이 글자 배율 상한에서 멈춰야 한다',
    );
  }
  for (final double height in heights) {
    expect(height, kBrandButtonHeight, reason: '$where: 버튼 높이는 글자 배율을 따르지 않는다');
  }
  expect(errors.fromButtons, isEmpty, reason: '$where: 버튼에서 비롯된 layout 오류가 있다');
  if (kBrandScaleAssertsWholeScreen) {
    expect(errors.outside, isEmpty, reason: '$where: 버튼 밖 위젯의 layout 오류가 있다');
  }
}

/// 화면에 그려진 [BrandedSocialButton] 의 element 를 트리 순서로 돌려준다.
List<Element> _findButtonElements() {
  return find.byType(BrandedSocialButton).evaluate().toList();
}

/// [button] 라벨의 유효 글자 크기를 읽는다.
double _readLabelSize(Element button) {
  final label = _findRenderObject<RenderParagraph>(button);
  if (label == null) {
    fail('소셜 버튼에서 라벨을 찾지 못했다: ${button.widget}');
  }
  return label.textScaler.scale(kBrandLabelFontSize);
}

/// [button] 의 바탕([Material])이 차지한 높이를 읽는다.
///
/// 포커스 테두리가 바깥에 두는 여백은 버튼 높이에 넣지 않는다.
double _readButtonHeight(Element button) {
  final body = _findElement(button, (Element e) => e.widget is Material);
  final box = body?.renderObject;
  if (box is! RenderBox) {
    fail('소셜 버튼에서 바탕을 찾지 못했다: ${button.widget}');
  }
  return box.size.height;
}

/// [root] 아래에서 [test] 를 만족하는 첫 element 를 트리 순서로 찾는다.
Element? _findElement(Element root, bool Function(Element) test) {
  Element? found;
  void visit(Element element) {
    if (found != null) {
      return;
    }
    if (test(element)) {
      found = element;
      return;
    }
    element.visitChildElements(visit);
  }

  root.visitChildElements(visit);
  return found;
}

/// [root] 아래에서 종류가 [T] 인 첫 render object 를 찾는다.
T? _findRenderObject<T extends RenderObject>(Element root) {
  final owner = _findElement(root, (Element e) => e.renderObject is T);
  final renderObject = owner?.renderObject;
  return renderObject is T ? renderObject : null;
}

/// [values] 의 최댓값 — 비어 있으면 0.
double _findMax(List<double> values) {
  return values.fold<double>(0, (double a, double b) => a > b ? a : b);
}

/// [details] 가 RenderFlex 넘침 보고인지 본다.
///
/// rendering library 는 넘침을 「A RenderFlex overflowed by …」 로 시작하는
/// 오류로 보고한다.
bool _isOverflowError(FlutterErrorDetails details) {
  return details.library == 'rendering library' &&
      details.exceptionAsString().startsWith('A RenderFlex overflowed');
}

/// 넘침이 난 자리 — 버튼 안인지와 측정 줄에 적을 설명.
typedef _ErrorOrigin = ({bool isInButton, String description});

/// [details] 의 오류를 낸 render object 가 어느 위젯 아래에서 만들어졌는지 찾는다.
///
/// layout 오류는 그 render object 를 만든 element 를 진단 항목으로 싣는다.
/// 그 element 에서 조상을 올라가며 [BrandedSocialButton] 을 찾는다. 진단
/// 항목이 없거나 element 가 이미 트리에서 빠졌으면 버튼 밖으로 본다.
_ErrorOrigin _findErrorOrigin(FlutterErrorDetails details) {
  final creator = _findErrorCreator(details);
  if (creator == null || !creator.mounted) {
    return (isInButton: false, description: 'unknown');
  }
  final ancestors = <String>[];
  var isInButton = creator.widget is BrandedSocialButton;
  creator.visitAncestorElements((Element ancestor) {
    if (ancestors.length < 2) {
      ancestors.add('${ancestor.widget.runtimeType}');
    }
    if (ancestor.widget is BrandedSocialButton) {
      isInButton = true;
    }
    return !isInButton;
  });
  final path = <String>['${creator.widget.runtimeType}', ...ancestors];
  return (isInButton: isInButton, description: path.join(' < '));
}

/// [details] 가 실은 진단 항목에서 오류를 낸 render object 의 만든 element 를
/// 꺼낸다.
Element? _findErrorCreator(FlutterErrorDetails details) {
  final collector = details.informationCollector;
  if (collector == null) {
    return null;
  }
  for (final DiagnosticsNode node in collector()) {
    if (node is DiagnosticsDebugCreator) {
      final Object? value = node.value;
      if (value is DebugCreator) {
        return value.element;
      }
    }
  }
  return null;
}

/// 실행마다 달라지는 객체 식별자(`#a1b2c`).
final RegExp _objectHashPattern = RegExp('#[0-9a-f]{5}');

/// [details] 의 예외 설명에서 첫 줄만 꺼낸다.
///
/// 측정 줄에 그대로 실리므로 큰따옴표와 실행마다 달라지는 객체 식별자를
/// 걷어 낸다.
String _readFirstLine(FlutterErrorDetails details) {
  return details
      .exceptionAsString()
      .split('\n')
      .first
      .replaceAll('"', "'")
      .replaceAll(_objectHashPattern, '')
      .trim();
}
