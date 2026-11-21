// 온보딩 마지막 슬라이드(약관 동의)의 기본 글자 배율 한 화면 회귀 시험.
//
// 고정하는 것: 360×780 dp · 3버튼 내비게이션 폰의 기본 글자 배율(1.0)에서
// 온보딩 마지막 슬라이드가 스크롤 없이 한 화면에 들어가고, 필수 약관에 체크하지
// 않고 「시작하기」 를 누르면 뜨는 오류 문구가 화면(PageView) 안에 보인다.
// ko · en · ja × (정상 · 체크 없이 「시작하기」 를 누른 뒤) = 6 조건이다.
//
// 조건의 출처: Galaxy 3버튼 단말(1080×2340 · DPR 3)의 `dumpsys window` 값 —
// 상태 표시줄 115 px · 내비게이션 바 144 px.
//
// 어디서 도는가: 이 시험은 킷 ARB 문구로 높이를 잰다. 킷을 받은 저장소가 3 번
// 화면 문구 · 모양을 바꾸면 깨지므로 유지보수자 트리에서만 돈다 —
// `onboarding_screen_test.dart` Test 13 이 레이아웃 단언을 두지 않는 것과 같은
// 까닭이다.
//
// viewport 단언이 먼저인 까닭: inset 이나 화면 크기가 빠지면 화면이 넓어져
// 「스크롤 0」 이 거짓 통과한다. 그래서 슬라이드 3 스크롤 뷰의 viewportDimension
// 이 기기 조건 값인지 같이 본다.
//
// loadAppFont 는 setUpAll 에서만 부른다 — testWidgets 본문에서 부르면 영원히
// 멈춘다. 실제 글꼴을 올려야 글자 폭 · 줄 수가 기기와 같다. 글꼴 적재는 프로세스
// 전역이라 기존 onboarding_screen_test.dart 의 측정을 바꾸지 않게 파일을 나눈다.
//
// 조건마다 testWidgets 하나 — 한 조건의 실패가 다른 조건을 가리지 않게 한다.

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_starter_kit/core/analytics/analytics_service.dart';
import 'package:flutter_starter_kit/core/crashlytics/crashlytics_service.dart';
import 'package:flutter_starter_kit/core/providers/firebase_providers.dart';
import 'package:flutter_starter_kit/core/router/app_routes.dart';
import 'package:flutter_starter_kit/core/theme/app_theme.dart';
import 'package:flutter_starter_kit/features/auth/data/auth_repository.dart';
import 'package:flutter_starter_kit/features/onboarding/presentation/_widgets/terms_checkbox_group.dart';
import 'package:flutter_starter_kit/features/onboarding/presentation/onboarding_screen.dart';
import 'package:flutter_starter_kit/l10n/generated/app_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/app_font.dart';
import '../../helpers/keep_hangul_words_finder.dart';
import '../../helpers/planning_docs.dart';

/// 인증 저장소 mock — 이 시험은 제출까지 가지 않는다.
class _MockAuthRepository extends Mock implements AuthRepository {}

/// 분석 서비스 mock — 수집을 꺼 둔다.
class _MockAnalyticsService extends Mock implements AnalyticsService {
  @override
  bool get isEnabled => false;
}

/// Crashlytics 서비스 mock.
class _MockCrashlytics extends Mock implements CrashlyticsService {}

/// 기기 DPR.
const double _dpr = 3;

/// 기기 논리 크기(dp).
const Size _logicalSize = Size(360, 780);

/// 위 시스템 inset(상태 표시줄 · px).
const double _topInsetPx = 115;

/// 아래 시스템 inset(3버튼 내비게이션 바 · px).
const double _bottomInsetPx = 144;

/// 슬라이드 3 스크롤 뷰의 기대 viewport 높이(dp).
///
/// 780 − 115/3(상태 표시줄 38.33) − AppBar 56 − 144/3(내비게이션 바 48) −
/// 아래 고정 영역 136(Gap 24 · 점 8 · Gap 24 · CTA 위아래 16 + 48).
const double _expectedViewport = 501.7;

/// 위치 · 크기 판정 허용치(dp).
const double _tolerance = 0.5;

/// 시험 조건 — 언어 · 필수 미동의 오류를 켠 상태인지.
typedef _Condition = ({String locale, bool showError});

/// 6 조건 — ko · en · ja × 정상 · 오류.
const List<_Condition> _conditions = [
  (locale: 'ko', showError: false),
  (locale: 'ko', showError: true),
  (locale: 'en', showError: false),
  (locale: 'en', showError: true),
  (locale: 'ja', showError: false),
  (locale: 'ja', showError: true),
];

void main() {
  group(
    '온보딩 약관 슬라이드 — 360×780 기본 배율 한 화면',
    skip: skipUnlessMaintainerTree(),
    () {
      setUpAll(loadAppFont);

      for (final condition in _conditions) {
        final locale = condition.locale;
        final state = condition.showError ? 'err' : 'ok';
        testWidgets('$locale $state — 360×780 · DPR 3 · inset 115/144 px — '
            '스크롤 0 · 오류 문구 화면 안', (tester) async {
          tester.view.devicePixelRatio = _dpr;
          tester.view.physicalSize = _logicalSize * _dpr;
          const pad = FakeViewPadding(top: _topInsetPx, bottom: _bottomInsetPx);
          tester.view.padding = pad;
          tester.view.viewPadding = pad;
          addTearDown(tester.view.reset);

          SharedPreferences.setMockInitialValues({});
          final router = GoRouter(
            initialLocation: AppRoutes.onboarding,
            routes: [
              GoRoute(
                path: AppRoutes.onboarding,
                builder: (_, _) => const OnboardingScreen(),
              ),
            ],
          );
          addTearDown(router.dispose);

          await tester.pumpWidget(
            ProviderScope(
              overrides: [
                isFirebaseInitializedProvider.overrideWithValue(false),
                authRepositoryProvider.overrideWithValue(_MockAuthRepository()),
                analyticsServiceProvider.overrideWithValue(
                  _MockAnalyticsService(),
                ),
                crashlyticsServiceProvider.overrideWithValue(
                  _MockCrashlytics(),
                ),
              ],
              child: MaterialApp.router(
                theme: AppTheme.light(),
                locale: Locale(locale),
                localizationsDelegates: const [
                  AppLocalizations.delegate,
                  GlobalMaterialLocalizations.delegate,
                  GlobalWidgetsLocalizations.delegate,
                  GlobalCupertinoLocalizations.delegate,
                ],
                supportedLocales: AppLocalizations.supportedLocales,
                routerConfig: router,
              ),
            ),
          );
          await tester.pump();
          // 「다음」 두 번 → 슬라이드 3.
          for (var i = 0; i < 2; i++) {
            await tester.tap(find.byType(FilledButton));
            await tester.pumpAndSettle();
          }
          // 체크 없이 「시작하기」 → 필수 미동의 오류 문구.
          if (condition.showError) {
            await tester.tap(find.byType(FilledButton));
            await tester.pumpAndSettle();
          }

          final violations = <String>[];
          final l10n = AppLocalizations.of(
            tester.element(find.byType(OnboardingScreen)),
          );

          final groupCount = find.byType(TermsCheckboxGroup).evaluate().length;
          if (groupCount != 1) {
            violations.add('[slide3] $locale $state count=$groupCount');
          } else {
            // ancestor 는 가까운 것부터 — 슬라이드 3 의 SingleChildScrollView.
            final position = tester
                .state<ScrollableState>(
                  find
                      .ancestor(
                        of: find.byType(TermsCheckboxGroup),
                        matching: find.byType(Scrollable),
                      )
                      .first,
                )
                .position;

            final viewport = position.viewportDimension;
            if ((viewport - _expectedViewport).abs() > _tolerance) {
              violations.add(
                '[viewport] $locale $state '
                'viewportDimension=${viewport.toStringAsFixed(1)}',
              );
            }

            // 화면 밖이어도 세어야 rect 판정이 의미 있다.
            final errorFinder = findKeepHangulWordsText(
              l10n.termsRequiredError,
              skipOffstage: false,
            );
            final errorCount = errorFinder.evaluate().length;
            final expectedErrorCount = condition.showError ? 1 : 0;
            if (errorCount != expectedErrorCount) {
              violations.add('[error-text] $locale $state count=$errorCount');
            }

            final maxScroll = position.maxScrollExtent;
            if (maxScroll > 0) {
              violations.add(
                '[scroll] $locale $state '
                'maxScrollExtent=${maxScroll.toStringAsFixed(1)}',
              );
            }

            if (condition.showError && errorCount == 1) {
              final error = tester.getRect(errorFinder);
              final page = tester.getRect(find.byType(PageView));
              if (error.top < page.top - _tolerance ||
                  error.bottom > page.bottom + _tolerance) {
                violations.add(
                  '[error-visible] $locale err '
                  'error=${error.top.toStringAsFixed(1)}'
                  '~${error.bottom.toStringAsFixed(1)} '
                  'page=${page.top.toStringAsFixed(1)}'
                  '~${page.bottom.toStringAsFixed(1)}',
                );
              }
            }
          }

          final exception = tester.takeException();
          if (exception != null) {
            violations.add(
              '[exception] $locale $state '
              '${exception.toString().split('\n').first}',
            );
          }

          expect(violations, isEmpty, reason: violations.join('\n'));
        });
      }
    },
  );
}
