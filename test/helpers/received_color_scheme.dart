// 킷 golden 과 팔레트를 `fromSeed` 와 직접 견주는 시험이 사용자 색 역할 자리
// 대신 넘기는 builder — 내 앱이 `lib/core/theme/app_color_scheme.dart` 를 채워도
// 그 시험은 받은 팔레트로 그린다.
//
// `AppTheme.light/dark(colorSchemeBuilder: keepReceivedColorScheme)` 꼴로 넘긴다.
// 글자 대비를 보는 비-golden 접근성 시험에는 넘기지 않는다 — 내 팔레트에서 글자가
// 안 보이면 그 시험이 빨개져 알려 준다.

import 'package:flutter/material.dart';
import 'package:flutter_starter_kit/core/theme/app_color_scheme_slot.dart';

/// 받은 팔레트를 그대로 돌려준다.
///
/// [AppColorSchemeBuilder] 꼴이다 — 테마가 시드로 만든 팔레트(`input.scheme`)를
/// 바꾸지 않고 돌려주므로, 이것을 넘긴 테마는 킷 판 색 역할 자리와 같은 팔레트를
/// 쓴다.
ColorScheme keepReceivedColorScheme(AppColorSchemeInput input) => input.scheme;
