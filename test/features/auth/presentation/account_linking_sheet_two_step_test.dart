// ignore_for_file: lines_longer_than_80_chars
//
// Phase 16 Plan 16-19 Task 2/3 — AccountLinkingSheet 2단계 reactive 플로우
// 회귀 테스트 (**hook 미주입 · 실제 repository 경로**).
//
// **CR-02 리뷰 요구사항 근거:** 16-REVIEW-FIX.md § Skipped Issues 의
// "hook 주입으로 repository 를 우회하는 테스트" anchor 에 대응해, 본 파일은
// `onExistingProviderSignIn` 을 **한 건도 주입하지 않고** `authRepositoryProvider`
// override 만으로 시트 → repository 경로를 실제로 통과시킨다.
//
// 역할 분담:
//   - 본 파일 (TS1~TS7) — 실 repository 경로 (hook 주입 0).
//   - account_linking_sheet_custom_token_test.dart — hook seam 계약 (주입 O).
//
// 7 behavior (mockup surface-a-two-step-reactive.md 경로 A/B/C/D):
//   TS1: CT↔CT end-to-end — 서버 already-exists(existingProvider=kakao,
//        pendingCredential 부재) → 시트 CTA 탭 → signInWithExistingProvider
//        1회 호출 + linkCustomTokenProviderArm verifyNever (경로 B)
//   TS2: 성공 후속 — 시트 닫힘 + 안내 SnackBar + /home 라우팅
//   TS3: 취소(null) — 시트 유지 + 네비게이션 0
//   TS4: 실패 graceful (A-16-19-01 익명 caller 재충돌) — 실패 SnackBar +
//        시트 유지 + 네비게이션 0 + 예외 전파 0
//   TS4b (WR-01, 2차·4차 리뷰): 실패 문구가 순환 안내
//        (errorAccountExistsWithUnknownProvider = "처음 가입한 방식으로 다시
//        로그인해 주세요") 로 collapse 되지 않고 transient / 결정적 실패
//        (A-16-19-01 익명 caller 재충돌) / 그 외로 분리된다 — 결정적 실패에
//        "잠시 후 다시 시도" 어휘가 붙지 않음을 함께 잠근다
//   TS5: native 회귀 (A1) — pendingCredential 존재 시 linkPendingNativeCredential
//        호출 + signInWithExistingProvider verifyNever (경로 A 변경 0)
//   TS6: naver 기존 — 과거 graceful 차단 분기 제거 확인 (경로 B 정상 수행)
//   TS7: email 기존 — repository 호출 0 + /login 라우팅 (경로 C 변경 0)

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

/// client-side `account-exists-with-different-credential` 이 보존하는 native
/// pending credential 대역 (경로 A 진입 조건).
const Object _kPendingCredential = Object();

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

  /// LoginScreen 을 GoRouter 가 감싸는 harness.
  ///
  /// **hook 주입 0** — LoginScreen 은 pendingCredential 만 전달하므로 시트는
  /// `authRepositoryProvider` 를 직접 read 한다 (CR-02 요구사항).
  Widget buildHarness({
    required AccountProvider existingProvider,
    Object? pendingCredential,
  }) {
    when(() => mockRepo.signInWithKakao()).thenAnswer(
      (_) async => Result<User>.failure(
        AccountExistsWithDifferentCredential(
          email: 'collide@example.com',
          existingProvider: existingProvider,
          pendingCredential: pendingCredential,
        ),
      ),
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
        activeStrategiesProvider(
          const Locale('en'),
        ).overrideWithValue(const <AuthStrategy>[KakaoAuthStrategy()]),
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

  /// 충돌 → 시트 노출까지 진행한다 (login screen 의 Kakao 버튼 탭).
  Future<void> openSheet(
    WidgetTester tester, {
    required AccountProvider existingProvider,
    Object? pendingCredential,
  }) async {
    await usePortraitSurface(tester);
    await tester.pumpWidget(
      buildHarness(
        existingProvider: existingProvider,
        pendingCredential: pendingCredential,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byType(BrandedSocialButton).first);
    await settleSheetEntrance(tester);
    expect(find.byType(AccountLinkingSheet), findsOneWidget);
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

  /// step 1 로그인 성공 응답 fixture.
  Result<User> successResult() => Result<User>.success(
    User(
      uid: 'u1',
      email: 'collide@example.com',
      emailVerified: true,
      createdAt: DateTime.utc(2026, 1, 1),
      providerIds: const ['kakao'],
    ),
  );

  group('TS1 — CT↔CT end-to-end (경로 B, hook 미주입)', () {
    testWidgets(
      '서버 already-exists(kakao) 시트 CTA 탭 → signInWithExistingProvider 1회 + '
      'linkCustomTokenProviderArm verifyNever',
      (tester) async {
        when(
          () => mockRepo.signInWithExistingProvider(
            provider: any(named: 'provider'),
          ),
        ).thenAnswer((_) async => successResult());
        when(
          () => mockRepo.linkCustomTokenProviderArm(
            targetProvider: any(named: 'targetProvider'),
          ),
        ).thenAnswer((_) async => null);

        await openSheet(tester, existingProvider: AccountProvider.kakao);
        await tapSheetCta(tester);

        verify(
          () => mockRepo.signInWithExistingProvider(
            provider: AccountProvider.kakao,
          ),
        ).called(1);
        verifyNever(
          () => mockRepo.linkCustomTokenProviderArm(
            targetProvider: any(named: 'targetProvider'),
          ),
        );
      },
    );
  });

  group('TS2 — 성공 후속 (시트 닫힘 + 안내 SnackBar + /home)', () {
    testWidgets(
      'step 1 성공 → 시트 pop + accountLinkingSignInThenLinkHint SnackBar + /home',
      (tester) async {
        when(
          () => mockRepo.signInWithExistingProvider(
            provider: any(named: 'provider'),
          ),
        ).thenAnswer((_) async => successResult());

        await openSheet(tester, existingProvider: AccountProvider.kakao);
        await tapSheetCta(tester);
        await tester.pump(const Duration(seconds: 1));

        expect(find.byType(AccountLinkingSheet), findsNothing);
        expect(
          find.text(
            'Signed in with your Kakao account. You can add other sign-in '
            'methods in Settings > Link an account.',
          ),
          findsOneWidget,
        );
        expect(find.text('HOME'), findsOneWidget);
      },
    );
  });

  group('TS3 — 취소 (경로 D silent no-op)', () {
    testWidgets('step 1 null 반환 → 시트 유지 + 네비게이션 0', (tester) async {
      when(
        () => mockRepo.signInWithExistingProvider(
          provider: any(named: 'provider'),
        ),
      ).thenAnswer((_) async => null);

      await openSheet(tester, existingProvider: AccountProvider.kakao);
      await tapSheetCta(tester);
      await tester.pump(const Duration(seconds: 1));

      expect(find.byType(AccountLinkingSheet), findsOneWidget);
      expect(find.text('HOME'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });

  group('TS4 — 실패 graceful (경로 D, A-16-19-01 익명 caller 재충돌)', () {
    testWidgets(
      'Failure(AccountExistsWithDifferentCredential) → 실패 SnackBar + 시트 유지 + '
      '네비게이션 0 + 예외 전파 0',
      (tester) async {
        when(
          () => mockRepo.signInWithExistingProvider(
            provider: any(named: 'provider'),
          ),
        ).thenAnswer(
          (_) async => const Result<User>.failure(
            AccountExistsWithDifferentCredential(
              email: 'collide@example.com',
              existingProvider: AccountProvider.kakao,
            ),
          ),
        );

        await openSheet(tester, existingProvider: AccountProvider.kakao);
        await tapSheetCta(tester);
        await tester.pump(const Duration(seconds: 1));

        // WR-01 (4차 리뷰): 순환 안내도, "잠시 후 다시 시도" 도 아닌
        // 결정적 실패 전용 문구 (재시도 무한 왕복 차단).
        expect(
          find.text(
            "You're browsing as a guest, so this existing account can't be "
            'signed in here. Please use another sign-in method below.',
          ),
          findsOneWidget,
        );
        // 재시도 어휘 미노출 — 이 실패는 재시도로 해소되지 않는다.
        expect(find.textContaining('try again later'), findsNothing);
        expect(find.byType(AccountLinkingSheet), findsOneWidget);
        expect(find.text('HOME'), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  });

  // WR-01 (2차 리뷰) — step 1 실패를 errorAccountExistsWithUnknownProvider 로
  // collapse 하면, 사용자는 바로 그 순간 시트가 지목한 "처음 가입한 방식" 으로
  // 로그인을 시도해 실패한 상태이므로 지시가 자기 자신을 가리키는 순환이
  // 된다. 프로젝트가 이미 한 번 진단하고 고친 collapse 패턴의 재발 방지.
  group('TS4b — WR-01: step 1 실패 문구 분리 (순환 안내 회귀 잠금)', () {
    /// step 1 실패 시 순환 안내 문구가 노출되지 않음을 단언한다.
    void expectNoCircularGuidance(WidgetTester tester) {
      expect(
        find.text(
          'This email is already registered with another sign-in method. '
          'Please sign in with the method you originally used.',
        ),
        findsNothing,
      );
    }

    testWidgets(
      'Failure(NoInternetConnection) → transient 문구 (재시도 유도) + 순환 안내 0',
      (tester) async {
        when(
          () => mockRepo.signInWithExistingProvider(
            provider: any(named: 'provider'),
          ),
        ).thenAnswer(
          (_) async => const Result<User>.failure(NoInternetConnection()),
        );

        await openSheet(tester, existingProvider: AccountProvider.kakao);
        await tapSheetCta(tester);
        await tester.pump(const Duration(seconds: 1));

        expect(
          find.text(
            "Couldn't sign in due to a network or service error. "
            'Please try again later.',
          ),
          findsOneWidget,
        );
        expectNoCircularGuidance(tester);
        expect(find.byType(AccountLinkingSheet), findsOneWidget);
        expect(find.text('HOME'), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('Failure(TooManyRequests) → transient 문구 (동일 arm)', (
      tester,
    ) async {
      when(
        () => mockRepo.signInWithExistingProvider(
          provider: any(named: 'provider'),
        ),
      ).thenAnswer((_) async => const Result<User>.failure(TooManyRequests()));

      await openSheet(tester, existingProvider: AccountProvider.kakao);
      await tapSheetCta(tester);
      await tester.pump(const Duration(seconds: 1));

      expect(
        find.text(
          "Couldn't sign in due to a network or service error. "
          'Please try again later.',
        ),
        findsOneWidget,
      );
      expectNoCircularGuidance(tester);
    });

    // 4차 WR-01 — 이 경로의 *지배적* 실패(A-16-19-01 익명 caller 재충돌)가
    // transient / catch-all arm 으로 되돌아가면 "잠시 후 다시 시도" 안내가
    // 붙어 무한 왕복이 된다. 전용 arm 을 잠근다.
    testWidgets(
      'Failure(AccountExistsWithDifferentCredential) → 결정적 실패 전용 문구 + '
      '재시도 어휘 0 + 순환 안내 0',
      (tester) async {
        when(
          () => mockRepo.signInWithExistingProvider(
            provider: any(named: 'provider'),
          ),
        ).thenAnswer(
          (_) async => const Result<User>.failure(
            AccountExistsWithDifferentCredential(
              email: 'collide@example.com',
              existingProvider: AccountProvider.kakao,
            ),
          ),
        );

        await openSheet(tester, existingProvider: AccountProvider.kakao);
        await tapSheetCta(tester);
        await tester.pump(const Duration(seconds: 1));

        expect(
          find.text(
            "You're browsing as a guest, so this existing account can't be "
            'signed in here. Please use another sign-in method below.',
          ),
          findsOneWidget,
        );
        // "Please try again later." 계열 (transient / catch-all) 미노출.
        expect(find.textContaining('try again later'), findsNothing);
        expectNoCircularGuidance(tester);
        expect(find.byType(AccountLinkingSheet), findsOneWidget);
      },
    );

    testWidgets('Failure(UnknownException) → catch-all 문구 + 순환 안내 0', (
      tester,
    ) async {
      when(
        () => mockRepo.signInWithExistingProvider(
          provider: any(named: 'provider'),
        ),
      ).thenAnswer((_) async => const Result<User>.failure(UnknownException()));

      await openSheet(tester, existingProvider: AccountProvider.kakao);
      await tapSheetCta(tester);
      await tester.pump(const Duration(seconds: 1));

      expect(
        find.text("Couldn't sign you in. Please try again later."),
        findsOneWidget,
      );
      expectNoCircularGuidance(tester);
      expect(find.byType(AccountLinkingSheet), findsOneWidget);
    });
  });

  group('TS5 — native 회귀 (경로 A, A1 시나리오 변경 0)', () {
    testWidgets(
      'pendingCredential 존재 native 충돌 → linkPendingNativeCredential 호출 + '
      'signInWithExistingProvider verifyNever',
      (tester) async {
        when(
          () => mockRepo.linkPendingNativeCredential(
            existingProvider: any(named: 'existingProvider'),
            pendingCredential: any(named: 'pendingCredential'),
          ),
        ).thenAnswer((_) async => successResult());
        when(
          () => mockRepo.signInWithExistingProvider(
            provider: any(named: 'provider'),
          ),
        ).thenAnswer((_) async => successResult());

        await openSheet(
          tester,
          existingProvider: AccountProvider.google,
          pendingCredential: _kPendingCredential,
        );
        await tapSheetCta(tester);

        verify(
          () => mockRepo.linkPendingNativeCredential(
            existingProvider: AccountProvider.google,
            pendingCredential: any(named: 'pendingCredential'),
          ),
        ).called(1);
        verifyNever(
          () => mockRepo.signInWithExistingProvider(
            provider: any(named: 'provider'),
          ),
        );
      },
    );
  });

  group('TS6 — naver 기존 provider (graceful 차단 분기 제거 확인)', () {
    testWidgets(
      'existingProvider=naver CTA 탭 → signInWithExistingProvider(naver) 호출',
      (tester) async {
        when(
          () => mockRepo.signInWithExistingProvider(
            provider: any(named: 'provider'),
          ),
        ).thenAnswer((_) async => successResult());

        await openSheet(tester, existingProvider: AccountProvider.naver);
        await tapSheetCta(tester);

        verify(
          () => mockRepo.signInWithExistingProvider(
            provider: AccountProvider.naver,
          ),
        ).called(1);
      },
    );
  });

  group('TS7 — email 기존 provider (경로 C 변경 0)', () {
    testWidgets('existingProvider=email CTA 탭 → repository 호출 0 + /login 유지', (
      tester,
    ) async {
      when(
        () => mockRepo.signInWithExistingProvider(
          provider: any(named: 'provider'),
        ),
      ).thenAnswer((_) async => successResult());

      await usePortraitSurface(tester);
      await tester.pumpWidget(
        buildHarness(existingProvider: AccountProvider.email),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byType(BrandedSocialButton).first);
      await settleSheetEntrance(tester);
      expect(find.byType(AccountLinkingSheet), findsOneWidget);

      // email 은 BrandedSocialButton 이 아닌 FilledButton fallback 이다.
      final emailCta = find.descendant(
        of: find.byType(AccountLinkingSheet),
        matching: find.byType(FilledButton),
      );
      await tester.ensureVisible(emailCta);
      await tester.pump();
      await tester.tap(emailCta);
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      verifyNever(
        () => mockRepo.signInWithExistingProvider(
          provider: any(named: 'provider'),
        ),
      );
      verifyNever(
        () => mockRepo.linkPendingNativeCredential(
          existingProvider: any(named: 'existingProvider'),
          pendingCredential: any(named: 'pendingCredential'),
        ),
      );
      expect(find.byType(AccountLinkingSheet), findsNothing);
      expect(find.text('HOME'), findsNothing);
      expect(find.byType(LoginScreen), findsOneWidget);
    });
  });
}
