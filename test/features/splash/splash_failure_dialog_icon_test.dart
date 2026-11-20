// 스플래시 실패 대화상자의 구름 아이콘이 대화상자 바탕(surfaceContainerHigh)과
// 짝인 오류 색 역할(error)로 그려지는지 고정한다.
// 아이콘 색은 Icon 이 칠하는 글리프(RichText)의 색으로, 바탕은 아이콘을 감싸는
// Material 의 색으로 읽는다 — 역할 상수가 아니라 실제로 그린 값이다.
// 킷 기본 테마는 사용자 색 역할 자리를 거치므로 내 팔레트에서 아이콘이 안
// 보이면 대비 시험이 실패해 알려 준다. 뒤집은 오류 상자 팔레트는 errorContainer
// 짝만 서로 바꿔 아이콘이 그 짝에 기대지 않는지 본다.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_starter_kit/core/config/auth_retry_config.dart';
import 'package:flutter_starter_kit/core/config/splash_config.dart';
import 'package:flutter_starter_kit/core/error/app_exception.dart';
import 'package:flutter_starter_kit/core/error/result.dart';
import 'package:flutter_starter_kit/core/router/app_routes.dart';
import 'package:flutter_starter_kit/core/theme/app_color_scheme_slot.dart';
import 'package:flutter_starter_kit/core/theme/app_theme.dart';
import 'package:flutter_starter_kit/features/auth/data/auth_repository.dart';
import 'package:flutter_starter_kit/features/splash/presentation/splash_initializer.dart';
import 'package:flutter_starter_kit/features/splash/presentation/splash_screen.dart';
import 'package:flutter_starter_kit/l10n/generated/app_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';

/// 익명 로그인 실패를 돌려주는 인증 저장소 목.
class _MockAuthRepository extends Mock implements AuthRepository {}

/// 일반 글자 대비 기준(WCAG AA).
const double _minContrast = 4.5;

/// 받은 팔레트에서 오류 상자 짝(errorContainer · onErrorContainer)만 서로 바꾼다.
ColorScheme _swappedErrorContainerScheme(AppColorSchemeInput input) =>
    input.scheme.copyWith(
      errorContainer: input.scheme.onErrorContainer,
      onErrorContainer: input.scheme.errorContainer,
    );

/// [color] 를 `#aarrggbb` 소문자 16진 문자열로 돌려준다.
String _hex(Color color) =>
    '#${color.toARGB32().toRadixString(16).padLeft(8, '0')}';

/// 두 색의 대비비 `(밝은 쪽 휘도 + 0.05) / (어두운 쪽 휘도 + 0.05)` 를 돌려준다.
double _contrastRatio(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  return la > lb ? (la + 0.05) / (lb + 0.05) : (lb + 0.05) / (la + 0.05);
}

/// 킷 시험용 로고 아래 내용 — 내 화면(`splash_body.dart`)에 기대지 않는다.
Widget _buildTestBody(BuildContext context, {required bool hasFailure}) =>
    Text(hasFailure ? 'TEST_BODY failed' : 'TEST_BODY running');

/// [theme] 으로 스플래시를 띄워 익명 로그인 실패 대화상자까지 진행한다.
Future<void> _pumpFailureDialog(WidgetTester tester, ThemeData theme) async {
  final repo = _MockAuthRepository();
  when(
    repo.signInAnonymously,
  ).thenAnswer((_) async => const Result.failure(NoInternetConnection()));
  final initializer = SplashInitializer(
    authRepository: repo,
    isFirebaseInitialized: true,
    currentUserIsNull: true,
    onboardingFuture: Future.value(true),
    isSocialLinkInProgress: false,
  );
  final router = GoRouter(
    initialLocation: AppRoutes.splash,
    routes: [
      GoRoute(
        path: AppRoutes.splash,
        name: AppRoutes.splashName,
        builder: (_, _) => const SplashScreen(bodyBuilder: _buildTestBody),
      ),
      GoRoute(
        path: AppRoutes.home,
        name: AppRoutes.homeName,
        builder: (_, _) => const Scaffold(body: Text('HOME')),
      ),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [splashInitializerProvider.overrideWith((ref) => initializer)],
      child: MaterialApp.router(
        theme: theme,
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        routerConfig: router,
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 50));
  await tester.pumpAndSettle();
  expect(find.byType(AlertDialog), findsOneWidget);
}

/// 대화상자 안 구름 아이콘을 찾는다.
Finder _findDialogIcon() => find.descendant(
  of: find.byType(AlertDialog),
  matching: find.byIcon(Icons.cloud_off),
);

/// 구름 아이콘이 실제로 칠하는 글리프 색을 읽는다.
///
/// 대화상자가 감싸는 IconTheme 은 아이콘 자체 색 인자를 반영하지 않으므로
/// 실제로 칠하는 span 색을 읽는다 — [Icon] 아래 [RichText] 의 글자 style 색이다.
Color _readGlyphColor(WidgetTester tester) {
  final icon = _findDialogIcon();
  expect(icon, findsOneWidget);
  final glyph = find.descendant(of: icon, matching: find.byType(RichText));
  expect(glyph, findsOneWidget);
  final color = tester.widget<RichText>(glyph).text.style?.color;
  if (color == null) {
    fail('구름 아이콘 글리프에 색이 없다');
  }
  return color;
}

/// 대화상자 바탕색을 읽는다 — 구름 아이콘을 감싸는 [Material] 의 색이다.
Color _readDialogBackground(WidgetTester tester) {
  final material = find.ancestor(
    of: _findDialogIcon(),
    matching: find.byType(Material),
  );
  expect(material, findsOneWidget);
  final color = tester.widget<Material>(material).color;
  if (color == null) {
    fail('대화상자 바탕에 색이 없다');
  }
  return color;
}

void main() {
  setUp(() {
    SplashConfig.overrideMinDuration = const Duration(milliseconds: 1);
    AuthRetryConfig.overrideBackoffSteps = const [
      Duration(milliseconds: 1),
      Duration(milliseconds: 1),
      Duration(milliseconds: 1),
    ];
  });

  tearDown(() {
    SplashConfig.overrideMinDuration = null;
    AuthRetryConfig.overrideBackoffSteps = null;
  });

  final themes = <String, ThemeData>{
    '킷 라이트': AppTheme.light(),
    '킷 다크': AppTheme.dark(),
    '킷 라이트 고대비': AppTheme.light(contrastLevel: 1),
    '킷 다크 고대비': AppTheme.dark(contrastLevel: 1),
    '뒤집은 오류 상자 라이트': AppTheme.light(
      colorSchemeBuilder: _swappedErrorContainerScheme,
    ),
    '뒤집은 오류 상자 다크': AppTheme.dark(
      colorSchemeBuilder: _swappedErrorContainerScheme,
    ),
  };

  group('스플래시 실패 대화상자 아이콘 색 역할', () {
    for (final MapEntry(key: name, value: theme) in themes.entries) {
      testWidgets('$name — 대화상자 바탕 역할', (tester) async {
        await _pumpFailureDialog(tester, theme);
        final background = _readDialogBackground(tester);

        expect(
          _hex(background),
          _hex(theme.colorScheme.surfaceContainerHigh),
          reason: '대화상자 바탕색이 surfaceContainerHigh 와 다르다',
        );
      });

      testWidgets('$name — 아이콘 글리프 역할', (tester) async {
        await _pumpFailureDialog(tester, theme);
        final glyph = _readGlyphColor(tester);

        expect(
          _hex(glyph),
          _hex(theme.colorScheme.error),
          reason: '아이콘 글리프 색이 대화상자 바탕의 짝 error 와 다르다',
        );
      });

      testWidgets('$name — 아이콘 · 바탕 대비', (tester) async {
        await _pumpFailureDialog(tester, theme);
        final glyph = _readGlyphColor(tester);
        final background = _readDialogBackground(tester);

        expect(
          _contrastRatio(glyph, background),
          greaterThanOrEqualTo(_minContrast),
          reason: '아이콘 · 대화상자 바탕 대비가 4.5 보다 낮다',
        );
      });
    }
  });
}
