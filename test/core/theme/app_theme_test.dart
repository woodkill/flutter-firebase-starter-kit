import 'package:flutter/material.dart';
import 'package:flutter_starter_kit/core/theme/app_color_scheme.dart';
import 'package:flutter_starter_kit/core/theme/app_color_scheme_slot.dart';
import 'package:flutter_starter_kit/core/theme/app_colors.dart';
import 'package:flutter_starter_kit/core/theme/app_elevation.dart';
import 'package:flutter_starter_kit/core/theme/app_icon_sizes.dart';
import 'package:flutter_starter_kit/core/theme/app_opacity.dart';
import 'package:flutter_starter_kit/core/theme/app_radius.dart';
import 'package:flutter_starter_kit/core/theme/app_spacing.dart';
import 'package:flutter_starter_kit/core/theme/app_theme.dart';
import 'package:flutter_starter_kit/core/theme/app_typography.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/planning_docs.dart';
import '../../helpers/received_color_scheme.dart';
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

      test('T-24-ELV-06: ThemeData에 AppElevation extension이 const 기본값으로 '
          '등록되어 있다', () {
        final theme = AppTheme.light();

        expect(theme.extension<AppElevation>(), equals(const AppElevation()));
      });

      test('colorScheme.brightness가 Brightness.light이다', () {
        final theme = AppTheme.light();

        expect(theme.colorScheme.brightness, equals(Brightness.light));
      });
    });

    test('light · dark 의 extensions.keys 는 7종이다', () {
      const expected = <Object>[
        AppColors,
        AppTypography,
        AppSpacing,
        AppIconSizes,
        AppRadius,
        AppOpacity,
        AppElevation,
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

      test('T-24-ELV-06: ThemeData에 AppElevation extension이 const 기본값으로 '
          '등록되어 있다', () {
        final theme = AppTheme.dark();

        expect(theme.extension<AppElevation>(), equals(const AppElevation()));
      });

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
      final defaultTheme = AppTheme.light(
        colorSchemeBuilder: keepReceivedColorScheme,
      );
      final tealTheme = AppTheme.light(
        seedColor: Colors.teal,
        colorSchemeBuilder: keepReceivedColorScheme,
      );

      expect(
        tealTheme.colorScheme.primary,
        isNot(equals(defaultTheme.colorScheme.primary)),
      );
      expect(tealTheme.colorScheme.brightness, equals(Brightness.light));
    });

    test('다른 seed 로 dark() 를 만들면 colorScheme.primary 가 달라진다', () {
      final defaultTheme = AppTheme.dark(
        colorSchemeBuilder: keepReceivedColorScheme,
      );
      final tealTheme = AppTheme.dark(
        seedColor: Colors.teal,
        colorSchemeBuilder: keepReceivedColorScheme,
      );

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

  // ─── 대비 · 색 변형 인자 ─────────────────────────────────
  //
  // 두 인자는 SDK `ColorScheme.fromSeed` 의 이름 · 기본값 그대로다. 생략하면
  // 지금 팔레트와 같아야 골든이 바뀌지 않는다.
  //
  // `fromSeed` 와 직접 견주므로 받은 팔레트를 그대로 돌려주는 builder 를 넘긴다 —
  // 내 앱이 자리를 채워도 통과한다.
  group('T-24-THM: 대비 · 색 변형 인자', () {
    test('T-24-THM-01: 인자를 생략한 테마는 SDK 기본값을 넘긴 테마와 같다', () {
      // 기본값과 같은 값을 상수가 아닌 값으로 넘겨 「생략 = SDK 기본값」 을 견준다.
      final contrastLevel = double.parse('0.0');
      final variant = DynamicSchemeVariant.values.byName('tonalSpot');

      expect(
        AppTheme.light(colorSchemeBuilder: keepReceivedColorScheme) ==
            AppTheme.light(
              colorSchemeBuilder: keepReceivedColorScheme,
              contrastLevel: contrastLevel,
              dynamicSchemeVariant: variant,
            ),
        isTrue,
      );
      expect(
        AppTheme.dark(colorSchemeBuilder: keepReceivedColorScheme) ==
            AppTheme.dark(
              colorSchemeBuilder: keepReceivedColorScheme,
              contrastLevel: contrastLevel,
              dynamicSchemeVariant: variant,
            ),
        isTrue,
      );
      expect(
        AppTheme.light(colorSchemeBuilder: keepReceivedColorScheme).colorScheme,
        equals(ColorScheme.fromSeed(seedColor: AppTheme.seedColor)),
      );
      expect(
        AppTheme.dark(colorSchemeBuilder: keepReceivedColorScheme).colorScheme,
        equals(
          ColorScheme.fromSeed(
            seedColor: AppTheme.seedColor,
            brightness: Brightness.dark,
          ),
        ),
      );
    });

    test('T-24-THM-02: contrastLevel 1.0 은 대비 1.0 팔레트이고 '
        'AppColors 는 그대로다', () {
      final light = AppTheme.light(
        contrastLevel: 1,
        colorSchemeBuilder: keepReceivedColorScheme,
      );
      final dark = AppTheme.dark(
        contrastLevel: 1,
        colorSchemeBuilder: keepReceivedColorScheme,
      );

      expect(
        light.colorScheme,
        equals(
          ColorScheme.fromSeed(seedColor: AppTheme.seedColor, contrastLevel: 1),
        ),
      );
      expect(
        dark.colorScheme,
        equals(
          ColorScheme.fromSeed(
            seedColor: AppTheme.seedColor,
            brightness: Brightness.dark,
            contrastLevel: 1,
          ),
        ),
      );
      expect(
        light.colorScheme,
        isNot(
          equals(
            AppTheme.light(
              colorSchemeBuilder: keepReceivedColorScheme,
            ).colorScheme,
          ),
        ),
      );
      expect(
        dark.colorScheme,
        isNot(
          equals(
            AppTheme.dark(
              colorSchemeBuilder: keepReceivedColorScheme,
            ).colorScheme,
          ),
        ),
      );
      expect(
        light.extension<AppColors>(),
        equals(
          AppTheme.light(
            colorSchemeBuilder: keepReceivedColorScheme,
          ).extension<AppColors>(),
        ),
      );
      expect(
        dark.extension<AppColors>(),
        equals(
          AppTheme.dark(
            colorSchemeBuilder: keepReceivedColorScheme,
          ).extension<AppColors>(),
        ),
      );
    });

    test('T-24-THM-03: dynamicSchemeVariant 는 fromSeed 로 넘어간다', () {
      const variant = DynamicSchemeVariant.fidelity;
      final light = AppTheme.light(
        dynamicSchemeVariant: variant,
        colorSchemeBuilder: keepReceivedColorScheme,
      );
      final dark = AppTheme.dark(
        dynamicSchemeVariant: variant,
        colorSchemeBuilder: keepReceivedColorScheme,
      );

      expect(
        light.colorScheme,
        equals(
          ColorScheme.fromSeed(
            seedColor: AppTheme.seedColor,
            dynamicSchemeVariant: variant,
          ),
        ),
      );
      expect(
        dark.colorScheme,
        equals(
          ColorScheme.fromSeed(
            seedColor: AppTheme.seedColor,
            brightness: Brightness.dark,
            dynamicSchemeVariant: variant,
          ),
        ),
      );
      expect(
        light.colorScheme,
        isNot(
          equals(
            AppTheme.light(
              colorSchemeBuilder: keepReceivedColorScheme,
            ).colorScheme,
          ),
        ),
      );
      expect(
        dark.colorScheme,
        isNot(
          equals(
            AppTheme.dark(
              colorSchemeBuilder: keepReceivedColorScheme,
            ).colorScheme,
          ),
        ),
      );
    });
  });

  group('아래 시트 테마', () {
    final expectedRadius = BorderRadius.vertical(
      top: Radius.circular(const AppRadius().xl),
    );

    for (final (String label, ThemeData Function() build)
        in <(String, ThemeData Function())>[
          ('light', AppTheme.light),
          ('dark', AppTheme.dark),
        ]) {
      test('$label — 손잡이를 켜고 배경은 지정하지 않는다', () {
        final BottomSheetThemeData sheet = build().bottomSheetTheme;

        expect(sheet.showDragHandle, isTrue);
        expect(sheet.backgroundColor, isNull);
        expect(sheet.modalBackgroundColor, isNull);
      });

      test('$label — 위 모서리는 등록한 AppRadius 의 xl 이다', () {
        final ThemeData theme = build();

        expect(theme.extension<AppRadius>()!.xl, 28);
        expect(
          theme.bottomSheetTheme.shape,
          isA<RoundedRectangleBorder>().having(
            (RoundedRectangleBorder s) => s.borderRadius,
            'borderRadius',
            expectedRadius,
          ),
        );
        expect(
          expectedRadius,
          BorderRadius.vertical(
            top: Radius.circular(theme.extension<AppRadius>()!.xl),
          ),
        );
      });

      test('$label — 버튼 · 구분선 · 진행 표시 테마는 Material 3 기본 그대로다', () {
        final ThemeData theme = build();

        expect(theme.filledButtonTheme, const FilledButtonThemeData());
        expect(theme.textButtonTheme, const TextButtonThemeData());
        expect(theme.outlinedButtonTheme, const OutlinedButtonThemeData());
        expect(theme.dividerTheme, const DividerThemeData());
        expect(
          theme.progressIndicatorTheme,
          const ProgressIndicatorThemeData(),
        );
      });
    }

    test('copyWith(extensions:) 로 바꾼 AppRadius 는 시트 모서리로 번지지 않는다', () {
      final ThemeData theme = AppTheme.light().copyWith(
        extensions: <ThemeExtension<dynamic>>[
          const AppRadius().copyWith(xl: 8),
        ],
      );

      expect(theme.extension<AppRadius>()!.xl, 8);
      expect(
        theme.bottomSheetTheme.shape,
        isA<RoundedRectangleBorder>().having(
          (RoundedRectangleBorder s) => s.borderRadius,
          'borderRadius',
          expectedRadius,
        ),
      );
    });
  });

  // ─── T-29-SLOT: 색 역할 자리 ─────────────────────────────
  //
  // 테마는 시드 팔레트를 색 역할 자리(`colorSchemeBuilder`)에 한 번 넘기고,
  // 돌려받은 팔레트로 `ThemeData` 를 만든다.
  group('T-29-SLOT: 색 역할 자리', () {
    test('T-29-SLOT-01: builder 는 테마 하나에 한 번 불리고 돌려준 팔레트가 colorScheme 이다', () {
      for (final brightness in Brightness.values) {
        final inputs = <AppColorSchemeInput>[];
        ColorScheme recordInput(AppColorSchemeInput input) {
          inputs.add(input);
          return input.scheme;
        }

        final ThemeData theme = brightness == Brightness.light
            ? AppTheme.light(colorSchemeBuilder: recordInput)
            : AppTheme.dark(colorSchemeBuilder: recordInput);

        expect(inputs, hasLength(1), reason: brightness.name);
        expect(
          theme.colorScheme,
          equals(inputs.single.scheme),
          reason: brightness.name,
        );
      }
    });

    test(
      'T-29-SLOT-02: builder 가 받는 scheme 은 같은 인자의 ColorScheme.fromSeed 다',
      () {
        const variants = <DynamicSchemeVariant>[
          DynamicSchemeVariant.tonalSpot,
          DynamicSchemeVariant.fidelity,
        ];
        for (final seed in <Color>[AppTheme.seedColor, Colors.teal]) {
          for (final brightness in Brightness.values) {
            for (final contrastLevel in <double>[0, 1]) {
              for (final variant in variants) {
                final input = _receivedInput(
                  brightness,
                  seedColor: seed,
                  contrastLevel: contrastLevel,
                  dynamicSchemeVariant: variant,
                );

                expect(
                  input.scheme,
                  equals(
                    ColorScheme.fromSeed(
                      seedColor: seed,
                      brightness: brightness,
                      contrastLevel: contrastLevel,
                      dynamicSchemeVariant: variant,
                    ),
                  ),
                  reason:
                      '$seed ${brightness.name} $contrastLevel ${variant.name}',
                );
              }
            }
          }
        }
      },
    );

    test('T-29-SLOT-03: 입력의 seedColor 는 정규화한 시드이고 대비 · 색 변형은 넘긴 값이다', () {
      final normalizedTeal = Color(Colors.teal.toARGB32());
      for (final brightness in Brightness.values) {
        final input = _receivedInput(
          brightness,
          seedColor: Colors.teal,
          contrastLevel: 0.5,
          dynamicSchemeVariant: DynamicSchemeVariant.fidelity,
        );
        final theme = _buildThemeFor(brightness, seedColor: Colors.teal);

        expect(
          input.seedColor,
          equals(normalizedTeal),
          reason: brightness.name,
        );
        expect(
          input.seedColor,
          equals(theme.extension<AppColors>()!.brand),
          reason: brightness.name,
        );
        expect(input.contrastLevel, equals(0.5), reason: brightness.name);
        expect(
          input.dynamicSchemeVariant,
          equals(DynamicSchemeVariant.fidelity),
          reason: brightness.name,
        );
        // 고대비 테마는 대비 단계 1.0 을 넘긴다.
        expect(
          _receivedInput(brightness, contrastLevel: 1).contrastLevel,
          equals(1.0),
          reason: brightness.name,
        );
      }
    });

    test('T-29-SLOT-04: 돌려준 팔레트가 colorScheme 이고 ThemeData 파생값도 따라간다', () {
      const changedPrimary = Color(0xFF123456);
      ColorScheme? lightResult;
      final light = AppTheme.light(
        colorSchemeBuilder: (input) {
          lightResult = input.scheme.copyWith(primary: changedPrimary);
          return lightResult!;
        },
      );

      expect(light.colorScheme, equals(lightResult));
      expect(light.colorScheme.primary, equals(changedPrimary));
      expect(light.primaryColor, equals(changedPrimary));

      const changedSurface = Color(0xFF0A1B2C);
      ColorScheme? darkResult;
      final dark = AppTheme.dark(
        colorSchemeBuilder: (input) {
          darkResult = input.scheme.copyWith(surface: changedSurface);
          return darkResult!;
        },
      );

      expect(dark.colorScheme, equals(darkResult));
      expect(dark.scaffoldBackgroundColor, equals(changedSurface));
      expect(dark.canvasColor, equals(changedSurface));
    });

    test('T-29-SLOT-05: 팔레트를 바꿔도 brand · extension · 시트 테마 · 글꼴은 그대로다', () {
      ColorScheme repaint(AppColorSchemeInput input) => input.scheme.copyWith(
        primary: const Color(0xFF123456),
        surface: const Color(0xFF0A1B2C),
      );
      for (final brightness in Brightness.values) {
        final changed = _buildThemeFor(
          brightness,
          seedColor: Colors.teal,
          colorSchemeBuilder: repaint,
        );
        final plain = _buildThemeFor(brightness, seedColor: Colors.teal);

        expect(
          changed.colorScheme,
          isNot(equals(plain.colorScheme)),
          reason: brightness.name,
        );
        expect(
          changed.extension<AppColors>()!.brand,
          equals(Color(Colors.teal.toARGB32())),
          reason: brightness.name,
        );
        expect(
          changed.extensions,
          equals(plain.extensions),
          reason: brightness.name,
        );
        expect(
          changed.bottomSheetTheme,
          equals(plain.bottomSheetTheme),
          reason: brightness.name,
        );
        expect(
          changed.textTheme.bodyMedium?.fontFamily,
          equals(AppTheme.fontFamily),
          reason: brightness.name,
        );
        expect(
          changed.textTheme.bodyMedium?.fontFamily,
          equals(plain.textTheme.bodyMedium?.fontFamily),
          reason: brightness.name,
        );
      }
    });

    test('T-29-SLOT-06: 같은 builder 로 두 번 만든 테마는 == 이다', () {
      for (final brightness in Brightness.values) {
        final first = _buildThemeFor(
          brightness,
          colorSchemeBuilder: _inkPrimaryScheme,
        );
        final second = _buildThemeFor(
          brightness,
          colorSchemeBuilder: _inkPrimaryScheme,
        );

        expect(first == second, isTrue, reason: brightness.name);
        expect(
          first.hashCode,
          equals(second.hashCode),
          reason: brightness.name,
        );

        // 같은 일을 하는 서로 다른 클로저 인스턴스여도 테마는 같다.
        final fromClosureA = _buildThemeFor(
          brightness,
          colorSchemeBuilder: (input) =>
              input.scheme.copyWith(primary: _inkColor),
        );
        final fromClosureB = _buildThemeFor(
          brightness,
          colorSchemeBuilder: (input) =>
              input.scheme.copyWith(primary: _inkColor),
        );

        expect(fromClosureA == fromClosureB, isTrue, reason: brightness.name);
      }
    });

    test('T-29-SLOT-07: builder 를 생략한 테마는 buildAppColorScheme 을 넘긴 테마와 같다', () {
      for (final brightness in Brightness.values) {
        for (final contrastLevel in <double>[0, 1]) {
          expect(
            _buildThemeFor(brightness, contrastLevel: contrastLevel) ==
                _buildThemeFor(
                  brightness,
                  contrastLevel: contrastLevel,
                  colorSchemeBuilder: buildAppColorScheme,
                ),
            isTrue,
            reason: '${brightness.name} $contrastLevel',
          );
        }
      }
    });

    test(
      'T-29-SLOT-07: app_theme.dart 는 형을 적은 지역 변수로 buildAppColorScheme 을 묶는다',
      () {
        final String code = stripSlashComments(
          readTrackedFile('lib/core/theme/app_theme.dart'),
        );

        expect(
          RegExp(
            r'final\s+AppColorSchemeBuilder\s+\w+\s*=\s*colorSchemeBuilder\s*\?\?\s*buildAppColorScheme\s*;',
          ).allMatches(code).length,
          greaterThanOrEqualTo(1),
        );
        expect(
          RegExp(
            r'AppColorSchemeBuilder\?\s+colorSchemeBuilder',
          ).allMatches(code).length,
          greaterThanOrEqualTo(2),
        );
      },
      // adopter 가 고치는 파일이라 유지보수자 트리에서만 본다.
      skip: skipUnlessMaintainerTree(),
    );

    test(
      'T-29-SLOT-08: 킷 판 buildAppColorScheme 은 받은 팔레트를 그대로 돌려준다',
      () {
        for (final brightness in Brightness.values) {
          final scheme = ColorScheme.fromSeed(
            seedColor: AppTheme.seedColor,
            brightness: brightness,
          );
          final input = AppColorSchemeInput(
            scheme: scheme,
            seedColor: Color(AppTheme.seedColor.toARGB32()),
            contrastLevel: 0,
            dynamicSchemeVariant: DynamicSchemeVariant.tonalSpot,
          );

          expect(
            identical(buildAppColorScheme(input), scheme),
            isTrue,
            reason: brightness.name,
          );
        }
      },
      // adopter 가 고치는 파일이라 유지보수자 트리에서만 본다.
      skip: skipUnlessMaintainerTree(),
    );

    test('T-29-SLOT-09: 밝기를 바꾼 팔레트를 돌려주면 debug assert 로 멈춘다', () {
      ColorScheme flipBrightness(AppColorSchemeInput input) =>
          ColorScheme.fromSeed(
            seedColor: input.seedColor,
            brightness: input.scheme.brightness == Brightness.light
                ? Brightness.dark
                : Brightness.light,
          );
      Matcher throwsBrightnessAssert(String received, String returned) =>
          throwsA(
            isA<AssertionError>().having(
              (AssertionError error) => '${error.message}',
              'message',
              allOf(
                contains('buildAppColorScheme'),
                contains('($received)'),
                contains('a $returned ColorScheme'),
              ),
            ),
          );

      expect(
        () => AppTheme.light(colorSchemeBuilder: flipBrightness),
        throwsBrightnessAssert('light', 'dark'),
      );
      expect(
        () => AppTheme.dark(colorSchemeBuilder: flipBrightness),
        throwsBrightnessAssert('dark', 'light'),
      );
    });
  });
}

/// 색 역할 자리 시험의 진한 primary 색이다.
const Color _inkColor = Color(0xFF2B2B2B);

/// primary 하나를 [_inkColor] 로 바꾸는 top-level builder 다.
ColorScheme _inkPrimaryScheme(AppColorSchemeInput input) =>
    input.scheme.copyWith(primary: _inkColor);

/// [brightness] 에 맞는 `AppTheme.light` · `AppTheme.dark` 를 같은 인자로 만든다.
ThemeData _buildThemeFor(
  Brightness brightness, {
  Color seedColor = AppTheme.seedColor,
  double contrastLevel = 0,
  DynamicSchemeVariant dynamicSchemeVariant = DynamicSchemeVariant.tonalSpot,
  AppColorSchemeBuilder? colorSchemeBuilder,
}) => brightness == Brightness.light
    ? AppTheme.light(
        seedColor: seedColor,
        contrastLevel: contrastLevel,
        dynamicSchemeVariant: dynamicSchemeVariant,
        colorSchemeBuilder: colorSchemeBuilder,
      )
    : AppTheme.dark(
        seedColor: seedColor,
        contrastLevel: contrastLevel,
        dynamicSchemeVariant: dynamicSchemeVariant,
        colorSchemeBuilder: colorSchemeBuilder,
      );

/// 테마를 하나 만들며 색 역할 자리가 받은 입력을 돌려준다(팔레트는 그대로).
AppColorSchemeInput _receivedInput(
  Brightness brightness, {
  Color seedColor = AppTheme.seedColor,
  double contrastLevel = 0,
  DynamicSchemeVariant dynamicSchemeVariant = DynamicSchemeVariant.tonalSpot,
}) {
  final inputs = <AppColorSchemeInput>[];
  _buildThemeFor(
    brightness,
    seedColor: seedColor,
    contrastLevel: contrastLevel,
    dynamicSchemeVariant: dynamicSchemeVariant,
    colorSchemeBuilder: (input) {
      inputs.add(input);
      return input.scheme;
    },
  );
  return inputs.single;
}
