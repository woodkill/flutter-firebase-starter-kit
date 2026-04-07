import 'package:flutter/material.dart';

import '../../../../core/theme/theme_extensions.dart';

/// Phase 6 인증 화면(Login/Signup/ForgotPassword) 공통 [Scaffold] 래퍼.
///
/// AppBar(title) + SafeArea + GestureDetector(unfocus) + SingleChildScrollView
/// 패턴을 통일하여 키보드 UX 와 패딩이 일관되게 적용되도록 한다.
/// (06-UI-SPEC.md / Interaction Contract / Keyboard, D-27, D-28)
class AuthScaffold extends StatelessWidget {
  /// [AuthScaffold] 를 생성한다.
  const AuthScaffold({
    super.key,
    required this.title,
    required this.child,
    this.showBackButton = false,
  });

  /// AppBar 에 표시할 화면 타이틀.
  final String title;

  /// 화면 본문. 일반적으로 [Form] + [Column] 트리.
  final Widget child;

  /// AppBar back 버튼 표시 여부. 기본값 false.
  final bool showBackButton;

  @override
  Widget build(BuildContext context) {
    final spacing = context.appSpacing;
    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        automaticallyImplyLeading: showBackButton,
      ),
      body: SafeArea(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
          child: SingleChildScrollView(
            padding: EdgeInsets.all(spacing.lg),
            child: child,
          ),
        ),
      ),
    );
  }
}
