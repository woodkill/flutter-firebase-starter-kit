import 'package:flutter/material.dart';
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
  final router = _buildRouter(
    _ConfirmationHarness(
      showConfirmationHints: showConfirmationHints,
      onConfirmationCalls: onConfirmationCalls,
    ),
  );
  return ProviderScope(
    child: MaterialApp.router(
      theme: AppTheme.light(),
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

/// 문구가 [label] 인 묶음 타일을 찾는다.
Finder _tileOf(String label) => find.ancestor(
  of: findKeepHangulWordsText(label),
  matching: find.byType(CheckboxListTile),
);

class _ChangeRecorder {
  bool? service;
  bool? privacy;
  bool? marketing;

  void call(bool s, bool p, bool m) {
    service = s;
    privacy = p;
    marketing = m;
  }
}

GoRouter _buildRouter(Widget child) {
  return GoRouter(
    initialLocation: '/',
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

Widget _wrap(_ChangeRecorder recorder) {
  final router = _buildRouter(_TermsHarness(recorder: recorder));
  return ProviderScope(
    child: MaterialApp.router(
      theme: AppTheme.light(),
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

      // 4개의 CheckboxListTile (전체 동의 + 3개 항목)
      expect(find.byType(CheckboxListTile), findsNWidgets(4));
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
      final tiles = find.byType(CheckboxListTile);
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

        final tiles = find.byType(CheckboxListTile);
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

      final tiles = find.byType(CheckboxListTile);
      await tester.tap(tiles.at(0)); // accept all
      await tester.pump();

      expect(recorder.service, isTrue);
      expect(recorder.privacy, isTrue);
      expect(recorder.marketing, isTrue);

      // WR-16: 자식이 상태를 갖지 않으므로 표시 값은 부모 값의 함수여야 한다
      // — 렌더된 4 체크박스가 모두 부모 상태를 그대로 반영한다.
      for (var i = 0; i < 4; i++) {
        expect(
          tester.widget<CheckboxListTile>(tiles.at(i)).value,
          isTrue,
          reason: 'index $i 체크박스가 부모 상태와 desync 되면 안 된다',
        );
      }
    });

    testWidgets('Test 6: "상세 보기" TextButton 탭 시 콜백(go_router push)이 '
        'service/privacy 각각 호출', (tester) async {
      final recorder = _ChangeRecorder();
      await tester.pumpWidget(_wrap(recorder));
      await tester.pumpAndSettle();

      // termsViewDetail = "View" (영어 ARB)
      final viewButtons = find.text('View');
      expect(viewButtons, findsNWidgets(2));

      await tester.tap(viewButtons.first);
      await tester.pumpAndSettle();
      expect(find.text('SERVICE_DETAIL'), findsOneWidget);

      // 뒤로 가서 두 번째 "View" 탭 → privacy 화면
      // Navigator pop
      // ignore: use_build_context_synchronously
      final navContext = tester.element(find.text('SERVICE_DETAIL'));
      Navigator.of(navContext).pop();
      await tester.pumpAndSettle();

      final viewButtons2 = find.text('View');
      await tester.tap(viewButtons2.last);
      await tester.pumpAndSettle();
      expect(find.text('PRIVACY_DETAIL'), findsOneWidget);
    });
  });

  group('TermsCheckboxGroup 필수 확인 행', () {
    testWidgets('T-33-GROUP-01: 타일 순서는 전체 동의 · 이용약관 · 개인정보 · 확인 행 · '
        '마케팅이고, 확인 행에는 [필수] 배지가 있고 「상세 보기」 가 없다', (tester) async {
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
      expect(find.byType(CheckboxListTile), findsNWidgets(order.length));
      for (var i = 0; i < order.length; i++) {
        expect(
          tester.widget(find.byType(CheckboxListTile).at(i)),
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
      expect(
        find.descendant(of: tile, matching: find.byType(TextButton)),
        findsNothing,
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
      expect(
        tester.widget<CheckboxListTile>(_tileOf(_confirmationLabel)).value,
        isTrue,
      );
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
      expect(
        tester.widget<CheckboxListTile>(_tileOf(_confirmationLabel)).value,
        isFalse,
      );
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
  });
}
