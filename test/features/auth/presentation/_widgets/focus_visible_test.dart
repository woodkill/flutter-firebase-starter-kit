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
      // 는 자신이 focus 를 받지 않고(CR-01), 자손 InkWell 이 focus 를 받을 때
      // Focus.onFocusChange(hasFocus: true) 로 전달받아 outline 을 그린다.
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

  // ─── T-03-CR-01: wrapper 가 죽은 Tab stop 을 만들지 않는다 ─────────
  //
  // Phase 03 code review CR-01 — 구 구현(`FocusableActionDetector`)은 wrapper
  // 자신이 traversal 정지점(`canRequestFocus: enabled`,
  // `skipTraversal: false`)이 되어 Tab 1회차가 wrapper 노드에 걸렸다.
  // wrapper 에는 `actions` 도 `Actions` 조상도 없어 Enter/Space 가 무시됐고
  // (실측 taps=0), Tab 2회차에서야 InkWell 이 활성화됐다. 아래 가드는
  // "provider 1개당 Tab stop 1개" 와 "Tab 1회 후 Enter 로 onPressed 호출" 을
  // 단언한다.
  group('T-03-CR-01: BrandFocusWrapper 는 traversal 정지점을 추가하지 않는다', () {
    testWidgets(
      'wrapper Focus 노드는 canRequestFocus=false + skipTraversal=true',
      (tester) async {
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

        final Focus wrapperFocus = tester.widget<Focus>(
          find
              .descendant(
                of: find.byType(BrandFocusWrapper),
                matching: find.byType(Focus),
              )
              .first,
        );

        expect(
          wrapperFocus.canRequestFocus,
          isFalse,
          reason:
              'wrapper 가 focus 를 직접 받으면 Enter 가 먹지 않는 죽은 Tab stop '
              '이 된다 (CR-01 회귀).',
        );
        expect(
          wrapperFocus.skipTraversal,
          isTrue,
          reason: 'wrapper 는 traversal 순회 대상에서 제외되어야 한다 (CR-01 회귀).',
        );
        expect(
          wrapperFocus.descendantsAreFocusable,
          isTrue,
          reason: 'isEnabled=true 면 자손(InkWell) focus 진입은 허용되어야 한다.',
        );
      },
    );

    testWidgets('provider 3개 — Tab 1회당 버튼 1개, Tab 직후 Enter 로 onPressed 호출', (
      tester,
    ) async {
      final taps = <String, int>{'google': 0, 'kakao': 0, 'naver': 0};

      await tester.pumpWidget(
        _wrap(
          Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              BrandedSocialButton.google(
                label: 'Sign in with Google',
                onPressed: () => taps['google'] = taps['google']! + 1,
              ),
              BrandedSocialButton.kakao(
                label: 'Login with Kakao',
                onPressed: () => taps['kakao'] = taps['kakao']! + 1,
              ),
              BrandedSocialButton.naver(
                label: 'Log in with NAVER',
                onPressed: () => taps['naver'] = taps['naver']! + 1,
              ),
            ],
          ),
          brightness: Brightness.light,
        ),
      );
      await tester.pumpAndSettle();

      // Tab n회차 → n 번째 버튼의 InkWell 이 primary focus.
      // 죽은 Tab stop 이 있으면 홈수가 2배로 늘어 짝수 회차에서만
      // Enter 가 먹는다.
      for (final provider in <String>['google', 'kakao', 'naver']) {
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pumpAndSettle();
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pumpAndSettle();

        expect(
          taps[provider],
          1,
          reason:
              '$provider — Tab 후 Enter 가 onPressed 를 정확히 1회 호출해야 한다. '
              '0 이면 wrapper 의 죽은 Tab stop 에 focus 가 머무른 것 (CR-01 회귀).',
        );
      }

      expect(
        taps.values.toList(),
        <int>[1, 1, 1],
        reason: 'Tab 3회로 provider 3개 모두 도달 — provider 당 Tab stop 은 1개.',
      );
    });
  });
}
