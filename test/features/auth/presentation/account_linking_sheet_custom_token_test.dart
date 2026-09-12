// ignore_for_file: lines_longer_than_80_chars
//
// Phase 16 Plan 16-09 Task 2 → Plan 16-19 Task 3 갱신 —
// AccountLinkingSheet 의 **hook seam 계약** 검증.
//
// **역할 분담 (Plan 16-19, CR-02 close):**
//   - 본 파일 — `onExistingProviderSignIn` **주입(seam)** 계약. 주입 시 시트가
//     repository 대신 콜백의 bool 결과를 쓰고, 미주입 시 실 repository 로
//     폴백한다는 두 방향을 모두 잠근다.
//   - account_linking_sheet_two_step_test.dart (TS1~TS7) — hook 을 한 건도
//     주입하지 않는 **실 repository 경로** 회귀 (리뷰가 요구한 테스트).
//
// **hook 의 의미 갱신 (16-09 → 16-19):** 과거 `onCustomTokenLink` 는 "Custom
// Token link 결과" 였으나, 2단계 플로우 도입 후 `onExistingProviderSignIn` 은
// **step 1 = 기존 provider 로그인 결과** override seam 이다 (`true` = 로그인
// 성공, `false` = 취소·실패). 프로덕션 호출처(LoginScreen/SignupScreen)는
// 주입하지 않는다.
//
// 7 behavior:
//   T1: Custom Token collision(existingProvider=kakao, isNative==false) →
//       login_screen 이 AccountLinkingSheet.show 노출 (변경 0)
//   T2: hook 주입 + true → 시트 pop + /home (seam 성공 계약)
//   T3: existingProvider == naver → 시트 노출 + CTA 탭이 hook 을 naver 로
//       호출 (Plan 16-19: naver graceful 차단 분기 제거 — 로그인 대상 지원)
//   T4: sheet dismiss → hook 미호출 + pop(false) (D-03 cancel invariant)
//   T6: hook 주입 + false → 시트 유지 + 네비게이션 0 (seam 취소·실패 계약)
//   T7: hook 미주입 → 실 repository signInWithExistingProvider 폴백
//   T5 (viewport): 좁은 viewport 에서 CTA ensureVisible 후 tap → hook 호출

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';

import 'package:flutter_starter_kit/core/auth/auth_strategies_registry.dart';
import 'package:flutter_starter_kit/core/auth/auth_strategy.dart';
import 'package:flutter_starter_kit/core/auth/provider_id.dart';
import 'package:flutter_starter_kit/core/auth/strategies/kakao_auth_strategy.dart';
import 'package:flutter_starter_kit/core/error/app_exception.dart';
import 'package:flutter_starter_kit/core/error/result.dart';
import 'package:flutter_starter_kit/core/router/app_routes.dart';
import 'package:flutter_starter_kit/core/theme/app_theme.dart';
import 'package:flutter_starter_kit/features/auth/data/auth_repository.dart';
import 'package:flutter_starter_kit/features/auth/domain/user.dart';
import 'package:flutter_starter_kit/features/auth/presentation/_widgets/account_linking_sheet.dart';
import 'package:flutter_starter_kit/features/auth/presentation/_widgets/branded_social_button.dart';
import 'package:flutter_starter_kit/features/auth/presentation/login_screen.dart';
import 'package:flutter_starter_kit/l10n/generated/app_localizations.dart';

class _MockAuthRepository extends Mock implements AuthRepository {}

void main() {
  late _MockAuthRepository mockRepo;

  setUpAll(() {
    registerFallbackValue(AccountProvider.kakao);
  });

  setUp(() {
    mockRepo = _MockAuthRepository();
  });

  /// 모바일 portrait viewport — modal bottom sheet 하단 컨텐츠 hit-test 함정
  /// 회피 (memory feedback_test_viewport_ensure_visible).
  Future<void> usePortraitSurface(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(400, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
  }

  /// modal bottom sheet entrance 애니메이션 settle (pumpAndSettle 은
  /// BrandedSocialButton 비동기 자산 디코딩으로 hang 가능 → 명시적 다단계 pump).
  Future<void> settleSheetEntrance(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(seconds: 1));
  }

  /// LoginScreen 을 GoRouter 가 감싸는 harness — Kakao Custom Token 충돌 시나리오
  /// (T1 의 sheet 노출 경로 — Plan 16-08/16-09 이후 변경 0).
  Widget buildHarness({required Result<User>? Function() onKakaoSignIn}) {
    when(
      () => mockRepo.signInWithKakao(),
    ).thenAnswer((_) async => onKakaoSignIn());
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
    return ProviderScope(
      overrides: [
        authRepositoryProvider.overrideWithValue(mockRepo),
        activeStrategiesProvider.overrideWithValue(const <AuthStrategy>[
          KakaoAuthStrategy(),
        ]),
      ],
      child: MaterialApp.router(
        theme: AppTheme.light(),
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        routerConfig: router,
      ),
    );
  }

  /// sheet 결과 Future 를 캡슐화한 wrapper — async 함수의 자동 Future unwrap 이
  /// sheet pop 까지 await 하여 hang 되는 함정 회피.
  ///
  /// [AccountLinkingSheet.show] 를 seam 파라미터와 함께 직접 호출하는 harness
  /// (LoginScreen 은 hook 을 주입하지 않으므로 seam 검증은 직접 show 로 한다).
  Future<Future<bool?>?> showSeamSheet(
    WidgetTester tester, {
    required AccountProvider existingProvider,
    ExistingProviderSignInCallback? onExistingProviderSignIn,
  }) async {
    Future<bool?>? sheetResult;
    final router = GoRouter(
      initialLocation: AppRoutes.login,
      routes: [
        GoRoute(
          path: AppRoutes.login,
          builder: (context, state) => Scaffold(
            body: Builder(
              builder: (innerContext) => ElevatedButton(
                onPressed: () {
                  sheetResult = AccountLinkingSheet.show(
                    innerContext,
                    existingProvider: existingProvider,
                    onExistingProviderSignIn: onExistingProviderSignIn,
                  );
                },
                child: const Text('open-sheet'),
              ),
            ),
          ),
        ),
        GoRoute(
          path: AppRoutes.home,
          builder: (context, state) => const Scaffold(body: Text('HOME')),
        ),
      ],
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [authRepositoryProvider.overrideWithValue(mockRepo)],
        child: MaterialApp.router(
          theme: AppTheme.light(),
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          routerConfig: router,
        ),
      ),
    );
    await tester.tap(find.text('open-sheet'));
    await settleSheetEntrance(tester);
    expect(find.byType(AccountLinkingSheet), findsOneWidget);
    return sheetResult;
  }

  /// 시트 안 CTA 를 탭한다 (form-tail 좌표 hit-test 회피 — ensureVisible 명시).
  Future<void> tapSheetCta(WidgetTester tester) async {
    final sheetButton = find.descendant(
      of: find.byType(AccountLinkingSheet),
      matching: find.byType(BrandedSocialButton),
    );
    await tester.ensureVisible(sheetButton);
    await tester.pump();
    await tester.tap(sheetButton);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
  }

  group('T1 — Custom Token collision → AccountLinkingSheet 노출', () {
    testWidgets('AsyncError(existingProvider=kakao, !isNative) → sheet 노출', (
      tester,
    ) async {
      await usePortraitSurface(tester);
      await tester.pumpWidget(
        buildHarness(
          onKakaoSignIn: () => const Result<User>.failure(
            AccountExistsWithDifferentCredential(
              email: 'collide@example.com',
              existingProvider: AccountProvider.kakao,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Kakao 소셜 버튼 tap → 충돌 → sheet 노출.
      await tester.tap(find.byType(BrandedSocialButton).first);
      await settleSheetEntrance(tester);

      expect(find.byType(AccountLinkingSheet), findsOneWidget);
    });
  });

  group('T2 — seam 주입 + true → 시트 pop + /home', () {
    testWidgets(
      'onExistingProviderSignIn(kakao) → true → sheet 닫힘 + /home 이동',
      (tester) async {
        await usePortraitSurface(tester);
        final calls = <AccountProvider>[];

        await showSeamSheet(
          tester,
          existingProvider: AccountProvider.kakao,
          onExistingProviderSignIn: (provider) async {
            calls.add(provider);
            return true;
          },
        );
        await tapSheetCta(tester);
        await tester.pump(const Duration(seconds: 1));

        expect(calls, <AccountProvider>[AccountProvider.kakao]);
        expect(find.byType(AccountLinkingSheet), findsNothing);
        expect(find.text('HOME'), findsOneWidget);
        // seam 이 주입되면 repository 는 우회된다.
        verifyNever(
          () => mockRepo.signInWithExistingProvider(
            provider: any(named: 'provider'),
          ),
        );
      },
    );
  });

  group('T3 — naver 도 seam 을 통과한다 (graceful 차단 분기 제거)', () {
    testWidgets(
      'existingProvider=naver → sheet 노출 + CTA 탭이 hook 을 naver 로 호출 + 크래시 0',
      (tester) async {
        await usePortraitSurface(tester);
        final calls = <AccountProvider>[];

        await showSeamSheet(
          tester,
          existingProvider: AccountProvider.naver,
          onExistingProviderSignIn: (provider) async {
            calls.add(provider);
            return true;
          },
        );
        await tapSheetCta(tester);
        await tester.pump(const Duration(seconds: 1));

        // Plan 16-19: naver 는 로그인 대상으로 지원 — 과거처럼 차단되지 않는다.
        expect(calls, <AccountProvider>[AccountProvider.naver]);
        expect(tester.takeException(), isNull);
      },
    );
  });

  group('T4 — sheet cancel → hook 미호출 (D-03)', () {
    testWidgets('TextButton dismiss → sheet pop(false) + hook 미호출', (
      tester,
    ) async {
      await usePortraitSurface(tester);
      var called = false;

      final sheetResult = await showSeamSheet(
        tester,
        existingProvider: AccountProvider.kakao,
        onExistingProviderSignIn: (provider) async {
          called = true;
          return true;
        },
      );

      final dismissBtn = find.text('Sign in with another method');
      await tester.ensureVisible(dismissBtn);
      await tester.pump();
      await tester.tap(dismissBtn);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.byType(AccountLinkingSheet), findsNothing);
      expect(called, isFalse);
      expect(await sheetResult, isFalse);
    });
  });

  group('T6 — seam 주입 + false → 시트 유지 + 네비게이션 0', () {
    testWidgets(
      'onExistingProviderSignIn → false (취소·실패) → sheet 유지 + /home 미진입',
      (tester) async {
        await usePortraitSurface(tester);

        await showSeamSheet(
          tester,
          existingProvider: AccountProvider.kakao,
          onExistingProviderSignIn: (provider) async => false,
        );
        await tapSheetCta(tester);
        await tester.pump(const Duration(seconds: 1));

        // 재시도 가능한 상태로 sheet 유지 (stuck sheet 방지 — dismiss 로 이탈 가능).
        expect(find.byType(AccountLinkingSheet), findsOneWidget);
        expect(find.text('HOME'), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  });

  group('T7 — seam 미주입 → 실 repository 폴백', () {
    testWidgets(
      'onExistingProviderSignIn 미주입 → signInWithExistingProvider 직접 호출',
      (tester) async {
        await usePortraitSurface(tester);
        when(
          () => mockRepo.signInWithExistingProvider(
            provider: any(named: 'provider'),
          ),
        ).thenAnswer(
          (_) async => Result<User>.success(
            User(
              uid: 'u1',
              email: 'collide@example.com',
              emailVerified: true,
              createdAt: DateTime.utc(2026, 1, 1),
              providerIds: const ['kakao'],
            ),
          ),
        );

        await showSeamSheet(tester, existingProvider: AccountProvider.kakao);
        await tapSheetCta(tester);
        await tester.pump(const Duration(seconds: 1));

        verify(
          () => mockRepo.signInWithExistingProvider(
            provider: AccountProvider.kakao,
          ),
        ).called(1);
        expect(find.text('HOME'), findsOneWidget);
      },
    );
  });

  group('T5 — viewport: 좁은 화면 ensureVisible 후 tap', () {
    testWidgets('좁은 viewport(320x560) → CTA ensureVisible 후 hook 호출', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(320, 560));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final calls = <AccountProvider>[];

      await showSeamSheet(
        tester,
        existingProvider: AccountProvider.kakao,
        onExistingProviderSignIn: (provider) async {
          calls.add(provider);
          return true;
        },
      );
      await tapSheetCta(tester);
      await tester.pump(const Duration(seconds: 1));

      expect(calls, <AccountProvider>[AccountProvider.kakao]);
    });
  });
}
