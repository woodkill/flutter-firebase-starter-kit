import 'dart:math' as math;

import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_starter_kit/core/providers/firebase_providers.dart';
import 'package:flutter_starter_kit/core/theme/app_theme.dart';
import 'package:flutter_starter_kit/features/auth/data/auth_repository.dart';
import 'package:flutter_starter_kit/features/home/presentation/environment_info_screen.dart';
import 'package:flutter_starter_kit/l10n/generated/app_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';

class _MockAuthRepository extends Mock implements AuthRepository {}

class _MockFirebaseAuth extends Mock implements fb.FirebaseAuth {}

class _MockUser extends Mock implements fb.User {}

/// [EnvironmentInfoScreen] 의 게스트 UI (Phase 10 D-13, D-11) 검증 harness.
///
/// [authStateUser] 가 null → AsyncData(null), non-null → AsyncData(user).
/// [isFirebaseInitialized] 를 통해 Provider 분기 제어.
/// [theme] 이 null 이면 기존처럼 `AppTheme.light()` 를 쓴다.
Future<void> pumpGuestHarness(
  WidgetTester tester, {
  required bool isFirebaseInitialized,
  fb.User? authStateUser,
  ThemeData? theme,
}) async {
  // 260425-n31: viewport 8000 (환경 정보 화면 컨텐츠가 _TypographySample
  // 패가그램 3행 확장으로 6000dp 를 초과한다 — environment_info_screen_test.dart
  // 와 동일 정책).
  tester.view.physicalSize = const Size(800, 8000);
  tester.view.devicePixelRatio = 1;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });

  final mockAuth = _MockFirebaseAuth();
  when(() => mockAuth.currentUser).thenReturn(authStateUser);

  final mockRepo = _MockAuthRepository();

  final router = GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(path: '/', builder: (_, _) => const EnvironmentInfoScreen()),
      GoRoute(
        path: '/login',
        builder: (_, _) =>
            const Scaffold(body: Center(child: Text('LoginStub'))),
      ),
    ],
  );

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        isFirebaseInitializedProvider.overrideWithValue(isFirebaseInitialized),
        firebaseAuthProvider.overrideWithValue(mockAuth),
        authStateProvider.overrideWith((ref) => Stream.value(authStateUser)),
        currentUserProvider.overrideWith((ref) => null),
        authRepositoryProvider.overrideWithValue(mockRepo),
      ],
      child: MaterialApp.router(
        theme: theme ?? AppTheme.light(),
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        routerConfig: router,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// 두 색의 WCAG 2.x 상대 휘도 대비를 계산한다.
///
/// `(max(L1, L2) + 0.05) / (min(L1, L2) + 0.05)` 이므로 인자 순서와 무관하다.
double _computeContrastRatio(Color a, Color b) {
  final luminanceA = a.computeLuminance();
  final luminanceB = b.computeLuminance();
  return (math.max(luminanceA, luminanceB) + 0.05) /
      (math.min(luminanceA, luminanceB) + 0.05);
}

/// 게스트 홈 AppBar 「로그인」 글자색과 AppBar 배경 대비를 [theme] 으로 검증한다.
///
/// 전체 화면 `textContrastGuideline` 대신 렌더된 글자색 vs AppBar `Material`
/// 색으로 결정적으로 계산한다 — 같은 화면 「테마」 SegmentedButton 의 기존
/// FAIL 노드를 피하기 위함이다 (quick 261001-d0x D-04).
Future<void> _verifySignInContrast(
  WidgetTester tester, {
  required ThemeData theme,
}) async {
  final anonUser = _MockUser();
  when(() => anonUser.isAnonymous).thenReturn(true);
  when(() => anonUser.uid).thenReturn('anon-uid');

  await pumpGuestHarness(
    tester,
    isFirebaseInitialized: true,
    authStateUser: anonUser,
    theme: theme,
  );

  final l10n = AppLocalizations.of(
    tester.element(find.byType(EnvironmentInfoScreen)),
  );
  final labelFinder = find.descendant(
    of: find.byType(AppBar),
    matching: find.text(l10n.homeSignIn),
  );
  expect(labelFinder, findsOneWidget);

  // 실제로 칠해진 글자색 — RenderParagraph 의 최종 TextSpan 스타일.
  final labelColor = tester
      .renderObject<RenderParagraph>(labelFinder)
      .text
      .style
      ?.color;
  expect(labelColor, isNotNull, reason: '「로그인」 글자색이 렌더 트리에 있어야 함');

  // AppBar 하위 첫 Material = AppBar 배경. elevation 0 이면 surfaceTint 겹침이
  // 없으므로 color 가 곧 칠해진 색이다.
  final appBarMaterial = tester.widget<Material>(
    find
        .descendant(of: find.byType(AppBar), matching: find.byType(Material))
        .first,
  );
  expect(appBarMaterial.elevation, 0, reason: 'AppBar 배경에 tint 겹침 없음');
  final backgroundColor = appBarMaterial.color;
  expect(backgroundColor, isNotNull, reason: 'AppBar 배경색이 지정돼 있어야 함');
  expect(backgroundColor!.a, 1.0, reason: 'AppBar 배경은 불투명이어야 함');

  final ratio = _computeContrastRatio(labelColor!, backgroundColor);
  expect(
    ratio,
    greaterThanOrEqualTo(4.5),
    reason:
        '「로그인」 대비 ${ratio.toStringAsFixed(2)} : 1 — '
        'WCAG AA 4.5 미달 (quick 261001-d0x D-04)',
  );
  expect(
    tester.widget<AppBar>(find.byType(AppBar)).backgroundColor,
    isNull,
    reason: 'AppBar 배경은 테마 기본(M3 surface)을 따라야 함 (D-01)',
  );
}

void main() {
  group('EnvironmentInfoScreen 게스트 UI (Phase 10 D-13, D-11)', () {
    testWidgets('isAnonymous=true 사용자 → body 상단에 _GuestBanner 렌더', (
      tester,
    ) async {
      final anonUser = _MockUser();
      when(() => anonUser.isAnonymous).thenReturn(true);
      when(() => anonUser.uid).thenReturn('anon-uid');

      await pumpGuestHarness(
        tester,
        isFirebaseInitialized: true,
        authStateUser: anonUser,
      );

      final l10n = AppLocalizations.of(
        tester.element(find.byType(EnvironmentInfoScreen)),
      );
      expect(
        find.text(l10n.homeGuestBanner),
        findsOneWidget,
        reason: '익명 사용자에게 게스트 배너가 상단에 노출되어야 함',
      );
    });

    testWidgets('isAnonymous=false 사용자 → 게스트 배너/AppBar 로그인 버튼 숨김', (
      tester,
    ) async {
      final verifiedUser = _MockUser();
      when(() => verifiedUser.isAnonymous).thenReturn(false);
      when(() => verifiedUser.uid).thenReturn('verified-uid');

      await pumpGuestHarness(
        tester,
        isFirebaseInitialized: true,
        authStateUser: verifiedUser,
      );

      final l10n = AppLocalizations.of(
        tester.element(find.byType(EnvironmentInfoScreen)),
      );
      expect(
        find.text(l10n.homeGuestBanner),
        findsNothing,
        reason: '정식 사용자는 게스트 배너 없음',
      );
      expect(
        find.text(l10n.homeSignIn),
        findsNothing,
        reason: '정식 사용자는 AppBar 로그인 버튼 없음',
      );
    });

    testWidgets('isAnonymous=true 사용자 → AppBar 우측에 homeSignIn TextButton 표시', (
      tester,
    ) async {
      final anonUser = _MockUser();
      when(() => anonUser.isAnonymous).thenReturn(true);
      when(() => anonUser.uid).thenReturn('anon-uid');

      await pumpGuestHarness(
        tester,
        isFirebaseInitialized: true,
        authStateUser: anonUser,
      );

      final l10n = AppLocalizations.of(
        tester.element(find.byType(EnvironmentInfoScreen)),
      );
      final appBarLoginFinder = find.widgetWithText(
        TextButton,
        l10n.homeSignIn,
      );
      expect(appBarLoginFinder, findsOneWidget);
    });

    testWidgets(
      '_ProtectedExampleSection 이 항상 렌더 + AuthRequired 래핑 OutlinedButton 포함',
      (tester) async {
        // isAnonymous=false 인 정식 사용자 케이스로도 섹션이 렌더되어야 함.
        final verifiedUser = _MockUser();
        when(() => verifiedUser.isAnonymous).thenReturn(false);
        when(() => verifiedUser.uid).thenReturn('verified-uid');

        await pumpGuestHarness(
          tester,
          isFirebaseInitialized: true,
          authStateUser: verifiedUser,
        );

        final l10n = AppLocalizations.of(
          tester.element(find.byType(EnvironmentInfoScreen)),
        );
        expect(
          find.text(l10n.homeProtectedExampleTitle),
          findsOneWidget,
          reason: '보호 예시 섹션은 isAnonymous 관계없이 항상 렌더',
        );
        expect(find.text(l10n.homeProtectedExampleBody), findsOneWidget);
        expect(
          find.widgetWithText(OutlinedButton, l10n.homeProtectedExampleCta),
          findsOneWidget,
          reason: 'AuthRequired 래핑된 OutlinedButton.icon 필요',
        );
      },
    );
  });

  // quick 261001-d0x D-04 — 게스트 AppBar 「로그인」 명암 대비 회귀 방지.
  group('홈 AppBar 「로그인」 대비 (quick 261001-d0x D-04)', () {
    testWidgets('light — 대비 ≥ 4.5 · AppBar 배경 테마 기본', (tester) async {
      await _verifySignInContrast(tester, theme: AppTheme.light());
    });

    testWidgets('dark — 대비 ≥ 4.5 · AppBar 배경 테마 기본', (tester) async {
      await _verifySignInContrast(tester, theme: AppTheme.dark());
    });
  });
}
