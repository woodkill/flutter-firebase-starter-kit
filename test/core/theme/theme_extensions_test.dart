import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_starter_kit/core/theme/app_colors.dart';
import 'package:flutter_starter_kit/core/theme/app_icon_sizes.dart';
import 'package:flutter_starter_kit/core/theme/app_spacing.dart';
import 'package:flutter_starter_kit/core/theme/app_theme.dart';
import 'package:flutter_starter_kit/core/theme/app_typography.dart';
import 'package:flutter_starter_kit/core/theme/theme_extensions.dart';
import 'package:flutter_starter_kit/l10n/generated/app_localizations.dart';

void main() {
  group('ThemeX', () {
    testWidgets('context.appColors가 non-null이다', (tester) async {
      late AppColors colors;

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: Builder(
            builder: (context) {
              colors = context.appColors;
              return const SizedBox.shrink();
            },
          ),
        ),
      );

      expect(colors, isNotNull);
      expect(colors, isA<AppColors>());
    });

    testWidgets('context.appTypography가 non-null이다', (tester) async {
      late AppTypography typography;

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: Builder(
            builder: (context) {
              typography = context.appTypography;
              return const SizedBox.shrink();
            },
          ),
        ),
      );

      expect(typography, isNotNull);
      expect(typography, isA<AppTypography>());
    });

    testWidgets('context.appSpacing이 non-null이다', (tester) async {
      late AppSpacing spacing;

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: Builder(
            builder: (context) {
              spacing = context.appSpacing;
              return const SizedBox.shrink();
            },
          ),
        ),
      );

      expect(spacing, isNotNull);
      expect(spacing, isA<AppSpacing>());
    });

    testWidgets('context.appIconSizes가 등록된 토큰을 돌려준다 (리뷰 IN-10)', (
      tester,
    ) async {
      late AppIconSizes iconSizes;
      final custom = const AppIconSizes().copyWith(sm: 28);

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light().copyWith(
            extensions: <ThemeExtension<dynamic>>[custom],
          ),
          home: Builder(
            builder: (context) {
              iconSizes = context.appIconSizes;
              return const SizedBox.shrink();
            },
          ),
        ),
      );

      expect(iconSizes, equals(custom));
    });

    testWidgets('context.colorScheme에 접근할 수 있다', (tester) async {
      late ColorScheme colorScheme;

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: Builder(
            builder: (context) {
              colorScheme = context.colorScheme;
              return const SizedBox.shrink();
            },
          ),
        ),
      );

      expect(colorScheme, isNotNull);
      expect(colorScheme.brightness, equals(Brightness.light));
    });

    testWidgets('context.textTheme에 접근할 수 있다', (tester) async {
      late TextTheme textTheme;

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: Builder(
            builder: (context) {
              textTheme = context.textTheme;
              return const SizedBox.shrink();
            },
          ),
        ),
      );

      expect(textTheme, isNotNull);
    });
  });

  // ─── T-03-WR-03: 타이포그래피 접근 경로 일관성 ───────────────
  //
  // 구 구현은 `Typography.material2021().englishLike` 기하를 고정 스냅샷으로
  // 굽어 extension 에 등록했다. Flutter 는 `Theme.build` 에서
  // `ThemeData.localize(theme, theme.typography.geometryThemeFor(scriptCategory))`
  // 로 로케일별 기하를 적용하며, ko/ja 는 `ScriptCategory.dense`
  // (`textBaseline: ideographic`) 다. 그 결과 `context.textTheme` 과
  // `context.appTypography` 가 갈려(실측: alphabetic vs ideographic) 같은 화면
  // 안에서 baseline 정렬이 어긋났다.
  group('T-03-WR-03: appTypography 가 로케일별 기하를 따른다', () {
    /// [locale] 로케일에서 15개 스타일이 테마 textTheme 과 일치하는지 단언한다.
    Future<void> expectStylesMatchTheme(
      WidgetTester tester,
      Locale locale,
    ) async {
      late AppTypography typography;
      late TextTheme textTheme;

      await tester.pumpWidget(
        MaterialApp(
          locale: locale,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: AppTheme.light(),
          home: Builder(
            builder: (context) {
              typography = context.appTypography;
              textTheme = Theme.of(context).textTheme;
              return const SizedBox.shrink();
            },
          ),
        ),
      );

      final pairs = <String, List<TextStyle?>>{
        'displayLarge': <TextStyle?>[
          typography.displayLarge,
          textTheme.displayLarge,
        ],
        'displayMedium': <TextStyle?>[
          typography.displayMedium,
          textTheme.displayMedium,
        ],
        'displaySmall': <TextStyle?>[
          typography.displaySmall,
          textTheme.displaySmall,
        ],
        'headlineLarge': <TextStyle?>[
          typography.headlineLarge,
          textTheme.headlineLarge,
        ],
        'headlineMedium': <TextStyle?>[
          typography.headlineMedium,
          textTheme.headlineMedium,
        ],
        'headlineSmall': <TextStyle?>[
          typography.headlineSmall,
          textTheme.headlineSmall,
        ],
        'titleLarge': <TextStyle?>[typography.titleLarge, textTheme.titleLarge],
        'titleMedium': <TextStyle?>[
          typography.titleMedium,
          textTheme.titleMedium,
        ],
        'titleSmall': <TextStyle?>[typography.titleSmall, textTheme.titleSmall],
        'bodyLarge': <TextStyle?>[typography.bodyLarge, textTheme.bodyLarge],
        'bodyMedium': <TextStyle?>[typography.bodyMedium, textTheme.bodyMedium],
        'bodySmall': <TextStyle?>[typography.bodySmall, textTheme.bodySmall],
        'labelLarge': <TextStyle?>[typography.labelLarge, textTheme.labelLarge],
        'labelMedium': <TextStyle?>[
          typography.labelMedium,
          textTheme.labelMedium,
        ],
        'labelSmall': <TextStyle?>[typography.labelSmall, textTheme.labelSmall],
      };

      pairs.forEach((name, styles) {
        expect(
          styles[0],
          equals(styles[1]),
          reason:
              '$locale — context.appTypography.$name 이 '
              'Theme.of(context).textTheme.$name 과 다르다 (WR-03 회귀). '
              '두 접근 경로가 갈리면 baseline 정렬·폰트 drift 가 발생한다.',
        );
      });
    }

    testWidgets('en 로케일 — 15개 스타일이 textTheme 과 일치한다', (tester) async {
      await expectStylesMatchTheme(tester, const Locale('en'));
    });

    testWidgets('ko 로케일 — 15개 스타일이 textTheme 과 일치한다', (tester) async {
      await expectStylesMatchTheme(tester, const Locale('ko'));
    });

    testWidgets('ko 로케일 — dense 기하(ideographic baseline)가 반영된다', (
      tester,
    ) async {
      late AppTypography typography;

      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('ko'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: AppTheme.light(),
          home: Builder(
            builder: (context) {
              typography = context.appTypography;
              return const SizedBox.shrink();
            },
          ),
        ),
      );

      expect(
        typography.bodyMedium.textBaseline,
        TextBaseline.ideographic,
        reason:
            'ko 는 ScriptCategory.dense — 구 구현은 englishLike 스냅샷을 굽어 '
            'alphabetic 이 나왔다 (WR-03 실측).',
      );
      expect(
        typography.bodyMedium.fontSize,
        isNotNull,
        reason: '로케라이즈된 textTheme 은 fontSize 가 resolve 되어 있다.',
      );
    });

    testWidgets('사용자 extension override 가 테마 기본값보다 우선한다', (tester) async {
      late AppTypography typography;
      late TextTheme textTheme;
      final base = AppTheme.light();

      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('ko'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: base.copyWith(
            extensions: <ThemeExtension<dynamic>>[
              AppColors.fromBrightness(Brightness.light),
              const AppSpacing(),
              AppTypography.empty.copyWith(
                bodyMedium: const TextStyle(fontSize: 99),
              ),
            ],
          ),
          home: Builder(
            builder: (context) {
              typography = context.appTypography;
              textTheme = Theme.of(context).textTheme;
              return const SizedBox.shrink();
            },
          ),
        ),
      );

      expect(
        typography.bodyMedium.fontSize,
        99,
        reason: 'override 로 지정한 fontSize 가 우선되어야 한다.',
      );
      expect(
        typography.bodyMedium.textBaseline,
        TextBaseline.ideographic,
        reason: 'override 가 지정하지 않은 속성은 로케일 기하가 유지되어야 한다.',
      );
      expect(
        typography.titleLarge,
        equals(textTheme.titleLarge),
        reason: 'override 가 건드리지 않은 스타일은 테마 값 그대로여야 한다.',
      );
    });
  });

  // ─── T-03-WR-04: extension 미등록 테마 방어 ─────────────────
  //
  // 구 구현은 세 getter 모두 `Theme.of(this).extension<T>()!` 로 강제
  // 언랩해서, 스타터킷 사용자가 (a) 자체 ThemeData 로 교체하거나
  // (b) 하위 트리에 `Theme(data: ThemeData(...))` 를 끼우거나 (c) 위젯
  // 테스트에서 맨몸 `MaterialApp()` 만 감싸면 즉시
  // `Null check operator used on a null value` 로 크래시했다.
  group('T-03-WR-04: extension 미등록 테마에서도 기본 토큰을 돌려준다', () {
    testWidgets('맨몸 MaterialApp 에서 세 getter 가 크래시하지 않는다', (tester) async {
      late AppColors colors;
      late AppSpacing spacing;
      late AppTypography typography;
      late AppIconSizes iconSizes;

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              colors = context.appColors;
              spacing = context.appSpacing;
              typography = context.appTypography;
              iconSizes = context.appIconSizes;
              return const SizedBox.shrink();
            },
          ),
        ),
      );

      expect(tester.takeException(), isNull);
      expect(colors, equals(AppColors.fromBrightness(Brightness.light)));
      expect(spacing, equals(const AppSpacing()));
      expect(iconSizes, equals(const AppIconSizes()));
      expect(typography.bodyMedium.fontSize, isNotNull);
    });

    testWidgets('하위 트리의 dark Theme 에서는 dark 기본 토큰으로 폴백한다', (tester) async {
      late AppColors colors;

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: Theme(
            // 사용자가 하위 트리에 자체 ThemeData 를 끼우는 시나리오.
            data: ThemeData(brightness: Brightness.dark),
            child: Builder(
              builder: (context) {
                colors = context.appColors;
                return const SizedBox.shrink();
              },
            ),
          ),
        ),
      );

      expect(tester.takeException(), isNull);
      expect(colors, equals(AppColors.fromBrightness(Brightness.dark)));
    });
  });
}
