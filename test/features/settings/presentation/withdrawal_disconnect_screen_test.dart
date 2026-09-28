// ignore_for_file: lines_longer_than_80_chars
//
// Phase 16.10 plan 07 — 탈퇴 진행 화면 (WithdrawalDisconnectScreen) widget 테스트.
//
// 스피너가 있는 상태에서는 pumpAndSettle 이 끝나지 않는다 — pump(Duration) 만 쓴다.
//
//   WS1: 카카오 한 줄 계정 — 탈퇴 다이얼로그 확인 → 진행 화면(삭제 0) → 행 완료 → 「탈퇴」 활성 → 삭제 1회

import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:mocktail/mocktail.dart';

import 'package:flutter_starter_kit/core/auth/auth_strategy.dart';
import 'package:flutter_starter_kit/core/auth/provider_id.dart';
import 'package:flutter_starter_kit/core/crashlytics/crashlytics_service.dart';
import 'package:flutter_starter_kit/core/router/app_routes.dart';
import 'package:flutter_starter_kit/core/theme/app_theme.dart';
import 'package:flutter_starter_kit/features/auth/data/auth_repository.dart';
import 'package:flutter_starter_kit/features/auth/data/line_sdk_client.dart';
import 'package:flutter_starter_kit/features/auth/data/naver_sdk_client.dart';
import 'package:flutter_starter_kit/features/auth/domain/user.dart';
import 'package:flutter_starter_kit/features/settings/data/disconnect/disconnect_step.dart';
import 'package:flutter_starter_kit/features/settings/data/disconnect/disconnect_steps.dart';
import 'package:flutter_starter_kit/features/settings/data/settings_repository.dart';
import 'package:flutter_starter_kit/features/settings/presentation/_widgets/withdrawal_confirmation_dialog.dart';
import 'package:flutter_starter_kit/features/settings/presentation/withdrawal_disconnect_screen.dart';
import 'package:flutter_starter_kit/l10n/generated/app_localizations.dart';

class _MockSettingsRepository extends Mock implements SettingsRepository {}

class _MockAuthRepository extends Mock implements AuthRepository {}

class _MockCrashlyticsService extends Mock implements CrashlyticsService {}

class _MockFirebaseAuth extends Mock implements fb.FirebaseAuth {}

class _MockFirebaseFunctions extends Mock implements FirebaseFunctions {}

class _MockGoogleSignIn extends Mock implements GoogleSignIn {}

class _MockLineSdkClient extends Mock implements LineSdkClient {}

class _MockNaverSdkClient extends Mock implements NaverSdkClient {}

/// 결과를 테스트가 제어하는 끊기 step — run 호출마다 Completer 1개.
class _FakeStep extends DisconnectStep {
  _FakeStep(this.provider);

  @override
  final AccountProvider provider;

  @override
  AuthStrategy? get signInStrategy => null;

  /// run 호출 순서대로 쌓인 결과 Completer.
  final List<Completer<DisconnectOutcome>> calls =
      <Completer<DisconnectOutcome>>[];

  @override
  Future<DisconnectOutcome> run(
    DisconnectDeps deps, {
    required bool reloginForFreshness,
  }) {
    final completer = Completer<DisconnectOutcome>();
    calls.add(completer);
    return completer.future;
  }
}

User _userWith(List<String> providerIds) => User(
  uid: 'uid-test',
  emailVerified: true,
  createdAt: DateTime(2026),
  providerIds: providerIds,
);

/// 테스트 viewport 를 넉넉히 키운다 — viewport 밖 탭 miss 방지.
void _useTallView(WidgetTester tester) {
  tester.view.physicalSize = const Size(400, 1400) * 3;
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
}

/// 탈퇴 다이얼로그 진입 root + 진행 화면 route + /login stub 을 띄운다.
Future<void> _pumpWithDialogEntry(
  WidgetTester tester, {
  required List<String> providerIds,
  required List<DisconnectStep> steps,
  required _MockSettingsRepository settingsRepo,
}) async {
  final authRepo = _MockAuthRepository();
  when(() => authRepo.signOutAndResetOnboarding()).thenAnswer((_) async {});
  final deps = DisconnectDeps(
    auth: _MockFirebaseAuth(),
    functions: _MockFirebaseFunctions(),
    googleSignIn: _MockGoogleSignIn(),
    lineSdkClient: _MockLineSdkClient(),
    naverSdkClient: _MockNaverSdkClient(),
    platform: TargetPlatform.android,
  );
  final router = GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(
        path: '/',
        builder: (context, state) => Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () =>
                  unawaited(WithdrawalConfirmationDialog.show(context)),
              child: const Text('open-dialog'),
            ),
          ),
        ),
      ),
      GoRoute(
        path: AppRoutes.withdrawalDisconnect,
        builder: (context, state) => const WithdrawalDisconnectScreen(),
      ),
      GoRoute(
        path: AppRoutes.login,
        builder: (context, state) =>
            const Scaffold(body: Center(child: Text('login-stub'))),
      ),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        currentUserProvider.overrideWith((ref) => _userWith(providerIds)),
        disconnectStepsProvider.overrideWithValue(steps),
        disconnectDepsProvider.overrideWithValue(deps),
        settingsRepositoryProvider.overrideWithValue(settingsRepo),
        authRepositoryProvider.overrideWithValue(authRepo),
        crashlyticsServiceProvider.overrideWithValue(_MockCrashlyticsService()),
      ],
      child: MaterialApp.router(
        locale: const Locale('ko'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: AppTheme.light(),
        routerConfig: router,
      ),
    ),
  );
}

/// 아래 고정 영역의 「탈퇴」 FilledButton.
FilledButton _finalButton(WidgetTester tester) => tester.widget<FilledButton>(
  find.descendant(
    of: find.byType(WithdrawalDisconnectScreen),
    matching: find.byType(FilledButton),
  ),
);

void main() {
  group('Phase 16.10 — WithdrawalDisconnectScreen', () {
    testWidgets(
      'WS1: 카카오 한 줄 계정 — 다이얼로그 확인 → 진행 화면 · 삭제 0 → 행 완료 → 「탈퇴」 → 삭제 1회',
      (tester) async {
        _useTallView(tester);
        final settingsRepo = _MockSettingsRepository();
        when(
          () => settingsRepo.requestAccountDeletion(),
        ).thenAnswer((_) async {});
        final kakao = _FakeStep(AccountProvider.kakao);
        await _pumpWithDialogEntry(
          tester,
          providerIds: <String>['kakao'],
          steps: <DisconnectStep>[kakao],
          settingsRepo: settingsRepo,
        );
        final l10n = await AppLocalizations.delegate.load(const Locale('ko'));

        await tester.tap(find.text('open-dialog'));
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField), '탈퇴');
        await tester.pump();
        await tester.tap(
          find.descendant(
            of: find.byType(WithdrawalConfirmationDialog),
            matching: find.byType(FilledButton),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));

        // 다이얼로그 닫힘 · 진행 화면 표시 · 이 시점 삭제 호출 0.
        expect(find.byType(WithdrawalConfirmationDialog), findsNothing);
        expect(find.byType(WithdrawalDisconnectScreen), findsOneWidget);
        verifyNever(() => settingsRepo.requestAccountDeletion());
        expect(kakao.calls.length, 1);
        expect(
          find.text(l10n.withdrawalDisconnectStatusWorking),
          findsOneWidget,
        );
        expect(_finalButton(tester).onPressed, isNull);

        kakao.calls.last.complete(const DisconnectDone());
        await tester.pumpAndSettle();
        expect(find.text(l10n.withdrawalDisconnectStatusDone), findsOneWidget);
        expect(find.text(l10n.withdrawalDisconnectFinalHint), findsNothing);
        expect(_finalButton(tester).onPressed, isNotNull);

        await tester.tap(
          find.descendant(
            of: find.byType(WithdrawalDisconnectScreen),
            matching: find.byType(FilledButton),
          ),
        );
        await tester.pumpAndSettle();
        verify(() => settingsRepo.requestAccountDeletion()).called(1);
        expect(find.text(l10n.withdrawalSuccess), findsOneWidget);
      },
    );
  });
}
