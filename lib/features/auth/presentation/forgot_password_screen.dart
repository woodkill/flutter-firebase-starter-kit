import 'package:flutter/material.dart';

/// Forgot Password placeholder 화면.
///
/// Phase 6 Plan 06에서 실제 비밀번호 재설정 UI(폼 + Notifier)로
/// 교체된다. 현재는 라우트 등록 컴파일을 위한 placeholder 이다.
class ForgotPasswordScreen extends StatelessWidget {
  /// Forgot Password placeholder 화면을 생성한다.
  const ForgotPasswordScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: Text('Forgot Password'),
      ),
    );
  }
}
