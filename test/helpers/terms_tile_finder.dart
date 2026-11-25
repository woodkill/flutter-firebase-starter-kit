// 온보딩 약관 묶음(`TermsCheckboxGroup`)의 행을 찾고 읽고 누르는 공용 헬퍼.
//
// **왜 따로 두나:** 약관 행이 어떤 위젯으로 그려지는지(지금은 `ListTile` 행 ·
// 「전체 동의」 는 `CheckboxListTile` 안의 `ListTile`)를 이 파일 한 곳만 안다.
// 시험마다 행 위젯 타입을 직접 적으면 행 꼴을 바꿀 때 시험 여러 곳이 함께
// 깨진다 — 행 꼴이 바뀌면 이 파일만 고친다.

import 'package:flutter/material.dart';
import 'package:flutter_starter_kit/features/onboarding/presentation/_widgets/terms_checkbox_group.dart';
import 'package:flutter_test/flutter_test.dart';

import 'keep_hangul_words_finder.dart';

/// 약관 묶음의 행 위젯을 그리는 순서대로 모두 찾는다.
///
/// 0 = 「전체 동의」 · 1 = 이용약관 · 2 = 개인정보처리방침 · 그다음 앱이 더한
/// 확인 행들 · 마지막 = 마케팅이다.
Finder findTermsTiles() => find.descendant(
  of: find.byType(TermsCheckboxGroup),
  matching: find.byType(ListTile),
);

/// 원문이 [label] 인 문구를 담은 약관 행 위젯을 찾는다.
///
/// 행 위젯은 서로 겹쳐 들지 않아 문구 하나에 행 위젯 조상이 하나다.
Finder findTermsTileOf(String label) => find.ancestor(
  of: findKeepHangulWordsText(label),
  matching: find.byType(ListTile),
);

/// [tile] 행 안의 체크박스를 찾는다.
Finder findTermsTileCheckbox(Finder tile) =>
    find.descendant(of: tile, matching: find.byType(Checkbox));

/// [tile] 행의 체크 값을 읽는다.
bool? readTermsTileValue(WidgetTester tester, Finder tile) =>
    tester.widget<Checkbox>(findTermsTileCheckbox(tile)).value;

/// [tile] 행의 체크 변경 콜백을 읽는다 — null 이면 행이 꺼져 있다.
ValueChanged<bool?>? readTermsTileOnChanged(WidgetTester tester, Finder tile) =>
    tester.widget<Checkbox>(findTermsTileCheckbox(tile)).onChanged;

/// [tile] 행 안 제목 링크의 누르는 위젯(`InkWell`)을 찾는다.
///
/// 링크가 없는 행에서는 아무것도 찾지 않는다. 타입만으로 찾지 않는다 — 행
/// 위젯도 자기 `InkWell` 을 만들어 `InkWell` 타입 finder 는 링크 행에서 2 개,
/// 링크 없는 행에서 1 개를 낸다. 그래서 링크 표시(`link: true`)를 단
/// [Semantics] 아래 `InkWell` 로 찾는다(링크 안에 `InkWell` 은 하나다).
Finder findTermsTitleLink(Finder tile) => find.descendant(
  of: find.descendant(
    of: tile,
    matching: find.byWidgetPredicate(
      (widget) => widget is Semantics && (widget.properties.link ?? false),
    ),
  ),
  matching: find.byType(InkWell),
);
