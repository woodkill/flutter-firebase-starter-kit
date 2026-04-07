import 'package:flutter/material.dart';

/// Signup placeholder 화면.
///
/// Phase 6 Plan 05에서 실제 가입 UI(폼 + Notifier)로 교체된다.
/// 현재는 라우트 등록 컴파일을 위한 placeholder 이다.
class SignupScreen extends StatelessWidget {
  /// Signup placeholder 화면을 생성한다.
  const SignupScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: Text('Signup'),
      ),
    );
  }
}
