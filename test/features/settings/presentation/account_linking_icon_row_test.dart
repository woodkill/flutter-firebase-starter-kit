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
import 'package:flutter_starter_kit/features/auth/data/auth_repository.dart';
import 'package:flutter_starter_kit/features/auth/domain/user.dart';
import 'package:flutter_starter_kit/features/auth/presentation/_widgets/branded_social_button.dart';
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
}
