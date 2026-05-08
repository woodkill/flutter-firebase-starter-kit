// Phase 13.1 Plan 13.1-08 — SocialSignInSection 회귀 가드.
//
// **갱신 의도:** Plan 13.1-08 caller refactor 결과로 Apple/Google 분기가
// `BrandedSocialButton` 위임으로 전환되어 더 이상 `SignInButton` 을 사용하지
// 않는다. Facebook 만 `SignInButton(Buttons.facebookNew)` 잔존 (R12).
//
// 본 테스트는 `SocialSignInSection` 의 통일 순서 (D-04) + 활성 strategies
// 렌더 (Phase 11-04) + 다크 모드 변형을 BrandedSocialButton 인스턴스 검증으로
// 갱신한다.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:sign_in_button/sign_in_button.dart';
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
Future<void> _pumpWithMobileViewport(
  WidgetTester tester,
  Widget widget,
) async {
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
    testWidgets(
      '3개 버튼이 Google -> Apple -> Facebook 순서로 렌더된다',
      (tester) async {
        await _pumpWithMobileViewport(
          tester,
          buildHarness(brightness: Brightness.light, repository: mockRepo),
        );
        await tester.pumpAndSettle();

        // Plan 13.1-08 — 3 SocialButton 의 분기:
        //   Google → BrandedSocialButton.google (GoogleSpec)
        //   Apple  → BrandedSocialButton.apple  (AppleSpec)
        //   Facebook → SignInButton (Buttons.facebookNew)
        final socialButtons = tester
            .widgetList<SocialButton>(find.byType(SocialButton))
            .toList();
        expect(socialButtons.length, 3);
        expect(socialButtons[0].strategy.providerId, 'google');
        expect(socialButtons[1].strategy.providerId, 'apple');
        expect(socialButtons[2].strategy.providerId, 'facebook');

        // BrandedSocialButton 2개 (Google + Apple) — Facebook 미위임.
        final branded = tester
            .widgetList<BrandedSocialButton>(find.byType(BrandedSocialButton))
            .toList();
        expect(branded.length, 2);
        expect(branded[0].spec, isA<GoogleSpec>());
        expect(branded[1].spec, isA<AppleSpec>());

        // Facebook 만 SignInButton 잔존.
        final signInButtons = tester
            .widgetList<SignInButton>(find.byType(SignInButton))
            .toList();
        expect(signInButtons.length, 1);
        expect(signInButtons[0].button, Buttons.facebookNew);
      },
    );

    testWidgets('Facebook 버튼 탭 시 signInWithFacebook이 호출된다', (tester) async {
      await _pumpWithMobileViewport(
        tester,
        buildHarness(brightness: Brightness.light, repository: mockRepo),
      );
      await tester.pumpAndSettle();

      // Facebook 만 SignInButton — 1개 잔존.
      final fb = tester.widget<SignInButton>(find.byType(SignInButton));
      expect(fb.button, Buttons.facebookNew);

      await tester.tap(find.byWidget(fb));
      await tester.pumpAndSettle();

      verify(() => mockRepo.signInWithFacebook()).called(1);
    });

    testWidgets(
      'isFormLoading=true일 때 Facebook 버튼 탭해도 '
      'signInWithFacebook이 호출되지 않는다',
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

        final fb = tester.widget<SignInButton>(find.byType(SignInButton));
        expect(fb.button, Buttons.facebookNew);

        await tester.tap(find.byWidget(fb));
        await tester.pumpAndSettle();

        // isFormLoading=true이면 onPressed가 빈 콜백으로 교체되어
        // Repository가 호출되지 않아야 한다.
        verifyNever(() => mockRepo.signInWithFacebook());
      },
    );

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

  group('SocialSignInSection 다크모드 버튼 변형 (Plan 13.1-08)', () {
    testWidgets(
      '라이트 모드 → Google.theme=light, Apple.style=black, Facebook=facebookNew',
      (tester) async {
        await _pumpWithMobileViewport(
          tester,
          buildHarness(brightness: Brightness.light, repository: mockRepo),
        );
        await tester.pumpAndSettle();

        final branded = tester
            .widgetList<BrandedSocialButton>(find.byType(BrandedSocialButton))
            .toList();
        expect((branded[0].spec as GoogleSpec).theme, GoogleTheme.light);
        expect(branded[1].appleStyle, SignInWithAppleButtonStyle.black);

        final fb = tester.widget<SignInButton>(find.byType(SignInButton));
        expect(fb.button, Buttons.facebookNew);
      },
    );

    testWidgets(
      '다크 모드 → Google.theme=dark, Apple.style=white, Facebook=facebookNew',
      (tester) async {
        await _pumpWithMobileViewport(
          tester,
          buildHarness(brightness: Brightness.dark, repository: mockRepo),
        );
        await tester.pumpAndSettle();

        final branded = tester
            .widgetList<BrandedSocialButton>(find.byType(BrandedSocialButton))
            .toList();
        expect((branded[0].spec as GoogleSpec).theme, GoogleTheme.dark);
        expect(branded[1].appleStyle, SignInWithAppleButtonStyle.white);

        final fb = tester.widget<SignInButton>(find.byType(SignInButton));
        // Facebook 은 라이트/다크 무관 동일 변형 (브랜드 가이드라인).
        expect(fb.button, Buttons.facebookNew);
      },
    );

    testWidgets(
      'isFormLoading=true 시 Apple BrandedSocialButton 의 onPressed 가 null',
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
        // Google + Apple 두 BrandedSocialButton 의 onPressed 모두 null.
        for (final b in branded) {
          expect(
            b.onPressed,
            isNull,
            reason: 'isFormLoading=true 면 onPressed 가 null 이어야 한다',
          );
        }
        // Repository 도 호출 안 됨.
        verifyNever(() => mockRepo.signInWithApple());
      },
    );
  });

  group(
    'SocialSignInSection 마이그레이션 회귀 가드 (Phase 11-04, Pattern H)',
    () {
      testWidgets(
        'activeStrategiesProvider 결과를 SocialButton 으로 렌더링한다',
        (tester) async {
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
        },
      );

      testWidgets(
        '빈 strategies 리스트 → SocialButton 0개 (D-14 disabled 미표시)',
        (tester) async {
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
        },
      );
    },
  );
}
