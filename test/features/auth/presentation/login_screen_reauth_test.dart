// debug reauth-login-auto-merge (2026-09-17) — 재인증 모드 로그인 화면.
//
// 설정(탈퇴 · 계정 연결)이 push 한 `/login?reauth=1` 은 일반 로그인 화면을
// 그대로 써서 연결 안 된 provider · 가입 링크가 노출되고, 버튼은 새 로그인을
// 호출했으며, 성공 · 취소 모두 홈으로 갔다. 사용자 sign-off(Q1~Q7) 된 재인증
// 모드 계약을 잠근다.
//
//   RL-1: 연결된 provider 만 노출 + 제목 · 안내 · 가입 링크 숨김 (Q1)
//   RL-2: 소셜 탭 → reauthenticate (새 로그인 0) → 성공 시 설정 복귀 + SnackBar (Q6)
//   RL-3: 취소 → 화면 유지 · 이동 0
//   RL-4: 다른 계정 → 인라인 배너 (Q2)
//   RL-5: 쓸 수 있는 수단 0 → 오류 배너 (Q7)
//   RL-6: 비밀번호만 연결 → 선택 화면에 「이메일로 계속」 하나 (Q4)
//   RL-7: 이메일 재인증 화면 — 읽기 전용 이메일 · 확인 CTA · 가입 링크 없음 (Q3)
//   RL-8: 대조군 — 표시 없는 /login 은 일반 로그인 화면 그대로
//   RL-9: ko 채택 문구 verbatim (en/ja 는 검토 대기 초안이라 잠그지 않는다)
//   RL-10~12: 선택 화면 열림 reload — SDK 캐시 providerData 가 서버보다 오래된
//          경우(앱 밖 해제) stale 버튼 제거 · 실패 시 새 UI 상태 없음 · 실행 시점
//          Q7 배너 (실기기 D1 Evidence 21 · 22)

import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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
import 'package:flutter_starter_kit/core/providers/firebase_providers.dart';
import 'package:flutter_starter_kit/core/router/app_routes.dart';
import 'package:flutter_starter_kit/core/theme/app_theme.dart';
import 'package:flutter_starter_kit/features/auth/data/auth_repository.dart';
import 'package:flutter_starter_kit/features/auth/domain/user.dart';
import 'package:flutter_starter_kit/features/auth/presentation/_widgets/email_auth_cta.dart';
import 'package:flutter_starter_kit/features/auth/presentation/_widgets/or_divider.dart';
import 'package:flutter_starter_kit/features/auth/presentation/_widgets/social_button.dart';
import 'package:flutter_starter_kit/features/auth/presentation/email_login_screen.dart';
import 'package:flutter_starter_kit/features/auth/presentation/login_screen.dart';
import 'package:flutter_starter_kit/l10n/generated/app_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';

class _MockFirebaseAuth extends Mock implements fb.FirebaseAuth {}

class _MockFirebaseUser extends Mock implements fb.User {}

class _MockAuthRepository extends Mock implements AuthRepository {}

class _MockUserInfo extends Mock implements fb.UserInfo {}

class _MockUserMetadata extends Mock implements fb.UserMetadata {}

const _settingsText = 'SETTINGS_STUB';
const _homeText = 'HOME_STUB';
const _currentEmail = 'current-user@example.com';
const _currentUid = 'current-uid-U';

/// 현행 활성 provider 6종 (`_allStrategies` 선언 순서).
const List<AuthStrategy> _sixStrategies = <AuthStrategy>[
  GoogleAuthStrategy(),
  AppleAuthStrategy(),
  FacebookAuthStrategy(),
  KakaoAuthStrategy(),
  NaverAuthStrategy(),
  LineAuthStrategy(),
];

/// [providerIds] 를 연결한 정식 사용자 도메인 모델.
User _userWith(List<String> providerIds) => User(
  uid: _currentUid,
  email: _currentEmail,
  emailVerified: true,
  createdAt: DateTime.utc(2026, 1, 1),
  providerIds: providerIds,
);

/// providerData 가 [providerIds] 인 SDK 사용자 객체.
///
/// SDK `reload()` 는 기존 객체를 고치지 않고 새 객체로 교체한 뒤 `userChanges`
/// 를 재방출한다 (firebase_auth_platform_interface 9.1.0
/// `MethodChannelUser.reload`) — reload 전후 사용자를 각각 만든다.
fb.User _sdkUserWith(List<String> providerIds) {
  final infos = List<fb.UserInfo>.generate(
    providerIds.length,
    (_) => _MockUserInfo(),
  );
  for (final (index, providerId) in providerIds.indexed) {
    when(() => infos[index].providerId).thenReturn(providerId);
  }
  final metadata = _MockUserMetadata();
  when(() => metadata.creationTime).thenReturn(DateTime.utc(2026, 1, 1));
  final user = _MockFirebaseUser();
  when(() => user.uid).thenReturn(_currentUid);
  when(() => user.email).thenReturn(_currentEmail);
  when(() => user.emailVerified).thenReturn(true);
  when(() => user.displayName).thenReturn(null);
  when(() => user.photoURL).thenReturn(null);
  when(() => user.isAnonymous).thenReturn(false);
  when(() => user.metadata).thenReturn(metadata);
  when(() => user.providerData).thenReturn(infos);
  return user;
}

/// production 라우터와 같은 builder (표시 → isReauth) 로 설정 위에 재인증
/// 로그인 화면을 push 한 상태를 만든다.
///
/// [sdkUserChanges] 가 있으면 `currentUserProvider` 를 고정하지 않고 production
/// 계산(SDK userChanges providerData ∪ Firestore [linkedProviders]) 을 그대로
/// 쓴다 — 화면 열림 reload 가 목록을 바꾸는지 보기 위한 경로다.
Future<GoRouter> _pumpReauthFlow(
  WidgetTester tester, {
  required _MockAuthRepository repo,
  User? user,
  Stream<fb.User?>? sdkUserChanges,
  List<String> linkedProviders = const <String>[],
  List<AuthStrategy> strategies = _sixStrategies,
  Locale locale = const Locale('en'),
  bool withMarker = true,
}) async {
  final mockAuth = _MockFirebaseAuth();
  final mockFbUser = _MockFirebaseUser();
  when(() => mockFbUser.isAnonymous).thenReturn(false);
  when(() => mockFbUser.emailVerified).thenReturn(true);
  when(() => mockAuth.currentUser).thenReturn(mockFbUser);
  when(
    () => mockAuth.authStateChanges(),
  ).thenAnswer((_) => const Stream<fb.User?>.empty());

  final router = GoRouter(
    initialLocation: AppRoutes.settings,
    routes: [
      GoRoute(
        path: AppRoutes.home,
        builder: (context, state) => const Scaffold(body: Text(_homeText)),
      ),
      GoRoute(
        path: AppRoutes.settings,
        builder: (context, state) => const Scaffold(body: Text(_settingsText)),
      ),
      GoRoute(
        path: AppRoutes.login,
        builder: (context, state) =>
            LoginScreen(isReauth: AppRoutes.hasReauthMarker(state.uri)),
      ),
      GoRoute(
        path: AppRoutes.emailLogin,
        builder: (context, state) =>
            EmailLoginScreen(isReauth: AppRoutes.hasReauthMarker(state.uri)),
      ),
      GoRoute(
        path: AppRoutes.signup,
        builder: (context, state) => const Scaffold(body: Text('SIGNUP_STUB')),
      ),
      GoRoute(
        path: AppRoutes.forgotPassword,
        builder: (context, state) => const Scaffold(body: Text('FORGOT_STUB')),
      ),
    ],
  );
  addTearDown(router.dispose);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        isFirebaseInitializedProvider.overrideWithValue(false),
        firebaseAuthProvider.overrideWithValue(mockAuth),
        authRepositoryProvider.overrideWithValue(repo),
        activeStrategiesProvider.overrideWithValue(strategies),
        if (sdkUserChanges == null)
          currentUserProvider.overrideWith((ref) => user)
        else ...[
          authStateProvider.overrideWith((ref) => sdkUserChanges),
          linkedProvidersStreamProvider(_currentUid).overrideWith(
            (ref) => Stream<UserProviderRecord>.value((
              linkedProviderIds: linkedProviders,
              signUpProviderId: null,
            )),
          ),
        ],
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
  unawaited(
    router.push(
      withMarker
          ? AppRoutes.buildReauthLocation(AppRoutes.login)
          : AppRoutes.login,
    ),
  );
  await tester.pumpAndSettle();
  return router;
}

/// 현재 화면 위 en 번역.
AppLocalizations _l10n(WidgetTester tester) =>
    AppLocalizations.of(tester.element(find.byType(Scaffold).last));

/// form-tail 버튼을 viewport 안으로 스크롤한 뒤 탭한다 (800x600 hit-test 함정).
Future<void> _tapVisible(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

void main() {
  late _MockAuthRepository repo;

  setUpAll(() {
    registerFallbackValue(AccountProvider.google);
  });

  setUp(() {
    repo = _MockAuthRepository();
    // 새 로그인 경로 — 재인증 모드에서는 호출되면 안 된다.
    when(() => repo.signInWithGoogle()).thenAnswer((_) async => null);
    when(() => repo.signInWithApple()).thenAnswer((_) async => null);
    when(() => repo.signInWithFacebook()).thenAnswer((_) async => null);
    when(() => repo.signInWithKakao()).thenAnswer((_) async => null);
    when(() => repo.signInWithNaver()).thenAnswer((_) async => null);
    when(() => repo.signInWithLine()).thenAnswer((_) async => null);
    when(
      () => repo.signInWithEmail(
        email: any(named: 'email'),
        password: any(named: 'password'),
      ),
    ).thenAnswer((_) async => const Result.failure(InvalidCredentials()));
    // 선택 화면 열림 reload — 기본은 성공 · 사용자 불변.
    when(
      () => repo.reloadUser(),
    ).thenAnswer((_) async => const Result.success(null));
  });

  group('재인증 모드 로그인 화면 (reauth-login-auto-merge)', () {
    testWidgets('RL-1: 연결된 provider 만 · 제목 · 안내 · 가입 링크 없음', (tester) async {
      await _pumpReauthFlow(
        tester,
        repo: repo,
        user: _userWith(const <String>['apple.com', 'google.com', 'password']),
      );
      final l10n = _l10n(tester);

      expect(find.text(l10n.authReauthTitle), findsOneWidget);
      expect(find.text(l10n.authReauthGuide), findsOneWidget);
      expect(find.text(l10n.authLoginTitle), findsNothing);
      expect(find.byType(SocialButton), findsNWidgets(2));
      expect(find.text(l10n.authGoogleSignIn), findsOneWidget);
      expect(find.text(l10n.authAppleSignIn), findsOneWidget);
      expect(find.text(l10n.authKakaoSignIn), findsNothing);
      expect(find.byType(OrDivider), findsOneWidget);
      expect(find.byType(EmailAuthCta), findsOneWidget);
      expect(find.text(l10n.authLoginNoAccount), findsNothing);
    });

    testWidgets(
      'RL-2: Naver 탭 → reauthenticate(naver) · 새 로그인 0 · 성공 시 설정 복귀 + SnackBar',
      (tester) async {
        when(() => repo.reauthenticate(AccountProvider.naver)).thenAnswer(
          (_) async => Result.success(_userWith(const <String>['naver'])),
        );
        final router = await _pumpReauthFlow(
          tester,
          repo: repo,
          user: _userWith(const <String>['naver']),
        );
        final l10n = _l10n(tester);
        expect(find.byType(SocialButton), findsOneWidget);

        await _tapVisible(tester, find.byType(SocialButton));

        verify(() => repo.reauthenticate(AccountProvider.naver)).called(1);
        verifyNever(() => repo.signInWithNaver());
        expect(router.state.matchedLocation, AppRoutes.settings);
        expect(find.text(_settingsText), findsOneWidget);
        expect(find.text(_homeText), findsNothing);
        expect(find.text(l10n.authReauthSucceeded), findsOneWidget);
      },
    );

    testWidgets('RL-3: IdP 취소 (null) → 재인증 화면 유지 · 이동 0 · SnackBar 0', (
      tester,
    ) async {
      when(
        () => repo.reauthenticate(AccountProvider.kakao),
      ).thenAnswer((_) async => null);
      final router = await _pumpReauthFlow(
        tester,
        repo: repo,
        user: _userWith(const <String>['kakao']),
      );
      final l10n = _l10n(tester);

      await _tapVisible(tester, find.byType(SocialButton));

      verify(() => repo.reauthenticate(AccountProvider.kakao)).called(1);
      expect(router.state.matchedLocation, AppRoutes.login);
      expect(find.text(l10n.authReauthTitle), findsOneWidget);
      expect(find.text(_homeText), findsNothing);
      expect(find.text(l10n.authReauthSucceeded), findsNothing);
    });

    testWidgets('RL-4: 다른 계정 (ReauthUserMismatch) → 인라인 배너 · 화면 유지', (
      tester,
    ) async {
      when(
        () => repo.reauthenticate(AccountProvider.google),
      ).thenAnswer((_) async => const Result.failure(ReauthUserMismatch()));
      final router = await _pumpReauthFlow(
        tester,
        repo: repo,
        user: _userWith(const <String>['google.com']),
      );
      final l10n = _l10n(tester);

      await _tapVisible(tester, find.byType(SocialButton));

      expect(find.text(l10n.errorReauthUserMismatch), findsOneWidget);
      expect(router.state.matchedLocation, AppRoutes.login);
      expect(find.text(_homeText), findsNothing);
    });

    testWidgets('RL-5: 연결 provider 가 모두 비활성 + 비밀번호 없음 → 수단 0 배너', (
      tester,
    ) async {
      await _pumpReauthFlow(
        tester,
        repo: repo,
        user: _userWith(const <String>['kakao']),
        strategies: const <AuthStrategy>[
          GoogleAuthStrategy(),
          AppleAuthStrategy(),
        ],
      );
      final l10n = _l10n(tester);

      expect(find.text(l10n.errorReauthMethodUnavailable), findsOneWidget);
      expect(find.byType(SocialButton), findsNothing);
      expect(find.byType(EmailAuthCta), findsNothing);
      expect(find.text(l10n.authLoginNoAccount), findsNothing);
    });

    testWidgets('RL-6: 비밀번호만 연결 → 「이메일로 계속」 하나 · 배너 0', (tester) async {
      await _pumpReauthFlow(
        tester,
        repo: repo,
        user: _userWith(const <String>['password']),
      );
      final l10n = _l10n(tester);

      expect(find.byType(SocialButton), findsNothing);
      expect(find.byType(EmailAuthCta), findsOneWidget);
      expect(find.byType(OrDivider), findsNothing);
      expect(find.text(l10n.errorReauthMethodUnavailable), findsNothing);
    });

    testWidgets(
      'RL-7: 이메일 재인증 — 읽기 전용 이메일 · 확인 · 가입 링크 없음 · 성공 시 설정 복귀 + SnackBar',
      (tester) async {
        when(
          () => repo.reauthenticateWithPassword(password: 'pw-123456'),
        ).thenAnswer(
          (_) async => Result.success(_userWith(const <String>['password'])),
        );
        final router = await _pumpReauthFlow(
          tester,
          repo: repo,
          user: _userWith(const <String>['password']),
        );

        await _tapVisible(tester, find.byType(EmailAuthCta));
        expect(router.state.matchedLocation, AppRoutes.emailLogin);
        expect(AppRoutes.hasReauthMarker(router.state.uri), isTrue);
        final l10n = _l10n(tester);

        expect(find.text(l10n.authReauthTitle), findsOneWidget);
        expect(find.text(l10n.authReauthEmailGuide), findsOneWidget);
        expect(find.text(l10n.authLoginNoAccount), findsNothing);
        expect(find.text(l10n.authLoginForgotPassword), findsOneWidget);
        final emailField = tester.widget<EditableText>(
          find.descendant(
            of: find.byType(TextFormField).first,
            matching: find.byType(EditableText),
          ),
        );
        expect(emailField.controller.text, _currentEmail);
        expect(emailField.readOnly, isTrue);

        await tester.enterText(find.byType(TextFormField).last, 'pw-123456');
        await _tapVisible(
          tester,
          find.widgetWithText(FilledButton, l10n.authReauthConfirmCta),
        );

        verify(
          () => repo.reauthenticateWithPassword(password: 'pw-123456'),
        ).called(1);
        verifyNever(
          () => repo.signInWithEmail(
            email: any(named: 'email'),
            password: any(named: 'password'),
          ),
        );
        expect(router.state.matchedLocation, AppRoutes.settings);
        expect(find.text(l10n.authReauthSucceeded), findsOneWidget);
      },
    );

    testWidgets('RL-7b: 이메일 재인증 틀린 비밀번호 → 배너 · 이메일 화면 유지', (tester) async {
      when(
        () => repo.reauthenticateWithPassword(password: any(named: 'password')),
      ).thenAnswer((_) async => const Result.failure(InvalidCredentials()));
      final router = await _pumpReauthFlow(
        tester,
        repo: repo,
        user: _userWith(const <String>['password']),
      );
      await _tapVisible(tester, find.byType(EmailAuthCta));
      final l10n = _l10n(tester);

      await tester.enterText(find.byType(TextFormField).last, 'wrong-pw');
      await _tapVisible(
        tester,
        find.widgetWithText(FilledButton, l10n.authReauthConfirmCta),
      );

      expect(find.text(l10n.errorInvalidCredentials), findsOneWidget);
      expect(router.state.matchedLocation, AppRoutes.emailLogin);
    });

    testWidgets('RL-8 (대조군): 표시 없는 /login 은 일반 로그인 화면 그대로', (tester) async {
      await _pumpReauthFlow(
        tester,
        repo: repo,
        user: _userWith(const <String>['naver']),
        withMarker: false,
      );
      final l10n = _l10n(tester);

      expect(find.text(l10n.authLoginTitle), findsOneWidget);
      expect(find.text(l10n.authReauthTitle), findsNothing);
      expect(find.byType(SocialButton), findsNWidgets(6));
      expect(find.text(l10n.authLoginNoAccount), findsOneWidget);
    });
  });

  group('선택 화면 열림 reload — stale providerData (reauth-login-auto-merge)', () {
    testWidgets(
      'RL-10: 캐시 [apple.com] · 서버 [] + Firestore [naver] → 열림 reload 1회 뒤 Apple 버튼 제거 · 네이버만',
      (tester) async {
        final userChanges = StreamController<fb.User?>();
        addTearDown(userChanges.close);
        final cachedUser = _sdkUserWith(const <String>['apple.com']);
        final reloadedUser = _sdkUserWith(const <String>[]);
        userChanges.add(cachedUser);
        // SDK reload 계약 — 새 사용자 객체로 교체 + userChanges 재방출.
        when(() => repo.reloadUser()).thenAnswer((_) async {
          userChanges.add(reloadedUser);
          return const Result.success(null);
        });

        await _pumpReauthFlow(
          tester,
          repo: repo,
          sdkUserChanges: userChanges.stream,
          linkedProviders: const <String>['naver'],
        );
        final l10n = _l10n(tester);

        expect(find.text(l10n.authAppleSignIn), findsNothing);
        expect(find.text(l10n.authNaverSignIn), findsOneWidget);
        expect(find.byType(SocialButton), findsOneWidget);
        expect(find.text(l10n.errorReauthMethodUnavailable), findsNothing);
        verify(() => repo.reloadUser()).called(1);
      },
    );

    testWidgets(
      'RL-11: 열림 reload 실패 → 기존 목록 유지 · 배너 0 (새 UI 상태 없음, 실행 직전 재확인이 방어)',
      (tester) async {
        final userChanges = StreamController<fb.User?>();
        addTearDown(userChanges.close);
        userChanges.add(_sdkUserWith(const <String>['apple.com']));
        when(
          () => repo.reloadUser(),
        ).thenAnswer((_) async => const Result.failure(NoInternetConnection()));

        await _pumpReauthFlow(
          tester,
          repo: repo,
          sdkUserChanges: userChanges.stream,
          linkedProviders: const <String>['naver'],
        );
        final l10n = _l10n(tester);

        expect(find.byType(SocialButton), findsNWidgets(2));
        expect(find.text(l10n.errorReauthMethodUnavailable), findsNothing);
        expect(find.text(l10n.errorNoInternet), findsNothing);
        expect(find.byType(CircularProgressIndicator), findsNothing);
      },
    );

    testWidgets(
      'RL-12: 탭 → ReauthMethodUnavailable (서버에서 해제 · reload 실패) → Q7 배너 · 화면 유지 · SnackBar 0',
      (tester) async {
        when(() => repo.reauthenticate(AccountProvider.apple)).thenAnswer(
          (_) async => const Result.failure(ReauthMethodUnavailable()),
        );
        final router = await _pumpReauthFlow(
          tester,
          repo: repo,
          user: _userWith(const <String>['apple.com', 'naver']),
        );
        final l10n = _l10n(tester);

        await _tapVisible(tester, find.text(l10n.authAppleSignIn));

        verify(() => repo.reauthenticate(AccountProvider.apple)).called(1);
        expect(find.text(l10n.errorReauthMethodUnavailable), findsOneWidget);
        expect(router.state.matchedLocation, AppRoutes.login);
        expect(find.text(l10n.authReauthSucceeded), findsNothing);
      },
    );
  });

  group('RL-9: ko 채택 문구 verbatim (사용자 sign-off Q1~Q7)', () {
    test('ko 7 키가 승인 문구와 문자 단위로 같다', () {
      final ko = lookupAppLocalizations(const Locale('ko'));
      expect(ko.authReauthTitle, '본인 확인');
      expect(ko.authReauthGuide, '보안을 위해 지금 로그인한 계정으로 한 번 더 로그인해 주세요.');
      expect(ko.authReauthEmailGuide, '보안을 위해 이 계정의 비밀번호를 입력해 주세요.');
      expect(ko.authReauthConfirmCta, '확인');
      expect(ko.authReauthSucceeded, '본인 확인이 끝났습니다. 하던 작업을 다시 시도해 주세요.');
      expect(
        ko.errorReauthUserMismatch,
        '지금 로그인한 계정과 다른 계정입니다. 같은 계정으로 다시 시도해 주세요.',
      );
      expect(
        ko.errorReauthMethodUnavailable,
        '지금은 이 계정의 로그인 수단으로 본인 확인을 할 수 없습니다. 잠시 후 다시 시도해 주세요.',
      );
    });
  });
}
