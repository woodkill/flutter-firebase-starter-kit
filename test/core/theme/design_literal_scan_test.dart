// 디자인 리터럴 소스 스캔 가드 — 실제 `lib/` 의 리터럴 0 건 · 표시 주석 총수 고정 ·
// 문자열 표본으로 패턴마다 RED 와 표시 통과를 고정한다.
//
// 스캔 범위 · 패턴 · 표시 규칙은 `test/helpers/design_literal_scan.dart` 에 있다.
// 사용 가이드 「디자인 토큰 바꾸기」 의 표 「쓰지 않는 것」 열이 그 패턴 이름과
// 1:1 이다.
//
// T-24-SCAN-01: 스캔 대상 파일마다 디자인 리터럴이 0 건이다.
// T-24-SCAN-02: 스캔 대상의 표시 주석 총수가 [_designLiteralMarkerCount] 다.
// T-24-SCAN-03: 스캔 대상 수집 · 제외 규칙 · Duration 범위 규칙의 표본.
// T-24-SCAN-04: 패턴마다 둘째 줄 리터럴 표본이 그 줄 · 그 이름 하나로 걸린다.
//   간격 · 크기 숫자는 인자마다, 1 미만 비율 소수(`0.x` · `.x`)는 곱의 앞이든
//   뒤든 걸린다 — 숫자 인자를 잡는 조건([kDesignLiteralPatterns] 문서)과 헬퍼
//   머리 주석의 블록 주석 정의에서 나오는 놓치는 꼴의 예시(알려진 빈틈)와
//   400자 길이 상한 경계를 표본으로 고정한다.
// T-24-SCAN-05: 리터럴 바로 윗줄의 이유 있는 표시만 통과시킨다.
// T-24-SCAN-06: 여러 줄 호출은 숫자가 있는 인자 줄로 알리고 줄 번호가 밀리지 않는다.
// T-24-SCAN-07: Duration 은 화면 · 공용 폴더에서 표시된 이름 붙인 선언만 통과한다.
// T-24-SCAN-08: 토큰 · 주석 · 색 파서 꼴 같은 음성 표본은 0 건이다.
//
// **표시를 더하거나 지우면 상수를 고친다** — 앱 코드에 표시 주석을 하나 더하면
// [_designLiteralMarkerCount] 를 올리고, 표시가 있는 파일을 지우면(데모 화면
// 지우기 포함) 내린다. 늘어난 수가 리뷰에 드러나게 하려는 상수다.
//
// 표본은 이 파일 안 문자열이다 — `test/` 는 스캔 범위 밖이라 표본 리터럴이 이
// 가드에 걸리지 않는다.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../helpers/design_literal_scan.dart';

/// 스캔 대상 `lib/` 의 표시 주석 총수다.
const int _designLiteralMarkerCount = 14;

/// 스캔 대상 수의 하한 — 수집기가 빈 목록으로 공허하게 통과하지 않게 한다.
const int _minScanTargetCount = 100;

/// 화면 폴더 표본 경로 — 모든 패턴(Duration 포함)을 본다.
const String _presentationPath =
    'lib/features/sample/presentation/sample_screen.dart';

/// data 폴더 표본 경로 — Duration 패턴은 보지 않는다.
const String _dataPath = 'lib/features/sample/data/sample_repository.dart';

/// 이유가 있는 표시 주석 표본이다.
const String _marker = '  // design-literal: 시험용 이유';

/// 이유가 없는 표시 주석 표본 — 표시로 치지 않는다.
const String _reasonlessMarker = '  // design-literal:';

/// 패턴 이름마다 그 패턴 하나에만 걸리는 리터럴 줄이다.
const Map<String, String> _literalLines = <String, String>{
  'material-colors': '  final Object value = Colors.red;',
  'color-hex': '  final Object value = Color(0xFF112233);',
  'color-from-components':
      '  final Object value = Color.fromRGBO(1, 2, 3, 0.5);',
  'font-size-number': '  final Object value = base.copyWith(fontSize: 14);',
  'font-weight-literal':
      '  final Object value = base.copyWith(fontWeight: FontWeight.w500);',
  'text-style-constructor': '  final Object value = TextStyle(color: color);',
  'edge-insets-number': '  final Object value = EdgeInsets.all(8);',
  'gap-number': '  final Object value = Gap(8);',
  'radius-number': '  final Object value = BorderRadius.circular(8);',
  'icon-size-number': '  final Object value = Icon(icon, size: 24);',
  'alpha-number': '  final Object value = color.withValues(alpha: 0.5);',
  'elevation-number': '  final Object value = Material(elevation: 2);',
  'duration-literal': '  static const Duration value = Duration(seconds: 2);',
  'curves-literal': '  final Object value = Curves.easeIn;',
  'border-width-number': '  final Object value = BorderSide(width: 2);',
  'width-compare-number': '  bool get isWide => width >= 600;',
  'sized-box-number': '  final Object value = SizedBox(width: 20);',
  'spacing-as-size':
      '  final Object value = SizedBox.square(dimension: spacing.xl);',
  'stroke-width-number':
      '  final Object value = CircularProgressIndicator(strokeWidth: 2);',
  'ratio-literal': '  final double value = size.height * 0.9;',
};

/// 인자 위치 · 피연산자 순서가 다른 리터럴 줄과 그 줄이 걸리는 패턴 이름이다.
///
/// 간격 · 크기 숫자는 첫 인자가 아니어도, 1 미만 비율 소수는 곱의 앞에 와도
/// 걸린다. 0 도 숫자 리터럴이다 — 한 변만 0 이면 `EdgeInsets.only` 로 그 변을
/// 생략한다.
/// 가드가 보지 못하는 꼴은 [_knownGapLines] 에 있다.
const List<(String, String)> _argumentPositionLines = <(String, String)>[
  (
    '  final Object value = EdgeInsets.fromLTRB(spacing.lg, 8, spacing.lg, 16);',
    'edge-insets-number',
  ),
  (
    '  final Object value = EdgeInsets.fromLTRB(spacing.lg, 0, spacing.lg, spacing.sm);',
    'edge-insets-number',
  ),
  (
    '  final Object value = EdgeInsets.only(left: spacing.md, top: 8);',
    'edge-insets-number',
  ),
  (
    '  final Object value = EdgeInsets.symmetric(horizontal: spacing.lg, vertical: 12);',
    'edge-insets-number',
  ),
  (
    '  final Object value = SizedBox(width: double.infinity, height: 48);',
    'sized-box-number',
  ),
  ('  final Object value = SizedBox(key: key, height: 8);', 'sized-box-number'),
  ('  final double value = 0.9 * size.height;', 'ratio-literal'),
];

/// 알려진 빈틈 — 가드가 보지 못하는 리터럴 꼴의 예시다.
///
/// 숫자 인자를 잡는 조건([kDesignLiteralPatterns] 문서)과 헬퍼 머리 주석의
/// 블록 주석 정의에서 나오는 놓치는 꼴 가운데 몇 개이고, 전부 목록이 아니다.
/// 지금 0 건임을 고정해 빈틈을 드러낸다 — 가드가 이 꼴을 잡게 되면 이 목록에서
/// 빼고 적중 줄을 단언하는 양성 시험으로 옮긴다.
const List<String> _knownGapLines = <String>[
  'EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom, top: 8)',
  'EdgeInsets.only(\n  left: spacing.sm, // 설명\n  top: 8,\n)',
  'EdgeInsets.only( // 설명\n  top: 8,\n)',
  'EdgeInsets.only(\n  left: spacing.sm, // 설명(시안)\n  right: spacing.sm,\n  top: 8,\n)',
  "EdgeInsets.only(left: k ?? '/*', top: 8) /* x */",
];

/// 여는 괄호 뒤 앞 인자 길이 상한 표본의 호출 머리 · 앞 인자 이름 · 숫자 인자 ·
/// 패턴 이름이다.
const List<(String, String, String, String)> _leadingLengthCalls =
    <(String, String, String, String)>[
      ('EdgeInsets.only', 'left', 'top: 8', 'edge-insets-number'),
      ('SizedBox', 'key', 'height: 8', 'sized-box-number'),
    ];

/// 토큰 · 주석 · 색 파서 꼴처럼 어느 패턴에도 걸리지 않는 음성 표본이다.
const List<String> _negativeLines = <String>[
  'final Object a = EdgeInsets.all(spacing.md);',
  'final Object a = Gap(spacing.sm);',
  'final Object a = BorderRadius.circular(context.appRadius.sm);',
  'final Object a = context.appColors.success;',
  'final Object a = AppColors.fromBrightness(Brightness.light);',
  'final Object a = Color(0xFF000000 | value);',
  'final Object a = EdgeInsets.only(left: spacing.lg, right: spacing.lg, bottom: spacing.sm);',
  'final Object a = EdgeInsets.only(left: spacing.md, top: spacing.sm);',
  'final Object a = SizedBox(width: double.infinity, height: spacing.md);',
  'final double a = size.height * factor;',
  'final Object a = Durations.short4;',
  'const double _kLogoSize = 40;',
  '// Colors.red',
  '/// Duration(seconds: 2)',
  '/* fontSize: 14 */',
  'final Object a = Gap(spacing.sm); /* Colors.red */',
];

/// 여는 괄호 바로 뒤부터 숫자 인자 앞 쉼표 직전까지가 [length] 자인 한 줄
/// 호출을 만든다.
///
/// 앞 인자는 `<name>: aaa…` 꼴이라 어느 패턴에도 걸리지 않는다.
String _callWithLeadingLength(
  String head,
  String name,
  String numberArgument,
  int length,
) {
  final leading = '$name: ';
  return '$head($leading${'a' * (length - leading.length)}, $numberArgument)';
}

/// [source] 의 첫 여는 괄호 바로 뒤부터 첫 쉼표 직전까지의 글자 수를 돌려준다.
int _leadingLength(String source) =>
    source.indexOf(',') - source.indexOf('(') - 1;

/// 첫 인자 줄 끝에 `//` 주석을 둔 여러 줄 `EdgeInsets.only` 호출을 만든다.
///
/// 공백 연속을 한 칸으로 접으면 여는 괄호 바로 뒤부터 숫자 인자 `top: 8` 앞
/// 쉼표 직전까지가 줄 끝 주석 글자를 넣어 [collapsedLength] 자다. 주석에는
/// 닫는 괄호가 없고 숫자 인자 바로 윗줄은 주석 없는 인자 줄이라, 숫자 인자
/// 바로 앞이 쉼표다 — 적중 여부는 길이 하나로 갈린다.
String _callWithTrailingComment(int collapsedLength) {
  const leading = ' left: ';
  const comment = ' // 이 줄 끝 주석의 글자도 센다';
  const middle = ' right: spacing.sm';
  final int filler =
      collapsedLength -
      leading.length -
      ','.length -
      comment.length -
      middle.length;
  return 'EdgeInsets.only(\n'
      '  left: ${'a' * filler},$comment\n'
      '  right: spacing.sm,\n'
      '  top: 8,\n'
      ')';
}

/// [source] 의 공백 연속을 한 칸으로 접은 텍스트에서 첫 여는 괄호 바로 뒤부터
/// 숫자 인자 `top: 8` 앞 쉼표 직전까지의 글자를 돌려준다.
///
/// 줄 전체 주석 · 블록 주석이 없는 표본에만 쓴다 — 그런 표본은 공백 접기만으로
/// 가드가 보는 텍스트와 같다.
String _collapsedLeading(String source) {
  final String collapsed = source.replaceAll(RegExp(r'\s+'), ' ');
  return collapsed.substring(
    collapsed.indexOf('(') + 1,
    collapsed.indexOf(', top: 8'),
  );
}

/// 앞 인자 끝에 코드와 붙은 여러 줄 블록 주석 `/*\n*/` 을 둔 `EdgeInsets.only`
/// 호출을 만든다.
///
/// 가드가 세는 텍스트는 [findDesignLiteralHits] 순서 2 · 3 을 거친 것이라 주석
/// 자리에 한 칸이 남는다 — 여는 괄호 바로 뒤부터 숫자 인자 `top: 8` 앞 쉼표
/// 직전까지가 그 한 칸을 넣어 [collapsedLength] 자다. 숫자 인자는 둘째 줄이다.
String _callWithAttachedBlockComment(int collapsedLength) {
  const leading = 'left: ';
  final int filler = collapsedLength - leading.length - ' '.length;
  return 'EdgeInsets.only($leading${'a' * filler}/*\n*/, top: 8)';
}

/// [body] 줄을 클래스 머리 · 꼬리 사이에 넣은 표본 소스를 만든다.
///
/// [body] 의 첫 줄이 소스의 둘째 줄이다.
String _wrapInClass(List<String> body) =>
    <String>['class Sample {', ...body, '}'].join('\n');

/// 화면 폴더 표본 경로의 위반 한 줄을 만든다.
String _presentationHit(int line, String name) =>
    '$_presentationPath:$line — $name';

void main() {
  group('실제 lib 스캔', () {
    test('T-24-SCAN-01: 스캔 대상 파일마다 디자인 리터럴이 0 건이다', () {
      final violations = <String>[];
      for (final String path in collectDesignLiteralScanPaths()) {
        final String source = File(path).readAsStringSync();
        violations.addAll(findDesignLiteralHits(path, source));
      }
      expect(
        violations,
        isEmpty,
        reason:
            '${violations.join('\n')}\n'
            '토큰 getter · SDK 상수로 바꾸거나, 한 컴포넌트만의 치수면 바로 윗줄에 '
            '`// design-literal: <이유>` 를 달고 `_designLiteralMarkerCount` 를 '
            '올린다 — docs/guide.md 「디자인 토큰 바꾸기」',
      );
    });

    test('T-24-SCAN-02: 스캔 대상의 표시 주석 총수가 고정 상수와 같다', () {
      var total = 0;
      for (final String path in collectDesignLiteralScanPaths()) {
        total += countDesignLiteralMarkers(File(path).readAsStringSync());
      }
      expect(
        total,
        _designLiteralMarkerCount,
        reason: '표시를 더했으면 상수를 올리고, 지웠으면(데모 지우기 포함) 내린다',
      );
    });

    test('T-24-SCAN-03: 수집 대상 · 제외 규칙 · Duration 범위 표본', () {
      final List<String> paths = collectDesignLiteralScanPaths();
      expect(paths.length, greaterThanOrEqualTo(_minScanTargetCount));
      expect(paths, contains('lib/main.dart'));
      expect(
        paths,
        contains('lib/shared/widgets/small_progress_indicator.dart'),
      );
      expect(paths, isNot(contains('lib/app.dart')));
      expect(
        paths,
        isNot(
          contains(
            'lib/features/auth/presentation/_widgets/branded_social_button.dart',
          ),
        ),
      );
      expect(
        paths.where((String path) => path.startsWith('lib/core/theme/')),
        isEmpty,
      );
      expect(
        paths.where((String path) => path.startsWith('lib/l10n/generated/')),
        isEmpty,
      );
      expect(paths, orderedEquals(List<String>.of(paths)..sort()));

      const nonTargets = <String>[
        'lib/app.dart',
        'lib/a/b.g.dart',
        'lib/a/b.freezed.dart',
        'lib/a/b.gr.dart',
        'lib/a/b.gen.dart',
        'test/a.dart',
        'lib/a/b.txt',
      ];
      for (final path in nonTargets) {
        expect(isDesignLiteralScanTarget(path), isFalse, reason: path);
      }
      expect(isDesignLiteralScanTarget('lib/a/b.dart'), isTrue);

      expect(isDurationScopePath('lib/shared/x.dart'), isTrue);
      expect(isDurationScopePath('lib/features/a/presentation/x.dart'), isTrue);
      expect(isDurationScopePath('lib/features/a/data/x.dart'), isFalse);
      expect(isDurationScopePath('lib/features/a/application/x.dart'), isFalse);
    });
  });

  group('패턴별 표본', () {
    test('T-24-SCAN-04: 표본 이름 집합이 패턴 이름 집합(20)과 같다', () {
      final Set<String> patternNames = kDesignLiteralPatterns
          .map((DesignLiteralPattern pattern) => pattern.name)
          .toSet();
      expect(patternNames, hasLength(20));
      expect(_literalLines.keys.toSet(), equals(patternNames));
    });

    for (final MapEntry<String, String> entry in _literalLines.entries) {
      test('T-24-SCAN-04: ${entry.key} 표본은 둘째 줄 · 그 이름 하나로 걸린다', () {
        expect(
          findDesignLiteralHits(
            _presentationPath,
            _wrapInClass(<String>[entry.value]),
          ),
          equals(<String>[_presentationHit(2, entry.key)]),
        );
      });

      test('T-24-SCAN-05: ${entry.key} 표본은 바로 윗줄 이유 있는 표시만 통과한다', () {
        expect(
          findDesignLiteralHits(
            _presentationPath,
            _wrapInClass(<String>[_marker, entry.value]),
          ),
          isEmpty,
        );
        expect(
          findDesignLiteralHits(
            _presentationPath,
            _wrapInClass(<String>[_reasonlessMarker, entry.value]),
          ),
          equals(<String>[_presentationHit(3, entry.key)]),
        );
        expect(
          findDesignLiteralHits(
            _presentationPath,
            _wrapInClass(<String>[_marker, '', entry.value]),
          ),
          equals(<String>[_presentationHit(4, entry.key)]),
        );
      });
    }

    for (final (String source, String name) in _argumentPositionLines) {
      test('T-24-SCAN-04: 인자 위치와 무관하게 $name 으로 걸린다 — $source', () {
        expect(
          findDesignLiteralHits(
            _presentationPath,
            _wrapInClass(<String>[source]),
          ),
          equals(<String>[_presentationHit(2, name)]),
        );
      });
    }

    test('T-24-SCAN-04: 여러 줄 호출의 둘째 인자 이후 숫자는 그 인자 줄로 걸린다', () {
      expect(
        findDesignLiteralHits(
          _presentationPath,
          'EdgeInsets.symmetric(\n'
          '  horizontal: spacing.lg,\n'
          '  vertical: 8,\n'
          ')',
        ),
        equals(<String>[_presentationHit(3, 'edge-insets-number')]),
      );
      expect(
        findDesignLiteralHits(
          _presentationPath,
          'SizedBox(\n'
          '  width: double.infinity,\n'
          '  height: 48,\n'
          ')',
        ),
        equals(<String>[_presentationHit(3, 'sized-box-number')]),
      );
    });

    test('T-24-SCAN-04: 한 호출의 숫자 인자 줄마다 따로 걸리고 표시는 그 줄만 푼다', () {
      const fromLtrbLines = <String>[
        'EdgeInsets.fromLTRB(',
        '  spacing.xl,',
        '  0,',
        '  spacing.xl,',
        '  16,',
        ')',
      ];
      expect(
        findDesignLiteralHits(_presentationPath, fromLtrbLines.join('\n')),
        equals(<String>[
          _presentationHit(3, 'edge-insets-number'),
          _presentationHit(5, 'edge-insets-number'),
        ]),
      );
      expect(
        findDesignLiteralHits(
          _presentationPath,
          <String>[
            ...fromLtrbLines.take(4),
            _marker,
            ...fromLtrbLines.skip(4),
          ].join('\n'),
        ),
        equals(<String>[_presentationHit(3, 'edge-insets-number')]),
      );
    });

    for (final (String head, String name, String numberArgument, String pattern)
        in _leadingLengthCalls) {
      test('T-24-SCAN-04: $pattern 은 여는 괄호 뒤 앞 인자들이 400자면 그 뒤 숫자 인자를 잡는다', () {
        final String source = _callWithLeadingLength(
          head,
          name,
          numberArgument,
          400,
        );
        expect(_leadingLength(source), 400);
        expect(
          findDesignLiteralHits(_presentationPath, source),
          equals(<String>[_presentationHit(1, pattern)]),
        );
      });

      test(
        'T-24-SCAN-04: $pattern 은 여는 괄호 뒤 앞 인자들이 401자면 그 뒤 숫자 인자를 보지 않는다',
        () {
          final String source = _callWithLeadingLength(
            head,
            name,
            numberArgument,
            401,
          );
          expect(_leadingLength(source), 401);
          expect(findDesignLiteralHits(_presentationPath, source), isEmpty);
        },
      );
    }

    test('T-24-SCAN-04: 앞 인자 길이는 줄 전체 주석을 지우고 공백 연속을 한 칸으로 접어 센다', () {
      String multiLine(int collapsedLength) =>
          'EdgeInsets.only(\n'
          '  // 이 주석 줄의 글자는 세지 않는다\n'
          '          left: ${'a' * (collapsedLength - ' left: '.length)},\n'
          '  top: 8,\n'
          ')';
      expect(_leadingLength(multiLine(400)), greaterThan(400));
      expect(
        findDesignLiteralHits(_presentationPath, multiLine(400)),
        equals(<String>[_presentationHit(4, 'edge-insets-number')]),
      );
      expect(findDesignLiteralHits(_presentationPath, multiLine(401)), isEmpty);
    });

    test('T-24-SCAN-04: 앞 인자 줄 끝 주석의 글자도 넣어 400자면 그 뒤 숫자 인자를 잡는다', () {
      final String source = _callWithTrailingComment(400);
      final String leading = _collapsedLeading(source);
      expect(leading, contains('//'));
      expect(leading.length, 400);
      expect(
        findDesignLiteralHits(_presentationPath, source),
        equals(<String>[_presentationHit(4, 'edge-insets-number')]),
      );
    });

    test('T-24-SCAN-04: 앞 인자 줄 끝 주석의 글자도 넣어 401자면 그 뒤 숫자 인자를 보지 않는다', () {
      final String source = _callWithTrailingComment(401);
      final String leading = _collapsedLeading(source);
      expect(leading, contains('//'));
      expect(leading.length, 401);
      expect(findDesignLiteralHits(_presentationPath, source), isEmpty);
    });

    test(
      'T-24-SCAN-04: 앞 인자 끝에 붙은 여러 줄 블록 주석은 줄바꿈 한 칸으로 세어 400자면 그 뒤 숫자 인자를 잡는다',
      () {
        final String source = _callWithAttachedBlockComment(400);
        expect(source, contains('a/*\n*/,'));
        expect(
          findDesignLiteralHits(_presentationPath, source),
          equals(<String>[_presentationHit(2, 'edge-insets-number')]),
        );
      },
    );

    test(
      'T-24-SCAN-04: 앞 인자 끝에 붙은 여러 줄 블록 주석은 줄바꿈 한 칸으로 세어 401자면 그 뒤 숫자 인자를 보지 않는다',
      () {
        final String source = _callWithAttachedBlockComment(401);
        expect(source, contains('a/*\n*/,'));
        expect(findDesignLiteralHits(_presentationPath, source), isEmpty);
      },
    );

    test('T-24-SCAN-04: 알려진 빈틈 — 가드가 보지 못하는 꼴은 지금 0 건이다', () {
      for (final source in _knownGapLines) {
        expect(
          findDesignLiteralHits(_presentationPath, source),
          isEmpty,
          reason: source,
        );
      }
    });

    test('T-24-SCAN-04: 줄 끝 주석이 쉼표로 끝나면 숫자 인자 바로 앞이 쉼표라 잡는다', () {
      // 알려진 빈틈의 여는 괄호 줄 끝 주석 꼴과 쉼표 하나만 다르다 — 쉼표는
      // 주석 안에 있어도 센다.
      expect(
        findDesignLiteralHits(
          _presentationPath,
          'EdgeInsets.only( // 설명,\n  top: 8,\n)',
        ),
        equals(<String>[_presentationHit(2, 'edge-insets-number')]),
      );
      expect(
        findDesignLiteralHits(
          _presentationPath,
          'SizedBox( // 설명,\n  height: 8,\n)',
        ),
        equals(<String>[_presentationHit(2, 'sized-box-number')]),
      );
    });

    test('T-24-SCAN-04: 모든 패턴의 일치는 길이 1 이상이다', () {
      final samples = <String>[
        '',
        ..._literalLines.values,
        for (final (String source, String _) in _argumentPositionLines) source,
        ..._negativeLines,
        ..._knownGapLines,
      ];
      for (final DesignLiteralPattern named in kDesignLiteralPatterns) {
        for (final sample in samples) {
          for (final RegExpMatch match in named.pattern.allMatches(sample)) {
            expect(
              match.end,
              greaterThan(match.start),
              reason: '${named.name}: $sample',
            );
          }
        }
      }
    });

    test('T-24-SCAN-05: 표시 수는 이유가 있는 표시 줄만 센다', () {
      const source = <String>[
        '// design-literal: 이유 하나',
        '    // design-literal: 들여 쓴 이유',
        '// design-literal:',
        '// design-literal:  ',
        '/// design-literal: 문서 주석은 표시가 아니다',
        'final a = 1; // design-literal: 줄 끝 주석은 표시가 아니다',
      ];
      expect(countDesignLiteralMarkers(source.join('\n')), 2);
    });
  });

  group('여러 줄 · 줄 번호', () {
    const constraintsLines = <String>[
      'BoxConstraints(',
      '  maxHeight: size.height * 0.9,',
      ')',
    ];

    test('T-24-SCAN-06: 여러 줄 호출은 숫자가 있는 인자 줄로 알린다', () {
      expect(
        findDesignLiteralHits(_presentationPath, constraintsLines.join('\n')),
        equals(<String>[_presentationHit(2, 'ratio-literal')]),
      );
      expect(
        findDesignLiteralHits(
          _presentationPath,
          <String>[
            constraintsLines[0],
            _marker,
            ...constraintsLines.skip(1),
          ].join('\n'),
        ),
        isEmpty,
      );
      expect(
        findDesignLiteralHits(
          _presentationPath,
          <String>[_marker, ...constraintsLines].join('\n'),
        ),
        equals(<String>[_presentationHit(3, 'ratio-literal')]),
      );
      expect(
        findDesignLiteralHits(
          _presentationPath,
          'SizedBox.square(\n  dimension: spacing.xl,\n)',
        ),
        equals(<String>[_presentationHit(2, 'spacing-as-size')]),
      );
      expect(
        findDesignLiteralHits(_presentationPath, 'SizedBox(\n  width: 20,\n)'),
        equals(<String>[_presentationHit(2, 'sized-box-number')]),
      );
    });

    test('T-24-SCAN-06: 주석을 지워도 줄 번호가 밀리지 않는다', () {
      const source = <String>[
        '/* 여러 줄',
        '   블록 주석 */',
        '/// 문서 주석 줄',
        '// 경로 꼴 `terms/*` 를 담은 행 주석',
        'final Object value = Gap(8);',
        '// 닫는 꼴 */ 을 담은 행 주석',
      ];
      expect(
        findDesignLiteralHits(_presentationPath, source.join('\n')),
        equals(<String>[_presentationHit(5, 'gap-number')]),
      );
    });

    test('T-24-SCAN-06: 한 줄의 같은 패턴은 한 번 · 여러 패턴은 패턴 순으로 낸다', () {
      expect(
        findDesignLiteralHits(
          _presentationPath,
          'final Object a = Gap(8);\n'
          'final Object b = Colors.red.withValues(alpha: 0.5); '
          'final Object c = Colors.blue;',
        ),
        equals(<String>[
          _presentationHit(1, 'gap-number'),
          _presentationHit(2, 'material-colors'),
          _presentationHit(2, 'alpha-number'),
        ]),
      );
    });
  });

  group('Duration', () {
    const inlineTimer = '  Timer(const Duration(seconds: 2), () {});';

    test('T-24-SCAN-07: 인라인 Duration 은 표시가 있어도 걸린다', () {
      expect(
        findDesignLiteralHits(_presentationPath, inlineTimer),
        equals(<String>[_presentationHit(1, 'duration-literal')]),
      );
      expect(
        findDesignLiteralHits(
          _presentationPath,
          <String>[_marker, inlineTimer].join('\n'),
        ),
        equals(<String>[_presentationHit(2, 'duration-literal')]),
      );
      expect(
        findDesignLiteralHits(
          _presentationPath,
          <String>[
            _marker,
            '  AnimatedOpacity(duration: const Duration(milliseconds: 200));',
          ].join('\n'),
        ),
        equals(<String>[_presentationHit(2, 'duration-literal')]),
      );
    });

    test('T-24-SCAN-07: 표시 없는 이름 붙인 선언은 걸리고 표시된 선언은 통과한다', () {
      expect(
        findDesignLiteralHits(
          _presentationPath,
          '  static const Duration _kA = Duration(seconds: 2);',
        ),
        equals(<String>[_presentationHit(1, 'duration-literal')]),
      );
      expect(
        findDesignLiteralHits(
          _presentationPath,
          <String>[
            _marker,
            '  static const Duration _kA = Duration(seconds: 2);',
            '// design-literal: 시험용 이유',
            'const Duration _kB = Duration(seconds: 1);',
            _marker,
            '  static const Duration _kC =',
            '      Duration(milliseconds: 300);',
          ].join('\n'),
        ),
        isEmpty,
      );
    });

    test('T-24-SCAN-07: data 폴더 Duration · Durations 토큰은 대상 밖이다', () {
      expect(findDesignLiteralHits(_dataPath, inlineTimer), isEmpty);
      expect(
        findDesignLiteralHits(
          _presentationPath,
          '  duration: Durations.medium2,',
        ),
        isEmpty,
      );
      expect(
        findDesignLiteralHits(_dataPath, 'final Object a = EdgeInsets.all(8);'),
        equals(<String>['$_dataPath:1 — edge-insets-number']),
      );
    });
  });

  group('음성 표본', () {
    test('T-24-SCAN-08: 토큰 · 주석 · 색 파서 꼴은 0 건이다', () {
      for (final String source in _negativeLines) {
        expect(
          findDesignLiteralHits(_presentationPath, source),
          isEmpty,
          reason: source,
        );
      }
    });
  });
}
