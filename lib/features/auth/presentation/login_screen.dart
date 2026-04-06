import 'package:flutter/material.dart';

/// Login placeholder 화면.
///
/// Phase 6에서 실제 로그인 UI로 교체된다.
/// 라우팅 동작 검증 목적으로만 사용한다.
class LoginScreen extends StatelessWidget {
  /// Login placeholder 화면을 생성한다.
  const LoginScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: Text('Login'),
      ),
    );
  }
}
