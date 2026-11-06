import 'package:flutter/material.dart';

import '../config/app_config.dart';
import 'app_colors.dart';
import 'app_icon_sizes.dart';
import 'app_opacity.dart';
import 'app_radius.dart';
import 'app_spacing.dart';
import 'app_typography.dart';

/// 앱의 라이트/다크 [ThemeData]를 조립하는 유틸리티 클래스.
///
/// [seedColor]를 기반으로 [ColorScheme.fromSeed]를 사용하여 M3 팔레트를 생성하고,
/// [AppColors], [AppTypography], [AppSpacing], [AppIconSizes], [AppRadius],
/// [AppOpacity] ThemeExtension을 등록한다.
/// [seedColor]를 변경하면 전체 팔레트가 교체된다.
/// [AppColors.brand] 에는 넘긴 시드를 불투명 [Color] 로 정규화해 그대로 넣는다.
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

  /// 라이트 모드 [ThemeData]를 생성한다.
  ///
  /// [AppColors], [AppTypography], [AppSpacing], [AppIconSizes], [AppRadius],
  /// [AppOpacity] 6개 ThemeExtension을 포함한다.
  /// [seedColor]를 넘기면 그 시드로 M3 팔레트를 생성한다 (기본값
  /// [AppTheme.seedColor]).
  /// [fontFamily] 를 테마 글꼴로 건다.
  static ThemeData light({Color seedColor = AppTheme.seedColor}) {
    final colorScheme = ColorScheme.fromSeed(seedColor: seedColor);
    // useMaterial3 미지정 — Flutter 3.41 기준 기본값이 true 다.
    final base = ThemeData(colorScheme: colorScheme, fontFamily: fontFamily);

    return base.copyWith(
      extensions: <ThemeExtension<dynamic>>[
        AppColors.fromBrightness(Brightness.light, brand: seedColor),
        AppTypography.empty,
        const AppSpacing(),
        const AppIconSizes(),
        const AppRadius(),
        const AppOpacity(),
      ],
    );
  }

  /// 다크 모드 [ThemeData]를 생성한다.
  ///
  /// [AppColors], [AppTypography], [AppSpacing], [AppIconSizes], [AppRadius],
  /// [AppOpacity] 6개 ThemeExtension을 포함한다.
  /// [seedColor]를 넘기면 그 시드로 M3 팔레트를 생성한다 (기본값
  /// [AppTheme.seedColor]). [light] 와 동일한 시드를 넘겨야 두 모드의
  /// 팔레트가 일관된다.
  /// [fontFamily] 를 테마 글꼴로 건다.
  static ThemeData dark({Color seedColor = AppTheme.seedColor}) {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: seedColor,
      brightness: Brightness.dark,
    );
    // brightness 미지정 — colorScheme 이 있으면 거기서 파생된다.
    final base = ThemeData(colorScheme: colorScheme, fontFamily: fontFamily);

    return base.copyWith(
      extensions: <ThemeExtension<dynamic>>[
        AppColors.fromBrightness(Brightness.dark, brand: seedColor),
        AppTypography.empty,
        const AppSpacing(),
        const AppIconSizes(),
        const AppRadius(),
        const AppOpacity(),
      ],
    );
  }
}
