// Phase 16 Plan 16-06 본체 채움 — Wave 0 sentinel placeholder.
//
// `WithdrawalConfirmationDialog` 는 탈퇴 확인 AlertDialog + 확인 텍스트
// 입력 필드. Plan 16-06 이 본체 (TextField + 확인 라벨 검증) 를
// add-only 로 확장한다.
import 'package:flutter/material.dart';

/// 탈퇴 확인 다이얼로그 (Phase 16 D-06 / UI-SPEC Surface C).
///
/// **Wave 0 sentinel placeholder** — Plan 16-06 이 본체 채움.
class WithdrawalConfirmationDialog extends StatelessWidget {
  /// [WithdrawalConfirmationDialog] 를 생성한다.
  const WithdrawalConfirmationDialog({super.key});

  /// 다이얼로그를 표시하고 사용자 확인 결과를 반환한다.
  ///
  /// 반환값:
  /// - `true`: 사용자가 확인 (탈퇴 진행)
  /// - `false` / `null`: 사용자가 취소
  static Future<bool?> show(BuildContext context) {
    return showDialog<bool>(
      context: context,
      builder: (_) => const WithdrawalConfirmationDialog(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return const AlertDialog(
      title: Text('Phase 16 Plan 16-06 placeholder'),
    );
  }
}
