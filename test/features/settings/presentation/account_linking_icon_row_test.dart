// 계정 연결 절의 아이콘 줄 시험 · 두 모양 시험.
//
// 기본 모양(인자 없이)이면 절이 제목 → 안내 문구 → 원형 아이콘 줄을 그린다.
// `shape: AccountLinkingShape.button` 이면 「{provider} 연결」 글자 버튼 세로
// 목록이다. 크기 · 간격 기대값은 `branded_social_button.dart` 의 상수에서
// 읽는다.

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
import 'package:flutter_starter_kit/core/theme/theme_extensions.dart';
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

/// 미연결 6 — 이메일로 가입해 소셜 연결이 하나도 없다.
const _unlinkedSixProviderIds = <String>['password'];

/// 미연결 1 — Apple 만 남고 나머지 소셜 5개는 연결돼 있다.
const _unlinkedAppleOnlyProviderIds = <String>[
  'password',
  'google.com',
  'facebook.com',
  'kakao',
  'naver',
  'line',
];

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

/// 「{provider} 연결」 라벨 6개만 고르는 패턴 — 절 제목은 빼고 센다.
final _linkLabelPattern = RegExp(
  r'^Link (Google|Apple|Facebook|Kakao|Naver|LINE)$',
);

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
/// [shape] 가 null 이면 인자 없이(기본 모양) 그리고, 값이 있으면 그 모양으로
/// 그린다. GoRouter · ProviderScope 안에서 pump 하고 화면 크기는 시험이
/// 끝나면 되돌린다.
///
/// [isInListView] 가 true 면 계정 정보 화면처럼 `ListView` 의 한 항목으로
/// 놓는다 — 절 안 글자들이 접근성 트리에서 한 항목 노드로 모이는 조건이다.
Future<void> _pumpSection(
  WidgetTester tester, {
  required User user,
  required AuthRepository repo,
  required double width,
  AccountLinkingShape? shape,
  Locale locale = const Locale('en'),
  List<Override> extraOverrides = const <Override>[],
  bool shouldSettle = true,
  bool isInListView = false,
}) async {
  tester.view.physicalSize = Size(width, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  final router = GoRouter(
    initialLocation: AppRoutes.home,
    routes: [
      GoRoute(
        path: AppRoutes.home,
        builder: (context, state) {
          final section = shape == null
              ? const AccountLinkingSection()
              : AccountLinkingSection(shape: shape);
          return Scaffold(
            body: isInListView
                ? ListView(children: <Widget>[section])
                : SingleChildScrollView(child: section),
          );
        },
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

/// 미연결 6 의 줄 나누기 기대값을 화면 폭 [width] 에서 구한다.
List<int> _resolveExpectedRows(double width) {
  return resolveBrandIconRowCounts(
    _enLabelsInOrder.length,
    maxWidth: width - 2 * _sectionGutter,
    iconSize: kBrandIconButtonSize,
    gap: kBrandIconButtonGap,
  );
}

/// 「{provider} 연결」 semantics 라벨을 읽는 순서(위 → 아래 · 왼쪽 →
/// 오른쪽)대로 돌려준다.
List<String> _readLinkLabelsInReadingOrder(WidgetTester tester) {
  final finder = find.bySemanticsLabel(_linkLabelPattern);
  final entries = <({Offset center, String label})>[
    for (var i = 0; i < finder.evaluate().length; i++)
      (
        center: tester.getCenter(finder.at(i)),
        label: tester.getSemantics(finder.at(i)).label,
      ),
  ];
  entries.sort((a, b) {
    final byRow = a.center.dy.compareTo(b.center.dy);
    return byRow != 0 ? byRow : a.center.dx.compareTo(b.center.dx);
  });
  return <String>[for (final entry in entries) entry.label];
}

void main() {
  late _MockAuthRepository repo;

  setUpAll(() {
    registerFallbackValue(AccountProvider.google);
  });

  setUp(() {
    repo = _MockAuthRepository();
  });

  group('계정 연결 아이콘 줄 — 관통', () {
    testWidgets('T-25-ICON-01 기본 모양 → 안내 문구 · 아이콘 6 · 라벨 순서 · Apple 탭 → '
        '연결 성공 스낵바', (tester) async {
      final user = _buildUser(providerIds: _unlinkedSixProviderIds);
      when(
        () => repo.linkAppleCredential(),
      ).thenAnswer((_) async => Result.success(user));
      final semantics = tester.ensureSemantics();

      await _pumpSection(tester, user: user, repo: repo, width: 280);

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

    testWidgets('T-25-ICON-02 글자 버튼 모양 → 안내 문구 0 · 글자 버튼 6 · 아이콘 0', (
      tester,
    ) async {
      await _pumpSection(
        tester,
        user: _buildUser(providerIds: _unlinkedSixProviderIds),
        repo: repo,
        width: 280,
        shape: AccountLinkingShape.button,
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
          );

          final rows = _groupRows(_readSlotRects(tester));
          expect(
            rows.map((row) => row.length).toList(),
            _resolveExpectedRows(width),
            reason: '줄별 칸 수',
          );
          for (final row in rows) {
            expect(row.first.left, _sectionGutter, reason: '시작 정렬');
            for (var i = 1; i < row.length; i++) {
              expect(
                row[i].left - row[i - 1].right,
                kBrandIconButtonGap,
                reason: '칸 사이 = 간격',
              );
            }
          }
          for (var i = 1; i < rows.length; i++) {
            expect(
              rows[i].first.top - rows[i - 1].first.bottom,
              kBrandIconButtonGap,
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
      await _pumpSection(tester, user: user, repo: repo, width: 280);

      final slot = _readSlotOf(tester, AccountProvider.apple);
      await tester.tapAt(
        slot.center - const Offset(0, kBrandIconButtonSize / 2 + 1),
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

  group('계정 연결 절 — 두 모양', () {
    testWidgets('T-25-SHAPE-01 글자 버튼 모양 → 안내 문구 0 · 글자 버튼 = 미연결 수 · '
        '버튼 사이 = spacing.sm · 아이콘 0', (tester) async {
      await _pumpSection(
        tester,
        user: _buildUser(providerIds: _unlinkedSixProviderIds),
        repo: repo,
        width: 280,
        shape: AccountLinkingShape.button,
      );

      expect(find.text('Add another way to sign in.'), findsNothing);
      expect(find.byType(BrandedSocialIconButton), findsNothing);
      final buttons = find.byType(BrandedSocialButton);
      expect(buttons, findsNWidgets(_enLabelsInOrder.length));
      final sm = tester
          .element(find.byType(AccountLinkingSection))
          .appSpacing
          .sm;
      for (var i = 1; i < _enLabelsInOrder.length; i++) {
        expect(
          tester.getRect(buttons.at(i)).top -
              tester.getRect(buttons.at(i - 1)).bottom,
          sm,
          reason: '버튼 사이 = spacing.sm',
        );
      }
    });

    testWidgets('T-25-SHAPE-02 인자 없이 → 아이콘 모양 · 안내 문구 1 · 아이콘 = 미연결 수 · '
        '글자 버튼 0', (tester) async {
      await _pumpSection(
        tester,
        user: _buildUser(providerIds: _unlinkedSixProviderIds),
        repo: repo,
        width: 280,
      );

      expect(
        tester
            .widget<AccountLinkingSection>(find.byType(AccountLinkingSection))
            .shape,
        AccountLinkingShape.icon,
      );
      expect(find.text('Add another way to sign in.'), findsOneWidget);
      expect(
        find.byType(BrandedSocialIconButton),
        findsNWidgets(_enLabelsInOrder.length),
      );
      expect(find.byType(BrandedSocialButton), findsNothing);
    });

    testWidgets('T-25-SHAPE-03 두 모양의 「{provider} 연결」 라벨 목록이 같은 순서 · '
        '같은 문자열', (tester) async {
      final semantics = tester.ensureSemantics();
      await _pumpSection(
        tester,
        user: _buildUser(providerIds: _unlinkedSixProviderIds),
        repo: repo,
        width: 280,
      );
      final iconLabels = _readLinkLabelsInReadingOrder(tester);

      // 앞 scope 를 먼저 내려 새 모양으로 다시 만든다.
      await tester.pumpWidget(const SizedBox());
      await _pumpSection(
        tester,
        user: _buildUser(providerIds: _unlinkedSixProviderIds),
        repo: repo,
        width: 280,
        shape: AccountLinkingShape.button,
      );
      final buttonLabels = _readLinkLabelsInReadingOrder(tester);

      expect(iconLabels, _enLabelsInOrder, reason: '아이콘 모양');
      expect(buttonLabels, iconLabels, reason: '글자 버튼 모양 = 아이콘 모양');
      semantics.dispose();
    });

    for (final shape in AccountLinkingShape.values) {
      testWidgets('T-25-SHAPE-04 ${shape.name} 모양 · 미연결 1 → 버튼 semantics '
          '라벨은 「{provider} 연결」 하나뿐 · 절 제목 · 안내 문구가 버튼 노드에 '
          '섞이지 않는다', (tester) async {
        final semantics = tester.ensureSemantics();
        await _pumpSection(
          tester,
          user: _buildUser(providerIds: _unlinkedAppleOnlyProviderIds),
          repo: repo,
          width: 280,
          shape: shape,
          isInListView: true,
        );

        // 버튼이 하나면 탭 동작끼리 부딪치지 않아, 경계가 없으면 형제 글자가
        // 버튼 노드로 합쳐진다 — 'Link Apple' 이 든 노드의 라벨 전체를 본다.
        final buttonNode = find.bySemanticsLabel(RegExp('Link Apple'));
        expect(buttonNode, findsOneWidget, reason: 'Apple 버튼 노드 1개');
        expect(
          tester.getSemantics(buttonNode).label,
          'Link Apple',
          reason: '버튼 라벨에 다른 글자가 섞이지 않는다',
        );
        // 절 제목은 버튼 밖 노드다 — 아이콘 모양은 안내 문구와 한 노드로 읽힌다.
        expect(
          find.bySemanticsLabel(RegExp('^Link an account')),
          findsOneWidget,
          reason: '절 제목은 버튼 밖에서 읽힌다',
        );
        semantics.dispose();
      });
    }
  });
}
