// Phase 13.2 Plan 13.2-06 — SocialSignInSection 회귀 가드.
//
// **갱신 의도:** Phase 13.2 옵션 A pivot (Wave 0 lock D-94) 채택 후 Facebook
// 분기도 `BrandedSocialButton.facebook` 위임으로 전환되어 모든 provider 가
// `BrandedSocialButton` 단일 진실원으로 일관. sign_in_button 패키지 의존 폐기
// (R10) + Meta 공식 자상 PNG + Apple SignInWithAppleButton 패턴 mirror 의
// `_renderFacebookButton` 위제 활성.
//
// 본 테스트는 `SocialSignInSection` 의 통일 순서 (D-04) + 활성 strategies
// 렌더 (Phase 11-04) + 다크 모드 변형을 BrandedSocialButton 인스턴스 검증으로
// 갱신한다.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

import 'package:flutter_starter_kit/core/auth/auth_strategies_registry.dart';
import 'package:flutter_starter_kit/core/auth/auth_strategy.dart';
import 'package:flutter_starter_kit/core/auth/strategies/apple_auth_strategy.dart';
import 'package:flutter_starter_kit/core/auth/strategies/facebook_auth_strategy.dart';
import 'package:flutter_starter_kit/core/auth/strategies/google_auth_strategy.dart';
import 'package:flutter_starter_kit/core/theme/app_theme.dart';
import 'package:flutter_starter_kit/features/auth/data/auth_repository.dart';
import 'package:flutter_starter_kit/features/auth/presentation/_widgets/branded_social_button.dart';
import 'package:flutter_starter_kit/features/auth/presentation/_widgets/social_button.dart';
import 'package:flutter_starter_kit/features/auth/presentation/_widgets/social_sign_in_section.dart';
import 'package:flutter_starter_kit/l10n/generated/app_localizations.dart';

/// [AuthRepository]를 mocktail로 대체하기 위한 Mock.
class _MockAuthRepository extends Mock implements AuthRepository {}

/// 테스트 harness -- [ProviderScope] + [MaterialApp] + [SocialSignInSection].
///
/// [brightness]로 라이트/다크 테마를 전환하고, [repository]를 주입해
/// `authRepositoryProvider`를 override한다. [isFormLoading]은 이메일 폼
/// 로딩 상태를 시뮬레이션한다. [errorBanner]는 소셜 에러 배너를 주입한다.
/// 기본 활성 Strategy 리스트 — Plan 11-04 마이그레이션 후 회귀 가드.
///
/// 정적 config + RC overlay 미초기화 환경 (테스트) 에서는
/// `activeStrategiesProvider` 가 RC throw 가능하므로 override 의무.
const List<AuthStrategy> _defaultStrategies = <AuthStrategy>[
  GoogleAuthStrategy(),
  AppleAuthStrategy(),
  FacebookAuthStrategy(),
];

Widget buildHarness({
  required Brightness brightness,
  required AuthRepository repository,
  bool isFormLoading = false,
  Widget? errorBanner,
  List<AuthStrategy> strategies = _defaultStrategies,
}) {
  return ProviderScope(
    overrides: [
      authRepositoryProvider.overrideWithValue(repository),
      activeStrategiesProvider(
        const Locale('en'),
      ).overrideWithValue(strategies),
    ],
    child: MaterialApp(
      // AppTheme.light/dark는 AppSpacing/AppTypography/AppColors
      // ThemeExtension을 등록한다. context.appSpacing null 가드 필수.
      theme: brightness == Brightness.dark ? AppTheme.dark() : AppTheme.light(),
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: SocialSignInSection(
          isFormLoading: isFormLoading,
          errorBanner: errorBanner,
        ),
      ),
    ),
  );
}

/// 좁은 시뮬레이터 surface 로 pump — 자상 placeholder 의 native size 가 큰
/// 기본 800x600 viewport 에서 발생하는 Row overflow 회피.
///
/// `binding.setSurfaceSize` 사용 (deprecated `tester.view.physicalSize` 회피).
Future<void> _pumpWithMobileViewport(WidgetTester tester, Widget widget) async {
  await tester.binding.setSurfaceSize(const Size(412, 800));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(widget);
}

void main() {
  late _MockAuthRepository mockRepo;

  setUp(() {
    mockRepo = _MockAuthRepository();
    // 기본값: Google/Apple/Facebook 로그인 호출 시 취소(null)로 조용히 무시.
    when(() => mockRepo.signInWithGoogle()).thenAnswer((_) async => null);
    when(() => mockRepo.signInWithApple()).thenAnswer((_) async => null);
    when(() => mockRepo.signInWithFacebook()).thenAnswer((_) async => null);
  });

  group('SocialSignInSection 통일 순서 (D-04)', () {
    testWidgets('3개 버튼이 Google -> Apple -> Facebook 순서로 렌더된다', (tester) async {
      await _pumpWithMobileViewport(
        tester,
        buildHarness(brightness: Brightness.light, repository: mockRepo),
      );
      await tester.pumpAndSettle();

      // Phase 13.2 R7/R8 — 3 SocialButton 의 분기 (모두 BrandedSocialButton
      // 단일 위임):
      //   Google → BrandedSocialButton.google (GoogleSpec)
      //   Apple  → BrandedSocialButton.apple  (AppleSpec)
      //   Facebook → BrandedSocialButton.facebook (FacebookSpec — Meta 공식
      //     자상 PNG + _renderFacebookButton 위제)
      final socialButtons = tester
          .widgetList<SocialButton>(find.byType(SocialButton))
          .toList();
      expect(socialButtons.length, 3);
      expect(socialButtons[0].strategy.providerId, 'google');
      expect(socialButtons[1].strategy.providerId, 'apple');
      expect(socialButtons[2].strategy.providerId, 'facebook');

      // BrandedSocialButton 3개 (Google + Apple + Facebook 모두 위임).
      final branded = tester
          .widgetList<BrandedSocialButton>(find.byType(BrandedSocialButton))
          .toList();
      expect(branded.length, 3);
      expect(branded[0].spec, isA<GoogleSpec>());
      expect(branded[1].spec, isA<AppleSpec>());
      expect(branded[2].spec, isA<FacebookSpec>());
    });

    testWidgets('Facebook 버튼 탭 시 signInWithFacebook이 호출된다', (tester) async {
      await _pumpWithMobileViewport(
        tester,
        buildHarness(brightness: Brightness.light, repository: mockRepo),
      );
      await tester.pumpAndSettle();

      // Phase 13.2 — Facebook 도 BrandedSocialButton 위임. SocialSignInSection
      // 안의 세 번째 (index 2) SocialButton 이 Facebook 분기.
      final fbSocialButton = find.byType(SocialButton).at(2);
      final fbBranded = find.descendant(
        of: fbSocialButton,
        matching: find.byType(BrandedSocialButton),
      );
      expect(fbBranded, findsOneWidget);
      expect(
        tester.widget<BrandedSocialButton>(fbBranded).spec,
        isA<FacebookSpec>(),
      );

      await tester.tap(fbBranded);
      await tester.pumpAndSettle();

      verify(() => mockRepo.signInWithFacebook()).called(1);
    });

    testWidgets('isFormLoading=true일 때 Facebook 버튼 탭해도 '
        'signInWithFacebook이 호출되지 않는다', (tester) async {
      await _pumpWithMobileViewport(
        tester,
        buildHarness(
          brightness: Brightness.light,
          repository: mockRepo,
          isFormLoading: true,
        ),
      );
      await tester.pumpAndSettle();

      // Phase 13.2 — Facebook BrandedSocialButton 위임. isFormLoading=true
      // 면 onPressed=null 로 비활성 상태.
      final fbSocialButton = find.byType(SocialButton).at(2);
      final fbBranded = find.descendant(
        of: fbSocialButton,
        matching: find.byType(BrandedSocialButton),
      );
      expect(fbBranded, findsOneWidget);
      final fb = tester.widget<BrandedSocialButton>(fbBranded);
      expect(fb.spec, isA<FacebookSpec>());
      expect(fb.onPressed, isNull);

      await tester.tap(fbBranded);
      await tester.pumpAndSettle();

      // onPressed=null 이면 Repository 호출 없음.
      verifyNever(() => mockRepo.signInWithFacebook());
    });

    testWidgets('errorBanner가 소셜 버튼과 OrDivider 사이에 표시된다', (tester) async {
      await _pumpWithMobileViewport(
        tester,
        buildHarness(
          brightness: Brightness.light,
          repository: mockRepo,
          errorBanner: const Text('test error'),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('test error'), findsOneWidget);
    });
  });

  group('SocialSignInSection 다크모드 버튼 변형 (Phase 13.2 Plan 13.2-06)', () {
    testWidgets('라이트 모드 → Google.theme=light, Apple.style=black, '
        'Facebook=FacebookSpec (BrandedSocialButton 단일 위임)', (tester) async {
      await _pumpWithMobileViewport(
        tester,
        buildHarness(brightness: Brightness.light, repository: mockRepo),
      );
      await tester.pumpAndSettle();

      // Phase 13.2 — 3 BrandedSocialButton 모두 단일 위임. 통일 순서
      // Google → Apple → Facebook.
      final branded = tester
          .widgetList<BrandedSocialButton>(find.byType(BrandedSocialButton))
          .toList();
      expect(branded.length, 3);
      expect((branded[0].spec as GoogleSpec).theme, GoogleTheme.light);
      expect(branded[1].appleStyle, SignInWithAppleButtonStyle.black);
      expect(branded[2].spec, isA<FacebookSpec>());
    });

    testWidgets('다크 모드 → Google.theme=dark, Apple.style=white, '
        'Facebook=FacebookSpec (Theme.brightness 자동 분기는 위제 내부 책임)', (
      tester,
    ) async {
      await _pumpWithMobileViewport(
        tester,
        buildHarness(brightness: Brightness.dark, repository: mockRepo),
      );
      await tester.pumpAndSettle();

      final branded = tester
          .widgetList<BrandedSocialButton>(find.byType(BrandedSocialButton))
          .toList();
      expect(branded.length, 3);
      expect((branded[0].spec as GoogleSpec).theme, GoogleTheme.dark);
      expect(branded[1].appleStyle, SignInWithAppleButtonStyle.white);
      // Facebook 은 D-94 lock (theme 매개변수 부재) — Theme.brightness 자동
      // 분기는 _renderFacebookButton 위제 내부 책임. spec 자체는 light/dark
      // 무관 동일.
      expect(branded[2].spec, isA<FacebookSpec>());
    });

    testWidgets(
      'isFormLoading=true 시 3 BrandedSocialButton 의 onPressed 가 모두 null',
      (tester) async {
        await _pumpWithMobileViewport(
          tester,
          buildHarness(
            brightness: Brightness.light,
            repository: mockRepo,
            isFormLoading: true,
          ),
        );
        await tester.pumpAndSettle();

        final branded = tester
            .widgetList<BrandedSocialButton>(find.byType(BrandedSocialButton))
            .toList();
        expect(branded.length, 3);
        // Google + Apple + Facebook 3 BrandedSocialButton 의 onPressed 모두 null.
        for (final b in branded) {
          expect(
            b.onPressed,
            isNull,
            reason: 'isFormLoading=true 면 onPressed 가 null 이어야 한다',
          );
        }
        // Repository 도 호출 안 됨.
        verifyNever(() => mockRepo.signInWithApple());
        verifyNever(() => mockRepo.signInWithFacebook());
      },
    );
  });

  group('SocialSignInSection 마이그레이션 회귀 가드 (Phase 11-04, Pattern H)', () {
    testWidgets('activeStrategiesProvider 결과를 SocialButton 으로 렌더링한다', (
      tester,
    ) async {
      await _pumpWithMobileViewport(
        tester,
        buildHarness(
          brightness: Brightness.light,
          repository: mockRepo,
          strategies: const <AuthStrategy>[
            GoogleAuthStrategy(),
            AppleAuthStrategy(),
          ],
        ),
      );
      await tester.pumpAndSettle();

      // override 한 2개 Strategy 만 SocialButton 으로 렌더링.
      expect(find.byType(SocialButton), findsNWidgets(2));
    });

    testWidgets('빈 strategies 리스트 → SocialButton 0개 (D-14 disabled 미표시)', (
      tester,
    ) async {
      await _pumpWithMobileViewport(
        tester,
        buildHarness(
          brightness: Brightness.light,
          repository: mockRepo,
          strategies: const <AuthStrategy>[],
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(SocialButton), findsNothing);
      // OrDivider 는 그대로 표시 (showOrDivider 기본 true).
    });
  });
}
