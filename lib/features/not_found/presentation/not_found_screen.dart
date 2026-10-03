// Phase 17.1 D-18 — 404 전용 화면 (라우터 파일 안 임시 함수에서 본문 그대로 승격)
import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import 'package:go_router/go_router.dart';

import '../../../core/l10n/l10n_extensions.dart';
import '../../../core/router/app_routes.dart';
import '../../../core/theme/theme_extensions.dart';

/// 404 화면의 안내 아이콘 크기 (IN-01 — 매직 넘버 명명).
///
/// [AppSpacing] 스케일(4px 기반)의 배수가 아닌 독립 illustration 치수이므로
/// spacing 토큰을 재사용하지 않고 전용 상수로 둔다.
const double _notFoundIconSize = 64;

/// 잘못된 경로 진입 시 보이는 명시적 404 화면 — home 으로 조용히 넘기지 않는다(IN-05).
///
/// [GoRouter.errorBuilder] 가 띄우는 root 화면이다. GoRouterState 를 받지
/// 않는다 — 요청 경로 · 쿼리 미표시(PII 0 · 경로 기록은 deferred).
/// 「홈으로」 버튼만이 home 으로 이동하는 경로다.
class NotFoundScreen extends StatelessWidget {
  /// [NotFoundScreen] 을 생성한다.
  const NotFoundScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final spacing = context.appSpacing;
    final colorScheme = context.colorScheme;
    // IN-01: 저장소 dominant 규약인 토큰 접근자를 사용한다. `context.textTheme`
    // 은 AppTypography extension override 를 반영하지 않아, 사용자가 ThemeData
    // 를 교체하면 이 화면만 나머지와 다르게 drift 한다.
    final typography = context.appTypography;
    // 기존 가운데 정렬 트리 — 아래 body 가 높이 부족 시에만 스크롤로 감싼다.
    final content = Center(
      child: Padding(
        padding: EdgeInsets.all(spacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.error_outline,
              size: _notFoundIconSize,
              color: colorScheme.onSurfaceVariant,
            ),
            Gap(spacing.lg),
            Text(
              l10n.errorNotFoundTitle,
              style: typography.titleLarge,
              textAlign: TextAlign.center,
            ),
            Gap(spacing.sm),
            Text(
              l10n.errorNotFoundBody,
              style: typography.bodyMedium.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            Gap(spacing.xl),
            FilledButton.icon(
              onPressed: () => context.go(AppRoutes.home),
              icon: const Icon(Icons.home),
              label: Text(l10n.errorNotFoundGoHomeCta),
            ),
          ],
        ),
      ),
    );
    return Scaffold(
      appBar: AppBar(title: Text(l10n.errorNotFoundTitle)),
      // 맞으면 지금처럼 가운데, 넘치면 스크롤 (Phase 3 D-09 · quick 261003-0fp ·
      // quick 260929-pze 와 같은 bounded 분기).
      body: LayoutBuilder(
        builder: (context, constraints) => SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: content,
          ),
        ),
      ),
    );
  }
}
