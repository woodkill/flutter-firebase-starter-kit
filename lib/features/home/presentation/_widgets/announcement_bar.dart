import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';

import '../../../../core/l10n/l10n_extensions.dart';
import '../../../../core/providers/locale_provider.dart';
import '../../../../core/remote_config/feature_flag.dart';
import '../../../../core/remote_config/feature_flags_provider.dart';
import '../../../../core/theme/theme_extensions.dart';

/// 홈 AppBar 바로 아래에 고정되는 운영 공지 배너 (Phase 17 D-09 · D-37).
///
/// Remote Config 의 공지 스위치 · 언어별 문구([resolveAnnouncementText])로
/// 표시 여부와 문구가 정해지고, 값이 바뀌면 같은 자리에서 다시 그려진다.
/// 표시할 문구가 없으면 크기 0 위젯이다. 게스트 · 가입자 모두에게 보인다.
///
/// 문구는 일반 텍스트 그대로 표시한다 — 링크 · 마크업으로 해석하지 않고
/// 줄 수도 자르지 않는다(UI-SPEC §(H)). 닫기는 항상 가능하다.
class AnnouncementBar extends ConsumerStatefulWidget {
  /// 공지 배너를 만든다.
  const AnnouncementBar({super.key});

  @override
  ConsumerState<AnnouncementBar> createState() => _AnnouncementBarState();
}

class _AnnouncementBarState extends ConsumerState<AnnouncementBar> {
  /// 이 화면에서 닫은 문구 — 같은 문구는 다시 그리지 않는다.
  String? _dismissedText;

  @override
  Widget build(BuildContext context) {
    final text = resolveAnnouncementText(
      ref.watch(featureFlagsProvider),
      ref.watch(localeProvider),
    );
    if (text == null || text == _dismissedText) return const SizedBox.shrink();
    return _AnnouncementSurface(
      message: text,
      onDismiss: () => setState(() => _dismissedText = text),
    );
  }
}

/// 공지 배너 외관 — UI-SPEC §(H) 트리 (참조 구현 `StickyAnnouncement`).
///
/// full-bleed `secondaryContainer` 바탕 + 하단 hairline 으로 게스트 바와 같은
/// 고정 바 문법을 따른다.
class _AnnouncementSurface extends StatelessWidget {
  const _AnnouncementSurface({required this.message, required this.onDismiss});

  /// 표시할 공지 문구.
  final String message;

  /// 닫기 버튼 콜백.
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final spacing = context.appSpacing;
    final scheme = context.colorScheme;
    final foreground = scheme.onSecondaryContainer;
    return Semantics(
      container: true,
      child: Material(
        color: scheme.secondaryContainer,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: EdgeInsetsDirectional.only(
                start: spacing.lg,
                end: spacing.xs,
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: EdgeInsets.only(top: spacing.md),
                    child: ExcludeSemantics(
                      child: Icon(Icons.campaign_outlined, color: foreground),
                    ),
                  ),
                  Gap(spacing.md),
                  Expanded(
                    child: Padding(
                      padding: EdgeInsets.symmetric(vertical: spacing.md),
                      child: Text(
                        message,
                        semanticsLabel:
                            '${l10n.homeAnnouncementLabel}: $message',
                        style: context.appTypography.bodyMedium.copyWith(
                          color: foreground,
                        ),
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: onDismiss,
                    tooltip: l10n.homeAnnouncementDismiss,
                    icon: const Icon(Icons.close),
                    color: foreground,
                  ),
                ],
              ),
            ),
            Divider(height: 1, thickness: 1, color: scheme.outlineVariant),
          ],
        ),
      ),
    );
  }
}
