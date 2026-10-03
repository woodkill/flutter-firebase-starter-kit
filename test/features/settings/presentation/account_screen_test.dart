// ignore_for_file: lines_longer_than_80_chars
//
// Phase 17.1 Plan 17.1-06 Task 1 — 계정 정보 화면(AccountScreen) widget test.
//
// 검증 (T-171-ACCOUNT):
// - 01 라우트 — 실제 appRouterProvider 에 `/settings/account` GoRoute 1개 ·
//   name `account` · builder = AccountScreen (D-02).
// - 02 행 순서 — AppBar 「내 계정」 · heading 「프로필」 · 「로그인 수단」 · 사진 행 <
//   표시 이름 < 이메일 < 가입일 < 가입 수단 < 연결된 계정 < 로그아웃 < 회원탈퇴
//   (D-02 · UI-SPEC E5 populated).
// - 03 로그아웃 — 로그아웃 행 → 확인 다이얼로그 → 확인 = signOutAndResetOnboarding
//   1회 · 취소 = 0회 (D-05 · 10.2 D-A4).
// - 04 계정 연결 섹션 간격 — 연결 가능 0(W5) 이면 섹션 크기 0 · 연결된 계정 ↔
//   로그아웃 간격 = xxl 1회 / 연결 가능 ≥ 1 이면 섹션이 둘 사이 (UI-SPEC §Spacing).

import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';

import 'package:flutter_starter_kit/core/auth/auth_strategies_registry.dart';
import 'package:flutter_starter_kit/core/auth/auth_strategy.dart';
import 'package:flutter_starter_kit/core/auth/strategies/apple_auth_strategy.dart';
import 'package:flutter_starter_kit/core/auth/strategies/facebook_auth_strategy.dart';
import 'package:flutter_starter_kit/core/auth/strategies/google_auth_strategy.dart';
import 'package:flutter_starter_kit/core/auth/strategies/kakao_auth_strategy.dart';
import 'package:flutter_starter_kit/core/auth/strategies/line_auth_strategy.dart';
import 'package:flutter_starter_kit/core/auth/strategies/naver_auth_strategy.dart';
import 'package:flutter_starter_kit/core/providers/firebase_providers.dart';
import 'package:flutter_starter_kit/core/router/app_router.dart';
import 'package:flutter_starter_kit/core/router/app_routes.dart';
import 'package:flutter_starter_kit/core/theme/app_theme.dart';
import 'package:flutter_starter_kit/core/theme/theme_extensions.dart';
import 'package:flutter_starter_kit/features/auth/data/auth_repository.dart';
import 'package:flutter_starter_kit/features/auth/domain/user.dart';
import 'package:flutter_starter_kit/features/auth/presentation/_widgets/branded_social_button.dart';
import 'package:flutter_starter_kit/features/notifications/application/notification_settings_notifier.dart';
import 'package:flutter_starter_kit/features/settings/presentation/_widgets/account_linking_section.dart';
import 'package:flutter_starter_kit/features/settings/presentation/_widgets/profile_photo_tile.dart';
import 'package:flutter_starter_kit/features/settings/presentation/account_screen.dart';
import 'package:flutter_starter_kit/l10n/generated/app_localizations.dart';

class _MockAuthRepository extends Mock implements AuthRepository {}

class _MockFirebaseAuth extends Mock implements fb.FirebaseAuth {}

/// 활성 소셜 Strategy 6종 전부.
const List<AuthStrategy> _allStrategies = <AuthStrategy>[
  GoogleAuthStrategy(),
  AppleAuthStrategy(),
  FacebookAuthStrategy(),
  KakaoAuthStrategy(),
  NaverAuthStrategy(),
  LineAuthStrategy(),
];

/// Phase 16.8 W5 — 가입 naver + 연결 5 (연결 가능 provider 0 · 도달 가능 최악).
const List<String> _kW5ProviderIds = <String>[
  'google.com',
  'apple.com',
  'facebook.com',
  'kakao',
  'line',
  'naver',
];

/// 테스트용 User factory.
User _testUser({
  List<String> providerIds = const <String>['password'],
  String? email = 'me@example.com',
  String? displayName,
  String? signUpProviderId,
}) {
  return User(
    uid: 'uid-1',
    email: email,
    emailVerified: true,
    displayName: displayName,
    createdAt: DateTime.utc(2026, 1, 1),
    providerIds: providerIds,
    signUpProviderId: signUpProviderId,
  );
}

/// 사진 출처 stream fixture — 업로드 사진 없음 (Phase 17 T-17-PHOTO-09).
///
/// 화면은 `currentUserProvider` override 로 사용자를 고정하므로 이 record 는
/// 사진 행의 출처 읽기 상태(data)만 결정한다.
const UserProviderRecord _kNoPhotoRecord = (
  linkedProviderIds: <String>[],
  signUpProviderId: null,
  customPhotoUrl: null,
);

/// [icon] 을 leading 으로 가진 `ListTile` finder.
Finder _findTileByIcon(IconData icon) =>
    find.ancestor(of: find.byIcon(icon), matching: find.byType(ListTile));

/// 테스트 view 를 logical [size](DPR 1)로 바꾼다 — 테스트 끝에 되돌린다.
void _useViewport(WidgetTester tester, Size size) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
}

/// [AccountScreen] 을 `MaterialApp(home:)` 으로 pump 한다.
///
/// override = 사용자 fixture · 활성 Strategy([strategies]) · (선택) repository
/// mock · 알림 꺼짐 · 사진 출처 stream(업로드 사진 없음).
Future<void> _pumpAccountScreen(
  WidgetTester tester, {
  required User? user,
  Locale locale = const Locale('en'),
  List<AuthStrategy> strategies = _allStrategies,
  AuthRepository? authRepo,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        currentUserProvider.overrideWith((ref) => user),
        // 활성 Strategy 직접 주입 — AccountLinkingSection available 계산 결정성.
        activeStrategiesProvider.overrideWith((ref) => strategies),
        if (authRepo != null)
          authRepositoryProvider.overrideWithValue(authRepo),
        notificationSettingsProvider.overrideWithBuild(
          (ref, notifier) => false,
        ),
        // 사진 행의 사진 출처 stream 을 data 로 고정(미초기화 Firestore 무접촉).
        if (user != null)
          linkedProvidersStreamProvider(
            user.uid,
          ).overrideWith((ref) => Stream.value(_kNoPhotoRecord)),
      ],
      child: MaterialApp(
        theme: AppTheme.light(),
        locale: locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const AccountScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// 로그아웃 경로 harness — [AccountScreen] 을 GoRouter(`/` · `/login` ·
/// `/onboarding` stub) 안에 pump 하고 repository mock 을 돌려준다.
///
/// `signOutAndResetOnboarding` · `signOut` 은 no-op stub 이다. 화면 이동은
/// 실 앱에서 authStateChanges → redirect 가 맡으므로(10.2 D-B1) 여기서는
/// 호출 횟수만 본다. 800×8000 view 로 긴 목록을 한 frame 에 그린다.
Future<_MockAuthRepository> _pumpLogoutHarness(
  WidgetTester tester, {
  Locale locale = const Locale('en'),
}) async {
  _useViewport(tester, const Size(800, 8000));

  final mockRepo = _MockAuthRepository();
  when(() => mockRepo.signOutAndResetOnboarding()).thenAnswer((_) async {});
  when(() => mockRepo.signOut()).thenAnswer((_) async {});

  final mockAuth = _MockFirebaseAuth();
  when(() => mockAuth.currentUser).thenReturn(null);

  final user = _testUser(displayName: 'Test User');

  final router = GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(path: '/', builder: (_, _) => const AccountScreen()),
      GoRoute(
        path: '/login',
        builder: (_, _) =>
            const Scaffold(body: Center(child: Text('LoginStub'))),
      ),
      // 로그아웃 뒤 redirect 목적지(10.2 D-B1) — 도달 가능성만 유지.
      GoRoute(
        path: '/onboarding',
        builder: (_, _) =>
            const Scaffold(body: Center(child: Text('OnboardingStub'))),
      ),
    ],
  );
  addTearDown(router.dispose);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        isFirebaseInitializedProvider.overrideWithValue(false),
        firebaseAuthProvider.overrideWithValue(mockAuth),
        authStateProvider.overrideWith((ref) => const Stream.empty()),
        currentUserProvider.overrideWith((ref) => user),
        authRepositoryProvider.overrideWithValue(mockRepo),
        activeStrategiesProvider.overrideWith((ref) => _allStrategies),
        notificationSettingsProvider.overrideWithBuild(
          (ref, notifier) => false,
        ),
        linkedProvidersStreamProvider(
          user.uid,
        ).overrideWith((ref) => Stream.value(_kNoPhotoRecord)),
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
  return mockRepo;
}

void main() {
  group('Phase 17.1 계정 정보 화면 (T-171-ACCOUNT)', () {
    testWidgets(
      'T-171-ACCOUNT-01: 실제 라우터에 /settings/account GoRoute 1개 · name account · '
      'builder = AccountScreen (D-02)',
      (tester) async {
        final mockAuth = _MockFirebaseAuth();
        when(
          () => mockAuth.authStateChanges(),
        ).thenAnswer((_) => const Stream<fb.User?>.empty());
        final container = ProviderContainer(
          overrides: [
            isFirebaseInitializedProvider.overrideWithValue(false),
            firebaseAuthProvider.overrideWithValue(mockAuth),
          ],
        );
        addTearDown(container.dispose);

        final router = container.read(appRouterProvider);
        final routes = router.configuration.routes
            .whereType<GoRoute>()
            .where((r) => r.path == AppRoutes.account)
            .toList();
        expect(routes, hasLength(1), reason: '/settings/account GoRoute 1개');
        final route = routes.single;
        expect(route.name, AppRoutes.accountName);

        // builder 는 context · state 를 쓰지 않는다 — 임의 element · state 로 호출.
        await tester.pumpWidget(const SizedBox());
        final built = route.builder!(
          tester.element(find.byType(SizedBox)),
          GoRouterState(
            router.configuration,
            uri: Uri.parse(AppRoutes.account),
            matchedLocation: AppRoutes.account,
            fullPath: AppRoutes.account,
            pathParameters: const <String, String>{},
            pageKey: const ValueKey<String>('account'),
          ),
        );
        expect(built, isA<AccountScreen>());
      },
    );

    testWidgets(
      'T-171-ACCOUNT-02: 정식 W5 · 사진 없음 — AppBar 「내 계정」 · heading 2 · 행 순서 '
      '사진 < 이름 < 이메일 < 가입일 < 가입 수단 < 연결된 계정 < 로그아웃 < 회원탈퇴 '
      '(D-02 · E5 populated)',
      (tester) async {
        _useViewport(tester, const Size(800, 8000));
        const locale = Locale('ko');
        final l10n = lookupAppLocalizations(locale);
        await _pumpAccountScreen(
          tester,
          user: _testUser(
            providerIds: _kW5ProviderIds,
            displayName: '홍길동',
            signUpProviderId: 'naver',
          ),
          locale: locale,
        );
        expect(tester.takeException(), isNull);

        expect(
          find.descendant(
            of: find.byType(AppBar),
            matching: find.text(l10n.settingsAccountSection),
          ),
          findsOneWidget,
          reason: 'AppBar 제목 = 「내 계정」',
        );
        final profileHeading = find.text(l10n.accountProfileSection);
        final methodsHeading = find.text(l10n.accountSignInMethodsSection);
        expect(profileHeading, findsOneWidget);
        expect(methodsHeading, findsOneWidget);

        double topOf(Finder finder) => tester.getTopLeft(finder).dy;
        final ordered = <(String, Finder)>[
          ('프로필 heading', profileHeading),
          ('사진 행', find.byType(ProfilePhotoTile)),
          ('표시 이름', _findTileByIcon(Icons.badge)),
          ('이메일', _findTileByIcon(Icons.alternate_email)),
          ('가입일', _findTileByIcon(Icons.calendar_today)),
          ('로그인 수단 heading', methodsHeading),
          ('가입 수단', _findTileByIcon(Icons.how_to_reg)),
          ('연결된 계정', _findTileByIcon(Icons.link)),
          ('로그아웃', _findTileByIcon(Icons.logout)),
          ('회원탈퇴', find.text(l10n.settingsWithdrawalLabel)),
        ];
        for (final (name, finder) in ordered) {
          expect(finder, findsOneWidget, reason: '$name 1개');
        }
        for (var i = 1; i < ordered.length; i++) {
          expect(
            topOf(ordered[i].$2),
            greaterThan(topOf(ordered[i - 1].$2)),
            reason: '${ordered[i - 1].$1} < ${ordered[i].$1}',
          );
        }
        expect(
          find.descendant(
            of: _findTileByIcon(Icons.badge),
            matching: find.text('홍길동'),
          ),
          findsOneWidget,
          reason: '표시 이름 값',
        );
      },
    );

    testWidgets('T-171-ACCOUNT-03: 로그아웃 행 → 확인 다이얼로그 → 확인 = '
        'signOutAndResetOnboarding 1회 · 취소 = 0회 (D-05 · 10.2 D-A4)', (
      tester,
    ) async {
      const locale = Locale('ko');
      final l10n = lookupAppLocalizations(locale);
      final repo = await _pumpLogoutHarness(tester, locale: locale);

      // 취소 — 호출 0.
      await tester.tap(find.text(l10n.authAccountSignOut));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.text(l10n.authLogoutConfirmMessage), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text(l10n.authLogoutConfirmTitle),
        ),
        findsWidgets,
      );
      await tester.tap(find.text(l10n.commonCancel));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      verifyNever(() => repo.signOutAndResetOnboarding());

      // 확인 — 호출 1 · signOut 단독 호출 0.
      await tester.tap(find.text(l10n.authAccountSignOut));
      await tester.pumpAndSettle();
      await tester.tap(find.text(l10n.authAccountSignOut).last);
      await tester.pumpAndSettle();
      verify(() => repo.signOutAndResetOnboarding()).called(1);
      verifyNever(() => repo.signOut());
    });

    testWidgets('T-171-ACCOUNT-04: 연결 가능 0(W5) — 섹션 크기 0 · 연결된 계정 ↔ 로그아웃 간격 '
        'xxl 1회 / 연결 가능 ≥ 1 — 섹션이 둘 사이 · 앞 간격 xxl (UI-SPEC §Spacing)', (
      tester,
    ) async {
      _useViewport(tester, const Size(800, 8000));
      await _pumpAccountScreen(
        tester,
        user: _testUser(
          providerIds: _kW5ProviderIds,
          signUpProviderId: 'naver',
        ),
      );
      final xxl = tester.element(find.byType(AccountScreen)).appSpacing.xxl;
      final linked = _findTileByIcon(Icons.link);
      final logout = _findTileByIcon(Icons.logout);

      expect(tester.getSize(find.byType(AccountLinkingSection)).height, 0);
      expect(
        tester.getTopLeft(logout).dy - tester.getBottomLeft(linked).dy,
        xxl,
        reason: 'W5 — 간격 겹침 0 (xxl 한 번)',
      );

      // 연결 가능 provider 가 있는 사용자(가입 naver + google) — 앞 scope 를
      // 먼저 내려 새 override 로 다시 만든다.
      await tester.pumpWidget(const SizedBox());
      await _pumpAccountScreen(
        tester,
        user: _testUser(
          providerIds: const <String>['google.com', 'naver'],
          signUpProviderId: 'naver',
        ),
      );
      final l10n = lookupAppLocalizations(const Locale('en'));
      final section = find.byType(AccountLinkingSection);
      final linkedBottom = tester.getBottomLeft(linked).dy;
      final logoutTop = tester.getTopLeft(logout).dy;
      expect(tester.getTopLeft(section).dy, linkedBottom);
      expect(tester.getBottomLeft(section).dy + xxl, logoutTop);
      // 섹션 heading = 섹션 첫 원소 Gap(xxl) 아래 heading padding(sm) 아래.
      final spacing = tester.element(section).appSpacing;
      expect(
        tester.getTopLeft(find.text(l10n.settingsAccountLinkingSection)).dy,
        linkedBottom + xxl + spacing.sm,
      );
      // 연결 가능 = 활성 6 − 연결(google · naver) = 4 (apple · facebook ·
      // kakao · line) — 버튼이 모두 연결된 계정 행과 로그아웃 행 사이.
      final buttons = find.descendant(
        of: section,
        matching: find.byType(BrandedSocialButton),
      );
      expect(buttons, findsNWidgets(4));
      for (var i = 0; i < 4; i++) {
        final rect = tester.getRect(buttons.at(i));
        expect(rect.top, greaterThan(linkedBottom));
        expect(rect.bottom, lessThan(logoutTop));
      }
    });
  });
}
