import 'package:flutter/material.dart';
import 'package:flutter_starter_kit/core/theme/app_colors.dart';
import 'package:flutter_starter_kit/core/theme/app_icon_sizes.dart';
import 'package:flutter_starter_kit/core/theme/app_opacity.dart';
import 'package:flutter_starter_kit/core/theme/app_radius.dart';
import 'package:flutter_starter_kit/core/theme/app_spacing.dart';
import 'package:flutter_starter_kit/core/theme/app_theme.dart';
import 'package:flutter_starter_kit/core/theme/app_typography.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/planning_docs.dart';
import '../../helpers/source_text.dart';

void main() {
  group('AppTheme', () {
    group('seedColor', () {
      test('seedColor는 Colors.deepPurple이다', () {
        expect(AppTheme.seedColor, equals(Colors.deepPurple));
      });
    });

    group('light', () {
      test('ThemeData에 AppColors extension이 등록되어 있다', () {
        final theme = AppTheme.light();

        expect(theme.extension<AppColors>(), isNotNull);
      });

      test('ThemeData에 AppTypography extension이 등록되어 있다', () {
        final theme = AppTheme.light();

        expect(theme.extension<AppTypography>(), isNotNull);
      });

      test('ThemeData에 AppSpacing extension이 등록되어 있다', () {
        final theme = AppTheme.light();

        expect(theme.extension<AppSpacing>(), isNotNull);
      });

      test('ThemeData에 AppIconSizes extension이 등록되어 있다 (리뷰 IN-10)', () {
        final theme = AppTheme.light();

        expect(theme.extension<AppIconSizes>(), equals(const AppIconSizes()));
      });

      test(
        'ThemeData에 AppRadius · AppOpacity extension이 const 기본값으로 등록되어 있다',
        () {
          final theme = AppTheme.light();

          expect(theme.extension<AppRadius>(), equals(const AppRadius()));
          expect(theme.extension<AppOpacity>(), equals(const AppOpacity()));
        },
      );

      test('colorScheme.brightness가 Brightness.light이다', () {
        final theme = AppTheme.light();

        expect(theme.colorScheme.brightness, equals(Brightness.light));
      });
    });

    test('light · dark 의 extensions.keys 는 6종이다', () {
      const expected = <Object>[
        AppColors,
        AppTypography,
        AppSpacing,
        AppIconSizes,
        AppRadius,
        AppOpacity,
      ];

      expect(AppTheme.light().extensions.keys, unorderedEquals(expected));
      expect(AppTheme.dark().extensions.keys, unorderedEquals(expected));
    });

    group('dark', () {
      test('ThemeData에 AppColors extension이 등록되어 있다', () {
        final theme = AppTheme.dark();

        expect(theme.extension<AppColors>(), isNotNull);
      });

      test('ThemeData에 AppTypography extension이 등록되어 있다', () {
        final theme = AppTheme.dark();

        expect(theme.extension<AppTypography>(), isNotNull);
      });

      test('ThemeData에 AppSpacing extension이 등록되어 있다', () {
        final theme = AppTheme.dark();

        expect(theme.extension<AppSpacing>(), isNotNull);
      });

      test('ThemeData에 AppIconSizes extension이 등록되어 있다 (리뷰 IN-10)', () {
        final theme = AppTheme.dark();

        expect(theme.extension<AppIconSizes>(), equals(const AppIconSizes()));
      });

      test(
        'ThemeData에 AppRadius · AppOpacity extension이 const 기본값으로 등록되어 있다',
        () {
          final theme = AppTheme.dark();

          expect(theme.extension<AppRadius>(), equals(const AppRadius()));
          expect(theme.extension<AppOpacity>(), equals(const AppOpacity()));
        },
      );

      test('colorScheme.brightness가 Brightness.dark이다', () {
        final theme = AppTheme.dark();

        expect(theme.colorScheme.brightness, equals(Brightness.dark));
      });
    });
  });

  // ─── T-03-WR-02: ThemeData 동등성 ────────────────────────
  //
  // `lib/app.dart` 는 build 안에서 `AppTheme.light()`/`dark()` 를 매번 새로
  // 만든다. extension 이 값 동등성을 구현하지 않으면 App 리빌드마다
  // ThemeData 가 불일치로 판정되어 `AnimatedTheme` 이 200ms 보간을
  // 재시작하고 `Theme.of` 의존 서브트리 전체가 리빌드된다.
  group('T-03-WR-02: ThemeData 동등성', () {
    test('AppTheme.light() 두 호출 결과가 == 이다', () {
      expect(AppTheme.light() == AppTheme.light(), isTrue);
      expect(AppTheme.light().hashCode, equals(AppTheme.light().hashCode));
    });

    test('AppTheme.dark() 두 호출 결과가 == 이다', () {
      expect(AppTheme.dark() == AppTheme.dark(), isTrue);
      expect(AppTheme.dark().hashCode, equals(AppTheme.dark().hashCode));
    });

    test('light 와 dark 는 != 이다', () {
      expect(AppTheme.light() == AppTheme.dark(), isFalse);
    });
  });

  // ─── T-03-IN-01: 중복 인자 제거 후 파생값 보존 ──────────────
  //
  // `useMaterial3` 는 Flutter 3.41 기준 기본값 true (`theme_data.dart` 의
  // `useMaterial3 ??= true`), `dark()` 의 `brightness` 는 colorScheme 에서
  // 파생된다. 인자를 지우고도 결과가 동일한지 고정한다.
  group('T-03-IN-01: 중복 인자를 제거해도 파생값은 동일하다', () {
    test('light() 의 brightness 는 light 다', () {
      expect(AppTheme.light().brightness, equals(Brightness.light));
    });

    test('dark() 의 brightness 는 colorScheme 에서 파생된다', () {
      final theme = AppTheme.dark();

      expect(
        theme.brightness,
        equals(Brightness.dark),
        reason:
            'ThemeData(brightness:) 인자를 제거했으므로 colorScheme.brightness '
            '파생이 깨지면 여기서 RED 가 된다.',
      );
      expect(theme.colorScheme.brightness, equals(Brightness.dark));
    });
  });

  // ─── T-03-IN-02: seedColor 주입 경로 ─────────────────────
  //
  // 스타터킷 커스터마이징 포인트인데도 상수였다 — 소스 수정 외에
  // 교체 경로가 없었다.
  group('T-03-IN-02: seedColor 를 인자로 주입할 수 있다', () {
    test('seedColor 는 MaterialColor 로 명시 타입이다', () {
      // public API 의 명시 타입 계약을 고정하려는 검사라 늘 참이어도 둔다.
      // ignore: unnecessary_type_check
      expect(AppTheme.seedColor is MaterialColor, isTrue);
    });

    test('다른 seed 로 light() 를 만들면 colorScheme.primary 가 달라진다', () {
      final defaultTheme = AppTheme.light();
      final tealTheme = AppTheme.light(seedColor: Colors.teal);

      expect(
        tealTheme.colorScheme.primary,
        isNot(equals(defaultTheme.colorScheme.primary)),
      );
      expect(tealTheme.colorScheme.brightness, equals(Brightness.light));
    });

    test('다른 seed 로 dark() 를 만들면 colorScheme.primary 가 달라진다', () {
      final defaultTheme = AppTheme.dark();
      final tealTheme = AppTheme.dark(seedColor: Colors.teal);

      expect(
        tealTheme.colorScheme.primary,
        isNot(equals(defaultTheme.colorScheme.primary)),
      );
      expect(tealTheme.colorScheme.brightness, equals(Brightness.dark));
    });

    test('인자를 생략하면 기본 seedColor 와 동일한 테마다', () {
      // 기본값과 같은 색을 상수가 아닌 값으로 넘겨 「생략 = 기본 seed」 를 견준다.
      final explicitSeed = Color(AppTheme.seedColor.toARGB32());
      expect(
        AppTheme.light() == AppTheme.light(seedColor: explicitSeed),
        isTrue,
      );
    });
  });

  // ─── 브랜드 원색 토큰 ─────────────────────────────────────
  //
  // 테마에 넘긴 시드가 그대로 `AppColors.brand` 가 된다 — `colorScheme.primary`
  // 처럼 다시 계산하지 않고, 라이트 · 다크가 같은 값이다.
  group('AppColors.brand = 넘긴 시드', () {
    test('light · dark 의 brand 는 넘긴 시드 색이다', () {
      const yellow = Color(0xFFF2B134);

      expect(
        AppTheme.light(seedColor: yellow).extension<AppColors>()!.brand,
        equals(yellow),
      );
      expect(
        AppTheme.dark(seedColor: yellow).extension<AppColors>()!.brand,
        equals(yellow),
      );
    });

    test('MaterialColor 시드도 불투명 Color 로 정규화해 넣는다', () {
      final expected = Color(Colors.teal.toARGB32());

      expect(
        AppTheme.light(seedColor: Colors.teal).extension<AppColors>()!.brand,
        equals(expected),
      );
      expect(
        AppTheme.dark(seedColor: Colors.teal).extension<AppColors>()!.brand,
        equals(expected),
      );
    });

    test('시드를 생략한 테마의 brand 는 AppTheme.brandColor 다', () {
      // 시험 환경은 brandColor 를 주입하지 않으므로 둘 다 킷 기본 색이다.
      expect(
        AppTheme.light().extension<AppColors>()!.brand,
        equals(AppTheme.brandColor),
      );
    });

    test(
      'lib/app.dart 가 AppTheme.brandColor 를 라이트 · 다크 테마 시드로 넘긴다',
      () {
        final String code = stripSlashComments(readTrackedFile('lib/app.dart'));

        expect(
          RegExp(
            r'final\s+Color\s+seed\s*=\s*AppTheme\.brandColor\s*;',
          ).allMatches(code),
          hasLength(1),
        );
        expect(
          RegExp(
            r'AppTheme\.light\(\s*seedColor:\s*seed\s*\)',
          ).allMatches(code),
          hasLength(1),
        );
        expect(
          RegExp(r'AppTheme\.dark\(\s*seedColor:\s*seed\s*\)').allMatches(code),
          hasLength(1),
        );
      },
      // 가이드가 adopter 에게 app.dart 시드 손질을 안내하므로 유지보수자 트리에서만 본다.
      skip: skipUnlessMaintainerTree(),
    );
  });
}
