// 계정 연결 절의 아이콘 줄 시험.
//
// 시험 전용 자리 `debugAccountLinkIconPreview` 를 채우면 절이 제목 → 안내
// 문구 → 원형 아이콘 줄을 그린다. 비우면 지금의 글자 버튼 목록 그대로다.
// 크기 · 간격 · 로고 비율은 시험이 인자로 넣는다 — 승인값이 아니다.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_starter_kit/core/auth/auth_strategies_registry.dart';
import 'package:flutter_starter_kit/core/auth/auth_strategy.dart';
import 'package:flutter_starter_kit/core/auth/provider_id.dart';
import 'package:flutter_starter_kit/core/auth/strategies/apple_auth_strategy.dart';
import 'package:flutter_starter_kit/core/auth/strategies/facebook_auth_strategy.dart';
import 'package:flutter_starter_kit/core/auth/strategies/google_auth_strategy.dart';
import 'package:flutter_starter_kit/core/auth/strategies/kakao_auth_strategy.dart';
import 'package:flutter_starter_kit/core/auth/strategies/line_auth_strategy.dart';
import 'package:flutter_starter_kit/core/auth/strategies/naver_auth_strategy.dart';
import 'package:flutter_starter_kit/core/error/result.dart';
import 'package:flutter_starter_kit/core/router/app_routes.dart';
import 'package:flutter_starter_kit/core/theme/app_theme.dart';
import 'package:flutter_starter_kit/core/theme/brand_focus_wrapper.dart';
import 'package:flutter_starter_kit/features/auth/data/auth_repository.dart';
import 'package:flutter_starter_kit/features/auth/domain/user.dart';
import 'package:flutter_starter_kit/features/auth/presentation/_widgets/auth_in_progress_overlay.dart';
import 'package:flutter_starter_kit/features/auth/presentation/_widgets/branded_social_button.dart';
import 'package:flutter_starter_kit/features/settings/application/account_link_in_progress.dart';
import 'package:flutter_starter_kit/features/settings/presentation/_widgets/account_linking_section.dart';
import 'package:flutter_starter_kit/l10n/generated/app_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';

class _MockAuthRepository extends Mock implements AuthRepository {}

/// 활성 소셜 Strategy 6종 — 후보 규칙을 결정적으로 고정한다.
const _allStrategies = <AuthStrategy>[
  GoogleAuthStrategy(),
  AppleAuthStrategy(),
  FacebookAuthStrategy(),
  KakaoAuthStrategy(),
  NaverAuthStrategy(),
  LineAuthStrategy(),
];

/// 관통 시험이 쓰는 미리보기 값 — 크기 48 · 간격 8 · 「절반」 비율.
const AccountLinkIconPreview _halfPreview = (
  iconSize: 48,
  gap: 8,
  appleLogoHeightRatio: 1.2,
  naverLogoHeightRatio: 0.45,
  lineLogoHeightRatio: 0.5,
);

/// 미연결 6 — 이메일로 가입해 소셜 연결이 하나도 없다.
const _unlinkedSixProviderIds = <String>['password'];

/// en 스크린 리더 라벨 — 킷 표준 순서(google · apple · facebook · kakao ·
/// naver · line).
const _enLabelsInOrder = <String>[
  'Link Google',
  'Link Apple',
  'Link Facebook',
  'Link Kakao',
  'Link Naver',
  'Link LINE',
];

/// 시험용 사용자를 만든다.
User _buildUser({required List<String> providerIds}) {
  return User(
    uid: 'uid-1',
    email: 'me@example.com',
    emailVerified: true,
    createdAt: DateTime.utc(2026),
    providerIds: providerIds,
  );
}

/// 계정 연결 절을 [width] 폭 화면에 올린다.
///
/// [preview] 를 시험 전용 자리에 넣고 GoRouter · ProviderScope 안에서
/// pump 한다. 화면 크기는 시험이 끝나면 되돌린다.
Future<void> _pumpSection(
  WidgetTester tester, {
  required User user,
  required AuthRepository repo,
  required double width,
  required AccountLinkIconPreview? preview,
  Locale locale = const Locale('en'),
  List<Override> extraOverrides = const <Override>[],
  bool shouldSettle = true,
}) async {
  tester.view.physicalSize = Size(width, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  debugAccountLinkIconPreview = preview;

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
        activeStrategiesProvider.overrideWith((ref) => _allStrategies),
        ...extraOverrides,
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
  if (shouldSettle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
  }
}

/// 크기 44 · 간격 8 미리보기 값 — 원 밖 · 칸 안 누르는 영역을 볼 때 쓴다.
const AccountLinkIconPreview _smallPreview = (
  iconSize: 44,
  gap: 8,
  appleLogoHeightRatio: 1.2,
  naverLogoHeightRatio: 0.45,
  lineLogoHeightRatio: 0.5,
);

/// 절의 가로 여백 (dp) — 화면 폭에서 아이콘 줄 가용 폭을 구할 때 뺀다.
const double _sectionGutter = 16;

/// 그려진 아이콘 칸(포커스 테두리 래퍼)의 사각형을 트리 순서대로 돌려준다.
List<Rect> _readSlotRects(WidgetTester tester) {
  final slots = find.descendant(
    of: find.byType(BrandedSocialIconButton),
    matching: find.byType(BrandFocusWrapper),
  );
  return <Rect>[
    for (var i = 0; i < slots.evaluate().length; i++)
      tester.getRect(slots.at(i)),
  ];
}

/// 칸 사각형을 위쪽 좌표가 같은 것끼리 줄로 묶는다.
List<List<Rect>> _groupRows(List<Rect> slots) {
  final rows = <List<Rect>>[];
  for (final slot in slots) {
    if (rows.isNotEmpty && rows.last.first.top == slot.top) {
      rows.last.add(slot);
    } else {
      rows.add(<Rect>[slot]);
    }
  }
  return rows;
}

/// [provider] 아이콘의 칸 사각형을 돌려준다.
Rect _readSlotOf(WidgetTester tester, AccountProvider provider) {
  return tester.getRect(
    find.descendant(
      of: find.byKey(ValueKey(provider)),
      matching: find.byType(BrandFocusWrapper),
    ),
  );
}

/// 미리보기 값의 줄 나누기 기대값을 화면 폭 [width] 에서 구한다.
List<int> _resolveExpectedRows(double width, AccountLinkIconPreview preview) {
  return resolveBrandIconRowCounts(
    _enLabelsInOrder.length,
    maxWidth: width - 2 * _sectionGutter,
    iconSize: preview.iconSize,
    gap: preview.gap,
  );
}

void main() {
  late _MockAuthRepository repo;

  setUpAll(() {
    registerFallbackValue(AccountProvider.google);
  });

  setUp(() {
    repo = _MockAuthRepository();
  });

  tearDown(() => debugAccountLinkIconPreview = null);

  group('계정 연결 아이콘 줄 — 관통', () {
    testWidgets('T-25-ICON-01 미리보기 값 → 안내 문구 · 아이콘 6 · 라벨 순서 · Apple 탭 → '
        '연결 성공 스낵바', (tester) async {
      final user = _buildUser(providerIds: _unlinkedSixProviderIds);
      when(
        () => repo.linkAppleCredential(),
      ).thenAnswer((_) async => Result.success(user));
      final semantics = tester.ensureSemantics();

      await _pumpSection(
        tester,
        user: user,
        repo: repo,
        width: 280,
        preview: _halfPreview,
      );

      expect(find.text('Add another way to sign in.'), findsOneWidget);
      expect(find.byType(BrandedSocialIconButton), findsNWidgets(6));
      expect(find.byType(BrandedSocialButton), findsNothing);

      // 라벨은 아이콘마다 한 번 · 읽는 순서(위 → 아래 · 왼쪽 → 오른쪽)가
      // 킷 표준 순서와 같다.
      Offset? previous;
      for (final label in _enLabelsInOrder) {
        final finder = find.bySemanticsLabel(label);
        expect(finder, findsOneWidget, reason: '$label 라벨은 한 번');
        final center = tester.getCenter(finder);
        if (previous != null) {
          final isSameRowAfter =
              center.dy == previous.dy && center.dx > previous.dx;
          final isNextRow = center.dy > previous.dy;
          expect(
            isSameRowAfter || isNextRow,
            isTrue,
            reason: '$label 은 앞 아이콘 뒤에 놓인다',
          );
        }
        previous = center;
      }

      await tester.tap(find.bySemanticsLabel('Link Apple'));
      await tester.pumpAndSettle();

      verify(() => repo.linkAppleCredential()).called(1);
      expect(find.text('Linked your Apple account.'), findsOneWidget);
      semantics.dispose();
    });

    testWidgets('T-25-ICON-02 미리보기 값 null → 안내 문구 0 · 글자 버튼 6 · 아이콘 0', (
      tester,
    ) async {
      await _pumpSection(
        tester,
        user: _buildUser(providerIds: _unlinkedSixProviderIds),
        repo: repo,
        width: 280,
        preview: null,
      );

      expect(find.text('Add another way to sign in.'), findsNothing);
      expect(find.byType(BrandedSocialButton), findsNWidgets(6));
      expect(find.byType(BrandedSocialIconButton), findsNothing);
    });
  });

  group('계정 연결 아이콘 줄 — 자동 맞춤 · 라벨 · 누르는 영역 · 진행 중', () {
    for (final width in <double>[280, 411]) {
      testWidgets(
        'T-25-ICON-${width == 280 ? '03' : '07'} 폭 ${width.toInt()} · 미연결 6 → '
        '줄 나누기 함수 결과대로 · 줄 사이 = 간격 · 시작 정렬',
        (tester) async {
          await _pumpSection(
            tester,
            user: _buildUser(providerIds: _unlinkedSixProviderIds),
            repo: repo,
            width: width,
            preview: _halfPreview,
          );

          final rows = _groupRows(_readSlotRects(tester));
          expect(
            rows.map((row) => row.length).toList(),
            _resolveExpectedRows(width, _halfPreview),
            reason: '줄별 칸 수',
          );
          for (final row in rows) {
            expect(row.first.left, _sectionGutter, reason: '시작 정렬');
            for (var i = 1; i < row.length; i++) {
              expect(
                row[i].left - row[i - 1].right,
                _halfPreview.gap,
                reason: '칸 사이 = 간격',
              );
            }
          }
          for (var i = 1; i < rows.length; i++) {
            expect(
              rows[i].first.top - rows[i - 1].first.bottom,
              _halfPreview.gap,
              reason: '줄 사이 = 간격',
            );
          }
        },
      );
    }

    testWidgets('T-25-ICON-04 라벨은 아이콘마다 한 번 — 툴팁은 있고 semantics 툴팁은 '
        '비어 있다', (tester) async {
      final semantics = tester.ensureSemantics();
      await _pumpSection(
        tester,
        user: _buildUser(providerIds: _unlinkedSixProviderIds),
        repo: repo,
        width: 411,
        preview: _halfPreview,
      );

      for (final label in _enLabelsInOrder) {
        final finder = find.bySemanticsLabel(label);
        expect(finder, findsOneWidget, reason: '$label 라벨 노드 1개');
        expect(
          tester.getSemantics(finder).getSemanticsData().tooltip,
          isEmpty,
          reason: '$label 툴팁은 semantics 에 없다',
        );
        expect(find.byTooltip(label), findsOneWidget, reason: '$label 툴팁');
      }
      semantics.dispose();
    });

    testWidgets('T-25-ICON-05 원 밖 · 칸 안 한 점을 누르면 연결이 한 번 불린다', (tester) async {
      final user = _buildUser(providerIds: _unlinkedSixProviderIds);
      when(
        () => repo.linkAppleCredential(),
      ).thenAnswer((_) async => Result.success(user));
      final semantics = tester.ensureSemantics();
      await _pumpSection(
        tester,
        user: user,
        repo: repo,
        width: 280,
        preview: _smallPreview,
      );

      final slot = _readSlotOf(tester, AccountProvider.apple);
      await tester.tapAt(
        slot.center - Offset(0, _smallPreview.iconSize / 2 + 1),
      );
      await tester.pumpAndSettle();

      verify(() => repo.linkAppleCredential()).called(1);
      expect(find.text('Linked your Apple account.'), findsOneWidget);
      semantics.dispose();
    });

    testWidgets('T-25-ICON-06 진행 중 → 아이콘 모두 비활성 · 투명도 0.38 · '
        '오버레이 · 눌러도 연결 0', (tester) async {
      final semantics = tester.ensureSemantics();
      await _pumpSection(
        tester,
        user: _buildUser(providerIds: _unlinkedSixProviderIds),
        repo: repo,
        width: 280,
        preview: _halfPreview,
        extraOverrides: <Override>[
          accountLinkInProgressProvider.overrideWithBuild(
            (ref, notifier) => true,
          ),
        ],
        shouldSettle: false,
      );

      expect(find.byType(AuthInProgressOverlay), findsOneWidget);
      for (final label in _enLabelsInOrder) {
        expect(
          tester.getSemantics(find.bySemanticsLabel(label)),
          isSemantics(
            label: label,
            isButton: true,
            hasEnabledState: true,
            isEnabled: false,
          ),
          reason: '$label 비활성',
        );
      }
      final opacities = tester.widgetList<Opacity>(
        find.descendant(
          of: find.byType(BrandedSocialIconButton),
          matching: find.byType(Opacity),
        ),
      );
      expect(opacities, hasLength(6));
      for (final opacity in opacities) {
        expect(opacity.opacity, kBrandButtonDisabledOpacity);
      }

      final slot = _readSlotOf(tester, AccountProvider.apple);
      await tester.tapAt(slot.center);
      await tester.pump();
      verifyNever(() => repo.linkAppleCredential());

      // 오버레이의 표시 지연 타이머를 흘려보낸다.
      await tester.pump(AuthInProgressOverlay.indicatorDelay);
      semantics.dispose();
    });
  });
}
