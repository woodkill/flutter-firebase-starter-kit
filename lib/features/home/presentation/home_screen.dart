// Phase 17.1 D-10 — production home 배선. 킷 사용자는 이 파일을 바꾸지 않고 home_body.dart 만 바꾼다.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';
import 'package:go_router/go_router.dart';

import '../../../core/l10n/app_title.dart';
import '../../../core/l10n/l10n_extensions.dart';
import '../../../core/providers/firebase_providers.dart';
import '../../../core/router/app_routes.dart';
import '../../../core/theme/theme_extensions.dart';
import '../../notifications/presentation/pending_notification_route_listener.dart';
import '_widgets/announcement_bar.dart';
import '_widgets/guest_banner.dart';
import 'home_body.dart';

/// production 홈 화면 — 앱이 `/` 에서 띄우는 화면 (Phase 17.1 D-10).
///
/// 킷 사용자가 바꾸지 않는 배선만 담는다: AppBar(앱 제목 · 게스트 「로그인」 ·
/// 설정 아이콘) · 알림 탭 이동 리스너 · 운영 공지 배너 · 게스트 안내 바. 본문은
/// [HomeBody] 하나이며, 앱 홈을 바꿀 때는 `home_body.dart` 만 고친다.
class HomeScreen extends ConsumerWidget {
  /// 홈 화면을 만든다.
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Phase 10 D-13: 익명 사용자는 AppBar 로그인 버튼 + 게스트 배너 표시.
    // loading · error 는 익명 아님으로 취급한다(UI-SPEC E2).
    final currentUser = ref
        .watch(authStateProvider)
        .maybeWhen(data: (user) => user, orElse: () => null);
    final isAnonymous = currentUser?.isAnonymous ?? false;

    final spacing = context.appSpacing;
    final l10n = context.l10n;

    return Scaffold(
      appBar: AppBar(
        // D-12 — App.onGenerateTitle 과 같은 함수.
        title: Text(resolveAppTitle(l10n)),
        actions: [
          if (isAnonymous)
            TextButton(
              onPressed: () => context.push(AppRoutes.login),
              child: Text(
                l10n.homeSignIn,
                style: context.appTypography.labelLarge.copyWith(
                  color: context.colorScheme.primary,
                ),
              ),
            ),
          // Phase 17.1 D-08 — 설정 진입점(게스트 포함).
          IconButton(
            icon: const Icon(Icons.settings),
            tooltip: l10n.settingsTitle,
            onPressed: () => context.push(AppRoutes.settings),
          ),
          Gap(spacing.sm),
        ],
      ),
      body: Column(
        children: [
          // 17 D-04 · Phase 17.1 D-17 — 알림 탭 이동 리스너는 위젯 트리에서 홈 1곳(lib 전체 source guard 테스트가 잠근다).
          const PendingNotificationRouteListener(),
          // Phase 17 D-37 — Remote Config 공지 배너는 AppBar 바로 아래 · 게스트
          // 바 위에 고정된다(게스트 · 가입자 모두). 표시할 문구가 없으면 크기 0.
          const AnnouncementBar(),
          // Phase 10 D-13 — 게스트 배너는 본문 밖 고정 요소다(본문을 끝까지
          // 내려도 AppBar 아래에 남는다).
          if (isAnonymous) const GuestBanner(),
          const Expanded(child: HomeBody()),
        ],
      ),
    );
  }
}
