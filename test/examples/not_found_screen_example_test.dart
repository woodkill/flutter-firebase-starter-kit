// 화면 위젯을 시험하는 widget 테스트 예제다.
//
// 앱과 같은 테마 · 다국어 설정으로 화면을 그리고, 화면 문구는 다국어 리소스에서
// 꺼내 위젯을 찾는다. 버튼을 누른 뒤 go_router 가 어느 경로로 이동했는지 확인한다.
// 이 파일을 복사해 내 화면 테스트를 만드는 방법은 `test/README.md` 에 있다.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_starter_kit/core/router/app_routes.dart';
import 'package:flutter_starter_kit/core/theme/app_theme.dart';
import 'package:flutter_starter_kit/features/not_found/presentation/not_found_screen.dart';
import 'package:flutter_starter_kit/l10n/generated/app_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

/// 홈 경로에 놓는 대역 화면의 문구.
const String _homeStubText = 'home';

void main() {
  group('NotFoundScreen 예제', () {
    testWidgets('없는 주소로 들어오면 404 화면이 보이고 「홈으로」 를 누르면 홈으로 간다', (tester) async {
      // 홈 경로 하나와 404 화면(errorBuilder)만 둔 작은 라우터.
      final router = GoRouter(
        initialLocation: '/no-such-page',
        routes: [
          GoRoute(
            path: AppRoutes.home,
            builder: (_, _) => const Scaffold(body: Text(_homeStubText)),
          ),
        ],
        errorBuilder: (_, _) => const NotFoundScreen(),
      );
      addTearDown(router.dispose);

      // ProviderScope 는 pumpWidget 의 직접 인자로 넘긴다.
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp.router(
            routerConfig: router,
            theme: AppTheme.light(),
            locale: const Locale('ko'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
          ),
        ),
      );
      await tester.pumpAndSettle();

      final l10n = lookupAppLocalizations(const Locale('ko'));
      expect(find.text(l10n.errorNotFoundTitle), findsAtLeastNWidgets(1));
      expect(find.text(l10n.errorNotFoundBody), findsOneWidget);

      await tester.tap(
        find.widgetWithText(FilledButton, l10n.errorNotFoundGoHomeCta),
      );
      await tester.pumpAndSettle();

      expect(find.text(_homeStubText), findsOneWidget);
      expect(
        router.routerDelegate.currentConfiguration.uri.path,
        AppRoutes.home,
      );
    });
  });
}
