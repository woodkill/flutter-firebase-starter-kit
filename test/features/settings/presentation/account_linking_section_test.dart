// ignore_for_file: lines_longer_than_80_chars
//
// Phase 16 Plan 16-11 Task 1 — AccountLinkingSection widget test (AL1~AL8).
//
// 검증 surface (Surface D mockup — email EXCLUDE / 활성 소셜 - linked 규칙):
// - AL1 available 규칙: linkedProviders=[google] → google 버튼 미노출 +
//   나머지 활성 소셜 provider "연결" 버튼 노출. email 버튼은 절대 없음.
// - AL2 native link 성공: Apple "연결" tap → linkAppleCredential 호출 →
//   accountLinkingSucceededSnackbar 노출.
// - AL3 Custom Token link 성공: LINE "연결" tap →
//   linkCustomTokenProviderArm(targetProvider: line) 호출 → 성공 snackbar.
// - AL4 reauth gate: ReauthenticationRequiredException → authReauthRequired
//   SnackBar + 재로그인 라우팅 (withdrawal reauth gate D-06 mirror).
// - AL5 already-linked: AccountAlreadyLinked → graceful SnackBar (크래시 0).
// - AL6 사용자 취소 (null) → no-op (snackbar 0, 버튼 유지).
// - AL7 viewport: below-fold 버튼 tester.ensureVisible 후 tap.
// - AL8 빈 available set: 모든 활성 소셜 provider link 완료 → 섹션 미노출.
//
// Phase 16 G-16-A6-2 추가 (실패 원인별 문구 분기 — collapse 해소):
// - AL9 emailInUse / AL10 transientFailure / AL11 failed: outcome 별 en
//   verbatim SnackBar 문구 단언.
// - AL12 (Phase 16.9 D-12): naver 후보 노출 · 순서 kakao < naver < line ·
//   tap → linkNaverProviderArm + 성공 SnackBar.
// - AL14~AL17 (Phase 16.9): naver 연결 후 버튼 소멸 · alreadyLinked 문구 ·
//   reauth 라우팅 · reactive 2단계 도착지(가입 kakao 사용자의 「네이버 연결」).
// - AL13 collapse 재발 방지: 5 문구 상호 비동등 + 이전 collapse 문구 미사용.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';

import 'package:flutter_starter_kit/core/auth/auth_strategies_registry.dart';
import 'package:flutter_starter_kit/core/auth/auth_strategy.dart';
import 'package:flutter_starter_kit/core/auth/provider_id.dart';
import 'package:flutter_starter_kit/core/auth/strategies/apple_auth_strategy.dart';
import 'package:flutter_starter_kit/core/auth/strategies/facebook_auth_strategy.dart';
import 'package:flutter_starter_kit/core/auth/strategies/google_auth_strategy.dart';
import 'package:flutter_starter_kit/core/auth/strategies/kakao_auth_strategy.dart';
import 'package:flutter_starter_kit/core/auth/strategies/line_auth_strategy.dart';
import 'package:flutter_starter_kit/core/auth/strategies/naver_auth_strategy.dart';
import 'package:flutter_starter_kit/core/error/app_exception.dart';
import 'package:flutter_starter_kit/core/error/result.dart';
import 'package:flutter_starter_kit/core/router/app_routes.dart';
import 'package:flutter_starter_kit/core/theme/app_theme.dart';
import 'package:flutter_starter_kit/features/auth/data/auth_repository.dart';
import 'package:flutter_starter_kit/features/auth/domain/user.dart';
import 'package:flutter_starter_kit/features/settings/presentation/_widgets/account_linking_section.dart';
import 'package:flutter_starter_kit/l10n/generated/app_localizations.dart';

class _MockAuthRepository extends Mock implements AuthRepository {}

// G-16-A6-2 — Surface D 실패 원인별 en verbatim 문구 (app_en.arb 와 1:1).
const _alreadyLinkedText =
    'This sign-in method is already linked to another account. '
    'Unlink it first, then try again.';
const _alreadyLinkedHereText =
    'This account is already linked to that sign-in method.';
const _emailInUseText = 'This email is already in use by another account.';
const _transientText =
    "Couldn't link due to a network or service error. Please try again later.";
const _unknownFailureText =
    "Couldn't link your account. Please try again later.";
// unsupported 는 email 전용 (Surface D EXCLUDE — 후보에 없어 방어적 분기).
const _unsupportedEmailText =
    "Linking a Email / Password account isn't supported yet.";

/// 테스트용 User factory.
User _testUser({required List<String> providerIds}) {
  return User(
    uid: 'uid-1',
    email: 'me@example.com',
    emailVerified: true,
    createdAt: DateTime.utc(2026, 1, 1),
    providerIds: providerIds,
  );
}

/// 활성 소셜 Strategy 6종 전부 (정적 + RC overlay 대신 직접 주입) — login/
/// signup 의 activeStrategiesProvider 결과를 결정적으로 고정한다.
const _allStrategies = <AuthStrategy>[
  GoogleAuthStrategy(),
  AppleAuthStrategy(),
  FacebookAuthStrategy(),
  KakaoAuthStrategy(),
  NaverAuthStrategy(),
  LineAuthStrategy(),
];

/// AccountLinkingSection 을 GoRouter 내에서 pump 한다 (reauth push 검증용).
///
/// [strategies] 는 `activeStrategiesProvider` 결과다 — 기본값 6종, Phase 17.3
/// 처음부터 off 테스트는 일부 · 빈 목록을 넘긴다.
Future<GoRouter> _pumpSection(
  WidgetTester tester, {
  required User user,
  required AuthRepository repo,
  Locale locale = const Locale('en'),
  List<AuthStrategy> strategies = _allStrategies,
}) async {
  final router = GoRouter(
    initialLocation: AppRoutes.home,
    routes: [
      GoRoute(
        path: AppRoutes.home,
        builder: (context, state) => const Scaffold(
          body: SingleChildScrollView(child: AccountLinkingSection()),
        ),
      ),
      GoRoute(
        path: AppRoutes.login,
        builder: (context, state) => const Scaffold(body: Text('LOGIN ROUTE')),
      ),
    ],
  );

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        currentUserProvider.overrideWith((ref) => user),
        authRepositoryProvider.overrideWithValue(repo),
        activeStrategiesProvider.overrideWith((ref) => strategies),
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
  await tester.pumpAndSettle();
  return router;
}

void main() {
  late _MockAuthRepository repo;

  setUpAll(() {
    registerFallbackValue(AccountProvider.google);
  });

  setUp(() {
    repo = _MockAuthRepository();
  });

  group('Phase 16 16-11 Task 1 — AccountLinkingSection', () {
    testWidgets(
      'AL1 available 규칙 — linkedProviders=[google.com] → google 미노출 + email 버튼 절대 없음',
      (tester) async {
        await _pumpSection(
          tester,
          user: _testUser(providerIds: const <String>['google.com']),
          repo: repo,
        );

        // 섹션 heading 노출 (en).
        expect(find.text('Link an account'), findsOneWidget);
        // google 은 이미 linked → "Link Google" 버튼 미노출.
        expect(find.text('Link Google'), findsNothing);
        // 다른 활성 소셜 provider 의 "연결" 버튼 노출 (예: Apple).
        expect(find.text('Link Apple'), findsOneWidget);
        // email 버튼 절대 없음 (email EXCLUDE).
        expect(find.text('Link Email / Password'), findsNothing);
        expect(find.textContaining('Email'), findsNothing);
      },
    );

    testWidgets(
      'AL2 native 성공 — Apple 연결 tap → linkAppleCredential + 성공 snackbar',
      (tester) async {
        final user = _testUser(providerIds: const <String>['google.com']);
        when(
          () => repo.linkAppleCredential(),
        ).thenAnswer((_) async => Result.success(user));

        await _pumpSection(tester, user: user, repo: repo);

        final btn = find.text('Link Apple');
        await tester.ensureVisible(btn);
        await tester.tap(btn);
        await tester.pumpAndSettle();

        verify(() => repo.linkAppleCredential()).called(1);
        // 성공 snackbar (en, provider 라벨 주입): "Linked your Apple account."
        expect(find.text('Linked your Apple account.'), findsOneWidget);
      },
    );

    testWidgets(
      'AL3 Custom Token 성공 — LINE 연결 tap → linkCustomTokenProviderArm(line)',
      (tester) async {
        final user = _testUser(providerIds: const <String>['google.com']);
        when(
          () => repo.linkCustomTokenProviderArm(
            targetProvider: any(named: 'targetProvider'),
          ),
        ).thenAnswer((_) async => Result.success(user));

        await _pumpSection(tester, user: user, repo: repo);

        final btn = find.text('Link LINE');
        await tester.ensureVisible(btn);
        await tester.tap(btn);
        await tester.pumpAndSettle();

        verify(
          () => repo.linkCustomTokenProviderArm(
            targetProvider: AccountProvider.line,
          ),
        ).called(1);
        expect(find.text('Linked your LINE account.'), findsOneWidget);
      },
    );

    testWidgets(
      'AL4 reauth gate — ReauthenticationRequired → authReauthRequired '
      'SnackBar + /login 라우팅',
      (tester) async {
        final user = _testUser(providerIds: const <String>['google.com']);
        when(() => repo.linkAppleCredential()).thenAnswer(
          (_) async =>
              const Result.failure(ReauthenticationRequiredException()),
        );

        final router = await _pumpSection(tester, user: user, repo: repo);

        final btn = find.text('Link Apple');
        await tester.ensureVisible(btn);
        await tester.tap(btn);
        await tester.pumpAndSettle();

        // WR-05 (4차 리뷰): 문구는 도메인 중립 키 authReauthRequired 가 낸다.
        // withdrawalReauthRequired 와 verbatim 동일하므로 이 단언만으로는 키
        // 교체가 잠기지 않는다 — 키 자체의 회귀 잠금은 IN-05 소스 sentinel
        // (account_linking_reauth_key_sentinel_test.dart) 이 담당한다.
        expect(
          find.text('For security, please sign in again and retry.'),
          findsOneWidget,
        );
        // 재로그인 라우팅 — /login push (withdrawal D-06 reauth gate mirror).
        // push 후 /login 화면이 스택 top 으로 노출되는지 사용자 가시 truth 검증.
        expect(find.text('LOGIN ROUTE'), findsOneWidget);
        expect(
          router.routerDelegate.currentConfiguration.last.matchedLocation,
          AppRoutes.login,
        );
        // 260916-p8d: 재인증 push 는 재인증 표시가 붙은 로그인 location 이어야 한다.
        expect(
          AppRoutes.hasReauthMarker(router.state.uri),
          isTrue,
          reason:
              'R_EXTRA_G3_REAUTH_LOGIN_BOUNCE: 표시가 없으면 실제 앱 guard 분기 (6) 이 '
              'push 한 로그인 화면을 홈으로 튕긴다',
        );
      },
    );

    testWidgets(
      'AL5 already-linked — AccountAlreadyLinked → 전용 문구 SnackBar (크래시 0)',
      (tester) async {
        final user = _testUser(providerIds: const <String>['google.com']);
        when(
          () => repo.linkAppleCredential(),
        ).thenAnswer((_) async => const Result.failure(AccountAlreadyLinked()));

        await _pumpSection(tester, user: user, repo: repo);

        final btn = find.text('Link Apple');
        await tester.ensureVisible(btn);
        await tester.tap(btn);
        await tester.pumpAndSettle();

        // 크래시 0 + 성공 snackbar 미노출.
        expect(tester.takeException(), isNull);
        expect(find.text('Linked your Apple account.'), findsNothing);
        // G-16-A6-2: already-linked 전용 문구 (이메일 문구 아님).
        expect(find.byType(SnackBar), findsOneWidget);
        expect(find.text(_alreadyLinkedText), findsOneWidget);
      },
    );

    testWidgets('AL6 사용자 취소 (null) — no-op (snackbar 0, 버튼 유지)', (
      tester,
    ) async {
      final user = _testUser(providerIds: const <String>['google.com']);
      when(() => repo.linkAppleCredential()).thenAnswer((_) async => null);

      await _pumpSection(tester, user: user, repo: repo);

      final btn = find.text('Link Apple');
      await tester.ensureVisible(btn);
      await tester.tap(btn);
      await tester.pumpAndSettle();

      // snackbar 0 + 버튼 유지.
      expect(find.byType(SnackBar), findsNothing);
      expect(find.text('Link Apple'), findsOneWidget);
    });

    testWidgets('AL7 viewport — below-fold 버튼 ensureVisible 후 tap 가능', (
      tester,
    ) async {
      // linkedProviders 비어있음 → 모든 활성 소셜 버튼 노출 (긴 리스트).
      final user = _testUser(providerIds: const <String>[]);
      when(
        () => repo.linkCustomTokenProviderArm(
          targetProvider: any(named: 'targetProvider'),
        ),
      ).thenAnswer((_) async => Result.success(user));

      await _pumpSection(tester, user: user, repo: repo);

      // LINE 은 리스트 말단 (below-fold 가능) — ensureVisible 후 tap.
      final btn = find.text('Link LINE');
      await tester.ensureVisible(btn);
      await tester.tap(btn);
      await tester.pumpAndSettle();

      verify(
        () => repo.linkCustomTokenProviderArm(
          targetProvider: AccountProvider.line,
        ),
      ).called(1);
    });

    testWidgets('AL8 빈 available — 모든 활성 소셜 linked → 섹션 미노출', (tester) async {
      // 활성 소셜 6종 모두 linked (URI 3 + slug 3).
      final user = _testUser(
        providerIds: const <String>[
          'google.com',
          'apple.com',
          'facebook.com',
          'kakao',
          'naver',
          'line',
        ],
      );

      await _pumpSection(tester, user: user, repo: repo);

      // available 빈 set → heading 미노출 (섹션 미노출).
      expect(find.text('Link an account'), findsNothing);
    });
  });

  group('Phase 16 G-16-A6-2 — Surface D 실패 원인별 SnackBar 문구', () {
    /// Apple 연결 버튼을 tap 해 [failure] 실패 경로를 재현한다.
    Future<void> tapAppleWithFailure(
      WidgetTester tester,
      AppException failure,
    ) async {
      final user = _testUser(providerIds: const <String>['google.com']);
      when(
        () => repo.linkAppleCredential(),
      ).thenAnswer((_) async => Result<User>.failure(failure));

      await _pumpSection(tester, user: user, repo: repo);

      final btn = find.text('Link Apple');
      await tester.ensureVisible(btn);
      await tester.tap(btn);
      await tester.pumpAndSettle();
    }

    testWidgets('AL9 emailInUse — EmailAlreadyInUse → 이메일 중복 전용 문구', (
      tester,
    ) async {
      await tapAppleWithFailure(tester, const EmailAlreadyInUse());

      expect(find.text(_emailInUseText), findsOneWidget);
      expect(find.text(_alreadyLinkedText), findsNothing);
    });

    testWidgets('AL10 transientFailure — NoInternetConnection → 일시 오류 문구', (
      tester,
    ) async {
      await tapAppleWithFailure(tester, const NoInternetConnection());

      expect(find.text(_transientText), findsOneWidget);
      expect(find.text(_unknownFailureText), findsNothing);
    });

    testWidgets('AL11 failed — 미분류 예외 → catch-all 문구', (tester) async {
      await tapAppleWithFailure(tester, const UnknownException());

      expect(find.text(_unknownFailureText), findsOneWidget);
      expect(find.text(_transientText), findsNothing);
    });

    testWidgets(
      'T-17-LINK-02 appCheckFailed — AppCheckFailedException → ko errorAppCheckFailed SnackBar · 라우팅 0 · 재로그인 문구 0',
      (tester) async {
        // Phase 17 D-42 · D-43 — App Check 차단은 같은 화면에서 재시도한다.
        final ko = lookupAppLocalizations(const Locale('ko'));
        final user = _testUser(providerIds: const <String>['google.com']);
        when(() => repo.linkAppleCredential()).thenAnswer(
          (_) async => const Result<User>.failure(AppCheckFailedException()),
        );

        final router = await _pumpSection(
          tester,
          user: user,
          repo: repo,
          locale: const Locale('ko'),
        );

        final btn = find.text(
          ko.settingsLinkProviderCta(ko.authAccountProviderApple),
        );
        await tester.ensureVisible(btn);
        await tester.tap(btn);
        await tester.pumpAndSettle();

        expect(
          find.descendant(
            of: find.byType(SnackBar),
            matching: find.text(ko.errorAppCheckFailed),
          ),
          findsOneWidget,
        );
        expect(find.text(ko.authReauthRequired), findsNothing);
        expect(find.text(ko.settingsLinkFailedTransient), findsNothing);
        expect(find.text('LOGIN ROUTE'), findsNothing);
        expect(
          router.routerDelegate.currentConfiguration.last.matchedLocation,
          AppRoutes.home,
        );
      },
    );

    testWidgets(
      'AL12 (16.9 D-12) — naver 후보 노출 · 순서 kakao < naver < line · tap → linkNaverProviderArm',
      (tester) async {
        final user = _testUser(providerIds: const <String>['google.com']);
        when(
          () => repo.linkNaverProviderArm(),
        ).thenAnswer((_) async => Result.success(user));

        await _pumpSection(tester, user: user, repo: repo);

        final kakao = find.text('Link Kakao');
        final naver = find.text('Link Naver');
        final line = find.text('Link LINE');
        expect(find.text('Link Naver'), findsOneWidget);

        // Pitfall 7 — 후보가 늘어 fold 아래일 수 있으므로 세 버튼 모두
        // ensureVisible 로 렌더를 확정한 뒤, 같은 스크롤 위치에서 세 좌표를
        // 한꺼번에 읽어 비교한다 (ensureVisible 마다 스크롤이 옮겨질 수 있음).
        for (final finder in <Finder>[kakao, naver, line]) {
          await tester.ensureVisible(finder);
        }
        final kakaoY = tester.getTopLeft(kakao).dy;
        final naverY = tester.getTopLeft(naver).dy;
        final lineY = tester.getTopLeft(line).dy;
        expect(kakaoY < naverY, isTrue, reason: 'kakao < naver');
        expect(naverY < lineY, isTrue, reason: 'naver < line');

        final naverButton = find.text('Link Naver');
        await tester.ensureVisible(naverButton);
        await tester.tap(naverButton);
        await tester.pumpAndSettle();

        verify(() => repo.linkNaverProviderArm()).called(1);
        verifyNever(
          () => repo.linkCustomTokenProviderArm(
            targetProvider: any(named: 'targetProvider'),
          ),
        );
        expect(find.text('Linked your Naver account.'), findsOneWidget);
      },
    );

    // WR-04: `provider-already-linked` (이미 현재 계정에 연결) 와
    // `credential-already-in-use` (다른 계정이 사용 중) 는 의미가 정반대다.
    // 한 문구로 뭉개면 전자에는 "another account" 가 사실과 반대이고,
    // 후자에는 "unlink it first" 가 수행 불가능한 안내가 된다.
    testWidgets(
      'AL5b (WR-04) — ProviderAlreadyLinkedToThisAccount → alreadyLinkedHere 전용 문구',
      (tester) async {
        final user = _testUser(providerIds: const <String>['google.com']);
        when(() => repo.linkAppleCredential()).thenAnswer(
          (_) async =>
              const Result.failure(ProviderAlreadyLinkedToThisAccount()),
        );

        await _pumpSection(tester, user: user, repo: repo);

        final btn = find.text('Link Apple');
        await tester.ensureVisible(btn);
        await tester.tap(btn);
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(find.byType(SnackBar), findsOneWidget);
        expect(find.text(_alreadyLinkedHereText), findsOneWidget);
        // alreadyLinked ("다른 계정에 연결됨") 문구로 되돌아가지 않는다.
        expect(find.text(_alreadyLinkedText), findsNothing);
      },
    );

    testWidgets('AL13 collapse 재발 방지 — 실패 5 문구 + 미지원 문구 상호 비동등', (
      tester,
    ) async {
      // 5 문구가 서로 다른 문자열임을 한 곳에서 고정한다. 어느 두 outcome 이
      // 같은 문구로 되돌아가면(2026-09-07 A6 collapse) 즉시 FAIL.
      const messages = <String>[
        _alreadyLinkedText,
        // WR-04 — alreadyLinkedHere 는 alreadyLinked 와 의미가 정반대다.
        _alreadyLinkedHereText,
        _emailInUseText,
        _transientText,
        _unknownFailureText,
        _unsupportedEmailText,
      ];

      expect(messages.toSet().length, messages.length);

      // 이전 collapse 문구(errorAccountExistsWithUnknownProvider)와도 분리.
      const oldCollapsedText =
          'This email is already registered with another sign-in method. '
          'Please sign in with the method you originally used.';
      expect(messages, isNot(contains(oldCollapsedText)));

      // 실제 렌더 경로에서도 실패 문구가 collapse 문구를 쓰지 않는지 확인.
      await tapAppleWithFailure(tester, const AccountAlreadyLinked());
      expect(find.text(oldCollapsedText), findsNothing);
      expect(find.text(_alreadyLinkedText), findsOneWidget);
    });
  });

  group('Phase 16.9 — Surface D 「네이버 연결」', () {
    testWidgets('AL14 naver 연결 후 — providerIds 에 naver → 버튼 소멸', (
      tester,
    ) async {
      await _pumpSection(
        tester,
        user: _testUser(providerIds: const <String>['google.com', 'naver']),
        repo: repo,
      );

      expect(find.text('Link Naver'), findsNothing);
      // 섹션은 다른 후보로 계속 렌더된다 (섹션 통째 미노출 회귀 방지).
      expect(find.text('Link Apple'), findsOneWidget);
    });

    testWidgets('AL15 naver AccountAlreadyLinked → 「다른 계정에 연결됨」 문구', (
      tester,
    ) async {
      final user = _testUser(providerIds: const <String>['google.com']);
      when(
        () => repo.linkNaverProviderArm(),
      ).thenAnswer((_) async => const Result.failure(AccountAlreadyLinked()));

      await _pumpSection(tester, user: user, repo: repo);

      final btn = find.text('Link Naver');
      await tester.ensureVisible(btn);
      await tester.tap(btn);
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text(_alreadyLinkedText), findsOneWidget);
      // alreadyLinkedHere (「이미 이 계정에 연결됨」) 와 뒤바뀌지 않는다.
      expect(find.text(_alreadyLinkedHereText), findsNothing);
    });

    testWidgets('AL16 naver ReauthenticationRequired → 재로그인 라우팅', (
      tester,
    ) async {
      final user = _testUser(providerIds: const <String>['google.com']);
      when(() => repo.linkNaverProviderArm()).thenAnswer(
        (_) async => const Result.failure(ReauthenticationRequiredException()),
      );

      final router = await _pumpSection(tester, user: user, repo: repo);

      final btn = find.text('Link Naver');
      await tester.ensureVisible(btn);
      await tester.tap(btn);
      await tester.pumpAndSettle();

      expect(
        find.text('For security, please sign in again and retry.'),
        findsOneWidget,
      );
      expect(find.text('LOGIN ROUTE'), findsOneWidget);
      expect(AppRoutes.hasReauthMarker(router.state.uri), isTrue);
    });

    // D-07 reactive 연결성: kakao 가입자가 Naver 로 로그인하다 이메일 충돌로
    // 시트(경로 B) → kakao 로그인 뒤 안내 문구를 본다. TS2
    // (account_linking_sheet_two_step_test.dart) 가 hint 문구까지, 이 케이스가
    // 안내가 가리키는 도착지 버튼(설정 「네이버 연결」)을 잇는다.
    testWidgets('AL17 (D-07) 가입 kakao 사용자 — 「네이버 연결」 노출 · tap → arm', (
      tester,
    ) async {
      final user = _testUser(providerIds: const <String>['kakao']);
      when(
        () => repo.linkNaverProviderArm(),
      ).thenAnswer((_) async => Result.success(user));

      await _pumpSection(tester, user: user, repo: repo);

      final btn = find.text('Link Naver');
      expect(btn, findsOneWidget);
      await tester.ensureVisible(btn);
      await tester.tap(btn);
      await tester.pumpAndSettle();

      verify(() => repo.linkNaverProviderArm()).called(1);
    });
  });

  group('Phase 17.3 처음부터 off — 계정 연결 후보는 activeStrategies 뿐', () {
    testWidgets('T-173-OFF-03: 표시 목록 Google 1개 · 연결 0 → Google 연결 후보만', (
      tester,
    ) async {
      await _pumpSection(
        tester,
        user: _testUser(providerIds: const <String>[]),
        repo: repo,
        strategies: const <AuthStrategy>[GoogleAuthStrategy()],
      );

      // 섹션이 그려졌는지 먼저 확인한 뒤 「없음」 을 단언한다(offstage 포함).
      expect(find.text('Link an account'), findsOneWidget);
      expect(find.text('Link Google', skipOffstage: false), findsOneWidget);
      for (final label in const <String>[
        'Link Apple',
        'Link Facebook',
        'Link Kakao',
        'Link Naver',
        'Link LINE',
      ]) {
        expect(
          find.text(label, skipOffstage: false),
          findsNothing,
          reason: '처음부터 off 인 provider 는 연결 후보에 없어야 함 ($label)',
        );
      }
    });

    testWidgets('T-173-OFF-04: 표시 목록 0개 → 계정 연결 섹션 미노출', (tester) async {
      await _pumpSection(
        tester,
        user: _testUser(providerIds: const <String>[]),
        repo: repo,
        strategies: const <AuthStrategy>[],
      );

      // AL8 과 같은 판정 — heading 미노출 = 섹션 미노출.
      expect(find.byType(AccountLinkingSection), findsOneWidget);
      expect(find.text('Link an account', skipOffstage: false), findsNothing);
    });
  });
}
