import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_starter_kit/core/theme/app_theme.dart';
import 'package:flutter_starter_kit/features/auth/presentation/_widgets/auth_in_progress_overlay.dart';
import 'package:flutter_starter_kit/l10n/generated/app_localizations.dart';

const List<LocalizationsDelegate<dynamic>> _delegates =
    <LocalizationsDelegate<dynamic>>[
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ];

/// Stack 이 화면 전체를 차지하도록 [SizedBox.expand] 로 감싼 호스트 빌더.
/// 실제 [LoginScreen] 에서는 첫 Stack child 가 [AuthScaffold] 라 화면 전체를
/// 차지하므로 동일한 layout invariant 를 모사한다.
Widget _host({required Locale locale, VoidCallback? underlyingTap}) {
  return MaterialApp(
    localizationsDelegates: _delegates,
    supportedLocales: AppLocalizations.supportedLocales,
    locale: locale,
    theme: AppTheme.light(),
    home: Scaffold(
      body: SizedBox.expand(
        child: Stack(
          children: <Widget>[
            ElevatedButton(
              onPressed: underlyingTap ?? () {},
              child: const Text('underlying-button'),
            ),
            const AuthInProgressOverlay(),
          ],
        ),
      ),
    ),
  );
}

void main() {
  group('AuthInProgressOverlay (Phase 11-04 hotfix UX gap)', () {
    testWidgets('Test 1: spinner + en 라벨 동시 표시', (tester) async {
      await tester.pumpWidget(_host(locale: const Locale('en')));
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('Signing you in…'), findsOneWidget);
    });

    testWidgets('Test 2: AbsorbPointer 가 underlying 버튼 탭을 차단한다', (
      tester,
    ) async {
      var underlyingTapped = false;
      await tester.pumpWidget(
        _host(
          locale: const Locale('en'),
          underlyingTap: () => underlyingTapped = true,
        ),
      );
      await tester.pump();

      await tester.tap(find.text('underlying-button'), warnIfMissed: false);
      await tester.pump();

      expect(
        underlyingTapped,
        isFalse,
        reason: 'AbsorbPointer 가 underlying 입력을 흡수해야 한다',
      );
    });

    testWidgets('Test 3: ko 라벨', (tester) async {
      await tester.pumpWidget(_host(locale: const Locale('ko')));
      await tester.pump();

      expect(find.text('로그인 처리 중…'), findsOneWidget);
    });

    testWidgets('Test 4: ja 라벨', (tester) async {
      await tester.pumpWidget(_host(locale: const Locale('ja')));
      await tester.pump();

      expect(find.text('サインイン処理中…'), findsOneWidget);
    });
  });
}
