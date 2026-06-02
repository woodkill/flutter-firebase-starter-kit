// ignore_for_file: lines_longer_than_80_chars
//
// Phase 16 Plan 16-06 Task 6.2 — SettingsScreen widget test (SS1~SS4).
// Phase 16 Plan 16-11 Task 2 — AccountLinkingSection 삽입 + 회귀 가드 (SS5~SS8).
//
// 검증:
// - SS1 render 정상: AppBar title "Settings" + 계정 section + Danger
//   zone section + 회원탈퇴 ListTile.
// - SS2 Danger zone destructive color: 회원탈퇴 ListTile title color ==
//   Theme.colorScheme.error.
// - SS3 tap → dialog: 회원탈퇴 tap 시 WithdrawalConfirmationDialog 노출.
// - SS4 linkedProviders empty fallback: providerIds==[] 시 graceful "-".
// - SS5 AccountLinkingSection 노출: settingsAccountLinkingSection heading +
//   AccountLinkingSection 위젯 (계정 section 다음, Danger zone 전).
// - SS6 회귀 0: 계정 section (email + linkedProviders) + Danger zone 모두 노출.
// - SS7 배치 순서: 계정 section → AccountLinkingSection → DangerZoneSection.
// - SS8 viewport: 360dp ListView scroll — Danger zone (말단) ensureVisible.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_starter_kit/core/auth/auth_strategies_registry.dart';
import 'package:flutter_starter_kit/core/auth/auth_strategy.dart';
import 'package:flutter_starter_kit/core/auth/strategies/apple_auth_strategy.dart';
import 'package:flutter_starter_kit/core/auth/strategies/facebook_auth_strategy.dart';
import 'package:flutter_starter_kit/core/auth/strategies/google_auth_strategy.dart';
import 'package:flutter_starter_kit/core/auth/strategies/kakao_auth_strategy.dart';
import 'package:flutter_starter_kit/core/auth/strategies/line_auth_strategy.dart';
import 'package:flutter_starter_kit/core/auth/strategies/naver_auth_strategy.dart';
import 'package:flutter_starter_kit/core/auth/strategies/yahoojp_auth_strategy.dart';
import 'package:flutter_starter_kit/core/theme/app_theme.dart';
import 'package:flutter_starter_kit/features/auth/data/auth_repository.dart';
import 'package:flutter_starter_kit/features/auth/domain/user.dart';
import 'package:flutter_starter_kit/features/settings/presentation/_widgets/account_linking_section.dart';
import 'package:flutter_starter_kit/features/settings/presentation/_widgets/danger_zone_section.dart';
import 'package:flutter_starter_kit/features/settings/presentation/_widgets/withdrawal_confirmation_dialog.dart';
import 'package:flutter_starter_kit/features/settings/presentation/settings_screen.dart';
import 'package:flutter_starter_kit/l10n/generated/app_localizations.dart';

/// 활성 소셜 Strategy 7종 전부.
const List<AuthStrategy> _allStrategies = <AuthStrategy>[
  GoogleAuthStrategy(),
  AppleAuthStrategy(),
  FacebookAuthStrategy(),
  KakaoAuthStrategy(),
  NaverAuthStrategy(),
  LineAuthStrategy(),
  YahoojpAuthStrategy(),
];

/// 모든 활성 소셜 provider 가 이미 linked 인 User (계정 연결 section 미노출
/// 상태) — Danger zone 회귀 검증을 baseline ListView 길이로 유지한다.
List<String> get _allSocialLinked => const <String>[
  'password',
  'google.com',
  'apple.com',
  'facebook.com',
  'kakao',
  'naver',
  'line',
  'yahoojp',
];

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
  List<AuthStrategy> strategies = _allStrategies,
}) async {
  // 280dp 이상 (PROJECT.md mobile 반응형) — default 800x600 사용.
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        currentUserProvider.overrideWith((ref) => user),
        // 활성 Strategy 직접 주입 — AccountLinkingSection available 계산 결정성.
        activeStrategiesProvider.overrideWith((ref, locale) => strategies),
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
      // 소셜 전부 linked → 계정 연결 section 미노출 → baseline ListView 길이.
      await _pumpSettingsScreen(
        tester,
        user: _testUser(providerIds: _allSocialLinked),
      );

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
      await _pumpSettingsScreen(
        tester,
        user: _testUser(providerIds: _allSocialLinked),
      );

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
      await _pumpSettingsScreen(
        tester,
        user: _testUser(providerIds: _allSocialLinked),
      );

      expect(find.byType(WithdrawalConfirmationDialog), findsNothing);

      await tester.ensureVisible(find.text('Delete account').last);
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

    testWidgets(
        'SS5 AccountLinkingSection 노출 — heading + 위젯 (계정 section 다음)',
        (tester) async {
      // linked=[password] (email native) → 소셜 0 linked → 활성 소셜 7 노출.
      await _pumpSettingsScreen(tester, user: _testUser());

      // 계정 연결 section heading (en) + 위젯.
      expect(find.text('Link an account'), findsOneWidget);
      expect(find.byType(AccountLinkingSection), findsOneWidget);
      // 소셜 연결 버튼 (예: Apple) 노출.
      expect(find.text('Link Apple'), findsOneWidget);
    });

    testWidgets(
        'SS6 회귀 0 — 계정 section + Danger zone 모두 노출 (AccountLinkingSection 공존)',
        (tester) async {
      // 단일 활성 Strategy (apple) → section 1 버튼 → ListView baseline 길이
      // 내 Danger zone 공존.
      await _pumpSettingsScreen(
        tester,
        user: _testUser(),
        strategies: const <AuthStrategy>[AppleAuthStrategy()],
      );

      // 계정 section (회귀 0).
      expect(find.text('My Account'), findsOneWidget);
      expect(find.textContaining('me@example.com'), findsOneWidget);
      // 계정 연결 section 공존.
      expect(find.byType(AccountLinkingSection), findsOneWidget);
      expect(find.text('Link Apple'), findsOneWidget);
      // Danger zone (회귀 0).
      expect(find.byType(DangerZoneSection), findsOneWidget);
      expect(find.text('Danger zone'), findsOneWidget);
    });

    testWidgets(
        'SS7 배치 순서 — 계정 section → AccountLinkingSection → DangerZoneSection',
        (tester) async {
      // 단일 활성 Strategy → 3 section 모두 viewport 내 동시 측정 가능.
      await _pumpSettingsScreen(
        tester,
        user: _testUser(),
        strategies: const <AuthStrategy>[AppleAuthStrategy()],
      );

      final accountY = tester.getTopLeft(find.text('My Account')).dy;
      final linkingY = tester.getTopLeft(find.text('Link an account')).dy;
      final dangerY = tester.getTopLeft(find.byType(DangerZoneSection)).dy;

      // 계정 section < 계정 연결 < Danger zone (mockup 배치 verbatim).
      expect(accountY, lessThan(linkingY));
      expect(linkingY, lessThan(dangerY));
    });

    testWidgets(
        'SS8 viewport — 360dp ListView scroll, Danger zone (말단) 접근 가능',
        (tester) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      // 단일 활성 Strategy → Danger zone 이 below-fold 여도 scroll 접근 가능.
      await _pumpSettingsScreen(
        tester,
        user: _testUser(),
        strategies: const <AuthStrategy>[AppleAuthStrategy()],
      );

      // Danger zone 회원탈퇴 ListTile 이 below-fold 여도 scroll 후 접근 가능.
      await tester.ensureVisible(find.text('Delete account').last);
      expect(find.byType(DangerZoneSection), findsOneWidget);
    });

    testWidgets(
        'SS9 모든 소셜 linked — AccountLinkingSection 미노출 (Danger zone 회귀 0)',
        (tester) async {
      await _pumpSettingsScreen(
        tester,
        user: _testUser(
          providerIds: const <String>[
            'password',
            'google.com',
            'apple.com',
            'facebook.com',
            'kakao',
            'naver',
            'line',
            'yahoojp',
          ],
        ),
      );

      // available 빈 set → 계정 연결 heading 미노출.
      expect(find.text('Link an account'), findsNothing);
      // 단, Danger zone 은 계속 노출 (회귀 0).
      expect(find.byType(DangerZoneSection), findsOneWidget);
    });
  });
}
