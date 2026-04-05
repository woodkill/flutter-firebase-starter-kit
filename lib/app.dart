import 'package:flutter/material.dart';
import 'package:flutter_starter_kit/features/home/presentation/environment_info_screen.dart';

/// 앱의 루트 위젯.
///
/// [MaterialApp]을 구성하고, 초기 화면으로 [EnvironmentInfoScreen]을 표시한다.
class App extends StatelessWidget {
  /// 앱의 루트 위젯을 생성한다.
  ///
  /// [isFirebaseInitialized]가 `true`이면 Firebase 연결 성공 상태를 표시한다.
  const App({required this.isFirebaseInitialized, super.key});

  /// Firebase 초기화 성공 여부.
  final bool isFirebaseInitialized;

  @override
  Widget build(BuildContext context) {
    const appName = String.fromEnvironment(
      'appName',
      defaultValue: 'StarterKit',
    );

    return MaterialApp(
      title: appName,
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: EnvironmentInfoScreen(
        isFirebaseInitialized: isFirebaseInitialized,
      ),
    );
  }
}
