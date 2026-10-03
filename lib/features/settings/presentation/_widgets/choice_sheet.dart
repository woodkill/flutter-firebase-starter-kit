// Phase 17.1 D-04 · UI-SPEC (P) Q1-A · Q2-A — 설정 값 선택창 (M3 modal bottom
// sheet · 라디오 목록).
//
// 참조 구현 = mockups/p171_widgets.dart.txt `showMockPicker` sheet 분기 ·
// `PickerOptions` (같은 트리 · 토큰). 바깥 트리는 사진 메뉴 시트
// (profile_photo_sheet.dart)와 같다.
import 'package:flutter/material.dart';
import 'package:gap/gap.dart';

import '../../../../core/theme/theme_extensions.dart';

/// 라디오 선택창을 아래 시트로 연다 (UI-SPEC (P) · Q1-A).
///
/// [options] 는 (값, 라벨) 쌍을 화면 순서대로 받고, [selected] 가 열릴 때의
/// 선택 상태다. 항목을 탭하면 시트를 닫고 고른 값을 돌려준다. 현재값을 다시
/// 탭 · 바깥 탭 · back · 아래로 끌기는 null — 호출부는 null 이면 아무것도
/// 바꾸지 않는다. 확인 버튼 · 「취소」 항목은 없다(라디오 선택 자체가 확정).
Future<T?> showChoiceSheet<T>(
  BuildContext context, {
  required String title,
  required List<(T, String)> options,
  required T selected,
}) {
  return showModalBottomSheet<T>(
    context: context,
    showDragHandle: true,
    builder: (_) =>
        ChoiceSheet<T>(title: title, options: options, selected: selected),
  );
}

/// 선택창 본문 — 제목 + [RadioGroup] › [RadioListTile] 목록.
///
/// 시트 높이 = 내용 높이이고, 가로 모드처럼 높이 상한이 내용보다 낮을 때만
/// 본문이 스크롤된다(사진 메뉴 시트와 같은 `SafeArea › SingleChildScrollView`).
/// 항목 제목은 maxLines 없이 줄을 늘린다(UI-SPEC E4 long-text).
///
/// 현재값 다시 탭 = 닫힘: [RadioListTile.toggleable] 이 true 면 선택된 항목을
/// 다시 탭할 때 SDK 가 [RadioGroup.onChanged] 를 null 로 부르고(Flutter 3.47.5
/// `material/radio_list_tile.dart` `_handleListTileTap`), 그 null 을 그대로
/// `pop` 한다.
class ChoiceSheet<T> extends StatelessWidget {
  /// [ChoiceSheet] 를 생성한다.
  const ChoiceSheet({
    super.key,
    required this.title,
    required this.options,
    required this.selected,
  });

  /// 시트 제목 (행 라벨과 같은 문구).
  final String title;

  /// (값, 라벨) 항목 — 화면 순서.
  final List<(T, String)> options;

  /// 열릴 때 선택된 값.
  final T selected;

  @override
  Widget build(BuildContext context) {
    final spacing = context.appSpacing;
    // WR-07: appTypography 가 AppTypography override 를 반영하는 유일한 경로.
    final typography = context.appTypography;
    final itemPadding = EdgeInsets.symmetric(horizontal: spacing.md);

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
              child: Text(title, style: typography.titleMedium),
            ),
            RadioGroup<T>(
              groupValue: selected,
              // 다른 항목 = 그 값 · 현재값 다시 탭 = null(toggleable) → 닫힘.
              onChanged: (value) => Navigator.of(context).pop(value),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final (value, label) in options)
                    RadioListTile<T>(
                      value: value,
                      toggleable: true,
                      contentPadding: itemPadding,
                      title: Text(label, style: typography.bodyLarge),
                    ),
                ],
              ),
            ),
            Gap(spacing.sm),
          ],
        ),
      ),
    );
  }
}
