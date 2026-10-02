// Phase 17 Plan 17-15 — 설정 알림 섹션 (T-17-NOTIF-05 · UI-SPEC (N) · E4).
//
// production [SettingsScreen] 에 「알림」 섹션이 계정 연결 아래 · Danger zone
// 위에 들어가고, 스위치 탭 → 처리 중 비활성 → 결과별 SnackBar 를 보이는지
// 검증한다. notifier 는 결과 · 완료 시점을 쥔 fake 로 바꾼다 — 상태 기계
// 자체는 `notification_settings_notifier_test.dart` 가 맡는다.
//
// 기본 테스트 viewport(800×600)에서는 섹션이 ListView 의 lazy build 범위
// 밖이라 위젯 자체가 없다 — 키 큰 viewport(800×2000)로 올리고, 탭 전에도
// `ensureVisible` 한다.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_starter_kit/core/auth/auth_strategies_registry.dart';
import 'package:flutter_starter_kit/core/error/app_exception.dart';
import 'package:flutter_starter_kit/core/theme/app_spacing.dart';
import 'package:flutter_starter_kit/core/theme/app_theme.dart';
import 'package:flutter_starter_kit/features/auth/data/auth_repository.dart';
import 'package:flutter_starter_kit/features/auth/domain/user.dart';
import 'package:flutter_starter_kit/features/notifications/application/notification_settings_notifier.dart';
import 'package:flutter_starter_kit/features/settings/presentation/_widgets/account_linking_section.dart';
import 'package:flutter_starter_kit/features/settings/presentation/_widgets/danger_zone_section.dart';
import 'package:flutter_starter_kit/features/settings/presentation/_widgets/notifications_section.dart';
import 'package:flutter_starter_kit/features/settings/presentation/settings_screen.dart';
import 'package:flutter_starter_kit/l10n/generated/app_localizations.dart';
import 'package:flutter_starter_kit/shared/widgets/error_banner.dart';
import 'package:flutter_test/flutter_test.dart';

import 'settings_golden_harness.dart';

/// 결과 · 완료 시점을 테스트가 쥐는 [NotificationSettingsNotifier] fake.
///
/// [_initial] 로 build 하고, [enable] · [disable] 은 [_gate] 가 완료될 때까지
/// 기다린 뒤 [_result] 를 돌려준다(성공이면 state 도 바꾼다).
class _FakeNotificationSettings extends NotificationSettingsNotifier {
  _FakeNotificationSettings({
    required Future<bool> Function() initial,
    NotificationToggleResult result = NotificationToggleResult.enabled,
  }) : _initial = initial,
       _result = result;

  final Future<bool> Function() _initial;
  final NotificationToggleResult _result;
  final Completer<void> _gate = Completer<void>();
  int _enableCalls = 0;
  int _disableCalls = 0;

  @override
  Future<bool> build() => _initial();

  @override
  Future<NotificationToggleResult> enable() async {
    _enableCalls++;
    await _gate.future;
    if (_result == NotificationToggleResult.enabled) {
      state = const AsyncData(true);
    }
    return _result;
  }

  @override
  Future<NotificationToggleResult> disable() async {
    _disableCalls++;
    await _gate.future;
    if (_result == NotificationToggleResult.disabled) {
      state = const AsyncData(false);
    }
    return _result;
  }
}

/// 설정 화면 fixture 사용자 — 가입 Google · 보유 Google (합성 값 · PII 0).
final User _user = User(
  uid: 'uid-settings-1',
  email: 'me@example.com',
  emailVerified: true,
  createdAt: DateTime.utc(2026, 9, 26, 12),
  providerIds: const <String>['google.com'],
  signUpProviderId: 'google.com',
);

/// 섹션까지 한 화면에 들어오는 키 큰 viewport (800×2000 · DPR 1).
void _useTallViewport(WidgetTester tester) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(800, 2000);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
}

/// production [SettingsScreen] 을 [notifier] 로 pump 한다.
Future<void> _pumpSettings(
  WidgetTester tester, {
  required _FakeNotificationSettings notifier,
  Locale locale = const Locale('ko'),
}) async {
  _useTallViewport(tester);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        currentUserProvider.overrideWith((ref) => _user),
        activeStrategiesProvider.overrideWith((ref) => kGoldenSixStrategies),
        notificationSettingsProvider.overrideWith(() => notifier),
      ],
      retry: (retryCount, error) => null,
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

/// 알림 스위치 위젯.
SwitchListTile _switch(WidgetTester tester) =>
    tester.widget<SwitchListTile>(find.byType(SwitchListTile));

/// 스위치를 보이게 스크롤한 뒤 탭한다 (처리 중 상태까지 1 frame).
Future<void> _tapSwitch(WidgetTester tester) async {
  await tester.ensureVisible(find.byType(SwitchListTile));
  await tester.pumpAndSettle();
  await tester.tap(find.byType(SwitchListTile));
  await tester.pump();
}

void main() {
  final l10n = lookupAppLocalizations(const Locale('ko'));

  group('Phase 17 알림 토글 (T-17-NOTIF)', () {
    testWidgets('T-17-NOTIF-05: 「알림」 heading · 「알림 받기」 스위치 · 부제가 계정 '
        '연결 아래 · Danger zone 위에 있다', (tester) async {
      await _pumpSettings(
        tester,
        notifier: _FakeNotificationSettings(initial: () async => false),
      );

      final heading = find.text(l10n.settingsNotificationsSection);
      expect(heading, findsOneWidget);
      expect(find.text(l10n.settingsNotificationsToggle), findsOneWidget);
      expect(
        find.text(l10n.settingsNotificationsToggleSubtitle),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byType(NotificationsSection),
          matching: find.byIcon(Icons.notifications),
        ),
        findsOneWidget,
      );
      expect(_switch(tester).value, isFalse);

      final linkingBottom = tester
          .getBottomLeft(find.byType(AccountLinkingSection))
          .dy;
      final sectionTop = tester
          .getTopLeft(find.byType(NotificationsSection))
          .dy;
      final sectionBottom = tester
          .getBottomLeft(find.byType(NotificationsSection))
          .dy;
      final dangerTop = tester.getTopLeft(find.byType(DangerZoneSection)).dy;
      expect(linkingBottom, lessThan(sectionTop));
      expect(sectionBottom, lessThan(dangerTop));
      expect(tester.takeException(), isNull);
    });

    testWidgets('T-17-NOTIF-05: 켜기 탭 → 처리 중 onChanged null · 값은 이전 값 → '
        '완료 뒤 켜짐 · 성공 SnackBar 0', (tester) async {
      final notifier = _FakeNotificationSettings(initial: () async => false);
      await _pumpSettings(tester, notifier: notifier);

      await _tapSwitch(tester);
      expect(notifier._enableCalls, 1);
      expect(_switch(tester).onChanged, isNull);
      expect(_switch(tester).value, isFalse);

      notifier._gate.complete();
      await tester.pumpAndSettle();

      expect(_switch(tester).value, isTrue);
      expect(_switch(tester).onChanged, isNotNull);
      expect(find.byType(SnackBar), findsNothing);
    });

    testWidgets('T-17-NOTIF-05: 켜기 → permissionDenied → 권한 안내 SnackBar '
        '(ko 문구 · action 0) · 꺼짐 유지', (tester) async {
      final notifier = _FakeNotificationSettings(
        initial: () async => false,
        result: NotificationToggleResult.permissionDenied,
      );
      await _pumpSettings(tester, notifier: notifier);

      await _tapSwitch(tester);
      notifier._gate.complete();
      await tester.pumpAndSettle();

      expect(
        find.text(l10n.settingsNotificationsPermissionDenied),
        findsOneWidget,
      );
      expect(find.byType(SnackBarAction), findsNothing);
      expect(_switch(tester).value, isFalse);
      expect(_switch(tester).onChanged, isNotNull);
    });

    testWidgets('T-17-NOTIF-05: 끄기 → failed → errorNotificationsUpdateFailed '
        'SnackBar · 이전 값(켜짐) 유지', (tester) async {
      final notifier = _FakeNotificationSettings(
        initial: () async => true,
        result: NotificationToggleResult.failed,
      );
      await _pumpSettings(tester, notifier: notifier);
      expect(_switch(tester).value, isTrue);

      await _tapSwitch(tester);
      expect(notifier._disableCalls, 1);
      notifier._gate.complete();
      await tester.pumpAndSettle();

      expect(find.text(l10n.errorNotificationsUpdateFailed), findsOneWidget);
      expect(_switch(tester).value, isTrue);
    });

    testWidgets('T-17-NOTIF-05: E4 loading — 첫 값 전에는 heading 아래 스피너 · '
        '스위치 0', (tester) async {
      final pending = Completer<bool>();
      _useTallViewport(tester);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            currentUserProvider.overrideWith((ref) => _user),
            activeStrategiesProvider.overrideWith(
              (ref) => kGoldenSixStrategies,
            ),
            notificationSettingsProvider.overrideWith(
              () => _FakeNotificationSettings(initial: () => pending.future),
            ),
          ],
          child: MaterialApp(
            theme: AppTheme.light(),
            locale: const Locale('ko'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: const SettingsScreen(),
          ),
        ),
      );
      await tester.pump();

      expect(find.text(l10n.settingsNotificationsSection), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(NotificationsSection),
          matching: find.byType(CircularProgressIndicator),
        ),
        findsOneWidget,
      );
      expect(find.byType(SwitchListTile), findsNothing);

      pending.complete(false);
      await tester.pumpAndSettle();
      expect(find.byType(SwitchListTile), findsOneWidget);
    });

    testWidgets('T-17-NOTIF-05: E4 error — 읽기 실패 시 오류 배너'
        '(errorNotificationsUpdateFailed) + 「재시도」 → 다시 읽는다', (tester) async {
      var builds = 0;
      await _pumpSettings(
        tester,
        notifier: _FakeNotificationSettings(
          initial: () async {
            builds++;
            if (builds == 1) throw const NotificationSettingsUpdateException();
            return false;
          },
        ),
      );

      expect(find.byType(ErrorBanner), findsOneWidget);
      expect(find.text(l10n.errorNotificationsUpdateFailed), findsOneWidget);
      expect(find.byType(SwitchListTile), findsNothing);
      // UI-SPEC §(N) — 오류 표시(배너 · 재시도)만 좌우 lg 안쪽 (리뷰 IN-17 —
      // errorPadding 으로 옮겨도 기하가 같다).
      final section = tester.getRect(find.byType(NotificationsSection));
      final banner = tester.getRect(find.byType(ErrorBanner));
      final retryButton = tester.getRect(find.byType(TextButton));
      final lg = const AppSpacing().lg;
      expect(banner.left - section.left, lg);
      expect(section.right - banner.right, lg);
      expect(retryButton.left - section.left, lg);

      final retry = find.text(l10n.commonRetry);
      await tester.ensureVisible(retry);
      await tester.pumpAndSettle();
      await tester.tap(retry);
      await tester.pumpAndSettle();

      expect(builds, 2);
      expect(find.byType(ErrorBanner), findsNothing);
      expect(find.byType(SwitchListTile), findsOneWidget);
    });
  });
}
