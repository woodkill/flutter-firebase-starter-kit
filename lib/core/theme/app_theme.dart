import 'package:flutter/material.dart';

import '../config/app_config.dart';
import 'app_color_scheme.dart';
import 'app_color_scheme_slot.dart';
import 'app_colors.dart';
import 'app_elevation.dart';
import 'app_icon_sizes.dart';
import 'app_opacity.dart';
import 'app_radius.dart';
import 'app_spacing.dart';
import 'app_typography.dart';

/// 앱의 라이트/다크 [ThemeData]를 조립하는 유틸리티 클래스.
///
/// [seedColor]를 기반으로 [ColorScheme.fromSeed]를 사용하여 M3 팔레트를 생성하고,
/// [AppColors], [AppTypography], [AppSpacing], [AppIconSizes], [AppRadius],
/// [AppOpacity], [AppElevation] ThemeExtension을 등록한다.
/// 컴포넌트 테마는 Material 3 기본과 다른 아래 시트 테마 하나만 건다 — 버튼 높이 ·
/// 구분선 · 진행 표시는 Material 3 기본값을 쓴다.
/// [seedColor]를 변경하면 전체 팔레트가 교체된다.
/// [ColorScheme.fromSeed] 팔레트를 사용자 파일의 [buildAppColorScheme] 에 넘겨
/// 돌려받은 팔레트로 [ThemeData] 를 만든다 — `colorSchemeBuilder` 인자를
/// 넘기면 그 함수에 넘기고, 킷 판 [buildAppColorScheme] 은 받은 팔레트 그대로다.
/// [AppColors.brand] 에는 넘긴 시드를 `toARGB32()` 로 정규화해 그대로 넣는다 —
/// 넘긴 시드가 불투명이면 불투명이다.
/// [fontFamily] 를 테마 글꼴로 건다.
///
/// **타이포그래피 계약:** 등록되는 [AppTypography] 는 기하를 포함하지 않는
/// **override 레이어**([AppTypography.empty])다. 로케일별 기하(ko/ja 는
/// `ScriptCategory.dense` — `textBaseline: ideographic`)는 Flutter 가
/// `Theme.build` 에서 `ThemeData.localize` 로 적용하므로, 완전한 스타일은
/// 반드시 `context.appTypography` (또는 `Theme.of(context).textTheme`) 로 얻어야
/// 한다. 사용자는 `copyWith(extensions: [AppTypography(...)])` 로 이 레이어를
/// 채워 타이포그래피를 부분 override 할 수 있다.
abstract final class AppTheme {
  /// 앱 전체 테마의 기본 시드 컬러.
  ///
  /// 이 값을 변경하면 [ColorScheme.fromSeed]를 통해 전체 팔레트가 교체된다.
  ///
  /// **커스터마이징 포인트:** 소스를 고치지 않고도 [light]/[dark] 의
  /// `seedColor` 인자로 주입할 수 있다 — 예:
  /// `AppTheme.light(seedColor: Colors.teal)`.
  static const MaterialColor seedColor = Colors.deepPurple;

  /// config 의 `brandColor` 원문 [raw] 를 브랜드 원색으로 푼다 — `#RRGGBB` 가
  /// 아니면 [seedColor] 다.
  ///
  /// 반환은 언제나 불투명 [Color] 다 — [MaterialColor] 를 정규화해 `==` 가 런타임
  /// 타입에 흔들리지 않는다. 판정은 [AppConfig.parseBrandColor] 이고 그 규칙은
  /// `hosting/test/shared_rules.json` 공유 표가 고정한다.
  static Color resolveBrandColor(String raw) =>
      Color((AppConfig.parseBrandColor(raw) ?? seedColor).toARGB32());

  /// 앱의 브랜드 원색 — config `brandColor`(빌드 때 들어간다)를 [resolveBrandColor]
  /// 로 푼 색이다.
  ///
  /// 테마 시드 · [AppColors.brand] · 알림 색이 같은 값이다.
  static final Color brandColor = resolveBrandColor(AppConfig.brandColor);

  /// 앱 전체 글자의 글꼴 family 이름이다.
  ///
  /// `pubspec.yaml` 이 `assets/fonts/pretendard-jp/PretendardJPVariable.ttf` 를
  /// 이 이름으로 선언한다. Pretendard JP 는 한글 · 가나 · 한자 · 라틴을 한 파일에
  /// 담아 앱 언어 · OS 와 상관없이 같은 글꼴로 그린다.
  ///
  /// 대체 글꼴 목록은 두지 않는다 — 소셜 로그인 버튼 라벨은 글꼴 이름을 직접
  /// 지정하고, 그 글꼴에 없는 글자를 기기 글꼴로 넘긴다.
  ///
  /// 바꾸거나 빼는 법은 `docs/guide.md` 「디자인 토큰 바꾸기」 의 「6. 앱 글꼴
  /// 바꾸기 · 빼기」 를 본다.
  static const String fontFamily = 'PretendardJP';

  /// Material 3 기본과 다르게 정한 아래 시트 테마를 만든다.
  ///
  /// 손잡이를 켠다 — 킷 시트가 모두 손잡이를 쓴다.
  /// 위 모서리는 extension 으로 등록하는 `const AppRadius()` 의 [AppRadius.xl]
  /// 이라 `app_radius.dart` 기본값을 고치면 함께 바뀌고, `copyWith(extensions:)`
  /// 로 바꾼 값은 따라가지 않는다.
  /// 배경은 지정하지 않아 Material 3 기본(`surfaceContainerLow`)이다.
  static BottomSheetThemeData _buildBottomSheetTheme() => BottomSheetThemeData(
    showDragHandle: true,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(
        top: Radius.circular(const AppRadius().xl),
      ),
    ),
  );

  /// 시드 팔레트 [seedScheme] 를 색 역할 자리에 넘겨 테마에 쓸 팔레트를 받는다.
  ///
  /// [colorSchemeBuilder] 가 null 이면 사용자 파일의 [buildAppColorScheme] 을
  /// 부른다. 자리는 [ThemeData] 생성자 앞이라 [ThemeData] 가 팔레트에서
  /// 파생하는 값도 돌려받은 팔레트를 따른다. 돌려받은 팔레트의 밝기가
  /// [seedScheme] 과 다르면 debug 빌드에서 멈춘다.
  static ColorScheme _resolveColorScheme({
    required ColorScheme seedScheme,
    required Color seedColor,
    required double contrastLevel,
    required DynamicSchemeVariant dynamicSchemeVariant,
    required AppColorSchemeBuilder? colorSchemeBuilder,
  }) {
    final AppColorSchemeBuilder build =
        colorSchemeBuilder ?? buildAppColorScheme;
    final ColorScheme scheme = build(
      AppColorSchemeInput(
        scheme: seedScheme,
        seedColor: Color(seedColor.toARGB32()),
        contrastLevel: contrastLevel,
        dynamicSchemeVariant: dynamicSchemeVariant,
      ),
    );
    assert(
      scheme.brightness == seedScheme.brightness,
      colorSchemeBuilder == null
          ? 'buildAppColorScheme (${seedScheme.brightness.name}) returned a '
                '${scheme.brightness.name} ColorScheme — keep the brightness.'
          : 'colorSchemeBuilder (passed in place of buildAppColorScheme) '
                '(${seedScheme.brightness.name}) returned a '
                '${scheme.brightness.name} ColorScheme — keep the brightness.',
    );
    return scheme;
  }

  /// 라이트 모드 [ThemeData]를 생성한다.
  ///
  /// [AppColors], [AppTypography], [AppSpacing], [AppIconSizes], [AppRadius],
  /// [AppOpacity], [AppElevation] 7개 ThemeExtension을 포함한다.
  /// [seedColor]를 넘기면 그 시드로 M3 팔레트를 생성한다 (기본값
  /// [AppTheme.seedColor]).
  ///
  /// 대비 · 색 변형 인자 `contrastLevel` · `dynamicSchemeVariant` 는
  /// [ColorScheme.fromSeed] 의 같은 이름 인자 그대로이고 기본값도 같다 —
  /// 생략하면 지금 팔레트와 같다.
  /// - `contrastLevel`: -1.0(최저) ~ 1.0(최고) · 기본 0.0 · Material 3 의
  ///   중간 대비는 0.5, 높은 대비는 1.0 이다.
  /// - `dynamicSchemeVariant`: 팔레트 생성 방식 · 기본
  ///   [DynamicSchemeVariant.tonalSpot].
  /// - `colorSchemeBuilder`: 시드 팔레트에서 색 역할을 바꾸는 함수 · null 이면
  ///   사용자 파일의 [buildAppColorScheme] · 킷 golden 시험은 받은 팔레트를
  ///   그대로 돌려주는 함수를 넘긴다.
  ///
  /// [AppColors] 의 시맨틱 색(`success` · `warning` · `info`)은 대비 단계를
  /// 따르지 않는다 — 대비를 바꿔도 같은 색이다.
  ///
  /// [fontFamily] 를 테마 글꼴로 건다.
  /// 아래 시트 테마(손잡이 · 위 모서리)를 건다.
  static ThemeData light({
    Color seedColor = AppTheme.seedColor,
    double contrastLevel = 0.0,
    DynamicSchemeVariant dynamicSchemeVariant = DynamicSchemeVariant.tonalSpot,
    AppColorSchemeBuilder? colorSchemeBuilder,
  }) {
    final colorScheme = _resolveColorScheme(
      seedScheme: ColorScheme.fromSeed(
        seedColor: seedColor,
        contrastLevel: contrastLevel,
        dynamicSchemeVariant: dynamicSchemeVariant,
      ),
      seedColor: seedColor,
      contrastLevel: contrastLevel,
      dynamicSchemeVariant: dynamicSchemeVariant,
      colorSchemeBuilder: colorSchemeBuilder,
    );
    // useMaterial3 미지정 — Flutter 3.41 기준 기본값이 true 다.
    final base = ThemeData(colorScheme: colorScheme, fontFamily: fontFamily);

    return base.copyWith(
      bottomSheetTheme: _buildBottomSheetTheme(),
      extensions: <ThemeExtension<dynamic>>[
        AppColors.fromBrightness(Brightness.light, brand: seedColor),
        AppTypography.empty,
        const AppSpacing(),
        const AppIconSizes(),
        const AppRadius(),
        const AppOpacity(),
        const AppElevation(),
      ],
    );
  }

  /// 다크 모드 [ThemeData]를 생성한다.
  ///
  /// [AppColors], [AppTypography], [AppSpacing], [AppIconSizes], [AppRadius],
  /// [AppOpacity], [AppElevation] 7개 ThemeExtension을 포함한다.
  /// [seedColor]를 넘기면 그 시드로 M3 팔레트를 생성한다 (기본값
  /// [AppTheme.seedColor]). [light] 와 동일한 시드를 넘겨야 두 모드의
  /// 팔레트가 일관된다.
  ///
  /// 대비 · 색 변형 인자 `contrastLevel` · `dynamicSchemeVariant` 는
  /// [ColorScheme.fromSeed] 의 같은 이름 인자 그대로이고 기본값도 같다 —
  /// 생략하면 지금 팔레트와 같다.
  /// - `contrastLevel`: -1.0(최저) ~ 1.0(최고) · 기본 0.0 · Material 3 의
  ///   중간 대비는 0.5, 높은 대비는 1.0 이다.
  /// - `dynamicSchemeVariant`: 팔레트 생성 방식 · 기본
  ///   [DynamicSchemeVariant.tonalSpot].
  /// - `colorSchemeBuilder`: 시드 팔레트에서 색 역할을 바꾸는 함수 · null 이면
  ///   사용자 파일의 [buildAppColorScheme] · 킷 golden 시험은 받은 팔레트를
  ///   그대로 돌려주는 함수를 넘긴다.
  ///
  /// [AppColors] 의 시맨틱 색(`success` · `warning` · `info`)은 대비 단계를
  /// 따르지 않는다 — 대비를 바꿔도 같은 색이다.
  ///
  /// [fontFamily] 를 테마 글꼴로 건다.
  /// 아래 시트 테마(손잡이 · 위 모서리)를 건다.
  static ThemeData dark({
    Color seedColor = AppTheme.seedColor,
    double contrastLevel = 0.0,
    DynamicSchemeVariant dynamicSchemeVariant = DynamicSchemeVariant.tonalSpot,
    AppColorSchemeBuilder? colorSchemeBuilder,
  }) {
    final colorScheme = _resolveColorScheme(
      seedScheme: ColorScheme.fromSeed(
        seedColor: seedColor,
        brightness: Brightness.dark,
        contrastLevel: contrastLevel,
        dynamicSchemeVariant: dynamicSchemeVariant,
      ),
      seedColor: seedColor,
      contrastLevel: contrastLevel,
      dynamicSchemeVariant: dynamicSchemeVariant,
      colorSchemeBuilder: colorSchemeBuilder,
    );
    // brightness 미지정 — colorScheme 이 있으면 거기서 파생된다.
    final base = ThemeData(colorScheme: colorScheme, fontFamily: fontFamily);

    return base.copyWith(
      bottomSheetTheme: _buildBottomSheetTheme(),
      extensions: <ThemeExtension<dynamic>>[
        AppColors.fromBrightness(Brightness.dark, brand: seedColor),
        AppTypography.empty,
        const AppSpacing(),
        const AppIconSizes(),
        const AppRadius(),
        const AppOpacity(),
        const AppElevation(),
      ],
    );
  }
}
