// Phase 17 D-03 · D-23 — 설정 「알림」 section (UI-SPEC §(N) 채택 Q3-A).
//
// heading + AsyncValueView(기본 loading · 오류 배너 + 재시도 · SwitchListTile).
// 스위치 값 = OS 알림 권한 ∧ 로컬 opt-in (notifier). 처리 중에는 스위치를
// 비활성화하고 값은 이전 값을 유지한다(낙관적 표시 없음 · 성공 SnackBar 없음).
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/error/app_exception.dart';
import '../../../../core/l10n/l10n_extensions.dart';
import '../../../../core/theme/theme_extensions.dart';
import '../../../../shared/widgets/async_value_view.dart';
import '../../../../shared/widgets/error_snack_bar.dart';
import '../../../notifications/application/notification_settings_notifier.dart';

/// 설정 화면의 「알림」 섹션 (Phase 17 D-03 · UI-SPEC §(N)).
///
/// 「알림 받기」 스위치를 켤 때만 OS 알림 권한을 요청한다 — 홈 · 온보딩 ·
/// 로그인 직후 자동 요청은 없다. 결과 처리:
/// - 켜짐 · 꺼짐 성공: SnackBar 없음 (스위치 상태 자체가 결과).
/// - 권한 거부: `settingsNotificationsPermissionDenied` SnackBar (액션 버튼
///   없음 — 시스템 설정 열기 플러그인을 들이지 않고 문구로 안내).
/// - 실패: `errorNotificationsUpdateFailed` SnackBar · 이전 값 유지.
///
/// 상태 읽기 실패는 섹션 안 오류 배너 + 「재시도」 로 보인다(UI-SPEC E4).
class NotificationsSection extends ConsumerStatefulWidget {
  /// [NotificationsSection] 을 생성한다.
  const NotificationsSection({super.key});

  @override
  ConsumerState<NotificationsSection> createState() =>
      _NotificationsSectionState();
}

class _NotificationsSectionState extends ConsumerState<NotificationsSection> {
  /// 켜기 · 끄기 처리 중이면 true — 스위치를 비활성화한다.
  bool _isBusy = false;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final spacing = context.appSpacing;
    // WR-07: appTypography 가 AppTypography override 를 반영하는 유일한 경로.
    final typography = context.appTypography;
    final scheme = context.colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(
            spacing.lg,
            spacing.sm,
            spacing.lg,
            spacing.xs,
          ),
          child: Text(
            l10n.settingsNotificationsSection,
            style: typography.labelMedium.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        ),
        AsyncValueView<bool>(
          value: ref.watch(notificationSettingsProvider),
          onRetry: _retry,
          // UI-SPEC §(N) — 오류 표시만 좌우 lg 안쪽에 둔다. 배너 · 재시도
          // 버튼 자체는 AsyncValueView 기본값을 그대로 쓴다.
          error: (error, stackTrace) => Padding(
            padding: EdgeInsets.symmetric(horizontal: spacing.lg),
            child: AsyncValueView<bool>(
              value: AsyncError<bool>(error, stackTrace),
              onRetry: _retry,
              data: (_) => const SizedBox.shrink(),
            ),
          ),
          data: (isOn) => SwitchListTile(
            secondary: const Icon(Icons.notifications),
            title: Text(
              l10n.settingsNotificationsToggle,
              style: typography.titleMedium,
            ),
            subtitle: Text(
              l10n.settingsNotificationsToggleSubtitle,
              style: typography.bodyMedium.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
            value: isOn,
            onChanged: _isBusy ? null : _onChanged,
          ),
        ),
      ],
    );
  }

  /// 상태를 다시 읽는다 (오류 배너 「재시도」).
  void _retry() => ref.invalidate(notificationSettingsProvider);

  /// 스위치 탭 — 켜기 · 끄기를 notifier 에 위임하고 결과별 SnackBar 를 띄운다.
  Future<void> _onChanged(bool isTurningOn) async {
    setState(() => _isBusy = true);
    final notifier = ref.read(notificationSettingsProvider.notifier);
    final result = isTurningOn
        ? await notifier.enable()
        : await notifier.disable();
    if (!mounted) return;
    setState(() => _isBusy = false);

    switch (result) {
      case NotificationToggleResult.enabled:
      case NotificationToggleResult.disabled:
        // 성공 SnackBar 없음 — 스위치 상태 자체가 결과다.
        break;
      case NotificationToggleResult.permissionDenied:
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              content: Text(context.l10n.settingsNotificationsPermissionDenied),
            ),
          );
      case NotificationToggleResult.failed:
        showErrorSnackBar(context, const NotificationSettingsUpdateException());
    }
  }
}
