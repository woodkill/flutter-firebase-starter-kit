// 시드 팔레트에서 내 앱이 바꾸는 색 역할 — 내 앱의 파일이다(킷 판은 받은 팔레트를 그대로 돌려준다).
import 'package:flutter/material.dart';

import 'app_color_scheme_slot.dart';

/// 시드에서 만든 팔레트에서 내 앱이 쓸 색 역할을 정해 돌려준다.
///
/// - 받은 밝기(라이트 · 다크)를 지킨다 — 다르면 디버그 빌드가 멈춘다.
/// - 같은 입력에는 늘 같은 팔레트를 돌려준다.
/// - 킷은 이 파일을 고치지 않는다. 킷 golden 시험은
///   `AppTheme.light/dark(colorSchemeBuilder:)` 로 받은 팔레트를 그대로
///   돌려주는 함수를 넘긴다.
/// - 안내: `docs/guide.md` 「디자인 토큰 바꾸기」 의 「색 역할 직접 정하기」.
ColorScheme buildAppColorScheme(AppColorSchemeInput input) => input.scheme;
