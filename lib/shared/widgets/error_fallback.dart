import 'package:flutter/material.dart';
import 'package:gap/gap.dart';

import '../../core/theme/theme_extensions.dart';
import '../../l10n/generated/app_localizations.dart';

/// [ErrorFallback] 이 아이콘만 그리는 영역 크기 기준 (logical px).
///
/// 최대 높이 또는 최대 너비가 이 값보다 작으면 compact(아이콘 띠)로 그린다
/// (UI-SPEC §(E) · E5 overflow — 카드 1장 크기 72 dp 실측).
const double kErrorFallbackCompactExtent = 200;

/// `Localizations` 가 없는 위치에서 쓸 문구 locale 을 [deviceLocale] 로 고른다.
///
/// [AppLocalizations.supportedLocales] 에 언어 코드가 있으면 그 언어를, 없으면
/// `en` 을 돌려준다 — `LocaleNotifier` 의 첫 locale 판정과 같은 규칙이다.
/// [lookupAppLocalizations] 는 미지원 locale 에서 throw 하므로 이 함수를 거친
/// 값만 넘긴다.
Locale resolveErrorFallbackLocale(Locale deviceLocale) {
  final isSupported = AppLocalizations.supportedLocales.any(
    (l) => l.languageCode == deviceLocale.languageCode,
  );
  return isSupported ? Locale(deviceLocale.languageCode) : const Locale('en');
}

/// release 빌드에서 깨진 위젯 자리를 대신하는 안내 화면 (Phase 17 D-22).
///
/// `ErrorWidget.builder` 가 돌려주는 위젯이라 **실패한 위젯의 자리**에 그려진다
/// — 화면 전체가 아닐 수 있다. 그래서 자리가 좁으면(최대 높이 또는 너비가
/// [kErrorFallbackCompactExtent] 미만) 아이콘만 그리고, 넉넉하면 아이콘 · 제목
/// · 본문을 스크롤 영역 안 가운데 정렬로 그린다. 재시도 버튼은 없다 — 위젯
/// 트리를 안전하게 다시 세울 수 없기 때문이다.
///
/// 위젯 트리 위쪽이 실패해 `Localizations` · `Directionality` · 테마가 없는
/// 위치에서도 throw 하지 않는다 (T-17-25):
/// - `Localizations` 부재 → 기기 locale([resolveErrorFallbackLocale])의 문구
/// - `Directionality` 부재 → [TextDirection.ltr] 로 감싼다
/// - 테마 부재 → `Theme.of` 기본 테마 · 토큰 getter 기본값
///
/// 문구는 ARB 2키(`errorWidgetFallbackTitle` · `errorWidgetFallbackBody`)만
/// 쓰고 예외 내용은 그리지 않는다 (T-17-24).
class ErrorFallback extends StatelessWidget {
  /// [ErrorFallback] 을 생성한다.
  const ErrorFallback({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n =
        Localizations.of<AppLocalizations>(context, AppLocalizations) ??
        lookupAppLocalizations(
          // binding 의 dispatcher = production 에서는 PlatformDispatcher.instance
          // 와 같은 객체이고, 테스트에서는 locale 을 주입할 수 있는 dispatcher 다.
          resolveErrorFallbackLocale(
            WidgetsBinding.instance.platformDispatcher.locale,
          ),
        );
    final content = _buildContent(
      context,
      title: l10n.errorWidgetFallbackTitle,
      body: l10n.errorWidgetFallbackBody,
    );
    if (Directionality.maybeOf(context) != null) return content;
    return Directionality(textDirection: TextDirection.ltr, child: content);
  }

  /// 영역 크기에 따라 compact(아이콘 띠) 또는 full(아이콘 · 제목 · 본문)을 그린다.
  Widget _buildContent(
    BuildContext context, {
    required String title,
    required String body,
  }) {
    final spacing = context.appSpacing;
    final typography = context.appTypography;
    final scheme = context.colorScheme;
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact =
            constraints.maxHeight < kErrorFallbackCompactExtent ||
            constraints.maxWidth < kErrorFallbackCompactExtent;
        if (compact) {
          return ColoredBox(
            color: scheme.surfaceContainerHighest,
            child: Center(
              child: Icon(
                Icons.error_outline,
                color: scheme.onSurfaceVariant,
                semanticLabel: '$title. $body',
              ),
            ),
          );
        }
        return ColoredBox(
          color: scheme.surface,
          child: Center(
            child: SingleChildScrollView(
              padding: EdgeInsets.all(spacing.xl),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.error_outline,
                    size: spacing.xxxl,
                    color: scheme.onSurfaceVariant,
                  ),
                  Gap(spacing.lg),
                  Text(
                    title,
                    textAlign: TextAlign.center,
                    style: typography.titleMedium.copyWith(
                      color: scheme.onSurface,
                    ),
                  ),
                  Gap(spacing.sm),
                  Text(
                    body,
                    textAlign: TextAlign.center,
                    style: typography.bodyMedium.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
