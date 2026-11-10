// Phase 17.1 Plan 17.1-06 Task 3 — 계정 정보 화면 golden · a11y · 줄바꿈 가드
// (D-02 · D-22 · D-23 · UI-SPEC Q9-A 정정).
//
// 설정 화면 golden 테스트에서 옮긴 그룹 4 — Phase 16.10 해제 다이얼로그 golden
// (ko 280 Google · Facebook × light/dark) · Phase 16.8 D-13 버튼 크기 · a11y
// guideline · Phase 16.7 연결된 계정 라벨 한 줄 · 줄바꿈 위치 · 가입 수단 값 1줄
// 가드. 해제 버튼이 계정 화면으로 옮겨 가(D-02) 다이얼로그를 여는 화면 = 계정
// 화면이다.
//
// **해제 다이얼로그 golden 4장:** `MaterialApp` 전체 캡처라 barrier 너머 배경이
// 설정 → 계정 화면으로 바뀌어 다시 찍었다. 다이얼로그 surface 는 변경 0 — 옛
// golden 과 다이얼로그 surface 사각형(AlertDialog 안 Material rect × DPR 3 ·
// 모서리 radius 28 dp 를 피해 사방 30 px 안쪽)을 잘라 `cmp` 한 결과가 4장 모두
// 같다(plan 17.1-06 Task 3 · SUMMARY 기록). AlertDialog 위젯 rect 자체는 화면
// 전체라 쓰지 않는다.
//
// **캡처 계약:** 기존 설정 golden 과 같다 — 280×800 logical · DPR 3 · 빈
// `Scaffold` 위 `MaterialPageRoute` push 진입 · production 폰트 FontLoader +
// `assets/test_fonts` Noto Sans CJK subset · `find.byType(MaterialApp)` 전체
// 캡처 (`settings_golden_harness.dart`).
//
// **fixture 갱신:** `fvm flutter test --update-goldens <this file>` 뒤 다이얼로그
// 영역 crop 이 옛 golden 과 같은지 대조한다. 다르면 다이얼로그 위젯이 바뀐
// 것이므로 원인을 먼저 찾는다.
//
// **공용 helper:** 계정 화면 pump · fixture · 끝까지 스크롤은
// `account_golden_harness.dart` 에 있다.

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_starter_kit/core/auth/provider_id.dart';
import 'package:flutter_starter_kit/features/settings/presentation/_widgets/account_linking_section.dart';
import 'package:flutter_starter_kit/l10n/generated/app_localizations.dart';
import 'package:flutter_starter_kit/shared/auth/provider_label_formatter.dart';
import 'package:flutter_test/flutter_test.dart';

import 'account_golden_harness.dart';
import 'settings_golden_harness.dart';

/// 단언 2 · 3 의 연결된 계정 값 줄 수 기대값 — UI-SPEC §Surface S (R1) 실측
/// 표 (280 · worst / D-11). 값 문단에는 행 라벨 prefix 가 없으므로 줄 수 =
/// 항목 기준선 묶음 수 그대로다.
const Map<String, (int, int)> _expectedLinkedLines = <String, (int, int)>{
  'ko': (3, 3),
  'en': (3, 3),
  'ja': (3, 3),
};

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

  group('Phase 16.10 해제 다이얼로그 golden — ko 280 Google · Facebook', () {
    for (final (provider, label) in const <(String, String)>[
      ('google', 'Google'),
      ('facebook', 'Facebook'),
    ]) {
      for (final brightness in Brightness.values) {
        final mode = brightness.name;

        testWidgets('dialog golden ko 280 $label — $mode', (tester) async {
          await pumpAccountScreen(
            tester,
            user: buildFixtureUser(
              'ko',
              signUpProviderId: 'naver',
              providerIds: kGoldenW5ProviderIds,
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

  group('Phase 17.1 계정 화면 golden — ko 280 worst (T-171-ACCOUNT-golden)', () {
    // 채택 시안 `mockups/adopted_account_ko_280_worst{,_end}_{light,dark}.png`
    // 와 byte 동일해야 한다 (D-23 · 성공 기준 5 · UI-SPEC E5 overflow).
    // fixture = mockup harness 계정 worst 와 같은 값 — W5(가입 네이버 + 연결
    // 5) · 홍길동 · 긴 이메일 · 사진 없음.
    for (final brightness in Brightness.values) {
      final mode = brightness.name;

      testWidgets('T-171-ACCOUNT-golden-top: 위 W5 + 긴 이메일 ko 280 — $mode', (
        tester,
      ) async {
        await pumpAccountScreen(
          tester,
          user: buildFixtureUser(
            'ko',
            signUpProviderId: 'naver',
            providerIds: kGoldenW5ProviderIds,
            email: kGoldenLongEmail,
          ),
          locale: const Locale('ko'),
          brightness: brightness,
          width: 280,
          isLocalePinned: true,
        );
        expect(
          tester.takeException(),
          isNull,
          reason: 'overflow 0 이어야 golden 이 시각 계약을 대표한다 (E5)',
        );
        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile('goldens/account_171_worst_ko_280_$mode.png'),
        );
      });

      testWidgets('T-171-ACCOUNT-golden-end: 끝 W5 + 긴 이메일 ko 280 — $mode', (
        tester,
      ) async {
        await pumpAccountScreen(
          tester,
          user: buildFixtureUser(
            'ko',
            signUpProviderId: 'naver',
            providerIds: kGoldenW5ProviderIds,
            email: kGoldenLongEmail,
          ),
          locale: const Locale('ko'),
          brightness: brightness,
          width: 280,
          isLocalePinned: true,
        );
        await jumpToEnd(tester);
        expect(
          tester.takeException(),
          isNull,
          reason: 'overflow 0 이어야 golden 이 시각 계약을 대표한다 (E5)',
        );
        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile('goldens/account_171_worst_end_ko_280_$mode.png'),
        );
      });
    }
  });

  group('Phase 17.1 계정 화면 a11y · 3 locale (T-171-ACCOUNT-08 · 09)', () {
    testWidgets('T-171-ACCOUNT-08: labeledTapTarget · textContrast (W5) · '
        'androidTapTarget (해제 버튼 없는 fixture) — ko 280 light', (tester) async {
      // (1) W5 + 긴 이메일 — 위 · 끝 모두 labeled · contrast 통과. tap48 은
      // inline 「{provider} 연결 해제」 버튼(16.8 Q6-A 알려진 예외 · 24×24
      // 충족)이 있어 이 fixture 에서는 단언하지 않는다.
      await pumpAccountScreen(
        tester,
        user: buildFixtureUser(
          'ko',
          signUpProviderId: 'naver',
          providerIds: kGoldenW5ProviderIds,
          email: kGoldenLongEmail,
        ),
        locale: const Locale('ko'),
        brightness: Brightness.light,
        width: 280,
        isLocalePinned: true,
      );
      final handle = tester.ensureSemantics();
      await tester.pump();
      expect(find.bySemanticsLabel('Google 연결 해제'), findsOneWidget);
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      await expectLater(tester, meetsGuideline(textContrastGuideline));
      await jumpToEnd(tester);
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      await expectLater(tester, meetsGuideline(textContrastGuideline));

      // (2) 연결 1 · 자격증명 1 — canUnlinkProvider false(D-03) 라 연결된
      // 계정 값이 일반 텍스트다. 예외 노드가 없으므로 계정 화면 전체(위 ·
      // 끝)에서 tap48 · labeled 가 통과해야 한다. textContrast 는 이
      // fixture 에서 걸지 않는다 — 미연결 provider 의 계정 연결 버튼이
      // 끝에서 보이고, 네이버 · LINE 버튼은 공식 BI 색(흰 라벨 · 브랜드
      // 녹색)을 verbatim 으로 쓰는 브랜드 자산 예외라 WCAG 4.5 미달이다
      // (Phase 13.3 브랜드 버튼 외관 hardcode). 대비는 (1) W5 에서 단언했다.
      await pumpAccountScreen(
        tester,
        user: buildFixtureUser(
          'ko',
          signUpProviderId: 'naver',
          providerIds: const <String>['google.com'],
          email: kGoldenLongEmail,
        ),
        locale: const Locale('ko'),
        brightness: Brightness.light,
        width: 280,
        isLocalePinned: true,
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.bySemanticsLabel(RegExp('연결 해제')), findsNothing);
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      await jumpToEnd(tester);
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      handle.dispose();
    });

    for (final lang in <String>['ko', 'en', 'ja']) {
      testWidgets('T-171-ACCOUNT-09: 넘침 0 W5 + 긴 이메일 — $lang 280', (
        tester,
      ) async {
        await pumpAccountScreen(
          tester,
          user: buildFixtureUser(
            lang,
            signUpProviderId: 'naver',
            providerIds: kGoldenW5ProviderIds,
            email: kGoldenLongEmail,
          ),
          locale: Locale(lang),
          brightness: Brightness.light,
          width: 280,
          isLocalePinned: true,
        );
        expect(tester.takeException(), isNull, reason: 'overflow 위 $lang');
        await jumpToEnd(tester);
        expect(tester.takeException(), isNull, reason: 'overflow 끝 $lang');
      });
    }

    // 미연결 6 — 계정 연결 절이 가장 길게 보이는 상태. 기본 모양이 바뀌어도
    // 같은 단언이 그 모양을 지킨다.
    for (final lang in <String>['ko', 'en', 'ja']) {
      testWidgets('T-171-ACCOUNT-09: 넘침 0 미연결 6 — $lang 280', (tester) async {
        await pumpAccountScreen(
          tester,
          user: buildFixtureUser(
            lang,
            signUpProviderId: 'password',
            providerIds: kAccountLinkingUnlinkedSixProviderIds,
          ),
          locale: Locale(lang),
          brightness: Brightness.light,
          width: 280,
          isLocalePinned: true,
        );
        expect(tester.takeException(), isNull, reason: 'overflow 위 $lang');
        await jumpToEnd(tester);
        expect(tester.takeException(), isNull, reason: 'overflow 끝 $lang');
      });
    }
  });

  group('계정 연결 golden 칸 — 스크롤 위치 · 탭 영역', () {
    final l10n = lookupAppLocalizations(const Locale('ko'));

    /// [provider] 의 ko 스크린 리더 라벨 「{provider} 연결」.
    String resolveLinkLabel(AccountProvider provider) {
      final providerLabel = switch (provider) {
        AccountProvider.google => l10n.authAccountProviderGoogle,
        AccountProvider.apple => l10n.authAccountProviderApple,
        AccountProvider.facebook => l10n.authAccountProviderFacebook,
        AccountProvider.email => l10n.authAccountProviderEmailPassword,
        AccountProvider.kakao => l10n.authAccountProviderKakao,
        AccountProvider.naver => l10n.authAccountProviderNaver,
        AccountProvider.line => l10n.authAccountProviderLine,
      };
      return l10n.settingsLinkProviderCta(providerLabel);
    }

    const socialProviders = <AccountProvider>[
      AccountProvider.google,
      AccountProvider.apple,
      AccountProvider.facebook,
      AccountProvider.kakao,
      AccountProvider.naver,
      AccountProvider.line,
    ];

    for (final (id, unlinked) in <(String, List<AccountProvider>)>[
      ('T-25-CELL-01', socialProviders),
      (
        'T-25-CELL-02',
        <AccountProvider>[
          AccountProvider.google,
          AccountProvider.apple,
          AccountProvider.facebook,
        ],
      ),
    ]) {
      testWidgets('$id: 기본 모양 · 미연결 ${unlinked.length} — 끝까지 스크롤 · '
          '아이콘 모양일 때만 계정 연결 절 전체가 화면에 든다', (tester) async {
        final handle = tester.ensureSemantics();

        await pumpAccountLinkingGoldenCell(
          tester,
          unlinkedCount: unlinked.length,
          brightness: Brightness.light,
        );

        expect(tester.takeException(), isNull);
        final position = tester
            .state<ScrollableState>(find.byType(Scrollable).first)
            .position;
        expect(position.pixels, position.maxScrollExtent, reason: '끝까지 스크롤');
        // golden 칸 조건은 아이콘 모양의 것이다 — 글자 버튼 모양이면 절이 길어
        // 화면 안에 들지 않아도 된다.
        final shape = tester
            .widget<AccountLinkingSection>(find.byType(AccountLinkingSection))
            .shape;
        if (shape == AccountLinkingShape.icon) {
          final section = tester.getRect(find.byType(AccountLinkingSection));
          final appBarBottom = tester.getBottomLeft(find.byType(AppBar)).dy;
          expect(
            section.top,
            greaterThanOrEqualTo(appBarBottom),
            reason: '절 위가 AppBar 아래',
          );
          expect(
            section.bottom,
            lessThanOrEqualTo(kGoldenHeight),
            reason: '절 아래가 화면 안',
          );
        }
        for (final provider in socialProviders) {
          expect(
            find.bySemanticsLabel(resolveLinkLabel(provider)),
            unlinked.contains(provider) ? findsOneWidget : findsNothing,
            reason: '${provider.name} 라벨',
          );
        }
        handle.dispose();
      });
    }

    testWidgets('T-25-CELL-03: 기본 모양 — 아이콘이 보이는 계정 화면이 위 · 끝에서 '
        'androidTapTarget · labeledTapTarget 를 통과한다', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpAccountScreen(
        tester,
        user: buildFixtureUser(
          'ko',
          signUpProviderId: 'naver',
          providerIds: const <String>['google.com'],
          email: kGoldenLongEmail,
        ),
        locale: const Locale('ko'),
        brightness: Brightness.light,
        width: 280,
        isLocalePinned: true,
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      await jumpToEnd(tester);
      expect(
        find.bySemanticsLabel(resolveLinkLabel(AccountProvider.apple)),
        findsOneWidget,
        reason: '아이콘이 보인다',
      );
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      handle.dispose();
    });
  });

  group('Phase 16.8 D-13 — 버튼 크기 · a11y guideline', () {
    testWidgets('해제 버튼 ≥ 24×24 · labeledTapTarget · textContrast — ko 280 W5', (
      tester,
    ) async {
      await pumpAccountScreen(
        tester,
        user: buildFixtureUser(
          'ko',
          signUpProviderId: 'naver',
          providerIds: kGoldenW5ProviderIds,
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

  group('Phase 16.7 계정 화면 연결된 계정 (R1) — 라벨 한 줄 · 줄바꿈 위치 (단언 2 · 3)', () {
    for (final lang in <String>['ko', 'en', 'ja']) {
      for (final worst in <bool>[true, false]) {
        final fixture = worst ? 'worst' : 'd11';

        testWidgets('라벨 한 줄 · 줄바꿈 위치 — $lang $fixture', (tester) async {
          await pumpAccountScreen(
            tester,
            user: buildFixtureUser(
              lang,
              signUpProviderId: worst ? 'line' : null,
            ),
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

  group('Phase 16.7 계정 화면 가입 수단 값 — 1줄 가드 (D-04 개정 (R1) · 단언 10)', () {
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
            await pumpAccountScreen(
              tester,
              user: buildFixtureUser(lang, signUpProviderId: id),
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

  // 계정 연결 golden — ko 280 미연결 6 · 3 × 밝은 · 어두운 4장. 기본
  // 모양(아이콘 줄)을 찍는다 — 등록 함수는 golden harness 에 있다.
  registerAccountLinkingGoldenTests();
}
