// ignore_for_file: lines_longer_than_80_chars
//
// Phase 16 Plan 16-08 Task 2 — login/signup catch path 의 AccountLinkingSheet
// wiring + sheet link action 검증.
//
// 5 behavior:
//   T1: social notifier AsyncError(existingProvider=google, isNative) →
//       AccountLinkingSheet 노출 + inline FormErrorBanner 미노출 (sheet 우선)
//   T2: existingProvider == null (unknown) → sheet 미노출 + FormErrorBanner
//       inline 노출 (R2 회귀 0)
//   T3: sheet provider 버튼 tap → linkPendingNativeCredential 호출 → 성공 →
//       sheet pop(true) + /home 이동
//   T4: sheet dismiss/cancel (TextButton) → pop(false) + linkedProviders 변경 0
//   T5 (viewport): sheet provider 버튼이 viewport 밖이면 ensureVisible 후 tap
//   T-17-APPCHECK-05: 경로 A link 실패 · 경로 B step 1 로그인 실패가
//       AppCheckFailedException 이면 SnackBar = ko errorAppCheckFailed · 라우팅 0
//       (Phase 17 D-42 · D-43)

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';

import 'package:flutter_starter_kit/core/auth/auth_strategies_registry.dart';
import 'package:flutter_starter_kit/core/auth/auth_strategy.dart';
import 'package:flutter_starter_kit/core/auth/provider_id.dart';
import 'package:flutter_starter_kit/core/auth/strategies/google_auth_strategy.dart';
import 'package:flutter_starter_kit/core/error/app_exception.dart';
import 'package:flutter_starter_kit/core/error/result.dart';
import 'package:flutter_starter_kit/core/router/app_routes.dart';
import 'package:flutter_starter_kit/core/theme/app_theme.dart';
import 'package:flutter_starter_kit/features/auth/data/auth_repository.dart';
import 'package:flutter_starter_kit/features/auth/domain/user.dart';
import 'package:flutter_starter_kit/features/auth/presentation/_widgets/account_linking_sheet.dart';
import 'package:flutter_starter_kit/features/auth/presentation/_widgets/branded_social_button.dart';
import 'package:flutter_starter_kit/features/auth/presentation/_widgets/form_error_banner.dart';
import 'package:flutter_starter_kit/features/auth/presentation/_widgets/social_sign_in_section.dart';
import 'package:flutter_starter_kit/features/auth/presentation/login_screen.dart';
import 'package:flutter_starter_kit/l10n/generated/app_localizations.dart';

class _MockAuthRepository extends Mock implements AuthRepository {}

/// client-side `account-exists-with-different-credential` 이 보존하는 native
/// pending credential 대역 (Plan 16-19 경로 A 진입 조건).
const Object _kPendingCredential = Object();

void main() {
  late _MockAuthRepository mockRepo;

  setUpAll(() {
    registerFallbackValue(AccountProvider.google);
  });

  setUp(() {
    mockRepo = _MockAuthRepository();
  });

  /// 모바일 portrait viewport 로 설정한다 — modal bottom sheet 하단 컨텐츠가
  /// default 800x600 landscape 밖에 위치해 hit-test 실패하는 함정 회피
  /// (memory feedback_test_viewport_ensure_visible).
  Future<void> usePortraitSurface(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(400, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
  }

  /// modal bottom sheet entrance 애니메이션을 완전히 settle 시킨다 —
  /// `pumpAndSettle` 은 BrandedSocialButton 비동기 자산 디코딩으로 hang 될
  /// 수 있어 명시적 다단계 pump 로 sheet slide-up 종료 후 안정화한다.
  Future<void> settleSheetEntrance(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(seconds: 1));
  }

  /// LoginScreen 을 GoRouter 가 감싸는 harness 를 [tester] 로 pump 한다 —
  /// sheet → context.go(/home) 검증 가능. /home 진입 시 sentinel 'HOME' 텍스트
  /// 노출. [ProviderScope] 는 `pumpWidget` 의 직접 인자다 (riverpod_lint root
  /// 판정). 라우팅 단언용으로 만든 [GoRouter] 를 돌려준다.
  Future<GoRouter> pumpHarness(
    WidgetTester tester, {
    required Result<User>? Function() onGoogleSignIn,
    Locale locale = const Locale('en'),
  }) async {
    when(
      () => mockRepo.signInWithGoogle(),
    ).thenAnswer((_) async => onGoogleSignIn());
    final router = GoRouter(
      initialLocation: AppRoutes.login,
      routes: [
        GoRoute(
          path: AppRoutes.login,
          builder: (context, state) => const LoginScreen(),
        ),
        GoRoute(
          path: AppRoutes.home,
          builder: (context, state) => const Scaffold(body: Text('HOME')),
        ),
      ],
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(mockRepo),
          activeStrategiesProvider.overrideWithValue(const <AuthStrategy>[
            GoogleAuthStrategy(),
          ]),
        ],
        child: MaterialApp.router(
          theme: AppTheme.light(),
          locale: locale,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          routerConfig: router,
        ),
      ),
    );
    return router;
  }

  group('T1 — native account-exists → AccountLinkingSheet 노출', () {
    testWidgets(
      'AsyncError(existingProvider=google, isNative) → sheet 노출 + inline banner 미노출',
      (tester) async {
        await usePortraitSurface(tester);
        await pumpHarness(
          tester,
          onGoogleSignIn: () => const Result<User>.failure(
            AccountExistsWithDifferentCredential(
              email: 'collide@example.com',
              existingProvider: AccountProvider.google,
              // Plan 16-19: native arm(경로 A) 진입 조건 — client-side
              // account-exists 충돌은 pendingCredential 을 보존한다.
              pendingCredential: _kPendingCredential,
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byType(BrandedSocialButton).first);
        await settleSheetEntrance(tester);

        // sheet 노출 (sheet 안 BrandedSocialButton + dismiss TextButton).
        expect(find.byType(AccountLinkingSheet), findsOneWidget);
        // inline FormErrorBanner 에 account-exists 미표시 (sheet 우선).
        final inlineBanner = tester.widget<FormErrorBanner>(
          find.descendant(
            of: find.byType(SocialSignInSection),
            matching: find.byType(FormErrorBanner),
          ),
        );
        expect(
          inlineBanner.exception,
          isNot(isA<AccountExistsWithDifferentCredential>()),
        );
      },
    );
  });

  group('T2 — unknown provider → FormErrorBanner inline (R2 회귀 0)', () {
    testWidgets(
      'existingProvider == null → sheet 미노출 + FormErrorBanner inline 노출',
      (tester) async {
        await pumpHarness(
          tester,
          onGoogleSignIn: () => const Result<User>.failure(
            AccountExistsWithDifferentCredential(email: 'old@example.com'),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byType(BrandedSocialButton).first);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));

        // sheet 미노출.
        expect(find.byType(AccountLinkingSheet), findsNothing);
        // inline FormErrorBanner 에 account-exists 표시 (R2 baseline).
        final inlineBanner = tester.widget<FormErrorBanner>(
          find.descendant(
            of: find.byType(SocialSignInSection),
            matching: find.byType(FormErrorBanner),
          ),
        );
        expect(
          inlineBanner.exception,
          isA<AccountExistsWithDifferentCredential>(),
        );
        // unknown fallback 메시지 verbatim.
        expect(
          find.text(
            'This email is already registered with another sign-in method. '
            'Please sign in with the method you originally used.',
          ),
          findsOneWidget,
        );
      },
    );
  });

  group('T3 — sheet provider 버튼 tap → link 성공 → /home', () {
    testWidgets(
      'sheet Google 버튼 tap → linkPendingNativeCredential 호출 → /home 이동',
      (tester) async {
        await usePortraitSurface(tester);
        when(
          () => mockRepo.linkPendingNativeCredential(
            existingProvider: any(named: 'existingProvider'),
            pendingCredential: any(named: 'pendingCredential'),
          ),
        ).thenAnswer(
          (_) async => Result<User>.success(
            User(
              uid: 'u1',
              email: 'collide@example.com',
              emailVerified: true,
              createdAt: DateTime.utc(2026, 1, 1),
              providerIds: const ['google.com'],
            ),
          ),
        );

        await pumpHarness(
          tester,
          onGoogleSignIn: () => const Result<User>.failure(
            AccountExistsWithDifferentCredential(
              email: 'collide@example.com',
              existingProvider: AccountProvider.google,
              // Plan 16-19: native arm(경로 A) 진입 조건 — client-side
              // account-exists 충돌은 pendingCredential 을 보존한다.
              pendingCredential: _kPendingCredential,
            ),
          ),
        );
        await tester.pumpAndSettle();

        // 충돌 trigger → sheet 노출.
        await tester.tap(find.byType(BrandedSocialButton).first);
        await settleSheetEntrance(tester);
        expect(find.byType(AccountLinkingSheet), findsOneWidget);

        // sheet 안 Google BrandedSocialButton tap (sheet 내부 단일 버튼).
        final sheetButton = find.descendant(
          of: find.byType(AccountLinkingSheet),
          matching: find.byType(BrandedSocialButton),
        );
        await tester.ensureVisible(sheetButton);
        await tester.tap(sheetButton);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));
        await tester.pumpAndSettle();

        verify(
          () => mockRepo.linkPendingNativeCredential(
            existingProvider: AccountProvider.google,
            pendingCredential: any(named: 'pendingCredential'),
          ),
        ).called(1);
        // /home 이동 확인.
        expect(find.text('HOME'), findsOneWidget);
      },
    );
  });

  group('T4 — sheet dismiss/cancel → pop(false) + link 미호출', () {
    testWidgets(
      'TextButton "Sign in with another method" tap → sheet dismiss + link 미호출',
      (tester) async {
        await usePortraitSurface(tester);
        await pumpHarness(
          tester,
          onGoogleSignIn: () => const Result<User>.failure(
            AccountExistsWithDifferentCredential(
              email: 'collide@example.com',
              existingProvider: AccountProvider.google,
              // Plan 16-19: native arm(경로 A) 진입 조건 — client-side
              // account-exists 충돌은 pendingCredential 을 보존한다.
              pendingCredential: _kPendingCredential,
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byType(BrandedSocialButton).first);
        await settleSheetEntrance(tester);
        expect(find.byType(AccountLinkingSheet), findsOneWidget);

        final dismissBtn = find.text('Sign in with another method');
        await tester.ensureVisible(dismissBtn);
        await tester.tap(dismissBtn);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));

        // sheet dismiss + linkedProviders 변경 0 (link 미호출).
        expect(find.byType(AccountLinkingSheet), findsNothing);
        verifyNever(
          () => mockRepo.linkPendingNativeCredential(
            existingProvider: any(named: 'existingProvider'),
            pendingCredential: any(named: 'pendingCredential'),
          ),
        );
      },
    );
  });

  group(
    'T6 — WR-01: native reauth-expired → SnackBar + sheet dismiss + /login',
    () {
      testWidgets(
        'linkPendingNativeCredential → ReauthenticationRequiredException → '
        'authReauthRequired SnackBar + sheet pop(false)',
        (tester) async {
          await usePortraitSurface(tester);
          when(
            () => mockRepo.linkPendingNativeCredential(
              existingProvider: any(named: 'existingProvider'),
              pendingCredential: any(named: 'pendingCredential'),
            ),
          ).thenAnswer(
            (_) async =>
                const Result<User>.failure(ReauthenticationRequiredException()),
          );

          await pumpHarness(
            tester,
            onGoogleSignIn: () => const Result<User>.failure(
              AccountExistsWithDifferentCredential(
                email: 'collide@example.com',
                existingProvider: AccountProvider.google,
                // Plan 16-19: native arm(경로 A) 진입 조건 — client-side
                // account-exists 충돌은 pendingCredential 을 보존한다.
                pendingCredential: _kPendingCredential,
              ),
            ),
          );
          await tester.pumpAndSettle();

          await tester.tap(find.byType(BrandedSocialButton).first);
          await settleSheetEntrance(tester);
          expect(find.byType(AccountLinkingSheet), findsOneWidget);

          final sheetButton = find.descendant(
            of: find.byType(AccountLinkingSheet),
            matching: find.byType(BrandedSocialButton),
          );
          await tester.ensureVisible(sheetButton);
          await tester.tap(sheetButton);
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 500));

          verify(
            () => mockRepo.linkPendingNativeCredential(
              existingProvider: AccountProvider.google,
              pendingCredential: any(named: 'pendingCredential'),
            ),
          ).called(1);
          // WR-01: 더 이상 mute pop 이 아니라 user-visible reauth 안내 SnackBar.
          expect(
            find.text('For security, please sign in again and retry.'),
            findsOneWidget,
          );
          // sheet 닫힘 (/login 라우팅 — 초기 location 도 /login).
          expect(find.byType(AccountLinkingSheet), findsNothing);
        },
      );
    },
  );

  group('T7 — WR-01/WR-02: native 기타 실패 → 원인별 SnackBar + sheet dismiss', () {
    testWidgets('linkPendingNativeCredential → AccountAlreadyLinked → '
        'settingsLinkFailedAlreadyLinked SnackBar + sheet pop(false)', (
      tester,
    ) async {
      await usePortraitSurface(tester);
      when(
        () => mockRepo.linkPendingNativeCredential(
          existingProvider: any(named: 'existingProvider'),
          pendingCredential: any(named: 'pendingCredential'),
        ),
      ).thenAnswer(
        (_) async => const Result<User>.failure(AccountAlreadyLinked()),
      );

      await pumpHarness(
        tester,
        onGoogleSignIn: () => const Result<User>.failure(
          AccountExistsWithDifferentCredential(
            email: 'collide@example.com',
            existingProvider: AccountProvider.google,
            // Plan 16-19: native arm(경로 A) 진입 조건 — client-side
            // account-exists 충돌은 pendingCredential 을 보존한다.
            pendingCredential: _kPendingCredential,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byType(BrandedSocialButton).first);
      await settleSheetEntrance(tester);
      expect(find.byType(AccountLinkingSheet), findsOneWidget);

      final sheetButton = find.descendant(
        of: find.byType(AccountLinkingSheet),
        matching: find.byType(BrandedSocialButton),
      );
      await tester.ensureVisible(sheetButton);
      await tester.tap(sheetButton);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      // WR-01: 기타 실패도 silent 가 아니라 graceful 안내 SnackBar.
      // WR-02 (4차 리뷰): 문구는 원인별 분기 결과다. AccountAlreadyLinked
      // 의 실제 원인은 credential-already-in-use ("그 자격증명을 **다른
      // 계정**이 쓰고 있다") 이므로 이메일 문구가 아니라 전용 문구가 뜬다.
      expect(
        find.text(
          'This sign-in method is already linked to another account. '
          'Unlink it first, then try again.',
        ),
        findsOneWidget,
      );
      // 순환 안내 문구 미노출 — 사용자는 방금 그 "처음 가입한 방식" 으로
      // 재인증까지 마친 상태다 (경로 A 는 _reauthNativeCredential 선행).
      expect(
        find.text(
          'This email is already registered with another sign-in method. '
          'Please sign in with the method you originally used.',
        ),
        findsNothing,
      );
      expect(find.byType(AccountLinkingSheet), findsNothing);
    });
  });

  group('T5 — viewport: 좁은 화면에서 ensureVisible 후 tap', () {
    testWidgets('좁은 viewport (320x560) → sheet 버튼 ensureVisible 후 link 호출', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(320, 560));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      when(
        () => mockRepo.linkPendingNativeCredential(
          existingProvider: any(named: 'existingProvider'),
          pendingCredential: any(named: 'pendingCredential'),
        ),
      ).thenAnswer(
        (_) async => Result<User>.success(
          User(
            uid: 'u1',
            email: 'collide@example.com',
            emailVerified: true,
            createdAt: DateTime.utc(2026, 1, 1),
            providerIds: const ['google.com'],
          ),
        ),
      );

      await pumpHarness(
        tester,
        onGoogleSignIn: () => const Result<User>.failure(
          AccountExistsWithDifferentCredential(
            email: 'collide@example.com',
            existingProvider: AccountProvider.google,
            // Plan 16-19: native arm(경로 A) 진입 조건 — client-side
            // account-exists 충돌은 pendingCredential 을 보존한다.
            pendingCredential: _kPendingCredential,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byType(BrandedSocialButton).first);
      await settleSheetEntrance(tester);
      expect(find.byType(AccountLinkingSheet), findsOneWidget);

      final sheetButton = find.descendant(
        of: find.byType(AccountLinkingSheet),
        matching: find.byType(BrandedSocialButton),
      );
      // 좁은 viewport 에서 CTA hit-test 회피 (ensureVisible 후 tap).
      await tester.ensureVisible(sheetButton);
      await tester.pump();
      await tester.tap(sheetButton);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();

      verify(
        () => mockRepo.linkPendingNativeCredential(
          existingProvider: AccountProvider.google,
          pendingCredential: any(named: 'pendingCredential'),
        ),
      ).called(1);
    });
  });

  group('T-17-APPCHECK-05: 연결 시트 App Check 문구 (Phase 17 D-42 · D-43)', () {
    const ko = Locale('ko');
    final appCheckCopy = lookupAppLocalizations(ko).errorAppCheckFailed;
    final reauthCopy = lookupAppLocalizations(ko).authReauthRequired;

    /// 시트를 열고 sheet provider 버튼을 탭한다. [pendingCredential] 이 있으면
    /// 경로 A(link), 없으면 경로 B(step 1 로그인)다.
    Future<GoRouter> openSheetAndTap(
      WidgetTester tester, {
      required Object? pendingCredential,
    }) async {
      await usePortraitSurface(tester);
      final router = await pumpHarness(
        tester,
        locale: ko,
        onGoogleSignIn: () => Result<User>.failure(
          AccountExistsWithDifferentCredential(
            email: 'collide@example.com',
            existingProvider: AccountProvider.google,
            pendingCredential: pendingCredential,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byType(BrandedSocialButton).first);
      await settleSheetEntrance(tester);
      expect(find.byType(AccountLinkingSheet), findsOneWidget);

      final sheetButton = find.descendant(
        of: find.byType(AccountLinkingSheet),
        matching: find.byType(BrandedSocialButton),
      );
      await tester.ensureVisible(sheetButton);
      await tester.tap(sheetButton);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      return router;
    }

    testWidgets('경로 A link 실패 AppCheckFailedException → 전용 문구 · 재로그인 0', (
      tester,
    ) async {
      when(
        () => mockRepo.linkPendingNativeCredential(
          existingProvider: any(named: 'existingProvider'),
          pendingCredential: any(named: 'pendingCredential'),
        ),
      ).thenAnswer(
        (_) async => const Result<User>.failure(AppCheckFailedException()),
      );

      final router = await openSheetAndTap(
        tester,
        pendingCredential: _kPendingCredential,
      );

      expect(find.text(appCheckCopy), findsOneWidget);
      expect(find.text(reauthCopy), findsNothing);
      expect(find.text('HOME'), findsNothing);
      expect(
        router.routerDelegate.currentConfiguration.uri.path,
        AppRoutes.login,
      );
    });

    testWidgets('경로 B step 1 로그인 실패 AppCheckFailedException → 전용 문구 · 시트 유지', (
      tester,
    ) async {
      when(
        () => mockRepo.signInWithExistingProvider(
          provider: any(named: 'provider'),
        ),
      ).thenAnswer(
        (_) async => const Result<User>.failure(AppCheckFailedException()),
      );

      final router = await openSheetAndTap(tester, pendingCredential: null);

      verify(
        () => mockRepo.signInWithExistingProvider(
          provider: AccountProvider.google,
        ),
      ).called(1);
      expect(find.text(appCheckCopy), findsOneWidget);
      expect(find.text(reauthCopy), findsNothing);
      // 실패는 시트 유지(재시도 가능) · 화면 이동 0.
      expect(find.byType(AccountLinkingSheet), findsOneWidget);
      expect(find.text('HOME'), findsNothing);
      expect(
        router.routerDelegate.currentConfiguration.uri.path,
        AppRoutes.login,
      );
    });
  });
}
