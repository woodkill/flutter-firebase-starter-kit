// ignore_for_file: lines_longer_than_80_chars
//
// Phase 16 Plan 16-06 Task 6.2 — WithdrawalConfirmationDialog widget test
// (WC1~WC10).
//
// 검증:
// - WC1 3-line GDPR 노출
// - WC2 confirmTextField disabled init (verbatim 미입력)
// - WC3 verbatim match enables button (ko locale "탈퇴")
// - WC4 verbatim mismatch — partial input disabled
// - WC5 cancel — Navigator.pop(false) + dialog close
// - WC6 confirm → loading → success → withdrawalSuccess SnackBar + /onboarding
// - WC7 reauth fail SnackBar + /login redirect
// - WC8 server fail SnackBar + dialog 유지
// - WC9 barrierDismissible:false during loading
// - WC10 Semantics destructive intent (withdrawalConfirmActionSemantic consume)
// - WC11/WC12 (WR-03) 원인별 실패 문구 — TooManyRequests /
//   NoInternetConnection → withdrawalFailureTransient (generic 미노출)
// - WC17~WC19 (Phase 16.10 D-05 · Q6-A) 확인 뒤 분기 — 끊을 행이 있으면
//   진행 화면 push(삭제 0), 없으면(이메일/비밀번호만 · 사용자 부재) 바로 삭제
// - WC20~WC21 (16.10 review WR-01) 행 입력 = 서버 1회 조회 — 조회 실패면
//   삭제 0 · 재시도 안내 · 다이얼로그 유지, 캐시가 비어도 서버에 CT 연결이
//   있으면 진행 화면

import 'dart:async';

import 'package:firebase_core/firebase_core.dart' show FirebaseException;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';

import 'package:flutter_starter_kit/core/error/app_exception.dart';
import 'package:flutter_starter_kit/core/router/app_routes.dart';
import 'package:flutter_starter_kit/core/theme/app_theme.dart';
import 'package:flutter_starter_kit/features/auth/data/auth_repository.dart';
import 'package:flutter_starter_kit/features/auth/domain/user.dart';
import 'package:flutter_starter_kit/features/settings/data/settings_repository.dart';
import 'package:flutter_starter_kit/features/settings/presentation/_widgets/withdrawal_confirmation_dialog.dart';
import 'package:flutter_starter_kit/l10n/generated/app_localizations.dart';

class _MockSettingsRepository extends Mock implements SettingsRepository {}

class _MockAuthRepository extends Mock implements AuthRepository {}

/// 다이얼로그 결과 Future 를 캡슐화 — async auto-unwrap 함정 회피
/// (memory `Plan 16-04 _SheetHandle` mirror).
class _DialogHandle {
  _DialogHandle(this.result);
  final Future<bool?>? result;
}

Future<_DialogHandle> _pumpAndShowDialog(
  WidgetTester tester, {
  _MockSettingsRepository? settingsRepo,
  _MockAuthRepository? authRepo,
  Locale locale = const Locale('ko'),
  List<String>? visitedRoutes,
  List<String>? providerIds,
  bool nullUser = false,
  List<String>? serverProviderIds,
  Object? serverReadError,
  List<int>? serverReads,
}) async {
  Future<bool?>? dialogResult;
  final repo = settingsRepo ?? _MockSettingsRepository();
  final aRepo = authRepo ?? _MockAuthRepository();
  when(() => aRepo.signOut()).thenAnswer((_) async {});
  // 16-07(ec7e13d) 이후 탈퇴 성공 path 는 signOutAndResetOnboarding 를 호출한다.
  when(() => aRepo.signOutAndResetOnboarding()).thenAnswer((_) async {});

  final router = GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(
        path: '/',
        builder: (context, state) => Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () {
                dialogResult = WithdrawalConfirmationDialog.show(context);
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
      // Phase 16.10 — 탈퇴 진행 화면 route stub (WC17).
      GoRoute(
        path: AppRoutes.withdrawalDisconnect,
        builder: (context, state) =>
            const Scaffold(body: Center(child: Text('withdraw-stub'))),
      ),
    ],
  );
  if (visitedRoutes != null) {
    router.routerDelegate.addListener(() {
      visitedRoutes.add(
        router.routerDelegate.currentConfiguration.uri.toString(),
      );
    });
  }

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        settingsRepositoryProvider.overrideWithValue(repo),
        authRepositoryProvider.overrideWithValue(aRepo),
        if (providerIds != null)
          currentUserProvider.overrideWith(
            (ref) => User(
              uid: 'uid-test',
              emailVerified: true,
              createdAt: DateTime(2026),
              providerIds: providerIds,
            ),
          ),
        if (nullUser) currentUserProvider.overrideWith((ref) => null),
        // 16.10 review WR-01: 행 입력은 서버 1회 조회다. 기본은 캐시와 같은
        // 목록(사용자 부재면 빈 목록)을 돌려준다.
        serverProviderIdsReaderProvider.overrideWithValue(() async {
          if (serverReads != null) serverReads[0] += 1;
          final error = serverReadError;
          if (error != null) throw error;
          return serverProviderIds ?? providerIds ?? const <String>[];
        }),
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

/// 다이얼로그가 부착한 [PopScope] 위젯을 찾는다 (WR-05).
///
/// `find.byType(PopScope)` 는 제네릭 타입 인자 때문에 매칭되지 않으므로
/// 다이얼로그 하위에서 predicate 로 좁힌다.
PopScope<Object?> _dialogPopScope(WidgetTester tester) {
  return tester.widget<PopScope<Object?>>(
    find.descendant(
      of: find.byType(WithdrawalConfirmationDialog),
      matching: find.byWidgetPredicate((w) => w is PopScope<Object?>),
    ),
  );
}

void main() {
  // ko locale verbatim phrase.
  const koHint = '탈퇴';

  setUpAll(() {
    registerFallbackValue(Object());
  });

  group('Phase 16 D-08 — WithdrawalConfirmationDialog', () {
    testWidgets('WC1 — 3-line GDPR 본문 모두 표시', (tester) async {
      await _pumpAndShowDialog(tester);

      // ko locale verbatim — withdrawalDialogBodyLine1/2/3.
      expect(find.text('이 계정과 모든 데이터는 영구 삭제됩니다.'), findsOneWidget);
      expect(find.text('삭제 후에는 복구할 수 없습니다.'), findsOneWidget);
      expect(
        find.text('다시 가입하려면 동일 이메일 또는 동일 로그인 방식으로 신규 등록해야 합니다.'),
        findsOneWidget,
      );
    });

    testWidgets('WC2 — confirmTextField 빈 입력 시 confirm FilledButton disabled', (
      tester,
    ) async {
      await _pumpAndShowDialog(tester);

      // 라벨 "탈퇴" 가 visible 한 FilledButton 위젯 찾기 (Semantics 래퍼 통과).
      final confirmBtn = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, koHint),
      );
      expect(confirmBtn.onPressed, isNull);
    });

    testWidgets('WC3 — verbatim "탈퇴" 입력 시 confirm enabled', (tester) async {
      await _pumpAndShowDialog(tester);

      await tester.enterText(find.byType(TextField), koHint);
      await tester.pump();

      final confirmBtn = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, koHint),
      );
      expect(confirmBtn.onPressed, isNotNull);
    });

    testWidgets('WC4 — partial input "탈" 시 confirm disabled', (tester) async {
      await _pumpAndShowDialog(tester);

      await tester.enterText(find.byType(TextField), '탈');
      await tester.pump();

      final confirmBtn = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, koHint),
      );
      expect(confirmBtn.onPressed, isNull);
    });

    testWidgets('WC5 — cancel 탭 → Navigator.pop(false) + dialog dismiss', (
      tester,
    ) async {
      final handle = await _pumpAndShowDialog(tester);

      // commonCancel ko verbatim = "취소"
      expect(find.text('취소'), findsOneWidget);
      await tester.tap(find.text('취소'));
      await tester.pumpAndSettle();

      expect(find.byType(WithdrawalConfirmationDialog), findsNothing);
      expect(await handle.result, isFalse);
    });

    testWidgets('WC6 — confirm 탭 → success SnackBar 노출', (tester) async {
      final settingsRepo = _MockSettingsRepository();
      when(
        () => settingsRepo.requestAccountDeletion(),
      ).thenAnswer((_) async {});

      await _pumpAndShowDialog(tester, settingsRepo: settingsRepo);

      await tester.enterText(find.byType(TextField), koHint);
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, koHint));
      // loading frame + complete frame.
      await tester.pump();
      await tester.pump();
      await tester.pumpAndSettle();

      // 성공 SnackBar "회원탈퇴가 완료되었습니다." 노출.
      expect(find.text('회원탈퇴가 완료되었습니다.'), findsOneWidget);
      verify(() => settingsRepo.requestAccountDeletion()).called(1);
    });

    testWidgets(
      'WC7 — reauth fail → withdrawalReauthRequired SnackBar + dialog close',
      (tester) async {
        final settingsRepo = _MockSettingsRepository();
        when(
          () => settingsRepo.requestAccountDeletion(),
        ).thenThrow(const ReauthenticationRequiredException());

        await _pumpAndShowDialog(tester, settingsRepo: settingsRepo);

        await tester.enterText(find.byType(TextField), koHint);
        await tester.pump();
        await tester.tap(find.widgetWithText(FilledButton, koHint));
        await tester.pump();
        await tester.pump();
        await tester.pumpAndSettle();

        // withdrawalReauthRequired ko verbatim.
        expect(
          find.text('보안을 위해 다시 로그인이 필요합니다. 로그인 후 다시 시도해 주세요.'),
          findsOneWidget,
        );
        // dialog 닫힘.
        expect(find.byType(WithdrawalConfirmationDialog), findsNothing);
        // 260916-p8d: 재인증 push 는 재인증 표시가 붙은 로그인 location 이어야 한다.
        expect(
          find.text('login-stub'),
          findsOneWidget,
          reason: '재인증 필요 예외 뒤 로그인 화면이 push 되어야 한다',
        );
        final loginState = GoRouterState.of(
          tester.element(find.text('login-stub')),
        );
        expect(
          loginState.matchedLocation,
          AppRoutes.login,
          reason: '재인증 push 대상은 로그인 화면이다',
        );
        expect(
          AppRoutes.hasReauthMarker(loginState.uri),
          isTrue,
          reason:
              'R_EXTRA_G3_REAUTH_LOGIN_BOUNCE: 표시가 없으면 실제 앱 guard 분기 (6) 이 '
              'push 한 로그인 화면을 홈으로 튕긴다',
        );
      },
    );

    testWidgets('WC8 — server fail → withdrawalFailure SnackBar + dialog 유지', (
      tester,
    ) async {
      final settingsRepo = _MockSettingsRepository();
      when(
        () => settingsRepo.requestAccountDeletion(),
      ).thenThrow(const UnknownException());

      await _pumpAndShowDialog(tester, settingsRepo: settingsRepo);

      await tester.enterText(find.byType(TextField), koHint);
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, koHint));
      await tester.pump();
      await tester.pump();
      await tester.pumpAndSettle();

      // withdrawalFailure ko verbatim.
      expect(find.text('회원탈퇴에 실패했습니다. 다시 시도해 주세요.'), findsOneWidget);
      // dialog 유지 (재시도 가능).
      expect(find.byType(WithdrawalConfirmationDialog), findsOneWidget);
    });

    // WR-03 (2차 리뷰): _mapDeleteError taxonomy 가 사용자에게 실제로
    // 다른 문구를 만든다는 계약. 수정 전에는 NoInternetConnection /
    // TooManyRequests / UnknownException 이 모두 withdrawalFailure 로
    // collapse 되어 taxonomy 분리가 화면에 아무 변화도 만들지 못했다
    // (S6~S8 은 repository 반환 타입만 단언해 이 사실을 드러내지 못한다).
    testWidgets(
      'WC11 (WR-03) — resource-exhausted(TooManyRequests) → withdrawalFailureTransient SnackBar (generic 미노출)',
      (tester) async {
        final settingsRepo = _MockSettingsRepository();
        when(
          () => settingsRepo.requestAccountDeletion(),
        ).thenThrow(const TooManyRequests());

        await _pumpAndShowDialog(tester, settingsRepo: settingsRepo);

        await tester.enterText(find.byType(TextField), koHint);
        await tester.pump();
        await tester.tap(find.widgetWithText(FilledButton, koHint));
        await tester.pump();
        await tester.pump();
        await tester.pumpAndSettle();

        // withdrawalFailureTransient ko verbatim.
        expect(
          find.text('네트워크 또는 서비스 오류로 회원탈퇴에 실패했습니다. 잠시 후 다시 시도해 주세요.'),
          findsOneWidget,
        );
        // generic 문구는 노출되지 않는다 (collapse 회귀 가드).
        expect(find.text('회원탈퇴에 실패했습니다. 다시 시도해 주세요.'), findsNothing);
        // dialog 유지 (재시도 가능).
        expect(find.byType(WithdrawalConfirmationDialog), findsOneWidget);
      },
    );

    testWidgets(
      'WC12 (WR-03) — unavailable(NoInternetConnection) → withdrawalFailureTransient SnackBar',
      (tester) async {
        final settingsRepo = _MockSettingsRepository();
        when(
          () => settingsRepo.requestAccountDeletion(),
        ).thenThrow(const NoInternetConnection());

        await _pumpAndShowDialog(tester, settingsRepo: settingsRepo);

        await tester.enterText(find.byType(TextField), koHint);
        await tester.pump();
        await tester.tap(find.widgetWithText(FilledButton, koHint));
        await tester.pump();
        await tester.pump();
        await tester.pumpAndSettle();

        expect(
          find.text('네트워크 또는 서비스 오류로 회원탈퇴에 실패했습니다. 잠시 후 다시 시도해 주세요.'),
          findsOneWidget,
        );
        expect(find.text('회원탈퇴에 실패했습니다. 다시 시도해 주세요.'), findsNothing);
        expect(find.byType(WithdrawalConfirmationDialog), findsOneWidget);
      },
    );

    testWidgets('WC9 — barrierDismissible:false (backdrop tap → dialog 유지)', (
      tester,
    ) async {
      await _pumpAndShowDialog(tester);

      // dialog 가 노출됐는지 sanity.
      expect(find.byType(WithdrawalConfirmationDialog), findsOneWidget);

      // ModalBarrier tap 시도 (showDialog 의 barrier — barrierDismissible:false
      // 라 어떤 input 도 dismiss 안 됨).
      final barriers = find.byType(ModalBarrier);
      if (barriers.evaluate().isNotEmpty) {
        await tester.tap(barriers.first, warnIfMissed: false);
        await tester.pumpAndSettle();
      }

      // dialog 그대로 유지.
      expect(find.byType(WithdrawalConfirmationDialog), findsOneWidget);
    });

    testWidgets(
      'WC10 — Semantics destructive intent (withdrawalConfirmActionSemantic consume)',
      (tester) async {
        await _pumpAndShowDialog(tester);

        // ko verbatim — "회원탈퇴 — 영구 삭제, 복구 불가" Semantics label.
        // Semantics 가 button: true + label 지정으로 부착됐는지 검증.
        final semanticsFinder = find.bySemanticsLabel('회원탈퇴 — 영구 삭제, 복구 불가');
        expect(semanticsFinder, findsAtLeast(1));
      },
    );

    testWidgets('WC13 (WR-05) — loading 중 시스템 back 으로 다이얼로그가 닫히지 않는다', (
      tester,
    ) async {
      // barrierDismissible:false 는 backdrop tap 만 막는다 (WC9). Android
      // 하드웨어 back / predictive back 은 PopScope 없이는 그대로 pop 되어,
      // 되돌릴 수 없는 삭제 진행 중에 성공/실패 피드백이 유실된다.
      final settingsRepo = _MockSettingsRepository();
      final deleteGate = Completer<void>();
      when(
        () => settingsRepo.requestAccountDeletion(),
      ).thenAnswer((_) => deleteGate.future);

      await _pumpAndShowDialog(tester, settingsRepo: settingsRepo);

      await tester.enterText(find.byType(TextField), koHint);
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, koHint));
      await tester.pump();

      // loading 진입 확인 — canPop 이 false 로 잠긴 구간.
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(_dialogPopScope(tester).canPop, isFalse);

      // 시스템 back 제스처 — PopScope 가 흡수해야 한다.
      await tester.binding.handlePopRoute();
      await tester.pump();

      expect(
        find.byType(WithdrawalConfirmationDialog),
        findsOneWidget,
        reason: '탈퇴 진행 중에는 back 으로 이탈할 수 없어야 한다 (D-08)',
      );

      // 정리 — gate 를 풀어 pending timer 없이 종료.
      deleteGate.complete();
      await tester.pumpAndSettle();
    });

    testWidgets('WC14 (WR-05) — loading 이 아닐 때는 back 으로 취소할 수 있다', (
      tester,
    ) async {
      // canPop 상시 false 면 사용자가 확인 전 단계에서도 갇힌다 — 잠금은
      // loading 구간에 한정된다.
      await _pumpAndShowDialog(tester);

      expect(_dialogPopScope(tester).canPop, isTrue);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(find.byType(WithdrawalConfirmationDialog), findsNothing);
    });

    testWidgets('WC15 (WR-06) — en 로케일에서 공백·대소문자 차이는 confirm 을 막지 않는다', (
      tester,
    ) async {
      // en hint 는 소문자 "delete" 다. 자동완성/붙여넣기가 넣은 trailing
      // space 나 "Delete" 로 확인 버튼이 영구 disabled 되면 사용자는 사유
      // 안내도 없이 막힌다 (en 버튼 라벨은 "Delete").
      await _pumpAndShowDialog(tester, locale: const Locale('en'));

      await tester.enterText(find.byType(TextField), ' Delete ');
      await tester.pump();

      final confirmBtn = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Delete'),
      );
      expect(confirmBtn.onPressed, isNotNull);
    });

    testWidgets('WC16 (WR-06) — 부분 입력은 여전히 불일치 (D-08 마찰 유지)', (tester) async {
      await _pumpAndShowDialog(tester, locale: const Locale('en'));

      await tester.enterText(find.byType(TextField), 'del');
      await tester.pump();

      final confirmBtn = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Delete'),
      );
      expect(confirmBtn.onPressed, isNull);
    });

    testWidgets('WC17 (16.10 D-05) — 끊을 행이 있으면 다이얼로그를 닫고 진행 화면 push · 삭제 0', (
      tester,
    ) async {
      final settingsRepo = _MockSettingsRepository();
      when(
        () => settingsRepo.requestAccountDeletion(),
      ).thenAnswer((_) async {});
      final handle = await _pumpAndShowDialog(
        tester,
        settingsRepo: settingsRepo,
        providerIds: const <String>['kakao', 'google.com'],
      );

      await tester.enterText(find.byType(TextField), koHint);
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, koHint));
      await tester.pumpAndSettle();

      expect(find.byType(WithdrawalConfirmationDialog), findsNothing);
      expect(find.text('withdraw-stub'), findsOneWidget);
      expect(
        GoRouterState.of(
          tester.element(find.text('withdraw-stub')),
        ).matchedLocation,
        AppRoutes.withdrawalDisconnect,
      );
      expect(await handle.result, isFalse);
      verifyNever(() => settingsRepo.requestAccountDeletion());
    });

    testWidgets('WC18 (16.10 Q6-A) — 이메일/비밀번호만이면 진행 화면 없이 바로 삭제', (
      tester,
    ) async {
      final settingsRepo = _MockSettingsRepository();
      when(
        () => settingsRepo.requestAccountDeletion(),
      ).thenAnswer((_) async {});
      await _pumpAndShowDialog(
        tester,
        settingsRepo: settingsRepo,
        providerIds: const <String>['password'],
      );

      await tester.enterText(find.byType(TextField), koHint);
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, koHint));
      await tester.pump();
      await tester.pump();
      await tester.pumpAndSettle();

      verify(() => settingsRepo.requestAccountDeletion()).called(1);
      expect(find.text('withdraw-stub'), findsNothing);
      expect(find.text('회원탈퇴가 완료되었습니다.'), findsOneWidget);
    });

    testWidgets('WC19 (16.10 Q6-A) — 로그인 사용자 부재(null)면 기존 경로로 바로 삭제', (
      tester,
    ) async {
      final settingsRepo = _MockSettingsRepository();
      when(
        () => settingsRepo.requestAccountDeletion(),
      ).thenAnswer((_) async {});
      await _pumpAndShowDialog(
        tester,
        settingsRepo: settingsRepo,
        nullUser: true,
      );

      await tester.enterText(find.byType(TextField), koHint);
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, koHint));
      await tester.pump();
      await tester.pump();
      await tester.pumpAndSettle();

      verify(() => settingsRepo.requestAccountDeletion()).called(1);
      expect(find.text('withdraw-stub'), findsNothing);
    });

    testWidgets('WC20 (review WR-01) — 서버 조회 실패면 삭제 0 · 재시도 안내 · 다이얼로그 유지', (
      tester,
    ) async {
      final settingsRepo = _MockSettingsRepository();
      when(
        () => settingsRepo.requestAccountDeletion(),
      ).thenAnswer((_) async {});
      final reads = <int>[0];
      await _pumpAndShowDialog(
        tester,
        settingsRepo: settingsRepo,
        // 캐시는 「연결 없음」 으로 보인다 — 읽기 실패를 빈 목록으로 흡수한 모양.
        providerIds: const <String>[],
        serverReadError: FirebaseException(
          plugin: 'cloud_firestore',
          code: 'unavailable',
        ),
        serverReads: reads,
      );

      await tester.enterText(find.byType(TextField), koHint);
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, koHint));
      await tester.pump();
      await tester.pump();
      await tester.pumpAndSettle();

      expect(reads.single, 1);
      verifyNever(() => settingsRepo.requestAccountDeletion());
      expect(
        find.text('네트워크 또는 서비스 오류로 회원탈퇴에 실패했습니다. 잠시 후 다시 시도해 주세요.'),
        findsOneWidget,
      );
      expect(find.byType(WithdrawalConfirmationDialog), findsOneWidget);
      expect(find.text('withdraw-stub'), findsNothing);
      // 재시도할 수 있다 — 확인 버튼이 다시 활성이다.
      final confirmBtn = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, koHint),
      );
      expect(confirmBtn.onPressed, isNotNull);
    });

    testWidgets(
      'WC21 (review WR-01) — 캐시가 비어도 서버에 카카오 · 라인이 있으면 진행 화면 · 삭제 0',
      (tester) async {
        final settingsRepo = _MockSettingsRepository();
        when(
          () => settingsRepo.requestAccountDeletion(),
        ).thenAnswer((_) async {});
        await _pumpAndShowDialog(
          tester,
          settingsRepo: settingsRepo,
          providerIds: const <String>[],
          serverProviderIds: const <String>['kakao', 'line'],
        );

        await tester.enterText(find.byType(TextField), koHint);
        await tester.pump();
        await tester.tap(find.widgetWithText(FilledButton, koHint));
        await tester.pumpAndSettle();

        expect(find.byType(WithdrawalConfirmationDialog), findsNothing);
        expect(find.text('withdraw-stub'), findsOneWidget);
        verifyNever(() => settingsRepo.requestAccountDeletion());
      },
    );
  });
}
