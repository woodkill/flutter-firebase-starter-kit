import 'package:flutter/material.dart';

import '../../../../core/l10n/l10n_extensions.dart';

/// 비밀번호 입력 [TextFormField] 래퍼 (D-21, D-26).
///
/// visibility toggle suffixIcon + autofillHints(password|newPassword) +
/// 최소 8자 검증을 캡슐화한다. [isNewPassword] 가 true 이면
/// [AutofillHints.newPassword] (가입), false 이면
/// [AutofillHints.password] (로그인) 를 사용한다.
///
/// 보안: [obscureText] true 기본값으로 화면 캡쳐 / 어깨너머 보기를
/// 회피하며, autofillHints 를 명시하여 OS 키체인이 정확한 컨텍스트에
/// 저장하도록 한다 (T-06.03-03 mitigation).
class PasswordField extends StatefulWidget {
  /// [PasswordField] 를 생성한다.
  const PasswordField({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.isNewPassword,
    this.onSubmitted,
    this.textInputAction = TextInputAction.done,
  });

  /// 입력값을 보유할 컨트롤러.
  final TextEditingController controller;

  /// 포커스 체인용 노드.
  final FocusNode focusNode;

  /// 가입(true) / 로그인(false) 구분. autofillHints 에 영향.
  final bool isNewPassword;

  /// 키보드 done 액션 시 호출될 콜백 (제출 트리거).
  final ValueChanged<String>? onSubmitted;

  /// 키보드 액션 타입. 기본값 [TextInputAction.done].
  final TextInputAction textInputAction;

  @override
  State<PasswordField> createState() => _PasswordFieldState();
}

class _PasswordFieldState extends State<PasswordField> {
  bool _obscure = true;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return TextFormField(
      controller: widget.controller,
      focusNode: widget.focusNode,
      autofillHints: <String>[
        widget.isNewPassword
            ? AutofillHints.newPassword
            : AutofillHints.password,
      ],
      obscureText: _obscure,
      textInputAction: widget.textInputAction,
      decoration: InputDecoration(
        labelText: l10n.authLoginPasswordLabel,
        suffixIcon: IconButton(
          tooltip: _obscure ? l10n.authShowPassword : l10n.authHidePassword,
          icon: Icon(_obscure ? Icons.visibility : Icons.visibility_off),
          onPressed: () => setState(() => _obscure = !_obscure),
        ),
      ),
      validator: (value) {
        final v = value ?? '';
        if (v.length < 8) return l10n.errorPasswordTooShort;
        return null;
      },
      onFieldSubmitted: widget.onSubmitted,
    );
  }
}
