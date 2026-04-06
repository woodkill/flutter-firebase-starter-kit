import 'package:flutter/material.dart';

/// Splash placeholder 화면.
///
/// Phase 10에서 실제 스플래시 UI로 교체된다.
/// 라우팅 동작 검증 목적으로만 사용한다.
class SplashScreen extends StatelessWidget {
  /// Splash placeholder 화면을 생성한다.
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: Text('Splash'),
      ),
    );
  }
}
