// ignore_for_file: lines_longer_than_80_chars
//
// Phase 16 Plan 16-09 Task 2 — Custom Token reactive link arm
// (sheet 노출 + onCustomTokenLink action + login/signup Custom Token wiring).
//
// 5 behavior:
//   T1: Custom Token collision(existingProvider=kakao, isNative==false) →
//       login_screen 이 AccountLinkingSheet.show 노출 (native 만이 아닌 Custom
//       Token 도 sheet)
//   T2: sheet Kakao 버튼 tap → onCustomTokenLink(kakao) →
//       linkCustomTokenProviderArm 호출 → 성공 시 pop(true) + /home
//   T3: existingProvider == naver (deployed callable 미지원) → sheet 노출 +
//       버튼 tap 시 graceful 안내 (SnackBar) + 크래시 0 + link 미호출
//   T4: sheet cancel → linkedProviders 변경 0 (D-03)
//   T5 (viewport): 좁은 viewport 에서 Custom Token 버튼 ensureVisible 후 tap

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

  /// LoginScreen 을 GoRouter 가 감싸는 harness — Kakao Custom Token 충돌 시나리오.
  Widget buildHarness({
    required Result<User>? Function() onKakaoSignIn,
  }) {
    when(() => mockRepo.signInWithKakao()).thenAnswer(
      (_) async => onKakaoSignIn(),
    );
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
        activeStrategiesProvider(const Locale('en')).overrideWithValue(
          const <AuthStrategy>[KakaoAuthStrategy()],
        ),
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

  group('T1 — Custom Token collision → AccountLinkingSheet 노출', () {
    testWidgets(
      'AsyncError(existingProvider=kakao, !isNative) → sheet 노출',
      (tester) async {
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
      },
    );
  });

  group('T2 — sheet Kakao 버튼 tap → link 성공 → /home', () {
    testWidgets(
      'sheet Kakao 버튼 tap → linkCustomTokenProviderArm 호출 → /home 이동',
      (tester) async {
        await usePortraitSurface(tester);
        when(
          () => mockRepo.linkCustomTokenProviderArm(
            targetProvider: any(named: 'targetProvider'),
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
        await tester.pumpAndSettle();

        verify(
          () => mockRepo.linkCustomTokenProviderArm(
            targetProvider: AccountProvider.kakao,
          ),
        ).called(1);
        expect(find.text('HOME'), findsOneWidget);
      },
    );
  });

  group('T3 — naver target → graceful 안내 (Phase 17+) + 크래시 0', () {
    testWidgets(
      'existingProvider=naver → sheet 노출 + 버튼 tap graceful + link 미호출',
      (tester) async {
        await usePortraitSurface(tester);
        await tester.pumpWidget(
          buildHarness(
            onKakaoSignIn: () => const Result<User>.failure(
              AccountExistsWithDifferentCredential(
                email: 'collide@example.com',
                existingProvider: AccountProvider.naver,
              ),
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

        // naver 는 deployed callable 미지원 → linkCustomTokenProviderArm 미호출
        // (graceful — 크래시 0).
        verifyNever(
          () => mockRepo.linkCustomTokenProviderArm(
            targetProvider: any(named: 'targetProvider'),
          ),
        );
        // tester 가 예외 없이 진행 (크래시 0).
        expect(tester.takeException(), isNull);
      },
    );
  });

  group('T4 — sheet cancel → link 미호출 (D-03)', () {
    testWidgets(
      'TextButton dismiss → sheet pop + linkCustomTokenProviderArm 미호출',
      (tester) async {
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

        await tester.tap(find.byType(BrandedSocialButton).first);
        await settleSheetEntrance(tester);
        expect(find.byType(AccountLinkingSheet), findsOneWidget);

        final dismissBtn = find.text('Sign in with another method');
        await tester.ensureVisible(dismissBtn);
        await tester.tap(dismissBtn);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));

        expect(find.byType(AccountLinkingSheet), findsNothing);
        verifyNever(
          () => mockRepo.linkCustomTokenProviderArm(
            targetProvider: any(named: 'targetProvider'),
          ),
        );
      },
    );
  });

  group('T6 — WR-02: Custom Token reauth-expired → SnackBar + sheet dismiss + /login', () {
    testWidgets(
      'linkCustomTokenProviderArm → ReauthenticationRequiredException → '
      'withdrawalReauthRequired SnackBar + sheet pop(false)',
      (tester) async {
        await usePortraitSurface(tester);
        when(
          () => mockRepo.linkCustomTokenProviderArm(
            targetProvider: any(named: 'targetProvider'),
          ),
        ).thenAnswer(
          (_) async => const Result<User>.failure(
            ReauthenticationRequiredException(),
          ),
        );

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
          () => mockRepo.linkCustomTokenProviderArm(
            targetProvider: AccountProvider.kakao,
          ),
        ).called(1);
        // WR-02: 더 이상 silent stuck sheet 가 아니라 reauth 안내 SnackBar.
        expect(
          find.text('For security, please sign in again and retry.'),
          findsOneWidget,
        );
        // reauth 는 sheet 닫고 /login 라우팅 (초기 location 도 /login).
        expect(find.byType(AccountLinkingSheet), findsNothing);
      },
    );
  });

  group('T7 — WR-02: Custom Token 기타 실패 → user-visible SnackBar + sheet 유지', () {
    testWidgets(
      'linkCustomTokenProviderArm → AccountAlreadyLinked → '
      'errorAccountExistsWithUnknownProvider SnackBar (stuck sheet 방지)',
      (tester) async {
        await usePortraitSurface(tester);
        when(
          () => mockRepo.linkCustomTokenProviderArm(
            targetProvider: any(named: 'targetProvider'),
          ),
        ).thenAnswer(
          (_) async => const Result<User>.failure(AccountAlreadyLinked()),
        );

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
          () => mockRepo.linkCustomTokenProviderArm(
            targetProvider: AccountProvider.kakao,
          ),
        ).called(1);
        // WR-02: 기타 실패도 silent 가 아니라 user-visible 안내 SnackBar.
        expect(
          find.text(
            'This email is already registered with another sign-in method. '
            'Please sign in with the method you originally used.',
          ),
          findsOneWidget,
        );
        // 기타 실패는 sheet 유지 (재시도 가능 — naver graceful 와 동일 시맨틱).
        expect(find.byType(AccountLinkingSheet), findsOneWidget);
      },
    );
  });

  group('T5 — viewport: 좁은 화면 ensureVisible 후 tap', () {
    testWidgets('좁은 viewport(320x560) → Custom Token 버튼 ensureVisible 후 link 호출', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(320, 560));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      when(
        () => mockRepo.linkCustomTokenProviderArm(
          targetProvider: any(named: 'targetProvider'),
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

      await tester.tap(find.byType(BrandedSocialButton).first);
      await settleSheetEntrance(tester);
      expect(find.byType(AccountLinkingSheet), findsOneWidget);

      final sheetButton = find.descendant(
        of: find.byType(AccountLinkingSheet),
        matching: find.byType(BrandedSocialButton),
      );
      await tester.ensureVisible(sheetButton);
      await tester.pump();
      await tester.tap(sheetButton);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();

      verify(
        () => mockRepo.linkCustomTokenProviderArm(
          targetProvider: AccountProvider.kakao,
        ),
      ).called(1);
    });
  });
}
