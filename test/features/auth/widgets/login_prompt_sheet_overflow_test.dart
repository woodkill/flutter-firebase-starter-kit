// LoginPromptSheet 레이아웃 회귀 가드 (Phase 16.1 SC 4).
//
// 이 파일이 지키는 계약은 하나다 — **sheet 본문이 스크롤 가능하다.**
// 본문을 감싼 스크롤 뷰 1겹을 되돌리면 default 800x600 viewport 에서
// 7 provider 는 `A RenderFlex overflowed by 218 pixels on the bottom.`,
// 8 provider 는 `282 pixels` 로 재현된다 (RED 실측 2026-09-10). 같은 시점
// 실측에서 CTA 중심 좌표는 `Offset(400.0, 778.0)` 로 viewport 밖 178px 였다.
//
// 회귀 조건 자체가 좁은 viewport 이므로 테스트에서 화면 크기를 인위적으로
// 넓히지 않는다 — 넓히면 코드를 되돌려도 통과하는 위조 가드가 된다.
// 같은 이유로 기존 `login_prompt_sheet_test.dart` 의 3 provider harness 를
// 재사용하지 않고 7/8 provider 를 명시 override 하는 별도 harness 를 둔다.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_starter_kit/core/auth/auth_strategies_registry.dart';
import 'package:flutter_starter_kit/core/auth/auth_strategy.dart';
import 'package:flutter_starter_kit/core/auth/strategies/apple_auth_strategy.dart';
import 'package:flutter_starter_kit/core/auth/strategies/facebook_auth_strategy.dart';
import 'package:flutter_starter_kit/core/auth/strategies/google_auth_strategy.dart';
import 'package:flutter_starter_kit/core/auth/strategies/kakao_auth_strategy.dart';
import 'package:flutter_starter_kit/core/auth/strategies/line_auth_strategy.dart';
import 'package:flutter_starter_kit/core/auth/strategies/naver_auth_strategy.dart';
import 'package:flutter_starter_kit/core/auth/strategies/yahoojp_auth_strategy.dart';
import 'package:flutter_starter_kit/core/router/app_routes.dart';
import 'package:flutter_starter_kit/core/theme/app_theme.dart';
import 'package:flutter_starter_kit/features/auth/data/auth_repository.dart';
import 'package:flutter_starter_kit/features/auth/presentation/_widgets/email_auth_cta.dart';
import 'package:flutter_starter_kit/features/auth/presentation/_widgets/login_prompt_sheet.dart';
import 'package:flutter_starter_kit/features/auth/presentation/_widgets/social_button.dart';
import 'package:flutter_starter_kit/l10n/generated/app_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';

/// [AuthRepository] 를 mocktail 로 대체하기 위한 Mock.
class _MockAuthRepository extends Mock implements AuthRepository {}

/// 마지막으로 push 된 URL 을 기록하기 위한 단순 recorder.
class LastLocationRecorder {
  /// 마지막으로 GoRouter 가 진입한 location (query 포함 URL) .
  String? lastPushedLocation;
}

/// 현행 활성 provider 7종 — `_allStrategies` 선언 순서 verbatim.
const List<AuthStrategy> _sevenStrategies = <AuthStrategy>[
  GoogleAuthStrategy(),
  AppleAuthStrategy(),
  FacebookAuthStrategy(),
  KakaoAuthStrategy(),
  NaverAuthStrategy(),
  LineAuthStrategy(),
  YahoojpAuthStrategy(),
];

/// 미래 provider 추가 시뮬 8종.
///
/// 새 `providerId` 를 가진 대체 구현을 만들지 않고 기존 const 를 1개
/// 중복시킨다 — 미지 provider 는 버튼 렌더 시점에 `UnsupportedError` 를
/// throw 해서 `takeException()` 이 overflow 가 아닌 이유로 non-null 이 된다.
const List<AuthStrategy> _eightStrategies = <AuthStrategy>[
  ..._sevenStrategies,
  GoogleAuthStrategy(),
];

/// [showLoginPromptSheet] 을 [strategies] 개수로 pump 하는 harness.
///
/// `activeStrategiesProvider` 의 family key 와 [MaterialApp.router] 의
/// locale 은 반드시 일치해야 한다 — 위젯이 `Localizations.localeOf` 로
/// 읽은 locale 로 provider 를 조회하기 때문이다.
Future<LastLocationRecorder> pumpOverflowHarness(
  WidgetTester tester,
  List<AuthStrategy> strategies,
) async {
  final recorder = LastLocationRecorder();
  final mockRepo = _MockAuthRepository();

  final router = GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(
        path: '/',
        builder: (_, _) => Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: ElevatedButton(
                onPressed: () => showLoginPromptSheet(context),
                child: const Text('Trigger'),
              ),
            ),
          ),
        ),
      ),
      GoRoute(
        path: AppRoutes.emailLogin,
        builder: (_, state) {
          recorder.lastPushedLocation = state.uri.toString();
          return const Scaffold(body: Center(child: Text('EmailLoginStub')));
        },
      ),
    ],
  );

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authRepositoryProvider.overrideWithValue(mockRepo),
        activeStrategiesProvider(
          const Locale('en'),
        ).overrideWithValue(strategies),
      ],
      child: MaterialApp.router(
        theme: AppTheme.light(),
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        routerConfig: router,
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('Trigger'));
  await tester.pumpAndSettle();
  return recorder;
}

void main() {
  group('LoginPromptSheet overflow 회귀 가드 (Phase 16.1 SC 4)', () {
    testWidgets('7 provider — default viewport 에서 overflow 예외가 없다', (
      tester,
    ) async {
      await pumpOverflowHarness(tester, _sevenStrategies);

      // settle 이 끝난 뒤에 확인한다 — entrance 애니메이션 중에는 레이아웃이
      // 확정되지 않아 위음성이 난다.
      expect(
        tester.takeException(),
        isNull,
        reason: '스크롤 wrap 이 없으면 218px RenderFlex overflow 가 재현된다',
      );
      expect(find.byType(SocialButton), findsNWidgets(7));
    });

    testWidgets('7 provider — CTA 가 스크롤로 도달 가능하고 /login/email 로 push 된다', (
      tester,
    ) async {
      final recorder = await pumpOverflowHarness(tester, _sevenStrategies);

      final ctaFinder = find.byType(EmailAuthCta);
      expect(ctaFinder, findsOneWidget);
      // viewport 밖 좌표에서는 tap 이 조용히 실패하므로 명시 스크롤이 필수다.
      await tester.ensureVisible(ctaFinder);
      await tester.tap(ctaFinder);
      await tester.pumpAndSettle();

      expect(find.byType(LoginPromptSheet), findsNothing);
      expect(recorder.lastPushedLocation, isNotNull);
      expect(recorder.lastPushedLocation, contains(AppRoutes.emailLogin));
      expect(
        recorder.lastPushedLocation,
        isNot(contains('?')),
        reason: '전용 route 로 직행하므로 쿼리 문자열이 없어야 함',
      );
    });

    testWidgets('8 provider — default viewport 에서 overflow 예외가 없다', (
      tester,
    ) async {
      await pumpOverflowHarness(tester, _eightStrategies);

      expect(
        tester.takeException(),
        isNull,
        reason: '스크롤 wrap 이 없으면 282px RenderFlex overflow 가 재현된다',
      );
      expect(find.byType(SocialButton), findsNWidgets(8));
    });

    testWidgets('8 provider — CTA 가 스크롤로 도달 가능하고 tap 이 성공한다', (tester) async {
      final recorder = await pumpOverflowHarness(tester, _eightStrategies);

      final ctaFinder = find.byType(EmailAuthCta);
      expect(ctaFinder, findsOneWidget);
      await tester.ensureVisible(ctaFinder);
      await tester.tap(ctaFinder);
      await tester.pumpAndSettle();

      expect(find.byType(LoginPromptSheet), findsNothing);
      expect(recorder.lastPushedLocation, contains(AppRoutes.emailLogin));
    });
  });
}
