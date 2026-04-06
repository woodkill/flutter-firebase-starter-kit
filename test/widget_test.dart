import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_starter_kit/core/providers/firebase_providers.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter_starter_kit/app.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('App renders EnvironmentInfoScreen', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          isFirebaseInitializedProvider.overrideWithValue(false),
        ],
        child: const App(),
      ),
    );

    // l10n delegate 로딩 대기
    await tester.pumpAndSettle();

    // 환경 정보 화면의 AppBar 타이틀 확인 (l10n: homeEnvironmentInfo)
    expect(find.text('Environment Info'), findsOneWidget);

    // Flavor 라벨 확인 (기술적 레이블 -- 영어 유지, 스크롤 영역 포함)
    expect(
      find.text('Flavor', skipOffstage: false),
      findsOneWidget,
    );

    // Firebase 미연결 상태 확인 (l10n: homeFirebaseNotConnected, 스크롤 영역 포함)
    expect(
      find.text('Not Connected', skipOffstage: false),
      findsOneWidget,
    );
  });
}
