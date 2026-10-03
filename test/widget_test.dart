import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_starter_kit/core/config/splash_config.dart';
import 'package:flutter_starter_kit/core/providers/firebase_providers.dart';
import 'package:flutter_starter_kit/features/home/presentation/home_screen.dart';
import 'package:flutter_starter_kit/features/notifications/presentation/pending_notification_route_listener.dart';
import 'package:flutter_starter_kit/l10n/generated/app_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter_starter_kit/app.dart';

/// Phase 10 Plan 05 이후: GoRouter.initialLocation 이 `/splash` 로 변경되었고
/// SplashScreen 이 최소 대기 후 [context.go] 를 호출하여 resolveAuthRedirect 가 최종
/// 경로를 결정한다. 여기서는 다음 조건이 모두 만족되면 Home 까지 도달함을
/// 검증한다:
/// - Firebase 미초기화 (`isFirebaseInitializedProvider.overrideWithValue(false)`)
///   -> resolveAuthRedirect 가 항상 null 반환 -> Home 랜딩 허용.
/// - SplashInitializer 의 signInAnonymously 는 isFirebaseInitialized=false
///   분기에서 호출되지 않는다 (Phase 1 D-13).
/// - `SplashConfig.overrideMinDuration = Duration(milliseconds: 1)` 로 실대기
///   단축 (WARNING #13 seam).
///
/// Phase 17.1 D-10 — `/` 는 production home([HomeScreen]) 이다. 옛 데모 화면의
/// 빌드 환경 단언(Flavor · Firebase 미연결)은 데모 화면 테스트로 옮겨 간다
/// (plan 08 · D-22).
void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    SplashConfig.overrideMinDuration = const Duration(milliseconds: 1);
  });

  tearDown(() {
    SplashConfig.overrideMinDuration = null;
  });

  testWidgets('T-171-HOME-01: 앱 기동 → / → HomeScreen (제목 · 안내 카드 · 알림 리스너 1)', (
    tester,
  ) async {
    final en = lookupAppLocalizations(const Locale('en'));

    await tester.pumpWidget(
      ProviderScope(
        overrides: [isFirebaseInitializedProvider.overrideWithValue(false)],
        child: const App(),
      ),
    );

    // Splash 최소 대기(1ms) + resolveAuthRedirect -> Home 랜딩 대기.
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pumpAndSettle();

    expect(find.byType(HomeScreen), findsOneWidget);
    // D-12 — AppBar 제목 = appName 미주입(테스트) → ARB appTitle.
    expect(
      find.descendant(
        of: find.byType(AppBar),
        matching: find.text(en.appTitle),
      ),
      findsOneWidget,
    );
    // D-11 — non-release 빌드는 개발자 안내 카드를 보인다.
    expect(find.text(en.homeDevGuideTitle), findsOneWidget);
    // 17 D-04 · Phase 17.1 D-17 — 알림 탭 이동 리스너는 홈 트리에 1개.
    expect(find.byType(PendingNotificationRouteListener), findsOneWidget);
  });
}
