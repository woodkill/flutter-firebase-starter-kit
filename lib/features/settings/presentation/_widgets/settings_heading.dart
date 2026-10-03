// Phase 17.1 UI-SPEC §(S) DRY — 설정 · 계정 화면 묶음 제목(heading) 공용 위젯.
//
// settings_screen.dart 의 「내 계정」 heading Padding 트리를 그대로 옮겼다.
import 'package:flutter/material.dart';

import '../../../../core/theme/theme_extensions.dart';

/// 설정 · 계정 화면의 묶음 제목 (UI-SPEC Layout Contract · Q3-A).
///
/// `Padding(LTRB lg, sm, lg, xs)` › `labelMedium` · `onSurfaceVariant` — 기존
/// 설정 heading 과 같은 트리 · 토큰이다. semantics 는 일반 텍스트(header 플래그
/// 없음 — 기존 설정 관례).
class SettingsHeading extends StatelessWidget {
  /// [SettingsHeading] 을 생성한다.
  const SettingsHeading({super.key, required this.label});

  /// 묶음 제목 문구.
  final String label;

  @override
  Widget build(BuildContext context) {
    final spacing = context.appSpacing;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        spacing.lg,
        spacing.sm,
        spacing.lg,
        spacing.xs,
      ),
      child: Text(
        label,
        // UI-SPEC Layout Contract verbatim — accent 토큰은 chevron 전용
        // 화이트리스트라 heading 에 쓰지 않는다.
        style: context.appTypography.labelMedium.copyWith(
          color: context.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}
