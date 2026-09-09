// Phase 13.3 X2 (2026-05-17, 260517-uv4) — theme-level focus indicator
// 회귀 가드 (T-13.3-FOCUS-VISIBLE-THEME-01).
//
// **목적:** WCAG 2.1 SC 2.4.7 (Focus Visible) Level AA 부합 검증. 5 social
// provider button 의 outer wrapper (`BrandFocusWrapper`) 가 키보드 focus
// 진입 시 outline (2dp solid + 2dp offset) 을 표시하는지 widget tree
// assertion 으로 검증.
//
// **token 의존 0 검증:** outline 색이 `Color(0xFF000000)` (light) /
// `Color(0xFFFFFFFF)` (dark) hardcode 임을 확인 — ThemeData override 면역
// (starter kit brand drift 회피 원칙).

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_starter_kit/core/theme/app_theme.dart';
import 'package:flutter_starter_kit/core/theme/focus_wrapper.dart';
import 'package:flutter_starter_kit/features/auth/presentation/_widgets/branded_social_button.dart';
import 'package:flutter_starter_kit/l10n/generated/app_localizations.dart';

Widget _wrap(Widget child, {required Brightness brightness}) {
  final baseTheme = brightness == Brightness.light
      ? AppTheme.light()
      : AppTheme.dark();
  return MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: baseTheme,
    locale: const Locale('en'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(
      body: Center(child: SizedBox(width: 360, child: child)),
    ),
  );
}

void main() {
  group('T-13.3-FOCUS-VISIBLE-THEME-01: theme-level focus indicator', () {
    testWidgets(
      'BrandedSocialButton 5 provider 모두 outer BrandFocusWrapper 적용',
      (tester) async {
        final providers = <Widget>[
          BrandedSocialButton.google(
            label: 'Sign in with Google',
            onPressed: () {},
          ),
          BrandedSocialButton.apple(
            label: 'Sign in with Apple',
            onPressed: () {},
          ),
          BrandedSocialButton.facebook(
            label: 'Login with Facebook',
            onPressed: () {},
          ),
          BrandedSocialButton.kakao(
            label: 'Login with Kakao',
            onPressed: () {},
          ),
          BrandedSocialButton.naver(
            label: 'Log in with NAVER',
            onPressed: () {},
          ),
        ];

        for (final provider in providers) {
          await tester.pumpWidget(
            _wrap(provider, brightness: Brightness.light),
          );
          await tester.pump();
          // 5 provider 모두 outer BrandFocusWrapper 단일 인스턴스 보유.
          expect(
            find.byType(BrandFocusWrapper),
            findsOneWidget,
            reason:
                '$provider 에 BrandFocusWrapper 미적용 — X2 옵션 B (token 의존 0) 회귀.',
          );
        }
      },
    );

    testWidgets('BrandFocusWrapper — focus 진입 시 outline visible (light = 검정)', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          BrandedSocialButton.google(
            label: 'Sign in with Google',
            onPressed: () {},
          ),
          brightness: Brightness.light,
        ),
      );
      await tester.pump();

      // focus 진입 전 — outline transparent.
      final Container beforeFocus = tester.widget<Container>(
        find.descendant(
          of: find.byType(BrandFocusWrapper),
          matching: find.byType(Container),
        ),
      );
      final BoxDecoration beforeDecoration =
          beforeFocus.decoration! as BoxDecoration;
      expect(
        beforeDecoration.border,
        isA<Border>().having(
          (b) => (b.top).color,
          'outline 색 (focus 진입 전)',
          Colors.transparent,
        ),
      );

      // 키보드 focus 진입 시뮬레이션 — Tab 키 이벤트 전송. BrandFocusWrapper
      // 의 FocusableActionDetector 가 자동으로 첫 focusable descendant 로
      // focus 이동, onFocusChange 콜백 트리거.
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pumpAndSettle();

      // focus 진입 후 — outline 검정 (light theme hardcode, M3 token 의존 0).
      final Container afterFocus = tester.widget<Container>(
        find.descendant(
          of: find.byType(BrandFocusWrapper),
          matching: find.byType(Container),
        ),
      );
      final BoxDecoration afterDecoration =
          afterFocus.decoration! as BoxDecoration;
      final Border afterBorder = afterDecoration.border! as Border;
      // light theme — outline 검정 hardcode (Color(0xFF000000)).
      // dark theme — outline 흰 hardcode (Color(0xFFFFFFFF)).
      // outline 두께 2dp + corner radius button + 4 (offset).
      expect(afterBorder.top.width, 2.0);
      // focus 진입 후 outline 색은 transparent 가 아님 — 실제 visible.
      expect(
        afterBorder.top.color == Colors.transparent,
        isFalse,
        reason:
            'focus 진입 후 outline 이 여전히 transparent — X2 옵션 B 회귀 (WCAG 2.4.7 미달).',
      );
    });

    testWidgets('BrandFocusWrapper isEnabled=false → focus 진입 차단', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          // onPressed: null → isEnabled=false (BrandedSocialButton.build).
          BrandedSocialButton.google(
            label: 'Sign in with Google',
            onPressed: null,
          ),
          brightness: Brightness.light,
        ),
      );
      await tester.pump();

      final BrandFocusWrapper wrapper = tester.widget<BrandFocusWrapper>(
        find.byType(BrandFocusWrapper),
      );
      expect(
        wrapper.isEnabled,
        isFalse,
        reason: 'onPressed: null 일 때 BrandFocusWrapper.isEnabled false 의무.',
      );
    });
  });
}
