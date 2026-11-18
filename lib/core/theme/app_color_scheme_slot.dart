// 색 역할 자리의 입력 객체와 builder 꼴 — 킷 파일이다(내 색 역할은 app_color_scheme.dart 에 둔다).
import 'package:flutter/material.dart';

/// 시드 팔레트를 받아 테마에 쓸 팔레트를 돌려주는 함수 꼴이다.
///
/// 받은 팔레트(`input.scheme`)의 밝기를 지킨다 — 라이트 테마에는 라이트
/// 팔레트, 다크 테마에는 다크 팔레트를 돌려준다. 같은 입력에는 늘 같은
/// 팔레트를 돌려준다(테마는 화면을 다시 그릴 때마다 새로 만들어진다).
typedef AppColorSchemeBuilder = ColorScheme Function(AppColorSchemeInput input);

/// 색 역할 자리에 넘기는 값 묶음이다.
///
/// 킷이 나중에 더하는 필드는 기본값이 있는 선택 인자로 더한다 — 이 객체를
/// 받는 사용자 함수와 직접 만드는 시험이 그대로 컴파일된다.
@immutable
class AppColorSchemeInput {
  /// [AppColorSchemeInput] 을 생성한다.
  const AppColorSchemeInput({
    required this.scheme,
    required this.seedColor,
    required this.contrastLevel,
    required this.dynamicSchemeVariant,
  });

  /// [ColorScheme.fromSeed] 결과 그대로다 — 밝기는 `scheme.brightness` 로
  /// 가른다.
  final ColorScheme scheme;

  /// 테마에 넘긴 시드를 불투명 [Color] 로 정규화한 값이다 — `AppColors.brand`
  /// 와 같다.
  final Color seedColor;

  /// 테마에 넘긴 대비 단계다 — 고대비 테마는 1.0 이다.
  final double contrastLevel;

  /// 테마에 넘긴 색 변형이다.
  final DynamicSchemeVariant dynamicSchemeVariant;
}
