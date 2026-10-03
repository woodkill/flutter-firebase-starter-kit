// Phase 17.1 D-14 · D-16 · D-17 — 데모 화면(`DemoScreen`) 위젯 테스트.
//
// T-171-DEMO-01: 실제 라우터의 `/settings/developer` GoRoute 1개 → DemoScreen ·
// production 배선(알림 리스너 · 공지 배너 · 게스트 바 · 테마 토글 · 언어
// 드롭다운) 0.

import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter_starter_kit/core/providers/firebase_providers.dart';
import 'package:flutter_starter_kit/core/router/app_router.dart';
import 'package:flutter_starter_kit/core/router/app_routes.dart';
import 'package:flutter_starter_kit/core/theme/app_theme.dart';
import 'package:flutter_starter_kit/features/auth/data/auth_repository.dart';
import 'package:flutter_starter_kit/features/auth/domain/user.dart';
import 'package:flutter_starter_kit/features/demo/presentation/demo_screen.dart';
import 'package:flutter_starter_kit/features/home/presentation/_widgets/announcement_bar.dart';
import 'package:flutter_starter_kit/features/home/presentation/_widgets/guest_banner.dart';
import 'package:flutter_starter_kit/features/notifications/presentation/pending_notification_route_listener.dart';
import 'package:flutter_starter_kit/l10n/generated/app_localizations.dart';

import '../../helpers/source_text.dart';

class _MockAuthRepository extends Mock implements AuthRepository {}

class _MockFirebaseAuth extends Mock implements fb.FirebaseAuth {}

/// 데모 화면 소스 경로 — import 줄 검사(D-17) 대상.
const String _demoSourcePath =
    'lib/features/demo/presentation/demo_screen.dart';

/// [DemoScreen] 을 [viewport] 크기 · DPR 1 로 띄운다.
///
/// 화면 전체 ListView 컨텐츠가 6000dp 를 넘으므로 기본 viewport 를 8000 으로
/// 키워 모든 카드 · 버튼이 한 번에 빌드되게 한다(lazy ListView 회피 — 옛 홈
/// 테스트와 같은 정책). Phase 16.7 H08 은 280dp 폭으로 overflow 0 을 본다.
Future<void> _pumpDemo(
  WidgetTester tester, {
  required User? user,
  _MockAuthRepository? mockRepo,
  Size viewport = const Size(800, 8000),
  bool isFirebaseInitialized = false,
  Locale locale = const Locale('en'),
}) async {
  tester.view.physicalSize = viewport;
  tester.view.devicePixelRatio = 1;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });

  await tester.pumpWidget(
    ProviderScope(
      key: UniqueKey(),
      overrides: [
        currentUserProvider.overrideWith((ref) => user),
        authRepositoryProvider.overrideWithValue(
          mockRepo ?? _MockAuthRepository(),
        ),
        isFirebaseInitializedProvider.overrideWithValue(isFirebaseInitialized),
        firebaseAuthProvider.overrideWithValue(_MockFirebaseAuth()),
      ],
      child: MaterialApp(
        theme: AppTheme.light(),
        locale: locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const DemoScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('Phase 17.1 데모 화면 (T-171-DEMO)', () {
    testWidgets('T-171-DEMO-01: /settings/developer GoRoute 1개 → DemoScreen · '
        'production 배선 · 테마 토글 · 언어 드롭다운 0 (D-14 · D-16 · D-17)', (
      tester,
    ) async {
      // (a) 실제 라우터 route 표 — 데모 경로 GoRoute 정확히 1개.
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
      final demoRoutes = router.configuration.routes
          .whereType<GoRoute>()
          .where((route) => route.path == AppRoutes.developerDemo)
          .toList();
      expect(demoRoutes, hasLength(1));
      expect(demoRoutes.single.name, AppRoutes.developerDemoName);

      await tester.pumpWidget(const SizedBox());
      final context = tester.element(find.byType(SizedBox));
      final state = GoRouterState(
        router.configuration,
        uri: Uri.parse(AppRoutes.developerDemo),
        matchedLocation: AppRoutes.developerDemo,
        fullPath: AppRoutes.developerDemo,
        pathParameters: const <String, String>{},
        pageKey: const ValueKey<String>(AppRoutes.developerDemo),
      );
      expect(demoRoutes.single.builder!(context, state), isA<DemoScreen>());

      // (b) 화면 — AppBar 제목 · actions 없음 · 빌드 환경 heading.
      await _pumpDemo(tester, user: null);
      final l10n = lookupAppLocalizations(const Locale('en'));
      expect(
        find.descendant(
          of: find.byType(AppBar),
          matching: find.text(l10n.demoScreenTitle),
        ),
        findsOneWidget,
      );
      expect(tester.widget<AppBar>(find.byType(AppBar)).actions, isNull);
      expect(find.text(l10n.homeBuildEnvironment), findsOneWidget);

      // (c) production 배선 · 테마 토글 · 언어 드롭다운 부재 (D-04 · D-17).
      expect(
        find.byType(PendingNotificationRouteListener, skipOffstage: false),
        findsNothing,
      );
      expect(find.byType(AnnouncementBar, skipOffstage: false), findsNothing);
      expect(find.byType(GuestBanner, skipOffstage: false), findsNothing);
      expect(
        find.byType(SegmentedButton<ThemeMode>, skipOffstage: false),
        findsNothing,
      );
      expect(
        find.byType(DropdownButton<Locale>, skipOffstage: false),
        findsNothing,
      );

      // (d) import 줄 — production 배선 파일 4종을 import 하지 않는다 (D-17).
      final importLines = readTrackedFile(_demoSourcePath)
          .split('\n')
          .where((line) => line.trimLeft().startsWith('import '))
          .toList();
      expect(importLines, isNotEmpty);
      for (final banned in <String>[
        'pending_notification_route_listener.dart',
        'announcement_bar.dart',
        'app_routes.dart',
        'theme_provider.dart',
      ]) {
        expect(
          importLines.where((line) => line.contains(banned)),
          isEmpty,
          reason: '데모는 $banned 를 import 하지 않는다 (D-17)',
        );
      }
    });
  });
}
