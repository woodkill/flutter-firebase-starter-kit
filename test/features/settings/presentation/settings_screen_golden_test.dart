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
//
// **Phase 16.8 (Plan 16.8-01 Task 2):** 설정 golden fixture = W5(가입 naver +
// 보유 6 — 도달 가능 최악)로 바꾸고 채택안 `mockups/adopted_settings_16_8_ko_280_
// worst_{light,dark}.png` 와 대조한다. 해제 확인 다이얼로그 golden 2장(ko 280 ·
// Facebook)은 같은 harness 에서 production 탭 경로(밑줄 이름 → 다이얼로그)로
// 열어 `adopted_unlink_dialog_ko_280_facebook_{light,dark}.png` 와 대조한다.
// D-13 — 해제 버튼 ≥ 24×24 dp · `labeledTapTargetGuideline` ·
// `textContrastGuideline` (Android 48dp guideline 은 inline 예외라 걸지 않는다 ·
// UI-SPEC Q6-A). 16.7 줄바꿈 단언 · 가입 수단 1줄 가드는 보유 7 fixture 그대로.
//
// **Phase 16.10 (Plan 16.10-08 Task 2):** 해제 다이얼로그 content 가 U′(본문 +
// 앱 연결 고지 + 재로그인 provider 로그인 안내)로 바뀌어(Q7-A) Facebook
// 다이얼로그 golden 은 반드시 바뀐다. 대조 채택안은 16.10
// `mockups/adopted_unlink_dialog_16_10_ko_280_{google,facebook}_{light,dark}.png`
// 로 바뀌고 Google 2장이 새로 생긴다 — 16.8 `adopted_unlink_dialog_ko_280_
// facebook_*` 는 이력으로 보존한다(덮어쓰기 0). 설정 화면 golden 은 byte 불변.
// 공용 harness(FontLoader · theme · settle · push 진입)는 같은 디렉터리의
// golden harness 파일로 승격했다(진행 화면 golden 과 공유).
//
// **Phase 17 (Plan 17-15 · 17-17):** 설정 화면에 알림 섹션(Q3-A) · 프로필 사진
// 행(Q2-A)이 들어가 설정 golden 2장이 바뀌고, 채택안
// `mockups/adopted_settings_17_ko_280_worst_{light,dark}.png`(사진 없음 · 알림
// 꺼짐)와 byte 동일해야 한다. 해제 다이얼로그 golden 4장은 barrier 너머 설정
// 배경만 바뀐다(다이얼로그 surface 변경 0 · UI-SPEC 「2026-10-01 정정」).

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_starter_kit/core/auth/auth_strategies_registry.dart';
import 'package:flutter_starter_kit/features/auth/data/auth_repository.dart';
import 'package:flutter_starter_kit/features/auth/domain/user.dart';
import 'package:flutter_starter_kit/shared/auth/provider_label_formatter.dart';
import 'package:flutter_starter_kit/features/settings/presentation/settings_screen.dart';
import 'package:flutter_starter_kit/l10n/generated/app_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'settings_golden_harness.dart';

/// [AuthRepository] 대체 Mock — 설정 화면 렌더는 repository 를 호출하지
/// 않으므로 stub 을 두지 않는다.
class _MockAuthRepository extends Mock implements AuthRepository {}

/// Phase 16.8 W5 — 가입 naver + 연결 5 (도달 가능 최악 · UI-SPEC §Golden
/// 캡처 계약 fixture verbatim 순서).
const List<String> _w5ProviderIds = <String>[
  'google.com',
  'apple.com',
  'facebook.com',
  'kakao',
  'line',
  'naver',
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
/// 보유 provider [providerIds] (기본 7종 · Phase 16.8 golden 은 [_w5ProviderIds]).
User _fixtureUser(
  String lang, {
  required String? signUpProviderId,
  List<String> providerIds = _allProviderIds,
}) {
  return User(
    uid: 'Xy7Qa2Lm9Rt4Wz8Kp1Nc5Vb3Hd6',
    email: 'me@example.com',
    emailVerified: true,
    displayName: _displayNames[lang],
    createdAt: DateTime.utc(2026, 9, 26, 12),
    providerIds: providerIds,
    signUpProviderId: signUpProviderId,
  );
}

/// 사진 출처 stream fixture — 업로드 사진 없음 (UI-SPEC §Golden 캡처 계약 ·
/// 채택안 조건 「사진 없음」).
const UserProviderRecord _kNoPhotoRecord = (
  linkedProviderIds: <String>[],
  signUpProviderId: null,
  customPhotoUrl: null,
);

/// 빈 [Scaffold] 위에 production [SettingsScreen] 을 push 해 [width]×800 ·
/// DPR 3 viewport 에 올린다 ([pumpGoldenRoute] 위임).
///
/// override 는 UI-SPEC §Golden 캡처 계약 S 열 — repository mock · 활성
/// strategy 6 · 사용자 fixture · 사진 출처 stream(업로드 사진 없음 · Phase 17).
Future<void> _pumpSettingsScreen(
  WidgetTester tester, {
  required User user,
  required Locale locale,
  required Brightness brightness,
  required double width,
}) {
  return pumpGoldenRoute(
    tester,
    route: (_) => const SettingsScreen(),
    overrides: [
      authRepositoryProvider.overrideWithValue(_MockAuthRepository()),
      activeStrategiesProvider.overrideWithValue(kGoldenSixStrategies),
      currentUserProvider.overrideWith((ref) => user),
      // Phase 17 (UI-SPEC §Golden 캡처 계약) — 사진 행의 사진 출처 stream 을
      // data(업로드 사진 없음)로 고정한다. 네트워크 사진 비결정성 회피 ·
      // 미초기화 Firestore 무접촉.
      linkedProvidersStreamProvider(
        user.uid,
      ).overrideWith((ref) => Stream.value(_kNoPhotoRecord)),
    ],
    locale: locale,
    brightness: brightness,
    width: width,
  );
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
///
/// 바깥 문단은 `ListTile.subtitle` 위젯 identity 로 특정한다 — Phase 16.8 의
/// 해제 버튼 항목도 `Text.rich` 라 위젯 술어로는 단일 특정 불가 (채택 harness
/// `_linkedLayout` 과 같은 기준).
({int lines, List<String> items, List<List<String>> rows, int innerWrap})
_linkedValueLayout(WidgetTester tester) {
  final tile = tester.widget<ListTile>(_linkedTile());
  final subtitle = tile.subtitle;
  expect(subtitle, isA<Text>());
  final paragraphs = find
      .descendant(of: find.byWidget(subtitle!), matching: find.byType(RichText))
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
    await loadGoldenFonts();
  });

  // Phase 17 T-17-PHOTO-08 — W5 fixture + 사진 없음(record data · customPhotoUrl ·
  // photoUrl null) + 알림 꺼짐으로 그린 golden 2장이 채택안
  // `mockups/adopted_settings_17_ko_280_worst_{light,dark}.png` 와 byte 동일하다는
  // 계약 이름이다(대조 = plan 17-17 Task 3 `cmp` · 채택안 파일은 test 에서 읽지
  // 않는다 — public 배포본에는 `.planning/` 이 없다).
  group('T-17-PHOTO-08: 설정 화면 golden — ko 280×800 W5 · 사진 없음 · 알림 꺼짐 '
      '= 채택안 byte 동일 (Phase 16.8 D-07 · D-14 · Phase 17)', () {
    for (final brightness in Brightness.values) {
      final mode = brightness.name;

      testWidgets('golden ko 280 worst — $mode', (tester) async {
        await _pumpSettingsScreen(
          tester,
          user: _fixtureUser(
            'ko',
            signUpProviderId: 'naver',
            providerIds: _w5ProviderIds,
          ),
          locale: const Locale('ko'),
          brightness: brightness,
          width: 280,
        );
        // W5 — 연결 가능 provider 전부 보유 · 「계정 연결」 section 은 숨는다.
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

  group('Phase 16.10 해제 다이얼로그 golden — ko 280 Google · Facebook', () {
    for (final (provider, label) in const <(String, String)>[
      ('google', 'Google'),
      ('facebook', 'Facebook'),
    ]) {
      for (final brightness in Brightness.values) {
        final mode = brightness.name;

        testWidgets('dialog golden ko 280 $label — $mode', (tester) async {
          await _pumpSettingsScreen(
            tester,
            user: _fixtureUser(
              'ko',
              signUpProviderId: 'naver',
              providerIds: _w5ProviderIds,
            ),
            locale: const Locale('ko'),
            brightness: brightness,
            width: 280,
          );
          // production 탭 경로 — 밑줄 이름 → _onUnlinkPressed →
          // UnlinkConfirmationDialog.show. router 없는 harness 에서도 예외 0
          // (GoRouter 는 reauthRequired arm 에서만 해석한다). 끊기 dispatch 는
          // 「해제」 탭 전이라 호출 0 (다이얼로그는 레지스트리 kind 만 읽는다).
          final handle = tester.ensureSemantics();
          await tester.tap(find.bySemanticsLabel('$label 연결 해제'));
          await tester.pumpAndSettle();
          await settleGoldenAssets(tester);
          expect(find.byType(AlertDialog), findsOneWidget);
          expect(
            tester.takeException(),
            isNull,
            reason: 'layout · 탭 경로 예외 0 이어야 golden 이 시각 계약을 대표한다',
          );
          await expectLater(
            find.byType(MaterialApp),
            matchesGoldenFile(
              'goldens/unlink_dialog_ko_280_${provider}_$mode.png',
            ),
          );
          handle.dispose();
        });
      }
    }
  });

  group('Phase 16.8 D-13 — 버튼 크기 · a11y guideline', () {
    testWidgets('해제 버튼 ≥ 24×24 · labeledTapTarget · textContrast — ko 280 W5', (
      tester,
    ) async {
      await _pumpSettingsScreen(
        tester,
        user: _fixtureUser(
          'ko',
          signUpProviderId: 'naver',
          providerIds: _w5ProviderIds,
        ),
        locale: const Locale('ko'),
        brightness: Brightness.light,
        width: 280,
      );
      final handle = tester.ensureSemantics();
      await tester.pump();
      for (final label in const <String>[
        'Google 연결 해제',
        'Apple 연결 해제',
        'Facebook 연결 해제',
        '카카오 연결 해제',
        '라인 연결 해제',
      ]) {
        final button = find.bySemanticsLabel(label);
        expect(button, findsOneWidget, reason: label);
        final size = tester.getSize(button);
        // WCAG 2.2 SC 2.5.8 (AA) 24 × 24 — 48 dp 미달은 inline 예외 (Q6-A).
        expect(size.width, greaterThanOrEqualTo(24), reason: 'width $label');
        expect(size.height, greaterThanOrEqualTo(24), reason: 'height $label');
      }
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      await expectLater(tester, meetsGuideline(textContrastGuideline));
      handle.dispose();
    });
  });

  group('Phase 16.7 설정 연결된 계정 (R1) — 라벨 한 줄 · 줄바꿈 위치 (단언 2 · 3)', () {
    for (final lang in <String>['ko', 'en', 'ja']) {
      for (final worst in <bool>[true, false]) {
        final fixture = worst ? 'worst' : 'd11';

        testWidgets('라벨 한 줄 · 줄바꿈 위치 — $lang $fixture', (tester) async {
          await _pumpSettingsScreen(
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
            await _pumpSettingsScreen(
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
            final label = formatSignUpMethod(id, l10n);
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
