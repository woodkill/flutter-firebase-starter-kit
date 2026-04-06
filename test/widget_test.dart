import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter_starter_kit/app.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('App renders EnvironmentInfoScreen', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: App(isFirebaseInitialized: false),
      ),
    );

    // 환경 정보 화면의 AppBar 타이틀 확인
    expect(find.text('Environment Info'), findsOneWidget);

    // Flavor 라벨 확인
    expect(find.text('Flavor'), findsOneWidget);

    // Firebase 미연결 상태 확인
    expect(find.text('Not Connected'), findsOneWidget);
  });
}
