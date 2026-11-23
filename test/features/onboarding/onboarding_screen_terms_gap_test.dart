// 온보딩 마지막 슬라이드에서 약관 묶음 위 간격이 확인 행 유무에 따라
// 토큰 sm · xl 인지 확인한다.

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_starter_kit/core/theme/app_theme.dart';
import 'package:flutter_starter_kit/core/theme/theme_extensions.dart';
import 'package:flutter_starter_kit/features/onboarding/presentation/_widgets/onboarding_slide.dart';
import 'package:flutter_starter_kit/features/onboarding/presentation/_widgets/terms_checkbox_group.dart';
import 'package:flutter_starter_kit/features/onboarding/presentation/app_terms_confirmation_slot.dart';
import 'package:flutter_starter_kit/features/onboarding/presentation/onboarding_screen.dart';
import 'package:flutter_starter_kit/l10n/generated/app_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

/// 확인 행이 하나인 목록을 돌려준다.
List<AppTermsConfirmation> _buildOneRow(AppTermsConfirmationsInput input) =>
    const <AppTermsConfirmation>[
      AppTermsConfirmation(
        label: 'Test confirmation A',
        missingHint: 'Test confirmation A is required.',
      ),
    ];

/// 확인 행이 없는 빈 목록을 돌려준다.
List<AppTermsConfirmation> _buildNoRows(AppTermsConfirmationsInput input) =>
    const <AppTermsConfirmation>[];

/// 온보딩 화면을 띄우고 마지막 슬라이드로 이동한다.
Future<void> _pumpLastSlide(
  WidgetTester tester,
  AppTermsConfirmationsBuilder builder,
) async {
  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        theme: AppTheme.light(),
        locale: const Locale('en'),
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: OnboardingScreen(termsConfirmationsBuilder: builder),
      ),
    ),
  );
  await tester.pumpAndSettle();
  for (var i = 0; i < 2; i++) {
    await tester.tap(find.widgetWithText(FilledButton, 'Next'));
    await tester.pumpAndSettle();
  }
}

/// 약관 묶음 위쪽과 같은 칸의 슬라이드 본문 아래쪽 사이 간격을 잰다.
double _measureGapAboveTermsGroup(WidgetTester tester) {
  final column = find
      .ancestor(
        of: find.byType(TermsCheckboxGroup),
        matching: find.byType(Column),
      )
      .first;
  final slide = find.descendant(
    of: column,
    matching: find.byType(OnboardingSlide),
  );
  expect(slide, findsOneWidget);
  return tester.getRect(find.byType(TermsCheckboxGroup)).top -
      tester.getRect(slide).bottom;
}

void main() {
  testWidgets('T-33-GAP-01: 확인 행이 있으면 약관 묶음 위 간격이 spacing.sm 이다', (
    tester,
  ) async {
    await _pumpLastSlide(tester, _buildOneRow);

    expect(
      _measureGapAboveTermsGroup(tester),
      tester.element(find.byType(TermsCheckboxGroup)).appSpacing.sm,
    );
  });

  testWidgets('T-33-GAP-02: 확인 행이 없으면 약관 묶음 위 간격이 spacing.xl 이다', (
    tester,
  ) async {
    await _pumpLastSlide(tester, _buildNoRows);

    expect(
      _measureGapAboveTermsGroup(tester),
      tester.element(find.byType(TermsCheckboxGroup)).appSpacing.xl,
    );
  });
}
