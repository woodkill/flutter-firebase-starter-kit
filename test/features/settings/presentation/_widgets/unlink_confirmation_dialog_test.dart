// ignore_for_file: lines_longer_than_80_chars
//
// Phase 16.8 Plan 16.8-04 Task 2 — UnlinkConfirmationDialog widget test
// (UD1~UD8 · D-07 · UI-SPEC §Surface U).
//
// 검증:
// - UD1 렌더 — 제목 · 본문 · [취소] [해제] · 스피너 0 · PopScope canPop true.
// - UD2 취소 — 결과 null · 다이얼로그 닫힘 · repository 미호출.
// - UD3 barrier 탭 — 결과 null · repository 미호출 (barrierDismissible 기본).
// - UD4 busy — 스피너 · 두 액션 비활성 · canPop false · barrier 탭에도 유지 →
//   완료 시 pop(success). busy 첫 프레임은 TextButton 비활성 반영이 다음
//   프레임이라(UI-SPEC §Surface U 1프레임 전이) `pump()` 를 한 번 더 한다.
// - UD5 실패 — pop(lastCredential) · SnackBar 0 (SnackBar 는 설정 화면 몫).
// - UD6 ko verbatim — 제목 · 본문 · 취소 · 해제.
// - UD7 ja · Facebook · 280×800 busy — overflow 0 · 다이얼로그 높이 ≤ 800.
// - UD8 액션 a11y — 두 액션 button + tap 노드 · labeled/android tap target
//   guideline 통과 (다이얼로그 액션 64×48 만 대상 — 설정 행은 이 테스트 밖).
//
// Phase 16.10 Plan 16.10-08 Task 1 — U′ content · 「해제」 = provider 측 끊기 →
// 킷 해제 (D-09 · D-10 · D-11 · D-19 · UI-SPEC §Surface U′):
// - 확인을 누르는 UD4 · UD5 · UD7 은 fake 끊기 step(Done) · dummy 실행 의존을
//   override 한다(기대 결과 불변 — 실 step 은 Firebase 를 읽는다).
// - UD6 ko verbatim 에 고지 · 로그인 안내(Google) 추가.
// - UD9 서버 행(Facebook · 카카오) = 본문 + 고지 · 안내 0.
// - UD10 재로그인 행(Google · Apple · 네이버 · 라인) = 안내 1.
// - UD11 신원 불일치 → pop(identityMismatch) · 킷 해제 0.
// - UD12 provider 로그인 취소 → pop(cancelled) · 킷 해제 0.
// - UD13 password(끊기 행 없음) = 본문만 · 고지 0.

import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart' show FirebaseFunctions;
import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:mocktail/mocktail.dart';

import 'package:flutter_starter_kit/core/auth/auth_strategy.dart';
import 'package:flutter_starter_kit/core/auth/provider_id.dart';
import 'package:flutter_starter_kit/core/auth/strategies/google_auth_strategy.dart';
import 'package:flutter_starter_kit/core/crashlytics/crashlytics_service.dart';
import 'package:flutter_starter_kit/core/error/app_exception.dart';
import 'package:flutter_starter_kit/core/error/result.dart';
import 'package:flutter_starter_kit/core/theme/app_theme.dart';
import 'package:flutter_starter_kit/features/auth/data/auth_repository.dart';
import 'package:flutter_starter_kit/features/auth/data/line_sdk_client.dart';
import 'package:flutter_starter_kit/features/auth/data/naver_sdk_client.dart';
import 'package:flutter_starter_kit/features/auth/domain/user.dart';
import 'package:flutter_starter_kit/features/settings/data/disconnect/disconnect_step.dart';
import 'package:flutter_starter_kit/features/settings/data/disconnect/disconnect_steps.dart';
import 'package:flutter_starter_kit/features/settings/data/settings_repository.dart';
import 'package:flutter_starter_kit/features/settings/presentation/_widgets/unlink_confirmation_dialog.dart';
import 'package:flutter_starter_kit/features/settings/presentation/settings_notifier.dart';
import 'package:flutter_starter_kit/l10n/generated/app_localizations.dart';

class _MockSettingsRepository extends Mock implements SettingsRepository {}

class _MockAuthRepository extends Mock implements AuthRepository {}

class _MockCrashlyticsService extends Mock implements CrashlyticsService {}

class _MockFirebaseAuth extends Mock implements fb.FirebaseAuth {}

class _MockFirebaseFunctions extends Mock implements FirebaseFunctions {}

class _MockGoogleSignIn extends Mock implements GoogleSignIn {}

class _MockLineSdkClient extends Mock implements LineSdkClient {}

class _MockNaverSdkClient extends Mock implements NaverSdkClient {}

/// 정해 둔 결과를 돌려주는 끊기 step — 실 step 은 Firebase 를 읽는다.
class _FixedStep extends DisconnectStep {
  const _FixedStep(this.provider, this.outcome, {this.signInStrategy});

  @override
  final AccountProvider provider;

  @override
  final AuthStrategy? signInStrategy;

  /// run 이 돌려줄 결과.
  final DisconnectOutcome outcome;

  @override
  Future<DisconnectOutcome> run(
    DisconnectDeps deps, {
    required bool reloginForFreshness,
  }) async => outcome;
}

/// Google 재로그인 행 fake — [outcome] 을 돌려준다.
DisconnectStep _googleStep(DisconnectOutcome outcome) => _FixedStep(
  AccountProvider.google,
  outcome,
  signInStrategy: const GoogleAuthStrategy(),
);

/// Facebook 서버 행 fake — 끊기 성공.
const DisconnectStep _facebookDone = _FixedStep(
  AccountProvider.facebook,
  DisconnectDone(),
);

/// 실행 의존 묶음 — fake step 은 읽지 않는다 (Firebase 초기화 회피용 dummy).
DisconnectDeps _dummyDeps() => DisconnectDeps(
  auth: _MockFirebaseAuth(),
  functions: _MockFirebaseFunctions(),
  googleSignIn: _MockGoogleSignIn(),
  lineSdkClient: _MockLineSdkClient(),
  naverSdkClient: _MockNaverSdkClient(),
  platform: TargetPlatform.android,
);

/// 다이얼로그 결과 Future 를 캡슐화 — async auto-unwrap 함정 회피
/// (`withdrawal_confirmation_dialog_test.dart` `_DialogHandle` mirror).
class _DialogHandle {
  _DialogHandle(this.result);
  final Future<AccountUnlinkOutcome?>? result;
}

/// 해제 성공 fixture — Google 을 뺀 뒤의 사용자.
final User _unlinkedUser = User(
  uid: 'uid-1',
  email: 'me@example.com',
  emailVerified: true,
  createdAt: DateTime.utc(2026, 1, 1),
  providerIds: const <String>['kakao'],
  signUpProviderId: 'kakao',
);

/// GoRouter `/` 의 버튼으로 [UnlinkConfirmationDialog.show] 를 열고 결과
/// handle 을 돌려준다. `/login` 은 stub. notifier 의존 3 을 override 한다
/// (`settings_notifier_test.dart` 와 같다). [overrides] 는 끊기 step · 실행
/// 의존 등 테스트별 추가 override 다 (기본 = 실 레지스트리 · 실행 의존 미평가).
Future<_DialogHandle> _pumpAndShowDialog(
  WidgetTester tester, {
  required _MockAuthRepository authRepo,
  Locale locale = const Locale('en'),
  String providerId = 'google.com',
  String providerLabel = 'Google',
  Size? viewport,
  List<Override> overrides = const <Override>[],
}) async {
  if (viewport != null) {
    tester.view.physicalSize = viewport;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  Future<AccountUnlinkOutcome?>? dialogResult;
  final router = GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(
        path: '/',
        builder: (context, state) => Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () {
                dialogResult = UnlinkConfirmationDialog.show(
                  context,
                  providerId: providerId,
                  providerLabel: providerLabel,
                );
              },
              child: const Text('open-dialog'),
            ),
          ),
        ),
      ),
      GoRoute(
        path: '/login',
        builder: (context, state) =>
            const Scaffold(body: Center(child: Text('login-stub'))),
      ),
    ],
  );
  addTearDown(router.dispose);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        settingsRepositoryProvider.overrideWithValue(_MockSettingsRepository()),
        authRepositoryProvider.overrideWithValue(authRepo),
        crashlyticsServiceProvider.overrideWithValue(_MockCrashlyticsService()),
        ...overrides,
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
  await tester.tap(find.text('open-dialog'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
  return _DialogHandle(dialogResult);
}

/// 다이얼로그가 부착한 [PopScope] 위젯 — 제네릭 타입 인자 때문에
/// `find.byType(PopScope)` 가 매칭되지 않아 predicate 로 좁힌다.
PopScope<Object?> _dialogPopScope(WidgetTester tester) {
  return tester.widget<PopScope<Object?>>(
    find.descendant(
      of: find.byType(UnlinkConfirmationDialog),
      matching: find.byWidgetPredicate((w) => w is PopScope<Object?>),
    ),
  );
}

/// 「해제」 를 누르고 busy 상태까지 진행한다 — 탭 프레임 + 1프레임 전이.
Future<void> _tapConfirmUntilBusy(WidgetTester tester, String confirm) async {
  await tester.tap(find.text(confirm));
  await tester.pump();
  // UI-SPEC §Surface U — TextButton 비활성 반영은 다음 프레임.
  await tester.pump();
}

void main() {
  late _MockAuthRepository authRepo;

  setUp(() {
    authRepo = _MockAuthRepository();
  });

  group('Phase 16.8 D-07 — UnlinkConfirmationDialog', () {
    testWidgets('UD1: 렌더 — 제목 · 본문 · 두 액션 · 스피너 0 · canPop true', (
      tester,
    ) async {
      await _pumpAndShowDialog(tester, authRepo: authRepo);

      expect(find.text('Unlink Google?'), findsOneWidget);
      expect(
        find.text(
          "You'll no longer be able to sign in with your Google account.",
        ),
        findsOneWidget,
      );
      expect(find.text('Cancel'), findsOneWidget);
      expect(find.text('Unlink'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(_dialogPopScope(tester).canPop, isTrue);
    });

    testWidgets('UD2: 취소 — 결과 null · 다이얼로그 닫힘 · repository 미호출', (
      tester,
    ) async {
      final handle = await _pumpAndShowDialog(tester, authRepo: authRepo);

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(await handle.result, isNull);
      expect(find.byType(AlertDialog), findsNothing);
      verifyNever(() => authRepo.unlinkNativeProvider(any()));
    });

    testWidgets('UD3: barrier 탭 — 결과 null · repository 미호출', (tester) async {
      final handle = await _pumpAndShowDialog(tester, authRepo: authRepo);

      await tester.tapAt(const Offset(5, 5));
      await tester.pumpAndSettle();

      expect(await handle.result, isNull);
      expect(find.byType(AlertDialog), findsNothing);
      verifyNever(() => authRepo.unlinkNativeProvider(any()));
      verifyNever(() => authRepo.unlinkCustomTokenProvider(any()));
    });

    testWidgets(
      'UD4: busy — 스피너 · 두 액션 비활성 · canPop false · barrier 탭에도 유지 → pop(success)',
      (tester) async {
        final completer = Completer<Result<User>>();
        when(
          () => authRepo.unlinkNativeProvider('google.com'),
        ).thenAnswer((_) => completer.future);
        final handle = await _pumpAndShowDialog(
          tester,
          authRepo: authRepo,
          overrides: [
            disconnectStepsProvider.overrideWithValue(<DisconnectStep>[
              _googleStep(const DisconnectDone()),
            ]),
            disconnectDepsProvider.overrideWithValue(_dummyDeps()),
          ],
        );

        await _tapConfirmUntilBusy(tester, 'Unlink');

        expect(find.byType(CircularProgressIndicator), findsOneWidget);
        final cancelButton = tester.widget<TextButton>(
          find.widgetWithText(TextButton, 'Cancel'),
        );
        expect(cancelButton.enabled, isFalse);
        final confirmButton = tester.widget<TextButton>(
          find.widgetWithText(TextButton, 'Unlink'),
        );
        expect(confirmButton.enabled, isFalse);
        expect(_dialogPopScope(tester).canPop, isFalse);

        // 처리 중 barrier 탭 — PopScope 가 막아 다이얼로그가 남는다.
        await tester.tapAt(const Offset(5, 5));
        await tester.pump();
        expect(find.byType(AlertDialog), findsOneWidget);

        completer.complete(Result<User>.success(_unlinkedUser));
        await tester.pumpAndSettle();

        expect(await handle.result, AccountUnlinkOutcome.success);
        expect(find.byType(AlertDialog), findsNothing);
        verify(() => authRepo.unlinkNativeProvider('google.com')).called(1);
      },
    );

    testWidgets(
      'UD5: 해제 거부(마지막 자격증명) — pop(lastCredential) · 다이얼로그는 SnackBar 를 띄우지 않는다',
      (tester) async {
        when(() => authRepo.unlinkNativeProvider('google.com')).thenAnswer(
          (_) async =>
              const Result<User>.failure(UnlinkLastCredentialRejected()),
        );
        final handle = await _pumpAndShowDialog(
          tester,
          authRepo: authRepo,
          overrides: [
            disconnectStepsProvider.overrideWithValue(<DisconnectStep>[
              _googleStep(const DisconnectDone()),
            ]),
            disconnectDepsProvider.overrideWithValue(_dummyDeps()),
          ],
        );

        await tester.tap(find.text('Unlink'));
        await tester.pumpAndSettle();

        expect(await handle.result, AccountUnlinkOutcome.lastCredential);
        expect(find.byType(AlertDialog), findsNothing);
        expect(find.byType(SnackBar), findsNothing);
      },
    );

    testWidgets('UD6: ko verbatim — 제목 · 본문 · 고지 · 로그인 안내 · 취소 · 해제 (U′)', (
      tester,
    ) async {
      await _pumpAndShowDialog(
        tester,
        authRepo: authRepo,
        locale: const Locale('ko'),
      );

      expect(find.text('Google 연결을 해제할까요?'), findsOneWidget);
      expect(find.text('해제하면 Google 계정으로 로그인할 수 없습니다.'), findsOneWidget);
      expect(find.text('Google 앱 연결(권한)도 함께 해제됩니다.'), findsOneWidget);
      expect(find.text('해제하려면 Google 계정으로 한 번 로그인합니다.'), findsOneWidget);
      expect(find.text('취소'), findsOneWidget);
      expect(find.text('해제'), findsOneWidget);
    });

    testWidgets(
      'UD7: ja · Facebook · 280×800 busy — overflow 0 · 다이얼로그 높이 ≤ 800 (UI-SPEC E2)',
      (tester) async {
        final completer = Completer<Result<User>>();
        when(
          () => authRepo.unlinkNativeProvider('facebook.com'),
        ).thenAnswer((_) => completer.future);
        final handle = await _pumpAndShowDialog(
          tester,
          authRepo: authRepo,
          locale: const Locale('ja'),
          providerId: 'facebook.com',
          providerLabel: 'Facebook',
          viewport: const Size(280, 800),
          overrides: [
            disconnectStepsProvider.overrideWithValue(<DisconnectStep>[
              _facebookDone,
            ]),
            disconnectDepsProvider.overrideWithValue(_dummyDeps()),
          ],
        );
        expect(tester.takeException(), isNull);

        await _tapConfirmUntilBusy(tester, '解除');

        expect(find.byType(CircularProgressIndicator), findsOneWidget);
        expect(tester.takeException(), isNull);
        expect(
          tester.getSize(find.byType(AlertDialog)).height,
          lessThanOrEqualTo(800),
        );

        // pending future 0 — 끝내고 닫힘까지 settle.
        completer.complete(Result<User>.success(_unlinkedUser));
        await tester.pumpAndSettle();
        expect(await handle.result, AccountUnlinkOutcome.success);
      },
    );

    testWidgets(
      'UD8: 액션 a11y — 두 액션 button + tap 노드 · labeled/android tap target guideline',
      (tester) async {
        final semanticsHandle = tester.ensureSemantics();
        await _pumpAndShowDialog(tester, authRepo: authRepo);

        for (final label in const <String>['Cancel', 'Unlink']) {
          expect(
            tester.getSemantics(find.text(label)),
            isSemantics(label: label, isButton: true, hasTapAction: true),
            reason: label,
          );
        }
        await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
        await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
        semanticsHandle.dispose();
      },
    );
    // 서버 행 — 고지만 (로그인 없이 서버가 끊는다). 실 레지스트리로 판정한다.
    for (final (providerId, label) in const <(String, String)>[
      ('facebook.com', 'Facebook'),
      ('kakao', '카카오'),
    ]) {
      testWidgets('UD9: $label 서버 행 — 본문 + 고지 · 로그인 안내 0 (D-19)', (
        tester,
      ) async {
        await _pumpAndShowDialog(
          tester,
          authRepo: authRepo,
          locale: const Locale('ko'),
          providerId: providerId,
          providerLabel: label,
        );

        expect(find.text('해제하면 $label 계정으로 로그인할 수 없습니다.'), findsOneWidget);
        expect(find.text('$label 앱 연결(권한)도 함께 해제됩니다.'), findsOneWidget);
        expect(find.textContaining('한 번 로그인합니다.'), findsNothing);
      });
    }

    // 재로그인 행 — 고지 + 로그인 안내 (레지스트리 kind 판정 · C-08).
    for (final (providerId, label) in const <(String, String)>[
      ('google.com', 'Google'),
      ('apple.com', 'Apple'),
      ('naver', '네이버'),
      ('line', '라인'),
    ]) {
      testWidgets('UD10: $label 재로그인 행 — 로그인 안내 1 (D-10 · Q7-A)', (
        tester,
      ) async {
        await _pumpAndShowDialog(
          tester,
          authRepo: authRepo,
          locale: const Locale('ko'),
          providerId: providerId,
          providerLabel: label,
        );

        expect(find.text('$label 앱 연결(권한)도 함께 해제됩니다.'), findsOneWidget);
        expect(find.text('해제하려면 $label 계정으로 한 번 로그인합니다.'), findsOneWidget);
      });
    }

    testWidgets(
      'UD11: 신원 불일치 → pop(identityMismatch) · 킷 해제 0 (D-08 · 연결 유지)',
      (tester) async {
        final handle = await _pumpAndShowDialog(
          tester,
          authRepo: authRepo,
          overrides: [
            disconnectStepsProvider.overrideWithValue(<DisconnectStep>[
              _googleStep(const DisconnectIdentityMismatch()),
            ]),
            disconnectDepsProvider.overrideWithValue(_dummyDeps()),
          ],
        );

        await tester.tap(find.text('Unlink'));
        await tester.pumpAndSettle();

        expect(await handle.result, AccountUnlinkOutcome.identityMismatch);
        expect(find.byType(AlertDialog), findsNothing);
        expect(find.byType(SnackBar), findsNothing);
        verifyNever(() => authRepo.unlinkNativeProvider(any()));
        verifyNever(() => authRepo.unlinkCustomTokenProvider(any()));
      },
    );

    testWidgets('UD12: provider 로그인 취소 → pop(cancelled) · 킷 해제 0 (D-11)', (
      tester,
    ) async {
      final handle = await _pumpAndShowDialog(
        tester,
        authRepo: authRepo,
        overrides: [
          disconnectStepsProvider.overrideWithValue(<DisconnectStep>[
            _googleStep(const DisconnectCancelled()),
          ]),
          disconnectDepsProvider.overrideWithValue(_dummyDeps()),
        ],
      );

      await tester.tap(find.text('Unlink'));
      await tester.pumpAndSettle();

      expect(await handle.result, AccountUnlinkOutcome.cancelled);
      expect(find.byType(AlertDialog), findsNothing);
      verifyNever(() => authRepo.unlinkNativeProvider(any()));
      verifyNever(() => authRepo.unlinkCustomTokenProvider(any()));
    });

    testWidgets('UD13: password — 끊기 행 없음 → 본문만 · 고지 · 안내 0 (D-09 범위)', (
      tester,
    ) async {
      await _pumpAndShowDialog(
        tester,
        authRepo: authRepo,
        locale: const Locale('ko'),
        providerId: 'password',
        providerLabel: '이메일',
      );

      expect(find.text('해제하면 이메일 계정으로 로그인할 수 없습니다.'), findsOneWidget);
      expect(find.textContaining('앱 연결(권한)'), findsNothing);
      expect(find.textContaining('한 번 로그인합니다.'), findsNothing);
    });
  });
}
