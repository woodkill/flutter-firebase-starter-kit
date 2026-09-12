import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_starter_kit/core/config/splash_config.dart';
import 'package:flutter_starter_kit/core/providers/firebase_providers.dart';
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
void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    SplashConfig.overrideMinDuration = const Duration(milliseconds: 1);
  });

  tearDown(() {
    SplashConfig.overrideMinDuration = null;
  });

  testWidgets(
    'App renders SplashScreen -> Home (EnvironmentInfoScreen, Phase 10 D-14)',
    (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [isFirebaseInitializedProvider.overrideWithValue(false)],
          child: const App(),
        ),
      );

      // Splash 최소 대기(1ms) + resolveAuthRedirect -> Home 랜딩 대기.
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pumpAndSettle();

      // 환경 정보 화면의 AppBar 타이틀 확인 (l10n: homeEnvironmentInfo)
      expect(find.text('Environment Info'), findsOneWidget);

      // Flavor 라벨 확인 (기술적 레이블 -- 영어 유지, 스크롤 영역 포함)
      expect(find.text('Flavor', skipOffstage: false), findsOneWidget);

      // Firebase 미연결 상태 확인 (l10n: homeFirebaseNotConnected, 스크롤 영역 포함)
      expect(find.text('Not Connected', skipOffstage: false), findsOneWidget);
    },
  );
}
