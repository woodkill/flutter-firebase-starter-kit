// 스플래시 화면의 색 · 로고와 로고 아래 내용 — 내 앱의 파일이다(킷은 이 파일을
// 고치지 않는다).
//
// 색 · 로고 상수는 `flutter_native_splash.yaml` 의 `color` · `color_dark` ·
// `image` · `image_dark` 와 같은 값이어야 한다 — 그래야 네이티브 스플래시에서 이
// 화면으로 넘어갈 때 배경 · 로고가 이어져 보인다.
// `test/infrastructure/native_splash_yaml_test.dart` 가 두 곳의 값을 대조한다.
// 안내: `docs/guide.md` 「스플래시 바꾸기」.
import 'package:flutter/material.dart';
import 'package:gap/gap.dart';

import '../../../core/l10n/l10n_extensions.dart';
import '../../../core/theme/theme_extensions.dart';
import '../../../shared/widgets/small_progress_indicator.dart';

/// OS 라이트일 때 스플래시 배경색 — yaml `color` 와 같은 값이다.
// design-literal: 네이티브 스플래시 yaml 의 color 와 같은 값이어야 해서 토큰이 아니다
const Color kSplashColor = Color(0xFFFFFFFF);

/// OS 다크일 때 스플래시 배경색 — yaml `color_dark` 와 같은 값이다.
// design-literal: 네이티브 스플래시 yaml 의 color_dark 와 같은 값이어야 해서 토큰이 아니다
const Color kSplashColorDark = Color(0xFF000000);

/// OS 라이트일 때 스플래시 로고 자산 경로 — yaml `image` 와 같은 파일이다.
///
/// 화면에는 원본 픽셀 ÷ 4 크기로 그린다(1152 × 1152 원본이면 288).
const String kSplashImage = 'assets/images/splash/logo.png';

/// OS 다크일 때 스플래시 로고 자산 경로 — yaml `image_dark` 와 같은 파일이다.
const String kSplashImageDark = 'assets/images/splash/logo_dark.png';

/// 스플래시 로고 아래 내용을 만든다 — 진행 표시와 준비 문구다.
///
/// - 로고 바로 아래부터 화면 아래까지가 이 내용의 칸이다. 첫 간격이 로고와의
///   거리다.
/// - [context] 의 테마는 배경 밝기에 맞춘 테마다 — 글자 · 진행 표시 색을 테마에서
///   읽으면 배경에 맞는다.
/// - `hasFailure` 는 초기화 실패 대화상자를 띄운 뒤 true 다 — 진행 표시를
///   숨긴다.
/// - 킷 시험은 이 함수 대신 시험용 내용을 넘겨 그린다
///   (`SplashFrame.bodyBuilder`).
Widget buildSplashBody(BuildContext context, {required bool hasFailure}) {
  final spacing = context.appSpacing;
  final colorScheme = context.colorScheme;
  final typography = context.appTypography;

  return Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      Gap(spacing.xxl),
      if (!hasFailure)
        SmallProgressIndicator(dimension: context.appIconSizes.md),
      Gap(spacing.sm),
      Text(
        context.l10n.splashPreparing,
        textAlign: TextAlign.center,
        style: typography.bodyMedium.copyWith(
          color: colorScheme.onSurfaceVariant,
        ),
      ),
    ],
  );
}
