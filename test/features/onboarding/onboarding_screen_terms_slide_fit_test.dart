// 온보딩 마지막 슬라이드(약관 동의)의 기본 글자 배율 한 화면 회귀 시험.
//
// 고정하는 것: 360×780 dp · 3버튼 내비게이션 폰의 기본 글자 배율(1.0)에서
// 온보딩 마지막 슬라이드가 스크롤 없이 한 화면에 들어가고, 필수 약관에 체크하지
// 않고 「시작하기」 를 누르면 뜨는 오류 문구가 화면(PageView) 안에 보인다.
// ko · en · ja × (정상 · 체크 없이 「시작하기」 를 누른 뒤) = 6 조건이다.
//
// 킷 판 6조건은 빈 목록 builder 로, 확인 행 1개 6조건은 guide 예시 문구 builder
// 로 잰다(둘 다 유지보수자 트리 전용 · 사용자 파일과 무관). 확인 행 1개 조건은
// 행 안내 문구도 화면(PageView) 안에 보이는지 같이 본다.
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
import 'package:flutter_starter_kit/features/onboarding/presentation/app_terms_confirmation_slot.dart';
import 'package:flutter_starter_kit/features/onboarding/presentation/onboarding_screen.dart';
import 'package:flutter_starter_kit/l10n/generated/app_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/app_font.dart';
import '../../helpers/keep_hangul_words_finder.dart';
import '../../helpers/planning_docs.dart';
import '../../helpers/terms_tile_finder.dart';

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

/// 확인 행 1개를 켰을 때 약관 묶음의 타일 수 — 「전체 동의」 · 이용약관 ·
/// 개인정보처리방침 · 확인 행 · 마케팅.
const int _tileCountWithOneRow = 5;

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

/// 확인 행 하나의 문구 — 행 문구와 체크하지 않았을 때의 안내.
typedef _ConfirmationTexts = ({String label, String hint});

/// guide 예시 확인 행 문구 — 언어 코드 → (행 문구, 안내 문구).
///
/// 승인 기록의 예시 문구 6개 그대로다. 실제 앱 문구 길이로 높이를 재려고 시험
/// 에만 둔다(앱 코드 · 킷 ARB 에는 두지 않는다).
const Map<String, _ConfirmationTexts> _guideExampleTexts = {
  'ko': (label: '만 14세 이상입니다', hint: '만 14세 미만은 가입할 수 없어요.'),
  'en': (
    label: 'I am 14 years or older',
    hint: 'You must be 14 or older to sign up.',
  ),
  'ja': (label: '14歳以上です', hint: '14歳未満の方は登録できません。'),
};

/// 킷 판 확인 행 builder — 빈 목록이다(사용자 파일의 행이 킷 판 측정에 섞이지
/// 않게 한다).
List<AppTermsConfirmation> _buildNoTermsConfirmations(
  AppTermsConfirmationsInput input,
) => const <AppTermsConfirmation>[];

/// guide 예시 확인 행 하나를 돌려주는 builder — 화면 언어의 문구를 고른다.
List<AppTermsConfirmation> _buildGuideExampleConfirmation(
  AppTermsConfirmationsInput input,
) {
  final texts = _resolveGuideExampleTexts(
    Localizations.localeOf(input.context).languageCode,
  );
  return <AppTermsConfirmation>[
    AppTermsConfirmation(label: texts.label, missingHint: texts.hint),
  ];
}

/// [languageCode] 의 guide 예시 문구를 돌려준다 — 표에 없는 언어면 실패시킨다.
_ConfirmationTexts _resolveGuideExampleTexts(String languageCode) {
  final texts = _guideExampleTexts[languageCode];
  if (texts == null) {
    throw StateError('guide 예시 문구가 없는 언어: $languageCode');
  }
  return texts;
}

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
          await _verifySlideFit(
            tester,
            termsConfirmationsBuilder: _buildNoTermsConfirmations,
            condition: condition,
          );
        });
      }

      for (final condition in _conditions) {
        final locale = condition.locale;
        final state = condition.showError ? 'err' : 'ok';
        testWidgets('확인 행 1개 · $locale $state — 360×780 · DPR 3 · '
            'inset 115/144 px — 스크롤 0 · 공통 문구 · 행 안내 화면 안', (tester) async {
          await _verifySlideFit(
            tester,
            termsConfirmationsBuilder: _buildGuideExampleConfirmation,
            condition: condition,
            confirmationRow: _resolveGuideExampleTexts(locale),
          );
        });
      }
    },
  );
}

/// 기기 조건으로 약관 슬라이드를 그리고 한 화면 판정을 한다.
///
/// [termsConfirmationsBuilder] 는 화면에 그대로 넘기는 확인 행 builder 다.
/// [confirmationRow] 가 있으면(확인 행 1개 조건) 행 안내 수 · 행 안내 위치 ·
/// 묶음 타일 수도 본다. 판정을 모두 모은 뒤 한 번에 단언한다.
Future<void> _verifySlideFit(
  WidgetTester tester, {
  required AppTermsConfirmationsBuilder termsConfirmationsBuilder,
  required _Condition condition,
  _ConfirmationTexts? confirmationRow,
}) async {
  final locale = condition.locale;
  final state = condition.showError ? 'err' : 'ok';

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
        builder: (_, _) => OnboardingScreen(
          termsConfirmationsBuilder: termsConfirmationsBuilder,
        ),
      ),
    ],
  );
  addTearDown(router.dispose);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        isFirebaseInitializedProvider.overrideWithValue(false),
        authRepositoryProvider.overrideWithValue(_MockAuthRepository()),
        analyticsServiceProvider.overrideWithValue(_MockAnalyticsService()),
        crashlyticsServiceProvider.overrideWithValue(_MockCrashlytics()),
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
  // 체크 없이 「시작하기」 → 필수 미동의 오류 문구(확인 행이 있으면 행 안내도).
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

    final page = tester.getRect(find.byType(PageView));
    if (condition.showError && errorCount == 1) {
      _checkInsidePage(
        violations,
        label: '[error-visible] $locale err',
        rect: tester.getRect(errorFinder),
        page: page,
      );
    }

    if (confirmationRow != null) {
      final tileCount = findTermsTiles().evaluate().length;
      if (tileCount != _tileCountWithOneRow) {
        violations.add('[tiles] $locale $state count=$tileCount');
      }

      final hintFinder = findKeepHangulWordsText(
        confirmationRow.hint,
        skipOffstage: false,
      );
      final hintCount = hintFinder.evaluate().length;
      if (hintCount != expectedErrorCount) {
        violations.add('[row-hint] $locale $state count=$hintCount');
      }
      if (condition.showError && hintCount == 1) {
        _checkInsidePage(
          violations,
          label: '[row-hint-visible] $locale err',
          rect: tester.getRect(hintFinder),
          page: page,
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
}

/// [rect] 가 [page](PageView) 위아래 안에 있는지 보고, 벗어나면 [violations] 에
/// [label] 로 적는다.
void _checkInsidePage(
  List<String> violations, {
  required String label,
  required Rect rect,
  required Rect page,
}) {
  if (rect.top < page.top - _tolerance ||
      rect.bottom > page.bottom + _tolerance) {
    violations.add(
      '$label '
      'rect=${rect.top.toStringAsFixed(1)}'
      '~${rect.bottom.toStringAsFixed(1)} '
      'page=${page.top.toStringAsFixed(1)}'
      '~${page.bottom.toStringAsFixed(1)}',
    );
  }
}
