// Phase 17 D-15 · D-17 · UI-SPEC (P) — 프로필 사진 메뉴 (M3 modal bottom sheet).
//
// 참조 구현 = mockups/p17_widgets.dart.txt `PhotoSheet` (같은 트리 · 토큰,
// 문구만 ARB). 항목을 고르면 시트를 닫고 고른 동작을 돌려준다 — 실제
// 업로드 · 삭제는 호출부(사진 행)가 시트가 닫힌 뒤 실행한다.
import 'package:flutter/material.dart';
import 'package:gap/gap.dart';

import '../../../../core/l10n/l10n_extensions.dart';
import '../../../../core/theme/theme_extensions.dart';

/// 사진 메뉴에서 고른 동작 (취소 · 바깥 탭 · back = null).
enum ProfilePhotoSheetAction {
  /// 「갤러리에서 사진 선택」.
  pick,

  /// 「올린 사진 삭제」 (직접 올린 사진이 있을 때만).
  remove,
}

/// 프로필 사진 메뉴를 연다 (UI-SPEC (P) · M3 modal bottom sheet).
///
/// 고른 동작을 돌려준다. 「취소」 · 바깥 탭 · back 은 null.
/// [hasCustomPhoto] 가 true 일 때만 「올린 사진 삭제」 항목을 그린다 — 항목
/// 3개(선택 · 삭제 · 취소), 아니면 2개(선택 · 취소) (UI-SPEC E3).
Future<ProfilePhotoSheetAction?> showProfilePhotoSheet(
  BuildContext context, {
  required bool hasCustomPhoto,
}) {
  return showModalBottomSheet<ProfilePhotoSheetAction>(
    context: context,
    showDragHandle: true,
    builder: (_) => ProfilePhotoSheet(hasCustomPhoto: hasCustomPhoto),
  );
}

/// 프로필 사진 메뉴 본문 — 제목 + 항목 [ListTile] + 「취소」.
///
/// 「올린 사진 삭제」 는 기본 색이다(destructive 강조 · 확인 다이얼로그 없음 —
/// 소셜 사진으로 돌아갈 뿐 복구 가능한 동작).
///
/// 시트 높이 상한(화면 높이 9/16 · showModalBottomSheet 기본)은 그대로이고,
/// 가로 모드처럼 상한이 내용보다 낮을 때만 본문이 스크롤된다(Phase 3 D-09 ·
/// quick 261003-0fp · LoginPromptSheet 16.1 과 같은 방식). 세로에서는 시트
/// 높이 = 내용 높이라 모양이 같다.
class ProfilePhotoSheet extends StatelessWidget {
  /// [ProfilePhotoSheet] 를 생성한다.
  const ProfilePhotoSheet({super.key, required this.hasCustomPhoto});

  /// 직접 올린 사진이 있으면 true — 「올린 사진 삭제」 항목을 그린다.
  final bool hasCustomPhoto;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final spacing = context.appSpacing;
    // WR-07: appTypography 가 AppTypography override 를 반영하는 유일한 경로.
    final typography = context.appTypography;
    final scheme = context.colorScheme;
    final itemPadding = EdgeInsets.symmetric(horizontal: spacing.xl);

    return SafeArea(
      // 가로 모드에서 높이 상한이 내용보다 낮을 때만 스크롤 (D-09 · 261003-0fp).
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(
                spacing.xl,
                0,
                spacing.xl,
                spacing.sm,
              ),
              child: Text(
                l10n.authAccountPhotoUrl,
                style: typography.titleMedium,
              ),
            ),
            ListTile(
              contentPadding: itemPadding,
              leading: const Icon(Icons.photo_library_outlined),
              title: Text(
                l10n.settingsProfilePhotoPick,
                style: typography.bodyLarge,
              ),
              onTap: () =>
                  Navigator.of(context).pop(ProfilePhotoSheetAction.pick),
            ),
            if (hasCustomPhoto)
              ListTile(
                contentPadding: itemPadding,
                leading: const Icon(Icons.delete_outline),
                title: Text(
                  l10n.settingsProfilePhotoRemove,
                  style: typography.bodyLarge,
                ),
                onTap: () =>
                    Navigator.of(context).pop(ProfilePhotoSheetAction.remove),
              ),
            ListTile(
              contentPadding: itemPadding,
              leading: Icon(Icons.close, color: scheme.onSurfaceVariant),
              title: Text(l10n.commonCancel, style: typography.bodyLarge),
              onTap: () => Navigator.of(context).pop(),
            ),
            Gap(spacing.sm),
          ],
        ),
      ),
    );
  }
}
