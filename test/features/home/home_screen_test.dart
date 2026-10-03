// Phase 17.1 Plan 03 — production home 배선 (D-03 · D-08 · D-09 · D-10 · D-12 · D-17).
//
// T-171-HOME-03 ~ 09 · 13: 게스트 · 정식 AppBar · 알림 리스너 1 · push 경로 ·
// 「로그인」 대비 · 로그아웃/아바타 부재 · auth loading/error · 280 dp AppBar ·
// 제목 식 단일 위치 source guard.

import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_starter_kit/core/providers/firebase_providers.dart';
import 'package:flutter_starter_kit/core/providers/locale_provider.dart';
import 'package:flutter_starter_kit/core/remote_config/feature_flag.dart';
import 'package:flutter_starter_kit/core/remote_config/feature_flags_provider.dart';
import 'package:flutter_starter_kit/core/router/app_routes.dart';
import 'package:flutter_starter_kit/core/theme/app_theme.dart';
import 'package:flutter_starter_kit/features/auth/data/auth_repository.dart';
import 'package:flutter_starter_kit/features/home/presentation/home_screen.dart';
import 'package:flutter_starter_kit/features/notifications/presentation/pending_notification_route_listener.dart';
import 'package:flutter_starter_kit/l10n/generated/app_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/source_text.dart';

class _MockAuthRepository extends Mock implements AuthRepository {}

class _MockFirebaseAuth extends Mock implements fb.FirebaseAuth {}

class _MockUser extends Mock implements fb.User {}

/// stub 화면 표시 문구 — push 도달 확인용.
const String _loginStub = 'LOGIN STUB';
const String _settingsStub = 'SETTINGS STUB';

/// 익명 여부가 [isAnonymous] 인 Firebase 사용자 mock 을 만든다.
fb.User _buildUser({required bool isAnonymous}) {
  final user = _MockUser();
  when(() => user.isAnonymous).thenReturn(isAnonymous);
  when(() => user.uid).thenReturn(isAnonymous ? 'anon-uid' : 'member-uid');
  return user;
}

/// 공지 꺼짐 [FeatureFlagValues] — 홈 배선만 보게 공지 배너를 높이 0 으로 둔다.
const FeatureFlagValues _flagsOff = FeatureFlagValues(<FeatureFlag, Object>{
  FeatureFlag.announcementBannerEnabled: false,
  FeatureFlag.announcementMessageKo: '',
  FeatureFlag.announcementMessageEn: '',
  FeatureFlag.announcementMessageJa: '',
});

/// [HomeScreen] 을 GoRouter 안(`/login` · `/settings` stub)에서 띄운다.
///
/// [authState] 가 `authStateProvider` 값이다 — `Stream.value(user)` 면 data,
/// 끝나지 않는 stream 이면 loading, `Stream.error` 면 error 다.
Future<GoRouter> _pumpHome(
  WidgetTester tester, {
  required Stream<fb.User?> Function() authState,
  fb.User? currentUser,
  Locale locale = const Locale('en'),
  ThemeData? theme,
  Size size = const Size(400, 800),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final auth = _MockFirebaseAuth();
  when(() => auth.currentUser).thenReturn(currentUser);

  final router = GoRouter(
    initialLocation: AppRoutes.home,
    routes: [
      GoRoute(
        path: AppRoutes.home,
        builder: (context, state) => const HomeScreen(),
      ),
      GoRoute(
        path: AppRoutes.login,
        builder: (context, state) =>
            const Scaffold(body: Center(child: Text(_loginStub))),
      ),
      GoRoute(
        path: AppRoutes.settings,
        builder: (context, state) =>
            const Scaffold(body: Center(child: Text(_settingsStub))),
      ),
    ],
  );
  addTearDown(router.dispose);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        isFirebaseInitializedProvider.overrideWithValue(false),
        firebaseAuthProvider.overrideWithValue(auth),
        authStateProvider.overrideWith((ref) => authState()),
        currentUserProvider.overrideWith((ref) => null),
        authRepositoryProvider.overrideWithValue(_MockAuthRepository()),
        localeProvider.overrideWithBuild((ref, notifier) => locale),
        featureFlagsProvider.overrideWithBuild((ref, notifier) => _flagsOff),
      ],
      child: MaterialApp.router(
        theme: theme ?? AppTheme.light(),
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

/// 게스트(익명) 홈을 띄운다.
Future<GoRouter> _pumpGuest(
  WidgetTester tester, {
  Locale locale = const Locale('en'),
  ThemeData? theme,
  Size size = const Size(400, 800),
}) {
  final user = _buildUser(isAnonymous: true);
  return _pumpHome(
    tester,
    authState: () => Stream.value(user),
    currentUser: user,
    locale: locale,
    theme: theme,
    size: size,
  );
}

/// 정식(비익명) 사용자 홈을 띄운다.
Future<GoRouter> _pumpMember(WidgetTester tester) {
  final user = _buildUser(isAnonymous: false);
  return _pumpHome(
    tester,
    authState: () => Stream.value(user),
    currentUser: user,
  );
}

/// AppBar 안 「로그인」 텍스트 finder.
Finder _signInIn(AppLocalizations l10n) => find.descendant(
  of: find.byType(AppBar),
  matching: find.text(l10n.homeSignIn),
);

/// 두 색의 WCAG 2.x 상대 휘도 대비를 계산한다 (인자 순서 무관).
double _computeContrastRatio(Color a, Color b) {
  final luminanceA = a.computeLuminance();
  final luminanceB = b.computeLuminance();
  return (math.max(luminanceA, luminanceB) + 0.05) /
      (math.min(luminanceA, luminanceB) + 0.05);
}

/// 게스트 AppBar 「로그인」 글자색과 AppBar 배경 대비를 [theme] 으로 검증한다.
///
/// 렌더된 글자색 vs AppBar `Material` 색으로 결정적으로 계산한다
/// (quick 261001-d0x D-04 단언 이전 · D-22).
Future<void> _verifySignInContrast(
  WidgetTester tester, {
  required ThemeData theme,
}) async {
  await _pumpGuest(tester, theme: theme);
  final en = lookupAppLocalizations(const Locale('en'));

  final labelFinder = _signInIn(en);
  expect(labelFinder, findsOneWidget);
  final labelColor = tester
      .renderObject<RenderParagraph>(labelFinder)
      .text
      .style
      ?.color;
  expect(labelColor, isNotNull, reason: '「로그인」 글자색이 렌더 트리에 있어야 함');

  // AppBar 하위 첫 Material = AppBar 배경(elevation 0 → tint 겹침 없음).
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
}

/// [paragraph] 가 몇 줄로 그려졌는지 센다 — 글자 상자의 서로 다른 top 개수.
int _countLines(RenderParagraph paragraph) {
  final length = paragraph.text.toPlainText().length;
  final boxes = paragraph.getBoxesForSelection(
    TextSelection(baseOffset: 0, extentOffset: length),
  );
  return boxes.map((box) => box.top.round()).toSet().length;
}

void main() {
  final en = lookupAppLocalizations(const Locale('en'));

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  group('Phase 17.1 production home (T-171-HOME)', () {
    testWidgets(
      'T-171-HOME-03: 게스트 → 게스트 바 · 「로그인」 · 설정 아이콘 · 리스너 1 (D-08 반전)',
      (tester) async {
        await _pumpGuest(tester);

        expect(find.text(en.homeGuestBanner), findsOneWidget);
        expect(find.widgetWithText(TextButton, en.homeSignIn), findsOneWidget);
        // D-08 — 설정 아이콘은 게스트에게도 보인다(옛 홈은 정식 사용자만).
        expect(find.byTooltip(en.settingsTitle), findsOneWidget);
        expect(find.byIcon(Icons.settings), findsOneWidget);
        expect(find.byType(PendingNotificationRouteListener), findsOneWidget);
      },
    );

    testWidgets('T-171-HOME-04: 정식 사용자 → 「로그인」 · 게스트 바 없음 · 설정 아이콘 1', (
      tester,
    ) async {
      await _pumpMember(tester);

      expect(find.text(en.homeGuestBanner), findsNothing);
      expect(find.text(en.homeSignIn), findsNothing);
      expect(find.byTooltip(en.settingsTitle), findsOneWidget);
      expect(find.byType(PendingNotificationRouteListener), findsOneWidget);
    });

    testWidgets('T-171-HOME-05: 게스트 「로그인」 → /login', (tester) async {
      await _pumpGuest(tester);
      await tester.tap(_signInIn(en));
      await tester.pumpAndSettle();
      expect(find.text(_loginStub), findsOneWidget);
    });

    testWidgets('T-171-HOME-05: 게스트 설정 아이콘 → /settings', (tester) async {
      await _pumpGuest(tester);
      await tester.tap(find.byTooltip(en.settingsTitle));
      await tester.pumpAndSettle();
      expect(find.text(_settingsStub), findsOneWidget);
    });

    testWidgets('T-171-HOME-05: 정식 사용자 설정 아이콘 → /settings', (tester) async {
      await _pumpMember(tester);
      await tester.tap(find.byTooltip(en.settingsTitle));
      await tester.pumpAndSettle();
      expect(find.text(_settingsStub), findsOneWidget);
    });

    testWidgets('T-171-HOME-06: 게스트 「로그인」 대비 ≥ 4.5 — light', (tester) async {
      await _verifySignInContrast(tester, theme: AppTheme.light());
    });

    testWidgets('T-171-HOME-06: 게스트 「로그인」 대비 ≥ 4.5 — dark', (tester) async {
      await _verifySignInContrast(tester, theme: AppTheme.dark());
    });

    testWidgets('T-171-HOME-07: 홈에 로그아웃 · 아바타 없음 — 게스트 · 정식 (D-03 · D-09)', (
      tester,
    ) async {
      await _pumpGuest(tester);
      expect(find.text(en.authAccountSignOut), findsNothing);
      expect(find.byType(CircleAvatar), findsNothing);

      await _pumpMember(tester);
      expect(find.text(en.authAccountSignOut), findsNothing);
      expect(find.byType(CircleAvatar), findsNothing);
    });

    testWidgets('T-171-HOME-08: auth loading → 「로그인」 0 · 설정 아이콘 1 (E2)', (
      tester,
    ) async {
      final controller = StreamController<fb.User?>();
      addTearDown(controller.close);
      await _pumpHome(tester, authState: () => controller.stream);

      expect(tester.takeException(), isNull);
      expect(find.text(en.homeSignIn), findsNothing);
      expect(find.text(en.homeGuestBanner), findsNothing);
      expect(find.byTooltip(en.settingsTitle), findsOneWidget);
    });

    testWidgets(
      'T-171-HOME-08: auth error → 「로그인」 0 · 설정 아이콘 1 · 오류 표시 없음 (E2)',
      (tester) async {
        await _pumpHome(
          tester,
          authState: () => Stream<fb.User?>.error(StateError('auth failed')),
        );

        expect(tester.takeException(), isNull);
        expect(find.text(en.homeSignIn), findsNothing);
        expect(find.byTooltip(en.settingsTitle), findsOneWidget);
        expect(
          find.descendant(
            of: find.byType(AppBar),
            matching: find.byIcon(Icons.error_outline),
          ),
          findsNothing,
        );
      },
    );

    for (final code in const ['ko', 'ja']) {
      testWidgets(
        'T-171-HOME-09: 게스트 $code 280x800 — 넘침 0 · 제목 한 줄 말줄임 · 버튼 hit-test',
        (tester) async {
          final locale = Locale(code);
          final l10n = lookupAppLocalizations(locale);
          await _pumpGuest(tester, locale: locale, size: const Size(280, 800));

          expect(tester.takeException(), isNull);
          final title = find.descendant(
            of: find.byType(AppBar),
            matching: find.text(l10n.appTitle),
          );
          expect(title, findsOneWidget);
          final paragraph = tester.renderObject<RenderParagraph>(title);
          expect(_countLines(paragraph), 1, reason: '제목은 한 줄이어야 함');
          expect(paragraph.overflow, TextOverflow.ellipsis);
          expect(
            paragraph.didExceedMaxLines,
            isTrue,
            reason: '280 게스트 제목은 말줄임',
          );

          final signIn = _signInIn(l10n);
          final settings = find.byTooltip(l10n.settingsTitle);
          expect(signIn.hitTestable(), findsOneWidget);
          expect(settings.hitTestable(), findsOneWidget);
          // actions 는 잘리지 않는다 — 화면 안에 온전히 놓인다.
          for (final finder in [signIn, settings]) {
            final rect = tester.getRect(finder);
            expect(rect.left, greaterThanOrEqualTo(0));
            expect(rect.right, lessThanOrEqualTo(280));
          }
        },
      );
    }

    test(
      'T-171-HOME-13: lib 에서 ARB 제목 getter 를 읽는 파일 = app_title.dart 1곳 (D-12)',
      () {
        const titleFile = 'lib/core/l10n/app_title.dart';
        final readers = <String>{};
        for (final entity in Directory('lib').listSync(recursive: true)) {
          if (entity is! File || !entity.path.endsWith('.dart')) continue;
          final path = entity.path.replaceAll(r'\', '/');
          if (path.startsWith('lib/l10n/generated/')) continue;
          final code = stripSlashComments(entity.readAsStringSync());
          if (code.contains('.appTitle')) readers.add(path);
        }

        // 양성 대조 — 같은 순회가 제목 함수 파일을 찾는다.
        expect(readers, contains(titleFile));
        expect(readers, {titleFile});
        expect(
          countOccurrences(
            stripSlashComments(readTrackedFile(titleFile)),
            'appName.isEmpty ? l10n.appTitle : appName',
          ),
          1,
        );
      },
    );
  });
}
