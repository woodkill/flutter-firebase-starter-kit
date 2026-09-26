// Phase 16.7 Plan 06 Task 1 — 홈 계정 section golden + 줄바꿈 단언 (D-07).
//
// 채택안 mockup PNG(`mockups/adopted_home_ko_280_worst_{light,dark}.png`) 와
// production `EnvironmentInfoScreen` 의 계정 section golden 이 byte 동일해야
// 사용자 sign-off 가 golden 으로 이어진 증거가 된다 (UI-SPEC §Golden 캡처 계약).
//
// **캡처 계약:** 280×1400 logical · DPR 3 · production 폰트 FontLoader +
// `assets/test_fonts` Noto Sans CJK KR/JP subset · test 전용 ThemeData 에만
// `fontFamilyFallback` · `localeProvider` override(가입일 `formatYMD`) ·
// section 을 감싼 ListView 항목 `RenderRepaintBoundary.toImage(pixelRatio: 3.0)`.
// `matchesGoldenFile(finder)` 는 비루트 boundary 를 pixelRatio 1 로 찍으므로
// 쓰지 않는다. viewport 는 `tester.view` 로 주입한다 (MediaQuery 동기화).
//
// **단언:** UI-SPEC §Line-break Mechanism 테스트 단언 2 · 3 · 7(ko/en/ja ×
// worst · D-11) + E1 가입 수단 값 ellipsis 0(7 라벨 × ko/en/ja × 280/360).
// 줄 수 1 은 단언하지 않는다 — 1줄 초과 조합은 plan verify 의 E1 gate 가
// 사용자 sign-off 로 넘긴다.
//
// **증거 수집 (opt-in, IN-04):** 기본 실행은 단언만 하고 파일을 쓰지 않는다.
// E1 줄 수 실측 TSV(`build/uat-16.7/p06-signup-lines-home.tsv`, 42 행) 와 1줄
// 초과 조합의 light · dark 재렌더 PNG(`build/uat-16.7/signup-label-exceed/`)
// 는 아래 명령으로만 다시 만든다.
//
//   fvm flutter test --dart-define=UAT_EVIDENCE=true \
//     test/features/home/environment_info_screen_golden_test.dart
//
// **fixture 갱신:** `fvm flutter test --update-goldens <this file>` 후 산출
// PNG 를 `cmp` 로 adopted 와 대조한다. 불일치면 adopted 를 덮어쓰지 말고
// 원인(replica 어긋남 · 계약 위반)을 먼저 찾는다.

import 'dart:io';
import 'dart:ui' as ui;

import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_starter_kit/core/providers/firebase_providers.dart';
import 'package:flutter_starter_kit/core/providers/locale_provider.dart';
import 'package:flutter_starter_kit/core/theme/app_theme.dart';
import 'package:flutter_starter_kit/features/auth/data/auth_repository.dart';
import 'package:flutter_starter_kit/features/auth/domain/user.dart';
import 'package:flutter_starter_kit/features/home/presentation/environment_info_screen.dart';
import 'package:flutter_starter_kit/shared/auth/provider_label_formatter.dart';
import 'package:flutter_starter_kit/l10n/generated/app_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// [AuthRepository] 대체 Mock — 계정 section 렌더는 repository 를 호출하지
/// 않으므로 stub 을 두지 않는다.
class _MockAuthRepository extends Mock implements AuthRepository {}

/// [fb.FirebaseAuth] 대체 Mock — `isFirebaseInitializedProvider` false 경로.
class _MockFirebaseAuth extends Mock implements fb.FirebaseAuth {}

/// golden device pixel ratio — mockup 촬영 조건(DPR 3)과 같다.
const double _dpr = 3.0;

/// 홈 viewport 높이 (logical px) — UI-SPEC §Golden 캡처 계약 H 열.
const double _homeHeight = 1400;

/// 증거 수집 게이트 — `--dart-define=UAT_EVIDENCE=true` 일 때만 TSV · PNG 를
/// 쓴다 (IN-04). 기본 실행은 읽기 전용 파일시스템에서도 통과해야 한다.
const bool _collectEvidence = bool.fromEnvironment('UAT_EVIDENCE');

/// 결과 산출 디렉터리 (gitignored `build/`).
const String _outDir = 'build/uat-16.7';

/// E1 가입 수단 값 줄 수 실측 TSV — 증거 수집 실행마다 42 행을 새로 쓴다.
const String _tsvPath = '$_outDir/p06-signup-lines-home.tsv';

/// 1줄 초과 조합의 실 렌더 PNG 디렉터리 (사용자 sign-off 제시용).
const String _exceedDir = '$_outDir/signup-label-exceed';

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

/// 단언 2 · 3 의 연결된 계정 값 줄 수 기대값 — UI-SPEC §Mockup 최종안 실측 표
/// (H 280 · worst / D-11).
const Map<String, (int, int)> _expectedLinkedLines = <String, (int, int)>{
  'ko': (4, 4),
  'en': (4, 4),
  'ja': (4, 4),
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

/// 홈 ListView 를 [target] 이 빌드될 때까지 내린 뒤 화면 안으로 가져온다.
///
/// 계정 section 은 lazy ListView 의 뒤쪽이라 첫 frame 에 빌드되지 않는다.
/// 드래그 제스처 대신 position 을 직접 옮겨 ink 효과가 생기지 않게 한다.
Future<void> _scrollIntoView(WidgetTester tester, Finder target) async {
  final scrollable = tester.state<ScrollableState>(
    find.byType(Scrollable).first,
  );
  final position = scrollable.position;
  while (target.evaluate().isEmpty) {
    if (position.pixels >= position.maxScrollExtent) {
      throw TestFailure('홈 ListView 끝까지 내려도 대상 위젯이 빌드되지 않았다');
    }
    position.jumpTo(
      (position.pixels + _homeHeight / 2).clamp(0, position.maxScrollExtent),
    );
    await tester.pump();
  }
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
}

/// production [EnvironmentInfoScreen] 을 [width]×1400 · DPR 3 viewport 에
/// 올리고 계정 section title 을 화면 안으로 가져온다.
///
/// override 는 `environment_info_screen_test.dart` `_pumpScreen` 의 4개 +
/// `localeProvider`(가입일 `formatYMD` 가 읽는 값 — MaterialApp locale 과 같게).
/// [ProviderScope] 에 새 key 를 줘 반복 pump 마다 새 container 를 만든다.
Future<void> _pumpHome(
  WidgetTester tester, {
  required User user,
  required Locale locale,
  required Brightness brightness,
  required double width,
}) async {
  tester.view.devicePixelRatio = _dpr;
  tester.view.physicalSize = Size(width, _homeHeight) * _dpr;
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);

  await tester.pumpWidget(
    ProviderScope(
      key: UniqueKey(),
      overrides: [
        currentUserProvider.overrideWith((ref) => user),
        authRepositoryProvider.overrideWithValue(_MockAuthRepository()),
        isFirebaseInitializedProvider.overrideWithValue(false),
        firebaseAuthProvider.overrideWithValue(_MockFirebaseAuth()),
        localeProvider.overrideWithBuild((ref, notifier) => locale),
      ],
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: _theme(brightness, locale.languageCode),
        locale: locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const EnvironmentInfoScreen(),
      ),
    ),
  );
  await tester.pump();
  final l10n = lookupAppLocalizations(locale);
  await _scrollIntoView(tester, find.text(l10n.authAccountSectionTitle));
  await _settleAssets(tester);
}

/// 계정 section 을 감싼 ListView 항목 [RenderRepaintBoundary] finder.
Finder _sectionBoundary(AppLocalizations l10n) => find
    .ancestor(
      of: find.text(l10n.authAccountSectionTitle),
      matching: find.byType(RepaintBoundary),
    )
    .first;

/// 계정 section boundary 를 pixelRatio 3 으로 캡처한다.
Future<ui.Image> _captureSection(
  WidgetTester tester,
  AppLocalizations l10n,
) async {
  final rb = tester.renderObject<RenderRepaintBoundary>(_sectionBoundary(l10n));
  late ui.Image image;
  await tester.runAsync(() async {
    image = await rb.toImage(pixelRatio: 3.0);
  });
  return image;
}

/// [cardIcon] 을 가진 [Card] finder (가입 수단 = how_to_reg · 연결 = link).
Finder _cardOf(IconData cardIcon) =>
    find.ancestor(of: find.byIcon(cardIcon), matching: find.byType(Card));

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
    ellipsis: rp.overflow == TextOverflow.ellipsis ? '\u2026' : null,
  )..layout(maxWidth: rp.constraints.maxWidth);
  final count = painter.computeLineMetrics().length;
  painter.dispose();
  return count;
}

/// 연결된 계정 값의 줄 구조 — 항목 문자열 · 기준선 줄 묶음 · 라벨 내부 줄바꿈 수.
///
/// 바깥 문단은 WidgetSpan 자리표시를 품어 [TextPainter] 로 재배치할 수 없다 —
/// 줄 수는 항목을 기준선 y 로 묶은 줄 수로 센다 (홈 값에는 앞 문구가 없다).
({List<String> items, List<List<String>> rows, int innerWrap})
_linkedValueLayout(WidgetTester tester) {
  final outer = find.descendant(
    of: _cardOf(Icons.link),
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
  return (items: items, rows: rows, innerWrap: innerWrap);
}

/// 1줄 초과 조합을 light · dark 로 다시 렌더해 section PNG 를 저장한다.
Future<void> _saveExceedPngs(
  WidgetTester tester, {
  required String lang,
  required double width,
  required String providerId,
}) async {
  final locale = Locale(lang);
  final l10n = lookupAppLocalizations(locale);
  Directory(_exceedDir).createSync(recursive: true);
  for (final brightness in Brightness.values) {
    await _pumpHome(
      tester,
      user: _fixtureUser(lang, signUpProviderId: providerId),
      locale: locale,
      brightness: brightness,
      width: width,
    );
    expect(tester.takeException(), isNull);
    final image = await _captureSection(tester, l10n);
    await tester.runAsync(() async {
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      File(
        '$_exceedDir/home_${lang}_${width.toInt()}_${providerId}_'
        '${brightness.name}.png',
      ).writeAsBytesSync(data!.buffer.asUint8List());
    });
  }
}

void main() {
  setUpAll(() async {
    await _loadGoldenFonts();
    if (_collectEvidence) {
      Directory(_outDir).createSync(recursive: true);
      final tsv = File(_tsvPath);
      if (tsv.existsSync()) tsv.deleteSync();
    }
  });

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  group('Phase 16.7 홈 계정 section golden — ko 280 worst (D-07)', () {
    for (final brightness in Brightness.values) {
      final mode = brightness.name;

      testWidgets('golden ko 280 worst — $mode', (tester) async {
        final l10n = lookupAppLocalizations(const Locale('ko'));
        await _pumpHome(
          tester,
          user: _fixtureUser('ko', signUpProviderId: 'line'),
          locale: const Locale('ko'),
          brightness: brightness,
          width: 280,
        );
        expect(
          tester.takeException(),
          isNull,
          reason: 'layout 예외 0 이어야 golden 이 시각 계약을 대표한다',
        );
        final image = await _captureSection(tester, l10n);
        await expectLater(
          image,
          matchesGoldenFile('goldens/account_section_ko_280_worst_$mode.png'),
        );
      });
    }
  });

  group('Phase 16.7 홈 연결된 계정 — 라벨 한 줄 · 줄바꿈 위치 (단언 2 · 3)', () {
    for (final lang in <String>['ko', 'en', 'ja']) {
      for (final worst in <bool>[true, false]) {
        final fixture = worst ? 'worst' : 'd11';

        testWidgets('라벨 한 줄 · 줄바꿈 위치 — $lang $fixture', (tester) async {
          await _pumpHome(
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
          expect(layout.rows, hasLength(worst ? expected.$1 : expected.$2));
        });
      }
    }
  });

  group('Phase 16.7 홈 가입 수단 값 — ellipsis 0 · 줄 수 실측 (E1)', () {
    for (final lang in <String>['ko', 'en', 'ja']) {
      for (final width in <double>[280, 360]) {
        testWidgets('가입 수단 값 ellipsis 0 · 줄 수 실측 — $lang ${width.toInt()}', (
          tester,
        ) async {
          final locale = Locale(lang);
          final l10n = lookupAppLocalizations(locale);
          final exceeded = <String>[];
          for (final providerId in kSupportedAuthProviderIds) {
            await _pumpHome(
              tester,
              user: _fixtureUser(lang, signUpProviderId: providerId),
              locale: locale,
              brightness: Brightness.light,
              width: width,
            );
            expect(tester.takeException(), isNull);
            final label = formatSignUpMethod(providerId, l10n);
            final value = find.descendant(
              of: _cardOf(Icons.how_to_reg),
              matching: find.text(label),
            );
            final rp = tester.renderObject<RenderParagraph>(value);
            expect(rp.didExceedMaxLines, isFalse, reason: '$providerId 값');
            // 이하 증거 수집 — 회귀 가드는 위 didExceedMaxLines 단언뿐이다.
            if (!_collectEvidence) continue;
            final lines = _renderedLineCount(rp);
            File(_tsvPath).writeAsStringSync(
              'home\t$lang\t${width.toInt()}\t$providerId\t$lines\t'
              '${rp.didExceedMaxLines ? 1 : 0}\n',
              mode: FileMode.append,
            );
            if (lines > 1) exceeded.add(providerId);
          }
          // 줄 수 1 은 단언하지 않는다 — 초과 조합은 PNG 로 남겨 sign-off.
          // exceeded 는 증거 수집 실행에서만 채워진다.
          for (final providerId in exceeded) {
            await _saveExceedPngs(
              tester,
              lang: lang,
              width: width,
              providerId: providerId,
            );
          }
        });
      }
    }
  });
}
