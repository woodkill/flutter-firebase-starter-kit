// Phase 17.1 D-14 · D-16 · D-17 — 데모 화면(`DemoScreen`) 위젯 테스트.
//
// T-171-DEMO-01: 실제 라우터의 `/settings/developer` GoRoute 1개 → DemoScreen ·
// production 배선(알림 리스너 · 공지 배너 · 게스트 바 · 테마 토글 · 언어
// 드롭다운) 0.
// T-171-DEMO-02: UI-SPEC E7 overflow — 280×800 ko · en · ja 끝까지 스크롤 넘침 0.
//
// 옛 홈 테스트의 데모 몫(D-22) — 계정 디버그 카드(Phase 6 · 7 · 16.7 H01~H08 ·
// 가입 수단 카드) · 환경 카드 Semantics(260409-gyp) · 보호 예시(Phase 10 D-11) ·
// App smoke 「Flavor」 · 「Not Connected」 — 를 데모 화면 대상으로 다시 잠근다.

import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
import 'package:flutter_starter_kit/features/auth/presentation/_widgets/auth_required.dart';
import 'package:flutter_starter_kit/features/demo/presentation/demo_screen.dart';
import 'package:flutter_starter_kit/features/home/presentation/_widgets/announcement_bar.dart';
import 'package:flutter_starter_kit/features/home/presentation/_widgets/guest_banner.dart';
import 'package:flutter_starter_kit/features/notifications/presentation/pending_notification_route_listener.dart';
import 'package:flutter_starter_kit/l10n/generated/app_localizations.dart';

import '../../helpers/route_tree.dart';
import '../../helpers/source_text.dart';

class _MockAuthRepository extends Mock implements AuthRepository {}

class _MockFirebaseAuth extends Mock implements fb.FirebaseAuth {}

class _MockFbUser extends Mock implements fb.User {}

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
  fb.FirebaseAuth? firebaseAuth,
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
        firebaseAuthProvider.overrideWithValue(
          firebaseAuth ?? _MockFirebaseAuth(),
        ),
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

/// 연결된 계정 카드(`Card`) finder — 라벨 「Linked accounts」 의 조상 Card.
Finder _findLinkedAccountsCard() => find.ancestor(
  of: find.text('Linked accounts', skipOffstage: false),
  matching: find.byType(Card, skipOffstage: false),
);

/// 연결된 계정 카드 값 `Text.rich` 의 [WidgetSpan] 을 표시 순서대로 모은다.
///
/// 값 위젯은 `textSpan` 을 가진 `Text` 1개다 — WidgetSpan 안 라벨 `Text` 는
/// `data` 만 가지므로 predicate 로 구분된다.
List<WidgetSpan> _collectLinkedWidgetSpans(WidgetTester tester) {
  final valueText = tester.widget<Text>(
    find.descendant(
      of: _findLinkedAccountsCard(),
      matching: find.byWidgetPredicate(
        (widget) => widget is Text && widget.textSpan != null,
        skipOffstage: false,
      ),
    ),
  );
  final spans = <WidgetSpan>[];
  valueText.textSpan!.visitChildren((span) {
    if (span is WidgetSpan) spans.add(span);
    return true;
  });
  return spans;
}

/// 연결된 계정 카드의 semantics label 을 돌려준다 (`Linked accounts: …`).
String _readLinkedAccountsSemantics(WidgetTester tester) => tester
    .getSemantics(find.bySemanticsLabel(RegExp(r'^Linked accounts: ')))
    .label;

/// 표시 span 이 낭독 문자열에 새면 나타나는 문자 — 자리표시(U+FFFC) ·
/// WORD JOINER(U+2060) · NBSP(U+00A0). 소스에 보이지 않는 문자가 저장되지
/// 않도록 code point 로 만든다.
final List<String> _kInvisibleChars = <String>[
  String.fromCharCode(0xFFFC),
  String.fromCharCode(0x2060),
  String.fromCharCode(0x00A0),
];

/// 테스트 fixture 사용자 — Phase 16.7 H 케이스 공통.
User _buildSplitUser({
  required List<String> providerIds,
  String? signUpProviderId,
}) {
  return User(
    uid: 'uid-split-1',
    email: 'split@example.com',
    emailVerified: true,
    displayName: 'Split User',
    createdAt: DateTime.utc(2026),
    providerIds: providerIds,
    signUpProviderId: signUpProviderId,
  );
}

/// 플랫폼 채널 `Clipboard.setData` 의 텍스트를 [sink] 에 모은다 (테스트 끝에 해제).
void _captureClipboard(WidgetTester tester, List<String> sink) {
  final messenger = tester.binding.defaultBinaryMessenger;
  messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
    if (call.method == 'Clipboard.setData') {
      final args = call.arguments as Map<Object?, Object?>;
      sink.add(args['text']! as String);
    }
    return null;
  });
  addTearDown(
    () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
  );
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
      // Phase 17.2 — 전체 경로를 findMatch 로 조회(트리 깊이 독립).
      final GoRoute demoRoute = findGoRouteByPath(
        router.configuration,
        AppRoutes.developerDemo,
      );
      expect(demoRoute.name, AppRoutes.developerDemoName);

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
      expect(demoRoute.builder!(context, state), isA<DemoScreen>());

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

  group('데모 화면 계정 디버그 카드 (Phase 6 · 옛 홈 Account 섹션)', () {
    testWidgets('비인증 시 계정 디버그 카드 미표시 (D-36)', (tester) async {
      await _pumpDemo(tester, user: null);
      final l10n = lookupAppLocalizations(const Locale('en'));

      expect(
        find.text(l10n.demoAccountDebugSection, skipOffstage: false),
        findsNothing,
      );
      expect(find.byIcon(Icons.fingerprint, skipOffstage: false), findsNothing);
      expect(find.byIcon(Icons.how_to_reg, skipOffstage: false), findsNothing);
      expect(find.byIcon(Icons.key, skipOffstage: false), findsNothing);
    });

    testWidgets('인증 시 제목 · UID 8자 표시 — 이름 · 이메일 · 가입일 · 아바타 · '
        '로그아웃은 계정 화면 몫 (D-01 · D-16)', (tester) async {
      final user = User(
        uid: 'abcdefgh-rest-of-uid-12345',
        email: 'user@example.com',
        emailVerified: true,
        displayName: 'Test User',
        createdAt: DateTime.utc(2026, 1, 15),
      );

      await _pumpDemo(tester, user: user);
      final l10n = lookupAppLocalizations(const Locale('en'));

      expect(
        find.text(l10n.demoAccountDebugSection, skipOffstage: false),
        findsOneWidget,
      );
      // uid truncated to first 8 chars + '...'
      expect(find.text('abcdefgh...', skipOffstage: false), findsOneWidget);
      expect(find.text('Test User', skipOffstage: false), findsNothing);
      expect(find.text('user@example.com', skipOffstage: false), findsNothing);
      expect(
        find.byIcon(Icons.calendar_today, skipOffstage: false),
        findsNothing,
      );
      expect(find.byType(CircleAvatar, skipOffstage: false), findsNothing);
      expect(find.byIcon(Icons.logout, skipOffstage: false), findsNothing);
      expect(find.byType(AlertDialog), findsNothing);
    });

    testWidgets('UID 카드 탭 → 전체 UID 클립보드 복사 · 「Copied」 SnackBar (D-16)', (
      tester,
    ) async {
      final copied = <String>[];
      _captureClipboard(tester, copied);
      final user = User(
        uid: 'abcdefgh-rest-of-uid-12345',
        email: 'user@example.com',
        emailVerified: true,
        createdAt: DateTime.utc(2026),
      );

      await _pumpDemo(tester, user: user);
      final l10n = lookupAppLocalizations(const Locale('en'));
      await tester.tap(find.text('abcdefgh...'));
      await tester.pumpAndSettle();

      expect(copied, ['abcdefgh-rest-of-uid-12345']);
      expect(find.text(l10n.authAccountCopied), findsOneWidget);
    });

    testWidgets('ID 토큰 복사(kDebugMode) — 성공 시 공유 금지 · 만료 경고 문구 '
        '(T-17.1-16 · IN-05)', (tester) async {
      final copied = <String>[];
      _captureClipboard(tester, copied);
      final fbUser = _MockFbUser();
      when(() => fbUser.getIdToken()).thenAnswer((_) async => 'id-token-171');
      final mockAuth = _MockFirebaseAuth();
      when(() => mockAuth.currentUser).thenReturn(fbUser);

      await _pumpDemo(
        tester,
        user: _buildSplitUser(providerIds: ['password']),
        firebaseAuth: mockAuth,
      );
      final l10n = lookupAppLocalizations(const Locale('en'));
      await tester.tap(find.text(l10n.authAccountCopyToken));
      await tester.pumpAndSettle();

      expect(copied, ['id-token-171']);
      expect(find.text(l10n.debugAuthTokenCopiedWarning), findsOneWidget);
      expect(find.text(l10n.authAccountCopied), findsNothing);
    });

    testWidgets('ID 토큰 복사 — 토큰 없음이면 복사 0 · 「unavailable」 SnackBar '
        '(T-17.1-16)', (tester) async {
      final copied = <String>[];
      _captureClipboard(tester, copied);
      final mockAuth = _MockFirebaseAuth();
      when(() => mockAuth.currentUser).thenReturn(null);

      await _pumpDemo(
        tester,
        user: _buildSplitUser(providerIds: ['password']),
        firebaseAuth: mockAuth,
      );
      final l10n = lookupAppLocalizations(const Locale('en'));
      await tester.tap(find.text(l10n.authAccountCopyToken));
      await tester.pumpAndSettle();

      expect(copied, isEmpty);
      expect(find.text(l10n.debugAuthTokenUnavailable), findsOneWidget);
    });
  });

  group('데모 화면 계정 디버그 카드 (Phase 7 D-11/D-12)', () {
    testWidgets('providerIds [password] 시 연결된 계정 "Email / Password" 표시 '
        '(D-11 · 16.7 재작성)', (tester) async {
      final handle = tester.ensureSemantics();
      final user = User(
        uid: 'uid-provider-1',
        email: 'pw@example.com',
        emailVerified: true,
        displayName: 'PW User',
        createdAt: DateTime.utc(2026),
        providerIds: ['password'],
      );

      await _pumpDemo(tester, user: user);

      // 기록 없음(null) → 가입 수단 「-」 · 연결된 계정 = 보유 전부 (D-11).
      // 라벨 1개 = WidgetSpan 안 Text 1개라 항목 find.text 로 확인한다.
      expect(
        find.text('Email / Password', skipOffstage: false),
        findsOneWidget,
      );
      expect(find.bySemanticsLabel('Sign-up method: -'), findsOneWidget);
      expect(
        find.bySemanticsLabel('Linked accounts: Email / Password'),
        findsOneWidget,
      );

      handle.dispose();
    });

    testWidgets('providerIds [password, google.com] 시 연결된 계정 '
        '"Google, Email / Password" 표시 (D-05 · 16.7 재작성)', (tester) async {
      final handle = tester.ensureSemantics();
      final user = User(
        uid: 'uid-provider-2',
        email: 'multi@example.com',
        emailVerified: true,
        displayName: 'Multi User',
        createdAt: DateTime.utc(2026),
        providerIds: ['password', 'google.com'],
      );

      await _pumpDemo(tester, user: user);

      // Text.rich 의 plain text 는 WidgetSpan 자리표시 문자를 담아 전체 목록
      // find.text 는 매칭 0 — 전체 목록은 semantics, 항목은 WidgetSpan Text.
      expect(
        find.bySemanticsLabel('Linked accounts: Google, Email / Password'),
        findsOneWidget,
      );
      expect(find.text('Google,', skipOffstage: false), findsOneWidget);
      expect(
        find.text('Email / Password', skipOffstage: false),
        findsOneWidget,
      );

      handle.dispose();
    });

    testWidgets('providerIds 빈 리스트 시 가입 수단 "-" · 연결된 계정 "None" 표시 '
        '(D-03 · D-11 · 16.7 재작성)', (tester) async {
      final handle = tester.ensureSemantics();
      final user = User(
        uid: 'uid-provider-3',
        email: 'empty@example.com',
        emailVerified: true,
        createdAt: DateTime.utc(2026),
      );

      await _pumpDemo(tester, user: user);

      expect(find.bySemanticsLabel('Sign-up method: -'), findsOneWidget);
      expect(find.bySemanticsLabel('Linked accounts: None'), findsOneWidget);
      expect(find.text('None', skipOffstage: false), findsOneWidget);

      handle.dispose();
    });

    testWidgets('미지원 프로바이더 → l10n.errorUnknownProvider Localizable Unknown '
        'fallback (Phase 13 D-53 — raw slug 노출 차단 · 16.7 재작성)', (tester) async {
      // Phase 13 D-53: switch 에 매핑되지 않은 slug 는 l10n.errorUnknownProvider
      // 로 fallback (raw slug 노출 절대 금지).
      // Phase 16.7: 기록 null 이면 연결된 계정 카드가 보유 전부를 표시한다.
      final handle = tester.ensureSemantics();
      final user = User(
        uid: 'uid-provider-4',
        email: 'raw@example.com',
        emailVerified: true,
        displayName: 'Raw',
        createdAt: DateTime.utc(2026),
        providerIds: ['twitter.com'],
      );

      await _pumpDemo(tester, user: user);

      // raw slug 'twitter.com' 미노출 — Localizable Unknown 으로 교체.
      expect(find.text('twitter.com', skipOffstage: false), findsNothing);
      expect(
        find.text('Unknown sign-in method', skipOffstage: false),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel('Linked accounts: Unknown sign-in method'),
        findsOneWidget,
      );

      handle.dispose();
    });

    testWidgets('providerIds [apple.com] 시 연결된 계정 "Apple" 표시 '
        '(Phase 8 · 16.7 재작성)', (tester) async {
      final handle = tester.ensureSemantics();
      final user = User(
        uid: 'uid-provider-apple',
        email: 'apple@example.com',
        emailVerified: true,
        displayName: 'Apple User',
        createdAt: DateTime.utc(2026),
        providerIds: ['apple.com'],
      );

      await _pumpDemo(tester, user: user);

      expect(find.text('Apple', skipOffstage: false), findsOneWidget);
      expect(find.bySemanticsLabel('Linked accounts: Apple'), findsOneWidget);

      handle.dispose();
    });
  });

  group('데모 화면 Accessibility (260409-gyp)', () {
    // SemanticsHandle 은 _endOfTestVerifications 시점에 살아 있으면 안 되므로
    // testWidgets 본문 끝에서 직접 dispose 한다 (addTearDown 사용 불가 —
    // teardown 콜백은 verification 이후에 실행됨).
    testWidgets('Firebase 미연결 카드는 Firebase Not Connected Semantics label 노출', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();

      // 기본 _pumpDemo 는 isFirebaseInitialized = false
      await _pumpDemo(tester, user: null);

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

      await _pumpDemo(tester, user: null, isFirebaseInitialized: true);

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

      await _pumpDemo(tester, user: null);

      // Flavor 카드: AppConfig.flavor 단일 진실원 (CR-01). 테스트 환경은
      // --dart-define 미주입이므로 빈 문자열 → '-' + warn chip,
      // fallback label = 'Flavor: -'.
      expect(find.bySemanticsLabel('Flavor: -'), findsOneWidget);

      handle.dispose();
    });

    testWidgets(
      'Firebase 연결 카드는 _EnvStatus.ok chip Container 를 success 배경으로 렌더한다',
      (tester) async {
        await _pumpDemo(tester, user: null, isFirebaseInitialized: true);

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

    testWidgets('빌드 환경 카드 「Flavor」 · 「Not Connected」 표시 '
        '(옛 App smoke 단언 이전 · plan 03 D-22)', (tester) async {
      await _pumpDemo(tester, user: null);

      expect(find.text('Flavor'), findsOneWidget);
      expect(find.text('Not Connected'), findsOneWidget);
    });
  });

  group('Phase 16.7 가입 수단 카드 (D-01 · D-11)', () {
    testWidgets('signUpProviderId=password 시 가입 수단 카드가 '
        '"Sign-up method: Email / Password" 로 노출 (D-01)', (tester) async {
      final handle = tester.ensureSemantics();
      final user = User(
        uid: 'uid-signup-1',
        email: 'signup@example.com',
        emailVerified: true,
        displayName: 'Sign-up User',
        createdAt: DateTime.utc(2026),
        providerIds: ['password'],
        signUpProviderId: 'password',
      );

      await _pumpDemo(tester, user: user);

      expect(
        find.bySemanticsLabel('Sign-up method: Email / Password'),
        findsOneWidget,
      );

      handle.dispose();
    });

    testWidgets('signUpProviderId null 시 가입 수단 카드가 '
        '"Sign-up method: -" 로 노출 (D-11 — 추론 0)', (tester) async {
      final handle = tester.ensureSemantics();
      final user = User(
        uid: 'uid-signup-2',
        email: 'legacy@example.com',
        emailVerified: true,
        displayName: 'Legacy User',
        createdAt: DateTime.utc(2026),
        providerIds: ['password'],
      );

      await _pumpDemo(tester, user: user);

      expect(find.bySemanticsLabel('Sign-up method: -'), findsOneWidget);

      handle.dispose();
    });
  });

  group('Phase 16.7 카드 2장 (D-01 · D-03 · D-05 · D-06 · D-11 · D-12)', () {
    testWidgets('16.7-H01 가입 수단 · 연결된 계정 카드 2장 — 옛 카드 부재 (D-01)', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();

      await _pumpDemo(
        tester,
        user: _buildSplitUser(
          providerIds: ['google.com', 'kakao', 'password'],
          signUpProviderId: 'google.com',
        ),
      );

      expect(find.text('Sign-up method', skipOffstage: false), findsOneWidget);
      expect(find.text('Linked accounts', skipOffstage: false), findsOneWidget);
      expect(find.bySemanticsLabel('Sign-up method: Google'), findsOneWidget);
      expect(
        find.bySemanticsLabel('Linked accounts: Kakao, Email / Password'),
        findsOneWidget,
      );
      expect(
        find.byIcon(Icons.how_to_reg, skipOffstage: false),
        findsOneWidget,
      );
      expect(find.byIcon(Icons.link, skipOffstage: false), findsOneWidget);
      expect(find.byIcon(Icons.security, skipOffstage: false), findsNothing);
      // H08 — overflow 0.
      expect(tester.takeException(), isNull);

      handle.dispose();
    });

    testWidgets('16.7-H02 연결 0개 — 카드 유지 · 「None」 TextSpan (D-03)', (
      tester,
    ) async {
      await _pumpDemo(
        tester,
        user: _buildSplitUser(
          providerIds: ['google.com'],
          signUpProviderId: 'google.com',
        ),
      );

      expect(_findLinkedAccountsCard(), findsOneWidget);
      expect(find.text('None', skipOffstage: false), findsOneWidget);
      expect(_collectLinkedWidgetSpans(tester), isEmpty);
      expect(tester.takeException(), isNull);
    });

    testWidgets('16.7-H03 기록 null — 가입 수단 「-」 · 연결 = 보유 전부 (D-11)', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();

      await _pumpDemo(
        tester,
        user: _buildSplitUser(
          providerIds: [
            'password',
            'line',
            'naver',
            'kakao',
            'facebook.com',
            'apple.com',
            'google.com',
          ],
        ),
      );

      expect(find.bySemanticsLabel('Sign-up method: -'), findsOneWidget);
      expect(
        find.bySemanticsLabel(
          'Linked accounts: Google, Apple, Facebook, Kakao, Naver, LINE, '
          'Email / Password',
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);

      handle.dispose();
    });

    testWidgets('16.7-H04 미보유 · 미지 기록값 — 그대로 표시 · raw 노출 0 (D-12)', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();

      await _pumpDemo(
        tester,
        user: _buildSplitUser(
          providerIds: ['password'],
          signUpProviderId: 'twitter.com',
        ),
      );

      expect(
        find.bySemanticsLabel('Sign-up method: Unknown sign-in method'),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel('Linked accounts: Email / Password'),
        findsOneWidget,
      );
      expect(find.textContaining('twitter', skipOffstage: false), findsNothing);
      expect(tester.takeException(), isNull);

      handle.dispose();
    });

    testWidgets('16.7-H05 연결 카드 semantics — 보이지 않는 문자 0 · 전체 목록', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();

      await _pumpDemo(
        tester,
        user: _buildSplitUser(
          providerIds: ['google.com', 'kakao', 'line', 'password'],
          signUpProviderId: 'google.com',
        ),
      );

      final label = _readLinkedAccountsSemantics(tester);
      expect(label, 'Linked accounts: Kakao, LINE, Email / Password');
      for (final char in _kInvisibleChars) {
        expect(label.contains(char), isFalse);
      }
      expect(tester.takeException(), isNull);

      handle.dispose();
    });

    testWidgets('16.7-H06 연결 순서 = kAllProviderIds 순 + 이메일 끝 (D-05)', (
      tester,
    ) async {
      await _pumpDemo(
        tester,
        user: _buildSplitUser(
          providerIds: ['password', 'line', 'google.com', 'kakao'],
        ),
      );

      final labels = _collectLinkedWidgetSpans(
        tester,
      ).map((span) => (span.child as Text).data).toList();
      expect(labels, ['Google,', 'Kakao,', 'LINE,', 'Email / Password']);
      expect(tester.takeException(), isNull);
    });

    testWidgets('16.7-H07 게스트 — 가입 수단 「-」 · 연결 「None」 (D-06)', (tester) async {
      final handle = tester.ensureSemantics();

      await _pumpDemo(tester, user: _buildSplitUser(providerIds: []));

      expect(find.bySemanticsLabel('Sign-up method: -'), findsOneWidget);
      expect(find.text('None', skipOffstage: false), findsOneWidget);
      expect(tester.takeException(), isNull);

      handle.dispose();
    });

    testWidgets('16.7-H08 280dp · 보유 전부 + 미지 값 — overflow 0 (D-02 개정)', (
      tester,
    ) async {
      await _pumpDemo(
        tester,
        user: _buildSplitUser(
          providerIds: [
            'google.com',
            'apple.com',
            'facebook.com',
            'kakao',
            'naver',
            'line',
            'twitter.com',
            'password',
          ],
          signUpProviderId: 'github.com',
        ),
        // 280dp 폭에서는 본문이 길어져 계정 디버그 카드까지 한 번에 렌더되도록
        // 높이를 더 키운다 (lazy ListView 회피 — _pumpDemo 와 같은 정책).
        viewport: const Size(280, 20000),
      );

      // maxLines 없이 전부 표시 — 항목 8개가 모두 WidgetSpan 으로 존재한다.
      expect(_collectLinkedWidgetSpans(tester), hasLength(8));
      expect(tester.takeException(), isNull);
    });
  });

  group('데모 화면 보호 예시 (Phase 10 D-11)', () {
    for (final signedIn in <bool>[false, true]) {
      testWidgets('보호 예시 섹션이 항상 렌더 + AuthRequired 래핑 OutlinedButton '
          '(${signedIn ? '로그인' : '비로그인'})', (tester) async {
        await _pumpDemo(
          tester,
          user: signedIn ? _buildSplitUser(providerIds: ['password']) : null,
        );
        final l10n = lookupAppLocalizations(const Locale('en'));

        expect(
          find.text(l10n.homeProtectedExampleTitle),
          findsOneWidget,
          reason: '보호 예시 섹션은 로그인 여부와 관계없이 항상 렌더',
        );
        expect(find.text(l10n.homeProtectedExampleBody), findsOneWidget);
        final cta = find.widgetWithText(
          OutlinedButton,
          l10n.homeProtectedExampleCta,
        );
        expect(cta, findsOneWidget, reason: 'AuthRequired 래핑된 OutlinedButton');
        expect(
          find.ancestor(of: cta, matching: find.byType(AuthRequired)),
          findsOneWidget,
        );
      });
    }
  });

  group('Phase 17.1 데모 화면 E7 overflow (T-171-DEMO-02)', () {
    for (final locale in const [Locale('ko'), Locale('en'), Locale('ja')]) {
      testWidgets(
        'T-171-DEMO-02 ${locale.languageCode} 280x800 — 끝까지 스크롤 · 넘침 0 '
        '(UI-SPEC E7 overflow)',
        (tester) async {
          await _pumpDemo(
            tester,
            user: _buildSplitUser(
              providerIds: [
                'google.com',
                'apple.com',
                'facebook.com',
                'kakao',
                'naver',
                'line',
                'password',
              ],
              signUpProviderId: 'line',
            ),
            viewport: const Size(280, 800),
            locale: locale,
          );
          expect(tester.takeException(), isNull);
          final l10n = lookupAppLocalizations(locale);

          final position = tester
              .state<ScrollableState>(find.byType(Scrollable).first)
              .position;
          expect(
            position.maxScrollExtent,
            greaterThan(0),
            reason: '넘치는 내용은 ListView 스크롤로 닿는다',
          );
          // 뷰포트 반 칸씩 내리며 매 frame 의 layout 예외를 확인한다(lazy
          // ListView 의 모든 항목이 한 번씩 layout 된다).
          var steps = 0;
          while (position.pixels < position.maxScrollExtent) {
            position.jumpTo(
              (position.pixels + 400).clamp(0.0, position.maxScrollExtent),
            );
            await tester.pump();
            expect(tester.takeException(), isNull);
            steps++;
            expect(steps, lessThan(500), reason: '스크롤 끝에 도달해야 한다');
          }
          await tester.pumpAndSettle();
          // 목록 끝(Dev Tools 강제 로그아웃 · kDebugMode)까지 닿았다.
          expect(find.text(l10n.devToolsForceSignOut), findsOneWidget);
          expect(tester.takeException(), isNull);
        },
      );
    }
  });
}
