// ignore_for_file: lines_longer_than_80_chars
//
// Phase 16 Plan 16-06 Task 6.2 — SettingsScreen widget test (SS1~SS4).
//
// 검증:
// - SS1 render 정상: AppBar title "Settings" + 계정 section + Danger
//   zone section + 회원탈퇴 ListTile.
// - SS2 Danger zone destructive color: 회원탈퇴 ListTile title color ==
//   Theme.colorScheme.error.
// - SS3 tap → dialog: 회원탈퇴 tap 시 WithdrawalConfirmationDialog 노출.
// - SS4 linkedProviders empty fallback: providerIds==[] 시 graceful "-".

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_starter_kit/core/theme/app_theme.dart';
import 'package:flutter_starter_kit/features/auth/data/auth_repository.dart';
import 'package:flutter_starter_kit/features/auth/domain/user.dart';
import 'package:flutter_starter_kit/features/settings/presentation/_widgets/withdrawal_confirmation_dialog.dart';
import 'package:flutter_starter_kit/features/settings/presentation/settings_screen.dart';
import 'package:flutter_starter_kit/l10n/generated/app_localizations.dart';

/// 테스트용 User factory.
User _testUser({
  List<String> providerIds = const <String>['password'],
  String email = 'me@example.com',
}) {
  return User(
    uid: 'uid-1',
    email: email,
    emailVerified: true,
    createdAt: DateTime.utc(2026, 1, 1),
    providerIds: providerIds,
  );
}

Future<void> _pumpSettingsScreen(
  WidgetTester tester, {
  required User? user,
  Locale locale = const Locale('en'),
}) async {
  // 280dp 이상 (PROJECT.md mobile 반응형) — default 800x600 사용.
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        currentUserProvider.overrideWith((ref) => user),
      ],
      child: MaterialApp(
        theme: AppTheme.light(),
        locale: locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const SettingsScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('Phase 16 D-05~D-08 — SettingsScreen', () {
    testWidgets(
        'SS1 render — AppBar title + 계정 section + Danger zone section 노출',
        (tester) async {
      await _pumpSettingsScreen(tester, user: _testUser());

      // AppBar title (en locale).
      expect(find.text('Settings'), findsOneWidget);
      // 계정 section heading.
      expect(find.text('My Account'), findsOneWidget);
      // 이메일 ListTile (placeholder 채워진 형태).
      expect(find.textContaining('me@example.com'), findsOneWidget);
      // Danger zone section heading.
      expect(find.text('Danger zone'), findsOneWidget);
      // Danger zone explainer.
      expect(find.text('These actions cannot be undone.'), findsOneWidget);
      // 회원탈퇴 ListTile.
      expect(find.text('Delete account'), findsAtLeast(1));
    });

    testWidgets(
        'SS2 Danger zone destructive color — 회원탈퇴 title color == error',
        (tester) async {
      await _pumpSettingsScreen(tester, user: _testUser());

      final dangerTile = tester.widget<ListTile>(
        find.ancestor(
          of: find.text('Delete account').last,
          matching: find.byType(ListTile),
        ),
      );
      final titleText = dangerTile.title! as Text;
      final theme = Theme.of(tester.element(find.byType(SettingsScreen)));
      expect(titleText.style?.color, equals(theme.colorScheme.error));
    });

    testWidgets(
        'SS3 tap → dialog — 회원탈퇴 ListTile tap 시 WithdrawalConfirmationDialog 노출',
        (tester) async {
      await _pumpSettingsScreen(tester, user: _testUser());

      expect(find.byType(WithdrawalConfirmationDialog), findsNothing);

      await tester.tap(find.text('Delete account').last);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byType(WithdrawalConfirmationDialog), findsOneWidget);
    });

    testWidgets(
        'SS4 linkedProviders empty fallback — providerIds==[] graceful',
        (tester) async {
      await _pumpSettingsScreen(
        tester,
        user: _testUser(providerIds: const <String>[]),
      );

      // formatProviderIds([]) → '-' fallback (provider_label_formatter).
      // settingsLinkedProviders('-') 렌더링 결과 (en="Linked sign-in: -").
      expect(find.text('Linked sign-in: -'), findsOneWidget);
    });
  });
}
