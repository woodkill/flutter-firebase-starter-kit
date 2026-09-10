import 'package:flutter/material.dart';
import 'package:flutter_starter_kit/core/theme/app_theme.dart';
import 'package:flutter_starter_kit/features/auth/presentation/_widgets/email_auth_cta.dart';
import 'package:flutter_starter_kit/l10n/generated/app_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

/// [EmailAuthCta] 를 단독으로 pump 하는 harness.
///
/// 위젯이 provider 를 읽지 않으므로 `ProviderScope` override 는 불필요하다.
Future<void> pumpEmailAuthCta(
  WidgetTester tester, {
  required Locale locale,
  VoidCallback? onPressed,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light(),
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: EmailAuthCta(onPressed: onPressed ?? () {})),
    ),
  );
  await tester.pump();
}

/// 현재 pump 된 [EmailAuthCta] 의 [AppLocalizations] 를 얻는다.
AppLocalizations l10nOf(WidgetTester tester) =>
    AppLocalizations.of(tester.element(find.byType(EmailAuthCta)));

void main() {
  group('EmailAuthCta (Phase 16.1 Surface S)', () {
    testWidgets('Test 1: en 에서 authContinueWithEmail 라벨을 정확히 1개 렌더한다', (
      tester,
    ) async {
      await pumpEmailAuthCta(tester, locale: const Locale('en'));

      // ARB verbatim 기준값과 getter 양쪽을 대조한다 (RESEARCH ARB 표).
      expect(l10nOf(tester).authContinueWithEmail, 'Continue with email');
      expect(find.text('Continue with email'), findsOneWidget);
      expect(
        find.widgetWithText(TextButton, 'Continue with email'),
        findsOneWidget,
      );
    });

    testWidgets('Test 2: 탭 타겟 높이가 48dp 이상이다 (M3 padded 기본값)', (tester) async {
      await pumpEmailAuthCta(tester, locale: const Locale('en'));

      expect(
        tester.getSize(find.byType(EmailAuthCta)).height,
        greaterThanOrEqualTo(48.0),
        reason: 'MaterialTapTargetSize.padded 기본값으로 48dp 터치 영역이 보장되어야 한다',
      );
    });

    testWidgets('Test 3: 탭 1회에 onPressed 가 정확히 1회 호출된다 (라우팅은 호출자 책임)', (
      tester,
    ) async {
      var tapCount = 0;
      await pumpEmailAuthCta(
        tester,
        locale: const Locale('en'),
        onPressed: () => tapCount++,
      );

      await tester.tap(find.byType(EmailAuthCta));
      await tester.pump();

      expect(tapCount, 1);
    });

    testWidgets('Test 4: ko / ja 라벨이 위젯 내부 ARB key 로 결정된다 (외부 주입 없음)', (
      tester,
    ) async {
      await pumpEmailAuthCta(tester, locale: const Locale('ko'));
      expect(l10nOf(tester).authContinueWithEmail, '이메일로 계속');
      expect(find.text('이메일로 계속'), findsOneWidget);

      await pumpEmailAuthCta(tester, locale: const Locale('ja'));
      expect(l10nOf(tester).authContinueWithEmail, 'メールアドレスで続行');
      expect(find.text('メールアドレスで続行'), findsOneWidget);
    });
  });
}
