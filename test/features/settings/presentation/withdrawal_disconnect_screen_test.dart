// ignore_for_file: lines_longer_than_80_chars
//
// Phase 16.10 plan 07 — 탈퇴 진행 화면 (WithdrawalDisconnectScreen) widget 테스트.
//
// 행 상태는 fake step 결과로 도달시킨다(Completer 제어). 스피너가 있는 상태에서는
// pumpAndSettle 이 끝나지 않는다 — pump(Duration) 만 쓴다. 상호작용 테스트는
// viewport 를 400×1400 으로 키워 화면 밖 탭 miss 를 피한다.
//
//   WS1: 카카오 한 줄 계정 — 탈퇴 다이얼로그 확인 → 진행 화면(삭제 0) → 행 완료 → 「탈퇴」 활성 → 삭제 1회
//   WS2: 행 상태 7종 — 아이콘 · 색 · 상태 문구
//   WS3: 구분선 = 행 수 − 1 (6행 → 5 · 1행 → 0) · outlineVariant · 1.0
//   WS4: 모두 끝난 상태에도 아래 영역 위 선 존재
//   WS5: 현재 재로그인 행만 브랜드 버튼 + 건너뛰기
//   WS6: 서버 행 실패 = 건너뛰기 왼쪽 · 재시도 오른쪽
//   WS7: 건너뛴 행 아래 직접 해제 안내
//   WS8: 미완료 = 안내 + 비활성 → 전부 끝남 = 안내 없음 + 활성(error 배경)
//   WS9: semantics — 행 머리 label · 버튼 button+tap · 「탈퇴」 enabled 플래그 · 표시 순서 = 낭독 순서
//   WS10: 해제 중 · 삭제 중 canPop false · 그 외 true
//   WS11: 5분 창 (b) — 재인증 push(reauth=1) → pop(true) → 카카오 재실행 · 끝나기 전 삭제 증가 0
//   WS12: 일시 오류 · 기타 오류 SnackBar · 화면 유지
//   WS13: 성공 SnackBar
//   WS14: ko/en/ja 280 중간 상태 overflow 0 · 「탈퇴」 viewport 안
//   WS15: 사용자 트리거 진행 중 다른 행 버튼 · 「탈퇴」 비활성
//   WS16: 5분 창 (a) — 「해제됨」 재로그인 행 재개방 · 재인증 push 0
//   WS17: 5분 창 (b) — 재인증 결과 없이 돌아와도 카카오 재실행

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
import 'package:flutter_starter_kit/core/auth/strategies/apple_auth_strategy.dart';
import 'package:flutter_starter_kit/core/auth/strategies/google_auth_strategy.dart';
import 'package:flutter_starter_kit/core/auth/strategies/line_auth_strategy.dart';
import 'package:flutter_starter_kit/core/auth/strategies/naver_auth_strategy.dart';
import 'package:flutter_starter_kit/core/crashlytics/crashlytics_service.dart';
import 'package:flutter_starter_kit/core/error/app_exception.dart';
import 'package:flutter_starter_kit/core/router/app_routes.dart';
import 'package:flutter_starter_kit/core/theme/app_theme.dart';
import 'package:flutter_starter_kit/core/theme/theme_extensions.dart';
import 'package:flutter_starter_kit/features/auth/data/auth_repository.dart';
import 'package:flutter_starter_kit/features/auth/domain/user.dart';
import 'package:flutter_starter_kit/features/auth/presentation/_widgets/social_button.dart';
import 'package:flutter_starter_kit/features/settings/data/disconnect/disconnect_step.dart';
import 'package:flutter_starter_kit/features/settings/data/disconnect/disconnect_steps.dart';
import 'package:flutter_starter_kit/features/settings/data/settings_repository.dart';
import 'package:flutter_starter_kit/features/settings/presentation/_widgets/withdrawal_confirmation_dialog.dart';
import 'package:flutter_starter_kit/features/settings/presentation/withdrawal_disconnect_notifier.dart';
import 'package:flutter_starter_kit/features/settings/presentation/withdrawal_disconnect_screen.dart';
import 'package:flutter_starter_kit/l10n/generated/app_localizations.dart';
import 'package:flutter_starter_kit/shared/auth/provider_label_formatter.dart';

class _MockSettingsRepository extends Mock implements SettingsRepository {}

class _MockAuthRepository extends Mock implements AuthRepository {}

class _MockCrashlyticsService extends Mock implements CrashlyticsService {}

class _MockFirebaseAuth extends Mock implements fb.FirebaseAuth {}

class _MockFirebaseFunctions extends Mock implements FirebaseFunctions {}

class _MockGoogleSignIn extends Mock implements GoogleSignIn {}

/// 결과를 테스트가 제어하는 끊기 step — run 호출마다 Completer 1개.
class _FakeStep extends DisconnectStep {
  _FakeStep(this.provider, {this.signInStrategy});

  @override
  final AccountProvider provider;

  @override
  final AuthStrategy? signInStrategy;

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

/// 레지스트리와 같은 모양의 fake step 6종 — 서버 2 · 재로그인 4.
class _Fakes {
  final _FakeStep kakao = _FakeStep(AccountProvider.kakao);
  final _FakeStep facebook = _FakeStep(AccountProvider.facebook);
  final _FakeStep google = _FakeStep(
    AccountProvider.google,
    signInStrategy: const GoogleAuthStrategy(),
  );
  final _FakeStep apple = _FakeStep(
    AccountProvider.apple,
    signInStrategy: const AppleAuthStrategy(),
  );
  final _FakeStep naver = _FakeStep(
    AccountProvider.naver,
    signInStrategy: const NaverAuthStrategy(),
  );
  final _FakeStep line = _FakeStep(
    AccountProvider.line,
    signInStrategy: const LineAuthStrategy(),
  );

  /// 레지스트리 목록.
  List<DisconnectStep> get all => <DisconnectStep>[
    kakao,
    facebook,
    google,
    apple,
    naver,
    line,
  ];
}

/// 재인증 route stub 방문 기록 (WS11 · WS16 · WS17).
class _LoginVisits {
  /// stub builder 가 받은 location 목록.
  final List<String> locations = <String>[];
}

User _userWith(List<String> providerIds) => User(
  uid: 'uid-test',
  emailVerified: true,
  createdAt: DateTime(2026),
  providerIds: providerIds,
);

/// 16.8 W5 fixture — 가입 naver · 보유 6종.
const List<String> _w5ProviderIds = <String>[
  'google.com',
  'apple.com',
  'facebook.com',
  'kakao',
  'line',
  'naver',
];

DisconnectDeps _deps() => DisconnectDeps(
  auth: _MockFirebaseAuth(),
  functions: _MockFirebaseFunctions(),
  googleSignIn: _MockGoogleSignIn(),
  platform: TargetPlatform.android,
  read: ProviderContainer.test().read,
);

_MockAuthRepository _authRepo() {
  final authRepo = _MockAuthRepository();
  when(() => authRepo.signOutAndResetOnboarding()).thenAnswer((_) async {});
  return authRepo;
}

/// 테스트 viewport 를 [size] 논리 크기 · DPR 3 으로 둔다.
void _useView(WidgetTester tester, {Size size = const Size(400, 1400)}) {
  tester.view.physicalSize = size * 3;
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
}

/// 탈퇴 다이얼로그 진입 root + 진행 화면 route + /login stub 을 띄운다 (WS1).
Future<void> _pumpWithDialogEntry(
  WidgetTester tester, {
  required List<String> providerIds,
  required List<DisconnectStep> steps,
  required _MockSettingsRepository settingsRepo,
}) async {
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
        disconnectDepsProvider.overrideWithValue(_deps()),
        settingsRepositoryProvider.overrideWithValue(settingsRepo),
        authRepositoryProvider.overrideWithValue(_authRepo()),
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

/// 진행 화면을 root 로 띄우고 첫 프레임 뒤 start 를 반영한다.
///
/// /login stub 은 [visits] 에 location 을 기록하고 「reauth-ok」(pop(true)) ·
/// 「reauth-back」(결과 없는 pop) 버튼을 둔다.
Future<void> _pumpScreen(
  WidgetTester tester, {
  required List<String> providerIds,
  required _Fakes fakes,
  required _MockSettingsRepository settingsRepo,
  _LoginVisits? visits,
  Locale locale = const Locale('ko'),
}) async {
  final router = GoRouter(
    initialLocation: AppRoutes.withdrawalDisconnect,
    routes: [
      GoRoute(
        path: AppRoutes.withdrawalDisconnect,
        builder: (context, state) => const WithdrawalDisconnectScreen(),
      ),
      GoRoute(
        path: AppRoutes.login,
        builder: (context, state) {
          visits?.locations.add(state.uri.toString());
          return Scaffold(
            body: Column(
              children: [
                TextButton(
                  onPressed: () => context.pop(true),
                  child: const Text('reauth-ok'),
                ),
                TextButton(
                  onPressed: () => context.pop(),
                  child: const Text('reauth-back'),
                ),
              ],
            ),
          );
        },
      ),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        currentUserProvider.overrideWith((ref) => _userWith(providerIds)),
        disconnectStepsProvider.overrideWithValue(fakes.all),
        disconnectDepsProvider.overrideWithValue(_deps()),
        settingsRepositoryProvider.overrideWithValue(settingsRepo),
        authRepositoryProvider.overrideWithValue(_authRepo()),
        crashlyticsServiceProvider.overrideWithValue(_MockCrashlyticsService()),
      ],
      child: MaterialApp.router(
        locale: locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: AppTheme.light(),
        routerConfig: router,
      ),
    ),
  );
  // 첫 프레임 뒤 start() → 행 스냅샷 반영.
  await tester.pump();
}

/// 삭제 호출 수를 세는 settings repository — [answers] 를 순서대로 적용한다.
///
/// 원소가 null 이면 성공, [Object] 면 그 값을 던진다. 목록을 넘으면 성공.
({_MockSettingsRepository repo, List<int> count}) _countingRepo([
  List<Object?> answers = const <Object?>[],
]) {
  final repo = _MockSettingsRepository();
  final count = <int>[0];
  when(() => repo.requestAccountDeletion()).thenAnswer((_) async {
    final index = count[0];
    count[0] = index + 1;
    final answer = index < answers.length ? answers[index] : null;
    if (answer != null) throw answer;
  });
  return (repo: repo, count: count);
}

/// 진행 화면의 notifier (fixture 도달용).
WithdrawalDisconnect _notifierOf(WidgetTester tester) =>
    ProviderScope.containerOf(
      tester.element(find.byType(WithdrawalDisconnectScreen)),
    ).read(withdrawalDisconnectProvider.notifier);

Finder _row(AccountProvider provider) =>
    find.byKey(ValueKey<AccountProvider>(provider));

Finder _inRow(AccountProvider provider, Finder matching) =>
    find.descendant(of: _row(provider), matching: matching);

Finder _finalButtonFinder() => find.descendant(
  of: find.byType(WithdrawalDisconnectScreen),
  matching: find.byType(FilledButton),
);

FilledButton _finalButton(WidgetTester tester) =>
    tester.widget<FilledButton>(_finalButtonFinder());

String _label(AppLocalizations l10n, String providerId) =>
    formatProviderLabels(<String>[providerId], l10n).single;

ColorScheme _schemeOf(WidgetTester tester) =>
    tester.element(find.byType(WithdrawalDisconnectScreen)).colorScheme;

/// 진행 화면 [PopScope] 의 canPop.
bool _canPop(WidgetTester tester) => tester
    .widget<PopScope<Object?>>(
      find
          .descendant(
            of: find.byType(WithdrawalDisconnectScreen),
            matching: find.byWidgetPredicate((w) => w is PopScope<Object?>),
          )
          .first,
    )
    .canPop;

/// 행 사이 구분선 — foreground 아래 테두리를 가진 DecoratedBox.
Finder _rowDividers() => find.descendant(
  of: find.byType(ListView),
  matching: find.byWidgetPredicate(
    (w) => switch (w) {
      DecoratedBox(
        position: DecorationPosition.foreground,
        decoration: BoxDecoration(border: Border(bottom: final side)),
      ) =>
        side.width == 1.0 && side.style == BorderStyle.solid,
      _ => false,
    },
  ),
);

/// 아래 고정 영역 위 선 — 위 테두리를 가진 Container.
Finder _footerBorder() => find.descendant(
  of: find.byType(WithdrawalDisconnectScreen),
  matching: find.byWidgetPredicate(
    (w) => switch (w) {
      Container(decoration: BoxDecoration(border: Border(top: final side))) =>
        side.width == 1.0 && side.style == BorderStyle.solid,
      _ => false,
    },
  ),
);

/// W5 중간 상태 — Facebook 해제됨 · 카카오 실패 · Google 해제됨 · Apple 건너뜀 ·
/// 네이버 로그인 대기(현재) · 라인 대기 (UI-SPEC §Golden fixture mid).
Future<void> _reachW5Mid(WidgetTester tester, _Fakes fakes) async {
  fakes.facebook.calls.last.complete(const DisconnectDone());
  fakes.kakao.calls.last.complete(const DisconnectFailed(ServiceUnavailable()));
  await tester.pump();
  final notifier = _notifierOf(tester);
  unawaited(notifier.signInAndDisconnect(AccountProvider.google));
  fakes.google.calls.last.complete(const DisconnectDone());
  await tester.pump();
  notifier.skip(AccountProvider.apple);
  await tester.pump();
}

void main() {
  group('Phase 16.10 — WithdrawalDisconnectScreen', () {
    testWidgets(
      'WS1: 카카오 한 줄 계정 — 다이얼로그 확인 → 진행 화면 · 삭제 0 → 행 완료 → 「탈퇴」 → 삭제 1회',
      (tester) async {
        _useView(tester);
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

        await tester.tap(_finalButtonFinder());
        await tester.pumpAndSettle();
        verify(() => settingsRepo.requestAccountDeletion()).called(1);
        expect(find.text(l10n.withdrawalSuccess), findsOneWidget);
      },
    );

    testWidgets('WS2: 행 상태 7종 — 아이콘 · 색 · 상태 문구', (tester) async {
      _useView(tester);
      final fakes = _Fakes();
      await _pumpScreen(
        tester,
        providerIds: _w5ProviderIds,
        fakes: fakes,
        settingsRepo: _countingRepo().repo,
      );
      final l10n = await AppLocalizations.delegate.load(const Locale('ko'));
      final scheme = _schemeOf(tester);
      final success = tester
          .element(find.byType(WithdrawalDisconnectScreen))
          .appColors
          .success;
      Color? iconColor(AccountProvider provider, IconData icon) =>
          tester.widget<Icon>(_inRow(provider, find.byIcon(icon))).color;

      // 해제 중 — 행 아이콘 자리 스피너 (주기 734 ms 지점 = 호 모양).
      await tester.pump(const Duration(milliseconds: 734));
      expect(
        _inRow(AccountProvider.kakao, find.byType(CircularProgressIndicator)),
        findsOneWidget,
      );
      expect(
        _inRow(
          AccountProvider.kakao,
          find.text(l10n.withdrawalDisconnectStatusWorking),
        ),
        findsOneWidget,
      );
      // 로그인 대기 (현재 재로그인 행).
      expect(
        iconColor(AccountProvider.google, Icons.login),
        scheme.onSurfaceVariant,
      );
      expect(
        _inRow(
          AccountProvider.google,
          find.text(l10n.withdrawalDisconnectStatusNeedsSignIn),
        ),
        findsOneWidget,
      );
      // 대기.
      expect(
        iconColor(AccountProvider.line, Icons.radio_button_unchecked),
        scheme.onSurfaceVariant,
      );
      expect(
        _inRow(
          AccountProvider.line,
          find.text(l10n.withdrawalDisconnectStatusWaiting),
        ),
        findsOneWidget,
      );

      fakes.facebook.calls.last.complete(const DisconnectDone());
      fakes.kakao.calls.last.complete(
        const DisconnectFailed(ServiceUnavailable()),
      );
      await tester.pump();
      // 해제됨.
      expect(iconColor(AccountProvider.facebook, Icons.check_circle), success);
      expect(
        _inRow(
          AccountProvider.facebook,
          find.text(l10n.withdrawalDisconnectStatusDone),
        ),
        findsOneWidget,
      );
      // 실패.
      expect(
        iconColor(AccountProvider.kakao, Icons.error_outline),
        scheme.error,
      );
      expect(
        _inRow(
          AccountProvider.kakao,
          find.text(l10n.withdrawalDisconnectStatusFailed),
        ),
        findsOneWidget,
      );

      // 신원 불일치.
      await tester.tap(find.byType(SocialButton));
      await tester.pump();
      fakes.google.calls.last.complete(const DisconnectIdentityMismatch());
      await tester.pump();
      final googleLabel = _label(l10n, 'google.com');
      expect(
        iconColor(AccountProvider.google, Icons.error_outline),
        scheme.error,
      );
      expect(
        _inRow(
          AccountProvider.google,
          find.text(l10n.withdrawalDisconnectStatusMismatch(googleLabel)),
        ),
        findsOneWidget,
      );

      // 건너뜀.
      await tester.tap(
        _inRow(
          AccountProvider.google,
          find.widgetWithText(TextButton, l10n.withdrawalDisconnectSkip),
        ),
      );
      await tester.pump();
      expect(
        iconColor(AccountProvider.google, Icons.remove_circle_outline),
        scheme.onSurfaceVariant,
      );
      expect(
        _inRow(
          AccountProvider.google,
          find.text(l10n.withdrawalDisconnectStatusSkipped),
        ),
        findsOneWidget,
      );
    });

    testWidgets('WS3: 구분선 = 행 수 − 1 · outlineVariant · 1.0 (6행 → 5 · 1행 → 0)', (
      tester,
    ) async {
      _useView(tester);
      await _pumpScreen(
        tester,
        providerIds: _w5ProviderIds,
        fakes: _Fakes(),
        settingsRepo: _countingRepo().repo,
      );
      final scheme = _schemeOf(tester);
      expect(_rowDividers(), findsNWidgets(5));
      for (final element in _rowDividers().evaluate()) {
        final box = element.widget as DecoratedBox;
        expect(box.position, DecorationPosition.foreground);
        final border = (box.decoration as BoxDecoration).border! as Border;
        expect(border.bottom.color, scheme.outlineVariant);
        expect(border.top, BorderSide.none);
      }
      // 마지막 행(라인)은 구분선으로 감싸지 않는다.
      expect(
        find.ancestor(of: _row(AccountProvider.line), matching: _rowDividers()),
        findsNothing,
      );

      await tester.pumpWidget(const SizedBox());
      await _pumpScreen(
        tester,
        providerIds: <String>['kakao'],
        fakes: _Fakes(),
        settingsRepo: _countingRepo().repo,
      );
      expect(_rowDividers(), findsNothing);
    });

    testWidgets('WS4: 모두 끝난 상태(스크롤 0)에도 아래 영역 위 선 존재', (tester) async {
      _useView(tester);
      final fakes = _Fakes();
      await _pumpScreen(
        tester,
        providerIds: <String>['kakao'],
        fakes: fakes,
        settingsRepo: _countingRepo().repo,
      );
      fakes.kakao.calls.last.complete(const DisconnectDone());
      await tester.pumpAndSettle();

      expect(_footerBorder(), findsOneWidget);
      final container = tester.widget<Container>(_footerBorder());
      final border = (container.decoration! as BoxDecoration).border! as Border;
      expect(border.top.color, _schemeOf(tester).outlineVariant);
      expect(border.top.width, 1.0);
    });

    testWidgets('WS5: 현재 재로그인 행만 브랜드 버튼 + 건너뛰기 · 대기 행 버튼 0', (tester) async {
      _useView(tester);
      await _pumpScreen(
        tester,
        providerIds: _w5ProviderIds,
        fakes: _Fakes(),
        settingsRepo: _countingRepo().repo,
      );
      final l10n = await AppLocalizations.delegate.load(const Locale('ko'));

      expect(find.byType(SocialButton), findsOneWidget);
      expect(
        _inRow(AccountProvider.google, find.byType(SocialButton)),
        findsOneWidget,
      );
      expect(
        _inRow(
          AccountProvider.google,
          find.widgetWithText(TextButton, l10n.withdrawalDisconnectSkip),
        ),
        findsOneWidget,
      );
      for (final provider in <AccountProvider>[
        AccountProvider.apple,
        AccountProvider.naver,
        AccountProvider.line,
      ]) {
        expect(_inRow(provider, find.byType(TextButton)), findsNothing);
        expect(_inRow(provider, find.byType(SocialButton)), findsNothing);
      }
    });

    testWidgets('WS6: 서버 행 실패 — 건너뛰기 왼쪽 · 재시도 오른쪽', (tester) async {
      _useView(tester);
      final fakes = _Fakes();
      await _pumpScreen(
        tester,
        providerIds: <String>['kakao'],
        fakes: fakes,
        settingsRepo: _countingRepo().repo,
      );
      final l10n = await AppLocalizations.delegate.load(const Locale('ko'));
      fakes.kakao.calls.last.complete(
        const DisconnectFailed(ServiceUnavailable()),
      );
      await tester.pumpAndSettle();

      final skip = _inRow(
        AccountProvider.kakao,
        find.widgetWithText(TextButton, l10n.withdrawalDisconnectSkip),
      );
      final retry = _inRow(
        AccountProvider.kakao,
        find.widgetWithText(TextButton, l10n.commonRetry),
      );
      expect(skip, findsOneWidget);
      expect(retry, findsOneWidget);
      expect(tester.getCenter(skip).dx, lessThan(tester.getCenter(retry).dx));

      await tester.tap(retry);
      await tester.pump();
      expect(fakes.kakao.calls.length, 2);
    });

    testWidgets('WS7: 건너뛴 행 아래 직접 해제 안내', (tester) async {
      _useView(tester);
      final fakes = _Fakes();
      await _pumpScreen(
        tester,
        providerIds: <String>['kakao'],
        fakes: fakes,
        settingsRepo: _countingRepo().repo,
      );
      final l10n = await AppLocalizations.delegate.load(const Locale('ko'));
      fakes.kakao.calls.last.complete(
        const DisconnectFailed(ServiceUnavailable()),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        _inRow(
          AccountProvider.kakao,
          find.widgetWithText(TextButton, l10n.withdrawalDisconnectSkip),
        ),
      );
      await tester.pumpAndSettle();

      final guide = l10n.withdrawalDisconnectSkippedGuide(
        _label(l10n, 'kakao'),
      );
      expect(_inRow(AccountProvider.kakao, find.text(guide)), findsOneWidget);
      expect(
        tester.getTopLeft(find.text(guide)).dy,
        greaterThan(
          tester
              .getTopLeft(find.text(l10n.withdrawalDisconnectStatusSkipped))
              .dy,
        ),
      );
    });

    testWidgets('WS8: 미완료 = 안내 + 비활성 → 전부 끝남 = 안내 없음 + 활성 · error 배경', (
      tester,
    ) async {
      _useView(tester);
      final fakes = _Fakes();
      await _pumpScreen(
        tester,
        providerIds: <String>['kakao', 'google.com'],
        fakes: fakes,
        settingsRepo: _countingRepo().repo,
      );
      final l10n = await AppLocalizations.delegate.load(const Locale('ko'));
      fakes.kakao.calls.last.complete(const DisconnectDone());
      await tester.pumpAndSettle();

      expect(find.text(l10n.withdrawalDisconnectFinalHint), findsOneWidget);
      expect(_finalButton(tester).onPressed, isNull);

      await tester.tap(
        _inRow(
          AccountProvider.google,
          find.widgetWithText(TextButton, l10n.withdrawalDisconnectSkip),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text(l10n.withdrawalDisconnectFinalHint), findsNothing);
      final button = _finalButton(tester);
      expect(button.onPressed, isNotNull);
      expect(
        button.style?.backgroundColor?.resolve(<WidgetState>{}),
        _schemeOf(tester).error,
      );
    });

    testWidgets(
      'WS9: semantics — 행 머리 label · 버튼 button+tap · 「탈퇴」 enabled · 표시 순서 = 낭독 순서',
      (tester) async {
        _useView(tester);
        final handle = tester.ensureSemantics();
        final fakes = _Fakes();
        await _pumpScreen(
          tester,
          providerIds: _w5ProviderIds,
          fakes: fakes,
          settingsRepo: _countingRepo().repo,
        );
        final l10n = await AppLocalizations.delegate.load(const Locale('ko'));
        fakes.facebook.calls.last.complete(const DisconnectDone());
        fakes.kakao.calls.last.complete(
          const DisconnectFailed(ServiceUnavailable()),
        );
        await tester.pump();
        _notifierOf(tester).skip(AccountProvider.google);
        await tester.pump();

        String label(String id) => _label(l10n, id);
        final facebookRow = l10n.withdrawalDisconnectRowSemantic(
          label('facebook.com'),
          l10n.withdrawalDisconnectStatusDone,
        );
        final kakaoRow = l10n.withdrawalDisconnectRowSemantic(
          label('kakao'),
          l10n.withdrawalDisconnectStatusFailed,
        );
        final kakaoSkip = l10n.withdrawalDisconnectSkipSemantic(label('kakao'));
        final kakaoRetry = l10n.withdrawalDisconnectRetrySemantic(
          label('kakao'),
        );
        final googleRow = l10n.withdrawalDisconnectRowSemantic(
          label('google.com'),
          l10n.withdrawalDisconnectStatusSkipped,
        );
        final googleGuide = l10n.withdrawalDisconnectSkippedGuide(
          label('google.com'),
        );
        final appleRow = l10n.withdrawalDisconnectRowSemantic(
          label('apple.com'),
          l10n.withdrawalDisconnectStatusNeedsSignIn,
        );
        final appleSkip = l10n.withdrawalDisconnectSkipSemantic(
          label('apple.com'),
        );
        final naverRow = l10n.withdrawalDisconnectRowSemantic(
          label('naver'),
          l10n.withdrawalDisconnectStatusWaiting,
        );
        final lineRow = l10n.withdrawalDisconnectRowSemantic(
          label('line'),
          l10n.withdrawalDisconnectStatusWaiting,
        );

        for (final rowLabel in <String>[
          facebookRow,
          kakaoRow,
          googleRow,
          appleRow,
          naverRow,
          lineRow,
        ]) {
          expect(
            find.bySemanticsLabel(rowLabel),
            findsOneWidget,
            reason: rowLabel,
          );
        }
        for (final buttonLabel in <String>[kakaoSkip, kakaoRetry, appleSkip]) {
          expect(
            tester.getSemantics(find.bySemanticsLabel(buttonLabel)),
            isSemantics(label: buttonLabel, isButton: true, hasTapAction: true),
            reason: buttonLabel,
          );
        }
        expect(
          tester.getSemantics(
            find.bySemanticsLabel(l10n.withdrawalConfirmActionSemantic),
          ),
          isSemantics(
            label: l10n.withdrawalConfirmActionSemantic,
            isButton: true,
            hasEnabledState: true,
            isEnabled: false,
          ),
        );
        expect(find.bySemanticsLabel(googleGuide), findsOneWidget);

        // 표시 순서 = 낭독 순서.
        final traversal = <String>[
          for (final node in tester.semantics.simulatedAccessibilityTraversal())
            node.label,
        ];
        final expectedOrder = <String>[
          l10n.withdrawalDisconnectIntro,
          facebookRow,
          kakaoRow,
          kakaoSkip,
          kakaoRetry,
          googleRow,
          googleGuide,
          appleRow,
          appleSkip,
          naverRow,
          lineRow,
          l10n.withdrawalDisconnectFinalHint,
          l10n.withdrawalConfirmActionSemantic,
        ];
        final indices = <int>[
          for (final value in expectedOrder) traversal.indexOf(value),
        ];
        expect(indices, isNot(contains(-1)), reason: '$traversal');
        final sorted = <int>[...indices]..sort();
        expect(indices, sorted, reason: '$traversal');
        handle.dispose();
      },
    );

    testWidgets('WS10: 해제 중 · 삭제 중 canPop false · 그 외 true', (tester) async {
      _useView(tester);
      final fakes = _Fakes();
      final settingsRepo = _MockSettingsRepository();
      final deletion = Completer<void>();
      when(
        () => settingsRepo.requestAccountDeletion(),
      ).thenAnswer((_) => deletion.future);
      await _pumpScreen(
        tester,
        providerIds: <String>['kakao'],
        fakes: fakes,
        settingsRepo: settingsRepo,
      );
      expect(_canPop(tester), isFalse);

      fakes.kakao.calls.last.complete(const DisconnectDone());
      await tester.pumpAndSettle();
      expect(_canPop(tester), isTrue);

      await tester.tap(_finalButtonFinder());
      await tester.pump();
      expect(_canPop(tester), isFalse);
      expect(_finalButton(tester).onPressed, isNull);
      expect(
        find.descendant(
          of: find.byType(WithdrawalDisconnectScreen),
          matching: find.byType(CircularProgressIndicator),
        ),
        findsOneWidget,
      );

      deletion.complete();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
    });

    testWidgets(
      'WS11: 5분 창 (b) — 카카오만 · 재인증 push(reauth=1) → pop(true) → 카카오 재실행 · 끝나기 전 삭제 증가 0',
      (tester) async {
        _useView(tester);
        final fakes = _Fakes();
        final visits = _LoginVisits();
        final deletion = _countingRepo(<Object?>[
          const ReauthenticationRequiredException(),
        ]);
        await _pumpScreen(
          tester,
          providerIds: <String>['kakao'],
          fakes: fakes,
          settingsRepo: deletion.repo,
          visits: visits,
        );
        final l10n = await AppLocalizations.delegate.load(const Locale('ko'));
        fakes.kakao.calls.last.complete(const DisconnectDone());
        await tester.pumpAndSettle();

        await tester.tap(_finalButtonFinder());
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));
        expect(deletion.count[0], 1);
        expect(find.text(l10n.withdrawalReauthRequired), findsOneWidget);
        expect(visits.locations, hasLength(1));
        expect(visits.locations.single, contains('reauth=1'));

        await tester.tap(find.text('reauth-ok'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 734));
        expect(fakes.kakao.calls.length, 2);
        expect(
          _inRow(
            AccountProvider.kakao,
            find.text(l10n.withdrawalDisconnectStatusWorking),
          ),
          findsOneWidget,
        );
        expect(_finalButton(tester).onPressed, isNull);
        expect(deletion.count[0], 1);

        fakes.kakao.calls.last.complete(const DisconnectDone());
        await tester.pumpAndSettle();
        expect(_finalButton(tester).onPressed, isNotNull);
        // 재인증 안내 SnackBar 가 「탈퇴」 를 가리지 않게 걷어 낸다.
        ScaffoldMessenger.of(
          tester.element(find.byType(WithdrawalDisconnectScreen)),
        ).removeCurrentSnackBar();
        await tester.pumpAndSettle();
        await tester.tap(_finalButtonFinder());
        await tester.pump();
        expect(deletion.count[0], 2);
      },
    );

    testWidgets(
      'WS12: 일시 오류 → withdrawalFailureTransient · 기타 → withdrawalFailure · 화면 유지',
      (tester) async {
        _useView(tester);
        final fakes = _Fakes();
        final deletion = _countingRepo(<Object?>[
          const NoInternetConnection(),
          const UnknownException(),
        ]);
        await _pumpScreen(
          tester,
          providerIds: <String>['kakao'],
          fakes: fakes,
          settingsRepo: deletion.repo,
        );
        final l10n = await AppLocalizations.delegate.load(const Locale('ko'));
        fakes.kakao.calls.last.complete(const DisconnectDone());
        await tester.pumpAndSettle();

        await tester.tap(_finalButtonFinder());
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));
        expect(find.text(l10n.withdrawalFailureTransient), findsOneWidget);
        expect(find.byType(WithdrawalDisconnectScreen), findsOneWidget);
        expect(_finalButton(tester).onPressed, isNotNull);

        // SnackBar 가 사라진 뒤 다시 누른다.
        await tester.pump(const Duration(seconds: 5));
        await tester.pumpAndSettle();
        await tester.tap(_finalButtonFinder());
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));
        expect(find.text(l10n.withdrawalFailure), findsOneWidget);
        expect(find.byType(WithdrawalDisconnectScreen), findsOneWidget);
        expect(
          _inRow(
            AccountProvider.kakao,
            find.text(l10n.withdrawalDisconnectStatusDone),
          ),
          findsOneWidget,
        );
        expect(deletion.count[0], 2);
      },
    );

    testWidgets('WS13: 삭제 성공 → withdrawalSuccess SnackBar', (tester) async {
      _useView(tester);
      final fakes = _Fakes();
      final deletion = _countingRepo();
      await _pumpScreen(
        tester,
        providerIds: <String>['kakao'],
        fakes: fakes,
        settingsRepo: deletion.repo,
      );
      final l10n = await AppLocalizations.delegate.load(const Locale('ko'));
      fakes.kakao.calls.last.complete(const DisconnectDone());
      await tester.pumpAndSettle();

      await tester.tap(_finalButtonFinder());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text(l10n.withdrawalSuccess), findsOneWidget);
      expect(deletion.count[0], 1);
    });

    for (final lang in <String>['ko', 'en', 'ja']) {
      testWidgets(
        'WS14: $lang 280 × 800 W5 중간 상태 — overflow 0 · 「탈퇴」 viewport 안',
        (tester) async {
          _useView(tester, size: const Size(280, 800));
          final fakes = _Fakes();
          await _pumpScreen(
            tester,
            providerIds: _w5ProviderIds,
            fakes: fakes,
            settingsRepo: _countingRepo().repo,
            locale: Locale(lang),
          );
          await _reachW5Mid(tester, fakes);

          expect(tester.takeException(), isNull);
          final rect = tester.getRect(_finalButtonFinder());
          expect(rect.bottom, lessThanOrEqualTo(800));
          expect(rect.top, greaterThanOrEqualTo(0));
          expect(
            ProviderScope.containerOf(
              tester.element(find.byType(WithdrawalDisconnectScreen)),
            ).read(withdrawalDisconnectProvider).currentReloginRow?.provider,
            AccountProvider.naver,
          );
        },
      );
    }

    testWidgets('WS15: 사용자 트리거 진행 중 — 다른 행 버튼 · 「탈퇴」 비활성', (tester) async {
      _useView(tester);
      final fakes = _Fakes();
      await _pumpScreen(
        tester,
        providerIds: <String>['kakao', 'google.com'],
        fakes: fakes,
        settingsRepo: _countingRepo().repo,
      );
      final l10n = await AppLocalizations.delegate.load(const Locale('ko'));
      fakes.kakao.calls.last.complete(
        const DisconnectFailed(ServiceUnavailable()),
      );
      await tester.pump();

      await tester.tap(find.byType(SocialButton));
      await tester.pump();
      expect(fakes.google.calls.length, 1);
      for (final text in <String>[
        l10n.withdrawalDisconnectSkip,
        l10n.commonRetry,
      ]) {
        final button = tester.widget<TextButton>(
          _inRow(AccountProvider.kakao, find.widgetWithText(TextButton, text)),
        );
        expect(button.onPressed, isNull, reason: text);
      }
      expect(_finalButton(tester).onPressed, isNull);

      fakes.google.calls.last.complete(const DisconnectDone());
      await tester.pump();
      final retry = tester.widget<TextButton>(
        _inRow(
          AccountProvider.kakao,
          find.widgetWithText(TextButton, l10n.commonRetry),
        ),
      );
      expect(retry.onPressed, isNotNull);
    });

    testWidgets(
      'WS16: 5분 창 (a) — 「해제됨」 Google 행 재개방 · 재인증 push 0 · Google 로그인 뒤 「탈퇴」 활성',
      (tester) async {
        _useView(tester);
        final fakes = _Fakes();
        final visits = _LoginVisits();
        final deletion = _countingRepo(<Object?>[
          const ReauthenticationRequiredException(),
        ]);
        await _pumpScreen(
          tester,
          providerIds: <String>['kakao', 'google.com'],
          fakes: fakes,
          settingsRepo: deletion.repo,
          visits: visits,
        );
        final l10n = await AppLocalizations.delegate.load(const Locale('ko'));
        fakes.kakao.calls.last.complete(const DisconnectDone());
        await tester.pump();
        await tester.tap(find.byType(SocialButton));
        await tester.pump();
        fakes.google.calls.last.complete(const DisconnectDone());
        await tester.pumpAndSettle();

        await tester.tap(_finalButtonFinder());
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));
        expect(deletion.count[0], 1);
        expect(find.text(l10n.withdrawalReauthRequired), findsOneWidget);
        expect(visits.locations, isEmpty);
        expect(find.byType(WithdrawalDisconnectScreen), findsOneWidget);

        expect(
          _inRow(
            AccountProvider.google,
            find.text(l10n.withdrawalDisconnectStatusNeedsSignIn),
          ),
          findsOneWidget,
        );
        expect(
          _inRow(AccountProvider.google, find.byType(SocialButton)),
          findsOneWidget,
        );
        expect(
          _inRow(
            AccountProvider.google,
            find.widgetWithText(TextButton, l10n.withdrawalDisconnectSkip),
          ),
          findsOneWidget,
        );
        expect(
          _inRow(
            AccountProvider.kakao,
            find.text(l10n.withdrawalDisconnectStatusDone),
          ),
          findsOneWidget,
        );
        expect(_finalButton(tester).onPressed, isNull);
        expect(find.text(l10n.withdrawalDisconnectFinalHint), findsOneWidget);

        await tester.tap(find.byType(SocialButton));
        await tester.pump();
        expect(fakes.google.calls.length, 2);
        fakes.google.calls.last.complete(const DisconnectDone());
        await tester.pump();
        await tester.pump(const Duration(seconds: 5));
        expect(_finalButton(tester).onPressed, isNotNull);
        expect(visits.locations, isEmpty);
        expect(deletion.count[0], 1);
      },
    );

    testWidgets('WS17: 5분 창 (b) — 재인증에서 결과 없이 돌아와도 카카오 재실행 · 끝나기 전 삭제 증가 0', (
      tester,
    ) async {
      _useView(tester);
      final fakes = _Fakes();
      final visits = _LoginVisits();
      final deletion = _countingRepo(<Object?>[
        const ReauthenticationRequiredException(),
      ]);
      await _pumpScreen(
        tester,
        providerIds: <String>['kakao'],
        fakes: fakes,
        settingsRepo: deletion.repo,
        visits: visits,
      );
      final l10n = await AppLocalizations.delegate.load(const Locale('ko'));
      fakes.kakao.calls.last.complete(const DisconnectDone());
      await tester.pumpAndSettle();

      await tester.tap(_finalButtonFinder());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text(l10n.withdrawalReauthRequired), findsOneWidget);
      expect(visits.locations, hasLength(1));

      await tester.tap(find.text('reauth-back'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 734));
      expect(fakes.kakao.calls.length, 2);
      expect(_finalButton(tester).onPressed, isNull);
      expect(deletion.count[0], 1);

      fakes.kakao.calls.last.complete(const DisconnectDone());
      await tester.pump();
      await tester.pump(const Duration(seconds: 5));
      expect(_finalButton(tester).onPressed, isNotNull);
      expect(deletion.count[0], 1);
    });
  });
}
