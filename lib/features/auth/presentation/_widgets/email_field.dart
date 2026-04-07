import 'package:flutter/material.dart';

import '../../../../core/l10n/l10n_extensions.dart';

/// 이메일 입력 [TextFormField] 래퍼 (D-20, D-24).
///
/// `keyboardType.emailAddress` + `autofillHints.email` + 정규식 검증을
/// 캡슐화한다. validator 는 빈 값에 대해서는 `errorEmailRequired`,
/// 정규식 미스매치에 대해서는 `errorInvalidEmailFormat` ARB 키 텍스트를
/// 반환하여 사용자에게 정확한 안내를 제공한다.
class EmailField extends StatelessWidget {
  /// [EmailField] 를 생성한다.
  const EmailField({
    super.key,
    required this.controller,
    required this.focusNode,
    this.onSubmitted,
    this.textInputAction = TextInputAction.next,
  });

  /// 입력값을 보유할 컨트롤러.
  final TextEditingController controller;

  /// 포커스 체인용 노드.
  final FocusNode focusNode;

  /// 키보드 done/next 액션 시 호출될 콜백.
  final ValueChanged<String>? onSubmitted;

  /// 키보드 액션 타입. 기본값 [TextInputAction.next].
  final TextInputAction textInputAction;

  /// 클라이언트 사이드 이메일 정규식 (D-20). 느슨한 검증.
  static final RegExp _emailRegex =
      RegExp(r'^[\w.+-]+@[\w-]+\.[\w.-]+$');

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return TextFormField(
      controller: controller,
      focusNode: focusNode,
      autofillHints: const [AutofillHints.email],
      keyboardType: TextInputType.emailAddress,
      textInputAction: textInputAction,
      decoration: InputDecoration(
        labelText: l10n.authLoginEmailLabel,
      ),
      validator: (value) {
        final v = (value ?? '').trim();
        if (v.isEmpty) return l10n.errorEmailRequired;
        if (!_emailRegex.hasMatch(v)) {
          return l10n.errorInvalidEmailFormat;
        }
        return null;
      },
      onFieldSubmitted: onSubmitted,
    );
  }
}
