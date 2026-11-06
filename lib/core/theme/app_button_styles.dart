import 'package:flutter/material.dart';

/// 되돌리기 어려운 동작(로그아웃 · 탈퇴 · 삭제) 버튼의 [ButtonStyle] 을
/// [ColorScheme] 에서 만든다.
///
/// Material 3 에는 이 버튼의 컴포넌트 테마 자리가 없어 킷이 정한다.
/// 지정한 색만 바꾸고 비활성 · 누름 모양은 각 버튼 기본을 따른다.
///
/// 사용 예:
/// ```dart
/// TextButton(
///   style: context.colorScheme.destructiveTextButtonStyle,
///   onPressed: onConfirm,
///   child: Text(label),
/// );
/// ```
extension AppButtonStyles on ColorScheme {
  /// [TextButton] 용 — 글자가 [ColorScheme.error] 다.
  ButtonStyle get destructiveTextButtonStyle =>
      TextButton.styleFrom(foregroundColor: error);

  /// [FilledButton] 용 — 바탕이 [ColorScheme.error] · 글자가
  /// [ColorScheme.onError] 다.
  ButtonStyle get destructiveFilledButtonStyle =>
      FilledButton.styleFrom(backgroundColor: error, foregroundColor: onError);

  /// [OutlinedButton] 용 — 글자와 누름 강조가 [ColorScheme.error] 다.
  ButtonStyle get destructiveOutlinedButtonStyle =>
      OutlinedButton.styleFrom(foregroundColor: error);
}
