import 'dart:ui' show CheckedState;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_starter_kit/core/router/app_routes.dart';
import 'package:flutter_starter_kit/core/theme/app_theme.dart';
import 'package:flutter_starter_kit/features/onboarding/presentation/_widgets/terms_checkbox_group.dart';
import 'package:flutter_starter_kit/features/onboarding/presentation/app_terms_confirmation_slot.dart';
import 'package:flutter_starter_kit/l10n/generated/app_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../../helpers/keep_hangul_words_finder.dart';
import '../../../helpers/terms_tile_finder.dart';

/// 부모가 3 플래그를 보유하는 테스트 하네스 (WR-16 이후 계약).
///
/// [TermsCheckboxGroup] 은 StatelessWidget 이므로 상태를 갖지 않는다. 실제
/// 소비처(OnboardingScreen) 와 동일하게 부모가 값을 보유하고 콜백으로
/// 갱신하는 구조를 재현해, 체크 반영 + 부모 통지를 함께 검증한다.
class _TermsHarness extends StatefulWidget {
  const _TermsHarness({required this.recorder});

  final _ChangeRecorder recorder;

  @override
  State<_TermsHarness> createState() => _TermsHarnessState();
}

class _TermsHarnessState extends State<_TermsHarness> {
  bool _service = false;
  bool _privacy = false;
  bool _marketing = false;

  void _set({bool? service, bool? privacy, bool? marketing}) {
    setState(() {
      _service = service ?? _service;
      _privacy = privacy ?? _privacy;
      _marketing = marketing ?? _marketing;
    });
    widget.recorder.call(_service, _privacy, _marketing);
  }

  @override
  Widget build(BuildContext context) {
    return TermsCheckboxGroup(
      service: _service,
      privacy: _privacy,
      marketing: _marketing,
      allChecked: _service && _privacy && _marketing,
      onServiceChanged: (v) => _set(service: v ?? false),
      onPrivacyChanged: (v) => _set(privacy: v ?? false),
      onMarketingChanged: (v) => _set(marketing: v ?? false),
      onAllChanged: (v) {
        final next = v ?? false;
        _set(service: next, privacy: next, marketing: next);
      },
    );
  }
}

/// 확인 행 시험의 행 문구.
const _confirmationLabel = 'Test confirmation A';

/// 확인 행 시험의 행 안내.
const _confirmationHint = 'Test confirmation A is required.';

/// 확인 행 시험의 행 목록 — 안내가 있는 행 하나.
const _confirmations = <AppTermsConfirmation>[
  AppTermsConfirmation(
    label: _confirmationLabel,
    missingHint: _confirmationHint,
  ),
];

/// 부모가 확인 행 체크 값을 보유하는 테스트 하네스 (WR-16 이후 계약).
///
/// 안내 표시 여부는 [showConfirmationHints] 로 고정한다 — 체크해도 내리지 않아,
/// 안내가 사라지는 것이 묶음의 판정 덕분인지 본다. 확인 행 콜백 인자는
/// [onConfirmationCalls] 에 차례로 기록한다.
class _ConfirmationHarness extends StatefulWidget {
  const _ConfirmationHarness({
    required this.showConfirmationHints,
    required this.onConfirmationCalls,
  });

  final bool showConfirmationHints;
  final List<(int, bool?)> onConfirmationCalls;

  @override
  State<_ConfirmationHarness> createState() => _ConfirmationHarnessState();
}

class _ConfirmationHarnessState extends State<_ConfirmationHarness> {
  final List<bool> _checks = List<bool>.filled(_confirmations.length, false);

  @override
  Widget build(BuildContext context) {
    return TermsCheckboxGroup(
      service: false,
      privacy: false,
      marketing: false,
      allChecked: false,
      onServiceChanged: (_) {},
      onPrivacyChanged: (_) {},
      onMarketingChanged: (_) {},
      onAllChanged: (_) {},
      confirmations: _confirmations,
      confirmationChecks: List<bool>.of(_checks),
      onConfirmationChanged: (index, value) {
        widget.onConfirmationCalls.add((index, value));
        setState(() => _checks[index] = value ?? false);
      },
      showConfirmationHints: widget.showConfirmationHints,
    );
  }
}

/// 확인 행 하네스를 앱 틀에 넣어 돌려준다.
Widget _wrapConfirmations({
  required bool showConfirmationHints,
  required List<(int, bool?)> onConfirmationCalls,
}) {
  return _wrapInApp(
    _ConfirmationHarness(
      showConfirmationHints: showConfirmationHints,
      onConfirmationCalls: onConfirmationCalls,
    ),
  );
}

/// 문구가 [label] 인 묶음 타일을 찾는다.
Finder _tileOf(String label) => findTermsTileOf(label);

class _ChangeRecorder {
  bool? service;
  bool? privacy;
  bool? marketing;

  /// 체크 변경 통지를 받은 횟수.
  int calls = 0;

  void call(bool s, bool p, bool m) {
    calls++;
    service = s;
    privacy = p;
    marketing = m;
  }
}

/// 화면이 push 된 횟수를 센다.
class _PushCounter extends NavigatorObserver {
  int pushes = 0;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    pushes++;
  }
}

GoRouter _buildRouter(
  Widget child, {
  List<NavigatorObserver> observers = const <NavigatorObserver>[],
}) {
  return GoRouter(
    initialLocation: '/',
    observers: observers,
    routes: [
      GoRoute(
        path: '/',
        builder: (_, _) => Scaffold(body: child),
      ),
      GoRoute(
        path: AppRoutes.termsService,
        name: AppRoutes.termsServiceName,
        builder: (_, _) => const Scaffold(body: Text('SERVICE_DETAIL')),
      ),
      GoRoute(
        path: AppRoutes.termsPrivacy,
        name: AppRoutes.termsPrivacyName,
        builder: (_, _) => const Scaffold(body: Text('PRIVACY_DETAIL')),
      ),
    ],
  );
}

Widget _wrap(_ChangeRecorder recorder) =>
    _wrapInApp(_TermsHarness(recorder: recorder));

/// [child] 를 앱 틀(테마 · 문구 · 라우터)에 넣어 돌려준다.
///
/// [locale] 이 null 이면 기본 언어(en)로 그리고, [observers] 는 라우터의
/// 화면 이동을 지켜본다.
Widget _wrapInApp(
  Widget child, {
  Locale? locale,
  List<NavigatorObserver> observers = const <NavigatorObserver>[],
}) {
  final router = _buildRouter(child, observers: observers);
  return ProviderScope(
    child: MaterialApp.router(
      theme: AppTheme.light(),
      locale: locale,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      routerConfig: router,
    ),
  );
}

void main() {
  group('TermsCheckboxGroup', () {
    testWidgets('Test 1: 4개 체크박스(전체 동의 + 이용약관 + 개인정보 + 마케팅) 렌더', (
      tester,
    ) async {
      final recorder = _ChangeRecorder();
      await tester.pumpWidget(_wrap(recorder));
      await tester.pumpAndSettle();

      // 4개의 행 (전체 동의 + 3개 항목)
      expect(findTermsTiles(), findsNWidgets(4));
    });

    testWidgets('Test 2: "필수" badge 2개, "선택" badge 1개 표시', (tester) async {
      final recorder = _ChangeRecorder();
      await tester.pumpWidget(_wrap(recorder));
      await tester.pumpAndSettle();

      // 영어 ARB: termsRequired = "Required", termsOptional = "Optional"
      expect(find.text('Required'), findsNWidgets(2));
      expect(find.text('Optional'), findsOneWidget);
    });

    testWidgets('Test 3: 이용약관 + 개인정보 + 마케팅 모두 체크 → '
        '(service:true, privacy:true, marketing:true) 통지', (tester) async {
      final recorder = _ChangeRecorder();
      await tester.pumpWidget(_wrap(recorder));
      await tester.pumpAndSettle();

      // index 0=AcceptAll, 1=Service, 2=Privacy, 3=Marketing
      final tiles = findTermsTiles();
      await tester.tap(tiles.at(1));
      await tester.pump();
      await tester.tap(tiles.at(2));
      await tester.pump();
      await tester.tap(tiles.at(3));
      await tester.pump();

      expect(recorder.service, isTrue);
      expect(recorder.privacy, isTrue);
      expect(recorder.marketing, isTrue);
    });

    testWidgets(
      'Test 4: 이용약관만 체크 → (service:true, privacy:false, marketing:false) 통지',
      (tester) async {
        final recorder = _ChangeRecorder();
        await tester.pumpWidget(_wrap(recorder));
        await tester.pumpAndSettle();

        final tiles = findTermsTiles();
        await tester.tap(tiles.at(1));
        await tester.pump();

        expect(recorder.service, isTrue);
        expect(recorder.privacy, isFalse);
        expect(recorder.marketing, isFalse);
      },
    );

    testWidgets('Test 5: "전체 동의" 탭 → 4개 모두 true 로 통지', (tester) async {
      final recorder = _ChangeRecorder();
      await tester.pumpWidget(_wrap(recorder));
      await tester.pumpAndSettle();

      final tiles = findTermsTiles();
      await tester.tap(tiles.at(0)); // accept all
      await tester.pump();

      expect(recorder.service, isTrue);
      expect(recorder.privacy, isTrue);
      expect(recorder.marketing, isTrue);

      // WR-16: 자식이 상태를 갖지 않으므로 표시 값은 부모 값의 함수여야 한다
      // — 렌더된 4 체크박스가 모두 부모 상태를 그대로 반영한다.
      for (var i = 0; i < 4; i++) {
        expect(
          readTermsTileValue(tester, tiles.at(i)),
          isTrue,
          reason: 'index $i 체크박스가 부모 상태와 desync 되면 안 된다',
        );
      }
    });

    testWidgets('Test 6: 제목 링크를 누르면 service/privacy 약관 화면이 각각 열린다', (
      tester,
    ) async {
      final recorder = _ChangeRecorder();
      await tester.pumpWidget(_wrap(recorder));
      await tester.pumpAndSettle();

      final l10n = AppLocalizations.of(
        tester.element(find.byType(TermsCheckboxGroup)),
      );
      await tester.tap(findTermsTitleLink(_tileOf(l10n.termsService)));
      await tester.pumpAndSettle();
      expect(find.text('SERVICE_DETAIL'), findsOneWidget);

      // 뒤로 가서 개인정보처리방침 제목 링크 탭 → privacy 화면
      Navigator.of(tester.element(find.text('SERVICE_DETAIL'))).pop();
      await tester.pumpAndSettle();

      await tester.tap(findTermsTitleLink(_tileOf(l10n.termsPrivacy)));
      await tester.pumpAndSettle();
      expect(find.text('PRIVACY_DETAIL'), findsOneWidget);
    });
  });

  group('TermsCheckboxGroup 필수 확인 행', () {
    testWidgets('T-33-GROUP-01: 타일 순서는 전체 동의 · 이용약관 · 개인정보 · 확인 행 · '
        '마케팅이고, 확인 행에는 [필수] 배지가 있고 제목 링크가 없다', (tester) async {
      await tester.pumpWidget(
        _wrapConfirmations(
          showConfirmationHints: false,
          onConfirmationCalls: <(int, bool?)>[],
        ),
      );
      await tester.pumpAndSettle();

      final l10n = AppLocalizations.of(
        tester.element(find.byType(TermsCheckboxGroup)),
      );
      final order = <String>[
        l10n.termsAcceptAll,
        l10n.termsService,
        l10n.termsPrivacy,
        _confirmationLabel,
        l10n.termsMarketing,
      ];
      expect(findTermsTiles(), findsNWidgets(order.length));
      for (var i = 0; i < order.length; i++) {
        expect(
          tester.widget(findTermsTiles().at(i)),
          same(tester.widget(_tileOf(order[i]))),
          reason: '타일 $i = ${order[i]}',
        );
      }

      final tile = _tileOf(_confirmationLabel);
      expect(
        find.descendant(
          of: tile,
          matching: findKeepHangulWordsText(l10n.termsRequired),
        ),
        findsOneWidget,
      );
      expect(findTermsTitleLink(tile), findsNothing);
      expect(
        _glyphStyleOf(tester, _confirmationLabel).decoration,
        isNot(TextDecoration.underline),
      );
    });

    testWidgets('T-33-GROUP-02: 안내 표시 중 체크하지 않은 확인 행만 오류 색 안내를 그리고, '
        '체크하거나 안내 표시가 꺼지면 그리지 않는다', (tester) async {
      await tester.pumpWidget(
        _wrapConfirmations(
          showConfirmationHints: true,
          onConfirmationCalls: <(int, bool?)>[],
        ),
      );
      await tester.pumpAndSettle();

      final hint = findKeepHangulWordsText(_confirmationHint);
      expect(hint, findsOneWidget);
      // 실제로 칠하는 색은 그려진 글리프(RichText) 의 style 색이다.
      final glyph = tester.widget<RichText>(
        find.descendant(of: hint, matching: find.byType(RichText)),
      );
      final colorScheme = Theme.of(
        tester.element(find.byType(TermsCheckboxGroup)),
      ).colorScheme;
      expect(glyph.text.style?.color, colorScheme.error);

      // 안내 표시는 켠 채로 행을 체크한다 — 안내가 사라져야 한다.
      await tester.tap(_tileOf(_confirmationLabel));
      await tester.pump();
      expect(readTermsTileValue(tester, _tileOf(_confirmationLabel)), isTrue);
      expect(findKeepHangulWordsText(_confirmationHint), findsNothing);

      // 안내 표시가 꺼져 있으면 체크하지 않은 행에도 안내가 없다.
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpWidget(
        _wrapConfirmations(
          showConfirmationHints: false,
          onConfirmationCalls: <(int, bool?)>[],
        ),
      );
      await tester.pumpAndSettle();
      expect(readTermsTileValue(tester, _tileOf(_confirmationLabel)), isFalse);
      expect(findKeepHangulWordsText(_confirmationHint), findsNothing);
    });

    testWidgets('T-33-GROUP-03: 확인 행을 탭하면 부모가 onConfirmationChanged(0, true) 를 '
        '받는다', (tester) async {
      final calls = <(int, bool?)>[];
      await tester.pumpWidget(
        _wrapConfirmations(
          showConfirmationHints: false,
          onConfirmationCalls: calls,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(_tileOf(_confirmationLabel));
      await tester.pump();

      expect(calls, <(int, bool?)>[(0, true)]);
    });

    testWidgets('T-33-GROUP-04: 확인 행은 넘기고 onConfirmationChanged 는 빼면 확인 행 '
        '타일만 꺼지고, 다른 타일은 켜져 있다', (tester) async {
      await tester.pumpWidget(
        _wrapInApp(
          TermsCheckboxGroup(
            service: false,
            privacy: false,
            marketing: false,
            allChecked: false,
            onServiceChanged: (_) {},
            onPrivacyChanged: (_) {},
            onMarketingChanged: (_) {},
            onAllChanged: (_) {},
            confirmations: _confirmations,
            confirmationChecks: List<bool>.filled(_confirmations.length, false),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        readTermsTileOnChanged(tester, _tileOf(_confirmationLabel)),
        isNull,
      );
      final l10n = AppLocalizations.of(
        tester.element(find.byType(TermsCheckboxGroup)),
      );
      expect(
        readTermsTileOnChanged(tester, _tileOf(l10n.termsService)),
        isNotNull,
      );
    });

    testWidgets('T-33-GROUP-05: 확인 행 수와 체크 값 수가 다르면 길이 assert 가 실패한다', (
      tester,
    ) async {
      // 체크 값이 더 길어 RangeError 경로가 없다 — assert 만이 잡는다.
      await tester.pumpWidget(
        _wrapInApp(
          TermsCheckboxGroup(
            service: false,
            privacy: false,
            marketing: false,
            allChecked: false,
            onServiceChanged: (_) {},
            onPrivacyChanged: (_) {},
            onMarketingChanged: (_) {},
            onAllChanged: (_) {},
            confirmations: _confirmations,
            confirmationChecks: const <bool>[false, false],
          ),
        ),
      );
      await tester.pump();

      expect(tester.takeException(), isA<AssertionError>());
    });
  });

  group('약관 제목 링크', () {
    testWidgets('이용약관 · 개인정보처리방침 제목만 강조색 밑줄 링크이고, 확인 행 · 마케팅 '
        '제목은 본문 색 · 밑줄 없음이며, 묶음 안에 글자 버튼이 없다', (tester) async {
      await tester.pumpWidget(
        _wrapConfirmations(
          showConfirmationHints: false,
          onConfirmationCalls: <(int, bool?)>[],
        ),
      );
      await tester.pumpAndSettle();

      final context = tester.element(find.byType(TermsCheckboxGroup));
      final l10n = AppLocalizations.of(context);
      final colorScheme = Theme.of(context).colorScheme;

      for (final label in [l10n.termsService, l10n.termsPrivacy]) {
        expect(findTermsTitleLink(_tileOf(label)), findsOneWidget);
        final style = _glyphStyleOf(tester, label);
        expect(style.color, colorScheme.primary, reason: label);
        expect(style.decoration, TextDecoration.underline, reason: label);
        expect(style.decorationColor, colorScheme.primary, reason: label);
      }
      for (final label in [_confirmationLabel, l10n.termsMarketing]) {
        expect(findTermsTitleLink(_tileOf(label)), findsNothing);
        final style = _glyphStyleOf(tester, label);
        expect(style.color, colorScheme.onSurface, reason: label);
        expect(
          style.decoration,
          isNot(TextDecoration.underline),
          reason: label,
        );
      }
      expect(
        find.descendant(
          of: find.byType(TermsCheckboxGroup),
          matching: find.byWidgetPredicate((w) => w is ButtonStyleButton),
        ),
        findsNothing,
      );
    });

    testWidgets('제목을 누르면 그 약관 화면이 1 번 열리고 체크는 바뀌지 않는다', (tester) async {
      final recorder = _ChangeRecorder();
      final counter = _PushCounter();
      await tester.pumpWidget(
        _wrapInApp(_TermsHarness(recorder: recorder), observers: [counter]),
      );
      await tester.pumpAndSettle();

      final l10n = AppLocalizations.of(
        tester.element(find.byType(TermsCheckboxGroup)),
      );
      for (final (label, page) in [
        (l10n.termsService, 'SERVICE_DETAIL'),
        (l10n.termsPrivacy, 'PRIVACY_DETAIL'),
      ]) {
        final link = findTermsTitleLink(_tileOf(label));
        expect(link, findsOneWidget, reason: label);
        final before = counter.pushes;
        await tester.tap(link);
        await tester.pumpAndSettle();
        expect(counter.pushes - before, 1, reason: label);
        expect(find.text(page), findsOneWidget);
        expect(recorder.calls, 0, reason: '$label 제목 탭은 체크를 바꾸지 않는다');

        Navigator.of(tester.element(find.text(page))).pop();
        await tester.pumpAndSettle();
        expect(readTermsTileValue(tester, _tileOf(label)), isFalse);
      }
    });

    testWidgets('체크박스 · 배지 · 행의 빈 자리를 누르면 체크가 뒤집힌다', (tester) async {
      final recorder = _ChangeRecorder();
      final counter = _PushCounter();
      await tester.pumpWidget(
        _wrapInApp(_TermsHarness(recorder: recorder), observers: [counter]),
      );
      await tester.pumpAndSettle();

      final l10n = AppLocalizations.of(
        tester.element(find.byType(TermsCheckboxGroup)),
      );
      final tile = _tileOf(l10n.termsService);
      expect(findTermsTitleLink(tile), findsOneWidget);
      final pushesBefore = counter.pushes;

      await tester.tap(findTermsTileCheckbox(tile));
      await tester.pump();
      expect(recorder.calls, 1);
      expect(readTermsTileValue(tester, tile), isTrue);

      await tester.tap(
        find.descendant(
          of: tile,
          matching: findKeepHangulWordsText(l10n.termsRequired),
        ),
      );
      await tester.pump();
      expect(recorder.calls, 2);
      expect(readTermsTileValue(tester, tile), isFalse);

      // 행 오른쪽 끝 빈 자리.
      await tester.tapAt(
        tester.getRect(tile).centerRight - const Offset(16, 0),
      );
      await tester.pump();
      expect(recorder.calls, 3);
      expect(readTermsTileValue(tester, tile), isTrue);
      expect(counter.pushes, pushesBefore);
    });

    for (final locale in const [Locale('en'), Locale('ko'), Locale('ja')]) {
      testWidgets('semantics(${locale.languageCode}): 링크는 행과 다른 자기 노드이고 '
          '행 노드는 체크 상태를 맡는다', (tester) async {
        final handle = tester.ensureSemantics();
        final recorder = _ChangeRecorder();
        final counter = _PushCounter();
        await tester.pumpWidget(
          _wrapInApp(
            _TermsHarness(recorder: recorder),
            locale: locale,
            observers: [counter],
          ),
        );
        await tester.pumpAndSettle();

        final l10n = AppLocalizations.of(
          tester.element(find.byType(TermsCheckboxGroup)),
        );
        for (final label in [l10n.termsService, l10n.termsPrivacy]) {
          final tile = _tileOf(label);
          final link = findTermsTitleLink(tile);
          expect(link, findsOneWidget, reason: label);
          final linkNode = tester.getSemantics(link);
          final rowNode = tester.getSemantics(tile);
          expect(linkNode.id, isNot(rowNode.id), reason: label);
          expect(
            linkNode,
            isSemantics(
              label: label,
              hint: l10n.termsViewDetail,
              isLink: true,
              hasTapAction: true,
              isFocusable: true,
            ),
          );
          final linkData = linkNode.getSemanticsData();
          expect(linkData.label.contains('⁠'), isFalse, reason: label);
          expect(linkData.hint.contains('⁠'), isFalse, reason: label);
          expect(
            rowNode,
            isSemantics(
              hasCheckedState: true,
              isChecked: false,
              hasTapAction: true,
              hasEnabledState: true,
              isEnabled: true,
              isButton: false,
            ),
          );
          final rowLabel = rowNode.getSemanticsData().label;
          expect(rowLabel.startsWith(label), isTrue, reason: rowLabel);
          expect(rowLabel.contains(l10n.termsRequired), isTrue);
          expect(_countCheckedStateNodes(rowNode), 1, reason: label);
        }

        // semantics tap — 링크는 약관을 열고, 행은 체크를 뒤집는다.
        final serviceTile = _tileOf(l10n.termsService);
        final pushesBefore = counter.pushes;
        _tapSemanticsNode(
          tester,
          tester.getSemantics(findTermsTitleLink(serviceTile)).id,
        );
        await tester.pumpAndSettle();
        expect(counter.pushes - pushesBefore, 1);
        expect(recorder.calls, 0);
        Navigator.of(tester.element(find.text('SERVICE_DETAIL'))).pop();
        await tester.pumpAndSettle();

        _tapSemanticsNode(
          tester,
          tester.getSemantics(_tileOf(l10n.termsService)).id,
        );
        await tester.pumpAndSettle();
        expect(recorder.calls, 1);
        expect(recorder.service, isTrue);
        expect(
          tester.getSemantics(_tileOf(l10n.termsService)),
          isSemantics(hasCheckedState: true, isChecked: true),
        );
        handle.dispose();
      });
    }

    testWidgets('누르는 영역: 링크 상자는 48×48 이상 · 링크 행은 56 이고, 상자 경계 안쪽은 '
        '약관을 열고 바깥은 체크한다', (tester) async {
      final handle = tester.ensureSemantics();
      final recorder = _ChangeRecorder();
      final counter = _PushCounter();
      // 화면 가장자리에 닿은 노드는 guideline 이 건너뛰므로 떨어뜨려 그린다.
      await tester.pumpWidget(
        _wrapInApp(
          Padding(
            padding: const EdgeInsets.all(24),
            child: _TermsHarness(recorder: recorder),
          ),
          observers: [counter],
        ),
      );
      await tester.pumpAndSettle();

      final l10n = AppLocalizations.of(
        tester.element(find.byType(TermsCheckboxGroup)),
      );
      for (final label in [l10n.termsService, l10n.termsPrivacy]) {
        final tile = _tileOf(label);
        final link = findTermsTitleLink(tile);
        expect(link, findsOneWidget, reason: label);
        expect(tester.getSize(tile).height, 56, reason: label);
        final linkRect = tester.getRect(link);
        expect(linkRect.width, greaterThanOrEqualTo(kMinInteractiveDimension));
        expect(linkRect.height, greaterThanOrEqualTo(kMinInteractiveDimension));
        final nodeRect = tester.getSemantics(link).rect;
        expect(nodeRect.width, greaterThanOrEqualTo(kMinInteractiveDimension));
        expect(nodeRect.height, greaterThanOrEqualTo(kMinInteractiveDimension));
      }

      final tile = _tileOf(l10n.termsService);
      final linkRect = tester.getRect(findTermsTitleLink(tile));
      for (final inside in [
        linkRect.topCenter + const Offset(0, 1),
        linkRect.bottomCenter - const Offset(0, 1),
      ]) {
        final before = counter.pushes;
        await tester.tapAt(inside);
        await tester.pumpAndSettle();
        expect(counter.pushes - before, 1, reason: '$inside');
        expect(recorder.calls, 0, reason: '$inside');
        Navigator.of(tester.element(find.text('SERVICE_DETAIL'))).pop();
        await tester.pumpAndSettle();
      }
      final outside = linkRect.topCenter - const Offset(0, 1);
      expect(tester.getRect(tile).contains(outside), isTrue);
      final before = counter.pushes;
      await tester.tapAt(outside);
      await tester.pumpAndSettle();
      expect(counter.pushes, before);
      expect(recorder.calls, 1);

      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      handle.dispose();
    });

    testWidgets('키보드: 링크에서 Enter 는 약관을 열고, 행에서 Space 는 체크를 뒤집는다', (
      tester,
    ) async {
      final recorder = _ChangeRecorder();
      final counter = _PushCounter();
      await tester.pumpWidget(
        _wrapInApp(_TermsHarness(recorder: recorder), observers: [counter]),
      );
      await tester.pumpAndSettle();

      final l10n = AppLocalizations.of(
        tester.element(find.byType(TermsCheckboxGroup)),
      );
      final tile = _tileOf(l10n.termsService);
      final link = findTermsTitleLink(tile);
      expect(link, findsOneWidget);

      await _moveFocusTo(tester, (focused) => _isInside(focused, link));
      final before = counter.pushes;
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(counter.pushes - before, 1);
      expect(recorder.calls, 0);
      Navigator.of(tester.element(find.text('SERVICE_DETAIL'))).pop();
      await tester.pumpAndSettle();

      await _moveFocusTo(
        tester,
        (focused) =>
            _isInside(focused, _tileOf(l10n.termsService)) &&
            !_isInside(focused, findTermsTitleLink(_tileOf(l10n.termsService))),
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pumpAndSettle();
      expect(recorder.calls, 1);
      expect(recorder.service, isTrue);
      // 체크박스는 초점을 받지 않는다 — 행이 초점을 맡는다.
      expect(
        _isInside(
          FocusManager.instance.primaryFocus?.context,
          findTermsTileCheckbox(_tileOf(l10n.termsService)),
        ),
        isFalse,
      );
    });
  });
}

/// 원문이 [label] 인 문구의 그려진 글리프(RichText) style 을 읽는다.
TextStyle _glyphStyleOf(WidgetTester tester, String label) {
  final glyph = tester.widget<RichText>(
    find
        .descendant(
          of: findKeepHangulWordsText(label),
          matching: find.byType(RichText),
        )
        .first,
  );
  return glyph.text.style!;
}

/// [node] 와 그 아래에서 체크 상태를 가진 semantics 노드 수를 센다.
int _countCheckedStateNodes(SemanticsNode node) {
  final flags = node.getSemanticsData().flagsCollection;
  var count = flags.isChecked == CheckedState.none ? 0 : 1;
  node.visitChildren((child) {
    count += _countCheckedStateNodes(child);
    return true;
  });
  return count;
}

/// [context] 가 [target] 이 찾은 위젯 자신이거나 그 아래에 있는지 본다.
bool _isInside(BuildContext? context, Finder target) {
  if (context == null) {
    return false;
  }
  final targets = target.evaluate().toSet();
  if (targets.contains(context)) {
    return true;
  }
  var isFound = false;
  context.visitAncestorElements((ancestor) {
    isFound = targets.contains(ancestor);
    return !isFound;
  });
  return isFound;
}

/// Tab 을 눌러 초점이 [isTarget] 을 만족하는 곳에 올 때까지 옮긴다.
Future<void> _moveFocusTo(
  WidgetTester tester,
  bool Function(BuildContext? focused) isTarget,
) async {
  for (var i = 0; i < 20; i++) {
    if (isTarget(FocusManager.instance.primaryFocus?.context)) {
      return;
    }
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
  }
  fail('Tab 20 번 안에 초점이 목표에 오지 않았다');
}

/// semantics 노드 [id] 에 스크린 리더의 탭 동작을 보낸다.
void _tapSemanticsNode(WidgetTester tester, int id) {
  tester.semantics.tap(find.semantics.byPredicate((node) => node.id == id));
}
