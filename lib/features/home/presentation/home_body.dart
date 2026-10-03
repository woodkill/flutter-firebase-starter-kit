import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import 'package:go_router/go_router.dart';

import '../../../core/l10n/l10n_extensions.dart';
import '../../../core/router/app_routes.dart';
import '../../../core/theme/theme_extensions.dart';

/// 홈 화면 본문 (Phase 17.1 D-10 · D-11).
///
/// **킷 사용자가 바꾸는 유일한 홈 파일이다.** 알림 탭 이동 · 공지 배너 ·
/// 게스트 안내 · 설정 진입은 `home_screen.dart`(배선)가 맡으므로, 이 위젯을
/// 앱의 홈 본문으로 통째로 바꿔도 그 기능들은 그대로 남는다.
///
/// release 빌드에서는 빈 본문이고, 그 밖 빌드(debug · profile)에서는 개발자
/// 안내 카드 1장 — 「데모 화면 열기」 버튼으로 데모 화면 경로
/// ([AppRoutes.developerDemo])에 들어간다(D-15). 데모 화면 위젯은 import 하지
/// 않고 경로 문자열만 쓴다(release tree-shake).
class HomeBody extends StatelessWidget {
  /// 홈 본문을 만든다.
  const HomeBody({this.showsDeveloperGuide = !kReleaseMode, super.key});

  /// release 가 아닌 빌드에서 개발자 안내 카드를 보인다 (D-11).
  ///
  /// 기본값은 const `!kReleaseMode` 이다. 테스트는 `false` 를 넘겨 release
  /// 본문(빈 화면)을 검증한다. 이 파일이 킷 사용자가 바꾸는 유일한 본문이다
  /// (D-10).
  final bool showsDeveloperGuide;

  @override
  Widget build(BuildContext context) {
    // D-11 — release 본문은 비어 있다(킷 사용자가 채울 자리).
    if (!showsDeveloperGuide) return const SizedBox.shrink();
    final spacing = context.appSpacing;
    final typography = context.appTypography;
    final scheme = context.colorScheme;
    final l10n = context.l10n;
    // UI-SPEC §(H) Q7-A — 위쪽 테두리 카드 · 넘치면 스크롤(E1 overflow).
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        spacing.lg,
        spacing.lg,
        spacing.lg,
        spacing.lg + MediaQuery.paddingOf(context).bottom,
      ),
      child: Card.outlined(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: EdgeInsets.all(spacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ExcludeSemantics(
                child: Icon(
                  Icons.developer_mode,
                  color: scheme.onSurfaceVariant,
                ),
              ),
              Gap(spacing.md),
              Text(l10n.homeDevGuideTitle, style: typography.titleMedium),
              Gap(spacing.sm),
              Text(
                l10n.homeDevGuideBody,
                style: typography.bodyMedium.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
              Gap(spacing.lg),
              FilledButton.tonal(
                // D-15 — 데모 화면 진입(경로 문자열만 · 위젯 import 0).
                onPressed: () => context.push(AppRoutes.developerDemo),
                child: Text(l10n.homeDevGuideOpenDemo),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
