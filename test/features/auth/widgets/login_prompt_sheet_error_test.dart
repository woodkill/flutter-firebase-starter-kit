// ignore_for_file: lines_longer_than_80_chars
//
// quick 260910-uff — LoginPromptSheet(Surface D) 소셜 실패 피드백 회귀 가드.
//
// 4 behavior:
//   A: 일반 AppException 실패 → 소셜 버튼 아래 FormErrorBanner inline + D 유지
//   B: existingProvider 有 충돌 → AccountLinkingSheet 가 D **위에** 스택
//   C: existingProvider 無 충돌 → 연결 시트 미노출 + inline 배너 fallback
//   D: 연결 성공(true) → 연결 시트 + D 모두 닫히고 /home 착지

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
import 'package:flutter_starter_kit/features/auth/presentation/_widgets/login_prompt_sheet.dart';
import 'package:flutter_starter_kit/features/auth/presentation/_widgets/social_sign_in_section.dart';
import 'package:flutter_starter_kit/l10n/generated/app_localizations.dart';

/// [AuthRepository] 를 mocktail 로 대체하기 위한 Mock.
class _MockAuthRepository extends Mock implements AuthRepository {}

/// client-side `account-exists-with-different-credential` 이 보존하는 native
/// pending credential 대역 (AccountLinkingSheet 경로 A 진입 조건).
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
  /// default 800x600 landscape 밖에 위치해 hit-test 가 실패하는 함정 회피
  /// (memory feedback_test_viewport_ensure_visible).
  Future<void> usePortraitSurface(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(400, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
  }

  /// modal bottom sheet entrance 애니메이션을 settle 시킨다 —
  /// `pumpAndSettle` 은 BrandedSocialButton 비동기 자산 디코딩으로 hang 될 수
  /// 있어 명시적 다단계 pump 로 대체한다.
  Future<void> settleSheetEntrance(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(seconds: 1));
  }

  /// 트리거 버튼 route + [AppRoutes.home] sentinel 2 route harness 를 [tester]
  /// 로 pump 한다.
  ///
  /// [ProviderScope] 는 `pumpWidget` 의 직접 인자다 (riverpod_lint root 판정).
  ///
  /// [onGoogleSignIn] 이 `signInWithGoogle` 결과를 주입한다 — Google 단일
  /// strategy 로 override 해 탭 대상 모호성을 제거한다.
  ///
  /// 트리거는 `/gated` 에 둔다 — [AppRoutes.home] 이 `/` 라서 트리거를 `/` 에
  /// 두면 home sentinel 과 경로가 충돌해 연결 성공 후 착지 화면을 구분할 수
  /// 없다.
  Future<void> pumpHarness(
    WidgetTester tester, {
    required Result<User>? Function() onGoogleSignIn,
  }) async {
    when(
      () => mockRepo.signInWithGoogle(),
    ).thenAnswer((_) async => onGoogleSignIn());
    final router = GoRouter(
      initialLocation: '/gated',
      routes: [
        GoRoute(
          path: '/gated',
          builder: (_, _) => Scaffold(
            body: Builder(
              builder: (context) => Center(
                child: ElevatedButton(
                  onPressed: () => showLoginPromptSheet(context),
                  child: const Text('Trigger'),
                ),
              ),
            ),
          ),
        ),
        GoRoute(
          path: AppRoutes.home,
          builder: (_, _) => const Scaffold(body: Text('HOME')),
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
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          routerConfig: router,
        ),
      ),
    );
  }

  /// 트리거 버튼을 탭해 [LoginPromptSheet] 를 연다.
  Future<void> openPromptSheet(WidgetTester tester) async {
    await tester.tap(find.text('Trigger'));
    await tester.pumpAndSettle();
  }

  /// D 안 소셜 버튼(Google 단일)을 탭하고 실패 결과를 settle 한다.
  Future<void> tapSocialButton(WidgetTester tester) async {
    await tester.tap(find.byType(BrandedSocialButton).first);
    await settleSheetEntrance(tester);
  }

  /// D 의 소셜 섹션이 소유한 inline 배너 인스턴스를 꺼낸다.
  FormErrorBanner readInlineBanner(WidgetTester tester) {
    return tester.widget<FormErrorBanner>(
      find.descendant(
        of: find.byType(SocialSignInSection),
        matching: find.byType(FormErrorBanner),
      ),
    );
  }

  group('A — 일반 실패 → 소셜 버튼 아래 inline 배너 + D 유지', () {
    testWidgets('NoInternetConnection → FormErrorBanner 에 해석된 문구가 뜬다', (
      tester,
    ) async {
      await usePortraitSurface(tester);
      await pumpHarness(
        tester,
        onGoogleSignIn: () =>
            const Result<User>.failure(NoInternetConnection()),
      );
      await openPromptSheet(tester);
      await tapSocialButton(tester);

      expect(readInlineBanner(tester).exception, isA<NoInternetConnection>());
      // 문구는 ARB + resolveExceptionMessage 소유 — 하드코딩 대신 l10n 경유.
      final l10n = AppLocalizations.of(
        tester.element(find.byType(LoginPromptSheet)),
      );
      expect(find.text(l10n.errorNoInternet), findsOneWidget);
      // 실패는 sheet 를 닫지 않는다 — 사용자는 현재 화면을 잃지 않는다.
      expect(find.byType(LoginPromptSheet), findsOneWidget);
      expect(find.byType(AccountLinkingSheet), findsNothing);
    });
  });

  group('B — existingProvider 有 → 연결 시트가 D 위에 스택', () {
    testWidgets('AccountExistsWithDifferentCredential → 연결 시트 + D 동시 존재', (
      tester,
    ) async {
      await usePortraitSurface(tester);
      await pumpHarness(
        tester,
        onGoogleSignIn: () => const Result<User>.failure(
          AccountExistsWithDifferentCredential(
            email: 'collide@example.com',
            existingProvider: AccountProvider.google,
            pendingCredential: _kPendingCredential,
          ),
        ),
      );
      await openPromptSheet(tester);
      await tapSocialButton(tester);

      expect(find.byType(AccountLinkingSheet), findsOneWidget);
      // D 는 연결 시트 **아래에** 그대로 mount 되어 있다 (취소 시 복귀 지점).
      expect(find.byType(LoginPromptSheet), findsOneWidget);
      // 충돌은 연결 시트가 담당하므로 inline 배너에는 싣지 않는다.
      expect(
        readInlineBanner(tester).exception,
        isNot(isA<AccountExistsWithDifferentCredential>()),
      );
    });
  });

  group('C — existingProvider 無 → inline fallback (R2 동형)', () {
    testWidgets('existingProvider == null → 연결 시트 미노출 + 배너 inline', (
      tester,
    ) async {
      await usePortraitSurface(tester);
      await pumpHarness(
        tester,
        onGoogleSignIn: () => const Result<User>.failure(
          AccountExistsWithDifferentCredential(email: 'old@example.com'),
        ),
      );
      await openPromptSheet(tester);
      await tapSocialButton(tester);

      expect(find.byType(AccountLinkingSheet), findsNothing);
      expect(
        readInlineBanner(tester).exception,
        isA<AccountExistsWithDifferentCredential>(),
      );
      expect(find.byType(LoginPromptSheet), findsOneWidget);
    });
  });

  group('D — 연결 성공 → 연결 시트 + D 정리', () {
    testWidgets('link 성공(true) → 두 modal 모두 닫히고 /home 착지', (tester) async {
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
            pendingCredential: _kPendingCredential,
          ),
        ),
      );
      await openPromptSheet(tester);
      await tapSocialButton(tester);
      expect(find.byType(AccountLinkingSheet), findsOneWidget);

      final sheetButton = find.descendant(
        of: find.byType(AccountLinkingSheet),
        matching: find.byType(BrandedSocialButton),
      );
      // 연결 시트 CTA 는 fold 밖일 수 있다 — ensureVisible 후 tap.
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
      expect(find.byType(AccountLinkingSheet), findsNothing);
      // 홈 위에 떠 있는 modal 이 남지 않는다.
      expect(find.byType(LoginPromptSheet), findsNothing);
      expect(find.text('HOME'), findsOneWidget);
    });
  });
}
