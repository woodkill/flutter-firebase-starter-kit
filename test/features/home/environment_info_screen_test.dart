import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter_starter_kit/core/providers/firebase_providers.dart';
import 'package:flutter_starter_kit/core/theme/app_theme.dart';
import 'package:flutter_starter_kit/features/auth/data/auth_repository.dart';
import 'package:flutter_starter_kit/features/auth/domain/user.dart';
import 'package:flutter_starter_kit/features/home/presentation/environment_info_screen.dart';
import 'package:flutter_starter_kit/l10n/generated/app_localizations.dart';

class _MockAuthRepository extends Mock implements AuthRepository {}

class _MockFirebaseAuth extends Mock implements fb.FirebaseAuth {}

/// EnvironmentInfoScreen 의 Account 섹션 위젯 테스트.
///
/// Plan 06-07 의 4 시나리오를 검증한다:
///   1. 비인증 시 Account 섹션 미표시 (D-36)
///   2. 인증 시 displayName/email/uid (truncated)/로그아웃 버튼 표시
///   3. 로그아웃 다이얼로그 취소 시 signOut 미호출
///   4. 로그아웃 다이얼로그 확인 시 signOut 호출
Future<void> _pumpScreen(
  WidgetTester tester, {
  required User? user,
  _MockAuthRepository? mockRepo,
}) async {
  final repo = mockRepo ?? _MockAuthRepository();
  // 화면 전체 ListView 컨텐츠가 약 6000dp 이상이므로 viewport 를 충분히
  // 키워 모든 카드/버튼이 한 번에 렌더되도록 한다 (lazy ListView 회피).
  // 260425-n31: _TypographySample 가 1행 → 3행 (라벨 + 영문 패가그램 + 한국어
  // 패가그램) 으로 확장되며 15 인스턴스 × 추가 라인으로 컨텐츠가 증가했다.
  // 안전 마진 포함하여 8000 으로 키운다 (dev_tools_test 와 동일 정책).
  tester.view.physicalSize = const Size(800, 8000);
  tester.view.devicePixelRatio = 1;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        currentUserProvider.overrideWith((ref) => user),
        authRepositoryProvider.overrideWithValue(repo),
        isFirebaseInitializedProvider.overrideWithValue(false),
        firebaseAuthProvider.overrideWithValue(_MockFirebaseAuth()),
      ],
      child: MaterialApp(
        theme: AppTheme.light(),
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const EnvironmentInfoScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// `_pumpScreen` 의 Firebase 연결 시나리오 변형.
///
/// `isFirebaseInitializedProvider` 만 다르게 override 하여 기존 Account 섹션
/// 테스트의 regression 을 차단한다. Quick task 260409-gyp Accessibility
/// 그룹 전용 헬퍼.
Future<void> _pumpScreenWithFirebase(
  WidgetTester tester, {
  required bool initialized,
}) async {
  // 260425-n31: viewport 8000 (위 _pumpScreen 과 동일 정책 — 패가그램 3행 확장
  // 후 컨텐츠가 6000dp 를 초과한다).
  tester.view.physicalSize = const Size(800, 8000);
  tester.view.devicePixelRatio = 1;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        currentUserProvider.overrideWith((ref) => null),
        authRepositoryProvider.overrideWithValue(_MockAuthRepository()),
        isFirebaseInitializedProvider.overrideWithValue(initialized),
        firebaseAuthProvider.overrideWithValue(_MockFirebaseAuth()),
      ],
      child: MaterialApp(
        theme: AppTheme.light(),
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const EnvironmentInfoScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('EnvironmentInfoScreen Account 섹션 (Phase 6)', () {
    testWidgets('비인증 시 Account 섹션 미표시 (D-36)', (tester) async {
      await _pumpScreen(tester, user: null);

      // Account 섹션 헤더 텍스트는 'Account' (en) 인데 다른 위치에 동일
      // 텍스트가 없도록 보장. 로그아웃 아이콘과 카드 라벨로 부재 확인.
      expect(find.text('Account', skipOffstage: false), findsNothing);
      expect(find.byIcon(Icons.logout, skipOffstage: false), findsNothing);
      expect(find.byIcon(Icons.fingerprint, skipOffstage: false), findsNothing);
    });

    testWidgets('인증 시 Account 섹션이 displayName/email/uid 표시', (tester) async {
      final user = User(
        uid: 'abcdefgh-rest-of-uid-12345',
        email: 'user@example.com',
        emailVerified: true,
        displayName: 'Test User',
        createdAt: DateTime.utc(2026, 1, 15),
      );

      await _pumpScreen(tester, user: user);

      expect(find.text('Account', skipOffstage: false), findsOneWidget);
      // displayName: CircleAvatar Row에 표시
      // (기존 _EnvironmentCard는 CircleAvatar Row로 교체됨).
      expect(find.text('Test User', skipOffstage: false), findsOneWidget);
      // email: CircleAvatar Row + _EnvironmentCard 양쪽에 표시.
      expect(
        find.text('user@example.com', skipOffstage: false),
        findsNWidgets(2),
      );
      // uid truncated to first 8 chars + '...'
      expect(find.text('abcdefgh...', skipOffstage: false), findsOneWidget);
      expect(find.byIcon(Icons.logout, skipOffstage: false), findsOneWidget);
    });

    testWidgets('로그아웃 버튼 탭 시 AlertDialog 표시, 취소 시 signOut 미호출', (tester) async {
      final user = User(
        uid: 'uid-cancel-1',
        email: 'a@b.com',
        emailVerified: true,
        displayName: 'A',
        createdAt: DateTime.utc(2026),
      );
      final mockRepo = _MockAuthRepository();
      when(() => mockRepo.signOut()).thenAnswer((_) async {});

      await _pumpScreen(tester, user: user, mockRepo: mockRepo);

      // 로그아웃 OutlinedButton 까지 스크롤
      await tester.scrollUntilVisible(
        find.byIcon(Icons.logout),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.byIcon(Icons.logout));
      await tester.pumpAndSettle();

      // 다이얼로그 등장 확인 (en: 'Are you sure you want to sign out?')
      expect(find.text('Are you sure you want to sign out?'), findsOneWidget);

      // Cancel 버튼은 다이얼로그 actions 안에만 존재
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      verifyNever(() => mockRepo.signOut());
    });

    testWidgets('로그아웃 다이얼로그 확인 시 authRepository.signOut() 호출', (tester) async {
      final user = User(
        uid: 'uid-confirm-1',
        email: 'a@b.com',
        emailVerified: true,
        displayName: 'A',
        createdAt: DateTime.utc(2026),
      );
      final mockRepo = _MockAuthRepository();
      when(() => mockRepo.signOut()).thenAnswer((_) async {});

      await _pumpScreen(tester, user: user, mockRepo: mockRepo);

      await tester.scrollUntilVisible(
        find.byIcon(Icons.logout),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.byIcon(Icons.logout));
      await tester.pumpAndSettle();

      // 'Sign out' 텍스트는 다이얼로그 title + 액션 버튼 양쪽에 존재한다
      // (authLogoutConfirmTitle == authAccountSignOut == "Sign out" en).
      // 액션 버튼만 타겟팅하기 위해 TextButton 자손을 찾는다.
      final dialogSignOutButton = find.descendant(
        of: find.byType(AlertDialog),
        matching: find.widgetWithText(TextButton, 'Sign out'),
      );
      expect(dialogSignOutButton, findsOneWidget);
      await tester.tap(dialogSignOutButton);
      await tester.pumpAndSettle();

      verify(() => mockRepo.signOut()).called(1);
    });
  });

  group('EnvironmentInfoScreen Account 섹션 (Phase 7 D-11/D-12)', () {
    testWidgets('providerIds [password] 시 "Email / Password" 표시 (D-11)', (
      tester,
    ) async {
      final user = User(
        uid: 'uid-provider-1',
        email: 'pw@example.com',
        emailVerified: true,
        displayName: 'PW User',
        createdAt: DateTime.utc(2026),
        providerIds: ['password'],
      );

      await _pumpScreen(tester, user: user);

      expect(
        find.text('Email / Password', skipOffstage: false),
        findsOneWidget,
      );
    });

    testWidgets('providerIds [password, google.com] 시 '
        '"Email / Password, Google" 표시 (D-11)', (tester) async {
      final user = User(
        uid: 'uid-provider-2',
        email: 'multi@example.com',
        emailVerified: true,
        displayName: 'Multi User',
        createdAt: DateTime.utc(2026),
        providerIds: ['password', 'google.com'],
      );

      await _pumpScreen(tester, user: user);

      expect(
        find.text('Email / Password, Google', skipOffstage: false),
        findsOneWidget,
      );
    });

    testWidgets('providerIds 빈 리스트 시 "-" 표시 (D-11 fallback)', (tester) async {
      final user = User(
        uid: 'uid-provider-3',
        email: 'empty@example.com',
        emailVerified: true,
        createdAt: DateTime.utc(2026),
      );

      await _pumpScreen(tester, user: user);

      // Providers 카드의 값이 '-'
      // (displayName도 null이므로 '-'가 복수 개 존재)
      final dashFinder = find.text('-', skipOffstage: false);
      expect(dashFinder, findsWidgets);
    });

    testWidgets('photoUrl null 시 CircleAvatar에 Icons.person 아이콘 표시 (D-12)', (
      tester,
    ) async {
      final user = User(
        uid: 'uid-avatar-1',
        email: 'no-photo@example.com',
        emailVerified: true,
        displayName: 'No Photo',
        createdAt: DateTime.utc(2026),
        providerIds: ['password'],
      );

      await _pumpScreen(tester, user: user);

      // CircleAvatar 존재
      expect(find.byType(CircleAvatar, skipOffstage: false), findsOneWidget);
      // CircleAvatar 내부에 person 아이콘 존재
      final personInAvatar = find.descendant(
        of: find.byType(CircleAvatar),
        matching: find.byIcon(Icons.person),
      );
      expect(personInAvatar, findsOneWidget);
    });

    testWidgets('CircleAvatar가 Semantics 위젯으로 래핑되어 있음 (D-12 접근성)', (
      tester,
    ) async {
      final user = User(
        uid: 'uid-avatar-2',
        email: 'sem@example.com',
        emailVerified: true,
        displayName: 'Semantic User',
        createdAt: DateTime.utc(2026),
        providerIds: ['google.com'],
      );

      await _pumpScreen(tester, user: user);

      // CircleAvatar의 직접 부모가 Semantics 위젯인지 확인
      final semanticsAncestor = find.ancestor(
        of: find.byType(CircleAvatar),
        matching: find.byType(Semantics),
      );
      expect(semanticsAncestor, findsWidgets);
    });

    testWidgets(
      '미지원 프로바이더 → l10n.errorUnknownProvider Localizable Unknown '
      'fallback (Phase 13 D-53 — raw slug 노출 차단)',
      (tester) async {
        // Phase 13 D-53: switch 에 매핑되지 않은 slug 는 l10n.errorUnknownProvider
        // 로 fallback (raw slug 노출 절대 금지). 기존 `_ => id` raw fallback 제거.
        final user = User(
          uid: 'uid-provider-4',
          email: 'raw@example.com',
          emailVerified: true,
          displayName: 'Raw',
          createdAt: DateTime.utc(2026),
          providerIds: ['twitter.com'],
        );

        await _pumpScreen(tester, user: user);

        // raw slug 'twitter.com' 미노출 — Localizable Unknown 으로 교체.
        expect(find.text('twitter.com', skipOffstage: false), findsNothing);
        // ko 로케일 (`_pumpScreen` 기본 — env 의 `Locale('ko')` 또는 en) 에 따른
        // Unknown 라벨 노출 검증. Phase 4 정책상 기본 en, l10n.errorUnknownProvider
        // 의 en 값.
        expect(
          find.text('Unknown sign-in method', skipOffstage: false),
          findsOneWidget,
        );
      },
    );

    testWidgets('providerIds [apple.com] 시 "Apple" 표시 (Phase 8)', (
      tester,
    ) async {
      final user = User(
        uid: 'uid-provider-apple',
        email: 'apple@example.com',
        emailVerified: true,
        displayName: 'Apple User',
        createdAt: DateTime.utc(2026),
        providerIds: ['apple.com'],
      );

      await _pumpScreen(tester, user: user);

      expect(find.text('Apple', skipOffstage: false), findsOneWidget);
    });
  });

  group('EnvironmentInfoScreen Accessibility (260409-gyp)', () {
    // SemanticsHandle 은 _endOfTestVerifications 시점에 살아 있으면 안 되므로
    // testWidgets 본문 끝에서 직접 dispose 한다 (addTearDown 사용 불가 —
    // teardown 콜백은 verification 이후에 실행됨).
    testWidgets('Firebase 미연결 카드는 Firebase Not Connected Semantics label 노출', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();

      // 기본 _pumpScreen 은 isFirebaseInitialized = false
      await _pumpScreen(tester, user: null);

      final firebaseSemantics = find.bySemanticsLabel('Firebase Not Connected');
      expect(firebaseSemantics, findsOneWidget);
      expect(
        tester.getSemantics(firebaseSemantics),
        matchesSemantics(label: 'Firebase Not Connected'),
      );

      handle.dispose();
    });

    testWidgets('Firebase 연결 카드는 Firebase Connected Semantics label 노출', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();

      await _pumpScreenWithFirebase(tester, initialized: true);

      final firebaseSemantics = find.bySemanticsLabel('Firebase Connected');
      expect(firebaseSemantics, findsOneWidget);
      expect(
        tester.getSemantics(firebaseSemantics),
        matchesSemantics(label: 'Firebase Connected'),
      );

      handle.dispose();
    });

    testWidgets('일반 카드는 fallback "label: value" Semantics label 노출', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();

      await _pumpScreen(tester, user: null);

      // Flavor 카드: String.fromEnvironment('flavor', defaultValue: 'dev')
      // → toUpperCase() = 'DEV', fallback label = 'Flavor: DEV'.
      expect(find.bySemanticsLabel('Flavor: DEV'), findsOneWidget);

      handle.dispose();
    });

    testWidgets(
      'Firebase 연결 카드는 _EnvStatus.ok chip Container 를 success 배경으로 렌더한다',
      (tester) async {
        await _pumpScreenWithFirebase(tester, initialized: true);

        // Firebase Connected 카드 Card 위젯을 찾는다 (en 로케일).
        // 'Connected' 텍스트(homeFirebaseConnected) 의 조상 Card 가 대상.
        final firebaseCard = find.ancestor(
          of: find.text('Connected'),
          matching: find.byType(Card),
        );
        expect(firebaseCard, findsOneWidget);

        // chip 컨테이너 (BoxDecoration 을 가진 Container) 를 찾는다.
        // _EnvStatus.ok 분기에서 정확히 1개 생성된다.
        final decoratedContainers = find
            .descendant(of: firebaseCard, matching: find.byType(Container))
            .evaluate()
            .map((e) => e.widget as Container)
            .where((c) => c.decoration is BoxDecoration)
            .toList();
        expect(decoratedContainers, hasLength(1));

        final decoration =
            decoratedContainers.first.decoration! as BoxDecoration;
        // Light 모드 success 색 = #FF2E7D32 (VERIFIED: app_colors.dart:29)
        expect(decoration.color, const Color(0xFF2E7D32));
      },
    );
  });
}
