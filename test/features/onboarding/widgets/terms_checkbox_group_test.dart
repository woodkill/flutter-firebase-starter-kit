import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:flutter_starter_kit/core/router/app_routes.dart';
import 'package:flutter_starter_kit/core/theme/app_theme.dart';
import 'package:flutter_starter_kit/features/onboarding/presentation/_widgets/terms_checkbox_group.dart';
import 'package:flutter_starter_kit/l10n/generated/app_localizations.dart';

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
      GoRoute(path: '/', builder: (_, _) => Scaffold(body: child)),
      GoRoute(
        path: AppRoutes.termsService,
        name: AppRoutes.termsServiceName,
        builder: (_, _) => const Scaffold(
          body: Text('SERVICE_DETAIL'),
        ),
      ),
      GoRoute(
        path: AppRoutes.termsPrivacy,
        name: AppRoutes.termsPrivacyName,
        builder: (_, _) => const Scaffold(
          body: Text('PRIVACY_DETAIL'),
        ),
      ),
    ],
  );
}

Widget _wrap(_ChangeRecorder recorder) {
  final group = TermsCheckboxGroup(onStateChanged: recorder.call);
  final router = _buildRouter(group);
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
    testWidgets('Test 1: 4개 체크박스(전체 동의 + 이용약관 + 개인정보 + 마케팅) 렌더',
        (tester) async {
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

    testWidgets(
        'Test 3: 이용약관 + 개인정보 + 마케팅 모두 체크 → '
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
    });

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
    });

    testWidgets(
        'Test 6: "상세 보기" TextButton 탭 시 콜백(go_router push)이 '
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
}
