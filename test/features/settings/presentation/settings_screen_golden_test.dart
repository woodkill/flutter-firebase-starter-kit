// Phase 16.7 Plan 12 — 설정 화면 golden (R1) + 줄바꿈 단언 (D-07).
//
// 설정 「내 계정」 3행(이메일 · 가입 수단 · 연결된 계정)은 제목 한 줄 + 값
// 아래 줄로 분리된다 (B2 · D-02 개정 (R1)). 사용자 sign-off 채택안 PNG
// `mockups/adopted_settings_r1_ko_280_worst_{light,dark}.png` 와 production
// `SettingsScreen` golden(`goldens/settings_screen_ko_280_worst_{light,dark}.png`)
// 이 byte 동일해야 sign-off 가 golden 으로 이어진 증거가 된다 (UI-SPEC
// §Golden 캡처 계약 (R1)).
//
// **캡처 계약:** 280×800 logical · DPR 3 · 빈 `Scaffold` 위 `MaterialPageRoute`
// push 진입(AppBar back 화살표 포함) · production 폰트 FontLoader +
// `assets/test_fonts` Noto Sans CJK KR/JP subset · test 전용 ThemeData 에만
// `fontFamilyFallback` · `find.byType(MaterialApp)` 전체 캡처. worst case 는
// 연결 가능 provider 가 없어 「계정 연결」 section 이 숨는다. viewport 는
// `tester.view` 로 주입한다 (MediaQuery 동기화).
//
// **단언:** UI-SPEC 「(R1) 설정 쪽 단언 변경」 2 · 3 — 연결된 계정 값(subtitle
// 문단)의 라벨 내부 줄바꿈 0 · 줄은 쉼표 뒤에서만 바뀜 · 줄 수 = 항목 기준선
// 묶음 수(ko/en/ja × worst · D-11, §Surface S (R1) 실측 표).
//
// **fixture 갱신:** `fvm flutter test --update-goldens <this file>` 후 산출
// PNG 를 `cmp` 로 adopted 와 대조한다. 불일치면 adopted 를 덮어쓰지 말고
// 원인(구현 트리 · harness 조건 차이)을 먼저 찾는다.

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_starter_kit/core/auth/auth_strategies_registry.dart';
import 'package:flutter_starter_kit/core/auth/auth_strategy.dart';
import 'package:flutter_starter_kit/core/auth/strategies/apple_auth_strategy.dart';
import 'package:flutter_starter_kit/core/auth/strategies/facebook_auth_strategy.dart';
import 'package:flutter_starter_kit/core/auth/strategies/google_auth_strategy.dart';
import 'package:flutter_starter_kit/core/auth/strategies/kakao_auth_strategy.dart';
import 'package:flutter_starter_kit/core/auth/strategies/line_auth_strategy.dart';
import 'package:flutter_starter_kit/core/auth/strategies/naver_auth_strategy.dart';
import 'package:flutter_starter_kit/core/theme/app_theme.dart';
import 'package:flutter_starter_kit/features/auth/data/auth_repository.dart';
import 'package:flutter_starter_kit/features/auth/domain/user.dart';
import 'package:flutter_starter_kit/shared/auth/provider_label_formatter.dart';
import 'package:flutter_starter_kit/features/settings/presentation/settings_screen.dart';
import 'package:flutter_starter_kit/l10n/generated/app_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

/// [AuthRepository] 대체 Mock — 설정 화면 렌더는 repository 를 호출하지
/// 않으므로 stub 을 두지 않는다.
class _MockAuthRepository extends Mock implements AuthRepository {}

/// golden device pixel ratio — mockup 촬영 조건(DPR 3)과 같다.
const double _dpr = 3.0;

/// 설정 viewport 높이 (logical px) — UI-SPEC §Golden 캡처 계약 S 열.
const double _settingsHeight = 800;

/// 활성 소셜 Strategy 6종 — `settings_screen_test.dart` `_allStrategies` 순서.
const List<AuthStrategy> _sixStrategies = <AuthStrategy>[
  GoogleAuthStrategy(),
  AppleAuthStrategy(),
  FacebookAuthStrategy(),
  KakaoAuthStrategy(),
  NaverAuthStrategy(),
  LineAuthStrategy(),
];

/// 보유 provider 7종 전부 — UI-SPEC fixture 표 verbatim 순서.
const List<String> _allProviderIds = <String>[
  'google.com',
  'apple.com',
  'facebook.com',
  'kakao',
  'naver',
  'line',
  'password',
];

/// locale 별 표시 이름 — UI-SPEC fixture 표 (합성 값 · PII 0).
const Map<String, String> _displayNames = <String, String>{
  'ko': '홍길동',
  'en': 'Jane Doe',
  'ja': '山田太郎',
};

/// 단언 2 · 3 의 연결된 계정 값 줄 수 기대값 — UI-SPEC §Surface S (R1) 실측
/// 표 (280 · worst / D-11). 값 문단에는 행 라벨 prefix 가 없으므로 줄 수 =
/// 항목 기준선 묶음 수 그대로다.
const Map<String, (int, int)> _expectedLinkedLines = <String, (int, int)>{
  'ko': (3, 3),
  'en': (3, 3),
  'ja': (3, 3),
};

/// UI-SPEC fixture — 가입 수단 [signUpProviderId](null = D-11 기록 없음) ·
/// 보유 provider 7종.
User _fixtureUser(String lang, {required String? signUpProviderId}) {
  return User(
    uid: 'Xy7Qa2Lm9Rt4Wz8Kp1Nc5Vb3Hd6',
    email: 'me@example.com',
    emailVerified: true,
    displayName: _displayNames[lang],
    createdAt: DateTime.utc(2026, 9, 26, 12),
    providerIds: _allProviderIds,
    signUpProviderId: signUpProviderId,
  );
}

/// [family] 이름으로 [paths] 의 폰트 파일들을 [FontLoader] 에 등록한다.
///
/// 자산 부재는 [TestFailure] 로 surface 한다 — silent fallback 으로 golden 이
/// tofu · Ahem 렌더로 바뀌는 drift 를 막는다.
Future<void> _loadFamily(String family, List<String> paths) async {
  final loader = FontLoader(family);
  for (final path in paths) {
    final file = File(path);
    if (!file.existsSync()) {
      throw TestFailure(
        '$family 폰트 자산 부재 ($path) — Phase 16.7 golden 생성 불가. '
        'production bundle 자산 또는 assets/test_fonts 누락 여부 확인 의무.',
      );
    }
    final bytes = await file.readAsBytes();
    loader.addFont(Future.value(ByteData.sublistView(bytes)));
  }
  await loader.load();
}

/// golden 폰트 5 family + CJK subset 2종을 등록한다.
///
/// flutter_test 는 pubspec `fonts:` 를 자동 로드하지 않고 동적 로드 폰트로
/// 자동 fallback 하지도 않는다 — ko/ja 글리프는 [_theme] 의 test 전용
/// `fontFamilyFallback` 으로만 CJK subset 에 닿는다.
Future<void> _loadGoldenFonts() async {
  await _loadFamily('Roboto', <String>[
    'assets/fonts/roboto/Roboto-VariableFont_wdth_wght.ttf',
  ]);
  await _loadFamily('Inter', <String>[
    'assets/fonts/inter/Inter-Regular.ttf',
    'assets/fonts/inter/Inter-Medium.ttf',
  ]);
  await _loadFamily('Pretendard', <String>[
    'assets/fonts/pretendard/PretendardVariable.ttf',
  ]);
  final flutterRoot = Platform.environment['FLUTTER_ROOT'];
  if (flutterRoot == null || flutterRoot.isEmpty) {
    throw TestFailure(
      'FLUTTER_ROOT 환경변수 부재 — MaterialIcons 폰트 경로를 결정할 수 없다. '
      '`fvm flutter test` 로 실행했는지 확인 의무.',
    );
  }
  await _loadFamily('MaterialIcons', <String>[
    '$flutterRoot/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
  ]);
  await _loadFamily('MockCjkKR', <String>[
    'assets/test_fonts/NotoSansCJKKR-Regular-Subset.otf',
  ]);
  await _loadFamily('MockCjkJP', <String>[
    'assets/test_fonts/NotoSansCJKJP-Regular-Subset.otf',
  ]);
}

/// [lang] 의 CJK fallback family 이름 (ko/ja 외 null).
String? _cjkFamily(String lang) => switch (lang) {
  'ko' => 'MockCjkKR',
  'ja' => 'MockCjkJP',
  _ => null,
};

/// production [AppTheme] + ko/ja 만 test 전용 CJK `fontFamilyFallback`.
///
/// `lib/` 테마는 건드리지 않는다 — Android 시스템 CJK fallback 을 test 에서
/// 재현하는 장치다 (UI-SPEC §Mockup CJK 재현성).
ThemeData _theme(Brightness brightness, String lang) {
  final base = brightness == Brightness.light
      ? AppTheme.light()
      : AppTheme.dark();
  final family = _cjkFamily(lang);
  if (family == null) return base;
  return base.copyWith(
    textTheme: base.textTheme.apply(fontFamilyFallback: <String>[family]),
  );
}

/// 비동기 이미지 디코딩을 흡수한 뒤 frame 을 안정화한다 (16.1 golden 패턴).
Future<void> _settleAssets(WidgetTester tester) async {
  await tester.runAsync(() async {
    await tester.pumpAndSettle();
    for (final element in find.byType(Image).evaluate().toList()) {
      final widget = element.widget as Image;
      await precacheImage(widget.image, element);
    }
    await Future<void>.delayed(const Duration(milliseconds: 200));
    await tester.pumpAndSettle();
  });
  await tester.pumpAndSettle();
}

/// 빈 [Scaffold] 위에 production [SettingsScreen] 을 push 해 [width]×800 ·
/// DPR 3 viewport 에 올린다.
///
/// override 는 UI-SPEC §Golden 캡처 계약 S 열 — repository mock · 활성
/// strategy 6 · 사용자 fixture. [ProviderScope] 에 새 key 를 줘 반복 pump
/// 마다 새 container 를 만든다.
Future<void> _pumpSettings(
  WidgetTester tester, {
  required User user,
  required Locale locale,
  required Brightness brightness,
  required double width,
}) async {
  tester.view.devicePixelRatio = _dpr;
  tester.view.physicalSize = Size(width, _settingsHeight) * _dpr;
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);

  await tester.pumpWidget(
    ProviderScope(
      key: UniqueKey(),
      overrides: [
        authRepositoryProvider.overrideWithValue(_MockAuthRepository()),
        activeStrategiesProvider.overrideWithValue(_sixStrategies),
        currentUserProvider.overrideWith((ref) => user),
      ],
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: _theme(brightness, locale.languageCode),
        locale: locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const Scaffold(),
      ),
    ),
  );
  await tester.pump();
  unawaited(
    Navigator.of(
      tester.element(find.byType(Scaffold)),
    ).push(MaterialPageRoute<void>(builder: (_) => const SettingsScreen())),
  );
  await _settleAssets(tester);
}

/// [rp] 를 같은 폭으로 [TextPainter] 에 재배치했을 때의 줄 수.
int _relaidLineCount(RenderParagraph rp) {
  final painter = TextPainter(
    text: rp.text,
    textDirection: rp.textDirection,
    textScaler: rp.textScaler,
    locale: rp.locale,
    strutStyle: rp.strutStyle,
    textWidthBasis: rp.textWidthBasis,
    textHeightBehavior: rp.textHeightBehavior,
  )..layout(maxWidth: rp.size.width);
  final count = painter.computeLineMetrics().length;
  painter.dispose();
  return count;
}

/// [rp] 가 실제 렌더된 줄 수 — 같은 제약 · maxLines · ellipsis 로 재배치해 센다.
///
/// [RenderParagraph] 는 줄 metric 을 노출하지 않으므로 [TextPainter] 로 같은
/// 조건을 재현한다 (mockup harness `_paragraphFacts` 와 같은 계산).
int _renderedLineCount(RenderParagraph rp) {
  final painter = TextPainter(
    text: rp.text,
    textDirection: rp.textDirection,
    textScaler: rp.textScaler,
    locale: rp.locale,
    strutStyle: rp.strutStyle,
    textWidthBasis: rp.textWidthBasis,
    textHeightBehavior: rp.textHeightBehavior,
    maxLines: rp.maxLines,
    ellipsis: rp.overflow == TextOverflow.ellipsis ? '…' : null,
  )..layout(maxWidth: rp.constraints.maxWidth);
  final count = painter.computeLineMetrics().length;
  painter.dispose();
  return count;
}

/// 「이메일」 행 [ListTile] finder — leading `Icons.alternate_email` 의 조상.
Finder _emailTile() => find.ancestor(
  of: find.byIcon(Icons.alternate_email),
  matching: find.byType(ListTile),
);

/// 「가입 수단」 행 [ListTile] finder — leading `Icons.how_to_reg` 의 조상.
Finder _signUpTile() => find.ancestor(
  of: find.byIcon(Icons.how_to_reg),
  matching: find.byType(ListTile),
);

/// 「연결된 계정」 행 [ListTile] finder — leading `Icons.link` 의 조상.
Finder _linkedTile() =>
    find.ancestor(of: find.byIcon(Icons.link), matching: find.byType(ListTile));

/// 연결된 계정 값의 줄 구조 — 줄 수 · 항목 문자열 · 기준선 줄 묶음 · 라벨
/// 내부 줄바꿈 수.
///
/// 값 문단(subtitle `Text.rich`)은 WidgetSpan 자리표시를 품어 [TextPainter] 로
/// 재배치할 수 없다 — 줄 수는 항목을 기준선 y 로 묶은 줄 수다. 제목은 별도
/// `Text` 이고 값 문단에는 행 라벨 prefix 가 없으므로 보정하지 않는다 (R1).
({int lines, List<String> items, List<List<String>> rows, int innerWrap})
_linkedValueLayout(WidgetTester tester) {
  final outer = find.descendant(
    of: _linkedTile(),
    matching: find.byWidgetPredicate((w) => w is Text && w.textSpan != null),
  );
  expect(outer, findsOneWidget);
  final paragraphs = find
      .descendant(of: outer, matching: find.byType(RichText))
      .evaluate()
      .map((e) => e.renderObject! as RenderParagraph)
      .toList();
  // 첫 RichText = 바깥 문단, 나머지 = WidgetSpan 안 항목 Text.
  final byBaseline = <int, List<(double, String)>>{};
  final items = <String>[];
  var innerWrap = 0;
  for (final rp in paragraphs.skip(1)) {
    final origin = rp.localToGlobal(Offset.zero);
    final baseline =
        origin.dy + rp.computeDistanceToActualBaseline(TextBaseline.alphabetic);
    final text = rp.text.toPlainText();
    items.add(text);
    byBaseline.putIfAbsent(baseline.round(), () => []).add((origin.dx, text));
    if (_relaidLineCount(rp) != 1) innerWrap++;
  }
  final keys = byBaseline.keys.toList()..sort();
  final rows = [
    for (final key in keys)
      ([
        ...byBaseline[key]!,
      ]..sort((a, b) => a.$1.compareTo(b.$1))).map((e) => e.$2).toList(),
  ];
  return (lines: rows.length, items: items, rows: rows, innerWrap: innerWrap);
}

void main() {
  setUpAll(() async {
    await _loadGoldenFonts();
  });

  group('Phase 16.7 설정 화면 golden (R1) — ko 280×800 worst · push (D-07)', () {
    for (final brightness in Brightness.values) {
      final mode = brightness.name;

      testWidgets('golden ko 280 worst — $mode', (tester) async {
        await _pumpSettings(
          tester,
          user: _fixtureUser('ko', signUpProviderId: 'line'),
          locale: const Locale('ko'),
          brightness: brightness,
          width: 280,
        );
        // 7 provider 전부 연결 — 「계정 연결」 section 은 숨는다.
        final l10n = lookupAppLocalizations(const Locale('ko'));
        expect(find.text(l10n.settingsAccountLinkingSection), findsNothing);
        expect(
          tester.takeException(),
          isNull,
          reason: 'layout 예외 0 이어야 golden 이 시각 계약을 대표한다',
        );
        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile('goldens/settings_screen_ko_280_worst_$mode.png'),
        );
      });
    }
  });

  group('Phase 16.7 설정 연결된 계정 (R1) — 라벨 한 줄 · 줄바꿈 위치 (단언 2 · 3)', () {
    for (final lang in <String>['ko', 'en', 'ja']) {
      for (final worst in <bool>[true, false]) {
        final fixture = worst ? 'worst' : 'd11';

        testWidgets('라벨 한 줄 · 줄바꿈 위치 — $lang $fixture', (tester) async {
          await _pumpSettings(
            tester,
            user: _fixtureUser(lang, signUpProviderId: worst ? 'line' : null),
            locale: Locale(lang),
            brightness: Brightness.light,
            width: 280,
          );
          expect(tester.takeException(), isNull);

          final layout = _linkedValueLayout(tester);
          expect(layout.items, hasLength(worst ? 6 : 7));
          expect(layout.innerWrap, 0, reason: '라벨 내부 줄바꿈 0 (D-04 보강)');
          for (final row in layout.rows.take(layout.rows.length - 1)) {
            expect(row.last, endsWith(','), reason: '줄은 쉼표 뒤에서만 바뀐다');
          }
          expect(layout.rows.last.last, isNot(endsWith(',')));
          final expected = _expectedLinkedLines[lang]!;
          expect(layout.lines, worst ? expected.$1 : expected.$2);
        });
      }
    }
  });

  group('Phase 16.7 설정 가입 수단 값 — 1줄 가드 (D-04 개정 (R1) · 단언 10)', () {
    // 지원 provider 전부 + 미지 값 1개 + 기록 없음 — 집합을 순회하고 provider
    // 별 분기 · 하드코딩 라벨을 두지 않는다 (D-27). 새 provider 라벨이 값 폭을
    // 넘으면 이 가드가 실패한다. 폰트 로드 harness 안에서만 의미가 있다 —
    // flutter_test 기본 Ahem 이면 en 라벨이 거짓 실패한다.
    final values = <String?>[...kSupportedAuthProviderIds, 'twitter.com', null];

    for (final lang in <String>['ko', 'en', 'ja']) {
      for (final width in <double>[280, 360]) {
        testWidgets('가입 수단 값 1줄 가드 — $lang ${width.toInt()}', (tester) async {
          final l10n = lookupAppLocalizations(Locale(lang));
          var isTitleChecked = false;
          for (final id in values) {
            await _pumpSettings(
              tester,
              user: _fixtureUser(lang, signUpProviderId: id),
              locale: Locale(lang),
              brightness: Brightness.light,
              width: width,
            );
            final combo = '$lang ${width.toInt()} $id';
            expect(tester.takeException(), isNull, reason: 'overflow $combo');

            // 기대 라벨 = production 과 같은 helper (null → '-' · 미지 값 →
            // errorUnknownProvider).
            final label = formatProviderIds(
              id == null ? const <String>[] : <String>[id],
              l10n,
            );
            final value = find.descendant(
              of: _signUpTile(),
              matching: find.text(label),
            );
            expect(value, findsOneWidget, reason: 'value $combo');
            final rp = tester.renderObject<RenderParagraph>(value);
            expect(_renderedLineCount(rp), 1, reason: 'guard-lines $combo');
            expect(rp.didExceedMaxLines, isFalse, reason: 'ellipsis $combo');
            expect(
              tester.getSize(_signUpTile()).height,
              closeTo(72, 0.5),
              reason: 'row-height $combo',
            );
            if (id == 'twitter.com') {
              expect(label, l10n.errorUnknownProvider);
              expect(find.textContaining('twitter'), findsNothing);
            }
            if (id == null) expect(label, '-');

            // 제목 3개 한 줄 — 280 렌더에서 케이스당 1회.
            if (width == 280 && !isTitleChecked) {
              isTitleChecked = true;
              final titles = <(Finder, String)>[
                (_emailTile(), l10n.authAccountEmail),
                (_signUpTile(), l10n.authAccountSignUpMethod),
                (_linkedTile(), l10n.authAccountLinkedAccounts),
              ];
              for (final (tile, title) in titles) {
                final titleRp = tester.renderObject<RenderParagraph>(
                  find.descendant(of: tile, matching: find.text(title)),
                );
                expect(
                  _renderedLineCount(titleRp),
                  1,
                  reason: 'title-lines $lang $title',
                );
              }
            }
          }
        });
      }
    }
  });
}
