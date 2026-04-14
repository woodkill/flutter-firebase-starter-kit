import 'package:flutter/material.dart';

import '../../../core/l10n/l10n_extensions.dart';
import '../../../core/theme/theme_extensions.dart';

/// 약관 상세 화면이 표시할 약관 종류 (Phase 10 D-21).
enum TermsType {
  /// 이용약관 (`/terms/service`).
  service,

  /// 개인정보처리방침 (`/terms/privacy`).
  privacy,
}

/// 약관 상세 placeholder 화면 (Phase 10 D-21).
///
/// `/terms/service`, `/terms/privacy` 두 경로에서 [type] 으로 분기한다.
/// Starter Kit 은 placeholder 텍스트만 제공하므로, 프로젝트에서 실제 약관
/// 본문(이용약관, 개인정보처리방침)으로 교체해야 한다. 또는 WebView +
/// 원격 URL 로 교체하는 방안도 검토 가능 (Starter Kit 범위 밖).
class TermsDetailScreen extends StatelessWidget {
  /// [TermsDetailScreen] 을 생성한다.
  const TermsDetailScreen({required this.type, super.key});

  /// 표시할 약관 종류.
  final TermsType type;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final spacing = context.appSpacing;
    final typography = context.appTypography;
    final colorScheme = context.colorScheme;

    final title = type == TermsType.service
        ? l10n.termsDetailServiceTitle
        : l10n.termsDetailPrivacyTitle;

    return Scaffold(
      backgroundColor: colorScheme.surfaceContainerHigh,
      appBar: AppBar(title: Text(title)),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.all(spacing.lg),
          child: Text(
            l10n.termsDetailPlaceholder,
            style: typography.bodyMedium,
          ),
        ),
      ),
    );
  }
}
